// Shared input parameters and shared config builder for both EA entry points:
// MultiStrategyAutonomousEA.mq5 (live) and MultiStrategyTestingEA.mq5 (test).
//
// Mode-specific inputs (different defaults or unique to one EA) remain in each
// EA file:
//   AI master toggles:  InpEnableAIMode, InpEnableNeuralNetwork, InpEnableTransformer,
//                       InpEnableEnsemble, InpEnableOnnxAI, InpEnablePythonBridgeAI,
//                       InpPythonBridgeMode
//   Risk:               InpMaxRiskPerTrade, InpMaxDailyRisk, InpMaxPortfolioRisk,
//                       InpDailyLossLimitPercent
//   Lot rounding:       InpAllowMinLotRoundUp, InpMinLotRiskMultiplier
//   Momentum scalping:  InpEnableMomentumScalping
//   Strategy set:       InpUseCuratedStrategySet
//   Batch 114 strategies: InpEnableKalmanMR, InpEnableChangepointDetect,
//                       InpEnableFourStateRegime, InpEnableVolTargeting,
//                       InpEnableLiquiditySweep, InpEnableRangeCompression
//   Testing EA only:    InpCompleteTestProfile, InpTestProfileOverrideAll,
//                       InpIncludeDeadCodeInProfiles
//   Autonomous EA only: InpBasketEquityStopEnabled, InpBasketEquityStopDrawdownPct,
//                       InpBasketEquityStopCloseOnBreach
//
// Everything below is identical in both EAs and is mapped into SOrchestratorConfig
// by PopulateSharedOrchestratorConfig().

#ifndef SHARED_EA_INPUTS_MQH
#define SHARED_EA_INPUTS_MQH

#include "../Orchestration/OrchestratorConfig.mqh"

//=== Shared inputs (identical in both EAs) ===

input group "Identity & EA Mode";
input long     InpMagicNumber = 123456;
input int      InpConfigVersion = 109;  // L7-005: Config version for migration tracking
input ENUM_EA_MODE InpEAMode = EA_MODE_HYBRID;
input bool     InpStrictEAMode = false;

input group "Risk & Money Management";
input double   InpLotSize = 0.1;
input bool     InpUseEnhancedRisk = true;
input double   InpMaxDrawdown = 15.0;
input bool     InpEnableCompoundingTiers = true;
input int      InpCompoundingTierCheckIntervalSec = 60;
input ENUM_RISK_TIER InpRiskTier = RISK_TIER_MODERATE;
input double   InpKellyFraction = 0.25;
input int      InpEquityCurveEmaPeriod = 20;
input double   InpEquityCurveReductionFactor = 0.50;

// Crisis limits and hardcoded thresholds (Item 19): class-member defaults replaced by operator inputs.
input double   InpPositionSizerMaxLotSize = 100.0;
input int      InpPositionSizerVolatilityLookback = 252;
input int      InpPositionSizerEquityCurveLookback = 100;
input double   InpRiskMarginHealthMaxFreeMarginUsage = 0.8;
input double   InpRiskMarginHealthMinMarginLevel = 200.0;
input double   InpPortfolioRiskCvarConfidence = 0.95;
input double   InpPortfolioRiskCvarMaxRisk = 0.10;
input int      InpPortfolioRiskMaxEquityCurveHistory = 500;
input double   InpRiskValidationMinAccountBalance = 100.0;
input double   InpPortfolioRiskStopFallbackPoints = 100.0;

input group "Portfolio & Position Limits";
input int      InpMaxPositionsTotal = 15;
input int      InpMaxPositionsTotalMin = 3;
input int      InpMaxPositionsPerSymbol = 5;
input int      InpMaxPositionsPerSymbolMin = 1;
input int      InpMaxTradeSendsPerCycle = 3;
input int      InpMinSecondsBetweenTrades = 10;
input int      InpMaxPositionsSameBase = 3;

