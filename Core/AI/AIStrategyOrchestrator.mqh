//+------------------------------------------------------------------+
//| AI Strategy Orchestrator                                        |
//| Intelligent strategy management with performance-based adaptation|
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Windsurf AI"
#property link      "https://www.windsurf.ai"
#property version   "1.00"
#property strict

#ifndef CORE_AI_STRATEGY_ORCHESTRATOR_MQH
#define CORE_AI_STRATEGY_ORCHESTRATOR_MQH

#include "../Utils/Enums.mqh"
#include "../Utils/ErrorHandling.mqh"
#include "../../Interfaces/IStrategy.mqh"
#include "../Signals/SignalDiagnostics.mqh"
#include "../Signals/TimeframeConsistency.mqh"
#include "../Signals/HedgingProtection.mqh"

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
//| Strategy Performance Tracking Structure                        |
//+------------------------------------------------------------------+
struct SStrategyPerformance
{
    string name;                    // Strategy name
    double weight;                  // Current weight
    bool enabled;                   // Strategy enabled flag
    
    // Performance metrics (20-trade rolling window)
    int totalTrades;                // Total trades executed
    int winningTrades;              // Winning trades count
    double winRate;                 // Win rate percentage
    double avgProfit;               // Average profit per trade
    double avgLoss;                 // Average loss per trade
    double profitFactor;            // Profit factor
    double sharpeRatio;             // Sharpe ratio
    
    // Recent performance tracking
    double recentTrades[20];        // Last 20 trade results
    int recentTradeIndex;           // Current index in circular buffer
    int recentTradeCount;           // Number of trades in buffer
    double recentWinRate;           // Recent win rate
    
    // Consecutive performance tracking
    int consecutiveLosses;          // Current consecutive losses
    int maxConsecutiveLosses;       // Maximum consecutive losses
    int consecutiveWins;            // Current consecutive wins
    
    // Adaptation flags
    bool temporarilyDisabled;       // Temporarily disabled flag
    datetime disabledUntil;         // Re-enable time
    datetime lastUpdate;            // Last performance update
    
    // Default constructor
    SStrategyPerformance()
    {
        name = "";
        weight = 1.0;
        enabled = true;
        totalTrades = 0;
        winningTrades = 0;
        winRate = 0.0;
        avgProfit = 0.0;
        avgLoss = 0.0;
        profitFactor = 0.0;
        sharpeRatio = 0.0;
        recentTradeIndex = 0;
        recentTradeCount = 0;
        recentWinRate = 0.0;
        consecutiveLosses = 0;
        maxConsecutiveLosses = 0;
        consecutiveWins = 0;
        temporarilyDisabled = false;
        disabledUntil = 0;
        lastUpdate = 0;
        ArrayInitialize(recentTrades, 0.0);
    }
    
    // Copy constructor
    SStrategyPerformance(const SStrategyPerformance &other)
    {
        this.name = other.name;
        this.weight = other.weight;
        this.enabled = other.enabled;
        this.totalTrades = other.totalTrades;
        this.winningTrades = other.winningTrades;
        this.winRate = other.winRate;
        this.avgProfit = other.avgProfit;
        this.avgLoss = other.avgLoss;
        this.profitFactor = other.profitFactor;
        this.sharpeRatio = other.sharpeRatio;
        this.recentTradeIndex = other.recentTradeIndex;
        this.recentTradeCount = other.recentTradeCount;
        this.recentWinRate = other.recentWinRate;
        this.consecutiveLosses = other.consecutiveLosses;
        this.maxConsecutiveLosses = other.maxConsecutiveLosses;
        this.consecutiveWins = other.consecutiveWins;
        this.temporarilyDisabled = other.temporarilyDisabled;
        this.disabledUntil = other.disabledUntil;
        this.lastUpdate = other.lastUpdate;
        
        // Copy array elements
        for(int i = 0; i < 20; i++)
            this.recentTrades[i] = other.recentTrades[i];
    }
    
    // Note: Use default assignment semantics for structs in MQL5
    
    // Market regime performance
    double regimePerformance[5];    // Performance by market regime
    int regimeTrades[5];            // Trade count by regime
};

//+------------------------------------------------------------------+
//| Ensemble Voting Structure                                       |
//+------------------------------------------------------------------+
struct SEnsembleVote
{
    string strategyName;            // Strategy name
    ENUM_TRADE_SIGNAL signal;      // Strategy signal
    double confidence;              // Signal confidence
    double weight;                  // Strategy weight
    double adjustedWeight;          // Performance-adjusted weight
    ENUM_MARKET_REGIME regime;      // Current market regime
    double signalStrength;          // Signal strength (0-1)
    string reasoning;               // Strategy reasoning
    datetime timestamp;             // Vote timestamp
    bool isValid;                   // Vote validity flag
};

//+------------------------------------------------------------------+
//| Ensemble Decision Structure                                     |
//+------------------------------------------------------------------+
struct SEnsembleDecision
{
    ENUM_TRADE_SIGNAL finalSignal;  // Final ensemble decision
    double confidence;              // Final confidence
    int totalVotes;                 // Total votes received
    int validVotes;                 // Valid votes processed
    double consensusStrength;       // Consensus strength (0-1)
    string decisionReasoning;       // Decision reasoning
    datetime decisionTime;          // Decision timestamp
    
    // Vote breakdown
    int buyVotes;                   // Number of buy votes
    int sellVotes;                  // Number of sell votes
    int neutralVotes;               // Number of neutral votes
    double buyWeight;               // Total buy weight
    double sellWeight;              // Total sell weight
    
    // Performance tracking
    bool wasSuccessful;             // Track if decision was successful
    double actualOutcome;           // Actual trade outcome
    datetime outcomeTime;           // Outcome timestamp

    SEnsembleDecision()
    {
        finalSignal = TRADE_SIGNAL_NONE;
        confidence = 0.0;
        totalVotes = 0;
        validVotes = 0;
        consensusStrength = 0.0;
        decisionReasoning = "";
        decisionTime = 0;

        buyVotes = 0;
        sellVotes = 0;
        neutralVotes = 0;
        buyWeight = 0.0;
        sellWeight = 0.0;

        wasSuccessful = false;
        actualOutcome = 0.0;
        outcomeTime = 0;
    }

    SEnsembleDecision(const SEnsembleDecision &other)
    {
        finalSignal = other.finalSignal;
        confidence = other.confidence;
        totalVotes = other.totalVotes;
        validVotes = other.validVotes;
        consensusStrength = other.consensusStrength;
        decisionReasoning = other.decisionReasoning;
        decisionTime = other.decisionTime;

        buyVotes = other.buyVotes;
        sellVotes = other.sellVotes;
        neutralVotes = other.neutralVotes;
        buyWeight = other.buyWeight;
        sellWeight = other.sellWeight;

        wasSuccessful = other.wasSuccessful;
        actualOutcome = other.actualOutcome;
        outcomeTime = other.outcomeTime;
    }
};

//+------------------------------------------------------------------+
//| AI Strategy Orchestrator Class                                 |
//+------------------------------------------------------------------+
class CAIStrategyOrchestrator : public CEnhancedErrorHandler
{
private:
    SStrategyPerformance m_strategies[MAX_STRATEGIES];  // Strategy performance array
    int m_strategyCount;                                // Number of strategies
    
    // Configuration parameters
    double m_minWinRateThreshold;                       // Minimum win rate (default 40%)
    int m_maxConsecutiveLosses;                         // Max consecutive losses (default 5)
    double m_performanceDecayFactor;                    // Performance decay factor
    int m_rollingWindowSize;                            // Rolling window size (default 20)
    
    // Ensemble voting parameters
    double m_minVotingConfidence;                       // Minimum confidence for voting
    double m_consensusThreshold;                        // Consensus threshold for signals
    bool m_useConfidenceWeighting;                      // Use confidence-based weighting
    
    // Market regime integration
    ENUM_MARKET_REGIME m_currentRegime;                 // Current market regime
    double m_regimeConfidence;                          // Regime detection confidence
    
    // Performance tracking
    datetime m_lastUpdate;                              // Last orchestrator update
    int m_totalEnsembleSignals;                         // Total ensemble signals
    int m_successfulEnsembleSignals;                    // Successful ensemble signals
    
    // Enhanced ensemble tracking
    SEnsembleDecision m_recentDecisions[50];            // Recent ensemble decisions
    int m_decisionIndex;                                // Current decision index
    int m_decisionCount;                                // Total decisions made
    double m_ensembleAccuracyHistory[20];               // Accuracy history
    int m_accuracyIndex;                                // Accuracy index
    
    // Enhanced voting parameters for task 3.4
    double m_agreementBonus;                            // Confidence bonus for agreement
    double m_disagreementPenalty;                       // Confidence penalty for disagreement
    double m_regimeUncertaintyThreshold;                // Regime uncertainty threshold
    double m_highConfidenceThreshold;                   // High confidence threshold for uncertain regimes
    
    bool m_initialized;
    
    // Diagnostic systems
    CSignalDiagnostics* m_diagnostics;
    CTimeframeConsistency* m_tfConsistency;
    CHedgingProtection* m_hedgingProtection;
    
public:
    // Constructor and destructor
    CAIStrategyOrchestrator(void);
    ~CAIStrategyOrchestrator(void);
    
    // Initialization
    bool Initialize(const double minWinRate = 0.40, const int maxConsecutiveLosses = 5);
    
    // Strategy management
    bool AddStrategy(const string strategyName, const double initialWeight = 1.0);
    bool RemoveStrategy(const string strategyName);
    bool UpdateStrategyPerformance(const string strategyName, const double tradeResult);
    
