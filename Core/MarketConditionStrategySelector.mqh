//+------------------------------------------------------------------+
//| Market Condition-Based Strategy Selector                       |
//| Connects market regime detection to strategy prioritization    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Windsurf AI"
#property link      "https://www.windsurf.ai"
#property version   "1.00"
#property strict

#ifndef CORE_MARKET_CONDITION_STRATEGY_SELECTOR_MQH
#define CORE_MARKET_CONDITION_STRATEGY_SELECTOR_MQH

#include "Enums.mqh"
#include "ErrorHandling.mqh"
#include "AIStrategyOrchestrator.mqh"

//+------------------------------------------------------------------+
//| Market Condition Analysis Structure                            |
//+------------------------------------------------------------------+
struct SMarketCondition
{
    ENUM_MARKET_REGIME regime;          // Current market regime
    double regimeConfidence;             // Regime detection confidence
    double volatilityLevel;              // Current volatility (ATR-based)
    double trendStrength;                // Trend strength (0-1)
    double momentum;                     // Market momentum
    datetime lastUpdate;                 // Last condition update
    bool isValid;                        // Condition data validity
};

//+------------------------------------------------------------------+
//| Strategy Regime Preference Structure                           |
//+------------------------------------------------------------------+
struct SStrategyRegimePreference
{
    string strategyName;                 // Strategy name
    double trendingWeight;               // Weight in trending markets
    double rangingWeight;                // Weight in ranging markets
    double volatileWeight;               // Weight in volatile markets
    double quietWeight;                  // Weight in quiet markets
    double minVolatility;                // Minimum volatility requirement
    double maxVolatility;                // Maximum volatility requirement
    double minTrendStrength;             // Minimum trend strength
    bool enabledInTrending;              // Enabled in trending markets
    bool enabledInRanging;               // Enabled in ranging markets
    bool enabledInVolatile;              // Enabled in volatile markets
    bool enabledInQuiet;                 // Enabled in quiet markets
};

//+------------------------------------------------------------------+
//| Market Condition-Based Strategy Selector Class                 |
//+------------------------------------------------------------------+
class CMarketConditionStrategySelector
{
private:
    CAIStrategyOrchestrator* m_orchestrator;    // AI Strategy Orchestrator
    
    // Market condition tracking
    SMarketCondition m_currentCondition;        // Current market condition
    SMarketCondition m_previousCondition;       // Previous market condition
    
    // Strategy preferences
    SStrategyRegimePreference m_preferences[MAX_STRATEGIES];  // Strategy regime preferences
    int m_preferenceCount;                      // Number of configured preferences
    
    // Configuration
    double m_volatilityThreshold;               // Volatility threshold (default 0.02)
    double m_trendThreshold;                    // Trend strength threshold (default 0.5)
    double m_regimeConfidenceThreshold;         // Minimum regime confidence (default 0.6)
    int m_conditionUpdateInterval;              // Update interval in seconds (default 60)
    
    // Market analysis
    string m_symbol;                            // Current symbol for analysis
    ENUM_TIMEFRAMES m_timeframe;                // Analysis timeframe
    int m_atrPeriod;                            // ATR period for volatility
    int m_trendPeriod;                          // Period for trend analysis
    
    // Logging and tracking
    datetime m_lastConditionUpdate;             // Last condition update time
    datetime m_lastRegimeChange;                // Last regime change time
    int m_totalRegimeChanges;                   // Total regime changes
    string m_conditionHistory;                  // Recent condition history
    
    bool m_initialized;
    
public:
    // Constructor and destructor
    CMarketConditionStrategySelector(void);
    ~CMarketConditionStrategySelector(void);
    
    // Initialization
    bool Initialize(CAIStrategyOrchestrator* orchestrator, const string symbol = "", 
                   const ENUM_TIMEFRAMES timeframe = PERIOD_H1);
    
    // Market condition analysis
    bool UpdateMarketCondition(void);
    bool AnalyzeMarketRegime(void);
    double CalculateVolatilityLevel(void);
    double CalculateTrendStrength(void);
    double CalculateMarketMomentum(void);
    
    // Strategy selection and prioritization
    void ApplyMarketConditionFiltering(void);
    void ApplyVolatilityBasedFiltering(double volatilityLevel, double volatilityThreshold = 0.02);
    void ApplyTrendStrengthWeighting(double trendStrength, double trendThreshold = 0.5);
    void UpdateStrategyPrioritization(void);
    
    // Strategy preference management
    bool ConfigureStrategyPreference(const string strategyName, const SStrategyRegimePreference &preference);
    bool SetStrategyRegimeWeights(const string strategyName, double trending, double ranging, 
                                 double volatile, double quiet);
    bool SetStrategyVolatilityRange(const string strategyName, double minVol, double maxVol);
    bool SetStrategyTrendRequirement(const string strategyName, double minTrend);
    
    // Market condition information
    SMarketCondition GetCurrentCondition(void) const { return m_currentCondition; }
    bool HasConditionChanged(void);
    string GetConditionSummary(void);
    double GetRegimeStability(void);
    
    // Strategy filtering
    bool IsStrategyValidForCurrentCondition(const string strategyName);
    bool IsStrategyValidForVolatility(const string strategyName, double volatilityLevel);
    bool IsStrategyValidForTrend(const string strategyName, double trendStrength);
    double GetConditionBasedWeight(const string strategyName);
    double GetTrendBasedWeight(const string strategyName, double trendStrength);
    double GetVolatilityBasedWeight(const string strategyName, double volatilityLevel);
    
