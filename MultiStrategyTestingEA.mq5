// Standalone Testing EA with Complete Test Profile System
// Load this instead of MultiStrategyAutonomousEA.mq5 for testing
#property copyright "Copyright 2024"
#property link      "https://github.com/"
#property version   "2.000"
#property strict

// First on purpose: it installs the IndicatorRelease guard every later header must compile under.
#include "IndicatorManager.mqh"
#include "Core/Orchestration/EAOrchestrator.mqh"

// Global variable definitions (declared extern in OrchestratorFwd)
#include "Core/Orchestration/GlobalDefs.mqh"

// Production logging & tracing. Both managers are DEFINED here to resolve the
// `extern` globals declared in their respective headers (pulled in transitively
// via EAOrchestrator.mqh). The Main EA defines the same two globals at
// MultiStrategyAutonomousEA.mq5:21-22. Without these definitions the Testing EA
// fails to link with error 370: unresolved extern variable
// ('g_structLog' / 'g_corrIdManager').
#include "Core/Utils/StructuredLogger.mqh"
#include "Core/Utils/CorrelationId.mqh"
#include "Core/Config/SharedEAInputs.mqh"

CStructuredLogger     g_structLog;
CCorrelationIdManager g_corrIdManager;

// L2-001: Global shutdown flag to prevent OnTimer accessing resources during deinit
bool g_shuttingDown;

// Forward declaration for GetDeInitReasonText
string GetDeInitReasonText(int reasonCode);

// Forward declarations for functions defined later in file
bool ValidateInputs();
void RestoreEngineStates();

// COMPLETE TEST PROFILE SYSTEM (from AUDIT_CompleteStrategyEngineTesting.md)

// 3.2 Complete Enum Definition (27 Single + 15 Combination + 3 Special = 45 Profiles)
enum ENUM_COMPLETE_TEST_PROFILE
{
    //--- Special / Utility
    TEST_PROFILE_CUSTOM              = 0,   // Use manual input flags (no override)
    TEST_PROFILE_DISABLE_ALL         = 1,   // Everything off - baseline noise floor

    //--- Single Indicator Strategies (Registry - executed via ProcessTradingLogic)
    TEST_PROFILE_SINGLE_MOMENTUM     = 10,  // Momentum only
    TEST_PROFILE_SINGLE_TREND        = 11,  // Trend only
    TEST_PROFILE_SINGLE_SR           = 12,  // Support/Resistance only
    TEST_PROFILE_SINGLE_ICT          = 13,  // Unified ICT/SMC only
    TEST_PROFILE_SINGLE_CANDLE       = 14,  // Candlestick only
    TEST_PROFILE_SINGLE_UNICORN      = 15,  // Unicorn Model only
    TEST_PROFILE_SINGLE_POT          = 16,  // Power of Three only
    TEST_PROFILE_SINGLE_MR           = 17,  // Mean Reversion only
    TEST_PROFILE_SINGLE_VB           = 18,  // Volatility Breakout only
    TEST_PROFILE_SINGLE_STATARB      = 19,  // Statistical Arbitrage only
    TEST_PROFILE_SINGLE_FVG          = 20,  // FVG Scalper only
    TEST_PROFILE_SINGLE_TURTLE       = 21,  // Turtle Soup only
    TEST_PROFILE_SINGLE_BREAKER      = 22,  // Breaker Block only
    TEST_PROFILE_SINGLE_NYGAP        = 23,  // NY Open Gap only
    TEST_PROFILE_SINGLE_ASIAN        = 24,  // Asian Range Break only
    TEST_PROFILE_SINGLE_LIQSWEEP     = 25,  // Liquidity Sweep only
    TEST_PROFILE_SINGLE_RANGECOMP    = 26,  // Range Compression only

    //--- Single AI Strategies (Registry)
    TEST_PROFILE_SINGLE_NN           = 30,  // Neural Network AI only
    TEST_PROFILE_SINGLE_TRANSF       = 31,  // Transformer AI only
    TEST_PROFILE_SINGLE_ENS          = 32,  // Ensemble AI only
    TEST_PROFILE_SINGLE_ONNX         = 33,  // ONNX AI only

    //--- Single Independent Engines (OnTick-direct, bypass consensus)
    TEST_PROFILE_SINGLE_FASTSCALP    = 40,  // Fast Scalp Engine only
    TEST_PROFILE_SINGLE_SPIKEHUNTER  = 41,  // Spike Hunter Engine only
    TEST_PROFILE_SINGLE_GRIDRECOVERY = 42,  // Grid Recovery Engine only
    TEST_PROFILE_SINGLE_ATRSCALP     = 43,  // ATR Scalping Engine only

    //--- Curated Strategy Families (Combination Profiles)
    TEST_PROFILE_TREND_SUITE         = 50,  // Trend + Momentum + VB + SR
    TEST_PROFILE_MEANREV_SUITE       = 51,  // MR + FVG + Turtle + Breaker
    TEST_PROFILE_ICT_SMC_SUITE       = 52,  // ICT + Candle + Unicorn + POT
    TEST_PROFILE_SESSION_SUITE       = 53,  // NYGap + Asian + LiqSweep + RangeComp
    TEST_PROFILE_SCALP_ENGINES_SUITE = 54,  // FastScalp + SpikeHunter + ATRScalp + GridRecovery

    //--- Aggregate Modes
    TEST_PROFILE_ALL_INDICATORS      = 60,  // All 19 registry indicators ON (no AI, no engines)
    TEST_PROFILE_ALL_INDICATORS_LIVE = 61,  // All indicators + live consensus mode
    TEST_PROFILE_AI_SUITE            = 62,  // All 4 AI modes ON (no indicators)
    TEST_PROFILE_ALL_ENGINES         = 63,  // All 4 independent engines ON
    TEST_PROFILE_ALL_ENGINES_SAFE    = 64,  // Engines with conservative risk caps

    //--- Full System Modes
    TEST_PROFILE_FULL_INDICATORS     = 70,  // All 19 indicators + consensus pipeline (production baseline)
    TEST_PROFILE_FULL_HYBRID         = 71,  // Full indicators + AI suite (hybrid mode)
    TEST_PROFILE_FULL_WITH_ENGINES   = 72,  // Full indicators + AI + all engines
    TEST_PROFILE_FULL_WITH_ENGINES_SAFE = 73, // Full system with safety caps
    TEST_PROFILE_EVERYTHING          = 74,  // Every single component enabled (max stress)
};

// 3.3 Resolved profile flags
//
// The profile system resolves ONE struct and then writes it into `SOrchestratorConfig` inside
// BuildOrchestratorConfig. It deliberately does not write the `InpEnable*` inputs: `input` variables
// are read-only in MQL5, so an ApplyFlagsToInputs() step could not exist at all - which is what the
// previous draft of this file assumed. The struct is the single carrier from profile to config.
struct SCompleteTestFlags
{
    // Registry indicators
    bool momentum;
    bool trend;
    bool supportResistance;
    bool candlestick;
    bool meanReversion;
    bool volatilityBreakout;
    bool fvgScalper;
    bool turtleSoup;
    bool breakerBlock;
    bool nyOpenGap;
    bool asianRangeBreak;
    bool statisticalArbitrage;
    bool liquiditySweep;
    bool rangeCompression;
    bool donchianBreakout;
    bool rsi2Pullback;
    bool dailyLevelBreakout;
    bool dailyLevelFade;
    bool emaRibbon;
    bool gapContinuation;
    bool openingRangeBreakout;
    bool ictSessionGap;
    bool ictStructureShift;
    // AI roster
    bool aiModeEnabled;
    bool neuralNetwork;
    bool transformer;
    bool ensemble;
    bool onnxAI;
    // Independent engines
    bool fastScalpEngine;
    bool spikeHunterEngine;
    bool gridRecoveryEngine;
    bool atrScalpingEngine;
    // Parked / dead-code engines - only switched on by an explicit include request
    bool enableHurstEngine;
    bool enableOUProcess;
};

