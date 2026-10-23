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
    double avgProfit;
    double avgLoss;
    double profitFactor;
    double sharpeRatio;
    
    // Recent performance tracking (20-trade rolling window)
    double recentTrades[20];
    int recentTradeIndex;
    int recentTradeCount;
    double recentWinRate;
    
    int consecutiveLosses;
    int maxConsecutiveLosses;
    int consecutiveWins;
    
    bool temporarilyDisabled;
    datetime disabledUntil;
    datetime lastUpdate;
    
    double regimePerformance[5];
    int regimeTrades[5];
    
    double healthScore;
    double netProfit;
    
    int consecutiveFilterCount;
    
    SStrategyHealthEntry()
    {
        totalTrades = 0;
        winningTrades = 0;
        winRate = 0.0;
        avgProfit = 0.0;
        avgLoss = 0.0;
        profitFactor = 0.0;
        sharpeRatio = 0.0;
        recentTradeIndex = 0;
        recentTradeCount = 0;
        recentWinRate = 0.0;
        consecutiveLosses = 0;
        maxConsecutiveLosses = 0;
        consecutiveWins = 0;
        temporarilyDisabled = false;
        disabledUntil = 0;
        lastUpdate = 0;
        for(int i = 0; i < 5; i++)
        {
            regimePerformance[i] = 0.0;
            regimeTrades[i] = 0;
        }
        healthScore = 1.0;
        netProfit = 0.0;
        consecutiveFilterCount = 0;
    }
};

class CStrategyHealthMonitor
{
private:
    double m_minWinRateThreshold;
    int m_maxConsecutiveLosses_Limit;
    double m_performanceDecayFactor;
    int m_rollingWindowSize;
    double m_maxDrawdownLimit;
    double m_strategyActivityDecayRate;
    int m_strategyInactiveCounterThreshold;
    
    
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
    double CalculateRecentWinRate(const SStrategyHealthEntry &entry) const
    {
        if(entry.recentTradeCount <= 0) return 0.0;
        return entry.recentWinRate;
    }
    double CalculateSharpeRatio(const SStrategyHealthEntry &entry) const
    {
        return entry.sharpeRatio;
    }
    void CalculateStrategyMetrics(SStrategyHealthEntry &entry)
    {
        if(entry.totalTrades > 0)
        {
            entry.winRate = (double)entry.winningTrades / (double)entry.totalTrades;
        }
        entry.healthScore = entry.winRate;
    }
    bool ShouldDisableStrategy(const SStrategyHealthEntry &entry) const
    {
        if(entry.consecutiveLosses >= m_maxConsecutiveLosses_Limit) return true;
        if(entry.recentTradeCount >= 5 && entry.recentWinRate < m_minWinRateThreshold) return true;
        return false;
    }
    bool ShouldReEnableStrategy(const SStrategyHealthEntry &entry) const
    {
        if(!entry.temporarilyDisabled) return false;
        // A disabled strategy cannot trade, so demanding post-disable wins was unreachable:
        // serving the cooldown is sufficient for a fresh sample. The same disable limits re-arm
        // immediately if performance is still poor (CheckAllStrategiesReEnabling resets the
        // rolling sample on re-enable).
        if(entry.disabledUntil > 0 && TimeCurrent() < entry.disabledUntil) return false;
        return true;
    }
    void ResetRecoverySample(SStrategyHealthEntry &entry)
    {
        entry.recentTradeIndex = 0;
        entry.recentTradeCount = 0;
        entry.recentWinRate = 0.0;
        entry.consecutiveLosses = 0;
        entry.consecutiveWins = 0;
    }
    void UpdateRecentPerformance(SStrategyHealthEntry &entry, const double result)
    {
        entry.totalTrades++;
        if(result > 0)
        {
            entry.winningTrades++;
            entry.consecutiveWins++;
            entry.consecutiveLosses = 0;
        }
        else if(result < 0)
        {
            entry.consecutiveLosses++;
            entry.consecutiveWins = 0;
            if(entry.consecutiveLosses > entry.maxConsecutiveLosses)
                entry.maxConsecutiveLosses = entry.consecutiveLosses;
        }
        entry.netProfit += result;
        if(result > 0)
        {
            entry.avgProfit = (entry.avgProfit * (entry.totalTrades - 1) + result) / entry.totalTrades;
        }
        else if(result < 0)
        {
            double lossVal = MathAbs(result);
            entry.avgLoss = (entry.avgLoss * (entry.totalTrades - 1) + lossVal) / entry.totalTrades;
        }
        if(entry.avgLoss > 0)
            entry.profitFactor = entry.avgProfit / entry.avgLoss;
        entry.lastUpdate = TimeCurrent();
        entry.recentTradeCount = MathMin(entry.recentTradeCount + 1, m_rollingWindowSize);
        if(result > 0) entry.recentWinRate = (entry.recentWinRate * (entry.recentTradeCount - 1) + 1.0) / entry.recentTradeCount;
        else entry.recentWinRate = (entry.recentWinRate * (entry.recentTradeCount - 1)) / entry.recentTradeCount;
    }
    void UpdateRegimePerformance(SStrategyHealthEntry &entry, int regime, const double result)
    {
        if(regime >= 0 && regime < 5)
        {
            entry.regimePerformance[regime] += result;
            entry.regimeTrades[regime]++;
        }
    }

public:
    CStrategyHealthMonitor()
        : m_minWinRateThreshold(0.5),
          m_maxConsecutiveLosses_Limit(5),
          m_performanceDecayFactor(0.95),
          m_rollingWindowSize(20),
          m_maxDrawdownLimit(0.2),
          m_strategyActivityDecayRate(0.9),
          m_strategyInactiveCounterThreshold(10),
          m_healthEntryCount(0)
    {
    }
    ~CStrategyHealthMonitor() {}
    
    
    void SetOrchestratorMode(double minWinRate, int maxLosses)
    {
        m_minWinRateThreshold = MathMax(0.0, MathMin(1.0, minWinRate));
        m_maxConsecutiveLosses_Limit = MathMax(1, maxLosses);
    }
    void SetPerformanceDecayFactor(const double factor) { m_performanceDecayFactor = MathMax(0.0, MathMin(1.0, factor)); }
    void SetRollingWindowSize(const int size) { m_rollingWindowSize = MathMax(5, size); }
    void SetMaxDrawdownLimit(const double limit) { m_maxDrawdownLimit = MathMax(0.0, MathMin(1.0, limit)); }
    void SetStrategyActivityDecayRate(const double rate) { m_strategyActivityDecayRate = MathMax(0.0, MathMin(1.0, rate)); }
    void SetStrategyInactiveCounterThreshold(const int threshold) { m_strategyInactiveCounterThreshold = MathMax(1, threshold); }
    