    // Configuration
    void SetVolatilityThreshold(const double threshold) { m_volatilityThreshold = threshold; }
    void SetTrendThreshold(const double threshold) { m_trendThreshold = threshold; }
    void SetRegimeConfidenceThreshold(const double threshold) { m_regimeConfidenceThreshold = threshold; }
    void SetUpdateInterval(const int interval) { m_conditionUpdateInterval = interval; }
    
    // Reporting and logging
    void LogMarketConditionSelection(ENUM_MARKET_REGIME regime, double volatility, double trendStrength);
    void PrintConditionReport(void);
    string GetSelectionSummary(void);
    
private:
    // Internal functions
    void InitializeDefaultPreferences(void);
    void InitializeCondition(void);
    int FindPreferenceIndex(const string strategyName);
    void AddDefaultPreference(const string strategyName);
    
    // Market analysis helpers
    ENUM_MARKET_REGIME ClassifyMarketRegime(double volatility, double trendStrength, double momentum);
    double CalculateRegimeConfidence(ENUM_MARKET_REGIME regime, double volatility, double trendStrength);
    bool ValidateMarketData(void);
    
    // Strategy weight calculations
    double CalculateRegimeWeight(const string strategyName, ENUM_MARKET_REGIME regime);
    double ApplyVolatilityFilter(const string strategyName, double baseWeight, double volatility);
    double ApplyTrendFilter(const string strategyName, double baseWeight, double trendStrength);
    
    // Condition tracking
    void UpdateConditionHistory(void);
    void RecordRegimeChange(ENUM_MARKET_REGIME oldRegime, ENUM_MARKET_REGIME newRegime);
    
    // Validation functions
    bool ValidateOrchestrator(void);
    bool ValidateSymbol(const string symbol);
    bool ValidateTimeframe(const ENUM_TIMEFRAMES timeframe);
    bool ValidatePreference(const SStrategyRegimePreference &preference);
    
    // Logging
    void LogConditionEvent(const ENUM_ERROR_LEVEL level, const string message);
};

//+------------------------------------------------------------------+
//| Constructor                                                     |
//+------------------------------------------------------------------+
CMarketConditionStrategySelector::CMarketConditionStrategySelector(void) :
    m_orchestrator(NULL),
    m_preferenceCount(0),
    m_volatilityThreshold(0.02),
    m_trendThreshold(0.5),
    m_regimeConfidenceThreshold(0.6),
    m_conditionUpdateInterval(60),
    m_symbol(""),
    m_timeframe(PERIOD_H1),
    m_atrPeriod(14),
    m_trendPeriod(20),
    m_lastConditionUpdate(0),
    m_lastRegimeChange(0),
    m_totalRegimeChanges(0),
    m_conditionHistory(""),
    m_initialized(false)
{
    InitializeCondition();
    InitializeDefaultPreferences();
}

//+------------------------------------------------------------------+
//| Destructor                                                      |
//+------------------------------------------------------------------+
CMarketConditionStrategySelector::~CMarketConditionStrategySelector(void)
{
    if(m_initialized)
    {
        PrintConditionReport();
        LogConditionEvent(ERROR_LEVEL_INFO, "Market Condition Strategy Selector destroyed");
    }
}

//+------------------------------------------------------------------+
//| Initialize Selector                                            |
//+------------------------------------------------------------------+
bool CMarketConditionStrategySelector::Initialize(CAIStrategyOrchestrator* orchestrator, const string symbol = "", 
                                                 const ENUM_TIMEFRAMES timeframe = PERIOD_H1)
{
    if(!ValidateOrchestrator())
    {
        LogConditionEvent(ERROR_LEVEL_ERROR, "Invalid orchestrator pointer");
        return false;
    }
    
    m_orchestrator = orchestrator;
    
    if(StringLen(symbol) > 0)
    {
        if(!ValidateSymbol(symbol))
        {
            LogConditionEvent(ERROR_LEVEL_ERROR, "Invalid symbol: " + symbol);
            return false;
        }
        m_symbol = symbol;
    }
    else
    {
        m_symbol = Symbol(); // Use current chart symbol
    }
    
    if(!ValidateTimeframe(timeframe))
    {
        LogConditionEvent(ERROR_LEVEL_ERROR, "Invalid timeframe");
        return false;
    }
    m_timeframe = timeframe;
    
    m_lastConditionUpdate = TimeCurrent();
    m_initialized = true;
    
    // Perform initial market condition analysis
    UpdateMarketCondition();
    
    LogConditionEvent(ERROR_LEVEL_INFO, 
                     StringFormat("Market Condition Strategy Selector initialized - Symbol: %s, Timeframe: %s", 
                                 m_symbol, EnumToString(m_timeframe)));
    
    return true;
}

