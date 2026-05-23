
//+------------------------------------------------------------------+
//| PythonBridge.mqh                                                 |
//| Purpose: Bridge between MQL5 EA and Python server                |
//| Features: Timeout handling, reconnection, fallback to local AI   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025"
#property link      ""
#property version   "1.00"
#property strict

#include "Enums.mqh"
#include "ErrorHandling.mqh"

//+------------------------------------------------------------------+
//| Python Bridge Health State Enum                                  |
//+------------------------------------------------------------------+
enum ENUM_PYTHON_BRIDGE_STATE
{
   PYTHON_BRIDGE_DISCONNECTED = 0,   // Not connected
   PYTHON_BRIDGE_CONNECTING   = 1,   // Attempting connection
   PYTHON_BRIDGE_CONNECTED    = 2,   // Connected and healthy
   PYTHON_BRIDGE_ERROR        = 3    // Error state
};

//+------------------------------------------------------------------+
//| Python Bridge Version Information                                |
//+------------------------------------------------------------------+
struct SPythonBridgeVersion
{
   string             version;         // Server version string
   int                major;           // Major version
   int                minor;           // Minor version
   int                patch;           // Patch version
   bool               compatible;      // Is compatible with this client
   
   SPythonBridgeVersion()
   {
      version = "";
      major = 0;
      minor = 0;
      patch = 0;
      compatible = false;
   }
};

//+------------------------------------------------------------------+
//| Python Bridge Health Status                                      |
//+------------------------------------------------------------------+
struct SPythonBridgeHealthStatus
{
   ENUM_PYTHON_BRIDGE_STATE state;    // Connection state
   bool               connected;       // Is connected
   bool               healthy;         // Is healthy
   datetime           last_heartbeat;  // Last successful heartbeat
   int                reconnect_attempts; // Number of reconnect attempts
   int                request_count;   // Total requests sent
   int                success_count;   // Successful requests
   int                error_count;     // Failed requests
   string             last_error;      // Last error message
   SPythonBridgeVersion version;       // Server version info
   
   SPythonBridgeHealthStatus()
   {
      state = PYTHON_BRIDGE_DISCONNECTED;
      connected = false;
      healthy = false;
      last_heartbeat = 0;
      reconnect_attempts = 0;
      request_count = 0;
      success_count = 0;
      error_count = 0;
      last_error = "";
   }
};

//+------------------------------------------------------------------+
//| Python Bridge Response Structure                                 |
//+------------------------------------------------------------------+
struct SPythonBridgeResponse
{
   bool               success;         // Request successful
   string             error_message;   // Error message if failed
   double             buy_prob;        // Buy probability
   double             sell_prob;       // Sell probability
   double             hold_prob;       // Hold probability
   double             lgbm_buy;        // LGBM buy probability
   double             lgbm_sell;       // LGBM sell probability
   double             stacker_signal;  // Stacker signal
   string             ts;              // Timestamp
   string             mode;            // Response mode
   double             adapted_features[]; // Adapted features (for doubleadapt)
   
   SPythonBridgeResponse()
   {
      success = false;
      error_message = "";
      buy_prob = 0.0;
      sell_prob = 0.0;
      hold_prob = 0.0;
      lgbm_buy = 0.0;
      lgbm_sell = 0.0;
      stacker_signal = 0.0;
      ts = "";
      mode = "";
      ArrayResize(adapted_features, 0);
   }
};

//+------------------------------------------------------------------+
//| Python Bridge Class                                              |
//+------------------------------------------------------------------+
class CPythonBridge
{
private:
   string              m_endpoint;          // Server endpoint (http://host:port)
   ENUM_PYTHON_BRIDGE_MODE m_mode;          // Bridge mode
   int                 m_request_timeout;   // Request timeout (ms)
   int                 m_heartbeat_timeout; // Heartbeat timeout (s)
   datetime            m_last_heartbeat;    // Last successful heartbeat
   datetime            m_last_reconnect;    // Last reconnection attempt
   int                 m_reconnect_attempts;// Number of reconnect attempts
   int                 m_max_reconnect_attempts; // Max reconnect attempts
   int                 m_reconnect_backoff; // Reconnect backoff (ms)
   ENUM_PYTHON_BRIDGE_STATE m_state;        // Current bridge state
   bool                m_initialized;       // Initialized flag
   SPythonBridgeVersion m_server_version;   // Server version info
   int                 m_request_count;     // Total requests count
   int                 m_success_count;     // Successful requests count
   int                 m_error_count;       // Failed requests count
   string              m_last_error;        // Last error message
   
