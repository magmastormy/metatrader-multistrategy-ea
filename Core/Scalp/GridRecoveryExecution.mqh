// Recovery order sequencing: pre-trade risk gate, AI-VOTE logging,
// grid entry execution with dynamic slippage, retcode diagnostics
// and grid position close.
// Extracted verbatim from GridRecoveryEngine.mqh (structural only).
#property copyright "Copyright 2026, Aggressive Trading Systems"
#property link      "https://www.aggressivetrading.com"
#property version   "1.00"
#property strict

#ifndef CORE_SCALP_GRID_RECOVERY_EXECUTION_MQH
#define CORE_SCALP_GRID_RECOVERY_EXECUTION_MQH

#include "../Risk/UnifiedRiskManager.mqh"
#include "../Trading/TradeMgrPricing.mqh"
#include "../Trading/TradeMgrPreflight.mqh"
#include <Trade\Trade.mqh>

#include "GridRecoveryTypes.mqh"

class CUnifiedRiskManager;

class CAIAdapter;

class CGridRecoveryExecution
{
private:
   CUnifiedRiskManager*      m_riskManager;
   CTradeManager*            m_tradeManager;    // L10-014: Use TradeManager for dynamic slippage
   CTrade                    m_trade;           // Fallback only
   CAIAdapter*               m_aiAdapter;       // L10-018: AI adapter for voting

public:
   CGridRecoveryExecution() :
      m_riskManager(NULL),
      m_tradeManager(NULL),
      m_aiAdapter(NULL)
   {
   }

