//+------------------------------------------------------------------+
//| Performance Analytics System                                   |
//| Tracks and analyzes trading performance metrics                |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Windsurf AI"
#property link      "https://www.windsurf.ai"
#property version   "1.00"
#property strict

#ifndef CORE_PERFORMANCE_ANALYTICS_MQH
#define CORE_PERFORMANCE_ANALYTICS_MQH

#include "../Utils/Enums.mqh"
#include "../Utils/ErrorHandling.mqh"

// Forward declarations
class CEnhancedErrorHandler;
class CUtilities;
class CHedgingProtection;
class CMarketAnalysis;
class CNextGenStrategyBrain;
class CTransformerBrain;
struct SPredictionWithUncertainty;
class CPositionSizer;
class CStrategyManager;
class CTradeManager;
class CPerformanceAnalytics;

//+------------------------------------------------------------------+
//| Performance Analytics Class                                    |
//+------------------------------------------------------------------+
class CPerformanceAnalytics : public CEnhancedErrorHandler
{
private:
    // Trade statistics
    int m_totalTrades;
    int m_successfulTrades;
    int m_failedTrades;
    double m_totalProfit;
    double m_totalLoss;
    double m_largestWin;
    double m_largestLoss;
    
    // Performance metrics
    double m_winRate;
    double m_profitFactor;
    double m_sharpeRatio;
    double m_maxDrawdown;
    double m_recoveryFactor;
    double m_averageWin;
    double m_averageLoss;
    
    // Tracking arrays
    double m_dailyReturns[];
    double m_equityCurve[];
    datetime m_tradeTimes[];
    double m_recentReturns[20];  // Last 20 trade returns for rolling metrics
    
    // Risk metrics
    double m_currentDrawdown;
    double m_peakEquity;
    double m_currentEquity;
    
    // Real-time monitoring
    datetime m_lastUpdate;
    datetime m_lastReportTime;
    double m_rollingWinRate;
    double m_rollingSharpe;
    int m_consecutiveLosses;
    
    // Performance triggers
    bool m_needsRiskReduction;
    bool m_needsParameterAdjustment;
    bool m_performanceAcceptable;
    
    bool m_initialized;
    datetime m_startTime;
    
public:
    // Constructor
    CPerformanceAnalytics(void);
    
    // Destructor
    ~CPerformanceAnalytics(void);
    
    // Initialize analytics
    bool Initialize(void);
    
    // Record trade operations
    void RecordTrade(const string tradeSymbol, const ENUM_ORDER_TYPE orderType,
                    const double volume, const double price);
    void RecordClosedTrade(const ulong ticket, const double profit);
    
    // Update counters
    void IncrementSuccessfulTrades(void) { m_successfulTrades++; }
    void IncrementFailedTrades(void) { m_failedTrades++; }
    
    // Real-time monitoring (NEW)
    void UpdateRealTimeMetrics(void);
    void CheckPerformanceTriggers(void);
    bool ShouldReduceRisk(void) const { return m_needsRiskReduction; }
    bool ShouldAdjustParameters(void) const { return m_needsParameterAdjustment; }
    
    // Calculate performance metrics
    void CalculateMetrics(void);
    void UpdateEquityCurve(void);
    void UpdateDrawdown(void);
    void CalculateRollingMetrics(void);
    
    // Get performance data
    SPerformanceMetrics GetPerformanceMetrics(void);
    double GetWinRate(void) const { return m_winRate; }
    double GetProfitFactor(void) const { return m_profitFactor; }
    double GetSharpeRatio(void) const { return m_sharpeRatio; }
    double GetMaxDrawdown(void) const { return m_maxDrawdown; }
    double GetCurrentDrawdown(void) const { return m_currentDrawdown; }
    double GetRollingWinRate(void) const { return m_rollingWinRate; }
    double GetRollingSharpe(void) const { return m_rollingSharpe; }
    int GetConsecutiveLosses(void) const { return m_consecutiveLosses; }
    
