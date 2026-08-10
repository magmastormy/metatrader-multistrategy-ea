
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
//| Structural decomposition (behaviour unchanged).                  |
//| This header is a thin coordinator: it aggregates the extracted   |
//| modules so that every symbol previously declared here remains    |
//| available to any translation unit including this file, and       |
//| forwards each public call to the owning module.                  |
//|                                                                  |
//|  PyBridgeTypes.mqh     - ENUM_PYTHON_BRIDGE_STATE and the        |
//|                          SPythonBridgeVersion / HealthStatus /   |
//|                          Response structures                     |
//|  PyBridgeProtocol.mqh  - stateless message framing: JSON escape, |
//|                          scalar extraction, response parsing,    |
//|                          request building, version validation    |
//|  PyBridgeTransport.mqh - connection/session state, HTTP          |
//|                          transport and bridge-state logging      |
//|  PyBridgeHealth.mqh    - heartbeat, reconnection backoff, server |
//|                          version negotiation, log throttling     |
//|  PyBridgeRequests.mqh  - prediction and correlation dispatch     |
//+------------------------------------------------------------------+
#include "PyBridgeTypes.mqh"
#include "PyBridgeProtocol.mqh"
#include "PyBridgeTransport.mqh"
#include "PyBridgeHealth.mqh"
#include "PyBridgeRequests.mqh"

//+------------------------------------------------------------------+
//| Python Bridge Class                                              |
//+------------------------------------------------------------------+
class CPythonBridge
{
private:
   CPyBridgeTransport  m_transport;         // Endpoint/mode/state/counters + HTTP
   CPyBridgeHealth     m_health;            // Heartbeat/reconnect/version/throttle
   
public:
   // Constructor/Destructor
                      CPythonBridge();
                     ~CPythonBridge();
   
