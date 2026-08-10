//+------------------------------------------------------------------+
//| FastScalpSizing.mqh                                              |
//| Decomposition extraction from CFastScalpEngine (behaviour        |
//| preserving).                                                     |
//|                                                                  |
//| Stateless lot-sizing and confidence-scoring helpers pulled out   |
//| of CFastScalpEngine:                                             |
//|   CapLotToMargin()      — was a private method                   |
//|   ResolveBaseLotSize()  — was the CPositionSizer / min-lot       |
//|                           fallback block inside ShouldEnterScalp |
//|   CalculateConfidence() — was the 0.60 / +0.15 / +0.10 / cap 0.90|
//|                           block inside ShouldEnterScalp          |
//|                                                                  |
//| The momentum-burst flag and the ATR are resolved by the caller   |
//| in the original order (IsMomentumBurst first, then GetATRCached) |
//| so the indicator refresh sequence is bit-for-bit identical.      |
//+------------------------------------------------------------------+
#property strict

#ifndef CORE_SCALP_FAST_SCALP_SIZING_MQH
#define CORE_SCALP_FAST_SCALP_SIZING_MQH

#include "../Utils/Enums.mqh"
#include "../Risk/PositionSizer.mqh"
#include "FastScalpTypes.mqh"

//+------------------------------------------------------------------+
//| CFastScalpSizing — stateless scalp sizing / confidence            |
//+------------------------------------------------------------------+
class CFastScalpSizing
{
public:
   //+------------------------------------------------------------------+
   //| Cap lot size to available margin and symbol volume limits         |
   //| Prevents margin rejections (retcode=10018) and volume limit       |
   //| rejections (retcode=10034) on small accounts                     |
   //+------------------------------------------------------------------+
   static double CapLotToMargin(double calculatedLot, const string symbol)
   {
      double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      double marginPerLot = 0;
      double askPrice = SymbolInfoDouble(symbol, SYMBOL_ASK);
      if(!OrderCalcMargin(ORDER_TYPE_BUY, symbol, 1.0, askPrice, marginPerLot) || marginPerLot <= 0.0)
         return calculatedLot;
      double maxLotByMargin = freeMargin / (marginPerLot * 1.5); // 1.5x safety factor
      double symbolMaxVolume = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
      double cappedLot = MathMin(calculatedLot, MathMin(maxLotByMargin, symbolMaxVolume));
      if(cappedLot < calculatedLot)
      {
         Print("[SCALP-LOT-CAPPED] ", symbol, " lot capped from ", calculatedLot, " to ", cappedLot,
               " (margin_max=", maxLotByMargin, " vol_max=", symbolMaxVolume, ")");
      }
      return cappedLot;
   }

   //+------------------------------------------------------------------+
   //| Confidence score for a validated scalp signal                     |
   //| Base 0.60 (EMA crossover + RSI), +0.15 momentum burst,            |
   //| +0.10 tight spread (< 15% ATR), hard cap at 0.90.                 |
   //+------------------------------------------------------------------+
   static double CalculateConfidence(const string symbol, double atr, bool momentumBurst)
   {
      // Calculate confidence
      double confidence = 0.60; // Base confidence for EMA crossover + RSI

      // Boost confidence with momentum burst
      if(momentumBurst)
         confidence += 0.15;

      // Tight spread bonus
      if(atr > 0.0)
      {
         double spread = (double)SymbolInfoInteger(symbol, SYMBOL_SPREAD);
         double point  = SymbolInfoDouble(symbol, SYMBOL_POINT);
         if(point > 0.0)
         {
            double spreadRatio = (spread * point) / atr;
            if(spreadRatio < 0.15)
               confidence += 0.10;
         }
      }

      // Cap confidence at 0.90
      return MathMin(confidence, 0.90);
   }

   //+------------------------------------------------------------------+
   //| Calculate lot size using CPositionSizer, with min-lot fallback    |
   //+------------------------------------------------------------------+
   static double ResolveBaseLotSize(const string symbol, const SScalpConfig &config,
                                    double confidence, CPositionSizer* positionSizer)
   {
      // Calculate lot size using CPositionSizer
      if(positionSizer != NULL && positionSizer.IsInitialized())
      {
         return positionSizer.CalculatePositionSize(
                   symbol, (double)config.scalpSLPips, confidence);
      }

      // Fallback to minimum lot
      double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      return (minLot > 0.0) ? minLot : MIN_LOT_SIZE;
   }
};

#endif // CORE_SCALP_FAST_SCALP_SIZING_MQH
