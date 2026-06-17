//+------------------------------------------------------------------+
//| MultiAssetProfiler.mqh                                           |
//| Multi-asset class profiler extending Deriv-only profiling        |
//| Covers Forex, Metals, Indices, Energies + all Deriv families    |
//| Batch 103: Full asset universe support                           |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Aggressive Trading Systems"
#property link      "https://www.aggressivetrading.com"
#property version   "1.00"
#property strict

#ifndef CORE_PROCESSING_MULTI_ASSET_PROFILER_MQH
#define CORE_PROCESSING_MULTI_ASSET_PROFILER_MQH

#include "../Utils/Instruments.mqh"
#include "DerivAssetProfiler.mqh"

//+------------------------------------------------------------------+
//| Asset class enumeration — coarse grouping for all instruments    |
//+------------------------------------------------------------------+
enum ENUM_ASSET_CLASS
{
   ASSET_FOREX,            // 0 - EURUSD, GBPUSD, etc.
   ASSET_METALS,           // 1 - XAUUSD, XAGUSD
   ASSET_INDICES,          // 2 - US30, US100, GER40, UK100
   ASSET_ENERGIES,         // 3 - WTI, BRENT, NG
   ASSET_DERIV_CRASHBOOM,  // 4 - Crash/Boom
   ASSET_DERIV_VOLATILITY, // 5 - VIX 10-300
   ASSET_DERIV_STEP,       // 6 - Step 10-200
   ASSET_DERIV_JUMP,       // 7 - Jump 10-100
   ASSET_DERIV_DEX,        // 8 - DEX 900-10000
   ASSET_UNIVERSAL         // 9 - Fallback
};

//+------------------------------------------------------------------+
//| Per-asset-class trading profile                                  |
//+------------------------------------------------------------------+
struct SAssetProfile
{
   ENUM_ASSET_CLASS  assetClass;          // Asset class enum value
   string            className;           // Human-readable class name
   double            atrMultiplierSL;     // SL = ATR * this
   double            atrMultiplierTP;     // TP = ATR * this
   double            hurstThreshold;      // Hurst exponent threshold
   double            riskPerTrade;        // Risk % per trade (0-100 scale)
   int               magicOffset;         // Magic number offset from base
   int               maxDrawdownPercent;  // Max drawdown % for this class
   bool              enableScalpEngine;   // Enable ATR scalping engine
   bool              enableGridRecovery;  // Enable grid recovery engine
   bool              enableSpikeHunter;   // Enable spike hunter engine
   bool              enableBreakoutEngine;// Enable volatility breakout
   bool              enableOUMeanReversion; // Enable OU mean-reversion filter
   int               featureSetSize;      // 57 = universal, 70 = deriv
   string            pythonModelFamily;   // Python model directory name

   // Default constructor — MQL5 requires explicit string initialization
   SAssetProfile()
   {
      assetClass          = ASSET_UNIVERSAL;
      className           = "";
      atrMultiplierSL     = 0.0;
      atrMultiplierTP     = 0.0;
      hurstThreshold      = 0.0;
      riskPerTrade        = 0.0;
      magicOffset         = 0;
      maxDrawdownPercent  = 0;
      enableScalpEngine   = false;
      enableGridRecovery  = false;
      enableSpikeHunter   = false;
      enableBreakoutEngine= false;
      enableOUMeanReversion = false;
      featureSetSize      = 57;
      pythonModelFamily   = "";
   }
};

//+------------------------------------------------------------------+
//| CMultiAssetProfiler — Multi-asset class profiler                 |
//| Wraps CDerivAssetProfiler for Deriv symbols (composition)        |
//| Adds Forex, Metals, Indices, Energies profiling                  |
//+------------------------------------------------------------------+
class CMultiAssetProfiler
{
private:
   SAssetProfile        m_profiles[10];   // 10 asset classes
   CDerivAssetProfiler  m_derivProfiler;  // Internal Deriv profiler (composition)
   ENUM_ASSET_CLASS     m_detectedClass;
   string               m_detectedSymbol;

