//+------------------------------------------------------------------+
//| Volatility Analysis Engine - Enterprise Grade                    |
//+------------------------------------------------------------------+
#property copyright "Enterprise Trading Solutions"
#property version   "2.0"
#property strict

#ifndef VOLATILITY_ENGINE_MQH
#define VOLATILITY_ENGINE_MQH

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

enum ENUM_VOLATILITY_STATE
{
    VOLATILITY_LOW = 0,
    VOLATILITY_NORMAL,
    VOLATILITY_HIGH,
    VOLATILITY_EXTREME
};

struct VolatilityMetrics
{
    double atr;
    double atrPercent;
    double bollinger_width;
    double historical_volatility;
    double relative_volatility;
    ENUM_VOLATILITY_STATE state;
    bool isExpanding;
    bool isContracting;
    datetime lastUpdate;

    VolatilityMetrics() :
        atr(0.0),
        atrPercent(0.0),
        bollinger_width(0.0),
        historical_volatility(0.0),
        relative_volatility(0.0),
        state(VOLATILITY_LOW),
        isExpanding(false),
        isContracting(false),
        lastUpdate(0)
    {
    }
};

class CVolatilityEngine
{
private:
    int m_atrPeriod;
    int m_bbPeriod;
    double m_bbDeviation;
    int m_hvPeriod;
    
    int m_handleATR;
    int m_handleBB;
    int m_handleStdDev;
    string m_indicatorSymbol;
    ENUM_TIMEFRAMES m_indicatorTimeframe;
    int m_consecutiveDataFaults;
    datetime m_lastFaultLogTime;
    datetime m_lastReuseLogTime;
    datetime m_lastStateLogTime;
    ENUM_VOLATILITY_STATE m_lastLoggedState;
    
    VolatilityMetrics m_metrics;
    VolatilityMetrics m_lastValidMetrics;
    CSignalDiagnostics* m_diagnostics;
    
    ENUM_VOLATILITY_STATE DetermineState(double atrPercent);
    double CalculateHistoricalVolatility(const string symbol, ENUM_TIMEFRAMES tf);
    void ResetHandles();
    bool EnsureHandles(const string symbol, ENUM_TIMEFRAMES timeframe);
    bool TryReuseLastMetrics(const string symbol, const ENUM_TIMEFRAMES timeframe, const string reasonTag, const int errorCode);
    void NoteDataFault(const string symbol, const ENUM_TIMEFRAMES timeframe, const string reasonTag, const int errorCode);
    int GetReuseWindowSeconds(const ENUM_TIMEFRAMES timeframe) const;
    void MaybeLogState(const string symbol, const ENUM_TIMEFRAMES timeframe);
    
public:
    CVolatilityEngine();
    ~CVolatilityEngine();
    
    bool Initialize(int atrPeriod = 14, int bbPeriod = 20, CSignalDiagnostics* diag = NULL);
    bool UpdateVolatility(const string symbol, ENUM_TIMEFRAMES timeframe);
    
    // Getters
    ENUM_VOLATILITY_STATE GetVolatilityState() const { return m_metrics.state; }
    double GetATR() const { return m_metrics.atr; }
    double GetATRPercent() const { return m_metrics.atrPercent; }
    bool IsVolatilityHigh() const { return m_metrics.state >= VOLATILITY_HIGH; }
    bool IsVolatilityExpanding() const { return m_metrics.isExpanding; }
    
    // Filters
    bool ShouldTradeInCurrentVolatility(double maxVolatility = 3.0);
    double GetVolatilityAdjustedStopLoss(double baseStop);
    double GetVolatilityAdjustedTakeProfit(double baseTp);
    
    void Reset();
};

CVolatilityEngine::CVolatilityEngine() : 
    m_atrPeriod(14), m_bbPeriod(20), m_bbDeviation(2.0), m_hvPeriod(20),
    m_handleATR(INVALID_HANDLE), m_handleBB(INVALID_HANDLE), m_handleStdDev(INVALID_HANDLE),
    m_indicatorSymbol(""), m_indicatorTimeframe(PERIOD_CURRENT),
    m_consecutiveDataFaults(0), m_lastFaultLogTime(0), m_lastReuseLogTime(0), m_lastStateLogTime(0),
    m_lastLoggedState(VOLATILITY_LOW),
    m_diagnostics(NULL)
{
}

