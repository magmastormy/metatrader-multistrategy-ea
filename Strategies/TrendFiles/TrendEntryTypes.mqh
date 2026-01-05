//+------------------------------------------------------------------+
//| TrendEntryTypes.mqh                                              |
//| Multiple Entry Types for Trend Strategy                          |
//| Implements Early, Pullback, and Continuation entries             |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Multi-Strategy EA"
#property version   "2.00"
#property strict

#ifndef __TREND_ENTRY_TYPES_MQH__
#define __TREND_ENTRY_TYPES_MQH__

#include "MultiEMASystem.mqh"

//+------------------------------------------------------------------+
//| Entry Type Enum                                                  |
//+------------------------------------------------------------------+
enum ENUM_TREND_ENTRY_TYPE
{
    ENTRY_NONE,
    ENTRY_EARLY_TREND,      // 8/21 crossover (early signal)
    ENTRY_PULLBACK,         // Price returns to 21 EMA
    ENTRY_CONTINUATION,     // Strong trend continuation
    ENTRY_CLASSIC_CROSS     // 50/200 crossover (late but reliable)
};

//+------------------------------------------------------------------+
//| Entry Signal Structure                                           |
//+------------------------------------------------------------------+
struct STrendEntrySignal
{
    ENUM_TREND_ENTRY_TYPE   type;
    ENUM_TRADE_SIGNAL       direction;
    double                  confidence;
    double                  entryPrice;
    double                  stopLoss;
    double                  takeProfit;
    string                  reason;
    
    STrendEntrySignal() : type(ENTRY_NONE), direction(TRADE_SIGNAL_NONE),
                          confidence(0), entryPrice(0), stopLoss(0),
                          takeProfit(0), reason("") {}
};

//+------------------------------------------------------------------+
//| Trend Entry Types Class                                          |
//+------------------------------------------------------------------+
class CTrendEntryTypes
{
private:
    string              m_symbol;
    ENUM_TIMEFRAMES     m_timeframe;
    
    // Reference to EMA system
    CMultiEMASystem*    m_emaSystem;
    bool                m_ownEmaSystem;
    
    // Configuration
    double              m_pullbackTolerance;    // Pips tolerance for pullback
    int                 m_minConsistencyBars;   // Min bars for continuation entry
    double              m_minADXForContinuation; // Min ADX for continuation
    
    // Internal methods
    bool                HasBullishRejection();
    bool                HasBearishRejection();
    bool                HasBullishMomentum();
    bool                HasBearishMomentum();
    double              GetATR(int period = 14);
    
public:
                        CTrendEntryTypes();
                       ~CTrendEntryTypes();
    
    // Initialization
    bool                Initialize(string symbol, ENUM_TIMEFRAMES timeframe,
                                  CMultiEMASystem* emaSystem = NULL);
    void                Deinit();
    
    // Update
    void                Update();
    
    // Entry detection
    STrendEntrySignal   GetEarlyTrendEntry();
    STrendEntrySignal   GetPullbackEntry();
    STrendEntrySignal   GetContinuationEntry();
    STrendEntrySignal   GetClassicCrossEntry();
    
    // Best entry selection
    STrendEntrySignal   GetBestEntry();
    
