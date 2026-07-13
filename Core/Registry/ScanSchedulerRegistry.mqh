//+------------------------------------------------------------------+
//| ScanSchedulerRegistry.mqh                                        |
//| Consolidates symbol scanning and scheduling logic                |
//+------------------------------------------------------------------+
#property strict

#ifndef CORE_REGISTRY_SCAN_SCHEDULER_REGISTRY_MQH
#define CORE_REGISTRY_SCAN_SCHEDULER_REGISTRY_MQH

#include "../../Core/Processing/SymbolScanScheduler.mqh"
#include "../../Core/Utils/Enums.mqh"

class CScanSchedulerRegistry
{
private:
    struct SSymbolScanState
    {
        string                        symbol;
        datetime                      lastBarTime;
        datetime                      lastIntrabarScanTime;
        bool                          pendingNewBarScan;
        int                           intrabarBackoffSeconds;
        int                           dormancyWarningCount;
        datetime                      dormantCooldownUntil;
        int                           scalpBlacklistFailCount;
        bool                          scalpBlacklisted;
        int                           scalpBlacklistDay;
        int                           externalCapacityLogThrottle;
        
        SSymbolScanState() : symbol(""), lastBarTime(0), lastIntrabarScanTime(0), 
                            pendingNewBarScan(false), intrabarBackoffSeconds(0),
                            dormancyWarningCount(0), dormantCooldownUntil(0),
                            scalpBlacklistFailCount(0), scalpBlacklisted(false), 
                            scalpBlacklistDay(0), externalCapacityLogThrottle(0) {}
    };
    
    SSymbolScanState m_states[];
    int m_stateCount;
    
