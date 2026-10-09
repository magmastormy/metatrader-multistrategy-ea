// Per-strategy performance accounting, rolling-window statistics and health/quality
// scoring: trade outcome accounting, the 20-trade rolling ring buffer, rolling win
// rate / Sharpe, derived metrics, the disable / re-enable governance predicates and
// the AI accuracy -> health blend.
// Like the Slice 2 collaborator CConsensusWeightingConfig this
// module MUTATES the manager, so it holds a NON-const back-pointer.
// Every read and every write goes through the manager's narrow
// per-field accessor surface, so the resulting state transitions
// are byte-for-byte identical to the original inline bodies.
// DELIBERATELY NOT MOVED:
// Multiplier. They are health/participation READS, but they are
// called from inside the DO-NOT-PIECEMEAL C9 consensus core
// (EvaluateConsensusInternal, EvaluateConsensusProbeOnly-
// Internal, TryFallbackSoloSignalInternal) on the hottest
// per-strategy loop. Same rationale C4 used for the atomic
// consensus setters: do not add indirection the C9 bodies must
// traverse.
// - CStrategyHealthMonitor itself. This module only orchestrates
// the manager-side mirror and the delegation to that monitor,
// exactly as the original code did.
// NOTE: this header is an implementation detail of
// EnterpriseStrategyManager.mqh and is included from there (after
// the shared free helpers, before the manager class). It is not
// intended to be included standalone.
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

        // Maintain rolling average profit per winning trade
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

        // Maintain rolling average loss magnitude per losing trade.
        // NOTE: totalTrades was already incremented above - preserved verbatim.
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

    // Regime-specific performance attribution is owned by the health monitor; no per-trade
    // regime update is performed here.

    CalculateStrategyMetrics(idx);

    // Health score update (original ESM logic blended with AISO metrics)
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

// Rolling-window win rate
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

// Rolling-window Sharpe ratio
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

// Governance predicate: should this strategy be disabled?
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

    // Only check if we have enough trades
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
        // Still record the trade result for health tracking
        healthMonitor.RecordTradeResult(index, result);
    }

    if(index < 0 || index >= m_src.GetStrategyCount()) return;

    // Regime-specific performance is tracked by the health monitor; this hook intentionally
    // performs no per-trade regime update.
}

void CStrategyPerformanceHealth::UpdateAIPerformanceMetrics(const string strategyName, const SAIModelMetrics &metrics)
{
    if(m_src == NULL)
        return;

    int idx = m_src.GetStrategyIndexByName(strategyName);
    if(idx < 0 || idx >= m_src.GetStrategyCount())
        return;

    // Only apply to AI strategies.
    // NOTE (verbatim): the original body dereferences the strategy pointer
    // without a NULL check. Preserved as-is - no behaviour change.
    ENUM_STRATEGY_TYPE stratType = m_src.GetStrategyPtr(idx).GetType();
    bool isAI = (stratType == STRATEGY_BRAIN || stratType == STRATEGY_AI_ENHANCED);
    if(!isAI)
        return;

    // Store AI metrics in the strategy entry for use in weight adaptation
    // Reuse recentWinRate for AI accuracy, avgProfit for AI profitability
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
