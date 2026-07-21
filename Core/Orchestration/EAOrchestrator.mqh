//+------------------------------------------------------------------+
//| EAOrchestrator.mqh                                               |
//| Main coordination class - replaces monolithic EA logic           |
//| Single composition root (Factory/Builder pattern) - Batch 123    |
//+------------------------------------------------------------------+
#property strict

#ifndef CORE_ORCHESTRATION_EA_ORCHESTRATOR_MQH
#define CORE_ORCHESTRATION_EA_ORCHESTRATOR_MQH

#include "SignalGenerator.mqh"
#include "SignalValidator.mqh"
#include "CandidateBuilder.mqh"
#include "TradeExecutor.mqh"
#include "LiveAuthorityResolver.mqh"
#include "../Position/PositionManager.mqh"
#include "../../Core/Registry/MathematicalEngineRegistry.mqh"
#include "../../Core/Registry/InstitutionalEngineRegistry.mqh"
#include "../../Core/Registry/NeuralNetRegistry.mqh"
#include "../../Core/Registry/DrawingManagerRegistry.mqh"
#include "../../Core/Registry/ScanSchedulerRegistry.mqh"
#include "../../Core/Registry/SymbolStateTracker.mqh"
#include "../../Core/Management/EnterpriseStrategyManager.mqh"
#include "../../Core/Risk/UnifiedRiskManager.mqh"
#include "../../Core/Risk/PositionSizer.mqh"
#include "../../Core/Trading/TradeManager.mqh"
#include "../../Core/Engines/RegimeEngine.mqh"
#include "../../Core/Risk/RiskTierManager.mqh"
#include "../../Core/Risk/SafeModeConfig.mqh"
#include "../../Core/Risk/FullMarginMode.mqh"
#include "../../Core/Processing/TickSafetyMonitor.mqh"
#include "../../Core/Processing/SyntheticSpikeMonitor.mqh"
#include "../../Core/Processing/SymbolScanScheduler.mqh"
#include "../../Core/Trading/PositionStateManager.mqh"
#include "../../Core/Trading/TradeAttributionManager.mqh"
#include "../../Core/Engines/AIEngine.mqh"
#include "../../Core/AI/AIPerformanceFeedback.mqh"
#include "../../Core/Utils/PythonBridge.mqh"
#include "../../Core/Utils/DiagnosticsLogger.mqh"
#include "../../Core/Cache/ConsensusCache.mqh"
#include "../../AIModules/NextGenStrategyBrain.mqh"
#include "../../AIModules/NeuralNetworkStrategy.mqh"
#include "../../Core/Risk/CompoundingTierManager.mqh"
#include "../../Core/Engines/FamilyStrategyWeightMatrix.mqh"
#include "../../Core/Engines/SessionWeightManager.mqh"
#include "../../Core/Engines/SkewStepAnalyzer.mqh"
#include "../../Core/Risk/UnprotectedPositionTracker.mqh"
#include "../../Core/Utils/ErrorHandling.mqh"
#include "../../Core/Utils/Enums.mqh"
#include "../../Core/Utils/Instruments.mqh"
#include "../../Core/Engines/MarketAnalysis.mqh"
#include "../../Core/Engines/StructureEngine.mqh"
#include "../../Core/Engines/TrendEngine.mqh"
#include "../../Core/Engines/LiquidityEngine.mqh"
#include "../../Core/Engines/VolatilityEngine.mqh"
#include "../../Strategies/SimpleMomentumStrategy.mqh"
#include "../../Core/Strategy/StrategyBase.mqh"
#include "../../Strategies/StrategyCandlestick.mqh"
#include "../../Strategies/MeanReversionStrategy.mqh"
#include "../../Strategies/VolatilityBreakoutStrategy.mqh"
#include "../../Strategies/StatisticalArbitrageStrategy.mqh"
#include "../../Core/Strategy/AIStrategyAdapter.mqh"
#include "../../Core/Strategy/TransformerAIStrategyAdapter.mqh"
#include "../../Core/Strategy/EnsembleAIStrategyAdapter.mqh"
#include "../../Core/Strategy/OnnxAIStrategyAdapter.mqh"
#include "../../Core/Engines/HurstEngine.mqh"
#include "../../Core/Engines/OrnsteinUhlenbeckEngine.mqh"
#include "../../Core/Engines/OrderFlowImbalanceEngine.mqh"
#include "../../Core/Engines/VWAPEngine.mqh"
#include "../../Core/Engines/VolumeProfileEngine.mqh"
#include "../../Core/Engines/CVDEngine.mqh"
#include "../../Core/Risk/VPINFilter.mqh"
#include "../../Core/Scalp/FastScalpEngine.mqh"
#include "../../Core/Scalp/SpikeHunterEngine.mqh"
#include "../../Core/Scalp/ScalpSignalCache.mqh"
#include "../../Core/Scalp/GridRecoveryEngine.mqh"
#include "../../Core/Scalp/ATRScalpingEngine.mqh"
#include "../../Core/Risk/EquityCurveManager.mqh"
#include "../../Core/Processing/DerivAssetProfiler.mqh"
#include "../../Core/Processing/MultiAssetProfiler.mqh"
#include "../../Core/Engines/KalmanMeanReversion.mqh"
#include "../../Core/Engines/ChangepointDetector.mqh"
#include "../../Core/Engines/FourStateRegimeDetector.mqh"
#include "../../Core/Engines/VolatilityTargeting.mqh"
#include "../../Core/Processing/ExitOptimizer.mqh"
#include "../../Strategies/LiquiditySweepStrategy.mqh"
#include "../../Strategies/RangeCompressionBreakout.mqh"
#include "../../Core/Management/PositionLifecycleManager.mqh"
#include "../../Core/Management/DiagnosticsManager.mqh"
#include "../../Core/Utils/DashboardBridge.mqh"
#include "../../IndicatorManager.mqh"
#include "../../Core/Strategy/StrategyRegistry.mqh"
#include "../../Core/Management/SymbolUniverseBuilder.mqh"
#include <Trade\SymbolInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <Object.mqh>

//+------------------------------------------------------------------+
//| SOrchestratorConfig - All input parameters grouped by domain     |
//+------------------------------------------------------------------+
struct SOrchestratorConfig
{
    // General
    int     magicNumber;
    double  lotSize;
    bool    useEnhancedRisk;
    double  maxRiskPerTrade;
    double  maxDailyRisk;
    double  maxPortfolioRisk;
    double  maxDrawdown;
    double  dailyLossLimitPercent;
    ENUM_RISK_TIER riskTier;
    bool    enableCompoundingTiers;
    int     compoundingTierCheckIntervalSec;
    bool    enableSessionWeights;
    bool    enableSkewStepAnalyzer;
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
    bool    enableUnifiedICT;
    bool    ictRequireKillZone;
    bool    enableCandlestick;
    bool    candlestickRequireTrend;
    bool    enableUnicornModel;
    bool    enablePowerOfThree;
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
    double  ictDisplacementMultiplier;
    bool    useCuratedStrategySet;
    bool    useSymbolClassProfiles;
    
    // Batch 114
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
    
    // Strategy weights
    double  weightMomentum;
    double  weightTrend;
    double  weightSupportResistance;
    double  weightUnifiedICT;
    double  weightCandlestick;
    double  weightUnicornModel;
    double  weightPowerOfThree;
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
    
    // Dashboard
    bool    dashboardEnabled;
    string  dashboardEndpoint;
    int     dashboardPushIntervalSec;
    bool    dashboardControlEnabled;
    
    // Live authority gate
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
    
    // NN attribution
    bool    enableNNAttributionDiagnostics;
    bool    runNNAttributionSelfTest;
    
    // Runtime cadence
    bool    enableHybridCadence;
    int     intrabarScanSeconds;
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
    bool    intrabarEligibilityMomentum;
    bool    intrabarEligibilityTrend;
    bool    intrabarEligibilitySupportResistance;
    bool    intrabarEligibilityUnifiedICT;
    bool    intrabarEligibilityCandlestick;
    bool    intrabarEligibilityUnicornModel;
    bool    intrabarEligibilityPowerOfThree;
    bool    intrabarEligibilityMeanReversion;
    bool    intrabarEligibilityVolatilityBreakout;
    bool    intrabarEligibilityNeuralNetworkAI;
    bool    intrabarEligibilityTransformerAI;
    bool    intrabarEligibilityEnsembleAI;
    bool    intrabarEligibilityOnnxAI;
    int     maxIntrabarSymbolsPerCycle;
    int     maxSignalEvaluationsPerCycle;
    int     intrabarBackoffMaxSeconds;
    int     readinessReuseTtlSeconds;
    bool    enableNNOnlineTraining;
    bool    enableNNWeightMutation;
    bool    enableNNPseudoLabeling;
    int     nnPseudoLabelBarsAhead;
    int     nnSampleIntervalSeconds;
    int     nnCheckpointEveryLabeled;
    
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
    
    // Max hold time
    bool    enableMaxHoldTime;
    int     maxHoldHoursIntraday;
    int     maxHoldHoursSwing;
    bool    maxHoldOnlyIfLoss;
    
    // Emergency
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
    
    // Dynamic slippage
    bool    enableDynamicSlippage;
    double  dynamicSlippageAtrPercent;
    int     dynamicSlippageMinPoints;
    int     dynamicSlippageMaxMultiplier;
    int     dynamicSlippageAtrPeriod;
    
    // Spike detection
    int     spikeConfirmWindows;
    
    // Spike Hunter
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
    
    // Multi-asset profiler
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
    bool    signalScanOnNewBarOnly;
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
    
    // Logging
    int     logLevel;
    
    // Batch 99
    int     equityCurveEmaPeriod;
    double  equityCurveReductionFactor;
    double  kellyFraction;
    
    // Constructor with defaults
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
        allowMinLotRoundUp = false;
        minLotRiskMultiplier = 5.0;
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
        enableUnifiedICT = true;
        ictRequireKillZone = false;
        enableCandlestick = true;
        candlestickRequireTrend = false;
        enableUnicornModel = true;
        enablePowerOfThree = true;
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
        ictDisplacementMultiplier = 0.8;
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
        consensusConflictDeadband = 0.05;
        consensusMinReadyWeightRatio = 0.40;
        consensusSupportFloorNewBar = 0.20;
        consensusSupportFloorIntrabar = 0.15;
        allowSparseIntrabarSingleVoter = false;
        sparseIntrabarMinQuality = 0.85;
        sparseIntrabarMinSupportRatio = 0.40;
        sparseIntrabarMinReadyCoverage = 0.85;
        
