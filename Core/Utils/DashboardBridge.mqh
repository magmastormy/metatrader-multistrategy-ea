//+------------------------------------------------------------------+
//| DashboardBridge.mqh                                              |
//| Purpose: Push EA state to external dashboard server               |
//| Features: State push, command poll, graceful degradation          |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025"
#property link      ""
#property version   "1.00"
#property strict

#include "Enums.mqh"
#include "ErrorHandling.mqh"

//+------------------------------------------------------------------+
//| Dashboard Bridge Class                                           |
//+------------------------------------------------------------------+
class CDashboardBridge
{
private:
   string              m_endpoint;          // Server endpoint (http://host:port)
   bool                m_enabled;           // Whether dashboard push is enabled
   bool                m_controlEnabled;    // Whether control channel is enabled
   int                 m_pushInterval;      // Push interval in seconds
   int                 m_requestTimeout;    // Request timeout (ms)
   datetime            m_lastPushTime;      // Last successful state push
   datetime            m_lastPollTime;      // Last command poll time
   int                 m_pushCount;         // Total pushes sent
   int                 m_pushSuccessCount;  // Successful pushes
   int                 m_pushErrorCount;    // Failed pushes
   bool                m_connected;         // Whether server is reachable
   string              m_lastError;         // Last error message
   datetime            m_lastErrorLogTime;  // Throttle error logs
   bool                m_initialized;       // Initialized flag

   // Internal methods
   string              EscapeJsonString(const string &str);
   bool                SendHttpRequest(const string &method, const string &url,
                                       const string &post_data, string &response);
   string              BuildStateJson();
   void                LogState(string message, bool isError = false);
   bool                ShouldLogError();

public:
   // Constructor/Destructor
                       CDashboardBridge();
                      ~CDashboardBridge();

   // Initialization
   bool              Initialize(const string &endpoint, bool enabled = true,
                                bool controlEnabled = false, int pushIntervalSec = 5,
                                int requestTimeoutMs = 3000);
   void              Shutdown();

   // Operations
   bool              PushState();
   bool              PollCommands();

