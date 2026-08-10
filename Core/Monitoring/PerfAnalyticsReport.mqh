//+------------------------------------------------------------------+
//| PerfAnalyticsReport.mqh                                          |
//| Reporting and snapshot assembly: console reports, real-time      |
//| dashboard, CSV export and SPerformanceMetrics assembly.          |
//| Extracted verbatim from PerformanceAnalytics.mqh.                |
//+------------------------------------------------------------------+
#ifndef CORE_PERF_ANALYTICS_REPORT_MQH
#define CORE_PERF_ANALYTICS_REPORT_MQH

#include "PerfAnalyticsTypes.mqh"
#include "PerfAnalyticsTradeStats.mqh"
#include "PerfAnalyticsEquity.mqh"
#include "PerfAnalyticsRiskTriggers.mqh"

//+------------------------------------------------------------------+
//| Stateless reporting helpers                                      |
//+------------------------------------------------------------------+
class CPerfAnalyticsReport
{
public:
    //+--------------------------------------------------------------+
    //| Get Performance Metrics                                      |
    //+--------------------------------------------------------------+
    static SPerformanceMetrics BuildPerformanceMetrics(const CPerfAnalyticsTradeStats &stats,
                                                       const CPerfAnalyticsEquity &equity)
    {
        SPerformanceMetrics metrics;

        metrics.totalTrades = stats.GetTotalTrades();
        metrics.winningTrades = stats.GetSuccessfulTrades();
        metrics.losingTrades = stats.GetLosingTrades();
        metrics.winRate = stats.GetWinRate();
        metrics.totalProfit = stats.GetNetProfit();
        metrics.averageWin = stats.GetAverageWin();
        metrics.averageLoss = stats.GetAverageLoss();
        metrics.profitFactor = stats.GetProfitFactor();
        metrics.sharpeRatio = stats.GetSharpeRatio();
        metrics.sharpeRatioWithRiskFree = stats.GetSharpeRatioWithRiskFree();
        metrics.maxDrawdown = equity.GetMaxDrawdown();
        metrics.recoveryFactor = stats.GetRecoveryFactor();

        return metrics;
    }

    //+--------------------------------------------------------------+
    //| Print Performance Report                                     |
    //+--------------------------------------------------------------+
    static void PrintPerformanceReport(const CPerfAnalyticsTradeStats &stats,
                                       const CPerfAnalyticsEquity &equity,
                                       const CPerfAnalyticsRiskTriggers &triggers)
    {
        Print("\n=== PERFORMANCE ANALYTICS REPORT ===");
        Print("📊 TRADE STATISTICS:");
        Print("   Total Trades: ", stats.GetTotalTrades());
        Print("   Winning Trades: ", stats.GetSuccessfulTrades());
        Print("   Losing Trades: ", stats.GetLosingTrades());
        Print("   Win Rate: ", DoubleToString(stats.GetWinRate(), 1), "%");

        Print("\n💰 PROFIT & LOSS:");
        Print("   Total Profit: $", DoubleToString(stats.GetTotalProfit(), 2));
        Print("   Total Loss: $", DoubleToString(stats.GetTotalLoss(), 2));
        Print("   Net Profit: $", DoubleToString(stats.GetNetProfit(), 2));
        Print("   Largest Win: $", DoubleToString(stats.GetLargestWin(), 2));
        Print("   Largest Loss: $", DoubleToString(stats.GetLargestLoss(), 2));

        Print("\n📈 PERFORMANCE METRICS:");
        Print("   Profit Factor: ", DoubleToString(stats.GetProfitFactor(), 2));
        Print("   Sharpe Ratio: ", DoubleToString(stats.GetSharpeRatio(), 2));
        Print("   Recovery Factor: ", DoubleToString(stats.GetRecoveryFactor(), 2));
        Print("   Average Win: $", DoubleToString(stats.GetAverageWin(), 2));
        Print("   Average Loss: $", DoubleToString(stats.GetAverageLoss(), 2));

        Print("\n⚠️ RISK METRICS:");
        Print("   Current Drawdown: ", DoubleToString(equity.GetCurrentDrawdown(), 2), "%");
        Print("   Maximum Drawdown: ", DoubleToString(equity.GetMaxDrawdown(), 2), "%");
        Print("   Current Risk Level: ", EnumToString(triggers.GetCurrentRiskLevel(stats, equity.GetCurrentDrawdown())));
        Print("   Performance Acceptable: ", triggers.IsPerformanceAcceptable(stats, equity.GetMaxDrawdown()) ? "YES" : "NO");

        Print("=====================================\n");
    }

