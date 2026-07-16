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

class CEnterpriseStrategyManager;

extern CEnterpriseStrategyManager* g_enterpriseManagers[];
extern string g_enterpriseManagerSymbols[];

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
   int                 m_pushTimeout;       // Push-specific timeout (ms) — Issue #34
   datetime            m_lastPushTime;      // Last successful state push
   datetime            m_lastPollTime;      // Last command poll time
   bool                m_pushInProgress;    // Guard against stacked pushes
   int                 m_pushCount;         // Total pushes sent
   int                 m_pushSuccessCount;  // Successful pushes
   int                 m_pushErrorCount;    // Failed pushes
   bool                m_connected;         // Whether server is reachable
   string              m_lastError;         // Last error message
   datetime            m_lastErrorLogTime;  // Throttle error logs
   bool                m_initialized;       // Initialized flag

    // Injected risk data
    double m_riskActiveRiskPerTrade;
    double m_riskDailyRiskUsed;
    double m_riskDailyEntryRisk;
    double m_riskDailyMtmLoss;
    double m_riskOpenExposure;
    double m_riskMaxDailyRisk;
    double m_riskPortfolioRisk;
    double m_riskCurrentDrawdown;
    bool   m_riskConservativeMode;
    bool   m_riskEmergencyMode;
    int    m_riskGateApproved;
    int    m_riskGateRejected;

    // Injected performance data
    int    m_perfTotalTrades;
    double m_perfWinRate;
    double m_perfProfitFactor;
    double m_perfSharpeRatio;
    double m_perfMaxDrawdown;
    double m_perfRecoveryFactor;
    double m_perfNetProfit;
    double m_perfAvgWin;
    double m_perfAvgLoss;

    // Injected python bridge data
    bool   m_pyConnected;
    string m_pyVersion;
    int    m_pyRequests;
    int    m_pyOk;
    int    m_pyErrors;
   
    // Heartbeat counter values
    int                 m_pScansCount;
    int                 m_pSignalsGenerated;
    int                 m_pSignalsValidated;
    int                 m_pTradesOpened;
    int                 m_pShadowTrades;
    int                 m_pSpikeEvents;
    bool                m_heartbeatCountersSet;

   // Internal methods
   string              EscapeJsonString(const string &str);
   bool                SendHttpRequest(const string &method, const string &url,
                                       const string &post_data, string &response,
                                       int timeoutMs = -1);
   string              BuildStateJson();
   string              BuildRiskJson();
   string              BuildPerformanceJson();
   string              BuildAIJson();
   string              BuildStrategiesJson();
   string              BuildConsensusJson();
   string              BuildHeartbeatJson();
   string              BuildPythonBridgeJson();
   void                LogState(string message, bool isError = false);
   bool                ShouldLogError();

