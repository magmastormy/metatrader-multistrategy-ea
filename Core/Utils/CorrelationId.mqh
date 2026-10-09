//+------------------------------------------------------------------+
//| CorrelationId.mqh                                                |
//| Correlation ID generation and propagation for trade tracing      |
//+------------------------------------------------------------------+
#property strict
#ifndef CORE_UTILS_CORRELATION_ID_MQH
#define CORE_UTILS_CORRELATION_ID_MQH

#include <Arrays/ArrayObj.mqh>
#include <Arrays/ArrayString.mqh>

//+------------------------------------------------------------------+
//| Simple String Map (replacement for CMapStringToString)           |
//+------------------------------------------------------------------+
class CStringMap
{
private:
    CArrayString m_keys;
    CArrayString m_values;
    
public:
    CStringMap() {}
    ~CStringMap() {}
    
    void SetValue(string key, string value) {
        int index = FindKey(key);
        if(index >= 0) {
            // CArrayString.At returns by value, so we need to remove and re-add
            m_keys.Delete(index);
            m_values.Delete(index);
            m_keys.Add(key);
            m_values.Add(value);
        } else {
            m_keys.Add(key);
            m_values.Add(value);
        }
    }
    
    string GetValue(string key) const {
        int index = FindKey(key);
        if(index >= 0) return m_values.At(index);
        return "";
    }
    
    int FindKey(string key) const {
        for(int i = 0; i < m_keys.Total(); i++) {
            if(m_keys.At(i) == key) return i;
        }
        return -1;
    }
    
    int Total() const { return m_keys.Total(); }
    
    void Clear() {
        m_keys.Clear();
        m_values.Clear();
    }
};

//+------------------------------------------------------------------+
//| Helper: Integer to Hex String (MQL5 doesn't have IntegerToHexString) |
//+------------------------------------------------------------------+
string IntToHex(int value, int digits = 4) {
    string hexChars = "0123456789ABCDEF";
    string result = "";
    for(int i = 0; i < digits; i++) {
        int nibble = value & 0xF;
        result = StringSubstr(hexChars, nibble, 1) + result;
        value = value >> 4;
    }
    return result;
}

//+------------------------------------------------------------------+
//| Correlation ID Manager                                           |
//+------------------------------------------------------------------+
class CCorrelationIdManager
{
private:
    // Map: context key -> correlation ID
    // Context key = symbol + "_" + timestamp_ms (unique per OnTick cycle)
    CStringMap m_idMap;
    
    // Current correlation ID for this tick cycle
    string m_currentId;
    bool   m_hasCurrentId;
    
    // Sequence for uniqueness within same millisecond
    int    m_sequence;
    ulong  m_lastTimestamp;

public:
    CCorrelationIdManager() : m_hasCurrentId(false), m_sequence(0), m_lastTimestamp(0) {}
    ~CCorrelationIdManager() {}

    // Generate new correlation ID for a new decision cycle
    string GenerateNewId(string context = "") {
        MqlDateTime dt; TimeCurrent(dt);
        ulong timestamp = (ulong)(TimeCurrent() * 1000 + GetMicrosecondCount() % 1000);
        int msec = (int)(GetMicrosecondCount() % 1000);
        
        if(timestamp == m_lastTimestamp) {
            m_sequence++;
        } else {
            m_sequence = 0;
            m_lastTimestamp = timestamp;
        }
        
        // Format: YYYYMMDD-HHMMSS-mmm-XXXX (XXXX = sequence + random)
        string base = StringFormat("%04d%02d%02d-%02d%02d%02d-%03d", 
                                   dt.year, dt.mon, dt.day, dt.hour, dt.min, dt.sec, msec);
        string seq = IntToHex(m_sequence + (int)(MathRand() * 4096), 4);
        
        string id = base + "-" + seq;
        
        // Store with context key
        string key = context != "" ? context : _Symbol;
        m_idMap.SetValue(key + "_" + IntegerToString(timestamp), id);
        
        m_currentId = id;
        m_hasCurrentId = true;
        
        return id;
    }
    
    // Get current correlation ID (for downstream components)
    string GetCurrentId() const { return m_currentId; }
    bool HasCurrentId() const { return m_hasCurrentId; }
    
    // Set correlation ID manually (e.g., from external source)
    void SetCurrentId(string id) {
        m_currentId = id;
        m_hasCurrentId = (id != "");
    }
    
