//+------------------------------------------------------------------+
//| SRTradingStrategies.mqh                                          |
//| S/R Bounce, Breakout, and Trendline Trading Logic                |
//| Copyright 2025, Multi-Strategy EA                                |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Multi-Strategy EA"
#property version   "1.00"
#property strict

#ifndef SR_TRADING_STRATEGIES_MQH
#define SR_TRADING_STRATEGIES_MQH

#include "SupportResistanceDetector.mqh"
#include "TrendlineDetector.mqh"
#include "SRSignalScorer.mqh"
#include "../../IndicatorManager.mqh"

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
    int                 m_emaFastHandle;
    int                 m_emaSlowHandle;
    int                 m_atrHandle;
    
    // Internal helpers
    bool                HasBullishRejection();
    bool                HasBearishRejection();
    bool                IsTrendAlignedBullish();
    bool                IsTrendAlignedBearish();
    double              GetEMA(int handle);
    double              GetATR(int period = 14);
    
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
    m_emaSlow(200),
    m_emaFastHandle(INVALID_HANDLE),
    m_emaSlowHandle(INVALID_HANDLE),
    m_atrHandle(INVALID_HANDLE)
{
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CSRBounceStrategy::~CSRBounceStrategy()
{
    // Handles managed by CIndicatorManager — no IndicatorRelease needed
    m_emaFastHandle = INVALID_HANDLE;
    m_emaSlowHandle = INVALID_HANDLE;
    m_atrHandle = INVALID_HANDLE;
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

    // Handles managed by CIndicatorManager — no IndicatorRelease needed
    m_emaFastHandle = INVALID_HANDLE;
    m_emaSlowHandle = INVALID_HANDLE;
    m_atrHandle = INVALID_HANDLE;

    m_emaFastHandle = CIndicatorManager::Instance().GetMAHandle(m_symbol, m_timeframe, m_emaFast, 0, MODE_EMA, PRICE_CLOSE);
    m_emaSlowHandle = CIndicatorManager::Instance().GetMAHandle(m_symbol, m_timeframe, m_emaSlow, 0, MODE_EMA, PRICE_CLOSE);
    m_atrHandle = CIndicatorManager::Instance().GetATRHandle(m_symbol, m_timeframe, 14);
    
    return (m_srDetector != NULL && m_emaFastHandle != INVALID_HANDLE && m_emaSlowHandle != INVALID_HANDLE && m_atrHandle != INVALID_HANDLE);
}

//+------------------------------------------------------------------+
//| Get Bounce Signal (Batch 103: Soft confluence scoring)           |
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

    double atr = GetATR(14);
    SSupportResistance nearestLevel;
    if(!m_srDetector.GetLevel(nearestIdx, nearestLevel))
        return result;

    double distance = MathAbs(price - nearestLevel.price);
    double tolerance = (atr > 0) ? (atr * 0.20) : (15 * SymbolInfoDouble(m_symbol, SYMBOL_POINT));

    // Batch 103: Soft confluence scoring (0-100) replaces hard AND logic
    CSRSignalScorer scorer;
    scorer.Reset();
    scorer.AddPriceAtLevel(distance <= tolerance);                                    // 30 pts
    scorer.AddCandleRejection(HasBullishRejection() || HasBearishRejection());        // 25 pts
    scorer.AddEMAAligned(IsTrendAlignedBullish() || IsTrendAlignedBearish());         // 20 pts
    if(m_trendDetector != NULL)
    {
        int touchedLineIdx = -1;
        scorer.AddTrendlineConfluence(m_trendDetector.IsAtTrendline(price, touchedLineIdx)); // 15 pts
    }
    scorer.AddMultipleTouches(nearestLevel.touches >= 3);                             // 10 pts

    if(!scorer.HasSignal())
        return result;  // Score < 60 → no signal

    // Determine direction from rejection pattern
    bool isSupport = (price >= nearestLevel.price);

    if(isSupport && HasBullishRejection())
    {
        result.signal = TRADE_SIGNAL_BUY;
        result.reason = "Bullish bounce from support";
    }
    else if(!isSupport && HasBearishRejection())
    {
        result.signal = TRADE_SIGNAL_SELL;
        result.reason = "Bearish bounce from resistance";
    }
    else
        return result;  // No directional rejection candle

    // Confidence from score (60-100 → 0.60-1.00)
    result.confidence = scorer.GetScore() / 100.0;
    result.entryPrice = price;

    atr = GetATR(14);
    double atrTargetMultiplier = 2.0;
    double atrStopMultiplier = 1.0;
    double defaultTarget = (atr > 0) ? (atr * atrTargetMultiplier) : (40 * point);
    double defaultStop = (atr > 0) ? (atr * atrStopMultiplier) : (20 * point);

    if(isSupport)
    {
        result.stopLoss = nearestLevel.price - defaultStop;
        result.takeProfit1 = price + defaultTarget;
        result.takeProfit2 = price + (defaultTarget * 2.0);
    }
    else
    {
        result.stopLoss = nearestLevel.price + defaultStop;
        result.takeProfit1 = price - defaultTarget;
        result.takeProfit2 = price - (defaultTarget * 2.0);
    }

    // Track confluence flags
    result.hasMultipleTouches = (nearestLevel.touches >= 3);
    if(m_trendDetector != NULL)
    {
        int touchedLineIdx = -1;
        result.hasTrendlineConfluence = m_trendDetector.IsAtTrendline(price, touchedLineIdx);
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
    double ema50 = GetEMA(m_emaFastHandle);
    double ema200 = GetEMA(m_emaSlowHandle);
    if(ema50 == 0 || ema200 == 0) return false;
    return (ema50 > ema200);
}

//+------------------------------------------------------------------+
//| Check Trend Aligned Bearish                                      |
//+------------------------------------------------------------------+
bool CSRBounceStrategy::IsTrendAlignedBearish()
{
    double ema50 = GetEMA(m_emaFastHandle);
    double ema200 = GetEMA(m_emaSlowHandle);
    if(ema50 == 0 || ema200 == 0) return false;
    return (ema50 < ema200);
}

//+------------------------------------------------------------------+
//| Get EMA Value                                                    |
//+------------------------------------------------------------------+
double CSRBounceStrategy::GetEMA(int handle)
{
    if(handle == INVALID_HANDLE) return 0;
    
    double value[1];
    if(CopyBuffer(handle, 0, 0, 1, value) > 0)
    {
        return value[0];
    }
    
    return 0;
}

//+------------------------------------------------------------------+
//| Get ATR Value                                                    |
//+------------------------------------------------------------------+
double CSRBounceStrategy::GetATR(int period)
{
    int handle = CIndicatorManager::Instance().GetATRHandle(m_symbol, m_timeframe, period);
    if(handle == INVALID_HANDLE) return 0;

    double atrBuf[1];
    if(CopyBuffer(handle, 0, 0, 1, atrBuf) > 0)
        return atrBuf[0];

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
    int                 m_atrHandle;
    
    bool                HasVolumeConfirmation();
    double              GetATR(int period = 14);
    bool                FalseBreakoutDetected(int &outDirection);
    
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
    m_minConfidence(0.65),
    m_atrHandle(INVALID_HANDLE)
{
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CSRBreakoutStrategy::~CSRBreakoutStrategy()
{
    // ATR handle managed by CIndicatorManager — no IndicatorRelease needed
    m_atrHandle = INVALID_HANDLE;
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
    // ATR handle managed by CIndicatorManager — no IndicatorRelease needed
    m_atrHandle = INVALID_HANDLE;
    m_atrHandle = CIndicatorManager::Instance().GetATRHandle(m_symbol, m_timeframe, 14);
    
    return (m_srDetector != NULL && m_atrHandle != INVALID_HANDLE);
}

//+------------------------------------------------------------------+
//| Get Breakout Signal (Batch 103: False breakout detection added)  |
//+------------------------------------------------------------------+
SSRSignalResult CSRBreakoutStrategy::GetSignal()
{
    SSRSignalResult result;

    if(m_srDetector == NULL)
        return result;

    double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    double price = SymbolInfoDouble(m_symbol, SYMBOL_BID);

    // Batch 103: Check for false breakout first (higher-value signal)
    int falseBreakDir = 0;
    if(FalseBreakoutDetected(falseBreakDir))
    {
        double atr = GetATR(14);
        double defaultTarget = (atr > 0) ? (atr * 1.5) : (30 * point);
        double defaultStop = (atr > 0) ? (atr * 0.8) : (15 * point);

        if(falseBreakDir == 1)  // False breakout down → buy
        {
            result.signal = TRADE_SIGNAL_BUY;
            result.entryPrice = price;
            result.stopLoss = price - defaultStop;
            result.takeProfit1 = price + defaultTarget;
            result.takeProfit2 = price + (defaultTarget * 2.0);
            result.reason = "False breakout below support";
            result.confidence = 0.70;
        }
        else if(falseBreakDir == -1)  // False breakout up → sell
        {
            result.signal = TRADE_SIGNAL_SELL;
            result.entryPrice = price;
            result.stopLoss = price + defaultStop;
            result.takeProfit1 = price - defaultTarget;
            result.takeProfit2 = price - (defaultTarget * 2.0);
            result.reason = "False breakout above resistance";
            result.confidence = 0.70;
        }

        if(result.confidence < m_minConfidence)
        {
            result.signal = TRADE_SIGNAL_NONE;
            result.confidence = 0;
        }
        return result;
    }

    // Standard breakout detection
    int brokenLevelIdx = -1;
    if(!m_srDetector.DetectBreakout(price, brokenLevelIdx))
        return result;

    if(brokenLevelIdx < 0)
        return result;

    SSupportResistance brokenLevel;
    if(!m_srDetector.GetLevel(brokenLevelIdx, brokenLevel))
        return result;

    double atr = GetATR(14);
    // Check if price is retesting the broken level
    double retestDistance = MathAbs(price - brokenLevel.price);
    double retestTolerance = (atr > 0) ? (atr * 0.15) : (15 * point);

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

    atr = GetATR(14);
    double defaultTarget = (atr > 0) ? (atr * 1.5) : (30 * point);
    double defaultStop = (atr > 0) ? (atr * 0.8) : (15 * point);

    if(price > brokenLevel.price)
    {
        // Broke resistance - look for buy on retest
        result.signal = TRADE_SIGNAL_BUY;
        result.entryPrice = price;
        result.stopLoss = brokenLevel.price - defaultStop;
        result.takeProfit1 = price + defaultTarget;
        result.takeProfit2 = price + (defaultTarget * 2.0);
        result.reason = "Breakout retest - resistance became support";
        brokenLevel.roleReversed = true;
    }
    else
    {
        // Broke support - look for sell on retest
        result.signal = TRADE_SIGNAL_SELL;
        result.entryPrice = price;
        result.stopLoss = brokenLevel.price + defaultStop;
        result.takeProfit1 = price - defaultTarget;
        result.takeProfit2 = price - (defaultTarget * 2.0);
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
//| Get ATR Value                                                    |
//+------------------------------------------------------------------+
double CSRBreakoutStrategy::GetATR(int period)
{
    int handle = CIndicatorManager::Instance().GetATRHandle(m_symbol, m_timeframe, period);
    if(handle == INVALID_HANDLE) return 0;

    double atrBuf[1];
    if(CopyBuffer(handle, 0, 0, 1, atrBuf) > 0)
        return atrBuf[0];

    return 0;
}

//+------------------------------------------------------------------+
//| Detect False Breakout (Batch 103)                                |
//| Level broken within last 3 bars then reclaimed = counter signal  |
//+------------------------------------------------------------------+
bool CSRBreakoutStrategy::FalseBreakoutDetected(int &outDirection)
{
    outDirection = 0;
    if(m_srDetector == NULL) return false;

    double price = SymbolInfoDouble(m_symbol, SYMBOL_BID);
    double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    double atr = GetATR(14);
    double tolerance = (atr > 0) ? atr * 0.20 : 15 * point;

    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    if(CopyRates(m_symbol, m_timeframe, 0, 4, rates) != 4) return false;

    // Check false breakout above resistance
    int nearestResIdx = m_srDetector.FindNearestResistance(price);
    if(nearestResIdx >= 0)
    {
        SSupportResistance resLevel;
        if(m_srDetector.GetLevel(nearestResIdx, resLevel))
        {
            bool brokeAbove = false;
            for(int i = 1; i <= 3; i++)
            {
                if(rates[i].high > resLevel.price + tolerance) { brokeAbove = true; break; }
            }
            bool backBelow = price < resLevel.price;
            if(brokeAbove && backBelow)
            {
                outDirection = -1;  // Sell signal
                return true;
            }
        }
    }

    // Check false breakout below support
    int nearestSupIdx = m_srDetector.FindNearestSupport(price);
    if(nearestSupIdx >= 0)
    {
        SSupportResistance supLevel;
        if(m_srDetector.GetLevel(nearestSupIdx, supLevel))
        {
            bool brokeBelow = false;
            for(int i = 1; i <= 3; i++)
            {
                if(rates[i].low < supLevel.price - tolerance) { brokeBelow = true; break; }
            }
            bool backAbove = price > supLevel.price;
            if(brokeBelow && backAbove)
            {
                outDirection = 1;  // Buy signal
                return true;
            }
        }
    }

    return false;
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
    int                 m_atrHandle;
    
    bool                HasBullishRejection();
    bool                HasBearishRejection();
    double              GetATR(int period = 14);
    
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
    m_minConfidence(0.65),
    m_atrHandle(INVALID_HANDLE)
{
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CTrendlineBounceStrategy::~CTrendlineBounceStrategy()
{
    // ATR handle managed by CIndicatorManager — no IndicatorRelease needed
    m_atrHandle = INVALID_HANDLE;
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
    // ATR handle managed by CIndicatorManager — no IndicatorRelease needed
    m_atrHandle = INVALID_HANDLE;
    m_atrHandle = CIndicatorManager::Instance().GetATRHandle(m_symbol, m_timeframe, 14);
    
    return (m_trendDetector != NULL && m_atrHandle != INVALID_HANDLE);
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
        double projectedPrice = m_trendDetector.ProjectTrendline(trendline, localTime);
        
        double atr = GetATR(14);
        double tolerance = (atr > 0) ? (atr * 0.20) : (15 * point);
        
        double targetMult = 2.0;
        double stopMult   = 1.0;
        double defaultTarget = (atr > 0) ? (atr * targetMult) : (40 * point);
        double defaultStop   = (atr > 0) ? (atr * stopMult) : (20 * point);
        
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
                    result.stopLoss = projectedPrice - defaultStop;
                    result.takeProfit1 = price + defaultTarget;
                    result.takeProfit2 = price + (defaultTarget * 2.0);
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
                    result.stopLoss = projectedPrice + defaultStop;
                    result.takeProfit1 = price - defaultTarget;
                    result.takeProfit2 = price - (defaultTarget * 2.0);
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

//+------------------------------------------------------------------+
//| Get ATR Value                                                    |
//+------------------------------------------------------------------+
double CTrendlineBounceStrategy::GetATR(int period)
{
    int handle = CIndicatorManager::Instance().GetATRHandle(m_symbol, m_timeframe, period);
    if(handle == INVALID_HANDLE) return 0;

    double atrBuf[1];
    if(CopyBuffer(handle, 0, 0, 1, atrBuf) > 0)
        return atrBuf[0];

    return 0;
}

#endif // __SR_TRADING_STRATEGIES_MQH__
