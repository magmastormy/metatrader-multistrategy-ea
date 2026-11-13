// Data-fault accounting, snapshot reuse and degraded-path logging
// Extracted verbatim from RegimeEngine.mqh (no behavior change)
#ifndef REGIME_FAULT_MQH
#define REGIME_FAULT_MQH

#include "RegimeTypes.mqh"
#include "RegimeComposite.mqh"
#include "RegimeVolatility.mqh"

// Owns the consecutive fault counter, the reuse TTL and the two
// throttled degraded-path log timestamps.
class CRegimeFaultTracker
{
private:
    int m_consecutiveDataFaults;
    datetime m_lastFaultLogTime;
    datetime m_lastReuseLogTime;
    int m_snapshotReuseTtlSeconds;

public:
    CRegimeFaultTracker() :
        m_consecutiveDataFaults(0),
        m_lastFaultLogTime(0),
        m_lastReuseLogTime(0),
        m_snapshotReuseTtlSeconds(60)
    {
    }

    void SetSnapshotReuseTtlSeconds(const int seconds)
    {
        m_snapshotReuseTtlSeconds = MathMax(10, seconds);
    }

    //--- Cleared together on symbol / timeframe switches
    void ResetFaultState()
    {
        m_consecutiveDataFaults = 0;
        m_lastReuseLogTime = 0;
    }

    void ClearDataFaults()
    {
        m_consecutiveDataFaults = 0;
    }

    int GetConsecutiveDataFaults() const { return m_consecutiveDataFaults; }

    int GetSnapshotReuseWindowSeconds(const ENUM_TIMEFRAMES timeframe) const
    {
        int barSeconds = PeriodSeconds(timeframe);
        if(barSeconds <= 0)
            barSeconds = 60;

        // Allow reuse for up to 3 bars, with minimum 60 seconds and maximum 1 hour
        int boundedBarWindow = MathMax(60, MathMin(3600, barSeconds * 3));
        return MathMin(boundedBarWindow, MathMax(10, m_snapshotReuseTtlSeconds));
    }

    //--- Throttled generic fault line
    void LogFault(const string tag, const int errorCode, const string contextSymbol, const ENUM_TIMEFRAMES contextTimeframe);

    bool RegisterDataFault(const string tag,
                           const int errorCode,
                           const string contextSymbol,
                           const ENUM_TIMEFRAMES contextTimeframe);

    //--- Throttled fallback-rates notice
    void LogFallbackRates(const string symbol,
                          const ENUM_TIMEFRAMES timeframe,
                          const double atrValue,
                          const double bbWidth,
                          const datetime now);

    //--- Reuse the last valid snapshot when it is still representative
    bool TryReuseRecentSnapshot(SRegimeSnapshot &snapshot,
                                const string contextSymbol,
                                const ENUM_TIMEFRAMES contextTimeframe,
                                const string symbol,
                                const ENUM_TIMEFRAMES timeframe,
                                const string reasonTag,
                                const int errorCode,
                                const SRegimeConfig &config);
};

void CRegimeFaultTracker::LogFault(const string tag, const int errorCode, const string contextSymbol, const ENUM_TIMEFRAMES contextTimeframe)
{
    datetime nowTime = TimeCurrent();
    if((nowTime - m_lastFaultLogTime) < 30)
        return;

    PrintFormat("[REGIME-STATE] %s | symbol=%s | timeframe=%s | err=%d",
                tag, contextSymbol, EnumToString(contextTimeframe), errorCode);
    m_lastFaultLogTime = nowTime;
}

// Count a data fault and report whether handles must be recycled
bool CRegimeFaultTracker::RegisterDataFault(const string tag,
                                            const int errorCode,
                                            const string contextSymbol,
                                            const ENUM_TIMEFRAMES contextTimeframe)
{
    m_consecutiveDataFaults++;
    LogFault(tag, errorCode, contextSymbol, contextTimeframe);

    return (m_consecutiveDataFaults >= 3);
}

void CRegimeFaultTracker::LogFallbackRates(const string symbol,
                                           const ENUM_TIMEFRAMES timeframe,
                                           const double atrValue,
                                           const double bbWidth,
                                           const datetime now)
{
    if(m_lastFaultLogTime == 0 || (now - m_lastFaultLogTime) >= 30)
    {
        PrintFormat("[REGIME-STATE] FALLBACK_RATES | symbol=%s | timeframe=%s | atr=%.5f | bb_width=%.5f",
                    symbol,
                    EnumToString(timeframe),
                    atrValue,
                    bbWidth);
        m_lastFaultLogTime = now;
    }
}

bool CRegimeFaultTracker::TryReuseRecentSnapshot(SRegimeSnapshot &snapshot,
                                                 const string contextSymbol,
                                                 const ENUM_TIMEFRAMES contextTimeframe,
                                                 const string symbol,
                                                 const ENUM_TIMEFRAMES timeframe,
                                                 const string reasonTag,
                                                 const int errorCode,
                                                 const SRegimeConfig &config)
{
    if(!snapshot.valid || contextSymbol != symbol || contextTimeframe != timeframe || snapshot.timestamp <= 0)
        return false;

    int snapshotAgeSeconds = (int)MathMax(0, TimeCurrent() - snapshot.timestamp);
    if(snapshotAgeSeconds > GetSnapshotReuseWindowSeconds(timeframe))
        return false;

    // Validate regime state consistency before reusing snapshot
    // Estimate current regime state from fallback indicators
    double atrValue = 0.0, bbUpperValue = 0.0, bbLowerValue = 0.0;
    ENUM_REGIME_STATE currentRegimeState = REGIME_TREND;
    if(CRegimeVolatility::BuildFallbackIndicators(symbol, timeframe, config, atrValue, bbUpperValue, bbLowerValue))
    {
        currentRegimeState = CRegimeComposite::EstimateRegimeStateFromFallback(symbol, atrValue, bbUpperValue, bbLowerValue, config);

        // Invalidate snapshot if regime state differs
        if(currentRegimeState != snapshot.state)
        {
            PrintFormat("[REGIME-STATE] REUSE_INVALIDATED | symbol=%s | timeframe=%s | snapshot_state=%s | current_state=%s | reason=%s",
                        symbol,
                        EnumToString(timeframe),
                        CRegimeComposite::RegimeToString(snapshot.state),
                        CRegimeComposite::RegimeToString(currentRegimeState),
                        reasonTag);
            return false;
        }
    }
    // If fallback fails, allow time-based reuse (conservative approach)

    datetime nowTime = TimeCurrent();
    if(m_lastReuseLogTime == 0 || (nowTime - m_lastReuseLogTime) >= 30)
    {
        PrintFormat("[REGIME-STATE] REUSE_LAST_VALID | symbol=%s | timeframe=%s | reason=%s | age=%ds | err=%d",
                    symbol,
                    EnumToString(timeframe),
                    reasonTag,
                    snapshotAgeSeconds,
                    errorCode);
        m_lastReuseLogTime = nowTime;
    }

    snapshot.reuseActive = true;
    snapshot.stalenessSeconds = snapshotAgeSeconds;
    snapshot.readinessClass = "REUSED_SNAPSHOT";

    return true;
}

#endif // REGIME_FAULT_MQH

