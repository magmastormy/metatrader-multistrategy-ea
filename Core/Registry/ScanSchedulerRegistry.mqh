// Remembers which bar each symbol was last seen on, so ProcessNewBars handles a bar once.
#property strict

#ifndef CORE_REGISTRY_SCAN_SCHEDULER_REGISTRY_MQH
#define CORE_REGISTRY_SCAN_SCHEDULER_REGISTRY_MQH

#include "../../Core/Utils/Enums.mqh"

class CScanSchedulerRegistry
{
private:
    struct SSymbolScanState
    {
        string                        symbol;
        datetime                      lastBarTime;

        SSymbolScanState() : symbol(""), lastBarTime(0) {}
    };

    SSymbolScanState m_states[];
    int m_stateCount;

    int GetIndex(const string symbol)
    {
        for(int i = 0; i < m_stateCount; i++)
            if(m_states[i].symbol == symbol) return i;

        int idx = m_stateCount;
        ArrayResize(m_states, idx + 1);
        m_states[idx].symbol = symbol;
        m_stateCount++;
        return idx;
    }

public:
    CScanSchedulerRegistry() : m_stateCount(0) { ArrayResize(m_states, 0); }
    ~CScanSchedulerRegistry() { Clear(); }

    void Clear() { ArrayResize(m_states, 0); m_stateCount = 0; }

    int Count() const { return m_stateCount; }

    bool CheckNewBar(const string symbol, datetime currentBarTime)
    {
        if(symbol == "") return false;

        int idx = GetIndex(symbol);
        if(m_states[idx].lastBarTime != currentBarTime)
        {
            m_states[idx].lastBarTime = currentBarTime;
            return true;
        }
        return false;
    }

    string GetStatusReport() const
    {
        string report = "[ScanSchedulerRegistry] Symbols: " + IntegerToString(m_stateCount) + "\n";
        for(int i = 0; i < m_stateCount; i++)
            report += "  " + m_states[i].symbol + ": lastBar="
                    + TimeToString(m_states[i].lastBarTime, TIME_SECONDS) + "\n";
        return report;
    }
};

#endif // CORE_REGISTRY_SCAN_SCHEDULER_REGISTRY_MQH