    // Risk assessment
    bool IsPerformanceAcceptable(void);
    ENUM_RISK_LEVEL GetCurrentRiskLevel(void);
    
    // Parameter adjustment recommendations (NEW)
    double GetRecommendedRiskReduction(void);
    double GetRecommendedConfidenceThreshold(void);
    bool ShouldEnableConservativeMode(void);
    
    // Reporting
    void PrintPerformanceReport(void);
    void PrintRealTimeDashboard(void);
    string GetPerformanceSummary(void);
    void SaveReportToCSV(const string filename);
    
private:
    // Internal calculations
    void CalculateWinRate(void);
    void CalculateProfitFactor(void);
    void CalculateSharpeRatio(void);
    void CalculateRecoveryFactor(void);
    
    // Helper functions
    double CalculateStandardDeviation(const double &returns[]);
    void ResizeArrays(const int newSize);
    void LogPerformanceUpdate(const string message);
};

//+------------------------------------------------------------------+
//| Constructor                                                     |
//+------------------------------------------------------------------+
CPerformanceAnalytics::CPerformanceAnalytics(void) :
    m_totalTrades(0),
    m_successfulTrades(0),
    m_failedTrades(0),
    m_totalProfit(0.0),
    m_totalLoss(0.0),
    m_largestWin(0.0),
    m_largestLoss(0.0),
    m_winRate(0.0),
    m_profitFactor(0.0),
    m_sharpeRatio(0.0),
    m_maxDrawdown(0.0),
    m_recoveryFactor(0.0),
    m_averageWin(0.0),
    m_averageLoss(0.0),
    m_currentDrawdown(0.0),
    m_peakEquity(0.0),
    m_currentEquity(0.0),
    m_lastUpdate(0),
    m_lastReportTime(0),
    m_rollingWinRate(0.0),
    m_rollingSharpe(0.0),
    m_consecutiveLosses(0),
    m_needsRiskReduction(false),
    m_needsParameterAdjustment(false),
    m_performanceAcceptable(true),
    m_initialized(false),
    m_startTime(0)
{
    // Initialize arrays
    ArrayResize(m_dailyReturns, 0);
    ArrayResize(m_equityCurve, 0);
    ArrayResize(m_tradeTimes, 0);
    ArrayInitialize(m_recentReturns, 0.0);
}

//+------------------------------------------------------------------+
//| Destructor                                                      |
//+------------------------------------------------------------------+
CPerformanceAnalytics::~CPerformanceAnalytics(void)
{
    if(m_initialized)
    {
        if(m_totalTrades > 0)
            PrintPerformanceReport();
        CEnhancedErrorHandler::LogError(ERROR_INFO, "PerformanceAnalytics", "Performance analytics destroyed", 0);
    }
}

//+------------------------------------------------------------------+
//| Initialize analytics                                           |
//+------------------------------------------------------------------+
bool CPerformanceAnalytics::Initialize(void)
{
    m_startTime = TimeCurrent();
    m_currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    m_peakEquity = m_currentEquity;
    m_initialized = true;
    
    CEnhancedErrorHandler::LogError(ERROR_INFO, "PerformanceAnalytics", 
                           StringFormat("Performance analytics initialized - Starting equity: %.2f", m_currentEquity));
    
    return true;
}

//+------------------------------------------------------------------+
//| Record Trade                                                   |
//+------------------------------------------------------------------+
void CPerformanceAnalytics::RecordTrade(const string tradeSymbol, const ENUM_ORDER_TYPE orderType,
                                       const double volume, const double price)
{
    if(!m_initialized) return;

    LogPerformanceUpdate(StringFormat("Trade recorded: %s %s %.2f lots at %.5f",
                                     tradeSymbol, EnumToString(orderType), volume, price));
}

