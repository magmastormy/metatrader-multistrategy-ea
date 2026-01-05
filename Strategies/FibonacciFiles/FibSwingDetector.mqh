//+------------------------------------------------------------------+
//| FibSwingDetector.mqh                                             |
//| Efficient Swing Point Detection for Fibonacci Strategy           |
//| Finds ALL significant swings, not just first pair                |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Multi-Strategy EA"
#property version   "2.00"
#property strict

#ifndef __FIB_SWING_DETECTOR_MQH__
#define __FIB_SWING_DETECTOR_MQH__

//+------------------------------------------------------------------+
//| Swing Point Structure                                            |
//+------------------------------------------------------------------+
struct SFibSwingPoint
{
    datetime    time;
    double      price;
    int         barIndex;
    bool        isHigh;
    double      strength;     // Confirmation bars on each side
    bool        isValid;
    bool        isMajor;      // Significant swing (> 0.5 ATR)
    
    SFibSwingPoint() : time(0), price(0), barIndex(0), isHigh(false),
                       strength(0), isValid(false), isMajor(false) {}
};

//+------------------------------------------------------------------+
//| Swing Pair for Fibonacci Calculation                             |
//+------------------------------------------------------------------+
struct SFibSwingPair
{
    SFibSwingPoint  high;
    SFibSwingPoint  low;
    bool            isBullish;    // Low before High = bullish setup
    double          range;
    datetime        createdTime;
    
    SFibSwingPair() : isBullish(false), range(0), createdTime(0) {}
};

//+------------------------------------------------------------------+
//| Fibonacci Swing Detector Class                                   |
//+------------------------------------------------------------------+
class CFibSwingDetector
{
private:
    string              m_symbol;
    ENUM_TIMEFRAMES     m_timeframe;
    
    // Swing storage
    SFibSwingPoint      m_swingHighs[];
    SFibSwingPoint      m_swingLows[];
    int                 m_maxSwings;
    int                 m_highCount;
    int                 m_lowCount;
    
    // Swing pairs for Fib calculation
    SFibSwingPair       m_swingPairs[];
    int                 m_pairCount;
    int                 m_maxPairs;
    
    // Configuration
    int                 m_confirmBars;      // Bars on each side for confirmation
    double              m_minSwingATR;      // Minimum swing size in ATR
    int                 m_lookback;         // Bars to scan
    
    // Internal methods
    double              GetATR(int period = 14);
    double              CalculateSwingStrength(int barIndex, bool isHigh);
    bool                IsValidSwingHigh(int barIndex);
    bool                IsValidSwingLow(int barIndex);
    void                BuildSwingPairs();
    
public:
                        CFibSwingDetector();
                       ~CFibSwingDetector();
    
    // Initialization
    bool                Initialize(const string symbol, ENUM_TIMEFRAMES timeframe,
                                  int confirmBars = 3, double minSwingATR = 0.5);
    
    // Detection
    void                DetectSwings(int lookback = 100);
    void                Update();
    
    // Getters - Swing Points
    int                 GetSwingHighCount() const { return m_highCount; }
    int                 GetSwingLowCount() const { return m_lowCount; }
    bool                GetSwingHighAt(int index, SFibSwingPoint &swing);
    bool                GetSwingLowAt(int index, SFibSwingPoint &swing);
    bool                GetLastSwingHigh(SFibSwingPoint &swing);
    bool                GetLastSwingLow(SFibSwingPoint &swing);
    
    // Getters - Swing Pairs
    int                 GetSwingPairCount() const { return m_pairCount; }
    bool                GetSwingPairAt(int index, SFibSwingPair &pair);
    bool                GetLatestBullishPair(SFibSwingPair &pair);
    bool                GetLatestBearishPair(SFibSwingPair &pair);
    
    // Major swings only
    bool                GetMajorSwings(SFibSwingPoint &swings[], int maxCount);
    
