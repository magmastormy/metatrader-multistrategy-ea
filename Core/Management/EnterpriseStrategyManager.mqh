//+------------------------------------------------------------------+
//| Enterprise Strategy Manager - Production Grade                   |
//| Central manager for all strategies with unified pipeline        |
//+------------------------------------------------------------------+
#ifndef ENTERPRISE_STRATEGY_MANAGER_MQH
#define ENTERPRISE_STRATEGY_MANAGER_MQH

#include "../Pipeline/UnifiedSignalPipeline.mqh"
#include "../AI/AIStrategyOrchestrator.mqh"
#include "../Visualization/DrawingCoordinator.mqh"
#include "../../Interfaces/IStrategy.mqh"

// Import all strategies in logical order
#include "../../Strategies/SimpleMomentumStrategy.mqh"
#include "../../Strategies/StrategyRSI.mqh"
#include "../../Strategies/StrategyTrend.mqh"
#include "../../Strategies/StrategyMeanReversion.mqh"
#include "../../Strategies/StrategySwing.mqh"
#include "../../Strategies/StrategyVolatility.mqh"
#include "../../Strategies/StrategyMACD.mqh"
#include "../../Strategies/StrategyBollinger.mqh"
#include "../../Strategies/StrategyBollingerBreakout.mqh"
#include "../../Strategies/StrategySMC.mqh"
#include "../../Strategies/StrategyBreakout.mqh"
#include "../../Strategies/StrategyFibonacci.mqh"
#include "../../Strategies/StrategyElliottWaveEnhanced.mqh"
#include "../../Strategies/StrategyIchimoku.mqh"
#include "../../Strategies/StrategyHarmonicPatterns.mqh"
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
class CAIStrategyOrchestrator;

//+------------------------------------------------------------------+
//| Strategy Registration Entry                                     |
//+------------------------------------------------------------------+
struct StrategyEntry
{
    IStrategy* strategy;
    string name;
    string orchestratorKey;
    bool enabled;
    double weight;
    ENUM_TIMEFRAMES timeframe;
    int successCount;
    int failCount;
    double avgConfidence;
    ENUM_TRADE_SIGNAL lastSignal;
    double lastSignalConfidence;
    datetime lastEvaluationTime;
};

//+------------------------------------------------------------------+
//| Enterprise Strategy Manager Class                               |
//+------------------------------------------------------------------+
class CEnterpriseStrategyManager
{
private:
    CUnifiedSignalPipeline* m_pipeline;
    CAIStrategyOrchestrator* m_orchestrator;
    CTradeManager* m_tradeManager;  // CRITICAL FIX: Store for strategy initialization
    CPositionSizer* m_positionSizer; // CRITICAL FIX: Store for strategy initialization
    
    StrategyEntry m_strategies[];
    int m_strategyCount;
    
    string m_symbol;
    ENUM_TIMEFRAMES m_baseTimeframe;
    long m_managedMagic;
    
    bool m_initialized;
    bool m_useOrchestrator;
    bool m_ownsOrchestrator;  // New flag to track ownership
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

    bool IsPositionIdStillOpen(const ulong positionId) const;
    string BuildOrchestratorStrategyKey(const string strategyName, ENUM_TIMEFRAMES timeframe) const;
    
public:
    CEnterpriseStrategyManager();
    ~CEnterpriseStrategyManager();
    
    // Initialization
    bool Initialize(const string symbol, ENUM_TIMEFRAMES timeframe, 
                   bool useOrchestrator = true, bool usePipeline = true,
                   CTradeManager* tradeManagerPtr = NULL, CPositionSizer* positionSizerPtr = NULL,
                   CAIStrategyOrchestrator* orchestratorPtr = NULL,
                   const long managedMagic = 0);
    
    // Strategy management
    bool RegisterStrategy(IStrategy* strategy, const string name, 
                         bool enabled = true, double weight = 1.0,
                         ENUM_TIMEFRAMES tf = PERIOD_CURRENT);
    bool EnableStrategy(const string name);
    bool DisableStrategy(const string name);
    void EnableAllStrategies();
    void DisableAllStrategies();
    
