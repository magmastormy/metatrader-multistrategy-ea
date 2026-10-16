// Unified trend analysis for all strategies. Coordinator only: the work lives in TrendTypes (value types),
// TrendMath (ATR/EMA fallbacks, momentum, angle), TrendStrength, TrendRegime, TrendMTF, TrendADX and
// TrendReadiness.
#property copyright "Enterprise Trading Solutions"
#property version   "2.0"
#property strict

#ifndef TREND_ENGINE_MQH
#define TREND_ENGINE_MQH

#include "../Utils/Enums.mqh"
#include "../Utils/Instruments.mqh"
#include "../Signals/SignalDiagnostics.mqh"

#include "TrendTypes.mqh"
#include "TrendMath.mqh"
#include "TrendStrength.mqh"
#include "TrendRegime.mqh"
#include "TrendMTF.mqh"
#include "TrendADX.mqh"
#include "TrendReadiness.mqh"

class CEnhancedErrorHandler;
class CUtilities;
class CMarketAnalysis;
class CNextGenStrategyBrain;
class CTransformerBrain;
struct SPredictionWithUncertainty;
class CPositionSizer;
class CTradeManager;
class CPerformanceAnalytics;

class CTrendEngine
{
private:
    int m_maPeriodFast;
    int m_maPeriodMedium;
    int m_maPeriodSlow;
    int m_adxPeriod;
    double m_trendThreshold;
    double m_strongTrendThreshold;
    
    TrendState m_currentTrend;
    MTFTrendState m_mtfTrend;
    
    int m_handleMAFast;
    int m_handleMAMedium;
    int m_handleMASlow;
    int m_handleADX;
    int m_handleATR;
    string m_indicatorSymbol;
    ENUM_TIMEFRAMES m_indicatorTimeframe;
    datetime m_lastIndicatorErrorLog;
    ENUM_TREND_TYPE m_lastLoggedTrendType;
    datetime m_lastTrendLogTime;

    // Extracted collaborators (owned by value)
    CTrendAdxHealth m_adxHealth;
    CTrendReadiness m_readiness;
    
    CSignalDiagnostics* m_diagnostics;
    
    bool InitializeIndicators(const string symbol, ENUM_TIMEFRAMES timeframe);
    bool IndicatorsReadyForRead(int minBars);
    void ReleaseIndicators();
    bool UsesAdxTrendModel(const string symbol) const;
    bool IsValidAdxDomainValue(const double value) const;
    void RecordAdxFailure(const string symbol,
                          ENUM_TIMEFRAMES timeframe,
                          const string reasonTag,
                          int adxCopyRet,
                          int plusCopyRet,
                          int minusCopyRet,
                          int lastErrorCode,
                          double rawAdxValue);
    void MaybeReinitializeAdxHandle(const string symbol, ENUM_TIMEFRAMES timeframe);
    void RecordReadinessFault(const string symbol,
                             ENUM_TIMEFRAMES timeframe,
                             int chartBars,
                             int fastBars,
                             int medBars,
                             int slowBars,
                             int adxBars,
                             int atrBars,
                             int minBars);
    void MaybeReinitializeIndicatorSet(const string symbol, ENUM_TIMEFRAMES timeframe);
    void SetReadinessState(const ENUM_TREND_READINESS_STATE state,
                           const string reasonTag,
                           const bool reuseActive,
                           const int stalenessSeconds);
    int GetReuseWindowSeconds(ENUM_TIMEFRAMES timeframe) const;
    bool TryReuseLastGoodTrend(const string symbol,
                               ENUM_TIMEFRAMES timeframe,
                               const string reasonTag);
    bool CalculateEmaFallbackSeries(const string symbol,
                                    ENUM_TIMEFRAMES timeframe,
                                    const int period,
                                    const int count,
                                    double &output[]) const;
    bool CopyOrFallbackMA(const string symbol,
                          ENUM_TIMEFRAMES timeframe,
                          const int handle,
                          const int period,
                          const string reasonTag,
                          double &output[],
                          bool &fallbackUsed);
    double CalculateMomentum(const string symbol, ENUM_TIMEFRAMES timeframe, int period);
    ENUM_TREND_TYPE DetermineTrendType(double strength, double angle, double adx);
    
public:
    CTrendEngine();
    ~CTrendEngine();
    
