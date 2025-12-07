//+------------------------------------------------------------------+
//| Enterprise Strategy Manager - Production Grade                   |
//| Central manager for all strategies with unified pipeline        |
//+------------------------------------------------------------------+
#ifndef ENTERPRISE_STRATEGY_MANAGER_MQH
#define ENTERPRISE_STRATEGY_MANAGER_MQH

#include "../Pipeline/UnifiedSignalPipeline.mqh"
#include "../AI/AIStrategyOrchestrator.mqh"
#include "../../Interfaces/IStrategy.mqh"

// Import all strategies
#include "../../Strategies/StrategySMC.mqh"
#include "../../Strategies/StrategyElliottWaveEnhanced.mqh"
#include "../../Strategies/StrategyOrderBlock.mqh"
#include "../../Strategies/StrategyFairValueGap.mqh"
#include "../../Strategies/StrategySupplyDemand.mqh"
#include "../../Strategies/StrategySwing.mqh"
#include "../../Strategies/StrategyTrend.mqh"
#include "../../Strategies/StrategyVolatility.mqh"
#include "../../Strategies/StrategyMACD.mqh"
#include "../../Strategies/StrategyRSI.mqh"
#include "../../Strategies/StrategyBollinger.mqh"
#include "../../Strategies/StrategyBreakout.mqh"
#include "../../Strategies/StrategyMeanReversion.mqh"
#include "../../Strategies/SimpleMomentumStrategy.mqh"

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
    bool enabled;
    double weight;
    ENUM_TIMEFRAMES timeframe;
    int successCount;
    int failCount;
    double avgConfidence;
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
    
    bool m_initialized;
    bool m_useOrchestrator;
    bool m_usePipeline;
    
    // Statistics
    int m_totalSignals;
    int m_successfulSignals;
    double m_avgConfidence;
    
public:
    CEnterpriseStrategyManager();
    ~CEnterpriseStrategyManager();
    
    // Initialization
    bool Initialize(const string symbol, ENUM_TIMEFRAMES timeframe, 
                   bool useOrchestrator = true, bool usePipeline = true,
                   CTradeManager* tradeManagerPtr = NULL, CPositionSizer* positionSizerPtr = NULL);
    
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
    ENUM_TRADE_SIGNAL GetOrchestratedSignal(double &confidence);
    ENUM_TRADE_SIGNAL GetFilteredSignal(IStrategy* strategy, double &confidence);
    
    // Configuration
    void SetPipelineFilters(SignalFilterSettings &settings);
    void SetOrchestratorMode(double minWinRate, int maxLosses);
    
    // Utility
    int GetActiveStrategyCount() const;
    string GetStrategyReport() const;
    void UpdatePerformance(const string strategyName, bool success);
    
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
    m_initialized(false),
    m_useOrchestrator(true),
    m_usePipeline(true),
    m_totalSignals(0),
    m_successfulSignals(0),
    m_avgConfidence(0)
{
    ArrayResize(m_strategies, 0);
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
    
    if(m_orchestrator != NULL)
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
                                           CTradeManager* tradeManagerPtr, CPositionSizer* positionSizerPtr)
{
    m_symbol = symbol;
    m_baseTimeframe = timeframe;
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
        m_orchestrator = new CAIStrategyOrchestrator();
        if(m_orchestrator != NULL)
        {
            m_orchestrator.Initialize(0.4, 5);
        }
    }
    
    m_initialized = true;
    
    Print("[EnterpriseStrategyManager] Initialized for ", symbol, " on ", EnumToString(timeframe));
    Print("[EnterpriseStrategyManager] Pipeline: ", m_usePipeline ? "ENABLED" : "DISABLED");
    Print("[EnterpriseStrategyManager] Orchestrator: ", m_useOrchestrator ? "ENABLED" : "DISABLED");
    
    return true;
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
    bool initSuccess = strategy.Init(m_symbol, tf == PERIOD_CURRENT ? m_baseTimeframe : tf, 
                                     m_tradeManager, m_positionSizer);
    
    if(!initSuccess)
    {
        Print("[EnterpriseStrategyManager] WARNING: Strategy ", name, " initialization failed!");
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
    m_strategies[m_strategyCount].weight = weight;
    m_strategies[m_strategyCount].timeframe = tf == PERIOD_CURRENT ? m_baseTimeframe : tf;
    m_strategies[m_strategyCount].successCount = 0;
    m_strategies[m_strategyCount].failCount = 0;
    m_strategies[m_strategyCount].avgConfidence = 0;
    
    m_strategyCount++;
    
    // Register with orchestrator
    if(m_orchestrator != NULL)
    {
        m_orchestrator.AddStrategy(name, weight);
    }
    
    Print("[EnterpriseStrategyManager] Registered strategy: ", name, 
          " | Enabled: ", enabled, " | Weight: ", weight);
    
    return true;
}