    // Dynamic weight adjustment
    void UpdateStrategyWeights(void);
    bool UpdateStrategyWeight(const string strategyName, const double newWeight);
    double CalculatePerformanceAdjustedWeight(const int strategyIndex);
    void ApplyRegimeBasedAdjustments(ENUM_MARKET_REGIME regime, double regimeConfidence);
    
    // Strategy adaptation
    void CheckStrategyDisabling(void);
    void CheckStrategyReEnabling(void);
    bool ShouldDisableStrategy(const int strategyIndex);
    bool ShouldReEnableStrategy(const int strategyIndex);
    
    // Ensemble voting system
    ENUM_TRADE_SIGNAL GetEnsembleSignal(SEnsembleVote &votes[], int voteCount, double &confidence);
    SEnsembleDecision GetEnsembleDecision(SEnsembleVote &votes[], int voteCount);
    ENUM_TRADE_SIGNAL ProcessWeightedVoting(SEnsembleVote &votes[], int voteCount, double &confidence);
    ENUM_TRADE_SIGNAL ResolveTieBreaking(SEnsembleVote &votes[], int voteCount, double &confidence);
    ENUM_TRADE_SIGNAL ResolveAdvancedTieBreaking(SEnsembleVote &votes[], int voteCount, double &confidence);
    
    // Enhanced voting features
    bool ValidateVote(const SEnsembleVote &vote);
    double CalculateConsensusStrength(SEnsembleVote &votes[], int voteCount, ENUM_TRADE_SIGNAL signal);
    void LogEnsembleDecision(const SEnsembleDecision &decision);
    void UpdateEnsemblePerformance(const SEnsembleDecision &decision, double outcome);
    
    // Task 3.4 specific enhancements
    double CalculateAgreementLevel(SEnsembleVote &votes[], int voteCount, ENUM_TRADE_SIGNAL signal);
    double CalculateDisagreementLevel(SEnsembleVote &votes[], int voteCount);
    bool IsRegimeUncertain(void);
    void ApplyAgreementBonus(double &confidence, double agreementLevel);
    void ApplyDisagreementPenalty(double &confidence, double disagreementLevel);
    bool ShouldSkipDueToUncertainty(double confidence);
    void LogVotingDecisionReasoning(SEnsembleVote &votes[], int voteCount, ENUM_TRADE_SIGNAL finalSignal, double confidence);
    
    // Performance tracking
    void RecordEnsembleResult(const bool successful);
    double GetEnsembleAccuracy(void);
    void UpdateRecentPerformance(const int strategyIndex, const double result);
    
    // Information functions
    bool GetStrategyPerformance(const string strategyName, SStrategyPerformance &performance);
    int GetActiveStrategyCount(void);
    double GetAverageWinRate(void);
    string GetPerformanceSummary(void);
    string GetStrategyWeightsJSON(void);
    double GetEnsembleConfidence(void);
    
    // Configuration
    void SetMinWinRateThreshold(const double threshold) { m_minWinRateThreshold = threshold; }
    void SetMaxConsecutiveLosses(const int maxLosses) { m_maxConsecutiveLosses = maxLosses; }
    void SetCurrentRegime(ENUM_MARKET_REGIME regime, double confidence);
    ENUM_MARKET_REGIME GetCurrentMarketRegime(void) const { return m_currentRegime; }
    void SetMinConfidenceThreshold(double threshold) { m_minVotingConfidence = threshold; }
    
    // Task 3.4 configuration methods
    void SetAgreementBonus(const double bonus) { m_agreementBonus = MathMax(0.0, MathMin(0.5, bonus)); }
    void SetDisagreementPenalty(const double penalty) { m_disagreementPenalty = MathMax(0.0, MathMin(0.5, penalty)); }
    void SetRegimeUncertaintyThreshold(const double threshold) { m_regimeUncertaintyThreshold = MathMax(0.1, MathMin(0.9, threshold)); }
    void SetHighConfidenceThreshold(const double threshold) { m_highConfidenceThreshold = MathMax(0.5, MathMin(1.0, threshold)); }
    
    // Getters for configuration
    double GetAgreementBonus(void) const { return m_agreementBonus; }
    double GetDisagreementPenalty(void) const { return m_disagreementPenalty; }
    double GetRegimeUncertaintyThreshold(void) const { return m_regimeUncertaintyThreshold; }
    double GetHighConfidenceThreshold(void) const { return m_highConfidenceThreshold; }
    
    // Reporting and logging
    void PrintOrchestrationReport(void);
    void LogStrategyAdaptation(const string strategyName, const string action, const string reason);
    
private:
    // Internal functions
    int FindStrategyIndex(const string strategyName);
    void InitializeStrategyPerformance(const int index, const string name, const double weight);
    void CalculateStrategyMetrics(const int index);
    void UpdateRegimePerformance(const int index, ENUM_MARKET_REGIME regime, const double result);
    
    // Validation functions
    bool ValidateStrategyName(const string name);
    bool ValidateWeight(const double weight);
    bool ValidateWinRateThreshold(const double threshold);
    
    // Utility functions
    double CalculateRecentWinRate(const int index);
    double CalculateSharpeRatio(const int index);
    double GetRegimeMultiplier(ENUM_MARKET_REGIME regime, const int strategyIndex);
    
    // Logging
    void LogOrchestrationEvent(const ENUM_ERROR_SEVERITY level, const string message);
};

//+------------------------------------------------------------------+
//| Constructor                                                     |
//+------------------------------------------------------------------+
CAIStrategyOrchestrator::CAIStrategyOrchestrator(void) :
    m_strategyCount(0),
    m_minWinRateThreshold(0.40),
    m_maxConsecutiveLosses(5),
    m_performanceDecayFactor(0.95),
    m_rollingWindowSize(20),
    m_minVotingConfidence(0.5),
    m_consensusThreshold(0.6),
    m_useConfidenceWeighting(true),
    m_currentRegime(MARKET_REGIME_UNKNOWN),
    m_regimeConfidence(0.0),
    m_lastUpdate(0),
    m_totalEnsembleSignals(0),
    m_successfulEnsembleSignals(0),
    m_decisionIndex(0),
    m_decisionCount(0),
    m_accuracyIndex(0),
    m_agreementBonus(0.2),
    m_disagreementPenalty(0.15),
    m_regimeUncertaintyThreshold(0.6),
    m_highConfidenceThreshold(0.8),
    m_initialized(false),
    m_diagnostics(NULL),
    m_tfConsistency(NULL),
    m_hedgingProtection(NULL)
{
    // Initialize strategy performance array
    for(int i = 0; i < MAX_STRATEGIES; i++)
    {
        m_strategies[i].name = "";
        m_strategies[i].weight = 0.0;
        m_strategies[i].enabled = false;
        m_strategies[i].totalTrades = 0;
        m_strategies[i].winningTrades = 0;
        m_strategies[i].winRate = 0.0;
        m_strategies[i].avgProfit = 0.0;
        m_strategies[i].avgLoss = 0.0;
        m_strategies[i].profitFactor = 0.0;
        m_strategies[i].sharpeRatio = 0.0;
        m_strategies[i].recentTradeIndex = 0;
        m_strategies[i].recentTradeCount = 0;
        m_strategies[i].recentWinRate = 0.0;
        m_strategies[i].consecutiveLosses = 0;
        m_strategies[i].maxConsecutiveLosses = 0;
        m_strategies[i].consecutiveWins = 0;
        m_strategies[i].temporarilyDisabled = false;
        m_strategies[i].disabledUntil = 0;
        m_strategies[i].lastUpdate = 0;
        
        // Initialize recent trades array
        for(int j = 0; j < 20; j++)
        {
            m_strategies[i].recentTrades[j] = 0.0;
        }
        
        // Initialize regime performance
        for(int k = 0; k < 5; k++)
        {
            m_strategies[i].regimePerformance[k] = 0.0;
            m_strategies[i].regimeTrades[k] = 0;
        }
    }
}

//+------------------------------------------------------------------+
//| Destructor                                                      |
//+------------------------------------------------------------------+
CAIStrategyOrchestrator::~CAIStrategyOrchestrator(void)
{
    if(m_initialized)
    {
        PrintOrchestrationReport();
        LogOrchestrationEvent(ERROR_INFO, "AI Strategy Orchestrator destroyed");
    }
    
    if(m_diagnostics != NULL)
    {
        delete m_diagnostics;
        m_diagnostics = NULL;
    }
    
    if(m_tfConsistency != NULL)
    {
        delete m_tfConsistency;
        m_tfConsistency = NULL;
    }
    
    if(m_hedgingProtection != NULL)
    {
        delete m_hedgingProtection;
        m_hedgingProtection = NULL;
    }
}