    double CalculateAtrFallback(const string symbol, ENUM_TIMEFRAMES timeframe, const int period) const;
    
    bool Initialize(int maFast = 20, int maMedium = 50, int maSlow = 200,
                   int adxPeriod = 14, CSignalDiagnostics* diagnostics = NULL);
    
    bool UpdateTrend(const string symbol, ENUM_TIMEFRAMES timeframe);
    bool UpdateMTFTrend(const string symbol, ENUM_TIMEFRAMES htf, 
                       ENUM_TIMEFRAMES mtf, ENUM_TIMEFRAMES ltf);
    
    ENUM_TREND_TYPE GetCurrentTrend() const { return m_currentTrend.type; }
    TrendState GetTrendState() const { return m_currentTrend; }
    MTFTrendState GetMTFTrendState() const { return m_mtfTrend; }
    double GetTrendStrength() const { return m_currentTrend.strength; }
    double GetTrendAngle() const { return m_currentTrend.angle; }
    double GetMomentum() const { return m_currentTrend.momentum; }
    STrendReadinessSnapshot GetReadinessSnapshot() const { return m_readiness.GetSnapshot(); }
    void SetReadinessReuseTtlSeconds(const int seconds) { m_readiness.SetReuseTtlSeconds(seconds); }
    
    bool IsTrendBullish() const;
    bool IsTrendBearish() const;
    bool IsStrongTrend() const;
    bool IsRanging() const;
    bool IsTrendAccelerating() const { return m_currentTrend.isAccelerating; }
    bool IsTrendDecelerating() const { return m_currentTrend.isDecelerating; }
    bool IsMTFAligned() const { return m_mtfTrend.isAligned; }
    double GetMTFAlignment() const { return m_mtfTrend.alignment; }
    
    bool ConfirmTrendContinuation(const string symbol, ENUM_TIMEFRAMES timeframe);
    bool DetectTrendReversal(const string symbol, ENUM_TIMEFRAMES timeframe);
    
    TrendState AnalyzeTrend(const string symbol, ENUM_TIMEFRAMES timeframe);
    double CalculateTrendStrength(double &ma_fast[], double &ma_medium[], double &ma_slow[], double adx);
    double CalculateTrendAngle(double &ma[], int period);
    
    void Reset();
};

CTrendEngine::CTrendEngine() :
    m_maPeriodFast(20),
    m_maPeriodMedium(50),
    m_maPeriodSlow(200),
    m_adxPeriod(14),
    m_trendThreshold(25.0),
    m_strongTrendThreshold(40.0),
    m_handleMAFast(INVALID_HANDLE),
    m_handleMAMedium(INVALID_HANDLE),
    m_handleMASlow(INVALID_HANDLE),
    m_handleADX(INVALID_HANDLE),
    m_handleATR(INVALID_HANDLE),
    m_indicatorSymbol(""),
    m_indicatorTimeframe(PERIOD_CURRENT),
    m_lastIndicatorErrorLog(0),
    m_lastLoggedTrendType(TREND_NONE),
    m_lastTrendLogTime(0),
    m_diagnostics(NULL)
{
}

CTrendEngine::~CTrendEngine()
{
    ReleaseIndicators();
}

bool CTrendEngine::Initialize(int maFast, int maMedium, int maSlow,
                             int adxPeriod, CSignalDiagnostics* diagnostics)
{
    m_maPeriodFast = maFast;
    m_maPeriodMedium = maMedium;
    m_maPeriodSlow = maSlow;
    m_adxPeriod = adxPeriod;
    m_diagnostics = diagnostics;
    
    Reset();
    
    if(m_diagnostics != NULL)
    {
        Print("[TrendEngine] Initialized | MA: ", maFast, "/", maMedium, "/", maSlow,
              " | ADX: ", adxPeriod);
    }
    
    return true;
}