CVolatilityEngine::~CVolatilityEngine()
{
    ResetHandles();
}

bool CVolatilityEngine::Initialize(int atrPeriod, int bbPeriod, CSignalDiagnostics* diag)
{
    m_atrPeriod = atrPeriod;
    m_bbPeriod = bbPeriod;
    m_diagnostics = diag;
    m_consecutiveDataFaults = 0;
    m_lastFaultLogTime = 0;
    m_lastReuseLogTime = 0;
    m_lastStateLogTime = 0;
    Reset();
    return true;
}

void CVolatilityEngine::ResetHandles()
{
    if(m_handleATR != INVALID_HANDLE)
    {
        IndicatorRelease(m_handleATR);
        m_handleATR = INVALID_HANDLE;
    }
    if(m_handleBB != INVALID_HANDLE)
    {
        IndicatorRelease(m_handleBB);
        m_handleBB = INVALID_HANDLE;
    }
    if(m_handleStdDev != INVALID_HANDLE)
    {
        IndicatorRelease(m_handleStdDev);
        m_handleStdDev = INVALID_HANDLE;
    }
}

int CVolatilityEngine::GetReuseWindowSeconds(const ENUM_TIMEFRAMES timeframe) const
{
    int barSeconds = PeriodSeconds(timeframe);
    if(barSeconds <= 0)
        barSeconds = 60;

    // Allow reuse for up to 3 bars, with minimum 60 seconds and maximum 1 hour
    return MathMax(60, MathMin(3600, barSeconds * 3));
}

bool CVolatilityEngine::EnsureHandles(const string symbol, ENUM_TIMEFRAMES timeframe)
{
    bool handlesReady = (m_handleATR != INVALID_HANDLE &&
                         m_handleBB != INVALID_HANDLE &&
                         m_handleStdDev != INVALID_HANDLE);
    bool contextMatches = (m_indicatorSymbol == symbol && m_indicatorTimeframe == timeframe);
    if(handlesReady && contextMatches)
        return true;

    if(!contextMatches)
    {
        m_lastValidMetrics = VolatilityMetrics();
        m_lastReuseLogTime = 0;
        m_consecutiveDataFaults = 0;
    }

    ResetHandles();
    m_indicatorSymbol = symbol;
    m_indicatorTimeframe = timeframe;

    m_handleATR = iATR(symbol, timeframe, m_atrPeriod);
    m_handleBB = iBands(symbol, timeframe, m_bbPeriod, 0, m_bbDeviation, PRICE_CLOSE);
    m_handleStdDev = iStdDev(symbol, timeframe, m_hvPeriod, 0, MODE_EMA, PRICE_CLOSE);

    return (m_handleATR != INVALID_HANDLE &&
            m_handleBB != INVALID_HANDLE &&
            m_handleStdDev != INVALID_HANDLE);
}

bool CVolatilityEngine::TryReuseLastMetrics(const string symbol, const ENUM_TIMEFRAMES timeframe, const string reasonTag, const int errorCode)
{
    if(m_indicatorSymbol != symbol || m_indicatorTimeframe != timeframe || m_lastValidMetrics.lastUpdate <= 0)
        return false;

    int ageSeconds = (int)MathMax(0, TimeCurrent() - m_lastValidMetrics.lastUpdate);
    if(ageSeconds > GetReuseWindowSeconds(timeframe))
        return false;

    datetime nowTime = TimeCurrent();
    if(m_lastReuseLogTime == 0 || (nowTime - m_lastReuseLogTime) >= 30)
    {
        PrintFormat("[VOLATILITY-FAULT] REUSE_LAST_VALID | symbol=%s | timeframe=%s | reason=%s | age=%ds | err=%d",
                    symbol,
                    EnumToString(timeframe),
                    reasonTag,
                    ageSeconds,
                    errorCode);
        m_lastReuseLogTime = nowTime;
    }

    m_metrics = m_lastValidMetrics;
    return true;
}

