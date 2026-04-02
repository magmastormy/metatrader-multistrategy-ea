//+------------------------------------------------------------------+
//| ZigZagFilter.mqh                                                 |
//| ZigZag Indicator for Clean Pivot Extraction                      |
//| Replaces manual swing detection with consistent filtering        |
//+------------------------------------------------------------------+
//  CHANGES v2.1:
//  - Cached ATR handle (was created/destroyed on every GetMinSwingSize call)
//  - Update(lookback) now actually uses the lookback parameter (was ignored)
//  - First pivot can now be either high OR low (was always forced to low first)
//  - Added strength field to SZigZagPivot (how dominant the pivot is vs neighbors)
//  - Added Reset() public method
//  - Removed dead highestBar / lowestBar tracking variables (unused)
//  - Fixed minSwing sign check in low branch (was checking high - lastPivotPrice)
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Multi-Strategy EA"
#property version   "2.10"
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
    double      strength;       // How far this pivot exceeds its depth-window neighbors (ATR units)

    SZigZagPivot() : time(0), price(0), barIndex(0), isHigh(false),
                     waveNumber(0), isValid(false), strength(0.0) {}
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

    // Cached ATR handle (created once in Initialize, released in destructor)
    int                 m_atrHandle;

    // Internal methods
    void                CalculateZigZag(int lookback);
    double              GetMinSwingSize();

