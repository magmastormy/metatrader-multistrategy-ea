// Owns the two scalp signal evaluation paths: cached fast path and indicator-refresh slow path.
// The engine keeps EvaluateScalpSignal() as a coordinator: m_initialized guard, cache pull, and only on a non-NONE fast-path signal does it mirror the cached indicator values into CFastScalpIndicators.
// Gate order in both paths: ATR/spread cost, then EMA 5/13 crossover, then RSI(7) confirmation.
// `gateReject` is written only by a gate; an absent crossover leaves it empty.
#property strict

#ifndef CORE_SCALP_FAST_SCALP_SIGNAL_MQH
#define CORE_SCALP_FAST_SCALP_SIGNAL_MQH

#include "../Utils/Enums.mqh"
#include "ScalpSignalCache.mqh"
#include "FastScalpTypes.mqh"
#include "FastScalpIndicators.mqh"
#include "FastScalpFilters.mqh"

class CFastScalpSignal
{
public:
// Fast path: evaluate purely from a populated SScalpIndicatorCache
// Returns TRADE_SIGNAL_NONE on any gate rejection. `gateReject` names the gate that refused, or stays
// empty for "no crossover this bar" - the common case, which is not a refusal worth a journal line.
   static ENUM_TRADE_SIGNAL EvaluateFromCache(const string symbol,
                                              const SScalpConfig &config,
                                              const SScalpIndicatorCache &cache,
                                              string &gateReject)
   {
      // Spread gate using cached values
      double pointVal = SymbolInfoDouble(symbol, SYMBOL_POINT);
      if(pointVal <= 0.0 || cache.atrValue <= 0.0)
      {
         gateReject = "no_atr_or_point";
         return TRADE_SIGNAL_NONE;
      }

      double spreadPrice = cache.spreadPoints * pointVal;
      if(spreadPrice > config.maxSpreadATRRatio * cache.atrValue)
      {
         gateReject = "spread_vs_atr";
         return TRADE_SIGNAL_NONE;
      }

      // EMA crossover detection using cached values
      ENUM_TRADE_SIGNAL emaSignal = TRADE_SIGNAL_NONE;
      if(cache.emaFastPrev <= cache.emaSlowPrev && cache.emaFast > cache.emaSlow)
         emaSignal = TRADE_SIGNAL_BUY;
      else if(cache.emaFastPrev >= cache.emaSlowPrev && cache.emaFast < cache.emaSlow)
         emaSignal = TRADE_SIGNAL_SELL;

      if(emaSignal == TRADE_SIGNAL_NONE)
         return TRADE_SIGNAL_NONE;

      // RSI confirmation using cached value. A failed CopyBuffer leaves the cached RSI at 0.0, which is not
      // an overbought/oversold reading: tested as one, it admits every BUY and refuses every SELL. The slow
      // path already fails closed on it (IsRSIConfirmed returns false at <= 0.0), so both paths now refuse.
      if(cache.rsiValue <= 0.0)
      {
         gateReject = "rsi_unavailable";
         return TRADE_SIGNAL_NONE;
      }

      if(emaSignal == TRADE_SIGNAL_BUY && cache.rsiValue >= config.rsiOverbought)
      {
         gateReject = "rsi_overbought";
         return TRADE_SIGNAL_NONE;
      }
      if(emaSignal == TRADE_SIGNAL_SELL && cache.rsiValue <= config.rsiOversold)
      {
         gateReject = "rsi_oversold";
         return TRADE_SIGNAL_NONE;
      }

      return emaSignal;
   }

// Fallback: existing RefreshIndicators path (slow path / timer path)
   static ENUM_TRADE_SIGNAL EvaluateSlowPath(const string symbol,
                                             const SScalpConfig &config,
                                             CFastScalpIndicators &indicators,
                                             string &gateReject)
   {
      if(!indicators.RefreshIndicators(symbol, config))
      {
         gateReject = "indicator_refresh_failed";
         return TRADE_SIGNAL_NONE;
      }

      // Spread gate first — cheap rejection
      if(!CFastScalpFilters::IsSpreadAcceptable(symbol,
                                                indicators.GetATRCached(symbol, config),
                                                config.maxSpreadATRRatio))
      {
         gateReject = "spread_vs_atr";
         return TRADE_SIGNAL_NONE;
      }

      ENUM_TRADE_SIGNAL emaSignal2 = TRADE_SIGNAL_NONE;
      if(!CFastScalpIndicators::GetEMACrossover(symbol, config, emaSignal2))
      {
         gateReject = "ema_handles_failed";
         return TRADE_SIGNAL_NONE;
      }

      if(emaSignal2 == TRADE_SIGNAL_NONE)
         return TRADE_SIGNAL_NONE;

      if(!indicators.IsRSIConfirmed(emaSignal2, config))
      {
         gateReject = emaSignal2 == TRADE_SIGNAL_BUY ? "rsi_overbought" : "rsi_oversold";
         return TRADE_SIGNAL_NONE;
      }

      return emaSignal2;
   }
};

#endif // CORE_SCALP_FAST_SCALP_SIGNAL_MQH
