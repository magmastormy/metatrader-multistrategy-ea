// Per-strategy performance accounting, rolling-window statistics and health/quality
// scoring: trade outcome accounting, the 20-trade rolling ring buffer, rolling win
// rate / Sharpe, derived metrics, the disable / re-enable governance predicates and
// the AI accuracy -> health blend.
// This module MUTATES the manager: non-const back-pointer, every read and write through
// the manager's narrow per-field accessors.
// Deliberately NOT moved:
// - The health / participation reads the consensus core calls on its hottest
//   per-strategy loop (EvaluateConsensusInternal, EvaluateConsensusProbeOnlyInternal,
//   TryFallbackSoloSignalInternal) - no extra indirection added there.
// - CStrategyHealthMonitor itself: this module only mirrors manager state and delegates.
// NOTE: implementation detail of EnterpriseStrategyManager.mqh, included from there
// (after the shared free helpers, before the manager class). Not for standalone include.
#ifndef STRATEGY_PERFORMANCE_HEALTH_MQH
#define STRATEGY_PERFORMANCE_HEALTH_MQH

#include "../Utils/Enums.mqh"                          // ENUM_STRATEGY_TYPE
#include "../../Interfaces/IStrategy.mqh"              // IStrategy::GetType
#include "StrategyHealthMonitor.mqh"                   // CStrategyHealthMonitor
#include "../../Core/AI/AIPerformanceFeedback.mqh"     // SAIModelMetrics

class CEnterpriseStrategyManager;   // forward: held as a mutable pointer

// Performance / health facade over CEnterpriseStrategyManager
class CStrategyPerformanceHealth
{
private:
    CEnterpriseStrategyManager* m_src;

public:
    CStrategyPerformanceHealth() : m_src(NULL) {}

    void SetSource(CEnterpriseStrategyManager* src) { m_src = src; }

    void   UpdatePerformance(const string strategyName, double netProfit);
    void   UpdateRecentPerformance(const int index, const double result);
    double CalculateRecentWinRate(const int index);
    double CalculateSharpeRatio(const int index);
    void   CalculateStrategyMetrics(const int index);
    bool   ShouldDisableStrategy(const int index);
    bool   ShouldReEnableStrategy(const int index);
    void   UpdateRegimePerformance(const int index, int regime, const double result);
    void   UpdateAIPerformanceMetrics(const string strategyName, const SAIModelMetrics &metrics);
};

// Record a closed-trade outcome against a named strategy
void CStrategyPerformanceHealth::UpdatePerformance(const string strategyName, double netProfit)
{
    if(m_src == NULL)
        return;

    int idx = m_src.GetStrategyIndexByName(strategyName);
    if(idx < 0 || idx >= m_src.GetStrategyCount())
        return;

    bool success = (netProfit > 0);

    m_src.SetStrategyTotalTrades(idx, m_src.GetStrategyTotalTrades(idx) + 1);
    if(success)
    {
        m_src.SetStrategySuccessCount(idx, m_src.GetStrategySuccessCount(idx) + 1);
        m_src.SetStrategyWinningTrades(idx, m_src.GetStrategyWinningTrades(idx) + 1);
        m_src.SetStrategyConsecutiveWins(idx, m_src.GetStrategyConsecutiveWins(idx) + 1);
        m_src.SetStrategyConsecutiveLosses(idx, 0);

        int wins = m_src.GetStrategyWinningTrades(idx);
        if(wins > 0)
        {
            double prevTotalProfit = m_src.GetStrategyAvgProfit(idx) * (wins - 1);
            m_src.SetStrategyAvgProfit(idx, (prevTotalProfit + netProfit) / wins);
        }
    }
    else
    {
        m_src.SetStrategyFailCount(idx, m_src.GetStrategyFailCount(idx) + 1);
        m_src.SetStrategyConsecutiveLosses(idx, m_src.GetStrategyConsecutiveLosses(idx) + 1);
        m_src.SetStrategyConsecutiveWins(idx, 0);

        // Losses = totalTrades - wins; totalTrades was already incremented above
        int losses = m_src.GetStrategyTotalTrades(idx) - m_src.GetStrategyWinningTrades(idx);
        if(losses > 0)
        {
            double absLoss = MathAbs(netProfit);
            double prevTotalLoss = m_src.GetStrategyAvgLoss(idx) * (losses - 1);
            m_src.SetStrategyAvgLoss(idx, (prevTotalLoss + absLoss) / losses);
        }

        if(m_src.GetStrategyConsecutiveLosses(idx) > m_src.GetStrategyMaxConsecutiveLosses(idx))
        {
            m_src.SetStrategyMaxConsecutiveLosses(idx, m_src.GetStrategyConsecutiveLosses(idx));
        }
    }

    UpdateRecentPerformance(idx, netProfit);

    // Regime attribution belongs to the health monitor; nothing per-trade happens here

    CalculateStrategyMetrics(idx);

    // Health score: 0.55 prior blended by sample trust = outcomes/20, clamped to 0.35..1.0
    int totalOutcomes = m_src.GetStrategySuccessCount(idx) + m_src.GetStrategyFailCount(idx);
    if(totalOutcomes > 0)
    {
        double realizedWinRate = (double)m_src.GetStrategySuccessCount(idx) / (double)totalOutcomes;
        double sampleTrust = MathMin(1.0, (double)totalOutcomes / 20.0);
        double prior = 0.55;
        double blendedWinRate = (prior * (1.0 - sampleTrust)) + (realizedWinRate * sampleTrust);
        m_src.SetStrategyHealthScore(idx, MathMax(0.35, MathMin(1.0, blendedWinRate)));
    }

    m_src.SetStrategyLastUpdate(idx, TimeCurrent());

    if(ShouldDisableStrategy(idx))
    {
        m_src.SetStrategyTemporarilyDisabled(idx, true);
        m_src.SetStrategyDisabledUntil(idx, TimeCurrent() + 3600); // Disable for 1 hour
        PrintFormat("[Enterprise-Adaptation] Strategy %s DISABLED due to poor performance (WinRate: %.2f, Losses: %d)",
                    strategyName, m_src.GetStrategyWinRate(idx), m_src.GetStrategyConsecutiveLosses(idx));
    }
}

