//+------------------------------------------------------------------+
//| Strategy Management System                                     |
//| Manages multiple trading strategies and signal aggregation     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Windsurf AI"
#property link      "https://www.windsurf.ai"
#property version   "1.00"
#property strict

#ifndef CORE_STRATEGY_MANAGER_MQH
#define CORE_STRATEGY_MANAGER_MQH

#include "Enums.mqh"
#include "ErrorHandling.mqh"
#include "../Interfaces/IStrategy.mqh"

//+------------------------------------------------------------------+
//| Strategy Entry Structure                                       |
//+------------------------------------------------------------------+
struct SStrategyEntry
{
    IStrategy* strategy;        // Strategy pointer
    double weight;              // Strategy weight
    bool enabled;               // Strategy enabled flag
    datetime lastUpdate;        // Last update time
    int signalCount;           // Total signals generated
    int successfulSignals;     // Successful signals
    double accuracy;           // Signal accuracy
};

//+------------------------------------------------------------------+
//| Strategy Manager Class                                         |
//+------------------------------------------------------------------+
class CStrategyManager : public CEnhancedErrorHandler
{
private:
    SStrategyEntry m_strategies[MAX_STRATEGIES];  // Strategy array
    int m_strategyCount;                          // Number of strategies
    double m_totalWeight;                         // Total weight of all strategies
    
    // Signal aggregation
    double m_minConfidence;                       // Minimum confidence threshold
    bool m_useWeightedSignals;                    // Use weighted signal aggregation
    
    // Performance tracking
    int m_totalSignals;                           // Total signals generated
    int m_successfulSignals;                      // Successful signals
    datetime m_lastSignalTime;                    // Last signal generation time
    
    bool m_initialized;
    
public:
    // Constructor
    CStrategyManager(void);
    
    // Destructor
    ~CStrategyManager(void);
    
    // Initialize strategy manager
    bool Initialize(const double minConfidence = 0.5, const bool useWeighted = true);
    
    // Strategy management
    bool AddStrategy(IStrategy* strategy, const double weight = 1.0);
    bool RemoveStrategy(const string strategyName);
    bool EnableStrategy(const string strategyName, const bool enabled = true);
    bool SetStrategyWeight(const string strategyName, const double weight);
    
    // Signal generation
    ENUM_TRADE_SIGNAL GetSignal(const string symbol, const ENUM_TIMEFRAMES timeframe, double &confidence);
    ENUM_TRADE_SIGNAL GetAggregatedSignal(const string symbol, const ENUM_TIMEFRAMES timeframe, double &confidence);
    
    // Strategy updates
    void OnNewBar(const string symbol, const ENUM_TIMEFRAMES timeframe);
    void UpdateAllStrategies(void);
    
    // Information functions
    int GetStrategyCount(void) const { return m_strategyCount; }
    int GetEnabledStrategyCount(void);
    double GetTotalWeight(void) const { return m_totalWeight; }
    
    // Performance tracking
    void RecordSignalResult(const bool successful);
    double GetSignalAccuracy(void);
    void GetOverallStatistics(int &total, int &successful, double &accuracy);
    
    // Strategy information
    bool GetStrategyInfo(const int index, string &name, double &weight, bool &enabled, double &accuracy);
    IStrategy* GetStrategy(const string strategyName);
    IStrategy* GetStrategy(const int index);
    
    // Configuration
    void SetMinConfidence(const double minConfidence) { m_minConfidence = minConfidence; }
    void SetUseWeightedSignals(const bool useWeighted) { m_useWeightedSignals = useWeighted; }
    
    // Market regime adaptation
    void AdaptToMarketRegime(ENUM_MARKET_REGIME regime, double regimeConfidence);
    void SetRegimeBasedWeights(ENUM_MARKET_REGIME regime);
    
    // Market condition-based strategy selection (Task 3.3)
    void ApplyVolatilityBasedFiltering(double volatilityLevel, double volatilityThreshold = 0.02);
    void ApplyTrendStrengthWeighting(double trendStrength, double trendThreshold = 0.5);
    void LogMarketConditionSelection(ENUM_MARKET_REGIME regime, double volatility, double trendStrength);
    bool IsStrategyValidForVolatility(const string strategyName, double volatilityLevel);
    double GetTrendBasedWeight(const string strategyName, double trendStrength);
    
    // Reporting
    void PrintStrategyReport(void);
    string GetStrategySummary(void);
    
private:
    // Internal functions
    int FindStrategyIndex(const string strategyName);
    void UpdateTotalWeight(void);
    void UpdateStrategyStatistics(const int index);
    
    // Signal processing
    ENUM_TRADE_SIGNAL ProcessSignals(double &signals[], double &weights[], int count, double &confidence);
    double CalculateWeightedConfidence(double &signals[], double &weights[], double &confidences[], int count);
    
    // Validation
    bool ValidateStrategy(IStrategy* strategy);
    bool ValidateWeight(const double weight);
    
    // Logging
    void LogStrategyEvent(const ENUM_ERROR_LEVEL level, const string message);
};

