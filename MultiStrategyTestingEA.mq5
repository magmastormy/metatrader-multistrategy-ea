// Standalone Testing EA with Complete Test Profile System
// Load this instead of MultiStrategyAutonomousEA.mq5 for testing
#property copyright "Copyright 2024"
#property link      "https://github.com/"
#property version   "2.000"
#property strict

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

// 3.3 Input Parameters Addition
input group "=== COMPLETE TEST PROFILE SYSTEM ==="
input ENUM_COMPLETE_TEST_PROFILE InpCompleteTestProfile = TEST_PROFILE_CUSTOM;
input bool     InpTestProfileOverrideAll = true;      // If true, profile overrides all individual flags
input bool     InpIncludeDeadCodeInProfiles = false;  // Include dead-code strategies in profiles

input group "=== GENERAL & RISK MANAGEMENT ==="
input long     InpMagicNumber = 123456;
input int      InpConfigVersion = 109;
input double   InpLotSize = 0.1;
input bool     InpUseEnhancedRisk = true;
input double   InpMaxRiskPerTrade = 5.0;
input double   InpMaxDailyRisk = 40.0;

// FINDING 0 (STRATEGY_AUDIT_2026-08-14): use strategy-designed SL/TP instead of
// the generic fallback in the consensus execution path. ENABLED for LIVE operation.
input bool     InpUseStrategyStops = true;
input double   InpMaxPortfolioRisk = 60.0;
input double   InpMaxDrawdown = 15.0;
input double   InpDailyLossLimitPercent = 10.0;
input ENUM_RISK_TIER InpRiskTier = RISK_TIER_MODERATE;
input bool     InpEnableCompoundingTiers = true;
input int      InpCompoundingTierCheckIntervalSec = 60;
input bool     InpEnableSessionWeights = true;
input int      InpSessionDSTOffsetHours = 0;
input bool     InpEnableSkewStepAnalyzer = true;
input bool     InpEnableFamilyWeightMatrix = true;
input bool     InpAllowMinLotRoundUp = false;
input double   InpMinLotRiskMultiplier = 1.0;
input string   InpSymbolsToTrade = "Volatility 25 Index,Volatility 75 Index,Boom 1000 Index,Crash 1000 Index,Jump 25 Index,Jump 75 Index,Step Index,EURUSD,GBPUSD,USDJPY,AUDUSD,XAUUSD,BTCUSD";
input int      InpMinSecondsBetweenTrades = 10;
input int      InpMaxPositionsTotal = 15;
input int      InpMaxPositionsTotalMin = 3;
input int      InpMaxPositionsPerSymbol = 5;
input int      InpMaxPositionsPerSymbolMin = 1;
input int      InpMaxTradeSendsPerCycle = 3;

input group "=== STRATEGY ENABLE / DISABLE ==="
input bool     InpEnableMomentum = true;
input bool     InpEnableTrend = false;
input bool     InpEnableSupportResistance = false;
input bool     InpEnableCandlestick = false;
input bool     InpCandlestickRequireTrend = false;
input bool     InpEnableMeanReversion = false;
input bool     InpEnableVolatilityBreakout = false;
input bool     InpEnableFVGScalper = false;
input bool     InpEnableTurtleSoup = false;
input bool     InpEnableBreakerBlock = false;
input bool     InpEnableNYOpenGap = false;
input bool     InpEnableAsianRangeBreak = false;
input bool     InpEnableStatisticalArbitrage = false;
input double   InpTrendADXNoTrendThreshold = 12.0;
input double   InpSyntheticADXNoTrendThreshold = 10.0;
input bool     InpUseCuratedStrategySet = false;
input bool     InpUseSymbolClassProfiles = false;

input group "=== BATCH 114: KALMAN, REGIME, LIQUIDITY ==="
input bool     InpEnableKalmanMR = false;
input double   InpKalmanLambda = 500.0;
input bool     InpEnableChangepointDetect = false;
input double   InpCPDHazardThreshold = 0.3;
input bool     InpEnableFourStateRegime = false;
input bool     InpEnableVolTargeting = false;
input double   InpTargetVol = 0.15;
input double   InpVolMinScale = 0.2;
input double   InpVolMaxScale = 3.0;
input bool     InpEnableLiquiditySweep = false;
input bool     InpEnableRangeCompression = false;
input bool     InpEnableExitOptimizer = false;

input group "=== EA OPERATING MODE ==="
input ENUM_EA_MODE InpEAMode = EA_MODE_HYBRID;
input bool     InpEnableVisualAnalysis = true;
input int      InpMaxVisualObjects = 500;
input bool     InpStrictEAMode = false;

input group "=== CONSENSUS QUORUM SETTINGS ==="
input CEnterpriseStrategyManager::ENUM_QUORUM_PROFILE InpQuorumProfile = CEnterpriseStrategyManager::QUORUM_BALANCED;
input double   InpQuorumThreshold = 0.60;
input int      InpMinLiveVoters = 2;
input double   InpConsensusConflictDeadband = 0.05;
input double   InpConsensusMinReadyWeightRatio = 0.40;
input double   InpConsensusSupportFloorNewBar = 0.20;
input double   InpConsensusSupportFloorIntrabar = 0.15;
input bool     InpAllowSparseIntrabarSingleVoter = false;
input double   InpSparseIntrabarMinQuality = 0.85;
input double   InpSparseIntrabarMinSupportRatio = 0.40;
input double   InpSparseIntrabarMinReadyCoverage = 0.85;

input group "=== STRATEGY WEIGHTS ==="
input double   InpWeightMomentum = 1.0;
input double   InpWeightTrend = 1.2;
input double   InpWeightSupportResistance = 1.8;
input double   InpWeightCandlestick = 0.8;
input double   InpWeightMeanReversion = 1.8;
input double   InpWeightVolatilityBreakout = 2.0;
input double   InpWeightStatisticalArbitrage = 1.5;
input double   InpWeightFVGScalper = 1.8;
input double   InpWeightTurtleSoup = 1.6;
input double   InpWeightBreakerBlock = 1.7;
input double   InpWeightNYOpenGap = 1.3;
input double   InpWeightAsianRangeBreak = 1.3;
input double   InpWeightLiquiditySweep = 1.9;
input double   InpWeightRangeCompression = 1.7;

