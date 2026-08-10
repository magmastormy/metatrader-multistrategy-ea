//+------------------------------------------------------------------+
//| PerfAnalyticsRiskTriggers.mqh                                    |
//| Performance trigger evaluation, risk-level classification and    |
//| parameter adjustment recommendations.                            |
//| Extracted verbatim from PerformanceAnalytics.mqh.                |
//+------------------------------------------------------------------+
#ifndef CORE_PERF_ANALYTICS_RISKTRIGGERS_MQH
#define CORE_PERF_ANALYTICS_RISKTRIGGERS_MQH

#include "PerfAnalyticsTypes.mqh"
#include "PerfAnalyticsTradeStats.mqh"

//+------------------------------------------------------------------+
//| Performance triggers and risk assessment                         |
//+------------------------------------------------------------------+
class CPerfAnalyticsRiskTriggers
{
private:
    // Performance triggers
    bool m_needsRiskReduction;
    bool m_needsParameterAdjustment;
    bool m_performanceAcceptable;

public:
    //+--------------------------------------------------------------+
    //| Constructor                                                  |
    //+--------------------------------------------------------------+
    CPerfAnalyticsRiskTriggers(void) :
        m_needsRiskReduction(false),
        m_needsParameterAdjustment(false),
        m_performanceAcceptable(true)
    {
    }

    //+--------------------------------------------------------------+
    //| Check Performance Triggers                                   |
    //+--------------------------------------------------------------+
    void CheckPerformanceTriggers(const CPerfAnalyticsTradeStats &stats, const double currentDrawdown)
    {
        if(stats.GetTotalTrades() < MIN_TRADES_FOR_STATS) return;

        // Reset flags
        m_needsRiskReduction = false;
        m_needsParameterAdjustment = false;
        m_performanceAcceptable = true;

        // Check win rate trigger (Requirement 6.1)
        if(stats.GetRollingWinRate() < 40.0 && stats.GetTotalTrades() >= 20)
        {
            m_needsRiskReduction = true;
            m_needsParameterAdjustment = true;
            CPerfAnalyticsLog::LogPerformanceUpdate(StringFormat("Performance trigger: Win rate %.1f%% below 40%", stats.GetRollingWinRate()));
        }

        // Check Sharpe ratio trigger (Requirement 6.2)
        if(stats.GetRollingSharpe() < 0.5 && stats.GetTotalTrades() >= 20)
        {
            m_needsParameterAdjustment = true;
            CPerfAnalyticsLog::LogPerformanceUpdate(StringFormat("Performance trigger: Sharpe ratio %.2f below 0.5", stats.GetRollingSharpe()));
        }

        // Check drawdown trigger (Requirement 6.3)
        if(currentDrawdown > DRAWDOWN_WARNING)
        {
            m_needsRiskReduction = true;
            if(currentDrawdown > DRAWDOWN_CRITICAL)
            {
                m_performanceAcceptable = false;
                CPerfAnalyticsLog::LogPerformanceUpdate(StringFormat("Critical drawdown: %.2f%% exceeds %.2f%%", currentDrawdown, DRAWDOWN_CRITICAL));
            }
        }

        // Check consecutive losses
        if(stats.GetConsecutiveLosses() >= MAX_CONSECUTIVE_LOSSES)
        {
            m_needsRiskReduction = true;
            m_needsParameterAdjustment = true;
            CPerfAnalyticsLog::LogPerformanceUpdate(StringFormat("Performance trigger: %d consecutive losses", stats.GetConsecutiveLosses()));
        }

        // Check profit factor
        if(stats.GetProfitFactor() < 1.2 && stats.GetTotalTrades() >= 20)
        {
            m_needsParameterAdjustment = true;
            CPerfAnalyticsLog::LogPerformanceUpdate(StringFormat("Performance trigger: Profit factor %.2f below 1.2", stats.GetProfitFactor()));
        }
    }