//+------------------------------------------------------------------+
//| Constructor                                                     |
//+------------------------------------------------------------------+
CStrategyManager::CStrategyManager(void) :
    m_strategyCount(0),
    m_totalWeight(0.0),
    m_minConfidence(0.5),
    m_useWeightedSignals(true),
    m_totalSignals(0),
    m_successfulSignals(0),
    m_lastSignalTime(0),
    m_initialized(false)
{
    // Initialize strategy array
    for(int i = 0; i < MAX_STRATEGIES; i++)
    {
        m_strategies[i].strategy = NULL;
        m_strategies[i].weight = 0.0;
        m_strategies[i].enabled = false;
        m_strategies[i].lastUpdate = 0;
        m_strategies[i].signalCount = 0;
        m_strategies[i].successfulSignals = 0;
        m_strategies[i].accuracy = 0.0;
    }
}

//+------------------------------------------------------------------+
//| Destructor                                                      |
//+------------------------------------------------------------------+
CStrategyManager::~CStrategyManager(void)
{
    if(m_initialized)
    {
        PrintStrategyReport();
        
        // Clean up strategies
        for(int i = 0; i < m_strategyCount; i++)
        {
            if(CheckPointer(m_strategies[i].strategy) != POINTER_INVALID)
            {
                delete m_strategies[i].strategy;
                m_strategies[i].strategy = NULL;
            }
        }
        
        LogStrategyEvent(ERROR_LEVEL_INFO, "Strategy manager destroyed");
    }
}

//+------------------------------------------------------------------+
//| Initialize Strategy Manager                                    |
//+------------------------------------------------------------------+
bool CStrategyManager::Initialize(const double minConfidence = 0.5, const bool useWeighted = true)
{
    if(minConfidence < 0.0 || minConfidence > 1.0)
    {
        LogStrategyEvent(ERROR_LEVEL_ERROR, "Invalid minimum confidence value");
        return false;
    }
    
    m_minConfidence = minConfidence;
    m_useWeightedSignals = useWeighted;
    m_initialized = true;
    
    LogStrategyEvent(ERROR_LEVEL_INFO, 
                    StringFormat("Strategy manager initialized - Min confidence: %.2f, Weighted: %s", 
                                m_minConfidence, m_useWeightedSignals ? "Yes" : "No"));
    
    return true;
}

//+------------------------------------------------------------------+
//| Add Strategy                                                   |
//+------------------------------------------------------------------+
bool CStrategyManager::AddStrategy(IStrategy* strategy, const double weight = 1.0)
{
    if(!m_initialized)
    {
        LogStrategyEvent(ERROR_LEVEL_ERROR, "Strategy manager not initialized");
        return false;
    }
    
    if(!ValidateStrategy(strategy))
    {
        LogStrategyEvent(ERROR_LEVEL_ERROR, "Invalid strategy pointer");
        return false;
    }
    
    if(!ValidateWeight(weight))
    {
        LogStrategyEvent(ERROR_LEVEL_ERROR, "Invalid strategy weight");
        return false;
    }
    
    if(m_strategyCount >= MAX_STRATEGIES)
    {
        LogStrategyEvent(ERROR_LEVEL_ERROR, "Maximum strategies limit reached");
        return false;
    }
    
    // Check for duplicate strategy names
    string strategyName = strategy.GetName();
    if(FindStrategyIndex(strategyName) >= 0)
    {
        LogStrategyEvent(ERROR_LEVEL_WARNING, "Strategy already exists: " + strategyName);
        return false;
    }
    
    // Add strategy
    m_strategies[m_strategyCount].strategy = strategy;
    m_strategies[m_strategyCount].weight = weight;
    m_strategies[m_strategyCount].enabled = true;
    m_strategies[m_strategyCount].lastUpdate = TimeCurrent();
    m_strategies[m_strategyCount].signalCount = 0;
    m_strategies[m_strategyCount].successfulSignals = 0;
    m_strategies[m_strategyCount].accuracy = 0.0;
    
    m_strategyCount++;
    UpdateTotalWeight();
    
    LogStrategyEvent(ERROR_LEVEL_INFO, 
                    StringFormat("Strategy added: %s (Weight: %.2f)", strategyName, weight));
    
    return true;
}

//+------------------------------------------------------------------+
//| Remove Strategy                                                |
//+------------------------------------------------------------------+
bool CStrategyManager::RemoveStrategy(const string strategyName)
{
    int index = FindStrategyIndex(strategyName);
    if(index < 0)
    {
        LogStrategyEvent(ERROR_LEVEL_WARNING, "Strategy not found: " + strategyName);
        return false;
    }
    
    // Delete strategy object
    if(CheckPointer(m_strategies[index].strategy) != POINTER_INVALID)
    {
        delete m_strategies[index].strategy;
    }
    
    // Shift remaining strategies
    for(int i = index; i < m_strategyCount - 1; i++)
    {
        m_strategies[i] = m_strategies[i + 1];
    }
    
    // Clear last entry
    m_strategies[m_strategyCount - 1].strategy = NULL;
    m_strategies[m_strategyCount - 1].weight = 0.0;
    m_strategies[m_strategyCount - 1].enabled = false;
    
    m_strategyCount--;
    UpdateTotalWeight();
    
    LogStrategyEvent(ERROR_LEVEL_INFO, "Strategy removed: " + strategyName);
    
    return true;
}

