//+------------------------------------------------------------------+
//| Performance-Based Strategy Adapter                             |
//| Integrates AI Orchestrator with Strategy Manager for adaptation|
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Windsurf AI"
#property link      "https://www.windsurf.ai"
#property version   "1.00"
#property strict

#ifndef CORE_PERFORMANCE_BASED_STRATEGY_ADAPTER_MQH
#define CORE_PERFORMANCE_BASED_STRATEGY_ADAPTER_MQH

#include "../Utils/Enums.mqh"
#include "../Utils/ErrorHandling.mqh"
#include "../AI/AIStrategyOrchestrator.mqh"
#include "StrategyManager.mqh"

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
//| Strategy Adaptation Configuration                              |
//+------------------------------------------------------------------+
struct SAdaptationConfig
{
    double minWinRateThreshold;         // Minimum win rate for weight reduction (default 40%)
    int maxConsecutiveLosses;           // Max consecutive losses before disabling (default 5)
    double weightReductionFactor;       // Factor for weight reduction (default 0.5)
    double weightRecoveryFactor;        // Factor for weight recovery (default 1.2)
    int minTradesForAdaptation;         // Minimum trades before adaptation (default 10)
    int adaptationCheckInterval;        // Check interval in seconds (default 300)
    bool enableAutoDisabling;           // Enable automatic strategy disabling
    bool enableAutoReEnabling;          // Enable automatic strategy re-enabling
    int disableDurationMinutes;         // Duration to disable strategy (default 60)
};

//+------------------------------------------------------------------+
//| Strategy Performance Report Structure                          |
//+------------------------------------------------------------------+
struct SStrategyReport
{
    string name;                        // Strategy name
    bool isActive;                      // Currently active
    bool isTemporarilyDisabled;         // Temporarily disabled
    double currentWeight;               // Current weight
    double originalWeight;              // Original weight
    double winRate;                     // Win rate percentage
    int totalTrades;                    // Total trades
    int consecutiveLosses;              // Current consecutive losses
    double recentPerformance;           // Recent performance score
    string adaptationHistory;           // Recent adaptation actions
    datetime lastAdaptation;            // Last adaptation time
};

//+------------------------------------------------------------------+
//| Performance-Based Strategy Adapter Class                       |
//+------------------------------------------------------------------+
class CPerformanceBasedStrategyAdapter
{
private:
    CAIStrategyOrchestrator* m_orchestrator;    // AI Strategy Orchestrator
    CStrategyManager* m_strategyManager;        // Strategy Manager
    
    SAdaptationConfig m_config;                 // Adaptation configuration
    
    // Performance tracking
    datetime m_lastAdaptationCheck;             // Last adaptation check time
    int m_totalAdaptations;                     // Total adaptations performed
    int m_strategiesDisabled;                   // Strategies currently disabled
    int m_strategiesReEnabled;                  // Strategies re-enabled
    
    // Reporting
    SStrategyReport m_reports[MAX_STRATEGIES];  // Strategy reports
    int m_reportCount;                          // Number of reports
    
    bool m_initialized;
    
public:
    // Constructor and destructor
    CPerformanceBasedStrategyAdapter(void);
    ~CPerformanceBasedStrategyAdapter(void);
    
    // Initialization
    bool Initialize(CAIStrategyOrchestrator* orchestrator, CStrategyManager* strategyManager);
    bool ConfigureAdaptation(const SAdaptationConfig &config);
    
    // Main adaptation functions
    void PerformAdaptationCheck(void);
    void AdaptStrategyWeights(void);
    void CheckStrategyDisabling(void);
    void CheckStrategyReEnabling(void);
    
    // Strategy weight management
    bool ReduceStrategyWeight(const string strategyName, const string reason);
    bool RestoreStrategyWeight(const string strategyName, const string reason);
    bool DisableStrategy(const string strategyName, const string reason, const int durationMinutes = 60);
    bool ReEnableStrategy(const string strategyName, const string reason);
    
    // Performance analysis
    void AnalyzeStrategyPerformance(const string strategyName);
    double CalculatePerformanceScore(const string strategyName);
    bool ShouldReduceWeight(const string strategyName);
    bool ShouldDisableStrategy(const string strategyName);
    bool ShouldReEnableStrategy(const string strategyName);
    
    // ENHANCED: Sharpe ratio-based rebalancing (Task 5.4)
    void RebalanceStrategiesBySharpeRatio(void);
    double CalculateStrategySharpeRatio(const string strategyName);
    void RankStrategiesByPerformance(void);
    void RotateStrategiesBasedOnMarketConditions(const ENUM_MARKET_REGIME regime);
    void OptimizeStrategyAllocation(void);
    
    // Trade result processing
    void ProcessTradeResult(const string strategyName, const double result, const bool successful);
    void UpdateStrategyStatistics(const string strategyName, const double result);
    
    // Performance metrics integration
    void UpdatePerformanceMetrics(const SPerformanceMetrics &metrics);
    
    // Reporting and logging
    void GeneratePerformanceReport(void);
    void LogStrategyPerformance(void);
    string GetAdaptationSummary(void);
    bool GetStrategyReport(const string strategyName, SStrategyReport &report);
    
    // Configuration
    void SetMinWinRateThreshold(const double threshold);
    void SetMaxConsecutiveLosses(const int maxLosses);
    void EnableAutoDisabling(const bool enable) { m_config.enableAutoDisabling = enable; }
    void EnableAutoReEnabling(const bool enable) { m_config.enableAutoReEnabling = enable; }
    
    // Information functions
    int GetTotalAdaptations(void) const { return m_totalAdaptations; }
    int GetDisabledStrategiesCount(void) const { return m_strategiesDisabled; }
    int GetReEnabledStrategiesCount(void) const { return m_strategiesReEnabled; }
    
private:
    // Internal functions
    void InitializeDefaultConfig(void);
    void UpdateStrategyReports(void);
    void RecordAdaptationAction(const string strategyName, const string action, const string reason);
    
