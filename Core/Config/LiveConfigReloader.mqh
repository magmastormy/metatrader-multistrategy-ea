// Hot-reload configuration from JSON file without restart
#property strict
#ifndef CORE_CONFIG_LIVE_CONFIG_RELOADER_MQH
#define CORE_CONFIG_LIVE_CONFIG_RELOADER_MQH

#include "../Utils/StructuredLogger.mqh"
#include "../Utils/LogMacros.mqh"

// Detects a content change in MQL5\Files\Config\live_overrides.json and hands the parsed text to its owner.
// It applies nothing itself: the callback seam this class used to expose was four stubs that printed
// "<section> section reloaded" and discarded the JSON, and MQL5 does not let a class declared inside a
// method reach its owner, so no callback there could ever have applied a value.
class CLiveConfigReloader
{
private:
    string m_configPath;           // path as the operator wrote it, relative to MQL5\Files
    string m_displayPath;          // absolute form, for the log line only
    uint   m_lastCheckMs;
    datetime m_lastModified;
    int    m_checkIntervalSec;
    bool   m_pendingReload;
    bool   m_unreadableReported;

    // Parsed config cache
    string m_lastJson;

public:
    CLiveConfigReloader() : m_lastCheckMs(0), m_lastModified(0),
                            m_checkIntervalSec(30),
                            m_pendingReload(false),
                            m_unreadableReported(false) {}
    
    // Initialize with the path as the operator wrote it, relative to MQL5\Files.
    // FileOpen cannot take an absolute path, and the absolute form this class used to build made both the mtime
    // probe and the read fail forever: m_lastModified stayed 0, so "currentModified <= m_lastModified" was always
    // true and no reload could ever be detected.
    void Init(string path = "Config/live_overrides.json", int checkIntervalSec = 30) {
        m_configPath = path;
        m_displayPath = TerminalInfoString(TERMINAL_DATA_PATH) + "\\MQL5\\Files\\" + path;
        m_checkIntervalSec = checkIntervalSec;

        m_lastModified = GetFileWriteTime(m_configPath);
        Print("[LIVE-CONFIG] Watching: ", m_displayPath, " (interval: ", m_checkIntervalSec, "s)");
        g_structLog.LogInfo("LIVE-CONFIG", "Initialized watching " + m_displayPath);
    }

    // Main check function - call from OnTimer. Throttled on GetTickCount(): TimeCurrent() advances only with
    // ticks, and a quiet market is exactly when an operator reaches for the override file.
    void CheckAndReload() {
        uint nowMs = GetTickCount();
        if(m_lastCheckMs != 0 && (nowMs - m_lastCheckMs) < (uint)(m_checkIntervalSec * 1000))
            return;
        m_lastCheckMs = nowMs;

        datetime currentModified = GetFileWriteTime(m_configPath);
        if(currentModified == 0)
        {
            if(!m_unreadableReported)
            {
                m_unreadableReported = true;
                Print("[LIVE-CONFIG] file not readable | path=", m_displayPath, " | live overrides inactive");
                g_structLog.LogError("LIVE-CONFIG", "File not readable: " + m_displayPath);
            }
            return;
        }
        m_unreadableReported = false;

        if(currentModified <= m_lastModified)
            return;

        m_lastModified = currentModified;

        Print("[LIVE-CONFIG] File changed, reloading...");
        g_structLog.LogInfo("LIVE-CONFIG", "File modified, reloading config");

        string json = ReadFileToString(m_configPath);
        if(json == "") {
            Print("[LIVE-CONFIG] ERROR: Failed to read config file");
            g_structLog.LogError("LIVE-CONFIG", "Failed to read config file");
            return;
        }

        if(!ValidateJson(json)) {
            Print("[LIVE-CONFIG] ERROR: Invalid JSON structure");
            g_structLog.LogError("LIVE-CONFIG", "Invalid JSON structure");
            return;
        }

        if(json == m_lastJson) {
            Print("[LIVE-CONFIG] Config unchanged (same content)");
            return;
        }
        m_lastJson = json;
        m_pendingReload = true;

        Print("[LIVE-CONFIG] Reload complete | owner applies the risk section");
        g_structLog.LogInfo("LIVE-CONFIG", "Reload complete");
    }

