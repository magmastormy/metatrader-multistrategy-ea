// Execution-quality telemetry extracted from CTradeManager
// Phase D, batch T2a. This module OWNS the execution-quality
// counters that used to live in CTradeManager::m_execMetrics:
// - UpdateExecutionMetrics   (the single ingest point; all 10
// writes to the metrics block happen here and nowhere else)
// - GetExecutionQualityMetrics / GetExecutionQualitySummary
// - GenerateExecutionQualityReport
// - ResetExecutionMetrics
// - narrow field getters for the one reader that stays behind
// in CTradeManager (AnalyzeAndRecommendOrderParams, which is
// entangled with the out-of-scope slippage/fill-mode config).
// STATE OWNERSHIP: CTradeManager holds this class BY VALUE and
// keeps thin forwarders with the original public signatures, so
// every existing call site is unchanged.
// NO BACK-POINTER: the two log-emitting bodies need a handful of
// CTradeManager configuration values (log level and the dynamic-
// slippage display block). Those are passed in as parameters
// rather than read through a back-pointer, keeping this module
// free of any dependency on CTradeManager.
// NOTE: the metrics struct is the pre-existing top-level
// ExecutionQualityMetrics from TradeTypes.mqh (field-for-field
// identical to the old nested CTradeManager::ExecutionQualityMetrics
// that this batch deletes) - see the report for details.
#property copyright "Copyright 2024, Windsurf AI"
#property link      "https://www.windsurf.ai"
#property strict

#ifndef CORE_TRADING_EXECUTION_QUALITY_TRACKER_MQH
#define CORE_TRADING_EXECUTION_QUALITY_TRACKER_MQH

#include "TradeTypes.mqh"            // ExecutionQualityMetrics, STradeExecutionReceipt
#include "TradeSpreadCostModel.mqh"  // Phase D T1: CTradeSpreadCostModel::CalculateSpreadCost

// Owns the execution-quality counters and every reader of them.
class CExecutionQualityTracker
{
private:
    ExecutionQualityMetrics m_execMetrics;

public:
    CExecutionQualityTracker()
    {
        // Verbatim replacement for the ZeroMemory(m_execMetrics) that used
        // to run in CTradeManager's constructor.
        ZeroMemory(m_execMetrics);
    }

    //--- Narrow read accessors (used by the reader retained in CTradeManager)
    int      TotalOrders(void)         const { return m_execMetrics.totalOrders; }
    int      FilledOrders(void)        const { return m_execMetrics.filledOrders; }
    int      PartialFills(void)        const { return m_execMetrics.partialFills; }
    int      RejectedOrders(void)      const { return m_execMetrics.rejectedOrders; }
    double   TotalSlippagePoints(void) const { return m_execMetrics.totalSlippagePoints; }
    double   TotalSpreadCost(void)     const { return m_execMetrics.totalSpreadCost; }
    double   TotalLatencyMs(void)      const { return m_execMetrics.totalLatencyMs; }
    double   MaxSlippagePoints(void)   const { return m_execMetrics.maxSlippagePoints; }
    double   MaxLatencyMs(void)        const { return m_execMetrics.maxLatencyMs; }
    datetime LastUpdateTime(void)      const { return m_execMetrics.lastUpdateTime; }

    void GetExecutionQualityMetrics(int &totalOrders, int &filledOrders, int &partialFills, int &rejectedOrders,
                                     double &avgSlippagePoints, double &avgLatencyMs, double &fillRate)
    {
        totalOrders = m_execMetrics.totalOrders;
        filledOrders = m_execMetrics.filledOrders;
        partialFills = m_execMetrics.partialFills;
        rejectedOrders = m_execMetrics.rejectedOrders;

        if(m_execMetrics.filledOrders > 0)
        {
            avgSlippagePoints = m_execMetrics.totalSlippagePoints / m_execMetrics.filledOrders;
            avgLatencyMs = m_execMetrics.totalLatencyMs / m_execMetrics.filledOrders;
        }
        else
        {
            avgSlippagePoints = 0.0;
            avgLatencyMs = 0.0;
        }

        if(m_execMetrics.totalOrders > 0)
        {
            fillRate = (double)m_execMetrics.filledOrders / m_execMetrics.totalOrders * 100.0;
        }
        else
        {
            fillRate = 0.0;
        }
    }

    void GetExecutionQualitySummary(string &summary, const int logLevel)
    {
        if(logLevel < 3)
        {
            summary = "";
            return;
        }
        int total, filled, partial, rejected;
        double avgSlippage, avgLatency, fillRate;
        GetExecutionQualityMetrics(total, filled, partial, rejected, avgSlippage, avgLatency, fillRate);

        summary = StringFormat("[EXECUTION-QUALITY] Total: %d | Filled: %d | Partial: %d | Rejected: %d | "
                              "Fill Rate: %.1f%% | Avg Slippage: %.1f pts | Avg Latency: %.0f ms | "
                              "Max Slippage: %.1f pts | Max Latency: %.0f ms",
                              total, filled, partial, rejected, fillRate, avgSlippage, avgLatency,
                              m_execMetrics.maxSlippagePoints, m_execMetrics.maxLatencyMs);
    }

    void ResetExecutionMetrics()
    {
        ZeroMemory(m_execMetrics);
    }

