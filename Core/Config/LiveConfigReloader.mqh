// Hot-reload configuration from JSON file without restart
#property strict
#ifndef CORE_CONFIG_LIVE_CONFIG_RELOADER_MQH
#define CORE_CONFIG_LIVE_CONFIG_RELOADER_MQH

#include "../Utils/StructuredLogger.mqh"
#include "../Utils/LogMacros.mqh"

// ------------------------------------------------------------------
// Single JSON tokenizer + recursive descent parser.
//
// JsonTokenize() scans the whole document once into a token array.
// Every validation and extraction pass runs on that token stream, so
// there is one tokenizer/parser for the whole file instead of ad-hoc
// StringFind scans. Objects reject duplicate keys.
// ------------------------------------------------------------------

enum EJsonTokenType
{
   JSON_TOK_NONE = -1,
   JSON_TOK_LBRACE,     // {
   JSON_TOK_RBRACE,     // }
   JSON_TOK_LBRACKET,   // [
   JSON_TOK_RBRACKET,   // ]
   JSON_TOK_COLON,      // :
   JSON_TOK_COMMA,      // ,
   JSON_TOK_STRING,
   JSON_TOK_NUMBER,
   JSON_TOK_TRUE,
   JSON_TOK_FALSE,
   JSON_TOK_NULL,
   JSON_TOK_EOF
};

struct SJsonToken
{
   EJsonTokenType type;   // token kind
   int            pos;    // start index in source string (0-based, characters)
   int            len;    // length in characters
   string         raw;    // source text of the token
   string         value;  // unescaped string value (strings); raw text otherwise
};

// ---------- forward declarations: helpers used by the class below ----------
ushort JsonCharAt(const string s, const int pos);
void   JsonSkipWhitespace(const string s, int &pos);
bool   JsonTokenize(const string s, SJsonToken &tokens[]);
bool   JsonDocumentIsWellFormed(const string s, string &reason);
string JsonExtractValue(const string json, const string path, string &reason);
bool   JsonIsNumericLiteral(const string valueStr);
double JsonGetDouble(string json, string path, double defaultVal);
long   JsonGetLong(string json, string path, long defaultVal);
bool   JsonGetBool(string json, string path, bool defaultVal);
string JsonGetString(string json, string path, string defaultVal);
bool   JsonCheckNumericBound(const string json, const string path, const double minVal, const double maxVal, string &reason);
bool   JsonCheckBoolLiteral(const string json, const string path, string &reason);
bool   ValidateLiveConfigDocument(const string json, string &reason);

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

// ---------- low-level character helpers ----------

ushort JsonCharAt(const string s, const int pos)
{
   return (pos >= 0 && pos < StringLen(s)) ? StringGetCharacter(s, pos) : 0;
}

void JsonSkipWhitespace(const string s, int &pos)
{
   while(pos < StringLen(s))
   {
      ushort c = StringGetCharacter(s, pos);
      if(c != ' ' && c != '\t' && c != '\r' && c != '\n') break;
      pos++;
   }
}