bool CTrendEngine::InitializeIndicators(const string symbol, ENUM_TIMEFRAMES timeframe)
{
    // Resolve PERIOD_CURRENT to actual chart timeframe
    ENUM_TIMEFRAMES resolvedTimeframe = (timeframe == PERIOD_CURRENT || timeframe == 0) ? Period() : timeframe;
    
    bool useAdxModel = UsesAdxTrendModel(symbol);
    bool handlesReady = (m_handleMAFast != INVALID_HANDLE &&
                         m_handleMAMedium != INVALID_HANDLE &&
                         m_handleMASlow != INVALID_HANDLE &&
                         (!useAdxModel || m_handleADX != INVALID_HANDLE) &&
                         m_handleATR != INVALID_HANDLE);
    bool contextMatches = (m_indicatorSymbol == symbol && m_indicatorTimeframe == resolvedTimeframe);
    if(handlesReady && contextMatches)
        return true;

    // Context changed or handles missing - rebuild once.
        ReleaseIndicators();
        m_indicatorSymbol = symbol;
        m_indicatorTimeframe = resolvedTimeframe;
    
        m_handleMAFast = iMA(symbol, resolvedTimeframe, m_maPeriodFast, 0, MODE_EMA, PRICE_CLOSE);
        if(m_handleMAFast == INVALID_HANDLE)
        {
            if(m_diagnostics != NULL)
                m_diagnostics.LogStrategyError("TrendEngine", "MA_FAST_INIT_FAILED", 
                                              "Failed to create fast MA indicator");
            return false;
        }
    
        m_handleMAMedium = iMA(symbol, resolvedTimeframe, m_maPeriodMedium, 0, MODE_EMA, PRICE_CLOSE);
        if(m_handleMAMedium == INVALID_HANDLE)
        {
            ReleaseIndicators();
            if(m_diagnostics != NULL)
                m_diagnostics.LogStrategyError("TrendEngine", "MA_MEDIUM_INIT_FAILED",
                                              "Failed to create medium MA indicator");
            return false;
        }
    
        m_handleMASlow = iMA(symbol, resolvedTimeframe, m_maPeriodSlow, 0, MODE_EMA, PRICE_CLOSE);
        if(m_handleMASlow == INVALID_HANDLE)
        {
            ReleaseIndicators();
            if(m_diagnostics != NULL)
                m_diagnostics.LogStrategyError("TrendEngine", "MA_SLOW_INIT_FAILED",
                                              "Failed to create slow MA indicator");
            return false;
        }
    
        if(useAdxModel)
        {
            m_handleADX = iADX(symbol, resolvedTimeframe, m_adxPeriod);
            if(m_handleADX == INVALID_HANDLE)
            {
                ReleaseIndicators();
                if(m_diagnostics != NULL)
                    m_diagnostics.LogStrategyError("TrendEngine", "ADX_INIT_FAILED",
                                                  "Failed to create ADX indicator");
                return false;
            }
        }
        else
            m_handleADX = INVALID_HANDLE;
    
        m_handleATR = iATR(symbol, resolvedTimeframe, 14);
    if(m_handleATR == INVALID_HANDLE)
    {
        ReleaseIndicators();
        if(m_diagnostics != NULL)
            m_diagnostics.LogStrategyError("TrendEngine", "ATR_INIT_FAILED",
                                          "Failed to create ATR indicator");
        return false;
    }

    m_readiness.ClearConsecutiveFaults();
    
    return true;
}