    // Signal generation
    ENUM_TRADE_SIGNAL GetConsensusSignal(double &confidence);
    ENUM_TRADE_SIGNAL GetConsensusSignalForSymbol(const string symbol, double &confidence);
    ENUM_TRADE_SIGNAL GetConsensusSignalWithConfluence(double &confidence, int &confluence);
    ENUM_TRADE_SIGNAL GetConsensusSignalForSymbolWithConfluence(const string symbol, double &confidence, int &confluence);
    ENUM_TRADE_SIGNAL GetOrchestratedSignal(const string symbol, ENUM_TIMEFRAMES timeframe, double &confidence);
    ENUM_TRADE_SIGNAL GetFilteredSignal(IStrategy* strategy, double &confidence);
    
    // Configuration
    void SetPipelineFilters(SignalFilterSettings &settings);
    void SetOrchestratorMode(double minWinRate, int maxLosses);
    void SetMinQuorum(int quorum) { m_minQuorum = MathMax(1, quorum); }  // Solo Mode support
    int  GetMinQuorum() const { return m_minQuorum; }
    
    // Utility
    int GetActiveStrategyCount() const;
    string GetStrategyReport() const;
    void UpdatePerformance(const string strategyName, bool success);
    
    // New bar processing - CRITICAL for zone scanning and drawing
    void OnNewBar(const string symbol, ENUM_TIMEFRAMES timeframe);
    
    // Trade Feedback - Wires trade results to AI Orchestrator
    void OnTradeTransaction(const MqlTradeTransaction& trans, const MqlTradeRequest& request, const MqlTradeResult& result);
    
    // Auto-registration
    void AutoRegisterStrategies(bool &enabledFlags[]);
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CEnterpriseStrategyManager::CEnterpriseStrategyManager() :
    m_pipeline(NULL),
    m_orchestrator(NULL),
    m_tradeManager(NULL),
    m_positionSizer(NULL),
    m_strategyCount(0),
    m_managedMagic(0),
    m_initialized(false),
    m_useOrchestrator(true),
    m_ownsOrchestrator(true), // Default to owning it unless injected
    m_usePipeline(true),
    m_minQuorum(1),         // Default to 1 for Solo Mode support (was 2)
    m_totalSignals(0),
    m_successfulSignals(0),
    m_avgConfidence(0),
    m_lastContributorCount(0),
    m_lastSignalSymbol(""),
    m_lastSignalTime(0)
{
    ArrayResize(m_strategies, 0);
    ArrayResize(m_lastSignalContributors, 0);
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
    
    if(m_orchestrator != NULL && m_ownsOrchestrator)
    {
        delete m_orchestrator;
        m_orchestrator = NULL;
    }
}

//+------------------------------------------------------------------+
//| Initialize Manager                                              |
//+------------------------------------------------------------------+
bool CEnterpriseStrategyManager::Initialize(const string symbol, ENUM_TIMEFRAMES timeframe,
                                           bool useOrchestrator, bool usePipeline,
                                           CTradeManager* tradeManagerPtr, CPositionSizer* positionSizerPtr,
                                           CAIStrategyOrchestrator* orchestratorPtr,
                                           const long managedMagic)
{
    m_symbol = symbol;
    m_baseTimeframe = timeframe;
    m_managedMagic = managedMagic;
    m_useOrchestrator = useOrchestrator;
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
    
    // Initialize orchestrator
    if(m_useOrchestrator)
    {
        if(orchestratorPtr != NULL)
        {
            // Use injected orchestrator
            m_orchestrator = orchestratorPtr;
            m_ownsOrchestrator = false;
            Print("[ENTERPRISE] Using injected AI Strategy Orchestrator");
        }
        else
        {
            // Create internal orchestrator (legacy behavior)
            m_orchestrator = new CAIStrategyOrchestrator();
            m_ownsOrchestrator = true;
            Print("[ENTERPRISE] Created internal AI Strategy Orchestrator");
        }

        if(m_orchestrator != NULL)
        {
            if(m_ownsOrchestrator) // Only initialize if we own it, otherwise assume it's initialized by owner
                m_orchestrator.Initialize(0.4, 5);
        }
    }
    
    m_initialized = true;
    
    Print("[EnterpriseStrategyManager] Initialized for ", symbol, " on ", EnumToString(timeframe));
    Print("[EnterpriseStrategyManager] Pipeline: ", m_usePipeline ? "ENABLED" : "DISABLED");
    Print("[EnterpriseStrategyManager] Orchestrator: ", m_useOrchestrator ? "ENABLED" : "DISABLED");
    
    return true;
}

string CEnterpriseStrategyManager::BuildOrchestratorStrategyKey(const string strategyName, ENUM_TIMEFRAMES timeframe) const
{
    ENUM_TIMEFRAMES resolvedTf = (timeframe == PERIOD_CURRENT ? m_baseTimeframe : timeframe);
    return strategyName + "|" + m_symbol + "|" + EnumToString(resolvedTf);
}

//+------------------------------------------------------------------+
//| Register Strategy                                               |
//+------------------------------------------------------------------+
bool CEnterpriseStrategyManager::RegisterStrategy(IStrategy* strategy, const string name,
                                                 bool enabled, double weight,
                                                 ENUM_TIMEFRAMES tf)
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
    m_strategies[m_strategyCount].orchestratorKey = BuildOrchestratorStrategyKey(name, resolvedTf);
    m_strategies[m_strategyCount].enabled = enabled;
    m_strategies[m_strategyCount].weight = weight;
    m_strategies[m_strategyCount].timeframe = resolvedTf;
    m_strategies[m_strategyCount].successCount = 0;
    m_strategies[m_strategyCount].failCount = 0;
    m_strategies[m_strategyCount].avgConfidence = 0;
    m_strategies[m_strategyCount].lastSignal = TRADE_SIGNAL_NONE;
    m_strategies[m_strategyCount].lastSignalConfidence = 0.0;
    m_strategies[m_strategyCount].lastEvaluationTime = 0;
    
