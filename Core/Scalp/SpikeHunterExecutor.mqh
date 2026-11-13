// Trade-execution collaborators and counters for the spike hunter. Per-symbol state is read and written
// through the detector pointer, so CSpikeHunterDetector stays the single owner of it. Thresholds, literals,
// log tags and short-circuit order are verbatim; the includes mirror SpikeHunterEngine.mqh so this module
// sees the same collaborator definitions the original class body saw.
#property strict

#ifndef CORE_SCALP_SPIKE_HUNTER_EXECUTOR_MQH
#define CORE_SCALP_SPIKE_HUNTER_EXECUTOR_MQH

#include "../Utils/Instruments.mqh"
#include "../Risk/PositionSizer.mqh"
#include "../Risk/UnifiedRiskManager.mqh"
#include "../Trading/TradeManager.mqh"
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

// Dependency injection -mirrors the CSpikeHunterEngine::Init
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
         PrintFormat("[SPIKE-HUNT-TRADE] ATR is zero for %s ->cannot calculate SL/TP", symbol);
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
      lotSize = MathFloor(lotSize / stepVol + 1e-9) * stepVol;
      if(lotSize < minVol)
      {
         PrintFormat("[SPIKE-HUNT-TRADE] Lot below broker minimum, skipped | symbol=%s | lot=%.4f | min=%.4f",
                     symbol, lotSize, minVol);
         return false;
      }

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

      // Engine band. The old term added the Deriv family offset (9000..9999) plus symbolIndex, which
      // put spike orders on the same magic as family-classified consensus entries.
      int magic = m_baseMagic + m_detector.GetEffectiveMagicOffset(idx);

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
            PrintFormat("[SPIKE-HUNT-TRADE] REJECTED by risk manager | symbol=%s | reason=%s", symbol, riskResult.message);
            return false;
         }

         // Shrink-only and logged: the pipeline can raise adjustedLotSize to SYMBOL_VOLUME_MIN, and
         // adopting that would ship more than this engine's own sizing decided.
         if(riskResult.adjustedLotSize > 0.0 && riskResult.adjustedLotSize < lotSize)
         {
            PrintFormat("[SPIKE-RISK-ADJUSTED] %s | lot=%.2f -> %.2f | reason=%s",
                        symbol, lotSize, riskResult.adjustedLotSize, riskResult.message);
            lotSize = riskResult.adjustedLotSize;
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
         PrintFormat("[SPIKE-HUNT] %s | TradeManager NULL — refusing to trade | magic=%d", symbol, magic);
         return false;
      }
   }
};

#endif // CORE_SCALP_SPIKE_HUNTER_EXECUTOR_MQH