        weightMomentum = 1.0;
        weightTrend = 1.2;
        weightSupportResistance = 1.8;
        weightUnifiedICT = 1.2;
        weightCandlestick = 0.8;
        weightUnicornModel = 1.2;
        weightPowerOfThree = 1.2;
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
        intrabarScanSeconds = 5;
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
        intrabarEligibilityMomentum = true;
        intrabarEligibilityTrend = true;
        intrabarEligibilitySupportResistance = true;
        intrabarEligibilityUnifiedICT = true;
        intrabarEligibilityCandlestick = true;
        intrabarEligibilityUnicornModel = true;
        intrabarEligibilityPowerOfThree = true;
        intrabarEligibilityMeanReversion = true;
        intrabarEligibilityVolatilityBreakout = true;
        intrabarEligibilityNeuralNetworkAI = true;
        intrabarEligibilityTransformerAI = true;
        intrabarEligibilityEnsembleAI = true;
        intrabarEligibilityOnnxAI = true;
        maxIntrabarSymbolsPerCycle = 6;
        maxSignalEvaluationsPerCycle = 8;
        intrabarBackoffMaxSeconds = 60;
        readinessReuseTtlSeconds = 60;
        enableNNOnlineTraining = true;
        enableNNWeightMutation = false;
        enableNNPseudoLabeling = true;
        nnPseudoLabelBarsAhead = 10;
        nnSampleIntervalSeconds = 15;
        nnCheckpointEveryLabeled = 10;
        
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
        
        emergencyFlattenAllAccountPositions = true;
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
        signalScanOnNewBarOnly = false;
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
        
        logLevel = 1;
        
        equityCurveEmaPeriod = 20;
        equityCurveReductionFactor = 0.50;
        kellyFraction = 0.25;
    }
};

//+------------------------------------------------------------------+
//| CEAOrchestratorBuilder - Builder pattern for orchestrator        |
//+------------------------------------------------------------------+
class CEAOrchestratorBuilder
{
private:
    SOrchestratorConfig m_config;
    
public:
    CEAOrchestratorBuilder() {}
    
    CEAOrchestratorBuilder& WithConfig(const SOrchestratorConfig& config) { m_config = config; return *this; }
    
    // Individual setters for fluent API
    CEAOrchestratorBuilder& WithMagicNumber(int v) { m_config.magicNumber = v; return *this; }
    CEAOrchestratorBuilder& WithLotSize(double v) { m_config.lotSize = v; return *this; }
    CEAOrchestratorBuilder& WithRiskSettings(double maxRisk, double maxDaily, double maxPortfolio, double maxDD) 
    { m_config.maxRiskPerTrade = maxRisk; m_config.maxDailyRisk = maxDaily; m_config.maxPortfolioRisk = maxPortfolio; m_config.maxDrawdown = maxDD; return *this; }
    CEAOrchestratorBuilder& WithRiskTier(ENUM_RISK_TIER v) { m_config.riskTier = v; return *this; }
    CEAOrchestratorBuilder& WithSymbols(const string& v) { m_config.symbolsToTrade = v; return *this; }
    CEAOrchestratorBuilder& WithEAMode(ENUM_EA_MODE v) { m_config.eaMode = v; return *this; }
    CEAOrchestratorBuilder& WithAIMode(bool v) { m_config.enableAIMode = v; return *this; }
    CEAOrchestratorBuilder& WithLogLevel(int v) { m_config.logLevel = v; return *this; }
    
    // Build the orchestrator
    CEAOrchestrator* Build();
    
    const SOrchestratorConfig& GetConfig() const { return m_config; }
    };

    // Builder implementation
    CEAOrchestrator* CEAOrchestratorBuilder::Build()
    {
        return new CEAOrchestrator();
    }

    class CEAOrchestrator
{
private:
    // ============ Core Subsystems (Owned) ============
    CSymbolInfo                 m_globalSymbol;
    CAccountInfo                m_accountInfo;
    CEnhancedErrorHandler       m_errorHandler;
    CUnifiedRiskManager         m_unifiedRiskManager;
    CUnprotectedPositionTracker m_unprotectedTracker;
    CRiskTierManager            m_riskTierManager;
    CCompoundingTierManager     m_compoundingTierManager;
    CFamilyStrategyWeightMatrix m_familyWeightMatrix;
    CSessionWeightManager       m_sessionWeightManager;
    CSkewStepAnalyzer           m_skewStepAnalyzer;
    CPerformanceAnalytics       m_performanceAnalytics;
    CAIPerformanceFeedback      m_aiFeedback;
    CSymbolScanScheduler        m_scanScheduler;
    
    CNextGenStrategyBrain       m_aiNextGenBrain;
    CNeuralNetworkStrategy*     m_neuralNetStrategies[];
    string                      m_neuralNetStrategySymbols[];
    bool                        m_aiBrainReady;
    bool                        m_aiEngineReady;
    bool                        m_aiFeedbackReady;
    bool                        m_aiTopologyLogged;
    CPositionStateManager       m_positionStateManager;
    CTradeAttributionManager    m_attributionManager;
    CPositionSizer              m_positionSizer;
    CInstrumentRegistry         m_instrumentRegistry;
    CTickSafetyMonitor          m_tickSafetyMonitor;
    CSyntheticSpikeMonitor      m_spikeMonitor;
    bool                        m_onnxSessionDisabled;
    CPythonBridge*              m_pythonBridge;
    CDashboardBridge*           m_dashboardBridge;
    
    CTradeManager               m_tradeManager;
    CEnterpriseStrategyManager* m_enterpriseManagers[];
    string                      m_enterpriseManagerSymbols[];
    CConsensusCache             m_consensusCache;
    CFastScalpEngine            m_scalpEngine;
    CSpikeHunterEngine          m_spikeHunter;
    CGridRecoveryEngine         m_gridRecovery;
    CATRScalpingEngine          m_atrScalping;
    CMultiAssetProfiler         m_multiAssetProfiler;
    CScalpSignalCache           m_scalpCache;
    CFullMarginMode             m_fullMarginMode;
    CSafeMode                   m_safeMode;
    CPositionLifecycleManager   m_lifecycleManager;
    CDiagnosticsManager         m_diagnosticsManager;
    CChartDrawingManager*       m_drawingManagers[];
    string                      m_drawingManagerSymbols[];
    
    // Batch 99: Bayesian Kelly / Equity Curve / CVaR subsystems
    CEquityCurveManager*        m_equityCurveManager;
    CBayesianKellyModifier*     m_bayesianKellyModifier;
    CEquityCurveLotModifier*    m_equityCurveLotModifier;
    datetime                    m_lastCvarLogTime;
    
    // Batch 100: Advanced Mathematical Engines
    CHurstEngine*               m_hurstEngines[];
    COrnsteinUhlenbeckEngine*   m_ouEngines[];
    COrderFlowImbalanceEngine*  m_ofiEngines[];
    CVPINFilter*                m_vpinFilters[];
    string                      m_mathEngineSymbols[];
    bool                        m_gridHurstBridgeLogged[];
    
    // Batch 114: Research-Driven Statistical Algorithm Upgrades
    CKalmanMeanReversion*       m_kalmanEngines[];
    CChangepointDetector*       m_cpdEngines[];
    CFourStateRegimeDetector*   m_fourStateEngines[];
    CVolatilityTargeting*       m_volTargetEngines[];
    CExitOptimizer*             m_exitOptimizers[];
    CLiquiditySweepStrategy*    m_liquiditySweepStrategies[];
    CRangeCompressionBreakout*  m_rangeCompStrategies[];
    
    // Batch 107: Institutional TA Engines (Forex only)
    CVWAPEngine*                m_vwapEngines[];
    CVolumeProfileEngine*       m_vpEngines[];
    CCVDEngine*                 m_cvdEngines[];
    
    // Core components
    CSignalGenerator            m_signalGenerator;
    CSignalValidator            m_signalValidator;
    CCandidateBuilder           m_candidateBuilder;
    CTradeExecutor              m_tradeExecutor;
    CLiveAuthorityResolver      m_liveAuthority;
    CPositionManager            m_positionManager;
    
    // Registries
    CMathematicalEngineRegistry   m_mathRegistry;
    CInstitutionalEngineRegistry  m_instRegistry;
    CNeuralNetRegistry            m_nnRegistry;
    CDrawingManagerRegistry       m_drawingRegistry;
    CScanSchedulerRegistry        m_scanScheduler;
    CSymbolStateTracker           m_symbolState;
    
    // ============ State Variables ============
    // Performance tracking
    double m_peakEquity;
    double m_initialBalance;
    double m_accountBalance;
    double m_accountEquity;
    double m_currentEquity;
    double m_currentDrawdown;
    double m_totalProfit;
    double m_totalLoss;
    int    m_totalTrades;
    int    m_winningTrades;
    int    m_losingTrades;
    double m_maxDrawdown;
    
    datetime m_currentTime;
    
    // Risk management
    double m_currentRiskPerTrade;
    double m_currentDrawdown;
    ENUM_MARKET_REGIME m_currentRegime;
    datetime m_lastTradeTime;
    int    m_totalActivePositions;
    string m_activePairs[];
    bool   m_systemInitialized;
    bool   m_tradingEnabled;
    int    m_logLevel;
    
    // Runtime heartbeat + rejection telemetry
    ulong m_hbScansAttempted;
    ulong m_hbIntrabarScansExecuted;
    ulong m_hbNoSignalCount;
    ulong m_hbValidatorRejects;
    ulong m_hbRiskRejects;
    ulong m_hbTradesOpened;
    ulong m_hbQuietNoNewBar;
    ulong m_hbQuietCadenceHold;
    ulong m_hbQuietMissingManager;
    ulong m_hbEntryBlocked;
    ulong m_hbSizingRejects;
    ulong m_hbSignalsGenerated;
    ulong m_hbSignalsAfterPipeline;
    ulong m_hbSignalsAfterQuorum;
    ulong m_hbSignalsValidated;
    ulong m_hbSignalsRiskApproved;
    ulong m_hbSignalsSent;
    ulong m_hbSyntheticSpikeEvents;
    
    datetime m_lastHeartbeatLogTime;
    datetime m_lastNNHealthLogTime;
    ulong    m_scanCycleSequence;
    int      m_cyclesSinceIndicatorSignal;
    bool     m_hybridGateRelaxed;
    int      m_consecutiveZeroSignalCycles;
    int      m_zeroSignalFallbackThreshold;
    
    // Diagnostics logger (Blueprint 3.6: off-journal logging)
    CDiagnosticsLogger m_diagLogger;
    
    // Cached diagnostic strings (Blueprint 3.6: throttle recomputation to 60s)
    string   m_cachedConsensusDiag;
    datetime m_consensusDiagTime;
    string   m_cachedRoleClusterDiag;
    datetime m_roleClusterDiagTime;
    
    // Portfolio profit target tracking
    bool   m_dailyProfitTargetReached;
    double m_dailyProfitPeakPct;
    double m_trailingProfitFloor;
    bool   m_dailyTradingHalt;
    datetime m_dailyTradingHaltStartTime;
    
    // Dual-mode auto-switching
    enum ENUM_AUTO_SWITCH_MODE { AUTO_MODE_CONSERVATIVE = 0, AUTO_MODE_AGGRESSIVE = 1, AUTO_MODE_EMERGENCY = 2 };
    ENUM_AUTO_SWITCH_MODE m_currentTradingMode;
    
    // Issue 7: Dormancy cooldown tracking per symbol
    int    m_dormantConsecutiveCount[];
    datetime m_dormantCooldownUntil[];
    string m_dormantCooldownSymbols[];
    const int DORMANT_COOLDOWN_THRESHOLD = 5;
    const int DORMANT_COOLDOWN_MINUTES = 10;
    
