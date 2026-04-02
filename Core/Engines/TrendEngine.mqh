//+------------------------------------------------------------------+
//| Trend Detection Engine - Enterprise Grade                        |
//| Unified trend analysis for all strategies                       |
//+------------------------------------------------------------------+
#property copyright "Enterprise Trading Solutions"
#property version   "2.0"
#property strict

#ifndef TREND_ENGINE_MQH
#define TREND_ENGINE_MQH

#include "../Utils/Enums.mqh"
#include "../Signals/SignalDiagnostics.mqh"

// Forward declarations
class CEnhancedErrorHandler;
class CUtilities;
class CHedgingProtection;
class CMarketAnalysis;
class CModeManager;
class CNextGenStrategyBrain;
class CTransformerBrain;
struct SPredictionWithUncertainty;
class CPositionSizer;
class CStrategyManager;
class CTradeManager;
class CPerformanceAnalytics;
class CAIStrategyOrchestrator;

//+------------------------------------------------------------------+
//| Trend Types                                                     |
//+------------------------------------------------------------------+
enum ENUM_TREND_TYPE
{
    TREND_NONE = 0,
    TREND_BULLISH_STRONG,
    TREND_BULLISH_WEAK,
    TREND_BEARISH_STRONG,
    TREND_BEARISH_WEAK,
    TREND_RANGING,
    TREND_VOLATILE,
    TREND_TRANSITIONING
};

//+------------------------------------------------------------------+
//| Trend State Structure                                           |
//+------------------------------------------------------------------+
struct TrendState
{
    ENUM_TREND_TYPE type;
    double strength;            // 0-100 trend strength
    double angle;               // Trend angle in degrees
    double momentum;            // Momentum value
    double volatility;          // Current volatility
    bool isAccelerating;        // Trend acceleration
    bool isDecelerating;        // Trend deceleration
    datetime lastUpdate;
    
    TrendState() : type(TREND_NONE), strength(0), angle(0), momentum(0),
                  volatility(0), isAccelerating(false), isDecelerating(false),
                  lastUpdate(0) {}
};

enum ENUM_TREND_READINESS_STATE
{
    TREND_READINESS_WARMUP = 0,
    TREND_READINESS_TRANSIENT_COPY_FAULT = 1,
    TREND_READINESS_HANDLE_FAULT = 2,
    TREND_READINESS_REUSED_SNAPSHOT = 3,
    TREND_READINESS_HEALTHY = 4
};

struct STrendReadinessSnapshot
{
    ENUM_TREND_READINESS_STATE state;
    bool reuseActive;
    int stalenessSeconds;
    datetime lastGoodTime;
    string reasonTag;

    STrendReadinessSnapshot() :
        state(TREND_READINESS_WARMUP),
        reuseActive(false),
        stalenessSeconds(0),
        lastGoodTime(0),
        reasonTag("WARMUP")
    {
    }
};

//+------------------------------------------------------------------+
//| Multi-Timeframe Trend                                           |
//+------------------------------------------------------------------+
struct MTFTrendState
{
    TrendState htf;            // Higher timeframe trend
    TrendState mtf;            // Medium timeframe trend
    TrendState ltf;            // Lower timeframe trend
    double alignment;          // 0-100 alignment score
    bool isAligned;           // All timeframes aligned
    ENUM_TREND_TYPE consensus; // Consensus trend
};

//+------------------------------------------------------------------+
//| Trend Detection Engine Class                                    |
//+------------------------------------------------------------------+
class CTrendEngine
{
private:
    // Configuration
    int m_maPeriodFast;
    int m_maPeriodMedium;
    int m_maPeriodSlow;
    int m_adxPeriod;
    double m_trendThreshold;
    double m_strongTrendThreshold;
    
    // State
    TrendState m_currentTrend;
    MTFTrendState m_mtfTrend;
    
    // Indicators
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
    bool m_lastAdxValid;
    int m_consecutiveAdxFailures;
    double m_lastAdxRawValue;
    int m_adxFailureReinitThreshold;
    datetime m_lastAdxHealthLogTime;
    datetime m_lastAdxReinitAttemptTime;
    int m_consecutiveReadinessFaults;
    int m_readinessFailureReinitThreshold;
    datetime m_lastReadinessReinitAttemptTime;
    STrendReadinessSnapshot m_readinessSnapshot;
    TrendState m_lastGoodTrend;
    bool m_hasLastGoodTrend;
    datetime m_lastGoodTrendTime;
    datetime m_lastReuseLogTime;
    int m_readinessReuseTtlSeconds;
    
