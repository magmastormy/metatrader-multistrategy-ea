// Singleton-attribution counters, average outcome and bounded health scoring; mutates the manager through
// narrow per-field accessors. Consensus health and participation reads remain in the hot voting loop.
// Implementation detail of EnterpriseStrategyManager.mqh - included from there, not standalone.
#ifndef STRATEGY_PERFORMANCE_HEALTH_MQH
#define STRATEGY_PERFORMANCE_HEALTH_MQH

#include "../Utils/Enums.mqh"                          // ENUM_STRATEGY_TYPE
#include "../../Interfaces/IStrategy.mqh"              // IStrategy::GetType
#include "../../Core/AI/AIPerformanceFeedback.mqh"     // SAIModelMetrics

#define AI_WEIGHT_MIN_PREDICTIONS 50

class CEnterpriseStrategyManager;   // forward: held as a mutable pointer

// Performance / health facade over CEnterpriseStrategyManager
class CStrategyPerformanceHealth
{
private:
    CEnterpriseStrategyManager* m_src;

    // Last AI metric set applied per strategy row. The orchestrator calls UpdateAIPerformanceMetrics
    // for every symbol on the runtime cadence, so with 11 symbols the identical global model metrics
    // were re-applied and re-printed about eight times a second - 174,804 of the 237,954 journal lines
    // in the 2026-10-23 session were this one print, and the health blend 0.70/0.30 was compounded
    // thousands of times per metrics update instead of once. Both stop here: the setters and the print
    // run only when the metrics actually change.
    struct SAIMetricStamp
    {
        double accuracy;
        double profitability;
        double recentAccuracy;
        bool   valid;
    };
    SAIMetricStamp m_aiMetricStamps[64];

public:
    CStrategyPerformanceHealth() : m_src(NULL) {}

    void SetSource(CEnterpriseStrategyManager* src) { m_src = src; }

    void   UpdatePerformance(const string strategyName, double netProfit);
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

    // Three-way outcome: a scratch close (netProfit == 0) is activity, not a decided result - it
    // increments totalTrades but touches neither the win/loss counters nor the consecutive streaks,
    // so breakeven exits stop dragging win-rate, health score and the consecutive-loss park.
    m_src.SetStrategyTotalTrades(idx, m_src.GetStrategyTotalTrades(idx) + 1);
    if(netProfit > 0.0)
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
    else if(netProfit < 0.0)
    {
        m_src.SetStrategyFailCount(idx, m_src.GetStrategyFailCount(idx) + 1);
        m_src.SetStrategyConsecutiveLosses(idx, m_src.GetStrategyConsecutiveLosses(idx) + 1);
        m_src.SetStrategyConsecutiveWins(idx, 0);
    }

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
    // CConsensusWeightingConfig reads for the [AI-WEIGHT-ADJUST] multiplier. Below the sample floor it
    // reads as neutral so a handful of predictions cannot move the weight.
    // Idempotence gate first: an unchanged metric set must not touch the roster or the journal, because
    // the caller runs this per symbol per tick-cadence while the metrics are global.
    if(idx < ArraySize(m_aiMetricStamps) && m_aiMetricStamps[idx].valid
       && m_aiMetricStamps[idx].accuracy == metrics.accuracy
       && m_aiMetricStamps[idx].profitability == metrics.profitability
       && m_aiMetricStamps[idx].recentAccuracy == metrics.recentAccuracy)
        return;

    if(idx < ArraySize(m_aiMetricStamps))
    {
        m_aiMetricStamps[idx].accuracy       = metrics.accuracy;
        m_aiMetricStamps[idx].profitability  = metrics.profitability;
        m_aiMetricStamps[idx].recentAccuracy = metrics.recentAccuracy;
        m_aiMetricStamps[idx].valid          = true;
    }

    double weightingProfit = (metrics.totalPredictions >= AI_WEIGHT_MIN_PREDICTIONS) ? metrics.profitability : 0.0;
    m_src.SetStrategyAvgProfit(idx, weightingProfit);

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