SCompleteTestFlags g_completeFlags;

void ClearCompleteTestFlags(SCompleteTestFlags &f)
{
    f.momentum = false;              f.trend = false;
    f.supportResistance = false;     f.candlestick = false;
    f.meanReversion = false;         f.volatilityBreakout = false;
    f.fvgScalper = false;            f.turtleSoup = false;
    f.breakerBlock = false;          f.nyOpenGap = false;
    f.asianRangeBreak = false;       f.statisticalArbitrage = false;
    f.liquiditySweep = false;        f.rangeCompression = false;
    f.donchianBreakout = false;      f.rsi2Pullback = false;
    f.dailyLevelBreakout = false;    f.dailyLevelFade = false;
    f.emaRibbon = false;             f.gapContinuation = false;
    f.openingRangeBreakout = false;  f.ictSessionGap = false;
    f.ictStructureShift = false;
    f.aiModeEnabled = false;         f.neuralNetwork = false;
    f.transformer = false;           f.ensemble = false;
    f.onnxAI = false;
    f.fastScalpEngine = false;       f.spikeHunterEngine = false;
    f.gridRecoveryEngine = false;    f.atrScalpingEngine = false;
    f.enableHurstEngine = false;     f.enableOUProcess = false;
}

void EnableAllIndicators(SCompleteTestFlags &f)
{
    f.momentum = true;               f.trend = true;
    f.supportResistance = true;      f.candlestick = true;
    f.meanReversion = true;          f.volatilityBreakout = true;
    f.fvgScalper = true;             f.turtleSoup = true;
    f.breakerBlock = true;           f.nyOpenGap = true;
    f.asianRangeBreak = true;        f.statisticalArbitrage = true;
    f.liquiditySweep = true;         f.rangeCompression = true;
    f.donchianBreakout = true;       f.rsi2Pullback = true;
    f.dailyLevelBreakout = true;     f.dailyLevelFade = true;
    f.emaRibbon = true;              f.gapContinuation = true;
    f.openingRangeBreakout = true;   f.ictSessionGap = true;
    f.ictStructureShift = true;
}

void EnableAllAI(SCompleteTestFlags &f)
{
    f.aiModeEnabled = true;
    f.neuralNetwork = true;          f.transformer = true;
    f.ensemble = true;               f.onnxAI = true;
}

void EnableAllEngines(SCompleteTestFlags &f)
{
    f.fastScalpEngine = true;        f.spikeHunterEngine = true;
    f.gridRecoveryEngine = true;     f.atrScalpingEngine = true;
}

// Resolve one profile into the flags struct. Returns false only for an unknown profile id, so a caller
// that trusts it cannot silently end up running the previous profile's flags.
bool ApplyCompleteTestProfile(ENUM_COMPLETE_TEST_PROFILE profile, SCompleteTestFlags &flags,
                              bool includeDeadCode)
{
    ClearCompleteTestFlags(flags);

    switch(profile)
    {
        case TEST_PROFILE_CUSTOM:
        case TEST_PROFILE_DISABLE_ALL:
            return true;

        //--- Single indicator strategies
        case TEST_PROFILE_SINGLE_MOMENTUM:    flags.momentum = true;          return true;
        case TEST_PROFILE_SINGLE_TREND:       flags.trend = true;             return true;
        case TEST_PROFILE_SINGLE_SR:          flags.supportResistance = true; return true;
        case TEST_PROFILE_SINGLE_CANDLE:      flags.candlestick = true;       return true;
        case TEST_PROFILE_SINGLE_MR:          flags.meanReversion = true;     return true;
        case TEST_PROFILE_SINGLE_VB:          flags.volatilityBreakout = true;return true;
        case TEST_PROFILE_SINGLE_STATARB:     flags.statisticalArbitrage = true; return true;
        case TEST_PROFILE_SINGLE_FVG:         flags.fvgScalper = true;        return true;
        case TEST_PROFILE_SINGLE_TURTLE:      flags.turtleSoup = true;        return true;
        case TEST_PROFILE_SINGLE_BREAKER:     flags.breakerBlock = true;      return true;
        case TEST_PROFILE_SINGLE_NYGAP:       flags.nyOpenGap = true;         return true;
        case TEST_PROFILE_SINGLE_ASIAN:       flags.asianRangeBreak = true;   return true;
        case TEST_PROFILE_SINGLE_LIQSWEEP:    flags.liquiditySweep = true;    return true;
        case TEST_PROFILE_SINGLE_RANGECOMP:   flags.rangeCompression = true;  return true;

        //--- Profiles whose class no longer exists (Unified ICT / Unicorn Model / Power of Three left
        //    the roster in Batch 207 - no class, so nothing could register them). They resolve to an
        //    empty set rather than a false success, and print the reason.
        case TEST_PROFILE_SINGLE_ICT:
        case TEST_PROFILE_SINGLE_UNICORN:
        case TEST_PROFILE_SINGLE_POT:
            PrintFormat("[TEST-PROFILE] %s selects a strategy with no class in this roster; resolving empty.",
                        EnumToString(profile));
            return true;

        //--- Single AI strategies
        case TEST_PROFILE_SINGLE_NN:
            flags.aiModeEnabled = true; flags.neuralNetwork = true;  return true;
        case TEST_PROFILE_SINGLE_TRANSF:
            flags.aiModeEnabled = true; flags.transformer = true;    return true;
        case TEST_PROFILE_SINGLE_ENS:
            flags.aiModeEnabled = true; flags.ensemble = true;       return true;
        case TEST_PROFILE_SINGLE_ONNX:
            flags.aiModeEnabled = true; flags.onnxAI = true;         return true;

        //--- Single engines
        case TEST_PROFILE_SINGLE_FASTSCALP:    flags.fastScalpEngine = true;   return true;
        case TEST_PROFILE_SINGLE_SPIKEHUNTER:  flags.spikeHunterEngine = true; return true;
        case TEST_PROFILE_SINGLE_GRIDRECOVERY: flags.gridRecoveryEngine = true;return true;
        case TEST_PROFILE_SINGLE_ATRSCALP:     flags.atrScalpingEngine = true; return true;

        //--- Curated families
        case TEST_PROFILE_TREND_SUITE:
            flags.trend = true; flags.momentum = true;
            flags.volatilityBreakout = true; flags.supportResistance = true;
            return true;
        case TEST_PROFILE_MEANREV_SUITE:
            flags.meanReversion = true; flags.fvgScalper = true;
            flags.turtleSoup = true; flags.breakerBlock = true;
            return true;
        case TEST_PROFILE_ICT_SMC_SUITE:
            flags.candlestick = true;    // the only ICT-family row that still has a class
            return true;
        case TEST_PROFILE_SESSION_SUITE:
            flags.nyOpenGap = true; flags.asianRangeBreak = true;
            flags.liquiditySweep = true; flags.rangeCompression = true;
            return true;
        case TEST_PROFILE_SCALP_ENGINES_SUITE:
            EnableAllEngines(flags);
            return true;

        //--- Aggregate modes
        case TEST_PROFILE_ALL_INDICATORS:
        case TEST_PROFILE_ALL_INDICATORS_LIVE:
        case TEST_PROFILE_FULL_INDICATORS:
            EnableAllIndicators(flags);
            return true;
        case TEST_PROFILE_AI_SUITE:
            EnableAllAI(flags);
            return true;
        case TEST_PROFILE_ALL_ENGINES:
        case TEST_PROFILE_ALL_ENGINES_SAFE:
            EnableAllEngines(flags);
            return true;
        case TEST_PROFILE_FULL_HYBRID:
            EnableAllIndicators(flags);
            EnableAllAI(flags);
            return true;
        case TEST_PROFILE_FULL_WITH_ENGINES:
        case TEST_PROFILE_FULL_WITH_ENGINES_SAFE:
            EnableAllIndicators(flags);
            EnableAllAI(flags);
            EnableAllEngines(flags);
            return true;
        case TEST_PROFILE_EVERYTHING:
            EnableAllIndicators(flags);
            EnableAllAI(flags);
            EnableAllEngines(flags);
            if(includeDeadCode)
            {
                flags.enableHurstEngine = true;
                flags.enableOUProcess = true;
            }
            return true;
    }

    PrintFormat("[TEST-PROFILE] ERROR: unknown profile id %d - no flags applied.", (int)profile);
    return false;
}

