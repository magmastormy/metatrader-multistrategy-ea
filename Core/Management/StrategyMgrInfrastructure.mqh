// Leaf value object held BY VALUE by CEnterpriseStrategyManager; it has no back-pointer to the manager.
// ReleaseOnDeinit()/FinishDeinit() must stay separate: the manager re-binds its attribution delegator between them.
// Include only from EnterpriseStrategyManager.mqh.
#ifndef STRATEGY_MGR_INFRASTRUCTURE_MQH
#define STRATEGY_MGR_INFRASTRUCTURE_MQH

#include "../Pipeline/UnifiedSignalPipeline.mqh"          // CUnifiedSignalPipeline, SignalFilterSettings
#include "../Signals/TimeframeConsistency.mqh"            // CTimeframeConsistency
#include "../Processing/DerivAssetProfiler.mqh"           // CDerivAssetProfiler
#include "../Processing/MultiAssetProfiler.mqh"           // CMultiAssetProfiler
#include "../Risk/VPINFilter.mqh"                         // CVPINFilter
#include "../Engines/OrderFlowImbalanceEngine.mqh"        // COrderFlowImbalanceEngine
#include "../Engines/FamilyStrategyWeightMatrix.mqh"      // CFamilyStrategyWeightMatrix
#include "../Engines/FourStateRegimeDetector.mqh"         // CFourStateRegimeDetector
#include "../Strategy/StrategyRegistry.mqh"               // CStrategyRegistry
#include "DiagnosticsManager.mqh"                         // CDiagnosticsManager
#include "StrategyHealthMonitor.mqh"                      // CStrategyHealthMonitor
#include "EntStrategyQuorumConfig.mqh"                    // CEntStrategyQuorumConfig (health-monitor config source)
#include "../../Core/Trading/TradeAttributionManager.mqh" // CTradeAttributionManager

// Pointer-only collaborators (never dereferenced here)
class CTradeManager;
class CPositionSizer;

class CStrategyMgrInfrastructure
{
private:
    CUnifiedSignalPipeline*      m_pipeline;
    CTimeframeConsistency*       m_tfConsistency;
    CTradeManager*               m_tradeManager;         // CRITICAL FIX: Store for strategy initialization
    CPositionSizer*              m_positionSizer;        // CRITICAL FIX: Store for strategy initialization
    CUnifiedRiskManager*         m_unifiedRiskManager;   // Unified risk validation gate (injected)
    CDerivAssetProfiler*         m_derivProfiler;        // Deriv family profiler for engine weighting
    CMultiAssetProfiler*         m_multiAssetProfiler;   // Multi-asset profiler (Batch 103)
    CChartDrawingManager*        m_drawingManager;       // Central drawing manager for the symbol
    CVPINFilter*                 m_vpinFilter;           // VPIN toxicity filter for consensus (Batch 104)
    COrderFlowImbalanceEngine*   m_ofiEngine;            // OFI for regime integration (Batch 104)
    CFamilyStrategyWeightMatrix* m_familyWeightMatrix;   // I1: Per-family cluster weight multipliers
    CFourStateRegimeDetector*    m_fourStateRegimeDetector;
    CStrategyRegistry*           m_strategyRegistry;     // L1-004: Injected registry (no global singleton)
    bool                         m_regimeDetectorInitialized;

    CDiagnosticsManager*      m_diagnostics;
    CTradeAttributionManager* m_attribution;
    CStrategyHealthMonitor*   m_healthMonitor;

    string          m_symbol;
    ENUM_TIMEFRAMES m_baseTimeframe;

    bool m_initialized;
    bool m_usePipeline;

public:
    CStrategyMgrInfrastructure();

    bool Initialize(const string symbol, ENUM_TIMEFRAMES timeframe,
                    bool usePipeline,
                    CTradeManager* tradeManagerPtr, CPositionSizer* positionSizerPtr,
                    CUnifiedRiskManager* unifiedRiskManagerPtr,
                    CEntStrategyQuorumConfig &quorumConfig);

