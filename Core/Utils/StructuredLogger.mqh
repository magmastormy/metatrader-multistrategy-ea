// JSONL structured logging: no-op when disabled, queryable when enabled.
#property strict
#ifndef CORE_UTILS_STRUCTURED_LOGGER_MQH
#define CORE_UTILS_STRUCTURED_LOGGER_MQH

#include <Arrays/ArrayObj.mqh>

// Forward declaration for global instance (defined in MultiStrategyAutonomousEA.mq5)
class CStructuredLogger;

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
    
    long   m_accountLogin;
    string m_eaVersion;
    

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
    
    // Call once from OnInit.
    void Init(string prefix = "EA") {
        if(m_enabled) return;

        m_accountLogin = AccountInfoInteger(ACCOUNT_LOGIN);

        // TimeCurrent() at OnInit is the last known server tick, not the wall clock - a session started
        // hours later than the last tick got that older name, and two sessions could collide on it.
        MqlDateTime dt; TimeLocal(dt);
        string timestamp = StringFormat("%04d%02d%02d_%02d%02d%02d",
                                        dt.year, dt.mon, dt.day, dt.hour, dt.min, dt.sec);

        // FileOpen accepted the old absolute path but wrote only its basename into MQL5\Files, so the sink
        // always worked while m_logPath named a MQL5\Logs file that never existed. This is the real location.
        string fileName = StringFormat("%s_structured_%s.jsonl", prefix, timestamp);
        m_fileHandle = FileOpen(fileName, FILE_WRITE|FILE_TXT|FILE_ANSI);
        m_logPath = TerminalInfoString(TERMINAL_DATA_PATH) + "\\MQL5\\Files\\" + fileName;
        m_enabled = (m_fileHandle != INVALID_HANDLE);

        if(m_enabled) {
            Print("[STRUCTLOG] Initialized: ", m_logPath);
            WriteRaw("{\"evt\":\"SESSION_START\",\"acct\":" + IntegerToString(m_accountLogin) +
                     ",\"ea_ver\":\"" + m_eaVersion + "\",\"ts\":" + IntegerToString(TimeCurrent() * 1000) + "}");
        } else {
            PrintFormat("[STRUCTLOG] WARNING: Failed to open %s | error=%d | structured JSONL sink inactive, the journal still prints",
                        fileName, GetLastError());
        }
    }
    
    // Call from OnDeinit.
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
    
    void LogError(string context, string error, int code = 0, string corrId = "") {
        Log("ERROR", error, context, 0, 0, code, corrId);
    }
    
    void LogWarning(string context, string warning, string corrId = "") {
        Log("WARNING", warning, context, 0, 0, 0, corrId);
    }
    
    void LogInfo(string context, string message, string corrId = "") {
        Log("INFO", message, context, 0, 0, 0, corrId);
    }
    
    void LogSpreadSpike(string symbol, double current, double average, string corrId = "") {
        Log("SPREAD_SPIKE", "", symbol, current, average, 0, corrId);
    }
    
    // Direct write + flush, bypassing the buffer; used by the session markers.
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

extern CStructuredLogger g_structLog;

#endif // CORE_UTILS_STRUCTURED_LOGGER_MQH