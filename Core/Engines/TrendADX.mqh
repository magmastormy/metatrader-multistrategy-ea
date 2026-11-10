// TrendADX.mqh - ADX acquisition, validation and health tracking
// Extracted verbatim from TrendEngine.mqh (no behavior change)
#property copyright "Enterprise Trading Solutions"
#property version   "2.0"
#property strict

#ifndef TREND_ADX_MQH
#define TREND_ADX_MQH

#include "../Utils/Instruments.mqh"
#include "../Signals/SignalDiagnostics.mqh"

// Owns the whole ADX health/cache state machine that used to live
// inside CTrendEngine: failure counters, corruption counters,
// last-good value cache and handle reinitialization throttling.
// The ADX indicator handle itself remains owned by CTrendEngine
// and is passed in by reference so reinit can replace it in place.
class CTrendAdxHealth
{
private:
    bool     m_lastAdxValid;
    int      m_consecutiveAdxFailures;
    double   m_lastAdxRawValue;
    int      m_adxFailureReinitThreshold;
    datetime m_lastAdxHealthLogTime;
    datetime m_lastAdxReinitAttemptTime;
    bool     m_adxReinitPending;
    datetime m_lastGoodAdxTime;
    double   m_lastGoodAdxValue;
    double   m_lastGoodPlusDI;
    double   m_lastGoodMinusDI;
    int      m_adxCacheReuseTtlSeconds;
    int      m_consecutiveAdxCorruptions;
    int      m_adxCorruptionReinitThreshold;
    datetime m_lastAdxCorruptionReinitTime;

public:
    CTrendAdxHealth();

    //--- Model selection / domain validation (pure).
    static bool UsesAdxTrendModel(const string symbol);
    static bool IsValidAdxDomainValue(const double value);

    //--- Deferred reinit handshake (L4-008).
    bool IsReinitPending() const { return m_adxReinitPending; }
    bool TryCompleteReinit(const string symbol,
                           ENUM_TIMEFRAMES timeframe,
                           const int handleADX,
                           const int minBars);

    //--- Health accounting.
    void RecordFailure(const string symbol,
                       ENUM_TIMEFRAMES timeframe,
                       const string reasonTag,
                       int adxCopyRet,
                       int plusCopyRet,
                       int minusCopyRet,
                       int lastErrorCode,
                       double rawAdxValue,
                       int &handleADX,
                       const int adxPeriod,
                       CSignalDiagnostics* diagnostics);

    void MaybeReinitializeHandle(const string symbol,
                                 ENUM_TIMEFRAMES timeframe,
                                 int &handleADX,
                                 const int adxPeriod,
                                 CSignalDiagnostics* diagnostics);

    //--- Full ADX read path (copy + retry + cache reuse + corruption handling).
    //--- Returns the adxValid flag; readinessTag is non-empty when the caller
    //--- must raise a TREND_READINESS_TRANSIENT_COPY_FAULT readiness state.
    bool Acquire(const string symbol,
                 ENUM_TIMEFRAMES timeframe,
                 int &handleADX,
                 const int adxPeriod,
                 CSignalDiagnostics* diagnostics,
                 double &adx[],
                 double &plusDI[],
                 double &minusDI[],
                 string &adxModeLabel,
                 string &readinessTag);

    //--- Mirrors exactly the ADX fields cleared by CTrendEngine::Reset().
    void ResetHealthState();
};

// Constructor - mirrors original CTrendEngine defaults
CTrendAdxHealth::CTrendAdxHealth() :
    m_lastAdxValid(true),
    m_consecutiveAdxFailures(0),
    m_lastAdxRawValue(0.0),
    m_adxFailureReinitThreshold(7),
    m_lastAdxHealthLogTime(0),
    m_lastAdxReinitAttemptTime(0),
    m_adxReinitPending(false),
    m_lastGoodAdxTime(0),
    m_lastGoodAdxValue(0.0),
    m_lastGoodPlusDI(0.0),
    m_lastGoodMinusDI(0.0),
    m_adxCacheReuseTtlSeconds(60),
    m_consecutiveAdxCorruptions(0),
    m_adxCorruptionReinitThreshold(5),
    m_lastAdxCorruptionReinitTime(0)
{
}

