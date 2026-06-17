//+------------------------------------------------------------------+
//| DerivAssetProfiler.mqh                                           |
//| Deriv synthetic index asset profiler                              |
//| Maps symbols to family-specific trading profiles                  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Aggressive Trading Systems"
#property link      "https://www.aggressivetrading.com"
#property version   "1.00"
#property strict

#ifndef CORE_PROCESSING_DERIV_ASSET_PROFILER_MQH
#define CORE_PROCESSING_DERIV_ASSET_PROFILER_MQH

#include "../Utils/Instruments.mqh"

//+------------------------------------------------------------------+
//| Deriv synthetic index family enumeration                          |
//+------------------------------------------------------------------+
enum ENUM_DERIV_FAMILY
{
   DERIV_CRASH_BOOM,       // Crash/Boom indices
   DERIV_VOLATILITY,       // Volatility indices (SFX Vol, FX Vol)
   DERIV_STEP,             // Step indices
   DERIV_JUMP,             // Jump indices
   DERIV_DEX,              // DEX indices
   DERIV_MULTISTEP,        // Multi-Step indices
   DERIV_EXPONENTIAL,      // Exponential/Growth indices
   DERIV_HYBRID,           // Hybrid indices
   DERIV_RANGE_BREAK,      // Range Break indices
   DERIV_SKEW_STEP,        // Skew Step indices
   DERIV_VOL_SWITCH,       // Vol Switch indices
   DERIV_DRIFT_SWITCH,     // Drift Switch indices
   DERIV_TREK,             // Trek indices
   DERIV_TACTICAL,         // Tactical indices
   DERIV_DERIVED,          // Derived indices
   DERIV_STABLE_SPREAD,    // Stable Spread indices
   DERIV_PAIRS_ARBITRAGE,  // Pairs Arbitrage indices
   DERIV_SPOT_VOLATILITY,  // Spot Volatility indices
   DERIV_UNKNOWN           // Unknown / unclassified
};

//+------------------------------------------------------------------+
//| Per-family Deriv trading profile                                  |
//+------------------------------------------------------------------+
struct SDerivProfile
{
   ENUM_DERIV_FAMILY family;           // Family enum value
   string            familyName;       // Human-readable family name
   double            spikeThreshold;   // Tick velocity multiplier for spike detection
   double            atrCompressionRatio; // ATR compression ratio for spike detection (Layer 3)
   double            atrMultiplierSL;  // SL = ATR * this
   double            atrMultiplierTP;  // TP = ATR * this
   double            hurstThreshold;   // Hurst exponent threshold for regime detection
   double            riskPerTrade;     // Risk % per trade (0-100 scale)
   int               magicOffset;      // Magic number offset from base
   int               maxDrawdownPercent; // Max drawdown % for this family
   bool              enableSpikeHunter;  // Enable spike hunter engine
   bool              enableGridRecovery; // Enable grid recovery
   bool              enableHurstRegime;  // Enable Hurst regime detection
   bool              enableOUFilter;     // Enable Ornstein-Uhlenbeck filter
   double            gridFactorATR;    // Grid spacing as fraction of ATR
   int               maxGridLevels;    // Max grid recovery levels
   double            gridProgressionFactor; // Lot progression factor (1.5 = Modified Martingale)
   int               spikeCooldownSec; // Cooldown between spike trades in seconds
   int               spikeWindowBars;  // Lookback bars for spike detection

   // Default constructor — MQL5 requires explicit string initialization
   SDerivProfile()
   {
      family               = DERIV_UNKNOWN;
      familyName           = "";
      spikeThreshold       = 0.0;
      atrCompressionRatio  = 0.0;
      atrMultiplierSL      = 0.0;
      atrMultiplierTP      = 0.0;
      hurstThreshold       = 0.0;
      riskPerTrade         = 0.0;
      magicOffset          = 0;
      maxDrawdownPercent   = 0;
      enableSpikeHunter    = false;
      enableGridRecovery   = false;
      enableHurstRegime    = false;
      enableOUFilter       = false;
      gridFactorATR        = 0.0;
      maxGridLevels        = 0;
      gridProgressionFactor = 0.0;
      spikeCooldownSec     = 0;
      spikeWindowBars      = 0;
   }
};

//+------------------------------------------------------------------+
//| CDerivAssetProfiler — Deriv synthetic index asset profiler        |
//+------------------------------------------------------------------+
class CDerivAssetProfiler
{
private:
   SDerivProfile  m_profiles[19];  // 18 families + unknown

