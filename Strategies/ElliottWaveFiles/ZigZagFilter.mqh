//+------------------------------------------------------------------+
//| ZigZagFilter.mqh                                                 |
//| ZigZag Indicator for Clean Pivot Extraction                      |
//| Replaces manual swing detection with consistent filtering        |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Multi-Strategy EA"
#property version   "2.00"
#property strict

#ifndef __ELLIOTT_ZIGZAG_FILTER_MQH__
#define __ELLIOTT_ZIGZAG_FILTER_MQH__

//+------------------------------------------------------------------+
//| ZigZag Pivot Structure                                           |
//+------------------------------------------------------------------+
struct SZigZagPivot
{
    datetime    time;
    double      price;
    int         barIndex;
    bool        isHigh;
    int         waveNumber;     // Assigned wave number (1-5, A-C)
    bool        isValid;
    
    SZigZagPivot() : time(0), price(0), barIndex(0), isHigh(false),
                     waveNumber(0), isValid(false) {}
};

//+------------------------------------------------------------------+
//| ZigZag Filter Class                                              |
//+------------------------------------------------------------------+
class CZigZagFilter
{
private:
    string              m_symbol;
    ENUM_TIMEFRAMES     m_timeframe;
    
    // ZigZag settings
    int                 m_depth;
    int                 m_deviation;
    int                 m_backstep;
    
    // Pivots storage
    SZigZagPivot        m_pivots[];
    int                 m_pivotCount;
    int                 m_maxPivots;
    
    // Internal methods
    void                CalculateZigZag();
    double              GetMinSwingSize();
    
public:
                        CZigZagFilter();
                       ~CZigZagFilter();
    
    // Initialization
    bool                Initialize(const string symbol, ENUM_TIMEFRAMES timeframe,
                                  int depth = 12, int deviation = 5, int backstep = 3);
    
    // Update
    void                Update(int lookback = 200);
    
    // Getters
    int                 GetPivotCount() const { return m_pivotCount; }
    bool                GetPivotAt(int index, SZigZagPivot &pivot);
    bool                GetLastPivot(SZigZagPivot &pivot);
    bool                GetLastHigh(SZigZagPivot &pivot);
    bool                GetLastLow(SZigZagPivot &pivot);
    
    // Get alternating pivots for wave analysis
    bool                GetAlternatingPivots(SZigZagPivot &pivots[], int count, bool startWithHigh);
    
    // Wave point extraction
    bool                GetWavePoints(SZigZagPivot &wave1, SZigZagPivot &wave2,
                                      SZigZagPivot &wave3, SZigZagPivot &wave4, SZigZagPivot &wave5);
    
