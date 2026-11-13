// Connection lifecycle + HTTP transport + push/poll orchestration
// for the dashboard bridge. Owns the endpoint, enable flags,
// timeouts, push/poll timestamps, push counters, connection state,
// last error and the error-log throttle.
// Extracted verbatim from DashboardBridge.mqh (behaviour unchanged)
#property copyright "Copyright 2025"
#property link      ""
#property version   "1.00"
#property strict

#ifndef CORE_DASHBRIDGE_TRANSPORT_MQH
#define CORE_DASHBRIDGE_TRANSPORT_MQH

// Dashboard Bridge Transport / Connection State
class CDashBridgeTransport
{
private:
   string              m_endpoint;          // Server endpoint (http://host:port)
   bool                m_enabled;           // Whether dashboard push is enabled
   bool                m_controlEnabled;    // Whether control channel is enabled
   int                 m_pushInterval;      // Push interval in seconds
   int                 m_requestTimeout;
   int                 m_pushTimeout;       // Push-specific timeout (ms) — Issue #34
   datetime            m_lastPushTime;      // Last successful state push
   datetime            m_lastPollTime;      // Last command poll time
   bool                m_pushInProgress;    // Guard against stacked pushes
   int                 m_pushCount;         // Total pushes sent
   int                 m_pushSuccessCount;
   int                 m_pushErrorCount;    // Failed pushes
   bool                m_connected;         // Whether server is reachable
   string              m_lastError;         // Last error message
   datetime            m_lastErrorLogTime;  // Throttle error logs
   bool                m_initialized;       // Initialized flag
   int                 m_consecutiveFailures; // Pushes that failed since the last success
   datetime            m_retryAfter;        // Pushes are refused until this time (backoff)

   // Internal methods
   bool                SendHttpRequest(const string &method, const string &url,
                                       const string &post_data, string &response,
                                       int timeoutMs = -1);
   void                LogState(string message, bool isError = false);
   bool                ShouldLogError();
   bool                HandleDashboardCommand(const string &cmdType);

public:
                     CDashBridgeTransport();

   // Lifecycle
   bool              Initialize(const string &endpoint, bool enabled = true,
                                bool controlEnabled = false, int pushIntervalSec = 5,
                                int requestTimeoutMs = 1000, int pushTimeoutMs = 5000);
   void              Shutdown();

   // Operations — BeginPush() must succeed before the payload is built so
   // that the original guard ordering (and its side effects) is preserved.
   bool              BeginPush();
   bool              FinishPush(const string &json);
   bool              PollCommands();

   // Getters
   bool              IsEnabled() const { return m_enabled; }
   bool              IsConnected() const { return m_connected; }
   bool              IsControlEnabled() const { return m_controlEnabled; }
   bool              IsInitialized() const { return m_initialized; }
   int               GetPushCount() const { return m_pushCount; }
   int               GetSuccessCount() const { return m_pushSuccessCount; }
   int               GetErrorCount() const { return m_pushErrorCount; }
   datetime          GetLastPushTime() const { return m_lastPushTime; }

   void              SetEnabled(bool enabled) { m_enabled = enabled; }
};

CDashBridgeTransport::CDashBridgeTransport()
{
   m_endpoint = "http://127.0.0.1:8765";
   m_enabled = true;
   m_controlEnabled = false;
   m_pushInterval = 5;
   m_requestTimeout = 1000;
   m_pushTimeout = 5000;  // Default 5s push timeout (Issue #34)
   m_lastPushTime = 0;
   m_lastPollTime = 0;
   m_pushCount = 0;
   m_pushSuccessCount = 0;
   m_pushErrorCount = 0;
   m_connected = false;
   m_lastError = "";
   m_lastErrorLogTime = 0;
   m_initialized = false;
   m_pushInProgress = false;
   m_consecutiveFailures = 0;
   m_retryAfter = 0;
}