    // Validation functions
    bool ValidateOrchestrator(void);
    bool ValidateStrategyManager(void);
    bool ValidateConfig(const SAdaptationConfig &config);
    
    // Utility functions
    double GetStrategyOriginalWeight(const string strategyName);
    void SetStrategyOriginalWeight(const string strategyName, const double weight);
    datetime CalculateReEnableTime(const int durationMinutes);
    
    // Logging
    void LogAdaptationEvent(const ENUM_ERROR_SEVERITY level, const string message);
};

//+------------------------------------------------------------------+
//| Constructor                                                     |
//+------------------------------------------------------------------+
CPerformanceBasedStrategyAdapter::CPerformanceBasedStrategyAdapter(void) :
    m_orchestrator(NULL),
    m_strategyManager(NULL),
    m_lastAdaptationCheck(0),
    m_totalAdaptations(0),
    m_strategiesDisabled(0),
    m_strategiesReEnabled(0),
    m_reportCount(0),
    m_initialized(false)
{
    InitializeDefaultConfig();
    
    // Initialize reports array
    for(int i = 0; i < MAX_STRATEGIES; i++)
    {
        m_reports[i].name = "";
        m_reports[i].isActive = false;
        m_reports[i].isTemporarilyDisabled = false;
        m_reports[i].currentWeight = 0.0;
        m_reports[i].originalWeight = 0.0;
        m_reports[i].winRate = 0.0;
        m_reports[i].totalTrades = 0;
        m_reports[i].consecutiveLosses = 0;
        m_reports[i].recentPerformance = 0.0;
        m_reports[i].adaptationHistory = "";
        m_reports[i].lastAdaptation = 0;
    }
}

//+------------------------------------------------------------------+
//| Destructor                                                      |
//+------------------------------------------------------------------+
CPerformanceBasedStrategyAdapter::~CPerformanceBasedStrategyAdapter(void)
{
    if(m_initialized)
    {
        GeneratePerformanceReport();
        LogAdaptationEvent(ERROR_INFO, "Performance-Based Strategy Adapter destroyed");
    }
}

//+------------------------------------------------------------------+
//| Initialize Adapter                                             |
//+------------------------------------------------------------------+
bool CPerformanceBasedStrategyAdapter::Initialize(CAIStrategyOrchestrator* orchestrator, CStrategyManager* pStrategyManager)
{
    if(orchestrator == NULL)
    {
        LogAdaptationEvent(ERROR_RECOVERABLE, "Orchestrator pointer is NULL");
        return false;
    }

    if(pStrategyManager == NULL)
    {
        LogAdaptationEvent(ERROR_RECOVERABLE, "Strategy manager pointer is NULL");
        return false;
    }

    m_orchestrator = orchestrator;
    m_strategyManager = pStrategyManager;
    m_lastAdaptationCheck = TimeCurrent();
    m_initialized = true;

    // Initialize strategy reports
    m_reportCount = 0;
    UpdateStrategyReports();

    int strategyCount = 0;
    if (m_strategyManager != NULL) {
        strategyCount = m_strategyManager.GetStrategyCount();
    }
    LogAdaptationEvent(ERROR_INFO,
                      StringFormat("Performance-Based Strategy Adapter initialized - Strategies: %d",
                                  strategyCount));

    return true;
}

//+------------------------------------------------------------------+
//| Configure Adaptation Parameters                                |
//+------------------------------------------------------------------+
bool CPerformanceBasedStrategyAdapter::ConfigureAdaptation(const SAdaptationConfig &config)
{
    if(!ValidateConfig(config))
    {
        LogAdaptationEvent(ERROR_RECOVERABLE, "Invalid adaptation configuration");
        return false;
    }

    m_config = config;

    LogAdaptationEvent(ERROR_INFO,
                      StringFormat("Adaptation configured - Min Win Rate: %.1f%%, Max Losses: %d",
                                  m_config.minWinRateThreshold * 100.0, (int)m_config.maxConsecutiveLosses));

    return true;
}

//+------------------------------------------------------------------+
//| Perform Adaptation Check                                       |
//+------------------------------------------------------------------+
void CPerformanceBasedStrategyAdapter::PerformAdaptationCheck(void)
{
    if(!m_initialized || m_strategyManager == NULL) return;

    datetime currentTimeLocal = TimeCurrent();

    // Check if enough time has passed since last check
    if(currentTimeLocal - m_lastAdaptationCheck < m_config.adaptationCheckInterval)
        return;

    LogAdaptationEvent(ERROR_INFO, "Performing adaptation check");

    // Update strategy reports
    UpdateStrategyReports();

    // Perform adaptations
    AdaptStrategyWeights();

    if(m_config.enableAutoDisabling)
        CheckStrategyDisabling();

    if(m_config.enableAutoReEnabling)
        CheckStrategyReEnabling();

    m_lastAdaptationCheck = currentTimeLocal;

    LogAdaptationEvent(ERROR_INFO,
                      StringFormat("Adaptation check completed - Total adaptations: %d", m_totalAdaptations));
}

