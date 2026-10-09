// Live symbol health monitoring - detect frozen feeds, spread spikes
#property strict
#ifndef CORE_MONITORING_SYMBOL_HEALTH_MONITOR_MQH
#define CORE_MONITORING_SYMBOL_HEALTH_MONITOR_MQH

#include <Arrays/ArrayObj.mqh>
#include "../Utils/StructuredLogger.mqh"
#include "../Utils/LogMacros.mqh"
#include "../Utils/Enums.mqh"

// Symbol Health Data Structure
struct SSymbolHealth
{
    string symbol;
    datetime lastTickTime;
    ulong  lastTickMs;
    int    tickCount;
    double currentSpread;
    double avgSpread;
    double maxSpread;
    double minSpread;
    int    spreadSpikes;
    int    spreadSpikeCount;
    bool   isStale;
    bool   isFrozen;
    bool   tradingAllowed;
    datetime lastAlertTime;
    int    alertCount;
    double spreadEma;
    int    emaInitialized;
    
    SSymbolHealth() : symbol(""), lastTickTime(0), lastTickMs(0), tickCount(0),
                      currentSpread(0), avgSpread(0), maxSpread(0), minSpread(0),
                      spreadSpikes(0), spreadSpikeCount(0), isStale(false), isFrozen(false),
                      tradingAllowed(true), lastAlertTime(0), alertCount(0),
                      spreadEma(0), emaInitialized(0) {}
};

// String wrapper for array storage
class CStringWrapper : public CObject
{
private:
    string m_value;
public:
    CStringWrapper(string value = "") : m_value(value) {}
    string Value() const { return m_value; }
    void Value(string v) { m_value = v; }
    virtual int Compare(const CObject* node, const int mode = 0) const override { return 0; }
};

class CSymbolHealthMonitor
{
private:
    // Simple parallel arrays for symbol health data (MQL5 limitation: no map iteration)
    string m_symbols[100];
    CStringWrapper m_healthData[100];
    int    m_symbolCount;
    
    int    m_staleThresholdSec;
    int    m_frozenThresholdSec;
    double m_spreadSpikeMultiplier;
    int    m_alertCooldownSec;
    bool   m_enabled;
    bool   m_autoDisableTrading;
    
    // Stats
    int    m_totalSymbols;
    int    m_healthySymbols;
    int    m_staleSymbols;
    int    m_frozenSymbols;
    
    int FindSymbolIndex(string symbol) {
        for(int i = 0; i < m_symbolCount; i++) {
            if(m_symbols[i] == symbol) return i;
        }
        return -1;
    }
    
    // Add new symbol
    int AddSymbol(string symbol) {
        if(m_symbolCount >= ArraySize(m_symbols)) return -1;
        m_symbols[m_symbolCount] = symbol;
        m_healthData[m_symbolCount] = CStringWrapper("");
        return m_symbolCount++;
    }

public:
    CSymbolHealthMonitor() : m_staleThresholdSec(30), m_frozenThresholdSec(120),
                             m_spreadSpikeMultiplier(3.0), m_alertCooldownSec(300),
                             m_enabled(true), m_autoDisableTrading(true),
                             m_totalSymbols(0), m_healthySymbols(0), m_staleSymbols(0), m_frozenSymbols(0),
                             m_symbolCount(0) {}
    
    ~CSymbolHealthMonitor() {
        // m_healthData holds objects (not pointers), no manual cleanup needed
        // The CStringWrapper objects will be destroyed automatically
    }
    
    // Initialize with thresholds
    void Init(int staleSec = 30, int frozenSec = 120, double spikeMult = 3.0, 
              int alertCooldown = 300, bool autoDisable = true) {
        m_staleThresholdSec = staleSec;
        m_frozenThresholdSec = frozenSec;
        m_spreadSpikeMultiplier = spikeMult;
        m_alertCooldownSec = alertCooldown;
        m_autoDisableTrading = autoDisable;
        m_enabled = true;
        
        Print("[SYM-HEALTH] Initialized: stale=", staleSec, "s frozen=", frozenSec, 
              "s spikeMult=", DoubleToString(spikeMult, 2), " autoDisable=", autoDisable);
        g_structLog.LogInfo("SYM-HEALTH", "Initialized with stale=" + IntegerToString(staleSec) + "s");
    }
    
