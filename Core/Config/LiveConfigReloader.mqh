//+------------------------------------------------------------------+
//| LiveConfigReloader.mqh                                           |
//| Hot-reload configuration from JSON file without restart          |
//+------------------------------------------------------------------+
#property strict
#ifndef CORE_CONFIG_LIVE_CONFIG_RELOADER_MQH
#define CORE_CONFIG_LIVE_CONFIG_RELOADER_MQH

#include <Arrays/ArrayObj.mqh>
#include "../Utils/StructuredLogger.mqh"
#include "../Utils/LogMacros.mqh"

//+------------------------------------------------------------------+
//| Callback interface for config changes                            |
//+------------------------------------------------------------------+
class IConfigCallback : public CObject
{
public:
    virtual void OnConfigChange(string section, string json) = 0;
    virtual string GetSectionName() const = 0;
    virtual ~IConfigCallback() {}
};

//+------------------------------------------------------------------+
//| Callback implementation - users derive from this class           |
//+------------------------------------------------------------------+
class CConfigCallbackBase : public IConfigCallback
{
protected:
    string m_sectionName;
    
public:
    CConfigCallbackBase(string section) : m_sectionName(section) {}
    
    virtual void OnConfigChange(string section, string json) override {
        // Override in derived class
    }
    
    virtual string GetSectionName() const override { return m_sectionName; }
};

//+------------------------------------------------------------------+
//| CLiveConfigReloader                                              |
//+------------------------------------------------------------------+
class CLiveConfigReloader
{
private:
    string m_configPath;
    datetime m_lastCheck;
    datetime m_lastModified;
    bool   m_enabled;
    int    m_checkIntervalSec;
    
    CArrayObj* m_callbacks;
    
    // Parsed config cache
    string m_lastJson;
    
public:
    CLiveConfigReloader() : m_lastCheck(0), m_lastModified(0), m_enabled(false), 
                            m_checkIntervalSec(30) {
        m_callbacks = new CArrayObj();
    }
    
    ~CLiveConfigReloader() {
        if(CheckPointer(m_callbacks) == POINTER_DYNAMIC) delete m_callbacks;
    }
    
    // Initialize with config file path
    void Init(string path = "Config/live_overrides.json", int checkIntervalSec = 30) {
        string dataPath = TerminalInfoString(TERMINAL_DATA_PATH);
        m_configPath = dataPath + "\\MQL5\\Files\\" + path;
        m_checkIntervalSec = checkIntervalSec;
        
        // Get initial file modification time
        m_lastModified = GetFileWriteTime(m_configPath);
        m_enabled = true;
        
        Print("[LIVE-CONFIG] Watching: ", m_configPath, " (interval: ", m_checkIntervalSec, "s)");
        g_structLog.LogInfo("LIVE-CONFIG", "Initialized watching " + m_configPath);
    }
    
    // Register callback for config section
    void RegisterCallback(IConfigCallback* callback) {
        if(callback != NULL) {
            m_callbacks.Add(callback);
            Print("[LIVE-CONFIG] Registered callback object for section: ", callback.GetSectionName());
        }
    }
    
    // Enable/disable
    void SetEnabled(bool enabled) { m_enabled = enabled; }
    bool IsEnabled() const { return m_enabled; }
    
    // Main check function - call from OnTimer
    void CheckAndReload() {
        if(!m_enabled) return;
        if(TimeCurrent() - m_lastCheck < m_checkIntervalSec) return;
        m_lastCheck = TimeCurrent();
        
        datetime currentModified = GetFileWriteTime(m_configPath);
        if(currentModified <= m_lastModified) {
            return;
        }
        
        m_lastModified = currentModified;
        
        Print("[LIVE-CONFIG] File changed, reloading...");
        g_structLog.LogInfo("LIVE-CONFIG", "File modified, reloading config");
        
        string json = ReadFileToString(m_configPath);
        if(json == "") {
            Print("[LIVE-CONFIG] ERROR: Failed to read config file");
            g_structLog.LogError("LIVE-CONFIG", "Failed to read config file");
            return;
        }
        
        // Validate JSON structure (basic)
        if(!ValidateJson(json)) {
            Print("[LIVE-CONFIG] ERROR: Invalid JSON structure");
            g_structLog.LogError("LIVE-CONFIG", "Invalid JSON structure");
            return;
        }
        
        // Check if actually changed
        if(json == m_lastJson) {
            Print("[LIVE-CONFIG] Config unchanged (same content)");
            return;
        }
        m_lastJson = json;
        
        // Parse and notify callbacks
        NotifyCallbacks(json);
        
        Print("[LIVE-CONFIG] Reload complete, ", m_callbacks.Total(), " callbacks notified");
        g_structLog.LogInfo("LIVE-CONFIG", "Reload complete, callbacks=" + IntegerToString(m_callbacks.Total()));
    }
    