    //--- destructor teardown; does NOT delete the injected m_diagnostics / m_attribution
    void ReleaseOnDestruct();
    //--- explicit-Deinit teardown, part 1 (up to and including attribution)
    void ReleaseOnDeinit();
    //--- explicit-Deinit teardown, part 2 (health monitor + init flag)
    void FinishDeinit();

    void AllocateHealthMonitor();

    //--- pipeline half of SetPipelineFilters(); the confidence-floor cache stays in the quorum config object
    void ApplyPipelineFilters(SignalFilterSettings &settings);
    void SetConsensusDiagnosticsIntervalSeconds(const int seconds);

    void SetStrategyRegistry(CStrategyRegistry* registry)          { m_strategyRegistry = registry; }
    void SetDiagnosticsManager(CDiagnosticsManager* diagnostics)   { m_diagnostics = diagnostics; }
    void SetAttributionManager(CTradeAttributionManager* attrib)   { m_attribution = attrib; }
    void SetDrawingManager(CChartDrawingManager* drawingManager)   { m_drawingManager = drawingManager; }
    void SetDerivProfiler(CDerivAssetProfiler* profiler)           { m_derivProfiler = profiler; }
    void SetFamilyWeightMatrix(CFamilyStrategyWeightMatrix* fam)   { m_familyWeightMatrix = fam; }
    void SetMultiAssetProfiler(CMultiAssetProfiler* profiler)      { m_multiAssetProfiler = profiler; }
    void SetVPINFilter(CVPINFilter* vpin)                          { m_vpinFilter = vpin; }
    void SetOFIEngine(COrderFlowImbalanceEngine* ofi)              { m_ofiEngine = ofi; }

    CUnifiedSignalPipeline*      GetPipeline() const               { return m_pipeline; }
    CTimeframeConsistency*       GetTFConsistency() const          { return m_tfConsistency; }
    CTradeManager*               GetTradeManager() const           { return m_tradeManager; }
    CPositionSizer*              GetPositionSizer() const          { return m_positionSizer; }
    CUnifiedRiskManager*         GetUnifiedRiskManager() const     { return m_unifiedRiskManager; }
    CDerivAssetProfiler*         GetDerivProfiler() const          { return m_derivProfiler; }
    CMultiAssetProfiler*         GetMultiAssetProfiler() const     { return m_multiAssetProfiler; }
    CChartDrawingManager*        GetDrawingManager() const         { return m_drawingManager; }
    CVPINFilter*                 GetVPINFilter() const             { return m_vpinFilter; }
    COrderFlowImbalanceEngine*   GetOFIEngine() const              { return m_ofiEngine; }
    CFamilyStrategyWeightMatrix* GetFamilyWeightMatrix() const     { return m_familyWeightMatrix; }
    CFourStateRegimeDetector*    GetFourStateRegimeDetector() const{ return m_fourStateRegimeDetector; }
    CStrategyRegistry*           GetStrategyRegistry() const       { return m_strategyRegistry; }
    CDiagnosticsManager*         GetDiagnostics() const            { return m_diagnostics; }
    CTradeAttributionManager*    GetAttribution() const            { return m_attribution; }
    CStrategyHealthMonitor*      GetHealthMonitor() const          { return m_healthMonitor; }

    bool            IsRegimeDetectorInitialized() const { return m_regimeDetectorInitialized; }
    string          GetManagedSymbol() const            { return m_symbol; }
    ENUM_TIMEFRAMES GetBaseTimeframe() const            { return m_baseTimeframe; }
    bool            IsManagerInitialized() const        { return m_initialized; }
    bool            IsPipelineEnabled() const           { return m_usePipeline; }
};

