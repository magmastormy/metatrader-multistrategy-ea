//+------------------------------------------------------------------+
//| ExecutionOrchestrator.mqh                                         |
//| Encapsulates trade execution logic extracted from                 |
//| MultiStrategyAutonomousEA.mq5 ProcessTradingLogic                 |
//| Blueprint Section 10.1 — Monolith Decomposition                  |
//+------------------------------------------------------------------+
#ifndef __EXECUTION_ORCHESTRATOR_MQH__
#define __EXECUTION_ORCHESTRATOR_MQH__

#include "..\Utils\Enums.mqh"
#include "..\Trading\TradeManager.mqh"
#include "..\Risk\UnifiedRiskManager.mqh"
#include "..\Risk\PositionSizer.mqh"
#include "..\Risk\RiskTierManager.mqh"
#include "..\Risk\FullMarginMode.mqh"
#include "..\Risk\SafeModeConfig.mqh"
#include "..\Monitoring\PerformanceAnalytics.mqh"

//+------------------------------------------------------------------+
//| Approved trade candidate struct (mirrors main EA definition)      |
//+------------------------------------------------------------------+
struct SOrchestratorTradeCandidate
{
   bool                valid;
   string              symbol;
   ENUM_TRADE_SIGNAL   signal;
   ENUM_ORDER_TYPE     orderType;
   ENUM_SIGNAL_EVAL_MODE evalMode;
   ENUM_VALIDATION_PROFILE validationProfile;
   double              consensusConfidence;
   double              tradeConfidence;
   double              qualityScore;
   double              convictionScore;
   double              contextScore;
   double              readinessScore;
   double              costScore;
   double              diversityScore;
   double              rankingScore;
   int                 confluence;
   double              entryPrice;
   double              atrValue;
   double              stopLossPips;
   double              takeProfitPips;
   double              lotSize;
   double              slPrice;
   double              tpPrice;
   string              signalType;
   string              strategyRoleTag;
   string              strategyClusterTag;
   string              strategyClusterCode;
   string              contributorSummary;
   bool                hasAIContributor;
   bool                hasONNXContributor;
   bool                hasIndicatorContributor;
   bool                liveAuthorityAllowed;
   double              liveAuthorityRiskMultiplier;
   string              liveAuthorityReason;
   ulong               cycleId;
   SValidationResult   riskResult;

   SOrchestratorTradeCandidate()
   {
      valid = false;
      symbol = "";
      signal = TRADE_SIGNAL_NONE;
      orderType = ORDER_TYPE_BUY;
      evalMode = EVAL_MODE_NEW_BAR;
      validationProfile = VALIDATION_PROFILE_NEW_BAR;
      consensusConfidence = 0.0;
      tradeConfidence = 0.0;
      qualityScore = 0.0;
      convictionScore = 0.0;
      contextScore = 0.0;
      readinessScore = 0.0;
      costScore = 0.0;
      diversityScore = 0.0;
      rankingScore = 0.0;
      confluence = 0;
      entryPrice = 0.0;
      atrValue = 0.0;
      stopLossPips = 0.0;
      takeProfitPips = 0.0;
      lotSize = 0.0;
      slPrice = 0.0;
      tpPrice = 0.0;
      signalType = "";
      strategyRoleTag = "PRIMARY_ALPHA";
      strategyClusterTag = "NONE";
      strategyClusterCode = "N";
      contributorSummary = "";
      hasAIContributor = false;
      hasONNXContributor = false;
      hasIndicatorContributor = false;
      liveAuthorityAllowed = false;
      liveAuthorityRiskMultiplier = 0.0;
      liveAuthorityReason = "";
      cycleId = 0;
      riskResult.approved = false;
      riskResult.message = "";
      riskResult.adjustedLotSize = 0.0;
      riskResult.riskPercent = 0.0;
      riskResult.portfolioRisk = 0.0;
      riskResult.correlationRisk = 0.0;
      riskResult.requiresAdjustment = false;
      riskResult.severity = ERROR_LEVEL_INFO;
   }
};