//+------------------------------------------------------------------+
//| Enable/Disable Strategy                                       |
//+------------------------------------------------------------------+
bool CStrategyManager::EnableStrategy(const string strategyName, const bool enabled = true)
{
    int index = FindStrategyIndex(strategyName);
    if(index < 0)
    {
        LogStrategyEvent(ERROR_LEVEL_WARNING, "Strategy not found: " + strategyName);
        return false;
    }
    
    m_strategies[index].enabled = enabled;
    UpdateTotalWeight();
    
    LogStrategyEvent(ERROR_LEVEL_INFO, 
                    StringFormat("Strategy %s: %s", strategyName, enabled ? "ENABLED" : "DISABLED"));
    
    return true;
}

//+------------------------------------------------------------------+
//| Set Strategy Weight                                            |
//+------------------------------------------------------------------+
bool CStrategyManager::SetStrategyWeight(const string strategyName, const double weight)
{
    if(!ValidateWeight(weight))
    {
        LogStrategyEvent(ERROR_LEVEL_ERROR, "Invalid weight value");
        return false;
    }
    
    int index = FindStrategyIndex(strategyName);
    if(index < 0)
    {
        LogStrategyEvent(ERROR_LEVEL_WARNING, "Strategy not found: " + strategyName);
        return false;
    }
    
    m_strategies[index].weight = weight;
    UpdateTotalWeight();
    
    LogStrategyEvent(ERROR_LEVEL_INFO, 
                    StringFormat("Strategy %s weight updated: %.2f", strategyName, weight));
    
    return true;
}

//+------------------------------------------------------------------+
//| Get Trading Signal                                             |
//+------------------------------------------------------------------+
ENUM_TRADE_SIGNAL CStrategyManager::GetSignal(const string symbolParam, const ENUM_TIMEFRAMES timeframe, double &confidence)
{
    if(!m_initialized)
    {
        confidence = 0.0;
        return TRADE_SIGNAL_NONE;
    }
    
    if(m_useWeightedSignals)
        return GetAggregatedSignal(symbolParam, timeframe, confidence);
    
    // Simple majority voting
    int buySignals = 0;
    int sellSignals = 0;
    double totalConfidence = 0.0;
    int activeStrategies = 0;
    
    for(int i = 0; i < m_strategyCount; i++)
    {
        if(!m_strategies[i].enabled || CheckPointer(m_strategies[i].strategy) == POINTER_INVALID)
            continue;
        
        double strategyConfidence = 0.0;
        ENUM_TRADE_SIGNAL signal = m_strategies[i].strategy.GetSignal(strategyConfidence);
        
        if(signal != TRADE_SIGNAL_NONE && strategyConfidence >= m_minConfidence)
        {
            if(signal == TRADE_SIGNAL_BUY)
                buySignals++;
            else if(signal == TRADE_SIGNAL_SELL)
                sellSignals++;
            
            totalConfidence += strategyConfidence;
            activeStrategies++;
            
            m_strategies[i].signalCount++;
            m_strategies[i].lastUpdate = TimeCurrent();
        }
    }
    
    // Determine final signal
    ENUM_TRADE_SIGNAL finalSignal = TRADE_SIGNAL_NONE;
    
    if(buySignals > sellSignals)
        finalSignal = TRADE_SIGNAL_BUY;
    else if(sellSignals > buySignals)
        finalSignal = TRADE_SIGNAL_SELL;
    
    // Calculate average confidence
    confidence = (activeStrategies > 0) ? totalConfidence / activeStrategies : 0.0;
    
    if(finalSignal != TRADE_SIGNAL_NONE)
    {
        m_totalSignals++;
        m_lastSignalTime = TimeCurrent();
        
        LogStrategyEvent(ERROR_LEVEL_INFO, 
                        StringFormat("Signal generated: %s | Confidence: %.2f | Active strategies: %d", 
                                    (finalSignal == TRADE_SIGNAL_BUY ? "BUY" : "SELL"), 
                                    confidence, activeStrategies));
    }
    
    return finalSignal;
}