CStrategyMgrInfrastructure::CStrategyMgrInfrastructure() :
    m_pipeline(NULL),
    m_tfConsistency(NULL),
    m_tradeManager(NULL),
    m_positionSizer(NULL),
    m_unifiedRiskManager(NULL),
    m_derivProfiler(NULL),
    m_multiAssetProfiler(NULL),
    m_drawingManager(NULL),
    m_vpinFilter(NULL),
    m_ofiEngine(NULL),
    m_familyWeightMatrix(NULL),
    m_fourStateRegimeDetector(NULL),
    m_strategyRegistry(NULL),                // L1-004: Injected registry
    m_regimeDetectorInitialized(false),
    m_diagnostics(NULL),
    m_attribution(NULL),
    m_healthMonitor(NULL),
    m_baseTimeframe(PERIOD_CURRENT),
    m_initialized(false),
    m_usePipeline(true)
{
    m_symbol = "";
}

void CStrategyMgrInfrastructure::AllocateHealthMonitor()
{
    m_healthMonitor = new CStrategyHealthMonitor();
}

// Pipeline and TimeframeConsistency are mandatory: either failure returns false (pipeline is deleted on rollback).
// FourStateRegimeDetector is optional: its failure only warns and leaves the pointer NULL.
bool CStrategyMgrInfrastructure::Initialize(const string symbol, ENUM_TIMEFRAMES timeframe,
                                            bool usePipeline,
                                            CTradeManager* tradeManagerPtr, CPositionSizer* positionSizerPtr,
                                            CUnifiedRiskManager* unifiedRiskManagerPtr,
                                            CEntStrategyQuorumConfig &quorumConfig)
{
    m_symbol = symbol;
    m_baseTimeframe = timeframe;
    m_usePipeline = usePipeline;
    m_tradeManager = tradeManagerPtr;   // CRITICAL FIX: Store for strategy initialization
    m_positionSizer = positionSizerPtr; // CRITICAL FIX: Store for strategy initialization
    m_unifiedRiskManager = unifiedRiskManagerPtr; // ARCHITECTURAL FIX: Inject unified risk manager

    if(m_usePipeline)
    {
        m_pipeline = new CUnifiedSignalPipeline();
        if(m_pipeline != NULL)
        {
            SignalFilterSettings filters;
            if(!m_pipeline.Initialize(filters))
            {
                Print("[EnterpriseStrategyManager] ERROR: Pipeline initialization failed for ", symbol);
                delete m_pipeline;
                m_pipeline = NULL;
                return false;
            }
        }
        else
        {
            Print("[EnterpriseStrategyManager] ERROR: Pipeline allocation failed for ", symbol);
            return false;
        }
    }

    if(m_tfConsistency != NULL)
    {
        delete m_tfConsistency;
        m_tfConsistency = NULL;
    }

    m_tfConsistency = new CTimeframeConsistency();
    if(m_tfConsistency == NULL)
    {
        Print("[EnterpriseStrategyManager] ERROR: TimeframeConsistency allocation failed for ", symbol);
        if(m_pipeline != NULL)
        {
            delete m_pipeline;
            m_pipeline = NULL;
        }
        return false;
    }
    if(!m_tfConsistency.Initialize(CONFLICT_RES_WEIGHTED, 0.6, false))
    {
        Print("[EnterpriseStrategyManager] ERROR: TimeframeConsistency initialization failed for ", symbol);
        delete m_tfConsistency;
        m_tfConsistency = NULL;
        if(m_pipeline != NULL)
        {
            delete m_pipeline;
            m_pipeline = NULL;
        }
        return false;
    }

    m_initialized = true;
    m_drawingManager = NULL;

    // m_diagnostics and m_attribution are injected from EAOrchestrator; never create them here.

    if(m_healthMonitor != NULL)
    {
        delete m_healthMonitor;
        m_healthMonitor = NULL;
    }
    m_healthMonitor = new CStrategyHealthMonitor();
    if(m_healthMonitor != NULL)
    {
        m_healthMonitor.SetOrchestratorMode(quorumConfig.GetMinWinRateThreshold(),
                                            quorumConfig.GetMaxConsecutiveLossesLimit());
        m_healthMonitor.SetRollingWindowSize(quorumConfig.GetRollingWindowSize());
    }

    m_fourStateRegimeDetector = new CFourStateRegimeDetector(m_symbol, m_baseTimeframe);
    if(m_fourStateRegimeDetector != NULL)
    {
        if(m_fourStateRegimeDetector.Initialize())
        {
            Print("[EnterpriseStrategyManager] FourStateRegimeDetector initialized for ", m_symbol);
            m_regimeDetectorInitialized = true;
        }
        else
        {
            Print("[EnterpriseStrategyManager] WARNING: FourStateRegimeDetector initialization failed for ", m_symbol);
            delete m_fourStateRegimeDetector;
            m_fourStateRegimeDetector = NULL;
            m_regimeDetectorInitialized = false;
        }
    }
    else
    {
        m_regimeDetectorInitialized = false;
    }

    Print("[EnterpriseStrategyManager] Initialized for ", symbol, " on ", EnumToString(timeframe));
    Print("[EnterpriseStrategyManager] Pipeline: ", m_usePipeline ? "ENABLED" : "DISABLED");

    return true;
}