    // Call on every tick for the symbol
    void OnTick(string symbol) {
        if(!m_enabled) return;
        if(symbol == "") return;
        
        MqlTick tick;
        if(!SymbolInfoTick(symbol, tick)) return;
        
        SSymbolHealth health = GetHealth(symbol);
        health.symbol = symbol;
        health.lastTickTime = tick.time;
        health.lastTickMs = (ulong)TimeCurrent() * 1000 + tick.time_msc % 1000;
        health.tickCount++;
        
        double spread = (tick.ask - tick.bid) / _Point;
        health.currentSpread = spread;
        
        // EMA for spread (alpha = 0.01 for slow adaptation)
        if(health.emaInitialized == 0) {
            health.spreadEma = spread;
            health.avgSpread = spread;
            health.minSpread = spread;
            health.maxSpread = spread;
            health.emaInitialized = 1;
        } else {
            health.spreadEma = health.spreadEma * 0.99 + spread * 0.01;
            health.avgSpread = health.spreadEma;
            if(spread > health.maxSpread) health.maxSpread = spread;
            if(spread < health.minSpread) health.minSpread = spread;
        }
        
        // Spike detection
        if(health.avgSpread > 0 && spread > health.avgSpread * m_spreadSpikeMultiplier) {
            health.spreadSpikes++;
            health.spreadSpikeCount++;
            AlertSpreadSpike(symbol, spread, health.avgSpread);
        }
        
        // Reset stale/frozen if we got a tick
        if(health.isFrozen || health.isStale) {
            health.isStale = false;
            health.isFrozen = false;
            health.tradingAllowed = true;
            Print("[SYM-HEALTH] Symbol ", symbol, " recovered (tick received)");
            g_structLog.LogInfo("SYM-HEALTH", "Symbol " + symbol + " recovered");
        }
        
        SetHealth(symbol, health);
    }
    
    // Call from OnTimer for all watched symbols
    void CheckAllSymbols(string symbolsCsv) {
        if(!m_enabled) return;
        if(symbolsCsv == "") return;
        
        m_totalSymbols = 0;
        m_healthySymbols = 0;
        m_staleSymbols = 0;
        m_frozenSymbols = 0;
        
        string temp = symbolsCsv;
        StringReplace(temp, " ", "");
        int start = 0;
        while(start < StringLen(temp)) {
            int comma = StringFind(temp, ",", start);
            if(comma < 0) comma = StringLen(temp);
            string sym = StringSubstr(temp, start, comma - start);
            if(sym != "") CheckSymbol(sym);
            start = comma + 1;
        }
        
        // Log summary periodically
        static datetime s_lastSummary = 0;
        if(TimeCurrent() - s_lastSummary > 300) { // Every 5 minutes
            Print("[SYM-HEALTH] Summary: total=", m_totalSymbols, " healthy=", m_healthySymbols, 
                  " stale=", m_staleSymbols, " frozen=", m_frozenSymbols);
            g_structLog.LogInfo("SYM-HEALTH", 
                "Summary: total=" + IntegerToString(m_totalSymbols) + 
                " healthy=" + IntegerToString(m_healthySymbols) +
                " stale=" + IntegerToString(m_staleSymbols) +
                " frozen=" + IntegerToString(m_frozenSymbols));
            s_lastSummary = TimeCurrent();
        }
    }
    
    // Check specific symbol for stale/frozen
    void CheckSymbol(string symbol) {
        if(symbol == "") return;
        m_totalSymbols++;
        
        SSymbolHealth health = GetHealth(symbol);
        
        if(health.tickCount == 0) {
            // Never received a tick
            health.isFrozen = true;
            health.tradingAllowed = false;
            m_frozenSymbols++;
            if(health.alertCount == 0 || TimeCurrent() - health.lastAlertTime > m_alertCooldownSec) {
                Print("[SYM-HEALTH] Symbol ", symbol, " NEVER RECEIVED TICK - disabling trading");
                g_structLog.LogWarning("SYM-HEALTH", "Symbol " + symbol + " never received tick");
                health.lastAlertTime = TimeCurrent();
                health.alertCount++;
            }
        } else {
            int secondsSinceTick = (int)(TimeCurrent() - health.lastTickTime);
            
            if(!health.isFrozen && secondsSinceTick > m_frozenThresholdSec) {
                health.isFrozen = true;
                health.isStale = true;
                health.tradingAllowed = false;
                m_frozenSymbols++;
                if(TimeCurrent() - health.lastAlertTime > m_alertCooldownSec) {
                    Print("[SYM-HEALTH] Symbol ", symbol, " FROZEN (", secondsSinceTick, "s) - disabling trading");
                    g_structLog.LogWarning("SYM-HEALTH", "Symbol " + symbol + " FROZEN " + IntegerToString(secondsSinceTick) + "s");
                    health.lastAlertTime = TimeCurrent();
                    health.alertCount++;
                }
            }
            else if(!health.isStale && secondsSinceTick > m_staleThresholdSec) {
                health.isStale = true;
                m_staleSymbols++;
                if(TimeCurrent() - health.lastAlertTime > m_alertCooldownSec) {
                    Print("[SYM-HEALTH] Symbol ", symbol, " STALE (", secondsSinceTick, "s)");
                    g_structLog.LogWarning("SYM-HEALTH", "Symbol " + symbol + " STALE " + IntegerToString(secondsSinceTick) + "s");
                    health.lastAlertTime = TimeCurrent();
                    health.alertCount++;
                }
            }
            else {
                m_healthySymbols++;
            }
        }
        
        SetHealth(symbol, health);
    }
    