void LogCompleteActivationMatrix()
{
    Print("[TEST-PROFILE] ===== resolved activation matrix =====");
    PrintFormat("[TEST-PROFILE] ind: mom=%d trend=%d sr=%d candle=%d mr=%d vb=%d fvg=%d turtle=%d breaker=%d nygap=%d asian=%d statarb=%d liqswp=%d range=%d",
                (int)g_completeFlags.momentum, (int)g_completeFlags.trend,
                (int)g_completeFlags.supportResistance, (int)g_completeFlags.candlestick,
                (int)g_completeFlags.meanReversion, (int)g_completeFlags.volatilityBreakout,
                (int)g_completeFlags.fvgScalper, (int)g_completeFlags.turtleSoup,
                (int)g_completeFlags.breakerBlock, (int)g_completeFlags.nyOpenGap,
                (int)g_completeFlags.asianRangeBreak, (int)g_completeFlags.statisticalArbitrage,
                (int)g_completeFlags.liquiditySweep, (int)g_completeFlags.rangeCompression);
    PrintFormat("[TEST-PROFILE] ind+: donchian=%d rsi2=%d dlbo=%d dlfade=%d ribbon=%d gapcont=%d orb=%d ictgap=%d ictshift=%d",
                (int)g_completeFlags.donchianBreakout, (int)g_completeFlags.rsi2Pullback,
                (int)g_completeFlags.dailyLevelBreakout, (int)g_completeFlags.dailyLevelFade,
                (int)g_completeFlags.emaRibbon, (int)g_completeFlags.gapContinuation,
                (int)g_completeFlags.openingRangeBreakout, (int)g_completeFlags.ictSessionGap,
                (int)g_completeFlags.ictStructureShift);
    PrintFormat("[TEST-PROFILE] ai: mode=%d nn=%d transf=%d ens=%d onnx=%d | engines: scalp=%d spike=%d grid=%d atr=%d | deadcode: hurst=%d ou=%d",
                (int)g_completeFlags.aiModeEnabled, (int)g_completeFlags.neuralNetwork,
                (int)g_completeFlags.transformer, (int)g_completeFlags.ensemble,
                (int)g_completeFlags.onnxAI, (int)g_completeFlags.fastScalpEngine,
                (int)g_completeFlags.spikeHunterEngine, (int)g_completeFlags.gridRecoveryEngine,
                (int)g_completeFlags.atrScalpingEngine, (int)g_completeFlags.enableHurstEngine,
                (int)g_completeFlags.enableOUProcess);
}
input group "=== COMPLETE TEST PROFILE SYSTEM ==="
input ENUM_COMPLETE_TEST_PROFILE InpCompleteTestProfile = TEST_PROFILE_CUSTOM;
input bool     InpTestProfileOverrideAll = true;      // If true, profile overrides all individual flags
input bool     InpIncludeDeadCodeInProfiles = false;  // Include dead-code strategies in profiles

//=== Mode-specific inputs (shared inputs are in Core/Config/SharedEAInputs.mqh) ===

input group "=== GENERAL & RISK MANAGEMENT ==="
input double   InpMaxRiskPerTrade = 5.0;
input double   InpMaxDailyRisk = 40.0;
input double   InpMaxPortfolioRisk = 60.0;
input double   InpDailyLossLimitPercent = 10.0;
input bool     InpAllowMinLotRoundUp = false;
input double   InpMinLotRiskMultiplier = 1.0;

input group "=== STRATEGY ENABLE / DISABLE ==="
input bool     InpUseCuratedStrategySet = false;

input group "=== BATCH 114: KALMAN, REGIME, LIQUIDITY ==="
input bool     InpEnableKalmanMR = false;
input bool     InpEnableChangepointDetect = false;
input bool     InpEnableFourStateRegime = false;
input bool     InpEnableVolTargeting = false;
input bool     InpEnableLiquiditySweep = false;
input bool     InpEnableRangeCompression = false;

input group "=== AI ENGINE SETTINGS ==="
input bool     InpEnableAIMode = false;
input bool     InpEnableNeuralNetwork = false;
input bool     InpEnableTransformer = false;
input bool     InpEnableEnsemble = false;
input bool     InpEnableOnnxAI = false;
input bool     InpEnablePythonBridgeAI = false;
input ENUM_PYTHON_BRIDGE_MODE InpPythonBridgeMode = PYTHON_BRIDGE_OFF;

input group "=== EA OPERATING MODE ==="
input bool     InpEnableMomentumScalping = false;

input group "=== SPIKE HUNTER ENGINE ==="
input bool     InpSpikeHunterEnabled = false;


// ORCHESTRATOR CONFIG BUILDER (with test profile integration)

