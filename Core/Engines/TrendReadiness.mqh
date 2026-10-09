// TrendReadiness.mqh - Readiness state + last-good-trend reuse
// Extracted verbatim from TrendEngine.mqh (no behavior change)
#property copyright "Enterprise Trading Solutions"
#property version   "2.0"
#property strict

#ifndef TREND_READINESS_MQH
#define TREND_READINESS_MQH

#include "TrendTypes.mqh"
#include "../Signals/SignalDiagnostics.mqh"

// Save/restore bundle used by CTrendEngine::AnalyzeTrend so that a
// nested UpdateTrend() call cannot leak readiness/reuse state.
struct STrendReadinessRestorePoint
{
    STrendReadinessSnapshot snapshot;
    TrendState              lastGoodTrend;
    bool                    hasLastGoodTrend;
    datetime                lastGoodTrendTime;

    STrendReadinessRestorePoint() :
        hasLastGoodTrend(false),
        lastGoodTrendTime(0)
    {
    }
};

// Owns the readiness snapshot, the readiness fault counters and
// the last-good-trend reuse cache previously held by CTrendEngine.
class CTrendReadiness
{
private:
    STrendReadinessSnapshot m_snapshot;
    TrendState m_lastGoodTrend;
    bool       m_hasLastGoodTrend;
    datetime   m_lastGoodTrendTime;
    datetime   m_lastReuseLogTime;
    int        m_reuseTtlSeconds;
    int        m_consecutiveFaults;
    int        m_failureReinitThreshold;
    datetime   m_lastReinitAttemptTime;

public:
    CTrendReadiness();

    //--- Readiness snapshot.
    void SetState(const ENUM_TREND_READINESS_STATE state,
                  const string reasonTag,
                  const bool reuseActive,
                  const int stalenessSeconds);
    STrendReadinessSnapshot GetSnapshot() const { return m_snapshot; }

    //--- Reuse window configuration.
    void SetReuseTtlSeconds(const int seconds) { m_reuseTtlSeconds = MathMax(10, seconds); }
    int  GetReuseWindowSeconds(ENUM_TIMEFRAMES timeframe) const;

    //--- Last-good-trend cache.
    bool TryReuseLastGoodTrend(const string symbol,
                               ENUM_TIMEFRAMES timeframe,
                               const string reasonTag,
                               const string indicatorSymbol,
                               ENUM_TIMEFRAMES indicatorTimeframe,
                               TrendState &currentTrend);
    void RecordGoodTrend(const TrendState &trend);

    //--- Readiness fault accounting.
    int  GetConsecutiveFaults() const { return m_consecutiveFaults; }
    void ClearConsecutiveFaults() { m_consecutiveFaults = 0; }
    void RecordFault(const string symbol,
                     ENUM_TIMEFRAMES timeframe,
                     int chartBars,
                     int fastBars,
                     int medBars,
                     int slowBars,
                     int adxBars,
                     int atrBars,
                     int minBars,
                     datetime &lastIndicatorErrorLog,
                     CSignalDiagnostics* diagnostics);
    bool ShouldReinitializeIndicatorSet();

    //--- Nested-analysis state protection.
    STrendReadinessRestorePoint Capture() const;
    void Restore(const STrendReadinessRestorePoint &point);

    //--- Mirrors exactly the readiness subset of CTrendEngine::Reset().
    void ResetReadinessState();
};

// Constructor - mirrors original CTrendEngine defaults
CTrendReadiness::CTrendReadiness() :
    m_hasLastGoodTrend(false),
    m_lastGoodTrendTime(0),
    m_lastReuseLogTime(0),
    m_reuseTtlSeconds(60),
    m_consecutiveFaults(0),
    m_failureReinitThreshold(3),
    m_lastReinitAttemptTime(0)
{
}

void CTrendReadiness::SetState(const ENUM_TREND_READINESS_STATE state,
                               const string reasonTag,
                               const bool reuseActive,
                               const int stalenessSeconds)
{
    m_snapshot.state = state;
    m_snapshot.reasonTag = reasonTag;
    m_snapshot.reuseActive = reuseActive;
    m_snapshot.stalenessSeconds = MathMax(0, stalenessSeconds);
    if(m_hasLastGoodTrend)
        m_snapshot.lastGoodTime = m_lastGoodTrendTime;
}

int CTrendReadiness::GetReuseWindowSeconds(ENUM_TIMEFRAMES timeframe) const
{
    int barSeconds = PeriodSeconds(timeframe);
    if(barSeconds <= 0)
        barSeconds = 60;
    return MathMin(MathMax(10, m_reuseTtlSeconds), MathMax(10, barSeconds));
}

