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
#define MAX_TRADES 1000

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
    double m_sharpeRatioWithRiskFree; // Sharpe ratio with risk-free rate
    double m_maxDrawdown;
    double m_recoveryFactor;
    double m_averageWin;
    double m_averageLoss;
    double m_riskFreeRate; // Configurable risk-free rate
    
    // Tracking arrays - circular buffer
    double m_dailyReturns[];
    double m_equityCurve[];
    datetime m_tradeTimes[];
    double m_recentReturns[20];  // Last 20 trade returns for rolling metrics
    int m_bufferIndex;
    
    // Risk metrics
    double m_currentDrawdown;
    double m_peakEquity;
    double m_currentEquity;
    double m_equityHistoryPeak; // Track peak in circular buffer for accurate drawdown
    
    // Real-time monitoring
    datetime m_lastUpdate;
    datetime m_lastReportTime;
    double m_rollingWinRate;
    double m_rollingSharpe;
    int m_consecutiveLosses;
    int m_consecutiveWins;              // Anti-Martingale: consecutive win streak

    // Momentum scale log throttle
    datetime m_lastMomentumScaleLogTime;
    double m_lastMomentumScaleValue;

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
    int GetConsecutiveWins(void) const { return m_consecutiveWins; }

    // Anti-Martingale momentum scaling
    double CalculateMomentumScale(void);

    // Risk assessment
    bool IsPerformanceAcceptable(void);
    ENUM_RISK_LEVEL GetCurrentRiskLevel(void);
    
    // Set risk-free rate
    void SetRiskFreeRate(double rate) { m_riskFreeRate = MathMax(0.0, rate); }
    
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
    m_sharpeRatioWithRiskFree(0.0),
    m_maxDrawdown(0.0),
    m_recoveryFactor(0.0),
    m_averageWin(0.0),
    m_averageLoss(0.0),
    m_riskFreeRate(BENCHMARK_RETURN), // Default to benchmark return
    m_currentDrawdown(0.0),
    m_peakEquity(0.0),
    m_currentEquity(0.0),
    m_equityHistoryPeak(0.0),
    m_lastUpdate(0),
    m_lastReportTime(0),
    m_rollingWinRate(0.0),
    m_rollingSharpe(0.0),
    m_consecutiveLosses(0),
    m_consecutiveWins(0),
    m_lastMomentumScaleLogTime(0),
    m_lastMomentumScaleValue(1.0),
    m_needsRiskReduction(false),
    m_needsParameterAdjustment(false),
    m_performanceAcceptable(true),
    m_initialized(false),
    m_startTime(0),
    m_bufferIndex(0)
{
    // Initialize arrays - circular buffer size MAX_TRADES
    ArrayResize(m_dailyReturns, MAX_TRADES);
    ArrayResize(m_equityCurve, MAX_TRADES);
    ArrayResize(m_tradeTimes, MAX_TRADES);
    ArrayInitialize(m_recentReturns, 0.0);
    ArrayInitialize(m_dailyReturns, 0.0);
    ArrayInitialize(m_equityCurve, 0.0);
    ArrayInitialize(m_tradeTimes, 0);
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
    
    // Store in circular buffer
    m_tradeTimes[m_bufferIndex] = TimeCurrent();
    m_dailyReturns[m_bufferIndex] = normalizedReturn;
    
    // Update equity curve in circular buffer
    m_currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    m_equityCurve[m_bufferIndex] = m_currentEquity;
    
    // Update peak equity
    if(m_currentEquity > m_peakEquity)
        m_peakEquity = m_currentEquity;
    
    // Increment buffer index, wrap around
    m_bufferIndex++;
    if(m_bufferIndex >= MAX_TRADES)
        m_bufferIndex = 0;
    
    // Update profit/loss tracking
    if(profit > 0)
    {
        m_successfulTrades++;
        m_consecutiveLosses = 0;
        m_consecutiveWins++;
        m_totalProfit += profit;
        if(profit > m_largestWin)
            m_largestWin = profit;
    }
    else if(profit < 0)
    {
        m_failedTrades++;
        m_consecutiveLosses++;
        m_consecutiveWins = 0;
        m_totalLoss += MathAbs(profit);
        if(MathAbs(profit) > m_largestLoss)
            m_largestLoss = MathAbs(profit);
    }
    else
    {
        m_consecutiveLosses = 0;
        m_consecutiveWins = 0;
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
    
    // Update current index in circular buffer
    m_equityCurve[m_bufferIndex] = m_currentEquity;
    
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
    metrics.sharpeRatioWithRiskFree = m_sharpeRatioWithRiskFree;
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
//| Calculate Sharpe Ratio                                          |
//+------------------------------------------------------------------+
void CPerformanceAnalytics::CalculateSharpeRatio(void)
{
    int validTrades = MathMin(m_totalTrades, MAX_TRADES);
    if(validTrades < 10)
    {
        m_sharpeRatio = 0.0;
        m_sharpeRatioWithRiskFree = 0.0;
        return;
    }
    
    // Calculate average return from circular buffer
    double avgReturn = 0.0;
    int count = 0;
    
    // Iterate through circular buffer
    for(int i = 0; i < validTrades; i++)
    {
        int index = (m_bufferIndex - 1 - i + MAX_TRADES) % MAX_TRADES;
        avgReturn += m_dailyReturns[index];
        count++;
    }
    
    avgReturn /= count;
    
    // Create a temporary array for standard deviation calculation
    double tempReturns[];
    ArrayResize(tempReturns, validTrades);
    
    for(int i = 0; i < validTrades; i++)
    {
        int index = (m_bufferIndex - 1 - i + MAX_TRADES) % MAX_TRADES;
        tempReturns[i] = m_dailyReturns[index];
    }
    
    // Calculate standard deviation
    double stdDev = CalculateStandardDeviation(tempReturns);
    
    if(stdDev > 0)
    {
        m_sharpeRatio = avgReturn / stdDev; // Simple Sharpe ratio
        m_sharpeRatioWithRiskFree = (avgReturn - m_riskFreeRate) / stdDev; // Risk-adjusted
    }
    else
    {
        m_sharpeRatio = 0.0;
        m_sharpeRatioWithRiskFree = 0.0;
    }
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
//| Resize Arrays (deprecated - using circular buffer)              |
//+------------------------------------------------------------------+
void CPerformanceAnalytics::ResizeArrays(const int newSize)
{
    // No longer needed - using fixed-size circular buffer
    // ArrayResize(m_dailyReturns, newSize);
    // ArrayResize(m_equityCurve, newSize);
    // ArrayResize(m_tradeTimes, newSize);
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

//+------------------------------------------------------------------+
//| Anti-Martingale Momentum Scale                                   |
//| Win streak: scale up by 10% per win, capped at 1.5x             |
//| Loss streak: scale down by 15% per loss, floored at 0.5x        |
//+------------------------------------------------------------------+
double CPerformanceAnalytics::CalculateMomentumScale(void)
{
    double scale = 1.0;

    // Win streak and loss streak are mutually exclusive (each resets the other)
    if(m_consecutiveWins > 0)
    {
        // Win streak: increase size by 10% per win, capped at 1.5x
        scale = MathMin(1.5, 1.0 + m_consecutiveWins * 0.10);
    }
    else if(m_consecutiveLosses > 0)
    {
        // Loss streak: decrease size by 15% per loss, floored at 0.5x
        scale = MathMax(0.5, 1.0 - m_consecutiveLosses * 0.15);
    }

    // Throttle logging: only print every 60 seconds or when the scale value changes
    datetime now = TimeCurrent();
    if(MathAbs(scale - m_lastMomentumScaleValue) > 0.001 || now - m_lastMomentumScaleLogTime >= 60)
    {
        PrintFormat("[MOMENTUM-SCALE] Wins=%d Losses=%d Scale=%.2f",
                    m_consecutiveWins, m_consecutiveLosses, scale);
        m_lastMomentumScaleLogTime = now;
        m_lastMomentumScaleValue = scale;
    }

    return scale;
}



#endif // CORE_PERFORMANCE_ANALYTICS_MQH

