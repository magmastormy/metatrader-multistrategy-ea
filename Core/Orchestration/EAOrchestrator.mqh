// EA composition root: owns and wires every trading subsystem (Factory/Builder).
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
#include "../../Core/Risk/BasketEquityStop.mqh"      // basket-level equity stop (article 23662)
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
#include "../../Core/Utils/MagicRange.mqh"
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
#include "../../Core/Utils/StructuredLogger.mqh"
#include "../../Core/Utils/CorrelationId.mqh"
#include "../../Core/Config/LiveConfigReloader.mqh"
#include "../../Core/Visualization/RiskDashboardPanel.mqh"
#include "../../Core/Monitoring/SymbolHealthMonitor.mqh"
#include "../../crash_recovery_helpers.mqh"
#include <Trade\SymbolInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <Object.mqh>

// Guarded: CMagicRange (Core/Utils/MagicRange.mqh) is the single owner of this arithmetic.
#ifndef MAGIC_SYMBOL_MULTIPLIER
#define MAGIC_SYMBOL_MULTIPLIER 100
#endif

#define STRATEGY_COUNT 21  // Number of indicator strategies in flags array (0-20, max enum value is STRATEGY_EXIT_OPTIMIZER=20)

// AI Strategy types (registered separately via AI adapters)
#define STRATEGY_NEURAL_NETWORK_AI 17
#define STRATEGY_TRANSFORMER_AI 18
#define STRATEGY_ENSEMBLE_AI 19
#define STRATEGY_ONNX_AI 20
#define STRATEGY_PYTHON_BRIDGE_AI 21

#define CRASH_RECOVERY_STATE_FILE "CrashRecoveryState.json"

#include "OrchestratorConfig.mqh"
#include "StrategyConfigBuilder.mqh"

// Included after the engine/profiler/registry headers above because the two stateful
// decomposition hubs are held BY VALUE and need their complete type.
#include "OrchestratorSymbolClassifier.mqh"     // static: symbol / roster classification
#include "OrchestratorStrategyFlagBuilder.mqh"  // static: global + per-symbol strategy flags
#include "OrchestratorIntrabarPolicy.mqh"       // static: L7-009/L7-010 intrabar + timeframe policy
#include "OrchestratorModeResolver.mqh"         // static: EA-mode degradation + topology logs
#include "OrchestratorProfitGuard.mqh"          // stateful: daily profit target / trading halt
#include "OrchestratorMathEngineHub.mqh"        // stateful: mathematical + institutional engine fleets

class CEAOrchestratorBuilder
{
    private:
    SOrchestratorConfig m_config;

    public:
    CEAOrchestratorBuilder() {}

    CEAOrchestratorBuilder* WithConfig(const SOrchestratorConfig &config) { m_config = config; return GetPointer(this); }

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

    void* Build();

    SOrchestratorConfig GetConfig() const { return m_config; }
};

void* CEAOrchestratorBuilder::Build()
{
    return new CEAOrchestrator();
}

class CEAOrchestrator
{
    private:
    CSymbolInfo                 m_globalSymbol;
    CAccountInfo                m_accountInfo;
    CEnhancedErrorHandler       m_errorHandler;
    CUnifiedRiskManager         m_unifiedRiskManager;
    CUnprotectedPositionTracker m_unprotectedTracker;
    CRiskTierManager            m_riskTierManager;
    CCompoundingTierManager     m_compoundingTierManager;
    CFamilyStrategyWeightMatrix m_familyWeightMatrix;
    CMagicNumberAllocator     m_magicNumberAllocator;  // centralized magic-number allocation
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

    // Bayesian Kelly / equity-curve / ADX / CVaR sizing subsystems
    CEquityCurveManager*        m_equityCurveManager;
    CBayesianKellyModifier*     m_bayesianKellyModifier;
    CEquityCurveLotModifier*    m_equityCurveLotModifier;
    CADXLotModifier*            m_adxModifier;
    datetime                    m_lastCvarLogTime;

    // Per-symbol mathematical/institutional engine arrays live in the hub below. Held BY
    // VALUE so construction/teardown order is fixed; the hub OWNS every engine pointer.
    COrchestratorMathEngineHub  m_mathEngineHub;

    CSignalGenerator            m_signalGenerator;
    CCandidateBuilder           m_candidateBuilder;
    CTradeExecutor              m_tradeExecutor;
    CLiveAuthorityResolver      m_liveAuthority;
    CPositionManager            m_positionManager;

    CRegistryAggregator             m_registryAggregator;

    // Heartbeat status text. Wired once by WireAndValidateDependencies(); read-only, no trading impact.
    COrchestratorStatusReporter     m_statusReporter;

    // Live equity/PnL state is owned by CPerformanceAnalytics and CUnifiedRiskManager.

    ENUM_MARKET_REGIME m_currentRegime;
    datetime m_lastTradeTime;
    int    m_totalActivePositions;
    string m_activePairs[];
    bool   m_systemInitialized;
    bool   m_tradingEnabled;
    // Set only after WireAndValidateDependencies() confirms every trading-path manager got
    // all required deps. While false, Initialize() fails and OnInit fails (fail-closed).
    bool   m_dependenciesValid;

    // Heartbeat / rejection funnel counters. Write-only telemetry; no control flow branches on them.
    CHeartbeatTelemetry m_heartbeat;

    ulong    m_scanCycleSequence;
    int      m_cyclesSinceIndicatorSignal;
    bool     m_hybridGateRelaxed;
    int      m_consecutiveZeroSignalCycles;
    int      m_zeroSignalFallbackThreshold;

    // Provenance of AI-contributed executed trades, keyed by open position id and fed into
    // CLiveAuthorityResolver::RecordOutcome on full close so PROVEN_AI promotion accumulates
    // evidence. Parallel arrays because MQL5 forbids dynamic arrays of structs holding arrays.
    ulong    m_execProvPositionIds[];
    int      m_execProvManagerIdx[];
    string   m_execProvContributorCsv[];
    string   m_execProvIndicesCsv[];
    int      m_execProvCount;

    // Off-journal diagnostics logger. Do NOT remove: InitializeEx() writes
    // "MultiStrategyEA_diagnostics.log" and emits [DIAG-LOGGER] journal lines.
    CDiagnosticsLogger m_diagLogger;

    // Daily profit-target / trading-halt state lives in COrchestratorProfitGuard (BY VALUE).
    COrchestratorProfitGuard m_profitGuard;
    CBasketEquityStop      m_basketEquityStop;   // basket-level equity stop
    bool   m_shuttingDown;
    bool   m_bridgesReady;
    datetime m_lastPush;

    // Crash-recovery state: read at the top of Initialize(), applied only AFTER
    // CUnifiedRiskManager::Initialize() (its breaker reset would discard an early restore).
    bool     m_recoveryStateLoaded;
    double   m_savedEquityBaseline;
    double   m_savedPeakEquity;
    int      m_savedDDBreachCount;
    double   m_savedDDMax;
    int      m_savedHaltFlags;      // bit0 = daily-loss halt, bit1 = drawdown halt
    int      m_savedTradingDayKey;  // broker trading day the saved state belongs to
    uint     m_lastStatePersistTime; // GetTickCount() ms, wall clock

    CLiveConfigReloader      m_configReloader;
    CRiskDashboardPanel      m_riskDashboard;
    CSymbolHealthMonitor     m_symbolHealth;
    string                   m_currentCorrId;

    enum ENUM_AUTO_SWITCH_MODE { AUTO_MODE_CONSERVATIVE = 0, AUTO_MODE_AGGRESSIVE = 1, AUTO_MODE_EMERGENCY = 2 };
    ENUM_AUTO_SWITCH_MODE m_currentTradingMode;

    // Dormancy cooldown tracking per symbol
    int    m_dormantConsecutiveCount[];
    datetime m_dormantCooldownUntil[];
    string m_dormantCooldownSymbols[];
    int m_dormantCooldownThreshold;
    int m_dormantCooldownMinutes;

    // Scalp blacklist tracking per symbol (time-based cooldown)
    int    m_scalpBlacklistFailCount[];
    bool   m_scalpBlacklisted[];
    datetime m_scalpBlacklistUntil[];
    string m_scalpBlacklistSymbols[];
    int m_scalpBlacklistThreshold;
    int m_scalpBlacklistCooldownMinutes;
    int m_scalpBlacklistCooldownMinutesStd;

    int m_callCount;
    int m_managerCount;

    SOrchestratorConfig m_config;

    public:
    CEAOrchestrator() : m_systemInitialized(false), m_tradingEnabled(false),
        m_dependenciesValid(false),
        m_managerCount(0), m_aiEngine(NULL),
        m_pythonBridge(NULL),
        m_lastTradeTime(0), m_scanCycleSequence(0), m_cyclesSinceIndicatorSignal(0),
    m_execProvCount(0),
        m_hybridGateRelaxed(false), m_callCount(0),
        m_currentRegime(MARKET_REGIME_UNKNOWN),
        m_totalActivePositions(0),
        m_zeroSignalFallbackThreshold(20),
        m_currentTradingMode(AUTO_MODE_CONSERVATIVE),
        m_lastCvarLogTime(0), m_shuttingDown(false), m_bridgesReady(false), m_lastPush(0),
        m_recoveryStateLoaded(false),
        m_savedEquityBaseline(0.0), m_savedPeakEquity(0.0),
        m_savedDDBreachCount(0), m_savedDDMax(0.0),
        m_savedHaltFlags(0), m_savedTradingDayKey(0),
        m_lastStatePersistTime(0),
        m_aiBrainReady(false), m_aiEngineReady(false), m_aiFeedbackReady(false),
        m_aiTopologyLogged(false),
        m_adxModifier(NULL)
        // m_onnxInit initialises itself (disabled=false, retryCount=0, lastAttempt=0).
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
        // Set the shutdown flag FIRST: OnTimer must not touch resources being released.
        m_shuttingDown = true;

        // Math + institutional engine Deinit()/delete ordering owned by ReleaseAll().
        m_mathEngineHub.ReleaseAll();

        // EA owns the modifiers; PositionSizer holds only non-owning refs
        if(m_positionSizer.IsInitialized())
        {
            m_positionSizer.ClearModifiers();
        }

        if(m_bayesianKellyModifier != NULL) { delete m_bayesianKellyModifier; m_bayesianKellyModifier = NULL; }
        if(m_equityCurveLotModifier != NULL) { delete m_equityCurveLotModifier; m_equityCurveLotModifier = NULL; }
        if(m_adxModifier != NULL) { delete m_adxModifier; m_adxModifier = NULL; }
        if(m_equityCurveManager != NULL) { delete m_equityCurveManager; m_equityCurveManager = NULL; }

        if(m_pythonBridge != NULL) { m_pythonBridge.Shutdown(); delete m_pythonBridge; m_pythonBridge = NULL; }
        if(m_dashboardBridge != NULL) { m_dashboardBridge.Shutdown(); delete m_dashboardBridge; m_dashboardBridge = NULL; }

        for(int i = 0; i < ArraySize(m_neuralNetStrategies); i++)
        {
            if(m_neuralNetStrategies[i] != NULL) { delete m_neuralNetStrategies[i]; m_neuralNetStrategies[i] = NULL; }
        }
        ArrayResize(m_neuralNetStrategies, 0);
        ArrayResize(m_neuralNetStrategySymbols, 0);

        for(int i = 0; i < ArraySize(m_drawingManagers); i++)
        {
            if(m_drawingManagers[i] != NULL) { delete m_drawingManagers[i]; m_drawingManagers[i] = NULL; }
        }
        ArrayResize(m_drawingManagers, 0);
        ArrayResize(m_drawingManagerSymbols, 0);

        CleanupAISubsystems();

        CJsonLogger::Shutdown();
        
        m_riskDashboard.Destroy();
        m_symbolHealth.SetEnabled(false);

