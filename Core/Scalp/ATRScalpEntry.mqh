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
#include <Trade\Trade.mqh>

#include "ATRScalpTypes.mqh"

class CUnifiedRiskManager;

class CATRScalpEntry
{
private:
   int                    m_baseMagic;
   CPositionSizer*        m_positionSizer;
   CUnifiedRiskManager*   m_riskManager;
   int                    m_totalTradesOpened;

public:
   CATRScalpEntry() :
      m_baseMagic(0),
      m_positionSizer(NULL),
      m_riskManager(NULL),
      m_totalTradesOpened(0)
   {
   }

   void Configure(int baseMagic, CPositionSizer *pSizer, CUnifiedRiskManager *pRiskManager)
   {
      m_baseMagic     = baseMagic;
      m_positionSizer = pSizer;
      m_riskManager   = pRiskManager;
   }

   int TotalTradesOpened() const { return m_totalTradesOpened; }

   bool OpenScalpTrade(int idx, int direction, SATRScalpSymbolState &state,
                       const SATRScalpingConfig &config, CTrade &trade)
   {
      string symbol = state.symbol;
      double atr = state.currentATR;

      if(atr <= 0.0)
      {
         PrintFormat("[ATR-SCALP] ATR is zero for %s �?cannot calculate SL/TP", symbol);
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

      // Stop validation must happen here: this engine sends through its own CTrade object, not CTradeManager, so the broker minimum stop distance, sized-stop widening rejection and take-profit-must-clear-spread tests are absent from the shared path - stops are validated before the send, not adjusted after.
      string scalpStopError = "";
      if(!CTradeMgrPricing::NormalizeAndValidateStops(symbol, orderType, entryPrice, tp, sl, tp, scalpStopError))
      {
         PrintFormat("[ATR-SCALP] STOPS REJECTED | %s | %s", symbol, scalpStopError);
         return false;
      }

      // Calculate magic number: baseMagic + magicOffset + symbolIndex
      int magic = m_baseMagic + config.magicOffset + idx;

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
            PrintFormat("[ATR-SCALP] REJECTED by risk manager | symbol=%s | reason=%s", symbol, riskResult.reason);
            return false;
         }
      }

      trade.SetExpertMagicNumber(magic);
      trade.SetDeviationInPoints(50);
      // L7-015: honor the symbol's supported fill mode; fall back to market (RETURN) when IOC/FOK unavailable
      long symFillMode = SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
      ENUM_ORDER_TYPE_FILLING scalpFill = ((symFillMode & SYMBOL_FILLING_IOC) != 0) ? ORDER_FILLING_IOC :
                                         (((symFillMode & SYMBOL_FILLING_FOK) != 0) ? ORDER_FILLING_FOK : ORDER_FILLING_RETURN);
      trade.SetTypeFilling(scalpFill);

      bool result = false;
      string dirStr = (direction == 1) ? "BUY" : "SELL";

      if(direction == 1)
         result = trade.Buy(lotSize, symbol, entryPrice, sl, tp,
                     "ATR-SCALP|" + dirStr);
      else
         result = trade.Sell(lotSize, symbol, entryPrice, sl, tp,
                     "ATR-SCALP|" + dirStr);

      uint retcode = trade.ResultRetcode();

      // Batch 177: this engine sends on its own CTrade, so it never reaches the
      // confirmation queue CTradeManager runs sends through. A DONE_PARTIAL retcode
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
