//+------------------------------------------------------------------+
//| RiskMath.mqh                                                      |
//| Centralized risk calculation utilities to ensure consistency     |
//| across all risk components (UnifiedRiskManager, PositionSizer,   |
//| PortfolioRiskManager, etc.)                                      |
//| Fixes L5-001: Risk Denominator Inconsistency Across Components   |
//+------------------------------------------------------------------+
#ifndef CORE_UTILS_RISK_MATH_MQH
#define CORE_UTILS_RISK_MATH_MQH

//+------------------------------------------------------------------+
//| Risk Math Utilities                                              |
//+------------------------------------------------------------------+
class CRiskMath
{
public:
    // Returns the stress-aware risk denominator for risk percentage calculations.
    // Uses equity-aware logic: when both balance and equity are positive,
    // returns the minimum (stress state). When one is non-positive,
    // returns the positive value. Returns 0 if both are <= 0.
    // This implementation MUST be used by all risk components to ensure
    // consistent risk percentage calculations.
    static double GetRiskDenominator()
    {
        double balance = AccountInfoDouble(ACCOUNT_BALANCE);
        double equity  = AccountInfoDouble(ACCOUNT_EQUITY);

        if(balance > 0.0 && equity > 0.0)
            return MathMin(balance, equity);
        else if(balance > 0.0)
            return balance;
        else if(equity > 0.0)
            return equity;

        return 0.0;
    }

    // Safe wrapper that returns a minimum valid denominator (1.0) to avoid
    // division by zero. Use this when a non-zero denominator is required.
    static double GetSafeRiskDenominator()
    {
        double denom = GetRiskDenominator();
        return (denom > 0.0) ? denom : 1.0;
    }

    // Converts absolute risk amount to percentage using the stress-aware denominator.
    // Returns 0 if denominator is invalid.
    static double RiskAmountToPercent(double riskAmount)
    {
        double denom = GetRiskDenominator();
        if(denom <= 0.0)
            return 0.0;
        return (riskAmount / denom) * 100.0;
    }

    // Converts risk percentage to absolute amount using the stress-aware denominator.
    // Returns 0 if denominator is invalid.
    static double RiskPercentToAmount(double riskPercent)
    {
        double denom = GetRiskDenominator();
        if(denom <= 0.0)
            return 0.0;
        return denom * (riskPercent / 100.0);
    }
};

#endif // CORE_UTILS_RISK_MATH_MQH