    // True once per detected content change; the owner then reads GetCurrentConfig() and applies it.
    bool ConsumeReloaded() { bool pending = m_pendingReload; m_pendingReload = false; return pending; }

    string GetCurrentConfig() const { return m_lastJson; }
    
    // Parse helpers for common types
    static double GetDouble(string json, string path, double defaultVal = 0) {
        return JsonGetDouble(json, path, defaultVal);
    }
    
    static int GetInt(string json, string path, int defaultVal = 0) {
        return (int)JsonGetLong(json, path, defaultVal);
    }
    
    static bool GetBool(string json, string path, bool defaultVal = false) {
        return JsonGetBool(json, path, defaultVal);
    }
    
    static string GetString(string json, string path, string defaultVal = "") {
        return JsonGetString(json, path, defaultVal);
    }
    

private:
    // Get file write time using MQL5 file functions
    datetime GetFileWriteTime(string path) {
        int handle = FileOpen(path, FILE_READ|FILE_TXT|FILE_ANSI);
        if(handle == INVALID_HANDLE) return 0;
        
        // Use FileGetInteger with FILE_MODIFY_TIME or fallback
        datetime writeTime = TimeCurrent();
        
        // Try to get file write time - use FILE_WRITE_DATE or FILE_MODIFY_DATE
        long fileTime = FileGetInteger(handle, FILE_MODIFY_DATE);
        if(fileTime > 0) {
            writeTime = (datetime)fileTime;
        }
        
        FileClose(handle);
        return writeTime;
    }
    
    string ReadFileToString(string path) {
        int h = FileOpen(path, FILE_READ|FILE_TXT|FILE_ANSI);
        if(h == INVALID_HANDLE) return "";
        string content = "";
        while(!FileIsEnding(h)) content += FileReadString(h);
        FileClose(h);
        return content;
    }
    
    bool ValidateJson(string json) {
        // Basic validation - check for balanced braces
        int openBraces = 0, closeBraces = 0;
        for(int i = 0; i < StringLen(json); i++) {
            ushort c = StringGetCharacter(json, i);
            if(c == '{') openBraces++;
            else if(c == '}') closeBraces++;
        }
        return openBraces == closeBraces && openBraces > 0;
    }
    
};

// JSON parsing helpers (MQL5 Json functions are limited)
bool JsonIsNumericLiteral(const string valueStr) {
    if(valueStr == "") return false;
    for(int i = 0; i < StringLen(valueStr); i++) {
        ushort c = StringGetCharacter(valueStr, i);
        bool digit = (c >= '0' && c <= '9');
        bool sign = (c == '+' || c == '-');
        bool point = (c == '.');
        bool exponent = (c == 'e' || c == 'E');
        if(!digit && !sign && !point && !exponent) return false;
    }
    return true;
}

double JsonGetDouble(string json, string path, double defaultVal) {
    // Simple dot-path parser: "risk.maxRiskPerTrade"
    string valueStr = JsonExtractValue(json, path);
    if(valueStr == "") return defaultVal;
    if(!JsonIsNumericLiteral(valueStr)) {
        PrintFormat("[LIVE-CONFIG] %s is not numeric (%s) - keeping default %.4f", path, valueStr, defaultVal);
        return defaultVal;
    }
    return StringToDouble(valueStr);
}

long JsonGetLong(string json, string path, long defaultVal) {
    string valueStr = JsonExtractValue(json, path);
    if(valueStr == "") return defaultVal;
    if(!JsonIsNumericLiteral(valueStr)) {
        PrintFormat("[LIVE-CONFIG] %s is not an integer (%s) - keeping default %d", path, valueStr, defaultVal);
        return defaultVal;
    }
    return StringToInteger(valueStr);
}

