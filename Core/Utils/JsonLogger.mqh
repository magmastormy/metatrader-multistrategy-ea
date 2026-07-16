//+------------------------------------------------------------------+
//| JsonLogger.mqh - Structured JSON Logging Utility                 |
//| Provides structured JSON logging with correlation IDs            |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Aggressive Trading Systems"
#property link      "https://www.aggressivetrading.com"
#property version   "1.00"
#property strict

#ifndef JSON_LOGGER_MQH
#define JSON_LOGGER_MQH

#include "ErrorHandling.mqh"
#include "Enums.mqh"

//+------------------------------------------------------------------+
//| JSON Log Entry Structure                                         |
//+------------------------------------------------------------------+
struct SJsonLogEntry
{
    string timestamp;           // ISO 8601 timestamp
    string level;               // DEBUG, INFO, WARNING, ERROR, CRITICAL
    string component;           // Component name
    string message;             // Human-readable message
    string correlationId;       // Correlation ID for tracing
    string eventType;           // Event type (HEARTBEAT, TRADE, SIGNAL, RISK, AI, etc.)
    string symbol;              // Symbol (if applicable)
    string jsonData;            // Additional structured data as JSON
    
    SJsonLogEntry() {
        timestamp = "";
        level = "INFO";
        component = "";
        message = "";
        correlationId = "";
        eventType = "";
        symbol = "";
        jsonData = "{}";
    }
};

//+------------------------------------------------------------------+
//| Correlation ID Generator                                         |
//+------------------------------------------------------------------+
class CCorrelationIdGenerator
{
private:
    static ulong m_sequence;
    static datetime m_lastReset;
    
public:
    static string Generate(const string prefix = "EA") {
        datetime now = TimeCurrent();
        if(now - m_lastReset > 86400) { // Reset daily
            m_sequence = 0;
            m_lastReset = now;
        }
        m_sequence++;
        return StringFormat("%s-%d-%06I64u", prefix, (int)now, m_sequence);
    }
    
    static string GenerateForTrade(const string symbol, const ENUM_TRADE_SIGNAL signal) {
        datetime now = TimeCurrent();
        string sigStr = (signal == TRADE_SIGNAL_BUY) ? "B" : (signal == TRADE_SIGNAL_SELL) ? "S" : "N";
        return StringFormat("TRD-%s-%s-%d-%06I64u", symbol, sigStr, (int)now, m_sequence++);
    }
    
    static string GenerateForSignal(const string symbol, const string strategy) {
        datetime now = TimeCurrent();
        return StringFormat("SIG-%s-%s-%d-%06I64u", symbol, strategy, (int)now, m_sequence++);
    }
    
    static string GenerateForAI(const string symbol, const string aiType) {
        datetime now = TimeCurrent();
        return StringFormat("AI-%s-%s-%d-%06I64u", symbol, aiType, (int)now, m_sequence++);
    }
};

ulong CCorrelationIdGenerator::m_sequence = 0;
datetime CCorrelationIdGenerator::m_lastReset = 0;

//+------------------------------------------------------------------+
//| JSON Logger Class                                                |
//+------------------------------------------------------------------+
class CJsonLogger
{
private:
    static bool m_enabled;
    static string m_logFile;
    static ENUM_LOG_VERBOSITY m_minVerbosity;
    static string m_currentCorrelationId;
    static int m_logCount;
    
    // Escape JSON string
    static string EscapeJson(const string &value) {
        string escaped = value;
        StringReplace(escaped, "\\", "\\\\");
        StringReplace(escaped, "\"", "\\\"");
        StringReplace(escaped, "\r", "\\r");
        StringReplace(escaped, "\n", "\\n");
        StringReplace(escaped, "\t", "\\t");
        // Note: \b (backspace) and \f (form feed) not directly supported in MQL5 string literals
        // They are rarely used in practice, skip them
        return escaped;
    }
    
    // Format timestamp as ISO 8601
    static string FormatTimestamp(datetime time = 0) {
        if(time == 0) time = TimeCurrent();
        string dateStr = TimeToString(time, TIME_DATE | TIME_MINUTES | TIME_SECONDS);
        StringReplace(dateStr, ".", "-");
        return dateStr + "." + IntegerToString(TimeCurrent() % 1000, 3) + "Z";
    }
    