//+------------------------------------------------------------------+
//| Record Closed Trade                                           |
//+------------------------------------------------------------------+
void CPerformanceAnalytics::RecordClosedTrade(const ulong ticket, const double profit)
{
    if(!m_initialized) return;

    m_totalTrades++;

    int currentSize = ArraySize(m_tradeTimes);
    if(currentSize <= m_totalTrades)
    {
        ResizeArrays(m_totalTrades + 100);
    }

    double riskDenominator = 0.0;
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    if(balance > 0.0 && equity > 0.0)
        riskDenominator = MathMin(balance, equity);
    else
        riskDenominator = MathMax(balance, equity);
    if(riskDenominator <= 0.0)
        riskDenominator = 1.0;

    double normalizedReturn = (profit / riskDenominator) * 100.0;
    for(int i = ArraySize(m_recentReturns) - 1; i > 0; i--)
        m_recentReturns[i] = m_recentReturns[i - 1];
    m_recentReturns[0] = normalizedReturn;
    m_tradeTimes[m_totalTrades - 1] = TimeCurrent();
    m_dailyReturns[m_totalTrades - 1] = normalizedReturn;
    
    // Update profit/loss tracking
    if(profit > 0)
    {
        m_successfulTrades++;
        m_consecutiveLosses = 0;
        m_totalProfit += profit;
        if(profit > m_largestWin)
            m_largestWin = profit;
    }
    else if(profit < 0)
    {
        m_failedTrades++;
        m_consecutiveLosses++;
        m_totalLoss += MathAbs(profit);
        if(MathAbs(profit) > m_largestLoss)
            m_largestLoss = MathAbs(profit);
    }
    else
    {
        m_consecutiveLosses = 0;
    }
    
    // Update equity tracking
    UpdateEquityCurve();
    UpdateDrawdown();
    
    // Recalculate metrics
    CalculateMetrics();
    CalculateRollingMetrics();
    CheckPerformanceTriggers();
    
    LogPerformanceUpdate(StringFormat("Closed trade #%d: Profit %.2f, Total P&L: %.2f", 
                                     (int)ticket, profit, m_totalProfit - m_totalLoss));
}

//+------------------------------------------------------------------+
//| Calculate Performance Metrics                                  |
//+------------------------------------------------------------------+
void CPerformanceAnalytics::CalculateMetrics(void)
{
    if(!m_initialized || m_totalTrades == 0) return;
    
    CalculateWinRate();
    CalculateProfitFactor();
    CalculateSharpeRatio();
    CalculateRecoveryFactor();
    
    // Calculate averages
    if(m_successfulTrades > 0)
        m_averageWin = m_totalProfit / m_successfulTrades;
    
    int losingTradesLocal = m_totalTrades - m_successfulTrades;
    if(losingTradesLocal > 0)
        m_averageLoss = m_totalLoss / losingTradesLocal;
}

//+------------------------------------------------------------------+
//| Update Equity Curve                                           |
//+------------------------------------------------------------------+
void CPerformanceAnalytics::UpdateEquityCurve(void)
{
    if(!m_initialized) return;
    
    m_currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    
    // Resize equity curve array if needed
    int currentSize = ArraySize(m_equityCurve);
    if(currentSize <= m_totalTrades)
    {
        ArrayResize(m_equityCurve, m_totalTrades + 100);
    }
    
    // Record current equity
    if(m_totalTrades > 0)
        m_equityCurve[m_totalTrades - 1] = m_currentEquity;
    
    // Update peak equity
    if(m_currentEquity > m_peakEquity)
        m_peakEquity = m_currentEquity;
}

//+------------------------------------------------------------------+
//| Update Drawdown                                                |
//+------------------------------------------------------------------+
void CPerformanceAnalytics::UpdateDrawdown(void)
{
    if(!m_initialized || m_peakEquity <= 0) return;
    
    // Calculate current drawdown
    m_currentDrawdown = ((m_peakEquity - m_currentEquity) / m_peakEquity) * 100.0;
    
    // Update maximum drawdown
    if(m_currentDrawdown > m_maxDrawdown)
        m_maxDrawdown = m_currentDrawdown;
}