   //+------------------------------------------------------------------+
   //| Initialize all family profiles with production defaults          |
   //+------------------------------------------------------------------+
   void InitializeProfiles()
   {
      // DERIV_CRASH_BOOM (index 0)
      m_profiles[DERIV_CRASH_BOOM].family               = DERIV_CRASH_BOOM;
      m_profiles[DERIV_CRASH_BOOM].familyName           = "CrashBoom";
      m_profiles[DERIV_CRASH_BOOM].spikeThreshold       = 2.8;
      m_profiles[DERIV_CRASH_BOOM].atrCompressionRatio  = 0.80;
      m_profiles[DERIV_CRASH_BOOM].atrMultiplierSL      = 1.5;
      m_profiles[DERIV_CRASH_BOOM].atrMultiplierTP      = 3.0;
      m_profiles[DERIV_CRASH_BOOM].hurstThreshold       = 0.50;
      m_profiles[DERIV_CRASH_BOOM].riskPerTrade         = 1.5;
      m_profiles[DERIV_CRASH_BOOM].magicOffset          = 9000;
      m_profiles[DERIV_CRASH_BOOM].maxDrawdownPercent   = 15;
      m_profiles[DERIV_CRASH_BOOM].enableSpikeHunter    = true;
      m_profiles[DERIV_CRASH_BOOM].enableGridRecovery   = true;
      m_profiles[DERIV_CRASH_BOOM].enableHurstRegime    = true;
      m_profiles[DERIV_CRASH_BOOM].enableOUFilter       = false;
      m_profiles[DERIV_CRASH_BOOM].gridFactorATR        = 0.20;
      m_profiles[DERIV_CRASH_BOOM].maxGridLevels        = 6;
      m_profiles[DERIV_CRASH_BOOM].gridProgressionFactor = 1.5;
      m_profiles[DERIV_CRASH_BOOM].spikeCooldownSec     = 60;
      m_profiles[DERIV_CRASH_BOOM].spikeWindowBars      = 50;

      // DERIV_VOLATILITY (index 1)
      m_profiles[DERIV_VOLATILITY].family               = DERIV_VOLATILITY;
      m_profiles[DERIV_VOLATILITY].familyName           = "Volatility";
      m_profiles[DERIV_VOLATILITY].spikeThreshold       = 3.5;
      m_profiles[DERIV_VOLATILITY].atrCompressionRatio  = 0.75;
      m_profiles[DERIV_VOLATILITY].atrMultiplierSL      = 1.0;
      m_profiles[DERIV_VOLATILITY].atrMultiplierTP      = 1.5;
      m_profiles[DERIV_VOLATILITY].hurstThreshold       = 0.45;
      m_profiles[DERIV_VOLATILITY].riskPerTrade         = 1.0;
      m_profiles[DERIV_VOLATILITY].magicOffset          = 9100;
      m_profiles[DERIV_VOLATILITY].maxDrawdownPercent   = 10;
      m_profiles[DERIV_VOLATILITY].enableSpikeHunter    = false;
      m_profiles[DERIV_VOLATILITY].enableGridRecovery   = true;
      m_profiles[DERIV_VOLATILITY].enableHurstRegime    = true;
      m_profiles[DERIV_VOLATILITY].enableOUFilter       = true;
      m_profiles[DERIV_VOLATILITY].gridFactorATR        = 0.25;
      m_profiles[DERIV_VOLATILITY].maxGridLevels        = 8;
      m_profiles[DERIV_VOLATILITY].gridProgressionFactor = 1.5;
      m_profiles[DERIV_VOLATILITY].spikeCooldownSec     = 45;
      m_profiles[DERIV_VOLATILITY].spikeWindowBars      = 40;

      // DERIV_STEP (index 2)
      m_profiles[DERIV_STEP].family                     = DERIV_STEP;
      m_profiles[DERIV_STEP].familyName                 = "Step";
      m_profiles[DERIV_STEP].spikeThreshold             = 4.0;
      m_profiles[DERIV_STEP].atrCompressionRatio        = 0.70;
      m_profiles[DERIV_STEP].atrMultiplierSL            = 0.75;
      m_profiles[DERIV_STEP].atrMultiplierTP            = 1.25;
      m_profiles[DERIV_STEP].hurstThreshold             = 0.40;
      m_profiles[DERIV_STEP].riskPerTrade               = 0.75;
      m_profiles[DERIV_STEP].magicOffset                = 9200;
      m_profiles[DERIV_STEP].maxDrawdownPercent         = 8;
      m_profiles[DERIV_STEP].enableSpikeHunter          = false;
      m_profiles[DERIV_STEP].enableGridRecovery         = true;
      m_profiles[DERIV_STEP].enableHurstRegime          = true;
      m_profiles[DERIV_STEP].enableOUFilter             = true;
      m_profiles[DERIV_STEP].gridFactorATR              = 0.20;
      m_profiles[DERIV_STEP].maxGridLevels              = 10;
      m_profiles[DERIV_STEP].gridProgressionFactor      = 1.618;
      m_profiles[DERIV_STEP].spikeCooldownSec           = 30;
      m_profiles[DERIV_STEP].spikeWindowBars            = 35;

      // DERIV_JUMP (index 3)
      m_profiles[DERIV_JUMP].family                     = DERIV_JUMP;
      m_profiles[DERIV_JUMP].familyName                 = "Jump";
      m_profiles[DERIV_JUMP].spikeThreshold             = 2.5;
      m_profiles[DERIV_JUMP].atrCompressionRatio        = 0.85;
      m_profiles[DERIV_JUMP].atrMultiplierSL            = 2.0;
      m_profiles[DERIV_JUMP].atrMultiplierTP            = 2.5;
      m_profiles[DERIV_JUMP].hurstThreshold             = 0.55;
      m_profiles[DERIV_JUMP].riskPerTrade               = 1.25;
      m_profiles[DERIV_JUMP].magicOffset                = 9300;
      m_profiles[DERIV_JUMP].maxDrawdownPercent         = 12;
      m_profiles[DERIV_JUMP].enableSpikeHunter          = true;
      m_profiles[DERIV_JUMP].enableGridRecovery         = false;
      m_profiles[DERIV_JUMP].enableHurstRegime          = true;
      m_profiles[DERIV_JUMP].enableOUFilter             = false;
      m_profiles[DERIV_JUMP].gridFactorATR              = 0.0;
      m_profiles[DERIV_JUMP].maxGridLevels              = 0;
      m_profiles[DERIV_JUMP].gridProgressionFactor      = 0.0;
      m_profiles[DERIV_JUMP].spikeCooldownSec           = 60;
      m_profiles[DERIV_JUMP].spikeWindowBars            = 15;

      // DERIV_DEX (index 4)
      m_profiles[DERIV_DEX].family                      = DERIV_DEX;
      m_profiles[DERIV_DEX].familyName                  = "DEX";
      m_profiles[DERIV_DEX].spikeThreshold              = 2.2;
      m_profiles[DERIV_DEX].atrCompressionRatio         = 0.90;
      m_profiles[DERIV_DEX].atrMultiplierSL             = 2.5;
      m_profiles[DERIV_DEX].atrMultiplierTP             = 4.0;
      m_profiles[DERIV_DEX].hurstThreshold              = 0.60;
      m_profiles[DERIV_DEX].riskPerTrade                = 2.0;
      m_profiles[DERIV_DEX].magicOffset                 = 9400;
      m_profiles[DERIV_DEX].maxDrawdownPercent          = 18;
      m_profiles[DERIV_DEX].enableSpikeHunter           = true;
      m_profiles[DERIV_DEX].enableGridRecovery          = false;
      m_profiles[DERIV_DEX].enableHurstRegime           = true;
      m_profiles[DERIV_DEX].enableOUFilter              = false;
      m_profiles[DERIV_DEX].gridFactorATR               = 0.0;
      m_profiles[DERIV_DEX].maxGridLevels               = 0;
      m_profiles[DERIV_DEX].gridProgressionFactor       = 0.0;
      m_profiles[DERIV_DEX].spikeCooldownSec            = 90;
      m_profiles[DERIV_DEX].spikeWindowBars             = 20;

      // DERIV_MULTISTEP (index 5)
      m_profiles[DERIV_MULTISTEP].family                = DERIV_MULTISTEP;
      m_profiles[DERIV_MULTISTEP].familyName            = "MultiStep";
      m_profiles[DERIV_MULTISTEP].spikeThreshold        = 3.0;
      m_profiles[DERIV_MULTISTEP].atrCompressionRatio   = 0.72;
      m_profiles[DERIV_MULTISTEP].atrMultiplierSL       = 0.80;
      m_profiles[DERIV_MULTISTEP].atrMultiplierTP       = 1.30;
      m_profiles[DERIV_MULTISTEP].hurstThreshold        = 0.42;
      m_profiles[DERIV_MULTISTEP].riskPerTrade          = 0.80;
      m_profiles[DERIV_MULTISTEP].magicOffset           = 9500;
      m_profiles[DERIV_MULTISTEP].maxDrawdownPercent    = 9;
      m_profiles[DERIV_MULTISTEP].enableSpikeHunter     = false;
      m_profiles[DERIV_MULTISTEP].enableGridRecovery    = true;
      m_profiles[DERIV_MULTISTEP].enableHurstRegime     = true;
      m_profiles[DERIV_MULTISTEP].enableOUFilter        = true;
      m_profiles[DERIV_MULTISTEP].gridFactorATR         = 0.22;
      m_profiles[DERIV_MULTISTEP].maxGridLevels         = 10;
      m_profiles[DERIV_MULTISTEP].gridProgressionFactor = 1.618;
      m_profiles[DERIV_MULTISTEP].spikeCooldownSec      = 30;
      m_profiles[DERIV_MULTISTEP].spikeWindowBars       = 35;

      // DERIV_EXPONENTIAL (index 6)
      m_profiles[DERIV_EXPONENTIAL].family              = DERIV_EXPONENTIAL;
      m_profiles[DERIV_EXPONENTIAL].familyName          = "Exponential";
      m_profiles[DERIV_EXPONENTIAL].spikeThreshold      = 3.2;
      m_profiles[DERIV_EXPONENTIAL].atrCompressionRatio = 0.82;
      m_profiles[DERIV_EXPONENTIAL].atrMultiplierSL     = 1.8;
      m_profiles[DERIV_EXPONENTIAL].atrMultiplierTP     = 2.8;
      m_profiles[DERIV_EXPONENTIAL].hurstThreshold      = 0.58;
      m_profiles[DERIV_EXPONENTIAL].riskPerTrade        = 1.5;
      m_profiles[DERIV_EXPONENTIAL].magicOffset         = 9550;
      m_profiles[DERIV_EXPONENTIAL].maxDrawdownPercent  = 14;
      m_profiles[DERIV_EXPONENTIAL].enableSpikeHunter   = false;
      m_profiles[DERIV_EXPONENTIAL].enableGridRecovery  = false;
      m_profiles[DERIV_EXPONENTIAL].enableHurstRegime   = true;
      m_profiles[DERIV_EXPONENTIAL].enableOUFilter      = false;
      m_profiles[DERIV_EXPONENTIAL].gridFactorATR       = 0.0;
      m_profiles[DERIV_EXPONENTIAL].maxGridLevels       = 0;
      m_profiles[DERIV_EXPONENTIAL].gridProgressionFactor = 0.0;
      m_profiles[DERIV_EXPONENTIAL].spikeCooldownSec    = 45;
      m_profiles[DERIV_EXPONENTIAL].spikeWindowBars     = 40;

      // DERIV_HYBRID (index 7)
      m_profiles[DERIV_HYBRID].family                   = DERIV_HYBRID;
      m_profiles[DERIV_HYBRID].familyName               = "Hybrid";
      m_profiles[DERIV_HYBRID].spikeThreshold           = 2.8;
      m_profiles[DERIV_HYBRID].atrCompressionRatio      = 0.80;
      m_profiles[DERIV_HYBRID].atrMultiplierSL          = 1.5;
      m_profiles[DERIV_HYBRID].atrMultiplierTP          = 2.5;
      m_profiles[DERIV_HYBRID].hurstThreshold           = 0.50;
      m_profiles[DERIV_HYBRID].riskPerTrade             = 1.2;
      m_profiles[DERIV_HYBRID].magicOffset              = 9600;
      m_profiles[DERIV_HYBRID].maxDrawdownPercent       = 12;
      m_profiles[DERIV_HYBRID].enableSpikeHunter        = true;
      m_profiles[DERIV_HYBRID].enableGridRecovery       = true;
      m_profiles[DERIV_HYBRID].enableHurstRegime        = true;
      m_profiles[DERIV_HYBRID].enableOUFilter           = false;
      m_profiles[DERIV_HYBRID].gridFactorATR            = 0.25;
      m_profiles[DERIV_HYBRID].maxGridLevels            = 6;
      m_profiles[DERIV_HYBRID].gridProgressionFactor    = 1.5;
      m_profiles[DERIV_HYBRID].spikeCooldownSec         = 60;
      m_profiles[DERIV_HYBRID].spikeWindowBars          = 45;

      // DERIV_RANGE_BREAK (index 8)
      m_profiles[DERIV_RANGE_BREAK].family              = DERIV_RANGE_BREAK;
      m_profiles[DERIV_RANGE_BREAK].familyName          = "RangeBreak";
      m_profiles[DERIV_RANGE_BREAK].spikeThreshold      = 3.0;
      m_profiles[DERIV_RANGE_BREAK].atrCompressionRatio = 0.78;
      m_profiles[DERIV_RANGE_BREAK].atrMultiplierSL     = 1.2;
      m_profiles[DERIV_RANGE_BREAK].atrMultiplierTP     = 2.0;
      m_profiles[DERIV_RANGE_BREAK].hurstThreshold      = 0.48;
      m_profiles[DERIV_RANGE_BREAK].riskPerTrade        = 1.0;
      m_profiles[DERIV_RANGE_BREAK].magicOffset         = 9650;
      m_profiles[DERIV_RANGE_BREAK].maxDrawdownPercent  = 10;
      m_profiles[DERIV_RANGE_BREAK].enableSpikeHunter   = false;
      m_profiles[DERIV_RANGE_BREAK].enableGridRecovery  = false;
      m_profiles[DERIV_RANGE_BREAK].enableHurstRegime   = true;
      m_profiles[DERIV_RANGE_BREAK].enableOUFilter      = true;
      m_profiles[DERIV_RANGE_BREAK].gridFactorATR       = 0.0;
      m_profiles[DERIV_RANGE_BREAK].maxGridLevels       = 0;
      m_profiles[DERIV_RANGE_BREAK].gridProgressionFactor = 0.0;
      m_profiles[DERIV_RANGE_BREAK].spikeCooldownSec    = 45;
      m_profiles[DERIV_RANGE_BREAK].spikeWindowBars     = 40;

      // DERIV_SKEW_STEP (index 9)
      m_profiles[DERIV_SKEW_STEP].family                = DERIV_SKEW_STEP;
      m_profiles[DERIV_SKEW_STEP].familyName            = "SkewStep";
      m_profiles[DERIV_SKEW_STEP].spikeThreshold        = 3.5;
      m_profiles[DERIV_SKEW_STEP].atrCompressionRatio   = 0.73;
      m_profiles[DERIV_SKEW_STEP].atrMultiplierSL       = 0.85;
      m_profiles[DERIV_SKEW_STEP].atrMultiplierTP       = 1.40;
      m_profiles[DERIV_SKEW_STEP].hurstThreshold        = 0.43;
      m_profiles[DERIV_SKEW_STEP].riskPerTrade          = 0.85;
      m_profiles[DERIV_SKEW_STEP].magicOffset           = 9700;
      m_profiles[DERIV_SKEW_STEP].maxDrawdownPercent    = 9;
      m_profiles[DERIV_SKEW_STEP].enableSpikeHunter     = false;
      m_profiles[DERIV_SKEW_STEP].enableGridRecovery    = true;
      m_profiles[DERIV_SKEW_STEP].enableHurstRegime     = true;
      m_profiles[DERIV_SKEW_STEP].enableOUFilter        = true;
      m_profiles[DERIV_SKEW_STEP].gridFactorATR         = 0.20;
      m_profiles[DERIV_SKEW_STEP].maxGridLevels         = 10;
      m_profiles[DERIV_SKEW_STEP].gridProgressionFactor = 1.618;
      m_profiles[DERIV_SKEW_STEP].spikeCooldownSec      = 30;
      m_profiles[DERIV_SKEW_STEP].spikeWindowBars       = 35;

      // DERIV_VOL_SWITCH (index 10)
      m_profiles[DERIV_VOL_SWITCH].family               = DERIV_VOL_SWITCH;
      m_profiles[DERIV_VOL_SWITCH].familyName           = "VolSwitch";
      m_profiles[DERIV_VOL_SWITCH].spikeThreshold       = 3.0;
      m_profiles[DERIV_VOL_SWITCH].atrCompressionRatio  = 0.77;
      m_profiles[DERIV_VOL_SWITCH].atrMultiplierSL      = 1.3;
      m_profiles[DERIV_VOL_SWITCH].atrMultiplierTP      = 2.2;
      m_profiles[DERIV_VOL_SWITCH].hurstThreshold       = 0.47;
      m_profiles[DERIV_VOL_SWITCH].riskPerTrade         = 1.1;
      m_profiles[DERIV_VOL_SWITCH].magicOffset          = 9750;
      m_profiles[DERIV_VOL_SWITCH].maxDrawdownPercent   = 11;
      m_profiles[DERIV_VOL_SWITCH].enableSpikeHunter    = false;
      m_profiles[DERIV_VOL_SWITCH].enableGridRecovery   = false;
      m_profiles[DERIV_VOL_SWITCH].enableHurstRegime    = true;
      m_profiles[DERIV_VOL_SWITCH].enableOUFilter       = true;
      m_profiles[DERIV_VOL_SWITCH].gridFactorATR        = 0.0;
      m_profiles[DERIV_VOL_SWITCH].maxGridLevels        = 0;
      m_profiles[DERIV_VOL_SWITCH].gridProgressionFactor = 0.0;
      m_profiles[DERIV_VOL_SWITCH].spikeCooldownSec     = 45;
      m_profiles[DERIV_VOL_SWITCH].spikeWindowBars      = 40;

      // DERIV_DRIFT_SWITCH (index 11)
      m_profiles[DERIV_DRIFT_SWITCH].family             = DERIV_DRIFT_SWITCH;
      m_profiles[DERIV_DRIFT_SWITCH].familyName         = "DriftSwitch";
      m_profiles[DERIV_DRIFT_SWITCH].spikeThreshold     = 2.8;
      m_profiles[DERIV_DRIFT_SWITCH].atrCompressionRatio = 0.80;
      m_profiles[DERIV_DRIFT_SWITCH].atrMultiplierSL    = 1.5;
      m_profiles[DERIV_DRIFT_SWITCH].atrMultiplierTP    = 2.5;
      m_profiles[DERIV_DRIFT_SWITCH].hurstThreshold     = 0.52;
      m_profiles[DERIV_DRIFT_SWITCH].riskPerTrade       = 1.2;
      m_profiles[DERIV_DRIFT_SWITCH].magicOffset        = 9800;
      m_profiles[DERIV_DRIFT_SWITCH].maxDrawdownPercent = 12;
      m_profiles[DERIV_DRIFT_SWITCH].enableSpikeHunter  = false;
      m_profiles[DERIV_DRIFT_SWITCH].enableGridRecovery = false;
      m_profiles[DERIV_DRIFT_SWITCH].enableHurstRegime  = true;
      m_profiles[DERIV_DRIFT_SWITCH].enableOUFilter     = false;
      m_profiles[DERIV_DRIFT_SWITCH].gridFactorATR      = 0.0;
      m_profiles[DERIV_DRIFT_SWITCH].maxGridLevels      = 0;
      m_profiles[DERIV_DRIFT_SWITCH].gridProgressionFactor = 0.0;
      m_profiles[DERIV_DRIFT_SWITCH].spikeCooldownSec   = 45;
      m_profiles[DERIV_DRIFT_SWITCH].spikeWindowBars    = 40;

      // DERIV_TREK (index 12)
      m_profiles[DERIV_TREK].family                     = DERIV_TREK;
      m_profiles[DERIV_TREK].familyName                 = "Trek";
      m_profiles[DERIV_TREK].spikeThreshold             = 3.0;
      m_profiles[DERIV_TREK].atrCompressionRatio        = 0.79;
      m_profiles[DERIV_TREK].atrMultiplierSL            = 1.4;
      m_profiles[DERIV_TREK].atrMultiplierTP            = 2.3;
      m_profiles[DERIV_TREK].hurstThreshold             = 0.50;
      m_profiles[DERIV_TREK].riskPerTrade               = 1.1;
      m_profiles[DERIV_TREK].magicOffset                = 9850;
      m_profiles[DERIV_TREK].maxDrawdownPercent         = 11;
      m_profiles[DERIV_TREK].enableSpikeHunter          = false;
      m_profiles[DERIV_TREK].enableGridRecovery         = false;
      m_profiles[DERIV_TREK].enableHurstRegime          = true;
      m_profiles[DERIV_TREK].enableOUFilter             = false;
      m_profiles[DERIV_TREK].gridFactorATR              = 0.0;
      m_profiles[DERIV_TREK].maxGridLevels              = 0;
      m_profiles[DERIV_TREK].gridProgressionFactor      = 0.0;
      m_profiles[DERIV_TREK].spikeCooldownSec           = 45;
      m_profiles[DERIV_TREK].spikeWindowBars            = 40;

      // DERIV_TACTICAL (index 13)
      m_profiles[DERIV_TACTICAL].family                 = DERIV_TACTICAL;
      m_profiles[DERIV_TACTICAL].familyName             = "Tactical";
      m_profiles[DERIV_TACTICAL].spikeThreshold         = 3.0;
      m_profiles[DERIV_TACTICAL].atrCompressionRatio    = 0.79;
      m_profiles[DERIV_TACTICAL].atrMultiplierSL        = 1.4;
      m_profiles[DERIV_TACTICAL].atrMultiplierTP        = 2.3;
      m_profiles[DERIV_TACTICAL].hurstThreshold         = 0.50;
      m_profiles[DERIV_TACTICAL].riskPerTrade           = 1.1;
      m_profiles[DERIV_TACTICAL].magicOffset            = 9850;
      m_profiles[DERIV_TACTICAL].maxDrawdownPercent     = 11;
      m_profiles[DERIV_TACTICAL].enableSpikeHunter      = false;
      m_profiles[DERIV_TACTICAL].enableGridRecovery     = false;
      m_profiles[DERIV_TACTICAL].enableHurstRegime      = true;
      m_profiles[DERIV_TACTICAL].enableOUFilter         = false;
      m_profiles[DERIV_TACTICAL].gridFactorATR          = 0.0;
      m_profiles[DERIV_TACTICAL].maxGridLevels          = 0;
      m_profiles[DERIV_TACTICAL].gridProgressionFactor  = 0.0;
      m_profiles[DERIV_TACTICAL].spikeCooldownSec       = 45;
      m_profiles[DERIV_TACTICAL].spikeWindowBars        = 40;

      // DERIV_DERIVED (index 14)
      m_profiles[DERIV_DERIVED].family                  = DERIV_DERIVED;
      m_profiles[DERIV_DERIVED].familyName              = "Derived";
      m_profiles[DERIV_DERIVED].spikeThreshold          = 3.0;
      m_profiles[DERIV_DERIVED].atrCompressionRatio     = 0.79;
      m_profiles[DERIV_DERIVED].atrMultiplierSL         = 1.4;
      m_profiles[DERIV_DERIVED].atrMultiplierTP         = 2.3;
      m_profiles[DERIV_DERIVED].hurstThreshold          = 0.50;
      m_profiles[DERIV_DERIVED].riskPerTrade            = 1.1;
      m_profiles[DERIV_DERIVED].magicOffset             = 9850;
      m_profiles[DERIV_DERIVED].maxDrawdownPercent      = 11;
      m_profiles[DERIV_DERIVED].enableSpikeHunter       = false;
      m_profiles[DERIV_DERIVED].enableGridRecovery      = false;
      m_profiles[DERIV_DERIVED].enableHurstRegime       = true;
      m_profiles[DERIV_DERIVED].enableOUFilter          = false;
      m_profiles[DERIV_DERIVED].gridFactorATR           = 0.0;
      m_profiles[DERIV_DERIVED].maxGridLevels           = 0;
      m_profiles[DERIV_DERIVED].gridProgressionFactor   = 0.0;
      m_profiles[DERIV_DERIVED].spikeCooldownSec        = 45;
      m_profiles[DERIV_DERIVED].spikeWindowBars         = 40;

      // DERIV_STABLE_SPREAD (index 15)
      m_profiles[DERIV_STABLE_SPREAD].family            = DERIV_STABLE_SPREAD;
      m_profiles[DERIV_STABLE_SPREAD].familyName        = "StableSpread";
      m_profiles[DERIV_STABLE_SPREAD].spikeThreshold    = 4.0;
      m_profiles[DERIV_STABLE_SPREAD].atrCompressionRatio = 0.65;
      m_profiles[DERIV_STABLE_SPREAD].atrMultiplierSL   = 0.60;
      m_profiles[DERIV_STABLE_SPREAD].atrMultiplierTP   = 1.00;
      m_profiles[DERIV_STABLE_SPREAD].hurstThreshold    = 0.38;
      m_profiles[DERIV_STABLE_SPREAD].riskPerTrade      = 0.50;
      m_profiles[DERIV_STABLE_SPREAD].magicOffset       = 9900;
      m_profiles[DERIV_STABLE_SPREAD].maxDrawdownPercent = 6;
      m_profiles[DERIV_STABLE_SPREAD].enableSpikeHunter = false;
      m_profiles[DERIV_STABLE_SPREAD].enableGridRecovery = true;
      m_profiles[DERIV_STABLE_SPREAD].enableHurstRegime = true;
      m_profiles[DERIV_STABLE_SPREAD].enableOUFilter    = true;
      m_profiles[DERIV_STABLE_SPREAD].gridFactorATR     = 0.15;
      m_profiles[DERIV_STABLE_SPREAD].maxGridLevels     = 12;
      m_profiles[DERIV_STABLE_SPREAD].gridProgressionFactor = 1.618;
      m_profiles[DERIV_STABLE_SPREAD].spikeCooldownSec  = 20;
      m_profiles[DERIV_STABLE_SPREAD].spikeWindowBars   = 30;

      // DERIV_PAIRS_ARBITRAGE (index 16)
      m_profiles[DERIV_PAIRS_ARBITRAGE].family          = DERIV_PAIRS_ARBITRAGE;
      m_profiles[DERIV_PAIRS_ARBITRAGE].familyName      = "PairsArbitrage";
      m_profiles[DERIV_PAIRS_ARBITRAGE].spikeThreshold  = 4.5;
      m_profiles[DERIV_PAIRS_ARBITRAGE].atrCompressionRatio = 0.60;
      m_profiles[DERIV_PAIRS_ARBITRAGE].atrMultiplierSL = 0.50;
      m_profiles[DERIV_PAIRS_ARBITRAGE].atrMultiplierTP = 0.80;
      m_profiles[DERIV_PAIRS_ARBITRAGE].hurstThreshold  = 0.35;
      m_profiles[DERIV_PAIRS_ARBITRAGE].riskPerTrade    = 0.40;
      m_profiles[DERIV_PAIRS_ARBITRAGE].magicOffset     = 9900;
      m_profiles[DERIV_PAIRS_ARBITRAGE].maxDrawdownPercent = 5;
      m_profiles[DERIV_PAIRS_ARBITRAGE].enableSpikeHunter = false;
      m_profiles[DERIV_PAIRS_ARBITRAGE].enableGridRecovery = true;
      m_profiles[DERIV_PAIRS_ARBITRAGE].enableHurstRegime = true;
      m_profiles[DERIV_PAIRS_ARBITRAGE].enableOUFilter  = true;
      m_profiles[DERIV_PAIRS_ARBITRAGE].gridFactorATR   = 0.15;
      m_profiles[DERIV_PAIRS_ARBITRAGE].maxGridLevels   = 12;
      m_profiles[DERIV_PAIRS_ARBITRAGE].gridProgressionFactor = 1.618;
      m_profiles[DERIV_PAIRS_ARBITRAGE].spikeCooldownSec = 20;
      m_profiles[DERIV_PAIRS_ARBITRAGE].spikeWindowBars = 30;

      // DERIV_SPOT_VOLATILITY (index 17)
      m_profiles[DERIV_SPOT_VOLATILITY].family          = DERIV_SPOT_VOLATILITY;
      m_profiles[DERIV_SPOT_VOLATILITY].familyName      = "SpotVolatility";
      m_profiles[DERIV_SPOT_VOLATILITY].spikeThreshold  = 3.5;
      m_profiles[DERIV_SPOT_VOLATILITY].atrCompressionRatio = 0.75;
      m_profiles[DERIV_SPOT_VOLATILITY].atrMultiplierSL = 1.0;
      m_profiles[DERIV_SPOT_VOLATILITY].atrMultiplierTP = 1.5;
      m_profiles[DERIV_SPOT_VOLATILITY].hurstThreshold  = 0.45;
      m_profiles[DERIV_SPOT_VOLATILITY].riskPerTrade    = 1.0;
      m_profiles[DERIV_SPOT_VOLATILITY].magicOffset     = 9100;
      m_profiles[DERIV_SPOT_VOLATILITY].maxDrawdownPercent = 10;
      m_profiles[DERIV_SPOT_VOLATILITY].enableSpikeHunter = false;
      m_profiles[DERIV_SPOT_VOLATILITY].enableGridRecovery = true;
      m_profiles[DERIV_SPOT_VOLATILITY].enableHurstRegime = true;
      m_profiles[DERIV_SPOT_VOLATILITY].enableOUFilter  = true;
      m_profiles[DERIV_SPOT_VOLATILITY].gridFactorATR   = 0.25;
      m_profiles[DERIV_SPOT_VOLATILITY].maxGridLevels   = 8;
      m_profiles[DERIV_SPOT_VOLATILITY].gridProgressionFactor = 1.5;
      m_profiles[DERIV_SPOT_VOLATILITY].spikeCooldownSec = 45;
      m_profiles[DERIV_SPOT_VOLATILITY].spikeWindowBars = 40;

      // DERIV_UNKNOWN (index 18)
      m_profiles[DERIV_UNKNOWN].family                  = DERIV_UNKNOWN;
      m_profiles[DERIV_UNKNOWN].familyName              = "Unknown";
      m_profiles[DERIV_UNKNOWN].spikeThreshold          = 3.0;
      m_profiles[DERIV_UNKNOWN].atrCompressionRatio     = 0.80;
      m_profiles[DERIV_UNKNOWN].atrMultiplierSL         = 1.5;
      m_profiles[DERIV_UNKNOWN].atrMultiplierTP         = 2.5;
      m_profiles[DERIV_UNKNOWN].hurstThreshold          = 0.50;
      m_profiles[DERIV_UNKNOWN].riskPerTrade            = 1.0;
      m_profiles[DERIV_UNKNOWN].magicOffset             = 9999;
      m_profiles[DERIV_UNKNOWN].maxDrawdownPercent      = 10;
      m_profiles[DERIV_UNKNOWN].enableSpikeHunter       = false;
      m_profiles[DERIV_UNKNOWN].enableGridRecovery      = false;
      m_profiles[DERIV_UNKNOWN].enableHurstRegime       = false;
      m_profiles[DERIV_UNKNOWN].enableOUFilter          = false;
      m_profiles[DERIV_UNKNOWN].gridFactorATR           = 0.0;
      m_profiles[DERIV_UNKNOWN].maxGridLevels           = 0;
      m_profiles[DERIV_UNKNOWN].gridProgressionFactor   = 0.0;
      m_profiles[DERIV_UNKNOWN].spikeCooldownSec        = 60;
      m_profiles[DERIV_UNKNOWN].spikeWindowBars         = 40;
   }

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CDerivAssetProfiler()
   {
      InitializeProfiles();
   }