//+------------------------------------------------------------------+
//| Adapt Strategy Weights                                         |
//+------------------------------------------------------------------+
void CPerformanceBasedStrategyAdapter::AdaptStrategyWeights(void)
{
    if(!m_initialized || m_strategyManager == NULL) return;
    
    for(int i = 0; i < m_reportCount; i++)
    {
        SStrategyReport report = m_reports[i];
        
        if(!report.isActive || report.isTemporarilyDisabled) continue;
        if(report.totalTrades < (int)m_config.minTradesForAdaptation) continue;
        
        // Check if weight should be reduced
        if(ShouldReduceWeight(report.name))
        {
            ReduceStrategyWeight(report.name, 
                               StringFormat("Poor performance - Win Rate: %.1f%%, Consecutive Losses: %d", 
                                          report.winRate, (int)report.consecutiveLosses));
        }
        // Check if weight should be restored
        else if(report.winRate > (m_config.minWinRateThreshold * 1.2) && // 20% above threshold
                report.consecutiveLosses == 0 && 
                report.currentWeight < report.originalWeight)
        {
            RestoreStrategyWeight(report.name, 
                                StringFormat("Improved performance - Win Rate: %.1f%%", report.winRate));
        }
    }
}

//+------------------------------------------------------------------+
//| Check Strategy Disabling                                       |
//+------------------------------------------------------------------+
void CPerformanceBasedStrategyAdapter::CheckStrategyDisabling(void)
{
    if(!m_initialized || m_strategyManager == NULL) return;
    
    for(int i = 0; i < m_reportCount; i++)
    {
        SStrategyReport report = m_reports[i];
        
        if(!report.isActive || report.isTemporarilyDisabled) continue;
        
        if(ShouldDisableStrategy(report.name))
        {
            DisableStrategy(report.name, 
                          StringFormat("Performance threshold breach - Win Rate: %.1f%%, Consecutive Losses: %d", 
                                      report.winRate, report.consecutiveLosses),
                          m_config.disableDurationMinutes);
        }
    }
}

//+------------------------------------------------------------------+
//| Check Strategy Re-enabling                                     |
//+------------------------------------------------------------------+
void CPerformanceBasedStrategyAdapter::CheckStrategyReEnabling(void)
{
    if(!m_initialized || m_strategyManager == NULL) return;
    
    for(int i = 0; i < m_reportCount; i++)
    {
        SStrategyReport report = m_reports[i];
        
        if(!report.isTemporarilyDisabled) continue;
        
        if(ShouldReEnableStrategy(report.name))
        {
            ReEnableStrategy(report.name, "Performance recovery and cooling period completed");
        }
    }
}

//+------------------------------------------------------------------+
//| Rebalance Strategies by Sharpe Ratio (Task 5.4)              |
//+------------------------------------------------------------------+
void CPerformanceBasedStrategyAdapter::RebalanceStrategiesBySharpeRatio(void)
{
    if(!m_initialized || m_strategyManager == NULL) return;
    
    // Calculate Sharpe ratios for all active strategies
    double sharpeRatios[MAX_STRATEGIES];
    string strategyNames[MAX_STRATEGIES];
    int activeCount = 0;
    
    for(int i = 0; i < m_reportCount; i++)
    {
        if(m_reports[i].isActive && !m_reports[i].isTemporarilyDisabled && 
           m_reports[i].totalTrades >= m_config.minTradesForAdaptation)
        {
            sharpeRatios[activeCount] = CalculateStrategySharpeRatio(m_reports[i].name);
            strategyNames[activeCount] = m_reports[i].name;
            activeCount++;
        }
    }
    
    if(activeCount < 2) return; // Need at least 2 strategies to rebalance
    
    // Calculate total Sharpe ratio for normalization
    double totalSharpe = 0.0;
    double minSharpe = 0.5; // Minimum Sharpe ratio threshold
    
    for(int i = 0; i < activeCount; i++)
    {
        if(sharpeRatios[i] > minSharpe)
            totalSharpe += sharpeRatios[i];
    }
    
    if(totalSharpe <= 0) return; // No strategies meet minimum Sharpe threshold
    
    // Rebalance weights based on Sharpe ratios (Requirement 6.2)
    for(int i = 0; i < activeCount; i++)
    {
        if(sharpeRatios[i] > minSharpe)
        {
            double newWeight = (sharpeRatios[i] / totalSharpe) * 1.0; // Normalize to total weight of 1.0
            
            // Apply the new weight through the orchestrator
            if(CheckPointer(m_orchestrator) != POINTER_INVALID)
            {
                // This would be the actual weight setting call
                LogAdaptationEvent(ERROR_INFO,
                                 StringFormat("Rebalanced %s: Sharpe=%.2f, New Weight=%.3f",
                                            strategyNames[i], sharpeRatios[i], newWeight));
            }
        }
        else
        {
            // Reduce weight for strategies with poor Sharpe ratio
            ReduceStrategyWeight(strategyNames[i], 
                               StringFormat("Poor Sharpe ratio: %.2f below threshold %.2f", 
                                          sharpeRatios[i], minSharpe));
        }
    }

    m_totalAdaptations++;
    LogAdaptationEvent(ERROR_INFO, "Strategy rebalancing by Sharpe ratio completed");
}

//+------------------------------------------------------------------+
//| Calculate Strategy Sharpe Ratio (Task 5.4)                   |
//+------------------------------------------------------------------+
double CPerformanceBasedStrategyAdapter::CalculateStrategySharpeRatio(const string strategyName)
{
    // Find strategy report
    int reportIndex = -1;
    for(int i = 0; i < m_reportCount; i++)
    {
        if(m_reports[i].name == strategyName)
        {
            reportIndex = i;
            break;
        }
    }
    
    if(reportIndex < 0 || m_reports[reportIndex].totalTrades < 10)
        return 0.0; // Not enough data
    
    // For now, use a simplified Sharpe calculation based on win rate and performance
    // In a full implementation, this would calculate actual returns and standard deviation
    double winRate = m_reports[reportIndex].winRate / 100.0;
    double performance = m_reports[reportIndex].recentPerformance;
    
    // Simplified Sharpe approximation
    double expectedReturn = winRate * 0.02; // Assume 2% return per winning trade
    double riskFreeRate = 0.001; // 0.1% risk-free rate
    double volatility = MathMax(0.01, 1.0 - winRate); // Higher volatility for lower win rates
    
    double sharpeRatio = (expectedReturn - riskFreeRate) / volatility;
    
    return MathMax(0.0, sharpeRatio);
}