    // Configuration
    void                SetConfirmBars(int bars) { m_confirmBars = bars; }
    void                SetMinSwingATR(double atr) { m_minSwingATR = atr; }
    void                SetLookback(int bars) { m_lookback = bars; }
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CFibSwingDetector::CFibSwingDetector() :
    m_symbol(""),
    m_timeframe(PERIOD_CURRENT),
    m_maxSwings(50),
    m_highCount(0),
    m_lowCount(0),
    m_maxPairs(20),
    m_pairCount(0),
    m_confirmBars(3),
    m_minSwingATR(0.5),
    m_lookback(100)
{
    ArrayResize(m_swingHighs, 0);
    ArrayResize(m_swingLows, 0);
    ArrayResize(m_swingPairs, 0);
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CFibSwingDetector::~CFibSwingDetector()
{
    ArrayFree(m_swingHighs);
    ArrayFree(m_swingLows);
    ArrayFree(m_swingPairs);
}

//+------------------------------------------------------------------+
//| Initialize                                                       |
//+------------------------------------------------------------------+
bool CFibSwingDetector::Initialize(const string symbol, ENUM_TIMEFRAMES timeframe,
                                   int confirmBars, double minSwingATR)
{
    m_symbol = symbol;
    m_timeframe = timeframe;
    m_confirmBars = confirmBars;
    m_minSwingATR = minSwingATR;
    
    ArrayResize(m_swingHighs, 0);
    ArrayResize(m_swingLows, 0);
    ArrayResize(m_swingPairs, 0);
    m_highCount = 0;
    m_lowCount = 0;
    m_pairCount = 0;
    
    return true;
}

//+------------------------------------------------------------------+
//| Get ATR                                                          |
//+------------------------------------------------------------------+
double CFibSwingDetector::GetATR(int period)
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
//| Calculate Swing Strength                                         |
//+------------------------------------------------------------------+
double CFibSwingDetector::CalculateSwingStrength(int barIndex, bool isHigh)
{
    double strength = (double)m_confirmBars;
    
    // Check extra bars beyond minimum confirmation
    for(int i = m_confirmBars + 1; i <= m_confirmBars + 3; i++)
    {
        if(barIndex + i >= m_lookback || barIndex - i < 0) break;
        
        if(isHigh)
        {
            double high = iHigh(m_symbol, m_timeframe, barIndex);
            if(iHigh(m_symbol, m_timeframe, barIndex + i) < high) strength += 0.5;
            if(iHigh(m_symbol, m_timeframe, barIndex - i) < high) strength += 0.5;
        }
        else
        {
            double low = iLow(m_symbol, m_timeframe, barIndex);
            if(iLow(m_symbol, m_timeframe, barIndex + i) > low) strength += 0.5;
            if(iLow(m_symbol, m_timeframe, barIndex - i) > low) strength += 0.5;
        }
    }
    
    return strength / (m_confirmBars + 3);  // Normalize 0-1
}

//+------------------------------------------------------------------+
//| Is Valid Swing High                                              |
//+------------------------------------------------------------------+
bool CFibSwingDetector::IsValidSwingHigh(int barIndex)
{
    double high = iHigh(m_symbol, m_timeframe, barIndex);
    
    for(int i = 1; i <= m_confirmBars; i++)
    {
        if(iHigh(m_symbol, m_timeframe, barIndex + i) >= high) return false;
        if(iHigh(m_symbol, m_timeframe, barIndex - i) >= high) return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Is Valid Swing Low                                               |
//+------------------------------------------------------------------+
bool CFibSwingDetector::IsValidSwingLow(int barIndex)
{
    double low = iLow(m_symbol, m_timeframe, barIndex);
    
    for(int i = 1; i <= m_confirmBars; i++)
    {
        if(iLow(m_symbol, m_timeframe, barIndex + i) <= low) return false;
        if(iLow(m_symbol, m_timeframe, barIndex - i) <= low) return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Detect Swings                                                    |
//+------------------------------------------------------------------+
void CFibSwingDetector::DetectSwings(int lookback)
{
    m_lookback = lookback;
    
    // Clear existing
    ArrayResize(m_swingHighs, 0);
    ArrayResize(m_swingLows, 0);
    m_highCount = 0;
    m_lowCount = 0;
    
    int bars = iBars(m_symbol, m_timeframe);
    if(bars < lookback) lookback = bars - 1;
    
    double atr = GetATR(14);
    if(atr <= 0) atr = 0.0001;
    
    double minSize = atr * m_minSwingATR;
    
    // Detect ALL swing highs and lows
    for(int i = m_confirmBars; i < lookback - m_confirmBars; i++)
    {
        // Check for swing high
        if(IsValidSwingHigh(i))
        {
            double high = iHigh(m_symbol, m_timeframe, i);
            double strength = CalculateSwingStrength(i, true);
            
            // Check if major swing (significant size)
            bool isMajor = false;
            for(int j = 0; j < m_lowCount; j++)
            {
                if(MathAbs(high - m_swingLows[j].price) >= minSize)
                {
                    isMajor = true;
                    break;
                }
            }
            
            if(m_highCount < m_maxSwings)
            {
                ArrayResize(m_swingHighs, m_highCount + 1);
                m_swingHighs[m_highCount].price = high;
                m_swingHighs[m_highCount].time = iTime(m_symbol, m_timeframe, i);
                m_swingHighs[m_highCount].barIndex = i;
                m_swingHighs[m_highCount].isHigh = true;
                m_swingHighs[m_highCount].strength = strength;
                m_swingHighs[m_highCount].isValid = true;
                m_swingHighs[m_highCount].isMajor = isMajor || (m_highCount == 0);
                m_highCount++;
            }
        }
        
        // Check for swing low
        if(IsValidSwingLow(i))
        {
            double low = iLow(m_symbol, m_timeframe, i);
            double strength = CalculateSwingStrength(i, false);
            
            // Check if major swing
            bool isMajor = false;
            for(int j = 0; j < m_highCount; j++)
            {
                if(MathAbs(m_swingHighs[j].price - low) >= minSize)
                {
                    isMajor = true;
                    break;
                }
            }
            
            if(m_lowCount < m_maxSwings)
            {
                ArrayResize(m_swingLows, m_lowCount + 1);
                m_swingLows[m_lowCount].price = low;
                m_swingLows[m_lowCount].time = iTime(m_symbol, m_timeframe, i);
                m_swingLows[m_lowCount].barIndex = i;
                m_swingLows[m_lowCount].isHigh = false;
                m_swingLows[m_lowCount].strength = strength;
                m_swingLows[m_lowCount].isValid = true;
                m_swingLows[m_lowCount].isMajor = isMajor || (m_lowCount == 0);
                m_lowCount++;
            }
        }
    }
    
    // Build swing pairs for Fibonacci levels
    BuildSwingPairs();
}

//+------------------------------------------------------------------+
//| Build Swing Pairs                                                |
//+------------------------------------------------------------------+
void CFibSwingDetector::BuildSwingPairs()
{
    ArrayResize(m_swingPairs, 0);
    m_pairCount = 0;
    
    double atr = GetATR(14);
    if(atr <= 0) atr = 0.0001;
    double minRange = atr * m_minSwingATR;
    
    // Create pairs from alternating highs and lows
    // Sort by time and find valid pairs
    
    // Find most recent swing pairs
    for(int h = 0; h < m_highCount && m_pairCount < m_maxPairs; h++)
    {
        SFibSwingPoint high = m_swingHighs[h];
        
        for(int l = 0; l < m_lowCount && m_pairCount < m_maxPairs; l++)
        {
            SFibSwingPoint low = m_swingLows[l];
            
            double range = high.price - low.price;
            if(range < minRange) continue;
            
            SFibSwingPair pair;
            pair.high = high;
            pair.low = low;
            pair.range = range;
            
            // Determine if bullish or bearish setup
            if(low.time < high.time)
            {
                pair.isBullish = true;  // Low before high = bullish retracement setup
                pair.createdTime = high.time;
            }
            else
            {
                pair.isBullish = false;  // High before low = bearish retracement setup
                pair.createdTime = low.time;
            }
            
            // Check for duplicates
            bool exists = false;
            for(int p = 0; p < m_pairCount; p++)
            {
                if(m_swingPairs[p].high.time == high.time && 
                   m_swingPairs[p].low.time == low.time)
                {
                    exists = true;
                    break;
                }
            }
            
            if(!exists)
            {
                ArrayResize(m_swingPairs, m_pairCount + 1);
                m_swingPairs[m_pairCount++] = pair;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Update                                                           |
//+------------------------------------------------------------------+
void CFibSwingDetector::Update()
{
    DetectSwings(m_lookback);
}

//+------------------------------------------------------------------+
//| Get Swing High At Index                                          |
//+------------------------------------------------------------------+
bool CFibSwingDetector::GetSwingHighAt(int index, SFibSwingPoint &swing)
{
    if(index < 0 || index >= m_highCount) return false;
    swing = m_swingHighs[index];
    return true;
}

//+------------------------------------------------------------------+
//| Get Swing Low At Index                                           |
//+------------------------------------------------------------------+
bool CFibSwingDetector::GetSwingLowAt(int index, SFibSwingPoint &swing)
{
    if(index < 0 || index >= m_lowCount) return false;
    swing = m_swingLows[index];
    return true;
}

//+------------------------------------------------------------------+
//| Get Last Swing High                                              |
//+------------------------------------------------------------------+
bool CFibSwingDetector::GetLastSwingHigh(SFibSwingPoint &swing)
{
    if(m_highCount == 0) return false;
    swing = m_swingHighs[0];  // Most recent
    return true;
}

//+------------------------------------------------------------------+
//| Get Last Swing Low                                               |
//+------------------------------------------------------------------+
bool CFibSwingDetector::GetLastSwingLow(SFibSwingPoint &swing)
{
    if(m_lowCount == 0) return false;
    swing = m_swingLows[0];  // Most recent
    return true;
}

//+------------------------------------------------------------------+
//| Get Swing Pair At Index                                          |
//+------------------------------------------------------------------+
bool CFibSwingDetector::GetSwingPairAt(int index, SFibSwingPair &pair)
{
    if(index < 0 || index >= m_pairCount) return false;
    pair = m_swingPairs[index];
    return true;
}

//+------------------------------------------------------------------+
//| Get Latest Bullish Pair                                          |
//+------------------------------------------------------------------+
bool CFibSwingDetector::GetLatestBullishPair(SFibSwingPair &pair)
{
    for(int i = 0; i < m_pairCount; i++)
    {
        if(m_swingPairs[i].isBullish)
        {
            pair = m_swingPairs[i];
            return true;
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Get Latest Bearish Pair                                          |
//+------------------------------------------------------------------+
bool CFibSwingDetector::GetLatestBearishPair(SFibSwingPair &pair)
{
    for(int i = 0; i < m_pairCount; i++)
    {
        if(!m_swingPairs[i].isBullish)
        {
            pair = m_swingPairs[i];
            return true;
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Get Major Swings                                                 |
//+------------------------------------------------------------------+
bool CFibSwingDetector::GetMajorSwings(SFibSwingPoint &swings[], int maxCount)
{
    ArrayResize(swings, 0);
    int count = 0;
    
    // Add major highs
    for(int i = 0; i < m_highCount && count < maxCount; i++)
    {
        if(m_swingHighs[i].isMajor)
        {
            ArrayResize(swings, count + 1);
            swings[count++] = m_swingHighs[i];
        }
    }
    
    // Add major lows
    for(int i = 0; i < m_lowCount && count < maxCount; i++)
    {
        if(m_swingLows[i].isMajor)
        {
            ArrayResize(swings, count + 1);
            swings[count++] = m_swingLows[i];
        }
    }
    
    return (count > 0);
}

#endif // __FIB_SWING_DETECTOR_MQH__