    // Diagnostics
    CSignalDiagnostics* m_diagnostics;
    
    // Internal methods
    bool InitializeIndicators(const string symbol, ENUM_TIMEFRAMES timeframe);
    bool IndicatorsReadyForRead(int minBars);
    void ReleaseIndicators();
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
    double CalculateAtrFallback(const string symbol, ENUM_TIMEFRAMES timeframe, const int period) const;
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
    TrendState CalculateMAs(const string symbol, ENUM_TIMEFRAMES timeframe,
                      double &ma_fast[], double &ma_medium[], double &ma_slow[], double &ma[]);
    double GetTrendStrength(const double &ma_fast[], const double &ma_medium[], const double &ma_slow[]);
    double CalculateAngle(const double &ma[], int period);
    double CalculateMomentum(const string symbol, ENUM_TIMEFRAMES timeframe, int period);
    ENUM_TREND_TYPE DetermineTrendType(double strength, double angle, double adx);
    
public:
    // Constructor/Destructor
    CTrendEngine();
    ~CTrendEngine();
    
    // Initialization
    bool Initialize(int maFast = 20, int maMedium = 50, int maSlow = 200,
                   int adxPeriod = 14, CSignalDiagnostics* diagnostics = NULL);
    
    // Main analysis methods
    bool UpdateTrend(const string symbol, ENUM_TIMEFRAMES timeframe);
    bool UpdateMTFTrend(const string symbol, ENUM_TIMEFRAMES htf, 
                       ENUM_TIMEFRAMES mtf, ENUM_TIMEFRAMES ltf);
    
    // Getters
    ENUM_TREND_TYPE GetCurrentTrend() const { return m_currentTrend.type; }
    TrendState GetTrendState() const { return m_currentTrend; }
    MTFTrendState GetMTFTrendState() const { return m_mtfTrend; }
    double GetTrendStrength() const { return m_currentTrend.strength; }
    double GetTrendAngle() const { return m_currentTrend.angle; }
    double GetMomentum() const { return m_currentTrend.momentum; }
    STrendReadinessSnapshot GetReadinessSnapshot() const { return m_readinessSnapshot; }
    void SetReadinessReuseTtlSeconds(const int seconds) { m_readinessReuseTtlSeconds = MathMax(10, seconds); }
    
    // Utility methods
    bool IsTrendBullish() const;
    bool IsTrendBearish() const;
    bool IsStrongTrend() const;
    bool IsRanging() const;
    bool IsTrendAccelerating() const { return m_currentTrend.isAccelerating; }
    bool IsTrendDecelerating() const { return m_currentTrend.isDecelerating; }
    bool IsMTFAligned() const { return m_mtfTrend.isAligned; }
    double GetMTFAlignment() const { return m_mtfTrend.alignment; }
    
    // Trend confirmation
    bool ConfirmTrendContinuation(const string symbol, ENUM_TIMEFRAMES timeframe);
    bool DetectTrendReversal(const string symbol, ENUM_TIMEFRAMES timeframe);
    
    // Analysis methods
    TrendState AnalyzeTrend(const string symbol, ENUM_TIMEFRAMES timeframe);
    double CalculateTrendStrength(double &ma_fast[], double &ma_medium[], double &ma_slow[], double adx);
    double CalculateTrendAngle(double &ma[], int period);
    