void CVolatilityEngine::NoteDataFault(const string symbol, const ENUM_TIMEFRAMES timeframe, const string reasonTag, const int errorCode)
{
    m_consecutiveDataFaults++;

    datetime nowTime = TimeCurrent();
    if(m_lastFaultLogTime == 0 || (nowTime - m_lastFaultLogTime) >= 30)
    {
        PrintFormat("[VOLATILITY-FAULT] %s | symbol=%s | timeframe=%s | err=%d | faults=%d",
                    reasonTag,
                    symbol,
                    EnumToString(timeframe),
                    errorCode,
                    m_consecutiveDataFaults);
        m_lastFaultLogTime = nowTime;
    }

    if(m_consecutiveDataFaults >= 3)
    {
        ResetHandles();
        PrintFormat("[VOLATILITY-FAULT] HANDLE_RESET | symbol=%s | timeframe=%s | faults=%d",
                    symbol,
                    EnumToString(timeframe),
                    m_consecutiveDataFaults);
        m_consecutiveDataFaults = 0;
    }
}

void CVolatilityEngine::MaybeLogState(const string symbol, const ENUM_TIMEFRAMES timeframe)
{
    datetime nowTime = TimeCurrent();
    if(m_metrics.lastUpdate <= 0)
        return;

    if(m_metrics.state == m_lastLoggedState && (m_lastStateLogTime != 0 && (nowTime - m_lastStateLogTime) < 60))
        return;

    PrintFormat("[VOLATILITY-STATE] %s | timeframe=%s | state=%s | atr=%.5f | atr_pct=%.2f | rel=%.3f | expanding=%s | contracting=%s",
                symbol,
                EnumToString(timeframe),
                EnumToString(m_metrics.state),
                m_metrics.atr,
                m_metrics.atrPercent,
                m_metrics.relative_volatility,
                m_metrics.isExpanding ? "true" : "false",
                m_metrics.isContracting ? "true" : "false");
    m_lastLoggedState = m_metrics.state;
    m_lastStateLogTime = nowTime;
}