input group "=== AI ENGINE SETTINGS ==="
input bool     InpEnableAIMode = false;
input bool     InpEnableNeuralNetwork = false;
input bool     InpEnableTransformer = false;
input bool     InpEnableEnsemble = false;
input bool     InpEnableOnnxAI = false;
input bool     InpEnablePythonBridgeAI = false;
input ENUM_PYTHON_BRIDGE_MODE InpPythonBridgeMode = PYTHON_BRIDGE_OFF;
input string   InpPythonBridgeEndpoint = "http://127.0.0.1:8000";
input int      InpPythonBridgeRequestTimeoutMs = 2000;
input int      InpPythonBridgeHeartbeatTimeoutSec = 30;
input int      InpPythonBridgeMaxReconnectAttempts = 5;
input int      InpPythonBridgeReconnectBackoffMs = 2000;
input bool     InpEnableExternalLLM = false;
input string   InpExternalLLMEndpoint = "http://localhost:11434";
input double   InpAIConfidenceThreshold = 0.70;
input double   InpAIWeightMultiplier = 1.0;
input double   InpAIDrawdownSizingLimit = 0.20;

input group "=== DASHBOARD ==="
input bool     InpDashboardEnabled = true;
input string   InpDashboardEndpoint = "http://127.0.0.1:8765";
input int      InpDashboardPushIntervalSec = 5;
input bool     InpDashboardControlEnabled = false;

input group "=== LIVE AUTHORITY GATE ==="
input bool     InpEnableLiveAuthorityGate = false;
input bool     InpAllowAIWarmStartLive = true;
input bool     InpAllowHybridAIStandalone = true;
input double   InpAIStandaloneMinConfidence = 0.65;
input double   InpAIStandaloneRelaxedConfidence = 0.60;
input int      InpHybridGateRelaxAfterCycles = 5;
input int      InpAuthorityMinSamples = 12;
input int      InpAuthorityTrialHorizonSeconds = 900;
input int      InpAuthorityMaxTrackedTrials = 256;
input double   InpAuthorityMinExpectancyR = 0.03;
input double   InpAuthorityMinProfitFactor = 1.10;
input double   InpAuthorityMinCostScore = 0.50;
input double   InpAuthorityMinReadinessScore = 0.52;
input double   InpAuthorityMinContextScore = 0.48;
input double   InpAIBootstrapRiskMultiplier = 0.50;
input double   InpAIPromotedRiskMultiplier = 1.00;
input double   InpNonAIPromotedRiskMultiplier = 0.65;

input group "=== NN ATTRIBUTION ==="
input bool     InpEnableNNAttributionDiagnostics = false;
input bool     InpRunNNAttributionSelfTest = false;

input group "=== RUNTIME CADENCE & INTRABAR ==="
input bool     InpEnableHybridCadence = true;
input int      InpIntrabarScanSeconds = 5;
input bool     InpIntrabarChartSymbolOnly = false;
input bool     InpIntrabarDynamicQuorumEnabled = true;
input double   InpPipelineMinConfidence = 0.55;
input double   InpIntrabarSingleVoterMinConfidence = 0.95;
input double   InpSyntheticLeanSparseIntrabarMinQuality = 0.85;
input double   InpSyntheticLeanIntrabarSingleVoterMinConfidence = 0.95;
input double   InpPipelineIntrabarConfidenceCap = 0.05;
input bool     InpPipelineEnableRegimeCostGate = true;
input double   InpPipelineMaxSpreadToAtrRatio = 0.50;
input int      InpPipelineSpreadShockCooldownSec = 90;
input double   InpPipelineLateEntryZScoreLimit = 4.00;
input double   InpAtrCrisisRatioThreshold = 5.0;
input double   InpAtrCrisisRatioThresholdSynthetic = 15.0;
input double   InpAtrCrisisRatioThresholdVolatility = 10.0;
input double   InpAtrCrisisRatioThresholdDefault = 8.0;
input double   InpHardSpreadCutoffPoints = 200.0;
input int      InpDeadlockAttributionIntervalSec = 60;
input int      InpHeartbeatInterval = 60;
input bool     InpEnableMomentumScalping = false;
input int      InpMomentumScalpCooldownSeconds = 20;
input ENUM_TIMEFRAMES InpMomentumScalpTimeframe = PERIOD_M5;
input ENUM_TIMEFRAMES InpCandlestickIntrabarTimeframe = PERIOD_M5;
input ENUM_INTRABAR_POLICY InpIntrabarEligibilityMomentum = INTRABAR_POLICY_LIVE;
input ENUM_INTRABAR_POLICY InpIntrabarEligibilityTrend = INTRABAR_POLICY_LIVE;
input ENUM_INTRABAR_POLICY InpIntrabarEligibilitySupportResistance = INTRABAR_POLICY_LIVE;
input ENUM_INTRABAR_POLICY InpIntrabarEligibilityCandlestick = INTRABAR_POLICY_LIVE;
input ENUM_INTRABAR_POLICY InpIntrabarEligibilityMeanReversion = INTRABAR_POLICY_LIVE;
input ENUM_INTRABAR_POLICY InpIntrabarEligibilityVolatilityBreakout = INTRABAR_POLICY_LIVE;
input ENUM_INTRABAR_POLICY InpIntrabarEligibilityNeuralNetworkAI = INTRABAR_POLICY_LIVE;
input ENUM_INTRABAR_POLICY InpIntrabarEligibilityTransformerAI = INTRABAR_POLICY_LIVE;
input ENUM_INTRABAR_POLICY InpIntrabarEligibilityEnsembleAI = INTRABAR_POLICY_LIVE;
input ENUM_INTRABAR_POLICY InpIntrabarEligibilityOnnxAI = INTRABAR_POLICY_LIVE;
input int      InpMaxIntrabarSymbolsPerCycle = 6;
input int      InpMaxSignalEvaluationsPerCycle = 8;
input int      InpIntrabarBackoffMaxSeconds = 60;
input int      InpReadinessReuseTtlSeconds = 60;
input bool     InpEnableNNOnlineTraining = true;
input bool     InpEnableNNWeightMutation = false;
input bool     InpEnableNNPseudoLabeling = true;
input int      InpNNPseudoLabelBarsAhead = 10;
input int      InpNNSampleIntervalSeconds = 15;
input int      InpNNCheckpointEveryLabeled = 3;

input group "=== SIGNAL VALIDATOR ==="
input int      InpValidatorNewBarMinConfluence = 1;
input double   InpValidatorNewBarMinQuality = 0.68;
input double   InpValidatorNewBarMinConfidence = 0.55;
input int      InpValidatorIntrabarMinConfluence = 1;
input double   InpValidatorIntrabarMinQuality = 0.70;
input double   InpValidatorIntrabarMinConfidence = 0.60;

