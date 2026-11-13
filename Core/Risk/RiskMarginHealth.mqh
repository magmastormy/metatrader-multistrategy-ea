// Free-margin / margin-level pre-flight checks and the runtime margin-health monitor.
// This class measures and requests; closing belongs to the circuit breaker's emergency flag and
// sizing belongs to CRiskAdaptiveTuner, so it holds neither.
#ifndef CORE_RISK_RISK_MARGIN_HEALTH_MQH
#define CORE_RISK_RISK_MARGIN_HEALTH_MQH

#include "../Utils/Enums.mqh"
#include "RiskCircuitBreaker.mqh"

class CRiskMarginHealth
{
private:
    double m_maxFreeMarginUsage;   // Fraction of free margin usable by one order (0.8 = 80%)
    double m_minMarginLevel;       // Minimum acceptable post-trade margin level (%)

public:
    CRiskMarginHealth() :
        m_maxFreeMarginUsage(0.8),
        m_minMarginLevel(200.0)
    {
    }

    ~CRiskMarginHealth()
    {
    }

    void SetMaxFreeMarginUsage(double value) { m_maxFreeMarginUsage = MathMax(0.0, MathMin(1.0, value)); }
    void SetMinMarginLevel(double value)   { m_minMarginLevel   = MathMax(0.0, value); }

// Free-margin usage (maxFreeMarginUsage) and minimum margin level (minMarginLevel) are operator inputs
// flowing through SOrchestratorConfig, bound at EA init via ConfigureMarginHealth(). The rejection
// message prints the ceiling in force.

    //--- Free-margin headroom + post-trade margin-level check, behind CRiskValidationPipeline::ValidateMarginRequirements.
    bool CheckFreeMarginAndLevel(const double marginRequired,
                                 const bool isHedging,
                                 string &message) const
    {
        double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);

        if(marginRequired > freeMargin * m_maxFreeMarginUsage)
        {
            message = StringFormat("Insufficient margin: required %.2f, available %.2f (threshold: %.0f%%) [mode: %s]",
                                 marginRequired, freeMargin, m_maxFreeMarginUsage * 100.0,
                                 isHedging ? "hedging" : "netting");
            return false;
        }

        double currentMarginLevel = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
        if(currentMarginLevel > 0 && currentMarginLevel < m_minMarginLevel)
        {
            message = StringFormat("Margin level too low: %.2f%% (threshold: %.0f%%)",
                                 currentMarginLevel, m_minMarginLevel);
            return false;
        }

        double equity = AccountInfoDouble(ACCOUNT_EQUITY);
        double currentMargin = AccountInfoDouble(ACCOUNT_MARGIN);
        double projectedMargin;
        if(isHedging)
        {
            // Hedging: simply add new margin requirement
            projectedMargin = currentMargin + marginRequired;
        }
        else
        {
            // Netting: subtract margin already held on same symbol in opposite direction
            // before adding new requirement
            projectedMargin = currentMargin + marginRequired;
            // Note: For netting accounts, same-symbol opposite positions offset margin.
            // This requires symbol-specific position enumeration; conservatively keep full add.
        }
        if(projectedMargin > 0.0)
        {
            double projectedLevel = equity / projectedMargin * 100.0;
            if(projectedLevel < m_minMarginLevel)
            {
                message = StringFormat("Projected post-trade margin level %.2f%% below threshold %.0f%% [mode: %s]",
                                     projectedLevel, m_minMarginLevel, isHedging ? "hedging" : "netting");
                return false;
            }
        }

        return true;
    }

// Runtime monitoring

//--- The margin ladder measures and requests; it does not close and it does not size.
//--- EMERGENCY (<150%) asks the circuit breaker to flatten, which the orchestrator's single emergency-close path
//--- executes; CRITICAL (150-200%) is the owner's entry hold, applied by CUnifiedRiskManager from the returned level.
//--- Closing belongs to CTradeManager and conservative sizing belongs to CRiskAdaptiveTuner, so neither is written here:
//--- the version of this method that called PositionClose() itself was a second flatten authority, and the version that
//--- set conservativeMode latched it, because CRiskAdaptiveTuner only clears that flag when it was not already set.
    ENUM_MARGIN_HEALTH_LEVEL MonitorMarginHealth(CRiskCircuitBreaker &breaker)
    {
        double margin = AccountInfoDouble(ACCOUNT_MARGIN);
        if(margin <= 0.0)
            return MARGIN_HEALTH_OK; // No margin used = no risk

        double equity = AccountInfoDouble(ACCOUNT_EQUITY);
        if(equity <= 0.0)
        {
            breaker.RequestEmergencyClose();
            Print("[RISK-MARGIN] EMERGENCY | equity <= 0 while margin is in use | flatten requested");
            return MARGIN_HEALTH_EMERGENCY;
        }

        double marginLevel = (equity / margin) * 100.0;

        if(marginLevel < 150.0)
        {
            breaker.RequestEmergencyClose();
            PrintFormat("[RISK-MARGIN] EMERGENCY | Margin Level=%.1f%% < 150%% | flatten requested(circuit breaker owns closing) | equity=%.2f margin=%.2f",
                        marginLevel, equity, margin);
            return MARGIN_HEALTH_EMERGENCY;
        }

        if(marginLevel < 200.0)
        {
            PrintFormat("[RISK-MARGIN] CRITICAL | Margin Level=%.1f%% < 200%% | entries held(open positions untouched) | equity=%.2f margin=%.2f",
                        marginLevel, equity, margin);
            return MARGIN_HEALTH_CRITICAL;
        }

        if(marginLevel < 300.0)
        {
            static datetime s_lastMarginWarning = 0;
            datetime now = TimeCurrent();
            if(s_lastMarginWarning == 0 || (now - s_lastMarginWarning) >= 60)
            {
                PrintFormat("[RISK-MARGIN] WARNING | Margin Level=%.1f%% < 300%% | advisory only", marginLevel);
                s_lastMarginWarning = now;
            }
            return MARGIN_HEALTH_WARNING;
        }

        return MARGIN_HEALTH_OK;
}
};

#endif // CORE_RISK_RISK_MARGIN_HEALTH_MQH