bool CVolatilityEngine::UpdateVolatility(const string symbol, ENUM_TIMEFRAMES timeframe)
{
    if(!EnsureHandles(symbol, timeframe))
    {
        int handleErr = GetLastError();
        NoteDataFault(symbol, timeframe, "HANDLE_INIT_FAILED", handleErr);
        return TryReuseLastMetrics(symbol, timeframe, "HANDLE_INIT_FAILED", handleErr);
    }

    int minBars = MathMax(MathMax(m_atrPeriod + 5, m_bbPeriod + 5), m_hvPeriod + 5);
    int availableBars = Bars(symbol, timeframe);
    int calculatedBarsBB = BarsCalculated(m_handleBB);
    int calculatedBarsATR = BarsCalculated(m_handleATR);
    int calculatedBarsStdDev = BarsCalculated(m_handleStdDev);
    
    if(availableBars < minBars ||
       calculatedBarsBB < minBars ||
       calculatedBarsATR < minBars ||
       calculatedBarsStdDev < minBars)
    {
        NoteDataFault(symbol, timeframe, "WARMUP", 0);
        return TryReuseLastMetrics(symbol, timeframe, "WARMUP", 0);
    }

    double atr[];
    double bb_upper[];
    double bb_lower[];
    double stddev[];
    ArrayResize(atr, 2);
    ArrayResize(bb_upper, 1);
    ArrayResize(bb_lower, 1);
    ArrayResize(stddev, 1);
    ArraySetAsSeries(atr, true);

    ResetLastError();
    
    // HIGH FIX: Validate handles are valid before attempting copy
    if(m_handleATR == INVALID_HANDLE || m_handleBB == INVALID_HANDLE || m_handleStdDev == INVALID_HANDLE)
    {
        NoteDataFault(symbol, timeframe, "INVALID_HANDLE", 0);
        return TryReuseLastMetrics(symbol, timeframe, "INVALID_HANDLE", 0);
    }

    int atrRet = CopyBuffer(m_handleATR, 0, 0, 2, atr);
    int upperRet = CopyBuffer(m_handleBB, 1, 0, 1, bb_upper);
    int lowerRet = CopyBuffer(m_handleBB, 2, 0, 1, bb_lower);
    int stdDevRet = CopyBuffer(m_handleStdDev, 0, 0, 1, stddev);
    int copyErr = GetLastError();
    
    // HIGH FIX: Improved error detection with specific failure reasons
    if(atrRet <= 0)
    {
        NoteDataFault(symbol, timeframe, "ATR_BUFFER_COPY_FAILED", copyErr);
        return TryReuseLastMetrics(symbol, timeframe, "ATR_BUFFER_COPY_FAILED", copyErr);
    }
    if(upperRet <= 0 || lowerRet <= 0)
    {
        NoteDataFault(symbol, timeframe, "BB_BUFFER_COPY_FAILED", copyErr);
        return TryReuseLastMetrics(symbol, timeframe, "BB_BUFFER_COPY_FAILED", copyErr);
    }
    if(stdDevRet <= 0)
    {
        NoteDataFault(symbol, timeframe, "STDDEV_BUFFER_COPY_FAILED", copyErr);
        return TryReuseLastMetrics(symbol, timeframe, "STDDEV_BUFFER_COPY_FAILED", copyErr);
    }
    if(atr[0] <= 0.0)
    {
        NoteDataFault(symbol, timeframe, "INVALID_ATR_VALUE", 0);
        return TryReuseLastMetrics(symbol, timeframe, "INVALID_ATR_VALUE", 0);
    }

    double price = SymbolInfoDouble(symbol, SYMBOL_BID);
    if(price <= 0.0)
        price = SymbolInfoDouble(symbol, SYMBOL_ASK);
    if(price <= 0.0)
    {
        NoteDataFault(symbol, timeframe, "PRICE_UNAVAILABLE", 0);
        return TryReuseLastMetrics(symbol, timeframe, "PRICE_UNAVAILABLE", 0);
    }

    m_metrics.atr = atr[0];
    m_metrics.atrPercent = (atr[0] / price) * 100.0;
    m_metrics.bollinger_width = MathMax(0.0, bb_upper[0] - bb_lower[0]);
    m_metrics.historical_volatility = MathMax(0.0, stddev[0]);
    m_metrics.relative_volatility = (m_metrics.historical_volatility > 0.0)
                                    ? (m_metrics.atr / m_metrics.historical_volatility)
                                    : 1.0;
    m_metrics.state = DetermineState(m_metrics.atrPercent);
    m_metrics.isExpanding = atr[0] > atr[1] * 1.1;
    m_metrics.isContracting = atr[0] < atr[1] * 0.9;
    m_metrics.lastUpdate = TimeCurrent();

    m_lastValidMetrics = m_metrics;
    m_consecutiveDataFaults = 0;
    MaybeLogState(symbol, timeframe);

    return true;
}

ENUM_VOLATILITY_STATE CVolatilityEngine::DetermineState(double atrPercent)
{
    if(atrPercent < 0.5) return VOLATILITY_LOW;
    else if(atrPercent < 1.5) return VOLATILITY_NORMAL;
    else if(atrPercent < 3.0) return VOLATILITY_HIGH;
    else return VOLATILITY_EXTREME;
}

bool CVolatilityEngine::ShouldTradeInCurrentVolatility(double maxVolatility)
{
    return m_metrics.atrPercent <= maxVolatility;
}

double CVolatilityEngine::GetVolatilityAdjustedStopLoss(double baseStop)
{
    double multiplier = 1.0;
    if(m_metrics.state == VOLATILITY_HIGH) multiplier = 1.5;
    else if(m_metrics.state == VOLATILITY_EXTREME) multiplier = 2.0;
    return baseStop * multiplier;
}

double CVolatilityEngine::GetVolatilityAdjustedTakeProfit(double baseTp)
{
    double multiplier = 1.0;
    if(m_metrics.state == VOLATILITY_HIGH) multiplier = 1.25;
    else if(m_metrics.state == VOLATILITY_EXTREME) multiplier = 1.5;
    return baseTp * multiplier;
}

void CVolatilityEngine::Reset()
{
    m_metrics = VolatilityMetrics();
    m_lastValidMetrics = VolatilityMetrics();
    m_indicatorSymbol = "";
    m_indicatorTimeframe = PERIOD_CURRENT;
    m_lastLoggedState = VOLATILITY_LOW;
}

#endif // VOLATILITY_ENGINE_MQH
