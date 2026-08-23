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

// ------------------------------------------------------------------
// Phase F decomposition modules.
// Every cluster below was extracted out of CEAOrchestrator verbatim; the
// orchestrator keeps thin forwarders with the original signatures so no
// caller (internal or external) had to change. Included here - after the
// engine/profiler/registry headers above - because the two stateful hubs
// are held BY VALUE and therefore need their complete type.
// ------------------------------------------------------------------
#include "OrchestratorSymbolClassifier.mqh"     // static: symbol / roster classification
#include "OrchestratorStrategyFlagBuilder.mqh"  // static: global + per-symbol strategy flags
#include "OrchestratorIntrabarPolicy.mqh"       // static: L7-009/L7-010 intrabar + timeframe policy
#include "OrchestratorModeResolver.mqh"         // static: EA-mode degradation + topology logs
#include "OrchestratorProfitGuard.mqh"          // stateful: daily profit target / trading halt
#include "OrchestratorMathEngineHub.mqh"        // stateful: Batch 100/114/107 engine fleets

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

    // Phase F: the sixteen per-symbol engine arrays (Batch 100 Hurst/OU/OFI/VPIN,
    // Batch 114 Kalman/CPD/FourState/VolTarget/ExitOpt/LiquiditySweep/RangeComp,
    // Batch 107 VWAP/VolumeProfile/CVD), the parallel symbol + bridge-log
    // bookkeeping arrays and the m_mathEngineCount cursor now live in
    // COrchestratorMathEngineHub (Core/Orchestration/OrchestratorMathEngineHub.mqh).
    // Held BY VALUE so construction/teardown order is unchanged; the hub OWNS
    // every engine pointer and releases them in ReleaseAll().
    COrchestratorMathEngineHub  m_mathEngineHub;

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

    // Phase F: portfolio profit target tracking (m_lastProfitTargetDay,
    // m_dailyProfitTargetReached, m_dailyProfitPeakPct, m_trailingProfitFloor,
    // m_dailyTradingHalt, m_dailyTradingHaltStartTime) now lives in
    // COrchestratorProfitGuard (Core/Orchestration/OrchestratorProfitGuard.mqh).
    // Held BY VALUE; its constructor reproduces the original initialiser list.
    COrchestratorProfitGuard m_profitGuard;
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
        // Phase F: the six profit-target initialisers moved verbatim into the
        // COrchestratorProfitGuard constructor (m_profitGuard is a by-value member).
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

        // Cleanup mathematical / Batch 114 / institutional engines
        // (Deinit()+delete ordering unchanged - see COrchestratorMathEngineHub::ReleaseAll)
        m_mathEngineHub.ReleaseAll();

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
// (NULL-check on the registry is performed inside the hub, as before)
m_mathEngineHub.RegisterMathEngines(m_registryAggregator.GetMathRegistry());

// Register institutional engines with registry
m_mathEngineHub.RegisterInstitutionalEngines(m_registryAggregator.GetInstitutionalRegistry(),
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
    // Phase F: body moved verbatim to COrchestratorMathEngineHub. The registry
    // pointer that used to be fetched inside the body is now passed in.
    m_mathEngineHub.InitializeMathematicalEngines(m_config,
                                                  m_registryAggregator.GetMathRegistry(),
                                                  m_enterpriseManagerSymbols,
                                                  m_managerCount,
                                                  m_signalDiagnostics);
}

