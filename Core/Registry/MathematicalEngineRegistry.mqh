//+------------------------------------------------------------------+
//| MathematicalEngineRegistry.mqh                                   |
//| Consolidates all mathematical engines per symbol                 |
//+------------------------------------------------------------------+
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
#include "../../Core/Processing/ExitOptimizer.mqh"
#include "../../Strategies/LiquiditySweepStrategy.mqh"
#include "../../Strategies/RangeCompressionBreakout.mqh"

class CMathematicalEngineRegistry
{
private:
    struct SEngineSlot
    {
        string                     symbol;
        // Batch 101/102
        CHurstEngine*              hurst;
        COrnsteinUhlenbeckEngine*  ou;
        COrderFlowImbalanceEngine* ofi;
        CVPINFilter*               vpin;
        // Batch 114
        CKalmanMeanReversion*      kalman;
        CChangepointDetector*      cpd;
        CFourStateRegimeDetector*  fourState;
        CVolatilityTargeting*      volTarget;
        CExitOptimizer*            exitOptimizer;
        // Batch 103 strategies with engines
        CLiquiditySweepStrategy*   liquiditySweep;
        CRangeCompressionBreakout* rangeComp;
        
        SEngineSlot() : symbol(""), hurst(NULL), ou(NULL), ofi(NULL), vpin(NULL),
                       kalman(NULL), cpd(NULL), fourState(NULL), volTarget(NULL),
                       exitOptimizer(NULL), liquiditySweep(NULL), rangeComp(NULL) {}
        
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
            if(CheckPointer(exitOptimizer) == POINTER_DYNAMIC) { delete exitOptimizer; exitOptimizer = NULL; }
            if(CheckPointer(liquiditySweep) == POINTER_DYNAMIC) { delete liquiditySweep; liquiditySweep = NULL; }
            if(CheckPointer(rangeComp) == POINTER_DYNAMIC) { delete rangeComp; rangeComp = NULL; }
        }
        
        bool HasAnyEngine() const
        {
            return (hurst != NULL) || (ou != NULL) || (ofi != NULL) || (vpin != NULL) || (kalman != NULL) || (cpd != NULL) || (fourState != NULL) || (volTarget != NULL) || (exitOptimizer != NULL) || (liquiditySweep != NULL) || (rangeComp != NULL);
        }
    };
    
    SEngineSlot m_slots[];
    int m_slotCount;
    
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

public:
    CMathematicalEngineRegistry() : m_slotCount(0) { ArrayResize(m_slots, 0); }
    ~CMathematicalEngineRegistry() { Clear(); }
    
    void Clear()
    {
        ArrayResize(m_slots, 0);
        m_slotCount = 0;
    }
    
    // --- Batch 101/102 Engines ---
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
    
    // --- Batch 114 Engines ---
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
    
    CExitOptimizer* GetExitOptimizer(const string symbol, bool createIfMissing = true)
    {
        int idx = GetSlotIndex(symbol, createIfMissing);
        return (idx >= 0) ? m_slots[idx].exitOptimizer : NULL;
    }
    
    // --- Batch 103 Strategies ---
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
    
    // Bulk initialization for a symbol
    void EnsureEngines(const string symbol,
                       bool needHurst, bool needOU, bool needOFI, bool needVPIN,
                       bool needKalman, bool needCPD, bool needFourState, bool needVolTarget,
                       bool needExitOptimizer, bool needLiquiditySweep, bool needRangeComp,
                       ENUM_TIMEFRAMES timeframe = PERIOD_M15)
    {
        if(symbol == "") return;
        int idx = GetSlotIndex(symbol, true);
        
        if(needHurst && m_slots[idx].hurst == NULL) m_slots[idx].hurst = new CHurstEngine();
        if(needOU && m_slots[idx].ou == NULL) m_slots[idx].ou = new COrnsteinUhlenbeckEngine(symbol, timeframe, 100, 0.05);
        if(needOFI && m_slots[idx].ofi == NULL) m_slots[idx].ofi = new COrderFlowImbalanceEngine();
        if(needVPIN && m_slots[idx].vpin == NULL) m_slots[idx].vpin = new CVPINFilter(symbol);
        if(needKalman && m_slots[idx].kalman == NULL) m_slots[idx].kalman = new CKalmanMeanReversion();
        if(needCPD && m_slots[idx].cpd == NULL) m_slots[idx].cpd = new CChangepointDetector(symbol);
        if(needFourState && m_slots[idx].fourState == NULL) m_slots[idx].fourState = new CFourStateRegimeDetector(symbol);
        if(needVolTarget && m_slots[idx].volTarget == NULL) m_slots[idx].volTarget = new CVolatilityTargeting(symbol);
        if(needExitOptimizer && m_slots[idx].exitOptimizer == NULL) m_slots[idx].exitOptimizer = new CExitOptimizer();
        if(needLiquiditySweep && m_slots[idx].liquiditySweep == NULL) m_slots[idx].liquiditySweep = new CLiquiditySweepStrategy();
        if(needRangeComp && m_slots[idx].rangeComp == NULL) m_slots[idx].rangeComp = new CRangeCompressionBreakout();
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
    
    // Diagnostic
    string GetStatusReport() const
    {
        string report = "[MathEngineRegistry] Active symbols: " + IntegerToString(m_slotCount) + "\n";
        for(int i = 0; i < m_slotCount; i++)
        {
            if(!m_slots[i].HasAnyEngine()) continue;
            report += "  " + m_slots[i].symbol + ": ";
            if(m_slots[i].hurst) report += "Hurst ";
            if(m_slots[i].ou) report += "OU ";
            if(m_slots[i].ofi) report += "OFI ";
            if(m_slots[i].vpin) report += "VPIN ";
            if(m_slots[i].kalman) report += "Kalman ";
            if(m_slots[i].cpd) report += "CPD ";
            if(m_slots[i].fourState) report += "4State ";
            if(m_slots[i].volTarget) report += "VolTgt ";
            if(m_slots[i].exitOptimizer) report += "ExitOpt ";
            if(m_slots[i].liquiditySweep) report += "LiqSweep ";
            if(m_slots[i].rangeComp) report += "RangeComp ";
            report += "\n";
        }
        return report;
    }
    
void OnTickAll(const string symbol, double price, double volume, double bid, double ask)
    {
        int idx = GetSlotIndex(symbol, false);
        if(idx < 0) return;
        
        if(m_slots[idx].ofi != NULL)
        {
            m_slots[idx].ofi.OnTick(price, volume, bid, ask);
        }
        if(m_slots[idx].vpin != NULL)
        {
            // VPINFilter takes (price, volume) not (bid, ask, volume)
            m_slots[idx].vpin.OnTick(price, volume);
        }
        if(m_slots[idx].kalman != NULL)
        {
            m_slots[idx].kalman.FLSUpdate(price);
        }
    }
};

#endif // CORE_REGISTRY_MATHEMATICAL_ENGINE_REGISTRY_MQH