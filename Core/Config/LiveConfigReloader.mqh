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
    string m_lastRejectReason;

    // Parsed config cache
    string m_lastJson;

public:
    CLiveConfigReloader() : m_lastCheckMs(0), m_lastModified(0),
                            m_checkIntervalSec(30),
                            m_pendingReload(false),
                            m_unreadableReported(false),
                            m_lastRejectReason("") {}
    
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

        Print("[LIVE-CONFIG] File changed, reloading...");
        g_structLog.LogInfo("LIVE-CONFIG", "File modified, reloading config");

        string json = ReadFileToString(m_configPath);
        if(json == "") {
            Print("[LIVE-CONFIG] ERROR: Failed to read config file");
            g_structLog.LogError("LIVE-CONFIG", "Failed to read config file");
            return;
        }

        // All or nothing: a rejected file leaves the previous config active and is retried on the next check,
        // which also covers a read that caught the operator mid-write.
        string reason = "";
        if(!ValidateLiveConfigDocument(json, reason)) {
            if(reason != m_lastRejectReason) {
                m_lastRejectReason = reason;
                PrintFormat("[LIVE-CONFIG] REJECTED, previous config stays active | %s", reason);
                g_structLog.LogError("LIVE-CONFIG", "Rejected: " + reason);
            }
            return;
        }
        m_lastRejectReason = "";
        m_lastModified = currentModified;

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
    
};

// Strict JSON grammar check (RFC 8259) plus range checks for the keys the owner applies.
ushort JsonCharAt(const string s, const int pos) {
    return (pos >= 0 && pos < StringLen(s)) ? StringGetCharacter(s, pos) : 0;
}

void JsonSkipWhitespace(const string s, int &pos) {
    while(pos < StringLen(s)) {
        ushort c = StringGetCharacter(s, pos);
        if(c != ' ' && c != '\t' && c != '\r' && c != '\n') break;
        pos++;
    }
}

bool JsonIsDigitChar(const ushort c) {
    return c >= '0' && c <= '9';
}

bool JsonParseValueToken(const string s, int &pos, const int depth);

bool JsonParseStringToken(const string s, int &pos) {
    if(JsonCharAt(s, pos) != '"') return false;
    pos++;
    while(pos < StringLen(s)) {
        ushort c = StringGetCharacter(s, pos);
        if(c == '"') { pos++; return true; }
        if(c < 32) return false;
        if(c == '\\') {
            pos++;
            ushort e = JsonCharAt(s, pos);
            if(e == 'u') {
                for(int k = 0; k < 4; k++) {
                    pos++;
                    ushort h = JsonCharAt(s, pos);
                    bool hex = JsonIsDigitChar(h) || (h >= 'a' && h <= 'f') || (h >= 'A' && h <= 'F');
                    if(!hex) return false;
                }
            }
            else if(e == 0 || StringFind("\"\\/bfnrt", ShortToString(e)) < 0) return false;
        }
        pos++;
    }
    return false;
}

bool JsonParseNumberToken(const string s, int &pos) {
    int start = pos;
    if(JsonCharAt(s, pos) == '-') pos++;
    ushort c = JsonCharAt(s, pos);
    if(c == '0') pos++;
    else if(JsonIsDigitChar(c)) { while(JsonIsDigitChar(JsonCharAt(s, pos))) pos++; }
    else return false;
    if(JsonCharAt(s, pos) == '.') {
        pos++;
        if(!JsonIsDigitChar(JsonCharAt(s, pos))) return false;
        while(JsonIsDigitChar(JsonCharAt(s, pos))) pos++;
    }
    if(JsonCharAt(s, pos) == 'e' || JsonCharAt(s, pos) == 'E') {
        pos++;
        if(JsonCharAt(s, pos) == '+' || JsonCharAt(s, pos) == '-') pos++;
        if(!JsonIsDigitChar(JsonCharAt(s, pos))) return false;
        while(JsonIsDigitChar(JsonCharAt(s, pos))) pos++;
    }
    return pos > start;
}