void InitializeInstitutionalEngines()
{
    // Phase F: body moved verbatim to COrchestratorMathEngineHub.
    m_mathEngineHub.InitializeInstitutionalEngines(m_config,
                                                   m_registryAggregator.GetInstitutionalRegistry(),
                                                   m_enterpriseManagerSymbols,
                                                   m_managerCount);
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
    // (ArrayResize + NULL-init + cursor reset moved verbatim into the hub)
    m_mathEngineHub.Reserve(m_managerCount);

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
            int mathIdx = m_mathEngineHub.FindSymbolIndex(sym);
            if(mathIdx >= 0)
            {
                // Wire EnterpriseStrategyManager-level engines (consensus gating)
                m_enterpriseManagers[mi].SetVPINFilter(m_mathEngineHub.GetVPINFilter(mathIdx));
                m_enterpriseManagers[mi].SetOFIEngine(m_mathEngineHub.GetOFIEngine(mathIdx));
                if(m_config.logLevel >= 3)
                PrintFormat("[WIRE] VPIN/OFI wired to EnterpriseManager | Symbol=%s", sym);

                // Find and wire Trend strategy
                IStrategy* trendStrat = m_enterpriseManagers[mi].GetStrategyByName("Trend");
                if(trendStrat != NULL)
                {
                    CStrategyTrend* trendPtr = dynamic_cast<CStrategyTrend*>(trendStrat);
                    if(trendPtr != NULL)
                    {
                        trendPtr.SetHurstEngine(m_mathEngineHub.GetHurstEngine(mathIdx));
                        trendPtr.SetVPINFilter(m_mathEngineHub.GetVPINFilter(mathIdx));
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
                        srPtr.SetHurstEngine(m_mathEngineHub.GetHurstEngine(mathIdx));
                        srPtr.SetVPINFilter(m_mathEngineHub.GetVPINFilter(mathIdx));
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
                        mrPtr.SetHurstEngine(m_mathEngineHub.GetHurstEngine(mathIdx));
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
                        saPtr.SetOUEngine(m_mathEngineHub.GetOUEngine(mathIdx));
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
    // (construction block moved verbatim to COrchestratorMathEngineHub::CreateEnginesForSymbol,
    //  which also advances the m_mathEngineCount cursor exactly as before)
    m_mathEngineHub.CreateEnginesForSymbol(m_config, symbol);

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

// Phase F forwarders. Bodies live in COrchestratorStrategyFlagBuilder,
// COrchestratorSymbolClassifier and COrchestratorIntrabarPolicy; signatures,
// argument order and return values are unchanged so every call site (here and
// in CandidateBuilder / SignalGenerator / EnterpriseStrategyManager) is untouched.

bool BuildStrategyFlags(bool& flags[])
{
    return COrchestratorStrategyFlagBuilder::BuildStrategyFlags(m_config, flags);
}

bool BuildStrategyFlagsForSymbol(const string& symbol, const bool& globalFlags[], bool& symbolFlags[])
{
    return COrchestratorStrategyFlagBuilder::BuildStrategyFlagsForSymbol(
        m_config, GetPointer(m_multiAssetProfiler), symbol, globalFlags, symbolFlags);
}

int CountEffectiveIndicatorStrategiesForSymbol(const bool& symbolFlags[])
{
    return COrchestratorSymbolClassifier::CountEffectiveIndicatorStrategiesForSymbol(symbolFlags);
}

double ResolveSparseIntrabarMinQualityForSymbol(const string& symbol, const bool& strategyFlags[])
{
    return COrchestratorIntrabarPolicy::ResolveSparseIntrabarMinQualityForSymbol(m_config, symbol, strategyFlags);
}

double ResolveIntrabarSingleVoterMinConfidenceForSymbol(const string& symbol, const bool& strategyFlags[])
{
    return COrchestratorIntrabarPolicy::ResolveIntrabarSingleVoterMinConfidenceForSymbol(m_config, symbol, strategyFlags);
}

// L7-009/L7-010: Centralized intrabar policy resolution
// Replaces hardcoded switch statements and duplicate resolution functions
// Synthetic lean overrides driven by CDerivAssetProfiler family profile, not hardcoded indices
ENUM_INTRABAR_POLICY GetIntrabarPolicy(const string symbol, int strategyIndex, const bool& strategyFlags[])
{
    return COrchestratorIntrabarPolicy::GetIntrabarPolicy(
        m_config, GetPointer(m_multiAssetProfiler), symbol, strategyIndex, strategyFlags);
}

// L7-009: Get strategy timeframe config from centralized array
SStrategyTimeframeConfig GetStrategyTimeframeConfig(int strategyIndex) const
{
    return COrchestratorIntrabarPolicy::GetStrategyTimeframeConfig(m_config, strategyIndex);
}

double ClampConsensusInput(double value)
{
    return COrchestratorSymbolClassifier::ClampConsensusInput(value);
}

string BuildEnabledStrategyList(const bool& strategyFlags[])
{
    return COrchestratorSymbolClassifier::BuildEnabledStrategyList(strategyFlags);
}

void ApplyInstitutionalStrategyGovernance(CEnterpriseStrategyManager* manager, const string& symbol, const bool& strategyFlags[])
{
    // Institutional governance hook. No governance layer is active in this build; strategies are
    // registered and weighted through the standard consensus pipeline. Kept as an explicit
    // pass-through so the caller's intent is preserved without changing behaviour.
}

void ApplyStrategyWeights(CEnterpriseStrategyManager* manager, const string& symbol, const bool& strategyFlags[])
{
    // Strategy weights are applied through the consensus/role-cluster pipeline, not here.
    // Kept as an explicit pass-through; wiring a separate weight-application step is a future
    // enhancement, not a behavioural change to make silently.
}

string GetInstrumentExecutionProfileName(const string& symbol)
{
    return COrchestratorSymbolClassifier::GetInstrumentExecutionProfileName(symbol);
}

string GetSymbolStrategyProfileLabel(const string& symbol, const bool& strategyFlags[])
{
    return COrchestratorSymbolClassifier::GetSymbolStrategyProfileLabel(symbol, strategyFlags);
}

bool UseSyntheticLeanRosterProfile(const string& symbol, const bool& strategyFlags[])
{
    return COrchestratorSymbolClassifier::UseSyntheticLeanRosterProfile(m_config, symbol, strategyFlags);
}

// NOTE: this member intentionally shadows the free function of the same name in
// Core/Utils/Instruments.mqh, exactly as it did before Phase F.
bool IsSyntheticIndexSymbolName(const string& symbol)
{
    return COrchestratorSymbolClassifier::IsSyntheticIndexSymbolName(symbol);
}

bool IsForexSymbol(const string& symbol)
{
    return COrchestratorSymbolClassifier::IsForexSymbol(symbol);
}

// ============ New Helper Methods for AI/Strategy Initialization ============

double ResolveAIRuntimeVoteThreshold(ENUM_EA_MODE effectiveMode)
{
    return COrchestratorModeResolver::ResolveAIRuntimeVoteThreshold(m_config, effectiveMode);
}

ENUM_EA_MODE ResolveEffectiveEAMode()
{
    return COrchestratorModeResolver::ResolveEffectiveEAMode(m_config, m_registryAggregator.GetStrategyRegistry());
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
    // __FILE__ is passed in from here so the [RUNTIME-FINGERPRINT] line keeps
    // printing this file's name rather than the module's.
    COrchestratorModeResolver::LogAIRuntimeTopology(m_config,
                                                    m_registryAggregator.GetStrategyRegistry(),
                                                    __FILE__,
                                                    m_enterpriseManagerSymbols[0]);
    m_aiTopologyLogged = true;
}

void LogPositionLifecycleConfig()
{
    COrchestratorModeResolver::LogPositionLifecycleConfig(m_config);
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

    //==============================================================//
    // Batch 145: catalog-driven AI adapter registration.            //
    // The five hand-written Initialize*AIForSymbol() functions were //
    // collapsed into one loop over the CAT_KIND_AI rows of          //
    // Core/Strategy/StrategyCatalog.mqh. Every gate, prep step and  //
    // log line of the originals is preserved; the only behavioural  //
    // change is the F4 fix (no delete after a failed                //
    // RegisterStrategy - the manager already destroyed the adapter).//
    //==============================================================//

    // Per-row master switch (mirrors the old `if(!m_config.enableX) return false;`)
    bool IsCatalogAIRowEnabled(const ENUM_CATALOG_AI k)
    {
        switch(k)
        {
            case CAT_AI_NEURAL_NET:    return m_config.enableNeuralNetwork;
            case CAT_AI_TRANSFORMER:   return m_config.enableTransformer;
            case CAT_AI_ENSEMBLE:      return m_config.enableEnsemble;
            case CAT_AI_ONNX:          return m_config.enableOnnxAI;
            case CAT_AI_PYTHON_BRIDGE: return m_config.enablePythonBridgeAI;
            default:                   return false;
        }
    }

    // Gates that ran BEFORE the factory call in the original functions.
    // Returning false skips the row; alreadyLive=true means the row is
    // already satisfied for this symbol (old NN early `return true`).
    bool CatalogAIPreCreateGate(const ENUM_CATALOG_AI k, const string symbol, bool &alreadyLive)
    {
        alreadyLive = false;

        switch(k)
        {
            case CAT_AI_NEURAL_NET:
            {
                // Check if already initialized for this symbol
                for(int i = 0; i < ArraySize(m_neuralNetStrategies); i++)
                {
                    if(m_neuralNetStrategySymbols[i] == symbol && m_neuralNetStrategies[i] != NULL)
                    {
                        alreadyLive = true;
                        return false;
                    }
                }
                return true;
            }

            case CAT_AI_ONNX:
                // Backoff/disable state machine lives in CONNXInitManager; it emits
                // the retry log line and clears the disabled flag when a retry is
                // granted. Still in backoff => skip this attempt.
                return m_onnxInit.ShouldAttemptInit(symbol);

            case CAT_AI_PYTHON_BRIDGE:
                // Python Bridge AI keeps its OWN predicate (IsInitialized), which is
                // deliberately different from the Statistical Arbitrage bridge gate.
                if(m_pythonBridge == NULL || !m_pythonBridge.IsInitialized())
                {
                    Print("[AI-MODE] Python Bridge not initialized; skipping Python Bridge AI for ", symbol);
                    return false;
                }
                return true;

            default:
                return true;
        }
    }

    // Adapter-specific preparation performed after the factory call and
    // before registration. Caller owns `adapter` until this returns true.
    bool PrepareCatalogAIAdapter(const ENUM_CATALOG_AI k, IStrategy* adapter,
                                 const string symbol, ENUM_TIMEFRAMES tf)
    {
        if(adapter == NULL)
            return false;

        switch(k)
        {
            case CAT_AI_NEURAL_NET:
            {
                CAIStrategyAdapter* nnAdapter = (CAIStrategyAdapter*)adapter;

                // Get the neural network from adapter and initialize it
                CNeuralNetworkStrategy* nn = nnAdapter.GetNeuralNetwork();
                if(nn == NULL)
                {
                    Print("[AI-MODE] Adapter has no neural network for ", symbol);
                    return false;
                }

                nn.SetOnlineTrainingEnabled(m_config.enableNNOnlineTraining);
                nn.SetWeightMutationEnabled(m_config.enableNNWeightMutation);
                nn.SetConfidenceThreshold(ResolveAIRuntimeVoteThreshold(ResolveEffectiveEAMode()));

                if(!nn.Initialize(symbol, tf))
                {
                    Print("[AI-MODE] Neural Network initialization failed for ", symbol);
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
                return true;
            }

            case CAT_AI_TRANSFORMER:
            {
                CTransformerAIStrategyAdapter* tAdapter = (CTransformerAIStrategyAdapter*)adapter;
                if(!tAdapter.InitializeAI(symbol, tf, NULL))
                {
                    Print("[AI-MODE] Transformer AI adapter initialization failed for ", symbol);
                    return false;
                }
                return true;
            }

            case CAT_AI_ENSEMBLE:
            {
                CEnsembleAIStrategyAdapter* eAdapter = (CEnsembleAIStrategyAdapter*)adapter;
                if(!eAdapter.InitializeAI(symbol, tf, NULL))
                {
                    Print("[AI-MODE] Ensemble AI adapter initialization failed for ", symbol);
                    return false;
                }
                return true;
            }

            case CAT_AI_ONNX:
            {
                COnnxAIStrategyAdapter* oAdapter = (COnnxAIStrategyAdapter*)adapter;
                if(!oAdapter.InitializeAI(symbol, tf, NULL))
                {
                    Print("[AI-MODE] ONNX AI adapter initialization failed for ", symbol);
                    HandleONNXInitFailure(symbol);
                    return false;
                }
                return true;
            }

            case CAT_AI_PYTHON_BRIDGE:
            {
                CPythonBridgeAIStrategyAdapter* pAdapter = (CPythonBridgeAIStrategyAdapter*)adapter;

                // Set Python Bridge reference BEFORE initialization
                pAdapter.SetPythonBridge(m_pythonBridge);

                if(!pAdapter.InitializeAI(symbol, tf, NULL))
                {
                    Print("[AI-MODE] Python Bridge AI adapter initialization failed for ", symbol);
                    return false;
                }
                return true;
            }

            default:
                return false;
        }
    }

    // Shared registration tail: weight resolution, RegisterStrategy, registry
    // bookkeeping and the ONNX success/failure hooks.
    bool RegisterCatalogAIAdapter(CEnterpriseStrategyManager* mgr, const int catIdx,
                                  IStrategy* adapter, const string symbol)
    {
        if(mgr == NULL || adapter == NULL)
            return false;
        if(catIdx < 0 || catIdx >= g_strategyCatalogCount)
            return false;

        const string          name = g_strategyCatalog[catIdx].name;
        const ENUM_CATALOG_AI k    = g_strategyCatalog[catIdx].aiKind;

        // Register adapter with symbol manager (manager takes ownership)
        CStrategyRegistry* stratRegLocal = m_registryAggregator.GetStrategyRegistry();
        double aiWeight = -1.0;
        if(stratRegLocal != NULL)
            aiWeight = stratRegLocal.GetWeightByName(name);
        if(aiWeight <= 0.0)
            aiWeight = (g_strategyCatalog[catIdx].aiFallbackWeight > 0.0)
                       ? g_strategyCatalog[catIdx].aiFallbackWeight
                       : MathMax(0.1, m_config.aiWeightMultiplier);

        if(!mgr.RegisterStrategy(adapter, name, true, aiWeight,
                                 g_strategyCatalog[catIdx].tier,
                                 g_strategyCatalog[catIdx].timeframe,
                                 g_strategyCatalog[catIdx].fixedPolicy,
                                 g_strategyCatalog[catIdx].role,
                                 g_strategyCatalog[catIdx].cluster,
                                 g_strategyCatalog[catIdx].liveVoting))
        {
            Print("[AI-MODE] WARNING: Failed to register ", name, " adapter for ", symbol);
            if(stratRegLocal != NULL)
                stratRegLocal.MarkRegistered(name, false, g_strategyCatalog[catIdx].failReason);
            // Batch 145 / F4 fix: RegisterStrategy() already deleted the adapter on
            // failure - deleting it here again was a double free (4 of the 5 old
            // paths did exactly that).
            if(k == CAT_AI_ONNX)
                HandleONNXInitFailure(symbol);
            return false;
        }

        if(stratRegLocal != NULL)
            stratRegLocal.MarkRegistered(name, true);

        if(k == CAT_AI_ONNX)
            m_onnxInit.RegisterSuccess();   // Success - reset retry count

        Print("[AI-MODE] ", name, " ready for ", symbol);
        return true;
    }

    // Register every enabled AI catalog row for one symbol.
    // Returns the number of rows that are live for the symbol.
    int RegisterCatalogAIStrategiesForSymbol(const string symbol, ENUM_TIMEFRAMES timeframe)
    {
        BuildStrategyCatalog();

        CEnterpriseStrategyManager* symbolManager = GetEnterpriseManagerForSymbol(symbol);
        if(symbolManager == NULL)
        {
            Print("[AI-MODE] Skipping AI adapter initialization; no strategy manager for ", symbol);
            return 0;
        }

        int okCount = 0;
        for(int i = 0; i < g_strategyCatalogCount; i++)
        {
            if(g_strategyCatalog[i].kind != CAT_KIND_AI)
                continue;

            const ENUM_CATALOG_AI k = g_strategyCatalog[i].aiKind;
            if(!IsCatalogAIRowEnabled(k))
                continue;
            if(!CatalogSymbolAllowed(i, symbol))
                continue;

            bool alreadyLive = false;
            if(!CatalogAIPreCreateGate(k, symbol, alreadyLive))
            {
                if(alreadyLive)
                    okCount++;
                continue;
            }

            // L1-008: Use factory to create the AI adapter (adapter owns its model)
            CStrategyFactory::SStrategyConfig cfg;
            cfg.symbol            = symbol;
            cfg.timeframe         = timeframe;
            cfg.weight            = 1.0;
            cfg.tier              = STRATEGY_TIER_2;
            cfg.intrabarEligible  = false;
            cfg.liveVotingEnabled = true;
            cfg.role              = PRIMARY_ALPHA;
            cfg.cluster           = STRATEGY_CLUSTER_NONE;

            IStrategy* adapter = CStrategyFactory::Create(g_strategyCatalog[i].factoryName, cfg);
            if(adapter == NULL)
            {
                Print("[AI-MODE] Failed to create ", g_strategyCatalog[i].name, " adapter for ", symbol);
                if(k == CAT_AI_ONNX)
                    HandleONNXInitFailure(symbol);
                continue;
            }

            if(!PrepareCatalogAIAdapter(k, adapter, symbol, timeframe))
            {
                // Not yet owned by any manager - the orchestrator must free it.
                delete adapter;
                continue;
            }

            if(RegisterCatalogAIAdapter(symbolManager, i, adapter, symbol))
                okCount++;
        }

        return okCount;
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

// Phase F: body moved verbatim to COrchestratorMathEngineHub. The engine
// arrays it walked are owned by the hub now; the manager array/symbol list
// are still owned here and are passed through.
void ApplyHurstWeightModifiersToRegime()
{
    m_mathEngineHub.ApplyHurstWeightModifiersToRegime(m_config, m_enterpriseManagers, m_enterpriseManagerSymbols);
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
    // Phase F: loop + 200 ms throttle moved verbatim into the hub. The loop
    // bound stays ArraySize(m_mathEngineSymbols), which the hub exposes as
    // GetSymbolCount(), so the iteration count is unchanged.
    m_mathEngineHub.FeedMicrostructure(m_mathEngineHub.GetSymbolCount());
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

// Batch 100 + Batch 114: bar-level engine updates (Hurst, OU, Grid-Hurst
// bridge, Kalman, CPD, Four-State, VolTarget). Phase F: both loops moved
// verbatim into COrchestratorMathEngineHub::UpdateTimerEngines. m_gridRecovery
// is a by-value member so GetPointer() is never NULL.
m_mathEngineHub.UpdateTimerEngines(m_config, GetPointer(m_gridRecovery));

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
    // Phase F: VPIN/OFI feed loop + 200 ms throttle moved verbatim into the hub.
    m_mathEngineHub.FeedMicrostructure(m_managerCount);

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

// Phase F: state machine + its six state members moved verbatim to
// COrchestratorProfitGuard (held here by value).
void UpdateDailyProfitTarget()
{
    m_profitGuard.UpdateDailyProfitTarget(m_config);
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

    bool canOpenNewTrades = !(cooldownBlocked || positionLimitBlocked || unprotectedBlocked || spikePaused || m_profitGuard.IsTradingHalted());

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


bool IsEAOwnedMagic(long magic) const
{
    // Simplified check
    return m_tradeManager.IsEAOwnedMagic(magic);
}

// Phase F: body moved verbatim to COrchestratorProfitGuard (static helper).
double CalculateDailyPnLPercent()
{
    return COrchestratorProfitGuard::CalculateDailyPnLPercent();
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
    // Batch 145: one catalog pass per symbol replaces the five per-adapter calls.
    // The per-row m_config.enableX gate now lives in IsCatalogAIRowEnabled().
    int aiAdapterInitCount = 0;
    for(int i = 0; i < m_managerCount; i++)
    {
        string symbol = m_enterpriseManagerSymbols[i];
        ENUM_TIMEFRAMES timeframe = (ENUM_TIMEFRAMES)Period();

        aiAdapterInitCount += RegisterCatalogAIStrategiesForSymbol(symbol, timeframe);
    }
    PrintFormat("[AI-MODE] Catalog AI adapters initialized: %d across %d manager(s)",
                aiAdapterInitCount, m_managerCount);
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