//+------------------------------------------------------------------+
//| Get Aggregated Signal (Weighted)                              |
//+------------------------------------------------------------------+
ENUM_TRADE_SIGNAL CStrategyManager::GetAggregatedSignal(const string symbolParam, const ENUM_TIMEFRAMES timeframe, double &confidence)
{
    double signals[MAX_STRATEGIES];
    double weights[MAX_STRATEGIES];
    double confidences[MAX_STRATEGIES];
    int validSignals = 0;
    
    // Collect signals from all enabled strategies
    for(int i = 0; i < m_strategyCount; i++)
    {
        if(!m_strategies[i].enabled || CheckPointer(m_strategies[i].strategy) == POINTER_INVALID)
            continue;
        
        double strategyConfidence = 0.0;
        ENUM_TRADE_SIGNAL signal = m_strategies[i].strategy.GetSignal(strategyConfidence);
        
        if(signal != TRADE_SIGNAL_NONE && strategyConfidence >= m_minConfidence)
        {
            signals[validSignals] = (double)signal;
            weights[validSignals] = m_strategies[i].weight;
            confidences[validSignals] = strategyConfidence;
            validSignals++;
            
            m_strategies[i].signalCount++;
            m_strategies[i].lastUpdate = TimeCurrent();
        }
    }
    
    if(validSignals == 0)
    {
        confidence = 0.0;
        return TRADE_SIGNAL_NONE;
    }
    
    // Process weighted signals
    ENUM_TRADE_SIGNAL finalSignal = ProcessSignals(signals, weights, validSignals, confidence);
    
    if(finalSignal != TRADE_SIGNAL_NONE)
    {
        m_totalSignals++;
        m_lastSignalTime = TimeCurrent();
        
        LogStrategyEvent(ERROR_LEVEL_INFO, 
                        StringFormat("Weighted signal: %s | Confidence: %.2f | Strategies: %d", 
                                    (finalSignal == TRADE_SIGNAL_BUY ? "BUY" : "SELL"), 
                                    confidence, validSignals));
    }
    
    return finalSignal;
}

//+------------------------------------------------------------------+
//| Update Strategies on New Bar                                  |
//+------------------------------------------------------------------+
void CStrategyManager::OnNewBar(const string symbolParam, const ENUM_TIMEFRAMES timeframe)
{
    if(!m_initialized) return;
    
    for(int i = 0; i < m_strategyCount; i++)
    {
        if(m_strategies[i].enabled && CheckPointer(m_strategies[i].strategy) != POINTER_INVALID)
        {
            m_strategies[i].strategy.OnNewBar();
            m_strategies[i].lastUpdate = TimeCurrent();
        }
    }
}

//+------------------------------------------------------------------+
//| Update All Strategies                                          |
//+------------------------------------------------------------------+
void CStrategyManager::UpdateAllStrategies(void)
{
    if(!m_initialized) return;
    
    for(int i = 0; i < m_strategyCount; i++)
    {
        if(m_strategies[i].enabled && CheckPointer(m_strategies[i].strategy) != POINTER_INVALID)
        {
            UpdateStrategyStatistics(i);
        }
    }
}

//+------------------------------------------------------------------+
//| Get Enabled Strategy Count                                     |
//+------------------------------------------------------------------+
int CStrategyManager::GetEnabledStrategyCount(void)
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
//| Record Signal Result                                           |
//+------------------------------------------------------------------+
void CStrategyManager::RecordSignalResult(const bool successful)
{
    if(successful)
        m_successfulSignals++;
    
    // Update individual strategy statistics
    for(int i = 0; i < m_strategyCount; i++)
    {
        if(m_strategies[i].enabled && m_strategies[i].lastUpdate == m_lastSignalTime)
        {
            if(successful)
                m_strategies[i].successfulSignals++;
            
            UpdateStrategyStatistics(i);
        }
    }
}

//+------------------------------------------------------------------+
//| Get Signal Accuracy                                           |
//+------------------------------------------------------------------+
double CStrategyManager::GetSignalAccuracy(void)
{
    if(m_totalSignals == 0)
        return 0.0;
    
    return ((double)m_successfulSignals / m_totalSignals) * 100.0;
}

//+------------------------------------------------------------------+
//| Get Overall Statistics                                         |
//+------------------------------------------------------------------+
void CStrategyManager::GetOverallStatistics(int &total, int &successful, double &accuracy)
{
    total = m_totalSignals;
    successful = m_successfulSignals;
    accuracy = GetSignalAccuracy();
}

//+------------------------------------------------------------------+
//| Get Strategy Information                                       |
//+------------------------------------------------------------------+
bool CStrategyManager::GetStrategyInfo(const int index, string &name, double &weight, bool &enabled, double &accuracy)
{
    if(index < 0 || index >= m_strategyCount)
        return false;
    
    if(CheckPointer(m_strategies[index].strategy) == POINTER_INVALID)
        return false;
    
    name = m_strategies[index].strategy.GetName();
    weight = m_strategies[index].weight;
    enabled = m_strategies[index].enabled;
    accuracy = m_strategies[index].accuracy;
    
    return true;
}

//+------------------------------------------------------------------+
//| Get Strategy by Name                                           |
//+------------------------------------------------------------------+
IStrategy* CStrategyManager::GetStrategy(const string strategyName)
{
    int index = FindStrategyIndex(strategyName);
    if(index >= 0)
        return m_strategies[index].strategy;
    
    return NULL;
}

//+------------------------------------------------------------------+
//| Get Strategy by Index                                          |
//+------------------------------------------------------------------+
IStrategy* CStrategyManager::GetStrategy(const int index)
{
    if(index >= 0 && index < m_strategyCount)
        return m_strategies[index].strategy;
    
    return NULL;
}