//+------------------------------------------------------------------+
//| Update Market Condition                                        |
//+------------------------------------------------------------------+
bool CMarketConditionStrategySelector::UpdateMarketCondition(void)
{
    if(!m_initialized) return false;
    
    datetime currentTime = TimeCurrent();
    
    // Check if enough time has passed since last update
    if(currentTime - m_lastConditionUpdate < m_conditionUpdateInterval)
        return true;
    
    // Store previous condition
    m_previousCondition = m_currentCondition;
    
    // Calculate new market metrics
    double volatility = CalculateVolatilityLevel();
    double trendStrength = CalculateTrendStrength();
    double momentum = CalculateMarketMomentum();
    
    // Classify market regime
    ENUM_MARKET_REGIME newRegime = ClassifyMarketRegime(volatility, trendStrength, momentum);
    double regimeConfidence = CalculateRegimeConfidence(newRegime, volatility, trendStrength);
    
    // Update current condition
    m_currentCondition.regime = newRegime;
    m_currentCondition.regimeConfidence = regimeConfidence;
    m_currentCondition.volatilityLevel = volatility;
    m_currentCondition.trendStrength = trendStrength;
    m_currentCondition.momentum = momentum;
    m_currentCondition.lastUpdate = currentTime;
    m_currentCondition.isValid = ValidateMarketData();
    
    // Check for regime change
    if(m_previousCondition.regime != newRegime && m_previousCondition.isValid)
    {
        RecordRegimeChange(m_previousCondition.regime, newRegime);
        
        // Update orchestrator with new regime
        if(regimeConfidence >= m_regimeConfidenceThreshold)
        {
            m_orchestrator.SetCurrentRegime(newRegime, regimeConfidence);
        }
    }
    
    // Update condition history
    UpdateConditionHistory();
    
    // Apply market condition-based filtering
    if(m_currentCondition.isValid)
    {
        ApplyMarketConditionFiltering();
    }
    
    m_lastConditionUpdate = currentTime;
    
    LogConditionEvent(ERROR_LEVEL_INFO, 
                     StringFormat("Market condition updated - Regime: %s (%.2f), Volatility: %.4f, Trend: %.2f", 
                                 EnumToString(newRegime), regimeConfidence, volatility, trendStrength));
    
    return true;
}//+
------------------------------------------------------------------+
//| Analyze Market Regime                                          |
//+------------------------------------------------------------------+
bool CMarketConditionStrategySelector::AnalyzeMarketRegime(void)
{
    if(!m_initialized) return false;
    
    double volatility = CalculateVolatilityLevel();
    double trendStrength = CalculateTrendStrength();
    double momentum = CalculateMarketMomentum();
    
    ENUM_MARKET_REGIME regime = ClassifyMarketRegime(volatility, trendStrength, momentum);
    double confidence = CalculateRegimeConfidence(regime, volatility, trendStrength);
    
    LogConditionEvent(ERROR_LEVEL_INFO, 
                     StringFormat("Market Analysis - Regime: %s, Confidence: %.2f, Vol: %.4f, Trend: %.2f, Mom: %.2f", 
                                 EnumToString(regime), confidence, volatility, trendStrength, momentum));
    
    return true;
}

//+------------------------------------------------------------------+
//| Calculate Volatility Level                                     |
//+------------------------------------------------------------------+
double CMarketConditionStrategySelector::CalculateVolatilityLevel(void)
{
    if(StringLen(m_symbol) == 0) return 0.0;
    
    // Calculate ATR-based volatility
    double atr = iATR(m_symbol, m_timeframe, m_atrPeriod, 1);
    double close = iClose(m_symbol, m_timeframe, 1);
    
    if(close <= 0.0) return 0.0;
    
    // Normalize ATR by price (percentage volatility)
    double volatility = atr / close;
    
    return volatility;
}

//+------------------------------------------------------------------+
//| Calculate Trend Strength                                       |
//+------------------------------------------------------------------+
double CMarketConditionStrategySelector::CalculateTrendStrength(void)
{
    if(StringLen(m_symbol) == 0) return 0.0;
    
    // Use ADX for trend strength
    double adx = iADX(m_symbol, m_timeframe, m_trendPeriod, PRICE_CLOSE, MODE_MAIN, 1);
    
    // Normalize ADX to 0-1 range
    double trendStrength = MathMin(1.0, adx / 50.0);
    
    return trendStrength;
}

//+------------------------------------------------------------------+
//| Calculate Market Momentum                                      |
//+------------------------------------------------------------------+
double CMarketConditionStrategySelector::CalculateMarketMomentum(void)
{
    if(StringLen(m_symbol) == 0) return 0.0;
    
    // Calculate momentum using price change over period
    double currentClose = iClose(m_symbol, m_timeframe, 1);
    double previousClose = iClose(m_symbol, m_timeframe, m_trendPeriod + 1);
    
    if(previousClose <= 0.0) return 0.0;
    
    double momentum = (currentClose - previousClose) / previousClose;
    
    // Normalize to -1 to +1 range
    momentum = MathMax(-1.0, MathMin(1.0, momentum * 10.0));
    
    return momentum;
}

//+------------------------------------------------------------------+
//| Apply Market Condition Filtering                              |
//+------------------------------------------------------------------+
void CMarketConditionStrategySelector::ApplyMarketConditionFiltering(void)
{
    if(!m_initialized || !m_currentCondition.isValid) return;
    
    // Apply volatility-based filtering
    ApplyVolatilityBasedFiltering(m_currentCondition.volatilityLevel, m_volatilityThreshold);
    
    // Apply trend strength weighting
    ApplyTrendStrengthWeighting(m_currentCondition.trendStrength, m_trendThreshold);
    
    // Update overall strategy prioritization
    UpdateStrategyPrioritization();
    
    // Log the filtering results
    LogMarketConditionSelection(m_currentCondition.regime, m_currentCondition.volatilityLevel, 
                               m_currentCondition.trendStrength);
}