input group "Symbol Universe & Liquidity";
// Batch 292: the two Volatility indices are removed from the factory universe.
// Measured on five paired cold 7-day windows (Volatility 75 Index M15, Model=1, deposit 10,000,
// InpQuorumProfile=1, InpMinLiveVoters=1, scalp engine off, every run cold):
//   09.01-09.08  +5.945% vs +3.811%   +2.13 pp
//   09.08-09.15  +7.689% vs +0.635%   +7.05 pp
//   09.15-09.22  +7.459% vs +1.489%   +5.97 pp
//   09.22-09.29 +18.176% vs +2.640%  +15.54 pp
//   10.06-10.13  -0.599% vs -2.696%   +2.10 pp
// trimmed mean +7.734%, sd 6.74 pp, t 2.57, worst window -0.599%
// paired deltas mean +6.56 pp, sd 5.39 pp, t 2.72, 5 of 5 positive
// The full-universe arm's losses were five closes of Volatility 75 Index (-116.53 in the 10.06 window);
// the gain is dominated by Crash 1000 (up to +1,848.83 on 85 closes in one week), which is why the arm's
// sd is larger than the full universe's while its worst window is smaller. Restore the two indices by
// naming them here or in InpSymbolsToTrade; note InpAutoAddChartSymbol re-injects the chart symbol.
input string   InpSymbolsToTrade = "Boom 1000 Index,Crash 1000 Index,Jump 25 Index,Jump 75 Index,Step Index,EURUSD,GBPUSD,USDJPY,AUDUSD,XAUUSD,BTCUSD";
input bool     InpAutoAddChartSymbol = true;       // L7-021: Auto-add chart symbol to universe if missing
input long     InpSymbolMaxSpreadPoints = 1500;
input long     InpSymbolMinDailyVolumeLots = 1000;
input bool     InpSymbolEnableVolumeCheck = true;

input group "Strategies - Classic Set";
input bool     InpEnableMomentum = true;
input bool     InpEnableTrend = true;
input bool     InpEnableSupportResistance = true;
input bool     InpEnableCandlestick = true;
input bool     InpCandlestickRequireTrend = false;
input bool     InpEnableMeanReversion = true;
input bool     InpEnableVolatilityBreakout = true;
input bool     InpEnableFVGScalper = true;
input bool     InpEnableTurtleSoup = true;
input bool     InpEnableBreakerBlock = true;
input bool     InpEnableNYOpenGap = true;
input bool     InpEnableAsianRangeBreak = true;
input bool     InpEnableStatisticalArbitrage = false;
input bool     InpEnableDonchianBreakout = true;
input bool     InpEnableRSI2Pullback = true;
input bool     InpEnableDailyLevelBreakout = true;
input bool     InpEnableDailyLevelFade = true;
input bool     InpEnableEMARibbon = true;
input bool     InpEnableGapContinuation = true;
input bool     InpEnableOpeningRangeBreakout = true;
input bool     InpEnableICTSessionGap = true;
input bool     InpEnableICTStructureShift = true;
input bool     InpUseSymbolClassProfiles = false;

// FINDING 0 (STRATEGY_AUDIT_2026-08-14): when true, the consensus execution path
// uses each strategy's designed stop-loss / take-profit (in pips) instead of the
// generic fallback. ENABLED for LIVE operation (shadow mode removed 2026-08-14).
input bool     InpUseStrategyStops = true;

input group "Strategies - Statistical & Adaptive";
input double   InpKalmanLambda = 500.0;
input double   InpCPDHazardThreshold = 0.3;
input double   InpTargetVol = 0.15;
input double   InpVolMinScale = 0.2;
input double   InpVolMaxScale = 3.0;

input group "Strategies - Microstructure Engines";
input bool     InpEnableHurstEngine = true;
input int      InpHurstLookback = 300;
input bool     InpEnableOUProcess = true;
input int      InpOULookback = 100;
input bool     InpEnableOFIProxy = true;
input int      InpOFISlowWindow = 100;
input bool     InpEnableVPINFilter = true;
input double   InpVPINExtremeThreshold = 0.7;
input int      InpVPINNumBuckets = 50;
input bool     InpMultiAssetProfilerEnabled = true;
input bool     InpDerivProfilerEnabled = true;
input bool     InpGridRecoveryEnabled = true;
input bool     InpATRScalpingEnabled = true;