void CStrategyMgrInfrastructure::ReleaseOnDestruct()
{
    if(m_pipeline != NULL)
    {
        delete m_pipeline;
        m_pipeline = NULL;
    }

    if(m_fourStateRegimeDetector != NULL)
    {
        delete m_fourStateRegimeDetector;
        m_fourStateRegimeDetector = NULL;
    }

    if(m_tfConsistency != NULL)
    {
        delete m_tfConsistency;
        m_tfConsistency = NULL;
    }

    // Do not delete m_diagnostics / m_attribution here (injected; only Deinit releases them).
    if(m_healthMonitor != NULL)
    {
        delete m_healthMonitor;
        m_healthMonitor = NULL;
    }
}

void CStrategyMgrInfrastructure::ReleaseOnDeinit()
{
    if(m_pipeline != NULL)
    {
        delete m_pipeline;
        m_pipeline = NULL;
    }

    if(m_fourStateRegimeDetector != NULL)
    {
        delete m_fourStateRegimeDetector;
        m_fourStateRegimeDetector = NULL;
    }

    if(m_tfConsistency != NULL)
    {
        delete m_tfConsistency;
        m_tfConsistency = NULL;
    }

    if(m_diagnostics != NULL)
    {
        delete m_diagnostics;
        m_diagnostics = NULL;
    }

    if(m_attribution != NULL)
    {
        delete m_attribution;
        m_attribution = NULL;
    }
}

void CStrategyMgrInfrastructure::FinishDeinit()
{
    if(m_healthMonitor != NULL)
    {
        delete m_healthMonitor;
        m_healthMonitor = NULL;
    }

    m_initialized = false;
}

void CStrategyMgrInfrastructure::ApplyPipelineFilters(SignalFilterSettings &settings)
{
    if(m_pipeline != NULL)
    {
        // Apply runtime filter configuration without re-initializing pipeline engines.
        m_pipeline.SetFilters(settings);
        Print("[EnterpriseStrategyManager] Pipeline filters applied: TrendFilter=",
              settings.trend.enabled, " MinConf=", settings.confidence.minConfidence,
              " IntrabarCap=", settings.confidence.intrabarConfidenceCap,
              " RegimeCost=", settings.regimeCostGate.enabled,
              " MaxSpreadATR=", settings.regimeCostGate.maxSpreadToAtrRatio,
              " ShockCooldown=", settings.regimeCostGate.spreadShockCooldownSeconds,
              " MaxEntryZ=", settings.regimeCostGate.maxEntryRangeZScore,
              " MaxVol=", settings.volatility.maxVolatility,
              " StructureFilter=", settings.structure.enabled,
              " LiquidityFilter=", settings.liquidity.enabled);
    }
}

void CStrategyMgrInfrastructure::SetConsensusDiagnosticsIntervalSeconds(const int seconds)
{
    if(m_diagnostics != NULL)
        m_diagnostics.SetLogIntervalSeconds(seconds);
}

#endif // STRATEGY_MGR_INFRASTRUCTURE_MQH
