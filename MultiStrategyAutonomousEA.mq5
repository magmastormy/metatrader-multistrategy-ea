// Simplified thin wrapper using EAOrchestrator as composition root
#property copyright "Copyright 2024"
#property link      "https://github.com/"
#property version   "2.000"
#property strict

// First on purpose: it installs the IndicatorRelease guard every later header must compile under.
#include "IndicatorManager.mqh"
#include "Core/Orchestration/EAOrchestrator.mqh"

// Global variable definitions (declared extern in OrchestratorFwd)
#include "Core/Orchestration/GlobalDefs.mqh"

// Production logging & tracing
#include "Core/Utils/StructuredLogger.mqh"
#include "Core/Utils/CorrelationId.mqh"
#include "Core/Config/SharedEAInputs.mqh"

CStructuredLogger g_structLog;
CCorrelationIdManager g_corrIdManager;

// L2-001: Global shutdown flag to prevent OnTimer accessing resources during deinit
bool g_shuttingDown;

// Forward declaration for GetDeInitReasonText
string GetDeInitReasonText(int reasonCode);

//--- Input Parameters (mode-specific only; shared inputs are in Core/Config/SharedEAInputs.mqh)

input group "Risk & Money Management";
input double   InpMaxRiskPerTrade = 1.0;
input double   InpMaxDailyRisk = 4.0;
input double   InpMaxPortfolioRisk = 12.0;
input double   InpDailyLossLimitPercent = 4.0;
input bool     InpBasketEquityStopEnabled = true;
input double   InpBasketEquityStopDrawdownPct = 10.0;
input bool     InpBasketEquityStopCloseOnBreach = false;
input bool     InpAllowMinLotRoundUp = true;
input double   InpMinLotRiskMultiplier = 3.0;

input group "Strategies - Classic Set";
input bool     InpUseCuratedStrategySet = true;

input group "Strategies - Statistical & Adaptive";
input bool     InpEnableKalmanMR = true;
input bool     InpEnableChangepointDetect = true;
input bool     InpEnableFourStateRegime = true;
input bool     InpEnableVolTargeting = true;
input bool     InpEnableLiquiditySweep = true;
input bool     InpEnableRangeCompression = true;

input group "AI/ML - Master Toggles";
input bool     InpEnableAIMode = true;
input bool     InpEnableNeuralNetwork = true;
input bool     InpEnableTransformer = true;
input bool     InpEnableEnsemble = true;
input bool     InpEnableOnnxAI = true;
input bool     InpEnablePythonBridgeAI = true;
input ENUM_PYTHON_BRIDGE_MODE InpPythonBridgeMode = PYTHON_BRIDGE_OBSERVE;

input group "Momentum Scalping";
input bool     InpEnableMomentumScalping = true;

input group "Spike Hunter";
input bool     InpSpikeHunterEnabled = true;


// Build orchestrator config from inputs

