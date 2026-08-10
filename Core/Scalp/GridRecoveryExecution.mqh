//+------------------------------------------------------------------+
//| GridRecoveryExecution.mqh                                        |
//| Recovery order sequencing: pre-trade risk gate, AI-VOTE logging,  |
//| grid entry execution with dynamic slippage, retcode diagnostics   |
//| and grid position close.                                          |
//| Extracted verbatim from GridRecoveryEngine.mqh (structural only). |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Aggressive Trading Systems"
#property link      "https://www.aggressivetrading.com"
#property version   "1.00"
#property strict

#ifndef CORE_SCALP_GRID_RECOVERY_EXECUTION_MQH
#define CORE_SCALP_GRID_RECOVERY_EXECUTION_MQH

#include "../Risk/RiskValidationGate.mqh"
#include <Trade\Trade.mqh>

#include "GridRecoveryTypes.mqh"

class CUnifiedRiskManager;

// Forward declaration for AI adapter (L10-018)
class CAIAdapter;

//+------------------------------------------------------------------+
//| CGridRecoveryExecution — owns the trade execution dependencies    |
//+------------------------------------------------------------------+
class CGridRecoveryExecution
{
private:
   CUnifiedRiskManager*      m_riskManager;
   CTradeManager*            m_tradeManager;    // L10-014: Use TradeManager for dynamic slippage
   CTrade                    m_trade;           // Fallback only
   CAIAdapter*               m_aiAdapter;       // L10-018: AI adapter for voting

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CGridRecoveryExecution() :
      m_riskManager(NULL),
      m_tradeManager(NULL),
      m_aiAdapter(NULL)
   {
   }

   //+------------------------------------------------------------------+
   //| Wire up the execution dependencies                                |
   //+------------------------------------------------------------------+
   void Configure(CUnifiedRiskManager *pRiskManager, CTradeManager *pTradeManager, CAIAdapter *pAIAdapter)
   {
      m_riskManager    = pRiskManager;
      m_tradeManager   = pTradeManager;  // L10-014: Store TradeManager for dynamic slippage
      m_aiAdapter      = pAIAdapter;     // L10-018: Store AI adapter
   }

   //+------------------------------------------------------------------+
   //| Pre-trade risk validation via UnifiedRiskManager                  |
   //| (AGENTS.md invariant #1)                                          |
   //+------------------------------------------------------------------+
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

   //+------------------------------------------------------------------+
   //| L10-018: AI-VOTE logging                                          |
   //+------------------------------------------------------------------+
   void LogAIVote(const string symbol, int direction)
   {
      if(m_aiAdapter != NULL)
      {
         PrintFormat("[AI-VOTE] symbol=%s strategy=GridRecovery vote=%s",
                     symbol, direction == 1 ? "BUY" : "SELL");
      }
   }

   //+------------------------------------------------------------------+
   //| Execute a grid level entry; ticketOut receives the result order   |
   //+------------------------------------------------------------------+
   bool ExecuteEntry(const string symbol, int direction, int level, double lotSize,
                     double entryPrice, double sl, double tp, int magic, ulong &ticketOut)
   {
      ticketOut = 0;

      // L10-014: Use dynamic slippage from TradeManager if available, else fallback
      uint slippage = 50; // fallback
      if(m_tradeManager != NULL)
      {
         slippage = m_tradeManager.GetDynamicSlippage(symbol);
      }

      // Set up trade object
      m_trade.SetExpertMagicNumber(magic);
      m_trade.SetDeviationInPoints(slippage);
      m_trade.SetTypeFilling(ORDER_FILLING_IOC);

      // Execute trade
      bool result = false;
      string comment = "GRID-RECOVERY|L:" + IntegerToString(level) + "|D:" + IntegerToString(direction);

      if(direction == 1)
         result = m_trade.Buy(lotSize, symbol, entryPrice, sl, tp, comment);
      else
         result = m_trade.Sell(lotSize, symbol, entryPrice, sl, tp, comment);

      if(result)
      {
         ticketOut = m_trade.ResultOrder();

         PrintFormat("[GRID-RECOVERY] Level opened: %s L%d %s lot=%.2f entry=%.5f SL=%.5f TP=%.5f magic=%d",
                     symbol, level, direction == 1 ? "BUY" : "SELL",
                     lotSize, entryPrice, sl, tp, magic);
      }
      else
      {
         uint retcode = m_trade.ResultRetcode();
         PrintFormat("[GRID-RECOVERY-FAILED] %s L%d %s lot=%.2f retcode=%u | price=%.5f SL=%.5f TP=%.5f magic=%d",
                     symbol, level, direction == 1 ? "BUY" : "SELL", lotSize, retcode, entryPrice, sl, tp, magic);

         // Additional debug info for common errors
         if(retcode == 10016) // ERR_INVALID_VOLUME
         {
            PrintFormat("[GRID-RECOVERY-ERROR] %s ERR_INVALID_VOLUME: lot=%.2f minVol=%.2f maxVol=%.2f step=%.4f | freeMargin=%.2f leverage=%d",
                        symbol, lotSize,
                        SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN),
                        SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX),
                        SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP),
                        AccountInfoDouble(ACCOUNT_MARGIN_FREE),
                        AccountInfoInteger(ACCOUNT_LEVERAGE));
         }
         else if(retcode == 10014) // ERR_INVALID_PRICE
         {
            PrintFormat("[GRID-RECOVERY-ERROR] %s ERR_INVALID_PRICE: entryPrice=%.5f SL=%.5f TP=%.5f digits=%d",
                        symbol, entryPrice, sl, tp, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS));
         }
         else if(retcode == 10008) // ERR_NOT_ENOUGH_MONEY
         {
            double usedMargin = 0.0;
            // ACCOUNT_MARGIN_USED may not be available in all MT5 builds
            // Fallback: used margin = margin - free margin
            double totalMargin = AccountInfoDouble(ACCOUNT_MARGIN);
            double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
            usedMargin = totalMargin - freeMargin;
            if(usedMargin < 0) usedMargin = 0;
            PrintFormat("[GRID-RECOVERY-ERROR] %s ERR_NOT_ENOUGH_MONEY: lot=%.2f freeMargin=%.2f usedMargin=%.2f totalMargin=%.2f",
                        symbol, lotSize, freeMargin, usedMargin, totalMargin);
         }
      }

      return result;
   }

   //+------------------------------------------------------------------+
   //| Close a single grid level position; logs the retcode on failure   |
   //+------------------------------------------------------------------+
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
