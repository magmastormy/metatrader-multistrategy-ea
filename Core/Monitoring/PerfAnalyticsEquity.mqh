// Equity curve tracking and drawdown computation.
// Extracted verbatim from PerformanceAnalytics.mqh.
#ifndef CORE_PERF_ANALYTICS_EQUITY_MQH
#define CORE_PERF_ANALYTICS_EQUITY_MQH

#include "PerfAnalyticsTypes.mqh"

// Equity / drawdown tracker
class CPerfAnalyticsEquity
{
private:
    // Tracking array - circular buffer
    double m_equityCurve[];

    // Risk metrics
    double m_currentDrawdown;
    double m_maxDrawdown;
    double m_peakEquity;
    double m_currentEquity;
    double m_equityHistoryPeak; // Track peak in circular buffer for accurate drawdown

public:
// Constructor
    CPerfAnalyticsEquity(void) :
        m_currentDrawdown(0.0),
        m_maxDrawdown(0.0),
        m_peakEquity(0.0),
        m_currentEquity(0.0),
        m_equityHistoryPeak(0.0)
    {
        // Initialize array - circular buffer size MAX_TRADES
        ArrayResize(m_equityCurve, MAX_TRADES);
        ArrayInitialize(m_equityCurve, 0.0);
    }

// Seed the tracker with the current account equity
    void InitializeEquity(void)
    {
        m_currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
        m_peakEquity = m_currentEquity;
    }

// Store equity for a freshly registered trade slot
    void RecordTradeEquity(const int slot)
    {
        // Update equity curve in circular buffer
        m_currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
        m_equityCurve[slot] = m_currentEquity;

        // Update peak equity
        if(m_currentEquity > m_peakEquity)
            m_peakEquity = m_currentEquity;
    }

    void UpdateEquityCurve(const int bufferIndex)
    {
        m_currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);

        // Batch 120: Only update if buffer index hasn't been advanced yet
        // (RecordClosedTrade writes first, then advances index — avoid double-write)
        // This prevents polluting the next slot with a duplicate value
        if(bufferIndex < MAX_TRADES)
            m_equityCurve[bufferIndex] = m_currentEquity;

        // Update peak equity
        if(m_currentEquity > m_peakEquity)
            m_peakEquity = m_currentEquity;
    }

    void UpdateDrawdown(void)
    {
        if(m_peakEquity <= 0) return;

        // Calculate current drawdown
        m_currentDrawdown = ((m_peakEquity - m_currentEquity) / m_peakEquity) * 100.0;

        // Update maximum drawdown
        if(m_currentDrawdown > m_maxDrawdown)
            m_maxDrawdown = m_currentDrawdown;
    }

// Accessors
    double GetCurrentDrawdown(void) const { return m_currentDrawdown; }
    double GetMaxDrawdown(void) const { return m_maxDrawdown; }
    double GetPeakEquity(void) const { return m_peakEquity; }
    double GetCurrentEquity(void) const { return m_currentEquity; }
    double GetEquityHistoryPeak(void) const { return m_equityHistoryPeak; }
};

#endif // CORE_PERF_ANALYTICS_EQUITY_MQH