   void Configure(CUnifiedRiskManager *pRiskManager, CTradeManager *pTradeManager, CAIAdapter *pAIAdapter)
   {
      m_riskManager    = pRiskManager;
      m_tradeManager   = pTradeManager;  // L10-014: Store TradeManager for dynamic slippage
      m_aiAdapter      = pAIAdapter;     // L10-018: Store AI adapter
   }

// Pre-trade risk validation via UnifiedRiskManager
// (AGENTS.md invariant #1)
   bool PassesRiskValidation(const string symbol, ENUM_ORDER_TYPE orderType, double lotSize,
                             double slDistance, int level)
   {
      if(m_riskManager != NULL)
      {
         double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
         double slPips = (point > 0.0) ? (slDistance / point) : 0.0;
         STradeValidationRequest riskReq;
         ZeroMemory(riskReq);
         riskReq.symbol       = symbol;
         riskReq.orderType    = orderType;
         riskReq.lotSize      = lotSize;
         riskReq.stopLossPips = slPips;
         riskReq.confidence   = 0.6;
         riskReq.strategy     = "GRID-RECOVERY";
         riskReq.requestTime  = TimeCurrent();

         SValidationResult riskResult = m_riskManager.ValidateTradeRequest(riskReq, "grid-pretrade");
         if(!riskResult.approved)
         {
            PrintFormat("[GRID-RECOVERY] REJECTED by risk manager | symbol=%s level=%d | reason=%s", symbol, level, riskResult.reason);
            return false;
         }
      }
      return true;
   }

// L10-018: AI-VOTE logging
   void LogAIVote(const string symbol, int direction)
   {
      if(m_aiAdapter != NULL)
      {
         PrintFormat("[AI-VOTE] symbol=%s strategy=GridRecovery vote=%s",
                     symbol, direction == 1 ? "BUY" : "SELL");
      }
   }

// Execute a grid level entry; ticketOut receives the result order
   bool ExecuteEntry(const string symbol, int direction, int level, double lotSize,
                     double entryPrice, double sl, double tp, int magic, ulong &ticketOut)
   {
      ticketOut = 0;

      // Grid levels are added into a moving market - a level whose stop sits inside the broker minimum or whose target cannot clear the spread is the worst place to discover it.
      ENUM_ORDER_TYPE gridOrderType = (direction == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      string gridStopError = "";
      if(!CTradeMgrPricing::NormalizeAndValidateStops(symbol, gridOrderType, entryPrice, tp, sl, tp, gridStopError))
      {
         PrintFormat("[GRID-RECOVERY] STOPS REJECTED | %s L%d | %s", symbol, level, gridStopError);
         return false;
      }

      // L10-014: Use dynamic slippage from TradeManager if available, else fallback
      uint slippage = 50; // fallback
      if(m_tradeManager != NULL)
      {
         slippage = m_tradeManager.GetDynamicSlippage(symbol);
      }

      m_trade.SetExpertMagicNumber(magic);
      m_trade.SetDeviationInPoints(slippage);
      // L7-015: honor the symbol's supported fill mode; fall back to market (RETURN) when IOC/FOK unavailable
      long symFillMode = SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
      ENUM_ORDER_TYPE_FILLING scalpFill = ((symFillMode & SYMBOL_FILLING_IOC) != 0) ? ORDER_FILLING_IOC :
                                         (((symFillMode & SYMBOL_FILLING_FOK) != 0) ? ORDER_FILLING_FOK : ORDER_FILLING_RETURN);
      m_trade.SetTypeFilling(scalpFill);

      bool result = false;
      string comment = "GRID-RECOVERY|L:" + IntegerToString(level) + "|D:" + IntegerToString(direction);

      if(direction == 1)
         result = m_trade.Buy(lotSize, symbol, entryPrice, sl, tp, comment);
      else
         result = m_trade.Sell(lotSize, symbol, entryPrice, sl, tp, comment);

      uint sendRetcode = m_trade.ResultRetcode();

      // Batch 177: a DONE_PARTIAL retcode comes back through CTrade as result == false while a
      // position exists. The engine would then treat the level as never opened and the grid could
      // place another layer on top of the fill it already has.
      if(!result)
      {
         ulong confirmTicket = 0;
         double confirmVolume = 0.0;
         if(CTradeMgrPreflight::FindFreshPositionForSend(symbol,
                (direction == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,
                lotSize, confirmTicket, confirmVolume, "GRID-RECOVERY"))
         {
            PrintFormat("[GRID-RECOVERY] FILL CONFIRMED BY POSITION | %s L%d | ticket=%I64u | filled=%.2f of %.2f | retcode=%u | level tracked, not resent",
                        symbol, level, confirmTicket, confirmVolume, lotSize, sendRetcode);
            result = true;
         }
      }

      if(result)
      {
         // The stored ticket is used by PositionSelectByTicket and CTrade::PositionClose, both of
         // which take a POSITION ticket. ResultOrder() is the ORDER ticket and differs from it on a
         // hedging account, so a level tracked by order ticket can never be selected or closed -
         // the position then has no exit owner at all, because engine-tagged comments are excluded
         // from lifecycle management (Batch 170).
         ticketOut = FindLevelPositionTicket(symbol, magic);
         if(ticketOut == 0)
         {
            ticketOut = m_trade.ResultOrder();
            PrintFormat("[GRID-RECOVERY] TICKET UNRESOLVED | %s L%d | no open position matched magic=%d yet, tracking order ticket %I64u - this level cannot be closed until it resolves",
                        symbol, level, magic, ticketOut);
         }

         PrintFormat("[GRID-RECOVERY] Level opened: %s L%d %s lot=%.2f entry=%.5f SL=%.5f TP=%.5f magic=%d ticket=%I64u",
                     symbol, level, direction == 1 ? "BUY" : "SELL",
                     lotSize, entryPrice, sl, tp, magic, ticketOut);
      }
      else
      {
         uint retcode = m_trade.ResultRetcode();
         PrintFormat("[GRID-RECOVERY-FAILED] %s L%d %s lot=%.2f retcode=%u | price=%.5f SL=%.5f TP=%.5f magic=%d",
                     symbol, level, direction == 1 ? "BUY" : "SELL", lotSize, retcode, entryPrice, sl, tp, magic);

         // These branches must test MQL5 retcodes via the official symbolic codes (10016 TRADE_DISABLED, 10014 INVALID_VOLUME, 10008 PLACED).
         if(retcode == TRADE_RETCODE_INVALID_VOLUME)
         {
            PrintFormat("[GRID-RECOVERY-ERROR] %s TRADE_RETCODE_INVALID_VOLUME: lot=%.2f minVol=%.2f maxVol=%.2f step=%.4f | freeMargin=%.2f leverage=%d",
                        symbol, lotSize,
                        SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN),
                        SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX),
                        SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP),
                        AccountInfoDouble(ACCOUNT_MARGIN_FREE),
                        AccountInfoInteger(ACCOUNT_LEVERAGE));
         }
         else if(retcode == TRADE_RETCODE_INVALID_PRICE)
         {
            PrintFormat("[GRID-RECOVERY-ERROR] %s TRADE_RETCODE_INVALID_PRICE: entryPrice=%.5f SL=%.5f TP=%.5f digits=%d",
                        symbol, entryPrice, sl, tp, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS));
         }
         else if(retcode == TRADE_RETCODE_NO_MONEY)
         {
            double usedMargin = 0.0;
            // ACCOUNT_MARGIN_USED may not be available in all MT5 builds
            // Fallback: used margin = margin - free margin
            double totalMargin = AccountInfoDouble(ACCOUNT_MARGIN);
            double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
            usedMargin = totalMargin - freeMargin;
            if(usedMargin < 0) usedMargin = 0;
            PrintFormat("[GRID-RECOVERY-ERROR] %s TRADE_RETCODE_NO_MONEY: lot=%.2f freeMargin=%.2f usedMargin=%.2f totalMargin=%.2f",
                        symbol, lotSize, freeMargin, usedMargin, totalMargin);
         }
      }

      return result;
   }

// Resolve the open position this send just created: the grid's magic is unique per symbol and
// level (base + offset + symbolIndex*100 + level), so a magic match identifies the exact position.
   ulong FindLevelPositionTicket(const string symbol, const int magic)
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != symbol) continue;
         if(PositionGetInteger(POSITION_MAGIC) != magic) continue;
         return ticket;
      }
      return 0;
   }

// Close a single grid level position; logs the retcode on failure
   bool ClosePositionTicket(const string symbol, int level, ulong ticket)
   {
      if(!m_trade.PositionClose(ticket))
      {
         uint retcode = m_trade.ResultRetcode();
         PrintFormat("[GRID-RECOVERY-CLOSE-FAILED] %s L%d ticket=%I64u retcode=%u",
                     symbol, level, ticket, retcode);
         return false;
      }
      return true;
   }
};

#endif // CORE_SCALP_GRID_RECOVERY_EXECUTION_MQH