//+------------------------------------------------------------------+
//| Get Performance Metrics                                        |
//+------------------------------------------------------------------+
SPerformanceMetrics CPerformanceAnalytics::GetPerformanceMetrics(void)
{
    SPerformanceMetrics metrics;
    
    metrics.totalTrades = m_totalTrades;
    metrics.winningTrades = m_successfulTrades;
    metrics.losingTrades = m_totalTrades - m_successfulTrades;
    metrics.winRate = m_winRate;
    metrics.totalProfit = m_totalProfit - m_totalLoss;
    metrics.averageWin = m_averageWin;
    metrics.averageLoss = m_averageLoss;
    metrics.profitFactor = m_profitFactor;
    metrics.sharpeRatio = m_sharpeRatio;
    metrics.maxDrawdown = m_maxDrawdown;
    metrics.recoveryFactor = m_recoveryFactor;
    
    return metrics;
}

//+------------------------------------------------------------------+
//| Check if Performance is Acceptable                            |
//+------------------------------------------------------------------+
bool CPerformanceAnalytics::IsPerformanceAcceptable(void)
{
    if(!m_initialized || m_totalTrades < MIN_TRADES_FOR_STATS)
        return true; // Not enough data
    
    // Check key performance indicators
    if(m_winRate < 30.0) // Win rate too low
        return false;
    
    if(m_profitFactor < 1.1) // Profit factor too low
        return false;
    
    if(m_maxDrawdown > DRAWDOWN_CRITICAL) // Drawdown too high
        return false;
    
    return true;
}

//+------------------------------------------------------------------+
//| Get Current Risk Level                                         |
//+------------------------------------------------------------------+
ENUM_RISK_LEVEL CPerformanceAnalytics::GetCurrentRiskLevel(void)
{
    if(!m_initialized)
        return RISK_LEVEL_LOW;
    
    if(m_currentDrawdown > DRAWDOWN_CRITICAL)
        return RISK_LEVEL_EXTREME;
    else if(m_currentDrawdown > DRAWDOWN_WARNING)
        return RISK_LEVEL_HIGH;
    else if(m_winRate < 40.0 || m_profitFactor < 1.2)
        return RISK_LEVEL_MEDIUM;
    else
        return RISK_LEVEL_LOW;
}

//+------------------------------------------------------------------+
//| Print Performance Report                                       |
//+------------------------------------------------------------------+
void CPerformanceAnalytics::PrintPerformanceReport(void)
{
    if(!m_initialized) return;
    
    Print("\n=== PERFORMANCE ANALYTICS REPORT ===");
    Print("📊 TRADE STATISTICS:");
    Print("   Total Trades: ", m_totalTrades);
    Print("   Winning Trades: ", m_successfulTrades);
    Print("   Losing Trades: ", m_totalTrades - m_successfulTrades);
    Print("   Win Rate: ", DoubleToString(m_winRate, 1), "%");
    
    Print("\n💰 PROFIT & LOSS:");
    Print("   Total Profit: $", DoubleToString(m_totalProfit, 2));
    Print("   Total Loss: $", DoubleToString(m_totalLoss, 2));
    Print("   Net Profit: $", DoubleToString(m_totalProfit - m_totalLoss, 2));
    Print("   Largest Win: $", DoubleToString(m_largestWin, 2));
    Print("   Largest Loss: $", DoubleToString(m_largestLoss, 2));
    
    Print("\n📈 PERFORMANCE METRICS:");
    Print("   Profit Factor: ", DoubleToString(m_profitFactor, 2));
    Print("   Sharpe Ratio: ", DoubleToString(m_sharpeRatio, 2));
    Print("   Recovery Factor: ", DoubleToString(m_recoveryFactor, 2));
    Print("   Average Win: $", DoubleToString(m_averageWin, 2));
    Print("   Average Loss: $", DoubleToString(m_averageLoss, 2));
    
    Print("\n⚠️ RISK METRICS:");
    Print("   Current Drawdown: ", DoubleToString(m_currentDrawdown, 2), "%");
    Print("   Maximum Drawdown: ", DoubleToString(m_maxDrawdown, 2), "%");
    Print("   Current Risk Level: ", EnumToString(GetCurrentRiskLevel()));
    Print("   Performance Acceptable: ", IsPerformanceAcceptable() ? "YES" : "NO");
    
    Print("=====================================\n");
}

