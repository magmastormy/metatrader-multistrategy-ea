// Tracks performance, decay, disable/enable logic
#ifndef STRATEGY_HEALTH_MONITOR_MQH
#define STRATEGY_HEALTH_MONITOR_MQH

#include "../Utils/Enums.mqh"
#include "../../Interfaces/IStrategy.mqh"

struct SStrategyHealthEntry
{
    int totalTrades;
    int winningTrades;
    double winRate;

    // Rolling sample: recentTradeCount caps at m_rollingWindowSize and recentWinRate is the
    // running mean over it. The outcome series itself is not kept - only this mean and the counts.
    int recentTradeCount;
    double recentWinRate;

    int consecutiveLosses;

    bool temporarilyDisabled;

    SStrategyHealthEntry()
    {
        totalTrades = 0;
        winningTrades = 0;
        winRate = 0.0;
        recentTradeCount = 0;
        recentWinRate = 0.0;
        consecutiveLosses = 0;
        temporarilyDisabled = false;
    }
};

class CStrategyHealthMonitor
{
private:
    double m_minWinRateThreshold;
    int m_maxConsecutiveLosses_Limit;
    int m_rollingWindowSize;

    // Strategy health entries (indexed by strategy array index)
    SStrategyHealthEntry m_healthEntries[];
    int m_healthEntryCount;
    
    void EnsureCapacity(int index)
    {
        int currentSize = ArraySize(m_healthEntries);
        if(index >= currentSize)
        {
            int newSize = MathMax(currentSize * 2, index + 1);
            ArrayResize(m_healthEntries, newSize);
        }
    }
    void CalculateStrategyMetrics(SStrategyHealthEntry &entry)
    {
        if(entry.totalTrades > 0)
        {
            entry.winRate = (double)entry.winningTrades / (double)entry.totalTrades;
        }
    }
    bool ShouldDisableStrategy(const SStrategyHealthEntry &entry) const
    {
        if(entry.consecutiveLosses >= m_maxConsecutiveLosses_Limit) return true;
        if(entry.recentTradeCount >= 5 && entry.recentWinRate < m_minWinRateThreshold) return true;
        return false;
    }
    // CheckAllStrategiesDisabling is this flag's only writer and it never arms a cooldown, so a
    // strategy parked here is released on the next governance pass - the one-hour cooldown written
    // by CStrategyPerformanceHealth sits on the roster entry and is not consulted on this path.
    bool ShouldReEnableStrategy(const SStrategyHealthEntry &entry) const
    {
        return entry.temporarilyDisabled;
    }
    void ResetRecoverySample(SStrategyHealthEntry &entry)
    {
        entry.recentTradeCount = 0;
        entry.recentWinRate = 0.0;
        entry.consecutiveLosses = 0;
    }
    void UpdateRecentPerformance(SStrategyHealthEntry &entry, const double result)
    {
        entry.totalTrades++;
        if(result > 0)
        {
            entry.winningTrades++;
            entry.consecutiveLosses = 0;
        }
        else if(result < 0)
        {
            entry.consecutiveLosses++;
        }
        entry.recentTradeCount = MathMin(entry.recentTradeCount + 1, m_rollingWindowSize);
        if(result > 0) entry.recentWinRate = (entry.recentWinRate * (entry.recentTradeCount - 1) + 1.0) / entry.recentTradeCount;
        else entry.recentWinRate = (entry.recentWinRate * (entry.recentTradeCount - 1)) / entry.recentTradeCount;
    }

public:
    CStrategyHealthMonitor()
        : m_minWinRateThreshold(0.5),
          m_maxConsecutiveLosses_Limit(5),
          m_rollingWindowSize(20),
          m_healthEntryCount(0)
    {
    }
    ~CStrategyHealthMonitor() {}
    
    // These two limits are the disable rule the per-strategy park runs on; the quorum profile
    // owns them and pushes them here at construction (StrategyMgrInfrastructure).
    void SetOrchestratorMode(double minWinRate, int maxLosses)
    {
        m_minWinRateThreshold = MathMax(0.0, MathMin(1.0, minWinRate));
        m_maxConsecutiveLosses_Limit = MathMax(1, maxLosses);
    }
    void SetRollingWindowSize(const int size) { m_rollingWindowSize = MathMax(5, size); }
    
    // Called once per roster row, so entry indexes match strategy indexes for the manager's
    // whole life. Default-constructed: every field starts at its reset value.
    int RegisterStrategy()
    {
        int idx = m_healthEntryCount;
        EnsureCapacity(idx);
        SStrategyHealthEntry entry;
        m_healthEntries[idx] = entry;
        m_healthEntryCount++;
        return idx;
    }
    
    void UpdatePerformance(int index, double netProfit)
    {
        if(index < 0 || index >= m_healthEntryCount) return;
        UpdateRecentPerformance(m_healthEntries[index], netProfit);
        CalculateStrategyMetrics(m_healthEntries[index]);
    }
    
    void RecordTradeResult(int index, double netProfit)
    {
        UpdatePerformance(index, netProfit);
    }
    
    // Disable/Enable logic
    bool CheckStrategyDisabling(int index)
    {
        if(index < 0 || index >= m_healthEntryCount) return false;
        return ShouldDisableStrategy(m_healthEntries[index]);
    }
    bool CheckStrategyReEnabling(int index)
    {
        if(index < 0 || index >= m_healthEntryCount) return false;
        return ShouldReEnableStrategy(m_healthEntries[index]);
    }

    double GetWinRate(int index) const
    {
        if(index < 0 || index >= m_healthEntryCount) return 0.0;
        return m_healthEntries[index].winRate;
    }
    double GetRecentWinRate(int index) const
    {
        if(index < 0 || index >= m_healthEntryCount) return 0.0;
        return m_healthEntries[index].recentWinRate;
    }

    void CheckAllStrategiesDisabling()
    {
        for(int i = 0; i < m_healthEntryCount; i++)
        {
            if(ShouldDisableStrategy(m_healthEntries[i]))
            {
                m_healthEntries[i].temporarilyDisabled = true;
            }
        }
    }
    void CheckAllStrategiesReEnabling()
    {
        for(int i = 0; i < m_healthEntryCount; i++)
        {
            if(ShouldReEnableStrategy(m_healthEntries[i]))
            {
                m_healthEntries[i].temporarilyDisabled = false;
                // Fresh sample after cooldown: stale losing trades in the rolling window
                // would insta-redisable the strategy on its first new loss.
                ResetRecoverySample(m_healthEntries[i]);
            }
        }
    }
};

#endif // STRATEGY_HEALTH_MONITOR_MQH