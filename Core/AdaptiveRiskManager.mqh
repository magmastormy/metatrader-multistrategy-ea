//+------------------------------------------------------------------+
//| Adaptive Risk Management System                                |
//| Adjusts risk parameters based on performance metrics          |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Windsurf AI"
#property link      "https://www.windsurf.ai"
#property version   "1.00"
#property strict

#ifndef CORE_ADAPTIVE_RISK_MANAGER_MQH
#define CORE_ADAPTIVE_RISK_MANAGER_MQH

#include "Enums.mqh"
#include "ErrorHandling.mqh"
#include "PerformanceAnalytics.mqh"
#include "PositionSizer.mqh"

// Forward declarations
class CPerformanceAnalytics;
class CPositionSizer;

//+------------------------------------------------------------------+
//| Adaptive Risk Parameters Structure                             |
//+------------------------------------------------------------------+
struct SAdaptiveRiskParams
{
    double baseRiskPercent;           // Base risk percentage
    double minRiskPercent;            // Minimum risk percentage
    double maxRiskPercent;            // Maximum risk percentage
    double baseConfidenceThreshold;   // Base confidence threshold
    double minConfidenceThreshold;    // Minimum confidence threshold
    double maxConfidenceThreshold;    // Maximum confidence threshold
    int adaptationPeriod;             // Adaptation period in trades
    bool enableAdaptation;            // Enable adaptive behavior
};

//+------------------------------------------------------------------+
//| Adaptive Risk Manager Class                                   |
//+------------------------------------------------------------------+
class CAdaptiveRiskManager
{
private:
    SAdaptiveRiskParams m_params;
    CPerformanceAnalytics* m_perfAnalytics;   // Pointer to performance analytics
    CPositionSizer* m_positionSizer;          // Pointer to position sizer
    
    // Current adaptive parameters
    double m_currentRiskPercent;
    double m_currentConfidenceThreshold;
    bool m_conservativeModeActive;
    
    // Adaptation tracking
    datetime m_lastAdaptation;
    int m_adaptationInterval;
    
    bool m_initialized;
    
public:
    // Constructor/Destructor declarations
    CAdaptiveRiskManager();
    ~CAdaptiveRiskManager();
    
    // Delete copy constructor and assignment operator
    CAdaptiveRiskManager(const CAdaptiveRiskManager&) = delete;
    void operator=(const CAdaptiveRiskManager&) = delete;
    
    // Initialize with components
    bool Initialize(CPerformanceAnalytics* perfAnalytics, CPositionSizer* positionSizer);
    
    // Set adaptive parameters
    bool SetParameters(const SAdaptiveRiskParams &params);
    
    // Main adaptation method - called periodically
    void AdaptRiskParameters(void);
    
    // Get current adaptive parameters
    double GetCurrentRiskPercent(void) const { return m_currentRiskPercent; }
    double GetCurrentConfidenceThreshold(void) const { return m_currentConfidenceThreshold; }
    bool IsConservativeModeActive(void) const { return m_conservativeModeActive; }
    
    // Manual adaptation triggers
    void TriggerRiskReduction(const string reason);
    void TriggerConservativeMode(const string reason);
    void RestoreNormalMode(void);
    
    // Adaptive stop loss and take profit optimization
    double GetAdaptiveStopLoss(const string symbolName, const double baseStopLoss);
    double GetAdaptiveTakeProfit(const string symbolName, const double baseTakeProfit);
    
    // Check if adaptation is needed
    bool ShouldAdaptRisk(void);
    
    // Get adaptation status
    string GetAdaptationStatus(void);
    
    // Update performance metrics (called from main EA)
    void UpdatePerformanceMetrics(const SPerformanceMetrics &metrics);
    
    // Apply risk reduction factor
    void ApplyRiskReduction(const double reductionFactor);
    
private:
    // Internal adaptation methods
    void AdaptRiskBasedOnWinRate(const double winRate);
    void AdaptRiskBasedOnSharpe(const double sharpeRatio);
    void AdaptRiskBasedOnDrawdown(const double drawdown);
    void AdaptRiskBasedOnConsecutiveLosses(const int consecutiveLosses);
    
    // Parameter adjustment helpers
    double CalculateRiskAdjustment(const double winRate, const double sharpeRatio,
                                  const double drawdown, const int consecutiveLossesValue);
    double CalculateConfidenceAdjustment(const double winRate, const double sharpeRatio);
    
