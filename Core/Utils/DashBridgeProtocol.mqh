// Injected snapshot state (risk / performance / python bridge /
// AI adapters) plus the JSON sections serialized from it.
// Owns every field previously fed by the CDashboardBridge Set*Data
// injectors.
// Extracted verbatim from DashboardBridge.mqh (behaviour unchanged)
#property copyright "Copyright 2025"
#property link      ""
#property version   "1.00"
#property strict

#ifndef CORE_DASHBRIDGE_PROTOCOL_MQH
#define CORE_DASHBRIDGE_PROTOCOL_MQH

#include "DashBridgeTypes.mqh"

// Dashboard Bridge Snapshot Data + Section Serialization
class CDashBridgeProtocol
{
private:
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

public:
                     CDashBridgeProtocol();

   // Restore every injected field to its construction-time default
   void              Reset();

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

   // Serialization
   string            BuildRiskJson() const;
   string            BuildPerformanceJson() const;
   string            BuildAIJson() const;
   string            BuildPythonBridgeJson() const;
   static string     BuildStrategiesJson();
   static string     BuildConsensusJson();
};

// Constructor
CDashBridgeProtocol::CDashBridgeProtocol()
{
   Reset();
}

// Reset every injected snapshot field to its default
void CDashBridgeProtocol::Reset()
{
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

// Set AI adapter snapshot data
void CDashBridgeProtocol::SetAIData(bool nnActive, const string &nnSignal, double nnConf,
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

// Set risk snapshot data
void CDashBridgeProtocol::SetRiskData(double activeRiskPerTrade, double dailyRiskUsed,
                                      double dailyEntryRisk, double dailyMtmLoss,
                                      double openExposure, double maxDailyRisk,
                                      double portfolioRisk, double currentDrawdown,
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
   m_riskCurrentDrawdown = currentDrawdown;
   m_riskConservativeMode = conservativeMode;
   m_riskEmergencyMode = emergencyMode;
   m_riskGateApproved = gateApproved;
   m_riskGateRejected = gateRejected;
}

// Set performance analytics data
void CDashBridgeProtocol::SetPerformanceData(int totalTrades, double winRate, double profitFactor,
                                             double sharpeRatio, double maxDrawdown, double recoveryFactor,
                                             double netProfit, double avgWin, double avgLoss)
{
   m_perfTotalTrades = totalTrades;
   m_perfWinRate = winRate;
   m_perfProfitFactor = profitFactor;
   m_perfSharpeRatio = sharpeRatio;
   m_perfMaxDrawdown = maxDrawdown;
   m_perfRecoveryFactor = recoveryFactor;
   m_perfNetProfit = netProfit;
   m_perfAvgWin = avgWin;
   m_perfAvgLoss = avgLoss;
}

void CDashBridgeProtocol::SetPythonBridgeData(bool connected, const string &version,
                                              int requests, int ok, int errors)
{
   m_pyConnected = connected;
   m_pyVersion = version;
   m_pyRequests = requests;
   m_pyOk = ok;
   m_pyErrors = errors;
}

string CDashBridgeProtocol::BuildRiskJson() const
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

string CDashBridgeProtocol::BuildPerformanceJson() const
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

// Build AI adapters JSON
string CDashBridgeProtocol::BuildAIJson() const
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
   json += "\"signal\":\"" + CDashBridgeJson::EscapeJsonString(m_aiNnSignal) + "\",";
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
   json += "\"current\":\"" + CDashBridgeJson::EscapeJsonString(m_aiRegime) + "\",";
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

string CDashBridgeProtocol::BuildPythonBridgeJson() const
{
   string json = "\"python_bridge\":{";
   json += "\"connected\":" + (m_pyConnected ? "true" : "false") + ",";
   json += "\"version\":\"" + CDashBridgeJson::EscapeJsonString(m_pyVersion) + "\",";
   json += "\"requests\":" + IntegerToString(m_pyRequests) + ",";
   json += "\"ok\":" + IntegerToString(m_pyOk) + ",";
   json += "\"errors\":" + IntegerToString(m_pyErrors);
   json += "}";
   return json;
}

string CDashBridgeProtocol::BuildStrategiesJson()
{
   return "\"strategies\":[]";
}

string CDashBridgeProtocol::BuildConsensusJson()
{
   return "\"consensus\":{\"symbols\":{}}";
}

#endif // CORE_DASHBRIDGE_PROTOCOL_MQH