// Scan a JSON string starting at s[pos] == '"'. On success pos points past the closing quote.
bool JsonScanString(const string s, int &pos, SJsonToken &t)
{
   pos++; // skip opening quote
   int start = pos;
   string unescaped = "";
   while(pos < StringLen(s))
   {
      ushort c = StringGetCharacter(s, pos);
      if(c == '"')
      {
         t.type = JSON_TOK_STRING;
         t.len = pos - start + 1;          // include closing quote in raw span
         t.raw = StringSubstr(s, start - 1, t.len);
         t.value = unescaped;
         pos++;                            // skip closing quote
         return true;
      }
      if(c < 32) return false;             // raw control character not allowed
      if(c == '\\')
      {
         pos++;
         ushort e = StringGetCharacter(s, pos);
         if(e == '"')  { unescaped += "\"";  pos++; }
         else if(e == '\\') { unescaped += "\\"; pos++; }
         else if(e == '/')  { unescaped += "/"; pos++; }
         else if(e == 'b')  { unescaped += CharToString(8); pos++; }
         else if(e == 'f')  { unescaped += CharToString(12); pos++; }
         else if(e == 'n')  { unescaped += "\n"; pos++; }
         else if(e == 'r')  { unescaped += "\r"; pos++; }
         else if(e == 't')  { unescaped += "\t"; pos++; }
         else if(e == 'u')
         {
            pos++;
            ushort cp = 0;
            bool ok = true;
            for(int k = 0; k < 4; k++)
            {
               ushort h = StringGetCharacter(s, pos);
               bool hex = (h >= '0' && h <= '9') || (h >= 'a' && h <= 'f') || (h >= 'A' && h <= 'F');
               if(!hex) { ok = false; break; }
               if(h >= 'A' && h <= 'F') cp = (ushort)(cp * 16 + (h - 'A' + 10));
               else if(h >= 'a' && h <= 'f') cp = (ushort)(cp * 16 + (h - 'a' + 10));
               else cp = (ushort)(cp * 16 + (h - '0'));
               pos++;
            }
            if(!ok) return false;
            unescaped += CharToString((uchar)cp);
         }
         else return false;
      }
      else
      {
         unescaped += CharToString((uchar)c);
         pos++;
      }
   }
   return false; // unterminated string
}

// Scan a JSON number starting at s[pos].
bool JsonScanNumber(const string s, int &pos, SJsonToken &t)
{
   int start = pos;
   if(StringGetCharacter(s, pos) == '-') pos++;
   ushort c = StringGetCharacter(s, pos);
   if(c == '0') pos++;
   else if(c >= '1' && c <= '9')
   {
      while(pos < StringLen(s))
      {
         ushort cc = StringGetCharacter(s, pos);
         if(cc < '0' || cc > '9') break;
         pos++;
      }
   }
   else return false;
   if(pos < StringLen(s) && StringGetCharacter(s, pos) == '.')
   {
      pos++;
      if(pos >= StringLen(s) || StringGetCharacter(s, pos) < '0' || StringGetCharacter(s, pos) > '9') return false;
      while(pos < StringLen(s))
      {
         ushort cc = StringGetCharacter(s, pos);
         if(cc < '0' || cc > '9') break;
         pos++;
      }
   }
   if(pos < StringLen(s) && (StringGetCharacter(s, pos) == 'e' || StringGetCharacter(s, pos) == 'E'))
   {
      pos++;
      if(pos < StringLen(s) && (StringGetCharacter(s, pos) == '+' || StringGetCharacter(s, pos) == '-')) pos++;
      if(pos >= StringLen(s) || StringGetCharacter(s, pos) < '0' || StringGetCharacter(s, pos) > '9') return false;
      while(pos < StringLen(s))
      {
         ushort cc = StringGetCharacter(s, pos);
         if(cc < '0' || cc > '9') break;
         pos++;
      }
   }
   t.type = JSON_TOK_NUMBER;
   t.len = pos - start;
   return true;
}

// Tokenize the whole document once. Whitespace is skipped and not emitted.
bool JsonTokenize(const string s, SJsonToken &tokens[])
{
   int pos = 0;
   int n = StringLen(s);
   while(pos < n)
   {
      JsonSkipWhitespace(s, pos);
      if(pos >= n) break;
      ushort c = StringGetCharacter(s, pos);
      SJsonToken t;
      t.pos = pos;
      bool ok = true;
      switch(c)
      {
         case '{':  t.type = JSON_TOK_LBRACE;   t.len = 1; break;
         case '}':  t.type = JSON_TOK_RBRACE;   t.len = 1; break;
         case '[':  t.type = JSON_TOK_LBRACKET; t.len = 1; break;
         case ']':  t.type = JSON_TOK_RBRACKET; t.len = 1; break;
         case ':':  t.type = JSON_TOK_COLON;    t.len = 1; break;
         case ',':  t.type = JSON_TOK_COMMA;    t.len = 1; break;
         case '"':  ok = JsonScanString(s, pos, t); break;
         case '-':
         case '0': case '1': case '2': case '3': case '4':
         case '5': case '6': case '7': case '8': case '9':
            ok = JsonScanNumber(s, pos, t); break;
         default:
            {
               if(StringSubstr(s, pos, 4) == "true")  { t.type = JSON_TOK_TRUE;  t.len = 4; pos += 4; }
               else if(StringSubstr(s, pos, 5) == "false") { t.type = JSON_TOK_FALSE; t.len = 5; pos += 5; }
               else if(StringSubstr(s, pos, 4) == "null")  { t.type = JSON_TOK_NULL;  t.len = 4; pos += 4; }
               else ok = false;
            }
            break;
      }
      if(!ok) return false;
      t.raw = StringSubstr(s, t.pos, t.len);
      t.value = t.raw;
      ArrayResize(tokens, ArraySize(tokens) + 1);
      tokens[ArraySize(tokens) - 1] = t;
   }
   SJsonToken eof;
   eof.type = JSON_TOK_EOF; eof.pos = n; eof.len = 0; eof.raw = ""; eof.value = "";
   ArrayResize(tokens, ArraySize(tokens) + 1);
   tokens[ArraySize(tokens) - 1] = eof;
   return true;
}

