// Registry Aggregator - Enterprise Grade
// Aggregates multiple typed registries into a unified access point
#ifndef REGISTRY_AGGREGATOR_MQH
#define REGISTRY_AGGREGATOR_MQH

// NOTE: "IRegistry.mqh" (CRegistryBase<T>) is intentionally NOT included.
// That template models a single "string symbol -> T* owned instance" map, but every
// concrete registry here stores a struct-BY-VALUE array (SStrategyDescriptor[],
// SNNEntry[], SEngineSlot[], SDrawingEntry[], SSymbolScanState[]). MQL5 has no
// pointers to structs, and the engine registries map one symbol to MANY engines,
// so the template cannot be applied without rewriting their storage. The include
// was vestigial (nothing in this file referenced IRegistry/CRegistryBase).
#include "MathematicalEngineRegistry.mqh"
#include "InstitutionalEngineRegistry.mqh"
#include "NeuralNetRegistry.mqh"
#include "DrawingManagerRegistry.mqh"
#include "ScanSchedulerRegistry.mqh"
#include "SymbolStateTracker.mqh"
#include "../Strategy/StrategyRegistry.mqh"

// Forward declarations
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
    
    // Mathematical Engine Registry access
    CMathematicalEngineRegistry* GetMathRegistry() const { return m_mathRegistry; }
    
    // Institutional Engine Registry access
    CInstitutionalEngineRegistry* GetInstitutionalRegistry() const { return m_institutionalRegistry; }
    
    // Neural Net Registry access
    CNeuralNetRegistry* GetNeuralNetRegistry() const { return m_neuralNetRegistry; }
    
    // Neural Net online learning tick (drives ResolveBarriers + self-labeled training across all active nets).
    // Defined here (not via CNeuralNetRegistry* directly from EAOrchestrator) because EAOrchestrator only holds a
    // forward declaration of CNeuralNetRegistry and cannot call its member through an incomplete type.
    void TickNeuralNetOnlineLearning() const;
    
    // Drawing Manager Registry access
    CDrawingManagerRegistry* GetDrawingRegistry() const { return m_drawingRegistry; }
    
    // Scan Scheduler Registry access
    CScanSchedulerRegistry* GetScanRegistry() const { return m_scanRegistry; }
    
    // Symbol State Tracker access
        CSymbolStateTracker* GetSymbolStateTracker() const { return m_symbolStateTracker; }
    
        // Strategy Registry access
        CStrategyRegistry* GetStrategyRegistry() const { return m_strategyRegistry; }
    
        // Convenience methods for common engine access
    CTrendEngine* GetTrendEngine(const string symbol) const;
    CStructureEngine* GetStructureEngine(const string symbol) const;
    CLiquidityEngine* GetLiquidityEngine(const string symbol) const;
    CVolatilityEngine* GetVolatilityEngine(const string symbol) const;
    CRegimeEngine* GetRegimeEngine(const string symbol) const;
    COrderFlowImbalanceEngine* GetOFIEngine(const string symbol) const;
    CVPINFilter* GetVPINFilter(const string symbol) const;
    CChartDrawingManager* GetDrawingManager(const string symbol) const;
    CSymbolScanScheduler* GetScanScheduler(const string symbol) const;
    
    // Registry status
    bool IsMathRegistryReady() const { return m_mathRegistry != NULL; }
    bool IsInstitutionalRegistryReady() const { return m_institutionalRegistry != NULL; }
    bool IsNeuralNetRegistryReady() const { return m_neuralNetRegistry != NULL; }
    bool IsDrawingRegistryReady() const { return m_drawingRegistry != NULL; }
    bool IsScanRegistryReady() const { return m_scanRegistry != NULL; }
    bool IsSymbolStateTrackerReady() const { return m_symbolStateTracker != NULL; }
    
    // Get total registered count across all registries
    int GetTotalRegisteredCount() const;
    
    // Clear all registries
    void ClearAll();

private:
    // Prevent copying
    CRegistryAggregator(const CRegistryAggregator&);
};

CRegistryAggregator::~CRegistryAggregator()
{
    Deinitialize();
}