SOrchestratorConfig BuildOrchestratorConfig()
{
    SOrchestratorConfig config;
    PopulateSharedOrchestratorConfig(config);

    // Mode-specific overrides
    // General
    config.magicNumber = InpMagicNumber;
    config.configVersion = InpConfigVersion;
    config.lotSize = InpLotSize;
    config.useEnhancedRisk = InpUseEnhancedRisk;
    config.maxRiskPerTrade = InpMaxRiskPerTrade;
    config.maxDailyRisk = InpMaxDailyRisk;
    config.maxPortfolioRisk = InpMaxPortfolioRisk;
    config.maxDrawdown = InpMaxDrawdown;
    config.dailyLossLimitPercent = InpDailyLossLimitPercent;
    config.riskTier = InpRiskTier;
    config.enableCompoundingTiers = InpEnableCompoundingTiers;
    config.compoundingTierCheckIntervalSec = InpCompoundingTierCheckIntervalSec;
    config.enableSessionWeights = InpEnableSessionWeights;
    config.sessionDSTOffsetHours = InpSessionDSTOffsetHours;
    config.enableSkewStepAnalyzer = InpEnableSkewStepAnalyzer;
    config.enableFamilyWeightMatrix = InpEnableFamilyWeightMatrix;
    config.allowMinLotRoundUp = InpAllowMinLotRoundUp;
    config.minLotRiskMultiplier = InpMinLotRiskMultiplier;
    config.symbolsToTrade = InpSymbolsToTrade;
    config.minSecondsBetweenTrades = InpMinSecondsBetweenTrades;
    config.maxPositionsTotal = InpMaxPositionsTotal;
    config.maxPositionsTotalMin = InpMaxPositionsTotalMin;
    config.maxPositionsPerSymbol = InpMaxPositionsPerSymbol;
    config.maxPositionsPerSymbolMin = InpMaxPositionsPerSymbolMin;
    config.maxTradeSendsPerCycle = InpMaxTradeSendsPerCycle;

    // Strategy Selection - OVERRIDDEN BY TEST PROFILE if enabled
    if(InpTestProfileOverrideAll && InpCompleteTestProfile != TEST_PROFILE_CUSTOM)
    {
        ApplyCompleteTestProfile(InpCompleteTestProfile, g_completeFlags, InpIncludeDeadCodeInProfiles);

        config.enableMomentum = g_completeFlags.momentum;
        config.enableTrend = g_completeFlags.trend;
        config.enableSupportResistance = g_completeFlags.supportResistance;
        config.enableCandlestick = g_completeFlags.candlestick;
        config.candlestickRequireTrend = InpCandlestickRequireTrend;
        config.enableMeanReversion = g_completeFlags.meanReversion;
        config.enableVolatilityBreakout = g_completeFlags.volatilityBreakout;
        config.enableFVGScalper = g_completeFlags.fvgScalper;
        config.enableTurtleSoup = g_completeFlags.turtleSoup;
        config.enableBreakerBlock = g_completeFlags.breakerBlock;
        config.enableNYOpenGap = g_completeFlags.nyOpenGap;
        config.enableAsianRangeBreak = g_completeFlags.asianRangeBreak;
        config.enableStatisticalArbitrage = g_completeFlags.statisticalArbitrage;
        config.enableLiquiditySweep = g_completeFlags.liquiditySweep;
        config.enableRangeCompression = g_completeFlags.rangeCompression;
        config.enableDonchianBreakout = g_completeFlags.donchianBreakout;
        config.enableRSI2Pullback = g_completeFlags.rsi2Pullback;
        config.enableDailyLevelBreakout = g_completeFlags.dailyLevelBreakout;
        config.enableDailyLevelFade = g_completeFlags.dailyLevelFade;
        config.enableEMARibbon = g_completeFlags.emaRibbon;
        config.enableGapContinuation = g_completeFlags.gapContinuation;
        config.enableOpeningRangeBreakout = g_completeFlags.openingRangeBreakout;
        config.enableICTSessionGap = g_completeFlags.ictSessionGap;
        config.enableICTStructureShift = g_completeFlags.ictStructureShift;

        config.enableAIMode = g_completeFlags.aiModeEnabled;
        config.enableNeuralNetwork = g_completeFlags.neuralNetwork;
        config.enableTransformer = g_completeFlags.transformer;
        config.enableEnsemble = g_completeFlags.ensemble;
        config.enableOnnxAI = g_completeFlags.onnxAI;
        config.enablePythonBridgeAI = InpEnablePythonBridgeAI;
        config.pythonBridgeMode = InpPythonBridgeMode;
        config.pythonBridgeEndpoint = InpPythonBridgeEndpoint;
        config.pythonBridgeRequestTimeoutMs = InpPythonBridgeRequestTimeoutMs;
        config.pythonBridgeHeartbeatTimeoutSec = InpPythonBridgeHeartbeatTimeoutSec;
        config.pythonBridgeMaxReconnectAttempts = InpPythonBridgeMaxReconnectAttempts;
        config.pythonBridgeReconnectBackoffMs = InpPythonBridgeReconnectBackoffMs;
        config.enableExternalLLM = InpEnableExternalLLM;
        config.externalLLMEndpoint = InpExternalLLMEndpoint;
        config.aiConfidenceThreshold = InpAIConfidenceThreshold;
        config.aiWeightMultiplier = InpAIWeightMultiplier;
        config.aiDrawdownSizingLimit = InpAIDrawdownSizingLimit;

        config.enableScalpEngine = g_completeFlags.fastScalpEngine;
        config.scalpAsyncMode = InpScalpAsyncMode;
        config.scalpMaxLatencyMs = InpScalpMaxLatencyMs;
        config.spikeHunterEnabled = g_completeFlags.spikeHunterEngine;
        config.gridRecoveryEnabled = g_completeFlags.gridRecoveryEngine;
        config.atrScalpingEnabled = g_completeFlags.atrScalpingEngine;

        // Dead code
        config.enableHurstEngine = g_completeFlags.enableHurstEngine;
        config.enableOUProcess = g_completeFlags.enableOUProcess;

        config.adxMinLotMultiplier = InpAdxMinLotMultiplier;
        config.adxAllowNoTrendTrading = InpAdxTradeOnNoTrend;
    }
    else
    {
        // Use manual input flags (original behavior)
        config.enableMomentum = InpEnableMomentum;
        config.enableTrend = InpEnableTrend;
        config.enableSupportResistance = InpEnableSupportResistance;
        config.enableCandlestick = InpEnableCandlestick;
        config.candlestickRequireTrend = InpCandlestickRequireTrend;
        config.enableMeanReversion = InpEnableMeanReversion;
        config.enableVolatilityBreakout = InpEnableVolatilityBreakout;
        config.enableFVGScalper = InpEnableFVGScalper;
        config.enableTurtleSoup = InpEnableTurtleSoup;
        config.enableBreakerBlock = InpEnableBreakerBlock;
        config.enableNYOpenGap = InpEnableNYOpenGap;
        config.enableAsianRangeBreak = InpEnableAsianRangeBreak;
        config.enableStatisticalArbitrage = InpEnableStatisticalArbitrage;
        config.enableLiquiditySweep = InpEnableLiquiditySweep;
        config.enableRangeCompression = InpEnableRangeCompression;
        config.enableDonchianBreakout = InpEnableDonchianBreakout;
        config.enableRSI2Pullback = InpEnableRSI2Pullback;
        config.enableDailyLevelBreakout = InpEnableDailyLevelBreakout;
        config.enableDailyLevelFade = InpEnableDailyLevelFade;
        config.enableEMARibbon = InpEnableEMARibbon;
        config.enableGapContinuation = InpEnableGapContinuation;
        config.enableOpeningRangeBreakout = InpEnableOpeningRangeBreakout;
        config.enableICTSessionGap = InpEnableICTSessionGap;
        config.enableICTStructureShift = InpEnableICTStructureShift;

        // AI
        config.enableAIMode = InpEnableAIMode;
        config.enableNeuralNetwork = InpEnableNeuralNetwork;
        config.enableTransformer = InpEnableTransformer;
        config.enableEnsemble = InpEnableEnsemble;
        config.enableOnnxAI = InpEnableOnnxAI;
        config.enablePythonBridgeAI = InpEnablePythonBridgeAI;
        config.pythonBridgeMode = InpPythonBridgeMode;
        config.pythonBridgeEndpoint = InpPythonBridgeEndpoint;
        config.pythonBridgeRequestTimeoutMs = InpPythonBridgeRequestTimeoutMs;
        config.pythonBridgeHeartbeatTimeoutSec = InpPythonBridgeHeartbeatTimeoutSec;
        config.pythonBridgeMaxReconnectAttempts = InpPythonBridgeMaxReconnectAttempts;
        config.pythonBridgeReconnectBackoffMs = InpPythonBridgeReconnectBackoffMs;
        config.enableExternalLLM = InpEnableExternalLLM;
        config.externalLLMEndpoint = InpExternalLLMEndpoint;
        config.aiConfidenceThreshold = InpAIConfidenceThreshold;
        config.aiWeightMultiplier = InpAIWeightMultiplier;
        config.aiDrawdownSizingLimit = InpAIDrawdownSizingLimit;

        config.enableScalpEngine = InpEnableScalpEngine;
        config.scalpAsyncMode = InpScalpAsyncMode;
        config.scalpMaxLatencyMs = InpScalpMaxLatencyMs;
        config.spikeHunterEnabled = InpSpikeHunterEnabled;
        config.gridRecoveryEnabled = InpGridRecoveryEnabled;
        config.atrScalpingEnabled = InpATRScalpingEnabled;

        // Dead code
        config.enableHurstEngine = InpEnableHurstEngine;
        config.enableOUProcess = InpEnableOUProcess;

        config.adxMinLotMultiplier = InpAdxMinLotMultiplier;
        config.adxAllowNoTrendTrading = InpAdxTradeOnNoTrend;
    }

    // EA Operating Mode
    config.eaMode = InpEAMode;
    config.enableVisualAnalysis = InpEnableVisualAnalysis;
    config.maxVisualObjects = InpMaxVisualObjects;
    config.strictEAMode = InpStrictEAMode;

    // Consensus Quorum
    config.quorumProfile = InpQuorumProfile;
    config.quorumThreshold = InpQuorumThreshold;
    config.minLiveVoters = InpMinLiveVoters;
    config.consensusConflictDeadband = InpConsensusConflictDeadband;
    config.consensusMinReadyWeightRatio = InpConsensusMinReadyWeightRatio;
    config.consensusSupportFloorNewBar = InpConsensusSupportFloorNewBar;
    config.consensusSupportFloorIntrabar = InpConsensusSupportFloorIntrabar;
    config.singleVoterFloor = InpSingleVoterFloor;
    config.symbolLossStreakLimit = InpSymbolLossStreakLimit;
    config.symbolLossStreakCooldownMin = InpSymbolLossStreakCooldownMin;
    config.symbolStreakRiskScale = InpSymbolStreakRiskScale;
    config.symbolStreakRiskMinCount = InpSymbolStreakRiskMinCount;

    // Strategy Weights
    config.weightMomentum = InpWeightMomentum;
    config.weightTrend = InpWeightTrend;
    config.weightSupportResistance = InpWeightSupportResistance;
    config.weightCandlestick = InpWeightCandlestick;
    config.weightMeanReversion = InpWeightMeanReversion;
    config.weightVolatilityBreakout = InpWeightVolatilityBreakout;
    config.weightStatisticalArbitrage = InpWeightStatisticalArbitrage;
    config.weightFVGScalper = InpWeightFVGScalper;
    config.weightTurtleSoup = InpWeightTurtleSoup;
    config.weightBreakerBlock = InpWeightBreakerBlock;
    config.weightNYOpenGap = InpWeightNYOpenGap;
    config.weightAsianRangeBreak = InpWeightAsianRangeBreak;
    config.weightLiquiditySweep = InpWeightLiquiditySweep;
    config.weightRangeCompression = InpWeightRangeCompression;

    config.dashboardEnabled = InpDashboardEnabled;
    config.dashboardEndpoint = InpDashboardEndpoint;
    config.dashboardPushIntervalSec = InpDashboardPushIntervalSec;
    config.dashboardControlEnabled = InpDashboardControlEnabled;

    config.enableLiveAuthorityGate = InpEnableLiveAuthorityGate;
    config.allowHybridAIStandalone = InpAllowHybridAIStandalone;
    config.aiStandaloneMinConfidence = InpAIStandaloneMinConfidence;
    config.aiStandaloneRelaxedConfidence = InpAIStandaloneRelaxedConfidence;
    config.hybridGateRelaxAfterCycles = InpHybridGateRelaxAfterCycles;
    config.authorityMinSamples = InpAuthorityMinSamples;
    config.authorityMinExpectancyR = InpAuthorityMinExpectancyR;
    config.authorityMinProfitFactor = InpAuthorityMinProfitFactor;
    config.authorityMinCostScore = InpAuthorityMinCostScore;
    config.authorityMinReadinessScore = InpAuthorityMinReadinessScore;
    config.authorityMinContextScore = InpAuthorityMinContextScore;
    config.aiBootstrapRiskMultiplier = InpAIBootstrapRiskMultiplier;
    config.aiPromotedRiskMultiplier = InpAIPromotedRiskMultiplier;

    config.enableNNAttributionDiagnostics = InpEnableNNAttributionDiagnostics;
    config.runNNAttributionSelfTest = InpRunNNAttributionSelfTest;

    // Runtime Cadence
    config.intrabarDynamicQuorumEnabled = InpIntrabarDynamicQuorumEnabled;
    config.pipelineMinConfidence = InpPipelineMinConfidence;
    config.pipelineIntrabarConfidenceCap = InpPipelineIntrabarConfidenceCap;
    config.pipelineEnableRegimeCostGate = InpPipelineEnableRegimeCostGate;
    config.pipelineEngineRegistry = InpPipelineEngineRegistry;
    config.pipelineMaxSpreadToAtrRatio = InpPipelineMaxSpreadToAtrRatio;
    config.pipelineSpreadShockCooldownSec = InpPipelineSpreadShockCooldownSec;
    config.pipelineLateEntryZScoreLimit = InpPipelineLateEntryZScoreLimit;
    config.atrCrisisRatioThreshold = InpAtrCrisisRatioThreshold;
    config.atrCrisisRatioThresholdSynthetic = InpAtrCrisisRatioThresholdSynthetic;
    config.atrCrisisRatioThresholdVolatility = InpAtrCrisisRatioThresholdVolatility;
    config.atrCrisisRatioThresholdDefault = InpAtrCrisisRatioThresholdDefault;
    config.hardSpreadCutoffPoints = InpHardSpreadCutoffPoints;
    config.deadlockAttributionIntervalSec = InpDeadlockAttributionIntervalSec;
    config.heartbeatInterval = InpHeartbeatInterval;
    config.enableMomentumScalping = InpEnableMomentumScalping;
    config.momentumScalpCooldownSeconds = InpMomentumScalpCooldownSeconds;
    config.momentumScalpTimeframe = InpMomentumScalpTimeframe;
    config.candlestickIntrabarTimeframe = InpCandlestickIntrabarTimeframe;
    config.intrabarEligibilityMomentum = InpIntrabarEligibilityMomentum;
    config.intrabarEligibilityTrend = InpIntrabarEligibilityTrend;
    config.intrabarEligibilitySupportResistance = InpIntrabarEligibilitySupportResistance;
    config.intrabarEligibilityCandlestick = InpIntrabarEligibilityCandlestick;
    config.intrabarEligibilityMeanReversion = InpIntrabarEligibilityMeanReversion;
    config.intrabarEligibilityVolatilityBreakout = InpIntrabarEligibilityVolatilityBreakout;
    config.intrabarEligibilityNeuralNetworkAI = InpIntrabarEligibilityNeuralNetworkAI;
    config.intrabarEligibilityTransformerAI = InpIntrabarEligibilityTransformerAI;
    config.intrabarEligibilityEnsembleAI = InpIntrabarEligibilityEnsembleAI;
    config.intrabarEligibilityOnnxAI = InpIntrabarEligibilityOnnxAI;
    config.maxSignalEvaluationsPerCycle = InpMaxSignalEvaluationsPerCycle;
    config.readinessReuseTtlSeconds = InpReadinessReuseTtlSeconds;
    config.enableNNOnlineTraining = InpEnableNNOnlineTraining;
    config.enableNNWeightMutation = InpEnableNNWeightMutation;
    config.enableNNPseudoLabeling = InpEnableNNPseudoLabeling;
    config.nnPseudoLabelBarsAhead = InpNNPseudoLabelBarsAhead;
    config.nnSampleIntervalSeconds = InpNNSampleIntervalSeconds;
    config.nnCheckpointEveryLabeled = InpNNCheckpointEveryLabeled;

    // Signal Validator
    config.validatorNewBarMinConfluence = InpValidatorNewBarMinConfluence;
    config.validatorNewBarMinQuality = InpValidatorNewBarMinQuality;
    config.validatorNewBarMinConfidence = InpValidatorNewBarMinConfidence;
    config.validatorIntrabarMinConfluence = InpValidatorIntrabarMinConfluence;
    config.validatorIntrabarMinQuality = InpValidatorIntrabarMinQuality;
    config.validatorIntrabarMinConfidence = InpValidatorIntrabarMinConfidence;

    // Execution Safety
    config.orderFillingMode = InpOrderFillingMode;
    config.tradeSlippagePoints = InpTradeSlippagePoints;
    config.maxEntrySpreadPoints = InpMaxEntrySpreadPoints;
    config.maxEntryDriftPoints = InpMaxEntryDriftPoints;
    config.protectiveModifyCooldownSec = InpProtectiveModifyCooldownSec;
    config.enableSignalReversalExit = InpEnableSignalReversalExit;
    config.signalReversalMinConfidence = InpSignalReversalMinConfidence;
    config.signalReversalProfitGuard = InpSignalReversalProfitGuard;
    config.signalReversalMinLossR = InpSignalReversalMinLossR;
    config.signalReversalMaxLossR = InpSignalReversalMaxLossR;
    config.signalReversalMinTimeSec = InpSignalReversalMinTimeSec;
    config.enableStructuralInvalidation = InpEnableStructuralInvalidation;
    config.enablePositionLifecycleManager = InpEnablePositionLifecycleManager;
    config.lifecycleBreakevenBufferPoints = InpLifecycleBreakevenBufferPoints;
    config.lifecycleTrailingDistancePoints = InpLifecycleTrailingDistancePoints;
    config.lifecycleTrailingStepPoints = InpLifecycleTrailingStepPoints;
    config.lifecycleUseATRTrailing = InpLifecycleUseATRTrailing;
    config.lifecycleATRMultiplier = InpLifecycleATRMultiplier;

    config.enableMaxHoldTime = InpEnableMaxHoldTime;
    config.maxHoldHoursIntraday = InpMaxHoldHoursIntraday;
    config.maxHoldHoursSwing = InpMaxHoldHoursSwing;
    config.maxHoldOnlyIfLoss = InpMaxHoldOnlyIfLoss;

    config.lossGuardAdverseMomentumExit = InpLossGuardAdverseMomentumExit;
    config.lossGuardAdverseMomentumATRMultiplier = InpLossGuardAdverseMomentumATR;
    config.lossGuardConsecutiveLossLimit = InpLossGuardConsecutiveLossLimit;
    config.lossGuardConsecutiveLossCooldownSec = InpLossGuardConsecutiveLossCooldownSec;
    config.lossGuardDailyLossCircuitBreakerPercent = InpLossGuardDailyLossCircuitBreakerPct;
    config.lossGuardPositionLossLimitPercent = InpLossGuardPositionLossLimitPct;

    config.emergencyFlattenAllAccountPositions = InpEmergencyFlattenAllAccountPositions;
    config.unprotectedRemediationIntervalSec = InpUnprotectedRemediationIntervalSec;
    config.unprotectedMaxRestoreAttempts = InpUnprotectedMaxRestoreAttempts;
    config.syntheticSpikeVelocityMultiplier = InpSyntheticSpikeVelocityMultiplier;
    config.syntheticSpikePauseSeconds = InpSyntheticSpikePauseSeconds;

    config.enableDynamicSlippage = InpEnableDynamicSlippage;
    config.dynamicSlippageAtrPercent = InpDynamicSlippageAtrPercent;
    config.dynamicSlippageMinPoints = InpDynamicSlippageMinPoints;
    config.dynamicSlippageMaxMultiplier = InpDynamicSlippageMaxMultiplier;
    config.dynamicSlippageAtrPeriod = InpDynamicSlippageAtrPeriod;

    // Spike Detection
    config.spikeConfirmWindows = InpSpikeConfirmWindows;

    // Skew Step Analyzer
    config.skewStepBufferSize = InpSkewStepBufferSize;
    config.skewStepCalmThreshold = InpSkewStepCalmThreshold;
    config.skewStepSmallThreshold = InpSkewStepSmallThreshold;
    config.skewStepLargeThreshold = InpSkewStepLargeThreshold;

    config.spikeHunterEnabled = InpSpikeHunterEnabled;
    config.spikeHunterVelocityMult = InpSpikeHunterVelocityMult;
    config.spikeHunterMinConsecTicks = InpSpikeHunterMinConsecTicks;
    config.spikeHunterConsecWindowMs = InpSpikeHunterConsecWindowMs;
    config.spikeHunterATRCompression = InpSpikeHunterATRCompression;
    config.spikeHunterSLAtrMult = InpSpikeHunterSLAtrMult;
    config.spikeHunterTPAtrMult = InpSpikeHunterTPAtrMult;
    config.spikeHunterMaxPositions = InpSpikeHunterMaxPositions;
    config.spikeHunterCooldownMs = InpSpikeHunterCooldownMs;
    config.spikeHunterLongTermCooldownMs = InpSpikeHunterLongTermCooldownMs;
    config.spikeHunterPushAlerts = InpSpikeHunterPushAlerts;
    config.spikeHunterAlertThrottle = InpSpikeHunterAlertThrottle;
    config.spikeHunterMinConfluence = InpSpikeHunterMinConfluence;

    config.multiAssetProfilerEnabled = InpMultiAssetProfilerEnabled;
    config.derivProfilerEnabled = InpDerivProfilerEnabled;
    config.gridRecoveryEnabled = InpGridRecoveryEnabled;
    config.atrScalpingEnabled = InpATRScalpingEnabled;

    // Mathematical Engines
    config.enableHurstEngine = InpEnableHurstEngine;
    config.hurstLookback = InpHurstLookback;
    config.enableOUProcess = InpEnableOUProcess;
    config.ouLookback = InpOULookback;
    config.enableOFIProxy = InpEnableOFIProxy;
    config.ofiSlowWindow = InpOFISlowWindow;
    config.enableVPINFilter = InpEnableVPINFilter;
    config.vpinExtremeThreshold = InpVPINExtremeThreshold;
    config.vpinNumBuckets = InpVPINNumBuckets;

    // Enterprise Mode
    config.useSignalPipeline = InpUseSignalPipeline;
    config.allowSyntheticOffHours = InpAllowSyntheticOffHours;
    config.minTrendStrength = InpMinTrendStrength;
    config.maxVolatility = InpMaxVolatility;
    config.enableStructureFilter = InpEnableStructureFilter;
    config.enableLiquidityFilter = InpEnableLiquidityFilter;
    config.dormancyStrikeBars = MathMax(1, InpDormancyStrikeBars);
    config.dormancyCooldownMinutes = MathMax(1, InpDormancyCooldownMinutes);
    config.maxPositionsSameBase = InpMaxPositionsSameBase;
    config.enableClusterRiskGovernance = InpEnableClusterRiskGovernance;
    config.enableClusterMutex = InpEnableClusterMutex;
    config.riskMaxConcurrentPerCluster = InpRiskMaxConcurrentPerCluster;
    config.riskMaxClusterExposurePct = InpRiskMaxClusterExposurePct;

    // Portfolio Profit Target
    config.dailyProfitTargetPercent = InpDailyProfitTargetPercent;
    config.profitTrailFactor = InpProfitTrailFactor;
    config.dailyHaltCooldownMinutes = InpDailyHaltCooldownMinutes;

    // Dual-Mode Auto-Switching

    // Symbol Validation
    config.symbolMaxSpreadPoints = InpSymbolMaxSpreadPoints;
    config.symbolMinDailyVolumeLots = InpSymbolMinDailyVolumeLots;
    config.symbolEnableVolumeCheck = InpSymbolEnableVolumeCheck;

    config.logLevel = InpLogLevel;
    config.logVerbosity = InpLogVerbosity;
    config.logDerivFamilyDetection = InpLogDerivFamilyDetection;

    // Curated defaults
    config.useCuratedStrategySet = InpUseCuratedStrategySet;
    config.useSymbolClassProfiles = InpUseSymbolClassProfiles;

    config.enableKalmanMR = InpEnableKalmanMR;
    config.kalmanLambda = InpKalmanLambda;

    config.enableChangepointDetect = InpEnableChangepointDetect;
    config.cpdHazardThreshold = InpCPDHazardThreshold;

    config.enableFourStateRegime = InpEnableFourStateRegime;

    config.enableVolTargeting = InpEnableVolTargeting;
    config.targetVol = InpTargetVol;
    config.volMinScale = InpVolMinScale;
    config.volMaxScale = InpVolMaxScale;


    // Symbol Universe
    config.autoAddChartSymbol = InpAutoAddChartSymbol;

    // Batch 99
    config.equityCurveEmaPeriod = InpEquityCurveEmaPeriod;
    config.equityCurveReductionFactor = InpEquityCurveReductionFactor;
    config.kellyFraction = InpKellyFraction;

    return config;
}