    // Write to log file
    static void WriteToFile(const string jsonLine) {
        if(!m_enabled || m_logFile == "")
            return;
        
        int handle = FileOpen(m_logFile, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON);
        if(handle != INVALID_HANDLE) {
            FileSeek(handle, 0, SEEK_END);
            FileWriteString(handle, jsonLine + "\n");
            FileClose(handle);
        }
    }
    
    // Build JSON line
    static string BuildJsonLine(const SJsonLogEntry &entry) {
        string json = "{";
        json += "\"timestamp\":\"" + entry.timestamp + "\",";
        json += "\"level\":\"" + entry.level + "\",";
        json += "\"component\":\"" + EscapeJson(entry.component) + "\",";
        json += "\"message\":\"" + EscapeJson(entry.message) + "\",";
        json += "\"correlation_id\":\"" + entry.correlationId + "\",";
        json += "\"event_type\":\"" + entry.eventType + "\",";
        json += "\"symbol\":\"" + EscapeJson(entry.symbol) + "\",";
        json += "\"data\":" + entry.jsonData;
        json += "}";
        return json;
    }

public:
    // Initialize logger
    static bool Initialize(const string logFile, ENUM_LOG_VERBOSITY minVerbosity = VERBOSITY_NORMAL) {
        m_logFile = logFile;
        m_minVerbosity = minVerbosity;
        m_enabled = true;
        m_logCount = 0;
        
        // Create log file with header
        int handle = FileOpen(m_logFile, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON);
        if(handle != INVALID_HANDLE) {
            FileWriteString(handle, "# JSON Log started at " + FormatTimestamp() + "\n");
            FileClose(handle);
        }
        
        Print("[JSON-LOGGER] Initialized: " + logFile + " (verbosity=" + EnumToString(minVerbosity) + ")");
        return true;
    }
    
    // Shutdown logger
    static void Shutdown() {
        m_enabled = false;
        Print("[JSON-LOGGER] Shutdown. Total logs: " + IntegerToString(m_logCount));
    }
    
    // Set correlation ID for current context
    static void SetCorrelationId(const string correlationId) {
        m_currentCorrelationId = correlationId;
    }
    
    // Clear correlation ID
    static void ClearCorrelationId() {
        m_currentCorrelationId = "";
    }
    
    // Get current correlation ID
    static string GetCorrelationId() {
        return m_currentCorrelationId;
    }
    
    // Log with full entry
    static void Log(const SJsonLogEntry &entry) {
        if(!m_enabled) return;
        
        // Check verbosity
        int entryVerbosity = 0;
        if(entry.level == "DEBUG") entryVerbosity = VERBOSITY_DEBUG;
        else if(entry.level == "INFO") entryVerbosity = VERBOSITY_NORMAL;
        else if(entry.level == "WARNING") entryVerbosity = VERBOSITY_WARNING;
        else if(entry.level == "ERROR" || entry.level == "CRITICAL") entryVerbosity = VERBOSITY_ERRORS_ONLY;
        
        if(entryVerbosity < m_minVerbosity) return;
        
        // Use current correlation ID if not set in entry
        SJsonLogEntry e = entry;
        if(e.correlationId == "" && m_currentCorrelationId != "")
            e.correlationId = m_currentCorrelationId;
        if(e.timestamp == "")
            e.timestamp = FormatTimestamp();
        
        string jsonLine = BuildJsonLine(e);
        WriteToFile(jsonLine);
        
        // Also print to standard log for compatibility
        string logPrefix = "[" + e.level + "] " + e.component + " | " + e.message;
        if(e.correlationId != "") logPrefix += " | corr=" + e.correlationId;
        if(e.symbol != "") logPrefix += " | sym=" + e.symbol;
        Print(logPrefix);
        
        m_logCount++;
    }
    
