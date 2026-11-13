// SOrchestratorConfig and helper structs
#property strict

#ifndef ORCHESTRATOR_CONFIG_MQH
#define ORCHESTRATOR_CONFIG_MQH

#include "../Utils/Enums.mqh"
#include "../Management/EnterpriseStrategyManager.mqh"

// Per-slot registration config, indexed by the catalog row's siPolicyIndex. A timeframe of
// PERIOD_CURRENT means "register on the manager's base (chart) timeframe".
struct SStrategyIntrabarConfig
{
    ENUM_INTRABAR_POLICY defaultPolicy;
    bool                 syntheticLeanPrimary;

    SStrategyIntrabarConfig() : defaultPolicy(INTRABAR_POLICY_OFF), syntheticLeanPrimary(false) {}
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
    double  adxMinLotMultiplier;
    bool    adxAllowNoTrendTrading;
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
    bool    enableDonchianBreakout;
    bool    enableRSI2Pullback;
    bool    enableDailyLevelBreakout;
    bool    enableDailyLevelFade;
    bool    enableEMARibbon;
    bool    enableGapContinuation;
    bool    enableOpeningRangeBreakout;
    bool    enableICTSessionGap;
    bool    enableICTStructureShift;

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
    CEnterpriseStrategyManager::ENUM_QUORUM_PROFILE quorumProfile;
    double  singleVoterFloor;              // lone-voter confidence floor, the gate every measured reject hit
    int     symbolLossStreakLimit;         // consecutive losing closes on one symbol before it is stood down; 0 = off
    int     symbolLossStreakCooldownMin;    // how long the symbol stays stood down
    double  symbolStreakRiskScale;         // risk multiplier for a symbol in a losing run; 1.0 = off
    int     symbolStreakRiskMinCount;      // consecutive losing closes that trigger the smaller stake

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
    double  weightDonchianBreakout;
    double  weightRSI2Pullback;
    double  weightDailyLevelBreakout;
    double  weightDailyLevelFade;
    double  weightEMARibbon;
    double  weightGapContinuation;
    double  weightOpeningRangeBreakout;
    double  weightICTSessionGap;
    double  weightICTStructureShift;

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
    bool    allowHybridAIStandalone;
    double  aiStandaloneMinConfidence;
    double  aiStandaloneRelaxedConfidence;
    int     hybridGateRelaxAfterCycles;
    int     authorityMinSamples;
    double  authorityMinExpectancyR;
    double  authorityMinProfitFactor;
    double  authorityMinCostScore;
    double  authorityMinReadinessScore;
    double  authorityMinContextScore;
    double  aiBootstrapRiskMultiplier;
    double  aiPromotedRiskMultiplier;

    bool    enableNNAttributionDiagnostics;
    bool    runNNAttributionSelfTest;

    // Runtime cadence
    bool    intrabarDynamicQuorumEnabled;
    double  pipelineMinConfidence;
    double  pipelineIntrabarConfidenceCap;
    bool    pipelineEnableRegimeCostGate;
    bool    pipelineEngineRegistry;          // binds the shared math-engine registry to each symbol's pipeline
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

    ENUM_TIMEFRAMES         strategyTimeframes[MAX_STRATEGY_CONFIGS];
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

    // The loss guard has run on its constructor numbers since the first build: ConfigureLossMinimization
    // had no caller. These defaults are those same numbers, so binding them changes nothing until asked.
    bool    lossGuardAdverseMomentumExit;
    double  lossGuardAdverseMomentumATRMultiplier;
    int     lossGuardConsecutiveLossLimit;
    int     lossGuardConsecutiveLossCooldownSec;
    double  lossGuardDailyLossCircuitBreakerPercent;
    double  lossGuardPositionLossLimitPercent;