bool CTrendAdxHealth::UsesAdxTrendModel(const string symbol)
{
    return !IsSyntheticIndexSymbolName(symbol);
}

bool CTrendAdxHealth::IsValidAdxDomainValue(const double value)
{
    return (MathIsValidNumber(value) && value >= 0.0 && value <= 100.0);
}

// Complete a pending ADX handle reinit once the new handle is warm
bool CTrendAdxHealth::TryCompleteReinit(const string symbol,
                                        ENUM_TIMEFRAMES timeframe,
                                        const int handleADX,
                                        const int minBars)
{
    int adxBars = BarsCalculated(handleADX);
    if(adxBars < minBars * 2)
    {
        return false;
    }

    // New handle is ready, clear pending flag and reset failure counter
    m_adxReinitPending = false;
    m_consecutiveAdxFailures = 0;
    PrintFormat("[TrendEngine][ADX-HEALTH] ADX reinit complete for %s %s, %d bars calculated",
                symbol, EnumToString(timeframe), adxBars);
    return true;
}

void CTrendAdxHealth::RecordFailure(const string symbol,
                                    ENUM_TIMEFRAMES timeframe,
                                    const string reasonTag,
                                    int adxCopyRet,
                                    int plusCopyRet,
                                    int minusCopyRet,
                                    int lastErrorCode,
                                    double rawAdxValue,
                                    int &handleADX,
                                    const int adxPeriod,
                                    CSignalDiagnostics* diagnostics)
{
    m_lastAdxValid = false;
    m_lastAdxRawValue = rawAdxValue;
    m_consecutiveAdxFailures++;

    datetime nowTime = TimeCurrent();
    if((nowTime - m_lastAdxHealthLogTime) >= 30)
    {
        int chartBars = Bars(symbol, timeframe);
        int adxBars = (handleADX != INVALID_HANDLE) ? BarsCalculated(handleADX) : -1;
        PrintFormat("[TrendEngine][ADX-HEALTH] %s | symbol=%s | timeframe=%s | copyRet=%d/%d/%d | err=%d | Bars=%d | BarsCalculated=%d | raw_adx=%.6f | consecutive_failures=%d",
                    reasonTag,
                    symbol,
                    EnumToString(timeframe),
                    adxCopyRet,
                    plusCopyRet,
                    minusCopyRet,
                    lastErrorCode,
                    chartBars,
                    adxBars,
                    rawAdxValue,
                    m_consecutiveAdxFailures);

        if(diagnostics != NULL)
        {
            diagnostics.LogStrategyError("TrendEngine",
                                         reasonTag,
                                         StringFormat("ADX health fault for %s %s | copy=%d/%d/%d err=%d bars=%d calc=%d raw=%.6f consecutive=%d",
                                                      symbol,
                                                      EnumToString(timeframe),
                                                      adxCopyRet,
                                                      plusCopyRet,
                                                      minusCopyRet,
                                                      lastErrorCode,
                                                      chartBars,
                                                      adxBars,
                                                      rawAdxValue,
                                                      m_consecutiveAdxFailures));
        }

        m_lastAdxHealthLogTime = nowTime;
    }

    MaybeReinitializeHandle(symbol, timeframe, handleADX, adxPeriod, diagnostics);
}