// Skip one complete value, advancing pos past it.
bool JsonSkipValue(SJsonToken &tkns[], int &pos, string &reason, int depth)
{
   if(depth > 64) { reason = "JSON nesting too deep"; return false; }
   switch(tkns[pos].type)
   {
      case JSON_TOK_LBRACE:
      {
         pos++;
         if(tkns[pos].type == JSON_TOK_RBRACE) { pos++; return true; }
         while(true)
         {
            if(tkns[pos].type != JSON_TOK_STRING) { reason = "expected object key"; return false; }
            pos++;
            if(tkns[pos].type != JSON_TOK_COLON) { reason = "expected ':' after key"; return false; }
            pos++;
            if(!JsonSkipValue(tkns, pos, reason, depth + 1)) return false;
            if(tkns[pos].type == JSON_TOK_RBRACE) { pos++; return true; }
            if(tkns[pos].type != JSON_TOK_COMMA) { reason = "expected ',' or '}'"; return false; }
            pos++;
         }
      }
      case JSON_TOK_LBRACKET:
      {
         pos++;
         if(tkns[pos].type == JSON_TOK_RBRACKET) { pos++; return true; }
         while(true)
         {
            if(!JsonSkipValue(tkns, pos, reason, depth + 1)) return false;
            if(tkns[pos].type == JSON_TOK_RBRACKET) { pos++; return true; }
            if(tkns[pos].type != JSON_TOK_COMMA) { reason = "expected ',' or ']'"; return false; }
            pos++;
         }
      }
      default:
         pos++; return true; // string, number, true, false, null
   }
}

// Parse one object, tracking keys to detect duplicates within this object.
bool JsonParseObject(SJsonToken &tkns[], int &pos, string &reason, bool &dupKey, int depth)
{
   if(depth > 64) { reason = "JSON nesting too deep"; return false; }
   pos++; // skip {
   if(tkns[pos].type == JSON_TOK_RBRACE) { pos++; return true; }
   string keys[];
   while(true)
   {
      if(tkns[pos].type != JSON_TOK_STRING) { reason = "expected object key"; return false; }
      string key = tkns[pos].value;
      pos++;
      // reject duplicate keys within this object
      for(int i = 0; i < ArraySize(keys); i++)
      {
         if(keys[i] == key) { dupKey = true; break; }
      }
      ArrayResize(keys, ArraySize(keys) + 1);
      keys[ArraySize(keys) - 1] = key;
      if(tkns[pos].type != JSON_TOK_COLON) { reason = "expected ':' after key"; return false; }
      pos++;
      if(!JsonParseValue(tkns, pos, reason, dupKey, depth + 1)) return false;
      if(tkns[pos].type == JSON_TOK_RBRACE) { pos++; return true; }
      if(tkns[pos].type != JSON_TOK_COMMA) { reason = "expected ',' or '}'"; return false; }
      pos++;
   }
}