input group "ADX Lot Tiering (CADXLotModifier)";
input double   InpAdxMinLotMultiplier = 1.0;
input bool     InpAdxTradeOnNoTrend = true;

input group "Strategy Weights (Consensus)";
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
input double   InpWeightDonchianBreakout = 1.6;
input double   InpWeightRSI2Pullback = 1.5;
input double   InpWeightDailyLevelBreakout = 1.7;
input double   InpWeightDailyLevelFade = 1.5;
input double   InpWeightEMARibbon = 1.6;
input double   InpWeightGapContinuation = 1.5;
input double   InpWeightOpeningRangeBreakout = 1.7;
input double   InpWeightICTSessionGap = 1.5;
input double   InpWeightICTStructureShift = 1.6;

input group "Regime, Skew & Family Weighting";
input bool     InpEnableSessionWeights = true;
input int      InpSessionDSTOffsetHours = 0;  // L7-022: DST offset for session weights (-12 to +12)
input bool     InpEnableSkewStepAnalyzer = true;
input bool     InpEnableFamilyWeightMatrix = true;
input int      InpSkewStepBufferSize = 200;
input double   InpSkewStepCalmThreshold = 0.80;
input double   InpSkewStepSmallThreshold = 0.2;
input double   InpSkewStepLargeThreshold = 0.5;

input group "Consensus & Quorum";
input CEnterpriseStrategyManager::ENUM_QUORUM_PROFILE InpQuorumProfile = CEnterpriseStrategyManager::QUORUM_BALANCED;
input double   InpQuorumThreshold = 0.60;
// Measured default (Batch 288): 1, not 2. Six cold windows on one instrument gave the one-voter arm mean +0.46%
// (stdev 0.92 pp, 3 wins of 6) against the committee's mean -1.31% (4 losses of 4), paired delta +1.80 pp with
// t = 2.6 at n = 4, p about 0.08 and never worse than 0.11 pp. Rejections fall from 2,054-2,819 per window to
// 139-227. This is the only single-variable setting in this repository with multi-window evidence; it is a
// policy default, not an optimisation, and the committee remains selectable at 2.
input int      InpMinLiveVoters = 1;
input double   InpConsensusConflictDeadband = 0.35;
input double   InpConsensusMinReadyWeightRatio = 0.40;
input double   InpConsensusSupportFloorNewBar = 0.20;
input double   InpConsensusSupportFloorIntrabar = 0.15;
// The lone-voter confidence floor: a single voter's own mean confidence must clear this before it can
// carry a trade alone. Measured, not assumed: on a 24 h window every one of 103 consensus rejects was
// this floor, with rejected confidences averaging ~0.64 (min 0.54, max 0.69) - the distribution sits
// just under 0.70. Lower it and more one-voter entries pass; raise it and fewer do. Clamped [0.50, 0.95].
input double   InpSingleVoterFloor = 0.70;

// Per-symbol loss-streak breaker. Measured on the 2026.09.01->09.08 window: one instrument closed 13
// positions, 11 of them losers, longest losing run 5, and 244.22 of the 299.32 dollars lost sat inside
// losing runs of 2 or longer. Nothing in the risk layer is aware of that - the loss arrives as a series of
// same-symbol entries, each individually sized normally. Limit 0 disables the breaker (the shipped default,
// so a baseline run is unchanged); it is an A/B input, not a tuned value.
input group "Per-Symbol Loss Streak";
input int      InpSymbolLossStreakLimit = 0;     // consecutive losing closes on one symbol that stand it down; 0 = off
input int      InpSymbolLossStreakCooldownMin = 60; // how long that symbol is held after the limit is hit
// The sizing half of the same idea (Batch 287). Batch 286 measured that HOLDING a row is a reallocation rule:
// the slot and the risk budget pass to the next symbol, which took a +0.983% window down to -3.767%. This instead
// shrinks the risk fraction for a symbol in a losing run and leaves the entry free. 1.0 = off. The number to
// judge it by is cross-window stdev versus mean, not mean alone.
input double   InpSymbolStreakRiskScale = 1.0;   // risk multiplier applied once the streak below is reached
input int      InpSymbolStreakRiskMinCount = 2;  // consecutive losing closes that trigger the smaller stake

