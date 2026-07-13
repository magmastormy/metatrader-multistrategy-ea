//+------------------------------------------------------------------+
//| TradeStatistics.mqh                                              |
//| Trade execution statistics, metrics, and performance tracking    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Windsurf AI"
#property link      "https://www.windsurf.ai"
#property version   "2.00"
#property strict

#ifndef CORE_TRADE_STATISTICS_MQH
#define CORE_TRADE_STATISTICS_MQH

#include "../Utils/Enums.mqh"
#include "../Utils/ErrorHandling.mqh"
#include "TradeTypes.mqh"

#define MAX_TRADE_HISTORY 1000
#define MAX_SYMBOL_STATS 100

struct STradeRecord
{
    ulong ticket;
    string symbol;
    ENUM_ORDER_TYPE orderType;
    double volume;
    double openPrice;
    double closePrice;
    double stopLoss;
    double takeProfit;
    double profit;
    double commission;
    double swap;
    datetime openTime;
    datetime closeTime;
    ulong magic;
    string comment;

    STradeRecord()
    {
        ticket = 0;
        orderType = ORDER_TYPE_BUY;
        volume = 0;
        openPrice = 0;
        closePrice = 0;
        stopLoss = 0;
        takeProfit = 0;
        profit = 0;
        commission = 0;
        swap = 0;
        openTime = 0;
        closeTime = 0;
        magic = 0;
    }
};

class CTradeStatistics
{
private:
    STradeRecord m_tradeHistory[MAX_TRADE_HISTORY];
    int m_historyCount;
    int m_historyIndex;

    SSymbolTradeStats m_symbolStats[MAX_SYMBOL_STATS];
    int m_symbolCount;

    SExecutionQualityMetrics m_execMetrics;

    // Global stats
    int m_totalTrades;
    int m_successfulTrades;
    int m_failedTrades;
    double m_totalProfit;
    double m_totalLoss;
    double m_netProfit;
    double m_maxDrawdown;
    double m_maxEquity;
    double m_currentEquity;
    datetime m_lastTradeTime;

    // Performance periods
    double m_dailyPnL;
    double m_weeklyPnL;
    double m_monthlyPnL;
    datetime m_dailyResetTime;
    datetime m_weeklyResetTime;
    datetime m_monthlyResetTime;

public:
    struct SGlobalStats
    {
        int totalTrades;
        int successfulTrades;
        int failedTrades;
        double totalProfit;
        double totalLoss;
        double netProfit;
        double maxDrawdown;
        double winRate;
        double profitFactor;
        double sharpeRatio;
        double expectancy;
        datetime lastTradeTime;

        SGlobalStats() : totalTrades(0), successfulTrades(0), failedTrades(0),
                         totalProfit(0), totalLoss(0), netProfit(0), maxDrawdown(0),
                         winRate(0), profitFactor(0), sharpeRatio(0), expectancy(0),
                         lastTradeTime(0) {}
    };

    CTradeStatistics() : m_historyCount(0), m_historyIndex(0), m_symbolCount(0),
                         m_totalTrades(0), m_successfulTrades(0), m_failedTrades(0),
                         m_totalProfit(0), m_totalLoss(0), m_netProfit(0), m_maxDrawdown(0),
                         m_maxEquity(0), m_currentEquity(0), m_lastTradeTime(0),
                         m_dailyPnL(0), m_weeklyPnL(0), m_monthlyPnL(0)
    {
        m_dailyResetTime = TimeCurrent();
        m_weeklyResetTime = TimeCurrent();
        m_monthlyResetTime = TimeCurrent();
        ZeroMemory(m_tradeHistory);
        ZeroMemory(m_symbolStats);
    }

    ~CTradeStatistics() {}

    // Record a completed trade
    void RecordTrade(const STradeRecord &record);

    // Record execution quality metrics
    void RecordExecutionMetrics(const string symbol, const double slippagePoints,
                               const double spreadCost, const double latencyMs,
                               const bool filled, const bool partialFill);

    // Get global statistics
    SGlobalStats GetGlobalStats() const;

    // Get symbol-specific statistics
    bool GetSymbolStats(const string symbol, SSymbolTradeStats &stats) const;

    // Get execution quality metrics
    ExecutionQualityMetrics GetExecutionMetrics() const { return m_execMetrics; }

    // Get recent trades
    int GetRecentTrades(STradeRecord &records[], const int count, const datetime fromTime = 0) const;

    // Reset period PnL
    void ResetDailyPnL() { m_dailyPnL = 0; m_dailyResetTime = TimeCurrent(); }
    void ResetWeeklyPnL() { m_weeklyPnL = 0; m_weeklyResetTime = TimeCurrent(); }
    void ResetMonthlyPnL() { m_monthlyPnL = 0; m_monthlyResetTime = TimeCurrent(); }

    // Get period PnL
    double GetDailyPnL() const { return m_dailyPnL; }
    double GetWeeklyPnL() const { return m_weeklyPnL; }
    double GetMonthlyPnL() const { return m_monthlyPnL; }

    // Calculate performance metrics
    double CalculateWinRate() const;
    double CalculateProfitFactor() const;
    double CalculateExpectancy() const;
    double CalculateSharpeRatio(const int periodBars = 100) const;
    double CalculateMaxDrawdown() const;

    // Export to JSON
    string GetGlobalStatsJSON() const;
    string GetSymbolStatsJSON() const;

private:
    int FindSymbolIndex(const string symbol);
    void UpdateSymbolStats(const string symbol, const STradeRecord &record);
    void UpdateGlobalStats(const STradeRecord &record);
    void UpdatePeriodPnL(const double profit);
    double CalculateReturnsStdDev(const int periodBars) const;
};

#endif // CORE_TRADE_STATISTICS_MQH