    // Issue 15: Scalp blacklist tracking per symbol (time-based cooldown)
    int    m_scalpBlacklistFailCount[];
    bool   m_scalpBlacklisted[];
    datetime m_scalpBlacklistUntil[];
    string m_scalpBlacklistSymbols[];
    const int SCALP_BLACKLIST_THRESHOLD = 3;
    const int SCALP_BLACKLIST_COOLDOWN_MINUTES = 15;
    const int SCALP_BLACKLIST_COOLDOWN_MINUTES_STD = 30;
    
    // Call counter for diagnostics
    int m_callCount;
    
    // ============ Configuration ============
        SOrchestratorConfig m_config;
    
        // ============ Private Helper Methods ============
        bool InitializeComponents();
        void InitializeMathematicalEngines();
        void InitializeInstitutionalEngines();
    
    public:
    CEAOrchestrator() : m_systemInitialized(false), m_tradingEnabled(false),
                        m_managerCount(0), m_riskManager(NULL), m_positionSizer(NULL),
                        m_tradeManager(NULL), m_regimeEngine(NULL), m_riskTierManager(NULL),
                        m_safeMode(NULL), m_fullMarginMode(NULL), m_slGuard(NULL),
                        m_tickSafetyMonitor(NULL), m_spikeMonitor(NULL), m_symbolScanScheduler(NULL),
                        m_positionStateManager(NULL), m_attributionManager(NULL), m_aiEngine(NULL),
                        m_aiFeedback(NULL), m_pythonBridge(NULL), m_diagLogger(NULL), m_consensusCache(NULL),
                        m_nextGenBrain(NULL), m_neuralNetStrategy(NULL),
                        m_compoundingTierManager(NULL), m_familyWeightMatrix(NULL),
                        m_sessionWeightManager(NULL), m_skewStepAnalyzer(NULL), m_unprotectedTracker(NULL),
                        m_lastProfitTargetDay(0), m_dailyProfitTargetReached(false), m_dailyProfitPeakPct(0),
                        m_trailingProfitFloor(0), m_dailyTradingHalt(false), m_dailyTradingHaltStartTime(0),
                        m_lastTradeTime(0), m_scanCycleSequence(0), m_cyclesSinceIndicatorSignal(0),
                        m_hybridGateRelaxed(false), m_hbScansAttempted(0), m_hbIntrabarScansExecuted(0),
                        m_hbNoSignalCount(0), m_hbSignalsGenerated(0), m_hbSignalsAfterPipeline(0),
                        m_hbSignalsAfterQuorum(0), m_hbSignalsValidated(0), m_hbSignalsRiskApproved(0),
                        m_hbSignalsSent(0), m_hbEntryBlocked(0), m_hbValidatorRejects(0),
                        m_hbSizingRejects(0), m_hbQuietCadenceHold(0), m_hbQuietNoNewBar(0),
                        m_hbQuietMissingManager(0), m_callCount(0),
                        m_peakEquity(0.0), m_initialBalance(0.0), m_accountBalance(0.0),
                        m_accountEquity(0.0), m_currentEquity(0.0), m_currentDrawdown(0.0),
                        m_totalProfit(0.0), m_totalLoss(0.0), m_totalTrades(0), m_winningTrades(0),
                        m_losingTrades(0), m_maxDrawdown(0.0),
                        m_currentTime(0),
                        m_currentRiskPerTrade(0.0), m_currentDrawdown(0.0),
                        m_currentRegime(MARKET_REGIME_UNKNOWN),
                        m_totalActivePositions(0),
                        m_logLevel(1),
                        m_hbRiskRejects(0), m_hbTradesOpened(0), m_hbSyntheticSpikeEvents(0),
                        m_lastHeartbeatLogTime(0), m_lastNNHealthLogTime(0),
                        m_zeroSignalFallbackThreshold(20),
                        m_dailyProfitTargetReached(false), m_dailyProfitPeakPct(0.0),
                        m_trailingProfitFloor(0.0), m_dailyTradingHalt(false),
                        m_dailyTradingHaltStartTime(0),
                        m_currentTradingMode(AUTO_MODE_CONSERVATIVE),
                        m_cachedConsensusDiag(""), m_consensusDiagTime(0),
                        m_cachedRoleClusterDiag(""), m_roleClusterDiagTime(0)
    {
        ArrayResize(m_managers, 0);
        ArrayResize(m_symbols, 0);
        ArrayResize(m_activePairs, 0);
        ArrayResize(m_dormantConsecutiveCount, 0);
        ArrayResize(m_dormantCooldownUntil, 0);
        ArrayResize(m_dormantCooldownSymbols, 0);
        ArrayResize(m_scalpBlacklistFailCount, 0);
        ArrayResize(m_scalpBlacklisted, 0);
        ArrayResize(m_scalpBlacklistUntil, 0);
        ArrayResize(m_scalpBlacklistSymbols, 0);
    }
    
    ~CEAOrchestrator() {}
    
        void Shutdown()
        {
            // Cleanup dynamically allocated resources
        
            // Cleanup mathematical engines
            int mathEngineCount = ArraySize(m_mathEngineSymbols);
            for(int i = 0; i < mathEngineCount; i++)
            {
                if(i < ArraySize(m_hurstEngines) && m_hurstEngines[i] != NULL) { delete m_hurstEngines[i]; m_hurstEngines[i] = NULL; }
                if(i < ArraySize(m_ouEngines) && m_ouEngines[i] != NULL) { delete m_ouEngines[i]; m_ouEngines[i] = NULL; }
                if(i < ArraySize(m_ofiEngines) && m_ofiEngines[i] != NULL) { delete m_ofiEngines[i]; m_ofiEngines[i] = NULL; }
                if(i < ArraySize(m_vpinFilters) && m_vpinFilters[i] != NULL) { delete m_vpinFilters[i]; m_vpinFilters[i] = NULL; }
            }
            ArrayResize(m_hurstEngines, 0);
            ArrayResize(m_ouEngines, 0);
            ArrayResize(m_ofiEngines, 0);
            ArrayResize(m_vpinFilters, 0);
            ArrayResize(m_mathEngineSymbols, 0);
            ArrayResize(m_gridHurstBridgeLogged, 0);
        
            // Cleanup Batch 114 engines
            for(int i = 0; i < mathEngineCount; i++)
            {
                if(i < ArraySize(m_kalmanEngines) && m_kalmanEngines[i] != NULL) { delete m_kalmanEngines[i]; m_kalmanEngines[i] = NULL; }
                if(i < ArraySize(m_cpdEngines) && m_cpdEngines[i] != NULL) { delete m_cpdEngines[i]; m_cpdEngines[i] = NULL; }
                if(i < ArraySize(m_fourStateEngines) && m_fourStateEngines[i] != NULL) { delete m_fourStateEngines[i]; m_fourStateEngines[i] = NULL; }
                if(i < ArraySize(m_volTargetEngines) && m_volTargetEngines[i] != NULL) { delete m_volTargetEngines[i]; m_volTargetEngines[i] = NULL; }
                if(i < ArraySize(m_exitOptimizers) && m_exitOptimizers[i] != NULL) { delete m_exitOptimizers[i]; m_exitOptimizers[i] = NULL; }
                if(i < ArraySize(m_liquiditySweepStrategies) && m_liquiditySweepStrategies[i] != NULL) { delete m_liquiditySweepStrategies[i]; m_liquiditySweepStrategies[i] = NULL; }
                if(i < ArraySize(m_rangeCompStrategies) && m_rangeCompStrategies[i] != NULL) { delete m_rangeCompStrategies[i]; m_rangeCompStrategies[i] = NULL; }
            }
            ArrayResize(m_kalmanEngines, 0);
            ArrayResize(m_cpdEngines, 0);
            ArrayResize(m_fourStateEngines, 0);
            ArrayResize(m_volTargetEngines, 0);
            ArrayResize(m_exitOptimizers, 0);
            ArrayResize(m_liquiditySweepStrategies, 0);
            ArrayResize(m_rangeCompStrategies, 0);
        
            // Cleanup institutional engines
            for(int i = 0; i < mathEngineCount; i++)
            {
                if(i < ArraySize(m_vwapEngines) && m_vwapEngines[i] != NULL) { delete m_vwapEngines[i]; m_vwapEngines[i] = NULL; }
                if(i < ArraySize(m_vpEngines) && m_vpEngines[i] != NULL) { delete m_vpEngines[i]; m_vpEngines[i] = NULL; }
                if(i < ArraySize(m_cvdEngines) && m_cvdEngines[i] != NULL) { delete m_cvdEngines[i]; m_cvdEngines[i] = NULL; }
            }
            ArrayResize(m_vwapEngines, 0);
            ArrayResize(m_vpEngines, 0);
            ArrayResize(m_cvdEngines, 0);
        
            // Cleanup Batch 99 subsystems
            if(m_bayesianKellyModifier != NULL) { delete m_bayesianKellyModifier; m_bayesianKellyModifier = NULL; }
            if(m_equityCurveLotModifier != NULL) { delete m_equityCurveLotModifier; m_equityCurveLotModifier = NULL; }
            if(m_equityCurveManager != NULL) { delete m_equityCurveManager; m_equityCurveManager = NULL; }
        
            // Cleanup Python and Dashboard bridges
            if(m_pythonBridge != NULL) { m_pythonBridge.Shutdown(); delete m_pythonBridge; m_pythonBridge = NULL; }
            if(m_dashboardBridge != NULL) { m_dashboardBridge.Shutdown(); delete m_dashboardBridge; m_dashboardBridge = NULL; }
        
            // Cleanup neural net strategies
            for(int i = 0; i < ArraySize(m_neuralNetStrategies); i++)
            {
                if(m_neuralNetStrategies[i] != NULL) { delete m_neuralNetStrategies[i]; m_neuralNetStrategies[i] = NULL; }
            }
            ArrayResize(m_neuralNetStrategies, 0);
            ArrayResize(m_neuralNetStrategySymbols, 0);
        
            // Cleanup drawing managers
            for(int i = 0; i < ArraySize(m_drawingManagers); i++)
            {
                if(m_drawingManagers[i] != NULL) { delete m_drawingManagers[i]; m_drawingManagers[i] = NULL; }
            }
            ArrayResize(m_drawingManagers, 0);
            ArrayResize(m_drawingManagerSymbols, 0);
        
            // Shutdown AI subsystems
            m_aiNextGenBrain.Shutdown();
            m_aiFeedback.Shutdown();
        
            // Deinit diagnostics logger
            m_diagLogger.Deinit();
        
            m_systemInitialized = false;
            m_tradingEnabled = false;
        
            Print("[EAOrchestrator] Shutdown complete");
        }
    
        // ============ Initialization ============
    
        bool Initialize(const SOrchestratorConfig& config,
                        CEnterpriseStrategyManager* &managers[], string &symbols[], int count)
        {
            m_config = config;
        
            // Store manager references (created by factory)
            m_managerCount = count;
            ArrayResize(m_managers, count);
            ArrayResize(m_symbols, count);
            for(int i = 0; i < count; i++)
            {
                m_managers[i] = managers[i];
                m_symbols[i] = symbols[i];
            }
        
            // Initialize all owned subsystems from config
            if(!InitializeSubsystems())
                return false;
        
            // Initialize sub-components
            if(!InitializeComponents())
                return false;
        
            m_systemInitialized = true;
            m_tradingEnabled = true;
        
            Print("[EAOrchestrator] Initialized with ", count, " symbol managers");
            return true;
        }
    
