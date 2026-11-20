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
#include "../Trading/TradeManager.mqh"

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
      m_tradeManager(NULL),
      m_totalTradesOpened(0)
   {
   }

   void Configure(int baseMagic, CPositionSizer *pSizer, CUnifiedRiskManager *pRiskManager,
                  CTradeManager *pTradeManager)
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

      if(m_riskManager == NULL || !m_riskManager.IsInitialized())
      {
         PrintFormat("[ATR-SCALP] UnifiedRiskManager unavailable - refusing entry | symbol=%s", symbol);
         return false;
      }
      if(m_tradeManager == NULL)
      {
         PrintFormat("[ATR-SCALP] TradeManager unavailable - refusing entry | symbol=%s", symbol);
         return false;
      }

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

      if(m_positionSizer == NULL || !m_positionSizer.IsInitialized())
      {
         PrintFormat("[ATR-SCALP] PositionSizer unavailable - refusing entry | symbol=%s", symbol);
         return false;
      }
      lotSize = m_positionSizer.CalculatePositionSize(symbol, slPips, 0.65);

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

      // Validate normalized stops before routing the request through TradeManager.
      string scalpStopError = "";
      if(!CTradeMgrPricing::NormalizeAndValidateStops(symbol, orderType, entryPrice, tp, sl, tp, scalpStopError))
      {
         PrintFormat("[ATR-SCALP] STOPS REJECTED | %s | %s", symbol, scalpStopError);
         return false;
      }

      slPips = MathAbs(entryPrice - sl) / point;
      double tpPips = MathAbs(tp - entryPrice) / point;

      // Band only: base + 7000 + symbolIndex collided with ASSET_FOREX's consensus magic for that slot, and the position already names its symbol.
      int magic = m_baseMagic + config.magicOffset;

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

      double validatedLotSize = (riskResult.adjustedLotSize > 0.0) ? riskResult.adjustedLotSize : lotSize;
      if(riskResult.adjustedLotSize > 0.0 && riskResult.adjustedLotSize < lotSize)
      {
         PrintFormat("[ATR-SCALP-RISK-ADJUSTED] %s | lot=%.2f -> %.2f | reason=%s",
                     symbol, lotSize, riskResult.adjustedLotSize, riskResult.message);
         lotSize = riskResult.adjustedLotSize;
      }
      if(riskResult.virtualReservationOwnerTag != "")
         m_riskManager.UpdateVirtualPositionRisk(riskResult.virtualReservationOwnerTag,
                                                 lotSize,
                                                 riskResult.riskPercent * lotSize / validatedLotSize);

      string dirStr = (direction == 1) ? "BUY" : "SELL";
      bool result = m_tradeManager.OpenPosition(symbol, orderType, lotSize, entryPrice,
                                                slPips, tpPips, "ATR-SCALP|" + dirStr,
                                                (uint)magic);
      STradeExecutionReceipt receipt;
      m_tradeManager.GetLastExecutionReceipt(receipt);
      if(receipt.accepted && riskResult.virtualReservationOwnerTag != "")
      {
         double filledLotSize = receipt.filledVolume > 0.0 ? receipt.filledVolume : lotSize;
         m_riskManager.UpdateVirtualPositionRisk(riskResult.virtualReservationOwnerTag,
                                                 filledLotSize,
                                                 riskResult.riskPercent * filledLotSize / validatedLotSize);
      }
      else if(!result && !receipt.accepted)
         m_riskManager.ReleaseVirtualPosition(riskResult.virtualReservationOwnerTag);

      if(result)
      {
         state.lastTradeTime = TimeCurrent();
         m_totalTradesOpened++;

         PrintFormat("[ATR-SCALP] Symbol=%s Direction=%s Lot=%.2f SL=%.5f TP=%.5f ATR=%.5f magic=%d",
                     symbol, dirStr,
                     receipt.filledVolume > 0.0 ? receipt.filledVolume : lotSize,
                     receipt.stopLoss > 0.0 ? receipt.stopLoss : sl,
                     receipt.takeProfit > 0.0 ? receipt.takeProfit : tp,
                     atr, magic);
      }
      else
      {
         PrintFormat("[ATR-SCALP-FAILED] Symbol=%s Direction=%s Lot=%.2f retcode=%u",
                     symbol, dirStr, lotSize, receipt.retcode);
      }

      return result;
   }
};

#endif // CORE_SCALP_ATR_SCALP_ENTRY_MQH