    // Crisis limits and hardcoded thresholds (Item 19): class-member defaults replaced by operator inputs.
    double  positionSizerMaxLotSize;
    int     positionSizerVolatilityLookback;
    int     positionSizerEquityCurveLookback;
    double  riskMarginHealthMaxFreeMarginUsage;
    double  riskMarginHealthMinMarginLevel;
    double  portfolioRiskCvarConfidence;
    double  portfolioRiskCvarMaxRisk;
    int     portfolioRiskMaxEquityCurveHistory;
    double  riskValidationMinAccountBalance;
    double  portfolioRiskStopFallbackPoints;

    bool    emergencyFlattenAllAccountPositions;
    int     unprotectedRemediationIntervalSec;
    int     unprotectedMaxRestoreAttempts;
    double  syntheticSpikeVelocityMultiplier;
    int     syntheticSpikePauseSeconds;

    // Fast scalp engine
    bool    enableScalpEngine;
    bool    scalpAsyncMode;
    uint    scalpMaxLatencyMs;
    string  scalpSymbolsCsv;          // "" = every symbol; otherwise comma-separated names the scalp may trade

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

    // Enterprise mode
    bool    useSignalPipeline;
    // Prefer the strategy's own designed SL/TP over the ATR fallback when building a candidate.
    // Carried here because the headers that need it (EAOrchestrator, CandidateBuilder) cannot read a
    // program `input` - an input exists only in the .mq5 translation unit.
    bool    useStrategyStops;
    bool    allowSyntheticOffHours;
    double  minTrendStrength;
    double  maxVolatility;
    bool    enableStructureFilter;
    bool    enableLiquidityFilter;
    int     dormancyStrikeBars;
    int     dormancyCooldownMinutes;
    int     maxPositionsSameBase;
    bool    enableClusterRiskGovernance;
    bool    enableClusterMutex;
    int     riskMaxConcurrentPerCluster;
    double  riskMaxClusterExposurePct;

    // Portfolio profit target
    double  dailyProfitTargetPercent;
    double  profitTrailFactor;
    int     dailyHaltCooldownMinutes;

    // Dual-mode auto-switching

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
        adxMinLotMultiplier = 1.0;
        adxAllowNoTrendTrading = true;
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
        enableDonchianBreakout = true;
        enableRSI2Pullback = true;
        enableDailyLevelBreakout = true;
        enableDailyLevelFade = true;
        enableEMARibbon = true;
        enableGapContinuation = true;
        enableOpeningRangeBreakout = true;
        enableICTSessionGap = true;
        enableICTStructureShift = true;

        eaMode = EA_MODE_HYBRID;
        enableVisualAnalysis = true;
        maxVisualObjects = 500;

        quorumThreshold = 0.60;
        minLiveVoters = 2;
        consensusConflictDeadband = 0.35;
        consensusMinReadyWeightRatio = 0.40;
        consensusSupportFloorNewBar = 0.20;
        consensusSupportFloorIntrabar = 0.15;
        quorumProfile = CEnterpriseStrategyManager::QUORUM_BALANCED;
        singleVoterFloor = 0.70;
        symbolLossStreakLimit = 0;          // off by default: the breaker is an A/B input, not a shipped rule
        symbolLossStreakCooldownMin = 60;
        symbolStreakRiskScale = 1.0;        // off: the sizing rule ships disabled like the brake
        symbolStreakRiskMinCount = 2;

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
        weightDonchianBreakout = 1.6;
        weightRSI2Pullback = 1.5;
        weightDailyLevelBreakout = 1.7;
        weightDailyLevelFade = 1.5;
        weightEMARibbon = 1.6;
        weightGapContinuation = 1.5;
        weightOpeningRangeBreakout = 1.7;
        weightICTSessionGap = 1.5;
        weightICTStructureShift = 1.6;

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
        allowHybridAIStandalone = true;
        aiStandaloneMinConfidence = 0.65;
        aiStandaloneRelaxedConfidence = 0.60;
        hybridGateRelaxAfterCycles = 5;
        authorityMinSamples = 12;
        authorityMinExpectancyR = 0.03;
        authorityMinProfitFactor = 1.10;
        authorityMinCostScore = 0.50;
        authorityMinReadinessScore = 0.52;
        authorityMinContextScore = 0.48;
        aiBootstrapRiskMultiplier = 0.50;
        aiPromotedRiskMultiplier = 1.00;