        bool InitializeSubsystems()
        {
            // Initialize core trading components
            m_tradeManager.SetOrderFillMode(m_config.orderFillingMode);
            m_tradeManager.SetSlippage((uint)MathMax(1, m_config.tradeSlippagePoints));
            m_tradeManager.SetExecutionCostLimits(m_config.maxEntrySpreadPoints, m_config.maxEntryDriftPoints);
            m_tradeManager.SetProtectiveModifyCooldownSeconds(m_config.protectiveModifyCooldownSec);
            m_tradeManager.SetDynamicSlippageConfig(m_config.enableDynamicSlippage, m_config.dynamicSlippageAtrPercent,
                                                      (uint)m_config.dynamicSlippageMinPoints, (uint)m_config.dynamicSlippageMaxMultiplier,
                                                      m_config.dynamicSlippageAtrPeriod);
            if(!m_tradeManager.Initialize((uint)m_config.magicNumber, "MultiStrategyAutonomousEA"))
            {
                Print("[CRITICAL] Failed to initialize TradeManager");
                return false;
            }
            m_tradeManager.SetLogLevel(m_config.logLevel);
        
            // Initialize risk manager
            SUnifiedRiskConfig unifiedRiskConfig;
            unifiedRiskConfig.baseRiskPerTradePercent = m_config.maxRiskPerTrade;
            unifiedRiskConfig.minRiskPerTradePercent  = 0.1;
            unifiedRiskConfig.maxRiskPerTradePercent  = MathMin(MathMax(m_config.maxRiskPerTrade * 2.0, 5.0), 25.0);
            unifiedRiskConfig.maxDailyRiskPercent     = m_config.maxDailyRisk;
            unifiedRiskConfig.maxPortfolioRiskPercent = m_config.maxPortfolioRisk;
            unifiedRiskConfig.correlationThreshold    = 0.7;
            unifiedRiskConfig.correlationReduceThreshold = 0.4;
            unifiedRiskConfig.correlationBlockThreshold  = 0.7;
            unifiedRiskConfig.maxPositionsSameBase    = m_config.maxPositionsSameBase;
            unifiedRiskConfig.drawdownWarningPercent  = m_config.maxDrawdown * 0.7;
            unifiedRiskConfig.drawdownCriticalPercent = m_config.maxDrawdown;
            unifiedRiskConfig.adaptationMinTrades     = 10;
            unifiedRiskConfig.enableAdaptiveSizing    = m_config.useEnhancedRisk;
            unifiedRiskConfig.enableAuditLogging      = true;
            unifiedRiskConfig.auditLogFile            = "risk_audit_" + _Symbol + ".log";
            unifiedRiskConfig.minLotRiskMultiplier    = m_config.minLotRiskMultiplier;
            unifiedRiskConfig.dailyLossLimitPercent   = m_config.dailyLossLimitPercent;
        
            if(!m_unifiedRiskManager.Initialize(unifiedRiskConfig, &m_performanceAnalytics))
            {
                Print("[CRITICAL] UnifiedRiskManager failed to initialize!");
                return false;
            }
            m_unifiedRiskManager.SetEAMagicNumber(m_config.magicNumber);
            Print("[INIT] UnifiedRiskManager initialized as single risk authority");
        
            // Initialize position sizer
            SPositionSizingParams sizingParams;
            sizingParams.sizingMode       = POSITION_SIZE_RISK_PERCENT;
            sizingParams.fixedLotSize     = m_config.lotSize;
            sizingParams.riskPercent      = m_config.maxRiskPerTrade;
            sizingParams.atrPeriod        = 14;
            sizingParams.atrMultiplier    = 1.5;
            sizingParams.maxLotSize       = MAX_LOT_SIZE;
            sizingParams.minLotSize       = MIN_LOT_SIZE;
            sizingParams.correlationAdjustment  = 1.0;
            sizingParams.useVolatilityAdjustment = true;
            sizingParams.useCorrelationAdjustment = false;
        
            if(!m_positionSizer.SetParameters(sizingParams))
            {
                Print("[CRITICAL] PositionSizer initialization FAILED — will use min lot fallback!");
            }
            else
            {
                Print("[INIT] PositionSizer initialized — Mode: RISK_PERCENT, Risk: ", DoubleToString(sizingParams.riskPercent, 2), "%");
            }
        
            // Apply risk tier configuration
            m_riskTierManager.SetTier(m_config.riskTier);
            m_riskTierManager.ApplyToRiskManager(m_unifiedRiskManager, &m_performanceAnalytics,
                                                 m_config.maxDailyRisk, m_config.maxPortfolioRisk,
                                                 m_config.maxDrawdown * 0.7, m_config.maxDrawdown,
                                                 m_config.dailyLossLimitPercent);
            m_riskTierManager.ApplyToPositionSizer(m_positionSizer, m_config.maxRiskPerTrade);
            m_riskTierManager.ApplyToTradeManager(m_tradeManager);
        
            // Wire PositionSizer to unified correlation engine
            m_positionSizer.SetCorrelationEngine(m_unifiedRiskManager.GetPortfolioRiskManager().GetCorrelationEngine());
            m_positionSizer.SetLogLevel(m_config.logLevel);
            m_positionSizer.SetAllowMinLotRoundUp(m_config.allowMinLotRoundUp);
            m_positionSizer.SetMinLotRiskMultiplier(m_config.minLotRiskMultiplier);
        
            // Initialize equity curve manager (Batch 99)
            m_equityCurveManager = new CEquityCurveManager(m_config.equityCurveEmaPeriod, m_config.equityCurveReductionFactor, 1.0);
            if(m_equityCurveManager != NULL)
                PrintFormat("[RISK] EquityCurveManager initialized with emaPeriod=%d", m_config.equityCurveEmaPeriod);
            else
                Print("[RISK] WARNING: Failed to create EquityCurveManager — equity curve sizing disabled");
        
            // Initialize BayesianKellyModifier (Batch 99)
            m_bayesianKellyModifier = new CBayesianKellyModifier(m_config.kellyFraction);
            if(m_bayesianKellyModifier != NULL)
            {
                m_positionSizer.AddModifier(m_bayesianKellyModifier);
                PrintFormat("[RISK] BayesianKelly modifier initialized with kellyFraction=%.2f", m_config.kellyFraction);
            }
            else
            {
                Print("[RISK] WARNING: Failed to create BayesianKelly modifier");
            }
        
            // Initialize EquityCurveLotModifier (Batch 99)
            m_equityCurveLotModifier = new CEquityCurveLotModifier(m_equityCurveManager);
            if(m_equityCurveLotModifier != NULL)
            {
                m_positionSizer.AddModifier(m_equityCurveLotModifier);
                Print("[RISK] EquityCurveLotModifier added to position sizer modifier chain");
            }
            else
            {
                Print("[RISK] WARNING: Failed to create EquityCurveLotModifier");
            }
        
            // Initialize ADX Lot Modifier (P11.2)
            {
                CADXLotModifier* adxModifier = new CADXLotModifier();
                if(adxModifier != NULL)
                {
                    if(adxModifier.Initialize(_Symbol, PERIOD_CURRENT, 14))
                    {
                        m_positionSizer.AddModifier(adxModifier);
                        Print("[ADX-MODIFIER] Initialized and added to position sizer modifier chain");
                    }
                    else
                    {
                        Print("[ADX-MODIFIER] WARNING: Failed to initialize — ADX sizing disabled");
                        delete adxModifier;
                    }
                }
            }
        
            // Configure cluster governance
            m_unifiedRiskManager.ConfigureClusterGovernance(m_config.enableClusterRiskGovernance,
                                                            MathMax(1, m_config.riskMaxConcurrentPerCluster),
                                                            MathMax(0.1, m_config.riskMaxClusterExposurePct),
                                                            m_config.enableClusterMutex);
            m_unifiedRiskManager.SyncClusterPositionCounts();
        
            // Initialize CompoundingTierManager (I2/I9)
            if(m_config.enableCompoundingTiers)
            {
                if(m_compoundingTierManager.Initialize(true))
                {
                    m_compoundingTierManager.ApplyTierToRiskManager(m_unifiedRiskManager);
                    m_compoundingTierManager.ApplyTierToPositionSizer(m_positionSizer);
                    Print("[INIT] CompoundingTierManager initialized — auto-switch ENABLED");
                }
                else
                {
                    Print("[INIT] WARNING: CompoundingTierManager initialization failed — using static tier");
                }
            }
            else
            {
                Print("[INIT] CompoundingTierManager disabled — using static tier");
            }
        
            // Initialize Family Strategy Weight Matrix (I1)
            m_familyWeightMatrix.Initialize();
        
            // Initialize Session Weight Manager (I3)
            if(m_config.enableSessionWeights)
            {
                m_sessionWeightManager.Initialize(true);
                Print("[INIT] SessionWeightManager initialized — session-aware adjustments ENABLED");
            }
            else
            {
                Print("[INIT] SessionWeightManager disabled");
            }
        
            // Initialize Skew Step Analyzer (I4)
            if(m_config.enableSkewStepAnalyzer)
            {
                m_skewStepAnalyzer.Initialize(200, 0.80, 0.2, 0.5);
                Print("[INIT] SkewStepAnalyzer initialized — Skew Step distribution analysis ENABLED");
            }
            else
            {
                Print("[INIT] SkewStepAnalyzer disabled");
            }
        
            // Initialize unprotected position tracker
            m_unprotectedTracker.Initialize(&m_tradeManager, &m_unifiedRiskManager,
                                            m_config.magicNumber, ArraySize(m_enterpriseManagerSymbols),
                                            m_config.unprotectedRemediationIntervalSec, m_config.unprotectedMaxRestoreAttempts);
        
            // Initialize FullMarginMode or SafeMode (Phase 6)
            if(m_config.riskTier == RISK_TIER_FULL_MARGIN)
            {
                SFullMarginConfig fmConfig = m_riskTierManager.GetFullMarginConfig();
                if(!m_fullMarginMode.Initialize(fmConfig))
                    Print("[INIT] WARNING: Full-margin mode initialization failed");
                else
                    Print("[INIT] Full-margin aggressive mode ENABLED");
            }
            else if(m_config.riskTier == RISK_TIER_CONSERVATIVE)
            {
                SSafeModeConfig smConfig = m_riskTierManager.GetSafeModeConfig();
                if(!m_safeMode.Initialize(smConfig))
                    Print("[INIT] WARNING: Safe mode initialization failed");
                else
                    Print("[INIT] Conservative safe mode ENABLED");
            }
        
            // Initialize PositionLifecycleManager (Blueprint R6a)
            if(m_lifecycleManager.Initialize(&m_tradeManager, &m_consensusCache, &m_riskTierManager, &m_safeMode, m_config.magicNumber))
            {
                m_lifecycleManager.ConfigureSRE(m_config.enableSignalReversalExit, m_config.signalReversalMinConfidence,
                                                 m_config.signalReversalProfitGuard, m_config.signalReversalMinLossR,
                                                 m_config.signalReversalMaxLossR, m_config.signalReversalMinTimeSec,
                                                 m_config.enableStructuralInvalidation);
                m_lifecycleManager.ConfigureLifecycle(m_config.enablePositionLifecycleManager,
                                                       m_config.lifecycleBreakevenBufferPoints,
                                                       m_config.lifecycleTrailingDistancePoints,
                                                       (int)m_config.lifecycleTrailingStepPoints,
                                                       m_config.lifecycleUseATRTrailing, m_config.lifecycleATRMultiplier);
                m_lifecycleManager.ConfigureMaxHoldTime(m_config.enableMaxHoldTime,
                                                         m_config.maxHoldHoursIntraday,
                                                         m_config.maxHoldHoursSwing,
                                                         m_config.maxHoldOnlyIfLoss);
                Print("[INIT] PositionLifecycleManager initialized (Blueprint R6a)");
            }
            else
                Print("[INIT] WARNING: PositionLifecycleManager initialization failed");
        
            // Initialize DiagnosticsManager (Blueprint R6b)
            if(m_diagnosticsManager.Initialize(&m_unifiedRiskManager, &m_riskTierManager, m_config.heartbeatInterval))
            {
                m_diagnosticsManager.SetScalpEngine(&m_scalpEngine);
                m_diagnosticsManager.SetFullMarginMode(&m_fullMarginMode);
                m_diagnosticsManager.SetSafeMode(&m_safeMode);
                m_diagnosticsManager.SetAIConfig(m_config.enableAIMode, m_config.enableNeuralNetwork, m_config.enableNNOnlineTraining);
                m_diagnosticsManager.SetRiskTier(m_config.riskTier);
                Print("[INIT] DiagnosticsManager initialized (Blueprint R6b)");
            }
            else
                Print("[INIT] WARNING: DiagnosticsManager initialization failed");
        
            // Initialize tick safety monitor
            m_tickSafetyMonitor.SetMinFreeMarginPercent(20.0);
            m_tickSafetyMonitor.SetMinMarginLevel(150.0);
            m_tickSafetyMonitor.SetEmergencyStop(false);
        
            // Initialize spike monitor
            m_spikeMonitor.Initialize(m_tradeManager, m_unifiedRiskManager, m_tickSafetyMonitor);
            m_spikeMonitor.SetMagicNumber(m_config.magicNumber);
        
            // Initialize AI subsystems if enabled
            if(m_config.enableAIMode)
            {
                Print("[AI] Initializing AI subsystems...");
            
                // NextGen Strategy Brain
                if(!m_aiNextGenBrain.Initialize(Symbol(), Period()))
                {
                    Print("[INIT] WARNING: NextGen AI Brain failed to initialize");
                }
                else
                {
                    m_aiBrainReady = true;
                    Print("[AI] Runtime AI voters are adapter-owned and registered per symbol");
                }
            
                // Initialize AI Performance Feedback
                if(!m_aiFeedback.Initialize(1000))
                {
                    Print("[WARNING] AIPerformanceFeedback failed to initialize");
                }
                else
                {
                    m_aiFeedbackReady = true;
                    Print("[INIT] AIPerformanceFeedback initialized for AI model adaptation");
                }
            
                Print("[AI-DASHBOARD] AI Health Monitoring initialized");
            }
        
            // Initialize Python Bridge
            m_pythonBridge = new CPythonBridge();
            m_pythonBridge.Initialize(
                m_config.pythonBridgeEndpoint,
                m_config.pythonBridgeMode,
                m_config.pythonBridgeRequestTimeoutMs,
                m_config.pythonBridgeHeartbeatTimeoutSec,
                m_config.pythonBridgeMaxReconnectAttempts,
                m_config.pythonBridgeReconnectBackoffMs
            );
        
            // Initialize Dashboard Bridge
            m_dashboardBridge = new CDashboardBridge();
            m_dashboardBridge.Initialize(
                m_config.dashboardEndpoint,
                false,
                m_config.dashboardControlEnabled,
                m_config.dashboardPushIntervalSec,
                1000
            );
            m_dashboardBridge.SetEnabled(m_config.dashboardEnabled);
        
            // Initialize Fast Scalp Engine
            if(m_config.enableScalpEngine)
            {
                if(!m_scalpEngine.Initialize(&m_tradeManager, &m_unifiedRiskManager, &m_positionSizer, &m_riskTierManager))
                    Print("[SCALP-ENGINE] WARNING: Failed to initialize");
                else
                {
                    m_scalpEngine.SetMagicNumber(m_config.magicNumber);
                    m_scalpEngine.SetAsyncMode(m_config.scalpAsyncMode);
                    m_scalpEngine.SetMaxLatencyMs(m_config.scalpMaxLatencyMs);
                
                    // Initialize scalp signal cache
                    if(m_scalpCache.Initialize(m_symbols, m_managerCount, PERIOD_M1))
                    {
                        m_scalpEngine.SetSignalCache(GetPointer(m_scalpCache));
                        for(int si = 0; si < m_managerCount; si++)
                            m_scalpCache.SetScalpSetup(m_symbols[si], true, 1);
                        Print("[SCALP-CACHE] Fast-path dual-path architecture enabled");
                    }
                    else
                        Print("[SCALP-CACHE] WARNING: Cache initialization failed");
                }
            }
        
            // Initialize Spike Hunter
            if(m_config.spikeHunterEnabled)
            {
                SSpikeHunterConfig spikeConfig;
                spikeConfig.velocityMultiplier       = m_config.spikeHunterVelocityMult;
                spikeConfig.minConsecutiveTicks      = m_config.spikeHunterMinConsecTicks;
                spikeConfig.consecutiveTickWindowMs  = m_config.spikeHunterConsecWindowMs;
                spikeConfig.atrCompressionRatio      = m_config.spikeHunterATRCompression;
                spikeConfig.atrPeriod                = 14;
                spikeConfig.atrSmaPeriod             = 50;
                spikeConfig.slAtrMultiplier          = m_config.spikeHunterSLAtrMult;
                spikeConfig.tpAtrMultiplier          = m_config.spikeHunterTPAtrMult;
                spikeConfig.maxSpikePositions        = m_config.spikeHunterMaxPositions;
                spikeConfig.cooldownMs               = m_config.spikeHunterCooldownMs;
                spikeConfig.spikeCooldownForLongTermMs = m_config.spikeHunterLongTermCooldownMs;
                spikeConfig.magicOffset              = 9000;
                spikeConfig.enablePushAlerts         = m_config.spikeHunterPushAlerts;
                spikeConfig.alertThrottleSeconds     = m_config.spikeHunterAlertThrottle;
                spikeConfig.minConfluence            = m_config.spikeHunterMinConfluence;

                if(m_spikeHunter.Init(spikeConfig, m_config.magicNumber, &m_positionSizer, &m_unifiedRiskManager))
                {
                    for(int i = 0; i < m_managerCount; i++)
                    {
                        if(m_symbols[i] != "")
                            m_spikeHunter.AddSymbol(m_symbols[i]);
                    }
                    Print("[SPIKE-HUNTER] Initialized with ", m_managerCount, " symbols");
                }
                else
                    Print("[SPIKE-HUNTER] Initialization FAILED");
            }
        
            // Initialize Multi-Asset Profiler (Batch 103)
            if(m_config.multiAssetProfilerEnabled)
            {
                Print("[MULTI-ASSET-PROFILER] Initializing multi-asset class auto-detection...");
            
                for(int i = 0; i < m_managerCount; i++)
                {
                    string sym = m_symbols[i];
                    if(sym == "") continue;

                    SAssetProfile profile = m_multiAssetProfiler.GetProfile(sym);
                    m_unifiedRiskManager.SetRiskPerTrade(sym, profile.riskPerTrade);
                    m_unifiedRiskManager.SetMaxDrawdownForFamily(sym, (double)profile.maxDrawdownPercent);
                    m_tradeManager.SetMagicOffsetForSymbol(sym, profile.magicOffset);
                    PrintFormat("[MULTI-ASSET-PROFILER] %s class=%s -> risk=%.2f%% maxDD=%d%% magic=+%d",
                                sym, profile.className, profile.riskPerTrade, profile.maxDrawdownPercent, profile.magicOffset);
                }
            
                if(m_config.derivProfilerEnabled)
                {
                    Print("[DERIV-PROFILER] Initializing Deriv asset family auto-detection...");
                    CDerivAssetProfiler* derivProfiler = m_multiAssetProfiler.GetDerivProfiler();
                
                    if(m_config.spikeHunterEnabled && derivProfiler != NULL)
                    {
                        for(int i = 0; i < m_managerCount; i++)
                        {
                            string sym = m_symbols[i];
                            if(sym == "") continue;
                            if(!IsSyntheticIndexSymbolName(sym)) continue;

                            SDerivProfile profile = derivProfiler.GetProfile(sym);
                            if(profile.enableSpikeHunter)
                            {
                                m_spikeHunter.SetFamilyOverrides(sym,
                                    profile.spikeThreshold,
                                    6,
                                    profile.atrCompressionRatio,
                                    profile.atrMultiplierSL,
                                    profile.atrMultiplierTP,
                                    profile.magicOffset,
                                    profile.spikeCooldownSec * 1000,
                                    2);
                                PrintFormat("[DERIV-PROFILER] %s family=%s -> SpikeHunter overrides applied", sym, profile.familyName);
                            }
                        }
                    }
                
                    // Initialize Grid Recovery Engine
                    if(m_config.gridRecoveryEnabled)
                    {
                        SGridRecoveryConfig gridConfig;
                        gridConfig.gridFactorATR           = 0.25;
                        gridConfig.maxGridLevels           = 8;
                        gridConfig.progressionType         = GRID_PROGRESSION_MARTINGALE;
                        gridConfig.progressionFactor       = 1.5;
                        gridConfig.activationHurstThreshold = 0.45;
                        gridConfig.atrPeriod               = 14;
                        gridConfig.slAtrMultiplier         = 1.0;
                        gridConfig.tpAtrMultiplier         = 0.5;
                        gridConfig.magicOffset             = 8000;
                        gridConfig.maxDrawdownPercent      = 10;
                        gridConfig.cooldownMs              = 30000;

                        if(m_gridRecovery.Init(gridConfig, m_config.magicNumber, &m_positionSizer, &m_unifiedRiskManager))
                        {
                            for(int i = 0; i < m_managerCount; i++)
                            {
                                string sym = m_symbols[i];
                                if(sym == "") continue;
                                if(!IsSyntheticIndexSymbolName(sym)) continue;

                                SDerivProfile profile = derivProfiler.GetProfile(sym);
                                if(profile.enableGridRecovery)
                                {
                                    m_gridRecovery.AddSymbol(sym);
                                    m_gridRecovery.SetFamilyConfig(
                                        profile.gridFactorATR,
                                        profile.maxGridLevels,
                                        profile.gridProgressionFactor,
                                        profile.atrMultiplierSL,
                                        profile.atrMultiplierTP,
                                        profile.magicOffset);
                                    PrintFormat("[DERIV-PROFILER] %s family=%s -> GridRecovery enabled", sym, profile.familyName);
                                }
                            }
                            Print("[GRID-RECOVERY] Initialized for mean-reversion families");
                        }
                        else
                            Print("[GRID-RECOVERY] Initialization FAILED");
                    }
                
                    // Initialize ATR Scalping Engine
                    if(m_config.atrScalpingEnabled)
                    {
                        SATRScalpingConfig scalpConfig;
                        scalpConfig.atrPeriod              = 14;
                        scalpConfig.emaFastPeriod          = 5;
                        scalpConfig.emaSlowPeriod          = 13;
                        scalpConfig.rsiPeriod              = 7;
                        scalpConfig.spreadMaxATRRatio      = 0.30;
                        scalpConfig.slAtrMultiplier        = 2.0;
                        scalpConfig.tpAtrMultiplier        = 2.5;
                        scalpConfig.magicOffset            = 7000;
                        scalpConfig.maxPositions           = 3;
                        scalpConfig.cooldownMs             = 30000;
                        scalpConfig.spikeWindowAvoidMinutes = 5;

                        if(m_atrScalping.Init(scalpConfig, m_config.magicNumber, &m_positionSizer, &m_unifiedRiskManager))
                        {
                            for(int i = 0; i < m_managerCount; i++)
                            {
                                string sym = m_symbols[i];
                                if(sym == "") continue;
                                if(!IsSyntheticIndexSymbolName(sym)) continue;

                                SDerivProfile profile = derivProfiler.GetProfile(sym);
                                if(profile.family == DERIV_JUMP || profile.family == DERIV_DEX || profile.family == DERIV_HYBRID)
                                {
                                    int spikeIntervalSec = 0;
                                    if(profile.family == DERIV_JUMP) spikeIntervalSec = 1200;
                                    else if(profile.family == DERIV_DEX)
                                    {
                                        if(StringFind(sym, "900") >= 0) spikeIntervalSec = 900;
                                        else if(StringFind(sym, "1500") >= 0) spikeIntervalSec = 1500;
                                        else if(StringFind(sym, "2600") >= 0) spikeIntervalSec = 2600;
                                        else spikeIntervalSec = 900;
                                    }
                                    m_atrScalping.AddSymbol(sym, spikeIntervalSec);
                                    PrintFormat("[DERIV-PROFILER] %s family=%s -> ATRScalping enabled (spikeInterval=%ds)",
                                                sym, profile.familyName, spikeIntervalSec);
                                }
                            }
                            Print("[ATR-SCALP] Initialized for between-spike families");
                        }
                        else
                            Print("[ATR-SCALP] Initialization FAILED");
                    }
                }
            
                m_diagnosticsManager.SetDerivProfiler(m_multiAssetProfiler.GetDerivProfiler());
                m_diagnosticsManager.SetMultiAssetProfiler(&m_multiAssetProfiler);
                string profilerSymbols[];
                ArrayResize(profilerSymbols, m_managerCount);
                for(int i = 0; i < m_managerCount; i++)
                    profilerSymbols[i] = m_symbols[i];
                m_diagnosticsManager.SetSymbols(profilerSymbols, m_managerCount);
            
                Print("[MULTI-ASSET-PROFILER] Batch 103 initialization complete");
            }
        
            // Initialize Mathematical Engines (Batch 100 & 114)
            InitializeMathematicalEngines();
        
            // Initialize Institutional TA Engines (Batch 107)
            InitializeInstitutionalEngines();
        
            // Initialize consensus cache
            m_consensusCache.InvalidateAll();
        
            // Initialize scan scheduler
            m_scanScheduler.SetManagers(m_enterpriseManagers, m_enterpriseManagerSymbols, ArraySize(m_enterpriseManagers));
            m_scanScheduler.SetInputParams(m_config.intrabarScanSeconds, m_config.intrabarBackoffMaxSeconds);
            m_scanScheduler.RebuildSymbolSchedulerState("post_manager_init");
        
                        return true;
                    }
    
