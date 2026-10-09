// Performance Analytics System
// Tracks and analyzes trading performance metrics
#property copyright "Copyright 2024, Windsurf AI"
#property link      "https://www.windsurf.ai"
#property version   "1.00"
#property strict

#ifndef CORE_PERFORMANCE_ANALYTICS_MQH
#define CORE_PERFORMANCE_ANALYTICS_MQH

#include "../Utils/Enums.mqh"
#include "../Utils/ErrorHandling.mqh"

// Structural decomposition (behaviour unchanged).
// This header is a thin coordinator: it aggregates the extracted
// modules and forwards every call, so that each symbol previously
// declared here remains available to any translation unit.
// PerfAnalyticsTypes.mqh        - MAX_TRADES, stateless math and
// logging helpers
// PerfAnalyticsTradeStats.mqh   - trade statistics aggregation,
// ratio metrics, rolling window,
// streak momentum scaling
// PerfAnalyticsEquity.mqh       - equity curve / drawdown tracking
// PerfAnalyticsRiskTriggers.mqh - performance triggers and risk
// assessment recommendations
// PerfAnalyticsReport.mqh       - reporting / snapshot assembly
#include "PerfAnalyticsTypes.mqh"
#include "PerfAnalyticsTradeStats.mqh"
#include "PerfAnalyticsEquity.mqh"
#include "PerfAnalyticsRiskTriggers.mqh"
#include "PerfAnalyticsReport.mqh"

// Forward declarations
class CEnhancedErrorHandler;
class CUtilities;
class CMarketAnalysis;
class CNextGenStrategyBrain;
class CTransformerBrain;
struct SPredictionWithUncertainty;
class CPositionSizer;
class CTradeManager;
class CPerformanceAnalytics;

class CPerformanceAnalytics : public CEnhancedErrorHandler
{
private:
    // Extracted sub-modules (owned by value)
    CPerfAnalyticsTradeStats   m_stats;      // trade statistics + rolling/streak metrics
    CPerfAnalyticsEquity       m_equity;     // equity curve + drawdown tracking
    CPerfAnalyticsRiskTriggers m_triggers;   // performance triggers + risk assessment

    // Real-time monitoring cadence
    datetime m_lastUpdate;
    datetime m_lastReportTime;

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
    void IncrementSuccessfulTrades(void) { m_stats.IncrementSuccessfulTrades(); }
    void IncrementFailedTrades(void) { m_stats.IncrementFailedTrades(); }
    
    // Real-time monitoring (NEW)
    void UpdateRealTimeMetrics(void);
    void CheckPerformanceTriggers(void);
    bool ShouldReduceRisk(void) const { return m_triggers.NeedsRiskReduction(); }
    bool ShouldAdjustParameters(void) const { return m_triggers.NeedsParameterAdjustment(); }
    
    // Calculate performance metrics
    void CalculateMetrics(void);
    void UpdateEquityCurve(void);
    void UpdateDrawdown(void);
    void CalculateRollingMetrics(void);
    
    // Get performance data
    SPerformanceMetrics GetPerformanceMetrics(void);
    double GetWinRate(void) const { return m_stats.GetWinRate(); }
    double GetProfitFactor(void) const { return m_stats.GetProfitFactor(); }
    double GetSharpeRatio(void) const { return m_stats.GetSharpeRatio(); }
    double GetMaxDrawdown(void) const { return m_equity.GetMaxDrawdown(); }
    double GetCurrentDrawdown(void) const { return m_equity.GetCurrentDrawdown(); }
    double GetRollingWinRate(void) const { return m_stats.GetRollingWinRate(); }
    double GetRollingSharpe(void) const { return m_stats.GetRollingSharpe(); }
    int GetConsecutiveLosses(void) const { return m_stats.GetConsecutiveLosses(); }
    int GetConsecutiveWins(void) const { return m_stats.GetConsecutiveWins(); }