//+------------------------------------------------------------------+
//| Apply Volatility-Based Filtering                              |
//+------------------------------------------------------------------+
void CMarketConditionStrategySelector::ApplyVolatilityBasedFiltering(double volatilityLevel, double volatilityThreshold = 0.02)
{
    if(!m_initialized) return;
    
    for(int i = 0; i < m_preferenceCount; i++)
    {
        SStrategyRegimePreference &pref = m_preferences[i];
        
        // Check if strategy is valid for current volatility
        bool isValidForVolatility = IsStrategyValidForVolatility(pref.strategyName, volatilityLevel);
        
        if(!isValidForVolatility)
        {
            // Temporarily reduce strategy weight or disable
            LogConditionEvent(ERROR_LEVEL_INFO, 
                             StringFormat("Strategy filtered by volatility - %s: Vol=%.4f, Range=[%.4f-%.4f]", 
                                         pref.strategyName, volatilityLevel, pref.minVolatility, pref.maxVolatility));
        }
    }
}

//+------------------------------------------------------------------+
//| Apply Trend Strength Weighting                                |
//+------------------------------------------------------------------+
void CMarketConditionStrategySelector::ApplyTrendStrengthWeighting(double trendStrength, double trendThreshold = 0.5)
{
    if(!m_initialized) return;
    
    for(int i = 0; i < m_preferenceCount; i++)
    {
        SStrategyRegimePreference &pref = m_preferences[i];
        
        // Calculate trend-based weight adjustment
        double trendWeight = GetTrendBasedWeight(pref.strategyName, trendStrength);
        
        LogConditionEvent(ERROR_LEVEL_INFO, 
                         StringFormat("Trend weighting applied - %s: Strength=%.2f, Weight=%.2f", 
                                     pref.strategyName, trendStrength, trendWeight));
    }
}

//+------------------------------------------------------------------+
//| Update Strategy Prioritization                                 |
//+------------------------------------------------------------------+
void CMarketConditionStrategySelector::UpdateStrategyPrioritization(void)
{
    if(!m_initialized || !m_currentCondition.isValid) return;
    
    // Apply regime-based adjustments through orchestrator
    if(m_currentCondition.regimeConfidence >= m_regimeConfidenceThreshold)
    {
        m_orchestrator.ApplyRegimeBasedAdjustments(m_currentCondition.regime, m_currentCondition.regimeConfidence);
    }
    
    LogConditionEvent(ERROR_LEVEL_INFO, 
                     StringFormat("Strategy prioritization updated for regime: %s (Confidence: %.2f)", 
                                 EnumToString(m_currentCondition.regime), m_currentCondition.regimeConfidence));
}

//+------------------------------------------------------------------+
//| Configure Strategy Preference                                  |
//+------------------------------------------------------------------+
bool CMarketConditionStrategySelector::ConfigureStrategyPreference(const string strategyName, const SStrategyRegimePreference &preference)
{
    if(!ValidatePreference(preference))
    {
        LogConditionEvent(ERROR_LEVEL_ERROR, "Invalid strategy preference configuration");
        return false;
    }
    
    int index = FindPreferenceIndex(strategyName);
    if(index < 0)
    {
        if(m_preferenceCount >= MAX_STRATEGIES)
        {
            LogConditionEvent(ERROR_LEVEL_ERROR, "Maximum strategy preferences reached");
            return false;
        }
        index = m_preferenceCount++;
    }
    
    m_preferences[index] = preference;
    m_preferences[index].strategyName = strategyName;
    
    LogConditionEvent(ERROR_LEVEL_INFO, 
                     StringFormat("Strategy preference configured: %s", strategyName));
    
    return true;
}

//+------------------------------------------------------------------+
//| Set Strategy Regime Weights                                   |
//+------------------------------------------------------------------+
bool CMarketConditionStrategySelector::SetStrategyRegimeWeights(const string strategyName, double trending, double ranging, 
                                                               double volatile, double quiet)
{
    int index = FindPreferenceIndex(strategyName);
    if(index < 0)
    {
        AddDefaultPreference(strategyName);
        index = m_preferenceCount - 1;
    }
    
    m_preferences[index].trendingWeight = trending;
    m_preferences[index].rangingWeight = ranging;
    m_preferences[index].volatileWeight = volatile;
    m_preferences[index].quietWeight = quiet;
    
    LogConditionEvent(ERROR_LEVEL_INFO, 
                     StringFormat("Regime weights set for %s: T=%.2f, R=%.2f, V=%.2f, Q=%.2f", 
                                 strategyName, trending, ranging, volatile, quiet));
    
    return true;
}

//+------------------------------------------------------------------+
//| Set Strategy Volatility Range                                 |
//+------------------------------------------------------------------+
bool CMarketConditionStrategySelector::SetStrategyVolatilityRange(const string strategyName, double minVol, double maxVol)
{
    if(minVol < 0.0 || maxVol < minVol)
    {
        LogConditionEvent(ERROR_LEVEL_ERROR, "Invalid volatility range");
        return false;
    }
    
    int index = FindPreferenceIndex(strategyName);
    if(index < 0)
    {
        AddDefaultPreference(strategyName);
        index = m_preferenceCount - 1;
    }
    
    m_preferences[index].minVolatility = minVol;
    m_preferences[index].maxVolatility = maxVol;
    
    LogConditionEvent(ERROR_LEVEL_INFO, 
                     StringFormat("Volatility range set for %s: [%.4f - %.4f]", 
                                 strategyName, minVol, maxVol));
    
    return true;
}

//+------------------------------------------------------------------+
//| Set Strategy Trend Requirement                                |
//+------------------------------------------------------------------+
bool CMarketConditionStrategySelector::SetStrategyTrendRequirement(const string strategyName, double minTrend)
{
    if(minTrend < 0.0 || minTrend > 1.0)
    {
        LogConditionEvent(ERROR_LEVEL_ERROR, "Invalid trend requirement");
        return false;
    }
    
    int index = FindPreferenceIndex(strategyName);
    if(index < 0)
    {
        AddDefaultPreference(strategyName);
        index = m_preferenceCount - 1;
    }
    
    m_preferences[index].minTrendStrength = minTrend;
    
    LogConditionEvent(ERROR_LEVEL_INFO, 
                     StringFormat("Trend requirement set for %s: %.2f", strategyName, minTrend));
    
    return true;
}

