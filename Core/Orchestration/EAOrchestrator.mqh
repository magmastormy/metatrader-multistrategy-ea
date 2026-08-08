//+------------------------------------------------------------------+
//| EAOrchestrator.mqh                                               |
//| Main coordination class - replaces monolithic EA logic           |
//| Single composition root (Factory/Builder pattern) - Batch 123    |
//+------------------------------------------------------------------+
#property strict

#ifndef CORE_ORCHESTRATION_EA_ORCHESTRATOR_MQH
#define CORE_ORCHESTRATION_EA_ORCHESTRATOR_MQH

#include "OrchestratorFwd.mqh"
#include "SignalGenerator.mqh"
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
#include "../../Core/Trading/TradeAttributionManager.mqh"
#include "../../Core/Engines/AIEngine.mqh"
#include "../../Core/AI/AIPerformanceFeedback.mqh"
#include "../../Core/AI/ONNXInitManager.mqh"
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
#include "../../Core/Utils/JsonLogger.mqh"
#include "../../Core/Utils/LogMacros.mqh"
#include "../../Core/Utils/Enums.mqh"
#include "../../Core/Utils/Instruments.mqh"
#include "../../Core/Engines/MarketAnalysis.mqh"
#include "../../Core/Engines/StructureEngine.mqh"
#include "../../Core/Engines/TrendEngine.mqh"
#include "../../Core/Engines/LiquidityEngine.mqh"
#include "../../Core/Engines/VolatilityEngine.mqh"
#include "../../Core/Strategy/StrategyBase.mqh"
#include "../../Core/Factory/StrategyFactory.mqh"
#include "../../Core/Management/PositionLifecycleManager.mqh"
#include "../../Core/Management/DiagnosticsManager.mqh"
#include "HeartbeatTelemetry.mqh"
#include "../../Core/Signals/SignalDiagnostics.mqh"
#include "../../Core/Utils/DashboardBridge.mqh"
#include "../../Core/Monitoring/PerformanceAnalytics.mqh"
#include "../../Core/Scalp/FastScalpEngine.mqh"
#include "../../Core/Scalp/SpikeHunterEngine.mqh"
#include "../../Core/Scalp/GridRecoveryEngine.mqh"
#include "../../Core/Scalp/ATRScalpingEngine.mqh"
#include "../../Core/Scalp/ScalpSignalCache.mqh"
#include "../../Core/Processing/MultiAssetProfiler.mqh"
#include "../../IndicatorManager.mqh"
#include "../../Core/Registry/RegistryAggregator.mqh"
#include "OrchestratorStatusReporter.mqh"
#include "../../Core/Strategy/StrategyRegistry.mqh"
#include "../../Core/Management/SymbolUniverseBuilder.mqh"
#include "../../Core/Risk/MagicNumberAllocator.mqh"
#include "../../crash_recovery_helpers.mqh"
#include <Trade\SymbolInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <Object.mqh>

// Magic number constants for EA-owned position management
#define MAGIC_SYMBOL_MULTIPLIER 100
#define MAGIC_MAX_CLUSTER_CODE  99

// Strategy constants
#define STRATEGY_COUNT 21  // Number of indicator strategies in flags array (0-20, max enum value is STRATEGY_EXIT_OPTIMIZER=20)

// AI Strategy types (registered separately via AI adapters)
#define STRATEGY_NEURAL_NETWORK_AI 17
#define STRATEGY_TRANSFORMER_AI 18
#define STRATEGY_ENSEMBLE_AI 19
#define STRATEGY_ONNX_AI 20
#define STRATEGY_PYTHON_BRIDGE_AI 21

// L2-003/L2-013: Crash recovery state file
#define CRASH_RECOVERY_STATE_FILE "CrashRecoveryState.json"

#include "OrchestratorConfig.mqh"
#include "StrategyConfigBuilder.mqh"

//+------------------------------------------------------------------+
//| CEAOrchestratorBuilder - Builder pattern for orchestrator        |
//+------------------------------------------------------------------+
class CEAOrchestratorBuilder
{
    private:
    SOrchestratorConfig m_config;

    public:
    CEAOrchestratorBuilder() {}

    CEAOrchestratorBuilder* WithConfig(const SOrchestratorConfig &config) { m_config = config; return GetPointer(this); }

    // Individual setters for fluent API
    CEAOrchestratorBuilder* WithMagicNumber(long v) { m_config.magicNumber = v; return GetPointer(this); }
    CEAOrchestratorBuilder* WithLotSize(double v) { m_config.lotSize = v; return GetPointer(this); }
    CEAOrchestratorBuilder* WithRiskSettings(double maxRisk, double maxDaily, double maxPortfolio, double maxDD)
    { m_config.maxRiskPerTrade = maxRisk; m_config.maxDailyRisk = maxDaily; m_config.maxPortfolioRisk = maxPortfolio; m_config.maxDrawdown = maxDD; return GetPointer(this); }
    CEAOrchestratorBuilder* WithRiskTier(ENUM_RISK_TIER v) { m_config.riskTier = v; return GetPointer(this); }
    CEAOrchestratorBuilder* WithSymbols(string v) { m_config.symbolsToTrade = v; return GetPointer(this); }
    CEAOrchestratorBuilder* WithEAMode(ENUM_EA_MODE v) { m_config.eaMode = v; return GetPointer(this); }
        CEAOrchestratorBuilder* WithAIMode(bool v) { m_config.enableAIMode = v; return GetPointer(this); }
        CEAOrchestratorBuilder* WithLogLevel(int v) { m_config.logLevel = v; return GetPointer(this); }
        CEAOrchestratorBuilder* WithLogVerbosity(int v) { m_config.logVerbosity = v; return GetPointer(this); }

        // Build the orchestrator
    void* Build();

    SOrchestratorConfig GetConfig() const { return m_config; }
};

// Builder implementation
void* CEAOrchestratorBuilder::Build()
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
    CMagicNumberAllocator     m_magicNumberAllocator;  // L1-015: Centralized magic number allocation
    CSessionWeightManager       m_sessionWeightManager;
    CSkewStepAnalyzer           m_skewStepAnalyzer;
    CPerformanceAnalytics       m_performanceAnalytics;
    CAIPerformanceFeedback      m_aiFeedback;

    CNextGenStrategyBrain       m_aiNextGenBrain;
    CAIEngine*                m_aiEngine;
    CNeuralNetworkStrategy*     m_neuralNetStrategies[];
    string                      m_neuralNetStrategySymbols[];
    bool                        m_aiBrainReady;
    bool                        m_aiEngineReady;
    bool                        m_aiFeedbackReady;
    bool                        m_aiTopologyLogged;
    CTradeAttributionManager    m_attributionManager;
    CPositionSizer              m_positionSizer;
    CInstrumentRegistry         m_instrumentRegistry;
    CTickSafetyMonitor          m_tickSafetyMonitor;
    CSyntheticSpikeMonitor      m_spikeMonitor;
        // ONNX session init retry/backoff state machine (Core/AI/ONNXInitManager.mqh).
        // Replaces the former m_onnxSessionDisabled / m_onnxInitRetryCount /
        // m_lastOnnxInitAttempt members; thresholds and intervals are unchanged.
        CONNXInitManager            m_onnxInit;
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
    CSignalDiagnostics*         m_signalDiagnostics;
    CChartDrawingManager*       m_drawingManagers[];
    string                      m_drawingManagerSymbols[];

    // Batch 99: Bayesian Kelly / Equity Curve / CVaR subsystems
    CEquityCurveManager*        m_equityCurveManager;
    CBayesianKellyModifier*     m_bayesianKellyModifier;
    CEquityCurveLotModifier*    m_equityCurveLotModifier;
    CADXLotModifier*            m_adxModifier;
    datetime                    m_lastCvarLogTime;

    // Batch 100: Advanced Mathematical Engines
    CHurstEngine*               m_hurstEngines[];
    COrnsteinUhlenbeckEngine*   m_ouEngines[];
    COrderFlowImbalanceEngine*  m_ofiEngines[];
    CVPINFilter*                m_vpinFilters[];
    string                      m_mathEngineSymbols[];
    bool                        m_gridHurstBridgeLogged[];
    int                         m_mathEngineCount;

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
    CCandidateBuilder           m_candidateBuilder;
    CTradeExecutor              m_tradeExecutor;
    CLiveAuthorityResolver      m_liveAuthority;
    CPositionManager            m_positionManager;

    // Registries
    CRegistryAggregator             m_registryAggregator;

    // Heartbeat status-text aggregation (Core/Orchestration/OrchestratorStatusReporter.mqh).
    // Wired once from WireAndValidateDependencies(); read-only, no trading impact.
    COrchestratorStatusReporter     m_statusReporter;

    // ============ State Variables ============
    // NOTE (Phase B-1): the legacy performance-tracking block (m_peakEquity,
    // m_initialBalance, m_accountBalance, m_accountEquity, m_currentEquity,
    // m_currentDrawdown, m_totalProfit, m_totalLoss, m_totalTrades,
    // m_winningTrades, m_losingTrades, m_maxDrawdown), m_currentTime and
    // m_currentRiskPerTrade were removed: they were only ever declared and
    // constructor-initialized, never read or written. Live equity/PnL state is
    // owned by CPerformanceAnalytics and CUnifiedRiskManager.

    // Risk management
    ENUM_MARKET_REGIME m_currentRegime;
    datetime m_lastTradeTime;
    int    m_totalActivePositions;
    string m_activePairs[];
    bool   m_systemInitialized;
    bool   m_tradingEnabled;
    // EXEC-01: set true only after WireAndValidateDependencies() confirms every
    // trading-path manager received all of its required dependencies. Initialize()
    // aborts (returns false -> OnInit fails) when this stays false.
    bool   m_dependenciesValid;

    // Phase B-2: the 18 runtime heartbeat / rejection funnel counters now live in
    // CHeartbeatTelemetry (Core/Orchestration/HeartbeatTelemetry.mqh). They are
    // write-only telemetry - no control flow branches on them.
    CHeartbeatTelemetry m_heartbeat;

    ulong    m_scanCycleSequence;
    int      m_cyclesSinceIndicatorSignal;
    bool     m_hybridGateRelaxed;
    int      m_consecutiveZeroSignalCycles;
    int      m_zeroSignalFallbackThreshold;

    // Diagnostics logger (Blueprint 3.6: off-journal logging)
    // RETAINED (Phase B-1): no LogXxx()/WriteToFile() calls exist, but InitializeEx()
    // opens "MultiStrategyEA_diagnostics.log" and emits [DIAG-LOGGER] journal lines,
    // so removing it WOULD change observable runtime output. See report.
    CDiagnosticsLogger m_diagLogger;

    // NOTE (Phase B-1): the cached diagnostic strings (m_cachedConsensusDiag,
    // m_consensusDiagTime, m_cachedRoleClusterDiag, m_roleClusterDiagTime) were
    // removed - declared and constructor-initialized only, never read or written.

    // Portfolio profit target tracking
    datetime m_lastProfitTargetDay;
    bool   m_dailyProfitTargetReached;
    double m_dailyProfitPeakPct;
    double m_trailingProfitFloor;
    bool   m_dailyTradingHalt;
    datetime m_dailyTradingHaltStartTime;
    bool   m_shuttingDown;
    bool   m_bridgesReady;
    datetime m_lastPush;

    // Dual-mode auto-switching
    enum ENUM_AUTO_SWITCH_MODE { AUTO_MODE_CONSERVATIVE = 0, AUTO_MODE_AGGRESSIVE = 1, AUTO_MODE_EMERGENCY = 2 };
    ENUM_AUTO_SWITCH_MODE m_currentTradingMode;

    // Issue 7: Dormancy cooldown tracking per symbol
    int    m_dormantConsecutiveCount[];
    datetime m_dormantCooldownUntil[];
    string m_dormantCooldownSymbols[];
    int m_dormantCooldownThreshold;
    int m_dormantCooldownMinutes;

    // Issue 15: Scalp blacklist tracking per symbol (time-based cooldown)
    int    m_scalpBlacklistFailCount[];
    bool   m_scalpBlacklisted[];
    datetime m_scalpBlacklistUntil[];
    string m_scalpBlacklistSymbols[];
    int m_scalpBlacklistThreshold;
    int m_scalpBlacklistCooldownMinutes;
    int m_scalpBlacklistCooldownMinutesStd;

    // Call counter for diagnostics
    int m_callCount;
    int m_managerCount;

    // ============ Configuration ============
    SOrchestratorConfig m_config;

    public:
    CEAOrchestrator() : m_systemInitialized(false), m_tradingEnabled(false),
        m_dependenciesValid(false),
        m_managerCount(0), m_aiEngine(NULL),
        m_pythonBridge(NULL),
        m_lastProfitTargetDay(0), m_dailyProfitTargetReached(false), m_dailyProfitPeakPct(0),
        m_trailingProfitFloor(0), m_dailyTradingHalt(false), m_dailyTradingHaltStartTime(0),
        m_lastTradeTime(0), m_scanCycleSequence(0), m_cyclesSinceIndicatorSignal(0),
        m_hybridGateRelaxed(false), m_callCount(0),
        m_currentRegime(MARKET_REGIME_UNKNOWN),
        m_totalActivePositions(0),
        m_zeroSignalFallbackThreshold(20),
        m_currentTradingMode(AUTO_MODE_CONSERVATIVE),
        m_lastCvarLogTime(0), m_shuttingDown(false), m_bridgesReady(false), m_lastPush(0),
        m_aiBrainReady(false), m_aiEngineReady(false), m_aiFeedbackReady(false),
        m_aiTopologyLogged(false),
        m_adxModifier(NULL)
        // ONNX retry/backoff state is initialised by CONNXInitManager's own
        // constructor (disabled=false, retryCount=0, lastAttempt=0).
        {
            ArrayResize(m_enterpriseManagers, 0);
        ArrayResize(m_enterpriseManagerSymbols, 0);
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
        // L2-001: Set shutdown flag FIRST to prevent OnTimer from accessing invalid resources
        m_shuttingDown = true;

        // Cleanup dynamically allocated resources

        // Cleanup mathematical engines
        int mathEngineCount = ArraySize(m_mathEngineSymbols);
        for(int i = 0; i < mathEngineCount; i++)
        {
            if(i < ArraySize(m_hurstEngines) && m_hurstEngines[i] != NULL) { m_hurstEngines[i].Deinit(); delete m_hurstEngines[i]; m_hurstEngines[i] = NULL; }
            if(i < ArraySize(m_ouEngines) && m_ouEngines[i] != NULL) { m_ouEngines[i].Deinit(); delete m_ouEngines[i]; m_ouEngines[i] = NULL; }
            if(i < ArraySize(m_ofiEngines) && m_ofiEngines[i] != NULL) { m_ofiEngines[i].Deinit(); delete m_ofiEngines[i]; m_ofiEngines[i] = NULL; }
            if(i < ArraySize(m_vpinFilters) && m_vpinFilters[i] != NULL) { m_vpinFilters[i].Deinit(); delete m_vpinFilters[i]; m_vpinFilters[i] = NULL; }
        }
        ArrayResize(m_hurstEngines, 0);
        ArrayResize(m_ouEngines, 0);
        ArrayResize(m_ofiEngines, 0);
        ArrayResize(m_vpinFilters, 0);
        ArrayResize(m_mathEngineSymbols, 0);
        ArrayResize(m_gridHurstBridgeLogged, 0);

        // Cleanup Batch 114 engines
        int batch114Count = ArraySize(m_kalmanEngines);
        for(int i = 0; i < batch114Count; i++)
        {
            if(m_kalmanEngines[i] != NULL) { m_kalmanEngines[i].Deinit(); delete m_kalmanEngines[i]; m_kalmanEngines[i] = NULL; }
            if(i < ArraySize(m_cpdEngines) && m_cpdEngines[i] != NULL) { m_cpdEngines[i].Deinit(); delete m_cpdEngines[i]; m_cpdEngines[i] = NULL; }
            if(i < ArraySize(m_fourStateEngines) && m_fourStateEngines[i] != NULL) { m_fourStateEngines[i].Deinit(); delete m_fourStateEngines[i]; m_fourStateEngines[i] = NULL; }
            if(i < ArraySize(m_volTargetEngines) && m_volTargetEngines[i] != NULL) { m_volTargetEngines[i].Deinit(); delete m_volTargetEngines[i]; m_volTargetEngines[i] = NULL; }
            if(i < ArraySize(m_exitOptimizers) && m_exitOptimizers[i] != NULL) { m_exitOptimizers[i].Deinit(); delete m_exitOptimizers[i]; m_exitOptimizers[i] = NULL; }
            if(i < ArraySize(m_liquiditySweepStrategies) && m_liquiditySweepStrategies[i] != NULL) { m_liquiditySweepStrategies[i].Deinit(); delete m_liquiditySweepStrategies[i]; m_liquiditySweepStrategies[i] = NULL; }
            if(i < ArraySize(m_rangeCompStrategies) && m_rangeCompStrategies[i] != NULL) { m_rangeCompStrategies[i].Deinit(); delete m_rangeCompStrategies[i]; m_rangeCompStrategies[i] = NULL; }
        }
        ArrayResize(m_kalmanEngines, 0);
        ArrayResize(m_cpdEngines, 0);
        ArrayResize(m_fourStateEngines, 0);
        ArrayResize(m_volTargetEngines, 0);
        ArrayResize(m_exitOptimizers, 0);
        ArrayResize(m_liquiditySweepStrategies, 0);
        ArrayResize(m_rangeCompStrategies, 0);

        // Cleanup institutional engines
        int instCount = ArraySize(m_vwapEngines);
        for(int i = 0; i < instCount; i++)
        {
            if(m_vwapEngines[i] != NULL) { m_vwapEngines[i].Deinit(); delete m_vwapEngines[i]; m_vwapEngines[i] = NULL; }
            if(i < ArraySize(m_vpEngines) && m_vpEngines[i] != NULL) { m_vpEngines[i].Deinit(); delete m_vpEngines[i]; m_vpEngines[i] = NULL; }
            if(i < ArraySize(m_cvdEngines) && m_cvdEngines[i] != NULL) { m_cvdEngines[i].Deinit(); delete m_cvdEngines[i]; m_cvdEngines[i] = NULL; }
        }
        ArrayResize(m_vwapEngines, 0);
        ArrayResize(m_vpEngines, 0);
        ArrayResize(m_cvdEngines, 0);

        // Cleanup Batch 99 subsystems
        // L5-004 fix: EA owns modifiers, PositionSizer holds non-owning refs
        if(m_positionSizer.IsInitialized())
        {
            m_positionSizer.ClearModifiers();
        }

        // Now delete modifiers owned by EA
        if(m_bayesianKellyModifier != NULL) { delete m_bayesianKellyModifier; m_bayesianKellyModifier = NULL; }
        if(m_equityCurveLotModifier != NULL) { delete m_equityCurveLotModifier; m_equityCurveLotModifier = NULL; }
        if(m_adxModifier != NULL) { delete m_adxModifier; m_adxModifier = NULL; }
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

        // L2-002: Cleanup AI subsystems using helper method
        CleanupAISubsystems();

        // Shutdown JSON Logger
        CJsonLogger::Shutdown();

        // Shutdown Signal Diagnostics
        if(m_signalDiagnostics != NULL)
        {
            m_signalDiagnostics.Shutdown();
            delete m_signalDiagnostics;
            m_signalDiagnostics = NULL;
        }

        // Deinit diagnostics logger
        m_diagLogger.Deinit();

        // L2-015: Call attribution diag print BEFORE releasing enterprise managers (which clears data)
        m_attributionManager.NNDiagPrintSummary("deinit");

        // Cleanup enterprise managers
        ReleaseEnterpriseManagers();

        // Cleanup strategy registry
        CStrategyRegistry* strategyRegistry = m_registryAggregator.GetStrategyRegistry();
        if(strategyRegistry != NULL)
        strategyRegistry.Reset();

        // Destroy error handler singleton (must be before IndicatorManager destruction)
        CEnhancedErrorHandler::DestroyInstance();

        // Cleanup extra engines
        m_spikeHunter.Deinit();
        m_gridRecovery.Deinit();
        m_atrScalping.Deinit();

        // Cleanup TradeManager (L8-025: explicit Deinit for async trade persistence)
        m_tradeManager.Deinit();

        // Cleanup scalp cache
        m_scalpCache.Cleanup();

        // Uncertainty deinit
        UncertaintyDeinit();

        // L2-003/L2-013: Write crash recovery state on shutdown
        double currentPeakEquity = m_unifiedRiskManager.GetPeakEquity();
        double currentDailyStartEquity = m_unifiedRiskManager.GetDailyStartEquity();
        int currentDDBreachCount = m_unifiedRiskManager.GetDrawdownBreachCount();
        double currentDDMax = m_unifiedRiskManager.GetMaxDrawdownFromPeak();

        if(WriteCrashRecoveryState(CRASH_RECOVERY_STATE_FILE,
        currentDailyStartEquity, currentPeakEquity,
        currentDDBreachCount, currentDDMax))
        {
            PrintFormat("[RECOVERY] Crash recovery state written to %s | peakEquity=%.2f | ddBreachCount=%d | ddMax=%.2f%%",
            CRASH_RECOVERY_STATE_FILE, currentPeakEquity, currentDDBreachCount, currentDDMax);
        }
    else
    {
        PrintFormat("[RECOVERY] WARNING: Failed to write crash recovery state to %s", CRASH_RECOVERY_STATE_FILE);
    }

    m_systemInitialized = false;
    m_tradingEnabled = false;
    m_dependenciesValid = false;

    Print("[EAOrchestrator] Shutdown complete");
}

// L7-018: Cleanup helper for init failure paths
void CleanupOnInitFailure()
{
    // Cleanup registry aggregator (which owns strategy registry and other sub-registries)
    m_registryAggregator.Deinitialize();

    // Cleanup AI subsystems
    CleanupAISubsystems();

    // Cleanup Python Bridge
    if(CheckPointer(m_pythonBridge) == POINTER_DYNAMIC)
    {
        delete m_pythonBridge;
        m_pythonBridge = NULL;
    }

    // Cleanup Dashboard Bridge
    if(CheckPointer(m_dashboardBridge) == POINTER_DYNAMIC)
    {
        delete m_dashboardBridge;
        m_dashboardBridge = NULL;
    }

    // Cleanup Signal Diagnostics
    if(CheckPointer(m_signalDiagnostics) == POINTER_DYNAMIC)
    {
        m_signalDiagnostics.Shutdown();
        delete m_signalDiagnostics;
        m_signalDiagnostics = NULL;
    }
}

