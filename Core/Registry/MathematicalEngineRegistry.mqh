// Consolidates all mathematical engines per symbol
#property strict

#ifndef CORE_REGISTRY_MATHEMATICAL_ENGINE_REGISTRY_MQH
#define CORE_REGISTRY_MATHEMATICAL_ENGINE_REGISTRY_MQH

#include "../../Core/Engines/HurstEngine.mqh"
#include "../../Core/Engines/OrnsteinUhlenbeckEngine.mqh"
#include "../../Core/Engines/OrderFlowImbalanceEngine.mqh"
#include "../../Core/Risk/VPINFilter.mqh"
#include "../../Core/Engines/KalmanMeanReversion.mqh"
#include "../../Core/Engines/ChangepointDetector.mqh"
#include "../../Core/Engines/FourStateRegimeDetector.mqh"
#include "../../Core/Engines/VolatilityTargeting.mqh"
#include "../../Strategies/LiquiditySweepStrategy.mqh"
#include "../../Strategies/RangeCompressionBreakout.mqh"
#include "../../Core/Engines/TrendEngine.mqh"
#include "../../Core/Engines/StructureEngine.mqh"
#include "../../Core/Engines/LiquidityEngine.mqh"
#include "../../Core/Engines/VolatilityEngine.mqh"
#include "../../Core/Engines/RegimeEngine.mqh"
#include "../../Core/Signals/SignalDiagnostics.mqh"

class CMathematicalEngineRegistry
{
private:
    CSignalDiagnostics* m_signalDiagnostics;
    
    struct SEngineSlot
        {
            string                     symbol;
                        CHurstEngine*              hurst;
            COrnsteinUhlenbeckEngine*  ou;
            COrderFlowImbalanceEngine* ofi;
            CVPINFilter*               vpin;
                        CKalmanMeanReversion*      kalman;
            CChangepointDetector*      cpd;
            CFourStateRegimeDetector*  fourState;
            CVolatilityTargeting*      volTarget;
            // strategies with engines
            CLiquiditySweepStrategy*   liquiditySweep;
            CRangeCompressionBreakout* rangeComp;
            // Pipeline engines
            CTrendEngine*              trendEngine;
            CStructureEngine*          structureEngine;
            CLiquidityEngine*          liquidityEngine;
            CVolatilityEngine*         volatilityEngine;
            CRegimeEngine*             regimeEngine;
        
            SEngineSlot() : symbol(""), hurst(NULL), ou(NULL), ofi(NULL), vpin(NULL),
                           kalman(NULL), cpd(NULL), fourState(NULL), volTarget(NULL),
                           liquiditySweep(NULL), rangeComp(NULL),
                           trendEngine(NULL), structureEngine(NULL), liquidityEngine(NULL),
                           volatilityEngine(NULL), regimeEngine(NULL) {}
        
            ~SEngineSlot() { Clear(); }
        
            void Clear()
            {
                if(CheckPointer(hurst) == POINTER_DYNAMIC) { delete hurst; hurst = NULL; }
                if(CheckPointer(ou) == POINTER_DYNAMIC) { delete ou; ou = NULL; }
                if(CheckPointer(ofi) == POINTER_DYNAMIC) { delete ofi; ofi = NULL; }
                if(CheckPointer(vpin) == POINTER_DYNAMIC) { delete vpin; vpin = NULL; }
                if(CheckPointer(kalman) == POINTER_DYNAMIC) { delete kalman; kalman = NULL; }
                if(CheckPointer(cpd) == POINTER_DYNAMIC) { delete cpd; cpd = NULL; }
                if(CheckPointer(fourState) == POINTER_DYNAMIC) { delete fourState; fourState = NULL; }
                if(CheckPointer(volTarget) == POINTER_DYNAMIC) { delete volTarget; volTarget = NULL; }
                if(CheckPointer(liquiditySweep) == POINTER_DYNAMIC) { delete liquiditySweep; liquiditySweep = NULL; }
                if(CheckPointer(rangeComp) == POINTER_DYNAMIC) { delete rangeComp; rangeComp = NULL; }
                // Pipeline engines
                if(CheckPointer(trendEngine) == POINTER_DYNAMIC) { delete trendEngine; trendEngine = NULL; }
                if(CheckPointer(structureEngine) == POINTER_DYNAMIC) { delete structureEngine; structureEngine = NULL; }
                if(CheckPointer(liquidityEngine) == POINTER_DYNAMIC) { delete liquidityEngine; liquidityEngine = NULL; }
                if(CheckPointer(volatilityEngine) == POINTER_DYNAMIC) { delete volatilityEngine; volatilityEngine = NULL; }
                if(CheckPointer(regimeEngine) == POINTER_DYNAMIC) { delete regimeEngine; regimeEngine = NULL; }
            }
        