   //+------------------------------------------------------------------+
   //| Initialize all asset class profiles with production defaults    |
   //+------------------------------------------------------------------+
   void InitializeAllProfiles()
   {
      // === ASSET 0: FOREX ===
      m_profiles[ASSET_FOREX].assetClass           = ASSET_FOREX;
      m_profiles[ASSET_FOREX].className            = "Forex";
      m_profiles[ASSET_FOREX].atrMultiplierSL      = 1.0;
      m_profiles[ASSET_FOREX].atrMultiplierTP      = 1.5;
      m_profiles[ASSET_FOREX].hurstThreshold       = 0.45;
      m_profiles[ASSET_FOREX].riskPerTrade         = 1.0;
      m_profiles[ASSET_FOREX].magicOffset          = 7000;
      m_profiles[ASSET_FOREX].maxDrawdownPercent   = 10;
      m_profiles[ASSET_FOREX].enableScalpEngine    = true;
      m_profiles[ASSET_FOREX].enableGridRecovery   = true;
      m_profiles[ASSET_FOREX].enableSpikeHunter    = false;
      m_profiles[ASSET_FOREX].enableBreakoutEngine = true;
      m_profiles[ASSET_FOREX].enableOUMeanReversion= false;
      m_profiles[ASSET_FOREX].featureSetSize       = 60;  // 57 + 3 forex-specific
      m_profiles[ASSET_FOREX].pythonModelFamily    = "forex";

      // === ASSET 1: METALS (GOLD/SILVER) ===
      m_profiles[ASSET_METALS].assetClass          = ASSET_METALS;
      m_profiles[ASSET_METALS].className           = "Metals";
      m_profiles[ASSET_METALS].atrMultiplierSL     = 1.0;
      m_profiles[ASSET_METALS].atrMultiplierTP     = 2.0;
      m_profiles[ASSET_METALS].hurstThreshold      = 0.55;
      m_profiles[ASSET_METALS].riskPerTrade        = 0.75;
      m_profiles[ASSET_METALS].magicOffset         = 7100;
      m_profiles[ASSET_METALS].maxDrawdownPercent  = 12;
      m_profiles[ASSET_METALS].enableScalpEngine   = false;
      m_profiles[ASSET_METALS].enableGridRecovery  = false;
      m_profiles[ASSET_METALS].enableSpikeHunter   = false;
      m_profiles[ASSET_METALS].enableBreakoutEngine= true;
      m_profiles[ASSET_METALS].enableOUMeanReversion= false;
      m_profiles[ASSET_METALS].featureSetSize      = 61;  // 57 + 4 metals-specific
      m_profiles[ASSET_METALS].pythonModelFamily   = "metals";

      // === ASSET 2: INDICES (US30, US100, etc.) ===
      m_profiles[ASSET_INDICES].assetClass         = ASSET_INDICES;
      m_profiles[ASSET_INDICES].className          = "Indices";
      m_profiles[ASSET_INDICES].atrMultiplierSL    = 0.75;
      m_profiles[ASSET_INDICES].atrMultiplierTP    = 1.25;
      m_profiles[ASSET_INDICES].hurstThreshold     = 0.42;
      m_profiles[ASSET_INDICES].riskPerTrade       = 0.80;
      m_profiles[ASSET_INDICES].magicOffset        = 7200;
      m_profiles[ASSET_INDICES].maxDrawdownPercent = 10;
      m_profiles[ASSET_INDICES].enableScalpEngine  = false;
      m_profiles[ASSET_INDICES].enableGridRecovery = true;
      m_profiles[ASSET_INDICES].enableSpikeHunter  = false;
      m_profiles[ASSET_INDICES].enableBreakoutEngine= false;
      m_profiles[ASSET_INDICES].enableOUMeanReversion= true;
      m_profiles[ASSET_INDICES].featureSetSize     = 61;  // 57 + 4 indices-specific
      m_profiles[ASSET_INDICES].pythonModelFamily  = "indices";

      // === ASSET 3: ENERGIES ===
      m_profiles[ASSET_ENERGIES].assetClass        = ASSET_ENERGIES;
      m_profiles[ASSET_ENERGIES].className         = "Energies";
      m_profiles[ASSET_ENERGIES].atrMultiplierSL   = 1.25;
      m_profiles[ASSET_ENERGIES].atrMultiplierTP   = 1.75;
      m_profiles[ASSET_ENERGIES].hurstThreshold    = 0.50;
      m_profiles[ASSET_ENERGIES].riskPerTrade      = 0.90;
      m_profiles[ASSET_ENERGIES].magicOffset       = 7300;
      m_profiles[ASSET_ENERGIES].maxDrawdownPercent= 15;
      m_profiles[ASSET_ENERGIES].enableScalpEngine = false;
      m_profiles[ASSET_ENERGIES].enableGridRecovery= false;
      m_profiles[ASSET_ENERGIES].enableSpikeHunter = true;
      m_profiles[ASSET_ENERGIES].enableBreakoutEngine= true;
      m_profiles[ASSET_ENERGIES].enableOUMeanReversion= false;
      m_profiles[ASSET_ENERGIES].featureSetSize    = 60;  // 57 + 3 energies-specific
      m_profiles[ASSET_ENERGIES].pythonModelFamily = "energies";

      // === ASSET 4: DERIV CRASH/BOOM ===
      m_profiles[ASSET_DERIV_CRASHBOOM].assetClass          = ASSET_DERIV_CRASHBOOM;
      m_profiles[ASSET_DERIV_CRASHBOOM].className           = "DerivCrashBoom";
      m_profiles[ASSET_DERIV_CRASHBOOM].atrMultiplierSL     = 1.5;
      m_profiles[ASSET_DERIV_CRASHBOOM].atrMultiplierTP     = 3.0;
      m_profiles[ASSET_DERIV_CRASHBOOM].hurstThreshold      = 0.50;
      m_profiles[ASSET_DERIV_CRASHBOOM].riskPerTrade        = 1.5;
      m_profiles[ASSET_DERIV_CRASHBOOM].magicOffset         = 9000;
      m_profiles[ASSET_DERIV_CRASHBOOM].maxDrawdownPercent  = 15;
      m_profiles[ASSET_DERIV_CRASHBOOM].enableScalpEngine   = false;
      m_profiles[ASSET_DERIV_CRASHBOOM].enableGridRecovery  = true;
      m_profiles[ASSET_DERIV_CRASHBOOM].enableSpikeHunter   = true;
      m_profiles[ASSET_DERIV_CRASHBOOM].enableBreakoutEngine= false;
      m_profiles[ASSET_DERIV_CRASHBOOM].enableOUMeanReversion= false;
      m_profiles[ASSET_DERIV_CRASHBOOM].featureSetSize      = 70;
      m_profiles[ASSET_DERIV_CRASHBOOM].pythonModelFamily   = "deriv_crashboom";

      // === ASSET 5: DERIV VOLATILITY ===
      m_profiles[ASSET_DERIV_VOLATILITY].assetClass         = ASSET_DERIV_VOLATILITY;
      m_profiles[ASSET_DERIV_VOLATILITY].className          = "DerivVolatility";
      m_profiles[ASSET_DERIV_VOLATILITY].atrMultiplierSL    = 1.0;
      m_profiles[ASSET_DERIV_VOLATILITY].atrMultiplierTP    = 1.5;
      m_profiles[ASSET_DERIV_VOLATILITY].hurstThreshold     = 0.45;
      m_profiles[ASSET_DERIV_VOLATILITY].riskPerTrade       = 1.0;
      m_profiles[ASSET_DERIV_VOLATILITY].magicOffset        = 9100;
      m_profiles[ASSET_DERIV_VOLATILITY].maxDrawdownPercent = 10;
      m_profiles[ASSET_DERIV_VOLATILITY].enableScalpEngine  = false;
      m_profiles[ASSET_DERIV_VOLATILITY].enableGridRecovery = true;
      m_profiles[ASSET_DERIV_VOLATILITY].enableSpikeHunter  = false;
      m_profiles[ASSET_DERIV_VOLATILITY].enableBreakoutEngine= false;
      m_profiles[ASSET_DERIV_VOLATILITY].enableOUMeanReversion= true;
      m_profiles[ASSET_DERIV_VOLATILITY].featureSetSize     = 70;
      m_profiles[ASSET_DERIV_VOLATILITY].pythonModelFamily  = "deriv_volatility";

      // === ASSET 6: DERIV STEP ===
      m_profiles[ASSET_DERIV_STEP].assetClass               = ASSET_DERIV_STEP;
      m_profiles[ASSET_DERIV_STEP].className                = "DerivStep";
      m_profiles[ASSET_DERIV_STEP].atrMultiplierSL          = 0.75;
      m_profiles[ASSET_DERIV_STEP].atrMultiplierTP          = 1.25;
      m_profiles[ASSET_DERIV_STEP].hurstThreshold           = 0.40;
      m_profiles[ASSET_DERIV_STEP].riskPerTrade             = 0.75;
      m_profiles[ASSET_DERIV_STEP].magicOffset              = 9200;
      m_profiles[ASSET_DERIV_STEP].maxDrawdownPercent       = 8;
      m_profiles[ASSET_DERIV_STEP].enableScalpEngine        = false;
      m_profiles[ASSET_DERIV_STEP].enableGridRecovery       = true;
      m_profiles[ASSET_DERIV_STEP].enableSpikeHunter        = false;
      m_profiles[ASSET_DERIV_STEP].enableBreakoutEngine     = false;
      m_profiles[ASSET_DERIV_STEP].enableOUMeanReversion    = true;
      m_profiles[ASSET_DERIV_STEP].featureSetSize           = 70;
      m_profiles[ASSET_DERIV_STEP].pythonModelFamily        = "deriv_step";

      // === ASSET 7: DERIV JUMP ===
      m_profiles[ASSET_DERIV_JUMP].assetClass               = ASSET_DERIV_JUMP;
      m_profiles[ASSET_DERIV_JUMP].className                = "DerivJump";
      m_profiles[ASSET_DERIV_JUMP].atrMultiplierSL          = 2.0;
      m_profiles[ASSET_DERIV_JUMP].atrMultiplierTP          = 2.5;
      m_profiles[ASSET_DERIV_JUMP].hurstThreshold           = 0.55;
      m_profiles[ASSET_DERIV_JUMP].riskPerTrade             = 1.25;
      m_profiles[ASSET_DERIV_JUMP].magicOffset              = 9300;
      m_profiles[ASSET_DERIV_JUMP].maxDrawdownPercent       = 12;
      m_profiles[ASSET_DERIV_JUMP].enableScalpEngine        = true;
      m_profiles[ASSET_DERIV_JUMP].enableGridRecovery       = false;
      m_profiles[ASSET_DERIV_JUMP].enableSpikeHunter        = true;
      m_profiles[ASSET_DERIV_JUMP].enableBreakoutEngine     = false;
      m_profiles[ASSET_DERIV_JUMP].enableOUMeanReversion    = false;
      m_profiles[ASSET_DERIV_JUMP].featureSetSize           = 70;
      m_profiles[ASSET_DERIV_JUMP].pythonModelFamily        = "deriv_jump";

      // === ASSET 8: DERIV DEX ===
      m_profiles[ASSET_DERIV_DEX].assetClass                = ASSET_DERIV_DEX;
      m_profiles[ASSET_DERIV_DEX].className                 = "DerivDEX";
      m_profiles[ASSET_DERIV_DEX].atrMultiplierSL           = 2.5;
      m_profiles[ASSET_DERIV_DEX].atrMultiplierTP           = 4.0;
      m_profiles[ASSET_DERIV_DEX].hurstThreshold            = 0.60;
      m_profiles[ASSET_DERIV_DEX].riskPerTrade              = 2.0;
      m_profiles[ASSET_DERIV_DEX].magicOffset               = 9400;
      m_profiles[ASSET_DERIV_DEX].maxDrawdownPercent        = 18;
      m_profiles[ASSET_DERIV_DEX].enableScalpEngine         = true;
      m_profiles[ASSET_DERIV_DEX].enableGridRecovery        = false;
      m_profiles[ASSET_DERIV_DEX].enableSpikeHunter         = true;
      m_profiles[ASSET_DERIV_DEX].enableBreakoutEngine      = false;
      m_profiles[ASSET_DERIV_DEX].enableOUMeanReversion     = false;
      m_profiles[ASSET_DERIV_DEX].featureSetSize            = 70;
      m_profiles[ASSET_DERIV_DEX].pythonModelFamily         = "deriv_dex";

      // === ASSET 9: UNIVERSAL FALLBACK ===
      m_profiles[ASSET_UNIVERSAL].assetClass                = ASSET_UNIVERSAL;
      m_profiles[ASSET_UNIVERSAL].className                 = "Universal";
      m_profiles[ASSET_UNIVERSAL].atrMultiplierSL           = 1.0;
      m_profiles[ASSET_UNIVERSAL].atrMultiplierTP           = 1.5;
      m_profiles[ASSET_UNIVERSAL].hurstThreshold            = 0.45;
      m_profiles[ASSET_UNIVERSAL].riskPerTrade              = 1.0;
      m_profiles[ASSET_UNIVERSAL].magicOffset               = 0;
      m_profiles[ASSET_UNIVERSAL].maxDrawdownPercent        = 12;
      m_profiles[ASSET_UNIVERSAL].enableScalpEngine         = false;
      m_profiles[ASSET_UNIVERSAL].enableGridRecovery        = false;
      m_profiles[ASSET_UNIVERSAL].enableSpikeHunter         = false;
      m_profiles[ASSET_UNIVERSAL].enableBreakoutEngine      = false;
      m_profiles[ASSET_UNIVERSAL].enableOUMeanReversion     = false;
      m_profiles[ASSET_UNIVERSAL].featureSetSize            = 57;
      m_profiles[ASSET_UNIVERSAL].pythonModelFamily         = "universal";
   }

