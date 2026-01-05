//+------------------------------------------------------------------+
//| SRTradingStrategies.mqh                                          |
//| S/R Bounce, Breakout, and Trendline Trading Logic                |
//| Copyright 2025, Multi-Strategy EA                                |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Multi-Strategy EA"
#property version   "1.00"
#property strict

#ifndef __SR_TRADING_STRATEGIES_MQH__
#define __SR_TRADING_STRATEGIES_MQH__

#include "SupportResistanceDetector.mqh"
#include "TrendlineDetector.mqh"

//+------------------------------------------------------------------+
//| S/R Signal Result Structure                                      |
//+------------------------------------------------------------------+
struct SSRSignalResult
{
    ENUM_TRADE_SIGNAL signal;
    double confidence;
    double entryPrice;
    double stopLoss;
    double takeProfit1;
    double takeProfit2;
    string reason;
    bool hasTrendlineConfluence;
    bool hasMultipleTouches;
    
    SSRSignalResult() : signal(TRADE_SIGNAL_NONE), confidence(0), entryPrice(0),
                       stopLoss(0), takeProfit1(0), takeProfit2(0), reason(""),
                       hasTrendlineConfluence(false), hasMultipleTouches(false) {}
};

//+------------------------------------------------------------------+
//| S/R Bounce Strategy                                              |
//+------------------------------------------------------------------+
class CSRBounceStrategy
{
private:
    string              m_symbol;
    ENUM_TIMEFRAMES     m_timeframe;
    
    CSupportResistanceDetector* m_srDetector;
    CTrendlineDetector*         m_trendDetector;
    
    double              m_minConfidence;
    int                 m_emaFast;
    int                 m_emaSlow;
    
    // Internal helpers
    bool                HasBullishRejection();
    bool                HasBearishRejection();
    bool                IsTrendAlignedBullish();
    bool                IsTrendAlignedBearish();
    double              GetEMA(int period);
    
public:
                        CSRBounceStrategy();
                       ~CSRBounceStrategy();
    
    bool                Initialize(const string symbol, ENUM_TIMEFRAMES timeframe,
                                  CSupportResistanceDetector* srDetector,
                                  CTrendlineDetector* trendDetector);
    