    m_strategyCount++;
    
    // Register with orchestrator
    if(m_orchestrator != NULL)
    {
        if(!m_orchestrator.AddStrategy(m_strategies[m_strategyCount - 1].orchestratorKey, weight))
        {
            Print("[EnterpriseStrategyManager] WARNING: Failed to add strategy to orchestrator: ",
                  m_strategies[m_strategyCount - 1].orchestratorKey);
        }
    }
    
    Print("[EnterpriseStrategyManager] Registered strategy: ", name, 
          " | Enabled: ", enabled, " | Weight: ", weight);
    
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
    
    // AUDIT FIX: Use orchestrator if enabled (matching GetConsensusSignalWithConfluence behavior)
    if(m_useOrchestrator && m_orchestrator != NULL)
    {
        ENUM_TRADE_SIGNAL signal = GetOrchestratedSignal(symbol, m_baseTimeframe, confidence);
        confluence = (signal != TRADE_SIGNAL_NONE) ? m_lastContributorCount : 0;
        return signal;
    }
    
    // Store original symbol for restoration
    string originalSymbol = m_symbol;
    
    // Temporarily switch context to target symbol
    m_symbol = symbol;
    
    int buyVotes = 0, sellVotes = 0;
    double buyConf = 0, sellConf = 0;
    int activeStrategies = 0;
    
    for(int i = 0; i < m_strategyCount; i++)
    {
        if(!m_strategies[i].enabled)
            continue;
        
        double stratConf = 0;
        ENUM_TRADE_SIGNAL signal;
        
        // Get signal (filtered if pipeline enabled)
        if(m_usePipeline && m_pipeline != NULL)
        {
            signal = m_pipeline.ProcessSignal(m_strategies[i].strategy, 
                                            symbol, 
                                            m_strategies[i].timeframe, 
                                             stratConf);
        }
        else
        {
            signal = m_strategies[i].strategy.GetSignal(stratConf);
        }

        m_strategies[i].lastSignal = signal;
        m_strategies[i].lastSignalConfidence = stratConf;
        m_strategies[i].lastEvaluationTime = TimeCurrent();

        if(signal == TRADE_SIGNAL_BUY)
        {
            buyVotes++;
            buyConf += stratConf * m_strategies[i].weight;
        }
        else if(signal == TRADE_SIGNAL_SELL)
        {
            sellVotes++;
            sellConf += stratConf * m_strategies[i].weight;
        }

        activeStrategies++;
    }
    // Restore original symbol
    m_symbol = originalSymbol;

    if(
        activeStrategies == 0)
    {
        return TRADE_SIGNAL_NONE;
    }

