//+------------------------------------------------------------------+
//| ATRScalpEntry.mqh                                                |
//| Entry preparation and execution for the ATR scalping engine:     |
//| SL/TP sizing from ATR, lot sizing + margin cap, pre-trade risk   |
//| validation and the market order itself.                          |
//| Extracted verbatim from ATRScalpingEngine.mqh (structural only). |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Aggressive Trading Systems"
#property link      "https://www.aggressivetrading.com"
#property version   "1.00"
#property strict

#ifndef CORE_SCALP_ATR_SCALP_ENTRY_MQH
#define CORE_SCALP_ATR_SCALP_ENTRY_MQH

#include "../Utils/Instruments.mqh"
#include "../Risk/PositionSizer.mqh"
#include "../Risk/RiskValidationGate.mqh"
#include <Trade\Trade.mqh>

#include "ATRScalpTypes.mqh"

class CUnifiedRiskManager;

//+------------------------------------------------------------------+
//| CATRScalpEntry — owns the entry dependencies and open counter     |
//+------------------------------------------------------------------+
class CATRScalpEntry
{
private:
   int                    m_baseMagic;
   CPositionSizer*        m_positionSizer;
   CUnifiedRiskManager*   m_riskManager;
   int                    m_totalTradesOpened;

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CATRScalpEntry() :
      m_baseMagic(0),
      m_positionSizer(NULL),
      m_riskManager(NULL),
      m_totalTradesOpened(0)
   {
   }

   //+------------------------------------------------------------------+
   //| Wire up the entry dependencies                                    |
   //+------------------------------------------------------------------+
   void Configure(int baseMagic, CPositionSizer *pSizer, CUnifiedRiskManager *pRiskManager)
   {
      m_baseMagic     = baseMagic;
      m_positionSizer = pSizer;
      m_riskManager   = pRiskManager;
   }

   //+------------------------------------------------------------------+
   //| Opened trade counter                                              |
   //+------------------------------------------------------------------+
   int TotalTradesOpened() const { return m_totalTradesOpened; }

   //+------------------------------------------------------------------+
   //| Open a scalp trade in the given direction                         |
   //+------------------------------------------------------------------+
   bool OpenScalpTrade(int idx, int direction, SATRScalpSymbolState &state,
                       const SATRScalpingConfig &config, CTrade &trade)
   {
      string symbol = state.symbol;
      double atr = state.currentATR;

      if(atr <= 0.0)
      {
         PrintFormat("[ATR-SCALP] ATR is zero for %s — cannot calculate SL/TP", symbol);
         return false;
      }

      // Calculate SL and TP distances in price
      double slDistance = atr * config.slAtrMultiplier;
      double tpDistance = atr * config.tpAtrMultiplier;

      // Get current price
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

      // Calculate entry, SL, TP
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

      // Set up trade object
      trade.SetExpertMagicNumber(magic);
      trade.SetDeviationInPoints(50);
      trade.SetTypeFilling(ORDER_FILLING_IOC);

      // Execute trade
      bool result = false;
      string dirStr = (direction == 1) ? "BUY" : "SELL";

      if(direction == 1)
         result = trade.Buy(lotSize, symbol, entryPrice, sl, tp,
                     "ATR-SCALP|" + dirStr);
      else
         result = trade.Sell(lotSize, symbol, entryPrice, sl, tp,
                     "ATR-SCALP|" + dirStr);

      if(result)
      {
         state.lastTradeTime = TimeCurrent();
         m_totalTradesOpened++;

         PrintFormat("[ATR-SCALP] Symbol=%s Direction=%s Lot=%.2f SL=%.5f TP=%.5f ATR=%.5f magic=%d",
                     symbol, dirStr, lotSize, sl, tp, atr, magic);
      }
      else
      {
         uint retcode = trade.ResultRetcode();
         PrintFormat("[ATR-SCALP-FAILED] Symbol=%s Direction=%s Lot=%.2f retcode=%u",
                     symbol, dirStr, lotSize, retcode);
      }

      return result;
   }
};

#endif // CORE_SCALP_ATR_SCALP_ENTRY_MQH