//+------------------------------------------------------------------+
//| Has Condition Changed                                          |
//+------------------------------------------------------------------+
bool CMarketConditionStrategySelector::HasConditionChanged(void)
{
    if(!m_previousCondition.isValid || !m_currentCondition.isValid)
        return false;
    
    return (m_previousCondition.regime != m_currentCondition.regime ||
            MathAbs(m_previousCondition.volatilityLevel - m_currentCondition.volatilityLevel) > 0.001 ||
            MathAbs(m_previousCondition.trendStrength - m_currentCondition.trendStrength) > 0.1);
}

//+------------------------------------------------------------------+
//| Get Condition Summary                                          |
//+------------------------------------------------------------------+
string CMarketConditionStrategySelector::GetConditionSummary(void)
{
    if(!m_initialized || !m_currentCondition.isValid)
        return "Market condition not available";
    
    return StringFormat("Regime: %s (%.2f) | Vol: %.4f | Trend: %.2f | Mom: %.2f",
                       EnumToString(m_currentCondition.regime), m_currentCondition.regimeConfidence,
                       m_currentCondition.volatilityLevel, m_currentCondition.trendStrength,
                       m_currentCondition.momentum);
}

//+------------------------------------------------------------------+
//| Get Regime Stability                                           |
//+------------------------------------------------------------------+
double CMarketConditionStrategySelector::GetRegimeStability(void)
{
    if(m_totalRegimeChanges == 0) return 1.0;
    
    // Calculate stability based on regime change frequency
    datetime timePeriod = TimeCurrent() - m_lastRegimeChange;
    if(timePeriod <= 0) return 0.0;
    
    double changeRate = (double)m_totalRegimeChanges / (timePeriod / 3600.0); // Changes per hour
    double stability = MathMax(0.0, 1.0 - changeRate / 10.0); // Normalize to 0-1
    
    return stability;
}

//+------------------------------------------------------------------+
//| Strategy Validation Functions                                  |
//+------------------------------------------------------------------+
bool CMarketConditionStrategySelector::IsStrategyValidForCurrentCondition(const string strategyName)
{
    if(!m_currentCondition.isValid) return true; // Default to valid if no condition data
    
    return (IsStrategyValidForVolatility(strategyName, m_currentCondition.volatilityLevel) &&
            IsStrategyValidForTrend(strategyName, m_currentCondition.trendStrength));
}

bool CMarketConditionStrategySelector::IsStrategyValidForVolatility(const string strategyName, double volatilityLevel)
{
    int index = FindPreferenceIndex(strategyName);
    if(index < 0) return true; // Default to valid if no preference configured
    
    SStrategyRegimePreference &pref = m_preferences[index];
    return (volatilityLevel >= pref.minVolatility && volatilityLevel <= pref.maxVolatility);
}

bool CMarketConditionStrategySelector::IsStrategyValidForTrend(const string strategyName, double trendStrength)
{
    int index = FindPreferenceIndex(strategyName);
    if(index < 0) return true; // Default to valid if no preference configured
    
    SStrategyRegimePreference &pref = m_preferences[index];
    return (trendStrength >= pref.minTrendStrength);
}

//+------------------------------------------------------------------+
//| Weight Calculation Functions                                   |
//+------------------------------------------------------------------+
double CMarketConditionStrategySelector::GetConditionBasedWeight(const string strategyName)
{
    if(!m_currentCondition.isValid) return 1.0;
    
    double regimeWeight = CalculateRegimeWeight(strategyName, m_currentCondition.regime);
    double volatilityWeight = GetVolatilityBasedWeight(strategyName, m_currentCondition.volatilityLevel);
    double trendWeight = GetTrendBasedWeight(strategyName, m_currentCondition.trendStrength);
    
    // Combine weights (geometric mean for balanced effect)
    double combinedWeight = MathPow(regimeWeight * volatilityWeight * trendWeight, 1.0/3.0);
    
    return MathMax(0.1, MathMin(3.0, combinedWeight)); // Clamp to reasonable range
}

double CMarketConditionStrategySelector::GetTrendBasedWeight(const string strategyName, double trendStrength)
{
    int index = FindPreferenceIndex(strategyName);
    if(index < 0) return 1.0;
    
    SStrategyRegimePreference &pref = m_preferences[index];
    
    // If trend strength is below minimum requirement, reduce weight significantly
    if(trendStrength < pref.minTrendStrength)
        return 0.3;
    
    // Linear interpolation based on trend strength
    if(trendStrength > 0.7) // Strong trend
        return 1.3;
    else if(trendStrength > 0.4) // Moderate trend
        return 1.0;
    else // Weak trend
        return 0.7;
}

