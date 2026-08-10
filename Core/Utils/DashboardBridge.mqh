//+------------------------------------------------------------------+
//| DashboardBridge.mqh                                              |
//| Purpose: Push EA state to external dashboard server               |
//| Features: State push, command poll, graceful degradation          |
//| Thin coordinator — all logic lives in the DashBridge* modules:    |
//|   DashBridgeTypes     : shared JSON primitives                    |
//|   DashBridgeTransport : connection lifecycle + HTTP transport     |
//|   DashBridgeProtocol  : injected snapshot data + JSON sections    |
//|   DashBridgeHealth    : heartbeat counters                        |
//|   DashBridgePanels    : /state payload assembly                   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025"
#property link      ""
#property version   "1.00"
#property strict

#include "Enums.mqh"
#include "ErrorHandling.mqh"
#include "DashBridgeTypes.mqh"
#include "DashBridgeTransport.mqh"
#include "DashBridgeHealth.mqh"
#include "DashBridgeProtocol.mqh"
#include "DashBridgePanels.mqh"

class CEnterpriseStrategyManager;

extern CEnterpriseStrategyManager* g_enterpriseManagers[];
extern string g_enterpriseManagerSymbols[];

//+------------------------------------------------------------------+
//| Dashboard Bridge Class                                           |
//+------------------------------------------------------------------+
class CDashboardBridge
{
private:
   CDashBridgeTransport m_transport;   // Connection lifecycle + HTTP transport
   CDashBridgeProtocol  m_protocol;    // Injected snapshot data + JSON sections
   CDashBridgeHealth    m_health;      // Heartbeat counters

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
                                               int tradesOpened, int spikeEvents);

    // Getters
    bool              IsEnabled() const { return m_transport.IsEnabled(); }
    bool              IsConnected() const { return m_transport.IsConnected(); }
    bool              IsControlEnabled() const { return m_transport.IsControlEnabled(); }
    int               GetPushCount() const { return m_transport.GetPushCount(); }
    int               GetSuccessCount() const { return m_transport.GetSuccessCount(); }
    int               GetErrorCount() const { return m_transport.GetErrorCount(); }
    datetime          GetLastPushTime() const { return m_transport.GetLastPushTime(); }

   // Setters
   void              SetEnabled(bool enabled) { m_transport.SetEnabled(enabled); }

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
};

//+------------------------------------------------------------------+
//| Constructor — module members carry the original defaults         |
//+------------------------------------------------------------------+
CDashboardBridge::CDashboardBridge()
{
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
   return m_transport.Initialize(endpoint, enabled, controlEnabled, pushIntervalSec,
                                 requestTimeoutMs, pushTimeoutMs);
}

//+------------------------------------------------------------------+
//| Shutdown the Dashboard Bridge                                    |
//+------------------------------------------------------------------+
void CDashboardBridge::Shutdown()
{
   bool wasInitialized = m_transport.IsInitialized();
   m_transport.Shutdown();
   if(wasInitialized)
      m_protocol.Reset();
}

//+------------------------------------------------------------------+
//| Push current EA state to dashboard server                        |
//+------------------------------------------------------------------+
bool CDashboardBridge::PushState()
{
   if(!m_transport.BeginPush())
      return false;
   return m_transport.FinishPush(CDashBridgePanels::BuildStateJson(m_protocol, m_health));
}

//+------------------------------------------------------------------+
//| Poll for pending control commands                                |
//+------------------------------------------------------------------+
bool CDashboardBridge::PollCommands()
{
   return m_transport.PollCommands();
}

//+------------------------------------------------------------------+
//| Set heartbeat counter references                                 |
//+------------------------------------------------------------------+
void CDashboardBridge::SetHeartbeatCounters(int scans, int signalsGen, int signalsVal,
                                             int tradesOpened, int spikeEvents)
{
   m_health.SetHeartbeatCounters(scans, signalsGen, signalsVal, tradesOpened, spikeEvents);
}

//+------------------------------------------------------------------+
//| Set AI adapter snapshot data                                     |
//+------------------------------------------------------------------+
void CDashboardBridge::SetAIData(bool nnActive, const string &nnSignal, double nnConf,
                                  int nnLabels, int nnSteps, double nnConformalQ, double nnConformalAlpha,
                                  int nnAssetClass, double nnBarrierK, int nnBarrierVertBars,
                                  int nnTradeLinked, bool nnNormReady,
                                  const string &regime, double regimeTrend, double regimeRange,
                                  double regimeVolatile, double regimeSpike,
                                  int metaFeatures, int metaCooldown, int metaEarlyStop,
                                  double metaWinRate, double metaAvgConf, int metaSamplesSince)
{
   m_protocol.SetAIData(nnActive, nnSignal, nnConf, nnLabels, nnSteps, nnConformalQ,
                        nnConformalAlpha, nnAssetClass, nnBarrierK, nnBarrierVertBars,
                        nnTradeLinked, nnNormReady, regime, regimeTrend, regimeRange,
                        regimeVolatile, regimeSpike, metaFeatures, metaCooldown,
                        metaEarlyStop, metaWinRate, metaAvgConf, metaSamplesSince);
}

//+------------------------------------------------------------------+
//| Set risk snapshot data                                           |
//+------------------------------------------------------------------+
void CDashboardBridge::SetRiskData(double activeRiskPerTrade, double dailyRiskUsed,
                                   double dailyEntryRisk, double dailyMtmLoss,
                                   double openExposure, double maxDailyRisk,
                                   double portfolioRisk, double currentDrawdown,
                                   bool conservativeMode, bool emergencyMode,
                                   int gateApproved, int gateRejected)
{
   m_protocol.SetRiskData(activeRiskPerTrade, dailyRiskUsed, dailyEntryRisk, dailyMtmLoss,
                          openExposure, maxDailyRisk, portfolioRisk, currentDrawdown,
                          conservativeMode, emergencyMode, gateApproved, gateRejected);
}

//+------------------------------------------------------------------+
//| Set performance analytics data                                   |
//+------------------------------------------------------------------+
void CDashboardBridge::SetPerformanceData(int totalTrades, double winRate, double profitFactor,
                                           double sharpeRatio, double maxDrawdown, double recoveryFactor,
                                           double netProfit, double avgWin, double avgLoss)
{
   m_protocol.SetPerformanceData(totalTrades, winRate, profitFactor, sharpeRatio, maxDrawdown,
                                 recoveryFactor, netProfit, avgWin, avgLoss);
}

//+------------------------------------------------------------------+
//| Set python bridge data                                           |
//+------------------------------------------------------------------+
void CDashboardBridge::SetPythonBridgeData(bool connected, const string &version,
                                           int requests, int ok, int errors)
{
   m_protocol.SetPythonBridgeData(connected, version, requests, ok, errors);
}
