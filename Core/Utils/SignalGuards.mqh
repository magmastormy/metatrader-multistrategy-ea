// Local pre-trade guards: stop validity, reward-to-risk, and spread vs stop.
// Strategies call this from GetSignal() before emitting a signal so obviously
// untradeable setups never reach the unified risk gate.
//
// spread is in the same price units as entry/stop/target
// (SYMBOL_SPREAD points * SYMBOL_POINT). minRR defaults to 1.0 (at least 1R),
// maxSpreadRatio defaults to 0.5 (spread no more than half the stop distance).
// Both are overridable per strategy.
#ifndef CORE_UTILS_SIGNAL_GUARDS_MQH
#define CORE_UTILS_SIGNAL_GUARDS_MQH

class CSignalGuards
{
public:
    static bool IsSignalTradable(double entry, double stop, double target, double spread,
                                 double minRR = 1.0, double maxSpreadRatio = 0.5)
    {
        double stopDistance   = MathAbs(entry - stop);
        double targetDistance = MathAbs(target - entry);

        if(stopDistance <= 0.0)
            return false;   // invalid stop: entry equals stop, or stop not set
        if(targetDistance <= 0.0)
            return false;   // invalid target: entry equals target, or target not set

        double rr = targetDistance / stopDistance;
        if(rr < minRR)
            return false;   // poor reward-to-risk

        if(spread < 0.0)
            spread = 0.0;
        if(maxSpreadRatio > 0.0 && spread > maxSpreadRatio * stopDistance)
            return false;   // spread too wide relative to the stop

        return true;
    }
};

#endif // CORE_UTILS_SIGNAL_GUARDS_MQH