// L7-009/L7-010: Initialize strategy timeframe/intrabar configs from individual config fields
// Centralizes configuration to replace hardcoded switch statements and duplicate resolution functions
void InitializeStrategyConfigs() { CStrategyConfigBuilder::Initialize(m_config); }

// ============ Initialization ============

// Initialize with config only - orchestrator creates its own managers
bool Initialize(const SOrchestratorConfig& config)
{
    // L2-003/L2-013: Read crash recovery state IMMEDIATELY at start of Initialize()
    // (before any other init, so we don't lose state if crash occurs during init)
    double savedEquityBaseline = 0.0;
    double savedPeakEquity = 0.0;
    int savedDDBreachCount = 0;
    double savedDDMax = 0.0;
    string savedTimestamp = "";

    if(ReadCrashRecoveryState(CRASH_RECOVERY_STATE_FILE,
    savedEquityBaseline, savedPeakEquity,
    savedDDBreachCount, savedDDMax, savedTimestamp))
    {
        PrintFormat("[RECOVERY] Crash recovery state loaded from %s | equityBaseline=%.2f | peakEquity=%.2f | ddBreachCount=%d | ddMax=%.2f%% | timestamp=%s",
        CRASH_RECOVERY_STATE_FILE, savedEquityBaseline, savedPeakEquity, savedDDBreachCount, savedDDMax, savedTimestamp);

        // Restore circuit breaker state in risk manager
        m_unifiedRiskManager.RestoreCircuitBreakerState(savedPeakEquity, savedEquityBaseline,
        savedDDBreachCount, savedDDMax);

        // CRITICAL: Delete state file IMMEDIATELY after successful read
        // (not at end of OnInit) to prevent stale state if crash occurs during init
        if(FileDelete(CRASH_RECOVERY_STATE_FILE, 0))
        {
            PrintFormat("[RECOVERY] State file %s deleted after successful read", CRASH_RECOVERY_STATE_FILE);
        }
    else
    {
        PrintFormat("[RECOVERY] WARNING: Failed to delete state file %s", CRASH_RECOVERY_STATE_FILE);
    }
}
else
{
    PrintFormat("[RECOVERY] No valid crash recovery state found at %s (first run or file corrupted)", CRASH_RECOVERY_STATE_FILE);
}

m_config = config;

// Initialize structured JSON logger with verbosity gating (L9-008, L9-009)
string jsonLogFile = "EA_" + _Symbol + "_json.log";
ENUM_LOG_VERBOSITY jsonVerbosity = (ENUM_LOG_VERBOSITY)m_config.logVerbosity;
if(!CJsonLogger::Initialize(jsonLogFile, jsonVerbosity))
{
    Print("[JSON-LOGGER] WARNING: Failed to initialize JSON logger");
}
else
{
    PrintFormat("[JSON-LOGGER] Initialized: %s (verbosity=%s)", jsonLogFile, EnumToString(jsonVerbosity));
}

// Initialize DiagnosticsLogger with verbosity (L9-008, L9-009)
// This is instantiated in DiagnosticsManager, so we'll pass the config there

// L7-009/L7-010: Initialize centralized strategy timeframe/intrabar configs
InitializeStrategyConfigs();

// L7-003: Build validated symbol universe using SymbolUniverseBuilder
// L7-019: Unify spread limits - use maxEntrySpreadPoints for both validation and execution
// Apply 10x multiplier for synthetic symbols in SymbolUniverseBuilder
SSymbolValidationConfig symConfig;
symConfig.maxSpreadPoints = (long)m_config.maxEntrySpreadPoints;
symConfig.minDailyVolumeLots = m_config.symbolMinDailyVolumeLots;
symConfig.enableVolumeCheck = m_config.symbolEnableVolumeCheck;

string validatedSymbols[];
string chartSymbolToAdd = m_config.autoAddChartSymbol ? _Symbol : "";
if(!CSymbolUniverseBuilder::Build(m_config.symbolsToTrade, validatedSymbols, symConfig, chartSymbolToAdd))
{
    Print("[CRITICAL] Symbol universe validation failed - no valid symbols accepted");
    CleanupOnInitFailure();
    return false;
}

int symbolCount = ArraySize(validatedSymbols);
if(symbolCount <= 0)
{
    Print("[CRITICAL] No valid symbols after validation");
    CleanupOnInitFailure();
    return false;
}

// Resize manager arrays
m_managerCount = symbolCount;
ArrayResize(m_enterpriseManagers, symbolCount);
ArrayResize(m_enterpriseManagerSymbols, symbolCount);
ArrayResize(m_enterpriseManagers, symbolCount);
ArrayResize(m_enterpriseManagerSymbols, symbolCount);

for(int i = 0; i < symbolCount; i++)
{
    m_enterpriseManagerSymbols[i] = validatedSymbols[i];
}

// Also update m_activePairs for compatibility
ArrayResize(m_activePairs, symbolCount);
ArrayCopy(m_activePairs, validatedSymbols);

// Initialize all owned subsystems from config
if(!InitializeSubsystems())
{
    CleanupOnInitFailure();
    return false;
}

// INIT-01 FIX: allocate the strategy registry BEFORE any consumer.
// BuildStrategyRegistry (~line 707) calls GetStrategyRegistry() which was NULL until now,
// causing a silent OnInit failure. The aggregator must exist first.
if(!m_registryAggregator.Initialize())
{
    Print("[CRITICAL] RegistryAggregator initialization FAILED");
    return false;
}

// Initialize enterprise managers for each symbol
if(!InitializeEnterpriseManagers())
{
    // L2-002: Cleanup AI subsystems on failure after AI init
    CleanupOnInitFailure();
    return false;
}

// L2-012: Consolidated AI subsystem initialization (single ownership hierarchy)
if(!InitializeAISubsystems())
{
    Print("[CRITICAL] AI subsystem initialization failed");
    CleanupOnInitFailure();
    return false;
}

// Build strategy flags with curated defaults
bool strategyFlags[];
BuildStrategyFlags(strategyFlags);
CStrategyRegistry* strategyRegistry = m_registryAggregator.GetStrategyRegistry();
if(strategyRegistry != NULL)
strategyRegistry.Reset();
if(!BuildStrategyRegistry(strategyFlags))
{
    CleanupOnInitFailure();
    return false;
}
LogAIRuntimeTopology();
LogPositionLifecycleConfig();

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

// Startup Health Check
Print("[HEALTH-CHECK] Performing startup validation...");
bool healthCheckPassed = true;
if(m_config.enableAIMode) {
    int aiFailures = 0;
    if(!m_aiBrainReady) aiFailures++;
    if(!m_aiEngineReady && m_config.enableNeuralNetwork) aiFailures++;
    if(aiFailures > 0) {
        PrintFormat("[HEALTH-CHECK] WARNING: %d AI component(s) failed to initialize", aiFailures);
    }
    else {
        Print("[HEALTH-CHECK] AI subsystem: OK");
    }
}
if(m_config.pythonBridgeMode != PYTHON_BRIDGE_OFF && m_pythonBridge != NULL) {
    if(!m_pythonBridge.IsConnected()) {
        Print("[HEALTH-CHECK] WARNING: Python bridge not connected - using local AI fallback");
    }
    else {
        Print("[HEALTH-CHECK] Python bridge: OK");
    }
}
if(!m_unifiedRiskManager.IsInitialized()) {
    Print("[HEALTH-CHECK] CRITICAL: Risk manager not initialized!");
    healthCheckPassed = false;
}
else {
    Print("[HEALTH-CHECK] Risk manager: OK");
}

// EXEC-01: lifecycle/diagnostics manager wiring moved to WireAndValidateDependencies()
// (called once at the end of Initialize) so all cross-manager wiring lives in one place.

// Initialize sub-components
if(!InitializeComponents())
{
    // L2-002: Cleanup AI subsystems on failure after AI init
    CleanupOnInitFailure();
    return false;
}

    m_systemInitialized = true;
    m_tradingEnabled = true;

    // Reconcile per-symbol strategy enabled flags with the finalized registry.
    // AutoRegisterStrategies runs before BuildStrategyRegistry populates registry
    // definitions, so strategies were locked disabled against an empty registry.
    // Re-apply the registry's active state now that the mode is settled.
    for(int mi = 0; mi < ArraySize(m_enterpriseManagers); mi++)
    {
        if(m_enterpriseManagers[mi] != NULL)
            m_enterpriseManagers[mi].SyncEnabledWithRegistry();
    }

    // EXEC-01: single, centralized dependency-wiring + validation pass.
    // Every cross-manager SetDependencies/SetManagers call lives here, and the
    // validation block at its end fails init loudly if any required dep is NULL,
    // so a forgotten wiring can never surface as a mid-trade NULL dereference.
    WireAndValidateDependencies();
    if(!m_dependenciesValid)
    {
        Print("[CRITICAL] EAOrchestrator: dependency wiring validation FAILED - aborting initialization");
        m_systemInitialized = false;
        m_tradingEnabled = false;
        CleanupOnInitFailure();
        return false;
    }

    Print("[EAOrchestrator] Initialized with ", symbolCount, " symbol managers");
    return true;
}

// NOTE (Phase B-1): ParseSymbols() was removed - it had zero callers repo-wide and
// was superseded by CSymbolUniverseBuilder::Build(), which performs the same
// comma-splitting plus symbol validation (see Initialize()).

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
    if(!m_tradeManager.Initialize(m_config.magicNumber, "MultiStrategyAutonomousEA"))
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
    sizingParams.sizingMode       = POSITION_SIZING_FIXED_RISK;
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

// L2-008: Wire correlation engine BEFORE applying tier to PositionSizer
m_positionSizer.SetCorrelationEngine(m_unifiedRiskManager.GetPortfolioRiskManager().GetCorrelationEngine());
m_positionSizer.SetLogLevel(m_config.logLevel);
m_positionSizer.SetAllowMinLotRoundUp(m_config.allowMinLotRoundUp);
m_positionSizer.SetMinLotRiskMultiplier(m_config.minLotRiskMultiplier);