    // Validation methods
    bool ValidateRiskPercent(const double riskPercent);
    bool ValidateConfidenceThreshold(const double threshold);
    
    // Logging
    void LogAdaptation(const string message);
};

//+------------------------------------------------------------------+
//| Constructor                                                     |
//+------------------------------------------------------------------+
CAdaptiveRiskManager::CAdaptiveRiskManager() :
    m_perfAnalytics(NULL),
    m_positionSizer(NULL),
    m_currentRiskPercent(1.0),
    m_currentConfidenceThreshold(0.65),
    m_conservativeModeActive(false),
    m_lastAdaptation(0),
    m_adaptationInterval(300), // 5 minutes
    m_initialized(false)
{
    // Initialize default parameters
    m_params.baseRiskPercent = 1.0;
    m_params.minRiskPercent = 0.1;
    m_params.maxRiskPercent = 2.0;
    m_params.baseConfidenceThreshold = 0.65;
    m_params.minConfidenceThreshold = 0.55;
    m_params.maxConfidenceThreshold = 0.85;
    m_params.adaptationPeriod = 20;
    m_params.enableAdaptation = true;
}

//+------------------------------------------------------------------+
//| Destructor                                                      |
//+------------------------------------------------------------------+
CAdaptiveRiskManager::~CAdaptiveRiskManager()
{
    LogAdaptation("Adaptive Risk Manager destroyed");
}

//+------------------------------------------------------------------+
//| Initialize with components                                      |
//+------------------------------------------------------------------+
bool CAdaptiveRiskManager::Initialize(CPerformanceAnalytics* pPerfAnalytics, CPositionSizer* pPositionSizer)
{
    if(CheckPointer(pPerfAnalytics) == POINTER_INVALID)
    {
        CEnhancedErrorHandler::LogError(ERROR_RECOVERABLE, "AdaptiveRiskManager", "Invalid PerformanceAnalytics pointer", 0);
        return false;
    }

    if(CheckPointer(pPositionSizer) == POINTER_INVALID)
    {
        CEnhancedErrorHandler::LogError(ERROR_RECOVERABLE, "AdaptiveRiskManager", "Invalid PositionSizer pointer", 0);
        return false;
    }
    
    // Store the pointers
    m_perfAnalytics = pPerfAnalytics;
    m_positionSizer = pPositionSizer;
    
    // Initialize current parameters with base values
    m_currentRiskPercent = m_params.baseRiskPercent;
    m_currentConfidenceThreshold = m_params.baseConfidenceThreshold;
    
    m_initialized = true;
    
    LogAdaptation("Adaptive Risk Manager initialized successfully");
    return true;
}

//+------------------------------------------------------------------+
//| Set Adaptive Parameters                                        |
//+------------------------------------------------------------------+
bool CAdaptiveRiskManager::SetParameters(const SAdaptiveRiskParams &params)
{
    // Validate parameters
    if(!ValidateRiskPercent(params.baseRiskPercent) ||
       !ValidateRiskPercent(params.minRiskPercent) ||
       !ValidateRiskPercent(params.maxRiskPercent))
    {
        CEnhancedErrorHandler::LogError(ERROR_RECOVERABLE, "AdaptiveRiskManager", "Invalid risk parameters", 0);
        return false;
    }

    if(!ValidateConfidenceThreshold(params.baseConfidenceThreshold) ||
       !ValidateConfidenceThreshold(params.minConfidenceThreshold) ||
       !ValidateConfidenceThreshold(params.maxConfidenceThreshold))
    {
        CEnhancedErrorHandler::LogError(ERROR_RECOVERABLE, "AdaptiveRiskManager", "Invalid confidence parameters", 0);
        return false;
    }
    
    m_params = params;
    
    // Update current parameters
    m_currentRiskPercent = m_params.baseRiskPercent;
    m_currentConfidenceThreshold = m_params.baseConfidenceThreshold;
    
    LogAdaptation("Adaptive parameters updated successfully");
    return true;
}