bool CTrendEngine::IndicatorsReadyForRead(int minBars)
{
    bool useAdxModel = UsesAdxTrendModel(m_indicatorSymbol);
    
    if(useAdxModel && m_adxHealth.IsReinitPending())
    {
        if(!m_adxHealth.TryCompleteReinit(m_indicatorSymbol, m_indicatorTimeframe, m_handleADX, minBars))
        {
            // Still waiting for new handle to populate
            SetReadinessState(TREND_READINESS_WARMUP, "ADX_REINIT_WARMUP", false, 0);
            return false;
        }
    }
    
    if(m_handleMAFast == INVALID_HANDLE ||
       m_handleMAMedium == INVALID_HANDLE ||
       m_handleMASlow == INVALID_HANDLE ||
       (useAdxModel && m_handleADX == INVALID_HANDLE) ||
       m_handleATR == INVALID_HANDLE)
    {
        datetime nowTime = TimeCurrent();
        if((nowTime - m_lastIndicatorErrorLog) >= 30)
        {
            PrintFormat("[TrendEngine] Indicator handles invalid for %s %s | MAf=%d MAm=%d MAs=%d ADX=%d ATR=%d",
                        m_indicatorSymbol, EnumToString(m_indicatorTimeframe),
                        m_handleMAFast, m_handleMAMedium, m_handleMASlow, m_handleADX, m_handleATR);
            m_lastIndicatorErrorLog = nowTime;
        }
        SetReadinessState(TREND_READINESS_HANDLE_FAULT, "HANDLE_FAULT", false, 0);
        RecordReadinessFault(m_indicatorSymbol,
                             m_indicatorTimeframe,
                             0,
                             0,
                             0,
                             0,
                             0,
                             0,
                             minBars);
        return false;
    }

    int chartBars = Bars(m_indicatorSymbol, m_indicatorTimeframe);
    int fastBars = BarsCalculated(m_handleMAFast);
    int medBars = BarsCalculated(m_handleMAMedium);
    int slowBars = BarsCalculated(m_handleMASlow);
    int adxBars = useAdxModel ? BarsCalculated(m_handleADX) : -2;
    int atrBars = BarsCalculated(m_handleATR);

    if(chartBars < minBars)
    {
        datetime nowTime = TimeCurrent();
        if((nowTime - m_lastIndicatorErrorLog) >= 60)
        {
            PrintFormat("[TrendEngine] Indicators warming up for %s %s | Bars=%d MAf=%d MAm=%d MAs=%d ADX=%d ATR=%d need=%d",
                        m_indicatorSymbol, EnumToString(m_indicatorTimeframe),
                        chartBars, fastBars, medBars, slowBars, adxBars, atrBars, minBars);
            m_lastIndicatorErrorLog = nowTime;
        }
        SetReadinessState(TREND_READINESS_WARMUP, "WARMUP", false, 0);
        return false;
    }

    bool partialReady = (fastBars < minBars || medBars < minBars || slowBars < minBars ||
                         (useAdxModel && adxBars < minBars * 2) || atrBars < minBars);
    if(partialReady)
    {
        datetime nowTime = TimeCurrent();
        if((nowTime - m_lastIndicatorErrorLog) >= 30)
        {
            int logAdxBars = useAdxModel ? adxBars : -1; // Show -1 for disabled instead of -2 sentinel
            PrintFormat("[READINESS-STATE] TrendEngine partial readiness | symbol=%s | timeframe=%s | Bars=%d | MAf=%d | MAm=%d | MAs=%d | ADX=%d | ATR=%d | need=%d",
                        m_indicatorSymbol,
                        EnumToString(m_indicatorTimeframe),
                        chartBars,
                        fastBars,
                        medBars,
                        slowBars,
                        logAdxBars,
                        atrBars,
                        minBars);
            m_lastIndicatorErrorLog = nowTime;
        }
        SetReadinessState(TREND_READINESS_TRANSIENT_COPY_FAULT, "PARTIAL_READY", false, 0);
        RecordReadinessFault(m_indicatorSymbol,
                             m_indicatorTimeframe,
                             chartBars,
                             fastBars,
                             medBars,
                             slowBars,
                             adxBars,
                             atrBars,
                             minBars);
        // Do not hard-fail on BarsCalculated gaps when the underlying series is mature.
        // UpdateTrend has bounded MA/ATR fallbacks and reuse logic; allow it to attempt recovery.
        return true;
    }
    else
        SetReadinessState(TREND_READINESS_HEALTHY, "HEALTHY", false, 0);
    return true;
}

bool CTrendEngine::UsesAdxTrendModel(const string symbol) const
{
    return CTrendAdxHealth::UsesAdxTrendModel(symbol);
}

bool CTrendEngine::IsValidAdxDomainValue(const double value) const
{
    return CTrendAdxHealth::IsValidAdxDomainValue(value);
}

void CTrendEngine::RecordAdxFailure(const string symbol,
                                    ENUM_TIMEFRAMES timeframe,
                                    const string reasonTag,
                                    int adxCopyRet,
                                    int plusCopyRet,
                                    int minusCopyRet,
                                    int lastErrorCode,
                                    double rawAdxValue)
{
    m_adxHealth.RecordFailure(symbol, timeframe, reasonTag, adxCopyRet, plusCopyRet, minusCopyRet,
                              lastErrorCode, rawAdxValue, m_handleADX, m_adxPeriod, m_diagnostics);
}