public:
   // Constructor/Destructor
                       CDashboardBridge();
                      ~CDashboardBridge();

   // Initialization
   bool              Initialize(const string &endpoint, bool enabled = true,
                                bool controlEnabled = false, int pushIntervalSec = 5,
                                int requestTimeoutMs = 1000, int pushTimeoutMs = 5000);
   void              Shutdown();

    // Operations
    bool              PushState();
    bool              PollCommands();

    // Heartbeat counters
    void              SetHeartbeatCounters(int scans, int signalsGen, int signalsVal,
                                           int tradesOpened, int shadowTrades, int spikeEvents);

    // Getters
    bool              IsEnabled() const { return m_enabled; }
    bool              IsConnected() const { return m_connected; }
    bool              IsControlEnabled() const { return m_controlEnabled; }
    int               GetPushCount() const { return m_pushCount; }
    int               GetSuccessCount() const { return m_pushSuccessCount; }
    int               GetErrorCount() const { return m_pushErrorCount; }
    datetime          GetLastPushTime() const { return m_lastPushTime; }

   // Setters
   void              SetEnabled(bool enabled) { m_enabled = enabled; }

    // AI data injection — called from main loop before PushState
    void              SetAIData(bool nnActive, const string &nnSignal, double nnConf,
                                int nnLabels, int nnSteps, double nnConformalQ, double nnConformalAlpha,
                                int nnAssetClass, double nnBarrierK, int nnBarrierVertBars,
                                int nnTradeLinked, bool nnNormReady,
                                const string &regime, double regimeTrend, double regimeRange,
                                double regimeVolatile, double regimeSpike,
                                int metaFeatures, int metaCooldown, int metaEarlyStop,
                                double metaWinRate, double metaAvgConf, int metaSamplesSince);

    // Risk data injection — called from main loop before PushState
    void              SetRiskData(double activeRiskPerTrade, double dailyRiskUsed,
                                  double dailyEntryRisk, double dailyMtmLoss,
                                  double openExposure, double maxDailyRisk,
                                  double portfolioRisk, double currentDrawdown,
                                  bool conservativeMode, bool emergencyMode,
                                  int gateApproved, int gateRejected);

    // Performance data injection — called from main loop before PushState
    void              SetPerformanceData(int totalTrades, double winRate, double profitFactor,
                                         double sharpeRatio, double maxDrawdown, double recoveryFactor,
                                         double netProfit, double avgWin, double avgLoss);

    // Python bridge data injection — called from main loop before PushState
    void              SetPythonBridgeData(bool connected, const string &version,
                                          int requests, int ok, int errors);

private:
   // Stored AI data
   bool   m_aiNnActive;
   string m_aiNnSignal;
   double m_aiNnConf;
   int    m_aiNnLabels;
   int    m_aiNnSteps;
   double m_aiNnConformalQ;
   double m_aiNnConformalAlpha;
   int    m_aiNnAssetClass;
   double m_aiNnBarrierK;
   int    m_aiNnBarrierVertBars;
   int    m_aiNnTradeLinked;
   bool   m_aiNnNormReady;
   string m_aiRegime;
   double m_aiRegimeTrend;
   double m_aiRegimeRange;
   double m_aiRegimeVolatile;
   double m_aiRegimeSpike;
   int    m_aiMetaFeatures;
   int    m_aiMetaCooldown;
   int    m_aiMetaEarlyStop;
   double m_aiMetaWinRate;
   double m_aiMetaAvgConf;
   int    m_aiMetaSamplesSince;
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

   // Risk data defaults
   m_riskActiveRiskPerTrade = 0.0;
   m_riskDailyRiskUsed = 0.0;
   m_riskDailyEntryRisk = 0.0;
   m_riskDailyMtmLoss = 0.0;
   m_riskOpenExposure = 0.0;
   m_riskMaxDailyRisk = 0.0;
   m_riskPortfolioRisk = 0.0;
   m_riskCurrentDrawdown = 0.0;
   m_riskConservativeMode = false;
   m_riskEmergencyMode = false;
   m_riskGateApproved = 0;
   m_riskGateRejected = 0;

   // Performance data defaults
   m_perfTotalTrades = 0;
   m_perfWinRate = 0.0;
   m_perfProfitFactor = 0.0;
   m_perfSharpeRatio = 0.0;
   m_perfMaxDrawdown = 0.0;
   m_perfRecoveryFactor = 0.0;
   m_perfNetProfit = 0.0;
   m_perfAvgWin = 0.0;
   m_perfAvgLoss = 0.0;

   // Python bridge data defaults
   m_pyConnected = false;
   m_pyVersion = "";
   m_pyRequests = 0;
   m_pyOk = 0;
   m_pyErrors = 0;

   // AI data defaults
   m_aiNnActive = false;
   m_aiNnSignal = "NONE";
   m_aiNnConf = 0.0;
   m_aiNnLabels = 0;
   m_aiNnSteps = 0;
   m_aiNnConformalQ = 1.0;
   m_aiNnConformalAlpha = 0.05;
   m_aiNnAssetClass = 9;
   m_aiNnBarrierK = 1.5;
   m_aiNnBarrierVertBars = 20;
   m_aiNnTradeLinked = 0;
   m_aiNnNormReady = false;
   m_aiRegime = "RANGE";
   m_aiRegimeTrend = 0.25;
   m_aiRegimeRange = 0.25;
   m_aiRegimeVolatile = 0.25;
   m_aiRegimeSpike = 0.25;
   m_aiMetaFeatures = 65;
   m_aiMetaCooldown = 50;
   m_aiMetaEarlyStop = 20;
   m_aiMetaWinRate = 0.5;
   m_aiMetaAvgConf = 0.5;
   m_aiMetaSamplesSince = 0;
}

