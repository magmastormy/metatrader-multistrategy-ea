//+------------------------------------------------------------------+
//| HarmonicConfirmation.mqh                                         |
//| Confirmation Requirements for Harmonic Pattern Entries           |
//| RSI, Candle Patterns, Structure Breaks                           |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Multi-Strategy EA"
#property version   "2.00"
#property strict

#ifndef __HARMONIC_CONFIRMATION_MQH__
#define __HARMONIC_CONFIRMATION_MQH__

#include "HarmonicPatternScanner.mqh"

//+------------------------------------------------------------------+
//| Confirmation Type                                                |
//+------------------------------------------------------------------+
enum ENUM_HARMONIC_CONFIRM
{
    HCONFIRM_NONE,
    HCONFIRM_RSI_EXTREME,
    HCONFIRM_CANDLE_PATTERN,
    HCONFIRM_STRUCTURE_BREAK,
    HCONFIRM_ENGULFING,
    HCONFIRM_PIN_BAR
};

//+------------------------------------------------------------------+
//| Confirmation Result                                              |
//+------------------------------------------------------------------+
struct SHarmonicConfirmation
{
    ENUM_HARMONIC_CONFIRM   type;
    bool                    isValid;
    double                  strength;
    string                  description;
    
    SHarmonicConfirmation() : type(HCONFIRM_NONE), isValid(false),
                              strength(0), description("") {}
};

//+------------------------------------------------------------------+
//| Harmonic Confirmation Class                                      |
//+------------------------------------------------------------------+
class CHarmonicConfirmation
{
private:
    string              m_symbol;
    ENUM_TIMEFRAMES     m_timeframe;
    
    // Indicator handles
    int                 m_rsiHandle;
    
    // Configuration
    int                 m_rsiPeriod;
    int                 m_rsiOverbought;
    int                 m_rsiOversold;
    int                 m_confirmBars;      // Bars to wait for confirmation
    
    // Internal methods
    double              GetRSI(int shift = 0);
    bool                HasRSIExtreme(bool forBullish);
    bool                HasPinBar(bool forBullish);
    bool                HasEngulfing(bool forBullish);
    bool                HasStructureBreak(bool forBullish);
    
public:
                        CHarmonicConfirmation();
                       ~CHarmonicConfirmation();
    
    // Initialization
    bool                Initialize(const string symbol, ENUM_TIMEFRAMES timeframe);
    void                Deinit();
    
    // Confirmation checks
    SHarmonicConfirmation   CheckConfirmation(const SHarmonicPatternData &pattern);
    bool                    HasValidConfirmation(const SHarmonicPatternData &pattern);
    
    // Individual checks
    bool                IsRSIOversold();
    bool                IsRSIOverbought();
    bool                HasReversalCandle(bool forBullish);
    
