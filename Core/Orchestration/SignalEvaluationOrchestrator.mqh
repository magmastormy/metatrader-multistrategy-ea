//+------------------------------------------------------------------+
//| SignalEvaluationOrchestrator.mqh                                  |
//| Encapsulates signal evaluation logic extracted from               |
//| MultiStrategyAutonomousEA.mq5 ProcessTradingLogic                 |
//| Blueprint Section 10.1 — Monolith Decomposition                  |
//+------------------------------------------------------------------+
#ifndef __SIGNAL_EVALUATION_ORCHESTRATOR_MQH__
#define __SIGNAL_EVALUATION_ORCHESTRATOR_MQH__

#include "..\Utils\Enums.mqh"
#include "..\Management\EnterpriseStrategyManager.mqh"
#include "..\Cache\ConsensusCache.mqh"
#include "..\Risk\UnifiedRiskManager.mqh"

//+------------------------------------------------------------------+
//| Signal Evaluation Orchestrator                                    |
//| Encapsulates the consensus signal evaluation that was inline in   |
//| ProcessTradingLogic. Delegates to existing manager/cache code.    |
//+------------------------------------------------------------------+
class CSignalEvaluationOrchestrator
{
private:
   CEnterpriseStrategyManager*  m_managers[];      // per-symbol (not owned)
   CConsensusCache*             m_consensusCache;   // not owned
   CUnifiedRiskManager*         m_riskManager;      // not owned
   int                          m_symbolCount;
   bool                         m_initialized;

public:
   CSignalEvaluationOrchestrator() :
      m_consensusCache(NULL),
      m_riskManager(NULL),
      m_symbolCount(0),
      m_initialized(false)
   {
   }

   bool Initialize(CEnterpriseStrategyManager* &managers[], int count,
                   CConsensusCache* cache, CUnifiedRiskManager* riskMgr)
   {
      if(count <= 0 || cache == NULL || riskMgr == NULL)
         return false;

      ArrayResize(m_managers, count);
      for(int i = 0; i < count; i++)
         m_managers[i] = managers[i];

      m_symbolCount = count;
      m_consensusCache = cache;
      m_riskManager = riskMgr;
      m_initialized = true;
      return true;
   }

   bool IsInitialized() const { return m_initialized; }

   //--- Main evaluation method — replaces the inline signal eval in ProcessTradingLogic
   //--- Returns true if a viable signal was found (signal != TRADE_SIGNAL_NONE)
   bool EvaluateSignals(string symbol, ENUM_SIGNAL_EVAL_MODE evalMode,
                        ENUM_TRADE_SIGNAL &signal, double &confidence,
                        int &confluence, SConsensusDecisionContext &decisionContext)
   {
      signal = TRADE_SIGNAL_NONE;
      confidence = 0.0;
      confluence = 0;

      if(!m_initialized)
         return false;

      CEnterpriseStrategyManager* manager = GetManagerForSymbol(symbol);
      if(manager == NULL)
         return false;

      // Get signal with confluence tracking (per-symbol analysis)
      signal = manager.GetConsensusSignalForSymbolWithConfluenceMode(symbol, confidence, confluence, evalMode);

      // Retrieve the decision context for downstream use
      manager.GetLastDecisionContext(decisionContext);

      // Cache the result for SRE hot path
      if(m_consensusCache != NULL && signal != TRADE_SIGNAL_NONE)
         m_consensusCache.Store(symbol, evalMode, signal, confidence, confluence);

      return (signal != TRADE_SIGNAL_NONE);
   }

   //--- Two-tier evaluation (fast path) — uses cache when available
   bool EvaluateSignalsFastPath(string symbol, ENUM_SIGNAL_EVAL_MODE evalMode,
                                ENUM_TRADE_SIGNAL &signal, double &confidence,
                                int &confluence)
   {
      signal = TRADE_SIGNAL_NONE;
      confidence = 0.0;
      confluence = 0;

      if(!m_initialized)
         return false;

      // Try cache first
      if(m_consensusCache != NULL)
      {
         if(m_consensusCache.TryGet(symbol, evalMode, signal, confidence, confluence))
            return (signal != TRADE_SIGNAL_NONE);
      }

      // Cache miss — delegate to full evaluation
      SConsensusDecisionContext unusedContext;
      return EvaluateSignals(symbol, evalMode, signal, confidence, confluence, unusedContext);
   }

   //--- Get the consensus result (with cache)
   ENUM_TRADE_SIGNAL GetConsensus(string symbol, ENUM_SIGNAL_EVAL_MODE mode,
                                   double &confidence, int &confluence)
   {
      confidence = 0.0;
      confluence = 0;

      if(!m_initialized)
         return TRADE_SIGNAL_NONE;

      // Try cache first
      if(m_consensusCache != NULL)
      {
         ENUM_TRADE_SIGNAL cachedSignal;
         if(m_consensusCache.TryGet(symbol, mode, cachedSignal, confidence, confluence))
            return cachedSignal;
      }

      // Full evaluation
      SConsensusDecisionContext unusedContext;
      ENUM_TRADE_SIGNAL signal;
      EvaluateSignals(symbol, mode, signal, confidence, confluence, unusedContext);
      return signal;
   }

   //--- Get the last cycle funnel counts from a symbol's manager
   bool GetLastCycleFunnel(string symbol, int &signalsGenerated,
                           int &signalsAfterPipeline, bool &signalAfterQuorum)
   {
      CEnterpriseStrategyManager* manager = GetManagerForSymbol(symbol);
      if(manager == NULL)
      {
         signalsGenerated = 0;
         signalsAfterPipeline = 0;
         signalAfterQuorum = false;
         return false;
      }

      manager.GetLastCycleFunnel(signalsGenerated, signalsAfterPipeline, signalAfterQuorum);
      return true;
   }

   //--- Get signal execution context from a symbol's manager
   bool GetLastSignalExecutionContext(string symbol, string &roleTag,
                                      string &clusterTag, string &clusterCode,
                                      string &contributorSummary)
   {
      CEnterpriseStrategyManager* manager = GetManagerForSymbol(symbol);
      if(manager == NULL)
      {
         roleTag = "PRIMARY_ALPHA";
         clusterTag = "NONE";
         clusterCode = "N";
         contributorSummary = "";
         return false;
      }

      return manager.GetLastSignalExecutionContext(roleTag, clusterTag, clusterCode, contributorSummary);
   }

   //--- Get signal contributors from a symbol's manager
   void GetLastSignalContributors(string symbol, string &contributorsList[])
   {
      CEnterpriseStrategyManager* manager = GetManagerForSymbol(symbol);
      if(manager == NULL)
      {
         ArrayResize(contributorsList, 0);
         return;
      }

      manager.GetLastSignalContributors(contributorsList);
   }

   //--- Invalidate consensus cache for a symbol (on new bar)
   void InvalidateCache(string symbol)
   {
      if(m_consensusCache != NULL)
         m_consensusCache.Invalidate(symbol);
   }

   //--- Invalidate all cached entries
   void InvalidateAllCache()
   {
      if(m_consensusCache != NULL)
         m_consensusCache.InvalidateAll();
   }

private:
   CEnterpriseStrategyManager* GetManagerForSymbol(const string symbol) const
   {
      for(int i = 0; i < m_symbolCount; i++)
      {
         if(m_managers[i] != NULL && m_managers[i].GetSymbol() == symbol)
            return m_managers[i];
      }
      return NULL;
   }
};

#endif // __SIGNAL_EVALUATION_ORCHESTRATOR_MQH__