    // Configuration
    void                SetDepth(int depth) { m_depth = depth; }
    void                SetDeviation(int dev) { m_deviation = dev; }
    void                SetBackstep(int back) { m_backstep = back; }
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CZigZagFilter::CZigZagFilter() :
    m_symbol(""),
    m_timeframe(PERIOD_CURRENT),
    m_depth(12),
    m_deviation(5),
    m_backstep(3),
    m_pivotCount(0),
    m_maxPivots(50)
{
    ArrayResize(m_pivots, 0);
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CZigZagFilter::~CZigZagFilter()
{
    ArrayFree(m_pivots);
}

//+------------------------------------------------------------------+
//| Initialize                                                       |
//+------------------------------------------------------------------+
bool CZigZagFilter::Initialize(const string symbol, ENUM_TIMEFRAMES timeframe,
                               int depth, int deviation, int backstep)
{
    m_symbol = symbol;
    m_timeframe = timeframe;
    m_depth = depth;
    m_deviation = deviation;
    m_backstep = backstep;
    
    ArrayResize(m_pivots, 0);
    m_pivotCount = 0;
    
    return true;
}

//+------------------------------------------------------------------+
//| Get Minimum Swing Size                                           |
//+------------------------------------------------------------------+
double CZigZagFilter::GetMinSwingSize()
{
    // Calculate minimum swing size based on ATR
    int atrHandle = iATR(m_symbol, m_timeframe, 14);
    if(atrHandle == INVALID_HANDLE) return 0;
    
    double atr[];
    ArraySetAsSeries(atr, true);
    if(CopyBuffer(atrHandle, 0, 0, 1, atr) <= 0)
    {
        IndicatorRelease(atrHandle);
        return 0;
    }
    
    IndicatorRelease(atrHandle);
    return atr[0] * 0.5;  // 50% of ATR minimum
}

//+------------------------------------------------------------------+
//| Calculate ZigZag                                                 |
//+------------------------------------------------------------------+
void CZigZagFilter::CalculateZigZag()
{
    // Implements classic ZigZag algorithm
    // Finds alternating highs and lows based on deviation threshold
    
    ArrayResize(m_pivots, 0);
    m_pivotCount = 0;
    
    int bars = iBars(m_symbol, m_timeframe);
    int lookback = MathMin(200, bars - 1);
    
    if(lookback < m_depth * 2) return;
    
    double minSwing = GetMinSwingSize();
    double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    if(point <= 0) point = 0.0001;
    
    double deviance = m_deviation * point;
    
    // Track last confirmed pivot
    bool lastWasHigh = false;
    double lastPivotPrice = 0;
    int lastPivotBar = -1;
    
    // Initial pivot search
    double highestHigh = 0;
    double lowestLow = DBL_MAX;
    int highestBar = 0, lowestBar = 0;
    
    for(int i = lookback; i >= m_depth; i--)
    {
        double high = iHigh(m_symbol, m_timeframe, i);
        double low = iLow(m_symbol, m_timeframe, i);
        
        // Track extremes
        if(high > highestHigh)
        {
            highestHigh = high;
            highestBar = i;
        }
        if(low < lowestLow)
        {
            lowestLow = low;
            lowestBar = i;
        }
        
        // Check if this is a valid swing point
        bool isSwingHigh = true;
        bool isSwingLow = true;
        
        for(int j = 1; j <= m_depth; j++)
        {
            if(i + j >= lookback || i - j < 0) break;
            
            if(iHigh(m_symbol, m_timeframe, i - j) >= high ||
               iHigh(m_symbol, m_timeframe, i + j) >= high)
                isSwingHigh = false;
            
            if(iLow(m_symbol, m_timeframe, i - j) <= low ||
               iLow(m_symbol, m_timeframe, i + j) <= low)
                isSwingLow = false;
        }
        
        // Add swing point if valid and alternating
        if(isSwingHigh && !lastWasHigh)
        {
            if(lastPivotPrice == 0 || (high - lastPivotPrice) >= minSwing)
            {
                if(m_pivotCount < m_maxPivots)
                {
                    ArrayResize(m_pivots, m_pivotCount + 1);
                    m_pivots[m_pivotCount].price = high;
                    m_pivots[m_pivotCount].time = iTime(m_symbol, m_timeframe, i);
                    m_pivots[m_pivotCount].barIndex = i;
                    m_pivots[m_pivotCount].isHigh = true;
                    m_pivots[m_pivotCount].isValid = true;
                    m_pivotCount++;
                    
                    lastWasHigh = true;
                    lastPivotPrice = high;
                    lastPivotBar = i;
                }
            }
        }
        else if(isSwingLow && lastWasHigh)
        {
            if(lastPivotPrice == 0 || (lastPivotPrice - low) >= minSwing)
            {
                if(m_pivotCount < m_maxPivots)
                {
                    ArrayResize(m_pivots, m_pivotCount + 1);
                    m_pivots[m_pivotCount].price = low;
                    m_pivots[m_pivotCount].time = iTime(m_symbol, m_timeframe, i);
                    m_pivots[m_pivotCount].barIndex = i;
                    m_pivots[m_pivotCount].isHigh = false;
                    m_pivots[m_pivotCount].isValid = true;
                    m_pivotCount++;
                    
                    lastWasHigh = false;
                    lastPivotPrice = low;
                    lastPivotBar = i;
                }
            }
        }
        else if(isSwingLow && !lastWasHigh && m_pivotCount == 0)
        {
            // First pivot can be a low
            if(m_pivotCount < m_maxPivots)
            {
                ArrayResize(m_pivots, m_pivotCount + 1);
                m_pivots[m_pivotCount].price = low;
                m_pivots[m_pivotCount].time = iTime(m_symbol, m_timeframe, i);
                m_pivots[m_pivotCount].barIndex = i;
                m_pivots[m_pivotCount].isHigh = false;
                m_pivots[m_pivotCount].isValid = true;
                m_pivotCount++;
                
                lastWasHigh = false;
                lastPivotPrice = low;
                lastPivotBar = i;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Update                                                           |
//+------------------------------------------------------------------+
void CZigZagFilter::Update(int lookback)
{
    CalculateZigZag();
}

//+------------------------------------------------------------------+
//| Get Pivot At Index                                               |
//+------------------------------------------------------------------+
bool CZigZagFilter::GetPivotAt(int index, SZigZagPivot &pivot)
{
    if(index < 0 || index >= m_pivotCount) return false;
    pivot = m_pivots[index];
    return true;
}

//+------------------------------------------------------------------+
//| Get Last Pivot                                                   |
//+------------------------------------------------------------------+
bool CZigZagFilter::GetLastPivot(SZigZagPivot &pivot)
{
    if(m_pivotCount == 0) return false;
    pivot = m_pivots[m_pivotCount - 1];
    return true;
}

//+------------------------------------------------------------------+
//| Get Last High                                                    |
//+------------------------------------------------------------------+
bool CZigZagFilter::GetLastHigh(SZigZagPivot &pivot)
{
    for(int i = m_pivotCount - 1; i >= 0; i--)
    {
        if(m_pivots[i].isHigh)
        {
            pivot = m_pivots[i];
            return true;
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Get Last Low                                                     |
//+------------------------------------------------------------------+
bool CZigZagFilter::GetLastLow(SZigZagPivot &pivot)
{
    for(int i = m_pivotCount - 1; i >= 0; i--)
    {
        if(!m_pivots[i].isHigh)
        {
            pivot = m_pivots[i];
            return true;
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Get Alternating Pivots                                           |
//+------------------------------------------------------------------+
bool CZigZagFilter::GetAlternatingPivots(SZigZagPivot &pivots[], int count, bool startWithHigh)
{
    ArrayResize(pivots, count);
    int found = 0;
    bool lookingForHigh = startWithHigh;
    
    for(int i = 0; i < m_pivotCount && found < count; i++)
    {
        if(m_pivots[i].isHigh == lookingForHigh)
        {
            pivots[found++] = m_pivots[i];
            lookingForHigh = !lookingForHigh;
        }
    }
    
    return (found == count);
}

//+------------------------------------------------------------------+
//| Get Wave Points (5-wave impulse)                                 |
//+------------------------------------------------------------------+
bool CZigZagFilter::GetWavePoints(SZigZagPivot &wave1, SZigZagPivot &wave2,
                                  SZigZagPivot &wave3, SZigZagPivot &wave4, SZigZagPivot &wave5)
{
    // Need at least 5 pivots for a complete wave structure
    if(m_pivotCount < 5) return false;
    
    // Get 5 most recent alternating pivots
    SZigZagPivot pivots[5];
    
    // Try bullish wave (starts with low: L-H-L-H-L)
    if(GetAlternatingPivots(pivots, 5, false))
    {
        wave1 = pivots[0];  // Wave 1 start (low)
        wave2 = pivots[1];  // Wave 1 end / Wave 2 start (high)
        wave3 = pivots[2];  // Wave 2 end / Wave 3 start (low)
        wave4 = pivots[3];  // Wave 3 end / Wave 4 start (high)
        wave5 = pivots[4];  // Wave 4 end / Wave 5 start (low)
        
        // Label wave numbers
        wave1.waveNumber = 0;  // Wave 1 start
        wave2.waveNumber = 1;  // Wave 1 end
        wave3.waveNumber = 2;  // Wave 2 end
        wave4.waveNumber = 3;  // Wave 3 end
        wave5.waveNumber = 4;  // Wave 4 end
        
        return true;
    }
    
    // Try bearish wave (starts with high: H-L-H-L-H)
    if(GetAlternatingPivots(pivots, 5, true))
    {
        wave1 = pivots[0];
        wave2 = pivots[1];
        wave3 = pivots[2];
        wave4 = pivots[3];
        wave5 = pivots[4];
        
        wave1.waveNumber = 0;
        wave2.waveNumber = 1;
        wave3.waveNumber = 2;
        wave4.waveNumber = 3;
        wave5.waveNumber = 4;
        
        return true;
    }
    
    return false;
}

#endif // __ELLIOTT_ZIGZAG_FILTER_MQH__