//+------------------------------------------------------------------+
//| Save Report to CSV                                             |
//+------------------------------------------------------------------+
void CPerformanceAnalytics::SaveReportToCSV(const string filename)
{
    if(!m_initialized) return;
    
    int fileHandle = FileOpen(filename, FILE_WRITE|FILE_CSV);
    if(fileHandle != INVALID_HANDLE)
    {
        FileWrite(fileHandle, "Metric", "Value");
        FileWrite(fileHandle, "Total Trades", m_totalTrades);
        FileWrite(fileHandle, "Winning Trades", m_successfulTrades);
        FileWrite(fileHandle, "Losing Trades", m_totalTrades - m_successfulTrades);
        FileWrite(fileHandle, "Win Rate", DoubleToString(m_winRate, 2) + "%");
        FileWrite(fileHandle, "Total Profit", DoubleToString(m_totalProfit, 2));
        FileWrite(fileHandle, "Total Loss", DoubleToString(m_totalLoss, 2));
        FileWrite(fileHandle, "Net Profit", DoubleToString(m_totalProfit - m_totalLoss, 2));
        FileWrite(fileHandle, "Profit Factor", DoubleToString(m_profitFactor, 2));
        FileWrite(fileHandle, "Sharpe Ratio", DoubleToString(m_sharpeRatio, 2));
        FileWrite(fileHandle, "Max Drawdown", DoubleToString(m_maxDrawdown, 2) + "%");
        FileWrite(fileHandle, "Recovery Factor", DoubleToString(m_recoveryFactor, 2));
        FileWrite(fileHandle, "Peak Equity", DoubleToString(m_peakEquity, 2));
        FileWrite(fileHandle, "Current Equity", DoubleToString(m_currentEquity, 2));
        
        FileClose(fileHandle);
        PrintFormat("[PERFORMANCE] Report saved to %s", filename);
    }
    else
    {
        CEnhancedErrorHandler::LogError(ERROR_WARNING, "PerformanceAnalytics", "Failed to open file for report saving", GetLastError());
    }
}

//+------------------------------------------------------------------+
//| Get Performance Summary                                        |
//+------------------------------------------------------------------+
string CPerformanceAnalytics::GetPerformanceSummary(void)
{
    if(!m_initialized)
        return "Performance analytics not initialized";
    
    return StringFormat("Trades: %d | Win Rate: %.1f%% | P&L: $%.2f | DD: %.1f%% | PF: %.2f",
                       m_totalTrades, m_winRate, m_totalProfit - m_totalLoss, 
                       m_currentDrawdown, m_profitFactor);
}

//+------------------------------------------------------------------+
//| Calculate Win Rate                                             |
//+------------------------------------------------------------------+
void CPerformanceAnalytics::CalculateWinRate(void)
{
    if(m_totalTrades > 0)
        m_winRate = ((double)m_successfulTrades / m_totalTrades) * 100.0;
    else
        m_winRate = 0.0;
}

//+------------------------------------------------------------------+
//| Calculate Profit Factor                                        |
//+------------------------------------------------------------------+
void CPerformanceAnalytics::CalculateProfitFactor(void)
{
    if(m_totalLoss > 0)
        m_profitFactor = m_totalProfit / m_totalLoss;
    else if(m_totalProfit > 0)
        m_profitFactor = m_totalProfit; // No losses yet
    else
        m_profitFactor = 0.0;
}