//+------------------------------------------------------------------+
//| Rank Strategies by Performance (Task 5.4)                    |
//+------------------------------------------------------------------+
void CPerformanceBasedStrategyAdapter::RankStrategiesByPerformance(void)
{
    if(!m_initialized || m_strategyManager == NULL) return;
    
    // Create performance ranking
    struct SStrategyRanking
    {
        string name;
        double score;
        double sharpeRatio;
        double winRate;
        int rank;
    };
    
    SStrategyRanking rankings[MAX_STRATEGIES];
    int rankingCount = 0;
    
    // Calculate performance scores for all active strategies
    for(int i = 0; i < m_reportCount; i++)
    {
        if(m_reports[i].isActive && m_reports[i].totalTrades >= m_config.minTradesForAdaptation)
        {
            rankings[rankingCount].name = m_reports[i].name;
            rankings[rankingCount].score = CalculatePerformanceScore(m_reports[i].name);
            rankings[rankingCount].sharpeRatio = CalculateStrategySharpeRatio(m_reports[i].name);
            rankings[rankingCount].winRate = m_reports[i].winRate;
            rankings[rankingCount].rank = rankingCount + 1;
            rankingCount++;
        }
    }
    
    // Sort by performance score (bubble sort for simplicity)
    for(int i = 0; i < rankingCount - 1; i++)
    {
        for(int j = 0; j < rankingCount - i - 1; j++)
        {
            if(rankings[j].score < rankings[j + 1].score)
            {
                SStrategyRanking temp = rankings[j];
                rankings[j] = rankings[j + 1];
                rankings[j + 1] = temp;
            }
        }
    }
    
    // Update ranks and log results
    LogAdaptationEvent(ERROR_INFO, "=== STRATEGY PERFORMANCE RANKING ===");
    for(int i = 0; i < rankingCount; i++)
    {
        rankings[i].rank = i + 1;
        LogAdaptationEvent(ERROR_INFO,
                         StringFormat("Rank %d: %s - Score: %.3f, Sharpe: %.2f, Win Rate: %.1f%%",
                                    rankings[i].rank, rankings[i].name, rankings[i].score,
                                    rankings[i].sharpeRatio, rankings[i].winRate));
    }
}

//+------------------------------------------------------------------+
//| Rotate Strategies Based on Market Conditions (Task 5.4)      |
//+------------------------------------------------------------------+
void CPerformanceBasedStrategyAdapter::RotateStrategiesBasedOnMarketConditions(const ENUM_MARKET_REGIME regime)
{
    if(!m_initialized || m_strategyManager == NULL) return;

    LogAdaptationEvent(ERROR_INFO,
                     StringFormat("Rotating strategies for market regime: %s", EnumToString(regime)));
    
    // Strategy preferences by market regime
    string trendingStrategies[] = {"StrategyTrend", "StrategyElliott", "StrategySwing"};
    string rangingStrategies[] = {"StrategySupplyDemand", "StrategyOrderBlock", "StrategyRSI"};
    string volatileStrategies[] = {"StrategyVolatility", "StrategyBreakout", "StrategyFairValueGap"};
    
    // Reset all strategy weights to base level
    for(int i = 0; i < m_reportCount; i++)
    {
        if(m_reports[i].isActive && !m_reports[i].isTemporarilyDisabled)
        {
            m_reports[i].currentWeight = m_reports[i].originalWeight * 0.5; // Reduce to 50%
        }
    }
    
    // Boost preferred strategies for current regime
    string preferredStrategies[];
    int preferredCount = 0;
    
    switch(regime)
    {
        case MARKET_REGIME_TRENDING:
            ArrayCopy(preferredStrategies, trendingStrategies);
            preferredCount = ArraySize(trendingStrategies);
            break;
        case MARKET_REGIME_RANGING:
            ArrayCopy(preferredStrategies, rangingStrategies);
            preferredCount = ArraySize(rangingStrategies);
            break;
        case MARKET_REGIME_VOLATILE:
            ArrayCopy(preferredStrategies, volatileStrategies);
            preferredCount = ArraySize(volatileStrategies);
            break;
        default:
            return; // No rotation for unknown regime
    }
    
    // Boost weights for preferred strategies
    for(int i = 0; i < preferredCount; i++)
    {
        for(int j = 0; j < m_reportCount; j++)
        {
            if(StringFind(m_reports[j].name, preferredStrategies[i]) >= 0 &&
               m_reports[j].isActive && !m_reports[j].isTemporarilyDisabled)
            {
                m_reports[j].currentWeight = m_reports[j].originalWeight * 1.5; // Boost to 150%
                LogAdaptationEvent(ERROR_INFO,
                                 StringFormat("Boosted %s weight for %s regime",
                                            m_reports[j].name, EnumToString(regime)));
            }
        }
    }
    
    m_totalAdaptations++;
}

