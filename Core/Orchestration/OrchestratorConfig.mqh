// SOrchestratorConfig and helper structs
#property strict

#ifndef ORCHESTRATOR_CONFIG_MQH
#define ORCHESTRATOR_CONFIG_MQH

#include "../Utils/Enums.mqh"
#include "../Management/EnterpriseStrategyManager.mqh"

// Centralized per-strategy timeframe/intrabar config: the only place these are resolved.
struct SStrategyTimeframeConfig
{
    string              name;
    ENUM_TIMEFRAMES     defaultTF;
    bool                intrabarEnabled;
    ENUM_TIMEFRAMES     intrabarTF;
    bool                forceHigherOnM1Synthetic;

    SStrategyTimeframeConfig() : name(""), defaultTF(PERIOD_CURRENT), intrabarEnabled(false), intrabarTF(PERIOD_M5), forceHigherOnM1Synthetic(false) {}
};

struct SStrategyIntrabarConfig
{
    string              name;
    ENUM_INTRABAR_POLICY defaultPolicy;
    bool                syntheticLeanPrimary;

    SStrategyIntrabarConfig() : name(""), defaultPolicy(INTRABAR_POLICY_OFF), syntheticLeanPrimary(false) {}
};

// Static sizing for strategy config rows: must stay >= the number of strategies, because every
// strategy owns one policy row (FVG Scalper takes [21], Statistical Arbitrage [22]). Borrowing a
// neighbour's slot clobbers its policy. Legacy mode never indexes 21/22.
#define MAX_STRATEGY_CONFIGS 23

// SOrchestratorConfig - All input parameters grouped by domain
struct SOrchestratorConfig
{
    // General
    long    magicNumber;
    double  lotSize;
    bool    useEnhancedRisk;
    double  maxRiskPerTrade;
    double  maxDailyRisk;
    double  maxPortfolioRisk;
    double  maxDrawdown;
    double  dailyLossLimitPercent;
    // Basket-level equity stop: peak-equity drawdown guard
    bool    basketEquityStopEnabled;
    double  basketEquityStopDrawdownPct;
    bool    basketEquityStopCloseOnBreach;
    ENUM_RISK_TIER riskTier;
    bool    enableCompoundingTiers;
        int     compoundingTierCheckIntervalSec;
        bool    enableSessionWeights;
        bool    enableSkewStepAnalyzer;
        bool    enableFamilyWeightMatrix;
        bool    allowMinLotRoundUp;
        double  minLotRiskMultiplier;
    string  symbolsToTrade;
    int     minSecondsBetweenTrades;
    int     maxPositionsTotal;
    int     maxPositionsTotalMin;
    int     maxPositionsPerSymbol;
    int     maxPositionsPerSymbolMin;
    int     maxTradeSendsPerCycle;

    // Strategy selection
    bool    enableMomentum;
    bool    enableTrend;
    bool    enableSupportResistance;
    bool    enableCandlestick;
    bool    candlestickRequireTrend;
    bool    enableMeanReversion;
    bool    enableVolatilityBreakout;
    bool    enableFVGScalper;
    bool    enableTurtleSoup;
    bool    enableBreakerBlock;
    bool    enableNYOpenGap;
    bool    enableAsianRangeBreak;
    bool    enableStatisticalArbitrage;
    double  trendADXNoTrendThreshold;
    double  syntheticADXNoTrendThreshold;
    bool    useCuratedStrategySet;
    bool    useSymbolClassProfiles;
    bool    enableKalmanMR;
    double  kalmanLambda;
    bool    enableChangepointDetect;
    double  cpdHazardThreshold;
    bool    enableFourStateRegime;
    bool    enableVolTargeting;
    double  targetVol;
    double  volMinScale;
    double  volMaxScale;
    bool    enableLiquiditySweep;
    bool    enableRangeCompression;
    bool    enableExitOptimizer;

    // EA operating mode
    ENUM_EA_MODE eaMode;
    bool    enableVisualAnalysis;
    int     maxVisualObjects;

