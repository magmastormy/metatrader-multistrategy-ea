// Entry gates for the ATR scalping engine: spike-window avoidance,
// RSI confirmation and the spread-vs-ATR noise filter.
// Extracted verbatim from ATRScalpingEngine.mqh (structural only).
#property copyright "Copyright 2026, Aggressive Trading Systems"
#property link      "https://www.aggressivetrading.com"
#property version   "1.00"
#property strict

#ifndef CORE_SCALP_ATR_SCALP_FILTER_MQH
#define CORE_SCALP_ATR_SCALP_FILTER_MQH

#include "ATRScalpTypes.mqh"

class CATRScalpFilter
{
public:
// Check if within spikeWindowAvoidMinutes of expected spike
   static bool IsInSpikeWindow(SATRScalpSymbolState &state, int spikeWindowAvoidMinutes)
   {
      int spikeInterval = state.expectedSpikeIntervalSec;
      datetime lastSpike = state.lastSpikeTime;

      // If no spike interval set, never in spike window
      if(spikeInterval <= 0)
         return false;

      // If we've never seen a spike, can't predict next one
      if(lastSpike <= 0)
         return false;

      datetime now = TimeCurrent();
      int timeSinceLastSpike = (int)(now - lastSpike);
      int timeToNextSpike = spikeInterval - timeSinceLastSpike;

      // In window if time to next spike < spikeWindowAvoidMinutes * 60
      int avoidWindowSec = spikeWindowAvoidMinutes * 60;
      bool inWindow = (timeToNextSpike > 0 && timeToNextSpike < avoidWindowSec);

      state.inSpikeWindow = inWindow;
      return inWindow;
   }

// crossDir: 1 = bullish cross (BUY), otherwise bearish cross (SELL)
   static bool PassesRsiConfirmation(const SATRScalpSymbolState &state, const SATRScalpingConfig &config, int crossDir)
   {
      double rsi = state.rsiValue;
      if(crossDir == 1)  // Bullish cross — BUY
      {
         if(rsi <= 0.0 || rsi >= config.rsiOverbought)
            return false;
      }
      else  // Bearish cross — SELL
      {
         // Fix #29b: RSI must be above oversold (not below) for SELL signal
         // Old condition `rsi <= m_config.rsiOversold` blocked SELL at the exact zone
         // where bearish cross mean-reversion signals are valid
         if(rsi <= 0.0 || rsi < config.rsiOversold || rsi >= config.rsiOverbought)
            return false;
         // Log when the fixed condition allows a signal that would have been blocked before
         if(rsi >= config.rsiOversold && rsi <= config.rsiOversold + 5.0)
            PrintFormat("[ATR-SCALP-RSI-FIX] %s | RSI=%.1f oversold=%.1f — SELL allowed by fixed condition",
                        state.symbol, rsi, config.rsiOversold);
      }
      return true;
   }

   static bool PassesSpreadGate(const string symbol, double atr, double spreadMaxATRRatio)
   {
      if(atr <= 0.0)
         return false;

      double spread = (double)SymbolInfoInteger(symbol, SYMBOL_SPREAD);
      double point  = SymbolInfoDouble(symbol, SYMBOL_POINT);
      if(point <= 0.0)
         return false;

      double spreadPrice = spread * point;
      if(spreadPrice > spreadMaxATRRatio * atr)
         return false;

      return true;
   }
};

#endif // CORE_SCALP_ATR_SCALP_FILTER_MQH