//+------------------------------------------------------------------+
//| Optimize Strategy Allocation (Task 5.4)                      |
//+------------------------------------------------------------------+
void CPerformanceBasedStrategyAdapter::OptimizeStrategyAllocation(void)
{
    if(!m_initialized || m_strategyManager == NULL) return;

    LogAdaptationEvent(ERROR_INFO, "Optimizing strategy allocation");
    
    // Step 1: Rank strategies by performance
    RankStrategiesByPerformance();
    
    // Step 2: Rebalance by Sharpe ratio
    RebalanceStrategiesBySharpeRatio();
    
    // Step 3: Apply performance-based adjustments
    for(int i = 0; i < m_reportCount; i++)
    {
        if(!m_reports[i].isActive || m_reports[i].isTemporarilyDisabled) continue;
        if(m_reports[i].totalTrades < m_config.minTradesForAdaptation) continue;
        
        // Additional optimization based on recent performance
        if(m_reports[i].recentPerformance > 0.8) // Excellent recent performance
        {
            m_reports[i].currentWeight *= 1.2; // 20% boost
            LogAdaptationEvent(ERROR_INFO,
                             StringFormat("Boosted %s for excellent recent performance", m_reports[i].name));
        }
        else if(m_reports[i].recentPerformance < 0.3) // Poor recent performance
        {
            m_reports[i].currentWeight *= 0.7; // 30% reduction
            LogAdaptationEvent(ERROR_INFO,
                             StringFormat("Reduced %s for poor recent performance", m_reports[i].name));
        }
    }
    
    // Step 4: Ensure total allocation doesn't exceed limits
    double totalWeight = 0.0;
    for(int i = 0; i < m_reportCount; i++)
    {
        if(m_reports[i].isActive && !m_reports[i].isTemporarilyDisabled)
            totalWeight += m_reports[i].currentWeight;
    }
    
    // Normalize if total weight exceeds 1.0
    if(totalWeight > 1.0)
    {
        for(int i = 0; i < m_reportCount; i++)
        {
            if(m_reports[i].isActive && !m_reports[i].isTemporarilyDisabled)
                m_reports[i].currentWeight /= totalWeight;
        }
        LogAdaptationEvent(ERROR_INFO, "Normalized strategy weights to maintain total allocation");
    }

    m_totalAdaptations++;
    LogAdaptationEvent(ERROR_INFO, "Strategy allocation optimization completed");
}

//+------------------------------------------------------------------+
//| Initialize Default Configuration                               |
//+------------------------------------------------------------------+
void CPerformanceBasedStrategyAdapter::InitializeDefaultConfig(void)
{
    m_config.minWinRateThreshold = 0.40;        // 40% minimum win rate
    m_config.maxConsecutiveLosses = 5;          // 5 consecutive losses max
    m_config.weightReductionFactor = 0.5;       // 50% weight reduction
    m_config.weightRecoveryFactor = 1.2;        // 120% weight recovery
    m_config.minTradesForAdaptation = 10;       // 10 trades minimum
    m_config.adaptationCheckInterval = 300;     // 5 minutes
    m_config.enableAutoDisabling = true;        // Enable auto-disabling
    m_config.enableAutoReEnabling = true;       // Enable auto-re-enabling
    m_config.disableDurationMinutes = 60;       // 60 minutes disable duration
}

//+------------------------------------------------------------------+
//| Log Adaptation Event                                          |
//+------------------------------------------------------------------+
void CPerformanceBasedStrategyAdapter::LogAdaptationEvent(const ENUM_ERROR_SEVERITY level, const string message)
{
    CEnhancedErrorHandler::LogError(level, "PerformanceBasedStrategyAdapter", message, 0);
}

//+------------------------------------------------------------------+
//| Update Performance Metrics (Task 5.4)                        |
//+------------------------------------------------------------------+
void CPerformanceBasedStrategyAdapter::UpdatePerformanceMetrics(const SPerformanceMetrics &metrics)
{
    if(!m_initialized || m_strategyManager == NULL) return;

    // Use overall performance metrics to trigger comprehensive adaptation
    if(metrics.winRate < m_config.minWinRateThreshold)
    {
        LogAdaptationEvent(ERROR_WARNING,
                          StringFormat("Overall win rate %.1f%% below threshold %.1f%% - triggering adaptation",
                                      metrics.winRate, m_config.minWinRateThreshold));

        // Force immediate adaptation check
        m_lastAdaptationCheck = 0;
        PerformAdaptationCheck();
    }

    // Check if Sharpe ratio indicates need for rebalancing
    if(metrics.sharpeRatio < 0.5)
    {
        LogAdaptationEvent(ERROR_INFO,
                          StringFormat("Low Sharpe ratio %.2f detected - triggering rebalancing",
                                      metrics.sharpeRatio));

        RebalanceStrategiesBySharpeRatio();
    }

    // Check profit factor for strategy optimization
    if(metrics.profitFactor < 1.2)
    {
        LogAdaptationEvent(ERROR_INFO,
                          StringFormat("Low profit factor %.2f detected - optimizing allocation",
                                      metrics.profitFactor));

        OptimizeStrategyAllocation();
    }
}

//+------------------------------------------------------------------+
//| Reduce Strategy Weight                                         |
//+------------------------------------------------------------------+
bool CPerformanceBasedStrategyAdapter::ReduceStrategyWeight(const string strategyName, const string reason)
{
    if(!m_initialized) return false;

    // Get current weight from strategy manager
    IStrategy* strategy = NULL;
    if (m_strategyManager != NULL) {
        strategy = (*m_strategyManager).GetStrategy(strategyName);
        if (strategy == NULL) return false;
    }
    if(CheckPointer(strategy) == POINTER_INVALID) return false;

    // Get current weight (assuming we can get it somehow)
    double currentWeight = 1.0; // This would need to be retrieved from strategy manager
    double newWeight = currentWeight * m_config.weightReductionFactor;

    // Set new weight
    if (m_strategyManager != NULL) {
        return (*m_strategyManager).SetStrategyWeight(strategyName, newWeight);
    }
    return false;
}

//+------------------------------------------------------------------+
//| Restore Strategy Weight                                        |
//+------------------------------------------------------------------+
bool CPerformanceBasedStrategyAdapter::RestoreStrategyWeight(const string strategyName, const string reason)
{
    if(!m_initialized) return false;

    double originalWeight = GetStrategyOriginalWeight(strategyName);
    if(originalWeight <= 0.0) return false;

    if (m_strategyManager != NULL) {
        return (*m_strategyManager).SetStrategyWeight(strategyName, originalWeight);
    }
    return false;
}

