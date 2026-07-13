//+------------------------------------------------------------------+
//| InstitutionalEngineRegistry.mqh                                  |
//| Consolidates VWAP, Volume Profile, CVD engines                   |
//+------------------------------------------------------------------+
#property strict

#ifndef CORE_REGISTRY_INSTITUTIONAL_ENGINE_REGISTRY_MQH
#define CORE_REGISTRY_INSTITUTIONAL_ENGINE_REGISTRY_MQH

#include "../../Core/Engines/VWAPEngine.mqh"
#include "../../Core/Engines/VolumeProfileEngine.mqh"
#include "../../Core/Engines/CVDEngine.mqh"

class CInstitutionalEngineRegistry
{
private:
    struct SEngineSlot
    {
        string                    symbol;
        CVWAPEngine*              vwap;
        CVolumeProfileEngine*     vp;
        CCVDEngine*               cvd;
        
        SEngineSlot() : symbol(""), vwap(NULL), vp(NULL), cvd(NULL) {}
        
        ~SEngineSlot()
        {
            if(CheckPointer(vwap) == POINTER_DYNAMIC) { delete vwap; vwap = NULL; }
            if(CheckPointer(vp) == POINTER_DYNAMIC) { delete vp; vp = NULL; }
            if(CheckPointer(cvd) == POINTER_DYNAMIC) { delete cvd; cvd = NULL; }
        }
        
        bool HasAnyEngine() const
        {
            return (vwap != NULL) || (vp != NULL) || (cvd != NULL);
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
    
    void EnsureEngines(const string symbol, ENUM_TIMEFRAMES timeframe)
    {
        int idx = GetSlotIndex(symbol);
        SEngineSlot slot = m_slots[idx];
        
        if(slot.vwap == NULL)
        {
            slot.vwap = new CVWAPEngine();
            if(slot.vwap != NULL) slot.vwap.Initialize(symbol, 30);
        }
        
        if(slot.vp == NULL)
        {
            slot.vp = new CVolumeProfileEngine();
            if(slot.vp != NULL) slot.vp.Initialize(symbol, 20);
        }
        
        if(slot.cvd == NULL)
        {
            slot.cvd = new CCVDEngine();
            if(slot.cvd != NULL) slot.cvd.Initialize(symbol, 30);
        }
        
        m_slots[idx] = slot;
    }

public:
    CInstitutionalEngineRegistry() : m_slotCount(0) { ArrayResize(m_slots, 0); }
    
    ~CInstitutionalEngineRegistry()
    {
        Clear();
    }
    
    void Clear()
    {
        ArrayResize(m_slots, 0);
        m_slotCount = 0;
    }
    
    bool InitializeSymbol(const string symbol, ENUM_TIMEFRAMES timeframe)
    {
        if(symbol == "") return false;
        EnsureEngines(symbol, timeframe);
        return true;
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
    
    CVWAPEngine* GetVWAP(const string symbol)
    {
        int idx = GetSlotIndex(symbol, false);
        return (idx >= 0) ? m_slots[idx].vwap : NULL;
    }
    
    CVolumeProfileEngine* GetVP(const string symbol)
    {
        int idx = GetSlotIndex(symbol, false);
        return (idx >= 0) ? m_slots[idx].vp : NULL;
    }
    
    CCVDEngine* GetCVD(const string symbol)
    {
        int idx = GetSlotIndex(symbol, false);
        return (idx >= 0) ? m_slots[idx].cvd : NULL;
    }
    
    void OnNewBarAll(ENUM_TIMEFRAMES timeframe)
    {
        for(int i = 0; i < m_slotCount; i++)
        {
            // VWAP, VP, CVD don't have OnNewBar - they calculate on demand
            // This method kept for compatibility
        }
    }
    
    void OnTickAll(const string symbol, double price, double volume, double bid, double ask)
    {
        int idx = GetSlotIndex(symbol, false);
        if(idx < 0) return;
        
        // CVD is calculated per bar, not per tick
        // if(m_slots[idx].cvd != NULL)
        // {
        //     m_slots[idx].cvd.Calculate();
        // }
    }
    
    string GetStatusReport() const
    {
        string report = "[InstitutionalEngineRegistry] Active symbols: " + IntegerToString(m_slotCount) + "\n";
        for(int i = 0; i < m_slotCount; i++)
        {
            if(!m_slots[i].HasAnyEngine()) continue;
            report += "  " + m_slots[i].symbol + ": ";
            if(m_slots[i].vwap) report += "VWAP ";
            if(m_slots[i].vp) report += "VP ";
            if(m_slots[i].cvd) report += "CVD ";
            report += "\n";
        }
        return report;
    }
};

#endif // CORE_REGISTRY_INSTITUTIONAL_ENGINE_REGISTRY_MQH