//+------------------------------------------------------------------+
//| Execution Orchestrator                                            |
//| Encapsulates the trade execution logic that was inline in         |
//| ProcessTradingLogic. Delegates to existing TradeManager/Risk.     |
//+------------------------------------------------------------------+
class CExecutionOrchestrator
{
private:
   CTradeManager*          m_tradeManager;       // not owned
   CUnifiedRiskManager*    m_riskManager;        // not owned
   CPositionSizer*         m_positionSizer;      // not owned
   CRiskTierManager*       m_tierManager;        // not owned
   CFullMarginMode*        m_fullMarginMode;     // not owned
   CSafeMode*              m_safeMode;           // not owned
   CPerformanceAnalytics*  m_performanceAnalytics; // not owned
   bool                    m_initialized;

public:
   CExecutionOrchestrator() :
      m_tradeManager(NULL),
      m_riskManager(NULL),
      m_positionSizer(NULL),
      m_tierManager(NULL),
      m_fullMarginMode(NULL),
      m_safeMode(NULL),
      m_performanceAnalytics(NULL),
      m_initialized(false)
   {
   }

   bool Initialize(CTradeManager* tradeMgr, CUnifiedRiskManager* riskMgr,
                   CPositionSizer* sizer, CRiskTierManager* tierMgr,
                   CFullMarginMode* fmMode, CSafeMode* safeMode,
                   CPerformanceAnalytics* perfAnalytics)
   {
      if(tradeMgr == NULL || riskMgr == NULL || sizer == NULL || tierMgr == NULL)
         return false;

      m_tradeManager = tradeMgr;
      m_riskManager = riskMgr;
      m_positionSizer = sizer;
      m_tierManager = tierMgr;
      m_fullMarginMode = fmMode;
      m_safeMode = safeMode;
      m_performanceAnalytics = perfAnalytics;
      m_initialized = true;
      return true;
   }

   bool IsInitialized() const { return m_initialized; }

   //--- Execute a trade candidate — replaces the inline execution code
   //--- Returns true if the trade was successfully sent (live or shadow)
   bool ExecuteTradeCandidate(SOrchestratorTradeCandidate &candidate,
                               bool shadowMode,
                               bool enableLiveAuthorityGate,
                               ulong &hbTradesOpened,
                               ulong &hbShadowTrades,
                               ulong &hbSignalsSent,
                               datetime &lastTradeTime,
                               datetime tickTime)
   {
      if(!m_initialized || !candidate.valid)
         return false;

      bool executeAsShadow = (shadowMode || (enableLiveAuthorityGate && !candidate.liveAuthorityAllowed));

      if(executeAsShadow)
      {
         hbShadowTrades++;
         hbSignalsSent++;
         if(shadowMode)
            lastTradeTime = tickTime;
         return true;
      }

      // Live execution path
      string tradeComment = BuildClusterTaggedTradeComment(candidate.strategyClusterCode, "");
      int symbolIdx = 0; // Caller must provide mapping; simplified here
      int clusterNum = ClusterCodeToNumeric(candidate.strategyClusterCode);
      uint perSymbolMagic = (uint)GenerateMagicNumber(symbolIdx, clusterNum);

      bool tradeSuccess = m_tradeManager.OpenPosition(
         candidate.symbol,
         candidate.orderType,
         candidate.lotSize,
         candidate.entryPrice,
         candidate.stopLossPips,
         candidate.takeProfitPips,
         tradeComment,
         perSymbolMagic
      );

      if(tradeSuccess)
      {
         hbTradesOpened++;
         hbSignalsSent++;
         lastTradeTime = tickTime;

         STradeExecutionReceipt receipt;
         m_tradeManager.GetLastExecutionReceipt(receipt);
         double fillRatio = 1.0;
         if(receipt.requestedVolume > 0.0 && receipt.filledVolume > 0.0)
            fillRatio = MathMin(1.0, receipt.filledVolume / receipt.requestedVolume);

         m_riskManager.RegisterExecutedTradeRisk(candidate.riskResult, fillRatio);

         // Safe mode position registration
         if(candidate.symbol != "" && m_safeMode != NULL && m_safeMode.IsInitialized())
         {
            ulong safeTicket = m_tradeManager.GetLastTicket();
            double safeEntry = receipt.averagePrice > 0.0 ? receipt.averagePrice : candidate.entryPrice;
            double safeSL = m_tradeManager.GetLastRequestedStopLoss();
            double safeTP = m_tradeManager.GetLastRequestedTakeProfit();
            m_safeMode.RegisterPosition(safeTicket, candidate.symbol, safeEntry, safeSL, safeTP);
         }
      }

      return tradeSuccess;
   }

   //--- Validate and approve a trade — risk checks
   bool ValidateAndApproveTrade(string symbol, ENUM_TRADE_SIGNAL signal,
                                 double lotSize, double confidence,
                                 double