void CTrendAdxHealth::MaybeReinitializeHandle(const string symbol,
                                              ENUM_TIMEFRAMES timeframe,
                                              int &handleADX,
                                              const int adxPeriod,
                                              CSignalDiagnostics* diagnostics)
{
    if(m_consecutiveAdxFailures < m_adxFailureReinitThreshold)
        return;

    datetime nowTime = TimeCurrent();
    if(m_lastAdxReinitAttemptTime != 0 && (nowTime - m_lastAdxReinitAttemptTime) < 30)
        return;
    m_lastAdxReinitAttemptTime = nowTime;

    // L4-008: Set reinit pending flag instead of immediate reinit to avoid race condition
    m_adxReinitPending = true;
    
    // Release old handle immediately
    if(handleADX != INVALID_HANDLE)
    {
        IndicatorRelease(handleADX);
        handleADX = INVALID_HANDLE;
    }

    handleADX = iADX(symbol, timeframe, adxPeriod);
    if(handleADX == INVALID_HANDLE)
    {
        int err = GetLastError();
        m_adxReinitPending = false; // Clear flag on failure
        if(diagnostics != NULL)
        {
            diagnostics.LogStrategyError("TrendEngine", "ADX_REINIT_FAILED",
                                         StringFormat("ADX handle reinit failed for %s %s (err=%d)",
                                                      symbol, EnumToString(timeframe), err));
        }
        return;
    }

    PrintFormat("[TrendEngine][ADX-HEALTH] ADX handle reinitialized for %s %s after %d consecutive failures",
                symbol, EnumToString(timeframe), m_consecutiveAdxFailures);
    // Note: m_consecutiveAdxFailures reset after new handle is validated in IndicatorsReadyForRead
}