    // Consensus quorum
    double  quorumThreshold;
    int     minLiveVoters;
    double  consensusConflictDeadband;
    double  consensusMinReadyWeightRatio;
    double  consensusSupportFloorNewBar;
    double  consensusSupportFloorIntrabar;
    bool    allowSparseIntrabarSingleVoter;
    double  sparseIntrabarMinQuality;
    double  sparseIntrabarMinSupportRatio;
    double  sparseIntrabarMinReadyCoverage;
    CEnterpriseStrategyManager::ENUM_QUORUM_PROFILE quorumProfile;

    // Strategy weights
    double  weightMomentum;
    double  weightTrend;
    double  weightSupportResistance;
    double  weightCandlestick;
    double  weightMeanReversion;
    double  weightVolatilityBreakout;
    double  weightStatisticalArbitrage;
    double  weightFVGScalper;
    double  weightTurtleSoup;
    double  weightBreakerBlock;
    double  weightNYOpenGap;
    double  weightAsianRangeBreak;
    double  weightLiquiditySweep;
    double  weightRangeCompression;

    // AI Engine settings
    bool    enableAIMode;
    bool    enableNeuralNetwork;
    bool    enableTransformer;
    bool    enableEnsemble;
    bool    enableOnnxAI;
    bool    enablePythonBridgeAI;
    ENUM_PYTHON_BRIDGE_MODE pythonBridgeMode;
    string  pythonBridgeEndpoint;
    int     pythonBridgeRequestTimeoutMs;
    int     pythonBridgeHeartbeatTimeoutSec;
    int     pythonBridgeMaxReconnectAttempts;
    int     pythonBridgeReconnectBackoffMs;
    bool    enableExternalLLM;
    string  externalLLMEndpoint;
    double  aiConfidenceThreshold;
    double  aiWeightMultiplier;
    double  aiDrawdownSizingLimit;

    bool    dashboardEnabled;
    string  dashboardEndpoint;
    int     dashboardPushIntervalSec;
    bool    dashboardControlEnabled;

    bool    enableLiveAuthorityGate;
    bool    allowAIWarmStartLive;
    bool    allowHybridAIStandalone;
    double  aiStandaloneMinConfidence;
    double  aiStandaloneRelaxedConfidence;
    int     hybridGateRelaxAfterCycles;
    int     authorityMinSamples;
    int     authorityTrialHorizonSeconds;
    int     authorityMaxTrackedTrials;
    double  authorityMinExpectancyR;
    double  authorityMinProfitFactor;
    double  authorityMinCostScore;
    double  authorityMinReadinessScore;
    double  authorityMinContextScore;
    double  aiBootstrapRiskMultiplier;
    double  aiPromotedRiskMultiplier;
    double  nonAIPromotedRiskMultiplier;

    bool    enableNNAttributionDiagnostics;
    bool    runNNAttributionSelfTest;

    // Runtime cadence
    bool    enableHybridCadence;
    bool    intrabarChartSymbolOnly;
    bool    intrabarDynamicQuorumEnabled;
    double  pipelineMinConfidence;
    double  intrabarSingleVoterMinConfidence;
    double  syntheticLeanSparseIntrabarMinQuality;
    double  syntheticLeanIntrabarSingleVoterMinConfidence;
    double  pipelineIntrabarConfidenceCap;
    bool    pipelineEnableRegimeCostGate;
    double  pipelineMaxSpreadToAtrRatio;
    int     pipelineSpreadShockCooldownSec;
    double  pipelineLateEntryZScoreLimit;
    double  atrCrisisRatioThreshold;
    double  atrCrisisRatioThresholdSynthetic;
    double  atrCrisisRatioThresholdVolatility;
    double  atrCrisisRatioThresholdDefault;
    double  hardSpreadCutoffPoints;
    int     deadlockAttributionIntervalSec;
    int     heartbeatInterval;
    bool    enableMomentumScalping;
    int     momentumScalpCooldownSeconds;
    ENUM_TIMEFRAMES momentumScalpTimeframe;
    ENUM_TIMEFRAMES candlestickIntrabarTimeframe;
    ENUM_INTRABAR_POLICY intrabarEligibilityMomentum;
    ENUM_INTRABAR_POLICY intrabarEligibilityTrend;
    ENUM_INTRABAR_POLICY intrabarEligibilitySupportResistance;
    ENUM_INTRABAR_POLICY intrabarEligibilityCandlestick;
    ENUM_INTRABAR_POLICY intrabarEligibilityMeanReversion;
    ENUM_INTRABAR_POLICY intrabarEligibilityVolatilityBreakout;
    ENUM_INTRABAR_POLICY intrabarEligibilityNeuralNetworkAI;
    ENUM_INTRABAR_POLICY intrabarEligibilityTransformerAI;
    ENUM_INTRABAR_POLICY intrabarEligibilityEnsembleAI;
    ENUM_INTRABAR_POLICY intrabarEligibilityOnnxAI;
    ENUM_INTRABAR_POLICY intrabarEligibilityPythonBridgeAI;
    int     maxSignalEvaluationsPerCycle;
    int     readinessReuseTtlSeconds;
    bool    enableNNOnlineTraining;
    bool    enableNNWeightMutation;
    bool    enableNNPseudoLabeling;
    int     nnPseudoLabelBarsAhead;
    int     nnSampleIntervalSeconds;
    int     nnCheckpointEveryLabeled;