    // Check if symbol is healthy for trading
    bool IsHealthy(string symbol) {
        if(!m_enabled) return true; // If monitor disabled, allow all
        SSymbolHealth health = GetHealth(symbol);
        return health.tradingAllowed && health.tickCount > 0 && !health.isFrozen;
    }
    
    // Get health data for symbol
    SSymbolHealth GetHealth(string symbol) {
        int idx = FindSymbolIndex(symbol);
        if(idx < 0) {
            idx = AddSymbol(symbol);
            if(idx < 0) {
                SSymbolHealth h;
                h.symbol = symbol;
                return h;
            }
        }
        
        string json = m_healthData[idx].Value();
        SSymbolHealth h;
        h.symbol = symbol;
        if(json != "") {
            ParseHealthJson(json, h);
        }
        return h;
    }
    
    // Manually enable/disable trading for symbol
    void SetTradingAllowed(string symbol, bool allowed) {
        SSymbolHealth health = GetHealth(symbol);
        health.tradingAllowed = allowed;
        SetHealth(symbol, health);
        Print("[SYM-HEALTH] Trading ", (allowed ? "ENABLED" : "DISABLED"), " for ", symbol);
        g_structLog.LogInfo("SYM-HEALTH", "Trading " + (allowed ? "ENABLED" : "DISABLED") + " for " + symbol);
    }
    
    // Enable/disable monitor
    void SetEnabled(bool enabled) { m_enabled = enabled; }
    bool IsEnabled() const { return m_enabled; }
    
    // Get stats
    int GetTotalSymbols() const { return m_totalSymbols; }
    int GetHealthySymbols() const { return m_healthySymbols; }
    int GetStaleSymbols() const { return m_staleSymbols; }
    int GetFrozenSymbols() const { return m_frozenSymbols; }
    
    // Reset symbol health (e.g., after reconnect)
    void ResetSymbol(string symbol) {
        int idx = FindSymbolIndex(symbol);
        if(idx >= 0) {
            m_healthData[idx].Value("");
            Print("[SYM-HEALTH] Reset health for ", symbol);
        }
    }
    
    // Update thresholds at runtime
    void UpdateThresholds(int staleSec, int frozenSec, double spikeMult) {
        m_staleThresholdSec = staleSec;
        m_frozenThresholdSec = frozenSec;
        m_spreadSpikeMultiplier = spikeMult;
        Print("[SYM-HEALTH] Thresholds updated: stale=", staleSec, "s frozen=", frozenSec, "s spikeMult=", DoubleToString(spikeMult, 2));
    }

private:
    void SetHealth(string symbol, const SSymbolHealth& h) {
        int idx = FindSymbolIndex(symbol);
        if(idx < 0) idx = AddSymbol(symbol);
        if(idx < 0) return;
        
        string json = "{";
        json += "\"symbol\":\"" + h.symbol + "\",";
        json += "\"lastTick\":" + IntegerToString(h.lastTickTime) + ",";
        json += "\"lastTickMs\":" + IntegerToString((long)h.lastTickMs) + ",";
        json += "\"tickCount\":" + IntegerToString(h.tickCount) + ",";
        json += "\"currentSpread\":" + DoubleToString(h.currentSpread, 2) + ",";
        json += "\"avgSpread\":" + DoubleToString(h.avgSpread, 2) + ",";
        json += "\"maxSpread\":" + DoubleToString(h.maxSpread, 2) + ",";
        json += "\"minSpread\":" + DoubleToString(h.minSpread, 2) + ",";
        json += "\"spreadSpikes\":" + IntegerToString(h.spreadSpikes) + ",";
        json += "\"spreadSpikeCount\":" + IntegerToString(h.spreadSpikeCount) + ",";
        json += "\"isStale\":" + (h.isStale ? "true" : "false") + ",";
        json += "\"isFrozen\":" + (h.isFrozen ? "true" : "false") + ",";
        json += "\"tradingAllowed\":" + (h.tradingAllowed ? "true" : "false") + ",";
        json += "\"lastAlert\":" + IntegerToString(h.lastAlertTime) + ",";
        json += "\"alertCount\":" + IntegerToString(h.alertCount) + ",";
        json += "\"spreadEma\":" + DoubleToString(h.spreadEma, 2) + ",";
        json += "\"emaInit\":" + IntegerToString(h.emaInitialized);
        json += "}";
        
        m_healthData[idx].Value(json);
    }
    