//+------------------------------------------------------------------+
//| Print Strategy Report                                          |
//+------------------------------------------------------------------+
void CStrategyManager::PrintStrategyReport(void)
{
    if(!m_initialized) return;
    
    Print("\n=== STRATEGY MANAGER REPORT ===");
    Print("📊 OVERALL STATISTICS:");
    Print("   Total Strategies: ", m_strategyCount);
    Print("   Enabled Strategies: ", GetEnabledStrategyCount());
    Print("   Total Signals: ", m_totalSignals);
    Print("   Successful Signals: ", m_successfulSignals);
    Print("   Overall Accuracy: ", DoubleToString(GetSignalAccuracy(), 1), "%");
    Print("   Total Weight: ", DoubleToString(m_totalWeight, 2));
    
    Print("\n🎯 STRATEGY DETAILS:");
    for(int i = 0; i < m_strategyCount; i++)
    {
        if(CheckPointer(m_strategies[i].strategy) != POINTER_INVALID)
        {
            string name = m_strategies[i].strategy.GetName();
            Print("   ", i+1, ". ", name, 
                  " | Weight: ", DoubleToString(m_strategies[i].weight, 2),
                  " | Enabled: ", m_strategies[i].enabled ? "YES" : "NO",
                  " | Signals: ", m_strategies[i].signalCount,
                  " | Accuracy: ", DoubleToString(m_strategies[i].accuracy, 1), "%");
        }
    }
    
    Print("\n⚙️ CONFIGURATION:");
    Print("   Min Confidence: ", DoubleToString(m_minConfidence, 2));
    Print("   Weighted Signals: ", m_useWeightedSignals ? "YES" : "NO");
    Print("   Last Signal: ", TimeToString(m_lastSignalTime));
    
    Print("===============================\n");
}

//+------------------------------------------------------------------+
//| Get Strategy Summary                                           |
//+------------------------------------------------------------------+
string CStrategyManager::GetStrategySummary(void)
{
    if(!m_initialized)
        return "Strategy manager not initialized";
    
    return StringFormat("Strategies: %d/%d | Signals: %d | Accuracy: %.1f%% | Weight: %.1f",
                       GetEnabledStrategyCount(), m_strategyCount, m_totalSignals, 
                       GetSignalAccuracy(), m_totalWeight);
}

//+------------------------------------------------------------------+
//| Find Strategy Index                                            |
//+------------------------------------------------------------------+
int CStrategyManager::FindStrategyIndex(const string strategyName)
{
    for(int i = 0; i < m_strategyCount; i++)
    {
        if(CheckPointer(m_strategies[i].strategy) != POINTER_INVALID)
        {
            if(m_strategies[i].strategy.GetName() == strategyName)
                return i;
        }
    }
    return -1;
}

//+------------------------------------------------------------------+
//| Update Total Weight                                            |
//+------------------------------------------------------------------+
void CStrategyManager::UpdateTotalWeight(void)
{
    m_totalWeight = 0.0;
    for(int i = 0; i < m_strategyCount; i++)
    {
        if(m_strategies[i].enabled)
            m_totalWeight += m_strategies[i].weight;
    }
}

//+------------------------------------------------------------------+
//| Update Strategy Statistics                                     |
//+------------------------------------------------------------------+
void CStrategyManager::UpdateStrategyStatistics(const int index)
{
    if(index < 0 || index >= m_strategyCount)
        return;
    
    if(m_strategies[index].signalCount > 0)
    {
        m_strategies[index].accuracy = ((double)m_strategies[index].successfulSignals / 
                                       m_strategies[index].signalCount) * 100.0;
    }
    else
    {
        m_strategies[index].accuracy = 0.0;
    }
}

//+------------------------------------------------------------------+
//| Process Signals                                               |
//+------------------------------------------------------------------+
ENUM_TRADE_SIGNAL CStrategyManager::ProcessSignals(double &signals[], double &weights[], int count, double &confidence)
{
    if(count == 0)
    {
        confidence = 0.0;
        return TRADE_SIGNAL_NONE;
    }
    
    double weightedSum = 0.0;
    double totalWeight = 0.0;
    
    for(int i = 0; i < count; i++)
    {
        weightedSum += signals[i] * weights[i];
        totalWeight += weights[i];
    }
    
    if(totalWeight == 0.0)
    {
        confidence = 0.0;
        return TRADE_SIGNAL_NONE;
    }
    
    double averageSignal = weightedSum / totalWeight;
    confidence = MathAbs(averageSignal);
    
    if(averageSignal > 0.1)
        return TRADE_SIGNAL_BUY;
    else if(averageSignal < -0.1)
        return TRADE_SIGNAL_SELL;
    else
        return TRADE_SIGNAL_NONE;
}

//+------------------------------------------------------------------+
//| Calculate Weighted Confidence                                  |
//+------------------------------------------------------------------+
double CStrategyManager::CalculateWeightedConfidence(double &signals[], double &weights[], double &confidences[], int count)
{
    if(count == 0) return 0.0;
    
    double weightedConfidence = 0.0;
    double totalWeight = 0.0;
    
    for(int i = 0; i < count; i++)
    {
        weightedConfidence += confidences[i] * weights[i];
        totalWeight += weights[i];
    }
    
    return (totalWeight > 0.0) ? weightedConfidence / totalWeight : 0.0;
}