// EAOrchestrator instance - the composition root
CEAOrchestrator* g_orchestrator = NULL;
SOrchestratorConfig BuildOrchestratorConfig()
{
    SOrchestratorConfig config;
    PopulateSharedOrchestratorConfig(config);

    // General
        config.magicNumber = InpMagicNumber;
        config.configVersion = InpConfigVersion;  // L7-005: Config version for migration tracking
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
    
    // Strategy selection
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
    config.adxMinLotMultiplier = InpAdxMinLotMultiplier;
    config.adxAllowNoTrendTrading = InpAdxTradeOnNoTrend;
    config.useCuratedStrategySet = InpUseCuratedStrategySet;
    config.useSymbolClassProfiles = InpUseSymbolClassProfiles;
    
    // Batch 114
    config.enableKalmanMR = InpEnableKalmanMR;
    config.kalmanLambda = InpKalmanLambda;
    config.enableChangepointDetect = InpEnableChangepointDetect;
    config.cpdHazardThreshold = InpCPDHazardThreshold;
    config.enableFourStateRegime = InpEnableFourStateRegime;
    config.enableVolTargeting = InpEnableVolTargeting;
    config.targetVol = InpTargetVol;
    config.volMinScale = InpVolMinScale;
    config.volMaxScale = InpVolMaxScale;
    config.enableLiquiditySweep = InpEnableLiquiditySweep;
    config.enableRangeCompression = InpEnableRangeCompression;
    
    // EA operating mode
    config.eaMode = InpEAMode;
    config.enableVisualAnalysis = InpEnableVisualAnalysis;
    config.maxVisualObjects = InpMaxVisualObjects;
    
    // Consensus quorum
    config.quorumThreshold = InpQuorumThreshold;
    config.minLiveVoters = InpMinLiveVoters;
    config.consensusConflictDeadband = InpConsensusConflictDeadband;
    config.consensusMinReadyWeightRatio = InpConsensusMinReadyWeightRatio;
    config.consensusSupportFloorNewBar = InpConsensusSupportFloorNewBar;
    config.consensusSupportFloorIntrabar = InpConsensusSupportFloorIntrabar;
        config.quorumProfile = InpQuorumProfile;
    config.singleVoterFloor = InpSingleVoterFloor;
    config.symbolLossStreakLimit = InpSymbolLossStreakLimit;
    config.symbolLossStreakCooldownMin = InpSymbolLossStreakCooldownMin;
    config.symbolStreakRiskScale = InpSymbolStreakRiskScale;
    config.symbolStreakRiskMinCount = InpSymbolStreakRiskMinCount;
    
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
    
    // AI Engine settings
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
    
    config.enableDynamicSlippage = InpEnableDynamicSlippage;
    config.dynamicSlippageAtrPercent = InpDynamicSlippageAtrPercent;
    config.dynamicSlippageMinPoints = InpDynamicSlippageMinPoints;
    config.dynamicSlippageMaxMultiplier = InpDynamicSlippageMaxMultiplier;
    config.dynamicSlippageAtrPeriod = InpDynamicSlippageAtrPeriod;
    
    // Spike detection
    config.spikeConfirmWindows = InpSpikeConfirmWindows;
    
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
    
        // Batch 99
        config.equityCurveEmaPeriod = InpEquityCurveEmaPeriod;
        config.equityCurveReductionFactor = InpEquityCurveReductionFactor;
        config.kellyFraction = InpKellyFraction;

        // Theme 3 (article 23662): basket-level equity stop
        config.basketEquityStopEnabled = InpBasketEquityStopEnabled;
        config.basketEquityStopDrawdownPct = InpBasketEquityStopDrawdownPct;
        config.basketEquityStopCloseOnBreach = InpBasketEquityStopCloseOnBreach;
    
        // Strict EA Mode (L7-025)
                config.strictEAMode = InpStrictEAMode;
    
            // Symbol Universe (L7-021)
            config.autoAddChartSymbol = InpAutoAddChartSymbol;
    
            // Skew Step Analyzer (L7-023)
                        config.skewStepBufferSize = InpSkewStepBufferSize;
                        config.skewStepCalmThreshold = InpSkewStepCalmThreshold;
                        config.skewStepSmallThreshold = InpSkewStepSmallThreshold;
                        config.skewStepLargeThreshold = InpSkewStepLargeThreshold;
    
                // Session Weight Manager (L7-022)
                config.sessionDSTOffsetHours = InpSessionDSTOffsetHours;
    
                return config;
    }