    SSRSignalResult     GetSignal();
    void                SetMinConfidence(double conf) { m_minConfidence = conf; }
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CSRBounceStrategy::CSRBounceStrategy() :
    m_symbol(""),
    m_timeframe(PERIOD_CURRENT),
    m_srDetector(NULL),
    m_trendDetector(NULL),
    m_minConfidence(0.60),
    m_emaFast(50),
    m_emaSlow(200)
{
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CSRBounceStrategy::~CSRBounceStrategy()
{
}

//+------------------------------------------------------------------+
//| Initialize                                                       |
//+------------------------------------------------------------------+
bool CSRBounceStrategy::Initialize(const string symbol, ENUM_TIMEFRAMES timeframe,
                                  CSupportResistanceDetector* srDetector,
                                  CTrendlineDetector* trendDetector)
{
    m_symbol = symbol;
    m_timeframe = timeframe;
    m_srDetector = srDetector;
    m_trendDetector = trendDetector;
    
    return (m_srDetector != NULL);
}

//+------------------------------------------------------------------+
//| Get Bounce Signal                                                |
//+------------------------------------------------------------------+
SSRSignalResult CSRBounceStrategy::GetSignal()
{
    SSRSignalResult result;
    
    if(m_srDetector == NULL)
        return result;
    
    double price = SymbolInfoDouble(m_symbol, SYMBOL_BID);
    double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    
    // Find nearest S/R level
    int nearestIdx = m_srDetector.FindNearestLevel(price, 15);
    
    if(nearestIdx < 0)
        return result;
    
    SSupportResistance nearestLevel;
    if(!m_srDetector.GetLevel(nearestIdx, nearestLevel))
        return result;
    
    double distance = MathAbs(price - nearestLevel.price);
    double tolerance = 15 * point;
    
    // Must be AT the level
    if(distance > tolerance)
        return result;
    
    // Determine if support or resistance
    bool isSupport = (price >= nearestLevel.price);
    
    if(isSupport)
    {
        // Look for bullish bounce from support
        if(HasBullishRejection() && IsTrendAlignedBullish())
        {
            result.signal = TRADE_SIGNAL_BUY;
            result.confidence = nearestLevel.strength;
            result.entryPrice = price;
            result.stopLoss = nearestLevel.price - (20 * point);
            result.takeProfit1 = price + (40 * point);
            result.takeProfit2 = price + (80 * point);
            result.reason = "Bullish bounce from support";
        }
    }
    else
    {
        // Look for bearish bounce from resistance
        if(HasBearishRejection() && IsTrendAlignedBearish())
        {
            result.signal = TRADE_SIGNAL_SELL;
            result.confidence = nearestLevel.strength;
            result.entryPrice = price;
            result.stopLoss = nearestLevel.price + (20 * point);
            result.takeProfit1 = price - (40 * point);
            result.takeProfit2 = price - (80 * point);
            result.reason = "Bearish bounce from resistance";
        }
    }
    
    // Bonus confidence for multiple touches
    if(nearestLevel.touches >= 3)
    {
        result.confidence += 0.10;
        result.hasMultipleTouches = true;
    }
    
    // Bonus for confluence with trendline
    if(m_trendDetector != NULL)
    {
        int touchedLineIdx = -1;
        if(m_trendDetector.IsAtTrendline(price, touchedLineIdx))
        {
            result.confidence += 0.15;
            result.hasTrendlineConfluence = true;
        }
    }
    
    result.confidence = MathMin(1.0, result.confidence);
    
    // Minimum threshold
    if(result.confidence < m_minConfidence)
    {
        result.signal = TRADE_SIGNAL_NONE;
        result.confidence = 0;
    }
    
    return result;
}

//+------------------------------------------------------------------+
//| Check for Bullish Rejection                                      |
//+------------------------------------------------------------------+
bool CSRBounceStrategy::HasBullishRejection()
{
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    if(CopyRates(m_symbol, m_timeframe, 0, 3, rates) != 3)
        return false;
    
    // Pin bar with long lower wick
    double lowerWick = MathMin(rates[0].open, rates[0].close) - rates[0].low;
    double body = MathAbs(rates[0].close - rates[0].open);
    double range = rates[0].high - rates[0].low;
    
    if(range > 0 && lowerWick > body * 2.0 && rates[0].close > rates[0].open)
        return true;
    
    // Bullish engulfing
    if(rates[0].close > rates[0].open &&
       rates[0].close > rates[1].open &&
       rates[0].open < rates[1].close &&
       rates[1].close < rates[1].open)
        return true;
    
    return false;
}

//+------------------------------------------------------------------+
//| Check for Bearish Rejection                                      |
//+------------------------------------------------------------------+
bool CSRBounceStrategy::HasBearishRejection()
{
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    if(CopyRates(m_symbol, m_timeframe, 0, 3, rates) != 3)
        return false;
    
    // Pin bar with long upper wick
    double upperWick = rates[0].high - MathMax(rates[0].open, rates[0].close);
    double body = MathAbs(rates[0].close - rates[0].open);
    double range = rates[0].high - rates[0].low;
    
    if(range > 0 && upperWick > body * 2.0 && rates[0].close < rates[0].open)
        return true;
    
    // Bearish engulfing
    if(rates[0].close < rates[0].open &&
       rates[0].close < rates[1].open &&
       rates[0].open > rates[1].close &&
       rates[1].close > rates[1].open)
        return true;
    
    return false;
}

//+------------------------------------------------------------------+
//| Check Trend Aligned Bullish                                      |
//+------------------------------------------------------------------+
bool CSRBounceStrategy::IsTrendAlignedBullish()
{
    double ema50 = GetEMA(m_emaFast);
    double ema200 = GetEMA(m_emaSlow);
    return (ema50 > ema200);
}

//+------------------------------------------------------------------+
//| Check Trend Aligned Bearish                                      |
//+------------------------------------------------------------------+
bool CSRBounceStrategy::IsTrendAlignedBearish()
{
    double ema50 = GetEMA(m_emaFast);
    double ema200 = GetEMA(m_emaSlow);
    return (ema50 < ema200);
}

//+------------------------------------------------------------------+
//| Get EMA Value                                                    |
//+------------------------------------------------------------------+
double CSRBounceStrategy::GetEMA(int period)
{
    int handle = iMA(m_symbol, m_timeframe, period, 0, MODE_EMA, PRICE_CLOSE);
    if(handle == INVALID_HANDLE) return 0;
    
    double value[1];
    if(CopyBuffer(handle, 0, 0, 1, value) > 0)
    {
        IndicatorRelease(handle);
        return value[0];
    }
    
    IndicatorRelease(handle);
    return 0;
}

//+------------------------------------------------------------------+
//| S/R Breakout Strategy                                            |
//+------------------------------------------------------------------+
class CSRBreakoutStrategy
{
private:
    string              m_symbol;
    ENUM_TIMEFRAMES     m_timeframe;
    
    CSupportResistanceDetector* m_srDetector;
    
    double              m_minConfidence;
    
    bool                HasVolumeConfirmation();
    
public:
                        CSRBreakoutStrategy();
                       ~CSRBreakoutStrategy();
    
    bool                Initialize(const string symbol, ENUM_TIMEFRAMES timeframe,
                                  CSupportResistanceDetector* srDetector);
    
    SSRSignalResult     GetSignal();
    void                SetMinConfidence(double conf) { m_minConfidence = conf; }
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CSRBreakoutStrategy::CSRBreakoutStrategy() :
    m_symbol(""),
    m_timeframe(PERIOD_CURRENT),
    m_srDetector(NULL),
    m_minConfidence(0.65)
{
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CSRBreakoutStrategy::~CSRBreakoutStrategy()
{
}

//+------------------------------------------------------------------+
//| Initialize                                                       |
//+------------------------------------------------------------------+
bool CSRBreakoutStrategy::Initialize(const string symbol, ENUM_TIMEFRAMES timeframe,
                                    CSupportResistanceDetector* srDetector)
{
    m_symbol = symbol;
    m_timeframe = timeframe;
    m_srDetector = srDetector;
    
    return (m_srDetector != NULL);
}

//+------------------------------------------------------------------+
//| Get Breakout Signal                                              |
//+------------------------------------------------------------------+
SSRSignalResult CSRBreakoutStrategy::GetSignal()
{
    SSRSignalResult result;
    
    if(m_srDetector == NULL)
        return result;
    
    double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    double price = SymbolInfoDouble(m_symbol, SYMBOL_BID);
    
    // Check for recent breakout
    int brokenLevelIdx = -1;
    if(!m_srDetector.DetectBreakout(price, brokenLevelIdx))
        return result;
    
    if(brokenLevelIdx < 0)
        return result;
    
    SSupportResistance brokenLevel;
    if(!m_srDetector.GetLevel(brokenLevelIdx, brokenLevel))
        return result;
    
    // Check if price is retesting the broken level
    double retestDistance = MathAbs(price - brokenLevel.price);
    double retestTolerance = 15 * point;
    
    if(retestDistance > retestTolerance)
        return result; // Not retesting yet
    
    // Validate breakout (body > 60% of range)
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    if(CopyRates(m_symbol, m_timeframe, 1, 2, rates) != 2)
        return result;
    
    double body = MathAbs(rates[0].close - rates[0].open);
    double range = rates[0].high - rates[0].low;
    
    if(range > 0 && body < range * 0.6)
        return result; // Weak breakout
    
    result.confidence = 0.75;
    
    if(price > brokenLevel.price)
    {
        // Broke resistance - look for buy on retest
        result.signal = TRADE_SIGNAL_BUY;
        result.entryPrice = price;
        result.stopLoss = brokenLevel.price - (15 * point);
        result.takeProfit1 = price + (30 * point);
        result.takeProfit2 = price + (60 * point);
        result.reason = "Breakout retest - resistance became support";
        brokenLevel.roleReversed = true;
    }
    else
    {
        // Broke support - look for sell on retest
        result.signal = TRADE_SIGNAL_SELL;
        result.entryPrice = price;
        result.stopLoss = brokenLevel.price + (15 * point);
        result.takeProfit1 = price - (30 * point);
        result.takeProfit2 = price - (60 * point);
        result.reason = "Breakout retest - support became resistance";
        brokenLevel.roleReversed = true;
    }
    
    // Bonus for strong level
    if(brokenLevel.strength > 0.80)
        result.confidence += 0.10;
    
    // Bonus for volume confirmation
    if(HasVolumeConfirmation())
        result.confidence += 0.10;
    
    result.confidence = MathMin(1.0, result.confidence);
    
    if(result.confidence < m_minConfidence)
    {
        result.signal = TRADE_SIGNAL_NONE;
        result.confidence = 0;
    }
    
    return result;
}

//+------------------------------------------------------------------+
//| Check Volume Confirmation                                        |
//+------------------------------------------------------------------+
bool CSRBreakoutStrategy::HasVolumeConfirmation()
{
    long vol0 = iVolume(m_symbol, m_timeframe, 0);
    long vol1 = iVolume(m_symbol, m_timeframe, 1);
    
    long avgVol = 0;
    for(int i = 2; i < 22; i++)
        avgVol += iVolume(m_symbol, m_timeframe, i);
    avgVol /= 20;
    
    return (vol0 > avgVol * 1.5 || vol1 > avgVol * 1.5);
}

//+------------------------------------------------------------------+
//| Trendline Bounce Strategy                                        |
//+------------------------------------------------------------------+
class CTrendlineBounceStrategy
{
private:
    string              m_symbol;
    ENUM_TIMEFRAMES     m_timeframe;
    
    CTrendlineDetector*         m_trendDetector;
    CSupportResistanceDetector* m_srDetector;
    
    double              m_minConfidence;
    
    bool                HasBullishRejection();
    bool                HasBearishRejection();
    
public:
                        CTrendlineBounceStrategy();
                       ~CTrendlineBounceStrategy();
    
    bool                Initialize(const string symbol, ENUM_TIMEFRAMES timeframe,
                                  CTrendlineDetector* trendDetector,
                                  CSupportResistanceDetector* srDetector);
    
    SSRSignalResult     GetSignal();
    void                SetMinConfidence(double conf) { m_minConfidence = conf; }
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CTrendlineBounceStrategy::CTrendlineBounceStrategy() :
    m_symbol(""),
    m_timeframe(PERIOD_CURRENT),
    m_trendDetector(NULL),
    m_srDetector(NULL),
    m_minConfidence(0.65)
{
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CTrendlineBounceStrategy::~CTrendlineBounceStrategy()
{
}

//+------------------------------------------------------------------+
//| Initialize                                                       |
//+------------------------------------------------------------------+
bool CTrendlineBounceStrategy::Initialize(const string symbol, ENUM_TIMEFRAMES timeframe,
                                         CTrendlineDetector* trendDetector,
                                         CSupportResistanceDetector* srDetector)
{
    m_symbol = symbol;
    m_timeframe = timeframe;
    m_trendDetector = trendDetector;
    m_srDetector = srDetector;
    
    return (m_trendDetector != NULL);
}

//+------------------------------------------------------------------+
//| Get Signal                                                       |
//+------------------------------------------------------------------+
SSRSignalResult CTrendlineBounceStrategy::GetSignal()
{
    SSRSignalResult result;
    
    if(m_trendDetector == NULL)
        return result;
    
    double price = SymbolInfoDouble(m_symbol, SYMBOL_BID);
    double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    datetime localTime = TimeCurrent();
    
    // Find active trendlines
    for(int i = 0; i < m_trendDetector.GetTrendlineCount(); i++)
    {
        STrendline trendline;
        if(!m_trendDetector.GetTrendline(i, trendline))
            continue;
        
        if(trendline.isBroken || !trendline.isValid)
            continue;
        
        // Project trendline to current time
        double projectedPrice = m_trendDetector.ProjectTrendline(trendline, currentTime);
        
        double tolerance = 15 * point;
        
        // Check if price at trendline
        if(MathAbs(price - projectedPrice) < tolerance)
        {
            if(trendline.type == TRENDLINE_SUPPORT)
            {
                // Bounce up from support trendline
                if(HasBullishRejection())
                {
                    result.signal = TRADE_SIGNAL_BUY;
                    result.confidence = trendline.strength;
                    result.entryPrice = price;
                    result.stopLoss = projectedPrice - (20 * point);
                    result.takeProfit1 = price + (40 * point);
                    result.takeProfit2 = price + (80 * point);
                    result.reason = "Trendline support bounce";
                }
            }
            else if(trendline.type == TRENDLINE_RESISTANCE)
            {
                // Bounce down from resistance trendline
                if(HasBearishRejection())
                {
                    result.signal = TRADE_SIGNAL_SELL;
                    result.confidence = trendline.strength;
                    result.entryPrice = price;
                    result.stopLoss = projectedPrice + (20 * point);
                    result.takeProfit1 = price - (40 * point);
                    result.takeProfit2 = price - (80 * point);
                    result.reason = "Trendline resistance bounce";
                }
            }
            
            if(result.signal != TRADE_SIGNAL_NONE)
            {
                // Update touches
                trendline.touches++;
                
                // Bonus for multiple touches
                if(trendline.touches >= 4)
                    result.confidence += 0.10;
                
                // Bonus for S/R confluence
                if(m_srDetector != NULL)
                {
                    int levelIdx = m_srDetector.FindNearestLevel(projectedPrice, 10);
                    if(levelIdx >= 0)
                    {
                        result.confidence += 0.15;
                        result.hasTrendlineConfluence = true;
                    }
                }
                
                result.confidence = MathMin(1.0, result.confidence);
                
                if(result.confidence >= m_minConfidence)
                    return result;
            }
        }
    }
    
    result.signal = TRADE_SIGNAL_NONE;
    result.confidence = 0;
    return result;
}

//+------------------------------------------------------------------+
//| Check for Bullish Rejection                                      |
//+------------------------------------------------------------------+
bool CTrendlineBounceStrategy::HasBullishRejection()
{
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    if(CopyRates(m_symbol, m_timeframe, 0, 3, rates) != 3)
        return false;
    
    double lowerWick = MathMin(rates[0].open, rates[0].close) - rates[0].low;
    double body = MathAbs(rates[0].close - rates[0].open);
    
    if(lowerWick > body * 2.0 && rates[0].close > rates[0].open)
        return true;
    
    if(rates[0].close > rates[0].open &&
       rates[0].close > rates[1].open &&
       rates[0].open < rates[1].close &&
       rates[1].close < rates[1].open)
        return true;
    
    return false;
}

//+------------------------------------------------------------------+
//| Check for Bearish Rejection                                      |
//+------------------------------------------------------------------+
bool CTrendlineBounceStrategy::HasBearishRejection()
{
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    if(CopyRates(m_symbol, m_timeframe, 0, 3, rates) != 3)
        return false;
    
    double upperWick = rates[0].high - MathMax(rates[0].open, rates[0].close);
    double body = MathAbs(rates[0].close - rates[0].open);
    
    if(upperWick > body * 2.0 && rates[0].close < rates[0].open)
        return true;
    
    if(rates[0].close < rates[0].open &&
       rates[0].close < rates[1].open &&
       rates[0].open > rates[1].close &&
       rates[1].close > rates[1].open)
        return true;
    
    return false;
}

#endif // __SR_TRADING_STRATEGIES_MQH__