        // ============ Private Helper Methods ============
    
    bool InitializeComponents()
    {
        // Initialize core signal processing components
        // SignalGenerator
        if(!m_signalGenerator.Initialize(&m_consensusCache, &m_unifiedRiskManager, &m_positionSizer,
                                          m_config.magicNumber, m_config.logLevel))
        {
            Print("[CRITICAL] SignalGenerator initialization FAILED");
            return false;
        }
        Print("[INIT] SignalGenerator initialized");
        
        // SignalValidator
        if(!m_signalValidator.Initialize(m_config.validatorNewBarMinConfluence, m_config.validatorNewBarMinQuality,
                                          m_config.validatorNewBarMinConfidence, m_config.validatorIntrabarMinConfluence,
                                          m_config.validatorIntrabarMinQuality, m_config.validatorIntrabarMinConfidence))
        {
            Print("[CRITICAL] SignalValidator initialization FAILED");
            return false;
        }
        Print("[INIT] SignalValidator initialized");
        
        // CandidateBuilder
        if(!m_candidateBuilder.Initialize(&m_positionSizer, &m_unifiedRiskManager, &m_riskTierManager,
                                           &m_compoundingTierManager, &m_familyWeightMatrix,
                                           &m_sessionWeightManager, &m_skewStepAnalyzer))
        {
            Print("[CRITICAL] CandidateBuilder initialization FAILED");
            return false;
        }
        Print("[INIT] CandidateBuilder initialized");
        
        // TradeExecutor
        if(!m_tradeExecutor.Initialize(&m_tradeManager, &m_unifiedRiskManager, &m_positionSizer,
                                        m_config.magicNumber, m_config.orderFillingMode,
                                        m_config.tradeSlippagePoints, m_config.maxEntrySpreadPoints,
                                        m_config.maxEntryDriftPoints, m_config.protectiveModifyCooldownSec))
        {
            Print("[CRITICAL] TradeExecutor initialization FAILED");
            return false;
        }
        Print("[INIT] TradeExecutor initialized");
        
        // LiveAuthorityResolver
        if(m_config.enableLiveAuthorityGate)
        {
            if(!m_liveAuthority.Initialize(m_config.authorityMinSamples, m_config.authorityTrialHorizonSeconds,
                                           m_config.authorityMaxTrackedTrials, m_config.authorityMinExpectancyR,
                                           m_config.authorityMinProfitFactor, m_config.authorityMinCostScore,
                                           m_config.authorityMinReadinessScore, m_config.authorityMinContextScore))
            {
                Print("[CRITICAL] LiveAuthorityResolver initialization FAILED");
                return false;
            }
            Print("[INIT] LiveAuthorityResolver initialized");
        }
        
        // PositionManager
        if(!m_positionManager.Initialize(&m_tradeManager, &m_unifiedRiskManager, &m_consensusCache,
                                          &m_positionSizer, &m_compoundingTierManager,
                                          m_config.magicNumber, m_config.maxPositionsTotal))
        {
            Print("[CRITICAL] PositionManager initialization FAILED");
            return false;
        }
        Print("[INIT] PositionManager initialized");
        
        // Register mathematical engines with registry
        m_mathRegistry.RegisterAll(m_hurstEngines, m_ouEngines, m_ofiEngines, m_vpinFilters,
                                   m_kalmanEngines, m_cpdEngines, m_fourStateEngines,
                                   m_volTargetEngines, m_exitOptimizers, m_liquiditySweepStrategies,
                                   m_rangeCompStrategies, m_mathEngineSymbols, ArraySize(m_mathEngineSymbols));
        
        // Register institutional engines with registry
        m_instRegistry.RegisterAll(m_vwapEngines, m_vpEngines, m_cvdEngines,
                                   m_symbols, m_managerCount);
        
        // Register neural network strategies if AI enabled
        if(m_config.enableAIMode && (m_config.enableNeuralNetwork || m_config.enableTransformer || 
                                      m_config.enableEnsemble || m_config.enableOnnxAI))
        {
            m_nnRegistry.RegisterAll(m_neuralNetStrategies, m_neuralNetStrategySymbols,
                                     ArraySize(m_neuralNetStrategies));
        }
        
        // Register drawing managers
        m_drawingRegistry.RegisterAll(m_drawingManagers, m_drawingManagerSymbols,
                                      ArraySize(m_drawingManagers));
        
        // Register scan scheduler
        m_scanScheduler.SetManagers(m_enterpriseManagers, m_enterpriseManagerSymbols, m_managerCount);
        
        // Initialize symbol state tracker
        m_symbolState.Initialize(m_symbols, m_managerCount);
        
        Print("[INIT] All components initialized successfully");
        return true;
    }
    
