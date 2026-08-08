//+------------------------------------------------------------------+
//| RiskAdaptiveTuner.mqh                                            |
//| Adaptive risk-sizing state: active risk per trade, conservative  |
//| mode flag, throttle pressure, and profit-adjusted risk reduction |
//| factor.                                                           |
//|                                                                  |
//| Extracted verbatim from CUnifiedRiskManager (Phase E3, B):       |
//|   m_activeRiskPerTradePercent (double, init 1.0)                 |
//|   m_riskReductionFactor       (double, init 0.5)                 |
//|   m_lastThrottlePressure      (double, init 1.0)                 |
//|   m_conservativeMode          (bool,   init false)               |
//|   CUnifiedRiskManager::UpdateAdaptiveRiskLevel                   |
//|       -> UpdateAdaptiveRiskLevel                                 |
//|   CUnifiedRiskManager::GetThrottlePressure                       |
//|       -> GetThrottlePressure                                    |
//|   CUnifiedRiskManager::GetActiveRiskPerTradePercent              |
//|       -> GetActiveRiskPerTradePercent                            |
//|                                                                  |
//| Behaviour is byte-identical to the original member functions;    |
//| CUnifiedRiskManager keeps thin forwarders with the original      |
//| signatures so that all call sites remain unchanged.              |
//|                                                                  |
//| OWNERSHIP NOTE: config values (baseRiskPerTradePercent,          |
//| enableAdaptiveSizing, adaptationMinTrades, drawdown thresholds,  |
//| min/max risk percent) and the performance analytics pointer are  |
//| passed as parameters from the forwarder because they change at   |
//| runtime (ApplyTierOverrides / Initialize / SetPerformanceAnalytics).|
//| The moved state fields (active risk, conservative mode, throttle |
//| pressure, reduction factor) are owned exclusively by this class. |
//+------------------------------------------------------------------+
#ifndef CORE_RISK_RISK_ADAPTIVE_TUNER_MQH
#define CORE_RISK_RISK_ADAPTIVE_TUNER_MQH

#include "../Monitoring/PerformanceAnalytics.mqh"

//+------------------------------------------------------------------+
//| Adaptive risk tuner (stateful, owned by value)                   |
//+------------------------------------------------------------------+
class CRiskAdaptiveTuner
{
private:
    double m_activeRiskPerTradePercent;  // Blueprint 10.4: 0-100 scale (1.0 = 1%)
    double m_riskReductionFactor;        // Fraction of unrealized profit that frees risk budget
    double m_lastThrottlePressure;       // 1.0 = no pressure, 0.0 = max pressure
    bool   m_conservativeMode;           // Conservative risk mode flag

    //--- Local clamp helper (equivalent to URM's ClampRiskPercent but
    //--- receives min/max explicitly since this class doesn't own m_config).
    double ClampRiskPercent(const double minVal, const double maxVal, const double value) const
    {
        return MathMax(minVal, MathMin(maxVal, value));
    }

public:
    //--- Constructor performs the zero-init that used to live in
    //--- CUnifiedRiskManager's initialiser list (identical values).
    CRiskAdaptiveTuner() :
        m_activeRiskPerTradePercent(1.0),  // Blueprint 10.4: 0-100 scale (1.0 = 1%)
        m_riskReductionFactor(0.5),
        m_lastThrottlePressure(1.0),
        m_conservativeMode(false)
    {
    }

    ~CRiskAdaptiveTuner()
    {
        // No owned resources.
    }

    //+--------------------------------------------------------------+
    //| Getters / setters for the moved state fields                  |
    //+--------------------------------------------------------------+

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

    //+--------------------------------------------------------------+
    //| Update adaptive risk level                                    |
    //| Config values and analytics pointer are passed from the       |
    //| forwarder because they change at runtime.                    |
    //+--------------------------------------------------------------+
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
        m_conservativeMode = false;

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

        targetRisk = baseRiskPerTradePercent * reductionFactor;
        m_activeRiskPerTradePercent = ClampRiskPercent(minRiskPerTradePercent, maxRiskPerTradePercent, targetRisk);
    }
};

#endif // CORE_RISK_RISK_ADAPTIVE_TUNER_MQH