//+------------------------------------------------------------------+
//| Main Adaptation Method                                         |
//+------------------------------------------------------------------+
void CAdaptiveRiskManager::AdaptRiskParameters(void)
{
    if(!m_initialized || !m_params.enableAdaptation) return;
    
    datetime currentTimeLocal = TimeCurrent();
    
    // Check if enough time has passed since last adaptation
    if(currentTimeLocal - m_lastAdaptation < m_adaptationInterval) return;
    
    m_lastAdaptation = currentTimeLocal;
    
    // Get current performance metrics
    if(CheckPointer(m_perfAnalytics) == POINTER_INVALID)
        return;

    SPerformanceMetrics metrics;
    ZeroMemory(metrics);
    CPerformanceAnalytics* analytics = m_perfAnalytics;
    if(CheckPointer(analytics) != POINTER_INVALID)
        metrics = (*analytics).GetPerformanceMetrics();
    
    // Skip adaptation if not enough trades
    if(metrics.totalTrades < MIN_TRADES_FOR_STATS) return;
    
    // Get additional metrics
    double rollingWinRate = 0.0;
    double rollingSharpe = 0.0;
    double currentDrawdownValue = 0.0;
    int consecutiveLossesValue = 0;
    if(CheckPointer(analytics) != POINTER_INVALID)
    {
        rollingWinRate = (*analytics).GetRollingWinRate();
        rollingSharpe = (*analytics).GetRollingSharpe();
        currentDrawdownValue = (*analytics).GetCurrentDrawdown();
        consecutiveLossesValue = (*analytics).GetConsecutiveLosses();
    }
    
    // Calculate risk adjustment
    double riskAdjustment = CalculateRiskAdjustment(rollingWinRate, rollingSharpe,
                                                   currentDrawdownValue, consecutiveLossesValue);
    
    // Calculate confidence adjustment
    double confidenceAdjustment = CalculateConfidenceAdjustment(rollingWinRate, rollingSharpe);
    
    // Apply adjustments
    double newRiskPercent = m_params.baseRiskPercent * riskAdjustment;
    double newConfidenceThreshold = m_params.baseConfidenceThreshold + confidenceAdjustment;
    
    // Clamp to valid ranges
    newRiskPercent = MathMax(m_params.minRiskPercent, MathMin(m_params.maxRiskPercent, newRiskPercent));
    newConfidenceThreshold = MathMax(m_params.minConfidenceThreshold, 
                                    MathMin(m_params.maxConfidenceThreshold, newConfidenceThreshold));
    
    // Update current parameters if changed significantly
    if(MathAbs(newRiskPercent - m_currentRiskPercent) > 0.05 ||
       MathAbs(newConfidenceThreshold - m_currentConfidenceThreshold) > 0.02)
    {
        m_currentRiskPercent = newRiskPercent;
        m_currentConfidenceThreshold = newConfidenceThreshold;
        
        // Update position sizer
        if(CheckPointer(m_positionSizer) != POINTER_INVALID)
        {
            // m_positionSizer->AdaptRiskToPerformance(rollingWinRate, metrics.profitFactor, currentDrawdown);
            // Commented out as this method doesn't exist in CPositionSizer
        }
        
        LogAdaptation(StringFormat("Risk adapted: Risk=%.2f%%, Confidence=%.2f, WR=%.1f%%, SR=%.2f", 
                                  newRiskPercent, newConfidenceThreshold, rollingWinRate, rollingSharpe));
    }
    
    // Check for conservative mode
    bool shouldActivateConservative = false;
    if(CheckPointer(analytics) != POINTER_INVALID)
        shouldActivateConservative = (*analytics).ShouldEnableConservativeMode();
    if(shouldActivateConservative != m_conservativeModeActive)
    {
        m_conservativeModeActive = shouldActivateConservative;
        if(m_conservativeModeActive)
            TriggerConservativeMode("Performance-based trigger");
        else
            RestoreNormalMode();
    }
}