//+------------------------------------------------------------------+
//| Initialize Orchestrator                                         |
//+------------------------------------------------------------------+
bool CAIStrategyOrchestrator::Initialize(const double minWinRate = 0.40, const int maxConsecutiveLosses = 5)
{
    if(!ValidateWinRateThreshold(minWinRate))
    {
        LogOrchestrationEvent(ERROR_RECOVERABLE, "Invalid minimum win rate threshold");
        return false;
    }
    
    if(maxConsecutiveLosses < 1 || maxConsecutiveLosses > 20)
    {
        LogOrchestrationEvent(ERROR_RECOVERABLE, "Invalid maximum consecutive losses value");
        return false;
    }
    
    m_minWinRateThreshold = minWinRate;
    m_maxConsecutiveLosses = maxConsecutiveLosses;
    m_initialized = true;
    m_lastUpdate = TimeCurrent();
    
    // Initialize diagnostic systems
    m_diagnostics = new CSignalDiagnostics();
    if(m_diagnostics != NULL)
        m_diagnostics.Initialize(1000, 3);
    
    m_tfConsistency = new CTimeframeConsistency();
    if(m_tfConsistency != NULL)
        m_tfConsistency.Initialize(CONFLICT_RES_WEIGHTED, 0.6, false);
    
    m_hedgingProtection = new CHedgingProtection();
    if(m_hedgingProtection != NULL)
        m_hedgingProtection.Initialize(HEDGING_MODE_PREVENT, false);
    
    LogOrchestrationEvent(ERROR_INFO, 
                         StringFormat("AI Strategy Orchestrator initialized - Min Win Rate: %.1f%%, Max Consecutive Losses: %d", 
                                     m_minWinRateThreshold * 100, m_maxConsecutiveLosses));
    
    return true;
}

//+------------------------------------------------------------------+
//| Add Strategy to Orchestrator                                   |
//+------------------------------------------------------------------+
bool CAIStrategyOrchestrator::AddStrategy(const string strategyName, const double initialWeight = 1.0)
{
    if(!m_initialized)
    {
        LogOrchestrationEvent(ERROR_RECOVERABLE, "Orchestrator not initialized");
        return false;
    }
    
    if(!ValidateStrategyName(strategyName))
    {
        LogOrchestrationEvent(ERROR_RECOVERABLE, "Invalid strategy name: " + strategyName);
        return false;
    }
    
    if(!ValidateWeight(initialWeight))
    {
        LogOrchestrationEvent(ERROR_RECOVERABLE, "Invalid initial weight for strategy: " + strategyName);
        return false;
    }
    
    if(m_strategyCount >= MAX_STRATEGIES)
    {
        LogOrchestrationEvent(ERROR_RECOVERABLE, "Maximum strategies limit reached");
        return false;
    }
    
    // Check for duplicate strategy names
    if(FindStrategyIndex(strategyName) >= 0)
    {
        LogOrchestrationEvent(ERROR_WARNING, "Strategy already exists: " + strategyName);
        return false;
    }
    
    // Initialize strategy performance
    InitializeStrategyPerformance(m_strategyCount, strategyName, initialWeight);
    m_strategyCount++;
    
    LogOrchestrationEvent(ERROR_INFO, 
                         StringFormat("Strategy added to orchestrator: %s (Weight: %.2f)", 
                                     strategyName, initialWeight));
    
    return true;
}

//+------------------------------------------------------------------+
//| Remove Strategy from Orchestrator                              |
//+------------------------------------------------------------------+
bool CAIStrategyOrchestrator::RemoveStrategy(const string strategyName)
{
    int index = FindStrategyIndex(strategyName);
    if(index < 0)
    {
        LogOrchestrationEvent(ERROR_WARNING, "Strategy not found: " + strategyName);
        return false;
    }
    
    // Shift remaining strategies
    for(int i = index; i < m_strategyCount - 1; i++)
    {
        m_strategies[i] = m_strategies[i + 1];
    }
    
    // Clear last entry
    InitializeStrategyPerformance(m_strategyCount - 1, "", 0.0);
    m_strategyCount--;
    
    LogOrchestrationEvent(ERROR_INFO, "Strategy removed from orchestrator: " + strategyName);
    
    return true;
}