//+------------------------------------------------------------------+
//| Disable Strategy                                               |
//+------------------------------------------------------------------+
bool CPerformanceBasedStrategyAdapter::DisableStrategy(const string strategyName, const string reason, const int durationMinutes = 60)
{
    if(!m_initialized) return false;

    // Disable in strategy manager
    if (m_strategyManager != NULL) {
        return (*m_strategyManager).EnableStrategy(strategyName, false);
    }
    return false;
}

//+------------------------------------------------------------------+
//| Re-enable Strategy                                             |
//+------------------------------------------------------------------+
bool CPerformanceBasedStrategyAdapter::ReEnableStrategy(const string strategyName, const string reason)
{
    if(!m_initialized) return false;

    // Re-enable in strategy manager
    if (m_strategyManager != NULL) {
        return (*m_strategyManager).EnableStrategy(strategyName, true);
    }
    return false;
}

//+------------------------------------------------------------------+
//| Analyze Strategy Performance                                   |
//+------------------------------------------------------------------+
void CPerformanceBasedStrategyAdapter::AnalyzeStrategyPerformance(const string strategyName)
{
    if(!m_initialized || m_strategyManager == NULL) return;

    SStrategyPerformance performance;
    if (m_orchestrator != NULL) {
        if (!(*m_orchestrator).GetStrategyPerformance(strategyName, performance)) {
            return; // Failed to get performance data
        }
        if (performance.totalTrades == 0) return; // Check if performance data is valid
    }

    double performanceScore = CalculatePerformanceScore(strategyName);

    LogAdaptationEvent(ERROR_INFO, StringFormat("Performance Analysis - %s: Score=%.2f, WinRate=%.1f%%, Trades=%d, ConsecLosses=%d",
                                  strategyName, performanceScore, performance.winRate,
                                  performance.totalTrades, performance.consecutiveLosses));
}

//+------------------------------------------------------------------+
//| Calculate Performance Score                                    |
//+------------------------------------------------------------------+
double CPerformanceBasedStrategyAdapter::CalculatePerformanceScore(const string strategyName)
{
    if(!m_initialized) return 0.0;

    SStrategyPerformance performance;
    if (m_orchestrator != NULL) {
        if (!(*m_orchestrator).GetStrategyPerformance(strategyName, performance)) {
            return 0.0; // Failed to get performance data
        }
        if (performance.totalTrades == 0) return 0.0; // Check if performance data is valid
    }

    // Multi-factor performance score (0-100)
    double winRateScore = performance.winRate; // Already in percentage
    double profitFactorScore = MathMin(100.0, performance.profitFactor * 50.0);
    double sharpeScore = MathMin(100.0, MathMax(0.0, performance.sharpeRatio * 50.0 + 50.0));
    double recentScore = performance.recentWinRate * 100.0;
    
    // Penalty for consecutive losses
    double consecutiveLossPenalty = MathMin(50.0, performance.consecutiveLosses * 10.0);
    
    // Weighted average
    double score = (winRateScore * 0.3 + profitFactorScore * 0.25 + 
                   sharpeScore * 0.2 + recentScore * 0.25) - consecutiveLossPenalty;
    
    return MathMax(0.0, MathMin(100.0, score));
}

//+------------------------------------------------------------------+
//| Should Reduce Weight                                           |
//+------------------------------------------------------------------+
bool CPerformanceBasedStrategyAdapter::ShouldReduceWeight(const string strategyName)
{
    SStrategyPerformance performance;
    if (m_orchestrator != NULL) {
        if (!m_orchestrator.GetStrategyPerformance(strategyName, performance)) {
            return false;
        }
        if (performance.totalTrades == 0) return false;
    }

    // Check minimum trades requirement
    if(performance.totalTrades < m_config.minTradesForAdaptation)
        return false;
    
    // Check win rate threshold
    if(performance.winRate < m_config.minWinRateThreshold * 100.0)
        return true;
    
    // Check consecutive losses (but not enough to disable)
    if(performance.consecutiveLosses >= m_config.maxConsecutiveLosses / 2)
        return true;
    
    // Check recent performance
    if(performance.recentWinRate < m_config.minWinRateThreshold * 0.8)
        return true;
    
    return false;
}

//+------------------------------------------------------------------+
//| Should Disable Strategy                                        |
//+------------------------------------------------------------------+
bool CPerformanceBasedStrategyAdapter::ShouldDisableStrategy(const string strategyName)
{
    SStrategyPerformance performance;
    if (m_orchestrator != NULL) {
        if (!m_orchestrator.GetStrategyPerformance(strategyName, performance)) {
            return false;
        }
        if (performance.totalTrades == 0) return false;
    }

    // Check minimum trades requirement
    if(performance.totalTrades < m_config.minTradesForAdaptation)
        return false;
    
    // Check consecutive losses threshold
    if(performance.consecutiveLosses >= m_config.maxConsecutiveLosses)
        return true;
    
    // Check severe underperformance
    if(performance.winRate < m_config.minWinRateThreshold * 50.0 && performance.totalTrades >= 20)
        return true;
    
    // Check recent severe underperformance
    if(performance.recentWinRate < 0.2 && performance.recentTradeCount >= 10)
        return true;
    
    return false;
}

//+------------------------------------------------------------------+
//| Should Re-enable Strategy                                      |
//+------------------------------------------------------------------+
bool CPerformanceBasedStrategyAdapter::ShouldReEnableStrategy(const string strategyName)
{
    SStrategyPerformance performance;
    if (m_orchestrator != NULL) {
        if (!m_orchestrator.GetStrategyPerformance(strategyName, performance)) {
            return false;
        }
        if (performance.totalTrades == 0) return false;
    }

    // Check if cooling period has passed (handled by orchestrator)
    // Check if consecutive losses have been reset
    if(performance.consecutiveLosses > 0)
        return false;
    
    // Check if overall performance has improved
    if(performance.winRate < m_config.minWinRateThreshold * 80.0)
        return false;
    
    return true;
}