    // Anti-Martingale momentum scaling
    double CalculateMomentumScale(void);

    // Risk assessment
    bool IsPerformanceAcceptable(void);
    ENUM_RISK_LEVEL GetCurrentRiskLevel(void);
    
    void SetRiskFreeRate(double rate) { m_stats.SetRiskFreeRate(rate); }
    
    // Parameter adjustment recommendations (NEW)
    double GetRecommendedRiskReduction(void);
    double GetRecommendedConfidenceThreshold(void);
    bool ShouldEnableConservativeMode(void);
    
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
    void LogPerformanceUpdate(const string message);
};

// Constructor
CPerformanceAnalytics::CPerformanceAnalytics(void) :
    m_lastUpdate(0),
    m_lastReportTime(0),
    m_initialized(false),
    m_startTime(0)
{
    // Sub-module members initialise their own state (arrays, counters)
}

// Destructor
CPerformanceAnalytics::~CPerformanceAnalytics(void)
{
    if(m_initialized)
    {
        if(m_stats.GetTotalTrades() > 0)
            PrintPerformanceReport();
        CEnhancedErrorHandler::LogError(ERROR_INFO, "PerformanceAnalytics", "Performance analytics destroyed", 0);
    }
}

bool CPerformanceAnalytics::Initialize(void)
{
    m_startTime = TimeCurrent();
    m_equity.InitializeEquity();
    m_initialized = true;
    
    CEnhancedErrorHandler::LogError(ERROR_INFO, "PerformanceAnalytics", 
                           StringFormat("Performance analytics initialized - Starting equity: %.2f", m_equity.GetCurrentEquity()));
    
    return true;
}

void CPerformanceAnalytics::RecordTrade(const string tradeSymbol, const ENUM_ORDER_TYPE orderType,
                                       const double volume, const double price)
{
    if(!m_initialized) return;

    LogPerformanceUpdate(StringFormat("Trade recorded: %s %s %.2f lots at %.5f",
                                     tradeSymbol, EnumToString(orderType), volume, price));
}

void CPerformanceAnalytics::RecordClosedTrade(const ulong ticket, const double profit)
{
    if(!m_initialized) return;
    
    // Store return sample in circular buffer (index not advanced yet)
    int slot = m_stats.RegisterTradeSample(profit);
    
    // Update equity curve in the same slot, then advance the shared index
    m_equity.RecordTradeEquity(slot);
    m_stats.AdvanceBufferIndex();
    
    // Update profit/loss tracking
    m_stats.ApplyTradeOutcome(profit);
    
    // Update equity tracking
    UpdateEquityCurve();
    UpdateDrawdown();
    
    CalculateMetrics();
    CalculateRollingMetrics();
    CheckPerformanceTriggers();
    
    LogPerformanceUpdate(StringFormat("Closed trade #%d: Profit %.2f, Total P&L: %.2f", 
                                     (int)ticket, profit, m_stats.GetNetProfit()));
}

void CPerformanceAnalytics::CalculateMetrics(void)
{
    if(!m_initialized) return;
    
    m_stats.CalculateMetrics(m_equity.GetMaxDrawdown(), m_equity.GetPeakEquity());
}

void CPerformanceAnalytics::UpdateEquityCurve(void)
{
    if(!m_initialized) return;
    
    m_equity.UpdateEquityCurve(m_stats.GetBufferIndex());
}

void CPerformanceAnalytics::UpdateDrawdown(void)
{
    if(!m_initialized) return;
    
    m_equity.UpdateDrawdown();
}

SPerformanceMetrics CPerformanceAnalytics::GetPerformanceMetrics(void)
{
    return CPerfAnalyticsReport::BuildPerformanceMetrics(m_stats, m_equity);
}

bool CPerformanceAnalytics::IsPerformanceAcceptable(void)
{
    if(!m_initialized)
        return true; // Not enough data
    
    return m_triggers.IsPerformanceAcceptable(m_stats, m_equity.GetMaxDrawdown());
}