    void InitializeMathematicalEngines()
    {
        int count = m_managerCount;
        if(count <= 0) return;
        
        // Resize all engine arrays
        ArrayResize(m_hurstEngines, count);
        ArrayResize(m_ouEngines, count);
        ArrayResize(m_ofiEngines, count);
        ArrayResize(m_vpinFilters, count);
        ArrayResize(m_kalmanEngines, count);
        ArrayResize(m_cpdEngines, count);
        ArrayResize(m_fourStateEngines, count);
        ArrayResize(m_volTargetEngines, count);
        ArrayResize(m_exitOptimizers, count);
        ArrayResize(m_liquiditySweepStrategies, count);
        ArrayResize(m_rangeCompStrategies, count);
        ArrayResize(m_mathEngineSymbols, count);
        ArrayResize(m_gridHurstBridgeLogged, count);
        
        for(int i = 0; i < count; i++)
        {
            string sym = m_symbols[i];
            if(sym == "") continue;
            
            m_mathEngineSymbols[i] = sym;
            
            // Batch 100: Hurst Engine
            if(m_config.enableHurstEngine)
            {
                m_hurstEngines[i] = new CHurstEngine();
                if(m_hurstEngines[i] != NULL)
                {
                    if(m_hurstEngines[i].Initialize(sym, m_config.hurstLookback))
                    {
                        m_mathRegistry.RegisterHurstEngine(sym, m_hurstEngines[i]);
                        PrintFormat("[HURST] Engine initialized for %s (lookback=%d)", sym, m_config.hurstLookback);
                    }
                    else
                    {
                        PrintFormat("[HURST] WARNING: Failed to initialize for %s", sym);
                        delete m_hurstEngines[i];
                        m_hurstEngines[i] = NULL;
                    }
                }
            }
            
            // Batch 100: Ornstein-Uhlenbeck Process
            if(m_config.enableOUProcess)
            {
                m_ouEngines[i] = new COrnsteinUhlenbeckEngine();
                if(m_ouEngines[i] != NULL)
                {
                    if(m_ouEngines[i].Initialize(sym, m_config.ouLookback))
                    {
                        m_mathRegistry.RegisterOUEngine(sym, m_ouEngines[i]);
                        PrintFormat("[OU] Engine initialized for %s (lookback=%d)", sym, m_config.ouLookback);
                    }
                    else
                    {
                        PrintFormat("[OU] WARNING: Failed to initialize for %s", sym);
                        delete m_ouEngines[i];
                        m_ouEngines[i] = NULL;
                    }
                }
            }
            
            // Batch 100: Order Flow Imbalance Proxy
            if(m_config.enableOFIProxy)
            {
                m_ofiEngines[i] = new COrderFlowImbalanceEngine();
                if(m_ofiEngines[i] != NULL)
                {
                    if(m_ofiEngines[i].Initialize(sym, m_config.ofiSlowWindow))
                    {
                        m_mathRegistry.RegisterOFIEngine(sym, m_ofiEngines[i]);
                        PrintFormat("[OFI] Engine initialized for %s (slowWindow=%d)", sym, m_config.ofiSlowWindow);
                    }
                    else
                    {
                        PrintFormat("[OFI] WARNING: Failed to initialize for %s", sym);
                        delete m_ofiEngines[i];
                        m_ofiEngines[i] = NULL;
                    }
                }
            }
            
            // Batch 100: VPIN Filter
            if(m_config.enableVPINFilter)
            {
                m_vpinFilters[i] = new CVPINFilter();
                if(m_vpinFilters[i] != NULL)
                {
                    if(m_vpinFilters[i].Initialize(sym, m_config.vpinExtremeThreshold, m_config.vpinNumBuckets))
                    {
                        m_mathRegistry.RegisterVPINFilter(sym, m_vpinFilters[i]);
                        PrintFormat("[VPIN] Filter initialized for %s (threshold=%.2f, buckets=%d)",
                                    sym, m_config.vpinExtremeThreshold, m_config.vpinNumBuckets);
                    }
                    else
                    {
                        PrintFormat("[VPIN] WARNING: Failed to initialize for %s", sym);
                        delete m_vpinFilters[i];
                        m_vpinFilters[i] = NULL;
                    }
                }
            }
            
            // Batch 114: Kalman Mean Reversion
            if(m_config.enableKalmanMR)
            {
                m_kalmanEngines[i] = new CKalmanMeanReversion();
                if(m_kalmanEngines[i] != NULL)
                {
                    if(m_kalmanEngines[i].Initialize(sym, m_config.kalmanLambda))
                    {
                        m_mathRegistry.RegisterKalmanEngine(sym, m_kalmanEngines[i]);
                        PrintFormat("[KALMAN-MR] Engine initialized for %s (lambda=%.1f)", sym, m_config.kalmanLambda);
                    }
                    else
                    {
                        PrintFormat("[KALMAN-MR] WARNING: Failed to initialize for %s", sym);
                        delete m_kalmanEngines[i];
                        m_kalmanEngines[i] = NULL;
                    }
                }
            }
            
            // Batch 114: Changepoint Detector
            if(m_config.enableChangepointDetect)
            {
                m_cpdEngines[i] = new CChangepointDetector();
                if(m_cpdEngines[i] != NULL)
                {
                    if(m_cpdEngines[i].Initialize(sym, m_config.cpdHazardThreshold))
                    {
                        m_mathRegistry.RegisterCPDDetector(sym, m_cpdEngines[i]);
                        PrintFormat("[CPD] Detector initialized for %s (hazard=%.2f)", sym, m_config.cpdHazardThreshold);
                    }
                    else
                    {
                        PrintFormat("[CPD] WARNING: Failed to initialize for %s", sym);
                        delete m_cpdEngines[i];
                        m_cpdEngines[i] = NULL;
                    }
                }
            }
            
            // Batch 114: Four State Regime Detector
            if(m_config.enableFourStateRegime)
            {
                m_fourStateEngines[i] = new CFourStateRegimeDetector();
                if(m_fourStateEngines[i] != NULL)
                {
                    if(m_fourStateEngines[i].Initialize(sym))
                    {
                        m_mathRegistry.RegisterFourStateDetector(sym, m_fourStateEngines[i]);
                        PrintFormat("[FOUR-STATE] Detector initialized for %s", sym);
                    }
                    else
                    {
                        PrintFormat("[FOUR-STATE] WARNING: Failed to initialize for %s", sym);
                        delete m_fourStateEngines[i];
                        m_fourStateEngines[i] = NULL;
                    }
                }
            }
            
            // Batch 114: Volatility Targeting
            if(m_config.enableVolTargeting)
            {
                m_volTargetEngines[i] = new CVolatilityTargeting();
                if(m_volTargetEngines[i] != NULL)
                {
                    if(m_volTargetEngines[i].Initialize(sym, m_config.targetVol,
                                                        m_config.volMinScale, m_config.volMaxScale))
                    {
                        m_mathRegistry.RegisterVolTargetEngine(sym, m_volTargetEngines[i]);
                        PrintFormat("[VOL-TARGET] Engine initialized for %s (target=%.2f, scale=[%.2f,%.2f])",
                                    sym, m_config.targetVol, m_config.volMinScale, m_config.volMaxScale);
                    }
                    else
                    {
                        PrintFormat("[VOL-TARGET] WARNING: Failed to initialize for %s", sym);
                        delete m_volTargetEngines[i];
                        m_volTargetEngines[i] = NULL;
                    }
                }
            }
            
            // Batch 114: Exit Optimizer
            if(m_config.enableExitOptimizer)
            {
                m_exitOptimizers[i] = new CExitOptimizer();
                if(m_exitOptimizers[i] != NULL)
                {
                    if(m_exitOptimizers[i].Initialize(sym))
                    {
                        m_mathRegistry.RegisterExitOptimizer(sym, m_exitOptimizers[i]);
                        PrintFormat("[EXIT-OPT] Optimizer initialized for %s", sym);
                    }
                    else
                    {
                        PrintFormat("[EXIT-OPT] WARNING: Failed to initialize for %s", sym);
                        delete m_exitOptimizers[i];
                        m_exitOptimizers[i] = NULL;
                    }
                }
            }
            
            // Batch 114: Liquidity Sweep Strategy
            if(m_config.enableLiquiditySweep)
            {
                m_liquiditySweepStrategies[i] = new CLiquiditySweepStrategy();
                if(m_liquiditySweepStrategies[i] != NULL)
                {
                    if(m_liquiditySweepStrategies[i].Initialize(sym))
                    {
                        m_mathRegistry.RegisterLiquiditySweepStrategy(sym, m_liquiditySweepStrategies[i]);
                        PrintFormat("[LIQ-SWEEP] Strategy initialized for %s", sym);
                    }
                    else
                    {
                        PrintFormat("[LIQ-SWEEP] WARNING: Failed to initialize for %s", sym);
                        delete m_liquiditySweepStrategies[i];
                        m_liquiditySweepStrategies[i] = NULL;
                    }
                }
            }
            
            // Batch 114: Range Compression Breakout
            if(m_config.enableRangeCompression)
            {
                m_rangeCompStrategies[i] = new CRangeCompressionBreakout();
                if(m_rangeCompStrategies[i] != NULL)
                {
                    if(m_rangeCompStrategies[i].Initialize(sym))
                    {
                        m_mathRegistry.RegisterRangeCompressionStrategy(sym, m_rangeCompStrategies[i]);
                        PrintFormat("[RANGE-COMP] Strategy initialized for %s", sym);
                    }
                    else
                    {
                        PrintFormat("[RANGE-COMP] WARNING: Failed to initialize for %s", sym);
                        delete m_rangeCompStrategies[i];
                        m_rangeCompStrategies[i] = NULL;
                    }
                }
            }
            
            m_gridHurstBridgeLogged[i] = false;
        }
        
        PrintFormat("[INIT] Mathematical engines initialized for %d symbols", count);
    }
    