    // Force reload (e.g., from dashboard command)
    void ForceReload() {
        m_lastModified = 0; // Force reload
        CheckAndReload();
    }
    
    // Get current config as JSON string
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
    
    // Get object section
    static string GetSection(string json, string section) {
        return JsonGetSection(json, section);
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
    
    void NotifyCallbacks(string json) {
        // Parse top-level sections
        string riskJson = GetSection(json, "risk");
        string weightsJson = GetSection(json, "weights");
        string thresholdsJson = GetSection(json, "thresholds");
        string symbolsJson = GetSection(json, "symbols");
        string aiJson = GetSection(json, "ai");
        string engineJson = GetSection(json, "engines");
        
        // Notify each callback with relevant section
        for(int i = 0; i < m_callbacks.Total(); i++) {
            IConfigCallback* cb = m_callbacks.At(i);
            if(cb == NULL) continue;
            
            string section = cb.GetSectionName();
            string sectionJson = "";
            
            if(section == "Risk" || section == "risk") sectionJson = riskJson;
            else if(section == "Weights" || section == "weights") sectionJson = weightsJson;
            else if(section == "Thresholds" || section == "thresholds") sectionJson = thresholdsJson;
            else if(section == "Symbols" || section == "symbols") sectionJson = symbolsJson;
            else if(section == "AI" || section == "ai") sectionJson = aiJson;
            else if(section == "Engines" || section == "engines") sectionJson = engineJson;
            else sectionJson = json; // Full config
            
            if(sectionJson != "") {
                cb.OnConfigChange(section, sectionJson);
            }
        }
    }
};

//+------------------------------------------------------------------+
//| JSON parsing helpers (MQL5 Json functions are limited)           |
//+------------------------------------------------------------------+
double JsonGetDouble(string json, string path, double defaultVal) {
    // Simple dot-path parser: "risk.maxRiskPerTrade"
    string valueStr = JsonExtractValue(json, path);
    if(valueStr == "") return defaultVal;
    return StringToDouble(valueStr);
}

long JsonGetLong(string json, string path, long defaultVal) {
    string valueStr = JsonExtractValue(json, path);
    if(valueStr == "") return defaultVal;
    return StringToInteger(valueStr);
}

bool JsonGetBool(string json, string path, bool defaultVal) {
    string valueStr = JsonExtractValue(json, path);
    if(valueStr == "") return defaultVal;
    StringToLower(valueStr);
    return valueStr == "true" || valueStr == "1" || valueStr == "yes";
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

string JsonGetSection(string json, string section) {
    // Extract "section": { ... } as string
    string search = "\"" + section + "\"";
    int start = StringFind(json, search);
    if(start < 0) return "";
    
    start = StringFind(json, ":", start);
    if(start < 0) return "";
    start++; // Skip :
    
    // Skip whitespace
    while(start < StringLen(json) && (json[start] == ' ' || json[start] == '\t' || json[start] == '\n' || json[start] == '\r')) start++;
    if(start >= StringLen(json)) return "";
    
    if(json[start] != '{') return "";
    
    // Find matching closing brace
    int depth = 0;
    int end = start;
    for(; end < StringLen(json); end++) {
        if(json[end] == '{') depth++;
        else if(json[end] == '}') {
            depth--;
            if(depth == 0) break;
        }
    }
    
    if(depth != 0) return "";
    return StringSubstr(json, start, end - start + 1);
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