input group "=== EXECUTION SAFETY & LIFECYCLE ==="
input ENUM_ORDER_TYPE_FILLING InpOrderFillingMode = ORDER_FILLING_IOC;
input int      InpTradeSlippagePoints = 50;
input double   InpMaxEntrySpreadPoints = 15000.0;
input double   InpMaxEntryDriftPoints = 80.0;
input int      InpProtectiveModifyCooldownSec = 5;
input bool     InpEnableSignalReversalExit = true;
input double   InpSignalReversalMinConfidence = 0.58;
input bool     InpSignalReversalProfitGuard = true;
input double   InpSignalReversalMinLossR = 0.25;
input double   InpSignalReversalMaxLossR = 0.82;
input int      InpSignalReversalMinTimeSec = 45;
input bool     InpEnableStructuralInvalidation = true;
input bool     InpEnablePositionLifecycleManager = true;
input double   InpLifecycleBreakevenBufferPoints = 50.0;
input double   InpLifecycleTrailingDistancePoints = 150.0;
input double   InpLifecycleTrailingStepPoints = 30.0;
input bool     InpLifecycleUseATRTrailing = false;
input double   InpLifecycleATRMultiplier = 1.5;

input group "=== MAX HOLD TIME ==="
input bool     InpEnableMaxHoldTime = true;
input int      InpMaxHoldHoursIntraday = 24;
input int      InpMaxHoldHoursSwing = 120;
input bool     InpMaxHoldOnlyIfLoss = true;

input group "=== EMERGENCY PROTOCOLS ==="
input bool     InpEmergencyFlattenAllAccountPositions = false; // Batch 168: opt-in account-wide flatten
input int      InpUnprotectedRemediationIntervalSec = 15;
input int      InpUnprotectedMaxRestoreAttempts = 3;
input bool     InpCloseUnprotectedOnRemediationFailure = true;
input double   InpSyntheticSpikeVelocityMultiplier = 3.0;
input int      InpSyntheticSpikePauseSeconds = 30;

input group "=== FAST SCALP ENGINE ==="
input bool     InpEnableScalpEngine = true;
input bool     InpScalpAsyncMode = false;
input uint     InpScalpMaxLatencyMs = 500;

input group "=== DYNAMIC SLIPPAGE ==="
input bool     InpEnableDynamicSlippage = true;
input double   InpDynamicSlippageAtrPercent = 0.20;
input int      InpDynamicSlippageMinPoints = 10;
input int      InpDynamicSlippageMaxMultiplier = 10;
input int      InpDynamicSlippageAtrPeriod = 14;

input group "=== SPIKE DETECTION ==="
input int      InpSpikeConfirmWindows = 2;

input group "=== SKEW STEP ANALYZER ==="
input int      InpSkewStepBufferSize = 200;
input double   InpSkewStepCalmThreshold = 0.80;
input double   InpSkewStepSmallThreshold = 0.2;
input double   InpSkewStepLargeThreshold = 0.5;

input group "=== SPIKE HUNTER ENGINE ==="
input bool     InpSpikeHunterEnabled = false;
input double   InpSpikeHunterVelocityMult = 1.8;
input int      InpSpikeHunterMinConsecTicks = 8;
input int      InpSpikeHunterConsecWindowMs = 60000;
input double   InpSpikeHunterATRCompression = 0.80;
input double   InpSpikeHunterSLAtrMult = 1.5;
input double   InpSpikeHunterTPAtrMult = 3.0;
input int      InpSpikeHunterMaxPositions = 3;
input int      InpSpikeHunterCooldownMs = 60000;
input int      InpSpikeHunterLongTermCooldownMs = 60000;
input bool     InpSpikeHunterPushAlerts = true;
input int      InpSpikeHunterAlertThrottle = 120;
input int      InpSpikeHunterMinConfluence = 2;

input group "=== MULTI-ASSET PROFILER ==="
input bool     InpMultiAssetProfilerEnabled = true;
input bool     InpDerivProfilerEnabled = true;
input bool     InpGridRecoveryEnabled = true;
input bool     InpATRScalpingEnabled = true;

input group "=== MATHEMATICAL ENGINES ==="
input bool     InpEnableHurstEngine = true;
input int      InpHurstLookback = 300;
input bool     InpEnableOUProcess = true;
input int      InpOULookback = 100;
input bool     InpEnableOFIProxy = true;
input int      InpOFISlowWindow = 100;
input bool     InpEnableVPINFilter = true;
input double   InpVPINExtremeThreshold = 0.7;
input int      InpVPINNumBuckets = 50;

input group "=== INSTITUTIONAL TA ==="
input bool     InpEnableVWAPEngine = false;
input bool     InpEnableVolumeProfile = false;
input bool     InpEnableCVDEngine = false;
input int      InpVWAPMinPeriodBars = 30;
input double   InpVWAPBand1 = 1.0;
input double   InpVWAPBand2 = 1.5;
input double   InpVWAPBand3 = 2.0;
input int      InpVPLookback = 20;
input int      InpVPResolution = 20;
input int      InpCVDDivergenceLookback = 30;

input group "=== ENTERPRISE MODE & CLUSTER GOVERNANCE ==="
input bool     InpUseSignalPipeline = true;
input bool     InpAllowSyntheticOffHours = true;
input double   InpMinTrendStrength = 50.0;
input double   InpMaxVolatility = 3.0;
input bool     InpEnableStructureFilter = true;
input bool     InpEnableLiquidityFilter = true;
input int      InpDormancyStrikeBars = 3;
input int      InpDormancyCooldownMinutes = 30;
input int      InpPortfolioMaxPositionsPerSymbol = 3;
input int      InpMaxPositionsSameBase = 3;
input bool     InpEnableClusterRiskGovernance = true;
input bool     InpEnableClusterMutex = true;
input int      InpRiskMaxConcurrentPerCluster = 3;
input double   InpRiskMaxClusterExposurePct = 5.0;

input group "=== PORTFOLIO PROFIT TARGET ==="
input double   InpDailyProfitTargetPercent = 2.0;
input double   InpProfitTrailFactor = 0.7;
input double   InpProfitTargetHardFloorRatio = 0.50;
input int      InpDailyHaltCooldownMinutes = 30;

//--- Dual-Mode Auto-Switching
input bool     InpEnableAutoModeSwitch = false;
input double   InpConservativeBaseRiskPct = 1.0;
input double   InpAggressiveBaseRiskPct = 3.0;
input double   InpModeSwitchDrawdownPct = 5.0;
input int      InpModeSwitchWinStreak = 5;

//--- Symbol Validation
input long     InpSymbolMaxSpreadPoints = 1500;
input long     InpSymbolMinDailyVolumeLots = 1000;
input bool     InpSymbolEnableVolumeCheck = true;