    // Solo Mode: auto-adjust quorum based on active strategies
    int effectiveQuorum = (activeStrategies == 1) ? 1 : m_minQuorum;

    if(buyVotes > sellVotes && buyVotes >= effectiveQuorum)
    {
        confluence = buyVotes;
        confidence = buyConf / buyVotes;
        m_totalSignals++;
        return TRADE_SIGNAL_BUY;
    }
    else if(sellVotes > buyVotes && sellVotes >= effectiveQuorum)
    {
        confluence = sellVotes;
        confidence = sellConf / sellVotes;
        m_totalSignals++;
        return TRADE_SIGNAL_SELL;
    }
    
    confidence = 0;
    confluence = 0;
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
    if(m_orchestrator == NULL || m_strategyCount == 0)
    {
        confidence = 0;
        return TRADE_SIGNAL_NONE;
    }
    
    // Prepare votes for orchestrator
    SEnsembleVote votes[];
    ArrayResize(votes, m_strategyCount);
    
    int voteCount = 0;
    for(int i = 0; i < m_strategyCount; i++)
    {
        if(!m_strategies[i].enabled)
            continue;
        
        double stratConf = 0;
        ENUM_TRADE_SIGNAL signal;
        if(m_usePipeline && m_pipeline != NULL)
        {
            signal = m_pipeline.ProcessSignal(
                m_strategies[i].strategy,
                symbol,
                m_strategies[i].timeframe == PERIOD_CURRENT ? timeframe : m_strategies[i].timeframe,
                stratConf
            );
        }
        else
        {
            signal = m_strategies[i].strategy.GetSignal(stratConf);
        }

        m_strategies[i].lastSignal = signal;
        m_strategies[i].lastSignalConfidence = stratConf;
        m_strategies[i].lastEvaluationTime = TimeCurrent();
        
        if(signal != TRADE_SIGNAL_NONE)
        {
            votes[voteCount].strategyName = (m_strategies[i].orchestratorKey != ""
                                             ? m_strategies[i].orchestratorKey
                                             : m_strategies[i].name);
            votes[voteCount].signal = signal;
            votes[voteCount].confidence = stratConf;
            votes[voteCount].weight = m_strategies[i].weight;
            votes[voteCount].isValid = true;
            voteCount++;
        }
    }
    
    if(voteCount == 0)
    {
        confidence = 0;
        m_lastContributorCount = 0;
        ArrayResize(m_lastSignalContributors, 0);
        return TRADE_SIGNAL_NONE;
    }
    
    // Get orchestrated decision
    ArrayResize(votes, voteCount);
    ENUM_TRADE_SIGNAL finalSignal = m_orchestrator.GetEnsembleSignal(votes, voteCount, confidence);

    if(finalSignal != TRADE_SIGNAL_NONE)
    {
        int contributorCount = 0;
        ArrayResize(m_lastSignalContributors, voteCount);
        for(int i = 0; i < voteCount; i++)
        {
            if(votes[i].signal == finalSignal)
            {
                m_lastSignalContributors[contributorCount] = votes[i].strategyName;
                contributorCount++;
            }
        }
        ArrayResize(m_lastSignalContributors, contributorCount);
        m_lastContributorCount = contributorCount;
        m_lastSignalSymbol = symbol;
        m_lastSignalTime = TimeCurrent();
    }
    else
    {
        m_lastContributorCount = 0;
        ArrayResize(m_lastSignalContributors, 0);
    }

    return finalSignal;
}