bool CRegistryAggregator::Initialize()
{
    bool ok = true;
    
    // Initialize Mathematical Engine Registry
    m_mathRegistry = new CMathematicalEngineRegistry();
    if(m_mathRegistry == NULL)
    {
        Print("[RegistryAggregator] ERROR: Failed to allocate MathematicalEngineRegistry");
        ok = false;
    }
    
    // Initialize Institutional Engine Registry
    m_institutionalRegistry = new CInstitutionalEngineRegistry();
    if(m_institutionalRegistry == NULL)
    {
        Print("[RegistryAggregator] ERROR: Failed to allocate InstitutionalEngineRegistry");
        ok = false;
    }
    
    // Initialize Neural Net Registry
    m_neuralNetRegistry = new CNeuralNetRegistry();
    if(m_neuralNetRegistry == NULL)
    {
        Print("[RegistryAggregator] ERROR: Failed to allocate NeuralNetRegistry");
        ok = false;
    }
    
    // Initialize Drawing Manager Registry
    m_drawingRegistry = new CDrawingManagerRegistry();
    if(m_drawingRegistry == NULL)
    {
        Print("[RegistryAggregator] ERROR: Failed to allocate DrawingManagerRegistry");
        ok = false;
    }
    
    // Initialize Scan Scheduler Registry
    m_scanRegistry = new CScanSchedulerRegistry();
    if(m_scanRegistry == NULL)
    {
        Print("[RegistryAggregator] ERROR: Failed to allocate ScanSchedulerRegistry");
        ok = false;
    }
    
    // Initialize Symbol State Tracker
    m_symbolStateTracker = new CSymbolStateTracker();
    if(m_symbolStateTracker == NULL)
    {
        Print("[RegistryAggregator] ERROR: Failed to allocate SymbolStateTracker");
        ok = false;
    }
    
    // Initialize Strategy Registry
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
    // Clear all registries
    ClearAll();
    
    // Delete registry instances
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

// Convenience: Get Trend Engine
CTrendEngine* CRegistryAggregator::GetTrendEngine(const string symbol) const
{
    if(m_mathRegistry != NULL)
        return m_mathRegistry.GetTrend(symbol);
    return NULL;
}

// Convenience: Get Structure Engine
CStructureEngine* CRegistryAggregator::GetStructureEngine(const string symbol) const
{
    if(m_mathRegistry != NULL)
        return m_mathRegistry.GetStructure(symbol);
    return NULL;
}

// Convenience: Get Liquidity Engine
CLiquidityEngine* CRegistryAggregator::GetLiquidityEngine(const string symbol) const
{
    if(m_mathRegistry != NULL)
        return m_mathRegistry.GetLiquidity(symbol);
    return NULL;
}

// Convenience: Get Volatility Engine
CVolatilityEngine* CRegistryAggregator::GetVolatilityEngine(const string symbol) const
{
    if(m_mathRegistry != NULL)
            return m_mathRegistry.GetVolatility(symbol);
        return NULL;
    }

    // Convenience: Get Regime Engine
CRegimeEngine* CRegistryAggregator::GetRegimeEngine(const string symbol) const
{
    if(m_mathRegistry != NULL)
        return m_mathRegistry.GetRegime(symbol);
    return NULL;
}

// Convenience: Get OFI Engine
COrderFlowImbalanceEngine* CRegistryAggregator::GetOFIEngine(const string symbol) const
{
    if(m_mathRegistry != NULL)
        return m_mathRegistry.GetOFI(symbol);
    return NULL;
}

// Convenience: Get VPIN Filter
CVPINFilter* CRegistryAggregator::GetVPINFilter(const string symbol) const
{
    if(m_mathRegistry != NULL)
        return m_mathRegistry.GetVPIN(symbol);
    return NULL;
}

// Convenience: Get Drawing Manager
CChartDrawingManager* CRegistryAggregator::GetDrawingManager(const string symbol) const
{
    if(m_drawingRegistry != NULL)
        return m_drawingRegistry.GetManager(symbol);
    return NULL;
}

// Convenience: Get Scan Scheduler
// Note: CScanSchedulerRegistry doesn't have a GetScheduler method.
// It tracks scan state per symbol. Return NULL for now.
CSymbolScanScheduler* CRegistryAggregator::GetScanScheduler(const string symbol) const
{
    // CScanSchedulerRegistry doesn't expose a scheduler object per symbol
    // It tracks scan state internally. Return NULL.
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

// Clear All Registries
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