input int      InpLogLevel = 1;
input int      InpLogVerbosity = 3;
input bool     InpLogDerivFamilyDetection = true;

//--- Symbol Universe
input bool     InpAutoAddChartSymbol = true;

//--- Batch 99
input int      InpEquityCurveEmaPeriod = 20;
input double   InpEquityCurveReductionFactor = 0.50;
input double   InpKellyFraction = 0.25;

struct SCompleteComponentFlags
{
    // Registry Strategies (19) - executed via ProcessTradingLogic() -> Pipeline -> CUnifiedRiskManager
    bool momentum;
    bool trend;
    bool supportResistance;
    bool unifiedICT;
    bool candlestick;
    bool unicornModel;
    bool powerOfThree;
    bool meanReversion;
    bool volatilityBreakout;
    bool statisticalArbitrage;
    bool fvgScalper;
    bool turtleSoup;
    bool breakerBlock;
    bool nyOpenGap;
    bool asianRangeBreak;
    bool liquiditySweep;
    bool rangeCompression;

    // AI Strategies (4) - registry
    bool neuralNetwork;
    bool transformer;
    bool ensemble;
    bool onnxAI;

    // Independent Engines (4) - executed in OnTick() directly, bypassing consensus pipeline
    bool fastScalpEngine;
    bool spikeHunterEngine;
    bool gridRecoveryEngine;
    bool atrScalpingEngine;

    // Dead Code (2) - initialized per-symbol, NEVER called
    bool enableHurstEngine;
    bool enableOUProcess;

    // AI Mode master switch
    bool aiModeEnabled;

    //--- Default constructor: everything disabled
    SCompleteComponentFlags()
    {
        momentum = false; trend = false; supportResistance = false;
        unifiedICT = false; candlestick = false; unicornModel = false;
        powerOfThree = false; meanReversion = false; volatilityBreakout = false;
        statisticalArbitrage = false; fvgScalper = false; turtleSoup = false;
        breakerBlock = false; nyOpenGap = false; asianRangeBreak = false;
        liquiditySweep = false; rangeCompression = false;
        neuralNetwork = false; transformer = false; ensemble = false; onnxAI = false;
        fastScalpEngine = false; spikeHunterEngine = false;
        gridRecoveryEngine = false; atrScalpingEngine = false;
        enableHurstEngine = false; enableOUProcess = false;
        aiModeEnabled = false;
    }
};

// Global flags instance
SCompleteComponentFlags g_completeFlags;

// PROFILE APPLICATION LOGIC

// 3.5 Helper functions for flag groups (replaced C++ lambdas for MQL5 compatibility)
void SetIndicatorFlags(SCompleteComponentFlags &flags, bool m, bool t, bool sr, bool ict, bool cd, bool um, bool pot,
                        bool mr, bool vb, bool sa, bool fvg, bool ts, bool bb,
                        bool ny, bool ar, bool ls, bool rc)
{
    flags.momentum = m; flags.trend = t; flags.supportResistance = sr;
    flags.unifiedICT = ict; flags.candlestick = cd; flags.unicornModel = um;
    flags.powerOfThree = pot; flags.meanReversion = mr; flags.volatilityBreakout = vb;
    flags.statisticalArbitrage = sa; flags.fvgScalper = fvg; flags.turtleSoup = ts;
    flags.breakerBlock = bb; flags.nyOpenGap = ny; flags.asianRangeBreak = ar;
    flags.liquiditySweep = ls; flags.rangeCompression = rc;
}

void SetAIFlags(SCompleteComponentFlags &flags, bool nn, bool tf, bool ens, bool onnx)
{
    flags.neuralNetwork = nn; flags.transformer = tf;
    flags.ensemble = ens; flags.onnxAI = onnx;
    flags.aiModeEnabled = (nn || tf || ens || onnx);
}

void SetEngineFlags(SCompleteComponentFlags &flags, bool fs, bool sh, bool gr, bool atr)
{
    flags.fastScalpEngine = fs; flags.spikeHunterEngine = sh;
    flags.gridRecoveryEngine = gr; flags.atrScalpingEngine = atr;
}

void SetDeadFlags(SCompleteComponentFlags &flags, bool hurst, bool ou)
{
    flags.enableHurstEngine = hurst; flags.enableOUProcess = ou;
}