//+------------------------------------------------------------------+
//| Validate Strategy                                              |
//+------------------------------------------------------------------+
bool CStrategyManager::ValidateStrategy(IStrategy* strategy)
{
    if(CheckPointer(strategy) == POINTER_INVALID)
        return false;
    
    // Additional validation could be added here
    return true;
}

//+------------------------------------------------------------------+
//| Validate Weight                                                |
//+------------------------------------------------------------------+
bool CStrategyManager::ValidateWeight(const double weight)
{
    return (weight >= 0.0 && weight <= 10.0);
}

//+------------------------------------------------------------------+
//| Adapt Strategy Weights Based on Market Regime                 |
//+------------------------------------------------------------------+
void CStrategyManager::AdaptToMarketRegime(ENUM_MARKET_REGIME regime, double regimeConfidence)
{
    if(!m_initialized || regimeConfidence < 0.5) return;
    
    LogStrategyEvent(ERROR_LEVEL_INFO, 
                    StringFormat("Adapting strategies to regime: %s (Confidence: %.2f)", 
                                EnumToString(regime), regimeConfidence));
    
    // Apply regime-specific strategy weights
    SetRegimeBasedWeights(regime);
    
    // Update total weight after regime adaptation
    UpdateTotalWeight();
    
    LogStrategyEvent(ERROR_LEVEL_INFO, 
                    StringFormat("Regime adaptation complete - New total weight: %.2f", m_totalWeight));
}

//+------------------------------------------------------------------+
//| Set Strategy Weights Based on Market Regime                   |
//+------------------------------------------------------------------+
void CStrategyManager::SetRegimeBasedWeights(ENUM_MARKET_REGIME regime)
{
    for(int i = 0; i < m_strategyCount; i++)
    {
        if(CheckPointer(m_strategies[i].strategy) == POINTER_INVALID) continue;
        
        string strategyName = m_strategies[i].strategy.GetName();
        double originalWeight = m_strategies[i].weight;
        double newWeight = originalWeight;
        
        // Regime-specific strategy weighting
        switch(regime)
        {
            case MARKET_REGIME_TRENDING:
                // Favor trend-following strategies
                if(StringFind(strategyName, "RSI") >= 0) newWeight = originalWeight * 1.2;
                else if(StringFind(strategyName, "Elliott") >= 0) newWeight = originalWeight * 1.3;
                else if(StringFind(strategyName, "Swing") >= 0) newWeight = originalWeight * 1.4;
                else if(StringFind(strategyName, "SupplyDemand") >= 0) newWeight = originalWeight * 0.8;
                else if(StringFind(strategyName, "OrderBlock") >= 0) newWeight = originalWeight * 0.9;
                break;
                
            case MARKET_REGIME_RANGING:
                // Favor mean-reversion and support/resistance strategies
                if(StringFind(strategyName, "SupplyDemand") >= 0) newWeight = originalWeight * 1.4;
                else if(StringFind(strategyName, "OrderBlock") >= 0) newWeight = originalWeight * 1.3;
                else if(StringFind(strategyName, "Fibonacci") >= 0) newWeight = originalWeight * 1.2;
                else if(StringFind(strategyName, "RSI") >= 0) newWeight = originalWeight * 1.1;
                else if(StringFind(strategyName, "Swing") >= 0) newWeight = originalWeight * 0.7;
                else if(StringFind(strategyName, "Elliott") >= 0) newWeight = originalWeight * 0.6;
                break;
                
            case MARKET_REGIME_VOLATILE:
                // Reduce all strategy weights and favor breakout strategies
                if(StringFind(strategyName, "OrderBlock") >= 0) newWeight = originalWeight * 1.1;
                else if(StringFind(strategyName, "SupplyDemand") >= 0) newWeight = originalWeight * 1.0;
                else newWeight = originalWeight * 0.8; // Reduce other strategies
                break;
                
            case MARKET_REGIME_LOW_VOLATILITY:
                // Favor scalping and short-term strategies
                if(StringFind(strategyName, "RSI") >= 0) newWeight = originalWeight * 1.2;
                else if(StringFind(strategyName, "Fibonacci") >= 0) newWeight = originalWeight * 1.1;
                else if(StringFind(strategyName, "Swing") >= 0) newWeight = originalWeight * 0.8;
                else if(StringFind(strategyName, "Elliott") >= 0) newWeight = originalWeight * 0.7;
                break;
                
            default:
                // Unknown regime - use original weights
                newWeight = originalWeight;
                break;
        }
        
        // Apply the new weight
        m_strategies[i].weight = newWeight;
        
        LogStrategyEvent(ERROR_LEVEL_INFO, 
                        StringFormat("Strategy %s weight: %.2f -> %.2f (Regime: %s)", 
                                    strategyName, originalWeight, newWeight, EnumToString(regime)));
    }
}

