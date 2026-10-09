// Shared types for the grid recovery engine
// Extracted verbatim from GridRecoveryEngine.mqh (structural only)
#property copyright "Copyright 2026, Aggressive Trading Systems"
#property link      "https://www.aggressivetrading.com"
#property version   "1.00"
#property strict

#ifndef CORE_SCALP_GRID_RECOVERY_TYPES_MQH
#define CORE_SCALP_GRID_RECOVERY_TYPES_MQH

// Grid progression type
enum ENUM_GRID_PROGRESSION
{
   GRID_PROGRESSION_MARTINGALE,    // Lot = baseLot * (factor ^ level)
   GRID_PROGRESSION_FIBONACCI      // Lot = baseLot * fib(level)
};

struct SGridRecoveryConfig
{
   double   gridFactorATR;           // Grid spacing as fraction of ATR (0.20)
   int      maxGridLevels;           // Max grid levels (8)
   ENUM_GRID_PROGRESSION progressionType;  // Martingale or Fibonacci
   double   progressionFactor;       // Lot multiplier per level (1.5 for Martingale)
   double   activationHurstThreshold;// Only activate when Hurst < this (0.45)
   int      atrPeriod;               // ATR period (14)
   double   slAtrMultiplier;         // SL = ATR * this per level (1.5)
   double   tpAtrMultiplier;         // TP = 0.5 * grid size per level
   int      magicOffset;             // Magic number offset (8000)
   int      maxDrawdownPercent;      // Max total grid drawdown % (15)
   int      cooldownMs;              // Cooldown between grid entries in ms (30000)
   double   maxCumulativeLotMultiplier; // Cap on total lots vs base lot (3.0)
   double   equityFloorPercent;      // Min equity % of initial before blocking new levels (50)
   bool     enableAIMode;            // L10-018: Enable AI-VOTE logging

   // Default constructor with production defaults
   SGridRecoveryConfig()
   {
      gridFactorATR            = 0.20;
      maxGridLevels            = 8;
      progressionType          = GRID_PROGRESSION_FIBONACCI;
      progressionFactor        = 1.5;
      activationHurstThreshold = 0.45;
      atrPeriod                = 14;
      slAtrMultiplier          = 1.5;
      tpAtrMultiplier          = 0.5;   // 0.5 * grid spacing
      magicOffset              = 8000;
      maxDrawdownPercent       = 15;
      cooldownMs               = 30000;
      maxCumulativeLotMultiplier = 3.0; // Cap total exposure at 3x base lot
      equityFloorPercent       = 50.0;  // Stop grid if equity drops below 50% of initial
      enableAIMode             = false; // L10-018: AI-VOTE logging disabled by default
   }
};

// Single grid level tracking
struct SGridLevel
{
   int      level;          // Grid level number (0-based)
   double   lotSize;        // Lot size for this level
   double   entryPrice;     // Entry price for this level
   double   sl;             // Stop loss price
   double   tp;             // Take profit price
   ulong    ticket;         // Position ticket (0 if not filled)
   bool     isActive;       // Whether this level is active/filled
};

// Per-symbol grid state tracking
struct SGridSymbolState
{
   string      symbol;
   bool        isActive;               // Is this symbol being monitored
   SGridLevel  levels[];               // Array of grid levels for this symbol
   int         activeLevelCount;       // Count of active levels
   double      totalGridRisk;          // Sum of risk across all levels
   double      baseLotSize;            // Base lot size for level 0
   int         direction;              // 1=BUY, -1=SELL
   datetime    lastGridEntryTime;      // When last grid entry was placed
   double      currentATR;             // Current ATR value
   double      atrSMA;                 // ATR EMA value (L10-017: incremental EMA)
   bool        hurstRegimeConfirmed;   // Hurst < threshold = mean-reversion confirmed
   double      initialEquity;          // Equity at grid activation (for floor check)
};

#endif // CORE_SCALP_GRID_RECOVERY_TYPES_MQH
