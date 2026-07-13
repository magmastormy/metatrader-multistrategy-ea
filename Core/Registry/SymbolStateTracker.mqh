//+------------------------------------------------------------------+
//| SymbolStateTracker.mqh                                           |
//| Consolidates per-symbol state: scalp blacklist, dormancy, etc.   |
//+------------------------------------------------------------------+
#property strict

#ifndef CORE_REGISTRY_SYMBOL_STATE_TRACKER_MQH
#define CORE_REGISTRY_SYMBOL_STATE_TRACKER_MQH

#include "../../Core/Utils/Enums.mqh"

class CSymbolStateTracker
{
private:
    struct SSymbolState
    {
        string symbol;
        
        // Scalp blacklist
        int scalpFailCount;
        bool scalpBlacklisted;
        datetime scalpBlacklistDay;
        
        // Dormancy cooldown
        int dormantConsecutiveCount;
        datetime dormantCooldownUntil;
        
        // General
        datetime lastUpdate;
        
        SSymbolState() : symbol(""), scalpFailCount(0), scalpBlacklisted(false), 
                         scalpBlacklistDay(0), dormantConsecutiveCount(0), 
                         dormantCooldownUntil(0), lastUpdate(0) {}
    };
    
    SSymbolState m_states[];
    int m_stateCount;
    
    // Thresholds
    enum
    {
        SCALP_BLACKLIST_THRESHOLD = 5,
        DORMANT_COOLDOWN_THRESHOLD = 3,
        DORMANT_COOLDOWN_MINUTES = 30
    };
    
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
    CSymbolStateTracker() : m_stateCount(0) { ArrayResize(m_states, 0); }
    ~CSymbolStateTracker() { Clear(); }
    
    void Clear()
    {
        ArrayResize(m_states, 0);
        m_stateCount = 0;
    }
    
    // --- Scalp Blacklist ---
    bool IsScalpBlacklisted(const string symbol)
    {
        int idx = GetIndex(symbol);
        if(idx < 0) return false;
        
        // Clear on new day
        datetime today = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
        if(m_states[idx].scalpBlacklistDay != today)
        {
            m_states[idx].scalpFailCount = 0;
            m_states[idx].scalpBlacklisted = false;
            m_states[idx].scalpBlacklistDay = today;
        }
        
        return m_states[idx].scalpBlacklisted;
    }
    
    void RecordScalpCostFailure(const string symbol)
    {
        int idx = GetIndex(symbol);
        if(idx < 0) return;
        
        datetime today = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
        if(m_states[idx].scalpBlacklistDay != today)
        {
            m_states[idx].scalpFailCount = 0;
            m_states[idx].scalpBlacklisted = false;
            m_states[idx].scalpBlacklistDay = today;
        }
        
        m_states[idx].scalpFailCount++;
        if(m_states[idx].scalpFailCount >= SCALP_BLACKLIST_THRESHOLD && !m_states[idx].scalpBlacklisted)
        {
            m_states[idx].scalpBlacklisted = true;
            PrintFormat("[SCALP-BLACKLIST] %s | %d consecutive spread cost failures | blacklisted for session",
                        symbol, m_states[idx].scalpFailCount);
        }
    }
    
    void ResetScalpBlacklist(const string symbol)
    {
        int idx = GetIndex(symbol, false);
        if(idx >= 0)
        {
            m_states[idx].scalpFailCount = 0;
            m_states[idx].scalpBlacklisted = false;
        }
    }
    
    // --- Dormancy Cooldown ---
    bool IsInDormantCooldown(const string symbol)
    {
        int idx = GetIndex(symbol, false);
        if(idx < 0) return false;
        
        if(m_states[idx].dormantCooldownUntil <= 0) return false;
        return (TimeCurrent() < m_states[idx].dormantCooldownUntil);
    }
    
    void RecordDormantWarning(const string symbol)
    {
        int idx = GetIndex(symbol);
        if(idx < 0) return;
        
        m_states[idx].dormantConsecutiveCount++;
        if(m_states[idx].dormantConsecutiveCount >= DORMANT_COOLDOWN_THRESHOLD)
        {
            m_states[idx].dormantCooldownUntil = TimeCurrent() + DORMANT_COOLDOWN_MINUTES * 60;
            PrintFormat("[DORMANT-COOLDOWN] %s | %d consecutive dormancy warnings | skipping for %d minutes",
                        symbol, m_states[idx].dormantConsecutiveCount, DORMANT_COOLDOWN_MINUTES);
        }
    }
    
    void ClearDormantCooldownOnNewBar(const string symbol)
    {
        int idx = GetIndex(symbol, false);
        if(idx >= 0)
        {
            m_states[idx].dormantConsecutiveCount = 0;
            m_states[idx].dormantCooldownUntil = 0;
        }
    }
    
    // --- General ---
    void UpdateLastActivity(const string symbol)
    {
        int idx = GetIndex(symbol);
        if(idx < 0) return;
        
        m_states[idx].lastUpdate = TimeCurrent();
    }
    
    datetime GetLastActivity(const string symbol)
    {
        int idx = GetIndex(symbol, false);
        return (idx >= 0) ? m_states[idx].lastUpdate : 0;
    }
    
    // Diagnostic
    string GetStatusReport() const
    {
        string report = "[SymbolStateTracker] Tracked symbols: " + IntegerToString(m_stateCount) + "\n";
        for(int i = 0; i < m_stateCount; i++)
        {
            report += "  " + m_states[i].symbol + ": ";
            if(m_states[i].scalpBlacklisted) report += "SCALP_BLACKLISTED ";
            if(m_states[i].dormantCooldownUntil > TimeCurrent()) report += "DORMANT_COOLDOWN ";
            report += "\n";
        }
        return report;
    }
};

#endif // CORE_REGISTRY_SYMBOL_STATE_TRACKER_MQH