bool CTrendReadiness::TryReuseLastGoodTrend(const string symbol,
                                            ENUM_TIMEFRAMES timeframe,
                                            const string reasonTag,
                                            const string indicatorSymbol,
                                            ENUM_TIMEFRAMES indicatorTimeframe,
                                            TrendState &currentTrend)
{
    if(!m_hasLastGoodTrend || m_lastGoodTrendTime <= 0)
        return false;

    // AUDIT FIX: Validate symbol/timeframe context before reusing last good trend
    if(indicatorSymbol != symbol || indicatorTimeframe != timeframe)
    {
        // Cannot reuse trend from different symbol/timeframe context
        return false;
    }

    int stalenessSeconds = (int)MathMax(0, TimeCurrent() - m_lastGoodTrendTime);
    if(stalenessSeconds > GetReuseWindowSeconds(timeframe))
        return false;

    currentTrend = m_lastGoodTrend;
    currentTrend.lastUpdate = TimeCurrent();
    SetState(TREND_READINESS_REUSED_SNAPSHOT, reasonTag, true, stalenessSeconds);

    datetime nowTime = TimeCurrent();
    if(m_lastReuseLogTime == 0 || (nowTime - m_lastReuseLogTime) >= 30)
    {
        PrintFormat("[READINESS-STATE] TrendEngine reuse | symbol=%s | timeframe=%s | reason=%s | age=%d",
                    symbol,
                    EnumToString(timeframe),
                    reasonTag,
                    stalenessSeconds);
        m_lastReuseLogTime = nowTime;
    }

    return true;
}

// Record a healthy trend as the new reuse baseline
void CTrendReadiness::RecordGoodTrend(const TrendState &trend)
{
    m_lastGoodTrend = trend;
    m_hasLastGoodTrend = true;
    m_lastGoodTrendTime = trend.lastUpdate;
    m_consecutiveFaults = 0;
}

void CTrendReadiness::RecordFault(const string symbol,
                                  ENUM_TIMEFRAMES timeframe,
                                  int chartBars,
                                  int fastBars,
                                  int medBars,
                                  int slowBars,
                                  int adxBars,
                                  int atrBars,
                                  int minBars,
                                  datetime &lastIndicatorErrorLog,
                                  CSignalDiagnostics* diagnostics)
{
    m_consecutiveFaults++;

    datetime nowTime = TimeCurrent();
    if((nowTime - lastIndicatorErrorLog) >= 30)
    {
        PrintFormat("[TrendEngine][READINESS-FAULT] %s %s | Bars=%d MAf=%d MAm=%d MAs=%d ADX=%d ATR=%d need=%d | consecutive=%d",
                    symbol,
                    EnumToString(timeframe),
                    chartBars,
                    fastBars,
                    medBars,
                    slowBars,
                    adxBars,
                    atrBars,
                    minBars,
                    m_consecutiveFaults);

        if(diagnostics != NULL)
        {
            diagnostics.LogStrategyError("TrendEngine",
                                         "INDICATOR_READINESS_FAULT",
                                         StringFormat("Readiness fault for %s %s | bars=%d fast=%d med=%d slow=%d adx=%d atr=%d need=%d consecutive=%d",
                                                      symbol,
                                                      EnumToString(timeframe),
                                                      chartBars,
                                                      fastBars,
                                                      medBars,
                                                      slowBars,
                                                      adxBars,
                                                      atrBars,
                                                      minBars,
                                                      m_consecutiveFaults));
        }

        lastIndicatorErrorLog = nowTime;
    }
}

// Guard for indicator-set reinitialization (threshold + throttle)
bool CTrendReadiness::ShouldReinitializeIndicatorSet()
{
    if(m_consecutiveFaults < m_failureReinitThreshold)
        return false;

    datetime nowTime = TimeCurrent();
    if(m_lastReinitAttemptTime != 0 && (nowTime - m_lastReinitAttemptTime) < 30)
        return false;
    m_lastReinitAttemptTime = nowTime;

    return true;
}

// Capture readiness + reuse state
STrendReadinessRestorePoint CTrendReadiness::Capture() const
{
    STrendReadinessRestorePoint point;
    point.snapshot = m_snapshot;
    point.lastGoodTrend = m_lastGoodTrend;
    point.hasLastGoodTrend = m_hasLastGoodTrend;
    point.lastGoodTrendTime = m_lastGoodTrendTime;
    return point;
}

// Restore readiness + reuse state
void CTrendReadiness::Restore(const STrendReadinessRestorePoint &point)
{
    m_snapshot = point.snapshot;
    m_lastGoodTrend = point.lastGoodTrend;
    m_hasLastGoodTrend = point.hasLastGoodTrend;
    m_lastGoodTrendTime = point.lastGoodTrendTime;
}

// Reset - mirrors exactly the readiness subset of Reset()
// (deliberately does NOT touch the reuse TTL or the reinit
// threshold, matching the original implementation).
void CTrendReadiness::ResetReadinessState()
{
    m_consecutiveFaults = 0;
    m_lastReinitAttemptTime = 0;
    m_snapshot = STrendReadinessSnapshot();
    m_lastGoodTrend = TrendState();
    m_hasLastGoodTrend = false;
    m_lastGoodTrendTime = 0;
    m_lastReuseLogTime = 0;
}

#endif // TREND_READINESS_MQH