// 3.5 Profile Application Logic
void ApplyCompleteTestProfile(ENUM_COMPLETE_TEST_PROFILE profile, SCompleteComponentFlags &flags, bool includeDead = false)
{
    // Reset all to false first
    flags = SCompleteComponentFlags();

    bool includeDeadCode = includeDead;

    switch(profile)
    {
        //--- Special / Utility
        case TEST_PROFILE_CUSTOM:
            // No-op: keep manual input flags
            return;

        case TEST_PROFILE_DISABLE_ALL:
            // All flags already false from reset
            break;

        //--- Single Indicator Strategies
        case TEST_PROFILE_SINGLE_MOMENTUM:
            SetIndicatorFlags(flags, true, false, false, false, false, false, false,
                   false, false, false, false, false, false,
                   false, false, false, false);
            break;

        case TEST_PROFILE_SINGLE_TREND:
            SetIndicatorFlags(flags, false, true, false, false, false, false, false,
                   false, false, false, false, false, false,
                   false, false, false, false);
            break;

        case TEST_PROFILE_SINGLE_SR:
            SetIndicatorFlags(flags, false, false, true, false, false, false, false,
                   false, false, false, false, false, false,
                   false, false, false, false);
            break;

        case TEST_PROFILE_SINGLE_ICT:
            SetIndicatorFlags(flags, false, false, false, true, false, false, false,
                   false, false, false, false, false, false,
                   false, false, false, false);
            break;

        case TEST_PROFILE_SINGLE_CANDLE:
            SetIndicatorFlags(flags, false, false, false, false, true, false, false,
                   false, false, false, false, false, false,
                   false, false, false, false);
            break;

        case TEST_PROFILE_SINGLE_UNICORN:
            SetIndicatorFlags(flags, false, false, false, false, false, true, false,
                   false, false, false, false, false, false,
                   false, false, false, false);
            break;

        case TEST_PROFILE_SINGLE_POT:
            SetIndicatorFlags(flags, false, false, false, false, false, false, true,
                   false, false, false, false, false, false,
                   false, false, false, false);
            break;

        case TEST_PROFILE_SINGLE_MR:
            SetIndicatorFlags(flags, false, false, false, false, false, false, false,
                   true, false, false, false, false, false,
                   false, false, false, false);
            break;

        case TEST_PROFILE_SINGLE_VB:
            SetIndicatorFlags(flags, false, false, false, false, false, false, false,
                   false, true, false, false, false, false,
                   false, false, false, false);
            break;

        case TEST_PROFILE_SINGLE_STATARB:
            SetIndicatorFlags(flags, false, false, false, false, false, false, false,
                   false, false, true, false, false, false,
                   false, false, false, false);
            break;

        case TEST_PROFILE_SINGLE_FVG:
            SetIndicatorFlags(flags, false, false, false, false, false, false, false,
                   false, false, false, true, false, false,
                   false, false, false, false);
            break;

        case TEST_PROFILE_SINGLE_TURTLE:
            SetIndicatorFlags(flags, false, false, false, false, false, false, false,
                   false, false, false, false, true, false,
                   false, false, false, false);
            break;

        case TEST_PROFILE_SINGLE_BREAKER:
            SetIndicatorFlags(flags, false, false, false, false, false, false, false,
                   false, false, false, false, false, true,
                   false, false, false, false);
            break;

        case TEST_PROFILE_SINGLE_NYGAP:
            SetIndicatorFlags(flags, false, false, false, false, false, false, false,
                   false, false, false, false, false, false,
                   true, false, false, false);
            break;

        case TEST_PROFILE_SINGLE_ASIAN:
            SetIndicatorFlags(flags, false, false, false, false, false, false, false,
                   false, false, false, false, false, false,
                   false, true, false, false);
            break;

        case TEST_PROFILE_SINGLE_LIQSWEEP:
            SetIndicatorFlags(flags, false, false, false, false, false, false, false,
                   false, false, false, false, false, false,
                   false, false, true, false);
            break;

        case TEST_PROFILE_SINGLE_RANGECOMP:
            SetIndicatorFlags(flags, false, false, false, false, false, false, false,
                   false, false, false, false, false, false,
                   false, false, false, true);
            break;

        //--- Single AI Strategies
        case TEST_PROFILE_SINGLE_NN:
            SetAIFlags(flags, true, false, false, false);
            break;

        case TEST_PROFILE_SINGLE_TRANSF:
            SetAIFlags(flags, false, true, false, false);
            break;

        case TEST_PROFILE_SINGLE_ENS:
            SetAIFlags(flags, false, false, true, false);
            break;

        case TEST_PROFILE_SINGLE_ONNX:
            SetAIFlags(flags, false, false, false, true);
            break;

        //--- Single Independent Engines
        case TEST_PROFILE_SINGLE_FASTSCALP:
            SetEngineFlags(flags, true, false, false, false);
            break;

        case TEST_PROFILE_SINGLE_SPIKEHUNTER:
            SetEngineFlags(flags, false, true, false, false);
            break;

        case TEST_PROFILE_SINGLE_GRIDRECOVERY:
            SetEngineFlags(flags, false, false, true, false);
            break;

        case TEST_PROFILE_SINGLE_ATRSCALP:
            SetEngineFlags(flags, false, false, false, true);
            break;

        //--- Curated Strategy Families
        case TEST_PROFILE_TREND_SUITE:
            SetIndicatorFlags(flags, true, true, true, false, false, false, false,
                   false, true, false, false, false, false,
                   false, false, false, false);
            break;

        case TEST_PROFILE_MEANREV_SUITE:
            SetIndicatorFlags(flags, false, false, false, false, false, false, false,
                   true, false, false, true, true, true,
                   false, false, false, false);
            break;

        case TEST_PROFILE_ICT_SMC_SUITE:
            SetIndicatorFlags(flags, false, false, false, true, true, true, true,
                   false, false, false, false, false, false,
                   false, false, false, false);
            break;

        case TEST_PROFILE_SESSION_SUITE:
            SetIndicatorFlags(flags, false, false, false, false, false, false, false,
                   false, false, false, false, false, false,
                   true, true, true, true);
            break;

        case TEST_PROFILE_SCALP_ENGINES_SUITE:
            SetEngineFlags(flags, true, true, true, true);
            break;

        //--- Aggregate Modes
        case TEST_PROFILE_ALL_INDICATORS:
            SetIndicatorFlags(flags, true, true, true, true, true, true, true,
                   true, true, true, true, true, true,
                   true, true, true, true);
            break;

        case TEST_PROFILE_ALL_INDICATORS_LIVE:
            SetIndicatorFlags(flags, true, true, true, true, true, true, true,
                   true, true, true, true, true, true,
                   true, true, true, true);
            // Note: Live mode handled by EA operating mode input
            break;

        case TEST_PROFILE_AI_SUITE:
            SetAIFlags(flags, true, true, true, true);
            break;

        case TEST_PROFILE_ALL_ENGINES:
            SetEngineFlags(flags, true, true, true, true);
            break;

        case TEST_PROFILE_ALL_ENGINES_SAFE:
            SetEngineFlags(flags, true, true, true, true);
            // Conservative risk caps would be applied in ApplyFlagsToInputs
            break;

        //--- Full System Modes
        case TEST_PROFILE_FULL_INDICATORS:
            SetIndicatorFlags(flags, true, true, true, true, true, true, true,
                   true, true, true, true, true, true,
                   true, true, true, true);
            break;

        case TEST_PROFILE_FULL_HYBRID:
            SetIndicatorFlags(flags, true, true, true, true, true, true, true,
                   true, true, true, true, true, true,
                   true, true, true, true);
            SetAIFlags(flags, true, true, true, true);
            break;

        case TEST_PROFILE_FULL_WITH_ENGINES:
            SetIndicatorFlags(flags, true, true, true, true, true, true, true,
                   true, true, true, true, true, true,
                   true, true, true, true);
            SetAIFlags(flags, true, true, true, true);
            SetEngineFlags(flags, true, true, true, true);
            break;

        case TEST_PROFILE_FULL_WITH_ENGINES_SAFE:
            SetIndicatorFlags(flags, true, true, true, true, true, true, true,
                   true, true, true, true, true, true,
                   true, true, true, true);
            SetAIFlags(flags, true, true, true, true);
            SetEngineFlags(flags, true, true, true, true);
            // Safety caps applied in ApplyFlagsToInputs
            break;

        case TEST_PROFILE_EVERYTHING:
            SetIndicatorFlags(flags, true, true, true, true, true, true, true,
                   true, true, true, true, true, true,
                   true, true, true, true);
            SetAIFlags(flags, true, true, true, true);
            SetEngineFlags(flags, true, true, true, true);
            SetDeadFlags(flags, includeDeadCode, includeDeadCode);
            break;
    }

    // Handle dead code inclusion for all profiles if requested
    if(includeDeadCode && profile != TEST_PROFILE_CUSTOM && profile != TEST_PROFILE_DISABLE_ALL)
    {
        SetDeadFlags(flags, true, true);
    }
}