//+------------------------------------------------------------------+
//| Calculate Risk Adjustment Factor                              |
//+------------------------------------------------------------------+
double CAdaptiveRiskManager::CalculateRiskAdjustment(const double winRate, const double sharpeRatio,
                                                    const double drawdown, const int consecutiveLossesValue)
{
    double adjustment = 1.0;
    
    // Win rate adjustment (Requirement 6.1)
    if(winRate < 40.0)
    {
        adjustment *= (winRate < 30.0) ? 0.3 : 0.5;
    }
    else if(winRate > 60.0)
    {
        adjustment *= 1.2; // Increase risk for good performance
    }
    
    // Sharpe ratio adjustment
    if(sharpeRatio < 0.5)
    {
        adjustment *= 0.6;
    }
    else if(sharpeRatio > 1.5)
    {
        adjustment *= 1.1;
    }
    
    // Drawdown adjustment
    if(drawdown > DRAWDOWN_CRITICAL)
    {
        adjustment *= 0.2;
    }
    else if(drawdown > DRAWDOWN_WARNING)
    {
        adjustment *= 0.5;
    }
    
    // Consecutive losses adjustment
    if(consecutiveLossesValue >= MAX_CONSECUTIVE_LOSSES)
    {
        adjustment *= 0.3;
    }
    else if(consecutiveLossesValue >= 3)
    {
        adjustment *= 0.6;
    }
    
    return adjustment;
}

//+------------------------------------------------------------------+
//| Calculate Confidence Adjustment                               |
//+------------------------------------------------------------------+
double CAdaptiveRiskManager::CalculateConfidenceAdjustment(const double winRate, const double sharpeRatio)
{
    double adjustment = 0.0;
    
    // Increase threshold for poor performance
    if(winRate < 30.0)
        adjustment += 0.20;
    else if(winRate < 40.0)
        adjustment += 0.10;
    
    if(sharpeRatio < 0.3)
        adjustment += 0.15;
    else if(sharpeRatio < 0.5)
        adjustment += 0.05;
    
    // Decrease threshold for excellent performance
    if(winRate > 70.0 && sharpeRatio > 1.5)
        adjustment -= 0.10;
    
    return adjustment;
}

//+------------------------------------------------------------------+
//| Trigger Risk Reduction                                        |
//+------------------------------------------------------------------+
void CAdaptiveRiskManager::TriggerRiskReduction(const string reason)
{
    m_currentRiskPercent = m_params.minRiskPercent;
    m_currentConfidenceThreshold = m_params.maxConfidenceThreshold;
    
    LogAdaptation(StringFormat("Risk reduction triggered: %s", reason));
}

//+------------------------------------------------------------------+
//| Trigger Conservative Mode                                      |
//+------------------------------------------------------------------+
void CAdaptiveRiskManager::TriggerConservativeMode(const string reason)
{
    m_conservativeModeActive = true;
    m_currentRiskPercent *= 0.5; // Halve risk
    m_currentConfidenceThreshold = MathMax(m_currentConfidenceThreshold, 0.75);
    
    LogAdaptation(StringFormat("Conservative mode activated: %s", reason));
}

//+------------------------------------------------------------------+
//| Restore Normal Mode                                           |
//+------------------------------------------------------------------+
void CAdaptiveRiskManager::RestoreNormalMode(void)
{
    m_conservativeModeActive = false;
    m_currentRiskPercent = m_params.baseRiskPercent;
    m_currentConfidenceThreshold = m_params.baseConfidenceThreshold;
    
    LogAdaptation("Normal mode restored");
}

//+------------------------------------------------------------------+
//| Get Adaptive Stop Loss                                        |
//+------------------------------------------------------------------+
double CAdaptiveRiskManager::GetAdaptiveStopLoss(const string symbolName, const double baseStopLoss)
{
    if(!m_initialized) return baseStopLoss;
    
    double adaptiveStopLoss = baseStopLoss;
    
    // Widen stop loss in conservative mode
    if(m_conservativeModeActive)
    {
        adaptiveStopLoss *= 1.5; // 50% wider stops
    }
    
    // Adjust based on current performance
    double currentDrawdownValue = 0.0;
    CPerformanceAnalytics* analytics = m_perfAnalytics;
    if(CheckPointer(analytics) != POINTER_INVALID)
        currentDrawdownValue = (*analytics).GetCurrentDrawdown();
    if(currentDrawdownValue > DRAWDOWN_WARNING)
    {
        adaptiveStopLoss *= 1.3; // 30% wider stops during drawdown
    }
    
    return adaptiveStopLoss;
}

//+------------------------------------------------------------------+
//| Get Adaptive Take Profit                                      |
//+------------------------------------------------------------------+
double CAdaptiveRiskManager::GetAdaptiveTakeProfit(const string symbolName, const double baseTakeProfit)
{
    if(!m_initialized) return baseTakeProfit;
    
    double adaptiveTakeProfit = baseTakeProfit;
    
    // Reduce take profit in conservative mode (take profits earlier)
    if(m_conservativeModeActive)
    {
        adaptiveTakeProfit *= 0.8; // 20% closer take profits
    }
    
    return adaptiveTakeProfit;
}

