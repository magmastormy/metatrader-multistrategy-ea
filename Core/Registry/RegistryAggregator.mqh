// Owns and disposes the typed registries. EAOrchestrator holds exactly one CRegistryAggregator by value
// (m_registryAggregator) and injects the sub-registry pointers into consumers — managers receive
// GetStrategyRegistry() — so no second instance of any registry exists that could disagree with this one.
#ifndef REGISTRY_AGGREGATOR_MQH
#define REGISTRY_AGGREGATOR_MQH

// CRegistryBase<T> (IRegistry.mqh) is deliberately NOT included: it models one "string -> T* owned
// instance" map, but every registry here stores structs BY VALUE (SStrategyDescriptor, SNNEntry, SEngineSlot,
// SDrawingEntry, SSymbolScanState) and maps one symbol to MANY engines, which the template cannot express.
#include "MathematicalEngineRegistry.mqh"
#include "InstitutionalEngineRegistry.mqh"
#include "NeuralNetRegistry.mqh"
#include "DrawingManagerRegistry.mqh"
#include "ScanSchedulerRegistry.mqh"
#include "SymbolStateTracker.mqh"
#include "../Strategy/StrategyRegistry.mqh"

class CMathematicalEngineRegistry;
class CInstitutionalEngineRegistry;
class CDrawingManagerRegistry;
class CScanSchedulerRegistry;
class CSymbolStateTracker;
class CNeuralNetRegistry;
class CStrategyRegistry;

class CRegistryAggregator
{
private:
    CMathematicalEngineRegistry* m_mathRegistry;
    
    CInstitutionalEngineRegistry* m_institutionalRegistry;
    
    CNeuralNetRegistry* m_neuralNetRegistry;
    
    CDrawingManagerRegistry* m_drawingRegistry;
    
    CScanSchedulerRegistry* m_scanRegistry;
    
        CSymbolStateTracker* m_symbolStateTracker;
    
        CStrategyRegistry* m_strategyRegistry;

    public:
    CRegistryAggregator() :
        m_mathRegistry(NULL),
        m_institutionalRegistry(NULL),
        m_neuralNetRegistry(NULL),
        m_drawingRegistry(NULL),
        m_scanRegistry(NULL),
        m_symbolStateTracker(NULL),
        m_strategyRegistry(NULL)
    {
    }
    ~CRegistryAggregator();
    
    bool Initialize();
    void Deinitialize();
    
    CMathematicalEngineRegistry* GetMathRegistry() const { return m_mathRegistry; }
    
    CInstitutionalEngineRegistry* GetInstitutionalRegistry() const { return m_institutionalRegistry; }
    
    CNeuralNetRegistry* GetNeuralNetRegistry() const { return m_neuralNetRegistry; }
    
    // Drives online learning for every active net: TickOnlineLearningAll -> per-net TickOnlineLearning, which
    // runs ResolveBarriers plus the self-labeled observation capture.
    // Called from EAOrchestrator.mqh:2990; this aggregator owns the only CNeuralNetRegistry instance — the
    // old claim that EAOrchestrator could not see the type is stale, it includes NeuralNetRegistry.mqh at line 15.
    void TickNeuralNetOnlineLearning() const;
    
    CDrawingManagerRegistry* GetDrawingRegistry() const { return m_drawingRegistry; }
    
    CScanSchedulerRegistry* GetScanRegistry() const { return m_scanRegistry; }
    
        CSymbolStateTracker* GetSymbolStateTracker() const { return m_symbolStateTracker; }
    
        CStrategyRegistry* GetStrategyRegistry() const { return m_strategyRegistry; }
    
        // Dead surface: no caller in this repo uses the nine Get*(symbol) conveniences below, GetScanScheduler,
        // GetTotalRegisteredCount or any Is*Ready() probe. Live consumers take the whole registry instead —
        // GetMathRegistry()/GetInstitutionalRegistry()/GetDrawingRegistry() feed UnifiedSignalPipeline and
        // OrchestratorMathEngineHub, GetStrategyRegistry() feeds the symbol managers.
    CTrendEngine* GetTrendEngine(const string symbol) const;
    CStructureEngine* GetStructureEngine(const string symbol) const;
    CLiquidityEngine* GetLiquidityEngine(const string symbol) const;
    CVolatilityEngine* GetVolatilityEngine(const string symbol) const;
    CRegimeEngine* GetRegimeEngine(const string symbol) const;
    COrderFlowImbalanceEngine* GetOFIEngine(const string symbol) const;
    CVPINFilter* GetVPINFilter(const string symbol) const;
    CChartDrawingManager* GetDrawingManager(const string symbol) const;
    CSymbolScanScheduler* GetScanScheduler(const string symbol) const;
    