    // Convenience methods
    static void LogInfo(const string component, const string message, 
                        const string eventType = "", const string symbol = "",
                        const string correlationId = "", const string jsonData = "{}") {
        SJsonLogEntry entry;
        entry.level = "INFO";
        entry.component = component;
        entry.message = message;
        entry.eventType = eventType;
        entry.symbol = symbol;
        entry.correlationId = correlationId;
        entry.jsonData = jsonData;
        Log(entry);
    }
    
    static void LogWarning(const string component, const string message,
                           const string eventType = "", const string symbol = "",
                           const string correlationId = "", const string jsonData = "{}") {
        SJsonLogEntry entry;
        entry.level = "WARNING";
        entry.component = component;
        entry.message = message;
        entry.eventType = eventType;
        entry.symbol = symbol;
        entry.correlationId = correlationId;
        entry.jsonData = jsonData;
        Log(entry);
    }
    
    static void LogError(const string component, const string message,
                         const string eventType = "", const string symbol = "",
                         const string correlationId = "", const string jsonData = "{}") {
        SJsonLogEntry entry;
        entry.level = "ERROR";
        entry.component = component;
        entry.message = message;
        entry.eventType = eventType;
        entry.symbol = symbol;
        entry.correlationId = correlationId;
        entry.jsonData = jsonData;
        Log(entry);
    }
    
    static void LogDebug(const string component, const string message,
                         const string eventType = "", const string symbol = "",
                         const string correlationId = "", const string jsonData = "{}") {
        SJsonLogEntry entry;
        entry.level = "DEBUG";
        entry.component = component;
        entry.message = message;
        entry.eventType = eventType;
        entry.symbol = symbol;
        entry.correlationId = correlationId;
        entry.jsonData = jsonData;
        Log(entry);
    }
    
    // Specialized logging for common event types
    static void LogHeartbeat(const string component, const string jsonData) {
        LogInfo(component, "Heartbeat", "HEARTBEAT", "", m_currentCorrelationId, jsonData);
    }
    
    static void LogTradeOpen(const string symbol, const ENUM_TRADE_SIGNAL signal, 
                             const double lot, const double price,
                             const string strategy, const string correlationId,
                             const string jsonData = "{}") {
        SJsonLogEntry entry;
        entry.level = "INFO";
        entry.component = "TRADE";
        entry.message = "Trade opened";
        entry.eventType = "TRADE_OPEN";
        entry.symbol = symbol;
        entry.correlationId = correlationId;
        
        string data = "{";
        data += "\"signal\":\"" + (signal == TRADE_SIGNAL_BUY ? "BUY" : "SELL") + "\",";
        data += "\"lot\":" + DoubleToString(lot, 2) + ",";
        data += "\"price\":" + DoubleToString(price, 5) + ",";
        data += "\"strategy\":\"" + EscapeJson(strategy) + "\"";
        data += jsonData == "{}" ? "" : "," + StringSubstr(jsonData, 1, StringLen(jsonData) - 2);
        data += "}";
        entry.jsonData = data;
        Log(entry);
    }
    
    static void LogTradeClose(const string symbol, const double profit,
                              const string correlationId, const string jsonData = "{}") {
        SJsonLogEntry entry;
        entry.level = "INFO";
        entry.component = "TRADE";
        entry.message = "Trade closed";
        entry.eventType = "TRADE_CLOSE";
        entry.symbol = symbol;
        entry.correlationId = correlationId;
        
        string data = "{";
        data += "\"profit\":" + DoubleToString(profit, 2);
        data += jsonData == "{}" ? "" : "," + StringSubstr(jsonData, 1, StringLen(jsonData) - 2);
        data += "}";
        entry.jsonData = data;
        Log(entry);
    }
    
    static void LogSignal(const string symbol, const ENUM_TRADE_SIGNAL signal,
                          const double confidence, const string strategy,
                          const string correlationId, const string jsonData = "{}") {
        SJsonLogEntry entry;
        entry.level = "INFO";
        entry.component = "SIGNAL";
        entry.message = "Signal generated";
        entry.eventType = "SIGNAL";
        entry.symbol = symbol;
        entry.correlationId = correlationId;
        
        string data = "{";
        data += "\"signal\":\"" + (signal == TRADE_SIGNAL_BUY ? "BUY" : "SELL") + "\",";
        data += "\"confidence\":" + DoubleToString(confidence, 4) + ",";
        data += "\"strategy\":\"" + EscapeJson(strategy) + "\"";
        data += jsonData == "{}" ? "" : "," + StringSubstr(jsonData, 1, StringLen(jsonData) - 2);
        data += "}";
        entry.jsonData = data;
        Log(entry);
    }
    