    // Reset
    void Reset();
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
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
    m_lastAdxValid(true),
    m_consecutiveAdxFailures(0),
    m_lastAdxRawValue(0.0),
    m_adxFailureReinitThreshold(3),
    m_lastAdxHealthLogTime(0),
    m_lastAdxReinitAttemptTime(0),
    m_consecutiveReadinessFaults(0),
    m_readinessFailureReinitThreshold(3),
    m_lastReadinessReinitAttemptTime(0),
    m_hasLastGoodTrend(false),
    m_lastGoodTrendTime(0),
    m_lastReuseLogTime(0),
    m_readinessReuseTtlSeconds(60),
    m_diagnostics(NULL)
{
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CTrendEngine::~CTrendEngine()
{
    ReleaseIndicators();
}

//+------------------------------------------------------------------+
//| Initialize Engine                                               |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Initialize Indicators                                           |
//+------------------------------------------------------------------+
bool CTrendEngine::InitializeIndicators(const string symbol, ENUM_TIMEFRAMES timeframe)
{
    bool handlesReady = (m_handleMAFast != INVALID_HANDLE &&
                         m_handleMAMedium != INVALID_HANDLE &&
                         m_handleMASlow != INVALID_HANDLE &&
                         m_handleADX != INVALID_HANDLE &&
                         m_handleATR != INVALID_HANDLE);
    bool contextMatches = (m_indicatorSymbol == symbol && m_indicatorTimeframe == timeframe);
    if(handlesReady && contextMatches)
        return true;

    // Context changed or handles missing - rebuild once.
    ReleaseIndicators();
    m_indicatorSymbol = symbol;
    m_indicatorTimeframe = timeframe;
    
    // Create new indicators
    m_handleMAFast = iMA(symbol, timeframe, m_maPeriodFast, 0, MODE_EMA, PRICE_CLOSE);
    if(m_handleMAFast == INVALID_HANDLE)
    {
        if(m_diagnostics != NULL)
            m_diagnostics.LogStrategyError("TrendEngine", "MA_FAST_INIT_FAILED", 
                                          "Failed to create fast MA indicator");
        return false;
    }
    
    m_handleMAMedium = iMA(symbol, timeframe, m_maPeriodMedium, 0, MODE_EMA, PRICE_CLOSE);
    if(m_handleMAMedium == INVALID_HANDLE)
    {
        ReleaseIndicators();
        if(m_diagnostics != NULL)
            m_diagnostics.LogStrategyError("TrendEngine", "MA_MEDIUM_INIT_FAILED",
                                          "Failed to create medium MA indicator");
        return false;
    }
    
    m_handleMASlow = iMA(symbol, timeframe, m_maPeriodSlow, 0, MODE_EMA, PRICE_CLOSE);
    if(m_handleMASlow == INVALID_HANDLE)
    {
        ReleaseIndicators();
        if(m_diagnostics != NULL)
            m_diagnostics.LogStrategyError("TrendEngine", "MA_SLOW_INIT_FAILED",
                                          "Failed to create slow MA indicator");
        return false;
    }
    
    m_handleADX = iADX(symbol, timeframe, m_adxPeriod);
    if(m_handleADX == INVALID_HANDLE)
    {
        ReleaseIndicators();
        if(m_diagnostics != NULL)
            m_diagnostics.LogStrategyError("TrendEngine", "ADX_INIT_FAILED",
                                          "Failed to create ADX indicator");
        return false;
    }
    
    m_handleATR = iATR(symbol, timeframe, 14);
    if(m_handleATR == INVALID_HANDLE)
    {
        ReleaseIndicators();
        if(m_diagnostics != NULL)
            m_diagnostics.LogStrategyError("TrendEngine", "ATR_INIT_FAILED",
                                          "Failed to create ATR indicator");
        return false;
    }

    m_consecutiveReadinessFaults = 0;
    
    return true;
}

bool CTrendEngine::IndicatorsReadyForRead(int minBars)
{
    if(m_handleMAFast == INVALID_HANDLE ||
       m_handleMAMedium == INVALID_HANDLE ||
       m_handleMASlow == INVALID_HANDLE ||
       m_handleADX == INVALID_HANDLE ||
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
    int adxBars = BarsCalculated(m_handleADX);
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

    bool partialReady = (fastBars < minBars || medBars < minBars || slowBars < minBars || adxBars < minBars);
    if(partialReady)
    {
        datetime nowTime = TimeCurrent();
        if((nowTime - m_lastIndicatorErrorLog) >= 30)
        {
            PrintFormat("[READINESS-STATE] TrendEngine partial readiness | symbol=%s | timeframe=%s | Bars=%d | MAf=%d | MAm=%d | MAs=%d | ADX=%d | ATR=%d | need=%d",
                        m_indicatorSymbol,
                        EnumToString(m_indicatorTimeframe),
                        chartBars,
                        fastBars,
                        medBars,
                        slowBars,
                        adxBars,
                        atrBars,
                        minBars);
            m_lastIndicatorErrorLog = nowTime;
        }
        SetReadinessState(TREND_READINESS_TRANSIENT_COPY_FAULT, "PARTIAL_READY", false, 0);
    }
    else
        SetReadinessState(TREND_READINESS_HEALTHY, "HEALTHY", false, 0);
    return true;
}

bool CTrendEngine::IsValidAdxDomainValue(const double value) const
{
    return (MathIsValidNumber(value) && value >= 0.0 && value <= 100.0);
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
    m_lastAdxValid = false;
    m_lastAdxRawValue = rawAdxValue;
    m_consecutiveAdxFailures++;

    datetime nowTime = TimeCurrent();
    if((nowTime - m_lastAdxHealthLogTime) >= 30)
    {
        int chartBars = Bars(symbol, timeframe);
        int adxBars = (m_handleADX != INVALID_HANDLE) ? BarsCalculated(m_handleADX) : -1;
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

        if(m_diagnostics != NULL)
        {
            m_diagnostics.LogStrategyError("TrendEngine",
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

    MaybeReinitializeAdxHandle(symbol, timeframe);
}

void CTrendEngine::MaybeReinitializeAdxHandle(const string symbol, ENUM_TIMEFRAMES timeframe)
{
    if(m_consecutiveAdxFailures < m_adxFailureReinitThreshold)
        return;

    datetime nowTime = TimeCurrent();
    if(m_lastAdxReinitAttemptTime != 0 && (nowTime - m_lastAdxReinitAttemptTime) < 30)
        return;
    m_lastAdxReinitAttemptTime = nowTime;

    if(m_handleADX != INVALID_HANDLE)
    {
        IndicatorRelease(m_handleADX);
        m_handleADX = INVALID_HANDLE;
    }

    m_handleADX = iADX(symbol, timeframe, m_adxPeriod);
    if(m_handleADX == INVALID_HANDLE)
    {
        int err = GetLastError();
        if(m_diagnostics != NULL)
        {
            m_diagnostics.LogStrategyError("TrendEngine", "ADX_REINIT_FAILED",
                                           StringFormat("ADX handle reinit failed for %s %s (err=%d)",
                                                        symbol, EnumToString(timeframe), err));
        }
        return;
    }

    PrintFormat("[TrendEngine][ADX-HEALTH] ADX handle reinitialized for %s %s after %d consecutive failures",
                symbol, EnumToString(timeframe), m_consecutiveAdxFailures);
    m_consecutiveAdxFailures = 0;
}

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
    m_consecutiveReadinessFaults++;

    datetime nowTime = TimeCurrent();
    if((nowTime - m_lastIndicatorErrorLog) >= 30)
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
                    m_consecutiveReadinessFaults);

        if(m_diagnostics != NULL)
        {
            m_diagnostics.LogStrategyError("TrendEngine",
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
                                                        m_consecutiveReadinessFaults));
        }

        m_lastIndicatorErrorLog = nowTime;
    }

    MaybeReinitializeIndicatorSet(symbol, timeframe);
}

void CTrendEngine::MaybeReinitializeIndicatorSet(const string symbol, ENUM_TIMEFRAMES timeframe)
{
    if(m_consecutiveReadinessFaults < m_readinessFailureReinitThreshold)
        return;

    int faultsBeforeReset = m_consecutiveReadinessFaults;
    datetime nowTime = TimeCurrent();
    if(m_lastReadinessReinitAttemptTime != 0 && (nowTime - m_lastReadinessReinitAttemptTime) < 30)
        return;
    m_lastReadinessReinitAttemptTime = nowTime;

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
    m_consecutiveReadinessFaults = 0;
}

void CTrendEngine::SetReadinessState(const ENUM_TREND_READINESS_STATE state,
                                     const string reasonTag,
                                     const bool reuseActive,
                                     const int stalenessSeconds)
{
    m_readinessSnapshot.state = state;
    m_readinessSnapshot.reasonTag = reasonTag;
    m_readinessSnapshot.reuseActive = reuseActive;
    m_readinessSnapshot.stalenessSeconds = MathMax(0, stalenessSeconds);
    if(m_hasLastGoodTrend)
        m_readinessSnapshot.lastGoodTime = m_lastGoodTrendTime;
}

int CTrendEngine::GetReuseWindowSeconds(ENUM_TIMEFRAMES timeframe) const
{
    int barSeconds = PeriodSeconds(timeframe);
    if(barSeconds <= 0)
        barSeconds = 60;
    return MathMin(MathMax(10, m_readinessReuseTtlSeconds), MathMax(10, barSeconds));
}

double CTrendEngine::CalculateAtrFallback(const string symbol,
                                          ENUM_TIMEFRAMES timeframe,
                                          const int period) const
{
    int requiredBars = MathMax(period + 1, 5);
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    int copied = CopyRates(symbol, timeframe, 0, requiredBars, rates);
    if(copied <= period)
        return 0.0;

    double trueRangeSum = 0.0;
    int usable = MathMin(period, copied - 1);
    for(int i = 0; i < usable; i++)
    {
        double rangeHighLow = rates[i].high - rates[i].low;
        double rangeHighClose = MathAbs(rates[i].high - rates[i + 1].close);
        double rangeLowClose = MathAbs(rates[i].low - rates[i + 1].close);
        trueRangeSum += MathMax(rangeHighLow, MathMax(rangeHighClose, rangeLowClose));
    }

    if(usable <= 0)
        return 0.0;

    return trueRangeSum / (double)usable;
}

bool CTrendEngine::CalculateEmaFallbackSeries(const string symbol,
                                              ENUM_TIMEFRAMES timeframe,
                                              const int period,
                                              const int count,
                                              double &output[]) const
{
    if(period <= 0 || count <= 0)
        return false;

    int requiredBars = MathMax(period + count + 5, count + 5);
    double closes[];
    ArraySetAsSeries(closes, true);
    int copied = CopyClose(symbol, timeframe, 0, requiredBars, closes);
    if(copied <= (period + count))
        return false;

    double alpha = 2.0 / ((double)period + 1.0);
    for(int shift = 0; shift < count; shift++)
    {
        double ema = closes[copied - 1];
        for(int idx = copied - 2; idx >= shift; idx--)
            ema = (alpha * closes[idx]) + ((1.0 - alpha) * ema);
        output[shift] = ema;
    }

    return true;
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
    if(!m_hasLastGoodTrend || m_lastGoodTrendTime <= 0)
        return false;

    int stalenessSeconds = (int)MathMax(0, TimeCurrent() - m_lastGoodTrendTime);
    if(stalenessSeconds > GetReuseWindowSeconds(timeframe))
        return false;

    m_currentTrend = m_lastGoodTrend;
    m_currentTrend.lastUpdate = TimeCurrent();
    SetReadinessState(TREND_READINESS_REUSED_SNAPSHOT, reasonTag, true, stalenessSeconds);

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

//+------------------------------------------------------------------+
//| Release Indicators                                              |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Update Trend Analysis                                           |
//+------------------------------------------------------------------+
bool CTrendEngine::UpdateTrend(const string symbol, ENUM_TIMEFRAMES timeframe)
{
    // Initialize indicators if needed
    if(!InitializeIndicators(symbol, timeframe))
        return false;

    int minBars = MathMax(m_maPeriodSlow + 5, m_adxPeriod + 5);
    if(!IndicatorsReadyForRead(minBars))
        return false;
    
    // Get indicator values
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
    
    bool adxValid = true;
    ResetLastError();
    int adxCopyRet = CopyBuffer(m_handleADX, 0, 0, 1, adx);
    int plusCopyRet = CopyBuffer(m_handleADX, 1, 0, 1, plusDI);
    int minusCopyRet = CopyBuffer(m_handleADX, 2, 0, 1, minusDI);
    int adxCopyErr = GetLastError();
    if(adxCopyRet != 1 || plusCopyRet != 1 || minusCopyRet != 1)
    {
        adxValid = false;
        RecordAdxFailure(symbol,
                         timeframe,
                         "ADX_BUFFER_COPY_FAILED",
                         adxCopyRet,
                         plusCopyRet,
                         minusCopyRet,
                         adxCopyErr,
                         adx[0]);
    }
    else
    {
        m_lastAdxRawValue = adx[0];
        if(!IsValidAdxDomainValue(adx[0]) ||
           !IsValidAdxDomainValue(plusDI[0]) ||
           !IsValidAdxDomainValue(minusDI[0]))
        {
            adxValid = false;
            RecordAdxFailure(symbol,
                             timeframe,
                             "ADX_VALUE_OUT_OF_RANGE",
                             adxCopyRet,
                             plusCopyRet,
                             minusCopyRet,
                             0,
                             adx[0]);
        }
    }

    if(!adxValid)
    {
        adx[0] = 0.0;
        plusDI[0] = 0.0;
        minusDI[0] = 0.0;
    }
    else
    {
        m_lastAdxValid = true;
        m_consecutiveAdxFailures = 0;
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
    
    double effectiveAdx = adxValid ? adx[0] : 0.0;

    // Calculate trend strength
    m_currentTrend.strength = CalculateTrendStrength(ma_fast, ma_medium, ma_slow, effectiveAdx);
    
    // Calculate trend angle
    m_currentTrend.angle = CalculateTrendAngle(ma_medium, 5);
    
    // Calculate momentum
    m_currentTrend.momentum = CalculateMomentum(symbol, timeframe, 14);
    
    // Set volatility
    m_currentTrend.volatility = atr[0];
    
    // Determine trend type
    m_currentTrend.type = DetermineTrendType(m_currentTrend.strength, m_currentTrend.angle, effectiveAdx);
    if(!adxValid)
        m_currentTrend.type = TREND_RANGING;
    
    // Check acceleration/deceleration
    double prevMomentum = m_currentTrend.momentum;
    double currMomentum = CalculateMomentum(symbol, timeframe, 7);
    m_currentTrend.isAccelerating = currMomentum > prevMomentum && m_currentTrend.strength > 50;
    m_currentTrend.isDecelerating = currMomentum < prevMomentum && m_currentTrend.strength < 50;
    
    // Update timestamp
    m_currentTrend.lastUpdate = TimeCurrent();
    m_lastGoodTrend = m_currentTrend;
    m_hasLastGoodTrend = true;
    m_lastGoodTrendTime = m_currentTrend.lastUpdate;
    m_consecutiveReadinessFaults = 0;
    if(!atrFallbackUsed && !maFallbackUsed)
        SetReadinessState(TREND_READINESS_HEALTHY, "HEALTHY", false, 0);
    
    // Log trend update
    if(m_diagnostics != NULL)
    {
        datetime nowTime = TimeCurrent();
        if(m_currentTrend.type != m_lastLoggedTrendType || (nowTime - m_lastTrendLogTime) >= 300)
        {
            string trendStr = EnumToString(m_currentTrend.type);
            string msg = StringFormat("Trend: %s | Strength: %.1f | Angle: %.1f | ADX: %.1f | ADXValid: %s",
                                      trendStr, m_currentTrend.strength, m_currentTrend.angle, effectiveAdx,
                                      adxValid ? "true" : "false");
            Print("[TrendEngine] ", msg);
            m_lastLoggedTrendType = m_currentTrend.type;
            m_lastTrendLogTime = nowTime;
        }
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Update Multi-Timeframe Trend                                    |
//+------------------------------------------------------------------+
bool CTrendEngine::UpdateMTFTrend(const string symbol, ENUM_TIMEFRAMES htf,
                                  ENUM_TIMEFRAMES mtf, ENUM_TIMEFRAMES ltf)
{
    // Analyze each timeframe
    m_mtfTrend.htf = AnalyzeTrend(symbol, htf);
    m_mtfTrend.mtf = AnalyzeTrend(symbol, mtf);
    m_mtfTrend.ltf = AnalyzeTrend(symbol, ltf);
    
    // Calculate alignment
    int alignmentScore = 0;
    int totalWeight = 0;
    
    // HTF has highest weight (40%)
    if(m_mtfTrend.htf.type == TREND_BULLISH_STRONG || m_mtfTrend.htf.type == TREND_BULLISH_WEAK)
    {
        alignmentScore += 40;
    }
    else if(m_mtfTrend.htf.type == TREND_BEARISH_STRONG || m_mtfTrend.htf.type == TREND_BEARISH_WEAK)
    {
        alignmentScore -= 40;
    }
    
    // MTF has medium weight (35%)
    if(m_mtfTrend.mtf.type == TREND_BULLISH_STRONG || m_mtfTrend.mtf.type == TREND_BULLISH_WEAK)
    {
        alignmentScore += 35;
    }
    else if(m_mtfTrend.mtf.type == TREND_BEARISH_STRONG || m_mtfTrend.mtf.type == TREND_BEARISH_WEAK)
    {
        alignmentScore -= 35;
    }
    
    // LTF has lowest weight (25%)
    if(m_mtfTrend.ltf.type == TREND_BULLISH_STRONG || m_mtfTrend.ltf.type == TREND_BULLISH_WEAK)
    {
        alignmentScore += 25;
    }
    else if(m_mtfTrend.ltf.type == TREND_BEARISH_STRONG || m_mtfTrend.ltf.type == TREND_BEARISH_WEAK)
    {
        alignmentScore -= 25;
    }
    
    // Calculate alignment percentage
    m_mtfTrend.alignment = MathAbs(alignmentScore);
    
    // Determine if aligned
    m_mtfTrend.isAligned = m_mtfTrend.alignment >= 75;
    
    // Determine consensus
    if(alignmentScore > 50)
    {
        m_mtfTrend.consensus = m_mtfTrend.htf.strength > 50 ? 
                              TREND_BULLISH_STRONG : TREND_BULLISH_WEAK;
    }
    else if(alignmentScore < -50)
    {
        m_mtfTrend.consensus = m_mtfTrend.htf.strength > 50 ? 
                              TREND_BEARISH_STRONG : TREND_BEARISH_WEAK;
    }
    else
    {
        m_mtfTrend.consensus = TREND_RANGING;
    }
    
    // Log MTF analysis
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

//+------------------------------------------------------------------+
//| Analyze Trend for Specific Timeframe                           |
//+------------------------------------------------------------------+
TrendState CTrendEngine::AnalyzeTrend(const string symbol, ENUM_TIMEFRAMES timeframe)
{
    TrendState state;
    
    // Save current state
    TrendState savedState = m_currentTrend;
    STrendReadinessSnapshot savedReadiness = m_readinessSnapshot;
    TrendState savedLastGoodTrend = m_lastGoodTrend;
    bool savedHasLastGood = m_hasLastGoodTrend;
    datetime savedLastGoodTrendTime = m_lastGoodTrendTime;
    
    // Analyze the timeframe
    if(UpdateTrend(symbol, timeframe))
    {
        state = m_currentTrend;
    }
    
    // Restore previous state
    m_currentTrend = savedState;
    m_readinessSnapshot = savedReadiness;
    m_lastGoodTrend = savedLastGoodTrend;
    m_hasLastGoodTrend = savedHasLastGood;
    m_lastGoodTrendTime = savedLastGoodTrendTime;
    
    return state;
}

//+------------------------------------------------------------------+
//| Calculate Trend Strength                                        |
//+------------------------------------------------------------------+
double CTrendEngine::CalculateTrendStrength(double &ma_fast[], double &ma_medium[], 
                                           double &ma_slow[], double adx)
{
    double strength = 0;
    
    // Factor 1: MA alignment (40% weight)
    if(ma_fast[0] > ma_medium[0] && ma_medium[0] > ma_slow[0])
    {
        // Perfect bullish alignment
        strength += 40;
        double separation = ((ma_fast[0] - ma_slow[0]) / ma_slow[0]) * 100;
        strength += MathMin(10, separation); // Up to 10 additional points for separation
    }
    else if(ma_fast[0] < ma_medium[0] && ma_medium[0] < ma_slow[0])
    {
        // Perfect bearish alignment
        strength += 40;
        double separation = ((ma_slow[0] - ma_fast[0]) / ma_slow[0]) * 100;
        strength += MathMin(10, separation); // Up to 10 additional points for separation
    }
    else
    {
        // Partial alignment
        strength += 20;
    }
    
    // Factor 2: ADX strength (30% weight)
    if(adx > m_strongTrendThreshold)
    {
        strength += 30;
    }
    else if(adx > m_trendThreshold)
    {
        strength += 20;
    }
    else
    {
        strength += 10;
    }
    
    // Factor 3: MA slope consistency (20% weight)
    bool consistentSlope = true;
    for(int i = 1; i < 5; i++)
    {
        if((ma_fast[i-1] - ma_fast[i]) * (ma_medium[i-1] - ma_medium[i]) < 0)
        {
            consistentSlope = false;
            break;
        }
    }
    if(consistentSlope)
        strength += 20;
    else
        strength += 10;
    
    return MathMin(100.0, strength);
}

//+------------------------------------------------------------------+
//| Calculate Trend Angle                                           |
//+------------------------------------------------------------------+
double CTrendEngine::CalculateTrendAngle(double &ma[], int period)
{
    if(period < 2)
        return 0;
    
    // Calculate percentage change instead of raw slope
    // This normalizes across different price scales (BTC vs forex)
    double avgPrice = (ma[0] + ma[period-1]) / 2.0;
    if(avgPrice <= 0)
        return 0;
    
    // Calculate slope as percentage change per bar
    double pctChange = ((ma[0] - ma[period-1]) / avgPrice) * 100.0;
    double slopePerBar = pctChange / period;
    
    // Scale factor to get meaningful angles (0.1% per bar = ~45 degrees)
    double scaledSlope = slopePerBar * 10.0;
    
    // Clamp to prevent extreme values
    scaledSlope = MathMax(-10.0, MathMin(10.0, scaledSlope));
    
    // Convert to angle in degrees
    double angle = MathArctan(scaledSlope) * 180.0 / M_PI;
    
    return angle;
}

//+------------------------------------------------------------------+
//| Calculate Momentum                                              |
//+------------------------------------------------------------------+
double CTrendEngine::CalculateMomentum(const string symbol, ENUM_TIMEFRAMES timeframe, int period)
{
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    
    if(CopyRates(symbol, timeframe, 0, period + 1, rates) < period + 1)
        return 0;
    
    // Calculate rate of change
    double roc = ((rates[0].close - rates[period].close) / rates[period].close) * 100;
    
    return roc;
}

//+------------------------------------------------------------------+
//| Determine Trend Type                                            |
//+------------------------------------------------------------------+
ENUM_TREND_TYPE CTrendEngine::DetermineTrendType(double strength, double angle, double adx)
{
    // Strong trending conditions
    if(adx > m_strongTrendThreshold && strength > 70)
    {
        if(angle > 20)
            return TREND_BULLISH_STRONG;
        else if(angle < -20)
            return TREND_BEARISH_STRONG;
    }
    
    // Moderate trending conditions
    if(adx > m_trendThreshold && strength > 50)
    {
        if(angle > 10)
            return TREND_BULLISH_WEAK;
        else if(angle < -10)
            return TREND_BEARISH_WEAK;
    }
    
    // Ranging or volatile conditions
    if(adx < 20)
        return TREND_RANGING;
    
    if(strength < 30 && MathAbs(angle) > 30)
        return TREND_VOLATILE;
    
    // Transitioning
    if(strength < 50 && MathAbs(angle) < 10)
        return TREND_TRANSITIONING;
    
    return TREND_NONE;
}

//+------------------------------------------------------------------+
//| Check if Trend is Bullish                                      |
//+------------------------------------------------------------------+
bool CTrendEngine::IsTrendBullish() const
{
    return m_currentTrend.type == TREND_BULLISH_STRONG || 
           m_currentTrend.type == TREND_BULLISH_WEAK;
}

//+------------------------------------------------------------------+
//| Check if Trend is Bearish                                      |
//+------------------------------------------------------------------+
bool CTrendEngine::IsTrendBearish() const
{
    return m_currentTrend.type == TREND_BEARISH_STRONG || 
           m_currentTrend.type == TREND_BEARISH_WEAK;
}

//+------------------------------------------------------------------+
//| Check if Strong Trend                                          |
//+------------------------------------------------------------------+
bool CTrendEngine::IsStrongTrend() const
{
    return m_currentTrend.type == TREND_BULLISH_STRONG || 
           m_currentTrend.type == TREND_BEARISH_STRONG;
}

//+------------------------------------------------------------------+
//| Check if Ranging                                               |
//+------------------------------------------------------------------+
bool CTrendEngine::IsRanging() const
{
    return m_currentTrend.type == TREND_RANGING;
}

//+------------------------------------------------------------------+
//| Confirm Trend Continuation                                     |
//+------------------------------------------------------------------+
bool CTrendEngine::ConfirmTrendContinuation(const string symbol, ENUM_TIMEFRAMES timeframe)
{
    if(!UpdateTrend(symbol, timeframe))
        return false;
    
    // Check if trend is maintaining strength
    if(m_currentTrend.strength > 50 && !m_currentTrend.isDecelerating)
    {
        // Check if momentum is positive for bullish or negative for bearish
        if((IsTrendBullish() && m_currentTrend.momentum > 0) ||
           (IsTrendBearish() && m_currentTrend.momentum < 0))
        {
            return true;
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Detect Trend Reversal                                          |
//+------------------------------------------------------------------+
bool CTrendEngine::DetectTrendReversal(const string symbol, ENUM_TIMEFRAMES timeframe)
{
    if(!UpdateTrend(symbol, timeframe))
        return false;
    
    // Check for weakening trend with opposite momentum
    if(m_currentTrend.strength < 40 && m_currentTrend.isDecelerating)
    {
        // Check if momentum has reversed
        if((IsTrendBullish() && m_currentTrend.momentum < -5) ||
           (IsTrendBearish() && m_currentTrend.momentum > 5))
        {
            return true;
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Reset Engine State                                              |
//+------------------------------------------------------------------+
void CTrendEngine::Reset()
{
    m_currentTrend = TrendState();
    m_mtfTrend = MTFTrendState();
    m_indicatorSymbol = "";
    m_indicatorTimeframe = PERIOD_CURRENT;
    m_lastIndicatorErrorLog = 0;
    m_lastLoggedTrendType = TREND_NONE;
    m_lastTrendLogTime = 0;
    m_lastAdxValid = true;
    m_consecutiveAdxFailures = 0;
    m_lastAdxRawValue = 0.0;
    m_lastAdxHealthLogTime = 0;
    m_lastAdxReinitAttemptTime = 0;
    m_consecutiveReadinessFaults = 0;
    m_lastReadinessReinitAttemptTime = 0;
    m_readinessSnapshot = STrendReadinessSnapshot();
    m_lastGoodTrend = TrendState();
    m_hasLastGoodTrend = false;
    m_lastGoodTrendTime = 0;
    m_lastReuseLogTime = 0;
    ReleaseIndicators();
}


// Duplicate methods removed - already defined above


#endif // TREND_ENGINE_MQH