    bool IsMathRegistryReady() const { return m_mathRegistry != NULL; }
    bool IsInstitutionalRegistryReady() const { return m_institutionalRegistry != NULL; }
    bool IsNeuralNetRegistryReady() const { return m_neuralNetRegistry != NULL; }
    bool IsDrawingRegistryReady() const { return m_drawingRegistry != NULL; }
    bool IsScanRegistryReady() const { return m_scanRegistry != NULL; }
    bool IsSymbolStateTrackerReady() const { return m_symbolStateTracker != NULL; }
    
    // Not "all registries": it sums six of the seven and leaves m_strategyRegistry out entirely.
    int GetTotalRegisteredCount() const;
    
    void ClearAll();

private:
    // Declared private and never defined: copying this class is a link error, which is the point.
    CRegistryAggregator(const CRegistryAggregator&);
};

CRegistryAggregator::~CRegistryAggregator()
{
    Deinitialize();
}

// Must run BEFORE EAOrchestrator::BuildStrategyRegistry(): GetStrategyRegistry() would hand out NULL there.
// Descriptors stay empty until the orchestrator fills them, so CStrategyRegistry::IsStrategyActive() is false
// for every name at that point (unknown name -> false) and managers re-apply their flags afterwards.
bool CRegistryAggregator::Initialize()
{
    bool ok = true;
    
    m_mathRegistry = new CMathematicalEngineRegistry();
    if(m_mathRegistry == NULL)
    {
        Print("[RegistryAggregator] ERROR: Failed to allocate MathematicalEngineRegistry");
        ok = false;
    }
    
    m_institutionalRegistry = new CInstitutionalEngineRegistry();
    if(m_institutionalRegistry == NULL)
    {
        Print("[RegistryAggregator] ERROR: Failed to allocate InstitutionalEngineRegistry");
        ok = false;
    }
    
    m_neuralNetRegistry = new CNeuralNetRegistry();
    if(m_neuralNetRegistry == NULL)
    {
        Print("[RegistryAggregator] ERROR: Failed to allocate NeuralNetRegistry");
        ok = false;
    }
    
    m_drawingRegistry = new CDrawingManagerRegistry();
    if(m_drawingRegistry == NULL)
    {
        Print("[RegistryAggregator] ERROR: Failed to allocate DrawingManagerRegistry");
        ok = false;
    }
    
    m_scanRegistry = new CScanSchedulerRegistry();
    if(m_scanRegistry == NULL)
    {
        Print("[RegistryAggregator] ERROR: Failed to allocate ScanSchedulerRegistry");
        ok = false;
    }
    
    m_symbolStateTracker = new CSymbolStateTracker();
    if(m_symbolStateTracker == NULL)
    {
        Print("[RegistryAggregator] ERROR: Failed to allocate SymbolStateTracker");
        ok = false;
    }
    
    m_strategyRegistry = new CStrategyRegistry();
    if(m_strategyRegistry == NULL)
    {
        Print("[RegistryAggregator] ERROR: Failed to allocate StrategyRegistry");
        ok = false;
    }
    
    if(ok)
    {
        Print("[RegistryAggregator] All registries initialized successfully");
    }
    
    return ok;
}

void CRegistryAggregator::Deinitialize()
{
    ClearAll();
    
    if(m_mathRegistry != NULL)
    {
        delete m_mathRegistry;
        m_mathRegistry = NULL;
    }
    
    if(m_institutionalRegistry != NULL)
    {
        delete m_institutionalRegistry;
        m_institutionalRegistry = NULL;
    }
    
    if(m_neuralNetRegistry != NULL)
    {
        delete m_neuralNetRegistry;
        m_neuralNetRegistry = NULL;
    }
    
    if(m_drawingRegistry != NULL)
    {
        delete m_drawingRegistry;
        m_drawingRegistry = NULL;
    }
    
    if(m_scanRegistry != NULL)
    {
        delete m_scanRegistry;
        m_scanRegistry = NULL;
    }
    
    if(m_symbolStateTracker != NULL)
        {
            delete m_symbolStateTracker;
            m_symbolStateTracker = NULL;
        }
    
        if(m_strategyRegistry != NULL)
        {
            delete m_strategyRegistry;
            m_strategyRegistry = NULL;
        }
    
        Print("[RegistryAggregator] All registries deinitialized");
}

