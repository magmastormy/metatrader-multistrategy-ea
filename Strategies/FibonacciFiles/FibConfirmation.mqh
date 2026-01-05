//+------------------------------------------------------------------+
//| FibConfirmation.mqh                                              |
//| Confirmation Patterns for Fibonacci Entries                      |
//| Pin Bars, Engulfing, RSI Divergence, Trend Validation            |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Multi-Strategy EA"
#property version   "2.00"
#property strict

#ifndef __FIB_CONFIRMATION_MQH__
#define __FIB_CONFIRMATION_MQH__

//+------------------------------------------------------------------+
//| Confirmation Pattern Type                                        |
//+------------------------------------------------------------------+
enum ENUM_FIB_CONFIRMATION
{
    CONFIRM_NONE,
    CONFIRM_PIN_BAR,
    CONFIRM_ENGULFING,
    CONFIRM_INSIDE_BAR,
    CONFIRM_MOMENTUM,
    CONFIRM_RSI_DIVERGENCE
};

//+------------------------------------------------------------------+
//| Confirmation Result Structure                                    |
//+------------------------------------------------------------------+
struct SFibConfirmation
{
    ENUM_FIB_CONFIRMATION   type;
    bool                    isBullish;
    double                  strength;       // 0-1 score
    string                  description;
    
    SFibConfirmation() : type(CONFIRM_NONE), isBullish(false), 
                         strength(0), description("") {}
};

//+------------------------------------------------------------------+
//| Fibonacci Confirmation Class                                     |
//+------------------------------------------------------------------+
class CFibConfirmation
{
private:
    string              m_symbol;
    ENUM_TIMEFRAMES     m_timeframe;
    
    // RSI handle
    int                 m_rsiHandle;
    
    // Configuration
    double              m_pinBarRatio;          // Min wick/body ratio
    double              m_minCandleSize;        // Min candle size in pips
    int                 m_rsiPeriod;
    int                 m_rsiOverbought;
    int                 m_rsiOversold;
    
    // Internal methods
    double              GetRSI(int shift = 0);
    
public:
                        CFibConfirmation();
                       ~CFibConfirmation();
    
    // Initialization
    bool                Initialize(const string symbol, ENUM_TIMEFRAMES timeframe);
    void                Deinit();
    
    // Pattern detection
    bool                IsPinBar(int barIndex, bool &isBullish);
    bool                IsEngulfing(int barIndex, bool &isBullish);
    bool                IsInsideBar(int barIndex);
    bool                HasMomentum(bool isBullish, int barsToCheck = 3);
    bool                HasRSIDivergence(bool isBullish, int lookback = 10);
    
    // Combined confirmation check
    SFibConfirmation    GetConfirmation(double fibLevel, bool forBullish);
    bool                HasValidConfirmation(double fibLevel, bool forBullish);
    
    // Trend validation
    bool                IsTrendAligned(bool isBullish);
    double              GetTrendStrength();
    
