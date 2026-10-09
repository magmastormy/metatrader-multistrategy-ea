// JSONL structured logging for production debugging
// Zero overhead when disabled, queryable when enabled
#property strict
#ifndef CORE_UTILS_STRUCTURED_LOGGER_MQH
#define CORE_UTILS_STRUCTURED_LOGGER_MQH

#include <Arrays/ArrayObj.mqh>

// Forward declaration for global instance (defined in MultiStrategyAutonomousEA.mq5)
class CStructuredLogger;

// String object for buffer
class CStringObj : public CObject
{
private:
    string m_value;
public:
    CStringObj(string value = "") : m_value(value) {}
    string Value() const { return m_value; }
    void Value(string v) { m_value = v; }
    virtual int Compare(const CObject* node, const int mode = 0) const override { return 0; }
};

class CStructuredLogger
{
private:
    bool   m_enabled;
    int    m_fileHandle;
    string m_logPath;
    long   m_sequence;
    
    // Async write buffer
    CArrayObj* m_buffer;
    datetime m_lastFlush;
    int    m_flushIntervalMs;
    int    m_maxBuffer;
    
    // Context enrichment
    long   m_accountLogin;
    string m_eaVersion;
    
    // Helpers (defined inline in private section below)

public:
    CStructuredLogger() : m_enabled(false), m_fileHandle(INVALID_HANDLE), m_sequence(0), 
                          m_lastFlush(0), m_flushIntervalMs(100), m_maxBuffer(1000),
                          m_accountLogin(0), m_eaVersion("2.000") 
    {
        m_buffer = new CArrayObj();
    }
    
    ~CStructuredLogger() {
        FlushBuffer();
        if(m_fileHandle != INVALID_HANDLE) FileClose(m_fileHandle);
        if(CheckPointer(m_buffer) == POINTER_DYNAMIC) delete m_buffer;
    }
    
    // Initialize - call once from OnInit
    void Init(string prefix = "EA") {
        if(m_enabled) return; // Already initialized
        
        m_accountLogin = AccountInfoInteger(ACCOUNT_LOGIN);
        
        MqlDateTime dt; TimeCurrent(dt);
        string timestamp = StringFormat("%04d%02d%02d_%02d%02d%02d", 
                                        dt.year, dt.mon, dt.day, dt.hour, dt.min, dt.sec);
        
        string dataPath = TerminalInfoString(TERMINAL_DATA_PATH);
        m_logPath = StringFormat("%s\\MQL5\\Logs\\%s_structured_%s.jsonl", 
                                 dataPath, prefix, timestamp);
        
        m_fileHandle = FileOpen(m_logPath, FILE_WRITE|FILE_TXT|FILE_ANSI);
        m_enabled = (m_fileHandle != INVALID_HANDLE);
        
        if(m_enabled) {
            Print("[STRUCTLOG] Initialized: ", m_logPath);
            // Write session start marker
            WriteRaw("{\"evt\":\"SESSION_START\",\"acct\":" + IntegerToString(m_accountLogin) + 
                     ",\"ea_ver\":\"" + m_eaVersion + "\",\"ts\":" + IntegerToString(TimeCurrent() * 1000) + "}");
        } else {
            Print("[STRUCTLOG] WARNING: Failed to open log file: ", m_logPath, " error: ", GetLastError());
        }
    }
    
    // Shutdown - call from OnDeinit
    void Shutdown() {
        if(!m_enabled) return;
        FlushBuffer();
        WriteRaw("{\"evt\":\"SESSION_END\",\"acct\":" + IntegerToString(m_accountLogin) + 
                 ",\"ts\":" + IntegerToString(TimeCurrent() * 1000) + "}");
        if(m_fileHandle != INVALID_HANDLE) {
            FileClose(m_fileHandle);
            m_fileHandle = INVALID_HANDLE;
        }
        m_enabled = false;
        Print("[STRUCTLOG] Shutdown complete");
    }
    
    // Core logging function - all context auto-captured
    void Log(string eventType, string message = "", string symbol = "", 
             double value1 = 0, double value2 = 0, long value3 = 0, string corrId = "")
    {
        if(!m_enabled) return;
        
        string json = BuildJSON(eventType, message, symbol, value1, value2, value3, corrId);
        m_buffer.Add(new CStringObj(json));
        
        // Auto-flush on buffer full or interval
        ulong now = GetMicrosecondCount() / 1000;
        if(m_buffer.Total() >= m_maxBuffer || now - m_lastFlush > (ulong)m_flushIntervalMs)
            FlushBuffer();
    }
    
    // Force flush - call on critical events
    void Flush() { FlushBuffer(); }
    
    // Convenience wrappers for common events
    void LogSignal(string symbol, int strategyId, int direction, double confidence, double weight, string corrId = "") {
        long packed = ((long)strategyId << 32) | ((long)(direction + 1) & 0xFFFFFFFF);
        Log("SIGNAL", "", symbol, confidence, weight, packed, corrId);
    }
    
    void LogConsensus(string symbol, int direction, double score, int voterCount, double threshold, string corrId = "") {
        long packed = ((long)direction << 32) | ((long)voterCount & 0xFFFFFFFF);
        Log("CONSENSUS", "", symbol, score, threshold, packed, corrId);
    }
    
    void LogTrade(string symbol, int cmd, double volume, double price, double sl, double tp, 
                  long ticket, string corrId = "") {
        long packed = ((long)cmd << 32) | (ticket & 0xFFFFFFFF);
        Log("TRADE", corrId, symbol, volume, price, packed, corrId);
        if(sl > 0) Log("TRADE_SL", corrId, symbol, sl, 0, ticket, corrId);
        if(tp > 0) Log("TRADE_TP", corrId, symbol, tp, 0, ticket, corrId);
    }
    