        if(m_signalDiagnostics != NULL)
        {
            m_signalDiagnostics.Shutdown();
            delete m_signalDiagnostics;
            m_signalDiagnostics = NULL;
        }

        m_diagLogger.Deinit();

        // Attribution diag print BEFORE releasing enterprise managers (which clears the data)
        m_attributionManager.NNDiagPrintSummary("deinit");

        ReleaseEnterpriseManagers();

        CStrategyRegistry* strategyRegistry = m_registryAggregator.GetStrategyRegistry();
        if(strategyRegistry != NULL)
        strategyRegistry.Reset();

        // Destroy error handler singleton (must be before IndicatorManager destruction)
        CEnhancedErrorHandler::DestroyInstance();

        m_spikeHunter.Deinit();
        m_gridRecovery.Deinit();
        m_atrScalping.Deinit();

        // Explicit Deinit flushes async trade persistence
        m_tradeManager.Deinit();

        m_scalpCache.Cleanup();

        UncertaintyDeinit();

        // Forced write: the 30 s throttle never applies here, and deinit must leave a record.
        PersistRiskRuntimeState(true);

    m_systemInitialized = false;
    m_tradingEnabled = false;
    m_dependenciesValid = false;

    Print("[EAOrchestrator] Shutdown complete");
}

// Apply crash-recovery state; call only after CUnifiedRiskManager::Initialize().
void RestoreRiskRuntimeState()
{
    if(!m_recoveryStateLoaded)
        return;

    // Day-scoped fields (daily-start baseline, daily-loss halt) must not cross broker days.
    // version:1 files carry no day key, so they restore only the non-day-scoped fields.
    int currentDayKey = m_unifiedRiskManager.GetCurrentTradingDayKey();
    bool dayMatches = (m_savedTradingDayKey != 0 && m_savedTradingDayKey == currentDayKey);

    bool restoreDailyLossHalt = dayMatches && (m_savedHaltFlags & 1) != 0;
    bool restoreTradingHalt   = (m_savedHaltFlags & 2) != 0;

    m_unifiedRiskManager.RestoreCircuitBreakerState(
        m_savedPeakEquity,
        dayMatches ? m_savedEquityBaseline : 0.0,
        m_savedDDBreachCount,
        m_savedDDMax,
        restoreDailyLossHalt,
        restoreTradingHalt);

    // Otherwise the first CheckAndResetDailyLimits() would re-anchor the restored baseline.
    if(dayMatches)
        m_unifiedRiskManager.SeedTradingDayKey(m_savedTradingDayKey);

    PrintFormat("[RECOVERY] Applied after risk manager init | dayKey saved=%d current=%d (%s) | dailyHalt=%s | drawdownHalt=%s",
                m_savedTradingDayKey, currentDayKey,
                dayMatches ? "same broker day" : "stale - daily budget re-anchored",
                restoreDailyLossHalt ? "RESUMED" : "clear",
                restoreTradingHalt ? "RESUMED" : "clear");

    m_recoveryStateLoaded = false;
}

// Persist circuit-breaker state. Throttled unless forced.
void PersistRiskRuntimeState(const bool force)
{
    // Wall-clock throttle: TimeCurrent() only advances with ticks, so gating on it would stall
    // persistence on a quiet symbol or over a weekend. The day key stays on TimeCurrent().
    uint nowMs = GetTickCount();
    if(!force && m_lastStatePersistTime != 0 && (nowMs - m_lastStatePersistTime) < 30000)
        return;
    m_lastStatePersistTime = nowMs;

    int haltFlags = 0;
    if(m_unifiedRiskManager.IsDailyLossHaltActive())
        haltFlags |= 1;
    if(!m_unifiedRiskManager.IsTradingEnabled())
        haltFlags |= 2;

    if(WriteCrashRecoveryState(CRASH_RECOVERY_STATE_FILE,
    m_unifiedRiskManager.GetDailyStartEquity(),
    m_unifiedRiskManager.GetPeakEquity(),
    m_unifiedRiskManager.GetDrawdownBreachCount(),
    m_unifiedRiskManager.GetMaxDrawdownFromPeak(),
    haltFlags,
    m_unifiedRiskManager.GetCurrentTradingDayKey()))
    {
        // Log only when a halt is being recorded, so the 30s cadence stays quiet.
        if(haltFlags != 0)
            PrintFormat("[RECOVERY] State written | haltFlags=%d (bit0 daily-loss, bit1 drawdown) | peakEquity=%.2f",
                        haltFlags, m_unifiedRiskManager.GetPeakEquity());
    }
    else
    {
        PrintFormat("[RECOVERY] WARNING: Failed to write crash recovery state to %s", CRASH_RECOVERY_STATE_FILE);
    }
}

void CleanupOnInitFailure()
{
    // Must mirror every release Shutdown() performs; init can fail after those objects exist.

    m_mathEngineHub.ReleaseAll();

    // EA-owned position-sizing modifiers (PositionSizer holds non-owning refs)
    if(m_positionSizer.IsInitialized())
        m_positionSizer.ClearModifiers();
    if(m_bayesianKellyModifier != NULL) { delete m_bayesianKellyModifier; m_bayesianKellyModifier = NULL; }
    if(m_equityCurveLotModifier != NULL) { delete m_equityCurveLotModifier; m_equityCurveLotModifier = NULL; }
    if(m_adxModifier != NULL) { delete m_adxModifier; m_adxModifier = NULL; }
    if(m_equityCurveManager != NULL) { delete m_equityCurveManager; m_equityCurveManager = NULL; }

    for(int i = 0; i < ArraySize(m_neuralNetStrategies); i++)
    {
        if(m_neuralNetStrategies[i] != NULL) { delete m_neuralNetStrategies[i]; m_neuralNetStrategies[i] = NULL; }
    }
    ArrayResize(m_neuralNetStrategies, 0);
    ArrayResize(m_neuralNetStrategySymbols, 0);

    for(int i = 0; i < ArraySize(m_drawingManagers); i++)
    {
        if(m_drawingManagers[i] != NULL) { delete m_drawingManagers[i]; m_drawingManagers[i] = NULL; }
    }
    ArrayResize(m_drawingManagers, 0);
    ArrayResize(m_drawingManagerSymbols, 0);

    m_spikeHunter.Deinit();
    m_gridRecovery.Deinit();
    m_atrScalping.Deinit();
    m_tradeManager.Deinit();
    m_scalpCache.Cleanup();
    UncertaintyDeinit();

    // RegistryAggregator owns the strategy registry and the other sub-registries
    m_registryAggregator.Deinitialize();

    CleanupAISubsystems();

    CEnhancedErrorHandler::DestroyInstance();

    if(CheckPointer(m_pythonBridge) == POINTER_DYNAMIC)
    {
        delete m_pythonBridge;
        m_pythonBridge = NULL;
    }

    if(CheckPointer(m_dashboardBridge) == POINTER_DYNAMIC)
    {
        delete m_dashboardBridge;
        m_dashboardBridge = NULL;
    }

    if(CheckPointer(m_signalDiagnostics) == POINTER_DYNAMIC)
    {
        m_signalDiagnostics.Shutdown();
        delete m_signalDiagnostics;
        m_signalDiagnostics = NULL;
    }
}

void InitializeStrategyConfigs() { CStrategyConfigBuilder::Initialize(m_config); }

// Initialize from config only: the orchestrator creates and owns every manager.
bool Initialize(const SOrchestratorConfig& config)
{
    // Read now, before anything can fail; apply after CUnifiedRiskManager::Initialize, which
    // resets peak equity, breach count and both halts. The crash file is a record: never delete it.
    m_recoveryStateLoaded = false;
    m_savedEquityBaseline = 0.0;
    m_savedPeakEquity     = 0.0;
    m_savedDDBreachCount  = 0;
    m_savedDDMax          = 0.0;
    m_savedHaltFlags      = 0;
    m_savedTradingDayKey  = 0;

    string savedTimestamp = "";
    if(ReadCrashRecoveryState(CRASH_RECOVERY_STATE_FILE,
    m_savedEquityBaseline, m_savedPeakEquity,
    m_savedDDBreachCount, m_savedDDMax, savedTimestamp,
    m_savedHaltFlags, m_savedTradingDayKey))
    {
        m_recoveryStateLoaded = true;
        PrintFormat("[RECOVERY] Crash recovery state loaded from %s | equityBaseline=%.2f | peakEquity=%.2f | ddBreachCount=%d | ddMax=%.2f%% | haltFlags=%d | dayKey=%d | timestamp=%s | applying after risk manager init",
        CRASH_RECOVERY_STATE_FILE, m_savedEquityBaseline, m_savedPeakEquity, m_savedDDBreachCount,
        m_savedDDMax, m_savedHaltFlags, m_savedTradingDayKey, savedTimestamp);
    }
    else
    {
        PrintFormat("[RECOVERY] No valid crash recovery state found at %s (first run or file corrupted)", CRASH_RECOVERY_STATE_FILE);
    }

m_config = config;

// Structured JSON logger: its own verbosity gate controls what gets written
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

InitializeStrategyConfigs();

// The universe filter uses symbolMaxSpreadPoints, the config knob for this. The 15000-point
// maxEntrySpreadPoints stays where it belongs - a catastrophic-quote backstop at send time.
SSymbolValidationConfig symConfig;
symConfig.maxSpreadPoints = m_config.symbolMaxSpreadPoints;
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

m_managerCount = symbolCount;
ArrayResize(m_enterpriseManagers, symbolCount);
ArrayResize(m_enterpriseManagerSymbols, symbolCount);

for(int i = 0; i < symbolCount; i++)
{
    m_enterpriseManagerSymbols[i] = validatedSymbols[i];
}

// m_activePairs mirrors the validated universe for legacy consumers
ArrayResize(m_activePairs, symbolCount);
ArrayCopy(m_activePairs, validatedSymbols);

if(!InitializeSubsystems())
{
    CleanupOnInitFailure();
    return false;
}

// The registry aggregator must exist BEFORE BuildStrategyRegistry(): its
// GetStrategyRegistry() would return NULL and OnInit would fail silently.
if(!m_registryAggregator.Initialize())
{
    Print("[CRITICAL] RegistryAggregator initialization FAILED");
    return false;
}

if(!InitializeEnterpriseManagers())
{
    CleanupOnInitFailure();
    return false;
}

if(!InitializeAISubsystems())
{
    Print("[CRITICAL] AI subsystem initialization failed");
    CleanupOnInitFailure();
    return false;
}

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

// new can return NULL under memory pressure - guard instead of dereferencing.
m_pythonBridge = new CPythonBridge();
if(m_pythonBridge == NULL)
{
    Print("[CRITICAL] Python Bridge allocation FAILED");
    CleanupOnInitFailure();
    return false;
}
m_pythonBridge.Initialize(
m_config.pythonBridgeEndpoint,
m_config.pythonBridgeMode,
m_config.pythonBridgeRequestTimeoutMs,
m_config.pythonBridgeHeartbeatTimeoutSec,
m_config.pythonBridgeMaxReconnectAttempts,
m_config.pythonBridgeReconnectBackoffMs
);

m_dashboardBridge = new CDashboardBridge();
if(m_dashboardBridge == NULL)
{
    Print("[CRITICAL] Dashboard Bridge allocation FAILED");
    CleanupOnInitFailure();
    return false;
}
m_dashboardBridge.Initialize(
m_config.dashboardEndpoint,
false,
m_config.dashboardControlEnabled,
m_config.dashboardPushIntervalSec,
1000
);
m_dashboardBridge.SetEnabled(m_config.dashboardEnabled);

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

if(!InitializeComponents())
{
    CleanupOnInitFailure();
    return false;
}

    m_systemInitialized = true;
    m_tradingEnabled = true;

    // AutoRegisterStrategies ran before BuildStrategyRegistry populated the registry, so
    // strategies were locked disabled against an empty registry; re-apply its state now.
    for(int mi = 0; mi < ArraySize(m_enterpriseManagers); mi++)
    {
        if(m_enterpriseManagers[mi] != NULL)
            m_enterpriseManagers[mi].SyncEnabledWithRegistry();
    }

    // All cross-manager SetDependencies/SetManagers calls plus their validation live here;
    // a forgotten wiring fails init loudly instead of dereferencing NULL mid-trade.
    WireAndValidateDependencies();
    if(!m_dependenciesValid)
    {
        Print("[CRITICAL] EAOrchestrator: dependency wiring validation FAILED - aborting initialization");
        m_systemInitialized = false;
        m_tradingEnabled = false;
        CleanupOnInitFailure();
        return false;
    }

    m_configReloader.Init("Config/live_overrides.json", 30);
    
    class CRiskConfigCallback : public IConfigCallback
    {
    public:
        virtual void OnConfigChange(string section, string json) override {
            Print("[LIVE-CONFIG] Risk section reloaded");
        }
        virtual string GetSectionName() const override { return "Risk"; }
    };
    
    class CWeightsConfigCallback : public IConfigCallback
    {
    public:
        virtual void OnConfigChange(string section, string json) override {
            Print("[LIVE-CONFIG] Weights section reloaded");
        }
        virtual string GetSectionName() const override { return "Weights"; }
    };
    
    class CThresholdsConfigCallback : public IConfigCallback
    {
    public:
        virtual void OnConfigChange(string section, string json) override {
            Print("[LIVE-CONFIG] Thresholds section reloaded");
        }
        virtual string GetSectionName() const override { return "Thresholds"; }
    };
    
    class CSymbolsConfigCallback : public IConfigCallback
    {
    public:
        virtual void OnConfigChange(string section, string json) override {
            Print("[LIVE-CONFIG] Symbols section reloaded");
        }
        virtual string GetSectionName() const override { return "Symbols"; }
    };
    
    CRiskConfigCallback* riskCb = new CRiskConfigCallback();
    CWeightsConfigCallback* weightsCb = new CWeightsConfigCallback();
    CThresholdsConfigCallback* thresholdsCb = new CThresholdsConfigCallback();
    CSymbolsConfigCallback* symbolsCb = new CSymbolsConfigCallback();
    
    m_configReloader.RegisterCallback(riskCb);
    m_configReloader.RegisterCallback(weightsCb);
    m_configReloader.RegisterCallback(thresholdsCb);
    m_configReloader.RegisterCallback(symbolsCb);
    
    m_riskDashboard.Init(ChartID(), CORNER_RIGHT_UPPER, 10, 10);
    
    m_symbolHealth.Init(30, 120, 3.0, 300, true);
    
    Print("[EAOrchestrator] Initialized with ", symbolCount, " symbol managers");
    return true;
}