input group "AI/ML - Python Bridge";
input string   InpPythonBridgeEndpoint = "http://127.0.0.1:8000";
input int      InpPythonBridgeRequestTimeoutMs = 2000;
input int      InpPythonBridgeHeartbeatTimeoutSec = 30;
input int      InpPythonBridgeMaxReconnectAttempts = 5;
input int      InpPythonBridgeReconnectBackoffMs = 2000;

input group "AI/ML - External LLM";
input bool     InpEnableExternalLLM = false;
input string   InpExternalLLMEndpoint = "http://localhost:11434";

input group "AI/ML - Tuning";
input double   InpAIConfidenceThreshold = 0.70;
input double   InpAIWeightMultiplier = 1.0;
input double   InpAIDrawdownSizingLimit = 0.20;

input group "AI/ML - Neural Network Training";
input bool     InpEnableNNOnlineTraining = true;
input bool     InpEnableNNWeightMutation = false;
input bool     InpEnableNNPseudoLabeling = true;
input int      InpNNPseudoLabelBarsAhead = 10;
input int      InpNNSampleIntervalSeconds = 15;
input int      InpNNCheckpointEveryLabeled = 3;
input bool     InpEnableNNAttributionDiagnostics = true;   // Batch 238: the setter is wired now; true is what every build has printed
input bool     InpRunNNAttributionSelfTest = false;        // Batch 238: callable now; runs the prediction-comment and map round trip at init

input group "AI/ML - Authority & Live Gating";
input bool     InpEnableLiveAuthorityGate = false;
input bool     InpAllowHybridAIStandalone = true;
input double   InpAIStandaloneMinConfidence = 0.65;
input double   InpAIStandaloneRelaxedConfidence = 0.60;
input int      InpHybridGateRelaxAfterCycles = 5;
input int      InpAuthorityMinSamples = 12;
input double   InpAuthorityMinExpectancyR = 0.03;
input double   InpAuthorityMinProfitFactor = 1.10;
input double   InpAuthorityMinCostScore = 0.50;
input double   InpAuthorityMinReadinessScore = 0.52;
input double   InpAuthorityMinContextScore = 0.48;
input double   InpAIBootstrapRiskMultiplier = 0.50;
input double   InpAIPromotedRiskMultiplier = 1.00;

input group "Hybrid Cadence & Intrabar Scan";
input bool     InpIntrabarDynamicQuorumEnabled = true;
input int      InpMaxSignalEvaluationsPerCycle = 8;
input int      InpReadinessReuseTtlSeconds = 60;

input group "Intrabar Eligibility Policies";
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

input group "Pipeline, Spread & Crisis Filters";
input bool     InpUseSignalPipeline = true;
input bool     InpPipelineEngineRegistry = false;  // binds the shared engines to the pipeline's five filters (tightens entries)
input double   InpPipelineMinConfidence = 0.55;
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

input int      InpMomentumScalpCooldownSeconds = 20;
input ENUM_TIMEFRAMES InpMomentumScalpTimeframe = PERIOD_M5;
input ENUM_TIMEFRAMES InpCandlestickIntrabarTimeframe = PERIOD_M5;

input group "Signal Validator (Quality Gates)";
input int      InpValidatorNewBarMinConfluence = 1;
input double   InpValidatorNewBarMinQuality = 0.68;
input double   InpValidatorNewBarMinConfidence = 0.55;
input int      InpValidatorIntrabarMinConfluence = 1;
input double   InpValidatorIntrabarMinQuality = 0.70;
input double   InpValidatorIntrabarMinConfidence = 0.60;