// 3.5 Apply Flags to Inputs - Maps component flags to actual EA input parameters
void ApplyFlagsToInputs(const SCompleteComponentFlags &flags)
{
    // Note: In MQL5, input parameters are const at runtime.
    // This function logs the effective configuration for verification.
    // Actual input override requires InpTestProfileOverrideAll = true
    // and the orchestrator config to respect these flags.

    Print("[TEST-PROFILE] ========================================");
    Print("[TEST-PROFILE] Effective Component Configuration:");
    Print("[TEST-PROFILE] ========================================");

    // Registry Strategies
    PrintFormat("[TEST-PROFILE] Momentum: %s", flags.momentum ? "ON" : "OFF");
    PrintFormat("[TEST-PROFILE] Trend: %s", flags.trend ? "ON" : "OFF");
    PrintFormat("[TEST-PROFILE] Support/Resistance: %s", flags.supportResistance ? "ON" : "OFF");
    PrintFormat("[TEST-PROFILE] Unified ICT: %s", flags.unifiedICT ? "ON" : "OFF");
    PrintFormat("[TEST-PROFILE] Candlestick: %s", flags.candlestick ? "ON" : "OFF");
    PrintFormat("[TEST-PROFILE] Unicorn Model: %s", flags.unicornModel ? "ON" : "OFF");
    PrintFormat("[TEST-PROFILE] Power of Three: %s", flags.powerOfThree ? "ON" : "OFF");
    PrintFormat("[TEST-PROFILE] Mean Reversion: %s", flags.meanReversion ? "ON" : "OFF");
    PrintFormat("[TEST-PROFILE] Volatility Breakout: %s", flags.volatilityBreakout ? "ON" : "OFF");
    PrintFormat("[TEST-PROFILE] Statistical Arbitrage: %s", flags.statisticalArbitrage ? "ON" : "OFF");
    PrintFormat("[TEST-PROFILE] FVG Scalper: %s", flags.fvgScalper ? "ON" : "OFF");
    PrintFormat("[TEST-PROFILE] Turtle Soup: %s", flags.turtleSoup ? "ON" : "OFF");
    PrintFormat("[TEST-PROFILE] Breaker Block: %s", flags.breakerBlock ? "ON" : "OFF");
    PrintFormat("[TEST-PROFILE] NY Open Gap: %s", flags.nyOpenGap ? "ON" : "OFF");
    PrintFormat("[TEST-PROFILE] Asian Range Break: %s", flags.asianRangeBreak ? "ON" : "OFF");
    PrintFormat("[TEST-PROFILE] Liquidity Sweep: %s", flags.liquiditySweep ? "ON" : "OFF");
    PrintFormat("[TEST-PROFILE] Range Compression: %s", flags.rangeCompression ? "ON" : "OFF");

    // AI Strategies
    PrintFormat("[TEST-PROFILE] Neural Network AI: %s", flags.neuralNetwork ? "ON" : "OFF");
    PrintFormat("[TEST-PROFILE] Transformer AI: %s", flags.transformer ? "ON" : "OFF");
    PrintFormat("[TEST-PROFILE] Ensemble AI: %s", flags.ensemble ? "ON" : "OFF");
    PrintFormat("[TEST-PROFILE] ONNX AI: %s", flags.onnxAI ? "ON" : "OFF");
    PrintFormat("[TEST-PROFILE] AI Mode Enabled: %s", flags.aiModeEnabled ? "ON" : "OFF");

    // Independent Engines
    PrintFormat("[TEST-PROFILE] Fast Scalp Engine: %s", flags.fastScalpEngine ? "ON" : "OFF");
    PrintFormat("[TEST-PROFILE] Spike Hunter Engine: %s", flags.spikeHunterEngine ? "ON" : "OFF");
    PrintFormat("[TEST-PROFILE] Grid Recovery Engine: %s", flags.gridRecoveryEngine ? "ON" : "OFF");
    PrintFormat("[TEST-PROFILE] ATR Scalping Engine: %s", flags.atrScalpingEngine ? "ON" : "OFF");

    if(InpIncludeDeadCodeInProfiles)
    {
        PrintFormat("[TEST-PROFILE] Hurst Engine (dead): %s", flags.enableHurstEngine ? "ON" : "OFF");
        PrintFormat("[TEST-PROFILE] OU Process (dead): %s", flags.enableOUProcess ? "ON" : "OFF");
    }

    Print("[TEST-PROFILE] ========================================");
}

// 3.6 Enhanced: Complete Activation Matrix Visualization
void LogCompleteActivationMatrix()
{
    Print("[ACTIVATION-MATRIX] ========================================");
    Print("[ACTIVATION-MATRIX] COMPLETE COMPONENT ACTIVATION MATRIX");
    Print("[ACTIVATION-MATRIX] ========================================");

    // Registry Indicators
    string indNames[19] = {
        "Momentum", "Trend", "Support/Resistance", "Unified ICT",
        "Candlestick", "Unicorn Model", "Power of Three", "Mean Reversion",
        "Volatility Breakout", "Statistical Arbitrage", "FVG Scalper",
        "Turtle Soup", "Breaker Block", "NY Open Gap", "Asian Range Break",
        "Liquidity Sweep", "Range Compression", "Hurst Engine", "OU Process"
    };

    bool indActive[19] = {
        g_completeFlags.momentum, g_completeFlags.trend, g_completeFlags.supportResistance,
        g_completeFlags.unifiedICT, g_completeFlags.candlestick, g_completeFlags.unicornModel,
        g_completeFlags.powerOfThree, g_completeFlags.meanReversion, g_completeFlags.volatilityBreakout,
        g_completeFlags.statisticalArbitrage, g_completeFlags.fvgScalper, g_completeFlags.turtleSoup,
        g_completeFlags.breakerBlock, g_completeFlags.nyOpenGap, g_completeFlags.asianRangeBreak,
        g_completeFlags.liquiditySweep, g_completeFlags.rangeCompression,
        g_completeFlags.enableHurstEngine, g_completeFlags.enableOUProcess
    };

    int activeCount = 0;
    for(int i = 0; i < 19; i++)
    {
        string status = indActive[i] ? "[ACTIVE]" : "[OFF]";
        string deadTag = (i >= 17) ? " (DEAD)" : "";
        if(indActive[i]) activeCount++;
        PrintFormat("[ACTIVATION-MATRIX] %2d. %-25s %s%s", i+1, indNames[i], status, deadTag);
    }
    PrintFormat("[ACTIVATION-MATRIX] Active Indicators: %d/19", activeCount);

    // AI Strategies
    string aiNames[4] = {"Neural Network", "Transformer", "Ensemble", "ONNX"};
    bool aiActive[4] = {g_completeFlags.neuralNetwork, g_completeFlags.transformer,
                        g_completeFlags.ensemble, g_completeFlags.onnxAI};

    int aiCount = 0;
    for(int i = 0; i < 4; i++)
    {
        string status = aiActive[i] ? "[ACTIVE]" : "[OFF]";
        bool active = aiActive[i];
        if(active) aiCount++;
        PrintFormat("[ACTIVATION-MATRIX] AI:  %-20s %s", aiNames[i], status);
    }
    PrintFormat("[ACTIVATION-MATRIX] Active AI Modes: %d/4 (Master: %s)", aiCount,
                g_completeFlags.aiModeEnabled ? "ON" : "OFF");

    // Independent Engines
    string engNames[4] = {"Fast Scalp", "Spike Hunter", "Grid Recovery", "ATR Scalp"};
    string engRisk[4] = {"HIGH", "HIGH", "VERY HIGH", "HIGH"};
    bool engActive[4] = {g_completeFlags.fastScalpEngine, g_completeFlags.spikeHunterEngine,
                         g_completeFlags.gridRecoveryEngine, g_completeFlags.atrScalpingEngine};

    int engCount = 0;
    for(int i = 0; i < 4; i++)
    {
        string status = engActive[i] ? "[ACTIVE]" : "[OFF]";
        if(engActive[i]) engCount++;
        PrintFormat("[ACTIVATION-MATRIX] ENG: %-20s %s (Risk: %s)", engNames[i], status, engRisk[i]);
    }
    PrintFormat("[ACTIVATION-MATRIX] Active Engines: %d/4", engCount);

    Print("[ACTIVATION-MATRIX] ========================================");
}