    SStrategyTimeframeConfig strategyTimeframeConfigs[MAX_STRATEGY_CONFIGS];
    SStrategyIntrabarConfig  strategyIntrabarConfigs[MAX_STRATEGY_CONFIGS];
    int                     strategyConfigCount;

    // Signal validator
    int     validatorNewBarMinConfluence;
    double  validatorNewBarMinQuality;
    double  validatorNewBarMinConfidence;
    int     validatorIntrabarMinConfluence;
    double  validatorIntrabarMinQuality;
    double  validatorIntrabarMinConfidence;

    // Execution safety
    ENUM_ORDER_TYPE_FILLING orderFillingMode;
    int     tradeSlippagePoints;
    double  maxEntrySpreadPoints;
    double  maxEntryDriftPoints;
    int     protectiveModifyCooldownSec;
    bool    enableSignalReversalExit;
    double  signalReversalMinConfidence;
    bool    signalReversalProfitGuard;
    double  signalReversalMinLossR;
    double  signalReversalMaxLossR;
    int     signalReversalMinTimeSec;
    bool    enableStructuralInvalidation;
    bool    enablePositionLifecycleManager;
    double  lifecycleBreakevenBufferPoints;
    double  lifecycleTrailingDistancePoints;
    double  lifecycleTrailingStepPoints;
    bool    lifecycleUseATRTrailing;
    double  lifecycleATRMultiplier;

    bool    enableMaxHoldTime;
    int     maxHoldHoursIntraday;
    int     maxHoldHoursSwing;
    bool    maxHoldOnlyIfLoss;

    bool    emergencyFlattenAllAccountPositions;
    int     unprotectedRemediationIntervalSec;
    int     unprotectedMaxRestoreAttempts;
    bool    closeUnprotectedOnRemediationFailure;
    double  syntheticSpikeVelocityMultiplier;
    int     syntheticSpikePauseSeconds;

    // Fast scalp engine
    bool    enableScalpEngine;
    bool    scalpAsyncMode;
    uint    scalpMaxLatencyMs;

    bool    enableDynamicSlippage;
    double  dynamicSlippageAtrPercent;
    int     dynamicSlippageMinPoints;
    int     dynamicSlippageMaxMultiplier;
    int     dynamicSlippageAtrPeriod;

    // Spike detection
    int     spikeConfirmWindows;

    bool    spikeHunterEnabled;
    double  spikeHunterVelocityMult;
    int     spikeHunterMinConsecTicks;
    int     spikeHunterConsecWindowMs;
    double  spikeHunterATRCompression;
    double  spikeHunterSLAtrMult;
    double  spikeHunterTPAtrMult;
    int     spikeHunterMaxPositions;
    int     spikeHunterCooldownMs;
    int     spikeHunterLongTermCooldownMs;
    bool    spikeHunterPushAlerts;
    int     spikeHunterAlertThrottle;
    int     spikeHunterMinConfluence;

