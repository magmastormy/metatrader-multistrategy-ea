// Owns the trade-execution collaborators and counters:
// m_baseMagic, m_positionSizer, m_riskManager, m_tradeManager,
// m_trade (CTrade fallback), m_aiAdapter, m_totalTradesOpened
// Per-symbol state reads/writes are routed through the detector
// pointer (symbol, ATR, confluence, cooldown stamps) so the state
// stays single-owned by CSpikeHunterDetector. Every threshold,
// literal, log tag and short-circuit order is reproduced verbatim.
// The includes below mirror SpikeHunterEngine.mqh exactly so this
// module sees the identical set of collaborator definitions the
// original class body saw.
#property strict

#ifndef CORE_SCALP_SPIKE_HUNTER_EXECUTOR_MQH
#define CORE_SCALP_SPIKE_HUNTER_EXECUTOR_MQH

#include "../Utils/Instruments.mqh"
#include "../Risk/PositionSizer.mqh"
#include "../Risk/UnifiedRiskManager.mqh"
#include "../Trading/TradeMgrPricing.mqh"
#include "../Trading/TradeMgrPreflight.mqh"
#include <Trade\Trade.mqh>

#include "SpikeHunterTypes.mqh"
#include "SpikeHunterDetector.mqh"

class CUnifiedRiskManager;

class CAIAdapter;

class CSpikeHunterExecutor
{
private:
   SSpikeHunterConfig              m_config;
   int                             m_baseMagic;
   CPositionSizer*                 m_positionSizer;
   CUnifiedRiskManager*            m_riskManager;
   CTradeManager*                  m_tradeManager;        // For safe trade execution via TradeManager
   CTrade                          m_trade;                // For synchronous order execution (legacy)
   CAIAdapter*                     m_aiAdapter;            // L10-018: AI adapter for vote logging

   CSpikeHunterDetector*           m_detector;             // Per-symbol state owner (not owned)

   int                             m_totalTradesOpened;

public:
   CSpikeHunterExecutor() :
      m_baseMagic(0),
      m_positionSizer(NULL),
      m_riskManager(NULL),
      m_tradeManager(NULL),
      m_aiAdapter(NULL),
      m_detector(NULL),
      m_totalTradesOpened(0)
   {
   }

// Dependency injection �?mirrors the CSpikeHunterEngine::Init
// assignment block one-for-one.
   void Init(const SSpikeHunterConfig &config,
             int baseMagic,
             CPositionSizer *pSizer,
             CUnifiedRiskManager *pRiskManager,
             CTradeManager *pTradeManager,
             CAIAdapter *pAIAdapter,
             CSpikeHunterDetector *pDetector)
   {
      m_config         = config;
      m_baseMagic      = baseMagic;
      m_positionSizer  = pSizer;
      m_riskManager    = pRiskManager;
      m_tradeManager   = pTradeManager;
      m_aiAdapter      = pAIAdapter;
      m_detector       = pDetector;
   }