// MAIN EA EVENT HANDLERS

CEAOrchestrator *g_orchestrator = NULL;

// Expert Advisor Initialization
int OnInit()
{
    // Validate inputs first
        if(!ValidateInputs())
        {
            Print("[CRITICAL] Input validation failed - EA will not start");
            return INIT_FAILED;
        }
    
        // L2-001: Initialize global shutdown flag
        g_shuttingDown = false;
    
        // Clamp log level
    if(InpLogLevel < 0 || InpLogLevel > 4)
    {
        PrintFormat("[VALIDATION] Clamping InpLogLevel from %d to range [0, 4]", InpLogLevel);
    }
    g_logLevel = MathMax(0, MathMin(4, InpLogLevel));

    Print("[MULTI-STRATEGY-TESTING-EA] ========================================");
    Print("[MULTI-STRATEGY-TESTING-EA] Testing EA with Complete Test Profile System v2.0");
    Print("[MULTI-STRATEGY-TESTING-EA] ========================================");

    // Validate MetaTrader 5 environment
    if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
    {
        Alert("[CRITICAL] Trading is not allowed in the terminal! Enable AutoTrading!");
        return INIT_FAILED;
    }

    if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
    {
        Alert("[CRITICAL] Trading is not allowed for this EA! Check EA properties!");
        return INIT_FAILED;
    }

    if(AccountInfoDouble(ACCOUNT_BALANCE) < 100.0)
    {
        Alert("[CRITICAL] Insufficient account balance for safe operation!");
        return INIT_FAILED;
    }

    // Apply test profile if enabled - resolve the flags once at init so a bad profile id is reported
    // before any trading starts, and so the matrix is readable beside the boot banner. The actual
    // config is written in BuildOrchestratorConfig, from this same struct; there is no separate
    // "apply flags to inputs" step because `input` variables are read-only in MQL5.
    if(InpTestProfileOverrideAll && InpCompleteTestProfile != TEST_PROFILE_CUSTOM)
    {
        PrintFormat("[TEST-PROFILE] Applying profile: %s (%d)",
                    EnumToString(InpCompleteTestProfile), InpCompleteTestProfile);
        if(ApplyCompleteTestProfile(InpCompleteTestProfile, g_completeFlags, InpIncludeDeadCodeInProfiles))
            LogCompleteActivationMatrix();
    }

    // Create and initialize orchestrator
    SOrchestratorConfig config = BuildOrchestratorConfig();

    // Config version migration warning
    const int CURRENT_CONFIG_VERSION = 109;
    if(config.configVersion < CURRENT_CONFIG_VERSION)
    {
        PrintFormat("[CONFIG-MIGRATION] Config version %d is outdated (current: %d). Consider resetting to curated defaults.",
                    config.configVersion, CURRENT_CONFIG_VERSION);
        if(config.configVersion < 100)
        {
            Print("[CONFIG-MIGRATION] WARNING: Config version < 100 indicates legacy .set file. Manual review recommended.");
        }
    }
    else if(config.configVersion > CURRENT_CONFIG_VERSION)
    {
        PrintFormat("[CONFIG-MIGRATION] Config version %d is newer than EA version %d. Forward compatibility not guaranteed.",
                    config.configVersion, CURRENT_CONFIG_VERSION);
    }

    g_orchestrator = new CEAOrchestrator();
    if(g_orchestrator == NULL)
    {
        Print("[CRITICAL] Failed to allocate EAOrchestrator");
        return INIT_FAILED;
    }

    if(!g_orchestrator.Initialize(config))
    {
        Print("[CRITICAL] EAOrchestrator initialization failed");
        delete g_orchestrator;
        g_orchestrator = NULL;
        return INIT_FAILED;
    }

    // Replay async trade requests from persistence (restart recovery)
    g_orchestrator.GetTradeManager().ReplayAsyncTradeRequests();

    // Restore engine states from open positions
    RestoreEngineStates();

    // Start timer AFTER orchestrator fully initialized
    EventSetTimer(1);

    Print("[MULTI-STRATEGY-TESTING-EA] Initialization complete - EA is READY");
    Print("[MULTI-STRATEGY-TESTING-EA] ========================================");

    return INIT_SUCCEEDED;
}