    int RegisterStrategy()
    {
        int idx = m_healthEntryCount;
        EnsureCapacity(idx);
        SStrategyHealthEntry entry;
        entry.healthScore = 1.0;
        m_healthEntries[idx] = entry;
        m_healthEntryCount++;
        return idx;
    }
    void UnregisterStrategy(int index)
    {
        if(index >= 0 && index < m_healthEntryCount)
        {
            m_healthEntries[index].temporarilyDisabled = true;
        }
    }
    void ClearAll()
    {
        m_healthEntryCount = 0;
        ArrayResize(m_healthEntries, 0);
    }
    
    void UpdatePerformance(int index, double netProfit)
    {
        if(index < 0 || index >= m_healthEntryCount) return;
        UpdateRecentPerformance(m_healthEntries[index], netProfit);
        CalculateStrategyMetrics(m_healthEntries[index]);
    }
    void RecordSignalGenerated(int index)
    {
        if(index < 0 || index >= m_healthEntryCount) return;
        m_healthEntries[index].consecutiveFilterCount = 0;
    }
    void RecordSignalFiltered(int index)
    {
        if(index < 0 || index >= m_healthEntryCount) return;
        m_healthEntries[index].consecutiveFilterCount++;
    }
    
    void RecordTradeResult(int index, double netProfit)
    {
        UpdatePerformance(index, netProfit);
        if(index < 0 || index >= m_healthEntryCount) return;
        UpdateRegimePerformance(m_healthEntries[index], 0, netProfit);
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
    bool IsStrategyTemporarilyDisabled(int index) const
    {
        if(index < 0 || index >= m_healthEntryCount) return false;
        return m_healthEntries[index].temporarilyDisabled;
    }
    datetime GetStrategyDisabledUntil(int index) const
    {
        if(index < 0 || index >= m_healthEntryCount) return 0;
        return m_healthEntries[index].disabledUntil;
    }
    void SetStrategyTemporarilyDisabled(int index, bool disabled, datetime until = 0)
    {
        if(index < 0 || index >= m_healthEntryCount) return;
        m_healthEntries[index].temporarilyDisabled = disabled;
        m_healthEntries[index].disabledUntil = until;
    }
    
    double GetStrategyHealthScore(int index) const
    {
        if(index < 0 || index >= m_healthEntryCount) return 0.0;
        return m_healthEntries[index].healthScore;
    }
    
    double GetWinRate(int index) const
    {
        if(index < 0 || index >= m_healthEntryCount) return 0.0;
        return m_healthEntries[index].winRate;
    }
    double GetProfitFactor(int index) const
    {
        if(index < 0 || index >= m_healthEntryCount) return 0.0;
        return m_healthEntries[index].profitFactor;
    }
    double GetSharpeRatio(int index) const
    {
        if(index < 0 || index >= m_healthEntryCount) return 0.0;
        return m_healthEntries[index].sharpeRatio;
    }
    int GetConsecutiveLosses(int index) const
    {
        if(index < 0 || index >= m_healthEntryCount) return 0;
        return m_healthEntries[index].consecutiveLosses;
    }
    int GetMaxConsecutiveLosses(int index) const
    {
        if(index < 0 || index >= m_healthEntryCount) return 0;
        return m_healthEntries[index].maxConsecutiveLosses;
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
                m_healthEntries[i].disabledUntil = 0;
                // Fresh sample after cooldown: stale losing trades in the rolling window
                // would insta-redisable the strategy on its first new loss.
                ResetRecoverySample(m_healthEntries[i]);
            }
        }
    }
    
    int GetActiveStrategyCount() const
    {
        int count = 0;
        for(int i = 0; i < m_healthEntryCount; i++)
        {
            if(!m_healthEntries[i].temporarilyDisabled) count++;
        }
        return count;
    }
    int GetTotalStrategyCount() const { return m_healthEntryCount; }
};

#endif // STRATEGY_HEALTH_MONITOR_MQH