void CDashboardBridge::SetAIData(bool nnActive, const string &nnSignal, double nnConf,
                                  int nnLabels, int nnSteps, double nnConformalQ, double nnConformalAlpha,
                                  int nnAssetClass, double nnBarrierK, int nnBarrierVertBars,
                                  int nnTradeLinked, bool nnNormReady,
                                  const string &regime, double regimeTrend, double regimeRange,
                                  double regimeVolatile, double regimeSpike,
                                  int metaFeatures, int metaCooldown, int metaEarlyStop,
                                  double metaWinRate, double metaAvgConf, int metaSamplesSince)
{
   m_aiNnActive = nnActive;
   m_aiNnSignal = nnSignal;
   m_aiNnConf = nnConf;
   m_aiNnLabels = nnLabels;
   m_aiNnSteps = nnSteps;
   m_aiNnConformalQ = nnConformalQ;
   m_aiNnConformalAlpha = nnConformalAlpha;
   m_aiNnAssetClass = nnAssetClass;
   m_aiNnBarrierK = nnBarrierK;
   m_aiNnBarrierVertBars = nnBarrierVertBars;
   m_aiNnTradeLinked = nnTradeLinked;
   m_aiNnNormReady = nnNormReady;
   m_aiRegime = regime;
   m_aiRegimeTrend = regimeTrend;
   m_aiRegimeRange = regimeRange;
   m_aiRegimeVolatile = regimeVolatile;
   m_aiRegimeSpike = regimeSpike;
   m_aiMetaFeatures = metaFeatures;
   m_aiMetaCooldown = metaCooldown;
   m_aiMetaEarlyStop = metaEarlyStop;
   m_aiMetaWinRate = metaWinRate;
   m_aiMetaAvgConf = metaAvgConf;
   m_aiMetaSamplesSince = metaSamplesSince;
}

//+------------------------------------------------------------------+
//| Set risk snapshot data                                           |
//+------------------------------------------------------------------+
void CDashboardBridge::SetRiskData(double activeRiskPerTrade, double dailyRiskUsed,
                                   double dailyEntryRisk, double dailyMtmLoss,
                                   double openExposure, double maxDailyRisk,
                                   double portfolioRisk, double currentDD,
                                   bool conservativeMode, bool emergencyMode,
                                   int gateApproved, int gateRejected)
{
   m_riskActiveRiskPerTrade = activeRiskPerTrade;
   m_riskDailyRiskUsed = dailyRiskUsed;
   m_riskDailyEntryRisk = dailyEntryRisk;
   m_riskDailyMtmLoss = dailyMtmLoss;
   m_riskOpenExposure = openExposure;
   m_riskMaxDailyRisk = maxDailyRisk;
   m_riskPortfolioRisk = portfolioRisk;
   m_riskCurrentDrawdown = currentDD;
   m_riskConservativeMode = conservativeMode;
   m_riskEmergencyMode = emergencyMode;
   m_riskGateApproved = gateApproved;
   m_riskGateRejected = gateRejected;
}

//+------------------------------------------------------------------+
//| Set performance analytics data                                   |
//+------------------------------------------------------------------+
void CDashboardBridge::SetPerformanceData(int totalTradesParam, double winRate, double profitFactor,
                                           double sharpeRatio, double maxDD, double recoveryFactor,
                                           double netProfit, double avgWin, double avgLoss)
{
   m_perfTotalTrades = totalTradesParam;
   m_perfWinRate = winRate;
   m_perfProfitFactor = profitFactor;
   m_perfSharpeRatio = sharpeRatio;
   m_perfMaxDrawdown = maxDrawdown;
   m_perfRecoveryFactor = recoveryFactor;
   m_perfNetProfit = netProfit;
   m_perfAvgWin = avgWin;
   m_perfAvgLoss = avgLoss;
}