   // Initialization
   bool              Initialize(const string &endpoint, 
                                 ENUM_PYTHON_BRIDGE_MODE mode = PYTHON_BRIDGE_OBSERVE,
                                 int request_timeout_ms = 2000,
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
   SPythonBridgeVersion GetServerVersion() const { return m_health.GetServerVersion(); }
   
   // Prediction methods
   SPythonBridgeResponse Predict(const double &features[], int features_size,
                                  const string mode,
                                  int family_id = -1,
                                  const string symbol = "",
                                  int asset_class = -1,
                                  const string asset_class_name = "");
   SPythonBridgeResponse PredictDoubleAdapt(const double &features[], int features_size);
   SPythonBridgeResponse PredictMamlPpo(const double &features[], int features_size);
   SPythonBridgeResponse PredictFamily(const double &features[], int features_size,
                                        int family_id, const string symbol);
   SPythonBridgeResponse PredictMultiAsset(const double &features[], int features_size,
                                            int asset_class, const string asset_class_name,
                                            int family_id, const string symbol);
   
   // ENHANCEMENT: Correlation Matrix Methods (Batch 93 - Week 4)
   bool              GetCorrelationMatrix(double &corrMatrix[], int &size, string &symbols[]);
   double            GetPairCorrelation(const string symbol1, const string symbol2);
   bool              FindBestCorrelatedPair(const string symbol, string &bestPair, double &correlation);
   
   // Getters
   ENUM_PYTHON_BRIDGE_STATE GetState() const { return m_transport.GetState(); }
   ENUM_PYTHON_BRIDGE_MODE  GetMode() const { return m_transport.GetMode(); }
   bool              IsConnected() const { return m_transport.IsConnected(); }
   bool              IsInitialized() const { return m_transport.IsInitialized(); }
   string            GetEndpoint() const { return m_transport.GetEndpoint(); }
   int               GetRequestCount() const { return m_transport.GetRequestCount(); }
   int               GetSuccessCount() const { return m_transport.GetSuccessCount(); }
   int               GetErrorCount() const { return m_transport.GetErrorCount(); }
   string            GetLastError() const { return m_transport.GetLastError(); }
   
   // Utility
   bool              AttemptReconnect();
   bool              ShouldLogNotConfigured();  // Returns true if 300s elapsed since last NOT_CONFIGURED log
};

//+------------------------------------------------------------------+
//| Constructor (module members self-initialize to the same defaults)|
//+------------------------------------------------------------------+
CPythonBridge::CPythonBridge()
{
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
   m_transport.Configure(endpoint, mode, request_timeout_ms);
   m_health.Configure(heartbeat_timeout_s, max_reconnect_attempts, reconnect_backoff_ms);
   return m_transport.CompleteInitialization();
}

//+------------------------------------------------------------------+
//| Shutdown the Python Bridge                                       |
//+------------------------------------------------------------------+
void CPythonBridge::Shutdown()
{
   if(m_transport.IsInitialized())
   {
      m_transport.LogShutdown();
      
      // Reset all state
      m_transport.Reset();
      m_health.Reset();
   }
}

//+------------------------------------------------------------------+
//| Check server health                                              |
//+------------------------------------------------------------------+
bool CPythonBridge::CheckHealth()
{
   return m_health.CheckHealth(m_transport);
}

//+------------------------------------------------------------------+
//| Send heartbeat                                                   |
//+------------------------------------------------------------------+
bool CPythonBridge::SendHeartbeat()
{
   return m_health.SendHeartbeat(m_transport);
}

//+------------------------------------------------------------------+
//| Attempt reconnection                                             |
//+------------------------------------------------------------------+
bool CPythonBridge::AttemptReconnect()
{
   return m_health.AttemptReconnect(m_transport);
}

//+------------------------------------------------------------------+
//| Check server version                                             |
//+------------------------------------------------------------------+
bool CPythonBridge::CheckVersion()
{
   return m_health.CheckVersion(m_transport);
}

//+------------------------------------------------------------------+
//| Get health status                                                 |
//+------------------------------------------------------------------+
SPythonBridgeHealthStatus CPythonBridge::GetHealthStatus()
{
   return m_health.GetHealthStatus(m_transport);
}

//+------------------------------------------------------------------+
//| Should log NOT_CONFIGURED dashboard entry (throttled to 300s)    |
//+------------------------------------------------------------------+
bool CPythonBridge::ShouldLogNotConfigured()
{
   return m_health.ShouldLogNotConfigured();
}

//+------------------------------------------------------------------+
//| Send prediction request                                          |
//+------------------------------------------------------------------+
SPythonBridgeResponse CPythonBridge::Predict(const double &features[], int features_size,
                                              const string mode,
                                              int family_id,
                                              const string symbol,
                                              int asset_class,
                                              const string asset_class_name)
{
   return CPyBridgeRequests::Predict(m_transport, m_health, features, features_size, mode,
                                     family_id, symbol, asset_class, asset_class_name);
}

//+------------------------------------------------------------------+
//| DoubleAdapt prediction                                           |
//+------------------------------------------------------------------+
SPythonBridgeResponse CPythonBridge::PredictDoubleAdapt(const double &features[], int features_size)
{
   return CPyBridgeRequests::PredictDoubleAdapt(m_transport, m_health, features, features_size);
}

//+------------------------------------------------------------------+
//| MAML-PPO prediction                                              |
//+------------------------------------------------------------------+
SPythonBridgeResponse CPythonBridge::PredictMamlPpo(const double &features[], int features_size)
{
   return CPyBridgeRequests::PredictMamlPpo(m_transport, m_health, features, features_size);
}

//+------------------------------------------------------------------+
//| Family-aware prediction                                          |
//+------------------------------------------------------------------+
SPythonBridgeResponse CPythonBridge::PredictFamily(const double &features[], int features_size,
                                                    int family_id, const string symbol)
{
   return CPyBridgeRequests::PredictFamily(m_transport, m_health, features, features_size,
                                           family_id, symbol);
}

//+------------------------------------------------------------------+
//| Multi-asset class prediction (Batch 103)                         |
//+------------------------------------------------------------------+
SPythonBridgeResponse CPythonBridge::PredictMultiAsset(const double &features[], int features_size,
                                                        int asset_class, const string asset_class_name,
                                                        int family_id, const string symbol)
{
   return CPyBridgeRequests::PredictMultiAsset(m_transport, m_health, features, features_size,
                                               asset_class, asset_class_name, family_id, symbol);
}

//+------------------------------------------------------------------+
//| ENHANCEMENT: Get Correlation Matrix (Batch 93 - Week 4)          |
//+------------------------------------------------------------------+
bool CPythonBridge::GetCorrelationMatrix(double &corrMatrix[], int &size, string &symbols[])
{
   return CPyBridgeRequests::GetCorrelationMatrix(m_transport, corrMatrix, size, symbols);
}

//+------------------------------------------------------------------+
//| ENHANCEMENT: Get Pair Correlation (Batch 93 - Week 4)            |
//+------------------------------------------------------------------+
double CPythonBridge::GetPairCorrelation(const string symbol1, const string symbol2)
{
   return CPyBridgeRequests::GetPairCorrelation(m_transport, symbol1, symbol2);
}

//+------------------------------------------------------------------+
//| ENHANCEMENT: Find Best Correlated Pair (Batch 93 - Week 4)       |
//+------------------------------------------------------------------+
bool CPythonBridge::FindBestCorrelatedPair(const string symbol, string &bestPair, double &correlation)
{
   return CPyBridgeRequests::FindBestCorrelatedPair(m_transport, symbol, bestPair, correlation);
}