   //+------------------------------------------------------------------+
   //| Map Deriv family to coarse asset class                          |
   //+------------------------------------------------------------------+
   ENUM_ASSET_CLASS DerivFamilyToAssetClass(ENUM_DERIV_FAMILY family)
   {
      switch(family)
      {
         case DERIV_CRASH_BOOM:     return ASSET_DERIV_CRASHBOOM;
         case DERIV_VOLATILITY:     return ASSET_DERIV_VOLATILITY;
         case DERIV_SPOT_VOLATILITY:return ASSET_DERIV_VOLATILITY;
         case DERIV_STEP:           return ASSET_DERIV_STEP;
         case DERIV_MULTISTEP:      return ASSET_DERIV_STEP;
         case DERIV_SKEW_STEP:      return ASSET_DERIV_STEP;
         case DERIV_JUMP:           return ASSET_DERIV_JUMP;
         case DERIV_DEX:            return ASSET_DERIV_DEX;
         case DERIV_EXPONENTIAL:    return ASSET_DERIV_CRASHBOOM;  // Spike-like behavior
         case DERIV_HYBRID:         return ASSET_DERIV_CRASHBOOM;  // Spike-like behavior
         case DERIV_RANGE_BREAK:    return ASSET_DERIV_VOLATILITY; // Mean-reversion
         case DERIV_VOL_SWITCH:     return ASSET_DERIV_VOLATILITY; // Volatility family
         case DERIV_DRIFT_SWITCH:   return ASSET_DERIV_VOLATILITY; // Volatility family
         case DERIV_TREK:           return ASSET_DERIV_STEP;       // Step-like
         case DERIV_TACTICAL:       return ASSET_DERIV_STEP;       // Step-like
         case DERIV_DERIVED:        return ASSET_DERIV_STEP;       // Step-like
         case DERIV_STABLE_SPREAD:  return ASSET_DERIV_STEP;       // Mean-reversion
         case DERIV_PAIRS_ARBITRAGE:return ASSET_DERIV_STEP;       // Mean-reversion
         default:                   return ASSET_UNIVERSAL;
      }
   }

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CMultiAssetProfiler()
   {
      InitializeAllProfiles();
      m_detectedClass = ASSET_UNIVERSAL;
      m_detectedSymbol = "";
   }