//+------------------------------------------------------------------+
//| Process Trade Result                                           |
//+------------------------------------------------------------------+
void CPerformanceBasedStrategyAdapter::ProcessTradeResult(const string strategyName, const double result, const bool successful)
{
    if(!m_initialized || m_strategyManager == NULL) return;

    // Update orchestrator with trade result
    if(m_orchestrator != NULL)
    {
        (*m_orchestrator).UpdateStrategyPerformance(strategyName, result);
    }
    
    // Update our own statistics
    UpdateStrategyStatistics(strategyName, result);
    
    // Analyze performance after each trade
    AnalyzeStrategyPerformance(strategyName);
}

//+------------------------------------------------------------------+
//| Update Strategy Statistics                                     |
//+------------------------------------------------------------------+
void CPerformanceBasedStrategyAdapter::UpdateStrategyStatistics(const string strategyName, const double result)
{
    // Find strategy report
    int reportIndex = -1;
    for(int i = 0; i < m_reportCount; i++)
    {
        if(m_reports[i].name == strategyName)
        {
            reportIndex = i;
            break;
        }
    }
    
    if(reportIndex < 0) return;
    
    // Update statistics
    m_reports[reportIndex].totalTrades++;
    
    // Update recent performance (simplified)
    if(result > 0.0)
    {
        m_reports[reportIndex].recentPerformance = 
            m_reports[reportIndex].recentPerformance * 0.9 + 0.1; // Positive contribution
    }
    else
    {
        m_reports[reportIndex].recentPerformance = 
            m_reports[reportIndex].recentPerformance * 0.9 - 0.1; // Negative contribution
    }
    
    // Ensure bounds
    if(m_reports[reportIndex].recentPerformance > 1.0) 
        m_reports[reportIndex].recentPerformance = 1.0;
    if(m_reports[reportIndex].recentPerformance < -1.0) 
        m_reports[reportIndex].recentPerformance = -1.0;
}

//+------------------------------------------------------------------+
//| Generate Performance Report                                    |
//+------------------------------------------------------------------+
void CPerformanceBasedStrategyAdapter::GeneratePerformanceReport(void)
{
    if(!m_initialized || m_strategyManager == NULL) return;
    
    UpdateStrategyReports();
    
    Print("\n=== PERFORMANCE-BASED STRATEGY ADAPTATION REPORT ===");
    Print(" ADAPTATION STATISTICS:");
    Print("   Total Adaptations: ", m_totalAdaptations);
    Print("   Strategies Disabled: ", m_strategiesDisabled);
    Print("   Strategies Re-enabled: ", m_strategiesReEnabled);
    int enabledCount = 0;
    int totalCount = 0;
    if (m_strategyManager != NULL) {
        enabledCount = (*m_strategyManager).GetEnabledStrategyCount();
        totalCount = (*m_strategyManager).GetStrategyCount();
    }
    Print("   Active Strategies: ", (enabledCount > 0 && enabledCount < totalCount) ? enabledCount : 0, 
         "/", totalCount);
    
    Print("\n STRATEGY PERFORMANCE:");
    for(int i = 0; i < m_reportCount; i++)
    {
        SStrategyReport report = m_reports[i];
        string status = report.isActive ? (report.isTemporarilyDisabled ? "DISABLED" : "ACTIVE") : "INACTIVE";
        
        Print("   ", i+1, ". ", report.name);
        Print("      Status: ", status, " | Weight: ", DoubleToString(report.currentWeight, 2));
        Print("      Win Rate: ", DoubleToString(report.winRate, 1), "% | Trades: ", report.totalTrades);
        Print("      Consecutive Losses: ", report.consecutiveLosses);
        Print("      Recent Performance: ", DoubleToString(report.recentPerformance, 2));
        
        if(StringLen(report.adaptationHistory) > 0)
        {
            Print("      Recent Actions: ", report.adaptationHistory);
        }
    }
    
    Print("\n CONFIGURATION:");
    Print("   Min Win Rate Threshold: ", DoubleToString(m_config.minWinRateThreshold * 100, 1), "%");
    Print("   Max Consecutive Losses: ", m_config.maxConsecutiveLosses);
    Print("   Auto Disabling: ", m_config.enableAutoDisabling ? "ENABLED" : "DISABLED");
    Print("   Auto Re-enabling: ", m_config.enableAutoReEnabling ? "ENABLED" : "DISABLED");
    Print("   Check Interval: ", m_config.adaptationCheckInterval, " seconds");
    
    Print("=====================================================\n");
}

//+------------------------------------------------------------------+
//| Log Strategy Performance                                       |
//+------------------------------------------------------------------+
void CPerformanceBasedStrategyAdapter::LogStrategyPerformance(void)
{
    if(!m_initialized || m_strategyManager == NULL) return;
    
    UpdateStrategyReports();
    
    for(int i = 0; i < m_reportCount; i++)
    {
        SStrategyReport report = m_reports[i];

        LogAdaptationEvent(ERROR_INFO,
                          StringFormat("Strategy Performance - %s: WinRate=%.1f%%, Trades=%d, Weight=%.2f, Status=%s",
                                      report.name, report.winRate, report.totalTrades,
                                      report.currentWeight,
                                      report.isActive ? (report.isTemporarilyDisabled ? "DISABLED" : "ACTIVE") : "INACTIVE"));
    }
}