// Validate all input parameters
bool ValidateInputs()
{
    bool valid = true;
    
    // --- Risk parameter validation ---
    if(InpMaxRiskPerTrade < 0.1 || InpMaxRiskPerTrade > 25.0)
    {
        PrintFormat("[VALIDATION] ERROR: InpMaxRiskPerTrade=%.2f out of range [0.1, 25.0]", InpMaxRiskPerTrade);
        valid = false;
    }
    else
    {
        PrintFormat("[VALIDATION] OK: InpMaxRiskPerTrade=%.2f", InpMaxRiskPerTrade);
    }
    
    if(InpMaxDailyRisk < 0.1 || InpMaxDailyRisk > 100.0)
    {
        PrintFormat("[VALIDATION] ERROR: InpMaxDailyRisk=%.2f out of range [0.1, 100.0]", InpMaxDailyRisk);
        valid = false;
    }
    else
    {
        PrintFormat("[VALIDATION] OK: InpMaxDailyRisk=%.2f", InpMaxDailyRisk);
    }
    
    if(InpMaxPortfolioRisk < 0.1 || InpMaxPortfolioRisk > 100.0)
    {
        PrintFormat("[VALIDATION] ERROR: InpMaxPortfolioRisk=%.2f out of range [0.1, 100.0]", InpMaxPortfolioRisk);
        valid = false;
    }
    else
    {
        PrintFormat("[VALIDATION] OK: InpMaxPortfolioRisk=%.2f", InpMaxPortfolioRisk);
    }
    
    if(InpMaxDrawdown < 1.0 || InpMaxDrawdown > 50.0)
    {
        PrintFormat("[VALIDATION] ERROR: InpMaxDrawdown=%.2f out of range [1.0, 50.0]", InpMaxDrawdown);
        valid = false;
    }
    else
    {
        PrintFormat("[VALIDATION] OK: InpMaxDrawdown=%.2f", InpMaxDrawdown);
    }
    
    if(InpDailyLossLimitPercent < 1.0 || InpDailyLossLimitPercent > 50.0)
    {
        PrintFormat("[VALIDATION] ERROR: InpDailyLossLimitPercent=%.2f out of range [1.0, 50.0]", InpDailyLossLimitPercent);
        valid = false;
    }
    else
    {
        PrintFormat("[VALIDATION] OK: InpDailyLossLimitPercent=%.2f", InpDailyLossLimitPercent);
    }
    
    // Cross-parameter validation: Daily risk should not exceed portfolio risk
    if(InpMaxDailyRisk > InpMaxPortfolioRisk)
    {
        PrintFormat("[VALIDATION] ERROR: InpMaxDailyRisk (%.2f) > InpMaxPortfolioRisk (%.2f)", InpMaxDailyRisk, InpMaxPortfolioRisk);
        valid = false;
    }
    
    // Cross-parameter validation: Per-trade risk * max positions should not excessively exceed portfolio risk
    double maxPossibleRisk = InpMaxRiskPerTrade * InpMaxPositionsTotal;
    if(maxPossibleRisk > InpMaxPortfolioRisk * 1.5)
    {
        PrintFormat("[VALIDATION] WARNING: InpMaxRiskPerTrade * InpMaxPositionsTotal (%.2f) > InpMaxPortfolioRisk * 1.5 (%.2f)", 
                      maxPossibleRisk, InpMaxPortfolioRisk * 1.5);
        // Warning only, not an error
    }
    
    // Cross-parameter validation: Max drawdown should be greater than daily loss limit
    if(InpMaxDrawdown <= InpDailyLossLimitPercent)
    {
        PrintFormat("[VALIDATION] ERROR: InpMaxDrawdown (%.2f) <= InpDailyLossLimitPercent (%.2f)", InpMaxDrawdown, InpDailyLossLimitPercent);
        valid = false;
    }
    
    // --- Consensus parameter validation ---
    if(InpQuorumThreshold < 0.5 || InpQuorumThreshold > 0.9)
    {
        PrintFormat("[VALIDATION] ERROR: InpQuorumThreshold=%.2f out of range [0.5, 0.9]", InpQuorumThreshold);
        valid = false;
    }
    else
    {
        PrintFormat("[VALIDATION] OK: InpQuorumThreshold=%.2f", InpQuorumThreshold);
    }
    
    // Votes are integers, so the smallest non-zero conflict is 1/votes_cast, and a deadband at or under it is
    // not a tight tolerance but a unanimity requirement - 1/19 = 0.053, so even this range's own floor of 0.05
    // demands every voter agree. The consensus veto now floors the deadband at the finest dissent it can see
    // and prints [CONSENSUS-DEADBAND-FLOORED]; a value below ~0.06 is accepted but cannot bind.
    if(InpConsensusConflictDeadband < 0.05 || InpConsensusConflictDeadband > 0.50)
    {
        PrintFormat("[VALIDATION] ERROR: InpConsensusConflictDeadband=%.2f out of range [0.05, 0.5]", InpConsensusConflictDeadband);
        valid = false;
    }
    else if(InpConsensusConflictDeadband < 0.10)
    {
        PrintFormat("[VALIDATION] WARNING: InpConsensusConflictDeadband=%.2f is under the finest dissent 1/19=0.053, so the veto is floored at runtime and single dissents cannot block an entry",
                    InpConsensusConflictDeadband);
    }
    else
    {
        PrintFormat("[VALIDATION] OK: InpConsensusConflictDeadband=%.2f", InpConsensusConflictDeadband);
    }
    
    if(InpAIConfidenceThreshold < 0.5 || InpAIConfidenceThreshold > 0.95)
    {
        PrintFormat("[VALIDATION] ERROR: InpAIConfidenceThreshold=%.2f out of range [0.5, 0.95]", InpAIConfidenceThreshold);
        valid = false;
    }
    else
    {
        PrintFormat("[VALIDATION] OK: InpAIConfidenceThreshold=%.2f", InpAIConfidenceThreshold);
    }
    
    // --- Position limits validation ---
    if(InpMaxPositionsTotal < 1 || InpMaxPositionsTotal > 100)
    {
        PrintFormat("[VALIDATION] ERROR: InpMaxPositionsTotal=%d out of range [1, 100]", InpMaxPositionsTotal);
        valid = false;
    }
    else
    {
        PrintFormat("[VALIDATION] OK: InpMaxPositionsTotal=%d", InpMaxPositionsTotal);
    }
    
    if(InpMaxPositionsPerSymbol < 1 || InpMaxPositionsPerSymbol > 20)
    {
        PrintFormat("[VALIDATION] ERROR: InpMaxPositionsPerSymbol=%d out of range [1, 20]", InpMaxPositionsPerSymbol);
        valid = false;
    }
    else
    {
        PrintFormat("[VALIDATION] OK: InpMaxPositionsPerSymbol=%d", InpMaxPositionsPerSymbol);
    }
    
    // --- Lot size validation ---
    if(InpLotSize < 0.01)
    {
        PrintFormat("[VALIDATION] ERROR: InpLotSize=%.2f below minimum 0.01", InpLotSize);
        valid = false;
    }
    else
    {
        PrintFormat("[VALIDATION] OK: InpLotSize=%.2f", InpLotSize);
    }
    
    // --- Magic number validation ---
    if(InpMagicNumber < 1)
    {
        PrintFormat("[VALIDATION] ERROR: InpMagicNumber=%I64d out of range [1, 9223372036854775807]", InpMagicNumber);
        valid = false;
    }
    else
    {
        PrintFormat("[VALIDATION] OK: InpMagicNumber=%I64d", InpMagicNumber);
    }
    
    // --- Spread validation ---
    if(InpMaxEntrySpreadPoints < 0)
    {
        PrintFormat("[VALIDATION] ERROR: InpMaxEntrySpreadPoints=%.0f cannot be negative", InpMaxEntrySpreadPoints);
        valid = false;
    }
    else
    {
        PrintFormat("[VALIDATION] OK: InpMaxEntrySpreadPoints=%.0f", InpMaxEntrySpreadPoints);
    }
    
    // --- AI dependency validation (L7-011) ---
    if(InpEnableOnnxAI)
    {
        // g_onnxModel is the only source the adapter ever receives, and no line in the tree writes it, so
        // this answers directly instead of telling the operator to go check the build.
        if(ArraySize(g_onnxModel) > 0)
            PrintFormat("[VALIDATION] OK: InpEnableOnnxAI=true | model bytes=%d", ArraySize(g_onnxModel));
        else
            Print("[VALIDATION] WARNING: InpEnableOnnxAI=true but g_onnxModel is empty - no #resource feeds it, so ONNX AI cannot vote on any symbol");
    }
    
    if(InpEnablePythonBridgeAI)
    {
        Print("[VALIDATION] INFO: InpEnablePythonBridgeAI=true - ensure Python bridge server is running at " + InpPythonBridgeEndpoint);
    }
    
    if(InpEnableStatisticalArbitrage && InpPythonBridgeMode == PYTHON_BRIDGE_OFF)
    {
        Print("[VALIDATION] ERROR: InpEnableStatisticalArbitrage requires InpPythonBridgeMode != PYTHON_BRIDGE_OFF");
        valid = false;
    }
    
    if(InpEnableAIMode && !InpEnableNeuralNetwork && !InpEnableTransformer && !InpEnableEnsemble && !InpEnableOnnxAI && !InpEnablePythonBridgeAI)
    {
        Print("[VALIDATION] WARNING: InpEnableAIMode=true but no AI voters enabled (NeuralNetwork/Transformer/Ensemble/OnnxAI/PythonBridgeAI)");
    }
    
    if(InpEnableTransformer || InpEnableEnsemble)
    {
        Print("[VALIDATION] WARNING: Experimental AI family enabled (Transformer/Ensemble) - ensure models are trained");
    }
    
    // --- Log level clamp (L7-017) ---
    if(InpLogLevel < 0 || InpLogLevel > 4)
    {
        PrintFormat("[VALIDATION] WARNING: InpLogLevel=%d out of range [0, 4], clamping", InpLogLevel);
        // Clamping will be done in OnInit
    }
    
    // --- Batch 99 validation (L7-024) ---
        if(InpEquityCurveEmaPeriod < 5 || InpEquityCurveEmaPeriod > 200)
        {
            PrintFormat("[VALIDATION] ERROR: InpEquityCurveEmaPeriod=%d out of range [5, 200]", InpEquityCurveEmaPeriod);
            valid = false;
        }
    
        if(InpEquityCurveReductionFactor <= 0.0 || InpEquityCurveReductionFactor > 1.0)
        {
            PrintFormat("[VALIDATION] ERROR: InpEquityCurveReductionFactor=%.2f out of range (0.0, 1.0]", InpEquityCurveReductionFactor);
            valid = false;
        }
    
        if(InpKellyFraction <= 0.0 || InpKellyFraction > 1.0)
        {
            PrintFormat("[VALIDATION] ERROR: InpKellyFraction=%.2f out of range (0.0, 1.0]", InpKellyFraction);
            valid = false;
        }
    
        // --- L7-012: Cross-validate Enterprise/Session inputs with symbol universe ---
        // Check if synthetics are in the symbol universe
        bool hasSynthetics = false;
        bool hasForex = false;
        string tempSymbols = InpSymbolsToTrade;
        StringReplace(tempSymbols, " ", "");
        int start = 0;
        while(start < StringLen(tempSymbols))
        {
            int comma = StringFind(tempSymbols, ",", start);
            if(comma < 0) comma = StringLen(tempSymbols);
            string sym = StringSubstr(tempSymbols, start, comma - start);
            if(sym != "")
            {
                if(IsSyntheticIndexSymbolName(sym))
                    hasSynthetics = true;
                else
                    hasForex = true;
            }
            start = comma + 1;
        }
    
        // InpAllowSyntheticOffHours only relevant if synthetics present
        if(InpAllowSyntheticOffHours && !hasSynthetics)
        {
            Print("[VALIDATION] INFO: InpAllowSyntheticOffHours=true but no synthetic symbols in universe; input will have no effect");
        }
    
        // InpUseSymbolClassProfiles=false with synthetics is dangerous
        if(!InpUseSymbolClassProfiles && hasSynthetics)
        {
            Print("[VALIDATION] WARNING: InpUseSymbolClassProfiles=false but synthetic symbols detected; synthetics will use forex defaults (unsafe)");
        }
    
        // InpUseSignalPipeline with no synthetics might be overkill for pure forex
        if(InpUseSignalPipeline && !hasSynthetics && !hasForex)
        {
            Print("[VALIDATION] WARNING: InpUseSignalPipeline=true but no symbols in universe");
        }
    
        // --- Fast Scalp Engine validation (L7-015) ---
        if(InpEnableScalpEngine)
        {
            if(InpScalpMaxLatencyMs < 50)
            {
                PrintFormat("[VALIDATION] WARNING: InpScalpMaxLatencyMs=%d below realistic minimum 50ms", InpScalpMaxLatencyMs);
            }
        
            // Check IOC/FOK support for all symbols
            string temp = InpSymbolsToTrade;
            StringReplace(temp, " ", "");
            start = 0;
            while(start < StringLen(temp))
            {
                int comma = StringFind(temp, ",", start);
                if(comma < 0) comma = StringLen(temp);
                string sym = StringSubstr(temp, start, comma - start);
                if(sym != "")
                {
                    // Select symbol if needed
                    if(!SymbolInfoInteger(sym, SYMBOL_SELECT))
                        SymbolSelect(sym, true);
                
                    long fillingMode = SymbolInfoInteger(sym, SYMBOL_FILLING_MODE);
                    bool hasIOC = (fillingMode & SYMBOL_FILLING_IOC) != 0;
                    bool hasFOK = (fillingMode & SYMBOL_FILLING_FOK) != 0;
                
                    if(!hasIOC && !hasFOK)
                    {
                        PrintFormat("[VALIDATION] INFO: Scalp engine: symbol %s does not support IOC/FOK (mode=%d); scalp orders will use market (RETURN) fill", sym, fillingMode);
                    }
                }
                start = comma + 1;
                            }
                        }
    
                    // --- DST offset validation (L7-022) ---
                        if(InpSessionDSTOffsetHours < -12 || InpSessionDSTOffsetHours > 12)
                        {
                            PrintFormat("[VALIDATION] ERROR: InpSessionDSTOffsetHours=%d out of range [-12, 12]", InpSessionDSTOffsetHours);
                            valid = false;
                        }
                        else
                        {
                            PrintFormat("[VALIDATION] OK: InpSessionDSTOffsetHours=%d", InpSessionDSTOffsetHours);
                        }
    
                        // --- Symbol Universe validation (L7-021) ---
                        PrintFormat("[VALIDATION] OK: InpAutoAddChartSymbol=%s", InpAutoAddChartSymbol ? "true" : "false");
    
                        // --- Skew Step Analyzer validation (L7-023) ---
                        if(InpSkewStepBufferSize < 10 || InpSkewStepBufferSize > 1000)
                        {
                            PrintFormat("[VALIDATION] ERROR: InpSkewStepBufferSize=%d out of range [10, 1000]", InpSkewStepBufferSize);
                            valid = false;
                        }
                        else
                        {
                            PrintFormat("[VALIDATION] OK: InpSkewStepBufferSize=%d", InpSkewStepBufferSize);
                        }
    
                        if(InpSkewStepCalmThreshold < 0.5 || InpSkewStepCalmThreshold > 0.99)
                        {
                            PrintFormat("[VALIDATION] ERROR: InpSkewStepCalmThreshold=%.2f out of range [0.5, 0.99]", InpSkewStepCalmThreshold);
                            valid = false;
                        }
                        else
                        {
                            PrintFormat("[VALIDATION] OK: InpSkewStepCalmThreshold=%.2f", InpSkewStepCalmThreshold);
                        }
    
                        if(InpSkewStepSmallThreshold < 0.01 || InpSkewStepSmallThreshold > 1.0)
                        {
                            PrintFormat("[VALIDATION] ERROR: InpSkewStepSmallThreshold=%.2f out of range [0.01, 1.0]", InpSkewStepSmallThreshold);
                            valid = false;
                        }
                        else
                        {
                            PrintFormat("[VALIDATION] OK: InpSkewStepSmallThreshold=%.2f", InpSkewStepSmallThreshold);
                        }
    
                        if(InpSkewStepLargeThreshold < 0.01 || InpSkewStepLargeThreshold > 2.0)
                        {
                            PrintFormat("[VALIDATION] ERROR: InpSkewStepLargeThreshold=%.2f out of range [0.01, 2.0]", InpSkewStepLargeThreshold);
                            valid = false;
                        }
                        else
                        {
                            PrintFormat("[VALIDATION] OK: InpSkewStepLargeThreshold=%.2f", InpSkewStepLargeThreshold);
                        }
    
                        // --- Symbols validation ---
                    if(StringLen(InpSymbolsToTrade) == 0)
    {
        Print("[VALIDATION] ERROR: InpSymbolsToTrade is empty");
        valid = false;
    }
    
    if(valid)
        Print("[VALIDATION] All input parameters validated successfully");
    else
        Print("[VALIDATION] FAILED - One or more input parameters invalid");
    
    return valid;
    }