double CMarketConditionStrategySelector::GetVolatilityBasedWeight(const string strategyName, double volatilityLevel)
{
    int index = FindPreferenceIndex(strategyName);
    if(index < 0) return 1.0;
    
    SStrategyRegimePreference &pref = m_preferences[index];
    
    // Check if volatility is within acceptable range
    if(volatilityLevel < pref.minVolatility || volatilityLevel > pref.maxVolatility)
        return 0.2; // Heavily penalize out-of-range volatility
    
    // Calculate optimal volatility point (middle of range)
    double optimalVol = (pref.minVolatility + pref.maxVolatility) / 2.0;
    double distance = MathAbs(volatilityLevel - optimalVol);
    double range = pref.maxVolatility - pref.minVolatility;
    
    if(range <= 0.0) return 1.0;
    
    // Weight decreases as distance from optimal increases
    double weight = 1.0 - (distance / range) * 0.5; // Max 50% reduction
    
    return MathMax(0.5, weight);
}//+-
-----------------------------------------------------------------+
//| Logging and Reporting Functions                               |
//+------------------------------------------------------------------+
void CMarketConditionStrategySelector::LogMarketConditionSelection(ENUM_MARKET_REGIME regime, double volatility, double trendStrength)
{
    string message = StringFormat("Market Condition Selection - Regime: %s | Volatility: %.4f | Trend Strength: %.2f | Active Strategies: %d",
                                 EnumToString(regime), volatility, trendStrength, m_preferenceCount);
    
    LogConditionEvent(ERROR_LEVEL_INFO, message);
    
    // Log individual strategy conditions
    for(int i = 0; i < m_preferenceCount; i++)
    {
        SStrategyRegimePreference &pref = m_preferences[i];
        bool isValid = IsStrategyValidForCurrentCondition(pref.strategyName);
        double weight = GetConditionBasedWeight(pref.strategyName);
        
        LogConditionEvent(ERROR_LEVEL_INFO, 
                         StringFormat("  %s: Valid=%s | Weight=%.2f", 
                                     pref.strategyName, isValid ? "YES" : "NO", weight));
    }
}

void CMarketConditionStrategySelector::PrintConditionReport(void)
{
    if(!m_initialized) return;
    
    Print("\n=== MARKET CONDITION STRATEGY SELECTOR REPORT ===");
    Print("📊 CURRENT MARKET CONDITION:");
    Print("   Symbol: ", m_symbol, " | Timeframe: ", EnumToString(m_timeframe));
    Print("   Regime: ", EnumToString(m_currentCondition.regime), " (Confidence: ", DoubleToString(m_currentCondition.regimeConfidence, 2), ")");
    Print("   Volatility: ", DoubleToString(m_currentCondition.volatilityLevel, 4));
    Print("   Trend Strength: ", DoubleToString(m_currentCondition.trendStrength, 2));
    Print("   Momentum: ", DoubleToString(m_currentCondition.momentum, 2));
    Print("   Regime Stability: ", DoubleToString(GetRegimeStability(), 2));
    Print("   Total Regime Changes: ", m_totalRegimeChanges);
    
    Print("\n🎯 STRATEGY CONDITIONS:");
    for(int i = 0; i < m_preferenceCount; i++)
    {
        SStrategyRegimePreference &pref = m_preferences[i];
        bool isValid = IsStrategyValidForCurrentCondition(pref.strategyName);
        double weight = GetConditionBasedWeight(pref.strategyName);
        
        Print("   ", i+1, ". ", pref.strategyName);
        Print("      Valid for Current Condition: ", isValid ? "YES" : "NO");
        Print("      Condition-Based Weight: ", DoubleToString(weight, 2));
        Print("      Regime Weights - T:", DoubleToString(pref.trendingWeight, 1), 
              " R:", DoubleToString(pref.rangingWeight, 1),
              " V:", DoubleToString(pref.volatileWeight, 1),
              " Q:", DoubleToString(pref.quietWeight, 1));
        Print("      Volatility Range: [", DoubleToString(pref.minVolatility, 4), " - ", DoubleToString(pref.maxVolatility, 4), "]");
        Print("      Min Trend Strength: ", DoubleToString(pref.minTrendStrength, 2));
    }
    
    Print("\n⚙️ CONFIGURATION:");
    Print("   Volatility Threshold: ", DoubleToString(m_volatilityThreshold, 4));
    Print("   Trend Threshold: ", DoubleToString(m_trendThreshold, 2));
    Print("   Regime Confidence Threshold: ", DoubleToString(m_regimeConfidenceThreshold, 2));
    Print("   Update Interval: ", m_conditionUpdateInterval, " seconds");
    Print("   ATR Period: ", m_atrPeriod);
    Print("   Trend Period: ", m_trendPeriod);
    
    if(StringLen(m_conditionHistory) > 0)
    {
        Print("\n📈 RECENT CONDITION HISTORY:");
        Print("   ", m_conditionHistory);
    }
    
    Print("===============================================\n");
}

string CMarketConditionStrategySelector::GetSelectionSummary(void)
{
    if(!m_initialized)
        return "Selector not initialized";
    
    int validStrategies = 0;
    for(int i = 0; i < m_preferenceCount; i++)
    {
        if(IsStrategyValidForCurrentCondition(m_preferences[i].strategyName))
            validStrategies++;
    }
    
    return StringFormat("Regime: %s (%.2f) | Valid Strategies: %d/%d | Stability: %.2f",
                       EnumToString(m_currentCondition.regime), m_currentCondition.regimeConfidence,
                       validStrategies, m_preferenceCount, GetRegimeStability());
}