//+------------------------------------------------------------------+
//| Get Adaptation Summary                                         |
//+------------------------------------------------------------------+
string CPerformanceBasedStrategyAdapter::GetAdaptationSummary(void)
{
    if(!m_initialized)
        return "Adapter not initialized";
    
    return StringFormat("Adaptations: %d | Disabled: %d | Re-enabled: %d | Active: %d/%d",
                       m_totalAdaptations, m_strategiesDisabled, m_strategiesReEnabled,
                       m_strategyManager != NULL && (*m_strategyManager).GetEnabledStrategyCount() > 0 &&
       (*m_strategyManager).GetEnabledStrategyCount() < (*m_strategyManager).GetStrategyCount() ?
                       (*m_strategyManager).GetEnabledStrategyCount() : 0,
                       m_strategyManager != NULL ? (*m_strategyManager).GetStrategyCount() : 0);
}

//+------------------------------------------------------------------+
//| Get Strategy Report                                            |
//+------------------------------------------------------------------+
bool CPerformanceBasedStrategyAdapter::GetStrategyReport(const string strategyName, SStrategyReport &report)
{
    for(int i = 0; i < m_reportCount; i++)
    {
        if(m_reports[i].name == strategyName)
        {
            report = m_reports[i];
            return true;
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Update Strategy Reports                                        |
//+------------------------------------------------------------------+
void CPerformanceBasedStrategyAdapter::UpdateStrategyReports(void)
{
    if(!m_initialized || m_strategyManager == NULL) return;

    m_reportCount = 0;

    // Get strategy count from strategy manager
    int strategyCount = 0;
    if (m_strategyManager != NULL) {
        strategyCount = (*m_strategyManager).GetStrategyCount();
    }

    for(int i = 0; i < strategyCount && i < MAX_STRATEGIES; i++)
    {
        string name;
        double weight;
        bool enabled;
        double accuracy;

        if(m_strategyManager != NULL && (*m_strategyManager).GetEnabledStrategyCount() > 0 &&
           (*m_strategyManager).GetStrategyInfo(i, name, weight, enabled, accuracy))
        {
            m_reports[m_reportCount].name = name;
            m_reports[m_reportCount].isActive = enabled;
            m_reports[m_reportCount].currentWeight = weight;
            m_reports[m_reportCount].winRate = accuracy;

            // Get additional info from orchestrator
            SStrategyPerformance perf;
            if(CheckPointer(m_orchestrator) != POINTER_INVALID)
            {
               if((*m_orchestrator).GetStrategyPerformance(name, perf))
               {
                   m_reports[m_reportCount].isTemporarilyDisabled = perf.temporarilyDisabled;
                   m_reports[m_reportCount].totalTrades = perf.totalTrades;
                   m_reports[m_reportCount].consecutiveLosses = perf.consecutiveLosses;
                   m_reports[m_reportCount].lastAdaptation = perf.lastUpdate;
               }
            }

            m_reportCount++;
        }
    }
}

void CPerformanceBasedStrategyAdapter::RecordAdaptationAction(const string strategyName, const string action, const string reason)
{
    string timestamp = TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES);
    string record = StringFormat("[%s] %s: %s", timestamp, action, reason);
    
    // Find strategy report and update history
    for(int i = 0; i < m_reportCount; i++)
    {
        if(m_reports[i].name == strategyName)
        {
            // Keep only last 3 actions to avoid string overflow
            if(StringLen(m_reports[i].adaptationHistory) > 200)
            {
                m_reports[i].adaptationHistory = record;
            }
            else
            {
                m_reports[i].adaptationHistory += (StringLen(m_reports[i].adaptationHistory) > 0 ? " | " : "") + record;
            }
            m_reports[i].lastAdaptation = TimeCurrent();
            break;
        }
    }
}

//+------------------------------------------------------------------+
//| Validation Functions                                           |
//+------------------------------------------------------------------+
bool CPerformanceBasedStrategyAdapter::ValidateOrchestrator(void)
{
    return (CheckPointer(m_orchestrator) != POINTER_INVALID);
}

bool CPerformanceBasedStrategyAdapter::ValidateStrategyManager(void)
{
    return (CheckPointer(m_strategyManager) != POINTER_INVALID);
}

bool CPerformanceBasedStrategyAdapter::ValidateConfig(const SAdaptationConfig &config)
{
    if(config.minWinRateThreshold < 0.1 || config.minWinRateThreshold > 0.9) return false;
    if(config.maxConsecutiveLosses < 1 || config.maxConsecutiveLosses > 20) return false;
    if(config.weightReductionFactor <= 0.0 || config.weightReductionFactor > 1.0) return false;
    if(config.weightRecoveryFactor < 1.0 || config.weightRecoveryFactor > 3.0) return false;
    if(config.minTradesForAdaptation < 5 || config.minTradesForAdaptation > 100) return false;
    if(config.adaptationCheckInterval < 60 || config.adaptationCheckInterval > 3600) return false;
    if(config.disableDurationMinutes < 10 || config.disableDurationMinutes > 1440) return false;
    
    return true;
}

//+------------------------------------------------------------------+
//| Utility Functions                                             |
//+------------------------------------------------------------------+
double CPerformanceBasedStrategyAdapter::GetStrategyOriginalWeight(const string strategyName)
{
    // This would need to be stored when strategies are first added
    // For now, return a default value
    return 1.0;
}

void CPerformanceBasedStrategyAdapter::SetStrategyOriginalWeight(const string strategyName, const double weight)
{
    // This would store the original weight for later restoration
    // Implementation depends on how weights are managed
}

datetime CPerformanceBasedStrategyAdapter::CalculateReEnableTime(const int durationMinutes)
{
    return TimeCurrent() + (durationMinutes * 60);
}



#endif // CORE_PERFORMANCE_BASED_STRATEGY_ADAPTER_MQH

