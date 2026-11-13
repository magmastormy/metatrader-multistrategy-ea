// Owns the three plain-data structs of the spike hunter.
// SpikeHunterEngine.mqh #includes this header, so every existing
// consumer of these types keeps seeing them unchanged.
// Field order, defaults and comments are reproduced verbatim.
#property strict

#ifndef CORE_SCALP_SPIKE_HUNTER_TYPES_MQH
#define CORE_SCALP_SPIKE_HUNTER_TYPES_MQH

#include "../Utils/MagicRange.mqh"

struct SSpikeHunterConfig
{
   double   velocityMultiplier;         // Tick rate multiplier threshold (default 2.5)
   int      minConsecutiveTicks;        // Min consecutive ticks in one direction (default 12)
   int      consecutiveTickWindowMs;    // Time window for consecutive ticks in ms (default 10000)
   double   atrCompressionRatio;       // ATR compression threshold (default 0.60)
   int      atrPeriod;                 // ATR period (default 14)
   int      atrSmaPeriod;              // SMA period for ATR baseline (default 50)
   double   slAtrMultiplier;           // SL = this * ATR (default 2.0)
   double   tpAtrMultiplier;           // TP = this * ATR (default 4.0)
   int      maxSpikePositions;         // Max concurrent spike positions (default 3)
   int      cooldownMs;                // Cooldown between spike trades in ms (default 120000)
   int      spikeCooldownForLongTermMs;// Cooldown for long-term entries after spike (default 120000)
   int      magicOffset;               // Engine band offset from base (MAGIC_ENGINE_SPIKE)
   bool     enablePushAlerts;          // Send push notifications (default true)
   int      alertThrottleSeconds;      // Min seconds between push alerts (default 120)
   int      minConfluence;             // Min detection layers to confirm (default 2)

   // Default constructor with production defaults (ISS-1002)
   SSpikeHunterConfig()
   {
      velocityMultiplier         = 2.5;        // Was 1.8 - higher for noise rejection
      minConsecutiveTicks        = 12;         // Was 6 - more ticks for reliable direction confirmation
      consecutiveTickWindowMs    = 10000;      // Was 60000 - 10s for spike responsiveness
      atrCompressionRatio       = 0.60;        // Was 0.80 - tighter compression detection
      atrPeriod                 = 14;
      atrSmaPeriod              = 50;
      slAtrMultiplier           = 2.0;         // Was 1.5 - wider SL on spikes
      tpAtrMultiplier           = 4.0;         // Was 3.0 - better R:R
      maxSpikePositions         = 3;
      cooldownMs                = 120000;      // Was 60000 - longer spike recovery
      spikeCooldownForLongTermMs = 120000;    // Was 60000
      magicOffset               = MAGIC_ENGINE_SPIKE;   // Engine band; 9150 sat inside the Deriv family range
      enablePushAlerts          = true;
      alertThrottleSeconds      = 120;
      minConfluence             = 2;           // Was 1 - require 2/3 layers for quality
   }
};

// Per-symbol spike state tracking
struct SSpikeSymbolState
{
   string   symbol;
   bool     isActive;                  // Is this symbol being monitored

   datetime tickWindowStart;
   int      tickWindowCount;
   double   tickRateBaseline;          // EMA baseline tick rate
   bool     velocityTriggered;         // Layer 1 triggered

   int      consecutiveUpTicks;        // Consecutive upward ticks
   int      consecutiveDownTicks;
   double   lastBid;                   // Last bid for direction comparison
   datetime directionWindowStart;      // Start of direction accumulation window
   bool     directionTriggered;        // Layer 2 triggered
   int      directionSign;             // +1 = up, -1 = down

   double   currentATR;
   double   atrSMA;
   bool     compressionTriggered;      // Layer 3 triggered

   int      confluenceCount;           // How many layers are triggered
   datetime lastSpikeTradeTime;        // When last spike trade was opened
   datetime lastSpikeDetectionTime;    // When spike was last detected (for long-term cooldown)
   bool     inSpikeCooldown;           // Whether this symbol is in cooldown for long-term entries
   datetime lastDiagTime;              // Last time near-miss diagnostic was logged
};

// Per-symbol family override parameters (Batch 102)
struct SSpikeHunterFamilyOverrides
{
   string   symbol;
   double   velocityMultiplier;
   int      minConsecutiveTicks;
   double   atrCompressionRatio;
   double   slAtrMultiplier;
   double   tpAtrMultiplier;
   int      magicOffset;
   int      cooldownMs;
   int      minConfluence;
   bool     hasOverrides;

   SSpikeHunterFamilyOverrides()
   {
      symbol                = "";
      velocityMultiplier    = 0.0;    // 0 = use default config
      minConsecutiveTicks   = 0;      // 0 = use default config
      atrCompressionRatio   = 0.0;    // 0 = use default config
      slAtrMultiplier       = 0.0;    // 0 = use default config
      tpAtrMultiplier       = 0.0;    // 0 = use default config
      magicOffset           = 0;      // 0 = use default config
      cooldownMs            = 0;      // 0 = use default config
      minConfluence         = 0;      // 0 = use default config
      hasOverrides          = false;
   }
};

#endif // CORE_SCALP_SPIKE_HUNTER_TYPES_MQH

