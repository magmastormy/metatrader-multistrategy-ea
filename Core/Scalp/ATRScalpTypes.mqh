// Shared plain-data types for the ATR scalping engine.
// Extracted verbatim from ATRScalpingEngine.mqh (structural only).
// Field order, defaults and comments are reproduced unchanged.
#property copyright "Copyright 2026, Aggressive Trading Systems"
#property link      "https://www.aggressivetrading.com"
#property version   "1.00"
#property strict

#ifndef CORE_SCALP_ATR_SCALP_TYPES_MQH
#define CORE_SCALP_ATR_SCALP_TYPES_MQH

#include "../Utils/MagicRange.mqh"

struct SATRScalpingConfig
{
   int      atrPeriod;                // ATR period (default 14)
   int      emaFastPeriod;            // Fast EMA period (default 5)
   int      emaSlowPeriod;            // Slow EMA period (default 13)
   int      rsiPeriod;                // RSI period (default 7)
   double   spreadMaxATRRatio;        // Max spread as fraction of ATR (default 0.50 — widened for synthetic indices)
   double   slAtrMultiplier;          // SL = ATR * this (default 1.5)
   double   tpAtrMultiplier;          // TP = ATR * this (default 2.0)
   int      magicOffset;              // Engine band offset (MAGIC_ENGINE_ATR_SCALP)
   int      maxPositions;             // Max concurrent scalp positions (default 3)
   int      cooldownMs;               // Cooldown between scalp trades in ms (default 30000)
   int      spikeWindowAvoidMinutes;  // Don't trade this many minutes before expected spike (default 5)
   double   rsiOverbought;            // RSI overbought level (default 70.0)
   double   rsiOversold;              // RSI oversold level (default 30.0)

   // Default constructor with production defaults
   SATRScalpingConfig()
   {
      atrPeriod               = 14;
      emaFastPeriod           = 5;
      emaSlowPeriod           = 13;
      rsiPeriod               = 7;
      spreadMaxATRRatio       = 0.30;
      slAtrMultiplier         = 1.5;
      tpAtrMultiplier         = 2.0;
      magicOffset             = MAGIC_ENGINE_ATR_SCALP;   // 7000 is ASSET_FOREX's consensus offset
      maxPositions            = 3;
      cooldownMs              = 30000;
      spikeWindowAvoidMinutes = 5;
      rsiOverbought           = 70.0;
      rsiOversold             = 30.0;
   }
};

struct SATRScalpSymbolState
{
   string   symbol;
   bool     isActive;
   datetime lastTradeTime;
   int      activePositions;
   double   currentATR;
   double   emaFastValue;
   double   emaSlowValue;
   double   rsiValue;
   int      lastEmaCrossDirection;     // 0=none, 1=bullish cross, -1=bearish cross
   datetime lastEmaCrossBarTime;       // Batch 152 (S-M-02): M1 bar the cross was detected on - entries require this to be the current bar
   datetime lastSpikeTime;             // From external spike detection
   int      expectedSpikeIntervalSec;  // e.g., 900 for DEX 900, 1200 for Jump
   bool     inSpikeWindow;             // True if within spikeWindowAvoidMinutes of expected spike
};

#endif // CORE_SCALP_ATR_SCALP_TYPES_MQH
