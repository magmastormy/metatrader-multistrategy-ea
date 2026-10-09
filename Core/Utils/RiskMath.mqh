// One authority for risk arithmetic: every risk component (UnifiedRiskManager,
// PositionSizer, PortfolioRiskManager) must price risk on the same denominator.
#ifndef CORE_UTILS_RISK_MATH_MQH
#define CORE_UTILS_RISK_MATH_MQH

class CRiskMath
{
public:
    // Stress-aware denominator: min(balance, equity) when both are positive, the
    // positive one when only it is; 0 when neither is.
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

    // Absolute risk amount -> percent on the stress-aware denominator; 0 if invalid.
    static double RiskAmountToPercent(double riskAmount)
    {
        double denom = GetRiskDenominator();
        if(denom <= 0.0)
            return 0.0;
        return (riskAmount / denom) * 100.0;
    }

    // Risk percent -> absolute amount on the stress-aware denominator; 0 if invalid.
    static double RiskPercentToAmount(double riskPercent)
    {
        double denom = GetRiskDenominator();
        if(denom <= 0.0)
            return 0.0;
        return denom * (riskPercent / 100.0);
    }
};

#endif // CORE_UTILS_RISK_MATH_MQH