    bool    multiAssetProfilerEnabled;
    bool    derivProfilerEnabled;
    bool    gridRecoveryEnabled;
    bool    atrScalpingEnabled;

    // Mathematical engines
    bool    enableHurstEngine;
    int     hurstLookback;
    bool    enableOUProcess;
    int     ouLookback;
    bool    enableOFIProxy;
    int     ofiSlowWindow;
    bool    enableVPINFilter;
    double  vpinExtremeThreshold;
    int     vpinNumBuckets;

    // Institutional TA
    bool    enableVWAPEngine;
    bool    enableVolumeProfile;
    bool    enableCVDEngine;
    int     vwapMinPeriodBars;
    double  vwapBand1;
    double  vwapBand2;
    double  vwapBand3;
    int     vpLookback;
    int     vpResolution;
    int     cvdDivergenceLookback;

    // Enterprise mode
    bool    useSignalPipeline;
    bool    allowSyntheticOffHours;
    double  minTrendStrength;
    double  maxVolatility;
    bool    enableStructureFilter;
    bool    enableLiquidityFilter;
    int     dormancyStrikeBars;
    int     dormancyCooldownMinutes;
    int     portfolioMaxPositionsPerSymbol;
    int     maxPositionsSameBase;
    bool    enableClusterRiskGovernance;
    bool    enableClusterMutex;
    int     riskMaxConcurrentPerCluster;
    double  riskMaxClusterExposurePct;

    // Portfolio profit target
    double  dailyProfitTargetPercent;
    double  profitTrailFactor;
    double  profitTargetHardFloorRatio;
    int     dailyHaltCooldownMinutes;

    // Dual-mode auto-switching
    bool    enableAutoModeSwitch;
    double  conservativeBaseRiskPct;
    double  aggressiveBaseRiskPct;
    double  modeSwitchDrawdownPct;
    int     modeSwitchWinStreak;

    // Symbol Validation
    long    symbolMaxSpreadPoints;
    long    symbolMinDailyVolumeLots;
    bool    symbolEnableVolumeCheck;

        int     logLevel;
        int     logVerbosity;  // ENUM_LOG_VERBOSITY
        bool    logDerivFamilyDetection;

    int     equityCurveEmaPeriod;
    double  equityCurveReductionFactor;
    double  kellyFraction;

    bool    strictEAMode;

    // Config versioning
    int     configVersion;

    // Symbol Universe
    bool    autoAddChartSymbol;

    // Skew Step Analyzer
    int     skewStepBufferSize;
    double  skewStepCalmThreshold;
    double  skewStepSmallThreshold;
    double  skewStepLargeThreshold;

    // Session Weight Manager
    int     sessionDSTOffsetHours;

