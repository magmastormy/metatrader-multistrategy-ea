//+------------------------------------------------------------------+
//| DrawingManagerRegistry.mqh                                       |
//| Consolidates ChartDrawingManager instances per symbol            |
//+------------------------------------------------------------------+
#property strict

#ifndef CORE_REGISTRY_DRAWING_MANAGER_REGISTRY_MQH
#define CORE_REGISTRY_DRAWING_MANAGER_REGISTRY_MQH

#include "../../Core/Visualization/ChartDrawingManager.mqh"

class CDrawingManagerRegistry
{
private:
    struct SDrawingEntry
    {
        string                    symbol;
        CChartDrawingManager*     drawingManager;
        int                       objectCount;
        
        SDrawingEntry() : symbol(""), drawingManager(NULL), objectCount(0) {}
        
        ~SDrawingEntry()
        {
            if(CheckPointer(drawingManager) == POINTER_DYNAMIC) { delete drawingManager; drawingManager = NULL; }
        }
    };
    
    SDrawingEntry m_entries[];
    int m_entryCount;
    
    int GetIndex(const string symbol, bool createIfMissing = true)
    {
        for(int i = 0; i < m_entryCount; i++)
            if(m_entries[i].symbol == symbol) return i;
        
        if(!createIfMissing) return -1;
        
        int idx = m_entryCount;
        ArrayResize(m_entries, idx + 1);
        m_entries[idx].symbol = symbol;
        m_entryCount++;
        return idx;
    }

public:
    CDrawingManagerRegistry() : m_entryCount(0) { ArrayResize(m_entries, 0); }
    ~CDrawingManagerRegistry() { Clear(); }
    
    void Clear()
    {
        ArrayResize(m_entries, 0);
        m_entryCount = 0;
    }
    
    CChartDrawingManager* GetOrCreateManager(const string symbol, ENUM_TIMEFRAMES timeframe = PERIOD_CURRENT, const string prefix = "")
    {
        if(symbol == "") return NULL;
        
        int idx = GetIndex(symbol);
        if(idx < 0) return NULL;
        
        SDrawingEntry entry = m_entries[idx];
        
        if(entry.drawingManager == NULL)
        {
            entry.drawingManager = new CChartDrawingManager();
            if(entry.drawingManager != NULL)
            {
                entry.drawingManager.Initialize(symbol, timeframe, prefix);
                Print("[DrawingManagerRegistry] Drawing manager created for ", symbol);
            }
            m_entries[idx] = entry;
        }
        
        return entry.drawingManager;
    }
    
    CChartDrawingManager* GetManager(const string symbol)
    {
        int idx = GetIndex(symbol, false);
        return (idx >= 0) ? m_entries[idx].drawingManager : NULL;
    }
    
    void ReleaseSymbol(const string symbol)
    {
        int idx = GetIndex(symbol, false);
        if(idx >= 0)
        {
            for(int i = idx; i < m_entryCount - 1; i++)
                m_entries[i] = m_entries[i + 1];
            ArrayResize(m_entries, m_entryCount - 1);
            m_entryCount--;
        }
    }
    
    void UpdateObjectCounts()
    {
        for(int i = 0; i < m_entryCount; i++)
        {
            if(m_entries[i].drawingManager != NULL)
            {
                m_entries[i].objectCount = m_entries[i].drawingManager.GetObjectCount();
            }
        }
    }
    
    int GetTotalObjectCount() const
    {
        int total = 0;
        for(int i = 0; i < m_entryCount; i++)
            total += m_entries[i].objectCount;
        return total;
    }
    
    string GetStatusReport() const
    {
        string report = "[DrawingManagerRegistry] Active symbols: " + IntegerToString(m_entryCount) + " | Total objects: " + IntegerToString(GetTotalObjectCount()) + "\n";
        for(int i = 0; i < m_entryCount; i++)
        {
            report += "  " + m_entries[i].symbol + ": " + IntegerToString(m_entries[i].objectCount) + " objects\n";
        }
        return report;
    }
};

#endif // CORE_REGISTRY_DRAWING_MANAGER_REGISTRY_MQH