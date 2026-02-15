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
    
    // Diagnostics
    CSignalDiagnostics* m_diagnostics;
    
    // Internal methods
    bool InitializeIndicators(const string symbol, ENUM_TIMEFRAMES timeframe);
    bool IndicatorsReadyForRead(int minBars);
    void ReleaseIndicators();
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
    
    return true;
}

bool CTrendEngine::IndicatorsReadyForRead(int minBars)
{
    int fastBars = BarsCalculated(m_handleMAFast);
    int medBars = BarsCalculated(m_handleMAMedium);
    int slowBars = BarsCalculated(m_handleMASlow);
    int adxBars = BarsCalculated(m_handleADX);
    int atrBars = BarsCalculated(m_handleATR);

    if(fastBars < minBars || medBars < minBars || slowBars < minBars || adxBars < minBars || atrBars < minBars)
    {
        datetime nowTime = TimeCurrent();
        if((nowTime - m_lastIndicatorErrorLog) >= 60)
        {
            PrintFormat("[TrendEngine] Indicators warming up for %s %s | MAf=%d MAm=%d MAs=%d ADX=%d ATR=%d need=%d",
                        m_indicatorSymbol, EnumToString(m_indicatorTimeframe),
                        fastBars, medBars, slowBars, adxBars, atrBars, minBars);
            m_lastIndicatorErrorLog = nowTime;
        }
        return false;
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
    
    ResetLastError();
    if(CopyBuffer(m_handleMAFast, 0, 0, 5, ma_fast) != 5 ||
       CopyBuffer(m_handleMAMedium, 0, 0, 5, ma_medium) != 5 ||
       CopyBuffer(m_handleMASlow, 0, 0, 5, ma_slow) != 5)
    {
        datetime nowTime = TimeCurrent();
        if(m_diagnostics != NULL && (nowTime - m_lastIndicatorErrorLog) >= 30)
        {
            int err = GetLastError();
            m_diagnostics.LogStrategyError("TrendEngine", "MA_BUFFER_COPY_FAILED",
                                          StringFormat("Failed to copy MA buffer data for %s %s (err=%d)",
                                                       symbol, EnumToString(timeframe), err));
            m_lastIndicatorErrorLog = nowTime;
        }
        return false;
    }
    
    ResetLastError();
    if(CopyBuffer(m_handleADX, 0, 0, 1, adx) != 1 ||
       CopyBuffer(m_handleADX, 1, 0, 1, plusDI) != 1 ||
       CopyBuffer(m_handleADX, 2, 0, 1, minusDI) != 1)
    {
        datetime nowTime = TimeCurrent();
        if(m_diagnostics != NULL && (nowTime - m_lastIndicatorErrorLog) >= 30)
        {
            int err = GetLastError();
            m_diagnostics.LogStrategyError("TrendEngine", "ADX_BUFFER_COPY_FAILED",
                                          StringFormat("Failed to copy ADX buffer data for %s %s (err=%d)",
                                                       symbol, EnumToString(timeframe), err));
            m_lastIndicatorErrorLog = nowTime;
        }
        return false;
    }
    
    ResetLastError();
    if(CopyBuffer(m_handleATR, 0, 0, 1, atr) != 1)
    {
        datetime nowTime = TimeCurrent();
        if(m_diagnostics != NULL && (nowTime - m_lastIndicatorErrorLog) >= 30)
        {
            int err = GetLastError();
            m_diagnostics.LogStrategyError("TrendEngine", "ATR_BUFFER_COPY_FAILED",
                                          StringFormat("Failed to copy ATR buffer data for %s %s (err=%d)",
                                                       symbol, EnumToString(timeframe), err));
            m_lastIndicatorErrorLog = nowTime;
        }
        return false;
    }
    
    // Calculate trend strength
    m_currentTrend.strength = CalculateTrendStrength(ma_fast, ma_medium, ma_slow, adx[0]);
    
    // Calculate trend angle
    m_currentTrend.angle = CalculateTrendAngle(ma_medium, 5);
    
    // Calculate momentum
    m_currentTrend.momentum = CalculateMomentum(symbol, timeframe, 14);
    
    // Set volatility
    m_currentTrend.volatility = atr[0];
    
    // Determine trend type
    m_currentTrend.type = DetermineTrendType(m_currentTrend.strength, m_currentTrend.angle, adx[0]);
    
    // Check acceleration/deceleration
    double prevMomentum = m_currentTrend.momentum;
    double currMomentum = CalculateMomentum(symbol, timeframe, 7);
    m_currentTrend.isAccelerating = currMomentum > prevMomentum && m_currentTrend.strength > 50;
    m_currentTrend.isDecelerating = currMomentum < prevMomentum && m_currentTrend.strength < 50;
    
    // Update timestamp
    m_currentTrend.lastUpdate = TimeCurrent();
    
    // Log trend update
    if(m_diagnostics != NULL)
    {
        datetime nowTime = TimeCurrent();
        if(m_currentTrend.type != m_lastLoggedTrendType || (nowTime - m_lastTrendLogTime) >= 300)
        {
            string trendStr = EnumToString(m_currentTrend.type);
            string msg = StringFormat("Trend: %s | Strength: %.1f | Angle: %.1f | ADX: %.1f",
                                      trendStr, m_currentTrend.strength, m_currentTrend.angle, adx[0]);
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
    
    // Analyze the timeframe
    if(UpdateTrend(symbol, timeframe))
    {
        state = m_currentTrend;
    }
    
    // Restore previous state
    m_currentTrend = savedState;
    
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
    ReleaseIndicators();
}


// Duplicate methods removed - already defined above


#endif // TREND_ENGINE_MQH