CTrendEngine* CRegistryAggregator::GetTrendEngine(const string symbol) const
{
    if(m_mathRegistry != NULL)
        return m_mathRegistry.GetTrend(symbol);
    return NULL;
}

CStructureEngine* CRegistryAggregator::GetStructureEngine(const string symbol) const
{
    if(m_mathRegistry != NULL)
        return m_mathRegistry.GetStructure(symbol);
    return NULL;
}

CLiquidityEngine* CRegistryAggregator::GetLiquidityEngine(const string symbol) const
{
    if(m_mathRegistry != NULL)
        return m_mathRegistry.GetLiquidity(symbol);
    return NULL;
}

CVolatilityEngine* CRegistryAggregator::GetVolatilityEngine(const string symbol) const
{
    if(m_mathRegistry != NULL)
            return m_mathRegistry.GetVolatility(symbol);
        return NULL;
    }

CRegimeEngine* CRegistryAggregator::GetRegimeEngine(const string symbol) const
{
    if(m_mathRegistry != NULL)
        return m_mathRegistry.GetRegime(symbol);
    return NULL;
}

COrderFlowImbalanceEngine* CRegistryAggregator::GetOFIEngine(const string symbol) const
{
    if(m_mathRegistry != NULL)
        return m_mathRegistry.GetOFI(symbol);
    return NULL;
}

CVPINFilter* CRegistryAggregator::GetVPINFilter(const string symbol) const
{
    if(m_mathRegistry != NULL)
        return m_mathRegistry.GetVPIN(symbol);
    return NULL;
}

CChartDrawingManager* CRegistryAggregator::GetDrawingManager(const string symbol) const
{
    if(m_drawingRegistry != NULL)
        return m_drawingRegistry.GetManager(symbol);
    return NULL;
}

// Always NULL, and no caller in this repo: CScanSchedulerRegistry holds scan state per symbol rather than
// scheduler objects. ProcessNewBars reads that state via CScanSchedulerRegistry::CheckNewBar directly
// (EAOrchestrator.mqh:3404).
CSymbolScanScheduler* CRegistryAggregator::GetScanScheduler(const string symbol) const
{
    return NULL;
}

int CRegistryAggregator::GetTotalRegisteredCount() const
{
    int total = 0;
    if(m_mathRegistry != NULL) total += m_mathRegistry.Count();
    if(m_institutionalRegistry != NULL) total += m_institutionalRegistry.Count();
    if(m_neuralNetRegistry != NULL) total += m_neuralNetRegistry.GetActiveCount();
    if(m_drawingRegistry != NULL) total += m_drawingRegistry.GetTotalObjectCount();
    if(m_scanRegistry != NULL) total += m_scanRegistry.GetPendingNewBarCount();
    if(m_symbolStateTracker != NULL) total += m_symbolStateTracker.Count();
    return total;
}

void CRegistryAggregator::TickNeuralNetOnlineLearning() const
{
    if(m_neuralNetRegistry != NULL)
        m_neuralNetRegistry.TickOnlineLearningAll();
}

void CRegistryAggregator::ClearAll()
{
    if(m_mathRegistry != NULL) m_mathRegistry.Clear();
    if(m_institutionalRegistry != NULL) m_institutionalRegistry.Clear();
    if(m_neuralNetRegistry != NULL) m_neuralNetRegistry.Clear();
    if(m_drawingRegistry != NULL) m_drawingRegistry.Clear();
    if(m_scanRegistry != NULL) m_scanRegistry.Clear();
    if(m_symbolStateTracker != NULL) m_symbolStateTracker.Clear();
    if(m_strategyRegistry != NULL) m_strategyRegistry.Reset();
}

#endif // REGISTRY_AGGREGATOR_MQH