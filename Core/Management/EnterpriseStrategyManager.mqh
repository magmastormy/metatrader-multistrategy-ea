//+------------------------------------------------------------------+
//| Enterprise Strategy Manager - Production Grade                   |
//| Central manager for all strategies with unified pipeline        |
//+------------------------------------------------------------------+
#ifndef ENTERPRISE_STRATEGY_MANAGER_MQH
#define ENTERPRISE_STRATEGY_MANAGER_MQH

#include "../Pipeline/UnifiedSignalPipeline.mqh"
#include "../Visualization/DrawingCoordinator.mqh"
#include "../../Interfaces/IStrategy.mqh"

// Retained production strategy inventory (7 kept in codebase)
#include "../../Strategies/SimpleMomentumStrategy.mqh"
#include "../../Strategies/StrategyTrend.mqh"
#include "../../Strategies/StrategyFibonacci.mqh"
#include "../../Strategies/StrategyElliottWaveEnhanced.mqh"
#include "../../Strategies/StrategySupportResistance.mqh"
#include "../../Strategies/StrategyUnifiedICT.mqh"
#include "../../Strategies/StrategyCandlestick.mqh"

// Forward declarations
class CEnhancedErrorHandler;
class CUtilities;
class CHedgingProtection;
class CMarketAnalysis;
class CModeManager;
class CNextGenStrategyBrain;
class CTransformerBrain;
struct SPredictionWithUncertainty;
class CPositionSizer;
class CStrategyManager;
class CTradeManager;
class CPerformanceAnalytics;

//+------------------------------------------------------------------+
//| Strategy Registration Entry                                     |
//+------------------------------------------------------------------+
struct StrategyEntry
{
    IStrategy* strategy;
    string name;
    bool enabled;
    bool intrabarEligible;
    double weight;
    ENUM_TIMEFRAMES timeframe;
    int successCount;
    int failCount;
    double avgConfidence;
    ENUM_TRADE_SIGNAL lastSignal;
    double lastSignalConfidence;
    datetime lastEvaluationTime;
};

enum ENUM_SIGNAL_EVAL_MODE
{
    EVAL_MODE_NEW_BAR = 0,
    EVAL_MODE_INTRABAR = 1
};

//+------------------------------------------------------------------+
//| Enterprise Strategy Manager Class                               |
//+------------------------------------------------------------------+
class CEnterpriseStrategyManager
{
private:
    CUnifiedSignalPipeline* m_pipeline;
    CTradeManager* m_tradeManager;  // CRITICAL FIX: Store for strategy initialization
    CPositionSizer* m_positionSizer; // CRITICAL FIX: Store for strategy initialization
    
    StrategyEntry m_strategies[];
    int m_strategyCount;
    
    string m_symbol;
    ENUM_TIMEFRAMES m_baseTimeframe;
    long m_managedMagic;
    
    bool m_initialized;
    bool m_usePipeline;
    int  m_minQuorum;       // Minimum number of strategies that must agree
    
    // Statistics
    int m_totalSignals;
    int m_successfulSignals;
    double m_avgConfidence;

    // Last orchestrated decision context for basic trade attribution
    string m_lastSignalContributors[];
    int m_lastContributorCount;
    string m_lastSignalSymbol;
    datetime m_lastSignalTime;

    // Consensus diagnostics counters
    ulong m_diagRawNone;
    ulong m_diagFilteredOut;
    ulong m_diagQuorumFailed;
    ulong m_diagIntrabarNotEligible;
    datetime m_lastDiagLogTime;

    // Position-level contributor attribution
    ulong m_attributionPositionIds[];
    string m_attributionContributorCsv[];
    string m_closedTradeContributors[];
    double m_closedTradeNetProfit;
    bool m_hasClosedTradeAttribution;

    bool IsPositionIdStillOpen(const ulong positionId) const;
    int FindStrategyIndexByName(const string name) const;
    void MaybeLogConsensusDiagnostics(const string symbol);
    int FindAttributionIndexByPositionId(const ulong positionId) const;
    string JoinContributors(const string &contributors[]) const;
    void SplitContributors(const string csv, string &contributors[]) const;
    void UpsertPositionAttribution(const ulong positionId, const string &contributors[]);
    bool PopPositionAttribution(const ulong positionId, string &contributors[]);
    
public:
    CEnterpriseStrategyManager();
    ~CEnterpriseStrategyManager();
    
    // Initialization
    bool Initialize(const string symbol, ENUM_TIMEFRAMES timeframe, 
                   bool usePipeline = true,
                   CTradeManager* tradeManagerPtr = NULL, CPositionSizer* positionSizerPtr = NULL,
                   const long managedMagic = 0);
    