//+------------------------------------------------------------------+
//| Update Strategy Performance                                     |
//+------------------------------------------------------------------+
bool CAIStrategyOrchestrator::UpdateStrategyPerformance(const string strategyName, const double tradeResult)
{
    int index = FindStrategyIndex(strategyName);
    if(index < 0)
    {
        LogOrchestrationEvent(ERROR_WARNING, "Strategy not found for performance update: " + strategyName);
        return false;
    }
    
    // Update trade counts
    m_strategies[index].totalTrades++;
    if(tradeResult > 0.0)
    {
        m_strategies[index].winningTrades++;
        m_strategies[index].consecutiveWins++;
        m_strategies[index].consecutiveLosses = 0;

        // Maintain rolling average profit per winning trade
        int wins = m_strategies[index].winningTrades;
        if(wins > 0)
        {
            double prevTotalProfit = m_strategies[index].avgProfit * (wins - 1);
            m_strategies[index].avgProfit = (prevTotalProfit + tradeResult) / wins;
        }
    }
    else
    {
        m_strategies[index].consecutiveLosses++;
        m_strategies[index].consecutiveWins = 0;

        // Maintain rolling average loss magnitude per losing trade
        int losses = m_strategies[index].totalTrades - m_strategies[index].winningTrades;
        if(losses > 0)
        {
            double absLoss = MathAbs(tradeResult);
            double prevTotalLoss = m_strategies[index].avgLoss * (losses - 1);
            m_strategies[index].avgLoss = (prevTotalLoss + absLoss) / losses;
        }
        
        // Update max consecutive losses
        if(m_strategies[index].consecutiveLosses > m_strategies[index].maxConsecutiveLosses)
        {
            m_strategies[index].maxConsecutiveLosses = m_strategies[index].consecutiveLosses;
        }
    }
    
    // Update recent performance
    UpdateRecentPerformance(index, tradeResult);
    
    // Update regime-specific performance
    UpdateRegimePerformance(index, m_currentRegime, tradeResult);
    
    // Recalculate strategy metrics
    CalculateStrategyMetrics(index);
    
    m_strategies[index].lastUpdate = TimeCurrent();
    
    // Check if strategy needs to be disabled
    if(ShouldDisableStrategy(index))
    {
        m_strategies[index].temporarilyDisabled = true;
        m_strategies[index].disabledUntil = TimeCurrent() + 3600; // Disable for 1 hour
        
        LogStrategyAdaptation(strategyName, "DISABLED", 
                             StringFormat("Poor performance - Win Rate: %.1f%%, Consecutive Losses: %d", 
                                         m_strategies[index].winRate, m_strategies[index].consecutiveLosses));
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Update Strategy Weights Based on Performance                   |
//+------------------------------------------------------------------+
void CAIStrategyOrchestrator::UpdateStrategyWeights(void)
{
    if(!m_initialized) return;
    
    for(int i = 0; i < m_strategyCount; i++)
    {
        if(m_strategies[i].totalTrades < 5) continue; // Need minimum trades for adjustment
        
        double newWeight = CalculatePerformanceAdjustedWeight(i);
        
        // Apply gradual weight adjustment to avoid sudden changes
        double currentWeight = m_strategies[i].weight;
        double adjustmentFactor = 0.1; // 10% adjustment per update
        
        m_strategies[i].weight = currentWeight + (newWeight - currentWeight) * adjustmentFactor;
        
        // Ensure weight stays within bounds
        if(m_strategies[i].weight < 0.1) m_strategies[i].weight = 0.1;
        if(m_strategies[i].weight > 3.0) m_strategies[i].weight = 3.0;
    }
    
    LogOrchestrationEvent(ERROR_INFO, "Strategy weights updated based on performance");
}

//+------------------------------------------------------------------+
//| Calculate Performance-Adjusted Weight                          |
//+------------------------------------------------------------------+
double CAIStrategyOrchestrator::CalculatePerformanceAdjustedWeight(const int strategyIndex)
{
    if(strategyIndex < 0 || strategyIndex >= m_strategyCount)
        return 1.0;
    
    SStrategyPerformance strategy = m_strategies[strategyIndex];
    
    // Base weight factors
    double winRateFactor = 1.0;
    double profitFactor = 1.0;
    double sharpeFactor = 1.0;
    double recentPerformanceFactor = 1.0;
    double regimeFactor = 1.0;
    double winRateNormalized = strategy.winRate / 100.0;
    
    // Win rate adjustment
    if(winRateNormalized > 0.6)
        winRateFactor = 1.5; // Boost high performers
    else if(winRateNormalized < m_minWinRateThreshold)
        winRateFactor = 0.5; // Reduce poor performers
    
    // Profit factor adjustment
    if(strategy.profitFactor > 1.5)
        profitFactor = 1.3;
    else if(strategy.profitFactor < 1.0)
        profitFactor = 0.7;
    
    // Sharpe ratio adjustment
    if(strategy.sharpeRatio > 1.0)
        sharpeFactor = 1.2;
    else if(strategy.sharpeRatio < 0.5)
        sharpeFactor = 0.8;
    
    // Recent performance adjustment
    if(strategy.recentWinRate > 0.7)
        recentPerformanceFactor = 1.4;
    else if(strategy.recentWinRate < 0.3)
        recentPerformanceFactor = 0.6;
    
    // Market regime adjustment
    regimeFactor = GetRegimeMultiplier(m_currentRegime, strategyIndex);
    
    // Calculate adjusted weight
    double adjustedWeight = 1.0 * winRateFactor * profitFactor * sharpeFactor * 
                           recentPerformanceFactor * regimeFactor;
    
    return adjustedWeight;
}

//+------------------------------------------------------------------+
//| Apply Regime-Based Adjustments                                 |
//+------------------------------------------------------------------+
void CAIStrategyOrchestrator::ApplyRegimeBasedAdjustments(ENUM_MARKET_REGIME regime, double regimeConfidence)
{
    if(!m_initialized || regimeConfidence < 0.5) return;
    
    m_currentRegime = regime;
    m_regimeConfidence = regimeConfidence;
    
    LogOrchestrationEvent(ERROR_INFO, 
                         StringFormat("Applying regime-based adjustments: %s (Confidence: %.2f)", 
                                     EnumToString(regime), regimeConfidence));
    
    // Update strategy weights based on regime
    UpdateStrategyWeights();
}

//+------------------------------------------------------------------+
//| Check Strategy Disabling                                       |
//+------------------------------------------------------------------+
void CAIStrategyOrchestrator::CheckStrategyDisabling(void)
{
    if(!m_initialized) return;
    
    for(int i = 0; i < m_strategyCount; i++)
    {
        if(m_strategies[i].enabled && !m_strategies[i].temporarilyDisabled)
        {
            if(ShouldDisableStrategy(i))
            {
                m_strategies[i].temporarilyDisabled = true;
                m_strategies[i].disabledUntil = TimeCurrent() + 3600; // 1 hour
                
                LogStrategyAdaptation(m_strategies[i].name, "AUTO_DISABLED", 
                                     StringFormat("Performance threshold breach - Win Rate: %.1f%%, Consecutive Losses: %d", 
                                                 m_strategies[i].winRate, m_strategies[i].consecutiveLosses));
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Check Strategy Re-enabling                                     |
//+------------------------------------------------------------------+
void CAIStrategyOrchestrator::CheckStrategyReEnabling(void)
{
    if(!m_initialized) return;
    
    datetime currentTimeLocal = TimeCurrent();
    
    for(int i = 0; i < m_strategyCount; i++)
    {
        if(m_strategies[i].temporarilyDisabled && currentTimeLocal >= m_strategies[i].disabledUntil)
        {
            if(ShouldReEnableStrategy(i))
            {
                m_strategies[i].temporarilyDisabled = false;
                m_strategies[i].disabledUntil = 0;
                m_strategies[i].consecutiveLosses = 0; // Reset consecutive losses
                
                LogStrategyAdaptation(m_strategies[i].name, "RE_ENABLED", 
                                     "Cooling period completed and conditions met");
            }
            else
            {
                // Extend disable period if conditions not met
                m_strategies[i].disabledUntil = currentTimeLocal + 1800; // 30 minutes more
                
                LogStrategyAdaptation(m_strategies[i].name, "DISABLE_EXTENDED", 
                                     "Re-enabling conditions not yet met");
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Should Disable Strategy                                        |
//+------------------------------------------------------------------+
bool CAIStrategyOrchestrator::ShouldDisableStrategy(const int strategyIndex)
{
    if(strategyIndex < 0 || strategyIndex >= m_strategyCount)
        return false;
    
    SStrategyPerformance strategy = m_strategies[strategyIndex];
    
    // Need minimum trades for reliable statistics
    if(strategy.totalTrades < 10) return false;
    
    // Check win rate threshold
    if(strategy.winRate < m_minWinRateThreshold * 100.0) return true;
    
    // Check consecutive losses
    if(strategy.consecutiveLosses >= m_maxConsecutiveLosses) return true;
    
    // Check recent performance
    if(strategy.recentTradeCount >= 10 && strategy.recentWinRate < 0.2) return true;
    
    // Check profit factor
    if(strategy.profitFactor < 0.8) return true;
    
    return false;
}

//+------------------------------------------------------------------+
//| Should Re-enable Strategy                                      |
//+------------------------------------------------------------------+
bool CAIStrategyOrchestrator::ShouldReEnableStrategy(const int strategyIndex)
{
    if(strategyIndex < 0 || strategyIndex >= m_strategyCount)
        return false;
    
    SStrategyPerformance strategy = m_strategies[strategyIndex];
    
    // Basic conditions for re-enabling
    if(strategy.consecutiveLosses > 0) return false; // Still in losing streak
    if(strategy.winRate < m_minWinRateThreshold * 80.0) return false; // Win rate too low
    
    // Market regime consideration
    double regimeMultiplier = GetRegimeMultiplier(m_currentRegime, strategyIndex);
    if(regimeMultiplier < 0.8) return false; // Poor regime fit
    
    return true;
}

//+------------------------------------------------------------------+
//| Get Ensemble Signal                                            |
//+------------------------------------------------------------------+
ENUM_TRADE_SIGNAL CAIStrategyOrchestrator::GetEnsembleSignal(SEnsembleVote &votes[], int voteCount, double &confidence)
{
    if(!m_initialized || voteCount == 0)
    {
        confidence = 0.0;
        return TRADE_SIGNAL_NONE;
    }
    
    // Filter out votes from disabled strategies and low confidence signals
    SEnsembleVote validVotes[MAX_STRATEGIES];
    int validVoteCount = 0;
    
    for(int i = 0; i < voteCount && i < MAX_STRATEGIES; i++)
    {
        int strategyIndex = FindStrategyIndex(votes[i].strategyName);
        if(strategyIndex >= 0 && !m_strategies[strategyIndex].temporarilyDisabled && 
           votes[i].confidence >= m_minVotingConfidence)
        {
            validVotes[validVoteCount] = votes[i];
            
            // Apply performance-adjusted weight
            validVotes[validVoteCount].adjustedWeight = 
                votes[i].weight * CalculatePerformanceAdjustedWeight(strategyIndex);
            
            validVoteCount++;
        }
    }
    
    if(validVoteCount == 0)
    {
        confidence = 0.0;
        return TRADE_SIGNAL_NONE;
    }

    // Require at least two valid voters when ensemble has multiple registered strategies.
    if(validVoteCount == 1 && m_strategyCount > 1)
    {
        confidence = 0.0;
        LogOrchestrationEvent(ERROR_INFO, "Single-vote ensemble signal rejected (multi-strategy quorum not met)");
        return TRADE_SIGNAL_NONE;
    }
    
    // Process weighted voting
    ENUM_TRADE_SIGNAL signal = ProcessWeightedVoting(validVotes, validVoteCount, confidence);
    
    // Record ensemble signal
    if(signal != TRADE_SIGNAL_NONE)
    {
        m_totalEnsembleSignals++;
        
        LogOrchestrationEvent(ERROR_INFO, 
                             StringFormat("Ensemble signal generated: %s | Confidence: %.2f | Votes: %d", 
                                         (signal == TRADE_SIGNAL_BUY ? "BUY" : "SELL"), 
                                         confidence, validVoteCount));
    }
    
    return signal;
}

//+------------------------------------------------------------------+
//| Process Weighted Voting                                        |
//+------------------------------------------------------------------+
ENUM_TRADE_SIGNAL CAIStrategyOrchestrator::ProcessWeightedVoting(SEnsembleVote &votes[], int voteCount, double &confidence)
{
    if(voteCount == 0)
    {
        confidence = 0.0;
        return TRADE_SIGNAL_NONE;
    }
    
    double buyWeight = 0.0;
    double sellWeight = 0.0;
    double totalWeight = 0.0;
    double totalConfidence = 0.0;
    int buyVotes = 0;
    int sellVotes = 0;
    
    // Calculate weighted votes
    for(int i = 0; i < voteCount; i++)
    {
        double effectiveWeight = m_useConfidenceWeighting ? 
                                votes[i].adjustedWeight * votes[i].confidence : 
                                votes[i].adjustedWeight;
        
        if(votes[i].signal == TRADE_SIGNAL_BUY)
        {
            buyWeight += effectiveWeight;
            buyVotes++;
        }
        else if(votes[i].signal == TRADE_SIGNAL_SELL)
        {
            sellWeight += effectiveWeight;
            sellVotes++;
        }
        
        totalWeight += effectiveWeight;
        totalConfidence += votes[i].confidence * votes[i].adjustedWeight;
    }
    
    if(totalWeight == 0.0)
    {
        confidence = 0.0;
        return TRADE_SIGNAL_NONE;
    }
    
    // Calculate consensus
    double buyConsensus = buyWeight / totalWeight;
    double sellConsensus = sellWeight / totalWeight;
    confidence = totalConfidence / totalWeight;
    
    // REQUIREMENT 4.5: IF multiple strategies agree on direction THEN confidence SHALL be increased
    double agreementLevel = MathMax(buyConsensus, sellConsensus);
    if(voteCount >= 2 && (buyVotes >= 2 || sellVotes >= 2) && agreementLevel >= 0.7) // Require real multi-strategy agreement
    {
        confidence += m_agreementBonus * agreementLevel;
        confidence = MathMin(confidence, 1.0); // Cap at 1.0
        
        LogOrchestrationEvent(ERROR_INFO, 
                             StringFormat("Strategy agreement bonus: %.1f%% consensus, confidence boosted by %.2f", 
                                         agreementLevel * 100, m_agreementBonus * agreementLevel));
    }
    
    // REQUIREMENT 4.6: WHEN strategies disagree THEN the EA SHALL either skip the trade or use ensemble voting
    double disagreementLevel = MathMin(buyConsensus, sellConsensus);
    if(disagreementLevel > 0.3 && MathAbs(buyConsensus - sellConsensus) < 0.3) // High disagreement
    {
        confidence -= m_disagreementPenalty * disagreementLevel;
        confidence = MathMax(confidence, 0.0); // Floor at 0.0
        
        LogOrchestrationEvent(ERROR_WARNING, 
                             StringFormat("Strategy disagreement: BUY=%.1f%%, SELL=%.1f%%, confidence reduced by %.2f", 
                                         buyConsensus * 100, sellConsensus * 100, m_disagreementPenalty * disagreementLevel));
        
        // If disagreement is too high and confidence too low, skip trade
        if(confidence < m_minVotingConfidence)
        {
            LogOrchestrationEvent(ERROR_INFO, "Trade skipped due to high strategy disagreement");
            return TRADE_SIGNAL_NONE;
        }
    }
    
    // REQUIREMENT 4.7: WHEN market regime is uncertain THEN only high-confidence signals SHALL be executed
    if(m_regimeConfidence < m_regimeUncertaintyThreshold)
    {
        int directionalVotes = (buyConsensus >= sellConsensus) ? buyVotes : sellVotes;
        if(confidence < m_highConfidenceThreshold || directionalVotes < 2)
        {
            LogOrchestrationEvent(ERROR_INFO, 
                                 StringFormat("Regime uncertain (%.2f), requiring high-confidence multi-vote signal (conf=%.2f, votes=%d) - signal rejected", 
                                             m_regimeConfidence, confidence, directionalVotes));
            return TRADE_SIGNAL_NONE;
        }
        else
        {
            LogOrchestrationEvent(ERROR_INFO, 
                                 StringFormat("High confidence multi-vote signal accepted despite regime uncertainty (conf=%.2f, votes=%d)", confidence, directionalVotes));
        }
    }
    
    // Check consensus threshold
    if(buyConsensus >= m_consensusThreshold)
        return TRADE_SIGNAL_BUY;
    else if(sellConsensus >= m_consensusThreshold)
        return TRADE_SIGNAL_SELL;
    else
        return ResolveTieBreaking(votes, voteCount, confidence);
}

//+------------------------------------------------------------------+
//| Get Enhanced Ensemble Decision                                 |
//+------------------------------------------------------------------+
SEnsembleDecision CAIStrategyOrchestrator::GetEnsembleDecision(SEnsembleVote &votes[], int voteCount)
{
    SEnsembleDecision decision;
    decision.decisionTime = TimeCurrent();
    decision.totalVotes = voteCount;
    decision.validVotes = 0;
    decision.buyVotes = 0;
    decision.sellVotes = 0;
    decision.neutralVotes = 0;
    decision.buyWeight = 0.0;
    decision.sellWeight = 0.0;
    
    if(!m_initialized || voteCount == 0)
    {
        decision.finalSignal = TRADE_SIGNAL_NONE;
        decision.confidence = 0.0;
        decision.decisionReasoning = "No valid votes or orchestrator not initialized";
        return decision;
    }
    
    // Validate and process votes
    SEnsembleVote validVotes[MAX_STRATEGIES];
    int validVoteCount = 0;
    
    for(int i = 0; i < voteCount && i < MAX_STRATEGIES; i++)
    {
        if(ValidateVote(votes[i]))
        {
            int strategyIndex = FindStrategyIndex(votes[i].strategyName);
            if(strategyIndex >= 0 && !m_strategies[strategyIndex].temporarilyDisabled)
            {
                validVotes[validVoteCount] = votes[i];
                validVotes[validVoteCount].adjustedWeight = 
                    votes[i].weight * CalculatePerformanceAdjustedWeight(strategyIndex);
                
                // Count votes by type
                if(votes[i].signal == TRADE_SIGNAL_BUY)
                {
                    decision.buyVotes++;
                    decision.buyWeight += validVotes[validVoteCount].adjustedWeight;
                }
                else if(votes[i].signal == TRADE_SIGNAL_SELL)
                {
                    decision.sellVotes++;
                    decision.sellWeight += validVotes[validVoteCount].adjustedWeight;
                }
                else
                {
                    decision.neutralVotes++;
                }
                
                validVoteCount++;
            }
        }
    }
    
    decision.validVotes = validVoteCount;
    
    if(validVoteCount == 0)
    {
        decision.finalSignal = TRADE_SIGNAL_NONE;
        decision.confidence = 0.0;
        decision.decisionReasoning = "No valid votes after filtering";
        return decision;
    }
    
    // Process weighted voting with enhanced logic
    double confidence = 0.0;
    decision.finalSignal = ProcessWeightedVoting(validVotes, validVoteCount, confidence);
    decision.confidence = confidence;
    
    // Calculate consensus strength
    decision.consensusStrength = CalculateConsensusStrength(validVotes, validVoteCount, decision.finalSignal);
    
    // Enhanced reasoning with agreement/disagreement analysis
    double agreementLevel = CalculateAgreementLevel(validVotes, validVoteCount, decision.finalSignal);
    double disagreementLevel = CalculateDisagreementLevel(validVotes, validVoteCount);
    
    string reasoningDetails = "";
    if(agreementLevel >= 0.7)
        reasoningDetails += StringFormat(" | Strong Agreement: %.1f%%", agreementLevel * 100);
    if(disagreementLevel > 0.3)
        reasoningDetails += StringFormat(" | High Disagreement: %.1f%%", disagreementLevel * 100);
    if(IsRegimeUncertain())
        reasoningDetails += StringFormat(" | Regime Uncertain: %.1f%%", m_regimeConfidence * 100);
    
    decision.decisionReasoning = StringFormat("Ensemble: %d votes, %.1f%% consensus, %.3f confidence%s",
                                            validVoteCount, decision.consensusStrength * 100, confidence, reasoningDetails);
    
    // Store decision for tracking
    m_recentDecisions[m_decisionIndex] = decision;
    m_decisionIndex = (m_decisionIndex + 1) % 50;
    if(m_decisionCount < 50) m_decisionCount++;
    
    // Log detailed decision reasoning
    LogVotingDecisionReasoning(validVotes, validVoteCount, decision.finalSignal, confidence);
    
    // Log the decision summary
    LogEnsembleDecision(decision);
    
    return decision;
}

//+------------------------------------------------------------------+
//| Resolve Tie Breaking                                           |
//+------------------------------------------------------------------+
ENUM_TRADE_SIGNAL CAIStrategyOrchestrator::ResolveTieBreaking(SEnsembleVote &votes[], int voteCount, double &confidence)
{
    return ResolveAdvancedTieBreaking(votes, voteCount, confidence);
}

//+------------------------------------------------------------------+
//| Resolve Advanced Tie Breaking                                  |
//+------------------------------------------------------------------+
ENUM_TRADE_SIGNAL CAIStrategyOrchestrator::ResolveAdvancedTieBreaking(SEnsembleVote &votes[], int voteCount, double &confidence)
{
    if(voteCount == 0)
    {
        confidence = 0.0;
        return TRADE_SIGNAL_NONE;
    }
    
    // Method 1: Highest confidence vote
    double maxConfidence = 0.0;
    ENUM_TRADE_SIGNAL bestSignal = TRADE_SIGNAL_NONE;
    string bestStrategy = "";
    
    for(int i = 0; i < voteCount; i++)
    {
        if(votes[i].confidence > maxConfidence)
        {
            maxConfidence = votes[i].confidence;
            bestSignal = votes[i].signal;
            bestStrategy = votes[i].strategyName;
        }
    }
    
    // Method 2: Best performing strategy in current regime
    double bestRegimePerformance = -1.0;
    ENUM_TRADE_SIGNAL regimeBestSignal = TRADE_SIGNAL_NONE;
    
    for(int i = 0; i < voteCount; i++)
    {
        int strategyIndex = FindStrategyIndex(votes[i].strategyName);
        if(strategyIndex >= 0)
        {
            double regimePerf = GetRegimeMultiplier(m_currentRegime, strategyIndex);
            if(regimePerf > bestRegimePerformance)
            {
                bestRegimePerformance = regimePerf;
                regimeBestSignal = votes[i].signal;
            }
        }
    }
    
    // Method 3: Recent performance weighted
    double bestRecentPerformance = 0.0;
    ENUM_TRADE_SIGNAL recentBestSignal = TRADE_SIGNAL_NONE;
    
    for(int i = 0; i < voteCount; i++)
    {
        int strategyIndex = FindStrategyIndex(votes[i].strategyName);
        if(strategyIndex >= 0)
        {
            double recentPerf = m_strategies[strategyIndex].recentWinRate;
            if(recentPerf > bestRecentPerformance)
            {
                bestRecentPerformance = recentPerf;
                recentBestSignal = votes[i].signal;
            }
        }
    }
    
    // Combine tie-breaking methods
    if(maxConfidence >= 0.8)
    {
        // High confidence wins
        confidence = maxConfidence;
        LogOrchestrationEvent(ERROR_INFO, 
                             StringFormat("Tie-breaking: High confidence method - %s (%.2f)", 
                                         bestStrategy, maxConfidence));
        return bestSignal;
    }
    else if(bestRegimePerformance > 1.2 && regimeBestSignal != TRADE_SIGNAL_NONE)
    {
        // Good regime performance wins
        confidence = maxConfidence * 0.8;
        LogOrchestrationEvent(ERROR_INFO, 
                             "Tie-breaking: Regime performance method");
        return regimeBestSignal;
    }
    else if(bestRecentPerformance > 0.6 && recentBestSignal != TRADE_SIGNAL_NONE)
    {
        // Recent performance wins
        confidence = maxConfidence * 0.7;
        LogOrchestrationEvent(ERROR_INFO, 
                             "Tie-breaking: Recent performance method");
        return recentBestSignal;
    }
    else if(maxConfidence >= 0.6)
    {
        // Moderate confidence as last resort
        confidence = maxConfidence * 0.6;
        LogOrchestrationEvent(ERROR_INFO, 
                             "Tie-breaking: Moderate confidence fallback");
        return bestSignal;
    }
    
    // No clear winner
    confidence = 0.0;
    LogOrchestrationEvent(ERROR_INFO, "Tie-breaking: No clear winner, skipping trade");
    return TRADE_SIGNAL_NONE;
}

//+------------------------------------------------------------------+
//| Record Ensemble Result                                          |
//+------------------------------------------------------------------+
void CAIStrategyOrchestrator::RecordEnsembleResult(const bool successful)
{
    if(successful)
        m_successfulEnsembleSignals++;
    
    LogOrchestrationEvent(ERROR_INFO, 
                         StringFormat("Ensemble result recorded: %s | Accuracy: %.1f%%", 
                                     successful ? "SUCCESS" : "FAILURE", GetEnsembleAccuracy()));
}

//+------------------------------------------------------------------+
//| Get Ensemble Accuracy                                          |
//+------------------------------------------------------------------+
double CAIStrategyOrchestrator::GetEnsembleAccuracy(void)
{
    if(m_totalEnsembleSignals == 0)
        return 0.0;
    
    return ((double)m_successfulEnsembleSignals / m_totalEnsembleSignals) * 100.0;
}

//+------------------------------------------------------------------+
//| Update Recent Performance                                       |
//+------------------------------------------------------------------+
void CAIStrategyOrchestrator::UpdateRecentPerformance(const int strategyIndex, const double result)
{
    if(strategyIndex < 0 || strategyIndex >= m_strategyCount)
        return;
    
    // Add to circular buffer
    m_strategies[strategyIndex].recentTrades[m_strategies[strategyIndex].recentTradeIndex] = result;
    m_strategies[strategyIndex].recentTradeIndex = (m_strategies[strategyIndex].recentTradeIndex + 1) % m_rollingWindowSize;
    
    if(m_strategies[strategyIndex].recentTradeCount < m_rollingWindowSize)
        m_strategies[strategyIndex].recentTradeCount++;
    
    // Recalculate recent win rate
    m_strategies[strategyIndex].recentWinRate = CalculateRecentWinRate(strategyIndex);
}

//+------------------------------------------------------------------+
//| Get Strategy Performance                                        |
//+------------------------------------------------------------------+
bool CAIStrategyOrchestrator::GetStrategyPerformance(const string strategyName, SStrategyPerformance &performance)
{
    int index = FindStrategyIndex(strategyName);
    if(index < 0)
        return false;
    
    performance = m_strategies[index];
    return true;
}

//+------------------------------------------------------------------+
//| Get Active Strategy Count                                      |
//+------------------------------------------------------------------+
int CAIStrategyOrchestrator::GetActiveStrategyCount(void)
{
    int count = 0;
    for(int i = 0; i < m_strategyCount; i++)
    {
        if(m_strategies[i].enabled && !m_strategies[i].temporarilyDisabled)
            count++;
    }
    return count;
}

//+------------------------------------------------------------------+
//| Get Average Win Rate                                           |
//+------------------------------------------------------------------+
double CAIStrategyOrchestrator::GetAverageWinRate(void)
{
    if(m_strategyCount == 0) return 0.0;
    
    double totalWinRate = 0.0;
    int activeStrategies = 0;
    
    for(int i = 0; i < m_strategyCount; i++)
    {
        if(m_strategies[i].enabled && m_strategies[i].totalTrades > 0)
        {
            totalWinRate += m_strategies[i].winRate;
            activeStrategies++;
        }
    }
    
    return (activeStrategies > 0) ? totalWinRate / activeStrategies : 0.0;
}

//+------------------------------------------------------------------+
//| Get Performance Summary                                         |
//+------------------------------------------------------------------+
string CAIStrategyOrchestrator::GetPerformanceSummary(void)
{
    if(!m_initialized)
        return "Orchestrator not initialized";
    
    return StringFormat("Strategies: %d/%d Active | Avg Win Rate: %.1f%% | Ensemble Accuracy: %.1f%% | Regime: %s",
                       GetActiveStrategyCount(), m_strategyCount, GetAverageWinRate(), 
                       GetEnsembleAccuracy(), EnumToString(m_currentRegime));
}

//+------------------------------------------------------------------+
//| Set Current Market Regime                                      |
//+------------------------------------------------------------------+
void CAIStrategyOrchestrator::SetCurrentRegime(ENUM_MARKET_REGIME regime, double confidence)
{
    if(regime != m_currentRegime && confidence > 0.6)
    {
        LogOrchestrationEvent(ERROR_INFO, 
                             StringFormat("Market regime changed: %s -> %s (Confidence: %.2f)", 
                                         EnumToString(m_currentRegime), EnumToString(regime), confidence));
        
        ApplyRegimeBasedAdjustments(regime, confidence);
    }
    
    m_currentRegime = regime;
    m_regimeConfidence = confidence;
}

//+------------------------------------------------------------------+
//| Print Orchestration Report                                     |
//+------------------------------------------------------------------+
void CAIStrategyOrchestrator::PrintOrchestrationReport(void)
{
    if(!m_initialized) return;
    
    Print("\n=== AI STRATEGY ORCHESTRATOR REPORT ===");
    Print("ENSEMBLE PERFORMANCE:");
    Print("   Total Strategies: ", m_strategyCount);
    Print("   Active Strategies: ", GetActiveStrategyCount());
    Print("   Average Win Rate: ", DoubleToString(GetAverageWinRate(), 1), "%");
    Print("   Ensemble Signals: ", m_totalEnsembleSignals);
    Print("   Ensemble Accuracy: ", DoubleToString(GetEnsembleAccuracy(), 1), "%");
    Print("   Current Regime: ", EnumToString(m_currentRegime), " (", DoubleToString(m_regimeConfidence, 2), ")");
    
    Print("\nSTRATEGY DETAILS:");
    for(int i = 0; i < m_strategyCount; i++)
    {
        string status = m_strategies[i].enabled ? (m_strategies[i].temporarilyDisabled ? "DISABLED" : "ACTIVE") : "INACTIVE";
        
        Print("   ", i+1, ". ", m_strategies[i].name);
        Print("      Status: ", status, " | Weight: ", DoubleToString(m_strategies[i].weight, 2));
        Print("      Trades: ", m_strategies[i].totalTrades, " | Win Rate: ", DoubleToString(m_strategies[i].winRate, 1), "%");
        Print("      Recent Win Rate: ", DoubleToString(m_strategies[i].recentWinRate * 100, 1), "%");
        Print("      Consecutive Losses: ", m_strategies[i].consecutiveLosses, "/", m_strategies[i].maxConsecutiveLosses);
        Print("      Profit Factor: ", DoubleToString(m_strategies[i].profitFactor, 2));
        
        if(m_strategies[i].temporarilyDisabled)
        {
            Print("      Disabled Until: ", TimeToString(m_strategies[i].disabledUntil));
        }
    }
    
    Print("\nCONFIGURATION:");
    Print("   Min Win Rate Threshold: ", DoubleToString(m_minWinRateThreshold * 100, 1), "%");
    Print("   Max Consecutive Losses: ", m_maxConsecutiveLosses);
    Print("   Rolling Window Size: ", m_rollingWindowSize);
    Print("   Consensus Threshold: ", DoubleToString(m_consensusThreshold, 2));
    Print("   Use Confidence Weighting: ", m_useConfidenceWeighting ? "YES" : "NO");
    
    Print("\nENSEMBLE VOTING CONFIG:");
    Print("   Agreement Bonus: ", DoubleToString(m_agreementBonus, 3));
    Print("   Disagreement Penalty: ", DoubleToString(m_disagreementPenalty, 3));
    Print("   Regime Uncertainty Threshold: ", DoubleToString(m_regimeUncertaintyThreshold, 2));
    Print("   High Confidence Threshold: ", DoubleToString(m_highConfidenceThreshold, 2));
    Print("   Min Voting Confidence: ", DoubleToString(m_minVotingConfidence, 2));
    
    Print("=========================================\n");
}

//+------------------------------------------------------------------+
//| Log Strategy Adaptation                                        |
//+------------------------------------------------------------------+
void CAIStrategyOrchestrator::LogStrategyAdaptation(const string strategyName, const string action, const string reason)
{
    string message = StringFormat("Strategy Adaptation - %s: %s | Reason: %s", 
                                 strategyName, action, reason);
    LogOrchestrationEvent(ERROR_INFO, message);
}

//+------------------------------------------------------------------+
//| Find Strategy Index                                            |
//+------------------------------------------------------------------+
int CAIStrategyOrchestrator::FindStrategyIndex(const string strategyName)
{
    for(int i = 0; i < m_strategyCount; i++)
    {
        if(m_strategies[i].name == strategyName)
            return i;
    }
    return -1;
}

//+------------------------------------------------------------------+
//| Initialize Strategy Performance                                 |
//+------------------------------------------------------------------+
void CAIStrategyOrchestrator::InitializeStrategyPerformance(const int index, const string name, const double weight)
{
    if(index < 0 || index >= MAX_STRATEGIES) return;
    
    m_strategies[index].name = name;
    m_strategies[index].weight = weight;
    m_strategies[index].enabled = true;
    m_strategies[index].totalTrades = 0;
    m_strategies[index].winningTrades = 0;
    m_strategies[index].winRate = 0.0;
    m_strategies[index].avgProfit = 0.0;
    m_strategies[index].avgLoss = 0.0;
    m_strategies[index].profitFactor = 0.0;
    m_strategies[index].sharpeRatio = 0.0;
    m_strategies[index].recentTradeIndex = 0;
    m_strategies[index].recentTradeCount = 0;
    m_strategies[index].recentWinRate = 0.0;
    m_strategies[index].consecutiveLosses = 0;
    m_strategies[index].maxConsecutiveLosses = 0;
    m_strategies[index].consecutiveWins = 0;
    m_strategies[index].temporarilyDisabled = false;
    m_strategies[index].disabledUntil = 0;
    m_strategies[index].lastUpdate = TimeCurrent();
    
    // Initialize arrays
    for(int j = 0; j < 20; j++)
    {
        m_strategies[index].recentTrades[j] = 0.0;
    }
    
    for(int k = 0; k < 5; k++)
    {
        m_strategies[index].regimePerformance[k] = 0.0;
        m_strategies[index].regimeTrades[k] = 0;
    }
}

//+------------------------------------------------------------------+
//| Calculate Strategy Metrics                                     |
//+------------------------------------------------------------------+
void CAIStrategyOrchestrator::CalculateStrategyMetrics(const int index)
{
    if(index < 0 || index >= m_strategyCount) return;
    
    // Calculate win rate
    if(m_strategies[index].totalTrades > 0)
    {
        m_strategies[index].winRate = ((double)m_strategies[index].winningTrades / m_strategies[index].totalTrades) * 100.0;
    }
    
    // Calculate profit factor from observed win/loss averages
    if(m_strategies[index].avgLoss > 0.0)
        m_strategies[index].profitFactor = m_strategies[index].avgProfit / m_strategies[index].avgLoss;
    else if(m_strategies[index].avgProfit > 0.0)
        m_strategies[index].profitFactor = 2.0;
    else
        m_strategies[index].profitFactor = 0.0;
    
    // Calculate Sharpe ratio (simplified)
    m_strategies[index].sharpeRatio = CalculateSharpeRatio(index);
    
    // Update recent win rate
    m_strategies[index].recentWinRate = CalculateRecentWinRate(index);
}

//+------------------------------------------------------------------+
//| Update Regime Performance                                       |
//+------------------------------------------------------------------+
void CAIStrategyOrchestrator::UpdateRegimePerformance(const int index, ENUM_MARKET_REGIME regime, const double result)
{
    if(index < 0 || index >= m_strategyCount) return;
    if(regime < 0 || regime >= 5) return;
    
    m_strategies[index].regimeTrades[regime]++;
    
    // Update running average
    double currentAvg = m_strategies[index].regimePerformance[regime];
    int tradeCount = m_strategies[index].regimeTrades[regime];
    
    m_strategies[index].regimePerformance[regime] = 
        ((currentAvg * (tradeCount - 1)) + result) / tradeCount;
}

//+------------------------------------------------------------------+
//| Validation Functions                                           |
//+------------------------------------------------------------------+
bool CAIStrategyOrchestrator::ValidateStrategyName(const string name)
{
    return (StringLen(name) > 0 && StringLen(name) <= 50);
}

bool CAIStrategyOrchestrator::ValidateWeight(const double weight)
{
    return (weight >= 0.0 && weight <= 10.0);
}

bool CAIStrategyOrchestrator::ValidateWinRateThreshold(const double threshold)
{
    return (threshold >= 0.1 && threshold <= 0.9);
}

//+------------------------------------------------------------------+
//| Utility Functions                                             |
//+------------------------------------------------------------------+
double CAIStrategyOrchestrator::CalculateRecentWinRate(const int index)
{
    if(index < 0 || index >= m_strategyCount) return 0.0;
    
    SStrategyPerformance strategy = m_strategies[index];
    if(strategy.recentTradeCount == 0) return 0.0;
    
    int wins = 0;
    for(int i = 0; i < strategy.recentTradeCount; i++)
    {
        if(strategy.recentTrades[i] > 0.0) wins++;
    }
    
    return (double)wins / strategy.recentTradeCount;
}

double CAIStrategyOrchestrator::CalculateSharpeRatio(const int index)
{
    if(index < 0 || index >= m_strategyCount) return 0.0;
    
    // Simplified Sharpe ratio calculation
    SStrategyPerformance strategy = m_strategies[index];
    
    if(strategy.totalTrades < 10) return 0.0;
    
    double avgReturn = (strategy.avgProfit * strategy.winRate / 100.0) + 
                      (strategy.avgLoss * (100.0 - strategy.winRate) / 100.0);
    
    // Simplified standard deviation estimate
    double stdDev = MathSqrt(strategy.winRate * (100.0 - strategy.winRate) / 100.0);
    
    return (stdDev > 0.0) ? avgReturn / stdDev : 0.0;
}

double CAIStrategyOrchestrator::GetRegimeMultiplier(ENUM_MARKET_REGIME regime, const int strategyIndex)
{
    if(strategyIndex < 0 || strategyIndex >= m_strategyCount) return 1.0;
    if(regime < 0 || regime >= 5) return 1.0;
    
    SStrategyPerformance strategy = m_strategies[strategyIndex];
    
    // If no regime-specific data, return neutral multiplier
    if(strategy.regimeTrades[regime] < 3) return 1.0;
    
    // Convert performance to multiplier (0.5 to 1.5 range)
    double performance = strategy.regimePerformance[regime];
    if(performance > 0.0)
        return MathMin(1.5, 1.0 + performance * 0.5);
    else
        return MathMax(0.5, 1.0 + performance * 0.5);
}

//+------------------------------------------------------------------+
//| Validate Vote                                                  |
//+------------------------------------------------------------------+
bool CAIStrategyOrchestrator::ValidateVote(const SEnsembleVote &vote)
{
    // Check basic validity
    if(vote.strategyName == "" || vote.confidence < 0.0 || vote.confidence > 1.0)
        return false;
    
    // Check signal validity
    if(vote.signal != TRADE_SIGNAL_BUY && vote.signal != TRADE_SIGNAL_SELL && vote.signal != TRADE_SIGNAL_NONE)
        return false;
    
    // Check weight validity
    if(vote.weight < 0.0 || vote.weight > 10.0)
        return false;
    
    // Check confidence threshold
    if(vote.confidence < m_minVotingConfidence)
        return false;
    
    // Check timestamp (not too old)
    if(vote.timestamp > 0 && (TimeCurrent() - vote.timestamp) > 300) // 5 minutes max age
        return false;
    
    return true;
}

//+------------------------------------------------------------------+
//| Calculate Consensus Strength                                   |
//+------------------------------------------------------------------+
double CAIStrategyOrchestrator::CalculateConsensusStrength(SEnsembleVote &votes[], int voteCount, ENUM_TRADE_SIGNAL signal)
{
    if(voteCount == 0 || signal == TRADE_SIGNAL_NONE)
        return 0.0;
    
    double totalWeight = 0.0;
    double agreementWeight = 0.0;
    
    for(int i = 0; i < voteCount; i++)
    {
        totalWeight += votes[i].adjustedWeight;
        if(votes[i].signal == signal)
        {
            agreementWeight += votes[i].adjustedWeight;
        }
    }
    
    return (totalWeight > 0.0) ? agreementWeight / totalWeight : 0.0;
}

//+------------------------------------------------------------------+
//| Log Ensemble Decision                                          |
//+------------------------------------------------------------------+
void CAIStrategyOrchestrator::LogEnsembleDecision(const SEnsembleDecision &decision)
{
    string signalStr = "NONE";
    if(decision.finalSignal == TRADE_SIGNAL_BUY) signalStr = "BUY";
    else if(decision.finalSignal == TRADE_SIGNAL_SELL) signalStr = "SELL";
    
    LogOrchestrationEvent(ERROR_INFO, 
                         StringFormat("Ensemble decision: %s | Confidence: %.2f | Consensus: %.1f%% | Votes: %d/%d valid",
                                     signalStr, decision.confidence, decision.consensusStrength * 100,
                                     decision.validVotes, decision.totalVotes));
    
    LogOrchestrationEvent(ERROR_INFO, 
                         StringFormat("   Vote Breakdown: BUY=%d (%.2f), SELL=%d (%.2f), NEUTRAL=%d",
                                     decision.buyVotes, decision.buyWeight,
                                     decision.sellVotes, decision.sellWeight,
                                     decision.neutralVotes));
    
    if(decision.decisionReasoning != "")
    {
        LogOrchestrationEvent(ERROR_INFO, "   Reasoning: " + decision.decisionReasoning);
    }
}

//+------------------------------------------------------------------+
//| Update Ensemble Performance                                    |
//+------------------------------------------------------------------+
void CAIStrategyOrchestrator::UpdateEnsemblePerformance(const SEnsembleDecision &decision, double outcome)
{
    // Find the decision in recent history
    for(int i = 0; i < m_decisionCount; i++)
    {
        if(MathAbs(m_recentDecisions[i].decisionTime - decision.decisionTime) < 5) // 5 second tolerance
        {
            m_recentDecisions[i].wasSuccessful = (outcome > 0.0);
            m_recentDecisions[i].actualOutcome = outcome;
            m_recentDecisions[i].outcomeTime = TimeCurrent();
            
            // Update overall ensemble performance
            RecordEnsembleResult(outcome > 0.0);
            
            // Update accuracy history
            double currentAccuracy = GetEnsembleAccuracy();
            m_ensembleAccuracyHistory[m_accuracyIndex] = currentAccuracy;
            m_accuracyIndex = (m_accuracyIndex + 1) % 20;
            
            LogOrchestrationEvent(ERROR_INFO, 
                                 StringFormat("Ensemble performance updated: Outcome=%.2f, Success=%s, Accuracy=%.1f%%",
                                             outcome, (outcome > 0.0) ? "YES" : "NO", currentAccuracy));
            break;
        }
    }
}

//+------------------------------------------------------------------+
//| Log Orchestration Event                                        |
//+------------------------------------------------------------------+
void CAIStrategyOrchestrator::LogOrchestrationEvent(const ENUM_ERROR_SEVERITY level, const string message)
{
    string prefix = "";
    switch(level)
    {
        case ERROR_INFO:        prefix = "[ORCHESTRATOR-INFO] "; break;
        case ERROR_WARNING:     prefix = "[ORCHESTRATOR-WARN] "; break;
        case ERROR_RECOVERABLE: prefix = "[ORCHESTRATOR-ERROR] "; break;
        case ERROR_CRITICAL:    prefix = "[ORCHESTRATOR-CRITICAL] "; break;
        case ERROR_FATAL:       prefix = "[ORCHESTRATOR-FATAL] "; break;
        default:                prefix = "[ORCHESTRATOR] "; break;
    }
    
    Print(prefix + message);
}

//+------------------------------------------------------------------+
//| Task 3.4 Enhanced Ensemble Voting Methods                     |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Calculate Agreement Level                                       |
//+------------------------------------------------------------------+
double CAIStrategyOrchestrator::CalculateAgreementLevel(SEnsembleVote &votes[], int voteCount, ENUM_TRADE_SIGNAL signal)
{
    if(voteCount == 0 || signal == TRADE_SIGNAL_NONE)
        return 0.0;
    
    double totalWeight = 0.0;
    double agreementWeight = 0.0;
    
    for(int i = 0; i < voteCount; i++)
    {
        totalWeight += votes[i].adjustedWeight;
        if(votes[i].signal == signal)
        {
            agreementWeight += votes[i].adjustedWeight;
        }
    }
    
    return (totalWeight > 0.0) ? agreementWeight / totalWeight : 0.0;
}

//+------------------------------------------------------------------+
//| Calculate Disagreement Level                                   |
//+------------------------------------------------------------------+
double CAIStrategyOrchestrator::CalculateDisagreementLevel(SEnsembleVote &votes[], int voteCount)
{
    if(voteCount <= 1)
        return 0.0;
    
    double buyWeight = 0.0;
    double sellWeight = 0.0;
    double totalWeight = 0.0;
    
    for(int i = 0; i < voteCount; i++)
    {
        if(votes[i].signal == TRADE_SIGNAL_BUY)
            buyWeight += votes[i].adjustedWeight;
        else if(votes[i].signal == TRADE_SIGNAL_SELL)
            sellWeight += votes[i].adjustedWeight;
        
        totalWeight += votes[i].adjustedWeight;
    }
    
    if(totalWeight == 0.0)
        return 0.0;
    
    double buyRatio = buyWeight / totalWeight;
    double sellRatio = sellWeight / totalWeight;
    
    // High disagreement when both sides have significant weight
    return MathMin(buyRatio, sellRatio) * 2.0; // Scale to 0-1 range
}

//+------------------------------------------------------------------+
//| Check if Market Regime is Uncertain                           |
//+------------------------------------------------------------------+
bool CAIStrategyOrchestrator::IsRegimeUncertain(void)
{
    return (m_regimeConfidence < m_regimeUncertaintyThreshold);
}

//+------------------------------------------------------------------+
//| Apply Agreement Bonus to Confidence                           |
//+------------------------------------------------------------------+
void CAIStrategyOrchestrator::ApplyAgreementBonus(double &confidence, double agreementLevel)
{
    if(agreementLevel >= 0.7) // Strong agreement threshold
    {
        double bonus = m_agreementBonus * agreementLevel;
        confidence += bonus;
        confidence = MathMin(confidence, 1.0); // Cap at 1.0
        
        LogOrchestrationEvent(ERROR_INFO, 
                             StringFormat("Agreement bonus applied: %.1f%% agreement, +%.3f confidence", 
                                         agreementLevel * 100, bonus));
    }
}

//+------------------------------------------------------------------+
//| Apply Disagreement Penalty to Confidence                      |
//+------------------------------------------------------------------+
void CAIStrategyOrchestrator::ApplyDisagreementPenalty(double &confidence, double disagreementLevel)
{
    if(disagreementLevel > 0.3) // Significant disagreement threshold
    {
        double penalty = m_disagreementPenalty * disagreementLevel;
        confidence -= penalty;
        confidence = MathMax(confidence, 0.0); // Floor at 0.0
        
        LogOrchestrationEvent(ERROR_WARNING, 
                             StringFormat("Disagreement penalty applied: %.1f%% disagreement, -%.3f confidence", 
                                         disagreementLevel * 100, penalty));
    }
}

//+------------------------------------------------------------------+
//| Check if Trade Should be Skipped Due to Uncertainty          |
//+------------------------------------------------------------------+
bool CAIStrategyOrchestrator::ShouldSkipDueToUncertainty(double confidence)
{
    if(IsRegimeUncertain())
    {
        if(confidence < m_highConfidenceThreshold)
        {
            LogOrchestrationEvent(ERROR_INFO, 
                                 StringFormat("Trade skipped: Regime uncertain (%.2f), confidence (%.2f) below threshold (%.2f)", 
                                             m_regimeConfidence, confidence, m_highConfidenceThreshold));
            return true;
        }
        else
        {
            LogOrchestrationEvent(ERROR_INFO, 
                                 StringFormat("High confidence trade accepted despite regime uncertainty: %.2f >= %.2f", 
                                             confidence, m_highConfidenceThreshold));
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Log Detailed Voting Decision Reasoning                        |
//+------------------------------------------------------------------+
void CAIStrategyOrchestrator::LogVotingDecisionReasoning(SEnsembleVote &votes[], int voteCount, ENUM_TRADE_SIGNAL finalSignal, double confidence)
{
    if(voteCount == 0) return;
    
    // Calculate voting statistics
    int buyVotes = 0, sellVotes = 0, neutralVotes = 0;
    double buyWeight = 0.0, sellWeight = 0.0;
    double avgConfidence = 0.0;
    
    for(int i = 0; i < voteCount; i++)
    {
        if(votes[i].signal == TRADE_SIGNAL_BUY)
        {
            buyVotes++;
            buyWeight += votes[i].adjustedWeight;
        }
        else if(votes[i].signal == TRADE_SIGNAL_SELL)
        {
            sellVotes++;
            sellWeight += votes[i].adjustedWeight;
        }
        else
        {
            neutralVotes++;
        }
        
        avgConfidence += votes[i].confidence;
    }
    
    avgConfidence /= voteCount;
    
    string signalStr = "NONE";
    if(finalSignal == TRADE_SIGNAL_BUY) signalStr = "BUY";
    else if(finalSignal == TRADE_SIGNAL_SELL) signalStr = "SELL";
    
    LogOrchestrationEvent(ERROR_INFO, "ENSEMBLE VOTING SUMMARY:");
    LogOrchestrationEvent(ERROR_INFO, StringFormat("   Final Decision: %s | Final Confidence: %.3f", signalStr, confidence));
    LogOrchestrationEvent(ERROR_INFO, StringFormat("   Vote Count: BUY=%d (%.2f), SELL=%d (%.2f), NEUTRAL=%d", buyVotes, buyWeight, sellVotes, sellWeight, neutralVotes));
    LogOrchestrationEvent(ERROR_INFO, StringFormat("   Average Strategy Confidence: %.3f", avgConfidence));
            LogOrchestrationEvent(ERROR_INFO, 
                         StringFormat("   Market Regime: %s (Confidence: %.2f)", 
                                     EnumToString(m_currentRegime), m_regimeConfidence));
    
    // Log individual strategy votes
    LogOrchestrationEvent(ERROR_INFO, "   Individual Votes:");
    for(int i = 0; i < voteCount; i++)
    {
        string voteSignal = "NONE";
        if(votes[i].signal == TRADE_SIGNAL_BUY) voteSignal = "BUY";
        else if(votes[i].signal == TRADE_SIGNAL_SELL) voteSignal = "SELL";
        
        LogOrchestrationEvent(ERROR_INFO, 
                             StringFormat("     %s: %s | Conf: %.2f | Weight: %.2f | Adj.Weight: %.2f", 
                                         votes[i].strategyName, voteSignal, votes[i].confidence, 
                                         votes[i].weight, votes[i].adjustedWeight));
    }
    // }
}

//+------------------------------------------------------------------+
//| Get Current Ensemble Confidence                                 |
//+------------------------------------------------------------------+
double CAIStrategyOrchestrator::GetEnsembleConfidence(void)
{
    if(m_decisionCount > 0)
    {
        int lastIdx = (m_decisionIndex - 1 + 50) % 50;
        return m_recentDecisions[lastIdx].confidence;
    }
    return 0.0;
}

//+------------------------------------------------------------------+
//| Get Strategy Weights as JSON                                    |
//+------------------------------------------------------------------+
string CAIStrategyOrchestrator::GetStrategyWeightsJSON(void)
{
    string json = "{";
    json += "\"strategies\":[";
    
    for(int i = 0; i < m_strategyCount; i++)
    {
        if(i > 0) json += ",";
        json += StringFormat("{\"name\":\"%s\",\"weight\":%.2f,\"enabled\":%s}",
                            m_strategies[i].name,
                            m_strategies[i].weight,
                            m_strategies[i].enabled ? "true" : "false");
    }
    
    json += "]}";
    return json;
}

//+------------------------------------------------------------------+
//| Update Single Strategy Weight                                   |
//+------------------------------------------------------------------+
bool CAIStrategyOrchestrator::UpdateStrategyWeight(const string strategyName, const double newWeight)
{
    int index = FindStrategyIndex(strategyName);
    if(index < 0) return false;
    
    if(!ValidateWeight(newWeight)) return false;
    
    m_strategies[index].weight = newWeight;
    LogOrchestrationEvent(ERROR_INFO, StringFormat("Strategy weight manually updated: %s -> %.2f", strategyName, newWeight));
    return true;
}

#endif // CORE_AI_STRATEGY_ORCHESTRATOR_MQH