    // Configuration
    void                SetRSIPeriod(int period) { m_rsiPeriod = period; }
    void                SetRSILevels(int ob, int os) { m_rsiOverbought = ob; m_rsiOversold = os; }
    void                SetConfirmBars(int bars) { m_confirmBars = bars; }
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CHarmonicConfirmation::CHarmonicConfirmation() :
    m_symbol(""),
    m_timeframe(PERIOD_CURRENT),
    m_rsiHandle(INVALID_HANDLE),
    m_rsiPeriod(14),
    m_rsiOverbought(70),
    m_rsiOversold(30),
    m_confirmBars(3)
{
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CHarmonicConfirmation::~CHarmonicConfirmation()
{
    Deinit();
}

//+------------------------------------------------------------------+
//| Initialize                                                       |
//+------------------------------------------------------------------+
bool CHarmonicConfirmation::Initialize(const string symbol, ENUM_TIMEFRAMES timeframe)
{
    m_symbol = symbol;
    m_timeframe = timeframe;
    
    m_rsiHandle = iRSI(symbol, timeframe, m_rsiPeriod, PRICE_CLOSE);
    
    return (m_rsiHandle != INVALID_HANDLE);
}

//+------------------------------------------------------------------+
//| Deinitialize                                                     |
//+------------------------------------------------------------------+
void CHarmonicConfirmation::Deinit()
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
double CHarmonicConfirmation::GetRSI(int shift)
{
    if(m_rsiHandle == INVALID_HANDLE) return 50.0;
    
    double rsi[];
    ArraySetAsSeries(rsi, true);
    
    if(CopyBuffer(m_rsiHandle, 0, shift, 1, rsi) <= 0)
        return 50.0;
    
    return rsi[0];
}

//+------------------------------------------------------------------+
//| Is RSI Oversold                                                  |
//+------------------------------------------------------------------+
bool CHarmonicConfirmation::IsRSIOversold()
{
    return GetRSI(1) < m_rsiOversold;
}

//+------------------------------------------------------------------+
//| Is RSI Overbought                                                |
//+------------------------------------------------------------------+
bool CHarmonicConfirmation::IsRSIOverbought()
{
    return GetRSI(1) > m_rsiOverbought;
}

//+------------------------------------------------------------------+
//| Has RSI Extreme                                                  |
//+------------------------------------------------------------------+
bool CHarmonicConfirmation::HasRSIExtreme(bool forBullish)
{
    if(forBullish)
        return IsRSIOversold();
    else
        return IsRSIOverbought();
}

//+------------------------------------------------------------------+
//| Has Pin Bar                                                      |
//+------------------------------------------------------------------+
bool CHarmonicConfirmation::HasPinBar(bool forBullish)
{
    double open1 = iOpen(m_symbol, m_timeframe, 1);
    double close1 = iClose(m_symbol, m_timeframe, 1);
    double high1 = iHigh(m_symbol, m_timeframe, 1);
    double low1 = iLow(m_symbol, m_timeframe, 1);
    
    double body = MathAbs(close1 - open1);
    double range = high1 - low1;
    double upperWick = high1 - MathMax(open1, close1);
    double lowerWick = MathMin(open1, close1) - low1;
    
    if(range < body * 2) return false;  // Need significant range
    
    if(forBullish)
    {
        // Bullish pin bar: long lower wick, small upper wick
        return (lowerWick > body * 2.5 && upperWick < body * 0.5 && close1 > low1 + range * 0.5);
    }
    else
    {
        // Bearish pin bar: long upper wick, small lower wick
        return (upperWick > body * 2.5 && lowerWick < body * 0.5 && close1 < high1 - range * 0.5);
    }
}

//+------------------------------------------------------------------+
//| Has Engulfing                                                    |
//+------------------------------------------------------------------+
bool CHarmonicConfirmation::HasEngulfing(bool forBullish)
{
    double open0 = iOpen(m_symbol, m_timeframe, 1);
    double close0 = iClose(m_symbol, m_timeframe, 1);
    double open1 = iOpen(m_symbol, m_timeframe, 2);
    double close1 = iClose(m_symbol, m_timeframe, 2);
    
    if(forBullish)
    {
        // Bullish engulfing: previous bearish, current bullish engulfs
        return (close1 < open1 && close0 > open0 && 
                open0 <= close1 && close0 >= open1);
    }
    else
    {
        // Bearish engulfing: previous bullish, current bearish engulfs
        return (close1 > open1 && close0 < open0 && 
                open0 >= close1 && close0 <= open1);
    }
}

//+------------------------------------------------------------------+
//| Has Structure Break                                              |
//+------------------------------------------------------------------+
bool CHarmonicConfirmation::HasStructureBreak(bool forBullish)
{
    // Simple structure break: break of recent swing
    double recentHigh = 0, recentLow = DBL_MAX;
    
    for(int i = 2; i <= 10; i++)
    {
        recentHigh = MathMax(recentHigh, iHigh(m_symbol, m_timeframe, i));
        recentLow = MathMin(recentLow, iLow(m_symbol, m_timeframe, i));
    }
    
    double close1 = iClose(m_symbol, m_timeframe, 1);
    
    if(forBullish)
    {
        // Break above recent swing high
        return (close1 > recentHigh);
    }
    else
    {
        // Break below recent swing low
        return (close1 < recentLow);
    }
}

//+------------------------------------------------------------------+
//| Has Reversal Candle                                              |
//+------------------------------------------------------------------+
bool CHarmonicConfirmation::HasReversalCandle(bool forBullish)
{
    return HasPinBar(forBullish) || HasEngulfing(forBullish);
}

//+------------------------------------------------------------------+
//| Check Confirmation                                               |
//+------------------------------------------------------------------+
SHarmonicConfirmation CHarmonicConfirmation::CheckConfirmation(const SHarmonicPatternData &pattern)
{
    SHarmonicConfirmation result;
    bool forBullish = (pattern.direction == HARMONIC_BULLISH);
    
    // Priority 1: RSI extreme with reversal candle (best confirmation)
    if(HasRSIExtreme(forBullish) && HasReversalCandle(forBullish))
    {
        result.type = HCONFIRM_RSI_EXTREME;
        result.isValid = true;
        result.strength = 0.95;
        result.description = forBullish ? "RSI oversold + reversal candle" : "RSI overbought + reversal candle";
        return result;
    }
    
    // Priority 2: Pin bar at PRZ
    if(HasPinBar(forBullish))
    {
        result.type = HCONFIRM_PIN_BAR;
        result.isValid = true;
        result.strength = 0.85;
        result.description = forBullish ? "Bullish pin bar at PRZ" : "Bearish pin bar at PRZ";
        return result;
    }
    
    // Priority 3: Engulfing pattern
    if(HasEngulfing(forBullish))
    {
        result.type = HCONFIRM_ENGULFING;
        result.isValid = true;
        result.strength = 0.80;
        result.description = forBullish ? "Bullish engulfing at PRZ" : "Bearish engulfing at PRZ";
        return result;
    }
    
    // Priority 4: RSI extreme alone
    if(HasRSIExtreme(forBullish))
    {
        result.type = HCONFIRM_RSI_EXTREME;
        result.isValid = true;
        result.strength = 0.65;
        result.description = forBullish ? "RSI oversold" : "RSI overbought";
        return result;
    }
    
    // Priority 5: Structure break (counter-trend confirmation)
    if(HasStructureBreak(forBullish))
    {
        result.type = HCONFIRM_STRUCTURE_BREAK;
        result.isValid = true;
        result.strength = 0.75;
        result.description = forBullish ? "Bullish structure break" : "Bearish structure break";
        return result;
    }
    
    return result;
}

//+------------------------------------------------------------------+
//| Has Valid Confirmation                                           |
//+------------------------------------------------------------------+
bool CHarmonicConfirmation::HasValidConfirmation(const SHarmonicPatternData &pattern)
{
    SHarmonicConfirmation confirm = CheckConfirmation(pattern);
    return (confirm.isValid && confirm.strength >= 0.65);
}

#endif // __HARMONIC_CONFIRMATION_MQH__