//+------------------------------------------------------------------+
//| Apply Volatility-Based Strategy Filtering (Task 3.3)         |
//+------------------------------------------------------------------+
void CStrategyManager::ApplyVolatilityBasedFiltering(double volatilityLevel, double volatilityThreshold = 0.02)
{
    if(!m_initialized) return;
    
    LogStrategyEvent(ERROR_LEVEL_INFO, 
                    StringFormat("Applying volatility-based filtering - Level: %.4f, Threshold: %.4f", 
                                volatilityLevel, volatilityThreshold));
    
    for(int i = 0; i < m_strategyCount; i++)
    {
        if(CheckPointer(m_strategies[i].strategy) == POINTER_INVALID) continue;
        
        string strategyName = m_strategies[i].strategy.GetName();
        bool wasEnabled = m_strategies[i].enabled;
        
        // Check if strategy is valid for current volatility
        bool isValidForVolatility = IsStrategyValidForVolatility(strategyName, volatilityLevel);
        
        if(!isValidForVolatility && wasEnabled)
        {
            m_strategies[i].enabled = false;
            LogStrategyEvent(ERROR_LEVEL_INFO, 
                            StringFormat("Strategy %s disabled due to volatility filter (Level: %.4f)", 
                                        strategyName, volatilityLevel));
        }
        else if(isValidForVolatility && !wasEnabled && volatilityLevel <= volatilityThreshold * 1.5)
        {
            // Re-enable if volatility normalizes
            m_strategies[i].enabled = true;
            LogStrategyEvent(ERROR_LEVEL_INFO, 
                            StringFormat("Strategy %s re-enabled as volatility normalized (Level: %.4f)", 
                                        strategyName, volatilityLevel));
        }
    }
    
    UpdateTotalWeight();
}

//+------------------------------------------------------------------+
//| Apply Trend Strength-Based Strategy Weighting (Task 3.3)     |
//+------------------------------------------------------------------+
void CStrategyManager::ApplyTrendStrengthWeighting(double trendStrength, double trendThreshold = 0.5)
{
    if(!m_initialized) return;
    
    LogStrategyEvent(ERROR_LEVEL_INFO, 
                    StringFormat("Applying trend strength weighting - Strength: %.3f, Threshold: %.3f", 
                                trendStrength, trendThreshold));
    
    for(int i = 0; i < m_strategyCount; i++)
    {
        if(CheckPointer(m_strategies[i].strategy) == POINTER_INVALID || !m_strategies[i].enabled) continue;
        
        string strategyName = m_strategies[i].strategy.GetName();
        double originalWeight = m_strategies[i].weight;
        
        // Get trend-based weight multiplier
        double trendMultiplier = GetTrendBasedWeight(strategyName, trendStrength);
        double newWeight = originalWeight * trendMultiplier;
        
        // Apply bounds checking
        if(newWeight < 0.1) newWeight = 0.1;
        if(newWeight > 3.0) newWeight = 3.0;
        
        m_strategies[i].weight = newWeight;
        
        if(MathAbs(newWeight - originalWeight) > 0.05) // Log significant changes
        {
            LogStrategyEvent(ERROR_LEVEL_INFO, 
                            StringFormat("Strategy %s trend weight: %.2f -> %.2f (Strength: %.3f)", 
                                        strategyName, originalWeight, newWeight, trendStrength));
        }
    }
    
    UpdateTotalWeight();
}

//+------------------------------------------------------------------+
//| Log Market Condition Selection for Audit (Task 3.3)          |
//+------------------------------------------------------------------+
void CStrategyManager::LogMarketConditionSelection(ENUM_MARKET_REGIME regime, double volatility, double trendStrength)
{
    if(!m_initialized) return;
    
    // Create detailed market condition log entry
    string logEntry = StringFormat(
        "MARKET_CONDITION_AUDIT | Time: %s | Regime: %s | Volatility: %.4f | Trend: %.3f | Active Strategies: %d/%d",
        TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS),
        EnumToString(regime),
        volatility,
        trendStrength,
        GetEnabledStrategyCount(),
        m_strategyCount
    );
    
    // Add individual strategy status
    string strategyStatus = " | Strategy Status: ";
    for(int i = 0; i < m_strategyCount; i++)
    {
        if(CheckPointer(m_strategies[i].strategy) == POINTER_INVALID) continue;
        
        string name = m_strategies[i].strategy.GetName();
        strategyStatus += StringFormat("%s(%.2f,%s)", 
                                      name, 
                                      m_strategies[i].weight, 
                                      m_strategies[i].enabled ? "ON" : "OFF");
        if(i < m_strategyCount - 1) strategyStatus += ",";
    }
    
    LogStrategyEvent(ERROR_LEVEL_INFO, logEntry + strategyStatus);
    
    // Also log to file for audit trail
    int fileHandle = FileOpen("MarketConditionAudit.log", FILE_WRITE|FILE_TXT|FILE_ANSI, '\t');
    if(fileHandle != INVALID_HANDLE)
    {
        FileWrite(fileHandle, logEntry + strategyStatus);
        FileClose(fileHandle);
    }
}