    // Generate detailed execution quality report
    void GenerateExecutionQualityReport(const int logLevel,
                                        const bool enableDynamicSlippage,
                                        const double dynamicSlippageAtrPercent,
                                        const uint dynamicSlippageMinPoints,
                                        const uint dynamicSlippageMaxMultiplier,
                                        const uint slippage)
    {
        if(logLevel < 3)
            return;

        Print("========== EXECUTION QUALITY REPORT ==========");
        PrintFormat("Report Generated: %s", TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS));

        if(m_execMetrics.totalOrders == 0)
        {
            Print("[EXECUTION-REPORT] No orders executed yet.");
            Print("==============================================");
            return;
        }

        // Order statistics
        double fillRate = (double)m_execMetrics.filledOrders / m_execMetrics.totalOrders * 100.0;
        double partialRate = m_execMetrics.filledOrders > 0 ?
                            (double)m_execMetrics.partialFills / m_execMetrics.filledOrders * 100.0 : 0.0;
        double rejectRate = (double)m_execMetrics.rejectedOrders / m_execMetrics.totalOrders * 100.0;

        Print("--- Order Statistics ---");
        PrintFormat("Total Orders:      %d", m_execMetrics.totalOrders);
        PrintFormat("Filled Orders:     %d (%.1f%%)", m_execMetrics.filledOrders, fillRate);
        PrintFormat("Partial Fills:     %d (%.1f%% of filled)", m_execMetrics.partialFills, partialRate);
        PrintFormat("Rejected Orders:   %d (%.1f%%)", m_execMetrics.rejectedOrders, rejectRate);

        // Slippage statistics
        Print("--- Slippage Analysis ---");
        if(m_execMetrics.filledOrders > 0)
        {
            double avgSlippage = m_execMetrics.totalSlippagePoints / m_execMetrics.filledOrders;
            PrintFormat("Average Slippage:  %.1f points", avgSlippage);
            PrintFormat("Maximum Slippage:  %.1f points", m_execMetrics.maxSlippagePoints);
            PrintFormat("Total Slippage:    %.1f points", m_execMetrics.totalSlippagePoints);
        }
        else
        {
            Print("No slippage data available.");
        }

        // Latency statistics
        Print("--- Latency Analysis ---");
        if(m_execMetrics.filledOrders > 0 && m_execMetrics.totalLatencyMs > 0)
        {
            double avgLatency = m_execMetrics.totalLatencyMs / m_execMetrics.filledOrders;
            PrintFormat("Average Latency:   %.0f ms", avgLatency);
            PrintFormat("Maximum Latency:   %.0f ms", m_execMetrics.maxLatencyMs);
            PrintFormat("Total Latency:     %.0f ms", m_execMetrics.totalLatencyMs);
        }
        else
        {
            Print("No latency data available.");
        }

        Print("--- Spread Cost Analysis ---");
        PrintFormat("Total Spread Cost: %.2f %s", m_execMetrics.totalSpreadCost,
                    AccountInfoString(ACCOUNT_CURRENCY));
        if(m_execMetrics.filledOrders > 0)
        {
            double avgSpreadCost = m_execMetrics.totalSpreadCost / m_execMetrics.filledOrders;
            PrintFormat("Average Spread Cost: %.2f %s per trade", avgSpreadCost,
                        AccountInfoString(ACCOUNT_CURRENCY));
        }

        Print("--- Dynamic Slippage Status ---");
        PrintFormat("Enabled:           %s", enableDynamicSlippage ? "Yes" : "No");
        PrintFormat("ATR Percentage:    %.0f%%", dynamicSlippageAtrPercent * 100);
        PrintFormat("Min Slippage:      %d points", dynamicSlippageMinPoints);
        PrintFormat("Max Multiplier:    %dx", dynamicSlippageMaxMultiplier);
        PrintFormat("Current Slippage:  %d points", slippage);

        Print("==============================================");
    }

    // Execution metrics update - the single ingest point for this subsystem
    void UpdateExecutionMetrics(const STradeExecutionReceipt &receipt)
    {
        m_execMetrics.totalOrders++;

        if(receipt.accepted)
        {
            m_execMetrics.filledOrders++;

            if(receipt.partialFill)
            {
                m_execMetrics.partialFills++;
            }

            // Track slippage
            if(receipt.slippagePoints > 0.0)
            {
                m_execMetrics.totalSlippagePoints += receipt.slippagePoints;
                if(receipt.slippagePoints > m_execMetrics.maxSlippagePoints)
                {
                    m_execMetrics.maxSlippagePoints = receipt.slippagePoints;
                }
            }

            // Track latency
            if(receipt.roundTripMs > 0)
            {
                m_execMetrics.totalLatencyMs += (double)receipt.roundTripMs;
                if((double)receipt.roundTripMs > m_execMetrics.maxLatencyMs)
                {
                    m_execMetrics.maxLatencyMs = (double)receipt.roundTripMs;
                }
            }

            // Track spread cost
            double spreadCost = CTradeSpreadCostModel::CalculateSpreadCost(receipt.symbol, receipt.filledVolume);
            if(spreadCost > 0.0)
            {
                m_execMetrics.totalSpreadCost += spreadCost;
            }
        }
        else
        {
            m_execMetrics.rejectedOrders++;
        }

        m_execMetrics.lastUpdateTime = TimeCurrent();
    }
};

#endif // CORE_TRADING_EXECUTION_QUALITY_TRACKER_MQH
//+------------------------------------------------------------------+