// Parse one array.
bool JsonParseArray(SJsonToken &tkns[], int &pos, string &reason, bool &dupKey, int depth)
{
   if(depth > 64) { reason = "JSON nesting too deep"; return false; }
   pos++; // skip [
   if(tkns[pos].type == JSON_TOK_RBRACKET) { pos++; return true; }
   while(true)
   {
      if(!JsonParseValue(tkns, pos, reason, dupKey, depth + 1)) return false;
      if(tkns[pos].type == JSON_TOK_RBRACKET) { pos++; return true; }
      if(tkns[pos].type != JSON_TOK_COMMA) { reason = "expected ',' or ']'"; return false; }
      pos++;
   }
}

// Parse one value.
bool JsonParseValue(SJsonToken &tkns[], int &pos, string &reason, bool &dupKey, int depth)
{
   switch(tkns[pos].type)
   {
      case JSON_TOK_LBRACE:   return JsonParseObject(tkns, pos, reason, dupKey, depth);
      case JSON_TOK_LBRACKET: return JsonParseArray(tkns, pos, reason, dupKey, depth);
      case JSON_TOK_STRING:
      case JSON_TOK_NUMBER:
      case JSON_TOK_TRUE:
      case JSON_TOK_FALSE:
      case JSON_TOK_NULL:     pos++; return true;
      default:                reason = "unexpected token"; return false;
   }
}

// Strict document check: single top-level object, no duplicates, no trailing data.
bool JsonDocumentIsWellFormed(const string s, string &reason)
{
   reason = "";
   SJsonToken tokens[];
   if(!JsonTokenize(s, tokens)) { reason = "failed to tokenize JSON"; return false; }
   int pos = 0;
   bool dupKey = false;
   if(tokens[pos].type != JSON_TOK_LBRACE) { reason = "JSON document must start with '{'"; return false; }
   if(!JsonParseValue(tokens, pos, reason, dupKey, 0)) return false;
   if(dupKey) { reason = "duplicate key in object"; return false; }
   if(tokens[pos].type != JSON_TOK_EOF) { reason = "trailing data after JSON document"; return false; }
   return true;
}

// Extract the raw value text for a dot-path (e.g. "risk.maxRiskPerTrade").
// Returns "" (and sets reason) when the path does not exist.
string JsonExtractValue(const string json, const string path, string &reason)
{
   reason = "";
   SJsonToken tokens[];
   if(!JsonTokenize(json, tokens)) { reason = "failed to tokenize JSON"; return ""; }
   int pos = 0;
   if(tokens[pos].type != JSON_TOK_LBRACE) { reason = "JSON document must start with '{'"; return ""; }

   // split dot-path into keys
   string keys[];
   {
      string remaining = path;
      while(true)
      {
         int dot = StringFind(remaining, ".");
         string key = (dot < 0) ? remaining : StringSubstr(remaining, 0, dot);
         ArrayResize(keys, ArraySize(keys) + 1);
         keys[ArraySize(keys) - 1] = key;
         if(dot < 0) break;
         remaining = StringSubstr(remaining, dot + 1);
      }
   }

   int last = ArraySize(keys) - 1;
   for(int i = 0; i <= last; i++)
   {
      if(tokens[pos].type != JSON_TOK_LBRACE)
      {
         reason = "path '" + path + "' is not an object at '" + keys[i] + "'";
         return "";
      }
      pos++; // skip {
      bool found = false;
      int valueStart = -1;
      if(tokens[pos].type != JSON_TOK_RBRACE)
      {
         while(true)
         {
            if(tokens[pos].type != JSON_TOK_STRING) { reason = "expected object key"; return ""; }
            string key = tokens[pos].value;
            pos++;
            if(tokens[pos].type != JSON_TOK_COLON) { reason = "expected ':' after key"; return ""; }
            pos++;
            valueStart = pos;
            if(!JsonSkipValue(tokens, pos, reason, 0)) return "";
            if(key == keys[i])
            {
               found = true;
               break;
            }
            if(tokens[pos].type == JSON_TOK_RBRACE) { pos++; break; }
            if(tokens[pos].type != JSON_TOK_COMMA) { reason = "expected ',' or '}'"; return ""; }
            pos++;
         }
      }
      else
      {
         pos++; // skip }
      }
      if(!found) { reason = "key not found: " + keys[i]; return ""; }
      if(i == last)
      {
         int start = tokens[valueStart].pos;
         int end = (pos > 0) ? (tokens[pos - 1].pos + tokens[pos - 1].len) : start;
         return StringSubstr(json, start, end - start);
      }
      // descend into the value for the next path segment
      pos = valueStart;
   }
   return "";
}