   // Internal methods
   string              EscapeJsonString(const string &str);
   bool                SendHttpRequest(const string &method, const string &url,
                                       const string &post_data, string &response);
   SPythonBridgeResponse ParsePredictionResponse(const string &json_str);
   void                LogBridgeState(string message, ENUM_ERROR_LEVEL level = ERROR_LEVEL_INFO);
   bool                ValidateJsonResponse(const string &json_str);
   bool                ParseVersionResponse(const string &json_str, SPythonBridgeVersion &version);
   bool                CheckVersionCompatibility(const SPythonBridgeVersion &version);
   
public:
   // Constructor/Destructor
                      CPythonBridge();
                     ~CPythonBridge();
   
   // Initialization
   bool              Initialize(const string &endpoint, 
                                 ENUM_PYTHON_BRIDGE_MODE mode = PYTHON_BRIDGE_OBSERVE,
                                 int request_timeout_ms = 5000,
                                 int heartbeat_timeout_s = 30,
                                 int max_reconnect_attempts = 5,
                                 int reconnect_backoff_ms = 2000);
   void              Shutdown();
   
   // Health checks
   bool              CheckHealth();
   bool              SendHeartbeat();
   SPythonBridgeHealthStatus GetHealthStatus();
   
   // Version checking
   bool              CheckVersion();
   SPythonBridgeVersion GetServerVersion() const { return m_server_version; }
   
   // Prediction methods
   SPythonBridgeResponse Predict(const double &features[], int features_size,
                                  const string mode);
   SPythonBridgeResponse PredictDoubleAdapt(const double &features[], int features_size);
   SPythonBridgeResponse PredictMamlPpo(const double &features[], int features_size);
   
   // Getters
   ENUM_PYTHON_BRIDGE_STATE GetState() const { return m_state; }
   bool              IsConnected() const { return m_state == PYTHON_BRIDGE_CONNECTED; }
   bool              IsInitialized() const { return m_initialized; }
   string            GetEndpoint() const { return m_endpoint; }
   int               GetRequestCount() const { return m_request_count; }
   int               GetSuccessCount() const { return m_success_count; }
   int               GetErrorCount() const { return m_error_count; }
   string            GetLastError() const { return m_last_error; }
   