   // Getters
   bool              IsEnabled() const { return m_enabled; }
   bool              IsConnected() const { return m_connected; }
   bool              IsControlEnabled() const { return m_controlEnabled; }
   int               GetPushCount() const { return m_pushCount; }
   int               GetSuccessCount() const { return m_pushSuccessCount; }
   int               GetErrorCount() const { return m_pushErrorCount; }
   datetime          GetLastPushTime() const { return m_lastPushTime; }
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CDashboardBridge::CDashboardBridge()
{
   m_endpoint = "http://127.0.0.1:8765";
   m_enabled = true;
   m_controlEnabled = false;
   m_pushInterval = 5;
   m_requestTimeout = 3000;
   m_lastPushTime = 0;
   m_lastPollTime = 0;
   m_pushCount = 0;
   m_pushSuccessCount = 0;
   m_pushErrorCount = 0;
   m_connected = false;
   m_lastError = "";
   m_lastErrorLogTime = 0;
   m_initialized = false;
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CDashboardBridge::~CDashboardBridge()
{
   Shutdown();
}

//+------------------------------------------------------------------+
//| Initialize the Dashboard Bridge                                  |
//+------------------------------------------------------------------+
bool CDashboardBridge::Initialize(const string &endpoint, bool enabled,
                                   bool controlEnabled, int pushIntervalSec,
                                   int requestTimeoutMs)
{
   m_endpoint = endpoint;
   m_enabled = enabled;
   m_controlEnabled = controlEnabled;
   m_pushInterval = pushIntervalSec;
   m_requestTimeout = requestTimeoutMs;
   m_initialized = true;

   if(!m_enabled)
   {
      LogState("Dashboard bridge disabled by configuration");
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
   }

   return true;
}

//+------------------------------------------------------------------+
//| Shutdown the Dashboard Bridge                                    |
//+------------------------------------------------------------------+
void CDashboardBridge::Shutdown()
{
   if(m_initialized)
   {
      LogState("Dashboard bridge shutting down (pushes=" +
               IntegerToString(m_pushCount) + " ok=" +
               IntegerToString(m_pushSuccessCount) + " err=" +
               IntegerToString(m_pushErrorCount) + ")");
      m_initialized = false;
      m_connected = false;
   }
}

//+------------------------------------------------------------------+
//| Escape JSON string                                               |
//+------------------------------------------------------------------+
string CDashboardBridge::EscapeJsonString(const string &str)
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
bool CDashboardBridge::SendHttpRequest(const string &method, const string &url,
                                        const string &post_data, string &response)
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

   int res = WebRequest(method, url, headers, m_requestTimeout,
                       request_array, response_array, response_headers);

   if(res == -1)
   {
      int err = ::GetLastError();
      m_lastError = "HTTP request failed: " + IntegerToString(err);
      return false;
   }

   response = CharArrayToString(response_array);
   return true;
}

//+------------------------------------------------------------------+
//| Build state JSON payload                                         |
//+------------------------------------------------------------------+
string CDashboardBridge::BuildStateJson()
{
   string json = "{";

   // Timestamp
   json += "\"timestamp\":\"" + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + "\",";

   // Account info
   json += "\"account\":{";
   json += "\"balance\":" + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + ",";
   json += "\"equity\":" + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2) + ",";
   json += "\"free_margin\":" + DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_FREE), 2) + ",";
   json += "\"margin_level\":" + DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_LEVEL), 2);
   json += "},";

   // Positions
   json += "\"positions\":[";
   int posTotal = PositionsTotal();
   int posAdded = 0;
   for(int i = 0; i < posTotal; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;

      if(posAdded > 0) json += ",";
      json += "{";
      json += "\"ticket\":" + IntegerToString((long)ticket) + ",";
      json += "\"symbol\":\"" + EscapeJsonString(PositionGetString(POSITION_SYMBOL)) + "\",";
      json += "\"type\":\"" + (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? "BUY" : "SELL") + "\",";
      json += "\"lots\":" + DoubleToString(PositionGetDouble(POSITION_VOLUME), 2) + ",";
      json += "\"open_price\":" + DoubleToString(PositionGetDouble(POSITION_PRICE_OPEN), 5) + ",";
      json += "\"current_price\":" + DoubleToString(PositionGetDouble(POSITION_PRICE_CURRENT), 5) + ",";
      json += "\"sl\":" + DoubleToString(PositionGetDouble(POSITION_SL), 5) + ",";
      json += "\"tp\":" + DoubleToString(PositionGetDouble(POSITION_TP), 5) + ",";
      json += "\"profit\":" + DoubleToString(PositionGetDouble(POSITION_PROFIT), 2) + ",";
      json += "\"swap\":" + DoubleToString(PositionGetDouble(POSITION_SWAP), 2) + ",";
      json += "\"open_time\":\"" + TimeToString((datetime)PositionGetInteger(POSITION_TIME), TIME_DATE|TIME_SECONDS) + "\",";
      json += "\"duration_minutes\":" + IntegerToString((int)((TimeCurrent() - PositionGetInteger(POSITION_TIME)) / 60)) + ",";
      json += "\"strategy\":\"" + EscapeJsonString(PositionGetString(POSITION_COMMENT)) + "\"";
      json += "}";
      posAdded++;
   }
   json += "],";

   // Risk (placeholder - will be wired to actual risk manager)
   json += "\"risk\":{";
   json += "\"active_risk_per_trade_pct\":0,";
   json += "\"daily_risk_used_pct\":0,";
   json += "\"daily_entry_risk_pct\":0,";
   json += "\"daily_mtm_loss_pct\":0,";
   json += "\"open_exposure_pct\":0,";
   json += "\"max_daily_risk_pct\":0,";
   json += "\"portfolio_risk_pct\":0,";
   json += "\"current_drawdown_pct\":0,";
   json += "\"conservative_mode\":false,";
   json += "\"emergency_mode\":false,";
   json += "\"gate_approved\":0,";
   json += "\"gate_rejected\":0";
   json += "},";

   // Performance (placeholder)
   json += "\"performance\":{";
   json += "\"total_trades\":0,";
   json += "\"win_rate\":0,";
   json += "\"profit_factor\":0,";
   json += "\"sharpe_ratio\":0,";
   json += "\"max_drawdown\":0,";
   json += "\"recovery_factor\":0,";
   json += "\"net_profit\":0,";
   json += "\"avg_win\":0,";
   json += "\"avg_loss\":0";
   json += "},";

   // Consensus (placeholder)
   json += "\"consensus\":{\"symbols\":{}},";

   // AI (placeholder)
   json += "\"ai\":{";
   json += "\"onnx\":{\"active\":false},";
   json += "\"ensemble\":{\"active\":false},";
   json += "\"transformer\":{\"active\":false},";
   json += "\"nn\":{\"active\":false}";
   json += "},";

   // Strategies (placeholder)
   json += "\"strategies\":[],";

   // Scalp (placeholder)
   json += "\"scalp\":{";
   json += "\"active\":false,";
   json += "\"open_positions\":0,";
   json += "\"max_positions\":0,";
   json += "\"total_entries\":0,";
   json += "\"total_rejections\":0";
   json += "},";

   // Heartbeat (placeholder)
   json += "\"heartbeat\":{";
   json += "\"scans\":0,";
   json += "\"signals_generated\":0,";
   json += "\"signals_validated\":0,";
   json += "\"trades_opened\":0,";
   json += "\"shadow_trades\":0,";
   json += "\"spike_events\":0";
   json += "},";

   // Execution mode
   json += "\"execution_mode\":\"LIVE_SEND\",";

   // Python bridge (placeholder)
   json += "\"python_bridge\":{";
   json += "\"connected\":false,";
   json += "\"version\":\"\",";
   json += "\"requests\":0,";
   json += "\"ok\":0,";
   json += "\"errors\":0";
   json += "}";

   json += "}";

   return json;
}