input group "Execution & Orders";
input ENUM_ORDER_TYPE_FILLING InpOrderFillingMode = ORDER_FILLING_IOC;
input int      InpTradeSlippagePoints = 50;
input double   InpMaxEntrySpreadPoints = 15000.0;
input double   InpMaxEntryDriftPoints = 80.0;
input int      InpProtectiveModifyCooldownSec = 5;

input group "Signal-Reversal Exit";
input bool     InpEnableSignalReversalExit = true;
input double   InpSignalReversalMinConfidence = 0.58;
input bool     InpSignalReversalProfitGuard = true;
input double   InpSignalReversalMinLossR = 0.25;
input double   InpSignalReversalMaxLossR = 0.82;
input int      InpSignalReversalMinTimeSec = 45;

input group "Position Lifecycle & Trailing";
input bool     InpEnablePositionLifecycleManager = true;
input double   InpLifecycleBreakevenBufferPoints = 50.0;
input double   InpLifecycleTrailingDistancePoints = 150.0;
input double   InpLifecycleTrailingStepPoints = 30.0;
input bool     InpLifecycleUseATRTrailing = false;
input double   InpLifecycleATRMultiplier = 1.5;
input bool     InpEnableStructuralInvalidation = true;
input bool     InpEnableMaxHoldTime = true;
input int      InpMaxHoldHoursIntraday = 24;
input int      InpMaxHoldHoursSwing = 120;
input bool     InpMaxHoldOnlyIfLoss = true;

input group "Loss Guard (exit path that ran unconfigurable until Batch 244)";
input bool     InpLossGuardAdverseMomentumExit = false;          // off is what every build has done: the flag had no writer
input double   InpLossGuardAdverseMomentumATR = 0.5;             // close when price moves this x ATR(14) against the entry
input int      InpLossGuardConsecutiveLossLimit = 3;             // >0 also ARMS the whole guard: 0 and the flag off = path dormant
input int      InpLossGuardConsecutiveLossCooldownSec = 1800;    // pause on the guard after that many guard-realized losses
input double   InpLossGuardDailyLossCircuitBreakerPct = 50.0;    // of InpMaxDailyRisk, counted from guard closes only
input double   InpLossGuardPositionLossLimitPct = 75.0;          // close at this fraction of the position's own SL distance

input group "Emergency & Unprotected Remediation";
input bool     InpEmergencyFlattenAllAccountPositions = false; // true = emergency flatten may close positions this EA did not open (manual trades / other EAs). Off by default (Batch 168).
input int      InpUnprotectedRemediationIntervalSec = 15;
input int      InpUnprotectedMaxRestoreAttempts = 3;
input double   InpSyntheticSpikeVelocityMultiplier = 3.0;
input int      InpSyntheticSpikePauseSeconds = 30;

input group "Scalp Engine";
// OFF by factory default since Batch 291. Measured on the Batch 290 build, Volatility 75 Index M15,
// Model=1, deposit 10,000, InpQuorumProfile=1, InpMinLiveVoters=1, every window cold:
//   scalp ON  2026.09.01-09.08: -258.77 (-2.588%), 2,265 fills
//   scalp OFF same build/window: +381.07 (+3.811%),   270 fills   (one input changed, no recompile)
//   scalp OFF four windows: +3.811 / +0.635 / +1.489 / +2.640 -> mean +2.14%, sd 1.38 pp, t 3.1, 4 wins of 4
// The engine is negative-expectancy once its stop admits every symbol; consistency beats fill volume.
// Turn it back on with InpEnableScalpEngine=true (optionally bounded by InpScalpSymbolsCsv) and measure
// a paired window before shipping it again.
input bool     InpEnableScalpEngine = false;
input bool     InpScalpAsyncMode = false;
input uint     InpScalpMaxLatencyMs = 500;
// Comma-separated symbols the fast-scalp engine may trade; "" = every symbol in the universe.
// Measured (Batch 290): with the Batch 289 per-symbol stop and every symbol allowed, the window
// 2026.09.01-09.08 returned -258.77 (-2.588%) on 2,265 fills, against +98.29 (+0.983%) on 849 fills
// when only Step Index and XAUUSD could pass the old 60/90-point cost gate. The stop geometry is
// arithmetic; symbol coverage is the variable that changed the book.
input string   InpScalpSymbolsCsv = "";

