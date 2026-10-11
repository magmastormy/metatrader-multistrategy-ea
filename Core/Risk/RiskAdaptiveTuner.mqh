// Adaptive risk-sizing state: active risk per trade, conservative mode, throttle pressure, reduction factor.
// OWNERSHIP: config and the analytics pointer are passed in per call because they change at runtime
// (ApplyTierOverrides / Initialize / SetPerformanceAnalytics); the state fields here are owned exclusively.
#ifndef CORE_RISK_RISK_ADAPTIVE_TUNER_MQH
#define CORE_RISK_RISK_ADAPTIVE_TUNER_MQH

#include "../Monitoring/PerformanceAnalytics.mqh"

// Adaptive risk tuner (stateful, owned by value)
class CRiskAdaptiveTuner
{
private:
    double m_activeRiskPerTradePercent;  // Blueprint 10.4: 0-100 scale (1.0 = 1%)
    double m_riskReductionFactor;        // Fraction of unrealized profit that frees risk budget
    double m_lastThrottlePressure;       // 1.0 = no pressure, 0.0 = max pressure
    bool   m_conservativeMode;           // Conservative risk mode flag

    //--- Clamp helper: min/max arrive as parameters because this class owns no risk config.
    double ClampRiskPercent(const double minVal, const double maxVal, const double value) const
    {
        return MathMax(minVal, MathMin(maxVal, value));
    }

public:
    CRiskAdaptiveTuner() :
        m_activeRiskPerTradePercent(1.0),  // Blueprint 10.4: 0-100 scale (1.0 = 1%)
        m_riskReductionFactor(0.5),
        m_lastThrottlePressure(1.0),
        m_conservativeMode(false)
    {
    }

    ~CRiskAdaptiveTuner()
    {
    }


    double GetActiveRiskPerTradePercent() const
    {
        return m_activeRiskPerTradePercent;
    }

    void SetActiveRiskPerTradePercent(const double value)
    {
        m_activeRiskPerTradePercent = value;
    }

    double GetThrottlePressure() const
    {
        return m_lastThrottlePressure;
    }

    void SetThrottlePressure(const double value)
    {
        m_lastThrottlePressure = value;
    }

    double GetRiskReductionFactor() const
    {
        return m_riskReductionFactor;
    }

    bool IsConservativeMode() const
    {
        return m_conservativeMode;
    }

    void SetConservativeMode(const bool value)
    {
        m_conservativeMode = value;
    }

// Config and analytics are parameters, not fields: they change at runtime.
    void UpdateAdaptiveRiskLevel(const double baseRiskPerTradePercent,
                                 const bool enableAdaptiveSizing,
                                 const int adaptationMinTrades,
                                 const double drawdownWarningPercent,
                                 const double drawdownCriticalPercent,
                                 const double minRiskPerTradePercent,
                                 const double maxRiskPerTradePercent,
                                 CPerformanceAnalytics* performanceAnalytics)
    {
        double targetRisk = baseRiskPerTradePercent;
        // m_conservativeMode is shared with the drawdown circuit breaker, which writes it through
        // SetConservativeMode; this path may clear it only when the breaker is not holding it.
        bool conservativeHeld = m_conservativeMode;

        if(!enableAdaptiveSizing)
        {
            m_activeRiskPerTradePercent = ClampRiskPercent(minRiskPerTradePercent, maxRiskPerTradePercent, targetRisk);
            return;
        }

        CPerformanceAnalytics* analytics = performanceAnalytics;
        if(CheckPointer(analytics) == POINTER_INVALID)
        {
            m_activeRiskPerTradePercent = ClampRiskPercent(minRiskPerTradePercent, maxRiskPerTradePercent, targetRisk);
            return;
        }

        SPerformanceMetrics perf = analytics.GetPerformanceMetrics();
        if(perf.totalTrades < adaptationMinTrades)
        {
            m_activeRiskPerTradePercent = ClampRiskPercent(minRiskPerTradePercent, maxRiskPerTradePercent, targetRisk);
            return;
        }

        double reductionFactor = analytics.GetRecommendedRiskReduction();
        reductionFactor = MathMax(0.1, MathMin(1.0, reductionFactor));

        double drawdownValue = analytics.GetCurrentDrawdown();
        if(drawdownValue >= drawdownCriticalPercent)
            reductionFactor = MathMin(reductionFactor, 0.35);
        else if(drawdownValue >= drawdownWarningPercent)
            reductionFactor = MathMin(reductionFactor, 0.65);

        if(analytics.ShouldEnableConservativeMode())
        {
            m_conservativeMode = true;
            reductionFactor = MathMin(reductionFactor, 0.60);
        }
        else if(!conservativeHeld)
        {
            // No breaker hold: clear explicitly so one stale trigger cannot latch the flag.
            m_conservativeMode = false;
        }

        targetRisk = baseRiskPerTradePercent * reductionFactor;
        m_activeRiskPerTradePercent = ClampRiskPercent(minRiskPerTradePercent, maxRiskPerTradePercent, targetRisk);
    }
};

#endif // CORE_RISK_RISK_ADAPTIVE_TUNER_MQH