   //+------------------------------------------------------------------+
   //| Detect the Deriv family for a symbol using priority-ordered      |
   //| detection functions from Instruments.mqh                         |
   //+------------------------------------------------------------------+
   ENUM_DERIV_FAMILY DetectFamily(const string symbol)
   {
      // Priority 1: Crash/Boom — most specific spike family
      if(IsBoomCrashSyntheticSymbolName(symbol))
         return DERIV_CRASH_BOOM;

      // Priority 2: DEX
      if(IsDexSyntheticSymbolName(symbol))
         return DERIV_DEX;

      // Priority 3: Jump
      if(IsJumpSyntheticSymbolName(symbol))
         return DERIV_JUMP;

      // Priority 4: Vol Switch — must check BEFORE Volatility
      //    (VolSwitch symbols contain "VOL" so IsVolatilitySyntheticSymbolName
      //     would also match — we want VolSwitch to win)
      if(IsVolSwitchSyntheticSymbolName(symbol))
         return DERIV_VOL_SWITCH;

      // Priority 5: Drift Switch
      if(IsDriftSwitchSyntheticSymbolName(symbol))
         return DERIV_DRIFT_SWITCH;

      // Priority 6: Skew Step
      if(IsSkewStepSyntheticSymbolName(symbol))
         return DERIV_SKEW_STEP;

      // Priority 7: Multi Step
      if(IsMultiStepSyntheticSymbolName(symbol))
         return DERIV_MULTISTEP;

      // Priority 8: Step — only if not already matched as SkewStep/MultiStep
      if(IsStepSyntheticSymbolName(symbol))
         return DERIV_STEP;

      // Priority 9: Volatility — safe now because VolSwitch already matched above
      if(IsVolatilitySyntheticSymbolName(symbol))
         return DERIV_VOLATILITY;

      // Priority 10: Exponential
      if(IsExponentialSyntheticSymbolName(symbol))
         return DERIV_EXPONENTIAL;

      // Priority 11: Hybrid
      if(IsHybridSyntheticSymbolName(symbol))
         return DERIV_HYBRID;

      // Priority 12: Range Break
      if(IsRangeBreakSyntheticSymbolName(symbol))
         return DERIV_RANGE_BREAK;

      // Priority 13: Trek
      if(IsTrekSyntheticSymbolName(symbol))
         return DERIV_TREK;

      // Priority 14: Tactical
      if(IsTacticalSyntheticSymbolName(symbol))
         return DERIV_TACTICAL;

      // Priority 15: Derived
      if(IsDerivedSyntheticSymbolName(symbol))
         return DERIV_DERIVED;

      // Priority 16: Stable Spread
      if(IsStableSpreadSyntheticSymbolName(symbol))
         return DERIV_STABLE_SPREAD;

      // Priority 17: Pairs Arbitrage
      if(IsPairsArbitrageSyntheticSymbolName(symbol))
         return DERIV_PAIRS_ARBITRAGE;

      // Priority 18: Spot Volatility
      if(IsSpotVolatilitySyntheticSymbolName(symbol))
         return DERIV_SPOT_VOLATILITY;

      // No match found
      return DERIV_UNKNOWN;
   }