   //--- Accessor (was CSpikeHunterEngine::m_totalTradesOpened)
   int GetTotalTradesOpened() const { return m_totalTradesOpened; }

// Count active spike positions (positions with SPIKE-HUNT comment)
   static int GetActiveSpikePositions()
   {
      int count = 0;
      int total = PositionsTotal();
      for(int i = 0; i < total; i++)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket <= 0) continue;
         if(PositionSelectByTicket(ticket))
         {
            string comment = PositionGetString(POSITION_COMMENT);
            if(StringFind(comment, "SPIKE-HUNT") >= 0)
               count++;
         }
      }
      return count;
   }

   bool CanOpenSpikeTrade(int idx) const
   {
      // Check cooldown (use family-specific cooldown)
      datetime now = TimeCurrent();
      if(m_detector.GetLastSpikeTradeTime(idx) > 0)
      {
         ulong elapsedMs = (ulong)((now - m_detector.GetLastSpikeTradeTime(idx)) * 1000);
         if(elapsedMs < (ulong)m_detector.GetEffectiveCooldownMs(idx))
            return false;
      }

      if(GetActiveSpikePositions() >= m_config.maxSpikePositions)
         return false;

      return true;
   }

   bool OpenSpikeTrade(int idx, int direction)
   {
      string symbol = m_detector.GetSymbolName(idx);
      double atr = m_detector.GetCurrentATR(idx);

      if(atr <= 0.0)
      {
         PrintFormat("[SPIKE-HUNT-TRADE] ATR is zero for %s �?cannot calculate SL/TP", symbol);
         return false;
      }

      // Calculate SL and TP distances in price (use family-specific multipliers)
      double slDistance = atr * m_detector.GetEffectiveSLAtrMultiplier(idx);
      double tpDistance = atr * m_detector.GetEffectiveTPAtrMultiplier(idx);

      // Convert SL distance to pips for position sizer
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      if(point <= 0.0)
      {
         PrintFormat("[SPIKE-HUNT-TRADE] Invalid point for %s", symbol);
         return false;
      }

      double slPips = slDistance / point;
      double tpPips = tpDistance / point;

      double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
      if(bid <= 0.0 || ask <= 0.0)
      {
         PrintFormat("[SPIKE-HUNT-TRADE] Invalid prices for %s: bid=%.5f ask=%.5f", symbol, bid, ask);
         return false;
      }

      // Calculate lot size using CPositionSizer
            double lotSize = 0.0;
            ENUM_ORDER_TYPE orderType = (direction == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;

            if(m_positionSizer != NULL && m_positionSizer.IsInitialized())
            {
               lotSize = m_positionSizer.CalculatePositionSize(
                           symbol, slPips, 0.80);
            }
      else
      {
         double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
         lotSize = (minLot > 0.0) ? minLot : MIN_LOT_SIZE;
      }

      if(lotSize <= 0.0)
      {
         PrintFormat("[SPIKE-HUNT-TRADE] Invalid lot size for %s: %.2f", symbol, lotSize);
         return false;
      }

      // Cap lot to available margin
      double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      double marginPerLot = 0.0;
      double priceForMargin = (orderType == ORDER_TYPE_BUY) ? ask : bid;
      if(OrderCalcMargin(orderType, symbol, 1.0, priceForMargin, marginPerLot) && marginPerLot > 0.0)
      {
         double maxLotByMargin = freeMargin / (marginPerLot * 1.5);
         double symbolMaxVolume = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
         lotSize = MathMin(lotSize, MathMin(maxLotByMargin, symbolMaxVolume));
      }

      // Normalize lot to step size
      double stepVol = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
      double minVol  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      if(stepVol <= 0.0) stepVol = 0.01;
      lotSize = MathRound(lotSize / stepVol) * stepVol;
      if(lotSize < minVol)
         lotSize = minVol;

      int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      double entryPrice = (direction == 1) ? ask : bid;
      double sl = 0.0, tp = 0.0;

      if(direction == 1) // BUY
      {
         sl = NormalizeDouble(entryPrice - slDistance, digits);
         tp = NormalizeDouble(entryPrice + tpDistance, digits);
      }
      else // SELL
      {
         sl = NormalizeDouble(entryPrice + slDistance, digits);
         tp = NormalizeDouble(entryPrice - tpDistance, digits);
      }

      // Shared stop-feasibility and expectancy gate (see ATRScalpEntry).
      string spikeStopError = "";
      if(!CTradeMgrPricing::NormalizeAndValidateStops(symbol, orderType, entryPrice, tp, sl, tp, spikeStopError))
      {
         PrintFormat("[SPIKE-HUNT] STOPS REJECTED | %s | %s", symbol, spikeStopError);
         return false;
      }

      // Calculate magic number: baseMagic + familyMagicOffset + symbolIndex
      int magic = m_baseMagic + m_detector.GetEffectiveMagicOffset(idx) + idx;

      string dirStr = (direction == 1) ? "BUY" : "SELL";

      // Pre-trade risk validation via UnifiedRiskManager (AGENTS.md invariant #1)
      if(m_riskManager != NULL)
      {
         STradeValidationRequest riskReq;
         ZeroMemory(riskReq);
         riskReq.symbol       = symbol;
         riskReq.orderType    = orderType;
         riskReq.lotSize      = lotSize;
         riskReq.stopLossPips = slPips;
         riskReq.takeProfitPips = tpPips;
         riskReq.confidence   = 0.8;
         riskReq.strategy     = "SPIKE-HUNT";
         riskReq.requestTime  = TimeCurrent();

         SValidationResult riskResult = m_riskManager.ValidateTradeRequest(riskReq, "spike-pretrade");
         if(!riskResult.approved)
         {
            PrintFormat("[SPIKE-HUNT-TRADE] REJECTED by risk manager | symbol=%s | reason=%s", symbol, riskResult.reason);
            return false;
         }
      }

      // L10-008: Use TradeManager for safety checks and execution
      if(m_tradeManager != NULL)
      {
         bool result = m_tradeManager.OpenPosition(
             symbol,
             orderType,
             lotSize,
             entryPrice,
             slPips,
             tpPips,
             "SPIKE-HUNT|" + dirStr + "|C:" + IntegerToString(m_detector.GetConfluenceCount(idx)) + "/3",
            (uint)magic
         );

         // L10-018: AI-VOTE logging
         if(m_aiAdapter != NULL)
         {
             PrintFormat("[AI-VOTE] symbol=%s strategy=SpikeHunter vote=%s",
                         symbol, dirStr);
         }

         if(result)
         {
            m_detector.MarkSpikeTradeOpened(idx);
            m_totalTradesOpened++;

            PrintFormat("[SPIKE-HUNT-TRADE] Symbol=%s Direction=%s Lot=%.2f SL=%.5f TP=%.5f Confluence=%d/3 ATR=%.5f magic=%d",
                        symbol, dirStr, lotSize, sl, tp,
                        m_detector.GetConfluenceCount(idx), atr, magic);
         }
         else
         {
            uint retcode = m_tradeManager.GetLastRetcode();
            PrintFormat("[SPIKE-HUNT-TRADE-FAILED] Symbol=%s Direction=%s Lot=%.2f retcode=%u",
                        symbol, dirStr, lotSize, retcode);
         }

         return result;
      }
      else
      {
         // NOTE: this is the branch that actually runs - EAOrchestrator's
         // m_spikeHunter.Init(...) passes no CTradeManager, so the governed send
         // path above is unreachable and the stop gate had to be added here too.
         m_trade.SetExpertMagicNumber(magic);
         // L10-014: Use dynamic slippage if TradeManager available, else default
         uint fallbackSlippage = 50;
         if(m_tradeManager != NULL)
         {
             fallbackSlippage = m_tradeManager.GetDynamicSlippage(symbol);
         }
         m_trade.SetDeviationInPoints(fallbackSlippage);
         // L7-015: honor the symbol's supported fill mode; fall back to market (RETURN) when IOC/FOK unavailable
         long symFillMode = SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
         ENUM_ORDER_TYPE_FILLING scalpFill = ((symFillMode & SYMBOL_FILLING_IOC) != 0) ? ORDER_FILLING_IOC :
                                            (((symFillMode & SYMBOL_FILLING_FOK) != 0) ? ORDER_FILLING_FOK : ORDER_FILLING_RETURN);
         m_trade.SetTypeFilling(scalpFill);

         bool result = false;
         if(direction == 1)
            result = m_trade.Buy(lotSize, symbol, entryPrice, sl, tp,
                        "SPIKE-HUNT|" + dirStr + "|C:" + IntegerToString(m_detector.GetConfluenceCount(idx)) + "/3");
         else
            result = m_trade.Sell(lotSize, symbol, entryPrice, sl, tp,
                        "SPIKE-HUNT|" + dirStr + "|C:" + IntegerToString(m_detector.GetConfluenceCount(idx)) + "/3");

         // L10-018: AI-VOTE logging (fallback path)
         if(m_aiAdapter != NULL)
         {
             PrintFormat("[AI-VOTE] symbol=%s strategy=SpikeHunter vote=%s",
                         symbol, dirStr);
         }

         // Batch 177: DONE_PARTIAL arrives as result == false with a position open, and the caller
         // would hunt the same spike again. Confirm from the position before declaring failure.
         uint sendRetcode = m_trade.ResultRetcode();
         if(!result)
         {
            ulong confirmTicket = 0;
            double confirmVolume = 0.0;
            if(CTradeMgrPreflight::FindFreshPositionForSend(symbol,
                   (direction == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,
                   lotSize, confirmTicket, confirmVolume))
            {
               PrintFormat("[SPIKE-HUNT] FILL CONFIRMED BY POSITION | Symbol=%s | Direction=%s | ticket=%I64u | filled=%.2f of %.2f | retcode=%u | spike marked opened, not resent",
                           symbol, dirStr, confirmTicket, confirmVolume, lotSize, sendRetcode);
               result = true;
            }
         }

         if(result)
         {
            m_detector.MarkSpikeTradeOpened(idx);
            m_totalTradesOpened++;

            PrintFormat("[SPIKE-HUNT-TRADE] Symbol=%s Direction=%s Lot=%.2f SL=%.5f TP=%.5f Confluence=%d/3 ATR=%.5f magic=%d",
                        symbol, dirStr, lotSize, sl, tp,
                        m_detector.GetConfluenceCount(idx), atr, magic);
         }
         else
         {
            PrintFormat("[SPIKE-HUNT-TRADE-FAILED] Symbol=%s Direction=%s Lot=%.2f retcode=%u",
                        symbol, dirStr, lotSize, sendRetcode);
         }

         return result;
      }
   }
};

#endif // CORE_SCALP_SPIKE_HUNTER_EXECUTOR_MQH
