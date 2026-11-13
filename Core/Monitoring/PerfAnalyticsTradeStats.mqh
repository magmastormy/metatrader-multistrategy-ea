// Trade statistics aggregation: counters, P&L, ratio metrics,
// rolling window metrics and streak based momentum scaling.
// Extracted verbatim from PerformanceAnalytics.mqh.
#ifndef CORE_PERF_ANALYTICS_TRADESTATS_MQH
#define CORE_PERF_ANALYTICS_TRADESTATS_MQH

#include "PerfAnalyticsTypes.mqh"

// Trade statistics aggregator
class CPerfAnalyticsTradeStats
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
    double m_recoveryFactor;
    double m_averageWin;
    double m_averageLoss;
    double m_riskFreeRate; // Configurable risk-free rate

    // Tracking arrays - circular buffer
    double m_dailyReturns[];
    datetime m_tradeTimes[];
    double m_recentReturns[20];  // Last 20 trade returns for rolling metrics
    int m_bufferIndex;

    // Rolling metrics
    double m_rollingWinRate;
    double m_rollingSharpe;
    int m_consecutiveLosses;
    int m_consecutiveWins;              // Anti-Martingale: consecutive win streak

    // Momentum scale log throttle
    datetime m_lastMomentumScaleLogTime;
    double m_lastMomentumScaleValue;

public:
// Constructor
    CPerfAnalyticsTradeStats(void) :
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
        m_recoveryFactor(0.0),
        m_averageWin(0.0),
        m_averageLoss(0.0),
        m_riskFreeRate(BENCHMARK_RETURN), // Default to benchmark return
        m_bufferIndex(0),
        m_rollingWinRate(0.0),
        m_rollingSharpe(0.0),
        m_consecutiveLosses(0),
        m_consecutiveWins(0),
        m_lastMomentumScaleLogTime(0),
        m_lastMomentumScaleValue(1.0)
    {
        // Initialize arrays - circular buffer size MAX_TRADES
        ArrayResize(m_dailyReturns, MAX_TRADES);
        ArrayResize(m_tradeTimes, MAX_TRADES);
        ArrayInitialize(m_recentReturns, 0.0);
        ArrayInitialize(m_dailyReturns, 0.0);
        ArrayInitialize(m_tradeTimes, 0);
    }

// Counter helpers
    void IncrementSuccessfulTrades(void) { m_successfulTrades++; }
    void IncrementFailedTrades(void) { m_failedTrades++; }
    void SetRiskFreeRate(const double rate) { m_riskFreeRate = MathMax(0.0, rate); }

// Register a closed trade sample into the circular buffer.
// Returns the buffer slot that was written (index NOT advanced
// yet, so the equity module can write the same slot).
    int RegisterTradeSample(const double profit)
    {
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

        return m_bufferIndex;
    }

// Increment buffer index, wrap around
    void AdvanceBufferIndex(void)
    {
        m_bufferIndex++;
        if(m_bufferIndex >= MAX_TRADES)
            m_bufferIndex = 0;
    }

// Update profit/loss tracking for a closed trade
    void ApplyTradeOutcome(const double profit)
    {
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
    }