            bool HasAnyEngine() const
            {
                return (hurst != NULL) || (ou != NULL) || (ofi != NULL) || (vpin != NULL) || (kalman != NULL) || (cpd != NULL) || (fourState != NULL) || (volTarget != NULL) || (liquiditySweep != NULL) || (rangeComp != NULL)
                       || (trendEngine != NULL) || (structureEngine != NULL) || (liquidityEngine != NULL) || (volatilityEngine != NULL) || (regimeEngine != NULL);
            }
        };
    
    SEngineSlot m_slots[];
    int m_slotCount;
    
    public:
    CMathematicalEngineRegistry() : m_slotCount(0), m_signalDiagnostics(NULL) { ArrayResize(m_slots, 0); }
    ~CMathematicalEngineRegistry() { Clear(); }
    
    void SetSignalDiagnostics(CSignalDiagnostics* diagnostics)
    {
        m_signalDiagnostics = diagnostics; }
    
    void Clear()
    {
        ArrayResize(m_slots, 0);
        m_slotCount = 0;
    }
    
    int Count() const { return m_slotCount; }
    
    int GetSlotIndex(const string symbol, bool createIfMissing = true)
    {
        for(int i = 0; i < m_slotCount; i++)
            if(m_slots[i].symbol == symbol) return i;
        
        if(!createIfMissing) return -1;
        
        int idx = m_slotCount;
        ArrayResize(m_slots, idx + 1);
        m_slots[idx].symbol = symbol;
        m_slotCount++;
        return idx;
    }
    
    // --- Engines ---
    CHurstEngine* GetHurst(const string symbol, bool createIfMissing = true)
    {
        int idx = GetSlotIndex(symbol, createIfMissing);
        return (idx >= 0) ? m_slots[idx].hurst : NULL;
    }
    
    COrnsteinUhlenbeckEngine* GetOU(const string symbol, bool createIfMissing = true)
    {
        int idx = GetSlotIndex(symbol, createIfMissing);
        return (idx >= 0) ? m_slots[idx].ou : NULL;
    }
    
    COrderFlowImbalanceEngine* GetOFI(const string symbol, bool createIfMissing = true)
    {
        int idx = GetSlotIndex(symbol, createIfMissing);
        return (idx >= 0) ? m_slots[idx].ofi : NULL;
    }
    
    CVPINFilter* GetVPIN(const string symbol, bool createIfMissing = true)
    {
        int idx = GetSlotIndex(symbol, createIfMissing);
        return (idx >= 0) ? m_slots[idx].vpin : NULL;
    }
    
    // --- Engines ---
    CKalmanMeanReversion* GetKalman(const string symbol, bool createIfMissing = true)
    {
        int idx = GetSlotIndex(symbol, createIfMissing);
        return (idx >= 0) ? m_slots[idx].kalman : NULL;
    }
    
    CChangepointDetector* GetCPD(const string symbol, bool createIfMissing = true)
    {
        int idx = GetSlotIndex(symbol, createIfMissing);
        return (idx >= 0) ? m_slots[idx].cpd : NULL;
    }
    
    CFourStateRegimeDetector* GetFourState(const string symbol, bool createIfMissing = true)
    {
        int idx = GetSlotIndex(symbol, createIfMissing);
        return (idx >= 0) ? m_slots[idx].fourState : NULL;
    }
    
    CVolatilityTargeting* GetVolTarget(const string symbol, bool createIfMissing = true)
    {
        int idx = GetSlotIndex(symbol, createIfMissing);
        return (idx >= 0) ? m_slots[idx].volTarget : NULL;
    }
    
    // --- Strategies ---
        CLiquiditySweepStrategy* GetLiquiditySweep(const string symbol, bool createIfMissing = true)
        {
            int idx = GetSlotIndex(symbol, createIfMissing);
            return (idx >= 0) ? m_slots[idx].liquiditySweep : NULL;
        }
    
        CRangeCompressionBreakout* GetRangeComp(const string symbol, bool createIfMissing = true)
        {
            int idx = GetSlotIndex(symbol, createIfMissing);
            return (idx >= 0) ? m_slots[idx].rangeComp : NULL;
        }
    
        // --- Pipeline Engines ---
                CTrendEngine* GetTrend(const string symbol, bool createIfMissing = true)
                {
                    int idx = GetSlotIndex(symbol, createIfMissing);
                    if(idx < 0) return NULL;
                    if(m_slots[idx].trendEngine == NULL)
                    {
                        m_slots[idx].trendEngine = new CTrendEngine();
                        if(m_signalDiagnostics != NULL)
                            m_slots[idx].trendEngine.Initialize(20, 50, 200, 14, m_signalDiagnostics);
                    }
                    return m_slots[idx].trendEngine;
                }
    