   // Utility
   bool              AttemptReconnect();
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CPythonBridge::CPythonBridge()
{
   m_endpoint = "http://127.0.0.1:8000";
   m_mode = PYTHON_BRIDGE_OBSERVE;
   m_request_timeout = 5000;
   m_heartbeat_timeout = 30;
   m_last_heartbeat = 0;
   m_last_reconnect = 0;
   m_reconnect_attempts = 0;
   m_max_reconnect_attempts = 5;
   m_reconnect_backoff = 2000;
   m_state = PYTHON_BRIDGE_DISCONNECTED;
   m_initialized = false;
   m_request_count = 0;
   m_success_count = 0;
   m_error_count = 0;
   m_last_error = "";
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CPythonBridge::~CPythonBridge()
{
   Shutdown();
}

//+------------------------------------------------------------------+
//| Initialize the Python Bridge                                     |
//+------------------------------------------------------------------+
bool CPythonBridge::Initialize(const string &endpoint,
                                ENUM_PYTHON_BRIDGE_MODE mode,
                                int request_timeout_ms,
                                int heartbeat_timeout_s,
                                int max_reconnect_attempts,
                                int reconnect_backoff_ms)
{
   m_endpoint = endpoint;
   m_mode = mode;
   m_request_timeout = request_timeout_ms;
   m_heartbeat_timeout = heartbeat_timeout_s;
   m_max_reconnect_attempts = max_reconnect_attempts;
   m_reconnect_backoff = reconnect_backoff_ms;
   m_initialized = true;
   
   LogBridgeState("Python bridge initialized with endpoint: " + m_endpoint);
   
   // Attempt initial health check
   if(m_mode != PYTHON_BRIDGE_OFF)
   {
      if(CheckHealth())
      {
         m_state = PYTHON_BRIDGE_CONNECTED;
         LogBridgeState("Python bridge connected successfully");
      }
      else
      {
         m_state = PYTHON_BRIDGE_DISCONNECTED;
         LogBridgeState("Python bridge connection failed - will use local AI fallback", ERROR_LEVEL_WARNING);
      }
   }
   else
   {
      m_state = PYTHON_BRIDGE_DISCONNECTED;
      LogBridgeState("Python bridge disabled by configuration");
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Shutdown the Python Bridge                                       |
//+------------------------------------------------------------------+
void CPythonBridge::Shutdown()
{
   if(m_initialized)
   {
      LogBridgeState("Python bridge shutting down");
      m_initialized = false;
      m_state = PYTHON_BRIDGE_DISCONNECTED;
   }
}

//+------------------------------------------------------------------+
//| Escape JSON string                                               |
//+------------------------------------------------------------------+
string CPythonBridge::EscapeJsonString(const string &str)
{
   string result = str;
   StringReplace(result, "\\", "\\\\");
   StringReplace(result, "\"", "\\\"");
   StringReplace(result, "\n", "\\n");
   StringReplace(result, "\r", "\\r");
   StringReplace(result, "\t", "\\t");
   return result;
}

//+------------------------------------------------------------------+
//| Send HTTP request                                                |
//+------------------------------------------------------------------+
bool CPythonBridge::SendHttpRequest(const string &method, const string &url,
                                    const string &post_data, string &response)
{
   if(!m_initialized)
      return false;
   
   string headers = "Content-Type: application/json\r\n";
   uchar request_array[];
   uchar response_array[];
   string response_headers;
   
   // Convert post data to uchar array
   if(StringToCharArray(post_data, request_array) < 0)
      return false;
   
   // Trim null terminator
   ArrayResize(request_array, ArraySize(request_array) - 1);
   
   // Send request
   int res = WebRequest(method, url, headers, m_request_timeout,
                       request_array, response_array, response_headers);
   
   if(res == -1)
   {
      int err = GetLastError();
      LogBridgeState("HTTP request failed: " + IntegerToString(err), ERROR_LEVEL_ERROR);
      return false;
   }
   
   // Convert response to string
   response = CharArrayToString(response_array);
   return true;
}

//+------------------------------------------------------------------+
//| Parse prediction response JSON                                   |
//+------------------------------------------------------------------+
SPythonBridgeResponse CPythonBridge::ParsePredictionResponse(const string &json_str)
{
   SPythonBridgeResponse result;
   
   if(json_str == "")
   {
      result.success = false;
      result.error_message = "Empty response from server";
      return result;
   }
   
   // Check for error in response
   if(StringFind(json_str, "\"error\"") != -1)
   {
      result.success = false;
      int err_start = StringFind(json_str, "\"error\":");
      if(err_start != -1)
      {
         int val_start = StringFind(json_str, "\"", err_start + 8);
         int val_end = StringFind(json_str, "\"", val_start + 1);
         if(val_start != -1 && val_end != -1)
            result.error_message = StringSubstr(json_str, val_start + 1, val_end - val_start - 1);
      }
      if(result.error_message == "")
         result.error_message = "Unknown error in server response";
      return result;
   }
   
   result.success = true;
   
   // Extract basic fields
   int pos;
   
   // buy_prob
   pos = StringFind(json_str, "\"buy_prob\":");
   if(pos != -1)
   {
      string val_str = StringSubstr(json_str, pos + 11);
      int end_pos = StringFind(val_str, ",");
      if(end_pos == -1) end_pos = StringFind(val_str, "}");
      if(end_pos != -1) val_str = StringSubstr(val_str, 0, end_pos);
      result.buy_prob = StringToDouble(val_str);
   }
   
   // sell_prob
   pos = StringFind(json_str, "\"sell_prob\":");
   if(pos != -1)
   {
      string val_str = StringSubstr(json_str, pos + 12);
      int end_pos = StringFind(val_str, ",");
      if(end_pos == -1) end_pos = StringFind(val_str, "}");
      if(end_pos != -1) val_str = StringSubstr(val_str, 0, end_pos);
      result.sell_prob = StringToDouble(val_str);
   }
   
   // hold_prob
   pos = StringFind(json_str, "\"hold_prob\":");
   if(pos != -1)
   {
      string val_str = StringSubstr(json_str, pos + 12);
      int end_pos = StringFind(val_str, ",");
      if(end_pos == -1) end_pos = StringFind(val_str, "}");
      if(end_pos != -1) val_str = StringSubstr(val_str, 0, end_pos);
      result.hold_prob = StringToDouble(val_str);
   }
   
   // lgbm_buy
   pos = StringFind(json_str, "\"lgbm_buy\":");
   if(pos != -1)
   {
      string val_str = StringSubstr(json_str, pos + 11);
      int end_pos = StringFind(val_str, ",");
      if(end_pos == -1) end_pos = StringFind(val_str, "}");
      if(end_pos != -1) val_str = StringSubstr(val_str, 0, end_pos);
      result.lgbm_buy = StringToDouble(val_str);
   }
   
   // lgbm_sell
   pos = StringFind(json_str, "\"lgbm_sell\":");
   if(pos != -1)
   {
      string val_str = StringSubstr(json_str, pos + 12);
      int end_pos = StringFind(val_str, ",");
      if(end_pos == -1) end_pos = StringFind(val_str, "}");
      if(end_pos != -1) val_str = StringSubstr(val_str, 0, end_pos);
      result.lgbm_sell = StringToDouble(val_str);
   }
   
   // stacker_signal
   pos = StringFind(json_str, "\"stacker_signal\":");
   if(pos != -1)
   {
      string val_str = StringSubstr(json_str, pos + 17);
      int end_pos = StringFind(val_str, ",");
      if(end_pos == -1) end_pos = StringFind(val_str, "}");
      if(end_pos != -1) val_str = StringSubstr(val_str, 0, end_pos);
      result.stacker_signal = StringToDouble(val_str);
   }
   
   // ts
   pos = StringFind(json_str, "\"ts\":");
   if(pos != -1)
   {
      int val_start = StringFind(json_str, "\"", pos + 5);
      int val_end = StringFind(json_str, "\"", val_start + 1);
      if(val_start != -1 && val_end != -1)
         result.ts = StringSubstr(json_str, val_start + 1, val_end - val_start - 1);
   }
   
   // mode
   pos = StringFind(json_str, "\"mode\":");
   if(pos != -1)
   {
      int val_start = StringFind(json_str, "\"", pos + 7);
      int val_end = StringFind(json_str, "\"", val_start + 1);
      if(val_start != -1 && val_end != -1)
         result.mode = StringSubstr(json_str, val_start + 1, val_end - val_start - 1);
   }
   
   return result;
}

//+------------------------------------------------------------------+
//| Log bridge state                                                 |
//+------------------------------------------------------------------+
void CPythonBridge::LogBridgeState(string message, ENUM_ERROR_LEVEL level)
{
   string state_str;
   switch(m_state)
   {
      case PYTHON_BRIDGE_DISCONNECTED: state_str = "DISCONNECTED"; break;
      case PYTHON_BRIDGE_CONNECTING:   state_str = "CONNECTING";   break;
      case PYTHON_BRIDGE_CONNECTED:    state_str = "CONNECTED";    break;
      case PYTHON_BRIDGE_ERROR:        state_str = "ERROR";        break;
   }
   CEnhancedErrorHandler::LogError((ENUM_ERROR_SEVERITY)level, 
                                    "PythonBridge [" + state_str + "]", 
                                    message, 0);
}

//+------------------------------------------------------------------+
//| Check server health                                              |
//+------------------------------------------------------------------+
bool CPythonBridge::CheckHealth()
{
   if(m_mode == PYTHON_BRIDGE_OFF)
      return false;
   
   string response;
   string healthUrl = m_endpoint + "/health";
   bool success = SendHttpRequest("GET", healthUrl, "", response);
   
   if(success && StringFind(response, "\"status\":\"healthy\"") != -1)
   {
      m_last_heartbeat = TimeCurrent();
      if(m_state != PYTHON_BRIDGE_CONNECTED)
      {
         m_state = PYTHON_BRIDGE_CONNECTED;
         m_reconnect_attempts = 0;
         LogBridgeState("Python bridge connection restored");
      }
      return true;
   }
   else
   {
      // Handle disconnection
      if(m_state == PYTHON_BRIDGE_CONNECTED)
      {
         m_state = PYTHON_BRIDGE_DISCONNECTED;
         LogBridgeState("Python bridge disconnected - will attempt reconnection", ERROR_LEVEL_WARNING);
      }
      return AttemptReconnect();
   }
}

//+------------------------------------------------------------------+
//| Send heartbeat                                                   |
//+------------------------------------------------------------------+
bool CPythonBridge::SendHeartbeat()
{
   if(m_mode == PYTHON_BRIDGE_OFF)
      return false;
   
   string response;
   string heartbeatUrl = m_endpoint + "/heartbeat";
   bool success = SendHttpRequest("GET", heartbeatUrl, "", response);
   
   if(success && StringFind(response, "\"status\":\"ok\"") != -1)
   {
      m_last_heartbeat = TimeCurrent();
      if(m_state != PYTHON_BRIDGE_CONNECTED)
      {
         m_state = PYTHON_BRIDGE_CONNECTED;
         m_reconnect_attempts = 0;
         LogBridgeState("Python bridge connection restored via heartbeat");
      }
      return true;
   }
   else
   {
      if(m_state == PYTHON_BRIDGE_CONNECTED)
      {
         m_state = PYTHON_BRIDGE_DISCONNECTED;
         LogBridgeState("Python bridge heartbeat failed", ERROR_LEVEL_WARNING);
      }
      return AttemptReconnect();
   }
}

//+------------------------------------------------------------------+
//| Attempt reconnection                                             |
//+------------------------------------------------------------------+
bool CPythonBridge::AttemptReconnect()
{
   if(m_mode == PYTHON_BRIDGE_OFF)
      return false;
   
   datetime now = TimeCurrent();
   
   // Check backoff
   if((now - m_last_reconnect) < (m_reconnect_backoff / 1000))
      return false;
   
   // Check max attempts
   if(m_reconnect_attempts >= m_max_reconnect_attempts)
   {
      if(m_state != PYTHON_BRIDGE_ERROR)
      {
         m_state = PYTHON_BRIDGE_ERROR;
         LogBridgeState("Max reconnection attempts reached - using local AI fallback", ERROR_LEVEL_ERROR);
      }
      return false;
   }
   
   m_last_reconnect = now;
   m_reconnect_attempts++;
   m_state = PYTHON_BRIDGE_CONNECTING;
   
   string reconnectMsg = "Attempting reconnection (" + IntegerToString(m_reconnect_attempts) + 
                         "/" + IntegerToString(m_max_reconnect_attempts) + ")...";
   LogBridgeState(reconnectMsg);
   
   // Try health check
   string response;
   string healthUrl = m_endpoint + "/health";
   bool success = SendHttpRequest("GET", healthUrl, "", response);
   
   if(success && StringFind(response, "\"status\":\"healthy\"") != -1)
   {
      m_state = PYTHON_BRIDGE_CONNECTED;
      m_reconnect_attempts = 0;
      m_last_heartbeat = now;
      LogBridgeState("Reconnection successful!");
      return true;
   }
   else
   {
      // Exponential backoff
      m_reconnect_backoff = MathMin(m_reconnect_backoff * 2, 30000);
      m_state = PYTHON_BRIDGE_DISCONNECTED;
      return false;
   }
}

//+------------------------------------------------------------------+
//| Send prediction request                                          |
//+------------------------------------------------------------------+
SPythonBridgeResponse CPythonBridge::Predict(const double &features[], int features_size,
                                              const string mode)
{
   SPythonBridgeResponse result;
   
   // Check if bridge is available
   if(m_mode == PYTHON_BRIDGE_OFF || !m_initialized)
   {
      result.success = false;
      result.error_message = "Python bridge disabled";
      return result;
   }
   
   // Check health first
   if(!CheckHealth())
   {
      result.success = false;
      result.error_message = "Python bridge not available";
      return result;
   }
   
   // Build JSON request
   string json = "{\"features\":[";
   for(int i = 0; i < features_size; i++)
   {
      if(i > 0) json += ",";
      json += DoubleToString(features[i], 10);
   }
   json += "],\"mode\":\"" + EscapeJsonString(mode) + "\"}";
   
   // Send request
   string response;
   string requestUrl = m_endpoint + "/predict";
   if(SendHttpRequest("POST", requestUrl, json, response))
   {
      result = ParsePredictionResponse(response);
      if(result.success)
         m_last_heartbeat = TimeCurrent();
   }
   else
   {
      result.success = false;
      result.error_message = "Failed to send prediction request";
      m_state = PYTHON_BRIDGE_DISCONNECTED;
   }
   
   return result;
}

//+------------------------------------------------------------------+
//| DoubleAdapt prediction                                           |
//+------------------------------------------------------------------+
SPythonBridgeResponse CPythonBridge::PredictDoubleAdapt(const double &features[], int features_size)
{
   return Predict(features, features_size, "doubleadapt");
}

//+------------------------------------------------------------------+
//| MAML-PPO prediction                                              |
//+------------------------------------------------------------------+
SPythonBridgeResponse CPythonBridge::PredictMamlPpo(const double &features[], int features_size)
{
   return Predict(features, features_size, "maml_ppo");
}

//+------------------------------------------------------------------+
//| Validate JSON response                                           |
//+------------------------------------------------------------------+
bool CPythonBridge::ValidateJsonResponse(const string &json_str)
{
   if(json_str == "")
      return false;
   
   // Basic JSON validation - check for balanced braces
   int brace_count = 0;
   int bracket_count = 0;
   int quote_count = 0;
   bool in_string = false;
   
   for(int i = 0; i < StringLen(json_str); i++)
   {
      ushort c = StringGetCharacter(json_str, i);
      
      if(c == '"' && (i == 0 || StringGetCharacter(json_str, i-1) != '\\'))
         in_string = !in_string;
      
      if(in_string)
         continue;
      
      if(c == '{') brace_count++;
      if(c == '}') brace_count--;
      if(c == '[') bracket_count++;
      if(c == ']') bracket_count--;
      
      if(brace_count < 0 || bracket_count < 0)
         return false;
   }
   
   return (brace_count == 0 && bracket_count == 0 && !in_string);
}

//+------------------------------------------------------------------+
//| Parse version response                                           |
//+------------------------------------------------------------------+
bool CPythonBridge::ParseVersionResponse(const string &json_str, SPythonBridgeVersion &version)
{
   if(!ValidateJsonResponse(json_str))
      return false;
   
   int pos;
   
   // Extract version string
   pos = StringFind(json_str, "\"version\":");
   if(pos != -1)
   {
      int val_start = StringFind(json_str, "\"", pos + 11);
      int val_end = StringFind(json_str, "\"", val_start + 1);
      if(val_start != -1 && val_end != -1)
         version.version = StringSubstr(json_str, val_start + 1, val_end - val_start - 1);
   }
   
   // Parse version components
   if(version.version != "")
   {
      string parts[];
      int parts_count = StringSplit(version.version, '.', parts);
      if(parts_count >= 1) version.major = (int)StringToInteger(parts[0]);
      if(parts_count >= 2) version.minor = (int)StringToInteger(parts[1]);
      if(parts_count >= 3) version.patch = (int)StringToInteger(parts[2]);
   }
   
   // Check compatibility
   version.compatible = CheckVersionCompatibility(version);
   
   return true;
}

//+------------------------------------------------------------------+
//| Check version compatibility                                      |
//+------------------------------------------------------------------+
bool CPythonBridge::CheckVersionCompatibility(const SPythonBridgeVersion &version)
{
   const int REQUIRED_MAJOR = 1;
   const int REQUIRED_MINOR = 0;
   
   // Major version must match
   if(version.major != REQUIRED_MAJOR)
      return false;
   
   // Minor version must be >= required
   if(version.minor < REQUIRED_MINOR)
      return false;
   
   return true;
}

//+------------------------------------------------------------------+
//| Check server version                                             |
//+------------------------------------------------------------------+
bool CPythonBridge::CheckVersion()
{
   if(m_mode == PYTHON_BRIDGE_OFF || !m_initialized)
      return false;
   
   string response;
   string versionUrl = m_endpoint + "/version";
   if(SendHttpRequest("GET", versionUrl, "", response))
   {
      if(ParseVersionResponse(response, m_server_version))
      {
         if(m_server_version.compatible)
         {
            LogBridgeState("Python bridge version OK: " + m_server_version.version);
            return true;
         }
         else
         {
            LogBridgeState("Python bridge version incompatible! Required: " + 
                          IntegerToString(1) + "." + IntegerToString(0) + 
                          ", Got: " + m_server_version.version, ERROR_LEVEL_ERROR);
            m_state = PYTHON_BRIDGE_ERROR;
            return false;
         }
      }
   }
   
   LogBridgeState("Failed to check Python bridge version", ERROR_LEVEL_WARNING);
   return false;
}

//+------------------------------------------------------------------+
//| Get health status                                                 |
//+------------------------------------------------------------------+
SPythonBridgeHealthStatus CPythonBridge::GetHealthStatus()
{
   SPythonBridgeHealthStatus status;
   
   status.state = m_state;
   status.connected = IsConnected();
   status.healthy = (m_state == PYTHON_BRIDGE_CONNECTED && 
                     (TimeCurrent() - m_last_heartbeat) < m_heartbeat_timeout);
   status.last_heartbeat = m_last_heartbeat;
   status.reconnect_attempts = m_reconnect_attempts;
   status.request_count = m_request_count;
   status.success_count = m_success_count;
   status.error_count = m_error_count;
   status.last_error = m_last_error;
   status.version = m_server_version;
   
   return status;
}