    //+--------------------------------------------------------------+
    //| Print Real-Time Dashboard                                    |
    //+--------------------------------------------------------------+
    static void PrintRealTimeDashboard(const CPerfAnalyticsTradeStats &stats,
                                       const CPerfAnalyticsEquity &equity,
                                       const CPerfAnalyticsRiskTriggers &triggers)
    {
        Print("\n📊 === REAL-TIME PERFORMANCE DASHBOARD ===");
        Print("🔄 CURRENT METRICS:");
        Print("   Trades: ", stats.GetTotalTrades(), " | Win Rate: ", DoubleToString(stats.GetRollingWinRate(), 1), "%");
        Print("   P&L: $", DoubleToString(stats.GetNetProfit(), 2), " | Drawdown: ", DoubleToString(equity.GetCurrentDrawdown(), 1), "%");
        Print("   Sharpe: ", DoubleToString(stats.GetRollingSharpe(), 2), " | PF: ", DoubleToString(stats.GetProfitFactor(), 2));

        Print("\n⚠️ PERFORMANCE STATUS:");
        Print("   Risk Reduction Needed: ", triggers.NeedsRiskReduction() ? "YES" : "NO");
        Print("   Parameter Adjustment: ", triggers.NeedsParameterAdjustment() ? "YES" : "NO");
        Print("   Conservative Mode: ", triggers.ShouldEnableConservativeMode(stats, equity.GetCurrentDrawdown()) ? "RECOMMENDED" : "NO");
        Print("   Consecutive Losses: ", stats.GetConsecutiveLosses());

        if(triggers.NeedsRiskReduction())
        {
            Print("   📉 Recommended Risk Reduction: ",
                  DoubleToString((1.0 - triggers.GetRecommendedRiskReduction(stats, equity.GetCurrentDrawdown())) * 100.0, 0), "%");
        }

        if(triggers.NeedsParameterAdjustment())
        {
            Print("   🎯 Recommended Confidence Threshold: ",
                  DoubleToString(triggers.GetRecommendedConfidenceThreshold(stats), 2));
        }

        Print("============================================\n");
    }

    //+--------------------------------------------------------------+
    //| Get Performance Summary                                      |
    //+--------------------------------------------------------------+
    static string GetPerformanceSummary(const CPerfAnalyticsTradeStats &stats,
                                        const CPerfAnalyticsEquity &equity)
    {
        return StringFormat("Trades: %d | Win Rate: %.1f%% | P&L: $%.2f | DD: %.1f%% | PF: %.2f",
                            stats.GetTotalTrades(), stats.GetWinRate(), stats.GetNetProfit(),
                            equity.GetCurrentDrawdown(), stats.GetProfitFactor());
    }

    //+--------------------------------------------------------------+
    //| Save Report to CSV                                           |
    //+--------------------------------------------------------------+
    static void SaveReportToCSV(const string filename,
                                const CPerfAnalyticsTradeStats &stats,
                                const CPerfAnalyticsEquity &equity)
    {
        int fileHandle = FileOpen(filename, FILE_WRITE|FILE_CSV);
        if(fileHandle != INVALID_HANDLE)
        {
            FileWrite(fileHandle, "Metric", "Value");
            FileWrite(fileHandle, "Total Trades", stats.GetTotalTrades());
            FileWrite(fileHandle, "Winning Trades", stats.GetSuccessfulTrades());
            FileWrite(fileHandle, "Losing Trades", stats.GetLosingTrades());
            FileWrite(fileHandle, "Win Rate", DoubleToString(stats.GetWinRate(), 2) + "%");
            FileWrite(fileHandle, "Total Profit", DoubleToString(stats.GetTotalProfit(), 2));
            FileWrite(fileHandle, "Total Loss", DoubleToString(stats.GetTotalLoss(), 2));
            FileWrite(fileHandle, "Net Profit", DoubleToString(stats.GetNetProfit(), 2));
            FileWrite(fileHandle, "Profit Factor", DoubleToString(stats.GetProfitFactor(), 2));
            FileWrite(fileHandle, "Sharpe Ratio", DoubleToString(stats.GetSharpeRatio(), 2));
            FileWrite(fileHandle, "Max Drawdown", DoubleToString(equity.GetMaxDrawdown(), 2) + "%");
            FileWrite(fileHandle, "Recovery Factor", DoubleToString(stats.GetRecoveryFactor(), 2));
            FileWrite(fileHandle, "Peak Equity", DoubleToString(equity.GetPeakEquity(), 2));
            FileWrite(fileHandle, "Current Equity", DoubleToString(equity.GetCurrentEquity(), 2));

            FileClose(fileHandle);
            PrintFormat("[PERFORMANCE] Report saved to %s", filename);
        }
        else
        {
            CEnhancedErrorHandler::LogError(ERROR_WARNING, "PerformanceAnalytics", "Failed to open file for report saving", GetLastError());
        }
    }
};

#endif // CORE_PERF_ANALYTICS_REPORT_MQH