// 5. Per-Symbol Effective Component Report
void LogPerSymbolEffectiveComponents()
{
    string symbols[] = {"Volatility 25 Index", "Volatility 75 Index", "Boom 1000 Index",
                        "Crash 1000 Index", "Jump 25 Index", "Jump 75 Index",
                        "Step Index", "EURUSD", "GBPUSD", "USDJPY", "AUDUSD", "XAUUSD", "BTCUSD"};
    int symbolCount = ArraySize(symbols);

    Print("[PER-SYMBOL-REPORT] ========================================");
    Print("[PER-SYMBOL-REPORT] PER-SYMBOL EFFECTIVE COMPONENT REPORT");
    Print("[PER-SYMBOL-REPORT] ========================================");

    for(int i = 0; i < symbolCount; i++)
    {
        string sym = symbols[i];
        bool isSynthetic = IsSyntheticIndexSymbolName(sym);

        // Engine eligibility per symbol
        bool spikeActive = g_completeFlags.spikeHunterEngine && isSynthetic;
        bool gridActive = g_completeFlags.gridRecoveryEngine && isSynthetic;
        bool atrActive = g_completeFlags.atrScalpingEngine;
        bool scalpActive = g_completeFlags.fastScalpEngine;

        int count = 0;
        string activeList = "";

        // Registry strategies active for this symbol
        string indNames[19] = {
            "Momentum", "Trend", "SR", "ICT", "Candle", "Unicorn", "POT",
            "MR", "VB", "StatArb", "FVG", "Turtle", "Breaker", "NYGap",
            "Asian", "LiqSweep", "RangeComp", "Hurst", "OU"
        };

        bool indActive[19] = {
            g_completeFlags.momentum, g_completeFlags.trend, g_completeFlags.supportResistance,
            g_completeFlags.unifiedICT, g_completeFlags.candlestick, g_completeFlags.unicornModel,
            g_completeFlags.powerOfThree, g_completeFlags.meanReversion, g_completeFlags.volatilityBreakout,
            g_completeFlags.statisticalArbitrage, g_completeFlags.fvgScalper, g_completeFlags.turtleSoup,
            g_completeFlags.breakerBlock, g_completeFlags.nyOpenGap, g_completeFlags.asianRangeBreak,
            g_completeFlags.liquiditySweep, g_completeFlags.rangeCompression,
            g_completeFlags.enableHurstEngine, g_completeFlags.enableOUProcess
        };

        for(int j = 0; j < 19; j++)
        {
            if(indActive[j] && (j < 17 || InpIncludeDeadCodeInProfiles))
            {
                if(StringLen(activeList) > 0) activeList += ", ";
                activeList += indNames[j];
                count++;
            }
        }

        // Add engines
        if(scalpActive) { if(StringLen(activeList) > 0) activeList += ", "; activeList += "FastScalp"; count++; }
        if(spikeActive) { if(StringLen(activeList) > 0) activeList += ", "; activeList += "SpikeHunter"; count++; }
        if(gridActive) { if(StringLen(activeList) > 0) activeList += ", "; activeList += "GridRecovery"; count++; }
        if(atrActive) { if(StringLen(activeList) > 0) activeList += ", "; activeList += "ATRScalp"; count++; }

        // AI
        if(g_completeFlags.neuralNetwork) { if(StringLen(activeList) > 0) activeList += ", "; activeList += "NN"; count++; }
        if(g_completeFlags.transformer) { if(StringLen(activeList) > 0) activeList += ", "; activeList += "Transformer"; count++; }
        if(g_completeFlags.ensemble) { if(StringLen(activeList) > 0) activeList += ", "; activeList += "Ensemble"; count++; }
        if(g_completeFlags.onnxAI) { if(StringLen(activeList) > 0) activeList += ", "; activeList += "ONNX"; count++; }

        PrintFormat("[PER-SYMBOL-REPORT] %-25s | Synthetic: %s | Active: %d | Components: %s",
                    sym, isSynthetic ? "YES" : "NO", count, activeList);
    }
    Print("[PER-SYMBOL-REPORT] ========================================");
}

// ORCHESTRATOR CONFIG BUILDER (with test profile integration)