// Acquire ADX / +DI / -DI values with retry, cache and corruption
// handling. Logic transcribed verbatim from CTrendEngine::UpdateTrend
bool CTrendAdxHealth::Acquire(const string symbol,
                              ENUM_TIMEFRAMES timeframe,
                              int &handleADX,
                              const int adxPeriod,
                              CSignalDiagnostics* diagnostics,
                              double &adx[],
                              double &plusDI[],
                              double &minusDI[],
                              string &adxModeLabel,
                              string &readinessTag)
{
    // Entry state mirrors the original inline block: adxValid starts false
    // (because useAdxModel is true) and the label starts at "VALID".
    bool adxValid = false;
    adxModeLabel = "VALID";
    readinessTag = "";

    ResetLastError();
    int adxCopyRet = CopyBuffer(handleADX, 0, 0, 1, adx);
    int plusCopyRet = CopyBuffer(handleADX, 1, 0, 1, plusDI);
    int minusCopyRet = CopyBuffer(handleADX, 2, 0, 1, minusDI);
    int adxCopyErr = GetLastError();
    if(adxCopyRet != 1 || plusCopyRet != 1 || minusCopyRet != 1)
    {
        // Single retry without blocking delay — if copy still fails, mark invalid and retry next tick
        ResetLastError();
        adxCopyRet = CopyBuffer(handleADX, 0, 0, 1, adx);
        plusCopyRet = CopyBuffer(handleADX, 1, 0, 1, plusDI);
        minusCopyRet = CopyBuffer(handleADX, 2, 0, 1, minusDI);
        adxCopyErr = GetLastError();
    }
    if(adxCopyRet != 1 || plusCopyRet != 1 || minusCopyRet != 1)
    {
        adxValid = false;
        // Attempt cached ADX reuse before recording failure
        datetime adxNowTime = TimeCurrent();
        if(m_lastGoodAdxTime != 0 && (int)(adxNowTime - m_lastGoodAdxTime) <= m_adxCacheReuseTtlSeconds)
        {
            adx[0] = m_lastGoodAdxValue;
            plusDI[0] = m_lastGoodPlusDI;
            minusDI[0] = m_lastGoodMinusDI;
            adxValid = true;
            adxModeLabel = "CACHED-REUSE";
            PrintFormat("[ADX-CACHED-REUSE] symbol=%s | timeframe=%s | adx=%.2f | plusDI=%.2f | minusDI=%.2f | age=%ds | copyErr=%d",
                        symbol, EnumToString(timeframe),
                        m_lastGoodAdxValue, m_lastGoodPlusDI, m_lastGoodMinusDI,
                        (int)(adxNowTime - m_lastGoodAdxTime), adxCopyErr);
            readinessTag = "ADX_CACHED_REUSE";
        }
        else
        {
            RecordFailure(symbol,
                          timeframe,
                          "ADX_BUFFER_COPY_FAILED",
                          adxCopyRet,
                          plusCopyRet,
                          minusCopyRet,
                          adxCopyErr,
                          adx[0],
                          handleADX,
                          adxPeriod,
                          diagnostics);
        }
    }
    else
    {
        m_lastAdxRawValue = adx[0];
        if(!IsValidAdxDomainValue(adx[0]) ||
           !IsValidAdxDomainValue(plusDI[0]) ||
           !IsValidAdxDomainValue(minusDI[0]))
        {
            adxValid = false;
            m_consecutiveAdxCorruptions++;
            PrintFormat("[ADX-CORRUPT] symbol=%s | timeframe=%s | raw_adx=%.2f | raw_plus=%.2f | raw_minus=%.2f | corruption_count=%d",
                        symbol, EnumToString(timeframe),
                        adx[0], plusDI[0], minusDI[0],
                        m_consecutiveAdxCorruptions);
            RecordFailure(symbol,
                          timeframe,
                          "ADX_VALUE_OUT_OF_RANGE",
                          adxCopyRet,
                          plusCopyRet,
                          minusCopyRet,
                          0,
                          adx[0],
                          handleADX,
                          adxPeriod,
                          diagnostics);
            if(m_lastGoodAdxTime != 0 && m_lastGoodAdxValue > 0.0)
            {
                adx[0] = m_lastGoodAdxValue;
                plusDI[0] = m_lastGoodPlusDI;
                minusDI[0] = m_lastGoodMinusDI;
                adxValid = true;
                adxModeLabel = "CORRUPT-REUSE";
                PrintFormat("[ADX-CORRUPT] Reusing last good value | adx=%.2f | plus=%.2f | minus=%.2f | age=%ds",
                            m_lastGoodAdxValue, m_lastGoodPlusDI, m_lastGoodMinusDI,
                            (int)(TimeCurrent() - m_lastGoodAdxTime));
            }
            datetime adxNow = TimeCurrent();
            if(m_consecutiveAdxCorruptions >= m_adxCorruptionReinitThreshold &&
               (m_lastAdxCorruptionReinitTime == 0 || (adxNow - m_lastAdxCorruptionReinitTime) >= 60))
            {
                m_lastAdxCorruptionReinitTime = adxNow;
                if(handleADX != INVALID_HANDLE)
                {
                    IndicatorRelease(handleADX);
                    handleADX = INVALID_HANDLE;
                }
                handleADX = iADX(symbol, timeframe, adxPeriod);
                if(handleADX != INVALID_HANDLE)
                {
                    PrintFormat("[ADX-CORRUPT] Handle recreated for %s %s after %d consecutive corruptions",
                                symbol, EnumToString(timeframe), m_consecutiveAdxCorruptions);
                    m_consecutiveAdxCorruptions = 0;
                }
            }
        }
    }

    if(!adxValid)
    {
        adx[0] = 0.0;
        plusDI[0] = 0.0;
        minusDI[0] = 0.0;
        adxModeLabel = "DEGRADED";
    }
    else if(adxModeLabel != "CACHED-REUSE" && adxModeLabel != "CORRUPT-REUSE")
    {
        // Cache good ADX values for future reuse on copy failure
        m_lastGoodAdxTime = TimeCurrent();
        m_lastGoodAdxValue = adx[0];
        m_lastGoodPlusDI = plusDI[0];
        m_lastGoodMinusDI = minusDI[0];
        m_lastAdxValid = true;
        m_consecutiveAdxFailures = 0;
        m_consecutiveAdxCorruptions = 0;
    }

    return adxValid;
}

// Reset - mirrors exactly the ADX subset of CTrendEngine::Reset()
// (deliberately does NOT touch reinitPending / corruption counters
// / thresholds, matching the original implementation).
void CTrendAdxHealth::ResetHealthState()
{
    m_lastAdxValid = true;
    m_consecutiveAdxFailures = 0;
    m_lastAdxRawValue = 0.0;
    m_lastAdxHealthLogTime = 0;
    m_lastAdxReinitAttemptTime = 0;
    m_lastGoodAdxTime = 0;
    m_lastGoodAdxValue = 0.0;
    m_lastGoodPlusDI = 0.0;
    m_lastGoodMinusDI = 0.0;
}

#endif // TREND_ADX_MQH