void CStrategyPerformanceHealth::UpdateRecentPerformance(const int index, const double result)
{
    if(m_src == NULL)
        return;

    CStrategyHealthMonitor* healthMonitor = m_src.GetHealthMonitor();
    if(healthMonitor != NULL)
    {
        healthMonitor.RecordTradeResult(index, result);
        return;
    }

    if(index < 0 || index >= m_src.GetStrategyCount())
        return;

    const int rollingWindowSize = m_src.GetRollingWindowSize();

    m_src.SetStrategyRecentTrade(index, m_src.GetStrategyRecentTradeIndex(index), result);
    m_src.SetStrategyRecentTradeIndex(index, (m_src.GetStrategyRecentTradeIndex(index) + 1) % rollingWindowSize);

    if(m_src.GetStrategyRecentTradeCount(index) < rollingWindowSize)
        m_src.SetStrategyRecentTradeCount(index, m_src.GetStrategyRecentTradeCount(index) + 1);
}

double CStrategyPerformanceHealth::CalculateRecentWinRate(const int index)
{
    if(m_src == NULL)
        return 0.0;

    CStrategyHealthMonitor* healthMonitor = m_src.GetHealthMonitor();
    if(healthMonitor != NULL)
    {
        return healthMonitor.GetRecentWinRate(index);
    }

    if(index < 0 || index >= m_src.GetStrategyCount()) return 0.0;

    const int recentTradeCount = m_src.GetStrategyRecentTradeCount(index);
    if(recentTradeCount == 0) return 0.0;

    int wins = 0;
    for(int i = 0; i < recentTradeCount; i++)
    {
        if(m_src.GetStrategyRecentTrade(index, i) > 0.0) wins++;
    }

    return (double)wins / recentTradeCount;
}

// Rolling-window Sharpe ratio; 0.0 (fail-closed) without a manager/index or below 5 trades
double CStrategyPerformanceHealth::CalculateSharpeRatio(const int index)
{
    if(m_src == NULL)
        return 0.0;

    CStrategyHealthMonitor* healthMonitor = m_src.GetHealthMonitor();
    if(healthMonitor != NULL)
    {
        return healthMonitor.GetSharpeRatio(index);
    }

    if(index < 0 || index >= m_src.GetStrategyCount()) return 0.0;

    const int recentTradeCount = m_src.GetStrategyRecentTradeCount(index);
    if(recentTradeCount < 5) return 0.0;

    double sum = 0;
    for(int i = 0; i < recentTradeCount; i++)
        sum += m_src.GetStrategyRecentTrade(index, i);

    double mean = sum / recentTradeCount;

    double sq_sum = 0;
    for(int i = 0; i < recentTradeCount; i++)
        sq_sum += MathPow(m_src.GetStrategyRecentTrade(index, i) - mean, 2);

    double stdev = MathSqrt(sq_sum / recentTradeCount);
    if(stdev == 0) return 0;

    return mean / stdev;
}