    // Clear current ID (end of cycle)
    void ClearCurrentId() {
        m_currentId = "";
        m_hasCurrentId = false;
    }
    
    // Get ID for specific context (symbol + time)
    string GetIdForContext(string symbol, ulong timestamp) {
        return m_idMap.GetValue(symbol + "_" + IntegerToString(timestamp));
    }
    
    // Cleanup old entries (call periodically)
    void Cleanup(ulong maxAgeMs = 3600000) { // 1 hour default
        ulong now = (ulong)TimeCurrent() * 1000;
        // CStringMap doesn't support easy iteration for cleanup
        // In practice, we'd recreate the map periodically
        if(m_idMap.Total() > 10000) {
            // Too many entries - recreate
            CStringMap newMap;
            // Note: Can't iterate CStringMap easily
            // This is a limitation - we just let it grow and recreate occasionally
        }
    }
    
    int Total() const { return m_idMap.Total(); }
};

// Global instance
extern CCorrelationIdManager g_corrIdManager;

//+------------------------------------------------------------------+
//| Helper functions for easy access                                 |
//+------------------------------------------------------------------+
inline string GenerateCorrelationId(string context = "") {
    return g_corrIdManager.GenerateNewId(context);
}

inline string GetCurrentCorrelationId() {
    return g_corrIdManager.GetCurrentId();
}

inline bool HasCurrentCorrelationId() {
    return g_corrIdManager.HasCurrentId();
}

inline void SetCurrentCorrelationId(string id) {
    g_corrIdManager.SetCurrentId(id);
}

inline void ClearCurrentCorrelationId() {
    g_corrIdManager.ClearCurrentId();
}

//+------------------------------------------------------------------+
//| Correlation ID Context Holder (RAII-style for MQL5)              |
//+------------------------------------------------------------------+
class CCorrelationScope
{
private:
    string m_previousId;
    bool   m_hadPrevious;
    
public:
    CCorrelationScope(string newId = "") {
        m_hadPrevious = g_corrIdManager.HasCurrentId();
        m_previousId = g_corrIdManager.GetCurrentId();
        
        if(newId != "") {
            g_corrIdManager.SetCurrentId(newId);
        } else if(!m_hadPrevious) {
            g_corrIdManager.GenerateNewId();
        }
    }
    
    ~CCorrelationScope() {
        if(m_hadPrevious) {
            g_corrIdManager.SetCurrentId(m_previousId);
        } else {
            g_corrIdManager.ClearCurrentId();
        }
    }
    
    string GetId() const { return g_corrIdManager.GetCurrentId(); }
};

//+------------------------------------------------------------------+
//| Strategy ID to short code mapping                                |
//+------------------------------------------------------------------+
string StrategyIdToCode(int strategyId) {
    static const string codes[21] = {
        "MOM", "TND", "SR", "CSL", "MR", "VB", "FVG", "TS", "BB", "NY", 
        "ARB", "STAT", "KLM", "CPD", "4ST", "VT", "LS", "RC", "EO", "EXT", "UNK"
    };
    if(strategyId >= 0 && strategyId < 21) return codes[strategyId];
    return "UNK";
}

string StrategyCodeToName(string code) {
    if(code == "MOM") return "Momentum";
    if(code == "TND") return "Trend";
    if(code == "SR") return "SupportResistance";
    if(code == "CSL") return "Candlestick";
    if(code == "MR") return "MeanReversion";
    if(code == "VB") return "VolatilityBreakout";
    if(code == "FVG") return "FVGScalper";
    if(code == "TS") return "TurtleSoup";
    if(code == "BB") return "BreakerBlock";
    if(code == "NY") return "NYOpenGap";
    if(code == "ARB") return "AsianRangeBreak";
    if(code == "STAT") return "StatisticalArbitrage";
    if(code == "KLM") return "KalmanMR";
    if(code == "CPD") return "ChangepointDetect";
    if(code == "4ST") return "FourStateRegime";
    if(code == "VT") return "VolTargeting";
    if(code == "LS") return "LiquiditySweep";
    if(code == "RC") return "RangeCompression";
    if(code == "EO") return "ExitOptimizer";
    if(code == "EXT") return "ExitOptimizer"; // alias
    return "Unknown";
}

#endif // CORE_UTILS_CORRELATION_ID_MQH