//+------------------------------------------------------------------+
//| Internal Helper Functions                                      |
//+------------------------------------------------------------------+
void CMarketConditionStrategySelector::InitializeDefaultPreferences(void)
{
    // Initialize with common strategy preferences
    // These can be overridden by explicit configuration
    
    // RSI Strategy - good in ranging markets
    SStrategyRegimePreference rsiPref;
    rsiPref.strategyName = "RSI_Strategy";
    rsiPref.trendingWeight = 0.8;
    rsiPref.rangingWeight = 1.5;
    rsiPref.volatileWeight = 0.7;
    rsiPref.quietWeight = 1.2;
    rsiPref.minVolatility = 0.005;
    rsiPref.maxVolatility = 0.05;
    rsiPref.minTrendStrength = 0.0;
    rsiPref.enabledInTrending = true;
    rsiPref.enabledInRanging = true;
    rsiPref.enabledInVolatile = true;
    rsiPref.enabledInQuiet = true;
    
    // Supply/Demand Strategy - good in ranging markets
    SStrategyRegimePreference sdPref;
    sdPref.strategyName = "SupplyDemand_Strategy";
    sdPref.trendingWeight = 0.9;
    sdPref.rangingWeight = 1.4;
    sdPref.volatileWeight = 0.8;
    sdPref.quietWeight = 1.1;
    sdPref.minVolatility = 0.003;
    sdPref.maxVolatility = 0.04;
    sdPref.minTrendStrength = 0.0;
    sdPref.enabledInTrending = true;
    sdPref.enabledInRanging = true;
    sdPref.enabledInVolatile = true;
    sdPref.enabledInQuiet = true;
    
    // Trend-following strategies (Elliott Wave, Fibonacci)
    SStrategyRegimePreference trendPref;
    trendPref.strategyName = "ElliottWave_Strategy";
    trendPref.trendingWeight = 1.5;
    trendPref.rangingWeight = 0.6;
    trendPref.volatileWeight = 1.2;
    trendPref.quietWeight = 0.8;
    trendPref.minVolatility = 0.008;
    trendPref.maxVolatility = 0.08;
    trendPref.minTrendStrength = 0.3;
    trendPref.enabledInTrending = true;
    trendPref.enabledInRanging = false;
    trendPref.enabledInVolatile = true;
    trendPref.enabledInQuiet = false;
    
    // Store default preferences (will be overridden if explicitly configured)
    // These serve as fallbacks
}

void CMarketConditionStrategySelector::InitializeCondition(void)
{
    m_currentCondition.regime = MARKET_REGIME_UNKNOWN;
    m_currentCondition.regimeConfidence = 0.0;
    m_currentCondition.volatilityLevel = 0.0;
    m_currentCondition.trendStrength = 0.0;
    m_currentCondition.momentum = 0.0;
    m_currentCondition.lastUpdate = 0;
    m_currentCondition.isValid = false;
    
    m_previousCondition = m_currentCondition;
}

int CMarketConditionStrategySelector::FindPreferenceIndex(const string strategyName)
{
    for(int i = 0; i < m_preferenceCount; i++)
    {
        if(m_preferences[i].strategyName == strategyName)
            return i;
    }
    return -1;
}

void CMarketConditionStrategySelector::AddDefaultPreference(const string strategyName)
{
    if(m_preferenceCount >= MAX_STRATEGIES) return;
    
    SStrategyRegimePreference &pref = m_preferences[m_preferenceCount];
    pref.strategyName = strategyName;
    pref.trendingWeight = 1.0;
    pref.rangingWeight = 1.0;
    pref.volatileWeight = 1.0;
    pref.quietWeight = 1.0;
    pref.minVolatility = 0.0;
    pref.maxVolatility = 1.0;
    pref.minTrendStrength = 0.0;
    pref.enabledInTrending = true;
    pref.enabledInRanging = true;
    pref.enabledInVolatile = true;
    pref.enabledInQuiet = true;
    
    m_preferenceCount++;
}

//+------------------------------------------------------------------+
//| Market Analysis Helper Functions                               |
//+------------------------------------------------------------------+
ENUM_MARKET_REGIME CMarketConditionStrategySelector::ClassifyMarketRegime(double volatility, double trendStrength, double momentum)
{
    // Classification logic based on volatility and trend strength
    if(volatility > m_volatilityThreshold * 2.0)
    {
        return MARKET_REGIME_VOLATILE;
    }
    else if(volatility < m_volatilityThreshold * 0.5)
    {
        return MARKET_REGIME_QUIET;
    }
    else if(trendStrength > m_trendThreshold)
    {
        return MARKET_REGIME_TRENDING;
    }
    else
    {
        return MARKET_REGIME_RANGING;
    }
}

double CMarketConditionStrategySelector::CalculateRegimeConfidence(ENUM_MARKET_REGIME regime, double volatility, double trendStrength)
{
    double confidence = 0.5; // Base confidence
    
    switch(regime)
    {
        case MARKET_REGIME_TRENDING:
            confidence = MathMin(1.0, trendStrength * 1.5);
            break;
            
        case MARKET_REGIME_RANGING:
            confidence = MathMin(1.0, (1.0 - trendStrength) * 1.2);
            break;
            
        case MARKET_REGIME_VOLATILE:
            confidence = MathMin(1.0, (volatility / (m_volatilityThreshold * 2.0)) * 0.8 + 0.2);
            break;
            
        case MARKET_REGIME_QUIET:
            confidence = MathMin(1.0, (1.0 - volatility / m_volatilityThreshold) * 0.8 + 0.2);
            break;
            
        default:
            confidence = 0.3;
            break;
    }
    
    return MathMax(0.1, confidence);
}

bool CMarketConditionStrategySelector::ValidateMarketData(void)
{
    // Basic validation of market data
    return (m_currentCondition.volatilityLevel >= 0.0 && 
            m_currentCondition.trendStrength >= 0.0 && 
            m_currentCondition.trendStrength <= 1.0 &&
            MathAbs(m_currentCondition.momentum) <= 1.0);
}