input group "Dynamic Slippage";
input bool     InpEnableDynamicSlippage = true;
input double   InpDynamicSlippageAtrPercent = 0.20;
input int      InpDynamicSlippageMinPoints = 10;
input int      InpDynamicSlippageMaxMultiplier = 10;
input int      InpDynamicSlippageAtrPeriod = 14;

input group "Spike Hunter";
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
input int      InpSpikeConfirmWindows = 2;
input bool     InpAllowSyntheticOffHours = true;

input group "Visualization";
input bool     InpEnableVisualAnalysis = true;
input int      InpMaxVisualObjects = 500;

input group "Dashboard";
input bool     InpDashboardEnabled = true;
input string   InpDashboardEndpoint = "http://127.0.0.1:8765";
input int      InpDashboardPushIntervalSec = 5;
input bool     InpDashboardControlEnabled = false;

input group "Signal Filters";
input double   InpMinTrendStrength = 50.0;
input double   InpMaxVolatility = 3.0;
input bool     InpEnableStructureFilter = true;
input bool     InpEnableLiquidityFilter = true;
input int      InpDormancyStrikeBars = 3;
input int      InpDormancyCooldownMinutes = 30;

input group "Cluster Risk Governance";
input bool     InpEnableClusterRiskGovernance = true;
input bool     InpEnableClusterMutex = true;
input int      InpRiskMaxConcurrentPerCluster = 3;
input double   InpRiskMaxClusterExposurePct = 5.0;

input group "Profit Targets & Daily Halt";
input double   InpDailyProfitTargetPercent = 2.0;
input double   InpProfitTrailFactor = 0.7;
input int      InpDailyHaltCooldownMinutes = 30;

input group "Logging";
input int      InpLogLevel = 1;
input int      InpLogVerbosity = 3;  // 0=SILENT, 1=ERRORS_ONLY, 2=WARNING, 3=NORMAL, 4=VERBOSE, 5=DEBUG
input bool     InpLogDerivFamilyDetection = true;  // L7-013: Enable logging for Deriv family detection

//=== Shared config builder: maps all shared inputs into SOrchestratorConfig ===
// Mode-specific fields (InpMaxRiskPerTrade, InpEnableAIMode, etc.) are set by
// each EA's own BuildOrchestratorConfig() after calling this function.