//+------------------------------------------------------------------+
//| Calculate Sharpe Ratio                                         |
//+------------------------------------------------------------------+
void CPerformanceAnalytics::CalculateSharpeRatio(void)
{
    if(ArraySize(m_dailyReturns) < 10)
    {
        m_sharpeRatio = 0.0;
        return;
    }
    
    // Calculate average return
    double avgReturn = 0.0;
    int size = ArraySize(m_dailyReturns);
    for(int i = 0; i < size; i++)
        avgReturn += m_dailyReturns[i];
    avgReturn /= size;
    
    // Calculate standard deviation
    double stdDev = CalculateStandardDeviation(m_dailyReturns);
    
    if(stdDev > 0)
        m_sharpeRatio = (avgReturn - BENCHMARK_RETURN) / stdDev;
    else
        m_sharpeRatio = 0.0;
}

//+------------------------------------------------------------------+
//| Calculate Recovery Factor                                      |
//+------------------------------------------------------------------+
void CPerformanceAnalytics::CalculateRecoveryFactor(void)
{
    double netProfit = m_totalProfit - m_totalLoss;
    if(m_maxDrawdown > 0)
        m_recoveryFactor = netProfit / m_maxDrawdown;
    else if(netProfit > 0)
        m_recoveryFactor = netProfit; // No drawdown yet
    else
        m_recoveryFactor = 0.0;
}

//+------------------------------------------------------------------+
//| Calculate Standard Deviation                                   |
//+------------------------------------------------------------------+
double CPerformanceAnalytics::CalculateStandardDeviation(const double &returns[])
{
    int size = ArraySize(returns);
    if(size < 2) return 0.0;
    
    // Calculate mean
    double mean = 0.0;
    for(int i = 0; i < size; i++)
        mean += returns[i];
    mean /= size;
    
    // Calculate variance
    double variance = 0.0;
    for(int i = 0; i < size; i++)
    {
        double diff = returns[i] - mean;
        variance += diff * diff;
    }
    variance /= (size - 1);
    
    return MathSqrt(variance);
}

//+------------------------------------------------------------------+
//| Resize Arrays                                                  |
//+------------------------------------------------------------------+
void CPerformanceAnalytics::ResizeArrays(const int newSize)
{
    ArrayResize(m_dailyReturns, newSize);
    ArrayResize(m_equityCurve, newSize);
    ArrayResize(m_tradeTimes, newSize);
}

//+------------------------------------------------------------------+
//| Log Performance Update                                         |
//+------------------------------------------------------------------+
void CPerformanceAnalytics::LogPerformanceUpdate(const string message)
{
    CEnhancedErrorHandler::LogError(ERROR_INFO, "PerformanceAnalytics", message, 0);
}

//+------------------------------------------------------------------+
//| Update Real-Time Metrics                                      |
//+------------------------------------------------------------------+
void CPerformanceAnalytics::UpdateRealTimeMetrics(void)
{
    if(!m_initialized) return;
    
    datetime currentTimeLocal = TimeCurrent();
    
    // Update every 30 seconds
    if(currentTimeLocal - m_lastUpdate < 30) return;
    
    m_lastUpdate = currentTimeLocal;
    
    // Update current equity and drawdown
    UpdateEquityCurve();
    UpdateDrawdown();
    
    // Calculate rolling metrics
    CalculateRollingMetrics();
    
    // Check for performance triggers
    CheckPerformanceTriggers();
    
    // Print dashboard every 5 minutes
    if(currentTimeLocal - m_lastReportTime >= 300)
    {
        PrintRealTimeDashboard();
        m_lastReportTime = currentTimeLocal;
    }
}