bool JsonParseObjectToken(const string s, int &pos, const int depth) {
    pos++;
    JsonSkipWhitespace(s, pos);
    if(JsonCharAt(s, pos) == '}') { pos++; return true; }
    while(true) {
        JsonSkipWhitespace(s, pos);
        if(!JsonParseStringToken(s, pos)) return false;
        JsonSkipWhitespace(s, pos);
        if(JsonCharAt(s, pos) != ':') return false;
        pos++;
        if(!JsonParseValueToken(s, pos, depth + 1)) return false;
        JsonSkipWhitespace(s, pos);
        ushort c = JsonCharAt(s, pos);
        pos++;
        if(c == '}') return true;
        if(c != ',') return false;
    }
    return false;
}

bool JsonParseArrayToken(const string s, int &pos, const int depth) {
    pos++;
    JsonSkipWhitespace(s, pos);
    if(JsonCharAt(s, pos) == ']') { pos++; return true; }
    while(true) {
        if(!JsonParseValueToken(s, pos, depth + 1)) return false;
        JsonSkipWhitespace(s, pos);
        ushort c = JsonCharAt(s, pos);
        pos++;
        if(c == ']') return true;
        if(c != ',') return false;
    }
    return false;
}

bool JsonParseValueToken(const string s, int &pos, const int depth) {
    if(depth > 64) return false;
    JsonSkipWhitespace(s, pos);
    ushort c = JsonCharAt(s, pos);
    if(c == '{') return JsonParseObjectToken(s, pos, depth);
    if(c == '[') return JsonParseArrayToken(s, pos, depth);
    if(c == '"') return JsonParseStringToken(s, pos);
    if(c == '-' || JsonIsDigitChar(c)) return JsonParseNumberToken(s, pos);
    if(StringSubstr(s, pos, 4) == "true" || StringSubstr(s, pos, 4) == "null") { pos += 4; return true; }
    if(StringSubstr(s, pos, 5) == "false") { pos += 5; return true; }
    return false;
}

bool JsonDocumentIsWellFormed(const string s) {
    int pos = 0;
    JsonSkipWhitespace(s, pos);
    if(JsonCharAt(s, pos) != '{') return false;
    if(!JsonParseValueToken(s, pos, 0)) return false;
    JsonSkipWhitespace(s, pos);
    return pos == StringLen(s);
}

bool JsonCheckNumericBound(const string json, const string path, const double minVal, const double maxVal, string &reason) {
    string valueStr = JsonExtractValue(json, path);
    if(valueStr == "") return true;
    if(!JsonIsNumericLiteral(valueStr)) {
        reason = path + " is not numeric (" + valueStr + ")";
        return false;
    }
    double v = StringToDouble(valueStr);
    if(v < minVal || v > maxVal) {
        reason = StringFormat("%s=%s outside [%g, %g]", path, valueStr, minVal, maxVal);
        return false;
    }
    return true;
}

bool JsonCheckBoolLiteral(const string json, const string path, string &reason) {
    string valueStr = JsonExtractValue(json, path);
    if(valueStr == "" || valueStr == "true" || valueStr == "false") return true;
    reason = path + " is not a boolean (" + valueStr + ")";
    return false;
}

bool ValidateLiveConfigDocument(const string json, string &reason) {
    reason = "";
    if(!JsonDocumentIsWellFormed(json)) {
        reason = "malformed JSON document";
        return false;
    }
    return JsonCheckNumericBound(json, "risk.maxRiskPerTrade", 0.0001, 10.0, reason)
        && JsonCheckNumericBound(json, "risk.maxDailyRisk", 0.0001, 100.0, reason)
        && JsonCheckNumericBound(json, "risk.maxPortfolioRisk", 0.0001, 100.0, reason)
        && JsonCheckNumericBound(json, "risk.maxDrawdown", 0.0001, 100.0, reason)
        && JsonCheckNumericBound(json, "risk.dailyLossLimitPercent", 0.0001, 100.0, reason)
        && JsonCheckNumericBound(json, "risk.minLotRiskMultiplier", 1.0, 10.0, reason)
        && JsonCheckNumericBound(json, "risk.riskTier", 0.0, 8.0, reason)
        && JsonCheckBoolLiteral(json, "risk.allowMinLotRoundUp", reason)
        && JsonCheckBoolLiteral(json, "risk.enableCompoundingTiers", reason)
        && JsonCheckBoolLiteral(json, "risk.resetCircuitBreaker", reason);
}

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