void PopulateSharedOrchestratorConfig(SOrchestratorConfig &config)
{
    // General
    config.magicNumber = InpMagicNumber;
    config.configVersion = InpConfigVersion;  // L7-005: Config version for migration tracking
    config.lotSize = InpLotSize;
    config.useEnhancedRisk = InpUseEnhancedRisk;
    config.maxDrawdown = InpMaxDrawdown;
    config.riskTier = InpRiskTier;
    config.enableCompoundingTiers = InpEnableCompoundingTiers;
        config.compoundingTierCheckIntervalSec = InpCompoundingTierCheckIntervalSec;
        config.enableSessionWeights = InpEnableSessionWeights;
        config.enableSkewStepAnalyzer = InpEnableSkewStepAnalyzer;
        config.enableFamilyWeightMatrix = InpEnableFamilyWeightMatrix;
    config.symbolsToTrade = InpSymbolsToTrade;
    config.minSecondsBetweenTrades = InpMinSecondsBetweenTrades;
    config.maxPositionsTotal = InpMaxPositionsTotal;
    config.maxPositionsTotalMin = InpMaxPositionsTotalMin;
    config.maxPositionsPerSymbol = InpMaxPositionsPerSymbol;
    config.maxPositionsPerSymbolMin = InpMaxPositionsPerSymbolMin;
    config.maxTradeSendsPerCycle = InpMaxTradeSendsPerCycle;

    // Strategy selection (from shared inputs directly)
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
    config.enableDonchianBreakout = InpEnableDonchianBreakout;
    config.enableRSI2Pullback = InpEnableRSI2Pullback;
    config.enableDailyLevelBreakout = InpEnableDailyLevelBreakout;
    config.enableDailyLevelFade = InpEnableDailyLevelFade;
    config.enableEMARibbon = InpEnableEMARibbon;
    config.enableGapContinuation = InpEnableGapContinuation;
    config.enableOpeningRangeBreakout = InpEnableOpeningRangeBreakout;
    config.enableICTSessionGap = InpEnableICTSessionGap;
    config.enableICTStructureShift = InpEnableICTStructureShift;
    config.adxMinLotMultiplier = InpAdxMinLotMultiplier;
    config.adxAllowNoTrendTrading = InpAdxTradeOnNoTrend;
    config.useSymbolClassProfiles = InpUseSymbolClassProfiles;

    // Batch 114
    config.kalmanLambda = InpKalmanLambda;
    config.cpdHazardThreshold = InpCPDHazardThreshold;
    config.targetVol = InpTargetVol;
    config.volMinScale = InpVolMinScale;
    config.volMaxScale = InpVolMaxScale;

    // EA operating mode
    config.eaMode = InpEAMode;
    config.enableVisualAnalysis = InpEnableVisualAnalysis;
    config.maxVisualObjects = InpMaxVisualObjects;
    config.strictEAMode = InpStrictEAMode;

    // Consensus quorum
    config.quorumThreshold = InpQuorumThreshold;
    config.minLiveVoters = InpMinLiveVoters;
    config.consensusConflictDeadband = InpConsensusConflictDeadband;
    config.consensusMinReadyWeightRatio = InpConsensusMinReadyWeightRatio;
    config.consensusSupportFloorNewBar = InpConsensusSupportFloorNewBar;
    config.consensusSupportFloorIntrabar = InpConsensusSupportFloorIntrabar;
    config.symbolLossStreakLimit = InpSymbolLossStreakLimit;
    config.symbolLossStreakCooldownMin = InpSymbolLossStreakCooldownMin;
    config.symbolStreakRiskScale = InpSymbolStreakRiskScale;
    config.symbolStreakRiskMinCount = InpSymbolStreakRiskMinCount;
        config.quorumProfile = InpQuorumProfile;
    config.singleVoterFloor = InpSingleVoterFloor;

    // Strategy weights
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
    config.weightDonchianBreakout = InpWeightDonchianBreakout;
    config.weightRSI2Pullback = InpWeightRSI2Pullback;
    config.weightDailyLevelBreakout = InpWeightDailyLevelBreakout;
    config.weightDailyLevelFade = InpWeightDailyLevelFade;
    config.weightEMARibbon = InpWeightEMARibbon;
    config.weightGapContinuation = InpWeightGapContinuation;
    config.weightOpeningRangeBreakout = InpWeightOpeningRangeBreakout;
    config.weightICTSessionGap = InpWeightICTSessionGap;
    config.weightICTStructureShift = InpWeightICTStructureShift;

    // AI Engine settings (shared fields only; master toggles are mode-specific)
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

    // Runtime cadence
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

    // Signal validator
    config.validatorNewBarMinConfluence = InpValidatorNewBarMinConfluence;
    config.validatorNewBarMinQuality = InpValidatorNewBarMinQuality;
    config.validatorNewBarMinConfidence = InpValidatorNewBarMinConfidence;
    config.validatorIntrabarMinConfluence = InpValidatorIntrabarMinConfluence;
    config.validatorIntrabarMinQuality = InpValidatorIntrabarMinQuality;
    config.validatorIntrabarMinConfidence = InpValidatorIntrabarMinConfidence;

    // Execution safety
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

    // Fast scalp engine
    config.enableScalpEngine = InpEnableScalpEngine;
    config.scalpAsyncMode = InpScalpAsyncMode;
    config.scalpMaxLatencyMs = InpScalpMaxLatencyMs;
    config.scalpSymbolsCsv = InpScalpSymbolsCsv;

    config.enableDynamicSlippage = InpEnableDynamicSlippage;
    config.dynamicSlippageAtrPercent = InpDynamicSlippageAtrPercent;
    config.dynamicSlippageMinPoints = InpDynamicSlippageMinPoints;
    config.dynamicSlippageMaxMultiplier = InpDynamicSlippageMaxMultiplier;
    config.dynamicSlippageAtrPeriod = InpDynamicSlippageAtrPeriod;

    // Spike detection
    config.spikeConfirmWindows = InpSpikeConfirmWindows;

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

    // Mathematical engines
    config.enableHurstEngine = InpEnableHurstEngine;
    config.hurstLookback = InpHurstLookback;
    config.enableOUProcess = InpEnableOUProcess;
    config.ouLookback = InpOULookback;
    config.enableOFIProxy = InpEnableOFIProxy;
    config.ofiSlowWindow = InpOFISlowWindow;
    config.enableVPINFilter = InpEnableVPINFilter;
    config.vpinExtremeThreshold = InpVPINExtremeThreshold;
    config.vpinNumBuckets = InpVPINNumBuckets;

    // Enterprise mode
    config.useSignalPipeline = InpUseSignalPipeline;
    config.useStrategyStops = InpUseStrategyStops;
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

    // Portfolio profit target
    config.dailyProfitTargetPercent = InpDailyProfitTargetPercent;
    config.profitTrailFactor = InpProfitTrailFactor;
    config.dailyHaltCooldownMinutes = InpDailyHaltCooldownMinutes;

    // Symbol Validation (L7-003)
    config.symbolMaxSpreadPoints = InpSymbolMaxSpreadPoints;
    config.symbolMinDailyVolumeLots = InpSymbolMinDailyVolumeLots;
    config.symbolEnableVolumeCheck = InpSymbolEnableVolumeCheck;

    config.logLevel = InpLogLevel;
    config.logVerbosity = InpLogVerbosity;
    config.logDerivFamilyDetection = InpLogDerivFamilyDetection;  // L7-013

    // Symbol Universe (L7-021)
    config.autoAddChartSymbol = InpAutoAddChartSymbol;

    // Batch 99
    config.equityCurveEmaPeriod = InpEquityCurveEmaPeriod;
    config.equityCurveReductionFactor = InpEquityCurveReductionFactor;
    config.kellyFraction = InpKellyFraction;

    // Crisis limits and hardcoded thresholds (Item 19)
    config.positionSizerMaxLotSize = InpPositionSizerMaxLotSize;
    config.positionSizerVolatilityLookback = InpPositionSizerVolatilityLookback;
    config.positionSizerEquityCurveLookback = InpPositionSizerEquityCurveLookback;
    config.riskMarginHealthMaxFreeMarginUsage = InpRiskMarginHealthMaxFreeMarginUsage;
    config.riskMarginHealthMinMarginLevel = InpRiskMarginHealthMinMarginLevel;
    config.portfolioRiskCvarConfidence = InpPortfolioRiskCvarConfidence;
    config.portfolioRiskCvarMaxRisk = InpPortfolioRiskCvarMaxRisk;
    config.portfolioRiskMaxEquityCurveHistory = InpPortfolioRiskMaxEquityCurveHistory;
    config.riskValidationMinAccountBalance = InpRiskValidationMinAccountBalance;
    config.portfolioRiskStopFallbackPoints = InpPortfolioRiskStopFallbackPoints;

    // Skew Step Analyzer (L7-023)
    config.skewStepBufferSize = InpSkewStepBufferSize;
    config.skewStepCalmThreshold = InpSkewStepCalmThreshold;
    config.skewStepSmallThreshold = InpSkewStepSmallThreshold;
    config.skewStepLargeThreshold = InpSkewStepLargeThreshold;

    // Session Weight Manager (L7-022)
    config.sessionDSTOffsetHours = InpSessionDSTOffsetHours;
}

#endif // SHARED_EA_INPUTS_MQH