bool JsonIsNumericLiteral(const string valueStr)
{
   if(valueStr == "") return false;
   for(int i = 0; i < StringLen(valueStr); i++)
   {
      ushort c = StringGetCharacter(valueStr, i);
      bool digit = (c >= '0' && c <= '9');
      bool sign = (c == '+' || c == '-');
      bool point = (c == '.');
      bool exponent = (c == 'e' || c == 'E');
      if(!digit && !sign && !point && !exponent) return false;
   }
   return true;
}

double JsonGetDouble(string json, string path, double defaultVal)
{
   // Dot-path lookup: "risk.maxRiskPerTrade"
   string reason = "";
   string valueStr = JsonExtractValue(json, path, reason);
   if(valueStr == "") return defaultVal;
   if(!JsonIsNumericLiteral(valueStr)) {
      PrintFormat("[LIVE-CONFIG] %s is not numeric (%s) - keeping default %.4f", path, valueStr, defaultVal);
      return defaultVal;
   }
   return StringToDouble(valueStr);
}

long JsonGetLong(string json, string path, long defaultVal)
{
   string reason = "";
   string valueStr = JsonExtractValue(json, path, reason);
   if(valueStr == "") return defaultVal;
   if(!JsonIsNumericLiteral(valueStr)) {
      PrintFormat("[LIVE-CONFIG] %s is not an integer (%s) - keeping default %d", path, valueStr, defaultVal);
      return defaultVal;
   }
   return StringToInteger(valueStr);
}

bool JsonGetBool(string json, string path, bool defaultVal)
{
   string reason = "";
   string valueStr = JsonExtractValue(json, path, reason);
   if(valueStr == "") return defaultVal;
   StringToLower(valueStr);
   if(valueStr == "true" || valueStr == "1") return true;
   if(valueStr == "false" || valueStr == "0") return false;
   PrintFormat("[LIVE-CONFIG] %s is not boolean (%s) - keeping default %s", path, valueStr, defaultVal ? "true" : "false");
   return defaultVal;
}

string JsonGetString(string json, string path, string defaultVal)
{
   string reason = "";
   string valueStr = JsonExtractValue(json, path, reason);
   if(valueStr == "") return defaultVal;
   // Remove surrounding quotes
   if(StringLen(valueStr) >= 2 && valueStr[0] == '"' && valueStr[StringLen(valueStr)-1] == '"') {
      return StringSubstr(valueStr, 1, StringLen(valueStr) - 2);
   }
   return valueStr;
}

bool JsonCheckNumericBound(const string json, const string path, const double minVal, const double maxVal, string &reason)
{
   string dummy = "";
   string valueStr = JsonExtractValue(json, path, dummy);
   if(valueStr == "") return true; // key absent: nothing to check
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

bool JsonCheckBoolLiteral(const string json, const string path, string &reason)
{
   string dummy = "";
   string valueStr = JsonExtractValue(json, path, dummy);
   if(valueStr == "" || valueStr == "true" || valueStr == "false") return true;
   reason = path + " is not a boolean (" + valueStr + ")";
   return false;
}

// Strict JSON grammar check (RFC 8259) plus range checks for the keys the owner applies.
// Rejects duplicate keys anywhere in the document.
bool ValidateLiveConfigDocument(const string json, string &reason)
{
   reason = "";
   if(!JsonDocumentIsWellFormed(json, reason)) {
      reason = "malformed JSON document: " + reason;
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

#endif // CORE_CONFIG_LIVE_CONFIG_RELOADER_MQH