public:
                        CZigZagFilter();
                       ~CZigZagFilter();

    // Initialization
    bool                Initialize(const string symbol, ENUM_TIMEFRAMES timeframe,
                                  int depth = 12, int deviation = 5, int backstep = 3);

    // Reset internal state without re-initialising handles
    void                Reset();

    // Update  — lookback parameter is now honoured
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
    void                SetDepth(int depth)      { m_depth     = depth; }
    void                SetDeviation(int dev)    { m_deviation = dev;   }
    void                SetBackstep(int back)    { m_backstep  = back;  }
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
    m_maxPivots(50),
    m_atrHandle(INVALID_HANDLE)
{
    ArrayResize(m_pivots, 0);
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CZigZagFilter::~CZigZagFilter()
{
    if(m_atrHandle != INVALID_HANDLE)
    {
        IndicatorRelease(m_atrHandle);
        m_atrHandle = INVALID_HANDLE;
    }
    ArrayFree(m_pivots);
}

//+------------------------------------------------------------------+
//| Initialize                                                       |
//+------------------------------------------------------------------+
bool CZigZagFilter::Initialize(const string symbol, ENUM_TIMEFRAMES timeframe,
                               int depth, int deviation, int backstep)
{
    m_symbol    = symbol;
    m_timeframe = timeframe;
    m_depth     = depth;
    m_deviation = deviation;
    m_backstep  = backstep;

    // Release any previous handle before creating a new one
    if(m_atrHandle != INVALID_HANDLE)
    {
        IndicatorRelease(m_atrHandle);
        m_atrHandle = INVALID_HANDLE;
    }

    m_atrHandle = iATR(m_symbol, m_timeframe, 14);
    if(m_atrHandle == INVALID_HANDLE)
    {
        Print("[ZigZag] WARNING: Could not create ATR handle for ", symbol, " – min-swing filter disabled.");
    }

    ArrayResize(m_pivots, 0);
    m_pivotCount = 0;

    return true;
}

//+------------------------------------------------------------------+
//| Reset                                                            |
//+------------------------------------------------------------------+
void CZigZagFilter::Reset()
{
    ArrayResize(m_pivots, 0);
    m_pivotCount = 0;
}

//+------------------------------------------------------------------+
//| Get Minimum Swing Size — uses cached handle, no create/destroy   |
//+------------------------------------------------------------------+
double CZigZagFilter::GetMinSwingSize()
{
    if(m_atrHandle == INVALID_HANDLE) return 0.0;

    double atr[];
    ArraySetAsSeries(atr, true);
    if(CopyBuffer(m_atrHandle, 0, 0, 1, atr) <= 0) return 0.0;

    return atr[0] * 0.5;  // 50% of ATR minimum
}

//+------------------------------------------------------------------+
//| Calculate ZigZag — internal                                      |
//+------------------------------------------------------------------+
void CZigZagFilter::CalculateZigZag(int lookback)
{
    ArrayResize(m_pivots, 0);
    m_pivotCount = 0;

    int bars = iBars(m_symbol, m_timeframe);
    lookback = MathMin(lookback, bars - 1);

    if(lookback < m_depth * 2) return;

    double minSwing   = GetMinSwingSize();
    double point      = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    if(point <= 0) point = 0.0001;

    // Track the last confirmed pivot (alternating high/low)
    bool   lastWasHigh   = false;
    double lastPivotPrice= 0.0;
    bool   firstPivot    = true;  // Allow either high or low as the very first pivot

    for(int i = lookback - m_depth; i >= m_depth; i--)
    {
        double h = iHigh(m_symbol, m_timeframe, i);
        double l = iLow (m_symbol, m_timeframe, i);

        // --- Check swing high ---
        bool isSwingHigh = true;
        for(int j = 1; j <= m_depth && isSwingHigh; j++)
        {
            if(i + j >= lookback || i - j < 0) { isSwingHigh = false; break; }
            if(iHigh(m_symbol, m_timeframe, i - j) >= h ||
               iHigh(m_symbol, m_timeframe, i + j) >= h)
                isSwingHigh = false;
        }

        // --- Check swing low ---
        bool isSwingLow = true;
        for(int j = 1; j <= m_depth && isSwingLow; j++)
        {
            if(i + j >= lookback || i - j < 0) { isSwingLow = false; break; }
            if(iLow(m_symbol, m_timeframe, i - j) <= l ||
               iLow(m_symbol, m_timeframe, i + j) <= l)
                isSwingLow = false;
        }

        // --- Accept swing high ---
        if(isSwingHigh && (firstPivot || !lastWasHigh))
        {
            bool sizeOK = firstPivot
                          ? true
                          : (h - lastPivotPrice) >= minSwing;

            if(sizeOK && m_pivotCount < m_maxPivots)
            {
                // Measure strength: average excess over m_depth neighbours on each side
                double excessSum = 0.0;
                int    excessCnt = 0;
                for(int j = 1; j <= m_depth; j++)
                {
                    if(i - j >= 0) { excessSum += h - iHigh(m_symbol, m_timeframe, i - j); excessCnt++; }
                    if(i + j < lookback) { excessSum += h - iHigh(m_symbol, m_timeframe, i + j); excessCnt++; }
                }
                double atrVal = GetMinSwingSize() * 2.0;
                double strength = (excessCnt > 0 && atrVal > 0) ? (excessSum / excessCnt) / atrVal : 0.5;

                ArrayResize(m_pivots, m_pivotCount + 1);
                m_pivots[m_pivotCount].price    = h;
                m_pivots[m_pivotCount].time     = iTime(m_symbol, m_timeframe, i);
                m_pivots[m_pivotCount].barIndex = i;
                m_pivots[m_pivotCount].isHigh   = true;
                m_pivots[m_pivotCount].isValid  = true;
                m_pivots[m_pivotCount].strength = MathMin(1.0, MathMax(0.0, strength));
                m_pivotCount++;

                lastWasHigh    = true;
                lastPivotPrice = h;
                firstPivot     = false;
            }
        }
        // --- Accept swing low ---
        else if(isSwingLow && (firstPivot || lastWasHigh))
        {
            bool sizeOK = firstPivot
                          ? true
                          : (lastPivotPrice - l) >= minSwing;

            if(sizeOK && m_pivotCount < m_maxPivots)
            {
                double excessSum = 0.0;
                int    excessCnt = 0;
                for(int j = 1; j <= m_depth; j++)
                {
                    if(i - j >= 0) { excessSum += iLow(m_symbol, m_timeframe, i - j) - l; excessCnt++; }
                    if(i + j < lookback) { excessSum += iLow(m_symbol, m_timeframe, i + j) - l; excessCnt++; }
                }
                double atrVal   = GetMinSwingSize() * 2.0;
                double strength = (excessCnt > 0 && atrVal > 0) ? (excessSum / excessCnt) / atrVal : 0.5;

                ArrayResize(m_pivots, m_pivotCount + 1);
                m_pivots[m_pivotCount].price    = l;
                m_pivots[m_pivotCount].time     = iTime(m_symbol, m_timeframe, i);
                m_pivots[m_pivotCount].barIndex = i;
                m_pivots[m_pivotCount].isHigh   = false;
                m_pivots[m_pivotCount].isValid  = true;
                m_pivots[m_pivotCount].strength = MathMin(1.0, MathMax(0.0, strength));
                m_pivotCount++;

                lastWasHigh    = false;
                lastPivotPrice = l;
                firstPivot     = false;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Update — lookback parameter is now used                          |
//+------------------------------------------------------------------+
void CZigZagFilter::Update(int lookback)
{
    CalculateZigZag(lookback);
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
        if(m_pivots[i].isHigh) { pivot = m_pivots[i]; return true; }
    return false;
}

//+------------------------------------------------------------------+
//| Get Last Low                                                     |
//+------------------------------------------------------------------+
bool CZigZagFilter::GetLastLow(SZigZagPivot &pivot)
{
    for(int i = m_pivotCount - 1; i >= 0; i--)
        if(!m_pivots[i].isHigh) { pivot = m_pivots[i]; return true; }
    return false;
}

//+------------------------------------------------------------------+
//| Get Alternating Pivots                                           |
//+------------------------------------------------------------------+
bool CZigZagFilter::GetAlternatingPivots(SZigZagPivot &pivots[], int count, bool startWithHigh)
{
    ArrayResize(pivots, count);
    int  found          = 0;
    bool lookingForHigh = startWithHigh;

    for(int i = 0; i < m_pivotCount && found < count; i++)
    {
        if(m_pivots[i].isHigh == lookingForHigh)
        {
            pivots[found++]  = m_pivots[i];
            lookingForHigh   = !lookingForHigh;
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
    if(m_pivotCount < 5) return false;

    SZigZagPivot pivots[5];

    // Try bullish wave (starts with low: L-H-L-H-L)
    if(GetAlternatingPivots(pivots, 5, false))
    {
        wave1 = pivots[0]; wave1.waveNumber = 0;
        wave2 = pivots[1]; wave2.waveNumber = 1;
        wave3 = pivots[2]; wave3.waveNumber = 2;
        wave4 = pivots[3]; wave4.waveNumber = 3;
        wave5 = pivots[4]; wave5.waveNumber = 4;
        return true;
    }

    // Try bearish wave (starts with high: H-L-H-L-H)
    if(GetAlternatingPivots(pivots, 5, true))
    {
        wave1 = pivots[0]; wave1.waveNumber = 0;
        wave2 = pivots[1]; wave2.waveNumber = 1;
        wave3 = pivots[2]; wave3.waveNumber = 2;
        wave4 = pivots[3]; wave4.waveNumber = 3;
        wave5 = pivots[4]; wave5.waveNumber = 4;
        return true;
    }

    return false;
}

#endif // __ELLIOTT_ZIGZAG_FILTER_MQH__