   //+------------------------------------------------------------------+
   //| Get the full profile for a symbol                                 |
   //+------------------------------------------------------------------+
   SDerivProfile GetProfile(const string symbol)
   {
      ENUM_DERIV_FAMILY family = DetectFamily(symbol);
      return m_profiles[family];
   }

   //+------------------------------------------------------------------+
   //| Get the magic offset for a symbol's family                        |
   //+------------------------------------------------------------------+
   int GetMagicOffset(const string symbol)
   {
      ENUM_DERIV_FAMILY family = DetectFamily(symbol);
      return m_profiles[family].magicOffset;
   }

   //+------------------------------------------------------------------+
   //| Get the family name string for a symbol                           |
   //+------------------------------------------------------------------+
   string GetFamilyName(const string symbol)
   {
      ENUM_DERIV_FAMILY family = DetectFamily(symbol);
      return m_profiles[family].familyName;
   }

   //+------------------------------------------------------------------+
   //| Print the full profile for a symbol                               |
   //+------------------------------------------------------------------+
   void PrintProfile(const string symbol)
   {
      SDerivProfile prof = GetProfile(symbol);

      PrintFormat("[DERIV-PROFILER] Symbol=%s | Family=%s | spikeThresh=%.1f | atrSL=%.2f | atrTP=%.2f | hurst=%.2f | risk=%.2f%% | magicOff=%d | maxDD=%d%% | spikeHunt=%s | gridRec=%s | hurstReg=%s | ouFilter=%s | gridATR=%.2f | gridLvl=%d | gridProg=%.3f | cooldown=%ds | window=%dbars",
                  symbol,
                  prof.familyName,
                  prof.spikeThreshold,
                  prof.atrMultiplierSL,
                  prof.atrMultiplierTP,
                  prof.hurstThreshold,
                  prof.riskPerTrade,
                  prof.magicOffset,
                  prof.maxDrawdownPercent,
                  prof.enableSpikeHunter  ? "Y" : "N",
                  prof.enableGridRecovery ? "Y" : "N",
                  prof.enableHurstRegime  ? "Y" : "N",
                  prof.enableOUFilter     ? "Y" : "N",
                  prof.gridFactorATR,
                  prof.maxGridLevels,
                  prof.gridProgressionFactor,
                  prof.spikeCooldownSec,
                  prof.spikeWindowBars);
   }
};

#endif // CORE_PROCESSING_DERIV_ASSET_PROFILER_MQH