void CTrendEngine::MaybeReinitializeAdxHandle(const string symbol, ENUM_TIMEFRAMES timeframe)
{
    m_adxHealth.MaybeReinitializeHandle(symbol, timeframe, m_handleADX, m_adxPeriod, m_diagnostics);
}

//--- Forwarder: see CTrendReadiness::RecordFault (reinit escalation kept here
//--- because it needs the engine-owned indicator lifecycle).
void CTrendEngine::RecordReadinessFault(const string symbol,
                                        ENUM_TIMEFRAMES timeframe,
                                        int chartBars,
                                        int fastBars,
                                        int medBars,
                                        int slowBars,
                                        int adxBars,
                                        int atrBars,
                                        int minBars)
{
    m_readiness.RecordFault(symbol, timeframe, chartBars, fastBars, medBars, slowBars,
                            adxBars, atrBars, minBars, m_lastIndicatorErrorLog, m_diagnostics);

    MaybeReinitializeIndicatorSet(symbol, timeframe);
}

void CTrendEngine::MaybeReinitializeIndicatorSet(const string symbol, ENUM_TIMEFRAMES timeframe)
{
    int faultsBeforeReset = m_readiness.GetConsecutiveFaults();
    if(!m_readiness.ShouldReinitializeIndicatorSet())
        return;

    ReleaseIndicators();
    if(!InitializeIndicators(symbol, timeframe))
    {
        if(m_diagnostics != NULL)
        {
            m_diagnostics.LogStrategyError("TrendEngine",
                                           "INDICATOR_SET_REINIT_FAILED",
                                           StringFormat("Indicator set reinit failed for %s %s",
                                                        symbol,
                                                        EnumToString(timeframe)));
        }
        return;
    }

    PrintFormat("[TrendEngine][READINESS-FAULT] Indicator set reinitialized for %s %s after %d readiness faults",
                symbol,
                EnumToString(timeframe),
                faultsBeforeReset);
    m_readiness.ClearConsecutiveFaults();
}

void CTrendEngine::SetReadinessState(const ENUM_TREND_READINESS_STATE state,
                                     const string reasonTag,
                                     const bool reuseActive,
                                     const int stalenessSeconds)
{
    m_readiness.SetState(state, reasonTag, reuseActive, stalenessSeconds);
}

int CTrendEngine::GetReuseWindowSeconds(ENUM_TIMEFRAMES timeframe) const
{
    return m_readiness.GetReuseWindowSeconds(timeframe);
}

double CTrendEngine::CalculateAtrFallback(const string symbol,
                                          ENUM_TIMEFRAMES timeframe,
                                          const int period) const
{
    return CTrendMath::CalculateAtrFallback(symbol, timeframe, period);
}

bool CTrendEngine::CalculateEmaFallbackSeries(const string symbol,
                                              ENUM_TIMEFRAMES timeframe,
                                              const int period,
                                              const int count,
                                              double &output[]) const
{
    return CTrendMath::CalculateEmaFallbackSeries(symbol, timeframe, period, count, output);
}

bool CTrendEngine::CopyOrFallbackMA(const string symbol,
                                    ENUM_TIMEFRAMES timeframe,
                                    const int handle,
                                    const int period,
                                    const string reasonTag,
                                    double &output[],
                                    bool &fallbackUsed)
{
    ResetLastError();
    if(handle != INVALID_HANDLE && CopyBuffer(handle, 0, 0, 5, output) == 5)
        return true;

    if(CalculateEmaFallbackSeries(symbol, timeframe, period, 5, output))
    {
        fallbackUsed = true;
        SetReadinessState(TREND_READINESS_TRANSIENT_COPY_FAULT, reasonTag, false, 0);
        datetime nowTime = TimeCurrent();
        if((nowTime - m_lastIndicatorErrorLog) >= 30)
        {
            PrintFormat("[READINESS-STATE] TrendEngine MA fallback | symbol=%s | timeframe=%s | period=%d | reason=%s",
                        symbol,
                        EnumToString(timeframe),
                        period,
                        reasonTag);
            m_lastIndicatorErrorLog = nowTime;
        }
        return true;
    }

    return false;
}