// Expert Advisor Deinitialization
void OnDeinit(const int reason)
{
    Print("[DEINIT-START] Deinitialization begun | reason=", reason, " (", GetDeInitReasonText(reason), ")");

    // Set global shutdown flag FIRST
    g_shuttingDown = true;

    if(g_orchestrator != NULL)
    {
        g_orchestrator.Shutdown();
        delete g_orchestrator;
        g_orchestrator = NULL;
    }

    // Destroy IndicatorManager BEFORE killing timer
    CIndicatorManager::DestroyInstance();

    CJsonLogger::Shutdown();

    EventKillTimer();

    Print("[MULTI-STRATEGY-TESTING-EA] ========================================");
    Print("[MULTI-STRATEGY-TESTING-EA] Shutdown complete - Memory cleaned");
    Print("[MULTI-STRATEGY-TESTING-EA] ========================================");

    Print("[DEINIT-COMPLETE] Deinitialization finished cleanly | reason=", reason, " (", GetDeInitReasonText(reason), ")");
}

// Timer Handler
void OnTimer()
{
    // Early exit during shutdown
    if(g_shuttingDown)
        return;

    if(g_orchestrator != NULL && g_orchestrator.GetSystemInitialized())
    {
        g_orchestrator.OnTimer();
    }
}

