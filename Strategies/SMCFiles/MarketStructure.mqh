//+------------------------------------------------------------------+
//| MarketStructure.mqh                                              |
//| Market Structure Engine for SMC/ICT Strategy                     |
//| Implements BOS, CHoCH, Swing Points, Trend Detection             |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Multi-Strategy EA"
#property version   "2.00"
#property strict

#ifndef __SMC_MARKET_STRUCTURE_MQH__
#define __SMC_MARKET_STRUCTURE_MQH__

#include <Arrays/ArrayObj.mqh>

//+------------------------------------------------------------------+
//| Trend Direction Enum                                             |
//+------------------------------------------------------------------+
enum ENUM_SMC_TREND_DIRECTION
{
    SMC_TREND_BULLISH,
    SMC_TREND_BEARISH,
    SMC_TREND_NEUTRAL
};

//+------------------------------------------------------------------+
//| Structure Break Type                                             |
//+------------------------------------------------------------------+
enum ENUM_STRUCTURE_BREAK
{
    STRUCTURE_NONE,
    STRUCTURE_BOS,      // Break of Structure (continuation)
    STRUCTURE_CHOCH     // Change of Character (reversal)
};

//+------------------------------------------------------------------+
//| Swing Point Structure                                            |
//+------------------------------------------------------------------+
struct SSMCSwingPoint
{
    datetime time;
    double   price;
    int      barIndex;
    bool     isHigh;
    bool     isBOS;
    bool     isCHoCH;
    double   strength;
    bool     isValid;
    
    SSMCSwingPoint() : time(0), price(0), barIndex(0), isHigh(false),
                       isBOS(false), isCHoCH(false), strength(0), isValid(false) {}
};

//+------------------------------------------------------------------+
//| Market Structure Class                                           |
//+------------------------------------------------------------------+
class CSMCMarketStructure
{
private:
    string              m_symbol;
    ENUM_TIMEFRAMES     m_timeframe;
    
    // Swing points storage
    SSMCSwingPoint      m_swingHighs[];
    SSMCSwingPoint      m_swingLows[];
    int                 m_maxSwings;
    
    // Structure tracking
    ENUM_SMC_TREND_DIRECTION m_currentTrend;
    SSMCSwingPoint      m_lastBOS;
    SSMCSwingPoint      m_lastCHoCH;
    
    // Configuration
    int                 m_swingStrength;    // Bars on each side for swing validation
    double              m_minSwingSize;     // Minimum swing size in ATR
    
    // Internal methods
    double              GetATR(int period);
    bool                IsValidSwingHigh(int barIndex, int strength);
    bool                IsValidSwingLow(int barIndex, int strength);
    void                DetectBOS();
    void                DetectCHoCH();
    
public:
                        CSMCMarketStructure();
                       ~CSMCMarketStructure();
    
    // Initialization
    bool                Initialize(const string symbol, ENUM_TIMEFRAMES timeframe,
                                  int swingStrength = 3, double minSwingATR = 0.5);
    
    // Core detection
    void                DetectSwingPoints(int lookback = 100);
    ENUM_STRUCTURE_BREAK DetectStructureBreak();
    
    // Getters
    ENUM_SMC_TREND_DIRECTION GetTrend() const { return m_currentTrend; }
    bool                HasBullishBOS() const { return m_lastBOS.isValid && m_currentTrend == SMC_TREND_BULLISH; }
    bool                HasBearishBOS() const { return m_lastBOS.isValid && m_currentTrend == SMC_TREND_BEARISH; }
    bool                HasBullishCHoCH() const { return m_lastCHoCH.isValid && m_currentTrend == SMC_TREND_BULLISH; }
    bool                HasBearishCHoCH() const { return m_lastCHoCH.isValid && m_currentTrend == SMC_TREND_BEARISH; }
    