    // Configuration
    void                SetPinBarRatio(double ratio) { m_pinBarRatio = ratio; }
    void                SetMinCandleSize(double pips) { m_minCandleSize = pips; }
    void                SetRSIPeriod(int period) { m_rsiPeriod = period; }
    void                SetRSILevels(int overbought, int oversold) 
                        { m_rsiOverbought = overbought; m_rsiOversold = oversold; }
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CFibConfirmation::CFibConfirmation() :
    m_symbol(""),
    m_timeframe(PERIOD_CURRENT),
    m_rsiHandle(INVALID_HANDLE),
    m_pinBarRatio(2.5),
    m_minCandleSize(10.0),
    m_rsiPeriod(14),
    m_rsiOverbought(70),
    m_rsiOversold(30)
{
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CFibConfirmation::~CFibConfirmation()
{
    Deinit();
}

//+------------------------------------------------------------------+
//| Initialize                                                       |
//+------------------------------------------------------------------+
bool CFibConfirmation::Initialize(const string symbol, ENUM_TIMEFRAMES timeframe)
{
    m_symbol = symbol;
    m_timeframe = timeframe;
    
    m_rsiHandle = iRSI(symbol, timeframe, m_rsiPeriod, PRICE_CLOSE);
    
    return (m_rsiHandle != INVALID_HANDLE);
}

//+------------------------------------------------------------------+
//| Deinitialize                                                     |
//+------------------------------------------------------------------+
void CFibConfirmation::Deinit()
{
    if(m_rsiHandle != INVALID_HANDLE)
    {
        IndicatorRelease(m_rsiHandle);
        m_rsiHandle = INVALID_HANDLE;
    }
}

//+------------------------------------------------------------------+
//| Get RSI                                                          |
//+------------------------------------------------------------------+
double CFibConfirmation::GetRSI(int shift)
{
    if(m_rsiHandle == INVALID_HANDLE) return 50.0;
    
    double rsi[];
    ArraySetAsSeries(rsi, true);
    
    if(CopyBuffer(m_rsiHandle, 0, shift, 1, rsi) <= 0)
        return 50.0;
    
    return rsi[0];
}

//+------------------------------------------------------------------+
//| Is Pin Bar                                                       |
//+------------------------------------------------------------------+
bool CFibConfirmation::IsPinBar(int barIndex, bool &isBullish)
{
    double open = iOpen(m_symbol, m_timeframe, barIndex);
    double close = iClose(m_symbol, m_timeframe, barIndex);
    double high = iHigh(m_symbol, m_timeframe, barIndex);
    double low = iLow(m_symbol, m_timeframe, barIndex);
    
    double body = MathAbs(close - open);
    double upperWick = high - MathMax(open, close);
    double lowerWick = MathMin(open, close) - low;
    double totalRange = high - low;
    
    double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    if(point <= 0) point = 0.0001;
    
    // Minimum candle size check
    if(totalRange < m_minCandleSize * point)
        return false;
    
    // Body must be small (< 25% of total range)
    if(body > totalRange * 0.25)
        return false;
    
    // Bullish pin bar: long lower wick, small upper wick
    if(lowerWick >= body * m_pinBarRatio && upperWick < body * 0.5)
    {
        // Close should be in upper third
        if(close >= low + (totalRange * 0.6))
        {
            isBullish = true;
            return true;
        }
    }
    
    // Bearish pin bar: long upper wick, small lower wick
    if(upperWick >= body * m_pinBarRatio && lowerWick < body * 0.5)
    {
        // Close should be in lower third
        if(close <= high - (totalRange * 0.6))
        {
            isBullish = false;
            return true;
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Is Engulfing                                                     |
//+------------------------------------------------------------------+
bool CFibConfirmation::IsEngulfing(int barIndex, bool &isBullish)
{
    double open0 = iOpen(m_symbol, m_timeframe, barIndex);
    double close0 = iClose(m_symbol, m_timeframe, barIndex);
    double open1 = iOpen(m_symbol, m_timeframe, barIndex + 1);
    double close1 = iClose(m_symbol, m_timeframe, barIndex + 1);
    
    // Bullish engulfing: previous bearish, current bullish engulfs it
    if(close1 < open1 && close0 > open0)  // Prev bear, curr bull
    {
        if(open0 <= close1 && close0 >= open1)
        {
            isBullish = true;
            return true;
        }
    }
    
    // Bearish engulfing: previous bullish, current bearish engulfs it
    if(close1 > open1 && close0 < open0)  // Prev bull, curr bear
    {
        if(open0 >= close1 && close0 <= open1)
        {
            isBullish = false;
            return true;
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Is Inside Bar                                                    |
//+------------------------------------------------------------------+
bool CFibConfirmation::IsInsideBar(int barIndex)
{
    double high0 = iHigh(m_symbol, m_timeframe, barIndex);
    double low0 = iLow(m_symbol, m_timeframe, barIndex);
    double high1 = iHigh(m_symbol, m_timeframe, barIndex + 1);
    double low1 = iLow(m_symbol, m_timeframe, barIndex + 1);
    
    return (high0 < high1 && low0 > low1);
}

//+------------------------------------------------------------------+
//| Has Momentum                                                     |
//+------------------------------------------------------------------+
bool CFibConfirmation::HasMomentum(bool isBullish, int barsToCheck)
{
    int consecutiveCount = 0;
    
    for(int i = 1; i <= barsToCheck; i++)
    {
        double close = iClose(m_symbol, m_timeframe, i);
        double open = iOpen(m_symbol, m_timeframe, i);
        
        if(isBullish && close > open)
            consecutiveCount++;
        else if(!isBullish && close < open)
            consecutiveCount++;
    }
    
    return (consecutiveCount >= 2);  // At least 2 of last 3 bars in direction
}

//+------------------------------------------------------------------+
//| Has RSI Divergence                                               |
//+------------------------------------------------------------------+
bool CFibConfirmation::HasRSIDivergence(bool isBullish, int lookback)
{
    if(m_rsiHandle == INVALID_HANDLE) return false;
    
    double rsi[];
    ArraySetAsSeries(rsi, true);
    
    if(CopyBuffer(m_rsiHandle, 0, 0, lookback, rsi) < lookback)
        return false;
    
    // Find local extremes in price and RSI
    double priceExtreme1 = 0, priceExtreme2 = 0;
    double rsiExtreme1 = 0, rsiExtreme2 = 0;
    int idx1 = -1, idx2 = -1;
    
    if(isBullish)
    {
        // Look for bullish divergence (price lower low, RSI higher low)
        for(int i = 1; i < lookback - 2; i++)
        {
            double low = iLow(m_symbol, m_timeframe, i);
            double lowPrev = iLow(m_symbol, m_timeframe, i + 1);
            double lowNext = iLow(m_symbol, m_timeframe, i - 1);
            
            if(low < lowPrev && low < lowNext)
            {
                if(idx1 < 0)
                {
                    idx1 = i;
                    priceExtreme1 = low;
                    rsiExtreme1 = rsi[i];
                }
                else if(idx2 < 0)
                {
                    idx2 = i;
                    priceExtreme2 = low;
                    rsiExtreme2 = rsi[i];
                    break;
                }
            }
        }
        
        // Check for divergence
        if(idx1 > 0 && idx2 > 0)
        {
            if(priceExtreme1 < priceExtreme2 && rsiExtreme1 > rsiExtreme2)
                return true;  // Bullish divergence
        }
    }
    else
    {
        // Look for bearish divergence (price higher high, RSI lower high)
        for(int i = 1; i < lookback - 2; i++)
        {
            double high = iHigh(m_symbol, m_timeframe, i);
            double highPrev = iHigh(m_symbol, m_timeframe, i + 1);
            double highNext = iHigh(m_symbol, m_timeframe, i - 1);
            
            if(high > highPrev && high > highNext)
            {
                if(idx1 < 0)
                {
                    idx1 = i;
                    priceExtreme1 = high;
                    rsiExtreme1 = rsi[i];
                }
                else if(idx2 < 0)
                {
                    idx2 = i;
                    priceExtreme2 = high;
                    rsiExtreme2 = rsi[i];
                    break;
                }
            }
        }
        
        // Check for divergence
        if(idx1 > 0 && idx2 > 0)
        {
            if(priceExtreme1 > priceExtreme2 && rsiExtreme1 < rsiExtreme2)
                return true;  // Bearish divergence
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Get Confirmation                                                 |
//+------------------------------------------------------------------+
SFibConfirmation CFibConfirmation::GetConfirmation(double fibLevel, bool forBullish)
{
    SFibConfirmation result;
    double price = SymbolInfoDouble(m_symbol, SYMBOL_BID);
    bool patternBullish = false;
    
    // Check for pin bar at level
    if(IsPinBar(1, patternBullish))
    {
        double low1 = iLow(m_symbol, m_timeframe, 1);
        double high1 = iHigh(m_symbol, m_timeframe, 1);
        
        // Pin bar should touch the Fib level
        if((forBullish && low1 <= fibLevel && patternBullish) ||
           (!forBullish && high1 >= fibLevel && !patternBullish))
        {
            result.type = CONFIRM_PIN_BAR;
            result.isBullish = patternBullish;
            result.strength = 0.85;
            result.description = patternBullish ? "Bullish Pin Bar at Fib" : "Bearish Pin Bar at Fib";
            return result;
        }
    }
    
    // Check for engulfing at level
    if(IsEngulfing(1, patternBullish))
    {
        if((forBullish && patternBullish) || (!forBullish && !patternBullish))
        {
            result.type = CONFIRM_ENGULFING;
            result.isBullish = patternBullish;
            result.strength = 0.80;
            result.description = patternBullish ? "Bullish Engulfing at Fib" : "Bearish Engulfing at Fib";
            return result;
        }
    }
    
    // Check for momentum
    if(HasMomentum(forBullish))
    {
        result.type = CONFIRM_MOMENTUM;
        result.isBullish = forBullish;
        result.strength = 0.65;
        result.description = forBullish ? "Bullish Momentum" : "Bearish Momentum";
        return result;
    }
    
    // Check RSI divergence
    if(HasRSIDivergence(forBullish))
    {
        result.type = CONFIRM_RSI_DIVERGENCE;
        result.isBullish = forBullish;
        result.strength = 0.75;
        result.description = forBullish ? "Bullish RSI Divergence" : "Bearish RSI Divergence";
        return result;
    }
    
    return result;
}

//+------------------------------------------------------------------+
//| Has Valid Confirmation                                           |
//+------------------------------------------------------------------+
bool CFibConfirmation::HasValidConfirmation(double fibLevel, bool forBullish)
{
    SFibConfirmation confirm = GetConfirmation(fibLevel, forBullish);
    return (confirm.type != CONFIRM_NONE && confirm.strength >= 0.60);
}

//+------------------------------------------------------------------+
//| Is Trend Aligned                                                 |
//+------------------------------------------------------------------+
bool CFibConfirmation::IsTrendAligned(bool isBullish)
{
    // Use 20/50/200 EMA alignment
    int ema20 = iMA(m_symbol, m_timeframe, 20, 0, MODE_EMA, PRICE_CLOSE);
    int ema50 = iMA(m_symbol, m_timeframe, 50, 0, MODE_EMA, PRICE_CLOSE);
    int ema200 = iMA(m_symbol, m_timeframe, 200, 0, MODE_EMA, PRICE_CLOSE);
    
    double ema20Val[], ema50Val[], ema200Val[];
    ArraySetAsSeries(ema20Val, true);
    ArraySetAsSeries(ema50Val, true);
    ArraySetAsSeries(ema200Val, true);
    
    bool result = false;
    
    if(CopyBuffer(ema20, 0, 0, 1, ema20Val) > 0 &&
       CopyBuffer(ema50, 0, 0, 1, ema50Val) > 0 &&
       CopyBuffer(ema200, 0, 0, 1, ema200Val) > 0)
    {
        double price = SymbolInfoDouble(m_symbol, SYMBOL_BID);
        
        if(isBullish)
        {
            result = (price > ema20Val[0] && ema20Val[0] > ema50Val[0] && ema50Val[0] > ema200Val[0]);
        }
        else
        {
            result = (price < ema20Val[0] && ema20Val[0] < ema50Val[0] && ema50Val[0] < ema200Val[0]);
        }
    }
    
    IndicatorRelease(ema20);
    IndicatorRelease(ema50);
    IndicatorRelease(ema200);
    
    return result;
}

//+------------------------------------------------------------------+
//| Get Trend Strength                                               |
//+------------------------------------------------------------------+
double CFibConfirmation::GetTrendStrength()
{
    int adx = iADX(m_symbol, m_timeframe, 14);
    double adxVal[];
    ArraySetAsSeries(adxVal, true);
    
    double result = 0;
    
    if(CopyBuffer(adx, 0, 0, 1, adxVal) > 0)
    {
        result = adxVal[0];
    }
    
    IndicatorRelease(adx);
    
    return result;
}

#endif // __FIB_CONFIRMATION_MQH__
