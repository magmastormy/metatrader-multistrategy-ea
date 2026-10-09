// Aggregate trade statistics extracted from CTradeManager
// Phase D, batch T2b. This module OWNS the counters that used to
// live in CTradeManager::m_stats:
// - RecordTrade           (the single ingest point, carved out
// of CTradeManager::UpdatePerformanceMetrics)
// - GetTradeStatistics    (total / successful / failed / rate)
// - ResetStatistics       (zeroes the block)
// - narrow field getters used by CTradeManager to refresh its
// legacy mirror members.
// STATE OWNERSHIP: CTradeManager holds this class BY VALUE and
// keeps thin forwarders with the original public signatures.
// DELIBERATELY NOT MOVED: CTradeManager::m_totalTrades /
// m_successfulTrades / m_failedTrades / m_lastTradeTime. Those are
// legacy backward-compatibility mirrors that remain owned by the
// manager; it re-reads them from this module via the getters below
// immediately after every RecordTrade call, exactly as before.
// NO BACK-POINTER: everything RecordTrade needs arrives as a
// parameter, so this module has no dependency on CTradeManager.
#property copyright "Copyright 2024, Windsurf AI"
#property link      "https://www.windsurf.ai"
#property strict

#ifndef CORE_TRADING_TRADE_STATS_TRACKER_MQH
#define CORE_TRADING_TRADE_STATS_TRACKER_MQH

// Trade tracking and statistics
// Promoted verbatim from the nested CTradeManager::TradeStats.
struct TradeStats
{
    int totalTrades;                     // Total trades executed
    int successfulTrades;
    int winningTrades;                   // Winning trades (profitable)
    uint failedTrades;                   // Number of failed trades
    double totalProfit;
    double totalLoss;
    datetime lastTradeTime;              // Last trade execution time
};

class CTradeStatsTracker
{
private:
    TradeStats m_stats;

public:
    CTradeStatsTracker()
    {
        ZeroMemory(m_stats);
    }

    //--- Narrow read accessors (feed CTradeManager's legacy mirror members)
    int      TotalTrades(void)      const { return m_stats.totalTrades; }
    int      SuccessfulTrades(void) const { return m_stats.successfulTrades; }
    int      WinningTrades(void)    const { return m_stats.winningTrades; }
    uint     FailedTrades(void)     const { return m_stats.failedTrades; }
    double   TotalProfit(void)      const { return m_stats.totalProfit; }
    double   TotalLoss(void)        const { return m_stats.totalLoss; }
    datetime LastTradeTime(void)    const { return m_stats.lastTradeTime; }

    //--- Ingest: accumulation block lifted verbatim out of
    //--- CTradeManager::UpdatePerformanceMetrics. netProfit is already
    //--- net of commission and swap when it reaches here.
    void RecordTrade(const bool isWin, const double netProfit)
    {
        if(isWin)
        {
            m_stats.successfulTrades++;
            if(netProfit > 0) {
                m_stats.winningTrades++;
                m_stats.totalProfit += netProfit;
            }
        }
        else
        {
            m_stats.failedTrades++;
            if(netProfit < 0) {
                m_stats.totalLoss += MathAbs(netProfit);
            }
        }

        m_stats.totalTrades++;
        m_stats.lastTradeTime = TimeCurrent();
    }

    void GetTradeStatistics(int &total, int &successful, int &failed, double &successRate)
    {
        total = m_stats.totalTrades;
        successful = m_stats.successfulTrades;
        failed = (int)m_stats.failedTrades;

        if(total > 0)
            successRate = (double)successful / total * 100.0;
        else
            successRate = 0.0;
    }

    void ResetStatistics(void)
    {
        ZeroMemory(m_stats);
    }
};

#endif // CORE_TRADING_TRADE_STATS_TRACKER_MQH