                CStructureEngine* GetStructure(const string symbol, bool createIfMissing = true)
                {
                    int idx = GetSlotIndex(symbol, createIfMissing);
                    if(idx < 0) return NULL;
                    if(m_slots[idx].structureEngine == NULL)
                    {
                        m_slots[idx].structureEngine = new CStructureEngine();
                        if(m_signalDiagnostics != NULL)
                            m_slots[idx].structureEngine.Initialize(10, 10.0, true, m_signalDiagnostics);
                    }
                    return m_slots[idx].structureEngine;
                }
    
                CLiquidityEngine* GetLiquidity(const string symbol, bool createIfMissing = true)
                {
                    int idx = GetSlotIndex(symbol, createIfMissing);
                    if(idx < 0) return NULL;
                    if(m_slots[idx].liquidityEngine == NULL)
                    {
                        m_slots[idx].liquidityEngine = new CLiquidityEngine();
                        if(m_signalDiagnostics != NULL)
                            m_slots[idx].liquidityEngine.Initialize(10.0, 2, m_signalDiagnostics);
                    }
                    return m_slots[idx].liquidityEngine;
                }
    
                CVolatilityEngine* GetVolatility(const string symbol, bool createIfMissing = true)
                {
                    int idx = GetSlotIndex(symbol, createIfMissing);
                    if(idx < 0) return NULL;
                    if(m_slots[idx].volatilityEngine == NULL)
                    {
                        m_slots[idx].volatilityEngine = new CVolatilityEngine();
                        if(m_signalDiagnostics != NULL)
                            m_slots[idx].volatilityEngine.Initialize(14, 20, m_signalDiagnostics);
                    }
                    return m_slots[idx].volatilityEngine;
                }
    
                CRegimeEngine* GetRegime(const string symbol, bool createIfMissing = true)
                {
                    int idx = GetSlotIndex(symbol, createIfMissing);
                    if(idx < 0) return NULL;
                    if(m_slots[idx].regimeEngine == NULL)
                    {
                        m_slots[idx].regimeEngine = new CRegimeEngine();
                        if(m_signalDiagnostics != NULL)
                            m_slots[idx].regimeEngine.Initialize(14, 20, 2.0, 30, 120, m_signalDiagnostics);
                    }
                    return m_slots[idx].regimeEngine;
                }
    
    bool RegisterHurstEngine(const string symbol, CHurstEngine* engine)
    {
        if(symbol == "") return false;
        int idx = GetSlotIndex(symbol, true);
        m_slots[idx].hurst = engine;
        return true;
    }
    
    bool RegisterOUEngine(const string symbol, COrnsteinUhlenbeckEngine* engine)
    {
        if(symbol == "") return false;
        int idx = GetSlotIndex(symbol, true);
        m_slots[idx].ou = engine;
        return true;
    }
    
    bool RegisterOFIEngine(const string symbol, COrderFlowImbalanceEngine* engine)
    {
        if(symbol == "") return false;
        int idx = GetSlotIndex(symbol, true);
        m_slots[idx].ofi = engine;
        return true;
    }
    
    bool RegisterVPINFilter(const string symbol, CVPINFilter* engine)
    {
        if(symbol == "") return false;
        int idx = GetSlotIndex(symbol, true);
        m_slots[idx].vpin = engine;
        return true;
    }
    
    bool RegisterKalmanEngine(const string symbol, CKalmanMeanReversion* engine)
    {
        if(symbol == "") return false;
        int idx = GetSlotIndex(symbol, true);
        m_slots[idx].kalman = engine;
        return true;
    }
    
    bool RegisterCPDDetector(const string symbol, CChangepointDetector* engine)
    {
        if(symbol == "") return false;
        int idx = GetSlotIndex(symbol, true);
        m_slots[idx].cpd = engine;
        return true;
    }
    
    bool RegisterFourStateDetector(const string symbol, CFourStateRegimeDetector* engine)
    {
        if(symbol == "") return false;
        int idx = GetSlotIndex(symbol, true);
        m_slots[idx].fourState = engine;
        return true;
    }
    
    bool RegisterVolTargetEngine(const string symbol, CVolatilityTargeting* engine)
    {
        if(symbol == "") return false;
        int idx = GetSlotIndex(symbol, true);
        m_slots[idx].volTarget = engine;
        return true;
    }
    