    // Configuration
    void                SetPullbackTolerance(double pips) { m_pullbackTolerance = pips; }
    void                SetMinConsistencyBars(int bars) { m_minConsistencyBars = bars; }
    void                SetMinADXForContinuation(double adx) { m_minADXForContinuation = adx; }
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CTrendEntryTypes::CTrendEntryTypes() :
    m_symbol(""),
    m_timeframe(PERIOD_CURRENT),
    m_emaSystem(NULL),
    m_ownEmaSystem(false),
    m_pullbackTolerance(15.0),
    m_minConsistencyBars(10),
    m_minADXForContinuation(35.0)
{
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CTrendEntryTypes::~CTrendEntryTypes()
{
    Deinit();
}

//+------------------------------------------------------------------+
//| Initialize                                                       |
//+------------------------------------------------------------------+
bool CTrendEntryTypes::Initialize(string symbol, ENUM_TIMEFRAMES timeframe,
                                  CMultiEMASystem* emaSystem)
{
    m_symbol = symbol;
    m_timeframe = timeframe;
    
    if(emaSystem != NULL)
    {
        m_emaSystem = emaSystem;
        m_ownEmaSystem = false;
    }
    else
    {
        m_emaSystem = new CMultiEMASystem();
        if(m_emaSystem != NULL)
        {
            m_emaSystem.Initialize(symbol, timeframe);
            m_ownEmaSystem = true;
        }
    }
    
    return (m_emaSystem != NULL);
}

//+------------------------------------------------------------------+
//| Deinitialize                                                     |
//+------------------------------------------------------------------+
void CTrendEntryTypes::Deinit()
{
    if(m_ownEmaSystem && m_emaSystem != NULL)
    {
        delete m_emaSystem;
        m_emaSystem = NULL;
    }
}

//+------------------------------------------------------------------+
//| Update                                                           |
//+------------------------------------------------------------------+
void CTrendEntryTypes::Update()
{
    if(m_emaSystem != NULL && m_ownEmaSystem)
        m_emaSystem.Update();
}

//+------------------------------------------------------------------+
//| Get ATR                                                          |
//+------------------------------------------------------------------+
double CTrendEntryTypes::GetATR(int period)
{
    int handle = iATR(m_symbol, m_timeframe, period);
    if(handle == INVALID_HANDLE) return 0;
    
    double atr[];
    ArraySetAsSeries(atr, true);
    if(CopyBuffer(handle, 0, 0, 1, atr) <= 0)
    {
        IndicatorRelease(handle);
        return 0;
    }
    
    IndicatorRelease(handle);
    return atr[0];
}

//+------------------------------------------------------------------+
//| Has Bullish Rejection                                            |
//+------------------------------------------------------------------+
bool CTrendEntryTypes::HasBullishRejection()
{
    double open1 = iOpen(m_symbol, m_timeframe, 1);
    double close1 = iClose(m_symbol, m_timeframe, 1);
    double high1 = iHigh(m_symbol, m_timeframe, 1);
    double low1 = iLow(m_symbol, m_timeframe, 1);
    
    double body = MathAbs(close1 - open1);
    double lowerWick = MathMin(open1, close1) - low1;
    double upperWick = high1 - MathMax(open1, close1);
    
    // Pin bar: long lower wick, small body
    bool isPinBar = (lowerWick > body * 2.0 && upperWick < body * 0.5);
    
    // Bullish engulfing
    double open2 = iOpen(m_symbol, m_timeframe, 2);
    double close2 = iClose(m_symbol, m_timeframe, 2);
    bool isEngulfing = (close2 < open2) && (close1 > open1) && 
                       (close1 > open2) && (open1 < close2);
    
    return (isPinBar || isEngulfing);
}

//+------------------------------------------------------------------+
//| Has Bearish Rejection                                            |
//+------------------------------------------------------------------+
bool CTrendEntryTypes::HasBearishRejection()
{
    double open1 = iOpen(m_symbol, m_timeframe, 1);
    double close1 = iClose(m_symbol, m_timeframe, 1);
    double high1 = iHigh(m_symbol, m_timeframe, 1);
    double low1 = iLow(m_symbol, m_timeframe, 1);
    
    double body = MathAbs(close1 - open1);
    double lowerWick = MathMin(open1, close1) - low1;
    double upperWick = high1 - MathMax(open1, close1);
    
    // Pin bar: long upper wick, small body
    bool isPinBar = (upperWick > body * 2.0 && lowerWick < body * 0.5);
    
    // Bearish engulfing
    double open2 = iOpen(m_symbol, m_timeframe, 2);
    double close2 = iClose(m_symbol, m_timeframe, 2);
    bool isEngulfing = (close2 > open2) && (close1 < open1) && 
                       (close1 < open2) && (open1 > close2);
    
    return (isPinBar || isEngulfing);
}

//+------------------------------------------------------------------+
//| Has Bullish Momentum                                             |
//+------------------------------------------------------------------+
bool CTrendEntryTypes::HasBullishMomentum()
{
    double close0 = iClose(m_symbol, m_timeframe, 0);
    double close1 = iClose(m_symbol, m_timeframe, 1);
    double close2 = iClose(m_symbol, m_timeframe, 2);
    
    // 3 consecutive higher closes
    return (close0 > close1 && close1 > close2);
}

//+------------------------------------------------------------------+
//| Has Bearish Momentum                                             |
//+------------------------------------------------------------------+
bool CTrendEntryTypes::HasBearishMomentum()
{
    double close0 = iClose(m_symbol, m_timeframe, 0);
    double close1 = iClose(m_symbol, m_timeframe, 1);
    double close2 = iClose(m_symbol, m_timeframe, 2);
    
    // 3 consecutive lower closes
    return (close0 < close1 && close1 < close2);
}

//+------------------------------------------------------------------+
//| Get Early Trend Entry (8/21 Cross)                               |
//+------------------------------------------------------------------+
STrendEntrySignal CTrendEntryTypes::GetEarlyTrendEntry()
{
    STrendEntrySignal signal;
    if(m_emaSystem == NULL) return signal;
    
    double price = SymbolInfoDouble(m_symbol, SYMBOL_BID);
    double atr = GetATR(14);
    
    // Check for 8/21 crossover with 50/200 alignment
    bool goldenCross = m_emaSystem.HasGoldenCross8_21();
    bool deathCross = m_emaSystem.HasDeathCross8_21();
    
    if(goldenCross)
    {
        // Validate with 50/200 alignment (bullish context)
        bool uptrendContext = (m_emaSystem.GetEMA50(0) > m_emaSystem.GetEMA200(0));
        
        if(uptrendContext)
        {
            signal.type = ENTRY_EARLY_TREND;
            signal.direction = TRADE_SIGNAL_BUY;
            signal.confidence = 0.70;
            signal.entryPrice = price;
            signal.stopLoss = m_emaSystem.GetEMA21(0) - (atr * 1.5);
            signal.takeProfit = price + (atr * 3.0);
            signal.reason = "8/21 Golden Cross in bullish context";
            
            // Boost confidence if ADX is strong
            if(m_emaSystem.GetADX() > 25)
                signal.confidence += 0.05;
        }
    }
    else if(deathCross)
    {
        // Validate with 50/200 alignment (bearish context)
        bool downtrendContext = (m_emaSystem.GetEMA50(0) < m_emaSystem.GetEMA200(0));
        
        if(downtrendContext)
        {
            signal.type = ENTRY_EARLY_TREND;
            signal.direction = TRADE_SIGNAL_SELL;
            signal.confidence = 0.70;
            signal.entryPrice = price;
            signal.stopLoss = m_emaSystem.GetEMA21(0) + (atr * 1.5);
            signal.takeProfit = price - (atr * 3.0);
            signal.reason = "8/21 Death Cross in bearish context";
            
            if(m_emaSystem.GetADX() > 25)
                signal.confidence += 0.05;
        }
    }
    
    return signal;
}

//+------------------------------------------------------------------+
//| Get Pullback Entry (Price returns to 21 EMA)                     |
//+------------------------------------------------------------------+
STrendEntrySignal CTrendEntryTypes::GetPullbackEntry()
{
    STrendEntrySignal signal;
    if(m_emaSystem == NULL) return signal;
    
    double price = SymbolInfoDouble(m_symbol, SYMBOL_BID);
    double atr = GetATR(14);
    double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    if(point <= 0) point = 0.0001;
    
    STrendState trend = m_emaSystem.GetTrendState();
    
    // Only in established trends
    if(!trend.isUptrend && !trend.isDowntrend)
        return signal;
    
    // Check if price is at 21 EMA
    double ema21 = m_emaSystem.GetEMA21(0);
    double ema50 = m_emaSystem.GetEMA50(0);
    double distance = MathAbs(price - ema21) / point;
    
    if(distance > m_pullbackTolerance)
        return signal;
    
    if(trend.isUptrend && ema21 > ema50)
    {
        // Bullish pullback - look for rejection at 21 EMA
        if(HasBullishRejection())
        {
            signal.type = ENTRY_PULLBACK;
            signal.direction = TRADE_SIGNAL_BUY;
            signal.confidence = 0.75;
            signal.entryPrice = price;
            signal.stopLoss = ema21 - (atr * 1.5);
            signal.takeProfit = price + (atr * 3.5);
            signal.reason = "Bullish pullback to 21 EMA with rejection";
            
            // Boost for strong trend
            if(trend.strength > 30)
                signal.confidence += 0.05;
        }
    }
    else if(trend.isDowntrend && ema21 < ema50)
    {
        // Bearish pullback - look for rejection at 21 EMA
        if(HasBearishRejection())
        {
            signal.type = ENTRY_PULLBACK;
            signal.direction = TRADE_SIGNAL_SELL;
            signal.confidence = 0.75;
            signal.entryPrice = price;
            signal.stopLoss = ema21 + (atr * 1.5);
            signal.takeProfit = price - (atr * 3.5);
            signal.reason = "Bearish pullback to 21 EMA with rejection";
            
            if(trend.strength > 30)
                signal.confidence += 0.05;
        }
    }
    
    return signal;
}

//+------------------------------------------------------------------+
//| Get Continuation Entry (Strong Trend)                            |
//+------------------------------------------------------------------+
STrendEntrySignal CTrendEntryTypes::GetContinuationEntry()
{
    STrendEntrySignal signal;
    if(m_emaSystem == NULL) return signal;
    
    double price = SymbolInfoDouble(m_symbol, SYMBOL_BID);
    double atr = GetATR(14);
    
    STrendState trend = m_emaSystem.GetTrendState();
    
    // Only in very strong, consistent trends
    if(trend.strength < m_minADXForContinuation)
        return signal;
    
    if(trend.consistency < m_minConsistencyBars)
        return signal;
    
    double ema8 = m_emaSystem.GetEMA8(0);
    
    if(trend.isUptrend && price > ema8)
    {
        // Price above 8 EMA in strong uptrend - add to position
        if(HasBullishMomentum())
        {
            signal.type = ENTRY_CONTINUATION;
            signal.direction = TRADE_SIGNAL_BUY;
            signal.confidence = 0.80;
            signal.entryPrice = price;
            signal.stopLoss = ema8 - (atr * 1.0);
            signal.takeProfit = price + (atr * 4.0);
            signal.reason = StringFormat("Continuation in strong uptrend (ADX: %.1f, %d bars)", 
                                         trend.strength, trend.consistency);
            
            // Extra boost for very strong trends
            if(trend.strength > 45)
                signal.confidence += 0.05;
        }
    }
    else if(trend.isDowntrend && price < ema8)
    {
        // Price below 8 EMA in strong downtrend
        if(HasBearishMomentum())
        {
            signal.type = ENTRY_CONTINUATION;
            signal.direction = TRADE_SIGNAL_SELL;
            signal.confidence = 0.80;
            signal.entryPrice = price;
            signal.stopLoss = ema8 + (atr * 1.0);
            signal.takeProfit = price - (atr * 4.0);
            signal.reason = StringFormat("Continuation in strong downtrend (ADX: %.1f, %d bars)", 
                                         trend.strength, trend.consistency);
            
            if(trend.strength > 45)
                signal.confidence += 0.05;
        }
    }
    
    return signal;
}

//+------------------------------------------------------------------+
//| Get Classic Cross Entry (50/200)                                 |
//+------------------------------------------------------------------+
STrendEntrySignal CTrendEntryTypes::GetClassicCrossEntry()
{
    STrendEntrySignal signal;
    if(m_emaSystem == NULL) return signal;
    
    double price = SymbolInfoDouble(m_symbol, SYMBOL_BID);
    double atr = GetATR(14);
    
    // Check for 50/200 crossover (classic golden/death cross)
    bool goldenCross = m_emaSystem.HasGoldenCross50_200();
    bool deathCross = m_emaSystem.HasDeathCross50_200();
    
    if(goldenCross)
    {
        signal.type = ENTRY_CLASSIC_CROSS;
        signal.direction = TRADE_SIGNAL_BUY;
        signal.confidence = 0.85;  // High confidence for this rare signal
        signal.entryPrice = price;
        signal.stopLoss = m_emaSystem.GetEMA200(0) - (atr * 2.0);
        signal.takeProfit = price + (atr * 5.0);
        signal.reason = "50/200 Golden Cross (major trend change)";
    }
    else if(deathCross)
    {
        signal.type = ENTRY_CLASSIC_CROSS;
        signal.direction = TRADE_SIGNAL_SELL;
        signal.confidence = 0.85;
        signal.entryPrice = price;
        signal.stopLoss = m_emaSystem.GetEMA200(0) + (atr * 2.0);
        signal.takeProfit = price - (atr * 5.0);
        signal.reason = "50/200 Death Cross (major trend change)";
    }
    
    return signal;
}

//+------------------------------------------------------------------+
//| Get Best Entry                                                   |
//+------------------------------------------------------------------+
STrendEntrySignal CTrendEntryTypes::GetBestEntry()
{
    STrendEntrySignal signals[4];
    
    // Get all entry types
    signals[0] = GetEarlyTrendEntry();
    signals[1] = GetPullbackEntry();
    signals[2] = GetContinuationEntry();
    signals[3] = GetClassicCrossEntry();
    
    // Find best signal
    STrendEntrySignal bestSignal;
    
    for(int i = 0; i < 4; i++)
    {
        if(signals[i].direction != TRADE_SIGNAL_NONE &&
           signals[i].confidence > bestSignal.confidence)
        {
            bestSignal = signals[i];
        }
    }
    
    return bestSignal;
}

#endif // __TREND_ENTRY_TYPES_MQH__