//+------------------------------------------------------------------+
//| Should Adapt Risk                                             |
//+------------------------------------------------------------------+
bool CAdaptiveRiskManager::ShouldAdaptRisk(void)
{
    if(!m_initialized) return false;
    
    CPerformanceAnalytics* analytics = m_perfAnalytics;
    if(CheckPointer(analytics) == POINTER_INVALID)
        return false;
    return (*analytics).ShouldReduceRisk() || (*analytics).ShouldAdjustParameters();
}

//+------------------------------------------------------------------+
//| Get Adaptation Status                                         |
//+------------------------------------------------------------------+
string CAdaptiveRiskManager::GetAdaptationStatus(void)
{
    if(!m_initialized) return "Not initialized";
    
    return StringFormat("Risk: %.2f%% | Confidence: %.2f | Conservative: %s", 
                       m_currentRiskPercent, m_currentConfidenceThreshold,
                       m_conservativeModeActive ? "YES" : "NO");
}

//+------------------------------------------------------------------+
//| Validate Risk Percent                                         |
//+------------------------------------------------------------------+
bool CAdaptiveRiskManager::ValidateRiskPercent(const double riskPercent)
{
    return (riskPercent > 0 && riskPercent <= MAX_RISK_PER_TRADE);
}

//+------------------------------------------------------------------+
//| Validate Confidence Threshold                                 |
//+------------------------------------------------------------------+
bool CAdaptiveRiskManager::ValidateConfidenceThreshold(const double threshold)
{
    return (threshold >= 0.1 && threshold <= 1.0);
}

//+------------------------------------------------------------------+
//| Update Performance Metrics                                    |
//+------------------------------------------------------------------+
void CAdaptiveRiskManager::UpdatePerformanceMetrics(const SPerformanceMetrics &metrics)
{
    if(!m_initialized) return;
    
    // Force immediate adaptation check when performance metrics are updated
    datetime currentTimeLocal = TimeCurrent();
    m_lastAdaptation = currentTimeLocal - m_adaptationInterval; // Force next adaptation
    
    LogAdaptation(StringFormat("Performance metrics updated - WR: %.1f%%, PF: %.2f, DD: %.2f%%", 
                              metrics.winRate, metrics.profitFactor, metrics.maxDrawdown));
}

//+------------------------------------------------------------------+
//| Apply Risk Reduction Factor                                   |
//+------------------------------------------------------------------+
void CAdaptiveRiskManager::ApplyRiskReduction(const double reductionFactor)
{
    if(!m_initialized || reductionFactor <= 0 || reductionFactor > 1.0) return;
    
    // Apply the reduction factor to current risk
    double newRiskPercent = m_currentRiskPercent * reductionFactor;
    
    // Ensure it doesn't go below minimum
    newRiskPercent = MathMax(m_params.minRiskPercent, newRiskPercent);
    
    if(newRiskPercent != m_currentRiskPercent)
    {
        m_currentRiskPercent = newRiskPercent;
        
        // Also increase confidence threshold when reducing risk
        m_currentConfidenceThreshold = MathMin(m_params.maxConfidenceThreshold, 
                                              m_currentConfidenceThreshold + 0.05);
        
        LogAdaptation(StringFormat("Risk reduction applied: Factor=%.2f, New Risk=%.2f%%, New Confidence=%.2f", 
                                  reductionFactor, newRiskPercent, m_currentConfidenceThreshold));
    }
}

//+------------------------------------------------------------------+
//| Log Adaptation                                                |
//+------------------------------------------------------------------+
void CAdaptiveRiskManager::LogAdaptation(const string message)
{
    SErrorContext context;
    context.component = "AdaptiveRiskManager";
    context.operation = "LogAdaptation";
    context.errorCode = 0;
    context.additionalInfo = message;
    context.severity = ERROR_INFO;
    CEnhancedErrorHandler* localErrorHandler = CEnhancedErrorHandler::GetInstance();
    if(CheckPointer(localErrorHandler) != POINTER_INVALID) {
        (*localErrorHandler).LogError(ERROR_INFO, context);
    }
}

#endif // CORE_ADAPTIVE_RISK_MANAGER_MQH