        enableNNAttributionDiagnostics = false;
        runNNAttributionSelfTest = false;

        intrabarDynamicQuorumEnabled = true;
        pipelineMinConfidence = 0.55;
        pipelineIntrabarConfidenceCap = 0.05;
        pipelineEnableRegimeCostGate = true;
        pipelineEngineRegistry = false;
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

        lossGuardAdverseMomentumExit = false;
        lossGuardAdverseMomentumATRMultiplier = 0.5;
        lossGuardConsecutiveLossLimit = 3;
        lossGuardConsecutiveLossCooldownSec = 1800;
        lossGuardDailyLossCircuitBreakerPercent = 50.0;
        lossGuardPositionLossLimitPercent = 75.0;

        // Crisis limits and hardcoded thresholds (Item 19): defaults match the literals they replace.
        positionSizerMaxLotSize = 100.0;
        positionSizerVolatilityLookback = 252;
        positionSizerEquityCurveLookback = 100;
        riskMarginHealthMaxFreeMarginUsage = 0.8;
        riskMarginHealthMinMarginLevel = 200.0;
        portfolioRiskCvarConfidence = 0.95;
        portfolioRiskCvarMaxRisk = 0.10;
        portfolioRiskMaxEquityCurveHistory = 500;
        riskValidationMinAccountBalance = 100.0;
        portfolioRiskStopFallbackPoints = 100.0;

        // Opt-in only: true flattens EVERY position on the account, manual trades and other EAs'
        // included. Default is EA-scoped; set true only on a single-strategy account you control.
        emergencyFlattenAllAccountPositions = false;
        unprotectedRemediationIntervalSec = 15;
        unprotectedMaxRestoreAttempts = 3;
        syntheticSpikeVelocityMultiplier = 3.0;
        syntheticSpikePauseSeconds = 30;

        enableScalpEngine = true;
        scalpAsyncMode = false;
        scalpMaxLatencyMs = 500;
        scalpSymbolsCsv = "";

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

        useSignalPipeline = true;
        useStrategyStops = true;
        allowSyntheticOffHours = true;
        minTrendStrength = 50.0;
        maxVolatility = 3.0;
        enableStructureFilter = true;
        enableLiquidityFilter = true;
        dormancyStrikeBars = 3;
        dormancyCooldownMinutes = 30;
        maxPositionsSameBase = 3;
        enableClusterRiskGovernance = true;
        enableClusterMutex = true;
        riskMaxConcurrentPerCluster = 3;
        riskMaxClusterExposurePct = 5.0;

        dailyProfitTargetPercent = 2.0;
        profitTrailFactor = 0.7;
        dailyHaltCooldownMinutes = 30;


        symbolMaxSpreadPoints = 1500;
        symbolMinDailyVolumeLots = 1000;
        symbolEnableVolumeCheck = true;

        logLevel = 1;
                logVerbosity = VERBOSITY_NORMAL;
                logDerivFamilyDetection = true;

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

        // strategyTimeframes/strategyIntrabarConfigs are filled by InitializeStrategyConfigs(),
        // not by this constructor; only the count is set here.
        strategyConfigCount = 0;
    }

    // One ceiling for the min-lot round-up, shared by the sizer, the risk gate and the candidate builder:
    // InpMinLotRiskMultiplier shipped at 15.0 while only CPositionSizer clamped to 3.0, so the two consumers
    // that decide the shipped lot widened a position up to fifteen times the risk the gate had approved.
    double EffectiveMinLotRiskMultiplier() const
    {
        return MathMin(MathMax(1.0, minLotRiskMultiplier), MAX_MIN_LOT_RISK_MULTIPLIER);
    }
};

#endif // ORCHESTRATOR_CONFIG_MQH