// Expert Advisor Trade Transaction Handler
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
    if(g_shuttingDown)
        return;

    if(g_orchestrator != NULL && g_orchestrator.GetSystemInitialized())
    {
        g_orchestrator.GetTradeManager().ProcessTradeTransaction(trans, request, result);

        // Batch 154: closed-trade feedback - per-strategy attribution/health
        // fan-out plus account-level learners (performance analytics, loss
        // guard, live-authority outcome recording).
        g_orchestrator.ProcessManagerTradeTransactions(trans, request, result);
    }
}

// Expert Advisor Tick Handler
void OnTick()
{
    if(g_orchestrator != NULL && g_orchestrator.GetSystemInitialized())
    {
        g_orchestrator.OnTick();
    }
}

// Chart Event Handler
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
    if(id == CHARTEVENT_OBJECT_CHANGE)
    {
        PrintFormat("[EA-CHART-EVENT] Input parameter changed: object=%s", sparam);
        if(g_orchestrator != NULL && g_orchestrator.GetSystemInitialized())
        {
            g_orchestrator.UpdateRiskParametersFromInputs(
                InpMaxRiskPerTrade, InpMaxDailyRisk, InpMaxPortfolioRisk,
                InpMaxDrawdown, InpDailyLossLimitPercent,
                InpAllowMinLotRoundUp, InpMinLotRiskMultiplier,
                InpEnableCompoundingTiers, InpRiskTier
            );
        }
    }
}

