// Thin coordinator: pushes EA state to the external dashboard server and polls
// it for control commands, degrading gracefully when the server is unreachable.
// All logic lives in the DashBridge* modules: Types (shared JSON primitives),
// Transport (connection lifecycle + HTTP), Protocol (injected snapshot data +
// JSON sections), Health (heartbeat counters), Panels (/state payload assembly).
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

class CDashboardBridge
{
private:
   CDashBridgeTransport m_transport;
   CDashBridgeProtocol  m_protocol;
   CDashBridgeHealth    m_health;

public:
                       CDashboardBridge();
                      ~CDashboardBridge();

   bool              Initialize(const string &endpoint, bool enabled = true,
                                bool controlEnabled = false, int pushIntervalSec = 5,
                                int requestTimeoutMs = 1000, int pushTimeoutMs = 5000);
   void              Shutdown();

    bool              PushState();
    bool              PollCommands();

        void              SetHeartbeatCounters(int scans, int signalsGen, int signalsVal,
                                               int tradesOpened, int spikeEvents);

    bool              IsEnabled() const { return m_transport.IsEnabled(); }
    bool              IsConnected() const { return m_transport.IsConnected(); }
    bool              IsControlEnabled() const { return m_transport.IsControlEnabled(); }
    int               GetPushCount() const { return m_transport.GetPushCount(); }
    int               GetSuccessCount() const { return m_transport.GetSuccessCount(); }
    int               GetErrorCount() const { return m_transport.GetErrorCount(); }
    datetime          GetLastPushTime() const { return m_transport.GetLastPushTime(); }

   void              SetEnabled(bool enabled) { m_transport.SetEnabled(enabled); }

    // Snapshot injectors: call from the main loop before PushState.
    void              SetAIData(bool nnActive, const string &nnSignal, double nnConf,
                                int nnLabels, int nnSteps, double nnConformalQ, double nnConformalAlpha,
                                int nnAssetClass, double nnBarrierK, int nnBarrierVertBars,
                                int nnTradeLinked, bool nnNormReady,
                                const string &regime, double regimeTrend, double regimeRange,
                                double regimeVolatile, double regimeSpike,
                                int metaFeatures, int metaCooldown, int metaEarlyStop,
                                double metaWinRate, double metaAvgConf, int metaSamplesSince);

    void              SetRiskData(double activeRiskPerTrade, double dailyRiskUsed,
                                  double dailyEntryRisk, double dailyMtmLoss,
                                  double openExposure, double maxDailyRisk,
                                  double portfolioRisk, double currentDrawdown,
                                  bool conservativeMode, bool emergencyMode,
                                  int gateApproved, int gateRejected);

    void              SetPerformanceData(int totalTrades, double winRate, double profitFactor,
                                         double sharpeRatio, double maxDrawdown, double recoveryFactor,
                                         double netProfit, double avgWin, double avgLoss);

    void              SetPythonBridgeData(bool connected, const string &version,
                                          int requests, int ok, int errors);
};

// Module members carry the original defaults, so this constructor is empty.
CDashboardBridge::CDashboardBridge()
{
}

CDashboardBridge::~CDashboardBridge()
{
   Shutdown();
}

bool CDashboardBridge::Initialize(const string &endpoint, bool enabled,
                                   bool controlEnabled, int pushIntervalSec,
                                   int requestTimeoutMs, int pushTimeoutMs)
{
   return m_transport.Initialize(endpoint, enabled, controlEnabled, pushIntervalSec,
                                 requestTimeoutMs, pushTimeoutMs);
}

void CDashboardBridge::Shutdown()
{
   bool wasInitialized = m_transport.IsInitialized();
   m_transport.Shutdown();
   if(wasInitialized)
      m_protocol.Reset();
}

bool CDashboardBridge::PushState()
{
   if(!m_transport.BeginPush())
      return false;
   string stateJson = CDashBridgePanels::BuildStateJson(m_protocol, m_health);
   return m_transport.FinishPush(stateJson);
}

bool CDashboardBridge::PollCommands()
{
   return m_transport.PollCommands();
}

void CDashboardBridge::SetHeartbeatCounters(int scans, int signalsGen, int signalsVal,
                                             int tradesOpened, int spikeEvents)
{
   m_health.SetHeartbeatCounters(scans, signalsGen, signalsVal, tradesOpened, spikeEvents);
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
   m_protocol.SetAIData(nnActive, nnSignal, nnConf, nnLabels, nnSteps, nnConformalQ,
                        nnConformalAlpha, nnAssetClass, nnBarrierK, nnBarrierVertBars,
                        nnTradeLinked, nnNormReady, regime, regimeTrend, regimeRange,
                        regimeVolatile, regimeSpike, metaFeatures, metaCooldown,
                        metaEarlyStop, metaWinRate, metaAvgConf, metaSamplesSince);
}

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

void CDashboardBridge::SetPerformanceData(int totalTrades, double winRate, double profitFactor,
                                           double sharpeRatio, double maxDrawdown, double recoveryFactor,
                                           double netProfit, double avgWin, double avgLoss)
{
   m_protocol.SetPerformanceData(totalTrades, winRate, profitFactor, sharpeRatio, maxDrawdown,
                                 recoveryFactor, netProfit, avgWin, avgLoss);
}

void CDashboardBridge::SetPythonBridgeData(bool connected, const string &version,
                                           int requests, int ok, int errors)
{
   m_protocol.SetPythonBridgeData(connected, version, requests, ok, errors);
}