//+------------------------------------------------------------------+
//| Check if Strategy is Valid for Current Volatility (Task 3.3)  |
//+------------------------------------------------------------------+
bool CStrategyManager::IsStrategyValidForVolatility(const string strategyName, double volatilityLevel)
{
    // Define volatility thresholds for different strategy types
    double lowVolThreshold = 0.01;   // 1% volatility
    double medVolThreshold = 0.02;   // 2% volatility  
    double highVolThreshold = 0.04;  // 4% volatility
    
    // Strategy-specific volatility filtering
    if(StringFind(strategyName, "Swing") >= 0)
    {
        // Swing strategies need moderate to high volatility
        return (volatilityLevel >= lowVolThreshold && volatilityLevel <= highVolThreshold * 2);
    }
    else if(StringFind(strategyName, "Elliott") >= 0)
    {
        // Elliott Wave needs clear trends, avoid extreme volatility
        return (volatilityLevel >= lowVolThreshold && volatilityLevel <= highVolThreshold);
    }
    else if(StringFind(strategyName, "RSI") >= 0)
    {
        // RSI works well in most volatility conditions but struggles in extreme volatility
        return (volatilityLevel <= highVolThreshold * 1.5);
    }
    else if(StringFind(strategyName, "SupplyDemand") >= 0 || StringFind(strategyName, "OrderBlock") >= 0)
    {
        // S/D and OrderBlock strategies work better in moderate volatility
        return (volatilityLevel >= lowVolThreshold * 0.5 && volatilityLevel <= medVolThreshold * 2);
    }
    else if(StringFind(strategyName, "Fibonacci") >= 0)
    {
        // Fibonacci retracements work in trending markets with moderate volatility
        return (volatilityLevel >= lowVolThreshold && volatilityLevel <= medVolThreshold * 1.5);
    }
    else if(StringFind(strategyName, "Brain") >= 0 || StringFind(strategyName, "AI") >= 0)
    {
        // AI strategies should adapt to all volatility conditions
        return true;
    }
    
    // Default: allow strategy in normal volatility ranges
    return (volatilityLevel <= highVolThreshold);
}

//+------------------------------------------------------------------+
//| Get Trend-Based Weight Multiplier (Task 3.3)                 |
//+------------------------------------------------------------------+
double CStrategyManager::GetTrendBasedWeight(const string strategyName, double trendStrength)
{
    // Normalize trend strength to 0-1 range (assuming input is -1 to 1)
    double normalizedTrend = MathAbs(trendStrength);
    
    // Strategy-specific trend strength weighting
    if(StringFind(strategyName, "Swing") >= 0)
    {
        // Swing strategies perform better in strong trends
        return 0.8 + (normalizedTrend * 0.6); // Range: 0.8 - 1.4
    }
    else if(StringFind(strategyName, "Elliott") >= 0)
    {
        // Elliott Wave excels in trending markets
        return 0.7 + (normalizedTrend * 0.8); // Range: 0.7 - 1.5
    }
    else if(StringFind(strategyName, "RSI") >= 0)
    {
        // RSI can work in both trending and ranging, slight preference for trends
        return 0.9 + (normalizedTrend * 0.3); // Range: 0.9 - 1.2
    }
    else if(StringFind(strategyName, "SupplyDemand") >= 0 || StringFind(strategyName, "OrderBlock") >= 0)
    {
        // S/D and OrderBlock work better in ranging markets (inverse relationship)
        return 1.3 - (normalizedTrend * 0.5); // Range: 0.8 - 1.3
    }
    else if(StringFind(strategyName, "Fibonacci") >= 0)
    {
        // Fibonacci retracements work well in trending markets
        return 0.8 + (normalizedTrend * 0.5); // Range: 0.8 - 1.3
    }
    else if(StringFind(strategyName, "Brain") >= 0 || StringFind(strategyName, "AI") >= 0)
    {
        // AI strategies should adapt, slight boost in strong trends
        return 1.0 + (normalizedTrend * 0.2); // Range: 1.0 - 1.2
    }
    
    // Default: neutral weighting with slight trend preference
    return 0.95 + (normalizedTrend * 0.1); // Range: 0.95 - 1.05
}

//+------------------------------------------------------------------+
//| Log Strategy Event                                             |
//+------------------------------------------------------------------+
void CStrategyManager::LogStrategyEvent(const ENUM_ERROR_LEVEL level, const string message)
{
    ENUM_ERROR_SEVERITY severity = ERROR_RECOVERABLE;
    if(level == ERROR_LEVEL_INFO) severity = ERROR_INFO;
    else if(level == ERROR_LEVEL_WARNING) severity = ERROR_WARNING;
    else if(level == ERROR_LEVEL_ERROR) severity = ERROR_RECOVERABLE;
    else if(level == ERROR_LEVEL_CRITICAL) severity = ERROR_CRITICAL;
    else if(level == ERROR_LEVEL_FATAL) severity = ERROR_FATAL;

    SErrorContext context;
    context.component = "StrategyManager";
    context.operation = "LogStrategyEvent";
    context.symbol = "";
    context.errorCode = 0;
    context.additionalInfo = message;
    context.timestamp = TimeCurrent();
    context.severity = severity;
    
    CEnhancedErrorHandler* localErrorHandler = CEnhancedErrorHandler::GetInstance();
    if(CheckPointer(localErrorHandler) != POINTER_INVALID) {
        localErrorHandler.LogError(severity, context);
    }
}

#endif // CORE_STRATEGY_MANAGER_MQH