    //+--------------------------------------------------------------+
    //| Get Recommended Risk Reduction                               |
    //+--------------------------------------------------------------+
    double GetRecommendedRiskReduction(const CPerfAnalyticsTradeStats &stats, const double currentDrawdown) const
    {
        if(!m_needsRiskReduction) return 1.0; // No reduction needed

        double reductionFactor = 1.0;

        // Reduce based on win rate
        if(stats.GetRollingWinRate() < 30.0)
            reductionFactor *= 0.3; // 70% reduction
        else if(stats.GetRollingWinRate() < 40.0)
            reductionFactor *= 0.5; // 50% reduction

        // Reduce based on drawdown
        if(currentDrawdown > DRAWDOWN_CRITICAL)
            reductionFactor *= 0.2; // 80% reduction
        else if(currentDrawdown > DRAWDOWN_WARNING)
            reductionFactor *= 0.5; // 50% reduction

        // Reduce based on consecutive losses
        if(stats.GetConsecutiveLosses() >= MAX_CONSECUTIVE_LOSSES)
            reductionFactor *= 0.3; // 70% reduction

        return MathMax(reductionFactor, 0.1); // Minimum 10% of original risk
    }

    //+--------------------------------------------------------------+
    //| Get Recommended Confidence Threshold                         |
    //+--------------------------------------------------------------+
    double GetRecommendedConfidenceThreshold(const CPerfAnalyticsTradeStats &stats) const
    {
        double baseThreshold = 0.65; // Default threshold

        if(!m_needsParameterAdjustment) return baseThreshold;

        // Increase threshold when performance is poor
        if(stats.GetRollingWinRate() < 30.0)
            return 0.85; // Very high threshold
        else if(stats.GetRollingWinRate() < 40.0)
            return 0.75; // High threshold

        if(stats.GetRollingSharpe() < 0.3)
            return 0.80; // High threshold for poor Sharpe

        if(stats.GetConsecutiveLosses() >= MAX_CONSECUTIVE_LOSSES)
            return 0.80; // High threshold after losses

        return baseThreshold;
    }

    //+--------------------------------------------------------------+
    //| Should Enable Conservative Mode                              |
    //+--------------------------------------------------------------+
    bool ShouldEnableConservativeMode(const CPerfAnalyticsTradeStats &stats, const double currentDrawdown) const
    {
        if(stats.GetTotalTrades() < MIN_TRADES_FOR_STATS) return false;

        // Enable conservative mode if multiple triggers are active
        int triggerCount = 0;

        if(stats.GetRollingWinRate() < 40.0) triggerCount++;
        if(stats.GetRollingSharpe() < 0.5) triggerCount++;
        if(currentDrawdown > DRAWDOWN_WARNING) triggerCount++;
        if(stats.GetConsecutiveLosses() >= 3) triggerCount++;
        if(stats.GetProfitFactor() < 1.2) triggerCount++;

        return triggerCount >= 2; // Conservative mode if 2+ triggers
    }

    //+--------------------------------------------------------------+
    //| Check if Performance is Acceptable                           |
    //+--------------------------------------------------------------+
    bool IsPerformanceAcceptable(const CPerfAnalyticsTradeStats &stats, const double maxDrawdown) const
    {
        if(stats.GetTotalTrades() < MIN_TRADES_FOR_STATS)
            return true; // Not enough data

        // Check key performance indicators
        if(stats.GetWinRate() < 30.0) // Win rate too low
            return false;

        if(stats.GetProfitFactor() < 1.1) // Profit factor too low
            return false;

        if(maxDrawdown > DRAWDOWN_CRITICAL) // Drawdown too high
            return false;

        return true;
    }

    //+--------------------------------------------------------------+
    //| Get Current Risk Level                                       |
    //+--------------------------------------------------------------+
    ENUM_RISK_LEVEL GetCurrentRiskLevel(const CPerfAnalyticsTradeStats &stats, const double currentDrawdown) const
    {
        if(currentDrawdown > DRAWDOWN_CRITICAL)
            return RISK_LEVEL_EXTREME;
        else if(currentDrawdown > DRAWDOWN_WARNING)
            return RISK_LEVEL_HIGH;
        else if(stats.GetWinRate() < 40.0 || stats.GetProfitFactor() < 1.2)
            return RISK_LEVEL_MEDIUM;
        else
            return RISK_LEVEL_LOW;
    }

    //+--------------------------------------------------------------+
    //| Accessors                                                    |
    //+--------------------------------------------------------------+
    bool NeedsRiskReduction(void) const { return m_needsRiskReduction; }
    bool NeedsParameterAdjustment(void) const { return m_needsParameterAdjustment; }
    bool IsPerformanceFlagAcceptable(void) const { return m_performanceAcceptable; }
};

#endif // CORE_PERF_ANALYTICS_RISKTRIGGERS_MQH