    void LogRiskCheck(string symbol, string checkName, bool passed, double value, double limit, string corrId = "") {
        Log("RISK_CHECK", passed ? "PASS" : "FAIL", symbol, value, limit, passed ? 1 : 0, corrId);
    }
    
    void LogError(string context, string error, int code = 0, string corrId = "") {
        Log("ERROR", error, context, 0, 0, code, corrId);
    }
    
    void LogWarning(string context, string warning, string corrId = "") {
        Log("WARNING", warning, context, 0, 0, 0, corrId);
    }
    
    void LogInfo(string context, string message, string corrId = "") {
        Log("INFO", message, context, 0, 0, 0, corrId);
    }
    
    // Symbol health events
    void LogSpreadSpike(string symbol, double current, double average, string corrId = "") {
        Log("SPREAD_SPIKE", "", symbol, current, average, 0, corrId);
    }
    
    void LogSymbolFrozen(string symbol, int secondsSinceTick, string corrId = "") {
        Log("SYMBOL_FROZEN", "", symbol, secondsSinceTick, 0, 0, corrId);
    }
    
    void LogSignalSkipped(string symbol, string reason, string corrId = "") {
        Log("SIGNAL_SKIPPED", reason, symbol, 0, 0, 0, corrId);
    }
    
    // Config reload events
    void LogConfigReload(string section, string changes, string corrId = "") {
        Log("CONFIG_RELOAD", changes, section, 0, 0, 0, corrId);
    }
    
    // AI events (when enabled)
    void LogAIVote(string symbol, string model, double confidence, int vote, string corrId = "") {
        Log("AI_VOTE", model, symbol, confidence, 0, vote, corrId);
    }
    
    void LogAIModelLoad(string model, bool success, string corrId = "") {
        Log("AI_MODEL_LOAD", success ? "SUCCESS" : "FAILED", model, 0, 0, success ? 1 : 0, corrId);
    }
    
    // Engine lifecycle
    void LogEngineInit(string engine, bool success, string corrId = "") {
        Log("ENGINE_INIT", success ? "OK" : "FAILED", engine, 0, 0, success ? 1 : 0, corrId);
    }
    
    // Position lifecycle
    void LogPositionOpen(string symbol, long ticket, double volume, double price, string corrId = "") {
        Log("POSITION_OPEN", "", symbol, volume, price, ticket, corrId);
    }
    
    void LogPositionClose(string symbol, long ticket, double profit, string reason, string corrId = "") {
        Log("POSITION_CLOSE", reason, symbol, profit, 0, ticket, corrId);
    }
    
    void LogPositionModify(string symbol, long ticket, double sl, double tp, string corrId = "") {
        Log("POSITION_MODIFY", "", symbol, sl, tp, ticket, corrId);
    }
    
    // Utility
    bool IsEnabled() const { return m_enabled; }
    string GetLogPath() const { return m_logPath; }
    long GetSequence() const { return m_sequence; }
    
    // Write raw JSON (for session markers)
    void WriteRaw(string json) {
        if(!m_enabled || m_fileHandle == INVALID_HANDLE) return;
        FileWriteString(m_fileHandle, json + "\n");
        FileFlush(m_fileHandle);
    }

private:
    string BuildJSON(string eventType, string message, string symbol,
                     double v1, double v2, long v3, string corrId)
    {
        m_sequence++;
        ulong timestamp = (ulong)(TimeCurrent() * 1000 + (GetMicrosecondCount() % 1000));
        string sym = (symbol != "" ? symbol : _Symbol);
        
        string json = "{";
        json += "\"ts\":" + IntegerToString((long)timestamp) + ",";
        json += "\"seq\":" + IntegerToString(m_sequence) + ",";
        json += "\"evt\":\"" + eventType + "\",";
        json += "\"acct\":" + IntegerToString(m_accountLogin) + ",";
        json += "\"sym\":\"" + sym + "\",";
        if(corrId != "") json += "\"corr_id\":\"" + corrId + "\",";
        string escapedMsg = message;
        StringReplace(escapedMsg, "\"", "\\\"");
        json += "\"msg\":\"" + escapedMsg + "\",";
        json += "\"v1\":" + DoubleToString(v1, 6) + ",";
        json += "\"v2\":" + DoubleToString(v2, 6) + ",";
        json += "\"v3\":" + IntegerToString((long)v3) + ",";
        json += "\"ea_ver\":\"" + m_eaVersion + "\"";
        json += "}";
        return json;
    }
    
    void FlushBuffer() {
        if(!m_enabled || m_fileHandle == INVALID_HANDLE || m_buffer.Total() == 0) return;
        
        for(int i = 0; i < m_buffer.Total(); i++) {
            CObject* obj = m_buffer.At(i);
            if(obj != NULL) {
                CStringObj* strObj = (CStringObj*)obj;
                FileWriteString(m_fileHandle, strObj.Value() + "\n");
            }
        }
        m_buffer.Clear();
        FileFlush(m_fileHandle);
        m_lastFlush = (datetime)(GetMicrosecondCount() / 1000);
    }
};

// Global instance declaration (definition in MultiStrategyAutonomousEA.mq5)
extern CStructuredLogger g_structLog;

#endif // CORE_UTILS_STRUCTURED_LOGGER_MQH