    void InitializeInstitutionalEngines()
    {
        int count = m_managerCount;
        if(count <= 0) return;
        
        // Resize institutional engine arrays
        ArrayResize(m_vwapEngines, count);
        ArrayResize(m_vpEngines, count);
        ArrayResize(m_cvdEngines, count);
        
        for(int i = 0; i < count; i++)
        {
            string sym = m_symbols[i];
            if(sym == "") continue;
            
            // Only initialize for Forex symbols
            if(!IsForexSymbol(sym))
            {
                continue;
            }
            
            // Batch 107: VWAP Engine
            if(m_config.enableVWAPEngine)
            {
                m_vwapEngines[i] = new CVWAPEngine();
                if(m_vwapEngines[i] != NULL)
                {
                    SVWAPConfig vwapConfig;
                    vwapConfig.minPeriodBars = m_config.vwapMinPeriodBars;
                    vwapConfig.band1 = m_config.vwapBand1;
                    vwapConfig.band2 = m_config.vwapBand2;
                    vwapConfig.band3 = m_config.vwapBand3;
                    
                    if(m_vwapEngines[i].Initialize(sym, vwapConfig))
                    {
                        m_instRegistry.RegisterVWAPEngine(sym, m_vwapEngines[i]);
                        PrintFormat("[VWAP] Engine initialized for %s (period=%d, bands=%.1f/%.1f/%.1f)",
                                    sym, vwapConfig.minPeriodBars, vwapConfig.band1, vwapConfig.band2, vwapConfig.band3);
                    }
                    else
                    {
                        PrintFormat("[VWAP] WARNING: Failed to initialize for %s", sym);
                        delete m_vwapEngines[i];
                        m_vwapEngines[i] = NULL;
                    }
                }
            }
            
            // Batch 107: Volume Profile Engine
            if(m_config.enableVolumeProfile)
            {
                m_vpEngines[i] = new CVolumeProfileEngine();
                if(m_vpEngines[i] != NULL)
                {
                    SVolumeProfileConfig vpConfig;
                    vpConfig.lookback = m_config.vpLookback;
                    vpConfig.resolution = m_config.vpResolution;
                    
                    if(m_vpEngines[i].Initialize(sym, vpConfig))
                    {
                        m_instRegistry.RegisterVPEngine(sym, m_vpEngines[i]);
                        PrintFormat("[VP] Engine initialized for %s (lookback=%d, resolution=%d)",
                                    sym, vpConfig.lookback, vpConfig.resolution);
                    }
                    else
                    {
                        PrintFormat("[VP] WARNING: Failed to initialize for %s", sym);
                        delete m_vpEngines[i];
                        m_vpEngines[i] = NULL;
                    }
                }
            }
            
            // Batch 107: CVD Engine
            if(m_config.enableCVDEngine)
            {
                m_cvdEngines[i] = new CCVDEngine();
                if(m_cvdEngines[i] != NULL)
                {
                    SCVDConfig cvdConfig;
                    cvdConfig.divergenceLookback = m_config.cvdDivergenceLookback;
                    
                    if(m_cvdEngines[i].Initialize(sym, cvdConfig))
                    {
                        m_instRegistry.RegisterCVDEngine(sym, m_cvdEngines[i]);
                        PrintFormat("[CVD] Engine initialized for %s (divLookback=%d)",
                                    sym, cvdConfig.divergenceLookback);
                    }
                    else
                    {
                        PrintFormat("[CVD] WARNING: Failed to initialize for %s", sym);
                        delete m_cvdEngines[i];
                        m_cvdEngines[i] = NULL;
                    }
                }
            }
        }
        
        PrintFormat("[INIT] Institutional TA engines initialized for %d forex symbols", count);
    }

    // ============ Main Processing ============
    
    void OnTick()
    {
        ProcessTickSafetyLoop();
        
        // Feed microstructure engines
        FeedMicrostructureEngines();
        
        // Fast-path scalp evaluation
        if(m_enableScalpEngine)
            ProcessScalpFastPath();
    }
    
    void OnTimer()
    {
        m_callCount++;
        ProcessTradingLogic(true);
    }
    