    // Strategy management
    bool RegisterStrategy(IStrategy* strategy, const string name, 
                         bool enabled = true, double weight = 1.0,
                         ENUM_TIMEFRAMES tf = PERIOD_CURRENT,
                         bool intrabarEligible = false);
    bool EnableStrategy(const string name);
    bool DisableStrategy(const string name);
    void EnableAllStrategies();
    void DisableAllStrategies();
    
    // Signal generation
    ENUM_TRADE_SIGNAL GetConsensusSignal(double &confidence);
    ENUM_TRADE_SIGNAL GetConsensusSignalForSymbol(const string symbol, double &confidence);
    ENUM_TRADE_SIGNAL GetConsensusSignalWithConfluence(double &confidence, int &confluence);
    ENUM_TRADE_SIGNAL GetConsensusSignalForSymbolWithConfluence(const string symbol, double &confidence, int &confluence);
    ENUM_TRADE_SIGNAL GetConsensusSignalForSymbolWithConfluenceMode(const string symbol, double &confidence, int &confluence, ENUM_SIGNAL_EVAL_MODE evalMode);
    ENUM_TRADE_SIGNAL GetOrchestratedSignal(const string symbol, ENUM_TIMEFRAMES timeframe, double &confidence);
    ENUM_TRADE_SIGNAL GetFilteredSignal(IStrategy* strategy, double &confidence);
    
    // Configuration
    void SetPipelineFilters(SignalFilterSettings &settings);
    void SetOrchestratorMode(double minWinRate, int maxLosses);
    void SetMinQuorum(int quorum) { m_minQuorum = MathMax(1, quorum); }  // Solo Mode support
    int  GetMinQuorum() const { return m_minQuorum; }
    bool UpdateStrategyWeightByName(const string name, const double weight);
    int GetRegisteredStrategyCount() const { return m_strategyCount; }
    string GetRegisteredStrategyName(const int index) const;
    double GetRegisteredStrategyWeight(const int index) const;
    void GetLastSignalContributors(string &contributors[]) const;
    bool PopClosedTradeAttribution(string &contributors[], double &netProfit);
    
    // Utility
    int GetActiveStrategyCount() const;
    int GetActiveBrainStrategyCount() const;
    string GetStrategyReport() const;
    void UpdatePerformance(const string strategyName, bool success);
    
    // New bar processing - CRITICAL for zone scanning and drawing
    void OnNewBar(const string symbol, ENUM_TIMEFRAMES timeframe);
    
    // Trade Feedback - manager-owned trade outcome tracking
    void OnTradeTransaction(const MqlTradeTransaction& trans, const MqlTradeRequest& request, const MqlTradeResult& result);
    