bool InitializeSubsystems()
{
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
    // Configure the magic ownership window as early as possible so no consumer evaluates
    // magic numbers against an unset range; re-run below with the real symbol count.
    ConfigureMagicOwnership(m_config.magicNumber, 0);
    m_tradeManager.SetMagicRangeMax(g_magicMax);
    m_tradeManager.SetLogLevel(m_config.logLevel);

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

    // Applied only after the risk manager reset breakers/halts; restoring earlier gets overwritten.
    RestoreRiskRuntimeState();
    m_unifiedRiskManager.SetEAMagicNumber(m_config.magicNumber);
    Print("[INIT] UnifiedRiskManager initialized as single risk authority");

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

m_riskTierManager.SetTier(m_config.riskTier);
m_riskTierManager.ApplyToRiskManager(m_unifiedRiskManager, &m_performanceAnalytics,
m_config.maxDailyRisk, m_config.maxPortfolioRisk,
m_config.maxDrawdown * 0.7, m_config.maxDrawdown,
m_config.dailyLossLimitPercent);

// Wire the correlation engine BEFORE applying the tier to PositionSizer
m_positionSizer.SetCorrelationEngine(m_unifiedRiskManager.GetPortfolioRiskManager().GetCorrelationEngine());
m_positionSizer.SetLogLevel(m_config.logLevel);
m_positionSizer.SetAllowMinLotRoundUp(m_config.allowMinLotRoundUp);
m_positionSizer.SetMinLotRiskMultiplier(m_config.minLotRiskMultiplier);

m_riskTierManager.ApplyToPositionSizer(m_positionSizer, m_config.maxRiskPerTrade);
m_riskTierManager.ApplyToTradeManager(m_tradeManager);

m_equityCurveManager = new CEquityCurveManager(m_config.equityCurveEmaPeriod, m_config.equityCurveReductionFactor, 1.0);
if(m_equityCurveManager != NULL)
PrintFormat("[RISK] EquityCurveManager initialized with emaPeriod=%d", m_config.equityCurveEmaPeriod);
else
Print("[RISK] WARNING: Failed to create EquityCurveManager — equity curve sizing disabled");

// Basket equity stop: configure before the trading loop
m_basketEquityStop.Configure(m_config.basketEquityStopEnabled,
                             m_config.basketEquityStopDrawdownPct,
                             m_config.basketEquityStopCloseOnBreach,
                             GetPointer(m_tradeManager), (int)m_config.magicNumber);

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

m_unifiedRiskManager.ConfigureClusterGovernance(m_config.enableClusterRiskGovernance,
MathMax(1, m_config.riskMaxConcurrentPerCluster),
MathMax(0.1, m_config.riskMaxClusterExposurePct),
m_config.enableClusterMutex);
m_unifiedRiskManager.SyncClusterPositionCounts();

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

m_magicNumberAllocator.Initialize((int)m_config.magicNumber, MAGIC_SYMBOL_MULTIPLIER);
if(m_config.multiAssetProfilerEnabled)
{
    CDerivAssetProfiler* derivProfiler = m_multiAssetProfiler.GetDerivProfiler();
    if(derivProfiler != NULL)
    {
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

if(m_config.enableSessionWeights)
{
    m_sessionWeightManager.Initialize(true, m_config.sessionDSTOffsetHours);
    PrintFormat("[INIT] SessionWeightManager initialized — session-aware adjustments ENABLED (DST offset=%d hours)", m_config.sessionDSTOffsetHours);
}
else
{
    Print("[INIT] SessionWeightManager disabled");
}

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

if(m_config.enableFamilyWeightMatrix)
{
    m_familyWeightMatrix.Initialize();
    Print("[INIT] FamilyStrategyWeightMatrix initialized — per-family cluster weighting ENABLED");
}
else
{
    Print("[INIT] FamilyStrategyWeightMatrix disabled");
}

// No magic-range arguments here: with an empty universe they yielded [base, 13], so every
// no-SL position looked external. Ownership resolves through CMagicRange, set below.
m_unprotectedTracker.Initialize(&m_tradeManager, &m_unifiedRiskManager,
m_config.unprotectedRemediationIntervalSec, m_config.unprotectedMaxRestoreAttempts);

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
{
    SSafeModeConfig announced = m_safeMode.GetConfig();
    PrintFormat("[INIT] Conservative safe mode ENABLED | enforced: minConfidence>=%.2f, minVoters>=%d, quorum>=%.2f, spread<=%.2f*ATR, noStacking(per-symbol cap -> %d) | not enforced: tradeOnlyKillZones (FX-session hours; the live roster is 24/7 synthetics the session filter exempts) and avoidNewsEvents (no calendar feed)",
                announced.minConfidence, announced.minVoters, announced.minQuorumThreshold,
                announced.maxSpreadATRRatio, 1);
}
}

// Pass the allocator's max cluster code so the dynamic magic-number range is exact
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
    // The loss guard's daily-loss circuit breaker compares realised losses against
    // maxDailyRisk x its own trigger percent; without this writer it could never arm.
    m_lifecycleManager.SetDailyRiskBudgetPercent(m_config.maxDailyRisk);
    PrintFormat("[INIT] PositionLifecycleManager initialized (Blueprint R6a) | dailyRiskBudget=%.2f%% of equity",
                m_config.maxDailyRisk);
    }
    else
    Print("[INIT] WARNING: PositionLifecycleManager initialization failed");

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

if(m_diagnosticsManager.Initialize(&m_unifiedRiskManager, &m_riskTierManager, &m_compoundingTierManager, m_config.heartbeatInterval, (ENUM_LOG_VERBOSITY)m_config.logVerbosity))
{
    m_diagnosticsManager.SetScalpEngine(&m_scalpEngine);
    m_diagnosticsManager.SetFullMarginMode(&m_fullMarginMode);
    m_diagnosticsManager.SetSafeMode(&m_safeMode);
    m_diagnosticsManager.SetAIConfig(m_config.enableAIMode, m_config.enableNeuralNetwork, m_config.enableNNOnlineTraining,
                                                 m_config.enableTransformer, m_config.enableEnsemble, m_config.enableOnnxAI);
    m_diagnosticsManager.SetRiskTier(m_config.riskTier);
        if(m_config.enableSessionWeights)
        {
            m_diagnosticsManager.SetSessionWeightManager(&m_sessionWeightManager);
        }
                        if(m_config.enableSkewStepAnalyzer)
                        {
                            m_diagnosticsManager.SetSkewStepAnalyzer(&m_skewStepAnalyzer);
                        }
                        if(m_config.enableFamilyWeightMatrix)
                        {
                            m_diagnosticsManager.SetFamilyWeightMatrix(&m_familyWeightMatrix);
                        }
                        Print("[INIT] DiagnosticsManager initialized (Blueprint R6b)");
}
else
Print("[INIT] WARNING: DiagnosticsManager initialization failed");

m_tickSafetyMonitor.SetMinFreeMarginPercent(20.0);
m_tickSafetyMonitor.SetMinMarginLevel(150.0);
m_tickSafetyMonitor.SetEmergencyStop(false);

m_spikeMonitor.Initialize(m_tradeManager, m_unifiedRiskManager, m_tickSafetyMonitor);

if(m_config.enableAIMode)
{
    Print("[AI] Initializing AI subsystems...");

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

if(m_config.enableScalpEngine)
{
    if(!m_scalpEngine.Initialize(&m_tradeManager, &m_unifiedRiskManager, &m_positionSizer, &m_riskTierManager))
    Print("[SCALP-ENGINE] WARNING: Failed to initialize");
else
{
    m_scalpEngine.SetMagicNumber(m_config.magicNumber);
    m_scalpEngine.SetAsyncMode(m_config.scalpAsyncMode);
    m_scalpEngine.SetMaxLatencyMs(m_config.scalpMaxLatencyMs);

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
    // Must stay 9150: the old hardcoded 9000 collides with DERIV_CRASH_BOOM's family
    // offset, so spike-hunter orders could share magics with crash-boom orders.
    spikeConfig.magicOffset              = 9150;
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
        Print("[SPIKE-HUNTER] Initialized with ", m_managerCount, " symbols",
              " | PARKED: not wired into the tick loop (documented-dormant; ProcessTick has no caller)");
    }
else
Print("[SPIKE-HUNTER] Initialization FAILED");
}

if(m_config.multiAssetProfilerEnabled)
{
    Print("[MULTI-ASSET-PROFILER] Initializing multi-asset class auto-detection...");

    // Re-bind the shared global profiler to THIS instance BEFORE any consumer touches it: this
    // re-runs at runtime under multi-instance deployment, and a stale global is an invalid pointer.
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

                g_multiAssetProfiler = &m_multiAssetProfiler;

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
                Print("[GRID-RECOVERY] Initialized for mean-reversion families",
              " | PARKED: not wired into the tick loop (documented-dormant; ProcessTick has no caller)");
            }
        else
        Print("[GRID-RECOVERY] Initialization FAILED");
    }

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
        Print("[ATR-SCALP] Initialized for between-spike families",
              " | PARKED: not wired into the tick loop (documented-dormant; ProcessTick has no caller)");
    }