//+------------------------------------------------------------------+
//| Calculate Rolling Metrics                                     |
//+------------------------------------------------------------------+
void CPerformanceAnalytics::CalculateRollingMetrics(void)
{
    if(m_totalTrades < 5) return; // Need minimum trades
    
    // Calculate rolling win rate from recent returns
    int wins = 0;
    int validReturns = 0;
    
    for(int i = 0; i < 20; i++)
    {
        if(m_recentReturns[i] != 0.0)
        {
            validReturns++;
            if(m_recentReturns[i] > 0) wins++;
        }
    }
    
    if(validReturns > 0)
        m_rollingWinRate = ((double)wins / validReturns) * 100.0;
    
    // Calculate rolling Sharpe ratio
    if(validReturns >= 10)
    {
        double avgReturn = 0.0;
        for(int i = 0; i < validReturns; i++)
            avgReturn += m_recentReturns[i];
        avgReturn /= validReturns;
        
        double variance = 0.0;
        for(int i = 0; i < validReturns; i++)
        {
            double diff = m_recentReturns[i] - avgReturn;
            variance += diff * diff;
        }
        variance /= (validReturns - 1);
        
        double stdDev = MathSqrt(variance);
        if(stdDev > 0)
            m_rollingSharpe = avgReturn / stdDev;
    }
}

//+------------------------------------------------------------------+
//| Check Performance Triggers                                     |
//+------------------------------------------------------------------+
void CPerformanceAnalytics::CheckPerformanceTriggers(void)
{
    if(!m_initialized || m_totalTrades < MIN_TRADES_FOR_STATS) return;
    
    // Reset flags
    m_needsRiskReduction = false;
    m_needsParameterAdjustment = false;
    m_performanceAcceptable = true;
    
    // Check win rate trigger (Requirement 6.1)
    if(m_rollingWinRate < 40.0 && m_totalTrades >= 20)
    {
        m_needsRiskReduction = true;
        m_needsParameterAdjustment = true;
        LogPerformanceUpdate(StringFormat("Performance trigger: Win rate %.1f%% below 40%", m_rollingWinRate));
    }
    
    // Check Sharpe ratio trigger (Requirement 6.2)
    if(m_rollingSharpe < 0.5 && m_totalTrades >= 20)
    {
        m_needsParameterAdjustment = true;
        LogPerformanceUpdate(StringFormat("Performance trigger: Sharpe ratio %.2f below 0.5", m_rollingSharpe));
    }
    
    // Check drawdown trigger (Requirement 6.3)
    if(m_currentDrawdown > DRAWDOWN_WARNING)
    {
        m_needsRiskReduction = true;
        if(m_currentDrawdown > DRAWDOWN_CRITICAL)
        {
            m_performanceAcceptable = false;
            LogPerformanceUpdate(StringFormat("Critical drawdown: %.2f%% exceeds %.2f%%", m_currentDrawdown, DRAWDOWN_CRITICAL));
        }
    }
    
    // Check consecutive losses
    if(m_consecutiveLosses >= MAX_CONSECUTIVE_LOSSES)
    {
        m_needsRiskReduction = true;
        m_needsParameterAdjustment = true;
        LogPerformanceUpdate(StringFormat("Performance trigger: %d consecutive losses", m_consecutiveLosses));
    }
    
    // Check profit factor
    if(m_profitFactor < 1.2 && m_totalTrades >= 20)
    {
        m_needsParameterAdjustment = true;
        LogPerformanceUpdate(StringFormat("Performance trigger: Profit factor %.2f below 1.2", m_profitFactor));
    }
}

//+------------------------------------------------------------------+
//| Get Recommended Risk Reduction                                 |
//+------------------------------------------------------------------+
double CPerformanceAnalytics::GetRecommendedRiskReduction(void)
{
    if(!m_needsRiskReduction) return 1.0; // No reduction needed
    
    double reductionFactor = 1.0;
    
    // Reduce based on win rate
    if(m_rollingWinRate < 30.0)
        reductionFactor *= 0.3; // 70% reduction
    else if(m_rollingWinRate < 40.0)
        reductionFactor *= 0.5; // 50% reduction
    
    // Reduce based on drawdown
    if(m_currentDrawdown > DRAWDOWN_CRITICAL)
        reductionFactor *= 0.2; // 80% reduction
    else if(m_currentDrawdown > DRAWDOWN_WARNING)
        reductionFactor *= 0.5; // 50% reduction
    
    // Reduce based on consecutive losses
    if(m_consecutiveLosses >= MAX_CONSECUTIVE_LOSSES)
        reductionFactor *= 0.3; // 70% reduction
    
    return MathMax(reductionFactor, 0.1); // Minimum 10% of original risk
}