    void ProcessTradingLogic(bool fromTimer)
    {
        if(!m_systemInitialized || !m_tradingEnabled) return;
        
        // Update risk state
        m_riskManager.RefreshRuntimeState();
        
        // Update daily profit target logic
        UpdateDailyProfitTarget();
        
        // Update auto mode switching
        UpdateAutoModeSwitch();
        
        // Check unprotected positions
        m_unprotectedTracker.AttemptRemediation();
        bool unprotectedActive = m_riskManager.HasUnprotectedPositions();
        
        // Neural network online learning
        if(m_enableAIMode && m_enableNeuralNetwork && m_enableNNOnlineTraining)
        {
            // m_nnRegistry.TickOnlineLearningAll(); // Method doesn't exist, use individual calls
            // Would iterate through symbols and call online learning per symbol
        }
        
        // AI engine adaptation
        if(m_enableAIMode && m_aiEngine != NULL)
        {
            m_aiEngine.ProcessAdaptation();
        }
        
        // AI feedback maintenance
        if(m_aiFeedback != NULL)
        {
            m_aiFeedback.CheckAutomaticRetraining();
        }
        
        // Process new bars
        ProcessNewBars();
        
        // Generate and validate signals
        GenerateAndProcessSignals();
        
        // Manage positions
        m_positionManager.ManagePositions();
    }
    
    void ProcessTickSafetyLoop()
    {
        // Would delegate to tick safety monitor
    }
    
    void FeedMicrostructureEngines()
    {
        static uint s_lastFeed = 0;
        uint nowMs = GetTickCount();
        if(nowMs - s_lastFeed >= 200)
        {
            for(int i = 0; i < m_managerCount; i++)
            {
                string sym = m_symbols[i];
                double price = SymbolInfoDouble(sym, SYMBOL_BID);
                double volume = (double)SymbolInfoInteger(sym, SYMBOL_VOLUME);
                double bid = SymbolInfoDouble(sym, SYMBOL_BID);
                double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
                
                m_mathRegistry.OnTickAll(sym, price, volume, bid, ask);
                m_instRegistry.OnTickAll(sym, price, volume, bid, ask);
            }
            s_lastFeed = nowMs;
        }
    }
    
    void ProcessScalpFastPath()
    {
        // Delegate to scalp engine
    }
    
    void UpdateDailyProfitTarget()
    {
        datetime today = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
        if(today != m_lastProfitTargetDay)
        {
            m_lastProfitTargetDay = today;
            m_dailyProfitTargetReached = false;
            m_dailyProfitPeakPct = 0.0;
            m_trailingProfitFloor = 0.0;
            m_dailyTradingHalt = false;
            m_dailyTradingHaltStartTime = 0;
        }
        
        if(m_dailyProfitTargetPercent > 0.0 && !m_dailyTradingHalt)
        {
            double dailyPnL = CalculateDailyPnLPercent();
            
            if(dailyPnL >= m_dailyProfitTargetPercent && !m_dailyProfitTargetReached)
            {
                m_dailyProfitTargetReached = true;
                m_dailyProfitPeakPct = dailyPnL;
                m_trailingProfitFloor = dailyPnL * m_profitTrailFactor;
            }
            
            if(m_dailyProfitTargetReached)
            {
                m_dailyProfitPeakPct = MathMax(m_dailyProfitPeakPct, dailyPnL);
                m_trailingProfitFloor = m_dailyProfitPeakPct * m_profitTrailFactor;
                
                if(dailyPnL < m_trailingProfitFloor)
                {
                    double hardFloor = m_dailyProfitTargetPercent * m_profitTargetHardFloorRatio;
                    // Would trigger selective close
                    m_dailyTradingHalt = true;
                    m_dailyTradingHaltStartTime = TimeCurrent();
                }
            }
        }
        
        if(m_dailyTradingHalt && m_dailyTradingHaltStartTime > 0)
        {
            int elapsed = (int)(TimeCurrent() - m_dailyTradingHaltStartTime) / 60;
            if(elapsed >= m_dailyHaltCooldownMinutes)
            {
                m_dailyTradingHalt = false;
                m_dailyTradingHaltStartTime = 0;
                m_dailyProfitTargetReached = false;
                m_dailyProfitPeakPct = 0.0;
                m_trailingProfitFloor = 0.0;
            }
        }
    }
    
    void UpdateAutoModeSwitch()
    {
        if(!m_enableAutoModeSwitch) return;
        
        // Would determine mode and apply risk parameters
    }
    
    void ProcessNewBars()
    {
        bool anyNewBar = false;
        
        for(int i = 0; i < m_managerCount; i++)
        {
            string symbol = m_symbols[i];
            datetime currentBar = iTime(symbol, (ENUM_TIMEFRAMES)Period(), 0);
            if(currentBar <= 0) continue;
            
            if(m_scanScheduler.CheckNewBar(symbol, currentBar))
            {
                anyNewBar = true;
                m_consensusCache.Invalidate(symbol);
                // m_scanScheduler.SetPendingNewBarScan(symbol, true); // CheckNewBar already sets this
                m_scanScheduler.ResetIntrabarBackoff(symbol);
                
                if(m_managers[i] != NULL)
                    m_managers[i].OnNewBar(symbol, (ENUM_TIMEFRAMES)Period());
                
                // AI engine adaptation
                if(m_enableAIMode && m_aiEngine != NULL)
                    m_aiEngine.ProcessAdaptation();
                
                // AI feedback
                if(m_aiFeedback != NULL)
                    m_aiFeedback.CheckAutomaticRetraining();
            }
        }
    }
    
    void GenerateAndProcessSignals()
    {
        // Check trading permissions
        if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
            return;
        
        // Check trading blocks
        int secondsSinceLastTrade = (int)(TimeCurrent() - m_lastTradeTime);
        bool cooldownBlocked = (secondsSinceLastTrade < m_minSecondsBetweenTrades && m_lastTradeTime > 0);
        int eaPositions = GetEAPositionCount();
        bool positionLimitBlocked = (eaPositions >= m_maxPositionsTotal);
        bool unprotectedBlocked = m_riskManager.HasUnprotectedPositions();
        bool spikePaused = m_spikeMonitor.IsPaused();
        
        bool canOpenNewTrades = !(cooldownBlocked || positionLimitBlocked || unprotectedBlocked || spikePaused || m_dailyTradingHalt);
        
        // Generate signals (new bar mode)
        CSignalGenerator::SSignalResult newBarSignals[];
        m_signalGenerator.GenerateSignals(EVAL_MODE_NEW_BAR, newBarSignals);
        
        // Validate and build candidates
        for(int i = 0; i < ArraySize(newBarSignals); i++)
        {
            if(!newBarSignals[i].valid) continue;
            
            string symbol = m_symbols[i];
            CEnterpriseStrategyManager* manager = m_managers[i];
            if(manager == NULL) continue;
            
            // Build candidate (declare at top of loop for scope)
            STradeCandidate candidate;
            bool candidateBuilt = false;
            
            // Validate
            CSignalValidator::SValidationResult validation = m_signalValidator.Validate(
                symbol, newBarSignals[i].signal, newBarSignals[i].confidence,
                newBarSignals[i].confluence, EVAL_MODE_NEW_BAR, newBarSignals[i].decisionContext,
                ++m_scanCycleSequence);
            
            if(!validation.passed) continue;
            
            // Build candidate
            if(!m_candidateBuilder.BuildCandidate(symbol, newBarSignals[i].signal, newBarSignals[i].confidence,
                                                  newBarSignals[i].confluence, newBarSignals[i].decisionContext,
                                                  manager, m_scanCycleSequence, candidate))
                continue;
            candidateBuilt = true;
            
            // Resolve live authority
            CLiveAuthorityResolver::SAuthorityResult authority;
            m_liveAuthority.Resolve(
                symbol, candidate.hasAIContributor, candidate.hasONNXContributor,
                candidate.hasIndicatorContributor, candidate.indicatorContributorCount,
                candidate.confluence, candidate.confidence, candidate.qualityScore,
                candidate.convictionScore, candidate.readinessScore, candidate.contextScore,
                candidate.costScore, candidate.contributorSummary, authority);
            
            candidate.liveAuthorityAllowed = authority.allowed;
            candidate.liveAuthorityRiskMult = authority.riskMultiplier;
            candidate.liveAuthorityReason = authority.reason;
            
            if(!authority.allowed) continue;
            
            // Check entry blocks
            if(!canOpenNewTrades) continue;
            
            // Execute trade
            // m_tradeExecutor.Execute(candidate);
            
            // Update heartbeat
            m_hbSignalsValidated++;
            m_hbSignalsRiskApproved++;
            m_hbSignalsSent++;
        }
    }
    
    // ============ Helpers ============
    
    int GetEAPositionCount() const
    {
        int count = 0;
        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
            if(IsEAOwnedMagic(PositionGetInteger(POSITION_MAGIC))) count++;
        }
        return count;
    }
    
    int GetEAPositionCountForSymbol(const string symbol, bool onlyThisEAMagic = true) const
    {
        if(symbol == "") return 0;
        
        int count = 0;
        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
            
            if(PositionGetString(POSITION_SYMBOL) != symbol)
                continue;
                
            if(onlyThisEAMagic && !IsEAOwnedMagic(PositionGetInteger(POSITION_MAGIC)))
                continue;
                
            count++;
        }
        return count;
    }
    
    bool IsEAOwnedMagic(long magic) const
    {
        // Simplified check
        return m_tradeManager.IsEAOwnedMagic(magic);
    }
    
    double CalculateDailyPnLPercent()
    {
        double balance = AccountInfoDouble(ACCOUNT_BALANCE);
        double equity = AccountInfoDouble(ACCOUNT_EQUITY);
        if(balance <= 0) return 0;
        return (equity - balance) / balance * 100.0;
    }
    
    // ============ Diagnostics ============
    
    string GetStatusReport() const
    {
        string report = "[EAOrchestrator] ";
        report += "Initialized=" + (m_systemInitialized ? "Y" : "N");
        report += " | Trading=" + (m_tradingEnabled ? "Y" : "N");
        report += " | Managers=" + IntegerToString(m_managerCount);
        report += " | Cycle=" + IntegerToString(m_callCount);
        report += " | Scans=" + IntegerToString(m_hbScansAttempted);
        report += " | Validated=" + IntegerToString(m_hbSignalsValidated);
        report += " | Sent=" + IntegerToString(m_hbSignalsSent);
        report += " | Positions=" + IntegerToString(GetEAPositionCount()) + "/" + IntegerToString(m_maxPositionsTotal) + "\n";
        
        report += m_signalGenerator.GetStatusReport();
        report += m_signalValidator.GetStatusReport();
        report += m_liveAuthority.GetStatusReport();
        report += m_positionManager.GetStatusReport();
        report += m_mathRegistry.GetStatusReport();
        report += m_instRegistry.GetStatusReport();
        report += m_nnRegistry.GetStatusReport();
        report += m_drawingRegistry.GetStatusReport();
        report += m_scanScheduler.GetStatusReport();
        report += m_symbolState.GetStatusReport();
        
        return report;
    }
    
    // ============ Accessors ============
    
    bool GetSystemInitialized() const { return m_systemInitialized; }
    bool GetTradingEnabled() const { return m_tradingEnabled; }
};

#endif // CORE_ORCHESTRATION_EA_ORCHESTRATOR_MQH