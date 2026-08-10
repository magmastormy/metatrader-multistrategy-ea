//+------------------------------------------------------------------+
//| FastScalpSignal.mqh                                              |
//| Decomposition extraction from CFastScalpEngine (behaviour        |
//| preserving).                                                     |
//|                                                                  |
//| Owns the two evaluation paths that made up                       |
//| CFastScalpEngine::EvaluateScalpSignal():                         |
//|   EvaluateFromCache() — zero-CopyBuffer fast path driven by      |
//|                         CScalpSignalCache                        |
//|   EvaluateSlowPath()  — RefreshIndicators + spread gate +        |
//|                         EMA crossover + RSI confirmation         |
//|                                                                  |
//| The engine keeps EvaluateScalpSignal() as a coordinator: it does |
//| the m_initialized guard, pulls the cache entry, and — only when  |
//| the fast path yields a non-NONE signal — mirrors the cached      |
//| indicator values into CFastScalpIndicators, exactly as the       |
//| original inline block did.                                       |
//|                                                                  |
//| Thresholds, comparison operators and short-circuit order are     |
//| reproduced verbatim.                                             |
//+------------------------------------------------------------------+
#property strict

#ifndef CORE_SCALP_FAST_SCALP_SIGNAL_MQH
#define CORE_SCALP_FAST_SCALP_SIGNAL_MQH

#include "../Utils/Enums.mqh"
#include "ScalpSignalCache.mqh"
#include "FastScalpTypes.mqh"
#include "FastScalpIndicators.mqh"
#include "FastScalpFilters.mqh"

//+------------------------------------------------------------------+
//| CFastScalpSignal — scalp signal evaluation                        |
//+------------------------------------------------------------------+
class CFastScalpSignal
{
public:
   //+------------------------------------------------------------------+
   //| Fast path: evaluate purely from a populated SScalpIndicatorCache  |
   //| Returns TRADE_SIGNAL_NONE on any gate rejection.                  |
   //+------------------------------------------------------------------+
   static ENUM_TRADE_SIGNAL EvaluateFromCache(const string symbol,
                                              const SScalpConfig &config,
                                              const SScalpIndicatorCache &cache)
   {
      // Spread gate using cached values
      double pointVal = SymbolInfoDouble(symbol, SYMBOL_POINT);
      if(pointVal > 0.0 && cache.atrValue > 0.0)
      {
         double spreadPrice = cache.spreadPoints * pointVal;
         if(spreadPrice > config.maxSpreadATRRatio * cache.atrValue)
            return TRADE_SIGNAL_NONE;
      }
      else
         return TRADE_SIGNAL_NONE;

      // EMA crossover detection using cached values
      ENUM_TRADE_SIGNAL emaSignal = TRADE_SIGNAL_NONE;
      if(cache.emaFastPrev <= cache.emaSlowPrev && cache.emaFast > cache.emaSlow)
         emaSignal = TRADE_SIGNAL_BUY;
      else if(cache.emaFastPrev >= cache.emaSlowPrev && cache.emaFast < cache.emaSlow)
         emaSignal = TRADE_SIGNAL_SELL;

      if(emaSignal == TRADE_SIGNAL_NONE)
         return TRADE_SIGNAL_NONE;

      // RSI confirmation using cached value
      if(emaSignal == TRADE_SIGNAL_BUY && cache.rsiValue >= config.rsiOverbought)
         return TRADE_SIGNAL_NONE;
      if(emaSignal == TRADE_SIGNAL_SELL && cache.rsiValue <= config.rsiOversold)
         return TRADE_SIGNAL_NONE;

      return emaSignal;
   }

   //+------------------------------------------------------------------+
   //| Fallback: existing RefreshIndicators path (slow path / timer path)|
   //+------------------------------------------------------------------+
   static ENUM_TRADE_SIGNAL EvaluateSlowPath(const string symbol,
                                             const SScalpConfig &config,
                                             CFastScalpIndicators &indicators)
   {
      // Fallback: existing RefreshIndicators path (slow path / timer path)
      if(!indicators.RefreshIndicators(symbol, config))
         return TRADE_SIGNAL_NONE;

      // Spread gate first — cheap rejection
      if(!CFastScalpFilters::IsSpreadAcceptable(symbol,
                                                indicators.GetATRCached(symbol, config),
                                                config.maxSpreadATRRatio))
         return TRADE_SIGNAL_NONE;

      // EMA crossover detection
      ENUM_TRADE_SIGNAL emaSignal2 = TRADE_SIGNAL_NONE;
      if(!CFastScalpIndicators::GetEMACrossover(symbol, config, emaSignal2))
         return TRADE_SIGNAL_NONE;

      if(emaSignal2 == TRADE_SIGNAL_NONE)
         return TRADE_SIGNAL_NONE;

      // RSI confirmation
      if(!indicators.IsRSIConfirmed(emaSignal2, config))
         return TRADE_SIGNAL_NONE;

      // Momentum burst as confluence booster (not required, but adds confidence)
      // Signal is valid without burst, but burst increases confidence
      return emaSignal2;
   }
};

#endif // CORE_SCALP_FAST_SCALP_SIGNAL_MQH