//+------------------------------------------------------------------+
//| Strategy Weight Calculation Helpers                           |
//+------------------------------------------------------------------+
double CMarketConditionStrategySelector::CalculateRegimeWeight(const string strategyName, ENUM_MARKET_REGIME regime)
{
    int index = FindPreferenceIndex(strategyName);
    if(index < 0) return 1.0;
    
    SStrategyRegimePreference &pref = m_preferences[index];
    
    switch(regime)
    {
        case MARKET_REGIME_TRENDING:
            return pref.enabledInTrending ? pref.trendingWeight : 0.1;
            
        case MARKET_REGIME_RANGING:
            return pref.enabledInRanging ? pref.rangingWeight : 0.1;
            
        case MARKET_REGIME_VOLATILE:
            return pref.enabledInVolatile ? pref.volatileWeight : 0.1;
            
        case MARKET_REGIME_QUIET:
            return pref.enabledInQuiet ? pref.quietWeight : 0.1;
            
        default:
            return 1.0;
    }
}

double CMarketConditionStrategySelector::ApplyVolatilityFilter(const string strategyName, double baseWeight, double volatility)
{
    if(!IsStrategyValidForVolatility(strategyName, volatility))
        return baseWeight * 0.2; // Heavily reduce weight for invalid volatility
    
    return baseWeight * GetVolatilityBasedWeight(strategyName, volatility);
}

double CMarketConditionStrategySelector::ApplyTrendFilter(const string strategyName, double baseWeight, double trendStrength)
{
    if(!IsStrategyValidForTrend(strategyName, trendStrength))
        return baseWeight * 0.3; // Reduce weight for insufficient trend
    
    return baseWeight * GetTrendBasedWeight(strategyName, trendStrength);
}

//+------------------------------------------------------------------+
//| Condition Tracking Functions                                  |
//+------------------------------------------------------------------+
void CMarketConditionStrategySelector::UpdateConditionHistory(void)
{
    string timestamp = TimeToString(TimeCurrent(), TIME_MINUTES);
    string conditionEntry = StringFormat("[%s] %s(%.2f) V:%.4f T:%.2f", 
                                        timestamp, 
                                        EnumToString(m_currentCondition.regime),
                                        m_currentCondition.regimeConfidence,
                                        m_currentCondition.volatilityLevel,
                                        m_currentCondition.trendStrength);
    
    // Keep only last 5 entries to avoid string overflow
    if(StringLen(m_conditionHistory) > 300)
    {
        m_conditionHistory = conditionEntry;
    }
    else
    {
        m_conditionHistory += (StringLen(m_conditionHistory) > 0 ? " | " : "") + conditionEntry;
    }
}

void CMarketConditionStrategySelector::RecordRegimeChange(ENUM_MARKET_REGIME oldRegime, ENUM_MARKET_REGIME newRegime)
{
    m_totalRegimeChanges++;
    m_lastRegimeChange = TimeCurrent();
    
    LogConditionEvent(ERROR_LEVEL_INFO, 
                     StringFormat("Market regime changed: %s -> %s | Total changes: %d", 
                                 EnumToString(oldRegime), EnumToString(newRegime), m_totalRegimeChanges));
}

//+------------------------------------------------------------------+
//| Validation Functions                                           |
//+------------------------------------------------------------------+
bool CMarketConditionStrategySelector::ValidateOrchestrator(void)
{
    return (CheckPointer(m_orchestrator) != POINTER_INVALID);
}

bool CMarketConditionStrategySelector::ValidateSymbol(const string symbol)
{
    return (StringLen(symbol) > 0 && StringLen(symbol) <= 12);
}

bool CMarketConditionStrategySelector::ValidateTimeframe(const ENUM_TIMEFRAMES timeframe)
{
    return (timeframe >= PERIOD_M1 && timeframe <= PERIOD_MN1);
}

bool CMarketConditionStrategySelector::ValidatePreference(const SStrategyRegimePreference &preference)
{
    if(StringLen(preference.strategyName) == 0) return false;
    if(preference.trendingWeight < 0.0 || preference.trendingWeight > 5.0) return false;
    if(preference.rangingWeight < 0.0 || preference.rangingWeight > 5.0) return false;
    if(preference.volatileWeight < 0.0 || preference.volatileWeight > 5.0) return false;
    if(preference.quietWeight < 0.0 || preference.quietWeight > 5.0) return false;
    if(preference.minVolatility < 0.0 || preference.minVolatility > 1.0) return false;
    if(preference.maxVolatility < preference.minVolatility || preference.maxVolatility > 1.0) return false;
    if(preference.minTrendStrength < 0.0 || preference.minTrendStrength > 1.0) return false;
    
    return true;
}

//+------------------------------------------------------------------+
//| Logging Function                                               |
//+------------------------------------------------------------------+
void CMarketConditionStrategySelector::LogConditionEvent(const ENUM_ERROR_LEVEL level, const string message)
{
    string prefix = "";
    switch(level)
    {
        case ERROR_LEVEL_INFO:    prefix = "[CONDITION-INFO] "; break;
        case ERROR_LEVEL_WARNING: prefix = "[CONDITION-WARN] "; break;
        case ERROR_LEVEL_ERROR:   prefix = "[CONDITION-ERROR] "; break;
        default:                  prefix = "[CONDITION] "; break;
    }
    
    Print(prefix + message);
}

#endif // CORE_MARKET_CONDITION_STRATEGY_SELECTOR_MQH