else
Print("[ATR-SCALP] Initialization FAILED");
}
}

// Batch 178: three engines take an enable input that defaults ON, initialize, register their
// symbols and deinit -- and have no tick-loop caller, so they open nothing. Each prints its own
// PARKED line above, but the "[INIT] ... enabled" lines around them read as live trading, so name
// the whole set once with the input responsible for each.
string parkedEngines = "";
if(m_config.spikeHunterEnabled)
parkedEngines += (parkedEngines == "" ? "" : ", ") + "SPIKE-HUNT (InpSpikeHunterEnabled)";
if(m_config.gridRecoveryEnabled)
parkedEngines += (parkedEngines == "" ? "" : ", ") + "GRID-RECOVERY (InpGridRecoveryEnabled)";
if(m_config.atrScalpingEnabled)
parkedEngines += (parkedEngines == "" ? "" : ", ") + "ATR-SCALP (InpATRScalpingEnabled)";
PrintFormat("[ENGINE-STATUS] tick-loop driver: %s | initialized but parked, no ProcessTick caller, opens zero trades: %s",
            m_config.enableScalpEngine ? "FAST-SCALP" : "none",
            parkedEngines == "" ? "none" : parkedEngines);

m_diagnosticsManager.SetDerivProfiler(m_multiAssetProfiler.GetDerivProfiler());
m_diagnosticsManager.SetMultiAssetProfiler(&m_multiAssetProfiler);
string profilerSymbols[];
ArrayResize(profilerSymbols, m_managerCount);
for(int i = 0; i < m_managerCount; i++)
profilerSymbols[i] = m_enterpriseManagerSymbols[i];
m_diagnosticsManager.SetSymbols(profilerSymbols, m_managerCount);

g_multiAssetProfiler = &m_multiAssetProfiler;

Print("[MULTI-ASSET-PROFILER] Batch 103 initialization complete");
}
return true;
}

private:

// Emits a uniform [INIT-FAIL] diagnostic for a missing dependency; returns whether it was present.
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