    void ParseHealthJson(string json, SSymbolHealth& h) {
        // Simple JSON parsing for our known structure
        h.lastTickTime = (datetime)JsonGetLong(json, "lastTick", 0);
        h.lastTickMs = (ulong)JsonGetLong(json, "lastTickMs", 0);
        h.tickCount = JsonGetInt(json, "tickCount", 0);
        h.currentSpread = JsonGetDouble(json, "currentSpread", 0);
        h.avgSpread = JsonGetDouble(json, "avgSpread", 0);
        h.maxSpread = JsonGetDouble(json, "maxSpread", 0);
        h.minSpread = JsonGetDouble(json, "minSpread", 0);
        h.spreadSpikes = JsonGetInt(json, "spreadSpikes", 0);
        h.spreadSpikeCount = JsonGetInt(json, "spreadSpikeCount", 0);
        h.isStale = JsonGetBool(json, "isStale", false);
        h.isFrozen = JsonGetBool(json, "isFrozen", false);
        h.tradingAllowed = JsonGetBool(json, "tradingAllowed", true);
        h.lastAlertTime = (datetime)JsonGetLong(json, "lastAlert", 0);
        h.alertCount = JsonGetInt(json, "alertCount", 0);
        h.spreadEma = JsonGetDouble(json, "spreadEma", 0);
        h.emaInitialized = JsonGetInt(json, "emaInit", 0);
    }
    
    void AlertSpreadSpike(string symbol, double current, double average) {
        double ratio = (average > 0) ? current / average : 0;
        Print("[SYM-HEALTH] SPREAD SPIKE: ", symbol, " current=", DoubleToString(current, 1), 
              " avg=", DoubleToString(average, 1), " ratio=", DoubleToString(ratio, 2));
        g_structLog.LogSpreadSpike(symbol, current, average);
    }
    
    // JSON helpers (simplified)
    double JsonGetDouble(string json, string key, double defaultVal) {
        string search = "\"" + key + "\"";
        int pos = StringFind(json, search);
        if(pos < 0) return defaultVal;
        pos = StringFind(json, ":", pos);
        if(pos < 0) return defaultVal;
        pos++;
        while(pos < StringLen(json) && (json[pos] == ' ' || json[pos] == '\t')) pos++;
        int end = pos;
        while(end < StringLen(json) && json[end] != ',' && json[end] != '}') end++;
        string val = StringSubstr(json, pos, end - pos);
        return StringToDouble(val);
    }
    
    long JsonGetLong(string json, string key, long defaultVal) {
        string search = "\"" + key + "\"";
        int pos = StringFind(json, search);
        if(pos < 0) return defaultVal;
        pos = StringFind(json, ":", pos);
        if(pos < 0) return defaultVal;
        pos++;
        while(pos < StringLen(json) && (json[pos] == ' ' || json[pos] == '\t')) pos++;
        int end = pos;
        while(end < StringLen(json) && json[end] != ',' && json[end] != '}') end++;
        string val = StringSubstr(json, pos, end - pos);
        return StringToInteger(val);
    }
    
    int JsonGetInt(string json, string key, int defaultVal) {
        return (int)JsonGetLong(json, key, defaultVal);
    }
    
    bool JsonGetBool(string json, string key, bool defaultVal) {
        string search = "\"" + key + "\"";
        int pos = StringFind(json, search);
        if(pos < 0) return defaultVal;
        pos = StringFind(json, ":", pos);
        if(pos < 0) return defaultVal;
        pos++;
        while(pos < StringLen(json) && (json[pos] == ' ' || json[pos] == '\t')) pos++;
        if(StringFind(json, "true", pos) == pos) return true;
        if(StringFind(json, "false", pos) == pos) return false;
        return defaultVal;
    }
};

#endif // CORE_MONITORING_SYMBOL_HEALTH_MONITOR_MQH