bool CTrendEngine::TryReuseLastGoodTrend(const string symbol,
                                         ENUM_TIMEFRAMES timeframe,
                                         const string reasonTag)
{
    return m_readiness.TryReuseLastGoodTrend(symbol, timeframe, reasonTag,
                                             m_indicatorSymbol, m_indicatorTimeframe,
                                             m_currentTrend);
}

void CTrendEngine::ReleaseIndicators()
{
    if(m_handleMAFast != INVALID_HANDLE)
    {
        IndicatorRelease(m_handleMAFast);
        m_handleMAFast = INVALID_HANDLE;
    }
    
    if(m_handleMAMedium != INVALID_HANDLE)
    {
        IndicatorRelease(m_handleMAMedium);
        m_handleMAMedium = INVALID_HANDLE;
    }
    
    if(m_handleMASlow != INVALID_HANDLE)
    {
        IndicatorRelease(m_handleMASlow);
        m_handleMASlow = INVALID_HANDLE;
    }
    
    if(m_handleADX != INVALID_HANDLE)
    {
        IndicatorRelease(m_handleADX);
        m_handleADX = INVALID_HANDLE;
    }
    
    if(m_handleATR != INVALID_HANDLE)
    {
        IndicatorRelease(m_handleATR);
        m_handleATR = INVALID_HANDLE;
    }
}