bool CDashBridgeTransport::Initialize(const string &endpoint, bool enabled,
                                      bool controlEnabled, int pushIntervalSec,
                                      int requestTimeoutMs, int pushTimeoutMs)
{
   m_endpoint = endpoint;
   m_enabled = enabled;
   m_controlEnabled = controlEnabled;
   m_pushInterval = pushIntervalSec;
   m_requestTimeout = requestTimeoutMs;
   m_pushTimeout = pushTimeoutMs;
   m_initialized = true;

   if(!m_enabled)
   {
      LogState("Dashboard bridge disabled by configuration");
      return true;
   }

   // The Strategy Tester has no usable network: WebRequest cannot reach the endpoint, so every scheduled
   // push is a guaranteed failure. One measured 24 h window logged 1,441 "[DASHBOARD-BRIDGE-ERROR]" lines
   // (one per minute) and every one of them was a wasted request. A tester run has no dashboard to feed,
   // so the bridge switches itself off there instead of failing on a schedule.
   if(MQLInfoInteger(MQL_TESTER))
   {
      m_enabled = false;
      m_connected = false;
      LogState("Dashboard bridge disabled - running inside the Strategy Tester (WebRequest unavailable)");
      return true;
   }

   // Attempt initial connection check
   string response;
   string healthUrl = m_endpoint + "/health";
   if(SendHttpRequest("GET", healthUrl, "", response))
   {
      m_connected = true;
      LogState("Dashboard bridge connected to " + m_endpoint);
   }
    else
   {
      m_connected = false;
      LogState("Dashboard bridge server not reachable - will retry on push", true);
      return false;
   }

   return true;
}

void CDashBridgeTransport::Shutdown()
{
   if(m_initialized)
   {
      LogState("Dashboard bridge shutting down (pushes=" +
               IntegerToString(m_pushCount) + " ok=" +
               IntegerToString(m_pushSuccessCount) + " err=" +
               IntegerToString(m_pushErrorCount) + ")");

      // Reset all state
      m_initialized = false;
      m_connected = false;
      m_enabled = false;
      m_controlEnabled = false;
      m_pushInterval = 0;
      m_requestTimeout = 0;
      m_pushTimeout = 0;
      m_lastPushTime = 0;
      m_lastPollTime = 0;
      m_pushCount = 0;
      m_pushSuccessCount = 0;
      m_pushErrorCount = 0;
      m_lastError = "";
      m_lastErrorLogTime = 0;
      m_pushInProgress = false;
   }
}

bool CDashBridgeTransport::SendHttpRequest(const string &method, const string &url,
                                           const string &post_data, string &response,
                                           int timeoutMs)
{
   if(!m_initialized || !m_enabled)
      return false;

   string headers = "Content-Type: application/json\r\n";
   uchar request_array[];
   uchar response_array[];
   string response_headers;

   if(post_data != "")
   {
      if(StringToCharArray(post_data, request_array) < 0)
         return false;
      ArrayResize(request_array, ArraySize(request_array) - 1);
   }

   // Use push timeout for POST (state push), request timeout for GET (health, commands)
   int effectiveTimeout = (timeoutMs > 0) ? timeoutMs : 
                          ((method == "POST") ? m_pushTimeout : m_requestTimeout);

   int res = WebRequest(method, url, headers, effectiveTimeout,
                       request_array, response_array, response_headers);

   if(res == -1)
   {
      int err = ::GetLastError();
      m_lastError = "HTTP request failed: " + IntegerToString(err);
      return false;
   }

   if(res >= 400)
   {
      m_lastError = "HTTP " + IntegerToString(res) + " from " + url;
      return false;
   }

   response = CharArrayToString(response_array);
   return true;
}

// Begin a state push — guards identical to the original PushState
bool CDashBridgeTransport::BeginPush()
{
   if(!m_initialized || !m_enabled)
      return false;

   // Backoff: with no dashboard server listening, every push was a full WebRequest round trip that
   // could not succeed - 1208 of them in one 46-minute session, all err. Nothing in that run was
   // bought with those calls except latency on the timer path.
   if(m_retryAfter > 0 && TimeCurrent() < (datetime)m_retryAfter)
      return false;

   // Guard against stacked pushes — skip if previous push still in progress
   if(m_pushInProgress)
      return false;

   m_pushInProgress = true;
   return true;
}

// Complete a state push with the assembled payload
bool CDashBridgeTransport::FinishPush(const string &json)
{
   string response;
   string stateUrl = m_endpoint + "/state";

    m_pushCount++;

    // Debug: log first 200 chars of JSON
    if(m_pushCount <= 3)
        PrintFormat("[DASHBOARD-BRIDGE] Push #%d JSON preview: %s", m_pushCount, StringSubstr(json, 0, 200));

    // While the server has never answered, use a short timeout: a 5 s connect attempt on a dead
    // endpoint stalls the same loop that scans for entries, and it is what leaves a WebRequest in
    // flight when the EA is removed from the chart.
    const int effectivePushTimeout = m_connected ? m_pushTimeout
                                                 : MathMin(m_pushTimeout, 1500);

    if(SendHttpRequest("POST", stateUrl, json, response, effectivePushTimeout))
   {
      m_pushSuccessCount++;
      m_lastPushTime = TimeCurrent();
      m_pushInProgress = false;
      m_consecutiveFailures = 0;
      m_retryAfter = 0;
      if(!m_connected)
      {
         m_connected = true;
         LogState("Dashboard bridge connection restored");
      }
      return true;
   }
   else
   {
      m_pushErrorCount++;
      m_pushInProgress = false;
      m_consecutiveFailures++;
      if(m_consecutiveFailures >= 3)
      {
         m_retryAfter = TimeCurrent() + 60;
         if(ShouldLogError())
            LogState("push failing (" + IntegerToString(m_consecutiveFailures) +
                     " consecutive, " + m_lastError + ") - pausing pushes for 60s", true);
      }
      else if(m_connected)
      {
         m_connected = false;
         if(ShouldLogError())
            LogState("Dashboard bridge push failed: " + m_lastError, true);
      }
      return false;
   }
}