//+------------------------------------------------------------------+
//| Push current EA state to dashboard server                        |
//+------------------------------------------------------------------+
bool CDashboardBridge::PushState()
{
   if(!m_initialized || !m_enabled)
      return false;

   string json = BuildStateJson();
   string response;
   string stateUrl = m_endpoint + "/state";

   m_pushCount++;

   if(SendHttpRequest("POST", stateUrl, json, response))
   {
      m_pushSuccessCount++;
      m_lastPushTime = TimeCurrent();
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
      if(m_connected)
      {
         m_connected = false;
         if(ShouldLogError())
            LogState("Dashboard bridge push failed: " + m_lastError, true);
      }
      return false;
   }
}

//+------------------------------------------------------------------+
//| Poll for pending control commands                                |
//+------------------------------------------------------------------+
bool CDashboardBridge::PollCommands()
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
         // Extract command entries - basic parsing
         int searchPos = 0;
         while(true)
         {
            int cmdStart = StringFind(response, "\"id\":", searchPos);
            if(cmdStart == -1) break;

            // Extract command id
            int idStart = cmdStart + 5;
            int idEnd = StringFind(response, "\"", StringFind(response, "\"", idStart) + 1);
            string cmdId = "";
            int q1 = StringFind(response, "\"", idStart);
            if(q1 != -1)
            {
               int q2 = StringFind(response, "\"", q1 + 1);
               if(q2 != -1)
                  cmdId = StringSubstr(response, q1 + 1, q2 - q1 - 1);
            }

            // Extract command type
            int typePos = StringFind(response, "\"type\":", cmdStart);
            string cmdType = "";
            if(typePos != -1)
            {
               int tq1 = StringFind(response, "\"", typePos + 7);
               int tq2 = StringFind(response, "\"", tq1 + 1);
               if(tq1 != -1 && tq2 != -1)
                  cmdType = StringSubstr(response, tq1 + 1, tq2 - tq1 - 1);
            }

            if(cmdId != "" && cmdType != "")
            {
               PrintFormat("[DASHBOARD-CMD] Received command: id=%s type=%s", cmdId, cmdType);

               // Acknowledge the command
               string ackUrl = m_endpoint + "/api/control/ack/" + cmdId;
               string ackResponse;
               SendHttpRequest("POST", ackUrl, "", ackResponse);
            }

            searchPos = cmdStart + 10;
            if(searchPos >= StringLen(response)) break;
         }
      }
      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Log dashboard bridge state                                       |
//+------------------------------------------------------------------+
void CDashboardBridge::LogState(string message, bool isError)
{
   string prefix = "[DASHBOARD-BRIDGE] ";
   if(isError)
      Print(prefix + message);
   else
      Print(prefix + message);
}

//+------------------------------------------------------------------+
//| Should log error (throttled to every 60s)                        |
//+------------------------------------------------------------------+
bool CDashboardBridge::ShouldLogError()
{
   datetime now = TimeCurrent();
   if(m_lastErrorLogTime == 0 || (now - m_lastErrorLogTime) >= 60)
   {
      m_lastErrorLogTime = now;
      return true;
   }
   return false;
}