bool CTrendEngine::UpdateTrend(const string symbol, ENUM_TIMEFRAMES timeframe)
{
    bool useAdxModel = UsesAdxTrendModel(symbol);
    if(!InitializeIndicators(symbol, timeframe))
        return false;

    int minBars = MathMax(m_maPeriodSlow + 5, m_adxPeriod + 5);
    if(!IndicatorsReadyForRead(minBars))
        return false;
    
    double ma_fast[5], ma_medium[5], ma_slow[5];
    double adx[1], plusDI[1], minusDI[1], atr[1];
    adx[0] = -1.0;
    plusDI[0] = -1.0;
    minusDI[0] = -1.0;
    atr[0] = 0.0;
    bool atrFallbackUsed = false;
    bool maFallbackUsed = false;
    
    if(!CopyOrFallbackMA(symbol, timeframe, m_handleMAFast, m_maPeriodFast, "MA_FAST_FALLBACK", ma_fast, maFallbackUsed) ||
       !CopyOrFallbackMA(symbol, timeframe, m_handleMAMedium, m_maPeriodMedium, "MA_MEDIUM_FALLBACK", ma_medium, maFallbackUsed) ||
       !CopyOrFallbackMA(symbol, timeframe, m_handleMASlow, m_maPeriodSlow, "MA_SLOW_FALLBACK", ma_slow, maFallbackUsed))
    {
        SetReadinessState(TREND_READINESS_TRANSIENT_COPY_FAULT, "MA_BUFFER_COPY_FAILED", false, 0);
        datetime nowTime = TimeCurrent();
        if(m_diagnostics != NULL && (nowTime - m_lastIndicatorErrorLog) >= 30)
        {
            int err = GetLastError();
            m_diagnostics.LogStrategyError("TrendEngine", "MA_BUFFER_COPY_FAILED",
                                          StringFormat("Failed to copy MA buffer data for %s %s (err=%d)",
                                                       symbol, EnumToString(timeframe), err));
            m_lastIndicatorErrorLog = nowTime;
        }
        return TryReuseLastGoodTrend(symbol, timeframe, "MA_BUFFER_COPY_FAILED");
    }
    
    bool adxValid = !useAdxModel;
    string adxModeLabel = useAdxModel ? "VALID" : "BYPASSED";
    if(useAdxModel)
    {
        // Delegated to CTrendAdxHealth::Acquire (copy + retry + cache reuse +
        // corruption handling). Behavior is transcribed verbatim.
        string adxReadinessTag = "";
        adxValid = m_adxHealth.Acquire(symbol, timeframe, m_handleADX, m_adxPeriod, m_diagnostics,
                                       adx, plusDI, minusDI, adxModeLabel, adxReadinessTag);
        if(adxReadinessTag != "")
            SetReadinessState(TREND_READINESS_TRANSIENT_COPY_FAULT, adxReadinessTag, false, 0);
    }
    
    ResetLastError();
    if(CopyBuffer(m_handleATR, 0, 0, 1, atr) != 1)
    {
        int atrCopyErr = GetLastError();
        double atrFallback = CalculateAtrFallback(symbol, timeframe, 14);
        if(atrFallback > 0.0)
        {
            atr[0] = atrFallback;
            atrFallbackUsed = true;
            SetReadinessState(TREND_READINESS_TRANSIENT_COPY_FAULT, "ATR_MANUAL_FALLBACK", false, 0);
            datetime nowTime = TimeCurrent();
            if((nowTime - m_lastIndicatorErrorLog) >= 30)
            {
                PrintFormat("[READINESS-STATE] TrendEngine ATR fallback | symbol=%s | timeframe=%s | err=%d | atr=%.6f",
                            symbol,
                            EnumToString(timeframe),
                            atrCopyErr,
                            atrFallback);
                m_lastIndicatorErrorLog = nowTime;
            }
        }
        else
        {
            SetReadinessState(TREND_READINESS_TRANSIENT_COPY_FAULT, "ATR_BUFFER_COPY_FAILED", false, 0);
            datetime nowTime = TimeCurrent();
            if(m_diagnostics != NULL && (nowTime - m_lastIndicatorErrorLog) >= 30)
            {
                m_diagnostics.LogStrategyError("TrendEngine", "ATR_BUFFER_COPY_FAILED",
                                              StringFormat("Failed to copy ATR buffer data for %s %s (err=%d)",
                                                           symbol, EnumToString(timeframe), atrCopyErr));
                m_lastIndicatorErrorLog = nowTime;
            }
            return TryReuseLastGoodTrend(symbol, timeframe, "ATR_BUFFER_COPY_FAILED");
        }
    }
    
    double effectiveAdx = useAdxModel ? (adxValid ? adx[0] : 0.0) : -1.0;

    m_currentTrend.strength = CalculateTrendStrength(ma_fast, ma_medium, ma_slow, effectiveAdx);
    
    m_currentTrend.angle = CalculateTrendAngle(ma_medium, 5);
    
    m_currentTrend.momentum = CalculateMomentum(symbol, timeframe, 14);
    
    m_currentTrend.volatility = atr[0];
    
    m_currentTrend.type = DetermineTrendType(m_currentTrend.strength, m_currentTrend.angle, effectiveAdx);
    if(useAdxModel && !adxValid)
        m_currentTrend.type = TREND_RANGING;
    
    double prevMomentum = m_currentTrend.momentum;
    double currMomentum = CalculateMomentum(symbol, timeframe, 7);
    m_currentTrend.isAccelerating = currMomentum > prevMomentum && m_currentTrend.strength > 50;
    m_currentTrend.isDecelerating = currMomentum < prevMomentum && m_currentTrend.strength < 50;
    
    m_currentTrend.lastUpdate = TimeCurrent();
    m_readiness.RecordGoodTrend(m_currentTrend);
    if(!atrFallbackUsed && !maFallbackUsed)
        SetReadinessState(TREND_READINESS_HEALTHY, "HEALTHY", false, 0);
    
    if(m_diagnostics != NULL)
    {
        datetime nowTime = TimeCurrent();
        if(m_currentTrend.type != m_lastLoggedTrendType || (nowTime - m_lastTrendLogTime) >= 300)
        {
            string trendStr = EnumToString(m_currentTrend.type);
            string msg = StringFormat("Trend: %s | Strength: %.1f | Angle: %.1f | ADX: %.1f | ADXMode: %s",
                                      trendStr, m_currentTrend.strength, m_currentTrend.angle, effectiveAdx,
                                      adxModeLabel);
            Print("[TrendEngine] ", msg);
            m_lastLoggedTrendType = m_currentTrend.type;
            m_lastTrendLogTime = nowTime;
        }
    }
    
    return true;
}