//+------------------------------------------------------------------+
//| Auto-register Strategies                                        |
//+------------------------------------------------------------------+
void CEnterpriseStrategyManager::AutoRegisterStrategies(bool &flags[])
{
    int size = ArraySize(flags);
    
    // 0: Momentum
    if(size > 0 && flags[0]) RegisterStrategy(new CSimpleMomentumStrategy(), "Momentum", true, 1.0);
    
    // 1: RSI
    if(size > 1 && flags[1]) RegisterStrategy(new CStrategyRSI(), "RSI", true, 1.0);
    
    // 2: Trend
    if(size > 2 && flags[2]) RegisterStrategy(new CStrategyTrend(), "Trend", true, 1.2);
    
    // 3: Mean Reversion
    if(size > 3 && flags[3]) RegisterStrategy(new CStrategyMeanReversion(), "Mean Reversion", true, 1.0);
    
    // 4: Swing
    if(size > 4 && flags[4]) RegisterStrategy(new CStrategySwing(), "Swing", true, 1.2);
    
    // 5: Volatility
    if(size > 5 && flags[5]) RegisterStrategy(new CStrategyVolatility(), "Volatility", true, 1.0);
    
    // 6: MACD
    if(size > 6 && flags[6]) RegisterStrategy(new CStrategyMACD(), "MACD", true, 1.0);
    
    // 7: Bollinger
    if(size > 7 && flags[7]) RegisterStrategy(new CStrategyBollinger(), "Bollinger", true, 1.0);
    
    // 8: Bollinger Breakout
    if(size > 8 && flags[8]) RegisterStrategy(new CStrategyBollingerBreakout(), "Bollinger Breakout", true, 1.2);
    
    // 9: SMC
    if(size > 9 && flags[9]) RegisterStrategy(new CStrategySMC(), "Advanced SMC", true, 2.5);
    
    // 10: Breakout
    if(size > 10 && flags[10]) RegisterStrategy(new CStrategyBreakout(), "Breakout", true, 1.5);
    
    // 11: Fibonacci
    if(size > 11 && flags[11]) RegisterStrategy(new CStrategyFibonacci(), "Fibonacci", true, 1.2);
    
    // 12: Elliott Wave
    if(size > 12 && flags[12]) RegisterStrategy(new CStrategyElliottWaveEnhanced(), "Elliott Wave", true, 2.0);
    
    // 13: Ichimoku
    if(size > 13 && flags[13]) RegisterStrategy(new CStrategyIchimoku(), "Ichimoku", true, 1.2);
    
    // 14: Harmonic Patterns
    if(size > 14 && flags[14]) RegisterStrategy(new CStrategyHarmonicPatterns(), "Harmonic Patterns", true, 1.5);
    
    // 15: Support/Resistance
    if(size > 15 && flags[15]) RegisterStrategy(new CStrategySupportResistance(), "Support/Resistance", true, 1.5);
    
    // 16: Unified ICT/SMC
    if(size > 16 && flags[16]) RegisterStrategy(new CStrategyUnifiedICT(), "Unified ICT/SMC", true, 2.2);
    
    // 17: Candlestick
    if(size > 17 && flags[17]) RegisterStrategy(new CStrategyCandlestick(), "Candlestick", true, 1.5);
    
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
    if(m_orchestrator != NULL)
    {
        double clampedWinRate = MathMax(0.0, MathMin(1.0, minWinRate));
        int clampedMaxLosses = MathMax(1, maxLosses);
        m_orchestrator.SetMinWinRateThreshold(clampedWinRate);
        m_orchestrator.SetMaxConsecutiveLosses(clampedMaxLosses);
        PrintFormat("[EnterpriseStrategyManager] Orchestrator mode updated | MinWinRate=%.2f | MaxConsecutiveLosses=%d",
                    clampedWinRate, clampedMaxLosses);
    }
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
                
                // Feed result to Orchestrator ensemble tracking
                if(m_orchestrator != NULL)
                {
                    bool success = (netProfit > 0);
                    m_orchestrator.RecordEnsembleResult(success);
                    
                    if(success) m_successfulSignals++;

                    // Best-effort attribution: assign closed trade outcome to latest contributors
                    if(m_lastContributorCount > 0 &&
                       trans.symbol == m_lastSignalSymbol &&
                       (TimeCurrent() - m_lastSignalTime) <= 3600)
                    {
                        for(int i = 0; i < m_lastContributorCount; i++)
                        {
                            if(m_lastSignalContributors[i] != "")
                                m_orchestrator.UpdateStrategyPerformance(m_lastSignalContributors[i], netProfit);
                        }
                        m_lastContributorCount = 0;
                        ArrayResize(m_lastSignalContributors, 0);
                    }
                    
                    // Log for debugging
                    PrintFormat("[EnterpriseManager] Trade Closed | Symbol: %s | Ticket: %I64u | PositionID: %I64u | Net Profit: %.2f | AI Feedback Sent: %s",
                               dealSymbol, dealTicket, positionId, netProfit, success ? "SUCCESS" : "FAILURE");
                }
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