SOrchestratorConfig BuildOrchestratorConfig()
{
    SOrchestratorConfig config;

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

        config.trendADXNoTrendThreshold = InpTrendADXNoTrendThreshold;
        config.syntheticADXNoTrendThreshold = InpSyntheticADXNoTrendThreshold;
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

        config.trendADXNoTrendThreshold = InpTrendADXNoTrendThreshold;
        config.syntheticADXNoTrendThreshold = InpSyntheticADXNoTrendThreshold;
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
    config.allowSparseIntrabarSingleVoter = InpAllowSparseIntrabarSingleVoter;
    config.sparseIntrabarMinQuality = InpSparseIntrabarMinQuality;
    config.sparseIntrabarMinSupportRatio = InpSparseIntrabarMinSupportRatio;
    config.sparseIntrabarMinReadyCoverage = InpSparseIntrabarMinReadyCoverage;

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
    config.allowAIWarmStartLive = InpAllowAIWarmStartLive;
    config.allowHybridAIStandalone = InpAllowHybridAIStandalone;
    config.aiStandaloneMinConfidence = InpAIStandaloneMinConfidence;
    config.aiStandaloneRelaxedConfidence = InpAIStandaloneRelaxedConfidence;
    config.hybridGateRelaxAfterCycles = InpHybridGateRelaxAfterCycles;
    config.authorityMinSamples = InpAuthorityMinSamples;
    config.authorityTrialHorizonSeconds = InpAuthorityTrialHorizonSeconds;
    config.authorityMaxTrackedTrials = InpAuthorityMaxTrackedTrials;
    config.authorityMinExpectancyR = InpAuthorityMinExpectancyR;
    config.authorityMinProfitFactor = InpAuthorityMinProfitFactor;
    config.authorityMinCostScore = InpAuthorityMinCostScore;
    config.authorityMinReadinessScore = InpAuthorityMinReadinessScore;
    config.authorityMinContextScore = InpAuthorityMinContextScore;
    config.aiBootstrapRiskMultiplier = InpAIBootstrapRiskMultiplier;
    config.aiPromotedRiskMultiplier = InpAIPromotedRiskMultiplier;
    config.nonAIPromotedRiskMultiplier = InpNonAIPromotedRiskMultiplier;

    config.enableNNAttributionDiagnostics = InpEnableNNAttributionDiagnostics;
    config.runNNAttributionSelfTest = InpRunNNAttributionSelfTest;

    // Runtime Cadence
    config.enableHybridCadence = InpEnableHybridCadence;
    config.intrabarScanSeconds = InpIntrabarScanSeconds;
    config.intrabarChartSymbolOnly = InpIntrabarChartSymbolOnly;
    config.intrabarDynamicQuorumEnabled = InpIntrabarDynamicQuorumEnabled;
    config.pipelineMinConfidence = InpPipelineMinConfidence;
    config.intrabarSingleVoterMinConfidence = InpIntrabarSingleVoterMinConfidence;
    config.syntheticLeanSparseIntrabarMinQuality = InpSyntheticLeanSparseIntrabarMinQuality;
    config.syntheticLeanIntrabarSingleVoterMinConfidence = InpSyntheticLeanIntrabarSingleVoterMinConfidence;
    config.pipelineIntrabarConfidenceCap = InpPipelineIntrabarConfidenceCap;
    config.pipelineEnableRegimeCostGate = InpPipelineEnableRegimeCostGate;
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
    config.maxIntrabarSymbolsPerCycle = InpMaxIntrabarSymbolsPerCycle;
    config.maxSignalEvaluationsPerCycle = InpMaxSignalEvaluationsPerCycle;
    config.intrabarBackoffMaxSeconds = InpIntrabarBackoffMaxSeconds;
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

    config.emergencyFlattenAllAccountPositions = InpEmergencyFlattenAllAccountPositions;
    config.unprotectedRemediationIntervalSec = InpUnprotectedRemediationIntervalSec;
    config.unprotectedMaxRestoreAttempts = InpUnprotectedMaxRestoreAttempts;
    config.closeUnprotectedOnRemediationFailure = InpCloseUnprotectedOnRemediationFailure;
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

    // Institutional TA
    config.enableVWAPEngine = InpEnableVWAPEngine;
    config.enableVolumeProfile = InpEnableVolumeProfile;
    config.enableCVDEngine = InpEnableCVDEngine;
    config.vwapMinPeriodBars = InpVWAPMinPeriodBars;
    config.vwapBand1 = InpVWAPBand1;
    config.vwapBand2 = InpVWAPBand2;
    config.vwapBand3 = InpVWAPBand3;
    config.vpLookback = InpVPLookback;
    config.vpResolution = InpVPResolution;
    config.cvdDivergenceLookback = InpCVDDivergenceLookback;

    // Enterprise Mode
    config.useSignalPipeline = InpUseSignalPipeline;
    config.allowSyntheticOffHours = InpAllowSyntheticOffHours;
    config.minTrendStrength = InpMinTrendStrength;
    config.maxVolatility = InpMaxVolatility;
    config.enableStructureFilter = InpEnableStructureFilter;
    config.enableLiquidityFilter = InpEnableLiquidityFilter;
    config.dormancyStrikeBars = MathMax(1, InpDormancyStrikeBars);
    config.dormancyCooldownMinutes = MathMax(1, InpDormancyCooldownMinutes);
    config.portfolioMaxPositionsPerSymbol = InpPortfolioMaxPositionsPerSymbol;
    config.maxPositionsSameBase = InpMaxPositionsSameBase;
    config.enableClusterRiskGovernance = InpEnableClusterRiskGovernance;
    config.enableClusterMutex = InpEnableClusterMutex;
    config.riskMaxConcurrentPerCluster = InpRiskMaxConcurrentPerCluster;
    config.riskMaxClusterExposurePct = InpRiskMaxClusterExposurePct;

    // Portfolio Profit Target
    config.dailyProfitTargetPercent = InpDailyProfitTargetPercent;
    config.profitTrailFactor = InpProfitTrailFactor;
    config.profitTargetHardFloorRatio = InpProfitTargetHardFloorRatio;
    config.dailyHaltCooldownMinutes = InpDailyHaltCooldownMinutes;

    // Dual-Mode Auto-Switching
    config.enableAutoModeSwitch = InpEnableAutoModeSwitch;
    config.conservativeBaseRiskPct = InpConservativeBaseRiskPct;
    config.aggressiveBaseRiskPct = InpAggressiveBaseRiskPct;
    config.modeSwitchDrawdownPct = InpModeSwitchDrawdownPct;
    config.modeSwitchWinStreak = InpModeSwitchWinStreak;

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

    config.enableExitOptimizer = InpEnableExitOptimizer;

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

    // Apply test profile if enabled
    if(InpTestProfileOverrideAll && InpCompleteTestProfile != TEST_PROFILE_CUSTOM)
    {
        PrintFormat("[TEST-PROFILE] Applying profile: %s (%d)",
                    EnumToString(InpCompleteTestProfile), InpCompleteTestProfile);
        ApplyCompleteTestProfile(InpCompleteTestProfile, g_completeFlags, InpIncludeDeadCodeInProfiles);
        ApplyFlagsToInputs(g_completeFlags);
        LogCompleteActivationMatrix();
        LogPerSymbolEffectiveComponents();
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