bool CTrendEngine::UpdateMTFTrend(const string symbol, ENUM_TIMEFRAMES htf,
                                  ENUM_TIMEFRAMES mtf, ENUM_TIMEFRAMES ltf)
{
    m_mtfTrend.htf = AnalyzeTrend(symbol, htf);
    m_mtfTrend.mtf = AnalyzeTrend(symbol, mtf);
    m_mtfTrend.ltf = AnalyzeTrend(symbol, ltf);
    
    CTrendMTF::ComputeAlignment(m_mtfTrend);
    
    if(m_diagnostics != NULL)
    {
        string msg = StringFormat("MTF Alignment: %.1f%% | HTF: %s | MTF: %s | LTF: %s",
                                m_mtfTrend.alignment,
                                EnumToString(m_mtfTrend.htf.type),
                                EnumToString(m_mtfTrend.mtf.type),
                                EnumToString(m_mtfTrend.ltf.type));
        Print("[TrendEngine] ", msg);
    }
    
    return true;
}

TrendState CTrendEngine::AnalyzeTrend(const string symbol, ENUM_TIMEFRAMES timeframe)
{
    TrendState state;
    
    TrendState savedState = m_currentTrend;
    STrendReadinessRestorePoint savedReadiness = m_readiness.Capture();
    
    if(UpdateTrend(symbol, timeframe))
    {
        state = m_currentTrend;
    }
    
    m_currentTrend = savedState;
    m_readiness.Restore(savedReadiness);
    
    return state;
}

double CTrendEngine::CalculateTrendStrength(double &ma_fast[], double &ma_medium[], 
                                           double &ma_slow[], double adx)
{
    return CTrendStrength::Calculate(ma_fast, ma_medium, ma_slow, adx,
                                     m_trendThreshold, m_strongTrendThreshold);
}

double CTrendEngine::CalculateTrendAngle(double &ma[], int period)
{
    return CTrendMath::CalculateTrendAngle(ma, period);
}

double CTrendEngine::CalculateMomentum(const string symbol, ENUM_TIMEFRAMES timeframe, int period)
{
    return CTrendMath::CalculateMomentum(symbol, timeframe, period);
}

ENUM_TREND_TYPE CTrendEngine::DetermineTrendType(double strength, double angle, double adx)
{
    return CTrendRegime::DetermineTrendType(strength, angle, adx,
                                            m_trendThreshold, m_strongTrendThreshold);
}

bool CTrendEngine::IsTrendBullish() const
{
    return CTrendRegime::IsBullish(m_currentTrend.type);
}

bool CTrendEngine::IsTrendBearish() const
{
    return CTrendRegime::IsBearish(m_currentTrend.type);
}

bool CTrendEngine::IsStrongTrend() const
{
    return CTrendRegime::IsStrong(m_currentTrend.type);
}

bool CTrendEngine::IsRanging() const
{
    return CTrendRegime::IsRanging(m_currentTrend.type);
}

bool CTrendEngine::ConfirmTrendContinuation(const string symbol, ENUM_TIMEFRAMES timeframe)
{
    if(!UpdateTrend(symbol, timeframe))
        return false;
    
    if(m_currentTrend.strength > 50 && !m_currentTrend.isDecelerating)
    {
        if((IsTrendBullish() && m_currentTrend.momentum > 0) ||
           (IsTrendBearish() && m_currentTrend.momentum < 0))
        {
            return true;
        }
    }
    
    return false;
}

bool CTrendEngine::DetectTrendReversal(const string symbol, ENUM_TIMEFRAMES timeframe)
{
    if(!UpdateTrend(symbol, timeframe))
        return false;
    
    if(m_currentTrend.strength < 40 && m_currentTrend.isDecelerating)
    {
        if((IsTrendBullish() && m_currentTrend.momentum < -5) ||
           (IsTrendBearish() && m_currentTrend.momentum > 5))
        {
            return true;
        }
    }
    
    return false;
}

void CTrendEngine::Reset()
{
    m_currentTrend = TrendState();
    m_mtfTrend = MTFTrendState();
    m_indicatorSymbol = "";
    m_indicatorTimeframe = PERIOD_CURRENT;
    m_lastIndicatorErrorLog = 0;
    m_lastLoggedTrendType = TREND_NONE;
    m_lastTrendLogTime = 0;
    m_adxHealth.ResetHealthState();
    m_readiness.ResetReadinessState();
    ReleaseIndicators();
}

#endif // TREND_ENGINE_MQH
