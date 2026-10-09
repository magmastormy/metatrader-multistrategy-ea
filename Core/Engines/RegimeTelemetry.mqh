// Throttled healthy-path regime logging
// Extracted verbatim from RegimeEngine.mqh (no behavior change)
#ifndef REGIME_TELEMETRY_MQH
#define REGIME_TELEMETRY_MQH

#include "RegimeTypes.mqh"
#include "RegimeComposite.mqh"

// Owns the state-log throttle window and the last logged regime.
// LogDetailedRegime() must be invoked before LogRegimeState() so
// both observe the same pre-update throttle timestamp.
class CRegimeTelemetry
{
private:
    datetime m_lastStateLogTime;
    ENUM_REGIME_STATE m_lastLoggedState;

public:
    CRegimeTelemetry() :
        m_lastStateLogTime(0),
        m_lastLoggedState(REGIME_RANGE)
    {
    }

    //--- Clear throttle state on symbol / timeframe switches
    void Reset()
    {
        m_lastStateLogTime = 0;
        m_lastLoggedState = REGIME_RANGE;
    }

    //--- Log detailed regime with weight multipliers
    void LogDetailedRegime(const SRegimeSnapshot &snapshot, const double adxValue, const datetime now) const;

    //--- Log the coarse regime state transition
    void LogRegimeState(const string symbol,
                        const ENUM_TIMEFRAMES resolvedTimeframe,
                        const ENUM_REGIME_STATE state,
                        const ENUM_REGIME_STATE confirmedState,
                        const double regimeConfidence,
                        const int stabilityBars,
                        const bool compression,
                        const bool spreadShock,
                        const bool cooldownActive,
                        const double spreadToAtr,
                        const double zScore,
                        const double bbWidthAtrRatio,
                        const datetime now);
};

void CRegimeTelemetry::LogDetailedRegime(const SRegimeSnapshot &snapshot, const double adxValue, const datetime now) const
{
    if(m_lastStateLogTime == 0 || (now - m_lastStateLogTime) >= 60)
    {
        PrintFormat("[REGIME-DETAILED] %s | ADX=%.1f | Momentum=%.1fx | Trend=%.1fx | MeanRev=%.1fx | Breakout=%.1fx | ICT=%.1fx",
                   CRegimeComposite::DetailedRegimeToString(snapshot.detailedRegime),
                   adxValue,
                   snapshot.momentumWeightMult,
                   snapshot.trendWeightMult,
                   snapshot.meanRevWeightMult,
                   snapshot.breakoutWeightMult,
                   snapshot.ictWeightMult);
    }
}

void CRegimeTelemetry::LogRegimeState(const string symbol,
                                      const ENUM_TIMEFRAMES resolvedTimeframe,
                                      const ENUM_REGIME_STATE state,
                                      const ENUM_REGIME_STATE confirmedState,
                                      const double regimeConfidence,
                                      const int stabilityBars,
                                      const bool compression,
                                      const bool spreadShock,
                                      const bool cooldownActive,
                                      const double spreadToAtr,
                                      const double zScore,
                                      const double bbWidthAtrRatio,
                                      const datetime now)
{
    if(state != m_lastLoggedState || m_lastStateLogTime == 0 || (now - m_lastStateLogTime) >= 60)
    {
        PrintFormat("[REGIME-STATE] %s | tf=%s | state=%s | confirmed=%s | conf=%.2f | stable_bars=%d | compression=%s | spread_shock=%s | cooldown=%s | spread_atr=%.4f | z=%.3f | bb_atr=%.2f",
                                symbol,
                                EnumToString(resolvedTimeframe),
                                CRegimeComposite::RegimeToString(state),
                                CRegimeComposite::RegimeToString(confirmedState),
                                regimeConfidence,
                                stabilityBars,
                                compression ? "true" : "false",
                                spreadShock ? "true" : "false",
                                cooldownActive ? "true" : "false",
                                spreadToAtr,
                                zScore,
                                bbWidthAtrRatio);
        m_lastLoggedState = state;
        m_lastStateLogTime = now;
    }
}

#endif // REGIME_TELEMETRY_MQH