ENUM_RISK_LEVEL CPerformanceAnalytics::GetCurrentRiskLevel(void)
{
    if(!m_initialized)
        return RISK_LEVEL_LOW;
    
    return m_triggers.GetCurrentRiskLevel(m_stats, m_equity.GetCurrentDrawdown());
}

void CPerformanceAnalytics::PrintPerformanceReport(void)
{
    if(!m_initialized) return;
    
    CPerfAnalyticsReport::PrintPerformanceReport(m_stats, m_equity, m_triggers);
}

void CPerformanceAnalytics::SaveReportToCSV(const string filename)
{
    if(!m_initialized) return;
    
    CPerfAnalyticsReport::SaveReportToCSV(filename, m_stats, m_equity);
}

string CPerformanceAnalytics::GetPerformanceSummary(void)
{
    if(!m_initialized)
        return "Performance analytics not initialized";
    
    return CPerfAnalyticsReport::GetPerformanceSummary(m_stats, m_equity);
}

void CPerformanceAnalytics::CalculateWinRate(void)
{
    m_stats.CalculateWinRate();
}

void CPerformanceAnalytics::CalculateProfitFactor(void)
{
    m_stats.CalculateProfitFactor();
}

void CPerformanceAnalytics::CalculateSharpeRatio(void)
{
    m_stats.CalculateSharpeRatio();
}

void CPerformanceAnalytics::CalculateRecoveryFactor(void)
{
    m_stats.CalculateRecoveryFactor(m_equity.GetMaxDrawdown(), m_equity.GetPeakEquity());
}

double CPerformanceAnalytics::CalculateStandardDeviation(const double &returns[])
{
    return CPerfAnalyticsMath::CalculateStandardDeviation(returns);
}

void CPerformanceAnalytics::LogPerformanceUpdate(const string message)
{
    CPerfAnalyticsLog::LogPerformanceUpdate(message);
}

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
    
    CalculateRollingMetrics();
    
    CheckPerformanceTriggers();
    
    // Print dashboard every 5 minutes
    if(currentTimeLocal - m_lastReportTime >= 300)
    {
        PrintRealTimeDashboard();
        m_lastReportTime = currentTimeLocal;
    }
}

void CPerformanceAnalytics::CalculateRollingMetrics(void)
{
    m_stats.CalculateRollingMetrics();
}

void CPerformanceAnalytics::CheckPerformanceTriggers(void)
{
    if(!m_initialized) return;
    
    m_triggers.CheckPerformanceTriggers(m_stats, m_equity.GetCurrentDrawdown());
}

double CPerformanceAnalytics::GetRecommendedRiskReduction(void)
{
    return m_triggers.GetRecommendedRiskReduction(m_stats, m_equity.GetCurrentDrawdown());
}

double CPerformanceAnalytics::GetRecommendedConfidenceThreshold(void)
{
    return m_triggers.GetRecommendedConfidenceThreshold(m_stats);
}

bool CPerformanceAnalytics::ShouldEnableConservativeMode(void)
{
    if(!m_initialized) return false;
    
    return m_triggers.ShouldEnableConservativeMode(m_stats, m_equity.GetCurrentDrawdown());
}

void CPerformanceAnalytics::PrintRealTimeDashboard(void)
{
    if(!m_initialized) return;
    
    CPerfAnalyticsReport::PrintRealTimeDashboard(m_stats, m_equity, m_triggers);
}

// Anti-Martingale Momentum Scale
// Win streak: scale up by 10% per win, capped at 1.5x
// Loss streak: scale down by 15% per loss, floored at 0.5x
double CPerformanceAnalytics::CalculateMomentumScale(void)
{
    return m_stats.CalculateMomentumScale();
}



#endif // CORE_PERFORMANCE_ANALYTICS_MQH