//+------------------------------------------------------------------+
//| Set python bridge data                                           |
//+------------------------------------------------------------------+
void CDashboardBridge::SetPythonBridgeData(bool connected, const string &version,
                                           int requests, int ok, int errors)
{
   m_pyConnected = connected;
   m_pyVersion = version;
   m_pyRequests = requests;
   m_pyOk = ok;
   m_pyErrors = errors;
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
                                        const string &post_data, string &response,
                                        int timeoutMs = -1)
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

//+------------------------------------------------------------------+
//| Build state JSON payload (removed old version — enhanced version at line 1014)
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Push current EA state to dashboard server                        |
//+------------------------------------------------------------------+
bool CDashboardBridge::PushState()
{
   if(!m_initialized || !m_enabled)
      return false;

   // Guard against stacked pushes — skip if previous push still in progress
   if(m_pushInProgress)
      return false;

   m_pushInProgress = true;
   string json = BuildStateJson();
   string response;
   string stateUrl = m_endpoint + "/state";

    m_pushCount++;

    // Debug: log first 200 chars of JSON
    if(m_pushCount <= 3)
        PrintFormat("[DASHBOARD-BRIDGE] Push #%d JSON preview: %s", m_pushCount, StringSubstr(json, 0, 200));

    if(SendHttpRequest("POST", stateUrl, json, response))
   {
      m_pushSuccessCount++;
      m_lastPushTime = TimeCurrent();
      m_pushInProgress = false;
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

               // Acknowledge the command
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

//+------------------------------------------------------------------+
//| Log dashboard bridge state                                       |
//+------------------------------------------------------------------+
void CDashboardBridge::LogState(string message, bool isError)
{
   string prefix = isError ? "[DASHBOARD-BRIDGE-ERROR] " : "[DASHBOARD-BRIDGE] ";
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

//+------------------------------------------------------------------+
//| Set heartbeat counter references                                 |
//+------------------------------------------------------------------+
void CDashboardBridge::SetHeartbeatCounters(int scans, int signalsGen, int signalsVal,
                                             int tradesOpened, int shadowTrades, int spikeEvents)
{
   m_pScansCount = scans;
   m_pSignalsGenerated = signalsGen;
   m_pSignalsValidated = signalsVal;
   m_pTradesOpened = tradesOpened;
   m_pShadowTrades = shadowTrades;
   m_pSpikeEvents = spikeEvents;
   m_heartbeatCountersSet = true;
}

//+------------------------------------------------------------------+
//| Build risk JSON from UnifiedRiskManager                          |
//+------------------------------------------------------------------+
string CDashboardBridge::BuildRiskJson()
{
   string json = "\"risk\":{";
   json += "\"active_risk_per_trade_pct\":" + DoubleToString(m_riskActiveRiskPerTrade, 2) + ",";
   json += "\"daily_risk_used_pct\":" + DoubleToString(m_riskDailyRiskUsed, 2) + ",";
   json += "\"daily_entry_risk_pct\":" + DoubleToString(m_riskDailyEntryRisk, 2) + ",";
   json += "\"daily_mtm_loss_pct\":" + DoubleToString(m_riskDailyMtmLoss, 2) + ",";
   json += "\"open_exposure_pct\":" + DoubleToString(m_riskOpenExposure, 2) + ",";
   json += "\"max_daily_risk_pct\":" + DoubleToString(m_riskMaxDailyRisk, 2) + ",";
   json += "\"portfolio_risk_pct\":" + DoubleToString(m_riskPortfolioRisk, 2) + ",";
   json += "\"current_drawdown_pct\":" + DoubleToString(m_riskCurrentDrawdown, 2) + ",";
   json += "\"conservative_mode\":" + (m_riskConservativeMode ? "true" : "false") + ",";
   json += "\"emergency_mode\":" + (m_riskEmergencyMode ? "true" : "false") + ",";
   json += "\"gate_approved\":" + IntegerToString(m_riskGateApproved) + ",";
   json += "\"gate_rejected\":" + IntegerToString(m_riskGateRejected);
   json += "}";
   return json;
}

//+------------------------------------------------------------------+
//| Build performance JSON from PerformanceAnalytics                 |
//+------------------------------------------------------------------+
string CDashboardBridge::BuildPerformanceJson()
{
   string json = "\"performance\":{";
   json += "\"total_trades\":" + IntegerToString(m_perfTotalTrades) + ",";
   json += "\"win_rate\":" + DoubleToString(m_perfWinRate, 2) + ",";
   json += "\"profit_factor\":" + DoubleToString(m_perfProfitFactor, 2) + ",";
   json += "\"sharpe_ratio\":" + DoubleToString(m_perfSharpeRatio, 2) + ",";
   json += "\"max_drawdown\":" + DoubleToString(m_perfMaxDrawdown, 2) + ",";
   json += "\"recovery_factor\":" + DoubleToString(m_perfRecoveryFactor, 2) + ",";
   json += "\"net_profit\":" + DoubleToString(m_perfNetProfit, 2) + ",";
   json += "\"avg_win\":" + DoubleToString(m_perfAvgWin, 2) + ",";
   json += "\"avg_loss\":" + DoubleToString(m_perfAvgLoss, 2);
   json += "}";
   return json;
}

//+------------------------------------------------------------------+
//| Build AI adapters JSON                                           |
//+------------------------------------------------------------------+
string CDashboardBridge::BuildAIJson()
{
   string json = "\"ai\":{";

   // ONNX adapter (no stored data — always inactive unless wired)
   json += "\"onnx\":{\"active\":false},";

   // Ensemble (no stored data — always inactive unless wired)
   json += "\"ensemble\":{\"active\":false},";

   // Transformer (no stored data — always inactive unless wired)
   json += "\"transformer\":{\"active\":false},";

   // Neural network — uses stored data from SetAIData
   json += "\"nn\":{";
   json += "\"active\":" + (m_aiNnActive ? "true" : "false") + ",";
   json += "\"signal\":\"" + EscapeJsonString(m_aiNnSignal) + "\",";
   json += "\"confidence\":" + DoubleToString(m_aiNnConf, 4) + ",";
   json += "\"labels\":" + IntegerToString(m_aiNnLabels) + ",";
   json += "\"steps\":" + IntegerToString(m_aiNnSteps) + ",";
   json += "\"conformal_q\":" + DoubleToString(m_aiNnConformalQ, 4) + ",";
   json += "\"conformal_alpha\":" + DoubleToString(m_aiNnConformalAlpha, 4) + ",";
   json += "\"asset_class\":" + IntegerToString(m_aiNnAssetClass) + ",";
   json += "\"barrier_k\":" + DoubleToString(m_aiNnBarrierK, 2) + ",";
   json += "\"barrier_vert_bars\":" + IntegerToString(m_aiNnBarrierVertBars) + ",";
   json += "\"trade_linked\":" + IntegerToString(m_aiNnTradeLinked) + ",";
   json += "\"norm_ready\":" + (m_aiNnNormReady ? "true" : "false");
   json += "},";

   // Regime — uses stored data from SetAIData
   json += "\"regime\":{";
   json += "\"current\":\"" + EscapeJsonString(m_aiRegime) + "\",";
   json += "\"trend\":" + DoubleToString(m_aiRegimeTrend, 4) + ",";
   json += "\"range\":" + DoubleToString(m_aiRegimeRange, 4) + ",";
   json += "\"volatile\":" + DoubleToString(m_aiRegimeVolatile, 4) + ",";
   json += "\"spike\":" + DoubleToString(m_aiRegimeSpike, 4);
   json += "},";

   // Meta-labeler — uses stored data from SetAIData
   json += "\"meta\":{";
   json += "\"features\":" + IntegerToString(m_aiMetaFeatures) + ",";
   json += "\"cooldown\":" + IntegerToString(m_aiMetaCooldown) + ",";
   json += "\"early_stop\":" + IntegerToString(m_aiMetaEarlyStop) + ",";
   json += "\"win_rate\":" + DoubleToString(m_aiMetaWinRate, 4) + ",";
   json += "\"avg_conf\":" + DoubleToString(m_aiMetaAvgConf, 4) + ",";
   json += "\"samples_since\":" + IntegerToString(m_aiMetaSamplesSince);
   json += "}";

   json += "}";
   return json;
}

//+------------------------------------------------------------------+
//| Build strategies JSON                                            |
//+------------------------------------------------------------------+
string CDashboardBridge::BuildStrategiesJson()
{
   return "\"strategies\":[]";
}

//+------------------------------------------------------------------+
//| Build consensus JSON                                             |
//+------------------------------------------------------------------+
string CDashboardBridge::BuildConsensusJson()
{
   return "\"consensus\":{\"symbols\":{}}";
}

//+------------------------------------------------------------------+
//| Build heartbeat JSON from counters                               |
//+------------------------------------------------------------------+
string CDashboardBridge::BuildHeartbeatJson()
{
   string json = "\"heartbeat\":{";
   
   if(m_heartbeatCountersSet)
   {
      json += "\"scans\":" + IntegerToString(m_pScansCount) + ",";
      json += "\"signals_generated\":" + IntegerToString(m_pSignalsGenerated) + ",";
      json += "\"signals_validated\":" + IntegerToString(m_pSignalsValidated) + ",";
      json += "\"trades_opened\":" + IntegerToString(m_pTradesOpened) + ",";
      json += "\"shadow_trades\":" + IntegerToString(m_pShadowTrades) + ",";
      json += "\"spike_events\":" + IntegerToString(m_pSpikeEvents);
   }
   else
   {
      json += "\"scans\":0,";
      json += "\"signals_generated\":0,";
      json += "\"signals_validated\":0,";
      json += "\"trades_opened\":0,";
      json += "\"shadow_trades\":0,";
      json += "\"spike_events\":0";
   }
   
   json += "}";
   return json;
}

//+------------------------------------------------------------------+
//| Build Python bridge JSON                                         |
//+------------------------------------------------------------------+
string CDashboardBridge::BuildPythonBridgeJson()
{
   string json = "\"python_bridge\":{";
   json += "\"connected\":" + (m_pyConnected ? "true" : "false") + ",";
   json += "\"version\":\"" + EscapeJsonString(m_pyVersion) + "\",";
   json += "\"requests\":" + IntegerToString(m_pyRequests) + ",";
   json += "\"ok\":" + IntegerToString(m_pyOk) + ",";
   json += "\"errors\":" + IntegerToString(m_pyErrors);
   json += "}";
   return json;
}

//+------------------------------------------------------------------+
//| Build state JSON payload (ENHANCED VERSION)                      |
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

   // Positions (actual data)
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

   // Risk (use enhanced method)
   json += BuildRiskJson() + ",";

   // Performance (use enhanced method)
   json += BuildPerformanceJson() + ",";

   // Consensus
   json += BuildConsensusJson() + ",";

   // AI adapters
   json += BuildAIJson() + ",";

   // Strategies
   json += BuildStrategiesJson() + ",";

   // Scalp (placeholder for now)
   json += "\"scalp\":{";
   json += "\"active\":false,";
   json += "\"open_positions\":0,";
   json += "\"max_positions\":0,";
   json += "\"total_entries\":0,";
   json += "\"total_rejections\":0";
   json += "},";

   // Heartbeat (use enhanced method with actual counters)
   json += BuildHeartbeatJson() + ",";

   // Execution mode
   json += "\"execution_mode\":\"LIVE_SEND\",";

   // Python bridge
   json += BuildPythonBridgeJson();

   json += "}";

   return json;
}