    SOrchestratorConfig()
    {
        magicNumber = 123456;
        lotSize = 0.1;
        useEnhancedRisk = true;
        maxRiskPerTrade = 5.0;
        maxDailyRisk = 40.0;
        maxPortfolioRisk = 60.0;
        maxDrawdown = 15.0;
        dailyLossLimitPercent = 10.0;
        riskTier = RISK_TIER_MODERATE;
        enableCompoundingTiers = true;
                compoundingTierCheckIntervalSec = 60;
                enableSessionWeights = true;
                enableSkewStepAnalyzer = true;
                enableFamilyWeightMatrix = true;
                allowMinLotRoundUp = false;
                minLotRiskMultiplier = 1.0;
        symbolsToTrade = "Volatility 25 Index,Volatility 75 Index,Boom 1000 Index,Crash 1000 Index,Jump 25 Index,Jump 75 Index,Step Index,EURUSD,GBPUSD,USDJPY,AUDUSD,XAUUSD,BTCUSD";
        minSecondsBetweenTrades = 10;
        maxPositionsTotal = 15;
        maxPositionsTotalMin = 3;
        maxPositionsPerSymbol = 5;
        maxPositionsPerSymbolMin = 1;
        maxTradeSendsPerCycle = 3;

        enableMomentum = true;
        enableTrend = true;
        enableSupportResistance = true;
        enableCandlestick = true;
        candlestickRequireTrend = false;
        enableMeanReversion = true;
        enableVolatilityBreakout = true;
        enableFVGScalper = true;
        enableTurtleSoup = true;
        enableBreakerBlock = true;
        enableNYOpenGap = true;
        enableAsianRangeBreak = true;
        enableStatisticalArbitrage = false;
        trendADXNoTrendThreshold = 12.0;
        syntheticADXNoTrendThreshold = 10.0;
        useCuratedStrategySet = true;
        useSymbolClassProfiles = false;
        enableKalmanMR = true;
        kalmanLambda = 500.0;
        enableChangepointDetect = true;
        cpdHazardThreshold = 0.3;
        enableFourStateRegime = true;
        enableVolTargeting = true;
        targetVol = 0.15;
        volMinScale = 0.2;
        volMaxScale = 3.0;
        enableLiquiditySweep = true;
        enableRangeCompression = true;
        enableExitOptimizer = true;

        eaMode = EA_MODE_HYBRID;
        enableVisualAnalysis = true;
        maxVisualObjects = 500;

        quorumThreshold = 0.60;
        minLiveVoters = 2;
        consensusConflictDeadband = 0.35;
        consensusMinReadyWeightRatio = 0.40;
        consensusSupportFloorNewBar = 0.20;
        consensusSupportFloorIntrabar = 0.15;
        allowSparseIntrabarSingleVoter = false;
        sparseIntrabarMinQuality = 0.85;
        sparseIntrabarMinSupportRatio = 0.40;
        sparseIntrabarMinReadyCoverage = 0.85;
        quorumProfile = CEnterpriseStrategyManager::QUORUM_BALANCED;

        weightMomentum = 1.0;
        weightTrend = 1.2;
        weightSupportResistance = 1.8;
        weightCandlestick = 0.8;
        weightMeanReversion = 1.8;
        weightVolatilityBreakout = 2.0;
        weightStatisticalArbitrage = 1.5;
        weightFVGScalper = 1.8;
        weightTurtleSoup = 1.6;
        weightBreakerBlock = 1.7;
        weightNYOpenGap = 1.3;
        weightAsianRangeBreak = 1.3;
        weightLiquiditySweep = 1.9;
        weightRangeCompression = 1.7;

        enableAIMode = false;
        enableNeuralNetwork = false;
        enableTransformer = false;
        enableEnsemble = false;
        enableOnnxAI = false;
        pythonBridgeMode = PYTHON_BRIDGE_OFF;
        pythonBridgeEndpoint = "http://127.0.0.1:8000";
        pythonBridgeRequestTimeoutMs = 2000;
        pythonBridgeHeartbeatTimeoutSec = 30;
        pythonBridgeMaxReconnectAttempts = 5;
        pythonBridgeReconnectBackoffMs = 2000;
        enableExternalLLM = false;
        externalLLMEndpoint = "http://localhost:11434";
        aiConfidenceThreshold = 0.70;
        aiWeightMultiplier = 1.0;
        aiDrawdownSizingLimit = 0.20;

        dashboardEnabled = true;
        dashboardEndpoint = "http://127.0.0.1:8765";
        dashboardPushIntervalSec = 5;
        dashboardControlEnabled = false;

        enableLiveAuthorityGate = false;
        allowAIWarmStartLive = true;
        allowHybridAIStandalone = true;
        aiStandaloneMinConfidence = 0.65;
        aiStandaloneRelaxedConfidence = 0.60;
        hybridGateRelaxAfterCycles = 5;
        authorityMinSamples = 12;
        authorityTrialHorizonSeconds = 900;
        authorityMaxTrackedTrials = 256;
        authorityMinExpectancyR = 0.03;
        authorityMinProfitFactor = 1.10;
        authorityMinCostScore = 0.50;
        authorityMinReadinessScore = 0.52;
        authorityMinContextScore = 0.48;
        aiBootstrapRiskMultiplier = 0.50;
        aiPromotedRiskMultiplier = 1.00;
        nonAIPromotedRiskMultiplier = 0.65;

        enableNNAttributionDiagnostics = false;
        runNNAttributionSelfTest = false;

        enableHybridCadence = true;
        intrabarChartSymbolOnly = false;
        intrabarDynamicQuorumEnabled = true;
        pipelineMinConfidence = 0.55;
        intrabarSingleVoterMinConfidence = 0.95;
        syntheticLeanSparseIntrabarMinQuality = 0.85;
        syntheticLeanIntrabarSingleVoterMinConfidence = 0.95;
        pipelineIntrabarConfidenceCap = 0.05;
        pipelineEnableRegimeCostGate = true;
        pipelineMaxSpreadToAtrRatio = 0.50;
        pipelineSpreadShockCooldownSec = 90;
        pipelineLateEntryZScoreLimit = 4.00;
        atrCrisisRatioThreshold = 5.0;
        atrCrisisRatioThresholdSynthetic = 15.0;
        atrCrisisRatioThresholdVolatility = 10.0;
        atrCrisisRatioThresholdDefault = 8.0;
        hardSpreadCutoffPoints = 200.0;
        deadlockAttributionIntervalSec = 60;
        heartbeatInterval = 60;
        enableMomentumScalping = true;
        momentumScalpCooldownSeconds = 20;
        momentumScalpTimeframe = PERIOD_M5;
        candlestickIntrabarTimeframe = PERIOD_M5;
        intrabarEligibilityMomentum = INTRABAR_POLICY_LIVE;
        intrabarEligibilityTrend = INTRABAR_POLICY_LIVE;
        intrabarEligibilitySupportResistance = INTRABAR_POLICY_LIVE;
        intrabarEligibilityCandlestick = INTRABAR_POLICY_LIVE;
        intrabarEligibilityMeanReversion = INTRABAR_POLICY_LIVE;
        intrabarEligibilityVolatilityBreakout = INTRABAR_POLICY_LIVE;
        intrabarEligibilityNeuralNetworkAI = INTRABAR_POLICY_LIVE;
        intrabarEligibilityTransformerAI = INTRABAR_POLICY_LIVE;
        intrabarEligibilityEnsembleAI = INTRABAR_POLICY_LIVE;
        intrabarEligibilityOnnxAI = INTRABAR_POLICY_LIVE;
        intrabarEligibilityPythonBridgeAI = INTRABAR_POLICY_LIVE;
        maxSignalEvaluationsPerCycle = 8;
        readinessReuseTtlSeconds = 60;
        enableNNOnlineTraining = true;
        enableNNWeightMutation = false;
        enableNNPseudoLabeling = true;
        nnPseudoLabelBarsAhead = 10;
        nnSampleIntervalSeconds = 15;
        nnCheckpointEveryLabeled = 3;

        validatorNewBarMinConfluence = 1;
        validatorNewBarMinQuality = 0.68;
        validatorNewBarMinConfidence = 0.55;
        validatorIntrabarMinConfluence = 1;
        validatorIntrabarMinQuality = 0.70;
        validatorIntrabarMinConfidence = 0.60;

        orderFillingMode = ORDER_FILLING_IOC;
        tradeSlippagePoints = 50;
        maxEntrySpreadPoints = 15000.0;
        maxEntryDriftPoints = 80.0;
        protectiveModifyCooldownSec = 5;
        enableSignalReversalExit = true;
        signalReversalMinConfidence = 0.58;
        signalReversalProfitGuard = true;
        signalReversalMinLossR = 0.25;
        signalReversalMaxLossR = 0.82;
        signalReversalMinTimeSec = 45;
        enableStructuralInvalidation = true;
        enablePositionLifecycleManager = true;
        lifecycleBreakevenBufferPoints = 50.0;
        lifecycleTrailingDistancePoints = 150.0;
        lifecycleTrailingStepPoints = 30.0;
        lifecycleUseATRTrailing = false;
        lifecycleATRMultiplier = 1.5;

        enableMaxHoldTime = true;
        maxHoldHoursIntraday = 24;
        maxHoldHoursSwing = 120;
        maxHoldOnlyIfLoss = true;

        // Opt-in only: true flattens EVERY position on the account, manual trades and other EAs'
        // included. Default is EA-scoped; set true only on a single-strategy account you control.
        emergencyFlattenAllAccountPositions = false;
        unprotectedRemediationIntervalSec = 15;
        unprotectedMaxRestoreAttempts = 3;
        closeUnprotectedOnRemediationFailure = true;
        syntheticSpikeVelocityMultiplier = 3.0;
        syntheticSpikePauseSeconds = 30;

        enableScalpEngine = true;
        scalpAsyncMode = false;
        scalpMaxLatencyMs = 500;

        enableDynamicSlippage = true;
        dynamicSlippageAtrPercent = 0.20;
        dynamicSlippageMinPoints = 10;
        dynamicSlippageMaxMultiplier = 10;
        dynamicSlippageAtrPeriod = 14;

        spikeConfirmWindows = 2;

        spikeHunterEnabled = true;
        spikeHunterVelocityMult = 1.8;
        spikeHunterMinConsecTicks = 8;
        spikeHunterConsecWindowMs = 60000;
        spikeHunterATRCompression = 0.80;
        spikeHunterSLAtrMult = 1.5;
        spikeHunterTPAtrMult = 3.0;
        spikeHunterMaxPositions = 3;
        spikeHunterCooldownMs = 60000;
        spikeHunterLongTermCooldownMs = 60000;
        spikeHunterPushAlerts = true;
        spikeHunterAlertThrottle = 120;
        spikeHunterMinConfluence = 2;

        multiAssetProfilerEnabled = true;
        derivProfilerEnabled = true;
        gridRecoveryEnabled = true;
        atrScalpingEnabled = true;

        enableHurstEngine = true;
        hurstLookback = 300;
        enableOUProcess = true;
        ouLookback = 100;
        enableOFIProxy = true;
        ofiSlowWindow = 100;
        enableVPINFilter = true;
        vpinExtremeThreshold = 0.7;
        vpinNumBuckets = 50;

        enableVWAPEngine = true;
        enableVolumeProfile = true;
        enableCVDEngine = true;
        vwapMinPeriodBars = 30;
        vwapBand1 = 1.0;
        vwapBand2 = 1.5;
        vwapBand3 = 2.0;
        vpLookback = 20;
        vpResolution = 20;
        cvdDivergenceLookback = 30;

        useSignalPipeline = true;
        allowSyntheticOffHours = true;
        minTrendStrength = 50.0;
        maxVolatility = 3.0;
        enableStructureFilter = true;
        enableLiquidityFilter = true;
        dormancyStrikeBars = 3;
        dormancyCooldownMinutes = 30;
        portfolioMaxPositionsPerSymbol = 3;
        maxPositionsSameBase = 3;
        enableClusterRiskGovernance = true;
        enableClusterMutex = true;
        riskMaxConcurrentPerCluster = 3;
        riskMaxClusterExposurePct = 5.0;

        dailyProfitTargetPercent = 2.0;
        profitTrailFactor = 0.7;
        profitTargetHardFloorRatio = 0.50;
        dailyHaltCooldownMinutes = 30;

        enableAutoModeSwitch = true;
        conservativeBaseRiskPct = 1.0;
        aggressiveBaseRiskPct = 3.0;
        modeSwitchDrawdownPct = 5.0;
        modeSwitchWinStreak = 5;

        symbolMaxSpreadPoints = 1500;
        symbolMinDailyVolumeLots = 1000;
        symbolEnableVolumeCheck = true;

        logLevel = 1;
                logVerbosity = VERBOSITY_NORMAL;
                logDerivFamilyDetection = true;  // L7-013

        equityCurveEmaPeriod = 20;
        equityCurveReductionFactor = 0.50;
        kellyFraction = 0.25;
        configVersion = 109;  // Current config version (batch number)
        autoAddChartSymbol = true;
        skewStepBufferSize = 200;
        skewStepCalmThreshold = 0.80;
        skewStepSmallThreshold = 0.2;
        skewStepLargeThreshold = 0.5;
        sessionDSTOffsetHours = 0;

        // strategyTimeframeConfigs/strategyIntrabarConfigs are filled by InitializeStrategyConfigs(),
        // not by this constructor; only the count is set here.
        strategyConfigCount = 0;
    }
};

#endif // ORCHESTRATOR_CONFIG_MQH