// L10-012: Restore engine states from open positions on restart
    void RestoreEngineStates()
    {
        if(g_orchestrator == NULL) return;
    
        Print("[RESTORE-STATE] Scanning open positions to restore engine states...");
    
        // Get all open positions
        CPositionInfo posInfo;
        int totalPositions = PositionsTotal();
    
        int foundGridPositions = 0;
        int foundScalpPositions = 0;
        int foundSpikePositions = 0;
    
        for(int i = 0; i < totalPositions; i++)
        {
            if(!posInfo.SelectByIndex(i)) continue;

            ulong ticket = posInfo.Ticket();
            if(ticket == 0) continue;

            string symbol = posInfo.Symbol();
            if(symbol == "") continue;

            long magic = posInfo.Magic();
            double volume = posInfo.Volume();
            ENUM_POSITION_TYPE type = posInfo.PositionType();
            double priceOpen = posInfo.PriceOpen();
            double sl = posInfo.StopLoss();
            double tp = posInfo.TakeProfit();
            datetime timeOpen = posInfo.Time();
            string comment = posInfo.Comment();
        
            // Batch 152 (T-03): ownership check must be the EA-magic RANGE test.
            // The old (int)(magic/100) != InpMagicNumber prefix test truncated the
            // last two digits (123656 -> 1236), so it never matched and restart
            // restore silently skipped every EA-owned position.
            if(!g_orchestrator.GetTradeManager().IsEAOwnedMagic((long)magic)) continue;
        
            // Identify engine by comment tag (more reliable than magic offset)
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
    
        // Engines will rebuild their internal state naturally as they process ticks
        // GridRecoveryEngine scans positions in ManageGridPositions()
        // SpikeHunterEngine scans positions in GetActiveSpikePositions()
        // FastScalpEngine tracks positions via RegisterScalpPosition() on new entries
    
        PrintFormat("[RESTORE-STATE] Complete: grid=%d scalp=%d spike=%d (engines will rebuild state on next tick)",
                    foundGridPositions, foundScalpPositions, foundSpikePositions);
    }

// Expert Advisor Initialization
    int OnInit()
{
    // L7-001: Validate all inputs first
        if(!ValidateInputs())
        {
            Print("[CRITICAL] Input validation failed - EA will not start");
            return INIT_FAILED;
        }
    
        // L2-001: Initialize global shutdown flag
        g_shuttingDown = false;
    
        // Clamp log level (L7-017)
        if(InpLogLevel < 0 || InpLogLevel > 4)
        {
            PrintFormat("[VALIDATION] Clamping InpLogLevel from %d to range [0, 4]", InpLogLevel);
            // Note: InpLogLevel is const input, so we use global g_logLevel
            // This will be handled when g_logLevel is assigned
        }
    
        // Set global log level for legacy code compatibility
        g_logLevel = MathMax(0, MathMin(4, InpLogLevel));
    
        g_structLog.Init("MultiStrategyEA");
    
        Print("[MULTI-STRATEGY-EA] ========================================");
    Print("[MULTI-STRATEGY-EA] Advanced AI Trading System v2.0 Starting (Orchestrator Architecture)");
    Print("[MULTI-STRATEGY-EA] ========================================");
    
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
    
    if(AccountInfoDouble(ACCOUNT_BALANCE) < 100.0) // MIN_ACCOUNT_BALANCE
    {
        Alert("[CRITICAL] Insufficient account balance for safe operation!");
        return INIT_FAILED;
    }
    
    // Create and initialize orchestrator
            SOrchestratorConfig config = BuildOrchestratorConfig();
    
            // L7-005: Config version migration warning
            const int CURRENT_CONFIG_VERSION = 109;
            if(config.configVersion < CURRENT_CONFIG_VERSION)
            {
                PrintFormat("[CONFIG-MIGRATION] Config version %d is outdated (current: %d). Consider resetting to curated defaults.", 
                            config.configVersion, CURRENT_CONFIG_VERSION);
                if(config.configVersion < 100)
                {
                    Print("[CONFIG-MIGRATION] WARNING: Config version < 100 indicates legacy .set file. Manual review of strategy weights and flags recommended.");
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
    
                    // L10-007: Replay async trade requests from persistence (restart recovery)
                    g_orchestrator.GetTradeManager().ReplayAsyncTradeRequests();
    
                    // L10-012: Restore engine states from open positions
                    RestoreEngineStates();
    
                    // L2-001: Start timer AFTER orchestrator fully initialized (managers wired)
                    EventSetTimer(1);
    
                    Print("[MULTI-STRATEGY-EA] Initialization complete - EA is READY");
                Print("[MULTI-STRATEGY-EA] ========================================");
    
                return INIT_SUCCEEDED;
}

// Expert Advisor Deinitialization
void OnDeinit(const int reason)
{
    Print("[DEINIT-START] Deinitialization begun | reason=", reason, " (", GetDeInitReasonText(reason), ")");
    
    // L2-001: Set global shutdown flag FIRST to prevent OnTimer from accessing resources during cleanup
    g_shuttingDown = true;
    
    if(g_orchestrator != NULL)
    {
        g_orchestrator.Shutdown();
        delete g_orchestrator;
        g_orchestrator = NULL;
    }
    
    // L2-001: Destroy IndicatorManager BEFORE killing timer to prevent timer accessing invalid handles
    CIndicatorManager::DestroyInstance();
    
    // L9-006: Shutdown CJsonLogger to flush buffers and close file handles
    CJsonLogger::Shutdown();
    
    g_structLog.Shutdown();
    
    EventKillTimer();
    
    Print("[MULTI-STRATEGY-EA] ========================================");
    Print("[MULTI-STRATEGY-EA] Shutdown complete - Memory cleaned");
    Print("[MULTI-STRATEGY-EA] ========================================");
    
    Print("[DEINIT-COMPLETE] Deinitialization finished cleanly | reason=", reason, " (", GetDeInitReasonText(reason), ")");
}

// Timer Handler
void OnTimer()
{
    // L2-001: Early exit during shutdown to prevent accessing invalid resources
    if(g_shuttingDown)
        return;
    
    if(g_orchestrator != NULL && g_orchestrator.GetSystemInitialized())
    {
        g_orchestrator.OnTimer();
    }
}

// Expert Advisor Trade Transaction Handler
// L10-007: Process async trade confirmations via TradeManager
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
    if(g_shuttingDown)
        return;
    
    if(g_orchestrator != NULL && g_orchestrator.GetSystemInitialized())
    {
        // Forward to TradeManager for async trade confirmation handling
        g_orchestrator.GetTradeManager().ProcessTradeTransaction(trans, request, result);

        // Batch 152 (S-H-01): route deal confirmations into the scalp async
        // tracker. Without this, filled async scalp orders never registered in
        // the position tracker and their 1R/breakeven management never applied.
        if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
            g_orchestrator.ProcessScalpDealConfirmed(trans.deal, trans.order);

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
// L5-018: Detect input parameter changes and propagate to risk manager
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
    if(id == CHARTEVENT_OBJECT_CHANGE)
    {
        // Input parameter changed - propagate to risk manager
        PrintFormat("[EA-CHART-EVENT] Input parameter changed: object=%s", sparam);
        if(g_orchestrator != NULL && g_orchestrator.GetSystemInitialized())
        {
            // Propagate current input parameter values to risk components
            g_orchestrator.UpdateRiskParametersFromInputs(
                InpMaxRiskPerTrade, InpMaxDailyRisk, InpMaxPortfolioRisk,
                InpMaxDrawdown, InpDailyLossLimitPercent,
                InpAllowMinLotRoundUp, InpMinLotRiskMultiplier,
                InpEnableCompoundingTiers, InpRiskTier
            );
        }
    }
}

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

// Helper functions (kept for compatibility)
int GetMagicNumberPrefix() { return (int)InpMagicNumber; }