// Helper functions
string GetDeInitReasonText(int reasonCode)
{
    switch(reasonCode)
    {
        case REASON_PROGRAM: return "EA terminated";
        case REASON_REMOVE: return "EA removed from chart";
        case REASON_RECOMPILE: return "EA recompiled";
        case REASON_CHARTCHANGE: return "Symbol or period changed";
        case REASON_CHARTCLOSE: return "Chart closed";
        case REASON_PARAMETERS: return "Input parameters changed";
        case REASON_ACCOUNT: return "Account changed";
        case REASON_TEMPLATE: return "New template applied";
        case REASON_INITFAILED: return "Initialization failed";
        case REASON_CLOSE: return "Terminal closed";
        default: return "Unknown reason";
    }
}

int GetMagicNumberPrefix() { return (int)InpMagicNumber; }

// Restore Engine States (from MultiStrategyAutonomousEA.mq5)
void RestoreEngineStates()
{
    int total = PositionsTotal();
    int foundGridPositions = 0;
    int foundScalpPositions = 0;
    int foundSpikePositions = 0;

    for(int i = 0; i < total; i++)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket == 0) continue;

        if(!PositionSelectByTicket(ticket)) continue;

        string symbol = PositionGetString(POSITION_SYMBOL);
        if(symbol == "") continue;

        long magic = PositionGetInteger(POSITION_MAGIC);
        double volume = PositionGetDouble(POSITION_VOLUME);
        ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
        double priceOpen = PositionGetDouble(POSITION_PRICE_OPEN);
        double sl = PositionGetDouble(POSITION_SL);
        double tp = PositionGetDouble(POSITION_TP);
        datetime timeOpen = (datetime)PositionGetInteger(POSITION_TIME);
        string comment = PositionGetString(POSITION_COMMENT);

        // Batch 152 (T-03): range-based ownership check (the old magic/100 prefix
        // test truncated two digits and never matched InpMagicNumber).
        if(!g_orchestrator.GetTradeManager().IsEAOwnedMagic((long)magic)) continue;

        if(StringFind(comment, "GRID-RECOVERY") >= 0)
        {
            foundGridPositions++;
            PrintFormat("[RESTORE-STATE] Found grid position: %s ticket=%I64u vol=%.2f comment=%s",
                       symbol, ticket, volume, comment);
        }
        else if(StringFind(comment, "SCALP") >= 0 || StringFind(comment, "FASTSCALP") >= 0)
        {
            foundScalpPositions++;
            PrintFormat("[RESTORE-STATE] Found scalp position: %s ticket=%I64u vol=%.2f comment=%s",
                       symbol, ticket, volume, comment);
        }
        else if(StringFind(comment, "SPIKE-HUNT") >= 0)
        {
            foundSpikePositions++;
            PrintFormat("[RESTORE-STATE] Found spike position: %s ticket=%I64u vol=%.2f comment=%s",
                       symbol, ticket, volume, comment);
        }
    }

    PrintFormat("[RESTORE-STATE] Complete: grid=%d scalp=%d spike=%d (engines will rebuild state on next tick)",
                foundGridPositions, foundScalpPositions, foundSpikePositions);
}

// Input Validation (Testing EA subset)
bool ValidateInputs()
{
    // Validates the subset of inputs that are relevant to the Testing EA.
    if(InpMagicNumber <= 0)
    {
        Print("[VALIDATION] InpMagicNumber must be > 0");
        return false;
    }
    if(InpLotSize <= 0)
    {
        Print("[VALIDATION] InpLotSize must be > 0");
        return false;
    }
    if(InpMaxRiskPerTrade <= 0 || InpMaxRiskPerTrade > 100)
    {
        Print("[VALIDATION] InpMaxRiskPerTrade must be in (0, 100]");
        return false;
    }
    return true;
}