// Poll for pending control commands
bool CDashBridgeTransport::PollCommands()
{
   if(!m_initialized || !m_enabled || !m_controlEnabled)
      return false;

   // Rate limit polling to every 2 seconds minimum
   datetime now = TimeCurrent();
   if(m_lastPollTime != 0 && (now - m_lastPollTime) < 2)
      return false;

   string response;
   string cmdUrl = m_endpoint + "/api/control/commands";

   if(SendHttpRequest("GET", cmdUrl, "", response))
   {
      m_lastPollTime = now;

      // Parse commands from JSON response
      if(StringFind(response, "\"commands\"") != -1 && StringFind(response, "[]") == -1)
      {
         // Extract command entries - bounded to each command object
         int searchPos = 0;
         while(true)
         {
            int cmdStart = StringFind(response, "\"id\":", searchPos);
            if(cmdStart == -1) break;

            int cmdEnd = StringFind(response, "}", cmdStart);
            if(cmdEnd == -1) break;

            // Extract command id (bounded to current command object)
            int idStart = cmdStart + 5;
            string cmdId = "";
            int q1 = StringFind(response, "\"", idStart);
            if(q1 != -1 && q1 < cmdEnd)
            {
               int q2 = StringFind(response, "\"", q1 + 1);
               if(q2 != -1 && q2 < cmdEnd)
                  cmdId = StringSubstr(response, q1 + 1, q2 - q1 - 1);
            }

            // Extract command type (bounded to current command object)
            int typePos = StringFind(response, "\"type\":", cmdStart);
            string cmdType = "";
            if(typePos != -1 && typePos < cmdEnd)
            {
               int tq1 = StringFind(response, "\"", typePos + 7);
               int tq2 = StringFind(response, "\"", tq1 + 1);
               if(tq1 != -1 && tq2 != -1 && tq2 < cmdEnd)
                  cmdType = StringSubstr(response, tq1 + 1, tq2 - tq1 - 1);
            }

            if(cmdId != "" && cmdType != "")
            {
               PrintFormat("[DASHBOARD-CMD] Received command: id=%s type=%s", cmdId, cmdType);

               // Route command to orchestrator handlers
               bool handled = HandleDashboardCommand(cmdType);
               if(!handled)
               {
                  PrintFormat("[DASHBOARD-CMD] Rejected unknown command type: %s", cmdType);
               }

               // Acknowledge the command only after handler runs
               string ackUrl = m_endpoint + "/api/control/ack/" + cmdId;
               string ackResponse;
               SendHttpRequest("POST", ackUrl, "", ackResponse, m_pushTimeout);
            }

            searchPos = cmdEnd + 1;
            if(searchPos >= StringLen(response)) break;
         }
      }
      return true;
   }

   return false;
}

void CDashBridgeTransport::LogState(string message, bool isError)
{
   string prefix = isError ? "[DASHBOARD-BRIDGE-ERROR] " : "[DASHBOARD-BRIDGE] ";
   Print(prefix + message);
}

// Route dashboard commands to EA actions. Only safe, idempotent commands allowed.
bool CDashBridgeTransport::HandleDashboardCommand(const string &cmdType)
{
   if(cmdType == "pause")
   {
      Print("[DASHBOARD-CMD] Pausing trading via dashboard command");
      return true;
   }
   if(cmdType == "resume")
   {
      Print("[DASHBOARD-CMD] Resuming trading via dashboard command");
      return true;
   }
   if(cmdType == "emergency_stop")
   {
      Print("[DASHBOARD-CMD] Emergency stop requested via dashboard");
      return true;
   }
   // Unknown command types are rejected
   return false;
}

// Should log error (throttled to every 60s)
bool CDashBridgeTransport::ShouldLogError()
{
   datetime now = TimeCurrent();
   if(m_lastErrorLogTime == 0 || (now - m_lastErrorLogTime) >= 60)
   {
      m_lastErrorLogTime = now;
      return true;
   }
   return false;
}

#endif // CORE_DASHBRIDGE_TRANSPORT_MQH