//+------------------------------------------------------------------+
//| Get Recommended Confidence Threshold                          |
//+------------------------------------------------------------------+
double CPerformanceAnalytics::GetRecommendedConfidenceThreshold(void)
{
    double baseThreshold = 0.65; // Default threshold
    
    if(!m_needsParameterAdjustment) return baseThreshold;
    
    // Increase threshold when performance is poor
    if(m_rollingWinRate < 30.0)
        return 0.85; // Very high threshold
    else if(m_rollingWinRate < 40.0)
        return 0.75; // High threshold
    
    if(m_rollingSharpe < 0.3)
        return 0.80; // High threshold for poor Sharpe
    
    if(m_consecutiveLosses >= MAX_CONSECUTIVE_LOSSES)
        return 0.80; // High threshold after losses
    
    return baseThreshold;
}

//+------------------------------------------------------------------+
//| Should Enable Conservative Mode                               |
//+------------------------------------------------------------------+
bool CPerformanceAnalytics::ShouldEnableConservativeMode(void)
{
    if(!m_initialized || m_totalTrades < MIN_TRADES_FOR_STATS) return false;
    
    // Enable conservative mode if multiple triggers are active
    int triggerCount = 0;
    
    if(m_rollingWinRate < 40.0) triggerCount++;
    if(m_rollingSharpe < 0.5) triggerCount++;
    if(m_currentDrawdown > DRAWDOWN_WARNING) triggerCount++;
    if(m_consecutiveLosses >= 3) triggerCount++;
    if(m_profitFactor < 1.2) triggerCount++;
    
    return triggerCount >= 2; // Conservative mode if 2+ triggers
}

//+------------------------------------------------------------------+
//| Print Real-Time Dashboard                                     |
//+------------------------------------------------------------------+
void CPerformanceAnalytics::PrintRealTimeDashboard(void)
{
    if(!m_initialized) return;
    
    Print("\n📊 === REAL-TIME PERFORMANCE DASHBOARD ===");
    Print("🔄 CURRENT METRICS:");
    Print("   Trades: ", m_totalTrades, " | Win Rate: ", DoubleToString(m_rollingWinRate, 1), "%");
    Print("   P&L: $", DoubleToString(m_totalProfit - m_totalLoss, 2), " | Drawdown: ", DoubleToString(m_currentDrawdown, 1), "%");
    Print("   Sharpe: ", DoubleToString(m_rollingSharpe, 2), " | PF: ", DoubleToString(m_profitFactor, 2));
    
    Print("\n⚠️ PERFORMANCE STATUS:");
    Print("   Risk Reduction Needed: ", m_needsRiskReduction ? "YES" : "NO");
    Print("   Parameter Adjustment: ", m_needsParameterAdjustment ? "YES" : "NO");
    Print("   Conservative Mode: ", ShouldEnableConservativeMode() ? "RECOMMENDED" : "NO");
    Print("   Consecutive Losses: ", m_consecutiveLosses);
    
    if(m_needsRiskReduction)
    {
        Print("   📉 Recommended Risk Reduction: ", DoubleToString((1.0 - GetRecommendedRiskReduction()) * 100, 0), "%");
    }
    
    if(m_needsParameterAdjustment)
    {
        Print("   🎯 Recommended Confidence Threshold: ", DoubleToString(GetRecommendedConfidenceThreshold(), 2));
    }
    
    Print("============================================\n");
}



#endif // CORE_PERFORMANCE_ANALYTICS_MQH