    bool RegisterLiquiditySweepStrategy(const string symbol, CLiquiditySweepStrategy* engine)
    {
        if(symbol == "") return false;
        int idx = GetSlotIndex(symbol, true);
        m_slots[idx].liquiditySweep = engine;
        return true;
    }
    
    bool RegisterRangeCompressionStrategy(const string symbol, CRangeCompressionBreakout* engine)
    {
        if(symbol == "") return false;
        int idx = GetSlotIndex(symbol, true);
        m_slots[idx].rangeComp = engine;
        return true;
    }
    
    void RegisterAll(CHurstEngine* &hurstArr[], COrnsteinUhlenbeckEngine* &ouArr[],
                     COrderFlowImbalanceEngine* &ofiArr[], CVPINFilter* &vpinArr[],
                     CKalmanMeanReversion* &kalmanArr[], CChangepointDetector* &cpdArr[],
                     CFourStateRegimeDetector* &fourStateArr[], CVolatilityTargeting* &volTargetArr[],
                     CLiquiditySweepStrategy* &liqSweepArr[],
                     CRangeCompressionBreakout* &rangeCompArr[], const string &symbols[], int count)
    {
        for(int i = 0; i < count; i++)
        {
            if(symbols[i] == "") continue;
            if(hurstArr[i] != NULL) RegisterHurstEngine(symbols[i], hurstArr[i]);
            if(ouArr[i] != NULL) RegisterOUEngine(symbols[i], ouArr[i]);
            if(ofiArr[i] != NULL) RegisterOFIEngine(symbols[i], ofiArr[i]);
            if(vpinArr[i] != NULL) RegisterVPINFilter(symbols[i], vpinArr[i]);
            if(kalmanArr[i] != NULL) RegisterKalmanEngine(symbols[i], kalmanArr[i]);
            if(cpdArr[i] != NULL) RegisterCPDDetector(symbols[i], cpdArr[i]);
            if(fourStateArr[i] != NULL) RegisterFourStateDetector(symbols[i], fourStateArr[i]);
            if(volTargetArr[i] != NULL) RegisterVolTargetEngine(symbols[i], volTargetArr[i]);
            if(liqSweepArr[i] != NULL) RegisterLiquiditySweepStrategy(symbols[i], liqSweepArr[i]);
            if(rangeCompArr[i] != NULL) RegisterRangeCompressionStrategy(symbols[i], rangeCompArr[i]);
        }
    }
    
            // Initialize pipeline engines with SignalDiagnostics
            void InitializePipelineEngines(const string symbol, ENUM_TIMEFRAMES timeframe = PERIOD_M15)
            {
                int idx = GetSlotIndex(symbol, false);
                if(idx < 0) return;
        
                // Initialize Trend Engine
                if(m_slots[idx].trendEngine != NULL)
                {
                    m_slots[idx].trendEngine.Initialize(20, 50, 200, 14, m_signalDiagnostics);
                }
        
                // Initialize Structure Engine
                if(m_slots[idx].structureEngine != NULL)
                {
                    m_slots[idx].structureEngine.Initialize(10, 10.0, true, m_signalDiagnostics);
                }
        
                // Initialize Liquidity Engine
                if(m_slots[idx].liquidityEngine != NULL)
                {
                    m_slots[idx].liquidityEngine.Initialize(10.0, 2, m_signalDiagnostics);
                }
        
                // Initialize Volatility Engine
                if(m_slots[idx].volatilityEngine != NULL)
                {
                    m_slots[idx].volatilityEngine.Initialize(14, 20, m_signalDiagnostics);
                }
        
                // Initialize Regime Engine
                                                if(m_slots[idx].regimeEngine != NULL)
                                                {
                                                    m_slots[idx].regimeEngine.Initialize(14, 20, 2.0, 30, 120, m_signalDiagnostics);
                                                }
                            }
    
                    // Initialize pipeline engines for all symbols in array
                    void InitializePipelineEngines(const string &symbols[], int count, ENUM_TIMEFRAMES timeframe = PERIOD_M15)
                    {
                        for(int i = 0; i < count; i++)
                        {
                            if(symbols[i] != "")
                            {
                                InitializePipelineEngines(symbols[i], timeframe);
                            }
                        }
                    }
    
                    void ReleaseSymbol(const string symbol)
    {
        int idx = GetSlotIndex(symbol, false);
        if(idx >= 0)
        {
            for(int i = idx; i < m_slotCount - 1; i++)
                m_slots[i] = m_slots[i + 1];
            ArrayResize(m_slots, m_slotCount - 1);
            m_slotCount--;
        }
    }
    
};

#endif // CORE_REGISTRY_MATHEMATICAL_ENGINE_REGISTRY_MQH
