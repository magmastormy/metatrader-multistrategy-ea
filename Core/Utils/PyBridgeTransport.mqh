// Connection/session state + HTTP transport + state logging for
// the Python bridge. Owns the endpoint, mode, timeout, connection
// state, initialization flag, request counters and last error.
// Extracted verbatim from PythonBridge.mqh (behaviour unchanged).
#property copyright "Copyright 2025"
#property link      ""
#property version   "1.00"
#property strict

#ifndef CORE_PYBRIDGE_TRANSPORT_MQH
#define CORE_PYBRIDGE_TRANSPORT_MQH

#include "Enums.mqh"
#include "ErrorHandling.mqh"
#include "PyBridgeTypes.mqh"

// Python Bridge Transport / Session State
class CPyBridgeTransport
{
private:
   string                   m_endpoint;        // Server endpoint (http://host:port)
   ENUM_PYTHON_BRIDGE_MODE  m_mode;
   int                      m_request_timeout;
   ENUM_PYTHON_BRIDGE_STATE m_state;           // Current bridge state
   bool                     m_initialized;     // Initialized flag
   int                      m_request_count;   // Total requests count
   int                      m_success_count;   // Successful requests count
   int                      m_error_count;     // Failed requests count
   string                   m_last_error;      // Last error message

public:
                     CPyBridgeTransport();

   // Lifecycle
   void              Configure(const string &endpoint, ENUM_PYTHON_BRIDGE_MODE mode,
                               int request_timeout_ms);
   bool              CompleteInitialization();
   void              LogShutdown();
   void              Reset();

   // Transport + logging
   bool              SendHttpRequest(const string &method, const string &url,
                                     const string &post_data, string &response);
   void              LogBridgeState(string message, ENUM_ERROR_LEVEL level = ERROR_LEVEL_INFO);

   ENUM_PYTHON_BRIDGE_STATE GetState() const { return m_state; }
   ENUM_PYTHON_BRIDGE_MODE  GetMode() const { return m_mode; }
   bool              IsConnected() const { return m_state == PYTHON_BRIDGE_CONNECTED; }
   bool              IsInitialized() const { return m_initialized; }
   string            GetEndpoint() const { return m_endpoint; }
   int               GetRequestTimeout() const { return m_request_timeout; }
   int               GetRequestCount() const { return m_request_count; }
   int               GetSuccessCount() const { return m_success_count; }
   int               GetErrorCount() const { return m_error_count; }
   string            GetLastError() const { return m_last_error; }

   // Mutators
   void              SetState(ENUM_PYTHON_BRIDGE_STATE new_state) { m_state = new_state; }
   void              SetLastError(const string &error_message) { m_last_error = error_message; }
   void              IncrementErrorCount() { m_error_count++; }
};

// Constructor - defaults identical to the original CPythonBridge
CPyBridgeTransport::CPyBridgeTransport()
{
   m_endpoint = "http://127.0.0.1:8000";
   m_mode = PYTHON_BRIDGE_OBSERVE;
   m_request_timeout = 2000;
   m_state = PYTHON_BRIDGE_DISCONNECTED;
   m_initialized = false;
   m_request_count = 0;
   m_success_count = 0;
   m_error_count = 0;
   m_last_error = "";
}

// Apply the connection configuration supplied to Initialize()
void CPyBridgeTransport::Configure(const string &endpoint, ENUM_PYTHON_BRIDGE_MODE mode,
                                   int request_timeout_ms)
{
   m_endpoint = endpoint;
   m_mode = mode;
   m_request_timeout = request_timeout_ms;
}

// Finish initialization: flag, banner logging and initial state
bool CPyBridgeTransport::CompleteInitialization()
{
   m_initialized = true;
   
   LogBridgeState("Python bridge initialized with endpoint: " + m_endpoint);
   
   // Attempt initial health check — skip during init to avoid blocking WebRequest
   // Health check will happen on first timer tick instead
   if(m_mode != PYTHON_BRIDGE_OFF)
   {
      m_state = PYTHON_BRIDGE_DISCONNECTED;
      LogBridgeState("Python bridge initialized (health check deferred to timer)");
   }
   else
   {
      m_state = PYTHON_BRIDGE_DISCONNECTED;
      LogBridgeState("Python bridge disabled by configuration");
   }
   
   return true;
}

// Shutdown banner (uses the counters owned by this module)
void CPyBridgeTransport::LogShutdown()
{
   LogBridgeState("Python bridge shutting down | requests=" + IntegerToString(m_request_count) + 
                    " success=" + IntegerToString(m_success_count) + " errors=" + IntegerToString(m_error_count));
}

// Reset all transport-owned state (Shutdown semantics)
void CPyBridgeTransport::Reset()
{
   m_initialized = false;
   m_state = PYTHON_BRIDGE_DISCONNECTED;
   m_endpoint = "";
   m_mode = PYTHON_BRIDGE_OFF;
   m_request_timeout = 0;
   m_request_count = 0;
   m_success_count = 0;
   m_error_count = 0;
   m_last_error = "";
}

bool CPyBridgeTransport::SendHttpRequest(const string &method, const string &url,
                                         const string &post_data, string &response)
{
   if(!m_initialized)
      return false;
   
   string headers = "Content-Type: application/json\r\n";
   uchar request_array[];
   uchar response_array[];
   string response_headers;
   
   // Convert post data to uchar array (only for POST/PUT with data)
   if(post_data != "")
   {
      if(StringToCharArray(post_data, request_array) < 0)
         return false;
      
      // Trim null terminator
      ArrayResize(request_array, ArraySize(request_array) - 1);
   }
   
   // Send request
   int res = WebRequest(method, url, headers, m_request_timeout,
                       request_array, response_array, response_headers);
   
   if(res == -1)
   {
      int err = ::GetLastError();
      LogBridgeState("HTTP request failed: " + IntegerToString(err), ERROR_LEVEL_ERROR);
      return false;
   }
   
   if(res >= 400)
   {
      m_state = PYTHON_BRIDGE_DISCONNECTED;
      LogBridgeState("HTTP " + IntegerToString(res) + " from " + url, ERROR_LEVEL_ERROR);
      return false;
   }
   
   // Convert response to string
   response = CharArrayToString(response_array);
   return true;
}

void CPyBridgeTransport::LogBridgeState(string message, ENUM_ERROR_LEVEL level)
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

#endif // CORE_PYBRIDGE_TRANSPORT_MQH
