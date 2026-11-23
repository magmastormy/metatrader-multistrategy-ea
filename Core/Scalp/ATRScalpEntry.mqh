// Entry preparation and execution for the ATR scalping engine:
// SL/TP sizing from ATR, lot sizing + margin cap, pre-trade risk
// validation and the market order itself.
// Extracted verbatim from ATRScalpingEngine.mqh (structural only).
#property copyright "Copyright 2026, Aggressive Trading Systems"
#property link      "https://www.aggressivetrading.com"
#property version   "1.00"
#property strict

#ifndef CORE_SCALP_ATR_SCALP_ENTRY_MQH
#define CORE_SCALP_ATR_SCALP_ENTRY_MQH

#include "../Utils/Instruments.mqh"
#include "../Risk/PositionSizer.mqh"
#include "../Risk/UnifiedRiskManager.mqh"
#include "../Trading/TradeMgrPricing.mqh"
#include "../Trading/TradeMgrPreflight.mqh"
#include "../Trading/TradeManager.mqh"
#include <Trade\Trade.mqh>

#include "ATRScalpTypes.mqh"

class CUnifiedRiskManager;

class CATRScalpEntry
{
private:
   int                    m_baseMagic;
   CPositionSizer*        m_positionSizer;
   CUnifiedRiskManager*   m_riskManager;
   CTradeManager*         m_tradeManager;
   int                    m_totalTradesOpened;

public:
   CATRScalpEntry() :
      m_baseMagic(0),
      m_positionSizer(NULL),
      m_riskManager(NULL),
      m_totalTradesOpened(0)
   {
   }

   void Configure(int baseMagic, CPositionSizer *pSizer, CUnifiedRiskManager *pRiskManager,
                  CTradeManager *pTradeManager = NULL)
   {
      m_baseMagic     = baseMagic;
      m_positionSizer = pSizer;
      m_riskManager   = pRiskManager;
      m_tradeManager  = pTradeManager;
   }

   int TotalTradesOpened() const { return m_totalTradesOpened; }