    // Swing point access
    int                 GetSwingHighCount() const { return ArraySize(m_swingHighs); }
    int                 GetSwingLowCount() const { return ArraySize(m_swingLows); }
    bool                GetLastSwingHigh(SSMCSwingPoint &swing);
    bool                GetLastSwingLow(SSMCSwingPoint &swing);
    bool                GetSwingHighAt(int index, SSMCSwingPoint &swing);
    bool                GetSwingLowAt(int index, SSMCSwingPoint &swing);
    
    // Higher Highs / Lower Lows
    bool                IsHigherHigh();
    bool                IsLowerLow();
    bool                IsHigherLow();
    bool                IsLowerHigh();
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CSMCMarketStructure::CSMCMarketStructure() :
    m_symbol(""),
    m_timeframe(PERIOD_CURRENT),
    m_maxSwings(50),
    m_currentTrend(SMC_TREND_NEUTRAL),
    m_swingStrength(3),
    m_minSwingSize(0.5)
{
    ArrayResize(m_swingHighs, 0);
    ArrayResize(m_swingLows, 0);
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CSMCMarketStructure::~CSMCMarketStructure()
{
    ArrayFree(m_swingHighs);
    ArrayFree(m_swingLows);
}

//+------------------------------------------------------------------+
//| Initialize                                                       |
//+------------------------------------------------------------------+
bool CSMCMarketStructure::Initialize(const string symbol, ENUM_TIMEFRAMES timeframe,
                                     int swingStrength, double minSwingATR)
{
    m_symbol = symbol;
    m_timeframe = timeframe;
    m_swingStrength = swingStrength;
    m_minSwingSize = minSwingATR;
    
    ArrayResize(m_swingHighs, 0);
    ArrayResize(m_swingLows, 0);
    
    m_currentTrend = SMC_TREND_NEUTRAL;
    m_lastBOS = SSMCSwingPoint();
    m_lastCHoCH = SSMCSwingPoint();
    
    return true;
}

//+------------------------------------------------------------------+
//| Get ATR Value                                                    |
//+------------------------------------------------------------------+
double CSMCMarketStructure::GetATR(int period)
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
//| Check Valid Swing High                                           |
//+------------------------------------------------------------------+
bool CSMCMarketStructure::IsValidSwingHigh(int barIndex, int strength)
{
    double high = iHigh(m_symbol, m_timeframe, barIndex);
    
    // Check bars on left
    for(int i = 1; i <= strength; i++)
    {
        if(iHigh(m_symbol, m_timeframe, barIndex + i) >= high)
            return false;
    }
    
    // Check bars on right
    for(int i = 1; i <= strength; i++)
    {
        if(iHigh(m_symbol, m_timeframe, barIndex - i) >= high)
            return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Check Valid Swing Low                                            |
//+------------------------------------------------------------------+
bool CSMCMarketStructure::IsValidSwingLow(int barIndex, int strength)
{
    double low = iLow(m_symbol, m_timeframe, barIndex);
    
    // Check bars on left
    for(int i = 1; i <= strength; i++)
    {
        if(iLow(m_symbol, m_timeframe, barIndex + i) <= low)
            return false;
    }
    
    // Check bars on right
    for(int i = 1; i <= strength; i++)
    {
        if(iLow(m_symbol, m_timeframe, barIndex - i) <= low)
            return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Detect Swing Points                                              |
//+------------------------------------------------------------------+
void CSMCMarketStructure::DetectSwingPoints(int lookback)
{
    // Clear existing swings
    ArrayResize(m_swingHighs, 0);
    ArrayResize(m_swingLows, 0);
    
    int bars = iBars(m_symbol, m_timeframe);
    if(bars < lookback) lookback = bars - 1;
    
    double atr = GetATR(14);
    if(atr <= 0) atr = 0.0001;
    
    double minSize = atr * m_minSwingSize;
    
    // Detect swing points
    for(int i = m_swingStrength; i < lookback - m_swingStrength; i++)
    {
        // Check for swing high
        if(IsValidSwingHigh(i, m_swingStrength))
        {
            double high = iHigh(m_symbol, m_timeframe, i);
            
            // Calculate swing strength (extra confirmation bars)
            double strength = (double)m_swingStrength;
            for(int j = m_swingStrength + 1; j <= m_swingStrength + 3; j++)
            {
                if(i + j < lookback && iHigh(m_symbol, m_timeframe, i + j) < high)
                    strength += 0.5;
                if(i - j >= 0 && iHigh(m_symbol, m_timeframe, i - j) < high)
                    strength += 0.5;
            }
            
            // Add swing high
            int size = ArraySize(m_swingHighs);
            if(size < m_maxSwings)
            {
                ArrayResize(m_swingHighs, size + 1);
                m_swingHighs[size].price = high;
                m_swingHighs[size].time = iTime(m_symbol, m_timeframe, i);
                m_swingHighs[size].barIndex = i;
                m_swingHighs[size].isHigh = true;
                m_swingHighs[size].strength = strength;
                m_swingHighs[size].isValid = true;
            }
        }
        
        // Check for swing low
        if(IsValidSwingLow(i, m_swingStrength))
        {
            double low = iLow(m_symbol, m_timeframe, i);
            
            // Calculate swing strength
            double strength = (double)m_swingStrength;
            for(int j = m_swingStrength + 1; j <= m_swingStrength + 3; j++)
            {
                if(i + j < lookback && iLow(m_symbol, m_timeframe, i + j) > low)
                    strength += 0.5;
                if(i - j >= 0 && iLow(m_symbol, m_timeframe, i - j) > low)
                    strength += 0.5;
            }
            
            // Add swing low
            int size = ArraySize(m_swingLows);
            if(size < m_maxSwings)
            {
                ArrayResize(m_swingLows, size + 1);
                m_swingLows[size].price = low;
                m_swingLows[size].time = iTime(m_symbol, m_timeframe, i);
                m_swingLows[size].barIndex = i;
                m_swingLows[size].isHigh = false;
                m_swingLows[size].strength = strength;
                m_swingLows[size].isValid = true;
            }
        }
    }
    
    // Detect BOS and CHoCH
    DetectBOS();
    DetectCHoCH();
}

//+------------------------------------------------------------------+
//| Detect Break of Structure (BOS)                                  |
//+------------------------------------------------------------------+
void CSMCMarketStructure::DetectBOS()
{
    m_lastBOS = SSMCSwingPoint();
    
    int highCount = ArraySize(m_swingHighs);
    int lowCount = ArraySize(m_swingLows);
    
    if(highCount < 2 || lowCount < 2) return;
    
    double lastPrice = iClose(m_symbol, m_timeframe, 0);
    
    // Bullish BOS: Price breaks above most recent swing high while making higher lows
    if(IsHigherLow() && lastPrice > m_swingHighs[0].price)
    {
        m_lastBOS = m_swingHighs[0];
        m_lastBOS.isBOS = true;
        m_currentTrend = SMC_TREND_BULLISH;
    }
    // Bearish BOS: Price breaks below most recent swing low while making lower highs
    else if(IsLowerHigh() && lastPrice < m_swingLows[0].price)
    {
        m_lastBOS = m_swingLows[0];
        m_lastBOS.isBOS = true;
        m_currentTrend = SMC_TREND_BEARISH;
    }
}

//+------------------------------------------------------------------+
//| Detect Change of Character (CHoCH)                               |
//+------------------------------------------------------------------+
void CSMCMarketStructure::DetectCHoCH()
{
    m_lastCHoCH = SSMCSwingPoint();
    
    int highCount = ArraySize(m_swingHighs);
    int lowCount = ArraySize(m_swingLows);
    
    if(highCount < 3 || lowCount < 3) return;
    
    double lastPrice = iClose(m_symbol, m_timeframe, 0);
    
    // Bullish CHoCH: Was making lower highs, now breaks above a swing high
    bool wasDowntrend = (m_swingHighs[1].price > m_swingHighs[0].price) && 
                        (m_swingHighs[2].price > m_swingHighs[1].price);
    
    if(wasDowntrend && lastPrice > m_swingHighs[0].price)
    {
        m_lastCHoCH = m_swingHighs[0];
        m_lastCHoCH.isCHoCH = true;
        m_currentTrend = SMC_TREND_BULLISH;
    }
    
    // Bearish CHoCH: Was making higher lows, now breaks below a swing low
    bool wasUptrend = (m_swingLows[1].price < m_swingLows[0].price) && 
                      (m_swingLows[2].price < m_swingLows[1].price);
    
    if(wasUptrend && lastPrice < m_swingLows[0].price)
    {
        m_lastCHoCH = m_swingLows[0];
        m_lastCHoCH.isCHoCH = true;
        m_currentTrend = SMC_TREND_BEARISH;
    }
}

//+------------------------------------------------------------------+
//| Detect Structure Break                                           |
//+------------------------------------------------------------------+
ENUM_STRUCTURE_BREAK CSMCMarketStructure::DetectStructureBreak()
{
    if(m_lastCHoCH.isValid && m_lastCHoCH.isCHoCH)
        return STRUCTURE_CHOCH;
    
    if(m_lastBOS.isValid && m_lastBOS.isBOS)
        return STRUCTURE_BOS;
    
    return STRUCTURE_NONE;
}

//+------------------------------------------------------------------+
//| Get Last Swing High                                              |
//+------------------------------------------------------------------+
bool CSMCMarketStructure::GetLastSwingHigh(SSMCSwingPoint &swing)
{
    if(ArraySize(m_swingHighs) == 0) return false;
    swing = m_swingHighs[0];
    return swing.isValid;
}

//+------------------------------------------------------------------+
//| Get Last Swing Low                                               |
//+------------------------------------------------------------------+
bool CSMCMarketStructure::GetLastSwingLow(SSMCSwingPoint &swing)
{
    if(ArraySize(m_swingLows) == 0) return false;
    swing = m_swingLows[0];
    return swing.isValid;
}

//+------------------------------------------------------------------+
//| Get Swing High At Index                                          |
//+------------------------------------------------------------------+
bool CSMCMarketStructure::GetSwingHighAt(int index, SSMCSwingPoint &swing)
{
    if(index < 0 || index >= ArraySize(m_swingHighs)) return false;
    swing = m_swingHighs[index];
    return swing.isValid;
}

//+------------------------------------------------------------------+
//| Get Swing Low At Index                                           |
//+------------------------------------------------------------------+
bool CSMCMarketStructure::GetSwingLowAt(int index, SSMCSwingPoint &swing)
{
    if(index < 0 || index >= ArraySize(m_swingLows)) return false;
    swing = m_swingLows[index];
    return swing.isValid;
}

//+------------------------------------------------------------------+
//| Is Higher High                                                   |
//+------------------------------------------------------------------+
bool CSMCMarketStructure::IsHigherHigh()
{
    if(ArraySize(m_swingHighs) < 2) return false;
    return m_swingHighs[0].price > m_swingHighs[1].price;
}

//+------------------------------------------------------------------+
//| Is Lower Low                                                     |
//+------------------------------------------------------------------+
bool CSMCMarketStructure::IsLowerLow()
{
    if(ArraySize(m_swingLows) < 2) return false;
    return m_swingLows[0].price < m_swingLows[1].price;
}

//+------------------------------------------------------------------+
//| Is Higher Low                                                    |
//+------------------------------------------------------------------+
bool CSMCMarketStructure::IsHigherLow()
{
    if(ArraySize(m_swingLows) < 2) return false;
    return m_swingLows[0].price > m_swingLows[1].price;
}

//+------------------------------------------------------------------+
//| Is Lower High                                                    |
//+------------------------------------------------------------------+
bool CSMCMarketStructure::IsLowerHigh()
{
    if(ArraySize(m_swingHighs) < 2) return false;
    return m_swingHighs[0].price < m_swingHighs[1].price;
}

#endif // __SMC_MARKET_STRUCTURE_MQH__