    int GetIndex(const string symbol, bool createIfMissing = true)
    {
        for(int i = 0; i < m_stateCount; i++)
            if(m_states[i].symbol == symbol) return i;
        
        if(!createIfMissing) return -1;
        
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
    
    // New bar detection
    bool CheckNewBar(const string symbol, datetime currentBarTime)
    {
        if(symbol == "") return false;
        
        int idx = GetIndex(symbol);
        if(idx < 0) return false;
        
        if(m_states[idx].lastBarTime != currentBarTime)
        {
            m_states[idx].lastBarTime = currentBarTime;
            m_states[idx].pendingNewBarScan = true;
            m_states[idx].intrabarBackoffSeconds = 0;
            return true;
        }
        return false;
    }
    
    bool IsPendingNewBar(const string symbol)
    {
        int idx = GetIndex(symbol, false);
        return (idx >= 0) ? m_states[idx].pendingNewBarScan : false;
    }
    
    void SetPendingNewBar(const string symbol, bool pending)
    {
        int idx = GetIndex(symbol, false);
        if(idx >= 0) m_states[idx].pendingNewBarScan = pending;
    }
    
    datetime GetLastBarTime(const string symbol)
    {
        int idx = GetIndex(symbol, false);
        return (idx >= 0) ? m_states[idx].lastBarTime : 0;
    }
    
    // Intrabar scheduling
    void SetLastIntrabarScanTime(const string symbol, datetime time)
    {
        int idx = GetIndex(symbol, false);
        if(idx >= 0) m_states[idx].lastIntrabarScanTime = time;
    }
    
    datetime GetLastIntrabarScanTime(const string symbol)
    {
        int idx = GetIndex(symbol, false);
        return (idx >= 0) ? m_states[idx].lastIntrabarScanTime : 0;
    }
    
    int GetIntrabarBackoffSeconds(const string symbol)
    {
        int idx = GetIndex(symbol, false);
        return (idx >= 0) ? m_states[idx].intrabarBackoffSeconds : 0;
    }
    
    void SetIntrabarBackoffSeconds(const string symbol, int seconds)
    {
        int idx = GetIndex(symbol, false);
        if(idx >= 0) m_states[idx].intrabarBackoffSeconds = seconds;
    }
    
    void ResetIntrabarBackoff(const string symbol)
    {
        int idx = GetIndex(symbol, false);
        if(idx >= 0) m_states[idx].intrabarBackoffSeconds = 0;
    }
    
    // Dormancy tracking
    void RecordDormancyWarning(const string symbol, int threshold, int cooldownMinutes)
    {
        int idx = GetIndex(symbol, false);
        if(idx < 0) return;
        
        m_states[idx].dormancyWarningCount++;
        
        if(m_states[idx].dormancyWarningCount >= threshold)
        {
            m_states[idx].dormantCooldownUntil = TimeCurrent() + cooldownMinutes * 60;
            PrintFormat("[DORMANT-COOLDOWN] %s | %d consecutive warnings | skipping for %d minutes",
                        symbol, m_states[idx].dormancyWarningCount, cooldownMinutes);
        }
    }
    
    bool IsInDormantCooldown(const string symbol)
    {
        int idx = GetIndex(symbol, false);
        if(idx < 0) return false;
        if(m_states[idx].dormantCooldownUntil <= 0) return false;
        return TimeCurrent() < m_states[idx].dormantCooldownUntil;
    }
    
    void ClearDormantCooldownOnNewBar(const string symbol)
    {
        int idx = GetIndex(symbol, false);
        if(idx >= 0)
        {
            m_states[idx].dormancyWarningCount = 0;
            m_states[idx].dormantCooldownUntil = 0;
        }
    }
    
    // Scalp blacklist
    void RecordScalpCostFailure(const string symbol, int threshold)
    {
        int idx = GetIndex(symbol, false);
        if(idx < 0) return;
        
        m_states[idx].scalpBlacklistFailCount++;
        
        if(m_states[idx].scalpBlacklistFailCount >= threshold)
        {
            m_states[idx].scalpBlacklisted = true;
            datetime today = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
            m_states[idx].scalpBlacklistDay = (int)today;
            PrintFormat("[SCALP-BLACKLIST] %s | %d consecutive failures | blacklisted for session",
                        symbol, m_states[idx].scalpBlacklistFailCount);
        }
    }
    
    bool IsScalpBlacklisted(const string symbol)
    {
        int idx = GetIndex(symbol, false);
        if(idx < 0) return false;
        
        // Check if new day - reset
        datetime today = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
        if(m_states[idx].scalpBlacklistDay != (int)today)
        {
            m_states[idx].scalpBlacklistFailCount = 0;
            m_states[idx].scalpBlacklisted = false;
            m_states[idx].scalpBlacklistDay = (int)today;
        }
        
        return m_states[idx].scalpBlacklisted;
    }
    
    void ResetScalpBlacklistCount(const string symbol)
    {
        int idx = GetIndex(symbol, false);
        if(idx >= 0) m_states[idx].scalpBlacklistFailCount = 0;
    }
    
    // External capacity logging throttle
    bool CanLogExternalCapacity(const string symbol)
    {
        int idx = GetIndex(symbol, false);
        if(idx < 0) return true;
        
        if(m_states[idx].externalCapacityLogThrottle == 0) return true;
        return (TimeCurrent() - m_states[idx].externalCapacityLogThrottle) >= 60;
    }
    
    void SetExternalCapacityLogTime(const string symbol)
    {
        int idx = GetIndex(symbol, false);
        if(idx >= 0) m_states[idx].externalCapacityLogThrottle = TimeCurrent();
    }
    
    // Release symbol
    void ReleaseSymbol(const string symbol)
    {
        int idx = GetIndex(symbol, false);
        if(idx >= 0)
        {
            for(int i = idx; i < m_stateCount - 1; i++)
                m_states[i] = m_states[i + 1];
            ArrayResize(m_states, m_stateCount - 1);
            m_stateCount--;
        }
    }
    
    // Diagnostics
    int GetPendingNewBarCount() const
    {
        int count = 0;
        for(int i = 0; i < m_stateCount; i++)
            if(m_states[i].pendingNewBarScan) count++;
        return count;
    }
    
    string GetStatusReport() const
    {
        string report = "[ScanSchedulerRegistry] Symbols: " + IntegerToString(m_stateCount) + "\n";
        for(int i = 0; i < m_stateCount; i++)
        {
            report += "  " + m_states[i].symbol + ": ";
            report += "lastBar=" + TimeToString(m_states[i].lastBarTime, TIME_SECONDS);
            report += " pending=" + (m_states[i].pendingNewBarScan ? "Y" : "N");
            report += " dormant=" + (m_states[i].dormantCooldownUntil > TimeCurrent() ? "Y" : "N");
            report += " scalpBL=" + (m_states[i].scalpBlacklisted ? "Y" : "N");
            report += "\n";
        }
        return report;
    }
};

#endif // CORE_REGISTRY_SCAN_SCHEDULER_REGISTRY_MQH