   //+------------------------------------------------------------------+
   //| Access the internal Deriv profiler for fine-grained queries     |
   //+------------------------------------------------------------------+
   CDerivAssetProfiler* GetDerivProfiler()
   {
      return &m_derivProfiler;
   }

   //+------------------------------------------------------------------+
   //| Detect the asset class for a symbol using priority-ordered      |
   //| detection — Deriv first, then traditional asset classes         |
   //+------------------------------------------------------------------+
   ENUM_ASSET_CLASS DetectAssetClass(const string symbol)
   {
      string sym = NormalizeInstrumentSymbolName(symbol);

      // === DERIV DETECTION FIRST (most specific patterns) ===
      if(IsSyntheticIndexSymbolName(symbol))
      {
         ENUM_DERIV_FAMILY family = m_derivProfiler.DetectFamily(symbol);
         return DerivFamilyToAssetClass(family);
      }

      // === METALS DETECTION ===
      if(IsMetalsSymbolName(symbol))
         return ASSET_METALS;

      // === INDICES DETECTION ===
      if(IsIndicesSymbolName(symbol))
         return ASSET_INDICES;

      // === ENERGIES DETECTION ===
      if(IsEnergiesSymbolName(symbol))
         return ASSET_ENERGIES;

      // === FOREX DETECTION ===
      if(IsForexPairSymbolName(symbol))
         return ASSET_FOREX;

      return ASSET_UNIVERSAL;
   }