    // Auto-registration
    void AutoRegisterStrategies(bool &enabledFlags[]);
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CEnterpriseStrategyManager::CEnterpriseStrategyManager() :
    m_pipeline(NULL),
    m_tradeManager(NULL),
    m_positionSizer(NULL),
    m_strategyCount(0),
    m_managedMagic(0),
    m_initialized(false),
    m_usePipeline(true),
    m_minQuorum(2),         // Require >=2 aligned contributors when multiple strategies are active
    m_totalSignals(0),
    m_successfulSignals(0),
    m_avgConfidence(0),
    m_lastContributorCount(0),
    m_lastSignalSymbol(""),
    m_lastSignalTime(0),
    m_diagRawNone(0),
    m_diagFilteredOut(0),
    m_diagQuorumFailed(0),
    m_diagIntrabarNotEligible(0),
    m_lastDiagLogTime(0),
    m_closedTradeNetProfit(0.0),
    m_hasClosedTradeAttribution(false)
{
    ArrayResize(m_strategies, 0);
    ArrayResize(m_lastSignalContributors, 0);
    ArrayResize(m_attributionPositionIds, 0);
    ArrayResize(m_attributionContributorCsv, 0);
    ArrayResize(m_closedTradeContributors, 0);
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CEnterpriseStrategyManager::~CEnterpriseStrategyManager()
{
    // Clean up strategies
    for(int i = 0; i < m_strategyCount; i++)
    {
        if(m_strategies[i].strategy != NULL)
        {
            delete m_strategies[i].strategy;
            m_strategies[i].strategy = NULL;
        }
    }
    
    if(m_pipeline != NULL)
    {
        delete m_pipeline;
        m_pipeline = NULL;
    }
}

//+------------------------------------------------------------------+
//| Initialize Manager                                              |
//+------------------------------------------------------------------+
bool CEnterpriseStrategyManager::Initialize(const string symbol, ENUM_TIMEFRAMES timeframe,
                                           bool usePipeline,
                                           CTradeManager* tradeManagerPtr, CPositionSizer* positionSizerPtr,
                                           const long managedMagic)
{
    m_symbol = symbol;
    m_baseTimeframe = timeframe;
    m_managedMagic = managedMagic;
    m_usePipeline = usePipeline;
    m_tradeManager = tradeManagerPtr;   // CRITICAL FIX: Store for strategy initialization
    m_positionSizer = positionSizerPtr; // CRITICAL FIX: Store for strategy initialization
    
    // Initialize pipeline
    if(m_usePipeline)
    {
        m_pipeline = new CUnifiedSignalPipeline();
        if(m_pipeline != NULL)
        {
            SignalFilterSettings filters;
            m_pipeline.Initialize(filters);
        }
    }
    
    m_initialized = true;
    
    Print("[EnterpriseStrategyManager] Initialized for ", symbol, " on ", EnumToString(timeframe));
    Print("[EnterpriseStrategyManager] Pipeline: ", m_usePipeline ? "ENABLED" : "DISABLED");
    
    return true;
}

//+------------------------------------------------------------------+
//| Register Strategy                                               |
//+------------------------------------------------------------------+
bool CEnterpriseStrategyManager::RegisterStrategy(IStrategy* strategy, const string name,
                                                 bool enabled, double weight,
                                                 ENUM_TIMEFRAMES tf,
                                                 bool intrabarEligible)
{
    if(strategy == NULL || !m_initialized)
        return false;
    
    // Initialize strategy with VALID pointers
    ENUM_TIMEFRAMES resolvedTf = (tf == PERIOD_CURRENT ? m_baseTimeframe : tf);
    bool initSuccess = strategy.Init(m_symbol, resolvedTf,
                                     m_tradeManager, m_positionSizer);
    
    if(!initSuccess)
    {
        Print("[EnterpriseStrategyManager] ERROR: Strategy ", name, " initialization failed. Skipping registration.");
        delete strategy;
        strategy = NULL;
        return false;
    }
    
    // CRITICAL FIX: Synchronize enabled state with strategy object
    strategy.SetEnabled(enabled);
    strategy.SetWeight(weight);
    
    // Add to array
    int newSize = m_strategyCount + 1;
    ArrayResize(m_strategies, newSize);
    
    m_strategies[m_strategyCount].strategy = strategy;
    m_strategies[m_strategyCount].name = name;
    m_strategies[m_strategyCount].enabled = enabled;
    m_strategies[m_strategyCount].intrabarEligible = intrabarEligible;
    m_strategies[m_strategyCount].weight = weight;
    m_strategies[m_strategyCount].timeframe = resolvedTf;
    m_strategies[m_strategyCount].successCount = 0;
    m_strategies[m_strategyCount].failCount = 0;
    m_strategies[m_strategyCount].avgConfidence = 0;
    m_strategies[m_strategyCount].lastSignal = TRADE_SIGNAL_NONE;
    m_strategies[m_strategyCount].lastSignalConfidence = 0.0;
    m_strategies[m_strategyCount].lastEvaluationTime = 0;
    
    m_strategyCount++;
    
    Print("[EnterpriseStrategyManager] Registered strategy: ", name, 
          " | Enabled: ", enabled, " | Weight: ", weight,
          " | Intrabar: ", intrabarEligible ? "YES" : "NO");
    
    return true;
}

//+------------------------------------------------------------------+
//| Get Consensus Signal (Enhanced with Confluence Tracking)        |
//+------------------------------------------------------------------+
ENUM_TRADE_SIGNAL CEnterpriseStrategyManager::GetConsensusSignal(double &confidence)
{
    int confluence = 0;
    return GetConsensusSignalWithConfluence(confidence, confluence);
}

//+------------------------------------------------------------------+
//| Get Consensus Signal With Confluence                            |
//+------------------------------------------------------------------+
ENUM_TRADE_SIGNAL CEnterpriseStrategyManager::GetConsensusSignalWithConfluence(double &confidence, int &confluence)
{
    return GetConsensusSignalForSymbolWithConfluence(m_symbol, confidence, confluence);
}

//+------------------------------------------------------------------+
//| Get Consensus Signal For Specific Symbol With Confluence        |
//+------------------------------------------------------------------+
ENUM_TRADE_SIGNAL CEnterpriseStrategyManager::GetConsensusSignalForSymbolWithConfluence(const string symbol, double &confidence, int &confluence)
{
    return GetConsensusSignalForSymbolWithConfluenceMode(symbol, confidence, confluence, EVAL_MODE_NEW_BAR);
}

ENUM_TRADE_SIGNAL CEnterpriseStrategyManager::GetConsensusSignalForSymbolWithConfluenceMode(const string symbol,
                                                                                              double &confidence,
                                                                                              int &confluence,
                                                                                              ENUM_SIGNAL_EVAL_MODE evalMode)
{
    confluence = 0;
    confidence = 0;

    if(!m_initialized || m_strategyCount == 0)
    {
        return TRADE_SIGNAL_NONE;
    }

    // Strategies are bound to the manager symbol; reject mismatched symbol requests.
    if(symbol != m_symbol)
    {
        PrintFormat("[CRITICAL] Cross-symbol request rejected in EnterpriseManager. Requested: %s, Bound: %s", symbol, m_symbol);
        return TRADE_SIGNAL_NONE;
    }
    
    int cycleRawNone = 0;
    int cycleFilteredOut = 0;
    int cycleQuorumFailed = 0;
    int cycleIntrabarNotEligible = 0;

    // Store original symbol for restoration
    string originalSymbol = m_symbol;

    // Temporarily switch context to target symbol
    m_symbol = symbol;

    int buyVotes = 0, sellVotes = 0;
    double buyConf = 0, sellConf = 0;
    double buyWeightSum = 0.0, sellWeightSum = 0.0;
    int activeStrategies = 0;
    string buyContributors[];
    string sellContributors[];
    ArrayResize(buyContributors, 0);
    ArrayResize(sellContributors, 0);

    for(int i = 0; i < m_strategyCount; i++)
    {
        if(!m_strategies[i].enabled)
            continue;

        if(evalMode == EVAL_MODE_INTRABAR && !m_strategies[i].intrabarEligible)
        {
            cycleIntrabarNotEligible++;
            continue;
        }

        double stratConf = 0;
        ENUM_TRADE_SIGNAL signal = TRADE_SIGNAL_NONE;

        // Get signal (filtered if pipeline enabled)
        if(m_usePipeline && m_pipeline != NULL)
        {
            signal = m_pipeline.ProcessSignal(m_strategies[i].strategy,
                                              symbol,
                                              m_strategies[i].timeframe,
                                              stratConf);
            if(m_pipeline.WasLastSignalRawNone())
                cycleRawNone++;
            if(m_pipeline.WasLastSignalFilteredByPipeline())
                cycleFilteredOut++;
        }
        else
        {
            signal = m_strategies[i].strategy.GetSignal(stratConf);
            if(signal == TRADE_SIGNAL_NONE)
                cycleRawNone++;
        }

        m_strategies[i].lastSignal = signal;
        m_strategies[i].lastSignalConfidence = stratConf;
        m_strategies[i].lastEvaluationTime = TimeCurrent();

        double strategyWeight = MathMax(0.0, m_strategies[i].weight);
        if(strategyWeight <= 0.0)
            strategyWeight = 1.0;

        if(signal == TRADE_SIGNAL_BUY)
        {
            buyVotes++;
            buyConf += stratConf * strategyWeight;
            buyWeightSum += strategyWeight;

            int buySize = ArraySize(buyContributors);
            ArrayResize(buyContributors, buySize + 1);
            buyContributors[buySize] = m_strategies[i].name;
        }
        else if(signal == TRADE_SIGNAL_SELL)
        {
            sellVotes++;
            sellConf += stratConf * strategyWeight;
            sellWeightSum += strategyWeight;

            int sellSize = ArraySize(sellContributors);
            ArrayResize(sellContributors, sellSize + 1);
            sellContributors[sellSize] = m_strategies[i].name;
        }

        activeStrategies++;
    }

    // Restore original symbol
    m_symbol = originalSymbol;

    m_diagRawNone += (ulong)MathMax(0, cycleRawNone);
    m_diagFilteredOut += (ulong)MathMax(0, cycleFilteredOut);
    m_diagIntrabarNotEligible += (ulong)MathMax(0, cycleIntrabarNotEligible);

    if(activeStrategies == 0)
    {
        MaybeLogConsensusDiagnostics(symbol);
        return TRADE_SIGNAL_NONE;
    }

    int effectiveQuorum = m_minQuorum;
    if(evalMode == EVAL_MODE_INTRABAR)
        effectiveQuorum = 1;
    else if(activeStrategies == 1)
        effectiveQuorum = 1;
    effectiveQuorum = MathMax(1, MathMin(effectiveQuorum, activeStrategies));

    bool buyQuorumMet = (buyVotes >= effectiveQuorum);
    bool sellQuorumMet = (sellVotes >= effectiveQuorum);

    ENUM_TRADE_SIGNAL finalSignal = TRADE_SIGNAL_NONE;
    double finalConfidence = 0.0;
    int finalConfluence = 0;
    string selectedContributors[];
    ArrayResize(selectedContributors, 0);

    if(buyQuorumMet && (!sellQuorumMet || buyConf > sellConf))
    {
        finalSignal = TRADE_SIGNAL_BUY;
        finalConfluence = buyVotes;
        finalConfidence = (buyWeightSum > 0.0) ? (buyConf / buyWeightSum) : 0.0;
        ArrayCopy(selectedContributors, buyContributors);
    }
    else if(sellQuorumMet && (!buyQuorumMet || sellConf > buyConf))
    {
        finalSignal = TRADE_SIGNAL_SELL;
        finalConfluence = sellVotes;
        finalConfidence = (sellWeightSum > 0.0) ? (sellConf / sellWeightSum) : 0.0;
        ArrayCopy(selectedContributors, sellContributors);
    }
    else
    {
        cycleQuorumFailed++;
    }

    // Intrabar safety gate: single-voter signal requires stronger confidence.
    if(finalSignal != TRADE_SIGNAL_NONE &&
       evalMode == EVAL_MODE_INTRABAR &&
       effectiveQuorum == 1 &&
       finalConfidence < 0.65)
    {
        cycleQuorumFailed++;
        finalSignal = TRADE_SIGNAL_NONE;
        finalConfidence = 0.0;
        finalConfluence = 0;
        ArrayResize(selectedContributors, 0);
    }

    m_diagQuorumFailed += (ulong)MathMax(0, cycleQuorumFailed);

    if(finalSignal != TRADE_SIGNAL_NONE)
    {
        confluence = finalConfluence;
        confidence = MathMax(0.0, MathMin(1.0, finalConfidence));
        m_totalSignals++;

        m_lastSignalSymbol = symbol;
        m_lastSignalTime = TimeCurrent();
        ArrayCopy(m_lastSignalContributors, selectedContributors);
        m_lastContributorCount = ArraySize(m_lastSignalContributors);

        MaybeLogConsensusDiagnostics(symbol);
        return finalSignal;
    }

    confidence = 0;
    confluence = 0;
    m_lastContributorCount = 0;
    ArrayResize(m_lastSignalContributors, 0);
    MaybeLogConsensusDiagnostics(symbol);
    return TRADE_SIGNAL_NONE;
}

//+------------------------------------------------------------------+
//| Get Consensus Signal For Specific Symbol                        |
//+------------------------------------------------------------------+
ENUM_TRADE_SIGNAL CEnterpriseStrategyManager::GetConsensusSignalForSymbol(const string symbol, double &confidence)
{
    int confluence = 0;
    return GetConsensusSignalForSymbolWithConfluence(symbol, confidence, confluence);
}

//+------------------------------------------------------------------+
//| Get Orchestrated Signal                                         |
//+------------------------------------------------------------------+
ENUM_TRADE_SIGNAL CEnterpriseStrategyManager::GetOrchestratedSignal(const string symbol, ENUM_TIMEFRAMES timeframe, double &confidence)
{
    // Legacy compatibility method: the orchestrator path is retired.
    // Delegate to manager-owned consensus logic and preserve confluence/quorum behavior.
    int confluence = 0;
    ENUM_TRADE_SIGNAL signal = GetConsensusSignalForSymbolWithConfluence(symbol, confidence, confluence);
    if(signal == TRADE_SIGNAL_NONE)
        ArrayResize(m_lastSignalContributors, 0);
    return signal;
}

//+------------------------------------------------------------------+
//| Auto-register Strategies                                        |
//+------------------------------------------------------------------+
void CEnterpriseStrategyManager::AutoRegisterStrategies(bool &flags[])
{
    int size = ArraySize(flags);
    
    // 0: Momentum
    if(size > 0 && flags[0]) RegisterStrategy(new CSimpleMomentumStrategy(), "Momentum", true, 1.0, PERIOD_CURRENT, false);
    
    // 1: Trend
    if(size > 1 && flags[1]) RegisterStrategy(new CStrategyTrend(), "Trend", true, 1.2, PERIOD_CURRENT, false);
    
    // 2: Fibonacci
    if(size > 2 && flags[2]) RegisterStrategy(new CStrategyFibonacci(), "Fibonacci", true, 1.2, PERIOD_CURRENT, false);
    
    // 3: Elliott Wave
    if(size > 3 && flags[3]) RegisterStrategy(new CStrategyElliottWaveEnhanced(), "Elliott Wave", true, 2.0, PERIOD_CURRENT, false);
    
    // 4: Support/Resistance
    if(size > 4 && flags[4]) RegisterStrategy(new CStrategySupportResistance(), "Support/Resistance", true, 1.5, PERIOD_CURRENT, false);
    
    // 5: Unified ICT/SMC
    if(size > 5 && flags[5]) RegisterStrategy(new CStrategyUnifiedICT(), "Unified ICT/SMC", true, 2.2, PERIOD_CURRENT, false);
    
    // 6: Candlestick
    if(size > 6 && flags[6]) RegisterStrategy(new CStrategyCandlestick(), "Candlestick", true, 1.5, PERIOD_CURRENT, false);
    
    Print("[EnterpriseStrategyManager] Auto-registration complete. Active strategies: ", 
          GetActiveStrategyCount());
}

//+------------------------------------------------------------------+
//| Get Active Strategy Count                                       |
//+------------------------------------------------------------------+
int CEnterpriseStrategyManager::GetActiveStrategyCount() const
{
    int count = 0;
    for(int i = 0; i < m_strategyCount; i++)
    {
        if(m_strategies[i].enabled)
            count++;
    }
    return count;
}

//+------------------------------------------------------------------+
//| Get Active Brain Strategy Count                                  |
//+------------------------------------------------------------------+
int CEnterpriseStrategyManager::GetActiveBrainStrategyCount() const
{
    int count = 0;
    for(int i = 0; i < m_strategyCount; i++)
    {
        if(!m_strategies[i].enabled || m_strategies[i].strategy == NULL)
            continue;

        ENUM_STRATEGY_TYPE strategyType = m_strategies[i].strategy.GetType();
        if(strategyType == STRATEGY_BRAIN || strategyType == STRATEGY_AI_ENHANCED)
            count++;
    }

    return count;
}

//+------------------------------------------------------------------+
//| Get Strategy Report                                             |
//+------------------------------------------------------------------+
string CEnterpriseStrategyManager::GetStrategyReport() const
{
    string report = "=== Enterprise Strategy Report ===\n";
    report += StringFormat("Total Strategies: %d | Active: %d\n", 
                         m_strategyCount, GetActiveStrategyCount());
    report += StringFormat("Total Signals: %d | Success Rate: %.1f%%\n",
                         m_totalSignals, 
                         m_totalSignals > 0 ? (double)m_successfulSignals/m_totalSignals*100 : 0);
    
    report += "\nStrategy Performance:\n";
    for(int i = 0; i < m_strategyCount; i++)
    {
        int total = m_strategies[i].successCount + m_strategies[i].failCount;
        double winRate = total > 0 ? (double)m_strategies[i].successCount/total*100 : 0;
        
        report += StringFormat("- %s: %s | Trades: %d | Win Rate: %.1f%% | Avg Conf: %.2f\n",
                             m_strategies[i].name,
                             m_strategies[i].enabled ? "ON" : "OFF",
                             total, winRate, m_strategies[i].avgConfidence);
    }
    
    if(m_pipeline != NULL)
    {
        report += StringFormat("\nPipeline Stats: Processed: %d | Filtered: %d | Filter Rate: %.1f%%\n",
                             m_pipeline.GetSignalsProcessed(),
                             m_pipeline.GetSignalsFiltered(),
                             m_pipeline.GetFilterRate() * 100);
    }
    
    return report;
}

//+------------------------------------------------------------------+
//| Set Pipeline Filters                                             |
//+------------------------------------------------------------------+
void CEnterpriseStrategyManager::SetPipelineFilters(SignalFilterSettings &settings)
{
    if(m_pipeline != NULL)
    {
        // Apply runtime filter configuration without re-initializing pipeline engines.
        m_pipeline.SetFilters(settings);
        Print("[EnterpriseStrategyManager] Pipeline filters applied: TrendFilter=",
              settings.enableTrendFilter, " MinConf=", settings.minConfidence,
              " MaxVol=", settings.maxVolatility,
              " StructureFilter=", settings.enableStructureFilter,
              " LiquidityFilter=", settings.enableLiquidityFilter);
    }
}

//+------------------------------------------------------------------+
//| Set Orchestrator Mode                                            |
//+------------------------------------------------------------------+
void CEnterpriseStrategyManager::SetOrchestratorMode(double minWinRate, int maxLosses)
{
    double clampedWinRate = MathMax(0.0, MathMin(1.0, minWinRate));
    int clampedMaxLosses = MathMax(1, maxLosses);
    PrintFormat("[EnterpriseStrategyManager] SetOrchestratorMode ignored (manager-only governance mode) | Requested MinWinRate=%.2f | MaxConsecutiveLosses=%d",
                clampedWinRate, clampedMaxLosses);
}

bool CEnterpriseStrategyManager::UpdateStrategyWeightByName(const string name, const double weight)
{
    int index = FindStrategyIndexByName(name);
    if(index < 0)
        return false;

    double sanitizedWeight = MathMax(0.0, MathMin(10.0, weight));
    m_strategies[index].weight = sanitizedWeight;
    if(m_strategies[index].strategy != NULL)
        m_strategies[index].strategy.SetWeight(sanitizedWeight);

    return true;
}

string CEnterpriseStrategyManager::GetRegisteredStrategyName(const int index) const
{
    if(index < 0 || index >= m_strategyCount)
        return "";
    return m_strategies[index].name;
}

double CEnterpriseStrategyManager::GetRegisteredStrategyWeight(const int index) const
{
    if(index < 0 || index >= m_strategyCount)
        return 0.0;
    return m_strategies[index].weight;
}

void CEnterpriseStrategyManager::GetLastSignalContributors(string &contributors[]) const
{
    ArrayCopy(contributors, m_lastSignalContributors);
}

bool CEnterpriseStrategyManager::PopClosedTradeAttribution(string &contributors[], double &netProfit)
{
    if(!m_hasClosedTradeAttribution)
        return false;

    ArrayCopy(contributors, m_closedTradeContributors);
    netProfit = m_closedTradeNetProfit;

    ArrayResize(m_closedTradeContributors, 0);
    m_closedTradeNetProfit = 0.0;
    m_hasClosedTradeAttribution = false;
    return true;
}

int CEnterpriseStrategyManager::FindStrategyIndexByName(const string name) const
{
    for(int i = 0; i < m_strategyCount; i++)
    {
        if(m_strategies[i].name == name)
            return i;
    }
    return -1;
}

void CEnterpriseStrategyManager::MaybeLogConsensusDiagnostics(const string symbol)
{
    datetime now = TimeCurrent();
    if(m_lastDiagLogTime == 0 || (now - m_lastDiagLogTime) >= 60)
    {
        PrintFormat("[CONSENSUS-DIAG] %s | raw_none=%I64u | filtered_out=%I64u | quorum_failed=%I64u | intrabar_not_eligible=%I64u",
                    symbol, m_diagRawNone, m_diagFilteredOut, m_diagQuorumFailed, m_diagIntrabarNotEligible);
        m_diagRawNone = 0;
        m_diagFilteredOut = 0;
        m_diagQuorumFailed = 0;
        m_diagIntrabarNotEligible = 0;
        m_lastDiagLogTime = now;
    }
}

int CEnterpriseStrategyManager::FindAttributionIndexByPositionId(const ulong positionId) const
{
    for(int i = 0; i < ArraySize(m_attributionPositionIds); i++)
    {
        if(m_attributionPositionIds[i] == positionId)
            return i;
    }
    return -1;
}

string CEnterpriseStrategyManager::JoinContributors(const string &contributors[]) const
{
    string csv = "";
    for(int i = 0; i < ArraySize(contributors); i++)
    {
        if(contributors[i] == "")
            continue;
        if(StringLen(csv) > 0)
            csv += ";";
        csv += contributors[i];
    }
    return csv;
}

void CEnterpriseStrategyManager::SplitContributors(const string csv, string &contributors[]) const
{
    ArrayResize(contributors, 0);
    if(csv == "")
        return;

    string parsed[];
    int count = StringSplit(csv, ';', parsed);
    if(count <= 0)
        return;

    ArrayResize(contributors, count);
    for(int i = 0; i < count; i++)
        contributors[i] = parsed[i];
}

void CEnterpriseStrategyManager::UpsertPositionAttribution(const ulong positionId, const string &contributors[])
{
    if(positionId == 0 || ArraySize(contributors) <= 0)
        return;

    string contributorCsv = JoinContributors(contributors);
    if(contributorCsv == "")
        return;

    int idx = FindAttributionIndexByPositionId(positionId);
    if(idx >= 0)
    {
        m_attributionContributorCsv[idx] = contributorCsv;
        return;
    }

    int size = ArraySize(m_attributionPositionIds);
    ArrayResize(m_attributionPositionIds, size + 1);
    ArrayResize(m_attributionContributorCsv, size + 1);
    m_attributionPositionIds[size] = positionId;
    m_attributionContributorCsv[size] = contributorCsv;
}

bool CEnterpriseStrategyManager::PopPositionAttribution(const ulong positionId, string &contributors[])
{
    int idx = FindAttributionIndexByPositionId(positionId);
    if(idx < 0)
        return false;

    SplitContributors(m_attributionContributorCsv[idx], contributors);

    int last = ArraySize(m_attributionPositionIds) - 1;
    if(last >= 0)
    {
        if(idx != last)
        {
            m_attributionPositionIds[idx] = m_attributionPositionIds[last];
            m_attributionContributorCsv[idx] = m_attributionContributorCsv[last];
        }
        ArrayResize(m_attributionPositionIds, last);
        ArrayResize(m_attributionContributorCsv, last);
    }

    return true;
}

//+------------------------------------------------------------------+
//| OnNewBar - CRITICAL for zone scanning and chart drawings         |
//| Must be called from main EA on each new bar                      |
//+------------------------------------------------------------------+
void CEnterpriseStrategyManager::OnNewBar(const string symbol, ENUM_TIMEFRAMES timeframe)
{
    if(!m_initialized || m_strategyCount == 0)
        return;

    datetime barTime = iTime(symbol, timeframe, 0);
    if(barTime <= 0)
        barTime = TimeCurrent();

    CDrawingCoordinator* drawingCoordinator = GetDrawingCoordinator();
    if(drawingCoordinator != NULL)
        drawingCoordinator.BeginBarCycle(symbol, timeframe, barTime);

    // Call OnNewBar and persist per-bar analysis snapshots
    for(int i = 0; i < m_strategyCount; i++)
    {
        if(m_strategies[i].strategy == NULL)
            continue;

        if(m_strategies[i].enabled)
        {
            m_strategies[i].strategy.OnNewBar(symbol, timeframe);
        }
        else
        {
            m_strategies[i].lastSignal = TRADE_SIGNAL_NONE;
            m_strategies[i].lastSignalConfidence = 0.0;
        }

        if(drawingCoordinator != NULL)
        {
            int totalSignals = 0;
            int successfulSignals = 0;
            double accuracy = 0.0;
            m_strategies[i].strategy.GetStatistics(totalSignals, successfulSignals, accuracy);

            drawingCoordinator.RecordStrategySnapshot(
                m_strategies[i].name,
                m_strategies[i].enabled,
                m_strategies[i].lastSignal,
                m_strategies[i].lastSignalConfidence,
                totalSignals,
                successfulSignals,
                accuracy,
                m_strategies[i].lastEvaluationTime > 0
                    ? m_strategies[i].lastEvaluationTime
                    : m_strategies[i].strategy.GetLastSignalTime()
            );
        }
    }

    if(drawingCoordinator != NULL)
        drawingCoordinator.EndBarCycle();
}

//+------------------------------------------------------------------+
//| OnTradeTransaction - Handle trade events for AI feedback        |
//+------------------------------------------------------------------+
void CEnterpriseStrategyManager::OnTradeTransaction(const MqlTradeTransaction& trans,
                                                   const MqlTradeRequest& request,
                                                   const MqlTradeResult& result)
{
    // Check for transaction adding a deal (trade execution)
    if(trans.type == TRADE_TRANSACTION_DEAL_ADD && trans.deal > 0)
    {
        ulong dealTicket = trans.deal;
        if(HistoryDealSelect(dealTicket))
        {
            long dealMagic = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
            if(m_managedMagic > 0 && dealMagic != m_managedMagic)
                return;

            string dealSymbol = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
            if(dealSymbol != "" && dealSymbol != m_symbol)
                return;

            ENUM_DEAL_ENTRY entryType = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
            ulong positionId = (ulong)HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);

            if((entryType == DEAL_ENTRY_IN || entryType == DEAL_ENTRY_INOUT) &&
               positionId > 0 &&
               m_lastContributorCount > 0 &&
               ArraySize(m_lastSignalContributors) > 0)
            {
                UpsertPositionAttribution(positionId, m_lastSignalContributors);
            }
            
            // We care about exits (deals that close a position) to meaningful profit/loss
            if(entryType == DEAL_ENTRY_OUT || entryType == DEAL_ENTRY_OUT_BY || entryType == DEAL_ENTRY_INOUT)
            {
                // Avoid double-counting partial closes; attribute only once when position is fully closed.
                if(positionId > 0 && IsPositionIdStillOpen(positionId))
                    return;

                double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
                double swap = HistoryDealGetDouble(dealTicket, DEAL_SWAP);
                double commission = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
                double netProfit = profit + swap + commission;
                
                bool success = (netProfit > 0);
                if(success)
                    m_successfulSignals++;

                m_hasClosedTradeAttribution = false;
                m_closedTradeNetProfit = 0.0;
                ArrayResize(m_closedTradeContributors, 0);

                string contributors[];
                if(positionId > 0 && PopPositionAttribution(positionId, contributors))
                {
                    ArrayCopy(m_closedTradeContributors, contributors);
                    m_closedTradeNetProfit = netProfit;
                    m_hasClosedTradeAttribution = (ArraySize(m_closedTradeContributors) > 0);
                }

                // Reset cached contributor context after close in manager-only governance mode.
                m_lastContributorCount = 0;
                ArrayResize(m_lastSignalContributors, 0);

                PrintFormat("[EnterpriseManager] Trade Closed | Symbol: %s | Ticket: %I64u | PositionID: %I64u | Net Profit: %.2f | Result: %s",
                           dealSymbol, dealTicket, positionId, netProfit, success ? "SUCCESS" : "FAILURE");
            }
        }
    }
}

bool CEnterpriseStrategyManager::IsPositionIdStillOpen(const ulong positionId) const
{
    if(positionId == 0)
        return false;

    for(int i = 0; i < PositionsTotal(); i++)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket == 0 || !PositionSelectByTicket(ticket))
            continue;

        ulong openPositionId = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
        if(openPositionId == positionId)
            return true;
    }

    return false;
}

#endif // ENTERPRISE_STRATEGY_MANAGER_MQH