// Centralized dependency-wiring pass plus init-time validation: every cross-manager
// SetDependencies/SetManagers call lives here.
// Ordering: MUST run after m_registryAggregator.Initialize() (so GetNeuralNetRegistry() is live)
// and after InitializeSubsystems()/InitializeComponents(); called exactly once, at the end of Initialize().
// Sets m_dependenciesValid only when every required dependency is non-NULL; otherwise OnInit fails.
void WireAndValidateDependencies()
{
    m_dependenciesValid = false;

    // Risk/sizer/trade/analytics/attribution/position managers are value sub-objects, so
    // GetPointer() yields a stable pointer. Only the Deriv profiler and the neural-net registry
    // (owned by the registry aggregator) are genuinely nullable.
    CUnifiedRiskManager*      riskManager     = GetPointer(m_unifiedRiskManager);
    CPositionSizer*           positionSizer   = GetPointer(m_positionSizer);
    CTradeManager*            tradeManager    = GetPointer(m_tradeManager);
    CPerformanceAnalytics*    perfAnalytics   = GetPointer(m_performanceAnalytics);
    CTradeAttributionManager* attributionMgr  = GetPointer(m_attributionManager);
    CPositionManager*         positionManager = GetPointer(m_positionManager);
    CDerivAssetProfiler*      derivProfiler   = m_multiAssetProfiler.GetDerivProfiler();
    CNeuralNetRegistry*       neuralRegistry  = m_registryAggregator.GetNeuralNetRegistry();

    // CandidateBuilder: none of these deps are set by its Initialize(), so they must be wired here.
    m_candidateBuilder.SetDependencies(riskManager, positionSizer, tradeManager,
                                       perfAnalytics, derivProfiler);

    // TradeExecutor: same rule - its Initialize() sets none of these deps.
    m_tradeExecutor.SetDependencies(tradeManager, attributionMgr,
                                    positionManager, neuralRegistry);

    // SetPositionManager takes a reference, so pass the sub-object directly.
    m_attributionManager.SetPositionManager(m_positionManager);

    // Lifecycle manager gets the per-symbol enterprise managers, only once it is up.
    if(m_lifecycleManager.IsInitialized())
    {
        m_lifecycleManager.SetManagers(m_enterpriseManagers, m_enterpriseManagerSymbols,
                                       ArraySize(m_enterpriseManagers));
    }

    // DiagnosticsManager takes the per-symbol enterprise managers (consensus diagnostics).
    m_diagnosticsManager.SetManagers(m_enterpriseManagers, ArraySize(m_enterpriseManagers));

    // Status reporter: heartbeat status text only, no trading impact. Slot 0 is passed only
    // once the manager array is populated (the reporter NULL-checks it either way).
    m_statusReporter.SetManagers(GetPointer(m_registryAggregator),
                                 GetPointer(m_liveAuthority),
                                 positionManager,
                                 (ArraySize(m_enterpriseManagers) > 0 ? m_enterpriseManagers[0] : NULL));

    // Every check runs (no short-circuit) so a misconfigured build reports ALL missing deps at once.
    bool ok = true;

    ok = RequireDependency(riskManager     != NULL, "CandidateBuilder", "CUnifiedRiskManager")   && ok;
    ok = RequireDependency(positionSizer   != NULL, "CandidateBuilder", "CPositionSizer")        && ok;
    ok = RequireDependency(tradeManager    != NULL, "CandidateBuilder", "CTradeManager")         && ok;
    ok = RequireDependency(perfAnalytics   != NULL, "CandidateBuilder", "CPerformanceAnalytics") && ok;
    ok = RequireDependency(derivProfiler   != NULL, "CandidateBuilder", "CDerivAssetProfiler")   && ok;

    ok = RequireDependency(tradeManager    != NULL, "TradeExecutor", "CTradeManager")            && ok;
    ok = RequireDependency(attributionMgr  != NULL, "TradeExecutor", "CTradeAttributionManager") && ok;
    ok = RequireDependency(positionManager != NULL, "TradeExecutor", "CPositionManager")         && ok;
    ok = RequireDependency(neuralRegistry  != NULL, "TradeExecutor", "CNeuralNetRegistry")       && ok;

    ok = RequireDependency(positionManager != NULL, "TradeAttributionManager", "CPositionManager") && ok;

    // These two take the enterprise manager array rather than individual collaborators.
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
    m_signalGenerator.Initialize(m_enterpriseManagers, m_enterpriseManagerSymbols, m_managerCount, &m_consensusCache);
    Print("[INIT] SignalGenerator initialized");

    if(!m_candidateBuilder.Initialize(&m_positionSizer, &m_unifiedRiskManager, &m_riskTierManager,
    &m_compoundingTierManager, &m_familyWeightMatrix,
    &m_sessionWeightManager, &m_skewStepAnalyzer))
    {
        Print("[CRITICAL] CandidateBuilder initialization FAILED");
        return false;
    }
    Print("[INIT] CandidateBuilder initialized");

    // Configure() must be called explicitly: without it the per-symbol position caps stay at 0
    // (CheckSymbolPositionLimit bypassed) and minLotRiskMultiplier ignores the configured input.
    // Safe mode's noStacking is enforced through this cap rather than a second counting gate:
    // CheckSymbolPositionLimit already owns "how many positions may this symbol hold".
    int safeModeMaxPositionsPerSymbol = m_config.maxPositionsPerSymbol;
    if(m_config.riskTier == RISK_TIER_CONSERVATIVE && m_safeMode.IsInitialized()
       && m_safeMode.GetConfig().noStacking)
    {
        safeModeMaxPositionsPerSymbol = 1;
        PrintFormat("[SAFE-MODE] noStacking enforced through the per-symbol position cap | max_positions_per_symbol %d -> 1",
                    m_config.maxPositionsPerSymbol);
    }
    m_candidateBuilder.Configure(2.0, 1.5, 5.0,
                                 0.15, m_config.minLotRiskMultiplier, m_config.aiDrawdownSizingLimit,
                                 true, safeModeMaxPositionsPerSymbol, m_config.portfolioMaxPositionsPerSymbol,
                                 m_config.hybridGateRelaxAfterCycles, m_config.aiStandaloneMinConfidence,
                                 m_config.aiStandaloneRelaxedConfidence);

    Print("[INIT] TradeExecutor initialized");

    if(m_config.enableLiveAuthorityGate)
    {
        Print("[INIT] LiveAuthorityResolver initialized");
    }

    if(!m_positionManager.Initialize(&m_tradeManager, NULL, &m_riskTierManager,
    &m_safeMode, &m_fullMarginMode, NULL,
    (int)m_config.magicNumber))
    {
        Print("[CRITICAL] PositionManager initialization FAILED");
        return false;
    }
    Print("[INIT] PositionManager initialized");

    m_signalDiagnostics = new CSignalDiagnostics();
    if(m_signalDiagnostics != NULL)
    {
        if(m_signalDiagnostics.Initialize(10000, 3))
        {
            Print("[INIT] SignalDiagnostics initialized");
            CMathematicalEngineRegistry* mathReg = m_registryAggregator.GetMathRegistry();
            if(mathReg != NULL)
            {
                mathReg.SetSignalDiagnostics(m_signalDiagnostics);
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

// The hub NULL-checks the math registry internally.
m_mathEngineHub.RegisterMathEngines(m_registryAggregator.GetMathRegistry());

m_mathEngineHub.RegisterInstitutionalEngines(m_registryAggregator.GetInstitutionalRegistry(),
m_enterpriseManagerSymbols, m_managerCount);

if(m_config.enableAIMode && (m_config.enableNeuralNetwork || m_config.enableTransformer ||
m_config.enableEnsemble || m_config.enableOnnxAI))
{
    // NNs are owned by adapters registered with the strategy managers; the neural-net registry
    // manages them internally via GetOrCreateNeuralNet.
}

CDrawingManagerRegistry* drawReg = m_registryAggregator.GetDrawingRegistry();
if(drawReg != NULL)
drawReg.RegisterAll(m_drawingManagers, m_drawingManagerSymbols,
ArraySize(m_drawingManagers));

CSymbolStateTracker* tracker = m_registryAggregator.GetSymbolStateTracker();
if(tracker != NULL)
    tracker.Initialize(m_enterpriseManagerSymbols, m_managerCount);

// Do NOT call CStrategyRegistry::Initialize()/Reset() here: it wipes the descriptors populated
// by BuildStrategyRegistry(), orphans every manager's view and leaves all strategies disabled.

return true;
}

void InitializeMathematicalEngines()
{
    m_mathEngineHub.InitializeMathematicalEngines(m_config,
                                                  m_registryAggregator.GetMathRegistry(),
                                                  m_enterpriseManagerSymbols,
                                                  m_managerCount,
                                                  m_signalDiagnostics);
}

void InitializeInstitutionalEngines()
{
    m_mathEngineHub.InitializeInstitutionalEngines(m_config,
                                                   m_registryAggregator.GetInstitutionalRegistry(),
                                                   m_enterpriseManagerSymbols,
                                                   m_managerCount);
}

bool InitializeEnterpriseManagers()
{
    if(m_managerCount <= 0)
    {
        Print("[ERROR] No symbols to initialize enterprise managers for");
        return false;
    }

    // Pre-allocates the per-symbol engine arrays (resize + NULL-init + cursor reset)
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

// The magic ownership window is sized once the universe is known, then asserted before it is
// trusted: orders ship with an asset-class offset of up to 9999 (CDerivAssetProfiler::DERIV_UNKNOWN),
// so a window sized only by symbolCount*100 would exclude every position this EA opens.
int symbolCount = ArraySize(m_enterpriseManagerSymbols);
ConfigureMagicOwnership(m_config.magicNumber, symbolCount);
long magicRangeMax = g_magicMax;
m_tradeManager.SetMagicRangeMax(magicRangeMax);

int maxShippedOffset = 0;
for(int ms = 0; ms < symbolCount; ms++)
{
    if(m_enterpriseManagerSymbols[ms] == "") continue;
    int off = m_multiAssetProfiler.GetMagicOffset(m_enterpriseManagerSymbols[ms]);
    if(off > maxShippedOffset) maxShippedOffset = off;
}
if(!ValidateMagicOwnershipCoverage(m_config.magicNumber, maxShippedOffset))
{
    Print("[CRITICAL] Magic ownership window does not cover the offsets this EA ships with - refusing to trade");
    return false;
}
for(int mi = 0; mi < ArraySize(m_enterpriseManagers); mi++)
{
    if(m_enterpriseManagers[mi] != NULL)
    {
        m_enterpriseManagers[mi].SetManagedMagicRangeMax((long)magicRangeMax);
        m_enterpriseManagers[mi].SetDiagnosticsManager(&m_diagnosticsManager);
        m_enterpriseManagers[mi].SetAttributionManager(&m_attributionManager);
        // Profilers drive asset-class-based engine weighting
        if(m_config.multiAssetProfilerEnabled)
        {
            m_enterpriseManagers[mi].SetDerivProfiler(m_multiAssetProfiler.GetDerivProfiler());
            m_enterpriseManagers[mi].SetMultiAssetProfiler(&m_multiAssetProfiler);
            m_enterpriseManagers[mi].ApplyAssetClassEngineWeights(m_enterpriseManagerSymbols[mi]);
            m_enterpriseManagers[mi].SetFamilyWeightMatrix(&m_familyWeightMatrix);
        }

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
                // Mean Reversion: Hurst engine (regime lockout)
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
                // Statistical Arbitrage: OU engine (half-life filter)
                IStrategy* saStrat = m_enterpriseManagers[mi].GetStrategyByName("Statistical Arbitrage");
                if(saStrat != NULL)
                {
                    CStatisticalArbitrageStrategy* saPtr = dynamic_cast<CStatisticalArbitrageStrategy*>(saStrat);
                    if(saPtr != NULL)
                    {
                        saPtr.SetOUEngine(m_mathEngineHub.GetOUEngine(mathIdx));
                        // The catalog registration path never injects the bridge, so without this
                        // the gate stayed NULL and every signal failed as STATARB_PYTHON_BRIDGE_UNAVAILABLE.
                        CPythonBridge* saBridge = ((g_pythonBridge != NULL && g_pythonBridge.IsConnected())
                                                   ? g_pythonBridge : m_pythonBridge);
                        if(saBridge != NULL)
                            saPtr.SetPythonBridge(saBridge);
                        if(m_config.logLevel >= 3)
                        PrintFormat("[WIRE] OU wired to Statistical Arbitrage | Symbol=%s", sym);
                    }
                }
            }
        }
    }
}
if(m_config.logLevel >= 2)
PrintFormat("[MAGIC-RANGE] base=%I64d | symbols=%d | range_max=%I64d | encoding=BASE+symbolIndex*%d+clusterCode",
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

    // Inject the strategy registry into the manager (not the global singleton)
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

        // Safe mode raises the minimum confidence floor
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

    // Batch 175: safe mode is an override that may only tighten, and ApplyQuorumProfile has just
    // written the profile's own floor, so the clamp belongs after it. minConfluence has no
    // consensus knob to tighten and is not enforced.
    if(m_config.riskTier == RISK_TIER_CONSERVATIVE && m_safeMode.IsInitialized())
    {
        SSafeModeConfig sm = m_safeMode.GetConfig();
        int votersAfterProfile = MathMax(1, manager.GetMinQuorum());
        manager.SetMinQuorum(MathMax(votersAfterProfile, sm.minVoters));
        manager.SetIntrabarMinQuorum(MathMax(1, MathMax(manager.GetIntrabarMinQuorum(), sm.minVoters)));
        double thrAfterProfile = manager.GetQuorumThreshold();
        manager.SetQuorumThreshold(MathMax(thrAfterProfile, sm.minQuorumThreshold));
        filters.regimeCostGate.maxSpreadToAtrRatio =
            MathMax(0.01, MathMin(filters.regimeCostGate.maxSpreadToAtrRatio, sm.maxSpreadATRRatio));
        manager.SetPipelineFilters(filters);
    }

    // Batch 175: CPostConsensusValidator::SetValidatorConfig existed with no call site anywhere in
    // the repository, so every arm below ran on the constructor's defaults. InpEnableOFIProxy and
    // InpEnableVPINFilter were therefore OFF regardless of the operator's inputs (which is also why
    // the VPIN veto armed in Batch 174 could not reach a live session), and the quality floors were
    // 0.72/0.75 rather than the configured 0.70/0.68.
    // The spread cutoff is the one value that must not come straight from config: the configured
    // InpHardSpreadCutoffPoints default (200) is below synthetic-index spreads of 1,727-11,140
    // points and would veto the entire synthetic book, which is the failure the constructor
    // documented by parking at max entry spread. Floor it at the symbol's admitted entry spread.
    double validatorHardSpreadCutoff = MathMax(m_config.hardSpreadCutoffPoints, m_config.maxEntrySpreadPoints);
    manager.SetValidatorConfig(MathMax(0.0, MathMin(1.0, m_config.validatorIntrabarMinQuality)),
                               MathMax(0.0, MathMin(1.0, m_config.validatorNewBarMinQuality)),
                               validatorHardSpreadCutoff,
                               m_config.spikeHunterEnabled,
                               m_config.enableOFIProxy,
                               m_config.enableVPINFilter,
                               VALIDATOR_BASE_SPREAD_ATR_RATIO,
                               VALIDATOR_SYNTHETIC_SPREAD_ATR_RATIO);
    PrintFormat("[VALIDATOR-CONFIG] %s | quality_newbar=%.3f quality_intrabar=%.3f | hard_spread_cutoff=%.1fpts (input=%.1f entry_max=%.1f) | OFI=%s VPIN=%s | spread_atr=%.2f/%.2f | spike_arm=%s",
                symbol,
                MathMax(0.0, MathMin(1.0, m_config.validatorIntrabarMinQuality)),
                MathMax(0.0, MathMin(1.0, m_config.validatorNewBarMinQuality)),
                validatorHardSpreadCutoff,
                m_config.hardSpreadCutoffPoints,
                m_config.maxEntrySpreadPoints,
                m_config.enableOFIProxy ? "ON" : "OFF",
                m_config.enableVPINFilter ? "ON" : "OFF",
                VALIDATOR_BASE_SPREAD_ATR_RATIO,
                VALIDATOR_SYNTHETIC_SPREAD_ATR_RATIO,
                m_config.spikeHunterEnabled ? "set(no-op branch)" : "OFF");
    PrintFormat("[ENTERPRISE-CONFIG] %s | class=%s | profile=%s | trend_filter=%s | quorum_threshold=%.2f | min_live_voters=%d | support_floor_newbar=%.2f | support_floor_intrabar=%.2f | sparse_single_voter=%s | sparse_quality=%.2f | sparse_support=%.2f | sparse_ready=%.2f | intrabar_dynamic_quorum_input=%s | single_voter_min_conf=%.2f | pipeline_min_conf=%.2f | validator_arms=spread_cutoff+exogenous_atr+quality+ofi+vpin | newbar(conf>=%.2f confluence>=%d quality>=%.2f) intrabar(conf>=%.2f confluence>=%d quality>=%.2f) — only the two quality floors are enforced; the confidence and confluence floors are printed here and gate nothing | deadlock_diag_interval=%ds | intrabar_conf_cap=%.2f",
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

    // Intrabar policies must be set from the config array before auto-registration
    for(int si = 0; si < m_config.strategyConfigCount; si++)
    {
        manager.SetStrategyIntrabarPolicyConfig(si, m_config.strategyIntrabarConfigs[si].defaultPolicy);
    }
    // Strategies beyond strategyConfigCount will use defaults from GetIntrabarPolicy lambda


    manager.AutoRegisterStrategies(strategyFlags);
    ApplyInstitutionalStrategyGovernance(manager, symbol, strategyFlags);
    ApplyStrategyWeights(manager, symbol, strategyFlags);

    // Array is pre-sized in Initialize(); place the manager at its symbol index. Do NOT append:
    // appending leaves indices 0..11 NULL, so CSignalGenerator sees an all-NULL manager array.
    m_enterpriseManagers[assignIndex] = manager;
    // m_enterpriseManagerSymbols[assignIndex] is already populated by the Initialize() pre-fill.

    // The hub creates the per-symbol engines and advances its own engine cursor.
    m_mathEngineHub.CreateEnginesForSymbol(m_config, symbol);

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
                draw.SetMaxObjects(MathMin(450, m_config.maxVisualObjects));

                int dSize = ArraySize(m_drawingManagers);
                ArrayResize(m_drawingManagers, dSize + 1);
                ArrayResize(m_drawingManagerSymbols, dSize + 1);
                m_drawingManagers[dSize] = draw;
                m_drawingManagerSymbols[dSize] = symbol;

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

// Forwarders to COrchestratorStrategyFlagBuilder, COrchestratorSymbolClassifier and COrchestratorIntrabarPolicy.

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

// Synthetic lean overrides come from the CDerivAssetProfiler family profile, not indices
ENUM_INTRABAR_POLICY GetIntrabarPolicy(const string symbol, int strategyIndex, const bool& strategyFlags[])
{
    return COrchestratorIntrabarPolicy::GetIntrabarPolicy(
        m_config, GetPointer(m_multiAssetProfiler), symbol, strategyIndex, strategyFlags);
}

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
    // Intentional pass-through: no governance layer is active; consensus weights the strategies.
}

void ApplyStrategyWeights(CEnterpriseStrategyManager* manager, const string& symbol, const bool& strategyFlags[])
{
    // Intentional pass-through: weights apply via the consensus/role-cluster pipeline; a step here would change behaviour.
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

// Intentionally shadows the same-named free function in Core/Utils/Instruments.mqh.
bool IsSyntheticIndexSymbolName(const string& symbol)
{
    return COrchestratorSymbolClassifier::IsSyntheticIndexSymbolName(symbol);
}

bool IsForexSymbol(const string& symbol)
{
    return COrchestratorSymbolClassifier::IsForexSymbol(symbol);
}

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

    // Strict EA mode: refuse to start when the requested mode degraded
    if(m_config.strictEAMode && effectiveMode != m_config.eaMode)
    {
        PrintFormat("[CRITICAL] Strict EA Mode enabled but mode degraded from %s to %s",
        EAModeToString(m_config.eaMode), EAModeToString(effectiveMode));
        return false;
    }

    // The live-authority gate must be configured explicitly once mode resolution has settled;
    // otherwise it runs on constructor defaults and ignores eaMode and aiStandaloneMinConfidence.
    // otherwise it runs on constructor defaults and ignores every InpAuthority* input.
    // authorityMinConfluence is the only threshold here without a config field.
    m_liveAuthority.Configure(effectiveMode,
                              m_config.aiStandaloneMinConfidence,
                              m_config.aiBootstrapRiskMultiplier,
                              2,   // authorityMinConfluence
                              m_config.authorityMinExpectancyR,
                              m_config.authorityMinProfitFactor,
                              m_config.authorityMinSamples,
                              m_config.authorityMinCostScore,
                              m_config.authorityMinReadinessScore,
                              m_config.authorityMinContextScore,
                              m_config.aiPromotedRiskMultiplier);

    PrintFormat("[STRATEGY-REGISTRY] %s", strategyRegistry.BuildStatusReport());
    return true;
}

void LogAIRuntimeTopology()
{
    // __FILE__ is passed here so [RUNTIME-FINGERPRINT] keeps printing this file's name.
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
    // Do NOT delete the neural nets: they are owned by the adapters, which the strategy
    // managers own. Clear the pointers only.
    for(int i = 0; i < ArraySize(m_neuralNetStrategies); i++)
    {
        m_neuralNetStrategies[i] = NULL;
    }
    ArrayResize(m_neuralNetStrategies, 0);
    ArrayResize(m_neuralNetStrategySymbols, 0);
    m_attributionManager.ClearAll();
}

    // Catalog-driven AI adapter registration: one loop over the CAT_KIND_AI rows of StrategyCatalog.mqh.

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

    // Gates that run BEFORE the factory call. Returning false skips the row;
    // alreadyLive=true means this symbol already holds the adapter.
    bool CatalogAIPreCreateGate(const ENUM_CATALOG_AI k, const string symbol, bool &alreadyLive)
    {
        alreadyLive = false;

        switch(k)
        {
            case CAT_AI_NEURAL_NET:
            {
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
                // Backoff/disable state and the retry log line live in CONNXInitManager;
                // still in backoff => skip this attempt.
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

    // Prepares the adapter after the factory call, before registration. The caller owns
    // `adapter` until this returns true.
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

    // Shared registration tail: weight resolution, RegisterStrategy, bookkeeping, ONNX hooks.
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
            // RegisterStrategy() already deleted the adapter on failure; do not delete it again.
            if(k == CAT_AI_ONNX)
                HandleONNXInitFailure(symbol);
            return false;
        }

        if(stratRegLocal != NULL)
            stratRegLocal.MarkRegistered(name, true);

        if(k == CAT_AI_ONNX)
            m_onnxInit.RegisterSuccess();

        Print("[AI-MODE] ", name, " ready for ", symbol);
        return true;
    }

    // Registers every enabled AI catalog row for one symbol; returns how many are live.
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

            // The adapter owns its model; created through the strategy factory.
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

    // ONNX failure entry point; attempt counting, the 3-failure disable threshold and logging live in CONNXInitManager.
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

// The engine arrays are owned by COrchestratorMathEngineHub; the manager array and symbol
// list are still owned here and are passed through.
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

    // Drop the status reporter's borrowed slot-0 pointer so it cannot outlive the deleted
    // manager; heartbeat status then skips that report section.
    m_statusReporter.ClearEnterpriseManager();
}

void OnTick()
{
    m_callCount++;

    // Emergency close request from the circuit breaker
    if(m_unifiedRiskManager.IsEmergencyCloseRequested())
    {
        PrintFormat("[RISK-EMERGENCY] Emergency close requested - closing all positions");
        m_tradeManager.CloseAllPositions("", "Emergency close", m_config.emergencyFlattenAllAccountPositions);
        m_unifiedRiskManager.ResetEmergencyCloseRequested();
    }

    // Basket equity stop close-on-breach sweep (magic-filtered; manual positions safe)
    if(m_basketEquityStop.ShouldCloseBasket())
        m_basketEquityStop.CloseBasket();

    ProcessTickSafetyLoop();

    // VPIN/OFI tick feed, throttled to 200 ms inside the hub. The loop bound stays
    // ArraySize(m_mathEngineSymbols), which the hub exposes as GetSymbolCount().
    m_mathEngineHub.FeedMicrostructure(m_mathEngineHub.GetSymbolCount());

    // Feed tick data to Skew Step Analyzer (throttled to 500 ms)
    if(m_config.enableSkewStepAnalyzer && m_skewStepAnalyzer.IsInitialized())
    {
        static uint s_lastSkewStepFeed = 0;
        uint nowMs = GetTickCount();
        if(nowMs - s_lastSkewStepFeed >= 500)
        {
            CDerivAssetProfiler* derivProf = m_multiAssetProfiler.GetDerivProfiler();
            if(derivProf != NULL)
            {
                for(int i = 0; i < ArraySize(m_enterpriseManagerSymbols); i++)
                {
                    string sym = m_enterpriseManagerSymbols[i];
                    ENUM_DERIV_FAMILY family = derivProf.DetectFamily(sym);
                    if(family == DERIV_SKEW_STEP)
                    {
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

    // Fast-path scalp evaluation on ticks (dual-path architecture), throttled to 1 s:
    // ShouldEnterScalp does indicator/ATR/cost/risk work for every symbol in the universe.
    static uint s_lastScalpFastPathMs = 0;
    uint scalpNowMs = GetTickCount();
    if(m_config.enableScalpEngine && m_scalpEngine.IsInitialized()
       && scalpNowMs - s_lastScalpFastPathMs >= 1000)
    {
        s_lastScalpFastPathMs = scalpNowMs;
        ProcessScalpFastPath();
    }
}

void OnTimer()
{
    // Early exit during shutdown: released resources must not be touched.
    if(m_shuttingDown)
    return;

    // Emergency close request from the circuit breaker
    if(m_unifiedRiskManager.IsEmergencyCloseRequested())
    {
        PrintFormat("[RISK-EMERGENCY] Emergency close requested - closing all positions");
        m_tradeManager.CloseAllPositions("", "Emergency close", m_config.emergencyFlattenAllAccountPositions);
        m_unifiedRiskManager.ResetEmergencyCloseRequested();
    }

    // Basket equity stop close-on-breach sweep (magic-filtered; manual positions safe)
    if(m_basketEquityStop.ShouldCloseBasket())
        m_basketEquityStop.CloseBasket();

    bool timerError = false;
    string timerErrorMsg = "";

    datetime now = TimeCurrent();

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

            if(m_aiBrainReady)
            aiStatus += "TF:RDY | ";
        else
        aiStatus += "TF:OFF | ";

        if(m_aiEngineReady)
        aiStatus += "NN:RDY | ";
    else
    aiStatus += "NN:OFF | ";

    int activeAIModels = 0;
    if(aiStratReg != NULL)
    activeAIModels = aiStratReg.GetActiveAICount();
    aiStatus += "ENS:" + IntegerToString(activeAIModels) + "/4 | ";

    aiStatus += "MEM:OPTIMIZED";

    Print(aiStatus);
}

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
        if(bridgeStatus.version.version != "")
        bridgeStatusStr += "VER:" + bridgeStatus.version.version + " | ";
    else
    bridgeStatusStr += "VER:UNKNOWN | ";

    bridgeStatusStr += "REQS:" + IntegerToString(bridgeStatus.request_count) + " | ";
    bridgeStatusStr += "OK:" + IntegerToString(bridgeStatus.success_count) + " | ";
    bridgeStatusStr += "ERR:" + IntegerToString(bridgeStatus.error_count);

    string corrId = CCorrelationIdGenerator::Generate("PYTHON");
    CJsonLogger::LogInfo("PYTHON-BRIDGE", bridgeStatusStr, "PYTHON_BRIDGE_DASHBOARD", "", corrId, "");
    // AGENTS.md §6: [PYTHON-BRIDGE-DASHBOARD] log signature
    PrintFormat(FMT_PYTHON_BRIDGE_DASHBOARD, bridgeStatusStr);
    }
}

// Set the bridge readiness gate after the first successful health check
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

// Update EquityCurveManager on every timer tick
if(m_equityCurveManager != NULL)
m_equityCurveManager.Update(AccountInfoDouble(ACCOUNT_EQUITY));

// Update basket equity stop peak/DD tracking each timer tick
m_basketEquityStop.Update(AccountInfoDouble(ACCOUNT_EQUITY));

// Bar-level engine updates (Hurst, OU, Grid-Hurst bridge, Kalman, CPD, Four-State, VolTarget).
// m_gridRecovery is a by-value member, so GetPointer() is never NULL.
m_mathEngineHub.UpdateTimerEngines(m_config, GetPointer(m_gridRecovery));

ApplyHurstWeightModifiersToRegime();

// CVaR periodic logging (every 5 minutes)
datetime nowCvar = TimeCurrent();
if(m_lastCvarLogTime == 0 || (nowCvar - m_lastCvarLogTime) >= 300)
{
    double cvarValue = m_unifiedRiskManager.GetPortfolioRiskManager().GetCurrentCVaR();
    double absCvar = MathAbs(cvarValue);
    PrintFormat("[CVAR] Portfolio CVaR=%.2f%% at 95%% confidence", absCvar * 100.0);
    m_lastCvarLogTime = nowCvar;
}

// Periodic indicator handle auto-eviction (every 60 seconds)
static datetime s_lastIndicatorEviction = 0;
if(s_lastIndicatorEviction == 0 || (now - s_lastIndicatorEviction) >= 60)
{
    CIndicatorManager::Instance().ReleaseUnused(300); // Release handles older than 5 minutes
    s_lastIndicatorEviction = now;
}

// Process pending async trade confirmations and timeouts
    m_tradeManager.CheckAsyncTimeouts();

    // Drain the executor's confirmation queue: Execute() queues every fill for
    // history-based resolution, so without this the queue only ever grows.
    m_tradeExecutor.CheckPendingConfirmations();

    // Emit heartbeat diagnostics
    static datetime s_lastHeartbeat = 0;
    if(s_lastHeartbeat == 0 || (now - s_lastHeartbeat) >= m_config.heartbeatInterval)
    {
        m_heartbeat.Emit(GetPointer(m_diagnosticsManager));
        s_lastHeartbeat = now;
    }
    
    m_configReloader.CheckAndReload();
    m_riskDashboard.OnTimer();
    m_symbolHealth.OnTick(_Symbol);
    m_symbolHealth.CheckAllSymbols(m_config.symbolsToTrade);
    
    SUnifiedRiskSnapshot riskSnap = m_unifiedRiskManager.GetSnapshot();
    double portfolioRisk = riskSnap.portfolioRiskPercent;
    double dailyRisk = riskSnap.dailyRiskUsedPercent;
    double drawdown = riskSnap.currentDrawdownPercent;
    int posTotal = GetEAPositionCount();
    int posLimit = m_config.maxPositionsTotal;
    double marginUsed = AccountInfoDouble(ACCOUNT_MARGIN) > 0 ? 
                        (AccountInfoDouble(ACCOUNT_MARGIN) - AccountInfoDouble(ACCOUNT_MARGIN_FREE)) / AccountInfoDouble(ACCOUNT_MARGIN) * 100 : 0;
    double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double unrealized = equity - balance;
    string eaMode = EnumToString(m_config.eaMode);
    
    m_riskDashboard.UpdateMetrics(portfolioRisk, dailyRisk, drawdown, posTotal, posLimit, 
                                  marginUsed, freeMargin, eaMode, equity, balance, unrealized);

    ProcessTradingLogic(true);  // true = called from timer
}

// Update risk parameters from input changes
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

    m_positionSizer.SetAllowMinLotRoundUp(allowMinLotRoundUp);
    m_positionSizer.SetMinLotRiskMultiplier(minLotRiskMultiplier);

    m_compoundingTierManager.SetAutoSwitch(enableCompoundingTiers);

    PrintFormat("[RISK-INPUT-UPDATE] Risk parameters updated | risk=%.1f%% daily=%.1f%% portfolio=%.1f%% dd=%.1f%% dailyLoss=%.1f%% roundUp=%s multiplier=%.1f compounding=%s tier=%d",
        maxRiskPerTrade, maxDailyRisk, maxPortfolioRisk, maxDrawdown, dailyLossLimitPercent,
        allowMinLotRoundUp ? "true" : "false", minLotRiskMultiplier,
        enableCompoundingTiers ? "true" : "false", (int)riskTier);
    }

    bool PreflightChecks(const string corrId)
    {
        if(m_unifiedRiskManager.IsEmergencyCloseRequested())
        {
            PrintFormat("[EMERGENCY-CLOSE] Circuit breaker emergency close requested - closing all positions");
            m_tradeManager.CloseAllPositions("", "Emergency close", m_config.emergencyFlattenAllAccountPositions);
            m_unifiedRiskManager.ResetEmergencyCloseRequested();
            CJsonLogger::ClearCorrelationId();
            return false;
        }

        // Basket equity stop close-on-breach sweep (magic-filtered; manual positions safe)
        if(m_basketEquityStop.ShouldCloseBasket())
            m_basketEquityStop.CloseBasket();

        if(!m_systemInitialized || !m_tradingEnabled)
        {
            CJsonLogger::ClearCorrelationId();
            return false;
        }
    
        return true;
    }

    void RefreshRuntimeState()
    {
        m_unifiedRiskManager.RefreshRuntimeState();

        UpdateDailyProfitTarget();

        UpdateAutoModeSwitch();

        m_unprotectedTracker.AttemptRemediation();

        // Persist circuit-breaker state on the runtime cadence (30 s throttle inside) for crash recovery.
        PersistRiskRuntimeState(false);
    }

    void ProcessAISubsystems()
    {
        // NN online learning is driven via CRegistryAggregator, which owns the CNeuralNetRegistry.
        if(m_config.enableAIMode && m_config.enableNeuralNetwork && m_config.enableNNOnlineTraining)
        {
            m_registryAggregator.TickNeuralNetOnlineLearning();
        }

        if(m_config.enableAIMode && m_aiEngine != NULL)
        {
            m_aiEngine.ProcessAdaptation();
        }

        if(m_aiFeedbackReady)
        {
            m_aiFeedback.CheckAutomaticRetraining();

            SAIModelMetrics aiMetrics = m_aiFeedback.GetCurrentMetrics();
            for(int m = 0; m < ArraySize(m_enterpriseManagers); m++)
            {
                if(m_enterpriseManagers[m] != NULL)
                {
                    // Feeds the AI weight-adaptation sync path back into the managers.
                    if(m_config.enableNeuralNetwork)
                    m_enterpriseManagers[m].UpdateAIPerformanceMetrics("Neural Network AI", aiMetrics);
                    if(m_config.enableTransformer)
                    m_enterpriseManagers[m].UpdateAIPerformanceMetrics("Transformer AI", aiMetrics);
                    if(m_config.enableEnsemble)
                    m_enterpriseManagers[m].UpdateAIPerformanceMetrics("Ensemble AI", aiMetrics);
                    if(m_config.enableOnnxAI)
                    m_enterpriseManagers[m].UpdateAIPerformanceMetrics("ONNX AI", aiMetrics);
                }
            }
        }
    }

    void DetectNewBarsPerSymbol()
    {
        ProcessNewBars();
    }

    void RunSignalEvaluationCycle(const string cycleCorrId)
    {
        GenerateAndProcessSignals(cycleCorrId);
    }

    void PostConsensusFiltering()
    {
        UpdateAIVoteActivity();
    }

    void ManageOpenPositions()
    {
        // The configured exit authority. CPositionManager is never configured and its
        // signal-reversal exit is a stub; it still owns the position-state registry.
        m_lifecycleManager.ManagePositions();

        ProcessClosedPositionsForNNTraining();
    }

    void ProcessTradingLogic(bool fromTimer)
{
    // Generate correlation ID for this trading cycle
    string cycleCorrId = CCorrelationIdGenerator::Generate("CYCLE");
    CJsonLogger::SetCorrelationId(cycleCorrId);
    
    if(!PreflightChecks(cycleCorrId))
    {
        return;
    }

    RefreshRuntimeState();

    // Strategy lifecycle governance: sweep disabling AND re-enabling on a 60 s cadence regardless
    // of AI mode, so a strategy auto-disabled by trade feedback can recover with AI off.
    static datetime s_lastGovernanceSweep = 0;
    datetime nowGov = TimeCurrent();
    if(nowGov - s_lastGovernanceSweep >= 60)
    {
        for(int gi = 0; gi < m_managerCount; gi++)
        {
            if(m_enterpriseManagers[gi] == NULL) continue;
            m_enterpriseManagers[gi].CheckStrategyDisabling();
            m_enterpriseManagers[gi].CheckStrategyReEnabling();
        }
        s_lastGovernanceSweep = nowGov;
    }

    ProcessAISubsystems();

    DetectNewBarsPerSymbol();

    RunSignalEvaluationCycle(cycleCorrId);

    PostConsensusFiltering();

    ManageOpenPositions();
    
    CJsonLogger::ClearCorrelationId();
}

    // Process closed positions and link them to NN predictions for online training.
    void ProcessClosedPositionsForNNTraining()
    {
        // NN diagnostics are not exposed publicly; the guard is the strategy-count check below.
        
        if(ArraySize(m_neuralNetStrategies) == 0)
            return;
        
        ulong positionIds[];
        double profits[];
        string predictionIds[];
        
        int closedCount = m_attributionManager.GetPendingCloseProfits(positionIds, profits, predictionIds);
        if(closedCount <= 0)
            return;
        
        for(int i = 0; i < closedCount; i++)
        {
            string predId = predictionIds[i];
            double profit = profits[i];
            
            if(predId == "")
                continue;
            
            // The prediction ID format is "symbol_timeframe_timestamp".
            for(int nnIdx = 0; nnIdx < ArraySize(m_neuralNetStrategies); nnIdx++)
            {
                CNeuralNetworkStrategy* nn = m_neuralNetStrategies[nnIdx];
                if(nn == NULL || !nn.IsTraining())
                    continue;
                
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
    // Intentional stub, not dead safety equipment: every concern it once routed is LIVE elsewhere.
    //  - Drawdown halt / conservative mode / emergency flatten: CRiskCircuitBreaker (thresholds from
    //    m_config.maxDrawdown) -> CUnifiedRiskManager -> OnTick honors IsEmergencyCloseRequested().
    //    Wiring CSyntheticSpikeMonitor::HandleEmergencyDrawdown here would create a second flatten
    //    authority with unconfigured thresholds.
    //  - Trading-pause expiry: m_spikeMonitor.ReleasePauseIfExpired() runs via the cycle gate (IsPaused).
    //  - Spread / free-margin / margin-level health: CRiskMarginHealth inside CRiskValidationPipeline
    //    plus TradeManager preflight gates; CTickSafetyMonitor stays a passive query API.
    //  - Synthetic tick-rate spike detection (EvaluateSpike): single-symbol (_Symbol) legacy with no
    //    multi-symbol configuration; deliberately not revived with invented thresholds.
}

void FeedMicrostructureEngines()
{
    // VPIN/OFI feed loop and its 200 ms throttle live in the hub.
    m_mathEngineHub.FeedMicrostructure(m_managerCount);

    // Feed tick data to Skew Step Analyzer (throttled to 500 ms)
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

// OnTradeTransaction forwarder: confirms filled async scalp orders into the position tracker (no-op when none pending).
void ProcessScalpDealConfirmed(const ulong dealTicket, const ulong orderTicket)
{
    if(m_config.enableScalpEngine && m_scalpEngine.IsInitialized())
        m_scalpEngine.OnDealConfirmed(dealTicket, orderTicket);
}

// Closed-trade feedback loop: the EA's OnTradeTransaction routes DEAL_ADD events here.
//  1. fan the transaction out to every symbol manager so per-strategy
//     attribution pop / UpdatePerformance / health monitor / auto-disable run;
//  2. feed account-level learners on full closes of EA-owned positions:
//     CPerformanceAnalytics::RecordClosedTrade (sole writer of win-rate/PF/
//     momentum stats consumed by live lot scaling + risk snapshots),
//     loss-guard consecutive-loss accounting, and live-authority outcome
//     learning (PROVEN_AI promotion).

bool IsEAPositionIdOpen(const ulong positionId)
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
        if((ulong)PositionGetInteger(POSITION_IDENTIFIER) == positionId) return true;
    }
    return false;
}

void RemoveExecutedTradeProvenance(const int index)
{
    if(index < 0 || index >= m_execProvCount) return;
    for(int i = index; i < m_execProvCount - 1; i++)
    {
        m_execProvPositionIds[i]   = m_execProvPositionIds[i + 1];
        m_execProvManagerIdx[i]    = m_execProvManagerIdx[i + 1];
        m_execProvContributorCsv[i] = m_execProvContributorCsv[i + 1];
        m_execProvIndicesCsv[i]    = m_execProvIndicesCsv[i + 1];
    }
    m_execProvCount--;
    ArrayResize(m_execProvPositionIds, m_execProvCount);
    ArrayResize(m_execProvManagerIdx, m_execProvCount);
    ArrayResize(m_execProvContributorCsv, m_execProvCount);
    ArrayResize(m_execProvIndicesCsv, m_execProvCount);
}

void RecordExecutedTradeProvenance(const ulong positionId, const int managerIdx,
                                   const string contributorSummary, const int &strategyIndices[])
{
    if(positionId == 0 || contributorSummary == "") return;
    if(managerIdx < 0 || managerIdx >= m_managerCount) return;

    // Ring cap: drop oldest when full.
    if(m_execProvCount >= 512)
        RemoveExecutedTradeProvenance(0);

    int n = m_execProvCount;
    ArrayResize(m_execProvPositionIds, n + 1);
    ArrayResize(m_execProvManagerIdx, n + 1);
    ArrayResize(m_execProvContributorCsv, n + 1);
    ArrayResize(m_execProvIndicesCsv, n + 1);
    m_execProvPositionIds[n] = positionId;
    m_execProvManagerIdx[n] = managerIdx;
    m_execProvContributorCsv[n] = contributorSummary;

    string idxCsv = "";
    for(int i = 0; i < ArraySize(strategyIndices); i++)
    {
        if(i > 0) idxCsv += ",";
        idxCsv += IntegerToString(strategyIndices[i]);
    }
    m_execProvIndicesCsv[n] = idxCsv;
    m_execProvCount++;
}

void FeedAuthorityOutcome(const ulong positionId, const double netProfit)
{
    int found = -1;
    for(int i = 0; i < m_execProvCount; i++)
    {
        if(m_execProvPositionIds[i] == positionId) { found = i; break; }
    }
    if(found < 0) return;

    int managerIdx           = m_execProvManagerIdx[found];
    string contributorCsv    = m_execProvContributorCsv[found];
    string indicesCsv        = m_execProvIndicesCsv[found];
    RemoveExecutedTradeProvenance(found);

    // Rebuild the strategy-index array for ExtractAIName.
    string parts[];
    int partsCount = StringSplit(indicesCsv, ',', parts);
    int strategyIndices[];
    ArrayResize(strategyIndices, 0);
    for(int p = 0; p < partsCount; p++)
    {
        if(parts[p] == "") continue;
        int n2 = ArraySize(strategyIndices) + 1;
        ArrayResize(strategyIndices, n2);
        strategyIndices[n2 - 1] = (int)StringToInteger(parts[p]);
    }

    if(managerIdx < 0 || managerIdx >= m_managerCount || m_enterpriseManagers[managerIdx] == NULL) return;
    if(ArraySize(strategyIndices) == 0) return;

    // Approximate R: profit against one unit of configured per-trade risk on current equity;
    // a consistent denominator is enough for the resolver's promote/demote thresholds.
    double riskMoney = AccountInfoDouble(ACCOUNT_EQUITY) * m_config.maxRiskPerTrade / 100.0;
    double profitR = (riskMoney > 0.0) ? netProfit / riskMoney : 0.0;
    bool isWin = (netProfit > 0.0);

    m_liveAuthority.SetStrategyManager(m_enterpriseManagers[managerIdx]);
    string aiName = m_liveAuthority.ExtractAIName(contributorCsv, strategyIndices);
    if(aiName == "") return;

    m_liveAuthority.RecordOutcome(aiName, profitR, isWin);
    PrintFormat("[AUTHORITY-LEARN] %s | profit=%.2f | R=%.2f | win=%s", aiName, netProfit, profitR, isWin ? "Y" : "N");
}

void ProcessManagerTradeTransactions(const MqlTradeTransaction &trans,
                                     const MqlTradeRequest &request,
                                     const MqlTradeResult &result)
{
    // Per-strategy fan-out: attribution pop, UpdatePerformance, health monitor, governance
    // disable write-through. Each manager filters by its own symbol/magic internally.
    for(int i = 0; i < m_managerCount; i++)
    {
        if(m_enterpriseManagers[i] == NULL) continue;
        m_enterpriseManagers[i].OnTradeTransaction(trans, request, result);
    }

    // Account-level feeds, on full closes of EA-owned positions only.
    if(trans.type != TRADE_TRANSACTION_DEAL_ADD || trans.deal == 0) return;
    if(!HistoryDealSelect(trans.deal)) return;

    long magic = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
    if(!m_tradeManager.IsEAOwnedMagic(magic)) return;

    ENUM_DEAL_ENTRY entryType = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
    if(entryType != DEAL_ENTRY_OUT && entryType != DEAL_ENTRY_OUT_BY && entryType != DEAL_ENTRY_INOUT) return;

    ulong positionId = (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
    if(positionId == 0 || IsEAPositionIdOpen(positionId)) return; // skip partial closes

    double netProfit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
                     + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
                     + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);

    m_performanceAnalytics.RecordClosedTrade(trans.deal, netProfit);
    m_positionManager.RecordClosedTrade(netProfit);
    FeedAuthorityOutcome(positionId, netProfit);
}

void ProcessScalpFastPath()
{
    if(m_config.enableScalpEngine && m_scalpEngine.IsInitialized())
    {
        // The cache must be refreshed here or entry decisions run on init-time snapshots forever:
        // UpdateOnNewBar self-throttles to new bars per symbol, UpdateTickValues only reads quotes.
        m_scalpCache.UpdateOnNewBar();
        m_scalpCache.UpdateTickValues();

        // Drive the scalp lifecycle BEFORE scanning for new entries: open scalps need their 1R partial /
        // breakeven / trailing management and pending sync+async orders need confirming or expiring.
        m_scalpEngine.SyncScalpPositionTracking();
        m_scalpEngine.ManageScalpPositions();
        m_scalpEngine.CheckPendingAsyncOrders();
        m_scalpEngine.CheckPendingScalpOrders();

        // Basket equity stop halts NEW scalp entries; existing scalps are already managed above.
        if(m_basketEquityStop.IsHaltActive())
            return;

        for(int si = 0; si < m_managerCount; si++)
        {
            string symbol = m_enterpriseManagerSymbols[si];
            if(symbol == "")
            continue;

            ENUM_TRADE_SIGNAL signal = TRADE_SIGNAL_NONE;
            double confidence = 0.0;
            double lotSize = 0.0;

            if(m_scalpEngine.ShouldEnterScalp(symbol, signal, confidence, lotSize))
            {
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

// Daily profit-target state lives in COrchestratorProfitGuard (held here by value).
void UpdateDailyProfitTarget()
{
    m_profitGuard.UpdateDailyProfitTarget(m_config);
}

void UpdateAutoModeSwitch()
{
    if(!m_config.enableAutoModeSwitch) return;

    // Auto mode switching is not implemented: no mode or risk parameters are applied here.
}

void ProcessNewBars()
{
    // Route through the scan registry, which holds the bar state: GetScanScheduler() always
    // returned NULL and silently disabled OnNewBar, consensus-cache invalidation, AI adaptation.
    CScanSchedulerRegistry* scanReg = m_registryAggregator.GetScanRegistry();
    if(scanReg == NULL) return;

    ENUM_TIMEFRAMES tf = (ENUM_TIMEFRAMES)Period();
    for(int i = 0; i < m_managerCount; i++)
    {
        string symbol = m_enterpriseManagerSymbols[i];
        if(symbol == "" || m_enterpriseManagers[i] == NULL) continue;

        datetime currentBar = iTime(symbol, tf, 0);
        if(currentBar <= 0) continue;
        if(!scanReg.CheckNewBar(symbol, currentBar)) continue;

        m_consensusCache.Invalidate(symbol);
        m_enterpriseManagers[i].OnNewBar(symbol, tf);

        if(m_config.enableAIMode && m_aiEngine != NULL)
            m_aiEngine.ProcessAdaptation();

        if(m_aiFeedbackReady)
            m_aiFeedback.CheckAutomaticRetraining();
    }
}

void GenerateAndProcessSignals(const string cycleCorrId)
{
    ulong startTotal = GetMicrosecondCount();
    
    if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
    return;

    int secondsSinceLastTrade = (int)(TimeCurrent() - m_lastTradeTime);
    bool cooldownBlocked = (secondsSinceLastTrade < m_config.minSecondsBetweenTrades && m_lastTradeTime > 0);
    int eaPositions = GetEAPositionCount();
    bool positionLimitBlocked = (eaPositions >= m_config.maxPositionsTotal);
    bool unprotectedBlocked = m_unifiedRiskManager.HasUnprotectedPositions();
    bool spikePaused = m_spikeMonitor.IsPaused();

    bool canOpenNewTrades = !(cooldownBlocked || positionLimitBlocked || unprotectedBlocked || spikePaused || m_profitGuard.IsTradingHalted() || m_basketEquityStop.IsHaltActive());

        ulong startSignalGen = GetMicrosecondCount();
        CSignalGenerator::SSignalResult newBarSignals[];
        m_signalGenerator.GenerateSignals(EVAL_MODE_NEW_BAR, newBarSignals, cycleCorrId);
            ulong signalGenTime = GetMicrosecondCount() - startSignalGen;
            CJsonLogger::LogPerformance("EAOrchestrator", "GenerateAndProcessSignals_SignalGen_us", (double)signalGenTime, cycleCorrId);

    ulong startCandidateBuild = GetMicrosecondCount();
    int candidatesBuilt = 0;
    for(int i = 0; i < ArraySize(newBarSignals); i++)
    {
        // Count every symbol slot as one attempted scan: the [HEARTBEAT] funnel counters
        // (scans / no_signal / validator_reject) have no other writers.
        m_heartbeat.IncScansAttempted();

        if(!newBarSignals[i].valid)
        {
            m_heartbeat.IncNoSignalCount();
            continue;
        }

        string symbol = m_enterpriseManagerSymbols[i];
        CEnterpriseStrategyManager* manager = m_enterpriseManagers[i];
        if(manager == NULL) continue;

        STradeCandidate candidate;
        bool candidateBuilt = false;

        // SPostConsensusValidation lives in PostConsensusValidator.mqh: the old nested name
        // shadowed the unrelated SValidationResult in Core/Utils/Enums.mqh.
        SPostConsensusValidation validation = manager.ValidateSignal(
                symbol, newBarSignals[i].signal, newBarSignals[i].confidence,
                newBarSignals[i].confluence, EVAL_MODE_NEW_BAR, newBarSignals[i].decisionContext,
                ++m_scanCycleSequence, cycleCorrId);

        if(!validation.passed)
        {
            m_heartbeat.IncValidatorRejects();
            continue;
        }

                if(!m_candidateBuilder.BuildCandidate(symbol, newBarSignals[i].signal, newBarSignals[i].confidence,
                newBarSignals[i].confluence, newBarSignals[i].decisionContext,
                manager, m_scanCycleSequence, candidate, cycleCorrId))
                continue;
        candidateBuilt = true;
        candidatesBuilt++;

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
        // Batch 173: this multiplier now sets the shipped lot (see ScaleLotByLiveAuthority). It is
        // shrink-only, and a lot that drops under the broker minimum is refused loudly rather than
        // rounded back up, so the gate cannot be silently undone by lot normalization.
        candidate.liveAuthorityRiskMult = authority.riskMultiplier;
        candidate.liveAuthorityReason = authority.reason;

        if(!authority.allowed) continue;

        if(!m_candidateBuilder.ScaleLotByLiveAuthority(candidate, authority.riskMultiplier, cycleCorrId))
            continue;

                if(!canOpenNewTrades) continue;

                // Only a real send arms the min-seconds-between-trades cooldown.
                CTradeExecutor::SExecutionResult execResult = m_tradeExecutor.Execute(candidate, cycleCorrId);
                if(execResult.executed)
                {
                    m_lastTradeTime = TimeCurrent();
                    m_heartbeat.IncSignalsSent();
                    // Book executed risk into the daily entry budget: RegisterExecutedTradeRisk is
                    // the only writer of realized per-trade risk.
                    SValidationResult executedRisk;
                    executedRisk.riskPercent = candidate.riskPercent;
                    double fillRatio = (candidate.lotSize > 0.0 && execResult.filledVolume > 0.0)
                                       ? MathMin(1.0, execResult.filledVolume / candidate.lotSize) : 1.0;
                    m_unifiedRiskManager.RegisterExecutedTradeRisk(executedRisk, fillRatio);

                    // Remember AI-contributed trades so their full close feeds RecordOutcome (PROVEN_AI).
                    if(candidate.hasAIContributor && execResult.dealTicket > 0
                       && HistoryDealSelect(execResult.dealTicket))
                    {
                        long provPosId = HistoryDealGetInteger(execResult.dealTicket, DEAL_POSITION_ID);
                        if(provPosId > 0)
                            RecordExecutedTradeProvenance((ulong)provPosId, i,
                                                          candidate.contributorSummary, strategyIndices);
                    }
                }

                // Update heartbeat funnel (validated + risk-approved reached execution)
                m_heartbeat.IncSignalsValidated();
                m_heartbeat.IncSignalsRiskApproved();
            }
    
        CJsonLogger::LogPerformance("EAOrchestrator", "GenerateAndProcessSignals_Total_us", (double)(GetMicrosecondCount() - startTotal), cycleCorrId);
}

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
    return m_tradeManager.IsEAOwnedMagic(magic);
}

// Delegates to COrchestratorProfitGuard's static helper.
double CalculateDailyPnLPercent()
{
    return COrchestratorProfitGuard::CalculateDailyPnLPercent();
}

// Status assembly lives in COrchestratorStatusReporter (deps injected in WireAndValidateDependencies).
// MQL5 cannot take the per-cycle counters by pointer, so they are forwarded on each call.
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

// AI cleanup helper: called on init failure and from Shutdown().
void CleanupAISubsystems()
{
    if(m_aiEngine != NULL)
    {
        delete m_aiEngine;
        m_aiEngine = NULL;
    }
    m_aiEngineReady = false;

    // No Shutdown() method on m_aiNextGenBrain: its destructor handles cleanup.
    m_aiBrainReady = false;

    // No Shutdown() method on m_aiFeedback: its destructor handles cleanup.
    m_aiFeedbackReady = false;

    Print("[CLEANUP] AI subsystems cleaned up");
}

// AI subsystem initialization. Ownership hierarchy:
// - Neural Network strategies (created via factory) are OWNED by their adapters, which are
//   registered with and OWNED by EnterpriseStrategyManager per symbol
// - CAIEngine (adaptation engine) is OWNED by CEAOrchestrator (this class)
// - m_aiNextGenBrain and m_aiFeedback are stack-allocated members of CEAOrchestrator
bool InitializeAISubsystems()
{
    if(!m_config.enableAIMode)
    {
        Print("[AI] AI mode disabled - skipping AI subsystem initialization");
        return true;
    }

    bool allSuccess = true;

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

// AI strategy adapters: created via factory, registered with EnterpriseStrategyManager (which owns them).
if(m_config.enableAIMode && (m_config.enableNeuralNetwork || m_config.enableTransformer || m_config.enableEnsemble || m_config.enableOnnxAI))
{
    ReleaseNeuralNetStrategies();
    // One catalog pass per symbol; the per-row m_config.enableX gates live in IsCatalogAIRowEnabled().
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

// AI Engine for adaptation (orchestrator-owned): adapts strategy weights from AI predictions.
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

bool GetSystemInitialized() const { return m_systemInitialized; }
bool GetTradingEnabled() const { return m_tradingEnabled; }

CTradeManager* GetTradeManager() { return GetPointer(m_tradeManager); }

// Call after signal generation so per-symbol [AI-VOTE] heartbeat activity is tracked.
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