   //+------------------------------------------------------------------+
   //| Get the full asset profile for a symbol                          |
   //+------------------------------------------------------------------+
   SAssetProfile GetProfile(const string symbol)
   {
      m_detectedClass = DetectAssetClass(symbol);
      m_detectedSymbol = symbol;

      // For Deriv symbols, override ATR SL/TP from the fine-grained Deriv profile
      SAssetProfile profile = m_profiles[m_detectedClass];
      if(IsSyntheticIndexSymbolName(symbol))
      {
         SDerivProfile derivProfile = m_derivProfiler.GetProfile(symbol);
         profile.atrMultiplierSL    = derivProfile.atrMultiplierSL;
         profile.atrMultiplierTP    = derivProfile.atrMultiplierTP;
         profile.hurstThreshold     = derivProfile.hurstThreshold;
         profile.riskPerTrade       = derivProfile.riskPerTrade;
         profile.maxDrawdownPercent = derivProfile.maxDrawdownPercent;
         // Deriv families may override engine enables
         profile.enableSpikeHunter  = derivProfile.enableSpikeHunter;
         profile.enableGridRecovery = derivProfile.enableGridRecovery;
         profile.enableOUMeanReversion = derivProfile.enableOUFilter;
      }

      return profile;
   }

   //+------------------------------------------------------------------+
   //| Get the magic number for a symbol's asset class                  |
   //+------------------------------------------------------------------+
   int GetMagicNumber(int baseMagic, const string symbol)
   {
      SAssetProfile profile = GetProfile(symbol);
      return baseMagic + profile.magicOffset;
   }

