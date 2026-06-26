//+------------------------------------------------------------------+
//| IntelligentSLGuard.mqh                                           |
//| Guards SL modifications against predictable wicks and noise       |
//| Implements Component 2 from sl_issue.md                          |
//+------------------------------------------------------------------+
#ifndef CORE_TRADING_INTELLIGENT_SL_GUARD_MQH
#define CORE_TRADING_INTELLIGENT_SL_GUARD_MQH

#include "..\Engines\RegimeEngine.mqh"

struct SGuardDecision
{
    bool   pauseTrailing;
    bool   pauseBreakeven;
    bool   obWiden;
    double adjustedSL;
    string reason;
};

class CIntelligentSLGuard
{
private:
    double m_atrSpikeThreshold;
    int    m_minAgeSeconds;

public:
    CIntelligentSLGuard() : m_atrSpikeThreshold(1.5), m_minAgeSeconds(30) {}

    void SetATRSpikeThreshold(double threshold) { m_atrSpikeThreshold = threshold; }
    void SetMinAgeSeconds(int seconds) { m_minAgeSeconds = seconds; }

    SGuardDecision Evaluate(
        const ulong ticket,
        const double proposedSL,
        CRegimeEngine* regime,
        const double atrBaseline,
        const double atrCurrent
    )
    {
        SGuardDecision decision;
        decision.pauseTrailing = false;
        decision.pauseBreakeven = false;
        decision.obWiden = false;
        decision.adjustedSL = proposedSL;
        decision.reason = "";

        if(ticket <= 0 || !PositionSelectByTicket(ticket))
            return decision;

        // 1. Position age check
        datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
        int ageSec = (int)(TimeCurrent() - openTime);
        if(ageSec < m_minAgeSeconds)
        {
            decision.pauseTrailing = true;
            decision.pauseBreakeven = true;
            decision.reason = "POSITION_TOO_YOUNG";
            return decision;
        }

        // 2. Regime check
        if(regime != NULL)
        {
            SRegimeSnapshot snap = regime.GetSnapshot();
            if(snap.state == REGIME_RANGE)
            {
                decision.pauseTrailing = true;
                decision.reason = "REGIME_RANGE";
            }
        }

        // 3. Volatility spike check
        if(atrBaseline > 0 && atrCurrent > atrBaseline * m_atrSpikeThreshold)
        {
            decision.pauseTrailing = true;
            if(StringLen(decision.reason) == 0)
                decision.reason = "VOLATILITY_SPIKE";
            else
                decision.reason = decision.reason + "+VOLATILITY_SPIKE";
        }

        return decision;
    }
};

#endif // CORE_TRADING_INTELLIGENT_SL_GUARD_MQH