    static void LogRiskEvent(const string symbol, const string event,
                             const double value, const string correlationId,
                             const string jsonData = "{}") {
        SJsonLogEntry entry;
        entry.level = "WARNING";
        entry.component = "RISK";
        entry.message = "Risk event: " + event;
        entry.eventType = "RISK_EVENT";
        entry.symbol = symbol;
        entry.correlationId = correlationId;
        
        string data = "{";
        data += "\"event\":\"" + EscapeJson(event) + "\",";
        data += "\"value\":" + DoubleToString(value, 4);
        data += jsonData == "{}" ? "" : "," + StringSubstr(jsonData, 1, StringLen(jsonData) - 2);
        data += "}";
        entry.jsonData = data;
        Log(entry);
    }
    
    static void LogAIEvent(const string symbol, const string aiType,
                           const string event, const double confidence,
                           const string correlationId, const string jsonData = "{}") {
        SJsonLogEntry entry;
        entry.level = "INFO";
        entry.component = "AI";
        entry.message = "AI event: " + event;
        entry.eventType = "AI_EVENT";
        entry.symbol = symbol;
        entry.correlationId = correlationId;
        
        string data = "{";
        data += "\"ai_type\":\"" + EscapeJson(aiType) + "\",";
        data += "\"event\":\"" + EscapeJson(event) + "\",";
        data += "\"confidence\":" + DoubleToString(confidence, 4);
        data += jsonData == "{}" ? "" : "," + StringSubstr(jsonData, 1, StringLen(jsonData) - 2);
        data += "}";
        entry.jsonData = data;
        Log(entry);
    }
    
    static void LogConsensus(const string symbol, const string event,
                             const double confidence, const int confluence,
                             const string correlationId, const string jsonData = "{}") {
        SJsonLogEntry entry;
        entry.level = "INFO";
        entry.component = "CONSENSUS";
        entry.message = "Consensus: " + event;
        entry.eventType = "CONSENSUS";
        entry.symbol = symbol;
        entry.correlationId = correlationId;
        
        string data = "{";
        data += "\"event\":\"" + EscapeJson(event) + "\",";
        data += "\"confidence\":" + DoubleToString(confidence, 4) + ",";
        data += "\"confluence\":" + IntegerToString(confluence);
        data += jsonData == "{}" ? "" : "," + StringSubstr(jsonData, 1, StringLen(jsonData) - 2);
        data += "}";
        entry.jsonData = data;
        Log(entry);
    }
    
    static void LogPerformance(const string component, const string metric,
                               const double value, const string correlationId,
                               const string jsonData = "{}") {
        SJsonLogEntry entry;
        entry.level = "DEBUG";
        entry.component = component;
        entry.message = "Performance metric: " + metric;
        entry.eventType = "PERFORMANCE";
        entry.symbol = "";
        entry.correlationId = correlationId;
        
        string data = "{";
        data += "\"metric\":\"" + EscapeJson(metric) + "\",";
        data += "\"value\":" + DoubleToString(value, 6);
        data += jsonData == "{}" ? "" : "," + StringSubstr(jsonData, 1, StringLen(jsonData) - 2);
        data += "}";
        entry.jsonData = data;
        Log(entry);
    }
    
    // Get log count
    static int GetLogCount() { return m_logCount; }
    
    // Check if enabled
    static bool IsEnabled() { return m_enabled; }
};

// Static member initialization
bool CJsonLogger::m_enabled = false;
string CJsonLogger::m_logFile = "";
ENUM_LOG_VERBOSITY CJsonLogger::m_minVerbosity = VERBOSITY_NORMAL;
string CJsonLogger::m_currentCorrelationId = "";
int CJsonLogger::m_logCount = 0;

#endif // JSON_LOGGER_MQH