bool JsonGetBool(string json, string path, bool defaultVal) {
    string valueStr = JsonExtractValue(json, path);
    if(valueStr == "") return defaultVal;
    StringToLower(valueStr);
    if(valueStr == "true" || valueStr == "1") return true;
    if(valueStr == "false" || valueStr == "0") return false;
    PrintFormat("[LIVE-CONFIG] %s is not boolean (%s) - keeping default %s", path, valueStr, defaultVal ? "true" : "false");
    return defaultVal;
}

string JsonGetString(string json, string path, string defaultVal) {
    string valueStr = JsonExtractValue(json, path);
    if(valueStr == "") return defaultVal;
    // Remove quotes
    if(StringLen(valueStr) >= 2 && valueStr[0] == '"' && valueStr[StringLen(valueStr)-1] == '"') {
        return StringSubstr(valueStr, 1, StringLen(valueStr) - 2);
    }
    return valueStr;
}

string JsonExtractValue(string json, string path) {
    // Parse dot notation: "risk.maxRiskPerTrade"
    string current = json;
    string remaining = path;
    
    while(true) {
        int dot = StringFind(remaining, ".");
        string key = (dot < 0) ? remaining : StringSubstr(remaining, 0, dot);
        
        // Find key in current object
        string search = "\"" + key + "\"";
        int pos = StringFind(current, search);
        if(pos < 0) return "";
        
        pos = StringFind(current, ":", pos);
        if(pos < 0) return "";
        pos++;
        
        // Skip whitespace
        while(pos < StringLen(current) && (current[pos] == ' ' || current[pos] == '\t' || current[pos] == '\n' || current[pos] == '\r')) pos++;
        if(pos >= StringLen(current)) return "";
        
        if(dot < 0) {
            // Last key - extract value
            if(current[pos] == '{') {
                // Object value - find matching brace
                int depth = 0;
                int end = pos;
                for(; end < StringLen(current); end++) {
                    if(current[end] == '{') depth++;
                    else if(current[end] == '}') {
                        depth--;
                        if(depth == 0) break;
                    }
                }
                if(depth == 0) return StringSubstr(current, pos, end - pos + 1);
            } else if(current[pos] == '[') {
                // Array value
                int depth = 0;
                int end = pos;
                for(; end < StringLen(current); end++) {
                    if(current[end] == '[') depth++;
                    else if(current[end] == ']') {
                        depth--;
                        if(depth == 0) break;
                    }
                }
                if(depth == 0) return StringSubstr(current, pos, end - pos + 1);
            } else if(current[pos] == '"') {
                // String value
                int end = pos + 1;
                for(; end < StringLen(current); end++) {
                    if(current[end] == '"' && current[end-1] != '\\') break;
                }
                return StringSubstr(current, pos, end - pos + 1);
            } else {
                // Number/boolean/null
                int end = pos;
                for(; end < StringLen(current); end++) {
                    ushort c = current[end];
                    if(c == ',' || c == '}' || c == ']' || c == ' ' || c == '\t' || c == '\n' || c == '\r') break;
                }
                return StringSubstr(current, pos, end - pos);
            }
            return "";
        } else {
            // Navigate into object
            if(current[pos] != '{') return "";
            int depth = 0;
            int end = pos;
            for(; end < StringLen(current); end++) {
                if(current[end] == '{') depth++;
                else if(current[end] == '}') {
                    depth--;
                    if(depth == 0) break;
                }
            }
            if(depth != 0) return "";
            current = StringSubstr(current, pos, end - pos + 1);
            remaining = StringSubstr(remaining, dot + 1);
        }
    }
    return "";
}

#endif // CORE_CONFIG_LIVE_CONFIG_RELOADER_MQH