   //+------------------------------------------------------------------+
   //| Get the magic offset for a symbol's asset class                  |
   //+------------------------------------------------------------------+
   int GetMagicOffset(const string symbol)
   {
      SAssetProfile profile = GetProfile(symbol);
      return profile.magicOffset;
   }

   //+------------------------------------------------------------------+
   //| Get the asset class for a symbol (public accessor)              |
   //+------------------------------------------------------------------+
   ENUM_ASSET_CLASS GetAssetClassForSymbol(const string symbol)
   {
      return DetectAssetClass(symbol);
   }

   //+------------------------------------------------------------------+
   //| Get the asset class name string                                  |
   //+------------------------------------------------------------------+
   string GetAssetClassName(const string symbol)
   {
      ENUM_ASSET_CLASS ac = DetectAssetClass(symbol);
      return m_profiles[ac].className;
   }

   //+------------------------------------------------------------------+
   //| Get the Python model family string for a symbol                  |
   //+------------------------------------------------------------------+
   string GetPythonModelFamily(const string symbol)
   {
      SAssetProfile profile = GetProfile(symbol);
      return profile.pythonModelFamily;
   }

   //+------------------------------------------------------------------+
   //| Get the feature set size for a symbol                            |
   //+------------------------------------------------------------------+
   int GetFeatureSetSize(const string symbol)
   {
      SAssetProfile profile = GetProfile(symbol);
      return profile.featureSetSize;
   }

   //+------------------------------------------------------------------+
   //| Check if symbol is a Deriv synthetic (delegates to Instruments) |
   //+------------------------------------------------------------------+
   bool IsDerivSymbol(const string symbol)
   {
      return IsSyntheticIndexSymbolName(symbol);
   }

   //+------------------------------------------------------------------+
   //| Print the full profile for a symbol                              |
   //+------------------------------------------------------------------+
   void PrintProfile(const string symbol)
   {
      SAssetProfile prof = GetProfile(symbol);

      PrintFormat("[MULTI-ASSET-PROFILER] Symbol=%s | Class=%s | atrSL=%.2f | atrTP=%.2f | hurst=%.2f | risk=%.2f%% | magicOff=%d | maxDD=%d%% | scalp=%s | grid=%s | spike=%s | breakout=%s | ouMR=%s | features=%d | python=%s",
                  symbol,
                  prof.className,
                  prof.atrMultiplierSL,
                  prof.atrMultiplierTP,
                  prof.hurstThreshold,
                  prof.riskPerTrade,
                  prof.magicOffset,
                  prof.maxDrawdownPercent,
                  prof.enableScalpEngine     ? "Y" : "N",
                  prof.enableGridRecovery    ? "Y" : "N",
                  prof.enableSpikeHunter     ? "Y" : "N",
                  prof.enableBreakoutEngine  ? "Y" : "N",
                  prof.enableOUMeanReversion ? "Y" : "N",
                  prof.featureSetSize,
                  prof.pythonModelFamily);

      // Also print fine-grained Deriv profile if applicable
      if(IsSyntheticIndexSymbolName(symbol))
         m_derivProfiler.PrintProfile(symbol);
   }
};

#endif // CORE_PROCESSING_MULTI_ASSET_PROFILER_MQH