// Calculate Performance Metrics
    void CalculateMetrics(const double maxDrawdown, const double peakEquity)
    {
        if(m_totalTrades == 0) return;

        CalculateWinRate();
        CalculateProfitFactor();
        CalculateSharpeRatio();
        CalculateRecoveryFactor(maxDrawdown, peakEquity);

        // Calculate averages
        if(m_successfulTrades > 0)
            m_averageWin = m_totalProfit / (double)m_successfulTrades;

        int losingTradesLocal = m_totalTrades - m_successfulTrades;
        if(losingTradesLocal > 0)
            m_averageLoss = m_totalLoss / (double)losingTradesLocal;
    }

    void CalculateWinRate(void)
    {
        if(m_totalTrades > 0)
            m_winRate = ((double)m_successfulTrades / (double)m_totalTrades) * 100.0;
        else
            m_winRate = 0.0;
    }

    void CalculateProfitFactor(void)
    {
        if(m_totalLoss > 0)
            m_profitFactor = m_totalProfit / m_totalLoss;
        else if(m_totalProfit > 0)
            m_profitFactor = m_totalProfit; // No losses yet
        else
            m_profitFactor = 0.0;
    }

    void CalculateSharpeRatio(void)
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

        avgReturn /= (double)count;

        // Create a temporary array for standard deviation calculation
        double tempReturns[];
        ArrayResize(tempReturns, validTrades);

        for(int i = 0; i < validTrades; i++)
        {
            int index = (m_bufferIndex - 1 - i + MAX_TRADES) % MAX_TRADES;
            tempReturns[i] = m_dailyReturns[index];
        }

        double stdDev = CPerfAnalyticsMath::CalculateStandardDeviation(tempReturns);

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

    void CalculateRecoveryFactor(const double maxDrawdown, const double peakEquity)
    {
        double netProfit = m_totalProfit - m_totalLoss;
        if(maxDrawdown > 0)
        {
            // Convert drawdown from percent to dollars for unit consistency
            double maxDrawdownDollars = (peakEquity > 0) ? (maxDrawdown / 100.0) * peakEquity : maxDrawdown;
            m_recoveryFactor = (maxDrawdownDollars > 0) ? netProfit / maxDrawdownDollars : 0.0;
        }
        else if(netProfit > 0)
            m_recoveryFactor = netProfit; // No drawdown yet
        else
            m_recoveryFactor = 0.0;
    }

    void CalculateRollingMetrics(void)
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
            m_rollingWinRate = ((double)wins / (double)validReturns) * 100.0;

        // Calculate rolling Sharpe ratio
        if(validReturns >= 10)
        {
            double avgReturn = 0.0;
            for(int i = 0; i < validReturns; i++)
                avgReturn += m_recentReturns[i];
            avgReturn /= (double)validReturns;

            double variance = 0.0;
            for(int i = 0; i < validReturns; i++)
            {
                double diff = m_recentReturns[i] - avgReturn;
                variance += diff * diff;
            }
            variance /= (double)(validReturns - 1);

            double stdDev = MathSqrt(variance);
            if(stdDev > 0)
                m_rollingSharpe = avgReturn / stdDev;
        }
    }

// Anti-Martingale Momentum Scale
// Win streak: scale up by 10% per win, capped at 1.5x
// Loss streak: scale down by 15% per loss, floored at 0.5x
    double CalculateMomentumScale(void)
    {
        double scale = 1.0;

        // Win streak and loss streak are mutually exclusive (each resets the other)
        if(m_consecutiveWins > 0)
        {
            // Win streak: increase size by 10% per win, capped at 1.5x
            scale = MathMin(1.5, 1.0 + (double)m_consecutiveWins * 0.10);
        }
        else if(m_consecutiveLosses > 0)
        {
            // Loss streak: decrease size by 15% per loss, floored at 0.5x
            scale = MathMax(0.5, 1.0 - (double)m_consecutiveLosses * 0.15);
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

// Accessors
    int GetTotalTrades(void) const { return m_totalTrades; }
    int GetSuccessfulTrades(void) const { return m_successfulTrades; }
    int GetFailedTrades(void) const { return m_failedTrades; }
    int GetLosingTrades(void) const { return m_totalTrades - m_successfulTrades; }
    double GetTotalProfit(void) const { return m_totalProfit; }
    double GetTotalLoss(void) const { return m_totalLoss; }
    double GetNetProfit(void) const { return m_totalProfit - m_totalLoss; }
    double GetLargestWin(void) const { return m_largestWin; }
    double GetLargestLoss(void) const { return m_largestLoss; }
    double GetWinRate(void) const { return m_winRate; }
    double GetProfitFactor(void) const { return m_profitFactor; }
    double GetSharpeRatio(void) const { return m_sharpeRatio; }
    double GetSharpeRatioWithRiskFree(void) const { return m_sharpeRatioWithRiskFree; }
    double GetRecoveryFactor(void) const { return m_recoveryFactor; }
    double GetAverageWin(void) const { return m_averageWin; }
    double GetAverageLoss(void) const { return m_averageLoss; }
    double GetRiskFreeRate(void) const { return m_riskFreeRate; }
    double GetRollingWinRate(void) const { return m_rollingWinRate; }
    double GetRollingSharpe(void) const { return m_rollingSharpe; }
    int GetConsecutiveLosses(void) const { return m_consecutiveLosses; }
    int GetConsecutiveWins(void) const { return m_consecutiveWins; }
    int GetBufferIndex(void) const { return m_bufferIndex; }
};

#endif // CORE_PERF_ANALYTICS_TRADESTATS_MQH