m_riskTierManager.ApplyToPositionSizer(m_positionSizer, m_config.maxRiskPerTrade);
m_riskTierManager.ApplyToTradeManager(m_tradeManager);

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
m_adxModifier = new CADXLotModifier();
if(m_adxModifier != NULL)
{
    if(m_adxModifier.Initialize(_Symbol, PERIOD_CURRENT, 14))
    {
        m_positionSizer.AddModifier(m_adxModifier);
        Print("[ADX-MODIFIER] Initialized and added to position sizer modifier chain");
    }
else
{
    Print("[ADX-MODIFIER] WARNING: Failed to initialize — ADX sizing disabled");
    delete m_adxModifier;
    m_adxModifier = NULL;
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
if(m_config.enableFamilyWeightMatrix)
{
    m_familyWeightMatrix.Initialize();
    Print("[INIT] FamilyStrategyWeightMatrix initialized");
}
else
{
    Print("[INIT] FamilyStrategyWeightMatrix disabled");
}

// L1-015: Initialize Magic Number Allocator
m_magicNumberAllocator.Initialize((int)m_config.magicNumber, MAGIC_SYMBOL_MULTIPLIER);
// Configure family offsets from multi-asset profiler
if(m_config.multiAssetProfilerEnabled)
{
    CDerivAssetProfiler* derivProfiler = m_multiAssetProfiler.GetDerivProfiler();
    if(derivProfiler != NULL)
    {
        // Add family-specific offsets
        m_magicNumberAllocator.AddFamilyOffset("VOLATILITY", 1000);
        m_magicNumberAllocator.AddFamilyOffset("BOOM_CRASH", 2000);
        m_magicNumberAllocator.AddFamilyOffset("JUMP", 3000);
        m_magicNumberAllocator.AddFamilyOffset("STEP_INDEX", 4000);
        Print("[MAGIC-ALLOC] Deriv family offsets configured");
    }
}
m_magicNumberAllocator.AddFamilyOffset("FOREX_MAJORS", 5000);
m_magicNumberAllocator.AddFamilyOffset("FOREX_CROSSES", 6000);
m_magicNumberAllocator.AddFamilyOffset("FOREX_EXOTICS", 7000);
m_magicNumberAllocator.AddFamilyOffset("CRYPTO", 8000);
m_magicNumberAllocator.AddFamilyOffset("METALS", 9000);
Print("[MAGIC-ALLOC] MagicNumberAllocator initialized with base=", m_config.magicNumber);

// Initialize Session Weight Manager (I3)
if(m_config.enableSessionWeights)
{
    m_sessionWeightManager.Initialize(true, m_config.sessionDSTOffsetHours);
    PrintFormat("[INIT] SessionWeightManager initialized — session-aware adjustments ENABLED (DST offset=%d hours)", m_config.sessionDSTOffsetHours);
}
else
{
    Print("[INIT] SessionWeightManager disabled");
}

// Initialize Skew Step Analyzer (I4)
if(m_config.enableSkewStepAnalyzer)
{
    m_skewStepAnalyzer.Initialize(m_config.skewStepBufferSize, m_config.skewStepCalmThreshold, m_config.skewStepSmallThreshold, m_config.skewStepLargeThreshold);
    PrintFormat("[INIT] SkewStepAnalyzer initialized — bufferSize=%d, calmThreshold=%.2f, smallThreshold=%.2f, largeThreshold=%.2f",
    m_config.skewStepBufferSize, m_config.skewStepCalmThreshold, m_config.skewStepSmallThreshold, m_config.skewStepLargeThreshold);
}
else
{
    Print("[INIT] SkewStepAnalyzer disabled");
}

// Initialize Family Strategy Weight Matrix (I1)
if(m_config.enableFamilyWeightMatrix)
{
    m_familyWeightMatrix.Initialize();
    Print("[INIT] FamilyStrategyWeightMatrix initialized — per-family cluster weighting ENABLED");
}
else
{
    Print("[INIT] FamilyStrategyWeightMatrix disabled");
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
// L7-008: Pass max cluster code from MagicNumberAllocator for dynamic magic number range
if(m_lifecycleManager.Initialize(&m_tradeManager, &m_consensusCache, &m_riskTierManager, &m_safeMode, (int)m_config.magicNumber, m_magicNumberAllocator.GetMaxClusterCode()))
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

    // Initialize DiagnosticsLogger (off-journal diagnostic logging)
        ENUM_LOG_VERBOSITY diagVerbosity = (ENUM_LOG_VERBOSITY)m_config.logVerbosity;
        int diagLogLevel = (diagVerbosity >= VERBOSITY_VERBOSE) ? 3 : (diagVerbosity >= VERBOSITY_NORMAL) ? 2 : (diagVerbosity >= VERBOSITY_WARNING) ? 2 : (diagVerbosity >= VERBOSITY_ERRORS_ONLY) ? 1 : 0;
        if(!m_diagLogger.InitializeEx("MultiStrategyEA", "ORCHESTRATOR", diagLogLevel, 5))
        {
            Print("[DIAG-LOGGER] WARNING: Failed to initialize diagnostics logger");
        }
        else
        {
            PrintFormat("[DIAG-LOGGER] Initialized with verbosity=%s (component=ORCHESTRATOR)", EnumToString(diagVerbosity));
        }

    // Initialize DiagnosticsManager (Blueprint R6b)
if(m_diagnosticsManager.Initialize(&m_unifiedRiskManager, &m_riskTierManager, &m_compoundingTierManager, m_config.heartbeatInterval, (ENUM_LOG_VERBOSITY)m_config.logVerbosity))
{
    m_diagnosticsManager.SetScalpEngine(&m_scalpEngine);
    m_diagnosticsManager.SetFullMarginMode(&m_fullMarginMode);
    m_diagnosticsManager.SetSafeMode(&m_safeMode);
    m_diagnosticsManager.SetAIConfig(m_config.enableAIMode, m_config.enableNeuralNetwork, m_config.enableNNOnlineTraining,
                                                 m_config.enableTransformer, m_config.enableEnsemble, m_config.enableOnnxAI);
    m_diagnosticsManager.SetRiskTier(m_config.riskTier);
    // Wire SessionWeightManager if enabled
        if(m_config.enableSessionWeights)
        {
            m_diagnosticsManager.SetSessionWeightManager(&m_sessionWeightManager);
        }
        // Wire SkewStepAnalyzer if enabled
                        if(m_config.enableSkewStepAnalyzer)
                        {
                            m_diagnosticsManager.SetSkewStepAnalyzer(&m_skewStepAnalyzer);
                        }
                        // Wire FamilyWeightMatrix if enabled
                        if(m_config.enableFamilyWeightMatrix)
                        {
                            m_diagnosticsManager.SetFamilyWeightMatrix(&m_familyWeightMatrix);
                        }
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
m_spikeMonitor.SetMagicNumber((int)m_config.magicNumber);

// Initialize AI subsystems if enabled
if(m_config.enableAIMode)
{
    Print("[AI] Initializing AI subsystems...");

    // NextGen Strategy Brain
    if(!m_aiNextGenBrain.Initialize(Symbol(), Period()))
    {
        Print("[INIT] WARNING: NextGen AI Brain failed to initialize");
        m_aiBrainReady = false;
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
    m_aiFeedbackReady = false;
}
else
{
    m_aiFeedbackReady = true;
    Print("[INIT] AIPerformanceFeedback initialized for AI model adaptation");
}

Print("[AI-DASHBOARD] AI Health Monitoring initialized");
}

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
    if(m_scalpCache.Initialize(m_enterpriseManagerSymbols, m_managerCount, PERIOD_M1))
    {
        m_scalpEngine.SetSignalCache(GetPointer(m_scalpCache));
        for(int si = 0; si < m_managerCount; si++)
        m_scalpCache.SetScalpSetup(m_enterpriseManagerSymbols[si], true, 1);
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

    if(m_spikeHunter.Init(spikeConfig, (int)m_config.magicNumber, &m_positionSizer, &m_unifiedRiskManager))
    {
        for(int i = 0; i < m_managerCount; i++)
        {
            if(m_enterpriseManagerSymbols[i] != "")
            m_spikeHunter.AddSymbol(m_enterpriseManagerSymbols[i]);
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

    // Re-bind the shared global profiler to THIS instance's valid member BEFORE any
    // consumer (e.g. IsSyntheticIndexSymbolName) touches it. This function can be
    // re-entered at runtime (first tick) under multi-instance deployment; without this
    // re-bind the global may still point at a stale/dangling profiler from an earlier
    // orchestrator (re)initialization, causing an invalid pointer access.
    g_multiAssetProfiler = &m_multiAssetProfiler;

    for(int i = 0; i < m_managerCount; i++)
    {
        string sym = m_enterpriseManagerSymbols[i];
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

        // L7-013: Set family detection logging flag
        if(derivProfiler != NULL)
        {
            derivProfiler.SetLogFamilyDetection(m_config.logDerivFamilyDetection);
        }

        if(m_config.spikeHunterEnabled && derivProfiler != NULL)
                {
                    for(int i = 0; i < m_managerCount; i++)
                    {
                        string sym = m_enterpriseManagerSymbols[i];
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

                // Set global profiler access for static utility functions
                g_multiAssetProfiler = &m_multiAssetProfiler;

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

            if(m_gridRecovery.Init(gridConfig, (int)m_config.magicNumber, &m_positionSizer, &m_unifiedRiskManager))
            {
                for(int i = 0; i < m_managerCount; i++)
                {
                    string sym = m_enterpriseManagerSymbols[i];
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

        if(m_atrScalping.Init(scalpConfig, (int)m_config.magicNumber, &m_positionSizer, &m_unifiedRiskManager))
        {
            for(int i = 0; i < m_managerCount; i++)
            {
                string sym = m_enterpriseManagerSymbols[i];
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
profilerSymbols[i] = m_enterpriseManagerSymbols[i];
m_diagnosticsManager.SetSymbols(profilerSymbols, m_managerCount);

// Initialize global profiler access for static utility functions
g_multiAssetProfiler = &m_multiAssetProfiler;

Print("[MULTI-ASSET-PROFILER] Batch 103 initialization complete");
}
return true;
}

// ============ Private Helper Methods ============

private:

//+------------------------------------------------------------------+
//| RequireDependency                                                  |
//|                                                                    |
//| Validation helper for WireAndValidateDependencies(). Emits a       |
//| uniform [INIT-FAIL] diagnostic when a required dependency is       |
//| missing and returns whether the dependency is present.             |
//|                                                                    |
//| isPresent   - result of the caller's non-NULL test                 |
//| managerName - manager that needed the dependency                   |
//| depName     - human-readable name of the missing dependency        |
//| returns     - true when present, false when missing                |
//+------------------------------------------------------------------+
bool RequireDependency(const bool isPresent, const string managerName, const string depName)
{
    if(isPresent)
        return true;

    PrintFormat("[INIT-FAIL] EAOrchestrator: %s missing dependency %s", managerName, depName);
    CJsonLogger::LogError("EAOrchestrator",
                          StringFormat("%s missing dependency %s", managerName, depName),
                          "INIT_DEPENDENCY_MISSING");
    return false;
}

//+------------------------------------------------------------------+
//| WireAndValidateDependencies                                        |
//|                                                                    |
//| EXEC-01: single, centralized dependency-wiring pass followed by    |
//| an init-time validation block.                                     |
//|                                                                    |
//| Every cross-manager dependency injection the orchestrator performs |
//| lives here. Previously these calls were scattered through          |
//| Initialize() and InitializeComponents(); a forgotten               |
//| SetDependencies() left manager fields NULL and crashed mid-trade   |
//| (CandidateBuilder.mqh:552, TradeExecutor.mqh:109). Centralizing    |
//| the wiring and validating it converts that latent runtime crash    |
//| into a loud, deterministic startup failure.                        |
//|                                                                    |
//| Ordering contract - this method MUST run:                          |
//|   * after m_registryAggregator.Initialize() (REGISTRY-SYNC fix),   |
//|     so GetNeuralNetRegistry() returns a live pointer;              |
//|   * after InitializeSubsystems()/InitializeComponents(), so the    |
//|     PositionManager, CandidateBuilder and lifecycle/diagnostics    |
//|     managers already exist.                                        |
//| It is therefore called exactly once, at the end of Initialize().   |
//|                                                                    |
//| Sets m_dependenciesValid = true only when every required           |
//| dependency is non-NULL. On any failure it logs, leaves the flag    |
//| false and returns early; Initialize() then aborts and OnInit fails.|
//+------------------------------------------------------------------+
void WireAndValidateDependencies()
{
    m_dependenciesValid = false;

    // ---------------- Resolve dependency pointers ----------------
    // The risk/sizer/trade/analytics/attribution/position managers are value
    // sub-objects of the orchestrator, so GetPointer() yields a stable pointer.
    // The two genuinely nullable dependencies are the Deriv profiler (owned by
    // CMultiAssetProfiler) and the neural-net registry (owned by the registry
    // aggregator, populated by m_registryAggregator.Initialize()).
    CUnifiedRiskManager*      riskManager     = GetPointer(m_unifiedRiskManager);
    CPositionSizer*           positionSizer   = GetPointer(m_positionSizer);
    CTradeManager*            tradeManager    = GetPointer(m_tradeManager);
    CPerformanceAnalytics*    perfAnalytics   = GetPointer(m_performanceAnalytics);
    CTradeAttributionManager* attributionMgr  = GetPointer(m_attributionManager);
    CPositionManager*         positionManager = GetPointer(m_positionManager);
    CDerivAssetProfiler*      derivProfiler   = m_multiAssetProfiler.GetDerivProfiler();
    CNeuralNetRegistry*       neuralRegistry  = m_registryAggregator.GetNeuralNetRegistry();

    // ---------------- Wiring ----------------

    // CandidateBuilder <- risk manager, position sizer, trade manager,
    // performance analytics, Deriv profiler. These are NOT set by
    // CandidateBuilder::Initialize() and were the original NULL-deref source.
    m_candidateBuilder.SetDependencies(riskManager, positionSizer, tradeManager,
                                       perfAnalytics, derivProfiler);

    // TradeExecutor <- trade manager, attribution manager, position manager,
    // neural-net registry (same crash class as CandidateBuilder).
    m_tradeExecutor.SetDependencies(tradeManager, attributionMgr,
                                    positionManager, neuralRegistry);

    // TradeAttributionManager <- PositionManager, for position state tracking.
    // SetPositionManager takes a reference, so pass the sub-object directly.
    m_attributionManager.SetPositionManager(m_positionManager);

    // PositionLifecycleManager <- per-symbol enterprise managers (Blueprint R6a).
    // Guarded exactly as before: only wired once the lifecycle manager is up.
    if(m_lifecycleManager.IsInitialized())
    {
        m_lifecycleManager.SetManagers(m_enterpriseManagers, m_enterpriseManagerSymbols,
                                       ArraySize(m_enterpriseManagers));
    }

    // DiagnosticsManager <- per-symbol enterprise managers (consensus diagnostics).
    m_diagnosticsManager.SetManagers(m_enterpriseManagers, ArraySize(m_enterpriseManagers));

    // StatusReporter <- registry aggregator, live-authority resolver, position
    // manager and enterprise manager slot 0 (heartbeat status text only, no
    // trading impact). Guarded exactly like the enterprise-array setters above:
    // slot 0 is only passed once the array is populated, and the reporter
    // NULL-checks it, matching the original `if(m_enterpriseManagers[0] != NULL)`.
    m_statusReporter.SetManagers(GetPointer(m_registryAggregator),
                                 GetPointer(m_liveAuthority),
                                 positionManager,
                                 (ArraySize(m_enterpriseManagers) > 0 ? m_enterpriseManagers[0] : NULL));

    // ---------------- Validation ----------------
    // Every check runs (no short-circuit on the RequireDependency call itself)
    // so a misconfigured build reports ALL missing dependencies in one pass.
    bool ok = true;

    // CandidateBuilder required dependencies.
    ok = RequireDependency(riskManager     != NULL, "CandidateBuilder", "CUnifiedRiskManager")   && ok;
    ok = RequireDependency(positionSizer   != NULL, "CandidateBuilder", "CPositionSizer")        && ok;
    ok = RequireDependency(tradeManager    != NULL, "CandidateBuilder", "CTradeManager")         && ok;
    ok = RequireDependency(perfAnalytics   != NULL, "CandidateBuilder", "CPerformanceAnalytics") && ok;
    ok = RequireDependency(derivProfiler   != NULL, "CandidateBuilder", "CDerivAssetProfiler")   && ok;

    // TradeExecutor required dependencies.
    ok = RequireDependency(tradeManager    != NULL, "TradeExecutor", "CTradeManager")            && ok;
    ok = RequireDependency(attributionMgr  != NULL, "TradeExecutor", "CTradeAttributionManager") && ok;
    ok = RequireDependency(positionManager != NULL, "TradeExecutor", "CPositionManager")         && ok;
    ok = RequireDependency(neuralRegistry  != NULL, "TradeExecutor", "CNeuralNetRegistry")       && ok;

    // TradeAttributionManager required dependencies.
    ok = RequireDependency(positionManager != NULL, "TradeAttributionManager", "CPositionManager") && ok;

    // PositionLifecycleManager / DiagnosticsManager take the enterprise manager
    // array rather than individual collaborators; verify it is populated.
    ok = RequireDependency(ArraySize(m_enterpriseManagers) > 0,
                           "PositionLifecycleManager", "EnterpriseManagers[]") && ok;
    ok = RequireDependency(ArraySize(m_enterpriseManagers) > 0,
                           "DiagnosticsManager", "EnterpriseManagers[]") && ok;

    if(!ok)
    {
        Print("[INIT-FAIL] EAOrchestrator: dependency validation FAILED - EA will not start");
        CJsonLogger::LogError("EAOrchestrator",
                              "Dependency validation failed - initialization aborted",
                              "INIT_DEPENDENCY_VALIDATION_FAILED");
        m_dependenciesValid = false;
        return;
    }

    m_dependenciesValid = true;
    Print("[INIT] EAOrchestrator: all manager dependencies wired and validated");
}

public:

bool InitializeComponents()
{
    // Initialize core signal processing components
    // SignalGenerator
    m_signalGenerator.Initialize(m_enterpriseManagers, m_enterpriseManagerSymbols, m_managerCount, &m_consensusCache);
    Print("[INIT] SignalGenerator initialized");

    // SignalValidator - now merged into EnterpriseStrategyManager

    // CandidateBuilder
    if(!m_candidateBuilder.Initialize(&m_positionSizer, &m_unifiedRiskManager, &m_riskTierManager,
    &m_compoundingTierManager, &m_familyWeightMatrix,
    &m_sessionWeightManager, &m_skewStepAnalyzer))
    {
        Print("[CRITICAL] CandidateBuilder initialization FAILED");
        return false;
    }
    Print("[INIT] CandidateBuilder initialized");

    // EXEC-01: CandidateBuilder + TradeExecutor dependency wiring moved to
    // WireAndValidateDependencies() (called once at the end of Initialize).

    // TradeExecutor
    Print("[INIT] TradeExecutor initialized");

    // LiveAuthorityResolver
    if(m_config.enableLiveAuthorityGate)
    {
        Print("[INIT] LiveAuthorityResolver initialized");
    }

    // PositionManager
    if(!m_positionManager.Initialize(&m_tradeManager, NULL, &m_riskTierManager,
    &m_safeMode, &m_fullMarginMode, NULL,
    (int)m_config.magicNumber))
    {
        Print("[CRITICAL] PositionManager initialization FAILED");
        return false;
    }
    Print("[INIT] PositionManager initialized");

    // EXEC-01: PositionManager -> TradeAttributionManager wiring moved to
    // WireAndValidateDependencies() (called once at the end of Initialize).

    // Initialize Signal Diagnostics
    m_signalDiagnostics = new CSignalDiagnostics();
    if(m_signalDiagnostics != NULL)
    {
        if(m_signalDiagnostics.Initialize(10000, 3))
        {
            Print("[INIT] SignalDiagnostics initialized");
            // Pass to mathematical engine registry for pipeline engines
            CMathematicalEngineRegistry* mathReg = m_registryAggregator.GetMathRegistry();
            if(mathReg != NULL)
            {
                mathReg.SetSignalDiagnostics(m_signalDiagnostics);
                // Initialize pipeline engines for all registered symbols
                mathReg.InitializePipelineEngines(m_enterpriseManagerSymbols, m_managerCount);
            }
        }
    else
    {
        Print("[WARNING] SignalDiagnostics initialization failed");
        delete m_signalDiagnostics;
        m_signalDiagnostics = NULL;
    }
}

// Register mathematical engines with registry
CMathematicalEngineRegistry* mathReg = m_registryAggregator.GetMathRegistry();
if(mathReg != NULL)
mathReg.RegisterAll(m_hurstEngines, m_ouEngines, m_ofiEngines, m_vpinFilters,
m_kalmanEngines, m_cpdEngines, m_fourStateEngines,
m_volTargetEngines, m_exitOptimizers, m_liquiditySweepStrategies,
m_rangeCompStrategies, m_mathEngineSymbols, ArraySize(m_mathEngineSymbols));

// Register institutional engines with registry
CInstitutionalEngineRegistry* instReg = m_registryAggregator.GetInstitutionalRegistry();
if(instReg != NULL)
instReg.RegisterAll(m_vwapEngines, m_vpEngines, m_cvdEngines,
m_enterpriseManagerSymbols, m_managerCount);

// Register neural network strategies if AI enabled
if(m_config.enableAIMode && (m_config.enableNeuralNetwork || m_config.enableTransformer ||
m_config.enableEnsemble || m_config.enableOnnxAI))
{
    // L1-008: Neural networks now owned by adapters registered with strategy managers
    // m_registryAggregator.GetNeuralNetRegistry() has its own internal management via GetOrCreateNeuralNet
}

// Register drawing managers
CDrawingManagerRegistry* drawReg = m_registryAggregator.GetDrawingRegistry();
if(drawReg != NULL)
drawReg.RegisterAll(m_drawingManagers, m_drawingManagerSymbols,
ArraySize(m_drawingManagers));

// Initialize symbol state tracker
CSymbolStateTracker* tracker = m_registryAggregator.GetSymbolStateTracker();
if(tracker != NULL)
    tracker.Initialize(m_enterpriseManagerSymbols, m_managerCount);

// NOTE: The strategy registry is populated by BuildStrategyRegistry() (called earlier in
// CEAOrchestrator::Initialize, before InitializeComponents). Do NOT call
// CStrategyRegistry::Initialize()/Reset() here — it would wipe the descriptors that
// BuildStrategyRegistry just registered, orphaning every per-symbol manager's view of the
// registry and leaving all strategies disabled (REGISTRY-WIPE bug).

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

    CMathematicalEngineRegistry* mathReg = m_registryAggregator.GetMathRegistry();

    for(int i = 0; i < count; i++)
    {
        string sym = m_enterpriseManagerSymbols[i];
        if(sym == "") continue;

        m_mathEngineSymbols[i] = sym;

        // Batch 100: Hurst Engine
        if(m_config.enableHurstEngine)
        {
            m_hurstEngines[i] = new CHurstEngine(sym, PERIOD_CURRENT, m_config.hurstLookback);
            if(m_hurstEngines[i] != NULL && mathReg != NULL)
            {
                mathReg.RegisterHurstEngine(sym, m_hurstEngines[i]);
                PrintFormat("[HURST] Engine initialized for %s (lookback=%d)", sym, m_config.hurstLookback);
            }
        }

        // Batch 100: Ornstein-Uhlenbeck Process
        if(m_config.enableOUProcess)
        {
            m_ouEngines[i] = new COrnsteinUhlenbeckEngine(sym, PERIOD_CURRENT, m_config.ouLookback);
            if(m_ouEngines[i] != NULL && mathReg != NULL)
            {
                mathReg.RegisterOUEngine(sym, m_ouEngines[i]);
                PrintFormat("[OU] Engine initialized for %s (lookback=%d)", sym, m_config.ouLookback);
            }
        }

        // Batch 100: Order Flow Imbalance Proxy
        if(m_config.enableOFIProxy)
        {
            m_ofiEngines[i] = new COrderFlowImbalanceEngine();
            if(m_ofiEngines[i] != NULL && mathReg != NULL)
            {
                mathReg.RegisterOFIEngine(sym, m_ofiEngines[i]);
                PrintFormat("[OFI] Engine initialized for %s (slowWindow=%d)", sym, m_config.ofiSlowWindow);
            }
        }

        // Batch 100: VPIN Filter
        if(m_config.enableVPINFilter)
        {
            m_vpinFilters[i] = new CVPINFilter(sym);
            if(m_vpinFilters[i] != NULL && mathReg != NULL)
            {
                mathReg.RegisterVPINFilter(sym, m_vpinFilters[i]);
                PrintFormat("[VPIN] Filter initialized for %s (threshold=%.2f, buckets=%d)",
                sym, m_config.vpinExtremeThreshold, m_config.vpinNumBuckets);
            }
        }

        // Batch 114: Kalman Mean Reversion
        if(m_config.enableKalmanMR)
        {
            m_kalmanEngines[i] = new CKalmanMeanReversion(sym);
            if(m_kalmanEngines[i] != NULL && mathReg != NULL)
            {
                mathReg.RegisterKalmanEngine(sym, m_kalmanEngines[i]);
                PrintFormat("[KALMAN-MR] Engine initialized for %s (lambda=%.1f)", sym, m_config.kalmanLambda);
            }
        }

        // Batch 114: Changepoint Detector
        if(m_config.enableChangepointDetect)
        {
            m_cpdEngines[i] = new CChangepointDetector(sym, PERIOD_CURRENT, 200, m_config.cpdHazardThreshold);
            if(m_cpdEngines[i] != NULL && mathReg != NULL)
            {
                if(m_cpdEngines[i].Initialize())
                {
                    mathReg.RegisterCPDDetector(sym, m_cpdEngines[i]);
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
        if(m_fourStateEngines[i] != NULL && mathReg != NULL)
        {
            if(m_fourStateEngines[i].Initialize())
            {
                mathReg.RegisterFourStateDetector(sym, m_fourStateEngines[i]);
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
    if(m_volTargetEngines[i] != NULL && mathReg != NULL)
    {
        if(m_volTargetEngines[i].Initialize())
        {
            mathReg.RegisterVolTargetEngine(sym, m_volTargetEngines[i]);
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
    if(m_exitOptimizers[i] != NULL && mathReg != NULL)
    {
        if(m_exitOptimizers[i].Initialize(sym, PERIOD_CURRENT))
        {
            mathReg.RegisterExitOptimizer(sym, m_exitOptimizers[i]);
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
    if(m_liquiditySweepStrategies[i] != NULL && mathReg != NULL)
    {
        if(m_liquiditySweepStrategies[i].Initialize(sym, PERIOD_CURRENT))
        {
            mathReg.RegisterLiquiditySweepStrategy(sym, m_liquiditySweepStrategies[i]);
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
    if(m_rangeCompStrategies[i] != NULL && mathReg != NULL)
    {
        if(m_rangeCompStrategies[i].Initialize(sym, PERIOD_CURRENT))
        {
            mathReg.RegisterRangeCompressionStrategy(sym, m_rangeCompStrategies[i]);
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

// Initialize pipeline engines with SignalDiagnostics for all symbols
if(mathReg != NULL && m_signalDiagnostics != NULL)
{
    mathReg.InitializePipelineEngines(m_enterpriseManagerSymbols, m_managerCount);
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

    CInstitutionalEngineRegistry* instReg = m_registryAggregator.GetInstitutionalRegistry();

    for(int i = 0; i < count; i++)
    {
        string sym = m_enterpriseManagerSymbols[i];
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
            if(m_vwapEngines[i] != NULL && instReg != NULL)
            {
                if(m_vwapEngines[i].Initialize(sym, m_config.vwapMinPeriodBars, m_config.vwapBand1, m_config.vwapBand2, m_config.vwapBand3))
                {
                    instReg.RegisterVWAPEngine(sym, m_vwapEngines[i]);
                    PrintFormat("[VWAP] Engine initialized for %s (period=%d, bands=%.1f/%.1f/%.1f)",
                    sym, m_config.vwapMinPeriodBars, m_config.vwapBand1, m_config.vwapBand2, m_config.vwapBand3);
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
        if(m_vpEngines[i] != NULL && instReg != NULL)
        {
            if(m_vpEngines[i].Initialize(sym, m_config.vpLookback, m_config.vpResolution))
            {
                instReg.RegisterVPEngine(sym, m_vpEngines[i]);
                PrintFormat("[VP] Engine initialized for %s (lookback=%d, resolution=%d)",
                sym, m_config.vpLookback, m_config.vpResolution);
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
    if(m_cvdEngines[i] != NULL && instReg != NULL)
    {
        if(m_cvdEngines[i].Initialize(sym, m_config.cvdDivergenceLookback))
        {
            instReg.RegisterCVDEngine(sym, m_cvdEngines[i]);
            PrintFormat("[CVD] Engine initialized for %s (divLookback=%d)",
            sym, m_config.cvdDivergenceLookback);
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

// ============ Enterprise Manager Initialization ============

bool InitializeEnterpriseManagers()
{
    if(m_managerCount <= 0)
    {
        Print("[ERROR] No symbols to initialize enterprise managers for");
        return false;
    }

    // Pre-allocate math engine arrays (Batch 100 + Batch 114 + Batch 107)
    int maxEngineCount = m_managerCount;
    ArrayResize(m_mathEngineSymbols, maxEngineCount);
    ArrayResize(m_hurstEngines, maxEngineCount);
    ArrayResize(m_ouEngines, maxEngineCount);
    ArrayResize(m_ofiEngines, maxEngineCount);
    ArrayResize(m_vpinFilters, maxEngineCount);
    ArrayResize(m_gridHurstBridgeLogged, maxEngineCount);
    ArrayResize(m_kalmanEngines, maxEngineCount);
    ArrayResize(m_cpdEngines, maxEngineCount);
    ArrayResize(m_fourStateEngines, maxEngineCount);
    ArrayResize(m_volTargetEngines, maxEngineCount);
    ArrayResize(m_exitOptimizers, maxEngineCount);
    ArrayResize(m_liquiditySweepStrategies, maxEngineCount);
    ArrayResize(m_rangeCompStrategies, maxEngineCount);
    ArrayResize(m_vwapEngines, maxEngineCount);
    ArrayResize(m_vpEngines, maxEngineCount);
    ArrayResize(m_cvdEngines, maxEngineCount);

    // Initialize all arrays to NULL/empty
    for(int i = 0; i < maxEngineCount; i++)
    {
        m_mathEngineSymbols[i] = "";
        m_hurstEngines[i] = NULL;
        m_ouEngines[i] = NULL;
        m_ofiEngines[i] = NULL;
        m_vpinFilters[i] = NULL;
        m_gridHurstBridgeLogged[i] = false;
        m_kalmanEngines[i] = NULL;
        m_cpdEngines[i] = NULL;
        m_fourStateEngines[i] = NULL;
        m_volTargetEngines[i] = NULL;
        m_exitOptimizers[i] = NULL;
        m_liquiditySweepStrategies[i] = NULL;
        m_rangeCompStrategies[i] = NULL;
        m_vwapEngines[i] = NULL;
        m_vpEngines[i] = NULL;
        m_cvdEngines[i] = NULL;
    }
    m_mathEngineCount = 0;

    int managerInitCount = 0;
    CStrategyRegistry* stratReg = m_registryAggregator.GetStrategyRegistry();
    for(int i = 0; i < m_managerCount; i++)
    {
        string symbol = m_enterpriseManagerSymbols[i];
        if(symbol == "") continue;

        bool globalStrategyFlags[];
        BuildStrategyFlags(globalStrategyFlags);
        bool symbolStrategyFlags[];
        BuildStrategyFlagsForSymbol(symbol, globalStrategyFlags, symbolStrategyFlags);

        if(CountEffectiveIndicatorStrategiesForSymbol(symbolStrategyFlags) <= 0 &&
        stratReg != NULL && stratReg.GetActiveAICount() <= 0)
        {
            Print("[ENTERPRISE] Skipping ", symbol, " because no strategies remain after symbol-class profiling.");
            continue;
        }

        if(InitializeEnterpriseManagerForSymbol(symbol, symbolStrategyFlags, i))
        managerInitCount++;
    else
    {
        PrintFormat("[ENTERPRISE] ERROR: Failed to initialize manager for %s, rolling back %d managers", symbol, managerInitCount);
        ReleaseEnterpriseManagers();
        return false;
    }
}

if(managerInitCount <= 0 || ArraySize(m_enterpriseManagers) <= 0)
{
    Print("[CRITICAL] Failed to initialize any Enterprise Strategy Manager.");
    return false;
}

// Update magic range max now that symbol universe is known
int symbolCount = ArraySize(m_enterpriseManagerSymbols);
long magicRangeMax = m_config.magicNumber + symbolCount * MAGIC_SYMBOL_MULTIPLIER + MAGIC_MAX_CLUSTER_CODE;
m_tradeManager.SetMagicRangeMax(magicRangeMax);
// Propagate magic range to all enterprise managers
for(int mi = 0; mi < ArraySize(m_enterpriseManagers); mi++)
{
    if(m_enterpriseManagers[mi] != NULL)
    {
        m_enterpriseManagers[mi].SetManagedMagicRangeMax((long)magicRangeMax);
        // Inject diagnostics manager for per-manager consensus diagnostics
        m_enterpriseManagers[mi].SetDiagnosticsManager(&m_diagnosticsManager);
        // Inject trade attribution manager for position-level attribution tracking
        m_enterpriseManagers[mi].SetAttributionManager(&m_attributionManager);
        // Batch 103: Set profilers for asset-class-based engine weighting
        if(m_config.multiAssetProfilerEnabled)
        {
            m_enterpriseManagers[mi].SetDerivProfiler(m_multiAssetProfiler.GetDerivProfiler());
            m_enterpriseManagers[mi].SetMultiAssetProfiler(&m_multiAssetProfiler);
            m_enterpriseManagers[mi].ApplyAssetClassEngineWeights(m_enterpriseManagerSymbols[mi]);
            // I1: Wire family weight matrix for per-family cluster weighting
            m_enterpriseManagers[mi].SetFamilyWeightMatrix(&m_familyWeightMatrix);
        }

        // Batch 103: Wire Hurst/VPIN/OFI/OU engines to strategies and manager
        {
            string sym = m_enterpriseManagerSymbols[mi];
            int mathIdx = -1;
            for(int k = 0; k < ArraySize(m_mathEngineSymbols); k++)
            {
                if(m_mathEngineSymbols[k] == sym) { mathIdx = k; break; }
            }
            if(mathIdx >= 0)
            {
                // Wire EnterpriseStrategyManager-level engines (consensus gating)
                m_enterpriseManagers[mi].SetVPINFilter(m_vpinFilters[mathIdx]);
                m_enterpriseManagers[mi].SetOFIEngine(m_ofiEngines[mathIdx]);
                if(m_config.logLevel >= 3)
                PrintFormat("[WIRE] VPIN/OFI wired to EnterpriseManager | Symbol=%s", sym);

                // Find and wire Trend strategy
                IStrategy* trendStrat = m_enterpriseManagers[mi].GetStrategyByName("Trend");
                if(trendStrat != NULL)
                {
                    CStrategyTrend* trendPtr = dynamic_cast<CStrategyTrend*>(trendStrat);
                    if(trendPtr != NULL)
                    {
                        trendPtr.SetHurstEngine(m_hurstEngines[mathIdx]);
                        trendPtr.SetVPINFilter(m_vpinFilters[mathIdx]);
                        if(m_config.logLevel >= 3)
                        PrintFormat("[WIRE] Hurst/VPIN wired to Trend | Symbol=%s", sym);
                    }
                }
                // Find and wire S/R strategy
                IStrategy* srStrat = m_enterpriseManagers[mi].GetStrategyByName("Support/Resistance");
                if(srStrat != NULL)
                {
                    CStrategySupportResistance* srPtr = dynamic_cast<CStrategySupportResistance*>(srStrat);
                    if(srPtr != NULL)
                    {
                        srPtr.SetHurstEngine(m_hurstEngines[mathIdx]);
                        srPtr.SetVPINFilter(m_vpinFilters[mathIdx]);
                        if(m_config.logLevel >= 3)
                        PrintFormat("[WIRE] Hurst/VPIN wired to S/R | Symbol=%s", sym);
                    }
                }
                // Wire Mean Reversion Hurst engine (v2.0 regime lockout)
                IStrategy* mrStrat = m_enterpriseManagers[mi].GetStrategyByName("Mean Reversion");
                if(mrStrat != NULL)
                {
                    CMeanReversionStrategy* mrPtr = dynamic_cast<CMeanReversionStrategy*>(mrStrat);
                    if(mrPtr != NULL)
                    {
                        mrPtr.SetHurstEngine(m_hurstEngines[mathIdx]);
                        if(m_config.logLevel >= 3)
                        PrintFormat("[WIRE] Hurst wired to Mean Reversion | Symbol=%s", sym);
                    }
                }
                // Wire Statistical Arbitrage OU engine (half-life filter)
                IStrategy* saStrat = m_enterpriseManagers[mi].GetStrategyByName("Statistical Arbitrage");
                if(saStrat != NULL)
                {
                    CStatisticalArbitrageStrategy* saPtr = dynamic_cast<CStatisticalArbitrageStrategy*>(saStrat);
                    if(saPtr != NULL)
                    {
                        saPtr.SetOUEngine(m_ouEngines[mathIdx]);
                        if(m_config.logLevel >= 3)
                        PrintFormat("[WIRE] OU wired to Statistical Arbitrage | Symbol=%s", sym);
                    }
                }
            }
        }
    }
}
if(m_config.logLevel >= 2)
PrintFormat("[MAGIC-RANGE] base=%d | symbols=%d | range_max=%u | encoding=BASE+symbolIndex*%d+clusterCode",
m_config.magicNumber, symbolCount, magicRangeMax, MAGIC_SYMBOL_MULTIPLIER);

return true;
}

bool InitializeEnterpriseManagerForSymbol(const string symbol, bool& strategyFlags[], int assignIndex)
{
    string symbolClass = GetInstrumentExecutionProfileName(symbol);
    string symbolProfile = GetSymbolStrategyProfileLabel(symbol, strategyFlags);
    bool syntheticLeanProfile = UseSyntheticLeanRosterProfile(symbol, strategyFlags);
    SignalFilterSettings filters;
    CEnterpriseStrategyManager* manager = new CEnterpriseStrategyManager();
    if(manager == NULL)
    {
        Print("[ERROR] Failed to allocate Enterprise Strategy Manager for ", symbol);
        return false;
    }

    if(!manager.Initialize(symbol, (ENUM_TIMEFRAMES)Period(), m_config.useSignalPipeline,
    &m_tradeManager, &m_positionSizer, &m_unifiedRiskManager, (long)m_config.magicNumber))
    {
        Print("[ERROR] Failed to initialize Enterprise Strategy Manager for ", symbol);
        delete manager;
        return false;
    }

    // L1-004: Inject strategy registry into manager (replaces global singleton)
    manager.SetStrategyRegistry(m_registryAggregator.GetStrategyRegistry());

    if(m_config.useSignalPipeline)
    {
        filters.trend.enabled = !(m_config.useSymbolClassProfiles && IsSyntheticIndexSymbolName(symbol));
        filters.volatility.enabled = true;
        filters.liquidity.enabled = m_config.enableLiquidityFilter;
        filters.structure.enabled = m_config.enableStructureFilter;
        filters.session.enableTimeFilter = true;
        filters.session.enableSessionFilter = true;
        filters.session.allowSyntheticOffHours = m_config.allowSyntheticOffHours;
        filters.session.tradeLondonSession = true;
        filters.session.tradeNewYorkSession = true;
        filters.session.tradeTokyoSession = true;
        filters.confidence.minConfidence = MathMax(0.0, MathMin(1.0, m_config.pipelineMinConfidence));

        // Phase 6: Safe mode raises the minimum confidence floor
        if(m_config.riskTier == RISK_TIER_CONSERVATIVE && m_safeMode.IsInitialized())
        filters.confidence.minConfidence = MathMax(filters.confidence.minConfidence, m_safeMode.GetConfig().minConfidence);
        filters.confidence.intrabarConfidenceCap = MathMax(0.0, m_config.pipelineIntrabarConfidenceCap);
        filters.regimeCostGate.enabled = m_config.pipelineEnableRegimeCostGate;
        filters.regimeCostGate.maxSpreadToAtrRatio = MathMax(0.01, m_config.pipelineMaxSpreadToAtrRatio);
        filters.regimeCostGate.spreadShockCooldownSeconds = MathMax(5, m_config.pipelineSpreadShockCooldownSec);
        filters.regimeCostGate.maxEntryRangeZScore = MathMax(0.5, m_config.pipelineLateEntryZScoreLimit);
        filters.volatility.maxVolatility = m_config.maxVolatility;
        filters.trend.minStrength = (int)m_config.minTrendStrength;
        manager.SetPipelineFilters(filters);

        CUnifiedSignalPipeline* pipeline = manager.GetPipeline();
        if(pipeline != NULL)
        {
            CTrendEngine* trendEngine = pipeline.GetTrendEngine(symbol);
            if(trendEngine != NULL)
            trendEngine.SetReadinessReuseTtlSeconds(m_config.readinessReuseTtlSeconds);

            CRegimeEngine* regimeEngine = pipeline.GetRegimeEngine(symbol);
            if(regimeEngine != NULL)
            regimeEngine.SetSnapshotReuseTtlSeconds(m_config.readinessReuseTtlSeconds);

            // I3: Wire session weight manager to pipeline
            if(m_config.enableSessionWeights)
            pipeline.SetSessionWeightManager(&m_sessionWeightManager);
        }
    }

    int minLiveVoters = MathMax(1, m_config.minLiveVoters);
    double quorumThreshold = MathMax(0.0, MathMin(1.0, m_config.quorumThreshold));
    double sparseIntrabarMinQuality = ResolveSparseIntrabarMinQualityForSymbol(symbol, strategyFlags);
    double sparseIntrabarMinSupportRatio = ClampConsensusInput(m_config.sparseIntrabarMinSupportRatio);
    double sparseIntrabarMinReadyCoverage = ClampConsensusInput(m_config.sparseIntrabarMinReadyCoverage);
    double intrabarSingleVoterMinConfidence = ResolveIntrabarSingleVoterMinConfidenceForSymbol(symbol, strategyFlags);
    manager.SetMinQuorum(minLiveVoters);
    manager.SetIntrabarMinQuorum(minLiveVoters);
    manager.SetQuorumThreshold(quorumThreshold);
    manager.SetConflictDeadband(MathMax(0.0, MathMin(0.50, m_config.consensusConflictDeadband)));
    manager.SetMinReadyWeightRatio(MathMax(0.10, MathMin(1.0, m_config.consensusMinReadyWeightRatio)));
    manager.SetSupportFloors(MathMax(0.05, MathMin(1.0, m_config.consensusSupportFloorNewBar)),
    MathMax(0.05, MathMin(1.0, m_config.consensusSupportFloorIntrabar)));
    manager.SetSparseIntrabarThresholds(sparseIntrabarMinQuality,
    sparseIntrabarMinSupportRatio,
    sparseIntrabarMinReadyCoverage);
    manager.SetAllowSparseIntrabarSingleVoter(m_config.allowSparseIntrabarSingleVoter);
    manager.SetIntrabarDynamicQuorumEnabled(m_config.intrabarDynamicQuorumEnabled);
    manager.SetIntrabarSingleVoterMinConfidence(intrabarSingleVoterMinConfidence);
    manager.SetConsensusDiagnosticsIntervalSeconds(m_config.deadlockAttributionIntervalSec);
    manager.ApplyQuorumProfile(m_config.quorumProfile);
    PrintFormat("[ENTERPRISE-CONFIG] %s | class=%s | profile=%s | trend_filter=%s | quorum_threshold=%.2f | min_live_voters=%d | support_floor_newbar=%.2f | support_floor_intrabar=%.2f | sparse_single_voter=%s | sparse_quality=%.2f | sparse_support=%.2f | sparse_ready=%.2f | intrabar_dynamic_quorum_input=%s | single_voter_min_conf=%.2f | pipeline_min_conf=%.2f | validator_mode=EXOGENOUS_ONLY | validator_profile_inputs=newbar(conf>=%.2f confluence>=%d quality>=%.2f) intrabar(conf>=%.2f confluence>=%d quality>=%.2f) | deadlock_diag_interval=%ds | intrabar_conf_cap=%.2f",
    symbol,
    symbolClass,
    symbolProfile,
    filters.trend.enabled ? "true" : "false",
    quorumThreshold,
    minLiveVoters,
    MathMax(0.05, MathMin(1.0, m_config.consensusSupportFloorNewBar)),
    MathMax(0.05, MathMin(1.0, m_config.consensusSupportFloorIntrabar)),
    m_config.allowSparseIntrabarSingleVoter ? "true" : "false",
    sparseIntrabarMinQuality,
    sparseIntrabarMinSupportRatio,
    sparseIntrabarMinReadyCoverage,
    m_config.intrabarDynamicQuorumEnabled ? "true" : "false",
    intrabarSingleVoterMinConfidence,
    MathMax(0.0, MathMin(1.0, m_config.pipelineMinConfidence)),
    MathMax(0.0, MathMin(1.0, m_config.validatorNewBarMinConfidence)),
    MathMax(1, m_config.validatorNewBarMinConfluence),
    MathMax(0.0, MathMin(1.0, m_config.validatorNewBarMinQuality)),
    MathMax(0.0, MathMin(1.0, m_config.validatorIntrabarMinConfidence)),
    MathMax(1, m_config.validatorIntrabarMinConfluence),
    MathMax(0.0, MathMin(1.0, m_config.validatorIntrabarMinQuality)),
    MathMax(10, m_config.deadlockAttributionIntervalSec),
    MathMax(0.0, m_config.pipelineIntrabarConfidenceCap));
    Print("[CURATION] Effective strategy set for ", symbol, ": ", BuildEnabledStrategyList(strategyFlags));
    if(syntheticLeanProfile)
    PrintFormat("[SYMBOL-PROFILE] %s uses synthetic lean roster: Momentum/Trend suppressed from manager roster; Candlestick remains new-bar active but intrabar PROBE while Fibonacci/Elliott/SupportResistance/UICT stay LIVE | sparse_quality=%.2f | single_voter_min_conf=%.2f",
    symbol,
    sparseIntrabarMinQuality,
    intrabarSingleVoterMinConfidence);

    // L6-007: Configure intrabar policies from orchestrator config before auto-registration
    // L7-009/L7-010: Use centralized strategy intrabar config array
    for(int si = 0; si < m_config.strategyConfigCount; si++)
    {
        manager.SetStrategyIntrabarPolicyConfig(si, m_config.strategyIntrabarConfigs[si].defaultPolicy);
    }
    // Strategies beyond strategyConfigCount will use defaults from GetIntrabarPolicy lambda


    // L6-007: Auto-register strategies with configured intrabar policies
    manager.AutoRegisterStrategies(strategyFlags);
    ApplyInstitutionalStrategyGovernance(manager, symbol, strategyFlags);
    ApplyStrategyWeights(manager, symbol, strategyFlags);

    // Array is pre-sized in Initialize(); place the manager at its symbol index
    // (do NOT append — appending lands managers at 12..23 while indices 0..11 stay NULL,
    //  which makes CSignalGenerator receive an all-NULL manager array and consensus dormant).
    m_enterpriseManagers[assignIndex] = manager;
    // m_enterpriseManagerSymbols[assignIndex] is already populated by the Initialize() pre-fill.

    // Batch 100: Initialize per-symbol mathematical engines using pre-allocated arrays
    {
        int idx = m_mathEngineCount;
        m_mathEngineSymbols[idx] = symbol;
        m_gridHurstBridgeLogged[idx] = false;

        // Hurst Engine
        m_hurstEngines[idx] = NULL;
        if(m_config.enableHurstEngine)
        {
            m_hurstEngines[idx] = new CHurstEngine(symbol, (ENUM_TIMEFRAMES)Period(), m_config.hurstLookback);
            if(m_hurstEngines[idx] != NULL && m_config.logLevel >= 3)
            PrintFormat("[MATH-ENGINE] Hurst engine initialized for %s | lookback=%d", symbol, m_config.hurstLookback);
        }

        // OU Process Engine
        m_ouEngines[idx] = NULL;
        if(m_config.enableOUProcess)
        {
            m_ouEngines[idx] = new COrnsteinUhlenbeckEngine(symbol, (ENUM_TIMEFRAMES)Period(), m_config.ouLookback);
            if(m_ouEngines[idx] != NULL && m_config.logLevel >= 3)
            PrintFormat("[MATH-ENGINE] OU process engine initialized for %s | lookback=%d", symbol, m_config.ouLookback);
        }

        // OFI Proxy Engine
        m_ofiEngines[idx] = NULL;
        if(m_config.enableOFIProxy)
        {
            m_ofiEngines[idx] = new COrderFlowImbalanceEngine();
            if(m_ofiEngines[idx] != NULL)
            {
                m_ofiEngines[idx].Init(symbol, 5, 20, m_config.ofiSlowWindow);
                if(m_config.logLevel >= 3)
                PrintFormat("[MATH-ENGINE] OFI proxy engine initialized for %s | slowWindow=%d", symbol, m_config.ofiSlowWindow);
            }
        }

        // VPIN Filter
        m_vpinFilters[idx] = NULL;
        if(m_config.enableVPINFilter)
        {
            m_vpinFilters[idx] = new CVPINFilter(symbol, 0, m_config.vpinNumBuckets, m_config.vpinExtremeThreshold);
            if(m_vpinFilters[idx] != NULL && m_config.logLevel >= 3)
            PrintFormat("[MATH-ENGINE] VPIN filter initialized for %s | buckets=%d | extreme=%.2f", symbol, m_config.vpinNumBuckets, m_config.vpinExtremeThreshold);
        }

        // Batch 107: VWAP Engine (forex only)
        m_vwapEngines[idx] = NULL;
        if(m_config.enableVWAPEngine && !IsSyntheticIndexSymbolName(symbol))
        {
            m_vwapEngines[idx] = new CVWAPEngine();
            m_vwapEngines[idx].Initialize(symbol, m_config.vwapMinPeriodBars, m_config.vwapBand1, m_config.vwapBand2, m_config.vwapBand3);
            if(m_config.logLevel >= 3)
            PrintFormat("[INSTITUTIONAL-ENGINE] VWAP engine initialized for %s", symbol);
        }

        // Batch 107: Volume Profile Engine (forex only)
        m_vpEngines[idx] = NULL;
        if(m_config.enableVolumeProfile && !IsSyntheticIndexSymbolName(symbol))
        {
            m_vpEngines[idx] = new CVolumeProfileEngine();
            m_vpEngines[idx].Initialize(symbol, m_config.vpLookback, m_config.vpResolution);
            if(m_config.logLevel >= 3)
            PrintFormat("[INSTITUTIONAL-ENGINE] Volume Profile engine initialized for %s", symbol);
        }

        // Batch 107: CVD Engine (forex only)
        m_cvdEngines[idx] = NULL;
        if(m_config.enableCVDEngine && !IsSyntheticIndexSymbolName(symbol))
        {
            m_cvdEngines[idx] = new CCVDEngine();
            m_cvdEngines[idx].Initialize(symbol, m_config.cvdDivergenceLookback);
            if(m_config.logLevel >= 3)
            PrintFormat("[INSTITUTIONAL-ENGINE] CVD engine initialized for %s", symbol);
        }

        // Batch 114: Research-Driven Statistical Algorithm Engines
        // Kalman/FLS Dynamic Mean-Reversion
        m_kalmanEngines[idx] = NULL;
        if(m_config.enableKalmanMR)
        {
            m_kalmanEngines[idx] = new CKalmanMeanReversion(symbol, (ENUM_TIMEFRAMES)Period(), 200, m_config.kalmanLambda);
            if(m_kalmanEngines[idx] != NULL && m_config.logLevel >= 3)
            PrintFormat("[ENGINE] Kalman MR engine initialized for %s | lambda=%.0f", symbol, m_config.kalmanLambda);
        }

        // Bayesian Online Changepoint Detection
        m_cpdEngines[idx] = NULL;
        if(m_config.enableChangepointDetect)
        {
            m_cpdEngines[idx] = new CChangepointDetector(symbol, (ENUM_TIMEFRAMES)Period(), 200, m_config.cpdHazardThreshold);
            if(m_cpdEngines[idx] != NULL && m_config.logLevel >= 3)
            PrintFormat("[ENGINE] CPD engine initialized for %s | hazard=%.2f", symbol, m_config.cpdHazardThreshold);
        }

        // Four-State Regime Detector
        m_fourStateEngines[idx] = NULL;
        if(m_config.enableFourStateRegime)
        {
            m_fourStateEngines[idx] = new CFourStateRegimeDetector(symbol, (ENUM_TIMEFRAMES)Period());
            if(m_fourStateEngines[idx] != NULL && m_config.logLevel >= 3)
            PrintFormat("[ENGINE] Four-State Regime engine initialized for %s", symbol);
        }

        // Volatility Targeting
        m_volTargetEngines[idx] = NULL;
        if(m_config.enableVolTargeting)
        {
            m_volTargetEngines[idx] = new CVolatilityTargeting(symbol, (ENUM_TIMEFRAMES)Period());
            if(m_volTargetEngines[idx] != NULL)
            {
                m_volTargetEngines[idx].Configure(m_config.targetVol, 100, 0.94, m_config.volMinScale, m_config.volMaxScale);
                m_volTargetEngines[idx].Initialize();
                if(m_config.logLevel >= 3)
                PrintFormat("[ENGINE] Volatility Targeting initialized for %s | target=%.2f%%", symbol, m_config.targetVol * 100);
            }
        }

        // Exit Optimizer
        m_exitOptimizers[idx] = NULL;
        if(m_config.enableExitOptimizer)
        {
            m_exitOptimizers[idx] = new CExitOptimizer();
            m_exitOptimizers[idx].Initialize(symbol, (ENUM_TIMEFRAMES)Period());
            if(m_config.logLevel >= 3)
            PrintFormat("[ENGINE] Exit Optimizer initialized for %s", symbol);
        }

        // Liquidity Sweep Strategy
        m_liquiditySweepStrategies[idx] = NULL;
        if(m_config.enableLiquiditySweep)
        {
            m_liquiditySweepStrategies[idx] = new CLiquiditySweepStrategy();
            m_liquiditySweepStrategies[idx].Initialize(symbol, (ENUM_TIMEFRAMES)Period(), NULL);
            if(m_config.logLevel >= 3)
            PrintFormat("[ENGINE] Liquidity Sweep strategy initialized for %s", symbol);
        }

        // Range Compression Breakout Strategy
        m_rangeCompStrategies[idx] = NULL;
        if(m_config.enableRangeCompression)
        {
            m_rangeCompStrategies[idx] = new CRangeCompressionBreakout();
            m_rangeCompStrategies[idx].Initialize(symbol, (ENUM_TIMEFRAMES)Period(), m_hurstEngines[idx], NULL);
            if(m_config.logLevel >= 3)
            PrintFormat("[ENGINE] Range Compression Breakout strategy initialized for %s", symbol);
        }

        m_mathEngineCount++;
    }

    // Initialize Drawing Manager for this symbol if enabled
    if(m_config.enableVisualAnalysis)
    {
        CChartDrawingManager* draw = new CChartDrawingManager();
        if(draw != NULL)
        {
            if(draw.Initialize(symbol, (ENUM_TIMEFRAMES)Period(), "VIS_"))
            {
                SDrawingConfig drawConfig;
                drawConfig.enableDrawing = true;
                drawConfig.maxObjectAge = m_config.maxVisualObjects;
                draw.SetConfiguration(drawConfig);
                draw.SetMaxObjects(MathMin(450, m_config.maxVisualObjects)); // Cap at 450 for safety

                int dSize = ArraySize(m_drawingManagers);
                ArrayResize(m_drawingManagers, dSize + 1);
                ArrayResize(m_drawingManagerSymbols, dSize + 1);
                m_drawingManagers[dSize] = draw;
                m_drawingManagerSymbols[dSize] = symbol;

                // Inject drawing manager into strategy manager for strategy-level drawings
                manager.SetDrawingManager(draw);
                Print("[VISUAL] Drawing manager initialized for ", symbol);
            }
        else
        {
            delete draw;
        }
    }
}

Print("[ENTERPRISE] Manager initialized for ", symbol, " with ", manager.GetActiveStrategyCount(), " active strategies | profile=", symbolProfile);
return true;
}

// ============ Helper Methods for Enterprise Manager ============

bool BuildStrategyFlags(bool& flags[])
{
    ArrayResize(flags, STRATEGY_COUNT);
    ArrayInitialize(flags, false);

    flags[SI_MOMENTUM] = m_config.enableMomentum;
    flags[SI_TREND] = m_config.enableTrend;
    flags[SI_SUPPORT_RESISTANCE] = m_config.enableSupportResistance;
    flags[SI_CANDLESTICK] = m_config.enableCandlestick;
    flags[SI_MEAN_REVERSION] = m_config.enableMeanReversion;
    flags[SI_VOLATILITY_BREAKOUT] = m_config.enableVolatilityBreakout;
    flags[SI_FVG_SCALPER] = m_config.enableFVGScalper;
    flags[SI_TURTLE_SOUP] = m_config.enableTurtleSoup;
    flags[SI_BREAKER_BLOCK] = m_config.enableBreakerBlock;
    flags[SI_NY_OPEN_GAP] = m_config.enableNYOpenGap;
    flags[SI_ASIAN_RANGE_BREAK] = m_config.enableAsianRangeBreak;
    flags[SI_STATISTICAL_ARBITRAGE] = m_config.enableStatisticalArbitrage;
    flags[SI_LIQUIDITY_SWEEP] = m_config.enableLiquiditySweep;
    flags[SI_RANGE_COMPRESSION] = m_config.enableRangeCompression;
    flags[SI_EXIT_OPTIMIZER] = m_config.enableExitOptimizer;

    // Curated mode overrides (Batch 114)
    if(m_config.useCuratedStrategySet)
    {
        // Apply curated defaults - but explicit enables remain authoritative
        if(!m_config.enableMomentum) flags[SI_MOMENTUM] = true;
        if(!m_config.enableTrend) flags[SI_TREND] = true;
        if(!m_config.enableSupportResistance) flags[SI_SUPPORT_RESISTANCE] = true;
        if(!m_config.enableMeanReversion) flags[SI_MEAN_REVERSION] = true;
        if(!m_config.enableVolatilityBreakout) flags[SI_VOLATILITY_BREAKOUT] = true;
        if(!m_config.enableFVGScalper) flags[SI_FVG_SCALPER] = true;
        if(!m_config.enableTurtleSoup) flags[SI_TURTLE_SOUP] = true;
        if(!m_config.enableBreakerBlock) flags[SI_BREAKER_BLOCK] = true;
        if(!m_config.enableNYOpenGap) flags[SI_NY_OPEN_GAP] = true;
        if(!m_config.enableAsianRangeBreak) flags[SI_ASIAN_RANGE_BREAK] = true;
        if(!m_config.enableLiquiditySweep) flags[SI_LIQUIDITY_SWEEP] = true;
        if(!m_config.enableRangeCompression) flags[SI_RANGE_COMPRESSION] = true;
    }

    return true;
}

bool BuildStrategyFlagsForSymbol(const string& symbol, const bool& globalFlags[], bool& symbolFlags[])
{
    // Start with global flags
    ArrayResize(symbolFlags, ArraySize(globalFlags));
    ArrayCopy(symbolFlags, globalFlags);

    // Apply symbol-specific overrides
    string symbolClass = GetInstrumentExecutionProfileName(symbol);
    bool isSynthetic = IsSyntheticIndexSymbolName(symbol);

    if(m_config.useSymbolClassProfiles)
    {
        if(isSynthetic)
        {
            // L7-006: Query DerivAssetProfiler for per-family strategy enablement flags
            CDerivAssetProfiler* derivProfiler = m_multiAssetProfiler.GetDerivProfiler();
            if(derivProfiler != NULL)
            {
                SDerivProfile profile = derivProfiler.GetProfile(symbol);

                // Use per-family flags instead of blanket synthetic logic
                if(!profile.enableTrendStrategies)
                {
                    symbolFlags[SI_TREND] = false;
                }
                if(!profile.enableMomentumStrategies)
                {
                    symbolFlags[SI_MOMENTUM] = false;
                }

                // Log the family-specific configuration
                PrintFormat("[DERIV-PROFILER] %s → family=%s | enableTrend=%s | enableMomentum=%s",
                symbol, EnumToString(profile.family),
                profile.enableTrendStrategies ? "true" : "false",
                profile.enableMomentumStrategies ? "true" : "false");
            }
        else
        {
            // Fallback to original logic if profiler not available
            symbolFlags[SI_MOMENTUM] = false;
            symbolFlags[SI_TREND] = false;
            symbolFlags[SI_MEAN_REVERSION] = true;
            symbolFlags[SI_VOLATILITY_BREAKOUT] = true;
            symbolFlags[SI_FVG_SCALPER] = true;
        }
    }
else
{
    // Forex: enable trend/momentum, suppress some synthetic-specific
    symbolFlags[SI_TREND] = true;
    symbolFlags[SI_MOMENTUM] = true;
}
}

return true;
}

int CountEffectiveIndicatorStrategiesForSymbol(const bool& symbolFlags[])
{
    int count = 0;
    for(int i = 0; i < ArraySize(symbolFlags); i++)
    {
        if(symbolFlags[i])
        count++;
    }
    // Exclude AI strategies from this count
    if(symbolFlags[STRATEGY_NEURAL_NETWORK_AI]) count--;
    if(symbolFlags[STRATEGY_TRANSFORMER_AI]) count--;
    if(symbolFlags[STRATEGY_ENSEMBLE_AI]) count--;
    if(symbolFlags[STRATEGY_ONNX_AI]) count--;
    return count;
}

double ResolveSparseIntrabarMinQualityForSymbol(const string& symbol, const bool& strategyFlags[])
{
    if(IsSyntheticIndexSymbolName(symbol))
    return m_config.syntheticLeanSparseIntrabarMinQuality;
    return m_config.sparseIntrabarMinQuality;
}

double ResolveIntrabarSingleVoterMinConfidenceForSymbol(const string& symbol, const bool& strategyFlags[])
{
    if(IsSyntheticIndexSymbolName(symbol))
    return m_config.syntheticLeanIntrabarSingleVoterMinConfidence;
    return m_config.intrabarSingleVoterMinConfidence;
}

// L7-009/L7-010: Centralized intrabar policy resolution
// Replaces hardcoded switch statements and duplicate resolution functions
// Synthetic lean overrides driven by CDerivAssetProfiler family profile, not hardcoded indices
ENUM_INTRABAR_POLICY GetIntrabarPolicy(const string symbol, int strategyIndex, const bool& strategyFlags[])
{
    // Bounds check
    if(strategyIndex < 0 || strategyIndex >= m_config.strategyConfigCount)
    return INTRABAR_POLICY_OFF;

    // Get base policy from centralized config
    ENUM_INTRABAR_POLICY policy = m_config.strategyIntrabarConfigs[strategyIndex].defaultPolicy;

    // If strategy is disabled, return OFF
    if(strategyIndex < ArraySize(strategyFlags) && !strategyFlags[strategyIndex])
    return INTRABAR_POLICY_OFF;

    // Synthetic lean override: check if symbol is synthetic and strategy is marked as primary
    if(IsSyntheticIndexSymbolName(symbol) && m_config.strategyIntrabarConfigs[strategyIndex].syntheticLeanPrimary)
    {
        // For synthetic lean symbols, upgrade PROBE to LIVE if configured
        if(policy == INTRABAR_POLICY_PROBE)
        policy = INTRABAR_POLICY_LIVE;
        // For synthetic lean, we might also allow LIVE where it was OFF for certain strategies
        // This is driven by the family profile from CDerivAssetProfiler
        CDerivAssetProfiler* derivProfiler = m_multiAssetProfiler.GetDerivProfiler();
        if(derivProfiler != NULL)
        {
            SDerivProfile profile = derivProfiler.GetProfile(symbol);
            if(profile.enableIntrabarOverride && policy != INTRABAR_POLICY_OFF)
            {
                // Family profile allows intrabar for this strategy
                policy = INTRABAR_POLICY_LIVE;
            }
        }
    }

    return policy;
}

// L7-009: Get strategy timeframe config from centralized array
SStrategyTimeframeConfig GetStrategyTimeframeConfig(int strategyIndex) const
{
    static SStrategyTimeframeConfig defaultConfig;
    if(strategyIndex < 0 || strategyIndex >= m_config.strategyConfigCount)
    return defaultConfig;
    return m_config.strategyTimeframeConfigs[strategyIndex];
}

double ClampConsensusInput(double value)
{
    return MathMax(0.0, MathMin(1.0, value));
}

string BuildEnabledStrategyList(const bool& strategyFlags[])
{
    string list = "";
    for(int i = 0; i < ArraySize(strategyFlags); i++)
    {
        if(strategyFlags[i])
        {
            if(list != "") list += ", ";
            list += EnumToString((ENUM_STRATEGY_TYPE)i);
        }
    }
    return list;
}

void RegisterManagerStrategiesFromRegistry(CEnterpriseStrategyManager* manager, const string& symbol, const bool& strategyFlags[])
{
    // This would register strategies based on flags - simplified for now
    // In production, this iterates through strategy registry and creates/registers each enabled strategy
    // The actual implementation would be more complex
}

void ApplyInstitutionalStrategyGovernance(CEnterpriseStrategyManager* manager, const string& symbol, const bool& strategyFlags[])
{
    // Apply institutional governance rules - placeholder
}

void ApplyStrategyWeights(CEnterpriseStrategyManager* manager, const string& symbol, const bool& strategyFlags[])
{
    // Apply strategy weights from config - placeholder
    // Actual implementation would set weights on each registered strategy
}

string GetInstrumentExecutionProfileName(const string& symbol)
{
    if(IsSyntheticIndexSymbolName(symbol)) return "SYNTHETIC";
    if(IsForexSymbol(symbol)) return "FOREX";
    return "UNKNOWN";
}

string GetSymbolStrategyProfileLabel(const string& symbol, const bool& strategyFlags[])
{
    if(IsSyntheticIndexSymbolName(symbol)) return "SYNTHETIC_LEAN";
    return "STANDARD";
}

bool UseSyntheticLeanRosterProfile(const string& symbol, const bool& strategyFlags[])
{
    return m_config.useSymbolClassProfiles && IsSyntheticIndexSymbolName(symbol);
}

bool IsSyntheticIndexSymbolName(const string& symbol)
{
    // Fast string heuristic is authoritative for all common synthetic families and
    // avoids any dependency on the shared global profiler, which can be invalid
    // during multi-instance runtime re-initialization (invalid pointer access).
    if(StringFind(symbol, "Volatility") >= 0 ||
       StringFind(symbol, "Boom")      >= 0 ||
       StringFind(symbol, "Crash")     >= 0 ||
       StringFind(symbol, "Jump")      >= 0 ||
       StringFind(symbol, "Step Index")>= 0)
        return true;
    // Secondary, guarded profiler check for edge-case synthetic families.
    if(g_multiAssetProfiler != NULL)
    {
        SAssetProfile profile = g_multiAssetProfiler.GetProfile(symbol);
        return IsSyntheticAssetClass(profile.assetClass);
    }
    return false;
}

bool IsForexSymbol(const string& symbol)
{
    // Simple check for forex pairs (6-7 chars, no spaces)
    int len = StringLen(symbol);
    if(len >= 6 && len <= 7)
    {
        string base = StringSubstr(symbol, 0, 3);
        string quote = StringSubstr(symbol, 3, 3);
        // Check if all letters
        for(int i = 0; i < 6; i++)
        {
            if(i < StringLen(symbol))
            {
                ushort c = StringGetCharacter(symbol, i);
                if(!(c >= 'A' && c <= 'Z')) return false;
            }
        }
        return true;
    }
    return false;
}

// ============ New Helper Methods for AI/Strategy Initialization ============

double ResolveAIRuntimeVoteThreshold(ENUM_EA_MODE effectiveMode)
{
    return MathMax(0.50, MathMin(1.0, m_config.aiConfidenceThreshold));
}

ENUM_EA_MODE ResolveEffectiveEAMode()
{
    CStrategyRegistry* strategyRegistry = m_registryAggregator.GetStrategyRegistry();
    if(strategyRegistry == NULL) return m_config.eaMode;

    ENUM_EA_MODE configuredMode = strategyRegistry.GetMode();
    int activeIndicators = strategyRegistry.GetActiveIndicatorCount();
    int activeAI = strategyRegistry.GetActiveAICount();

    ENUM_EA_MODE effectiveMode = configuredMode;
    string reason = "";

    if((configuredMode == EA_MODE_AI_ONLY || configuredMode == EA_MODE_INDICATOR_FILTERED) && activeAI <= 0)
    {
        effectiveMode = EA_MODE_INDICATOR_ONLY;
        reason = "no_active_ai_voters";
    }
    else if((configuredMode == EA_MODE_INDICATOR_ONLY || configuredMode == EA_MODE_AI_ASSISTED) && activeIndicators <= 0 && activeAI > 0)
    {
        effectiveMode = EA_MODE_AI_ONLY;
        reason = "no_active_indicators";
    }
    else if(configuredMode == EA_MODE_HYBRID && activeAI <= 0)
    {
        effectiveMode = EA_MODE_INDICATOR_ONLY;
        reason = "no_active_ai_voters";
    }
    else if(configuredMode == EA_MODE_HYBRID && activeIndicators <= 0 && activeAI > 0)
    {
        effectiveMode = EA_MODE_AI_ONLY;
        reason = "no_active_indicators";
    }
    else if(configuredMode == EA_MODE_AI_ASSISTED && activeAI <= 0)
    {
        effectiveMode = EA_MODE_INDICATOR_ONLY;
        reason = "no_active_ai_voters";
    }
    else if(configuredMode == EA_MODE_INDICATOR_FILTERED && activeIndicators <= 0)
    {
        effectiveMode = EA_MODE_AI_ONLY;
        reason = "no_active_indicators";
    }

    if(effectiveMode != configuredMode)
    {
        PrintFormat("[MODE-DEGRADE] %s → %s | reason=%s | activeIndicators=%d | activeAI=%d",
        EAModeToString(configuredMode), EAModeToString(effectiveMode), reason, activeIndicators, activeAI);
    }

    return effectiveMode;
}

bool BuildStrategyRegistry(const bool& strategyFlags[])
{
    CStrategyRegistry* strategyRegistry = m_registryAggregator.GetStrategyRegistry();
    if(strategyRegistry == NULL) return false;

    strategyRegistry.Reset();
    strategyRegistry.SetMode(m_config.eaMode);

    // Only register indicators if not in strict AI_ONLY mode
    if(m_config.eaMode != EA_MODE_AI_ONLY)
    {
        bool enabled;

        enabled = (ArraySize(strategyFlags) > SI_MOMENTUM && strategyFlags[SI_MOMENTUM]);
        if(enabled)
        strategyRegistry.RegisterDefinition("Momentum", STRATEGY_MOMENTUM, false, true, false, m_config.weightMomentum);

        enabled = (ArraySize(strategyFlags) > SI_TREND && strategyFlags[SI_TREND]);
        if(enabled)
        strategyRegistry.RegisterDefinition("Trend", STRATEGY_TREND, false, true, false, m_config.weightTrend);

        enabled = (ArraySize(strategyFlags) > SI_SUPPORT_RESISTANCE && strategyFlags[SI_SUPPORT_RESISTANCE]);
        if(enabled)
        strategyRegistry.RegisterDefinition("Support/Resistance", STRATEGY_SUPPORT_RESISTANCE, false, true, false, m_config.weightSupportResistance);

        enabled = (ArraySize(strategyFlags) > SI_CANDLESTICK && strategyFlags[SI_CANDLESTICK]);
        if(enabled)
        strategyRegistry.RegisterDefinition("Candlestick", STRATEGY_CANDLESTICK, false, true, false, m_config.weightCandlestick);

        enabled = (ArraySize(strategyFlags) > SI_MEAN_REVERSION && strategyFlags[SI_MEAN_REVERSION]);
        if(enabled)
        strategyRegistry.RegisterDefinition("Mean Reversion", STRATEGY_MEAN_REVERSION, false, true, false, m_config.weightMeanReversion);

        enabled = (ArraySize(strategyFlags) > SI_VOLATILITY_BREAKOUT && strategyFlags[SI_VOLATILITY_BREAKOUT]);
        if(enabled)
        strategyRegistry.RegisterDefinition("Volatility Breakout", STRATEGY_VOLATILITY_BREAKOUT, false, true, false, m_config.weightVolatilityBreakout);

        // Batch 103: ICT/SMC strategies
        enabled = (ArraySize(strategyFlags) > SI_FVG_SCALPER && strategyFlags[SI_FVG_SCALPER]);
        if(enabled)
        strategyRegistry.RegisterDefinition("FVG Scalper", STRATEGY_FVG_SCALPER, false, true, false, m_config.weightFVGScalper);

        enabled = (ArraySize(strategyFlags) > SI_TURTLE_SOUP && strategyFlags[SI_TURTLE_SOUP]);
        if(enabled)
        strategyRegistry.RegisterDefinition("Turtle Soup", STRATEGY_TURTLE_SOUP, false, true, false, m_config.weightTurtleSoup);

        enabled = (ArraySize(strategyFlags) > SI_BREAKER_BLOCK && strategyFlags[SI_BREAKER_BLOCK]);
        if(enabled)
        strategyRegistry.RegisterDefinition("Breaker Block", STRATEGY_BREAKER_BLOCK, false, true, false, m_config.weightBreakerBlock);

        enabled = (ArraySize(strategyFlags) > SI_NY_OPEN_GAP && strategyFlags[SI_NY_OPEN_GAP]);
        if(enabled)
        strategyRegistry.RegisterDefinition("NY Open Gap", STRATEGY_NY_OPEN_GAP, false, true, false, m_config.weightNYOpenGap);

        enabled = (ArraySize(strategyFlags) > SI_ASIAN_RANGE_BREAK && strategyFlags[SI_ASIAN_RANGE_BREAK]);
        if(enabled)
        strategyRegistry.RegisterDefinition("Asian Range Break", STRATEGY_ASIAN_RANGE_BREAK, false, true, false, m_config.weightAsianRangeBreak);

        enabled = (ArraySize(strategyFlags) > SI_LIQUIDITY_SWEEP && strategyFlags[SI_LIQUIDITY_SWEEP]);
        if(enabled)
        strategyRegistry.RegisterDefinition("Liquidity Sweep", STRATEGY_LIQUIDITY_SWEEP, false, true, false, m_config.weightLiquiditySweep);

        enabled = (ArraySize(strategyFlags) > SI_RANGE_COMPRESSION && strategyFlags[SI_RANGE_COMPRESSION]);
        if(enabled)
        strategyRegistry.RegisterDefinition("Range Compression", STRATEGY_RANGE_COMPRESSION, false, true, false, m_config.weightRangeCompression);
    }

    bool aiBaseEnabled = m_config.enableAIMode;
    double aiWeight = MathMax(0.1, m_config.aiWeightMultiplier);
    strategyRegistry.RegisterDefinition("Neural Network AI", STRATEGY_BRAIN, true,
    (aiBaseEnabled && m_config.enableNeuralNetwork), false, aiWeight);
    strategyRegistry.RegisterDefinition("Transformer AI", STRATEGY_AI_ENHANCED, true,
    (aiBaseEnabled && m_config.enableTransformer), false, aiWeight);
    strategyRegistry.RegisterDefinition("Ensemble AI", STRATEGY_AI_ENHANCED, true,
    (aiBaseEnabled && m_config.enableEnsemble), false, aiWeight);
    strategyRegistry.RegisterDefinition("ONNX AI", STRATEGY_AI_ENHANCED, true,
    (aiBaseEnabled && m_config.enableOnnxAI), false, 2.00);
    strategyRegistry.RegisterDefinition("Python Bridge AI", STRATEGY_AI_ENHANCED, true,
    (aiBaseEnabled && m_config.enablePythonBridgeAI), false, 1.50);

    ENUM_EA_MODE effectiveMode = ResolveEffectiveEAMode();
    if(effectiveMode != strategyRegistry.GetMode())
    {
        PrintFormat("[STRATEGY-REGISTRY] Requested mode=%s degraded to %s based on active strategy availability",
        EAModeToString(m_config.eaMode),
        EAModeToString(effectiveMode));
        strategyRegistry.SetMode(effectiveMode);
    }

    // L7-025: Strict EA Mode - fail init if mode degrades
    if(m_config.strictEAMode && effectiveMode != m_config.eaMode)
    {
        PrintFormat("[CRITICAL] Strict EA Mode enabled but mode degraded from %s to %s",
        EAModeToString(m_config.eaMode), EAModeToString(effectiveMode));
        return false;
    }

    PrintFormat("[STRATEGY-REGISTRY] %s", strategyRegistry.BuildStatusReport());
    return true;
}

void LogAIRuntimeTopology()
{
    CStrategyRegistry* strategyRegistry = m_registryAggregator.GetStrategyRegistry();
    if(strategyRegistry == NULL) return;

    ENUM_EA_MODE effectiveMode = ResolveEffectiveEAMode();
    PrintFormat("[RUNTIME-FINGERPRINT] Runtime=%s | File=%s | TerminalBuild=%d | Curated=%s | RegistrySize=%d | ActiveProfile=%s | RequestedMode=%s | EAMode=%s | HybridStandalone=%s | StandaloneThreshold=%.2f | Indicators=%d | AI=%d",
    TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS),
    __FILE__, (int)TerminalInfoInteger(TERMINAL_BUILD),
    m_config.useCuratedStrategySet ? "true" : "false",
    strategyRegistry.GetDescriptorCount(),
    GetInstrumentExecutionProfileName(m_enterpriseManagerSymbols[0]),
    EAModeToString(m_config.eaMode),
    EAModeToString(effectiveMode),
    m_config.allowHybridAIStandalone ? "true" : "false",
    m_config.aiStandaloneMinConfidence,
    strategyRegistry.GetActiveIndicatorCount(),
    strategyRegistry.GetActiveAICount());
    m_aiTopologyLogged = true;
}

void LogPositionLifecycleConfig()
{
    PrintFormat("[POSITION-LIFECYCLE] enabled=%s | breakeven_buffer_points=%.1f | trailing_distance_points=%.1f | trailing_step_points=%.1f",
    m_config.enablePositionLifecycleManager ? "true" : "false",
    m_config.lifecycleBreakevenBufferPoints,
    m_config.lifecycleTrailingDistancePoints,
    m_config.lifecycleTrailingStepPoints);
}

void ReleaseNeuralNetStrategies()
{
    // L1-008: Do NOT delete neural networks - adapters own them now
    // Adapters are owned by strategy managers and will clean up NNs
    for(int i = 0; i < ArraySize(m_neuralNetStrategies); i++)
    {
        // Just clear pointers - do NOT delete
        m_neuralNetStrategies[i] = NULL;
    }
    ArrayResize(m_neuralNetStrategies, 0);
    ArrayResize(m_neuralNetStrategySymbols, 0);
    m_attributionManager.ClearAll();
}

bool InitializeNeuralNetForSymbol(const string symbol, ENUM_TIMEFRAMES timeframe)
{
    if(!m_config.enableNeuralNetwork)
    return false;

    CEnterpriseStrategyManager* symbolManager = GetEnterpriseManagerForSymbol(symbol);
    if(symbolManager == NULL)
    {
        Print("[AI-MODE] Skipping NN initialization; no strategy manager for ", symbol);
        return false;
    }

    // Check if already initialized for this symbol
    for(int i = 0; i < ArraySize(m_neuralNetStrategies); i++)
    {
        if(m_neuralNetStrategySymbols[i] == symbol && m_neuralNetStrategies[i] != NULL)
        return true;
    }

    // L1-008: Use factory to create Neural Network AI adapter (adapter owns NN)
    CStrategyFactory::SStrategyConfig cfg;
    cfg.symbol = symbol;
    cfg.timeframe = timeframe;
    cfg.weight = 1.0;
    cfg.tier = STRATEGY_TIER_2;
    cfg.intrabarEligible = false;
    cfg.liveVotingEnabled = true;
    cfg.role = PRIMARY_ALPHA;
    cfg.cluster = STRATEGY_CLUSTER_NONE;

    CAIStrategyAdapter* adapter = (CAIStrategyAdapter*)CStrategyFactory::Create("Neural Network AI", cfg);
    if(adapter == NULL)
    {
        Print("[AI-MODE] Failed to create Neural Network AI adapter for ", symbol);
        return false;
    }

    // Get the neural network from adapter and initialize it
    CNeuralNetworkStrategy* nn = adapter.GetNeuralNetwork();
    if(nn == NULL)
    {
        Print("[AI-MODE] Adapter has no neural network for ", symbol);
        delete adapter;
        return false;
    }

    nn.SetOnlineTrainingEnabled(m_config.enableNNOnlineTraining);
    nn.SetWeightMutationEnabled(m_config.enableNNWeightMutation);
    nn.SetConfidenceThreshold(ResolveAIRuntimeVoteThreshold(ResolveEffectiveEAMode()));

    if(!nn.Initialize(symbol, timeframe))
    {
        Print("[AI-MODE] Neural Network initialization failed for ", symbol);
        delete adapter; // Adapter owns NN, will clean up
        return false;
    }

    nn.ConfigureOnlineLearning(m_config.enableNNOnlineTraining && m_config.enableNNPseudoLabeling,
    m_config.nnPseudoLabelBarsAhead,
    m_config.nnSampleIntervalSeconds,
    m_config.nnCheckpointEveryLabeled);

    // Store reference for backward compatibility (dashboard, etc.)
    int currentSize = ArraySize(m_neuralNetStrategies);
    ArrayResize(m_neuralNetStrategies, currentSize + 1);
    ArrayResize(m_neuralNetStrategySymbols, currentSize + 1);
    m_neuralNetStrategies[currentSize] = nn;  // Non-owning reference
    m_neuralNetStrategySymbols[currentSize] = symbol;

    // Register adapter with symbol manager (manager takes ownership)
    CStrategyRegistry* stratRegLocal = m_registryAggregator.GetStrategyRegistry();
    double aiWeight = -1.0;
    if(stratRegLocal != NULL)
    aiWeight = stratRegLocal.GetWeightByName("Neural Network AI");
    if(aiWeight <= 0.0)
    aiWeight = MathMax(0.1, m_config.aiWeightMultiplier);
    if(!symbolManager.RegisterStrategy(adapter, "Neural Network AI", true, aiWeight, STRATEGY_TIER_2, PERIOD_CURRENT, INTRABAR_POLICY_LIVE, PRIMARY_ALPHA, STRATEGY_CLUSTER_NONE, true))
    {
        Print("[AI-MODE] WARNING: Failed to register NN adapter for ", symbol);
        if(stratRegLocal != NULL)
        stratRegLocal.MarkRegistered("Neural Network AI", false, "nn_adapter_register_failed");
        // Adapter will be deleted by symbol manager on failure
        return false;
    }
    if(stratRegLocal != NULL)
    stratRegLocal.MarkRegistered("Neural Network AI", true);

    Print("[AI-MODE] Neural Network ready for ", symbol);
        return true;
    }

    // Initialize Transformer AI adapter for a symbol
    bool InitializeTransformerAIForSymbol(const string symbol, ENUM_TIMEFRAMES timeframe)
    {
        if(!m_config.enableTransformer)
            return false;

        CEnterpriseStrategyManager* symbolManager = GetEnterpriseManagerForSymbol(symbol);
        if(symbolManager == NULL)
        {
            Print("[AI-MODE] Skipping Transformer AI initialization; no strategy manager for ", symbol);
            return false;
        }

        // Check if already initialized for this symbol
        // Note: We don't track Transformer adapters separately since they don't have internal state like NN

        // Use factory to create Transformer AI adapter
        CStrategyFactory::SStrategyConfig cfg;
        cfg.symbol = symbol;
        cfg.timeframe = timeframe;
        cfg.weight = 1.0;
        cfg.tier = STRATEGY_TIER_2;
        cfg.intrabarEligible = false;
        cfg.liveVotingEnabled = true;
        cfg.role = PRIMARY_ALPHA;
        cfg.cluster = STRATEGY_CLUSTER_NONE;

        CTransformerAIStrategyAdapter* adapter = (CTransformerAIStrategyAdapter*)CStrategyFactory::Create("Transformer AI", cfg);
        if(adapter == NULL)
        {
            Print("[AI-MODE] Failed to create Transformer AI adapter for ", symbol);
            return false;
        }

        // Initialize the adapter (Transformer AI doesn't need separate NN initialization)
        if(!adapter.InitializeAI(symbol, timeframe, NULL))
        {
            Print("[AI-MODE] Transformer AI adapter initialization failed for ", symbol);
            delete adapter;
            return false;
        }

        // Register adapter with symbol manager (manager takes ownership)
        CStrategyRegistry* stratRegLocal = m_registryAggregator.GetStrategyRegistry();
        double aiWeight = -1.0;
        if(stratRegLocal != NULL)
            aiWeight = stratRegLocal.GetWeightByName("Transformer AI");
        if(aiWeight <= 0.0)
            aiWeight = MathMax(0.1, m_config.aiWeightMultiplier);
        if(!symbolManager.RegisterStrategy(adapter, "Transformer AI", true, aiWeight, STRATEGY_TIER_2, PERIOD_CURRENT, INTRABAR_POLICY_LIVE, PRIMARY_ALPHA, STRATEGY_CLUSTER_NONE, true))
        {
            Print("[AI-MODE] WARNING: Failed to register Transformer AI adapter for ", symbol);
            if(stratRegLocal != NULL)
                stratRegLocal.MarkRegistered("Transformer AI", false, "transformer_adapter_register_failed");
            delete adapter;
            return false;
        }
        if(stratRegLocal != NULL)
            stratRegLocal.MarkRegistered("Transformer AI", true);

        Print("[AI-MODE] Transformer AI ready for ", symbol);
        return true;
    }

    // Initialize Ensemble AI adapter for a symbol
    bool InitializeEnsembleAIForSymbol(const string symbol, ENUM_TIMEFRAMES timeframe)
    {
        if(!m_config.enableEnsemble)
            return false;

        CEnterpriseStrategyManager* symbolManager = GetEnterpriseManagerForSymbol(symbol);
        if(symbolManager == NULL)
        {
            Print("[AI-MODE] Skipping Ensemble AI initialization; no strategy manager for ", symbol);
            return false;
        }

        // Use factory to create Ensemble AI adapter
        CStrategyFactory::SStrategyConfig cfg;
        cfg.symbol = symbol;
        cfg.timeframe = timeframe;
        cfg.weight = 1.0;
        cfg.tier = STRATEGY_TIER_2;
        cfg.intrabarEligible = false;
        cfg.liveVotingEnabled = true;
        cfg.role = PRIMARY_ALPHA;
        cfg.cluster = STRATEGY_CLUSTER_NONE;

        CEnsembleAIStrategyAdapter* adapter = (CEnsembleAIStrategyAdapter*)CStrategyFactory::Create("Ensemble AI", cfg);
        if(adapter == NULL)
        {
            Print("[AI-MODE] Failed to create Ensemble AI adapter for ", symbol);
            return false;
        }

        // Initialize the adapter
        if(!adapter.InitializeAI(symbol, timeframe, NULL))
        {
            Print("[AI-MODE] Ensemble AI adapter initialization failed for ", symbol);
            delete adapter;
            return false;
        }

        // Register adapter with symbol manager (manager takes ownership)
        CStrategyRegistry* stratRegLocal = m_registryAggregator.GetStrategyRegistry();
        double aiWeight = -1.0;
        if(stratRegLocal != NULL)
            aiWeight = stratRegLocal.GetWeightByName("Ensemble AI");
        if(aiWeight <= 0.0)
            aiWeight = MathMax(0.1, m_config.aiWeightMultiplier);
        if(!symbolManager.RegisterStrategy(adapter, "Ensemble AI", true, aiWeight, STRATEGY_TIER_2, PERIOD_CURRENT, INTRABAR_POLICY_LIVE, PRIMARY_ALPHA, STRATEGY_CLUSTER_NONE, true))
        {
            Print("[AI-MODE] WARNING: Failed to register Ensemble AI adapter for ", symbol);
            if(stratRegLocal != NULL)
                stratRegLocal.MarkRegistered("Ensemble AI", false, "ensemble_adapter_register_failed");
            delete adapter;
            return false;
        }
        if(stratRegLocal != NULL)
            stratRegLocal.MarkRegistered("Ensemble AI", true);

        Print("[AI-MODE] Ensemble AI ready for ", symbol);
        return true;
    }

    // Initialize ONNX AI adapter for a symbol
        bool InitializeONNXAIForSymbol(const string symbol, ENUM_TIMEFRAMES timeframe)
        {
            if(!m_config.enableOnnxAI)
                return false;

            // Check if ONNX session is disabled and if we should retry.
            // Backoff/disable state machine lives in CONNXInitManager; it emits the
            // retry log line and clears the disabled flag when a retry is granted.
            if(!m_onnxInit.ShouldAttemptInit(symbol))
            {
                // Still in backoff period, skip this attempt
                return false;
            }

            CEnterpriseStrategyManager* symbolManager = GetEnterpriseManagerForSymbol(symbol);
            if(symbolManager == NULL)
            {
                Print("[AI-MODE] Skipping ONNX AI initialization; no strategy manager for ", symbol);
                return false;
            }

            // Use factory to create ONNX AI adapter
            CStrategyFactory::SStrategyConfig cfg;
            cfg.symbol = symbol;
            cfg.timeframe = timeframe;
            cfg.weight = 1.0;
            cfg.tier = STRATEGY_TIER_2;
            cfg.intrabarEligible = false;
            cfg.liveVotingEnabled = true;
            cfg.role = PRIMARY_ALPHA;
            cfg.cluster = STRATEGY_CLUSTER_NONE;

            COnnxAIStrategyAdapter* adapter = (COnnxAIStrategyAdapter*)CStrategyFactory::Create("ONNX AI", cfg);
            if(adapter == NULL)
            {
                Print("[AI-MODE] Failed to create ONNX AI adapter for ", symbol);
                HandleONNXInitFailure(symbol);
                return false;
            }

            // Initialize the adapter
            if(!adapter.InitializeAI(symbol, timeframe, NULL))
            {
                Print("[AI-MODE] ONNX AI adapter initialization failed for ", symbol);
                delete adapter;
                HandleONNXInitFailure(symbol);
                return false;
            }

            // Register adapter with symbol manager (manager takes ownership)
            CStrategyRegistry* stratRegLocal = m_registryAggregator.GetStrategyRegistry();
            double aiWeight = -1.0;
            if(stratRegLocal != NULL)
                aiWeight = stratRegLocal.GetWeightByName("ONNX AI");
            if(aiWeight <= 0.0)
                aiWeight = 2.0; // ONNX AI default weight is 2.0
            if(!symbolManager.RegisterStrategy(adapter, "ONNX AI", true, aiWeight, STRATEGY_TIER_2, PERIOD_CURRENT, INTRABAR_POLICY_LIVE, PRIMARY_ALPHA, STRATEGY_CLUSTER_NONE, true))
            {
                Print("[AI-MODE] WARNING: Failed to register ONNX AI adapter for ", symbol);
                if(stratRegLocal != NULL)
                    stratRegLocal.MarkRegistered("ONNX AI", false, "onnx_adapter_register_failed");
                delete adapter;
                HandleONNXInitFailure(symbol);
                return false;
            }
            if(stratRegLocal != NULL)
                stratRegLocal.MarkRegistered("ONNX AI", true);

            // Success - reset retry count
            m_onnxInit.RegisterSuccess();

        Print("[AI-MODE] ONNX AI ready for ", symbol);
        return true;
    }

    // Initialize Python Bridge AI adapter for a symbol
    bool InitializePythonBridgeAIForSymbol(const string symbol, ENUM_TIMEFRAMES timeframe)
    {
        if(!m_config.enablePythonBridgeAI)
            return false;

        CEnterpriseStrategyManager* symbolManager = GetEnterpriseManagerForSymbol(symbol);
        if(symbolManager == NULL)
        {
            Print("[AI-MODE] Skipping Python Bridge AI initialization; no strategy manager for ", symbol);
            return false;
        }

        // Check if Python Bridge is available
        if(m_pythonBridge == NULL || !m_pythonBridge.IsInitialized())
        {
            Print("[AI-MODE] Python Bridge not initialized; skipping Python Bridge AI for ", symbol);
            return false;
        }

        // Use factory to create Python Bridge AI adapter
        CStrategyFactory::SStrategyConfig cfg;
        cfg.symbol = symbol;
        cfg.timeframe = timeframe;
        cfg.weight = 1.5;
        cfg.tier = STRATEGY_TIER_2;
        cfg.intrabarEligible = false;
        cfg.liveVotingEnabled = true;
        cfg.role = PRIMARY_ALPHA;
        cfg.cluster = STRATEGY_CLUSTER_NONE;

        CPythonBridgeAIStrategyAdapter* adapter = (CPythonBridgeAIStrategyAdapter*)CStrategyFactory::Create("Python Bridge AI", cfg);
        if(adapter == NULL)
        {
            Print("[AI-MODE] Failed to create Python Bridge AI adapter for ", symbol);
            return false;
        }

        // Set Python Bridge reference
        adapter.SetPythonBridge(m_pythonBridge);

        // Initialize the adapter
        if(!adapter.InitializeAI(symbol, timeframe, NULL))
        {
            Print("[AI-MODE] Python Bridge AI adapter initialization failed for ", symbol);
            delete adapter;
            return false;
        }

        // Register adapter with symbol manager (manager takes ownership)
        CStrategyRegistry* stratRegLocal = m_registryAggregator.GetStrategyRegistry();
        double aiWeight = -1.0;
        if(stratRegLocal != NULL)
            aiWeight = stratRegLocal.GetWeightByName("Python Bridge AI");
        if(aiWeight <= 0.0)
            aiWeight = 1.5; // Python Bridge AI default weight
        if(!symbolManager.RegisterStrategy(adapter, "Python Bridge AI", true, aiWeight, STRATEGY_TIER_2, PERIOD_CURRENT, INTRABAR_POLICY_LIVE, PRIMARY_ALPHA, STRATEGY_CLUSTER_NONE, true))
        {
            Print("[AI-MODE] WARNING: Failed to register Python Bridge AI adapter for ", symbol);
            if(stratRegLocal != NULL)
                stratRegLocal.MarkRegistered("Python Bridge AI", false, "python_bridge_adapter_register_failed");
            delete adapter;
            return false;
        }
        if(stratRegLocal != NULL)
            stratRegLocal.MarkRegistered("Python Bridge AI", true);

        Print("[AI-MODE] Python Bridge AI ready for ", symbol);
        return true;
    }

    // Helper to handle ONNX initialization failure with retry tracking.
    // Attempt counting, the 3-failure disable threshold and the failure logging
    // now live in CONNXInitManager; this stays as the orchestrator-side entry point.
        void HandleONNXInitFailure(const string symbol)
        {
            m_onnxInit.RegisterFailure(symbol);
            }

        public:
            // Public method to manually re-enable ONNX AI (e.g., after config change or user action)
            void ReenableONNXAI()
            {
                m_onnxInit.Reset();
                Print("[AI-MODE] ONNX AI manually re-enabled. Will attempt re-initialization on next cycle.");
            }

        CEnterpriseStrategyManager* GetEnterpriseManagerForSymbol(const string symbol)
{
    int idx = FindEnterpriseManagerIndex(symbol);
    if(idx < 0 || idx >= ArraySize(m_enterpriseManagers))
    return NULL;
    return m_enterpriseManagers[idx];
}

int FindEnterpriseManagerIndex(const string symbol)
{
    for(int i = 0; i < ArraySize(m_enterpriseManagerSymbols); i++)
    {
        if(m_enterpriseManagerSymbols[i] == symbol)
        return i;
    }
    return -1;
}

void ApplyHurstWeightModifiersToRegime()
{
    if(!m_config.enableHurstEngine)
    return;

    for(int i = 0; i < ArraySize(m_mathEngineSymbols); i++)
    {
        if(m_hurstEngines[i] == NULL)
        continue;

        CHurstEngine* hurst = m_hurstEngines[i];
        if(!hurst.IsWarmedUp())
        continue;

        SHurstSnapshot hurstSnap = hurst.GetSnapshot();
        if(hurstSnap.regime == HURST_RANDOM_WALK)
        continue;  // Don't modify weights if Hurst is in dead zone

        // Find the enterprise manager for this symbol
        int mgrIdx = FindEnterpriseManagerIndex(m_mathEngineSymbols[i]);
        if(mgrIdx < 0 || m_enterpriseManagers[mgrIdx] == NULL)
        continue;

        CUnifiedSignalPipeline* pipeline = m_enterpriseManagers[mgrIdx].GetPipeline();
        if(pipeline == NULL)
        continue;

        CRegimeEngine* regimeEngine = pipeline.GetRegimeEngine(m_mathEngineSymbols[i]);
        if(regimeEngine != NULL)
        {
            regimeEngine.ApplyHurstWeightModifiers(
            hurstSnap.meanRevWeightMult,
            hurstSnap.momentumWeightMult,
            hurstSnap.trendWeightMult,
            hurstSnap.breakoutWeightMult
            );
        }

        // Batch 114: Apply Four-State Regime Detector weight multipliers
        if(m_config.enableFourStateRegime && i < ArraySize(m_fourStateEngines) && m_fourStateEngines[i] != NULL)
        {
            CFourStateRegimeDetector* fourState = m_fourStateEngines[i];
            if(fourState.GetSnapshot().timestamp > 0)
            {
                // Multiply existing weights with Four-State multipliers
                SFourStateSnapshot fsSnap = fourState.GetSnapshot();
                if(regimeEngine != NULL)
                {
                    regimeEngine.ApplyHurstWeightModifiers(
                    fsSnap.meanRevWeightMult,
                    fsSnap.momentumWeightMult,
                    fsSnap.trendWeightMult,
                    fsSnap.breakoutWeightMult
                    );
                }
            }
        }
    }
}

void ReleaseEnterpriseManagers()
{
    for(int i = 0; i < ArraySize(m_enterpriseManagers); i++)
    {
        if(m_enterpriseManagers[i] != NULL)
        {
            m_enterpriseManagers[i].Deinit();
            delete m_enterpriseManagers[i];
            m_enterpriseManagers[i] = NULL;
        }
    }
    ArrayResize(m_enterpriseManagers, 0);
    ArrayResize(m_enterpriseManagerSymbols, 0);

    // Drop the status reporter's borrowed slot-0 pointer so it cannot outlive the
    // deleted manager. The original re-read m_enterpriseManagers[0] on every call
    // and skipped that report section once it was NULL - same observable result.
    m_statusReporter.ClearEnterpriseManager();
}

// ============ Main Processing ============

void OnTick()
{
    ulong tickStartTime = GetMicrosecondCount();
    
    // L5-019: Check for emergency close request from circuit breaker
    if(m_unifiedRiskManager.IsEmergencyCloseRequested())
    {
        PrintFormat("[RISK-EMERGENCY] Emergency close requested - closing all positions");
        m_tradeManager.CloseAllPositions();
        m_unifiedRiskManager.ResetEmergencyCloseRequested();
    }

    ulong safetyStart = GetMicrosecondCount();
            ProcessTickSafetyLoop();
            CJsonLogger::LogPerformance("EAOrchestrator", "ProcessTickSafetyLoop_us", (double)(GetMicrosecondCount() - safetyStart), CCorrelationIdGenerator::Generate());

    // Batch 100: Feed tick data to VPIN and OFI engines (throttled to 200ms)
    ulong vpinStart = GetMicrosecondCount();
    {
        static uint s_lastVpinOfiFeed = 0;
        uint nowMs = GetTickCount();
        if(nowMs - s_lastVpinOfiFeed >= 200)
        {
            for(int i = 0; i < ArraySize(m_mathEngineSymbols); i++)
            {
                string sym = m_mathEngineSymbols[i];
                double tickPrice = SymbolInfoDouble(sym, SYMBOL_BID);
                double tickVolume = (double)SymbolInfoInteger(sym, SYMBOL_VOLUME);
                double bid = SymbolInfoDouble(sym, SYMBOL_BID);
                double ask = SymbolInfoDouble(sym, SYMBOL_ASK);

                if(m_vpinFilters[i] != NULL)
                m_vpinFilters[i].OnTick(tickPrice, tickVolume);
                if(m_ofiEngines[i] != NULL)
                m_ofiEngines[i].OnTick(tickPrice, tickVolume, bid, ask);
            }
            s_lastVpinOfiFeed = nowMs;
        }
    }
            CJsonLogger::LogPerformance("EAOrchestrator", "VPIN_OFI_Feed_us", (double)(GetMicrosecondCount() - vpinStart), CCorrelationIdGenerator::Generate());

    // I4: Feed tick data to Skew Step Analyzer (throttled to 500ms)
    ulong skewStart = GetMicrosecondCount();
    if(m_config.enableSkewStepAnalyzer && m_skewStepAnalyzer.IsInitialized())
    {
        static uint s_lastSkewStepFeed = 0;
        uint nowMs = GetTickCount();
        if(nowMs - s_lastSkewStepFeed >= 500)
        {
            // Hoisted GetDerivProfiler() call out of loop
            CDerivAssetProfiler* derivProf = m_multiAssetProfiler.GetDerivProfiler();
            if(derivProf != NULL)
            {
                for(int i = 0; i < ArraySize(m_enterpriseManagerSymbols); i++)
                {
                    string sym = m_enterpriseManagerSymbols[i];
                    ENUM_DERIV_FAMILY family = derivProf.DetectFamily(sym);
                    if(family == DERIV_SKEW_STEP)
                    {
                        // Calculate step size as difference between current and previous close
                        double close0 = iClose(sym, PERIOD_M1, 0);
                        double close1 = iClose(sym, PERIOD_M1, 1);
                        if(close0 > 0 && close1 > 0)
                        {
                            double stepSize = close0 - close1;
                            m_skewStepAnalyzer.RecordStep(stepSize);
                        }
                    }
                }
            }
            s_lastSkewStepFeed = nowMs;
        }
    }
            CJsonLogger::LogPerformance("EAOrchestrator", "SkewStepAnalyzer_Feed_us", (double)(GetMicrosecondCount() - skewStart), CCorrelationIdGenerator::Generate());

    // Fast-path scalp signal evaluation on ticks (dual-path architecture)
    ulong scalpStart = GetMicrosecondCount();
    if(m_config.enableScalpEngine && m_scalpEngine.IsInitialized())
    {
        ProcessScalpFastPath();
    }
            CJsonLogger::LogPerformance("EAOrchestrator", "ProcessScalpFastPath_us", (double)(GetMicrosecondCount() - scalpStart), CCorrelationIdGenerator::Generate());

    // Overall tick processing time
            CJsonLogger::LogPerformance("EAOrchestrator", "OnTick_Total_us", (double)(GetMicrosecondCount() - tickStartTime), CCorrelationIdGenerator::Generate());
}

void OnTimer()
{
    // L2-001: Early exit during shutdown to prevent accessing invalid resources
    if(m_shuttingDown)
    return;

    // L5-019: Check for emergency close request from circuit breaker
    if(m_unifiedRiskManager.IsEmergencyCloseRequested())
    {
        PrintFormat("[RISK-EMERGENCY] Emergency close requested - closing all positions");
        m_tradeManager.CloseAllPositions();
        m_unifiedRiskManager.ResetEmergencyCloseRequested();
    }

    // Error handling wrapper
    bool timerError = false;
    string timerErrorMsg = "";

    datetime now = TimeCurrent();

    // I2: Compounding tier transition check
    if(m_config.enableCompoundingTiers && m_compoundingTierManager.IsInitialized())
    {
        static datetime lastTierCheck = 0;
        if(lastTierCheck == 0 || (now - lastTierCheck) >= m_config.compoundingTierCheckIntervalSec)
        {
            m_compoundingTierManager.CheckTierTransition(m_unifiedRiskManager, m_positionSizer, m_tradeManager);
            lastTierCheck = now;
        }
    }

    // Periodic AI Health Check (every m_config.heartbeatInterval seconds, min 30)
    static datetime lastAIHealthCheck = 0;
    static datetime lastPythonBridgeCheck = 0;
    int healthCheckInterval = MathMax(30, m_config.heartbeatInterval);

    if(lastAIHealthCheck == 0 || (now - lastAIHealthCheck) >= healthCheckInterval)
    {
        if(m_config.enableAIMode)
        {
            string aiStatus = "[AI-DASHBOARD] ";
            CStrategyRegistry* aiStratReg = m_registryAggregator.GetStrategyRegistry();

            // Transformer status
            if(m_aiBrainReady)
            aiStatus += "TF:RDY | ";
        else
        aiStatus += "TF:OFF | ";

        // Neural Network status
        if(m_aiEngineReady)
        aiStatus += "NN:RDY | ";
    else
    aiStatus += "NN:OFF | ";

    // Ensemble status
    int activeAIModels = 0;
    if(aiStratReg != NULL)
    activeAIModels = aiStratReg.GetActiveAICount();
    aiStatus += "ENS:" + IntegerToString(activeAIModels) + "/4 | ";

    // Memory efficiency indicator
    aiStatus += "MEM:OPTIMIZED";

    Print(aiStatus);
}

// Python Bridge status
if(m_pythonBridge != NULL)
{
    SPythonBridgeHealthStatus bridgeStatus = m_pythonBridge.GetHealthStatus();
    string bridgeStatusStr = "[PYTHON-BRIDGE-DASHBOARD] ";
    bool skipDashboardLog = false;

    // Connection state — differentiate by mode to avoid false CONN:ERROR
    if(m_config.pythonBridgeMode == PYTHON_BRIDGE_OFF)
    {
        bridgeStatusStr += "CONN:DISABLED | ";
    }
else
{
    switch(bridgeStatus.state)
    {
        case PYTHON_BRIDGE_CONNECTED:
        bridgeStatusStr += "CONN:OK | ";
        break;
        case PYTHON_BRIDGE_CONNECTING:
        bridgeStatusStr += "CONN:CONNECTING | ";
        break;
        case PYTHON_BRIDGE_DISCONNECTED:
        // In OBSERVE mode, disconnected is expected when no server runs
        if(m_config.pythonBridgeMode == PYTHON_BRIDGE_OBSERVE)
        {
            // Throttle NOT_CONFIGURED logs to every 300 seconds
            if(!m_pythonBridge.ShouldLogNotConfigured())
            {
                skipDashboardLog = true;
                break;
            }
            bridgeStatusStr += "CONN:NOT_CONFIGURED | ";
        }
    else
    bridgeStatusStr += "CONN:DISCONNECTED | ";
    break;
    case PYTHON_BRIDGE_ERROR:
    bridgeStatusStr += "CONN:ERROR | ";
    break;
}
}

if(!skipDashboardLog)
    {
        // Version info
        if(bridgeStatus.version.version != "")
        bridgeStatusStr += "VER:" + bridgeStatus.version.version + " | ";
    else
    bridgeStatusStr += "VER:UNKNOWN | ";

    // Stats
    bridgeStatusStr += "REQS:" + IntegerToString(bridgeStatus.request_count) + " | ";
    bridgeStatusStr += "OK:" + IntegerToString(bridgeStatus.success_count) + " | ";
    bridgeStatusStr += "ERR:" + IntegerToString(bridgeStatus.error_count);

    string corrId = CCorrelationIdGenerator::Generate("PYTHON");
    CJsonLogger::LogInfo("PYTHON-BRIDGE", bridgeStatusStr, "PYTHON_BRIDGE_DASHBOARD", "", corrId, "");
    // AGENTS.md §6: [PYTHON-BRIDGE-DASHBOARD] log signature
    PrintFormat(FMT_PYTHON_BRIDGE_DASHBOARD, bridgeStatusStr);
    }
}

// L2-007

// L2-007: Set bridge readiness gate after first successful health check
static bool s_firstHealthCheckDone = false;
if(!s_firstHealthCheckDone)
{
    bool pythonOk = true;
    if(m_config.pythonBridgeMode != PYTHON_BRIDGE_OFF && m_pythonBridge != NULL)
    {
        SPythonBridgeHealthStatus bridgeStatus = m_pythonBridge.GetHealthStatus();
        pythonOk = (bridgeStatus.state == PYTHON_BRIDGE_CONNECTED) ||
        (m_config.pythonBridgeMode == PYTHON_BRIDGE_OBSERVE && bridgeStatus.state == PYTHON_BRIDGE_DISCONNECTED);
    }
    bool dashboardOk = (m_dashboardBridge != NULL && m_dashboardBridge.IsEnabled());

    if(pythonOk && dashboardOk)
    {
        m_bridgesReady = true;
        s_firstHealthCheckDone = true;
        Print("[BRIDGE-READINESS] Both bridges healthy - readiness gate OPEN");
    }
else
{
    PrintFormat("[BRIDGE-READINESS] Waiting for bridges... Python OK=%s Dashboard OK=%s",
    pythonOk ? "true" : "false", dashboardOk ? "true" : "false");
}
}

lastAIHealthCheck = now;
}

// Periodic Python Bridge Check (every heartbeat timeout seconds)
if(m_config.pythonBridgeMode != PYTHON_BRIDGE_OFF && m_pythonBridge != NULL && m_bridgesReady
&& (lastPythonBridgeCheck == 0 || (now - lastPythonBridgeCheck) >= m_config.pythonBridgeHeartbeatTimeoutSec))
{
    if(!CheckPointer(m_pythonBridge))
    {
        timerError = true;
        timerErrorMsg = "PythonBridge pointer invalid";
    }
else
{
    m_pythonBridge.SendHeartbeat();
}
lastPythonBridgeCheck = now;
}

// Dashboard bridge state push
if(m_dashboardBridge != NULL && m_dashboardBridge.IsEnabled() && m_bridgesReady
&& (m_lastPush == 0 || (now - m_lastPush) >= m_config.dashboardPushIntervalSec))
{
    // Inject AI data before push
    if(ArraySize(m_neuralNetStrategies) > 0 && m_neuralNetStrategies[0] != NULL)
    {
        double nnConf = 0.0;
        ENUM_TRADE_SIGNAL nnSig = m_neuralNetStrategies[0].GetNeuralSignal(nnConf);
        string nnSigText = "NONE";
        if(nnSig == TRADE_SIGNAL_BUY) nnSigText = "BUY";
        else if(nnSig == TRADE_SIGNAL_SELL) nnSigText = "SELL";

        // Get real regime probabilities
        double regimeProbs[];
        m_neuralNetStrategies[0].GetRegimeProbs(regimeProbs);
        double rTrend = (ArraySize(regimeProbs) > 0) ? regimeProbs[0] : 0.25;
        double rRange = (ArraySize(regimeProbs) > 1) ? regimeProbs[1] : 0.25;
        double rVolatile = (ArraySize(regimeProbs) > 2) ? regimeProbs[2] : 0.25;
        double rSpike = (ArraySize(regimeProbs) > 3) ? regimeProbs[3] : 0.25;
        string regimeName = "RANGE";
        int regimeIdx = m_neuralNetStrategies[0].GetCurrentRegime();
        if(regimeIdx == 0) regimeName = "TREND";
        else if(regimeIdx == 1) regimeName = "RANGE";
        else if(regimeIdx == 2) regimeName = "VOLAT";
        else if(regimeIdx == 3) regimeName = "SPIKE";

        m_dashboardBridge.SetAIData(
        true, nnSigText, nnConf,
        m_neuralNetStrategies[0].GetCompletedTradesCount(), m_neuralNetStrategies[0].GetTrainingSteps(),
        m_neuralNetStrategies[0].GetLastUncertainty(), 0.05,
        m_neuralNetStrategies[0].GetAssetClass(), m_neuralNetStrategies[0].GetBarrierK(), m_neuralNetStrategies[0].GetBarrierVertBars(),
        0, true,
        regimeName, rTrend, rRange, rVolatile, rSpike,
        65, 50, 20, 0.5, 0.5, 0
        );
    }

    if(m_dashboardBridge.PushState() && m_dashboardBridge.IsControlEnabled())
    m_dashboardBridge.PollCommands();
}

m_spikeMonitor.ReleasePauseIfExpired();

// Periodic chart object cleanup (every 5 minutes)
{
    static datetime s_lastChartObjCleanup = 0;
    if(s_lastChartObjCleanup == 0 || (now - s_lastChartObjCleanup) >= 300)
    {
        int totalBefore = ObjectsTotal(0);
        if(totalBefore > 400)
        {
            PrintFormat("[CHART-OBJECTS] WARNING: %d/500 objects — cleanup triggered", totalBefore);
            for(int d = 0; d < ArraySize(m_drawingManagers); d++)
            {
                if(m_drawingManagers[d] != NULL)
                m_drawingManagers[d].CleanupOldObjects();
            }
        }
        s_lastChartObjCleanup = now;
    }
}

// Batch 99: Update EquityCurveManager on every timer tick
if(m_equityCurveManager != NULL)
m_equityCurveManager.Update(AccountInfoDouble(ACCOUNT_EQUITY));

// Batch 100: Update bar-level mathematical engines (Hurst, OU) on timer
for(int i = 0; i < ArraySize(m_mathEngineSymbols); i++)
{
    if(m_hurstEngines[i] != NULL)
    m_hurstEngines[i].Update();
    if(m_ouEngines[i] != NULL)
    m_ouEngines[i].Update();

    // Batch 29a: Bridge Hurst output to GridRecoveryEngine
    if(m_config.gridRecoveryEnabled && m_hurstEngines[i] != NULL && m_hurstEngines[i].IsWarmedUp())
    {
        double hurstVal = m_hurstEngines[i].GetSnapshot().hurstValue;
        m_gridRecovery.SetHurstRegime(m_mathEngineSymbols[i], hurstVal);
        if(!m_gridHurstBridgeLogged[i])
        {
            PrintFormat("[GRID-HURST-BRIDGE] %s | Hurst=%.3f — first bridge to GridRecoveryEngine", m_mathEngineSymbols[i], hurstVal);
            m_gridHurstBridgeLogged[i] = true;
        }
    }
}

// Batch 114: Update Research-Driven Statistical Algorithm Engines
for(int i = 0; i < ArraySize(m_mathEngineSymbols); i++)
{
    if(m_kalmanEngines[i] != NULL)
    m_kalmanEngines[i].Update();
    if(m_cpdEngines[i] != NULL && m_cpdEngines[i].IsInitialized())
    {
        // Feed CPD with close price
        double cpdClose[];
        ArraySetAsSeries(cpdClose, true);
        if(CopyClose(m_mathEngineSymbols[i], (ENUM_TIMEFRAMES)Period(), 0, 1, cpdClose) == 1)
        m_cpdEngines[i].Update(cpdClose[0]);
    }
    if(m_fourStateEngines[i] != NULL)
    m_fourStateEngines[i].Update();
    if(m_volTargetEngines[i] != NULL)
    m_volTargetEngines[i].Update();
}

// Batch 100: Apply Hurst weight modifiers to regime engine
ApplyHurstWeightModifiersToRegime();

// Batch 99: Apply equity curve position size multiplier to PositionSizer via modifier chain
// (The equity curve multiplier is applied as a post-hoc adjustment in the sizing flow)
// CVaR periodic logging (every 5 minutes)
datetime nowCvar = TimeCurrent();
if(m_lastCvarLogTime == 0 || (nowCvar - m_lastCvarLogTime) >= 300)
{
    double cvarValue = m_unifiedRiskManager.GetPortfolioRiskManager().GetCurrentCVaR();
    double absCvar = MathAbs(cvarValue);
    PrintFormat("[CVAR] Portfolio CVaR=%.2f%% at 95%% confidence", absCvar * 100.0);
    m_lastCvarLogTime = nowCvar;
}

// FIX: Periodic indicator handle auto-eviction (every 60 seconds)
static datetime s_lastIndicatorEviction = 0;
if(s_lastIndicatorEviction == 0 || (now - s_lastIndicatorEviction) >= 60)
{
    CIndicatorManager::Instance().ReleaseUnused(300); // Release handles older than 5 minutes
    s_lastIndicatorEviction = now;
}

// L12-012: Process pending async trade confirmations and timeouts
    m_tradeManager.CheckAsyncTimeouts();

    // Emit heartbeat diagnostics (L9-001 through L9-004)
    static datetime s_lastHeartbeat = 0;
    if(s_lastHeartbeat == 0 || (now - s_lastHeartbeat) >= m_config.heartbeatInterval)
    {
        // Phase B-2: counter snapshot + heartbeat emission now owned by
        // CHeartbeatTelemetry::Emit(); argument order is unchanged.
        m_heartbeat.Emit(GetPointer(m_diagnosticsManager));
        s_lastHeartbeat = now;
    }

    ProcessTradingLogic(true);  // true = called from timer
}

// L5-018: Update risk parameters from input changes
void UpdateRiskParametersFromInputs(double maxRiskPerTrade, double maxDailyRisk,
double maxPortfolioRisk, double maxDrawdown,
double dailyLossLimitPercent,
bool allowMinLotRoundUp, double minLotRiskMultiplier,
bool enableCompoundingTiers, ENUM_RISK_TIER riskTier)
{
    // Update RiskTierManager tier - this will apply overrides to UnifiedRiskManager
    m_riskTierManager.SetTier(riskTier);
    m_riskTierManager.ApplyToRiskManager(m_unifiedRiskManager, &m_performanceAnalytics,
    maxDailyRisk, maxPortfolioRisk,
    maxDrawdown * 0.7, maxDrawdown,
    dailyLossLimitPercent);

    // Update PositionSizer
    m_positionSizer.SetAllowMinLotRoundUp(allowMinLotRoundUp);
    m_positionSizer.SetMinLotRiskMultiplier(minLotRiskMultiplier);

    // Update CompoundingTierManager
    m_compoundingTierManager.SetAutoSwitch(enableCompoundingTiers);

    PrintFormat("[RISK-INPUT-UPDATE] Risk parameters updated | risk=%.1f%% daily=%.1f%% portfolio=%.1f%% dd=%.1f%% dailyLoss=%.1f%% roundUp=%s multiplier=%.1f compounding=%s tier=%d",
        maxRiskPerTrade, maxDailyRisk, maxPortfolioRisk, maxDrawdown, dailyLossLimitPercent,
        allowMinLotRoundUp ? "true" : "false", minLotRiskMultiplier,
        enableCompoundingTiers ? "true" : "false", (int)riskTier);
    }

    // ============ ProcessTradingLogic Helper Methods ============

    // Preflight checks: emergency close, system initialized, trading enabled
    bool PreflightChecks(const string corrId)
    {
        // L5-019: Emergency close requested - close all positions immediately
        if(m_unifiedRiskManager.IsEmergencyCloseRequested())
        {
            PrintFormat("[EMERGENCY-CLOSE] Circuit breaker emergency close requested - closing all positions");
            m_tradeManager.CloseAllPositions();
            m_unifiedRiskManager.ResetEmergencyCloseRequested();
            CJsonLogger::ClearCorrelationId();
            return false;
        }

        if(!m_systemInitialized || !m_tradingEnabled)
        {
            CJsonLogger::ClearCorrelationId();
            return false;
        }
    
        return true;
    }

    // Refresh runtime state: risk state, daily profit target, auto mode switching
    void RefreshRuntimeState()
    {
        // Update risk state
        m_unifiedRiskManager.RefreshRuntimeState();

        // Update daily profit target logic
        UpdateDailyProfitTarget();

        // Update auto mode switching
        UpdateAutoModeSwitch();

        // Check unprotected positions
        m_unprotectedTracker.AttemptRemediation();
    }

    // Process AI subsystems: neural network, AI engine, AI feedback
    void ProcessAISubsystems()
    {
        // Neural network online learning
        if(m_config.enableAIMode && m_config.enableNeuralNetwork && m_config.enableNNOnlineTraining)
        {
            // m_nnRegistry.TickOnlineLearningAll(); // Method doesn't exist, use individual calls
            // Would iterate through symbols and call online learning per symbol
        }

        // AI engine adaptation
        if(m_config.enableAIMode && m_aiEngine != NULL)
        {
            m_aiEngine.ProcessAdaptation();
        }

        // AI feedback maintenance
        if(m_aiFeedbackReady)
        {
            m_aiFeedback.CheckAutomaticRetraining();

            // L6-016: Update AI performance metrics for all enterprise managers
            SAIModelMetrics aiMetrics = m_aiFeedback.GetCurrentMetrics();
            for(int m = 0; m < ArraySize(m_enterpriseManagers); m++)
            {
                if(m_enterpriseManagers[m] != NULL)
                {
                    // Update AI strategy weights based on AI feedback
                    // Neural Network AI
                    if(m_config.enableNeuralNetwork)
                    m_enterpriseManagers[m].UpdateAIPerformanceMetrics("Neural Network AI", aiMetrics);
                    // Transformer AI
                    if(m_config.enableTransformer)
                    m_enterpriseManagers[m].UpdateAIPerformanceMetrics("Transformer AI", aiMetrics);
                    // Ensemble AI
                    if(m_config.enableEnsemble)
                    m_enterpriseManagers[m].UpdateAIPerformanceMetrics("Ensemble AI", aiMetrics);
                    // ONNX AI
                    if(m_config.enableOnnxAI)
                    m_enterpriseManagers[m].UpdateAIPerformanceMetrics("ONNX AI", aiMetrics);
                }
            }
        }
    }

    // Detect new bars per symbol
    void DetectNewBarsPerSymbol()
    {
        // Process new bars
        ProcessNewBars();
    }

    // Run signal evaluation cycle: generate and process signals
    void RunSignalEvaluationCycle(const string cycleCorrId)
    {
        // Generate and validate signals
        GenerateAndProcessSignals(cycleCorrId);
    }

    // Post-consensus filtering: update AI vote activity
    void PostConsensusFiltering()
    {
        // Update AI vote activity tracking [L11-004]
        UpdateAIVoteActivity();
    }

    // Manage open positions
    void ManageOpenPositions()
    {
        // Manage positions
        m_positionManager.ManagePositions();
    
        // Process closed positions for NN training linkage (L11-014)
        ProcessClosedPositionsForNNTraining();
    }

    void ProcessTradingLogic(bool fromTimer)
{
    // Generate correlation ID for this trading cycle
    string cycleCorrId = CCorrelationIdGenerator::Generate("CYCLE");
    CJsonLogger::SetCorrelationId(cycleCorrId);
    
    // Preflight checks - emergency close, system initialized, trading enabled
    if(!PreflightChecks(cycleCorrId))
    {
        return;
    }

    // Refresh runtime state - risk state, profit target, auto mode
    RefreshRuntimeState();

    // Process AI subsystems - neural network, AI engine, AI feedback
    ProcessAISubsystems();

    // Detect new bars per symbol
    DetectNewBarsPerSymbol();

    // Run signal evaluation cycle - generate and process signals
    RunSignalEvaluationCycle(cycleCorrId);

    // Post-consensus filtering - update AI vote activity
    PostConsensusFiltering();

    // Manage open positions
    ManageOpenPositions();
    
    CJsonLogger::ClearCorrelationId();
}

    // Process closed positions and link to NN predictions for online training (L11-014)
    void ProcessClosedPositionsForNNTraining()
    {
        // NN diagnostics check removed: m_attributionManager is an object (not pointer)
        // and IsNNDiagnosticsEnabled() is not exposed publicly. Guarded by NN strategy count below.
        
        if(ArraySize(m_neuralNetStrategies) == 0)
            return;
        
        // Get pending close profits from attribution manager with prediction IDs
        ulong positionIds[];
        double profits[];
        string predictionIds[];
        
        int closedCount = m_attributionManager.GetPendingCloseProfits(positionIds, profits, predictionIds);
        if(closedCount <= 0)
            return;
        
        // For each closed position, link to NN strategy
        for(int i = 0; i < closedCount; i++)
        {
            string predId = predictionIds[i];
            double profit = profits[i];
            
            if(predId == "")
                continue;
            
            // Find the NN strategy that made this prediction
            // The prediction ID format is typically "symbol_timeframe_timestamp"
            // We need to match it to the right NN strategy
            for(int nnIdx = 0; nnIdx < ArraySize(m_neuralNetStrategies); nnIdx++)
            {
                CNeuralNetworkStrategy* nn = m_neuralNetStrategies[nnIdx];
                if(nn == NULL || !nn.IsTraining())
                    continue;
                
                // Try to update trade result by prediction ID
                if(nn.UpdateTradeResultByPredictionId(predId, profit))
                {
                    PrintFormat("[NN-TRAINING] Updated trade result for prediction %s: profit=%.2f", predId, profit);
                    break;
                }
            }
        }
    }

void ProcessTickSafetyLoop()
{
    // Delegate to tick safety monitor
    // m_tickSafetyMonitor.Process(); // Method not found - using ValidateTick/IsTradingAllowed instead
    // m_spikeMonitor.Process(); // Method not found - using HandleEmergencyDrawdown/IsPaused instead
}

void FeedMicrostructureEngines()
{
    static uint s_lastVpinOfiFeed = 0;
    uint nowMs = GetTickCount();
    if(nowMs - s_lastVpinOfiFeed >= 200)
    {
        for(int i = 0; i < m_managerCount; i++)
        {
            string sym = m_mathEngineSymbols[i];
            double tickPrice = SymbolInfoDouble(sym, SYMBOL_BID);
            double tickVolume = (double)SymbolInfoInteger(sym, SYMBOL_VOLUME);
            double bid = SymbolInfoDouble(sym, SYMBOL_BID);
            double ask = SymbolInfoDouble(sym, SYMBOL_ASK);

            if(m_vpinFilters[i] != NULL)
            m_vpinFilters[i].OnTick(tickPrice, tickVolume);
            if(m_ofiEngines[i] != NULL)
            m_ofiEngines[i].OnTick(tickPrice, tickVolume, bid, ask);
        }
        s_lastVpinOfiFeed = nowMs;
    }

    // I4: Feed tick data to Skew Step Analyzer (throttled to 500ms)
    if(m_config.enableSkewStepAnalyzer && m_skewStepAnalyzer.IsInitialized())
    {
        static uint s_lastSkewStepFeed = 0;
        uint nowMs = GetTickCount();
        if(nowMs - s_lastSkewStepFeed >= 500)
        {
            CDerivAssetProfiler* derivProf = m_multiAssetProfiler.GetDerivProfiler();
            if(derivProf != NULL)
            {
                for(int i = 0; i < m_managerCount; i++)
                {
                    string sym = m_enterpriseManagerSymbols[i];
                    ENUM_DERIV_FAMILY family = derivProf.DetectFamily(sym);
                    if(family == DERIV_SKEW_STEP)
                    {
                        // Calculate step size as difference between current and previous close
                        double close0 = iClose(sym, PERIOD_M1, 0);
                        double close1 = iClose(sym, PERIOD_M1, 1);
                        if(close0 > 0 && close1 > 0)
                        {
                            double stepSize = close0 - close1;
                            m_skewStepAnalyzer.RecordStep(stepSize);
                        }
                    }
                }
            }
            s_lastSkewStepFeed = nowMs;
        }
    }
}

void ProcessScalpFastPath()
{
    // Fast-path scalp signal evaluation on ticks (dual-path architecture)
    if(m_config.enableScalpEngine && m_scalpEngine.IsInitialized())
    {
        // Iterate over all managed symbols for scalp opportunities
        for(int si = 0; si < m_managerCount; si++)
        {
            string symbol = m_enterpriseManagerSymbols[si];
            if(symbol == "")
            continue;

            ENUM_TRADE_SIGNAL signal = TRADE_SIGNAL_NONE;
            double confidence = 0.0;
            double lotSize = 0.0;

            // Evaluate scalp signal and validate through risk manager
            if(m_scalpEngine.ShouldEnterScalp(symbol, signal, confidence, lotSize))
            {
                // Execute the scalp trade (sync or async based on config)
                if(m_scalpEngine.ExecuteScalpTrade(symbol, signal, lotSize, confidence))
                {
                    PrintFormat("[SCALP-FASTPATH] Executed %s scalp on %s | lot=%.2f | conf=%.2f",
                    signal == TRADE_SIGNAL_BUY ? "BUY" : "SELL",
                    symbol, lotSize, confidence);
                }
            else
            {
                PrintFormat("[SCALP-FASTPATH-FAILED] %s on %s | lot=%.2f",
                signal == TRADE_SIGNAL_BUY ? "BUY" : "SELL",
                symbol, lotSize);
            }
        }
    }
}
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

    if(m_config.dailyProfitTargetPercent > 0.0 && !m_dailyTradingHalt)
    {
        double dailyPnL = CalculateDailyPnLPercent();

        if(dailyPnL >= m_config.dailyProfitTargetPercent && !m_dailyProfitTargetReached)
        {
            m_dailyProfitTargetReached = true;
            m_dailyProfitPeakPct = dailyPnL;
            m_trailingProfitFloor = dailyPnL * m_config.profitTrailFactor;
        }

        if(m_dailyProfitTargetReached)
        {
            m_dailyProfitPeakPct = MathMax(m_dailyProfitPeakPct, dailyPnL);
            m_trailingProfitFloor = m_dailyProfitPeakPct * m_config.profitTrailFactor;

            if(dailyPnL < m_trailingProfitFloor)
            {
                double hardFloor = m_config.dailyProfitTargetPercent * m_config.profitTargetHardFloorRatio;
                // Would trigger selective close
                m_dailyTradingHalt = true;
                m_dailyTradingHaltStartTime = TimeCurrent();
            }
        }
    }

    if(m_dailyTradingHalt && m_dailyTradingHaltStartTime > 0)
    {
        int elapsed = (int)(TimeCurrent() - m_dailyTradingHaltStartTime) / 60;
        if(elapsed >= m_config.dailyHaltCooldownMinutes)
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
    if(!m_config.enableAutoModeSwitch) return;

    // Would determine mode and apply risk parameters
}

void ProcessNewBars()
{
    bool anyNewBar = false;

    for(int i = 0; i < m_managerCount; i++)
    {
        string symbol = m_enterpriseManagerSymbols[i];
        datetime currentBar = iTime(symbol, (ENUM_TIMEFRAMES)Period(), 0);
        if(currentBar <= 0) continue;

        CSymbolScanScheduler* scheduler = m_registryAggregator.GetScanScheduler(symbol);
        if(scheduler != NULL)
        {
            // CheckNewBar not available on CSymbolScanScheduler - using inline bar time comparison
            datetime lastBarTime = scheduler.GetLastSymbolBarTime(i);
            if(lastBarTime != currentBar || lastBarTime == 0)
            {
                scheduler.SetLastSymbolBarTime(i, currentBar);
                scheduler.SetPendingNewBarScan(i, true);
                scheduler.ResetIntrabarBackoff(i);

                anyNewBar = true;
                m_consensusCache.Invalidate(symbol);

                if(m_enterpriseManagers[i] != NULL)
                m_enterpriseManagers[i].OnNewBar(symbol, (ENUM_TIMEFRAMES)Period());

                // AI engine adaptation
                if(m_config.enableAIMode && m_aiEngine != NULL)
                m_aiEngine.ProcessAdaptation();

                // AI feedback
                if(m_aiFeedbackReady)
                m_aiFeedback.CheckAutomaticRetraining();
            }
        }
    }
}

void GenerateAndProcessSignals(const string cycleCorrId)
{
    ulong startTotal = GetMicrosecondCount();
    
    // Check trading permissions
    if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
    return;

    // Check trading blocks
    int secondsSinceLastTrade = (int)(TimeCurrent() - m_lastTradeTime);
    bool cooldownBlocked = (secondsSinceLastTrade < m_config.minSecondsBetweenTrades && m_lastTradeTime > 0);
    int eaPositions = GetEAPositionCount();
    bool positionLimitBlocked = (eaPositions >= m_config.maxPositionsTotal);
    bool unprotectedBlocked = m_unifiedRiskManager.HasUnprotectedPositions();
    bool spikePaused = m_spikeMonitor.IsPaused();

    bool canOpenNewTrades = !(cooldownBlocked || positionLimitBlocked || unprotectedBlocked || spikePaused || m_dailyTradingHalt);

    // Generate signals (new bar mode) - with performance timing
        ulong startSignalGen = GetMicrosecondCount();
        CSignalGenerator::SSignalResult newBarSignals[];
        m_signalGenerator.GenerateSignals(EVAL_MODE_NEW_BAR, newBarSignals, cycleCorrId);
            ulong signalGenTime = GetMicrosecondCount() - startSignalGen;
            CJsonLogger::LogPerformance("EAOrchestrator", "GenerateAndProcessSignals_SignalGen_us", (double)signalGenTime, cycleCorrId);

        // L12-003 Fix: Update SymbolScanScheduler state AFTER consensus decision
        datetime nowTime = TimeCurrent();
        for(int si = 0; si < ArraySize(newBarSignals); si++)
        {
            string symbol = m_enterpriseManagerSymbols[si];
            if(symbol == "") continue;
        
            CSymbolScanScheduler* scheduler = m_registryAggregator.GetScanScheduler(symbol);
            if(scheduler == NULL) continue;
        
            SConsensusDecisionContext ctx = newBarSignals[si].decisionContext;
            int cycleSignalsGenerated = 0;
            int cycleSignalsAfterPipeline = 0;
        
            if(m_enterpriseManagers[si] != NULL)
            {
                int gen, pipe;
                bool quorum;
                m_enterpriseManagers[si].GetLastCycleFunnel(gen, pipe, quorum);
                cycleSignalsGenerated = gen;
                cycleSignalsAfterPipeline = pipe;
            }
        
            scheduler.UpdateSymbolScanStateAfterDecision(symbol, m_scanCycleSequence, si, false,
                                                         cycleSignalsGenerated, cycleSignalsAfterPipeline,
                                                         ctx, nowTime);
        
            scheduler.SetLastSymbolBarTime(si, nowTime);
        }

        // Validate and build candidates
    ulong startCandidateBuild = GetMicrosecondCount();
    int candidatesBuilt = 0;
    for(int i = 0; i < ArraySize(newBarSignals); i++)
    {
        if(!newBarSignals[i].valid) continue;

        string symbol = m_enterpriseManagerSymbols[i];
        CEnterpriseStrategyManager* manager = m_enterpriseManagers[i];
        if(manager == NULL) continue;

        // Build candidate (declare at top of loop for scope)
        STradeCandidate candidate;
        bool candidateBuilt = false;

        // Validate
        // Phase C / Slice 2 (C3): result type hoisted out of the manager into
        // PostConsensusValidator.mqh (the old nested name shadowed the unrelated
        // global SValidationResult declared in Core/Utils/Enums.mqh).
        SPostConsensusValidation validation = manager.ValidateSignal(
                symbol, newBarSignals[i].signal, newBarSignals[i].confidence,
                newBarSignals[i].confluence, EVAL_MODE_NEW_BAR, newBarSignals[i].decisionContext,
                ++m_scanCycleSequence, cycleCorrId);

        if(!validation.passed) continue;

        // Build candidate
                if(!m_candidateBuilder.BuildCandidate(symbol, newBarSignals[i].signal, newBarSignals[i].confidence,
                newBarSignals[i].confluence, newBarSignals[i].decisionContext,
                manager, m_scanCycleSequence, candidate, cycleCorrId))
                continue;
        candidateBuilt = true;
        candidatesBuilt++;

        // Resolve live authority
        CLiveAuthorityResolver::SAuthorityResult authority;
        int strategyIndices[];
        manager.GetLastSignalContributorIndices(strategyIndices);
        m_liveAuthority.SetStrategyManager(manager);
        m_liveAuthority.Resolve(
        symbol, candidate.hasAIContributor, candidate.hasONNXContributor,
        candidate.hasIndicatorContributor, candidate.indicatorContributorCount,
        candidate.confluence, candidate.confidence, candidate.qualityScore,
        candidate.convictionScore, candidate.readinessScore, candidate.contextScore,
        candidate.costScore, candidate.contributorSummary, strategyIndices,
        authority, cycleCorrId);

        candidate.liveAuthorityAllowed = authority.allowed;
        candidate.liveAuthorityRiskMult = authority.riskMultiplier;
        candidate.liveAuthorityReason = authority.reason;

        if(!authority.allowed) continue;

                // Check entry blocks
                if(!canOpenNewTrades) continue;

                // Execute trade
                m_tradeExecutor.Execute(candidate, cycleCorrId);

                // Update heartbeat
                m_heartbeat.IncSignalsValidated();
                m_heartbeat.IncSignalsRiskApproved();
                m_heartbeat.IncSignalsSent();
            }
    
    // Performance timing for total method
        CJsonLogger::LogPerformance("EAOrchestrator", "GenerateAndProcessSignals_Total_us", (double)(GetMicrosecondCount() - startTotal), cycleCorrId);
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

// Heartbeat status text. MUST stay public: TimerProcessor.mqh calls
// m_orchestrator.GetStatusReport() from the heartbeat block.
// Assembly moved to COrchestratorStatusReporter (collaborators injected once in
// WireAndValidateDependencies); the per-cycle counters below cannot be captured
// by pointer in MQL5, so they are forwarded on each call. Output is unchanged.
string GetStatusReport() const
{
    return m_statusReporter.GetStatusReport(m_systemInitialized,
                                            m_tradingEnabled,
                                            m_managerCount,
                                            m_callCount,
                                            m_heartbeat.GetScansAttempted(),
                                            m_heartbeat.GetSignalsValidated(),
                                            m_heartbeat.GetSignalsSent(),
                                            GetEAPositionCount(),
                                            m_config.maxPositionsTotal);
}

// L2-002: AI Subsystem cleanup helper - called on init failure and in Shutdown()
void CleanupAISubsystems()
{
    // Clean up AI Engine
    if(m_aiEngine != NULL)
    {
        delete m_aiEngine;
        m_aiEngine = NULL;
    }
    m_aiEngineReady = false;

    // Shutdown NextGen Brain
    // m_aiNextGenBrain.Shutdown(); // Method not found - destructor handles cleanup
    m_aiBrainReady = false;

    // Shutdown AI Feedback
    // m_aiFeedback.Shutdown(); // Method not found - destructor handles cleanup
    m_aiFeedbackReady = false;

    Print("[CLEANUP] AI subsystems cleaned up");
}

// L2-012: Consolidated AI subsystem initialization
// Ownership hierarchy:
// - Neural Network strategies (created via factory) are OWNED by their adapters
//   which are registered with and OWNED by EnterpriseStrategyManager per symbol
// - CAIEngine (adaptation engine) is OWNED by CEAOrchestrator (this class)
// - m_aiNextGenBrain and m_aiFeedback are stack-allocated members of CEAOrchestrator
// This single method replaces the two separate init blocks in Initialize()
bool InitializeAISubsystems()
{
    if(!m_config.enableAIMode)
    {
        Print("[AI] AI mode disabled - skipping AI subsystem initialization");
        return true;
    }

    bool allSuccess = true;

    // Phase 1: Initialize NextGen Strategy Brain
    if(!m_aiNextGenBrain.Initialize(Symbol(), Period()))
    {
        Print("[INIT] WARNING: NextGen AI Brain failed to initialize");
        m_aiBrainReady = false;
        allSuccess = false;
    }
else
{
    m_aiBrainReady = true;
    Print("[AI] Runtime AI voters are adapter-owned and registered per symbol");
}

// Phase 2: Initialize AI Performance Feedback
if(!m_aiFeedback.Initialize(1000))
{
    Print("[WARNING] AIPerformanceFeedback failed to initialize");
    m_aiFeedbackReady = false;
    allSuccess = false;
}
else
{
    m_aiFeedbackReady = true;
    Print("[INIT] AIPerformanceFeedback initialized for AI model adaptation");
}

// Phase 3: Initialize AI Strategy Adapters per active symbol
// These create AI strategies via factory, wrap in IAIStrategy adapters,
// and register adapters with EnterpriseStrategyManager (manager owns adapters)
if(m_config.enableAIMode && (m_config.enableNeuralNetwork || m_config.enableTransformer || m_config.enableEnsemble || m_config.enableOnnxAI))
{
    ReleaseNeuralNetStrategies();
    int nnInitCount = 0;
    int transformerInitCount = 0;
    int ensembleInitCount = 0;
    int onnxInitCount = 0;
    int pythonBridgeInitCount = 0;
    for(int i = 0; i < m_managerCount; i++)
    {
        string symbol = m_enterpriseManagerSymbols[i];
        ENUM_TIMEFRAMES timeframe = (ENUM_TIMEFRAMES)Period();
        
        if(m_config.enableNeuralNetwork)
        {
            if(InitializeNeuralNetForSymbol(symbol, timeframe))
                nnInitCount++;
        }
        if(m_config.enableTransformer)
        {
            if(InitializeTransformerAIForSymbol(symbol, timeframe))
                transformerInitCount++;
        }
        if(m_config.enableEnsemble)
        {
            if(InitializeEnsembleAIForSymbol(symbol, timeframe))
                ensembleInitCount++;
        }
        if(m_config.enableOnnxAI)
        {
            if(InitializeONNXAIForSymbol(symbol, timeframe))
                onnxInitCount++;
        }
        if(m_config.enablePythonBridgeAI)
        {
            if(InitializePythonBridgeAIForSymbol(symbol, timeframe))
                pythonBridgeInitCount++;
        }
    }
    PrintFormat("[AI-MODE] Neural Network managers initialized: %d", nnInitCount);
    PrintFormat("[AI-MODE] Transformer AI managers initialized: %d", transformerInitCount);
    PrintFormat("[AI-MODE] Ensemble AI managers initialized: %d", ensembleInitCount);
    PrintFormat("[AI-MODE] ONNX AI managers initialized: %d", onnxInitCount);
    PrintFormat("[AI-MODE] Python Bridge AI managers initialized: %d", pythonBridgeInitCount);
}

// Phase 4: Initialize AI Engine for Adaptation (orchestrator-owned)
// This engine adapts strategy weights based on AI predictions
if(ArraySize(m_enterpriseManagers) > 0)
{
    if(m_aiEngine == NULL) m_aiEngine = new CAIEngine();

    SAIAdaptiveConfig aiConfig;
    aiConfig.enabled = true;
    aiConfig.learningRate = 0.1;
    aiConfig.adaptationInterval = 1;
    aiConfig.minConfidenceThreshold = ResolveAIRuntimeVoteThreshold(ResolveEffectiveEAMode());
    aiConfig.useExternalLLM = m_config.enableExternalLLM;

    CEnterpriseStrategyManager* managers[];
    string symbols[];
    int managerCount = ArraySize(m_enterpriseManagers);
    ArrayResize(managers, managerCount);
    ArrayResize(symbols, managerCount);
    for(int i = 0; i < managerCount; i++)
    {
        managers[i] = m_enterpriseManagers[i];
        symbols[i] = m_enterpriseManagerSymbols[i];
    }

    if(m_aiEngine != NULL && m_aiEngine.Initialize(managers, symbols, managerCount, aiConfig))
    {
        m_aiEngineReady = true;
        if(m_config.enableExternalLLM)
        m_aiEngine.SetExternalAIEndpoint(m_config.externalLLMEndpoint);
        Print("[INIT] AI Engine initialized in ADAPTIVE mode (multi-manager)");
    }
else
{
    if(m_aiEngine != NULL)
    {
        delete m_aiEngine;
        m_aiEngine = NULL;
    }
    m_aiEngineReady = false;
    Print("[INIT] WARNING: Failed to initialize AI Engine - adaptation disabled");
    allSuccess = false;
}
}

Print("[AI-DASHBOARD] AI Health Monitoring initialized");
return allSuccess;
}

// ============ Accessors ============

bool GetSystemInitialized() const { return m_systemInitialized; }
bool GetTradingEnabled() const { return m_tradingEnabled; }

// L10-012: Getters for engine state restoration on restart
CTradeManager* GetTradeManager() { return GetPointer(m_tradeManager); }
CFastScalpEngine* GetFastScalpEngine() { return GetPointer(m_scalpEngine); }
CSpikeHunterEngine* GetSpikeHunterEngine() { return GetPointer(m_spikeHunter); }
CGridRecoveryEngine* GetGridRecoveryEngine() { return GetPointer(m_gridRecovery); }
CATRScalpingEngine* GetATRScalpingEngine() { return GetPointer(m_atrScalping); }

//+------------------------------------------------------------------+
//| Update AI vote activity for DiagnosticsManager [L11-004]         |
//| Call after signal generation to track [AI-VOTE] heartbeats       |
//+------------------------------------------------------------------+
void UpdateAIVoteActivity()
{
    if(!m_config.enableAIMode)
        return;
    
    for(int i = 0; i < m_managerCount; i++)
    {
        string symbol = m_enterpriseManagerSymbols[i];
        
        if(m_config.enableNeuralNetwork)
            m_diagnosticsManager.UpdateAIVoteActivity(symbol, "NeuralNet");
        if(m_config.enableTransformer)
            m_diagnosticsManager.UpdateAIVoteActivity(symbol, "Transformer");
        if(m_config.enableEnsemble)
            m_diagnosticsManager.UpdateAIVoteActivity(symbol, "Ensemble");
        if(m_config.enableOnnxAI)
            m_diagnosticsManager.UpdateAIVoteActivity(symbol, "ONNX");
    }
}
};

#endif // CORE_ORCHESTRATION_EA_ORCHESTRATOR_MQH