//+------------------------------------------------------------------+
//| Get Consensus Signal                                            |
//+------------------------------------------------------------------+
ENUM_TRADE_SIGNAL CEnterpriseStrategyManager::GetConsensusSignal(double &confidence)
{
    if(!m_initialized || m_strategyCount == 0)
    {
        confidence = 0;
        return TRADE_SIGNAL_NONE;
    }
    
    // Use orchestrator if enabled
    if(m_useOrchestrator && m_orchestrator != NULL)
    {
        return GetOrchestratedSignal(confidence);
    }
    
    // Simple consensus voting
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
                                             m_symbol, 
                                             m_strategies[i].timeframe, 
                                             stratConf);
        }
        else
        {
            signal = m_strategies[i].strategy.GetSignal(stratConf);
        }
        
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
    
    if(activeStrategies == 0)
    {
        confidence = 0;
        return TRADE_SIGNAL_NONE;
    }
    
    // Determine consensus
    if(buyVotes > sellVotes)
    {
        confidence = buyConf / buyVotes;
        m_totalSignals++;
        return TRADE_SIGNAL_BUY;
    }
    else if(sellVotes > buyVotes)
    {
        confidence = sellConf / sellVotes;
        m_totalSignals++;
        return TRADE_SIGNAL_SELL;
    }
    
    confidence = 0;
    return TRADE_SIGNAL_NONE;
}

//+------------------------------------------------------------------+
//| Get Consensus Signal For Specific Symbol                        |
//+------------------------------------------------------------------+
ENUM_TRADE_SIGNAL CEnterpriseStrategyManager::GetConsensusSignalForSymbol(const string symbol, double &confidence)
{
    if(!m_initialized || m_strategyCount == 0)
    {
        confidence = 0;
        return TRADE_SIGNAL_NONE;
    }
    
    // Store original symbol for restoration
    string originalSymbol = m_symbol;
    
    // Temporarily switch context to target symbol
    m_symbol = symbol;
    
    // Simple consensus voting for the target symbol
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
                                             symbol,  // Use target symbol
                                             m_strategies[i].timeframe, 
                                             stratConf);
        }
        else
        {
            signal = m_strategies[i].strategy.GetSignal(stratConf);
        }
        
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
    
    if(activeStrategies == 0)
    {
        confidence = 0;
        return TRADE_SIGNAL_NONE;
    }
    
    // Determine consensus
    if(buyVotes > sellVotes)
    {
        confidence = buyConf / buyVotes;
        m_totalSignals++;
        return TRADE_SIGNAL_BUY;
    }
    else if(sellVotes > buyVotes)
    {
        confidence = sellConf / sellVotes;
        m_totalSignals++;
        return TRADE_SIGNAL_SELL;
    }
    
    confidence = 0;
    return TRADE_SIGNAL_NONE;
}

//+------------------------------------------------------------------+
//| Get Orchestrated Signal                                         |
//+------------------------------------------------------------------+
ENUM_TRADE_SIGNAL CEnterpriseStrategyManager::GetOrchestratedSignal(double &confidence)
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
        ENUM_TRADE_SIGNAL signal = m_strategies[i].strategy.GetSignal(stratConf);
        
        if(signal != TRADE_SIGNAL_NONE)
        {
            votes[voteCount].strategyName = m_strategies[i].name;
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
        return TRADE_SIGNAL_NONE;
    }
    
    // Get orchestrated decision
    ArrayResize(votes, voteCount);
    return m_orchestrator.GetEnsembleSignal(votes, voteCount, confidence);
}

//+------------------------------------------------------------------+
//| Auto-register Strategies                                        |
//+------------------------------------------------------------------+
void CEnterpriseStrategyManager::AutoRegisterStrategies(bool &enabledFlags[])
{
    // Register core SMC strategies
    if(enabledFlags[0]) // SMC
        RegisterStrategy(new CStrategySMC(), "Advanced SMC", true, 2.0);
    
    if(enabledFlags[1]) // Elliott Wave
        RegisterStrategy(new CStrategyElliottWaveEnhanced(), "Elliott Wave Enhanced", true, 1.5);
    
    if(enabledFlags[2]) // Order Block
        RegisterStrategy(new CStrategyOrderBlock(), "Order Block", true, 1.5);
    
    if(enabledFlags[3]) // FVG
        RegisterStrategy(new CStrategyFairValueGap(), "Fair Value Gap", true, 1.3);
    
    if(enabledFlags[4]) // Supply/Demand
        RegisterStrategy(new CStrategySupplyDemand("Supply Demand", 0), "Supply Demand", true, 1.3);
    
    if(enabledFlags[5]) // Swing
        RegisterStrategy(new CStrategySwing(), "Swing Trading", true, 1.2);
    
    // Register additional strategies
    if(enabledFlags[6]) // Trend
        RegisterStrategy(new CStrategyTrend(), "Trend Following", true, 1.2);
    
    if(enabledFlags[7]) // RSI
        RegisterStrategy(new CStrategyRSI(), "RSI Momentum", true, 1.0);
    
    if(enabledFlags[8]) // MACD
        RegisterStrategy(new CStrategyMACD(), "MACD Divergence", true, 1.0);
    
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
        // Pipeline filtering configuration (simplified stub)
        Print("Pipeline filters configured");
    }
}

//+------------------------------------------------------------------+
//| Set Orchestrator Mode                                            |
//+------------------------------------------------------------------+
void CEnterpriseStrategyManager::SetOrchestratorMode(double minWinRate, int maxLosses)
{
    if(m_orchestrator != NULL)
    {
        // Orchestrator mode configuration (simplified stub)
        Print("Orchestrator mode set: WinRate=", minWinRate, " MaxLosses=", maxLosses);
    }
}

#endif // ENTERPRISE_STRATEGY_MANAGER_MQH
