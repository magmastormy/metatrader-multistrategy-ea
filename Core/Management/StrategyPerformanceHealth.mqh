// Per-strategy performance accounting, rolling statistics and health scoring; mutates the manager through
// narrow per-field accessors. Deliberately NOT moved: the health/participation reads inside
// EvaluateConsensusInternal and its two siblings (the hottest per-strategy loop), and CStrategyHealthMonitor
// itself, which this module only mirrors and delegates to.
// Implementation detail of EnterpriseStrategyManager.mqh - included from there, not standalone.
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
    bool   ShouldDisableStrategy(const int index);
    bool   ShouldReEnableStrategy(const int index);
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
    }

    UpdateRecentPerformance(idx, netProfit);

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

    if(ShouldDisableStrategy(idx))
    {
        m_src.SetStrategyTemporarilyDisabled(idx, true);
        m_src.SetStrategyDisabledUntil(idx, TimeCurrent() + 3600); // Disable for 1 hour
        // The park is decided from the monitor's sample, so the numbers printed here come from the
        // same holder. The roster's own winRate/recentWinRate had no live writer and printed 0.00.
        CStrategyHealthMonitor* parkMonitor = m_src.GetHealthMonitor();
        PrintFormat("[Enterprise-Adaptation] Strategy %s DISABLED due to poor performance (WinRate: %.2f, recent: %.2f, Losses: %d)",
                    strategyName,
                    parkMonitor != NULL ? parkMonitor.GetWinRate(idx) : 0.0,
                    parkMonitor != NULL ? parkMonitor.GetRecentWinRate(idx) : 0.0,
                    m_src.GetStrategyConsecutiveLosses(idx));
    }
}

void CStrategyPerformanceHealth::UpdateRecentPerformance(const int index, const double result)
{
    if(m_src == NULL)
        return;

    // The manager's constructor allocates the monitor, so it is the only holder of these numbers;
    // the roster's own recent-trade ring was the second holder and never received a write.
    CStrategyHealthMonitor* healthMonitor = m_src.GetHealthMonitor();
    if(healthMonitor != NULL)
        healthMonitor.RecordTradeResult(index, result);
}

// Auto-disable predicate; without usable data it returns false (never disables blind)
bool CStrategyPerformanceHealth::ShouldDisableStrategy(const int index)
{
    if(m_src == NULL)
        return false;

    CStrategyHealthMonitor* healthMonitor = m_src.GetHealthMonitor();
    if(healthMonitor != NULL)
        return healthMonitor.CheckStrategyDisabling(index);

    return false;
}

// Governance predicate: the monitor parks on its own flag and releases it on the next
// CheckAllStrategiesReEnabling pass, which arms no cooldown of its own.
bool CStrategyPerformanceHealth::ShouldReEnableStrategy(const int index)
{
    if(m_src == NULL)
        return false;

    CStrategyHealthMonitor* healthMonitor = m_src.GetHealthMonitor();
    if(healthMonitor != NULL)
        return healthMonitor.CheckStrategyReEnabling(index);

    return false;
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

    // Field reuse: avgProfit carries AI profitability for these rows, which is what
    // CConsensusWeightingConfig reads for the [AI-WEIGHT-ADJUST] multiplier.
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