void CStrategyPerformanceHealth::CalculateStrategyMetrics(const int index)
{
    if(m_src == NULL)
        return;

    if(m_src.GetHealthMonitor() != NULL)
    {
        // The health monitor will calculate metrics internally
        return;
    }

    if(index < 0 || index >= m_src.GetStrategyCount()) return;

    if(m_src.GetStrategyTotalTrades(index) > 0)
        m_src.SetStrategyWinRate(index, ((double)m_src.GetStrategyWinningTrades(index) / m_src.GetStrategyTotalTrades(index)));

    if(m_src.GetStrategyAvgLoss(index) > 0.0)
        m_src.SetStrategyProfitFactor(index, m_src.GetStrategyAvgProfit(index) / m_src.GetStrategyAvgLoss(index));
    else if(m_src.GetStrategyAvgProfit(index) > 0.0)
        m_src.SetStrategyProfitFactor(index, 2.0);
    else
        m_src.SetStrategyProfitFactor(index, 0.0);

    m_src.SetStrategySharpeRatio(index, CalculateSharpeRatio(index));
    m_src.SetStrategyRecentWinRate(index, CalculateRecentWinRate(index));
}

// Auto-disable predicate; without usable data it returns false (never disables blind)
bool CStrategyPerformanceHealth::ShouldDisableStrategy(const int index)
{
    if(m_src == NULL)
        return false;

    CStrategyHealthMonitor* healthMonitor = m_src.GetHealthMonitor();
    if(healthMonitor != NULL)
    {
        return healthMonitor.CheckStrategyDisabling(index);
    }

    if(index < 0 || index >= m_src.GetStrategyCount()) return false;

    // Sample requirement: >=10 closed trades, then the 20-trade rolling win rate and
    // the consecutive-loss limit decide the disable
    if(m_src.GetStrategyTotalTrades(index) < 10) return false;

    if(m_src.GetStrategyRecentWinRate(index) < m_src.GetMinWinRateThreshold()) return true;

    if(m_src.GetStrategyConsecutiveLosses(index) >= m_src.GetMaxConsecutiveLossesLimit()) return true;

    return false;
}

// Governance predicate: has the cooldown expired?
bool CStrategyPerformanceHealth::ShouldReEnableStrategy(const int index)
{
    if(m_src == NULL)
        return false;

    CStrategyHealthMonitor* healthMonitor = m_src.GetHealthMonitor();
    if(healthMonitor != NULL)
        return healthMonitor.CheckStrategyReEnabling(index);

    if(index < 0 || index >= m_src.GetStrategyCount()) return false;
    if(!m_src.IsStrategyTemporarilyDisabled(index)) return true;

    return (TimeCurrent() >= m_src.GetStrategyDisabledUntil(index));
}

void CStrategyPerformanceHealth::UpdateRegimePerformance(const int index, int regime, const double result)
{
    if(m_src == NULL)
        return;

    // L1-007: Health monitor doesn't expose regime update by index; use fallback.
    CStrategyHealthMonitor* healthMonitor = m_src.GetHealthMonitor();
    if(healthMonitor != NULL)
    {
        healthMonitor.RecordTradeResult(index, result);
    }

    if(index < 0 || index >= m_src.GetStrategyCount()) return;

    // Regime attribution is the health monitor's; this hook does no per-trade regime work
}

void CStrategyPerformanceHealth::UpdateAIPerformanceMetrics(const string strategyName, const SAIModelMetrics &metrics)
{
    if(m_src == NULL)
        return;

    int idx = m_src.GetStrategyIndexByName(strategyName);
    if(idx < 0 || idx >= m_src.GetStrategyCount())
        return;

    // AI strategies only; the entry pointer is dereferenced unchecked here, as it always was
    ENUM_STRATEGY_TYPE stratType = m_src.GetStrategyPtr(idx).GetType();
    bool isAI = (stratType == STRATEGY_BRAIN || stratType == STRATEGY_AI_ENHANCED);
    if(!isAI)
        return;

    // Field reuse: recentWinRate carries AI accuracy, avgProfit carries AI profitability
    m_src.SetStrategyRecentWinRate(idx, metrics.recentAccuracy);
    m_src.SetStrategyAvgProfit(idx, metrics.profitability);

    double aiHealth = metrics.accuracy;
    if(aiHealth > 0.0)
    {
        // Blend AI accuracy with existing health score (70% existing, 30% AI)
        double blended = 0.70 * m_src.GetStrategyHealthScore(idx) + 0.30 * aiHealth;
        m_src.SetStrategyHealthScore(idx, MathMax(0.0, MathMin(1.0, blended)));
    }

    PrintFormat("[AI-FEEDBACK] %s | %s | accuracy=%.3f | profitability=%.3f | recentAcc=%.3f | health=%.3f",
                m_src.GetManagedSymbol(), strategyName, metrics.accuracy, metrics.profitability,
                metrics.recentAccuracy, m_src.GetStrategyHealthScore(idx));
}

#endif // STRATEGY_PERFORMANCE_HEALTH_MQH