   bool OpenScalpTrade(int idx, int direction, SATRScalpSymbolState &state,
                       const SATRScalpingConfig &config)
   {
      string symbol = state.symbol;
      double atr = state.currentATR;

      if(atr <= 0.0)
      {
         PrintFormat("[ATR-SCALP] ATR is zero for %s ->cannot calculate SL/TP", symbol);
         return false;
      }

      // Calculate SL and TP distances in price
      double slDistance = atr * config.slAtrMultiplier;
      double tpDistance = atr * config.tpAtrMultiplier;

      double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
      if(bid <= 0.0 || ask <= 0.0)
      {
         PrintFormat("[ATR-SCALP] Invalid prices for %s: bid=%.5f ask=%.5f", symbol, bid, ask);
         return false;
      }

      // Calculate lot size using CPositionSizer
      double lotSize = 0.0;
      ENUM_ORDER_TYPE orderType = (direction == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;

      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      if(point <= 0.0)
      {
         PrintFormat("[ATR-SCALP] Invalid point for %s", symbol);
         return false;
      }

      double slPips = slDistance / point;

      if(m_positionSizer != NULL && m_positionSizer.IsInitialized())
      {
         lotSize = m_positionSizer.CalculatePositionSize(
                     symbol, slPips, 0.65);
      }
      else
      {
         double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
         lotSize = (minLot > 0.0) ? minLot : MIN_LOT_SIZE;
      }

      if(lotSize <= 0.0)
      {
         PrintFormat("[ATR-SCALP] Invalid lot size for %s: %.2f", symbol, lotSize);
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
      lotSize = MathFloor((lotSize + 1e-12) / stepVol) * stepVol;
      if(lotSize < minVol)
      {
         PrintFormat("[ATR-SCALP] Lot below broker minimum after sizing for %s: %.4f < %.2f - trade skipped",
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

      // Pre-send stop validation: NormalizeAndValidateStops applies the broker minimum stop distance, sized-stop widening rejection and take-profit-must-clear-spread tests before the order reaches CTradeManager.
      string scalpStopError = "";
      if(!CTradeMgrPricing::NormalizeAndValidateStops(symbol, orderType, entryPrice, tp, sl, tp, scalpStopError))
      {
         PrintFormat("[ATR-SCALP] STOPS REJECTED | %s | %s", symbol, scalpStopError);
         return false;
      }

      // Band only: base + 7000 + symbolIndex collided with ASSET_FOREX's consensus magic for that slot, and the position already names its symbol.
      int magic = m_baseMagic + config.magicOffset;

      // Pre-trade risk validation via UnifiedRiskManager (AGENTS.md invariant #1)
      if(m_riskManager != NULL)
      {
         STradeValidationRequest riskReq;
         ZeroMemory(riskReq);
         riskReq.symbol       = symbol;
         riskReq.orderType    = orderType;
         riskReq.lotSize      = lotSize;
         riskReq.stopLossPips = slPips;
         riskReq.confidence   = 0.7;
         riskReq.strategy     = "ATR-SCALP";
         riskReq.requestTime  = TimeCurrent();

         SValidationResult riskResult = m_riskManager.ValidateTradeRequest(riskReq, "atr-scalp-pretrade");
         if(!riskResult.approved)
         {
            PrintFormat("[ATR-SCALP] REJECTED by risk manager | symbol=%s | reason=%s", symbol, riskResult.message);
            return false;
         }

         // Shrink-only and logged: the pipeline can raise adjustedLotSize to SYMBOL_VOLUME_MIN, and
         // adopting that would ship more than this engine's own sizing decided.
         if(riskResult.adjustedLotSize > 0.0 && riskResult.adjustedLotSize < lotSize)
         {
            PrintFormat("[ATR-SCALP-RISK-ADJUSTED] %s | lot=%.2f -> %.2f | reason=%s",
                        symbol, lotSize, riskResult.adjustedLotSize, riskResult.message);
            lotSize = riskResult.adjustedLotSize;
         }
      }

      if(m_tradeManager == NULL)
      {
         PrintFormat("[ATR-SCALP-FAILED] %s | no CTradeManager configured - entry refused", symbol);
         return false;
      }

      bool result = false;
      string dirStr = (direction == 1) ? "BUY" : "SELL";

      // Route through CTradeManager so the send reaches the confirmation queue,
      // per-symbol trade objects, execution-quality metrics and journal that the
      // raw CTrade path bypassed. OpenPosition takes stop distances in points
      // (measured from the fill price), so the ATR-derived absolute stops become
      // point distances off the pre-send quote.
      double pointSize = SymbolInfoDouble(symbol, SYMBOL_POINT);
      double slDistPoints = (pointSize > 0.0) ? MathAbs(entryPrice - sl) / pointSize : 0.0;
      double tpDistPoints = (pointSize > 0.0) ? MathAbs(entryPrice - tp) / pointSize : 0.0;
      result = m_tradeManager.OpenPosition(symbol, orderType, lotSize, entryPrice,
                                           slDistPoints, tpDistPoints,
                                           "ATR-SCALP|" + dirStr, (uint)magic);

      uint retcode = m_tradeManager.GetLastRetcode();

      // Sends now go through CTradeManager, which runs its own confirmation queue;
      // a DONE_PARTIAL retcode
      // arrives here as result == false while a position exists, and the caller would
      // re-fire the same scalp on the next scan - duplicating exposure the engine
      // believes it never opened. Confirm from the position before declaring failure.
      if(!result)
      {
         ulong confirmTicket = 0;
         double confirmVolume = 0.0;
         if(CTradeMgrPreflight::FindFreshPositionForSend(symbol,
                (direction == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,
                lotSize, confirmTicket, confirmVolume, "ATR-SCALP"))
         {
            PrintFormat("[ATR-SCALP] FILL CONFIRMED BY POSITION | Symbol=%s | Direction=%s | ticket=%I64u | filled=%.2f of %.2f | retcode=%u | not resent",
                        symbol, dirStr, confirmTicket, confirmVolume, lotSize, retcode);
            result = true;
         }
      }

      if(result)
      {
         state.lastTradeTime = TimeCurrent();
         m_totalTradesOpened++;

         PrintFormat("[ATR-SCALP] Symbol=%s Direction=%s Lot=%.2f SL=%.5f TP=%.5f ATR=%.5f magic=%d",
                     symbol, dirStr, lotSize, sl, tp, atr, magic);
      }
      else
      {
         PrintFormat("[ATR-SCALP-FAILED] Symbol=%s Direction=%s Lot=%.2f retcode=%u",
                     symbol, dirStr, lotSize, retcode);
      }

      return result;
   }
};

#endif // CORE_SCALP_ATR_SCALP_ENTRY_MQH


