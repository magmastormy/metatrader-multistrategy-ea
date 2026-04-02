//+------------------------------------------------------------------+
//| SupportResistanceDetector.mqh                                    |
//| S/R Level Detection Engine                                       |
//| Copyright 2025, Multi-Strategy EA                                |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Multi-Strategy EA"
#property version   "1.00"
#property strict

#ifndef __SR_SUPPORT_RESISTANCE_DETECTOR_MQH__
#define __SR_SUPPORT_RESISTANCE_DETECTOR_MQH__

#include <Arrays/ArrayObj.mqh>

// Dynamic array approach - no fixed limit

//+------------------------------------------------------------------+
//| S/R Type Enum                                                    |
//+------------------------------------------------------------------+
enum ENUM_SR_TYPE
{
    SR_SWING_HIGH_LOW,      // Previous swing points
    SR_PSYCHOLOGICAL,       // Round numbers (1.1000, 1.2000)
    SR_DAILY_HIGH_LOW,      // Previous day high/low
    SR_WEEKLY_HIGH_LOW,     // Previous week high/low
    SR_MONTHLY_HIGH_LOW,    // Previous month high/low
    SR_PIVOT_POINTS,        // Standard/Fibonacci pivots
    SR_STRUCTURE            // Major market structure levels
};

//+------------------------------------------------------------------+
//| S/R Level Structure                                              |
//+------------------------------------------------------------------+
struct SSupportResistance
{
    double price;
    ENUM_SR_TYPE type;
    datetime createdTime;
    int touches;
    double strength;
    bool isBroken;
    bool roleReversed;
    ENUM_TIMEFRAMES timeframe;
    bool isSupport;
    
    SSupportResistance() : price(0), type(SR_SWING_HIGH_LOW), createdTime(0),
                          touches(1), strength(0.5), isBroken(false),
                          roleReversed(false), timeframe(PERIOD_CURRENT), isSupport(true) {}
};

//+------------------------------------------------------------------+
//| Support/Resistance Detector Class                                |
//+------------------------------------------------------------------+
class CSupportResistanceDetector
{
private:
    string              m_symbol;
    ENUM_TIMEFRAMES     m_timeframe;
    SSupportResistance  m_levels[];
    int                 m_levelCount;
    int                 m_maxLevels;
    int                 m_atrHandle;
    
    double              m_clusterTolerance;
    int                 m_swingStrength;
    
    // Internal methods
    void                DetectSwingLevels(int lookback);
    void                DetectPsychologicalLevels();
    void                DetectTimeframeLevels();
    void                ClusterLevels();
    void                CalculateStrength();
    void                UpdateTouches();
    double              GetAtrValue() const;
    
    void                AddLevel(double price, ENUM_SR_TYPE type, bool isSupport, datetime barTime = 0)
    {
        // Dynamic resize - always ensure capacity
        if(m_levelCount >= ArraySize(m_levels))
        {
            ArrayResize(m_levels, m_levelCount + 50); // Add capacity in chunks of 50
        }
        
        m_levels[m_levelCount].price = price;
        m_levels[m_levelCount].type = type;
        m_levels[m_levelCount].createdTime = (barTime > 0) ? barTime : TimeCurrent();
        m_levels[m_levelCount].touches = 0;
        m_levels[m_levelCount].strength = 0.6;
        m_levels[m_levelCount].isSupport = isSupport;
        m_levelCount++;
    }
    
public:
                        CSupportResistanceDetector();
                       ~CSupportResistanceDetector();
    
    bool                Initialize(const string symbol, ENUM_TIMEFRAMES timeframe,
                                  double clusterPips = 20, int swingStrength = 3);
    
    void                DetectLevels(int lookback = 200);
    void                Update();
    
    // Getters
    int                 GetLevelCount() const { return m_levelCount; }
    bool                GetLevel(int index, SSupportResistance &level);
    int                 FindNearestLevel(double price, double tolerancePips = 15);
    int                 FindNearestSupport(double price);
    int                 FindNearestResistance(double price);
    
    // Level checks
    bool                IsAtSupportLevel(double price, double tolerancePips = 15);
    bool                IsAtResistanceLevel(double price, double tolerancePips = 15);
    bool                HasRoleReversed(double price);
    
    // Breakout detection
    bool                DetectBreakout(double price, int &brokenLevelIndex);
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CSupportResistanceDetector::CSupportResistanceDetector() :
    m_symbol(""),
    m_timeframe(PERIOD_CURRENT),
    m_levelCount(0),
    m_maxLevels(100),
    m_atrHandle(INVALID_HANDLE),
    m_clusterTolerance(20),
    m_swingStrength(3)
{
    ArrayResize(m_levels, 0);
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CSupportResistanceDetector::~CSupportResistanceDetector()
{
    if(m_atrHandle != INVALID_HANDLE)
    {
        IndicatorRelease(m_atrHandle);
        m_atrHandle = INVALID_HANDLE;
    }
    ArrayFree(m_levels);
}

//+------------------------------------------------------------------+
//| Initialize                                                       |
//+------------------------------------------------------------------+
bool CSupportResistanceDetector::Initialize(const string symbol, ENUM_TIMEFRAMES timeframe,
                                           double clusterPips, int swingStrength)
{
    if(m_atrHandle != INVALID_HANDLE)
    {
        IndicatorRelease(m_atrHandle);
        m_atrHandle = INVALID_HANDLE;
    }

    m_symbol = symbol;
    m_timeframe = timeframe;
    m_clusterTolerance = clusterPips;
    m_swingStrength = swingStrength;
    m_levelCount = 0;

    m_atrHandle = iATR(m_symbol, m_timeframe, 14);
    
    return (m_atrHandle != INVALID_HANDLE);
}

double CSupportResistanceDetector::GetAtrValue() const
{
    if(m_atrHandle == INVALID_HANDLE)
        return 0.0;

    double atrBuf[];
    ArraySetAsSeries(atrBuf, true);
    if(CopyBuffer(m_atrHandle, 0, 0, 1, atrBuf) <= 0)
        return 0.0;

    return atrBuf[0];
}

//+------------------------------------------------------------------+
//| Detect All S/R Levels                                            |
//+------------------------------------------------------------------+
void CSupportResistanceDetector::DetectLevels(int lookback)
{
    m_levelCount = 0;
    ArrayResize(m_levels, 0);
    
    // 1. Swing-based S/R
    DetectSwingLevels(lookback);
    
    // 2. Psychological levels
    DetectPsychologicalLevels();
    
    // 3. Daily/Weekly levels
    DetectTimeframeLevels();
    
    // 4. Cluster nearby levels
    ClusterLevels();
    
    // 5. Calculate strength
    CalculateStrength();
    
    // 6. Update touches
    UpdateTouches();
}

//+------------------------------------------------------------------+
//| Detect Swing-Based Levels                                        |
//+------------------------------------------------------------------+
void CSupportResistanceDetector::DetectSwingLevels(int lookback)
{
    double high[], low[];
    datetime time[];
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(time, true);
    
    if(CopyHigh(m_symbol, m_timeframe, 0, lookback, high) <= 0) return;
    if(CopyLow(m_symbol, m_timeframe, 0, lookback, low) <= 0) return;
    if(CopyTime(m_symbol, m_timeframe, 0, lookback, time) <= 0) return;
    
    int str = m_swingStrength;
    
    // SIGNIFICANCE FILTER
    double atr = GetAtrValue();
    double minSwingSize = (atr > 0) ? atr * 0.30 : 10 * SymbolInfoDouble(m_symbol, SYMBOL_POINT);

    // Find swing highs (resistance)
    for(int i = str; i < lookback - str; i++)
    {
        bool isSwingHigh = true;
        for(int j = 1; j <= str; j++)
        {
            if(high[i] <= high[i-j] || high[i] <= high[i+j])
            {
                isSwingHigh = false;
                break;
            }
        }
        
        if(isSwingHigh)
        {
            double neighborAvgHigh = (high[i-1] + high[i+1]) / 2.0;
            if((high[i] - neighborAvgHigh) >= minSwingSize)
            {
                AddLevel(high[i], SR_SWING_HIGH_LOW, false, time[i]);
            }
        }
    }
    
    // Find swing lows (support)
    for(int i = str; i < lookback - str; i++)
    {
        bool isSwingLow = true;
        for(int j = 1; j <= str; j++)
        {
            if(low[i] >= low[i-j] || low[i] >= low[i+j])
            {
                isSwingLow = false;
                break;
            }
        }
        
        if(isSwingLow)
        {
            double neighborAvgLow = (low[i-1] + low[i+1]) / 2.0;
            if((neighborAvgLow - low[i]) >= minSwingSize)
            {
                AddLevel(low[i], SR_SWING_HIGH_LOW, true, time[i]);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Detect Psychological Levels                                      |
//+------------------------------------------------------------------+
void CSupportResistanceDetector::DetectPsychologicalLevels()
{
    double lastPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);
    int digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
    
    double roundFactor = (digits == 5 || digits == 3) ? 100.0 : 1000.0;
    double roundLevel = MathRound(lastPrice * roundFactor) / roundFactor;
    double step = (digits == 5 || digits == 3) ? 0.01 : 0.001;
    
    for(int i = -5; i <= 5; i++)
    {
        double level = roundLevel + (i * step);
        
        // Dynamic array - no hard limit, but cap for performance
        if(m_levelCount >= 500) break; // Soft cap at 500 for performance
        
        bool exists = false;
        for(int j = 0; j < m_levelCount; j++)
        {
            if(MathAbs(m_levels[j].price - level) < step * 0.5)
            {
                exists = true;
                break;
            }
        }
        
        if(!exists && level > 0)
        {
            AddLevel(level, SR_PSYCHOLOGICAL, (level < lastPrice));
        }
    }
}

//+------------------------------------------------------------------+
//| Detect Timeframe Levels                                          |
//+------------------------------------------------------------------+
void CSupportResistanceDetector::DetectTimeframeLevels()
{
    // Yesterday's high/low
    double yesterdayHigh = iHigh(m_symbol, PERIOD_D1, 1);
    double yesterdayLow = iLow(m_symbol, PERIOD_D1, 1);
    
    if(yesterdayHigh > 0)
    {
        AddLevel(yesterdayHigh, SR_DAILY_HIGH_LOW, false);
        m_levels[m_levelCount-1].strength = 0.75;
    }
    
    if(yesterdayLow > 0)
    {
        AddLevel(yesterdayLow, SR_DAILY_HIGH_LOW, true);
        m_levels[m_levelCount-1].strength = 0.75;
    }
    
    // Previous week high/low
    double lastWeekHigh = iHigh(m_symbol, PERIOD_W1, 1);
    double lastWeekLow = iLow(m_symbol, PERIOD_W1, 1);
    
    if(lastWeekHigh > 0)
    {
        AddLevel(lastWeekHigh, SR_WEEKLY_HIGH_LOW, false);
        m_levels[m_levelCount-1].strength = 0.85;
    }
    
    if(lastWeekLow > 0)
    {
        AddLevel(lastWeekLow, SR_WEEKLY_HIGH_LOW, true);
        m_levels[m_levelCount-1].strength = 0.85;
    }
    
    // Previous month high/low
    double lastMonthHigh = iHigh(m_symbol, PERIOD_MN1, 1);
    double lastMonthLow = iLow(m_symbol, PERIOD_MN1, 1);
    
    if(lastMonthHigh > 0)
    {
        AddLevel(lastMonthHigh, SR_MONTHLY_HIGH_LOW, false);
        m_levels[m_levelCount-1].strength = 0.90;
    }
    
    if(lastMonthLow > 0)
    {
        AddLevel(lastMonthLow, SR_MONTHLY_HIGH_LOW, true);
        m_levels[m_levelCount-1].strength = 0.90;
    }
}

//+------------------------------------------------------------------+
//| Cluster Nearby Levels                                            |
//+------------------------------------------------------------------+
void CSupportResistanceDetector::ClusterLevels()
{
    double tolerance = m_clusterTolerance * SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    
    for(int i = 0; i < m_levelCount; i++)
    {
        for(int j = i + 1; j < m_levelCount; j++)
        {
            if(MathAbs(m_levels[i].price - m_levels[j].price) < tolerance)
            {
                // Merge levels - keep the price with more significance
                // Priority is based on enum value (smaller is higher timeframe/priority)
                bool iHigherPriority = (m_levels[i].type <= m_levels[j].type);
                if(!iHigherPriority)
                {
                    m_levels[i].price = m_levels[j].price;  // Keep j's price
                }
                
                m_levels[i].touches += m_levels[j].touches;
                m_levels[i].strength = MathMax(m_levels[i].strength, m_levels[j].strength);
                // DO NOT average the price
                
                // Remove j by shifting
                for(int k = j; k < m_levelCount - 1; k++)
                    m_levels[k] = m_levels[k + 1];
                
                m_levelCount--;
                ArrayResize(m_levels, m_levelCount);
                j--;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Calculate Level Strength                                         |
//+------------------------------------------------------------------+
void CSupportResistanceDetector::CalculateStrength()
{
    for(int i = 0; i < m_levelCount; i++)
    {
        double strength = 0.5;
        
        switch(m_levels[i].type)
        {
            case SR_MONTHLY_HIGH_LOW:
                strength = 0.95;
                break;
            case SR_WEEKLY_HIGH_LOW:
                strength = 0.90;
                break;
            case SR_DAILY_HIGH_LOW:
                strength = 0.80;
                break;
            case SR_SWING_HIGH_LOW:
                strength = 0.70;
                break;
            case SR_PSYCHOLOGICAL:
                strength = 0.60;
                break;
        }
        
        // Increase strength for multiple touches
        strength += (m_levels[i].touches - 1) * 0.05;
        strength = MathMin(1.0, strength);
        
        // Decrease strength for old levels
        if(m_levels[i].createdTime > 0)
        {
            int age = (int)((TimeCurrent() - m_levels[i].createdTime) / PeriodSeconds(PERIOD_D1));
            if(age > 30)
                strength -= 0.10;
        }
        
        m_levels[i].strength = MathMax(0.3, strength);
    }
}

//+------------------------------------------------------------------+
//| Update Touch Count                                               |
//+------------------------------------------------------------------+
void CSupportResistanceDetector::UpdateTouches()
{
    double atr = GetAtrValue();
    double tolerance = (atr > 0) ? atr * 0.15 : 10 * SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    int copied = CopyRates(m_symbol, m_timeframe, 0, 100, rates);
    if(copied <= 0) return;
    
    for(int i = 0; i < m_levelCount; i++)
    {
        int touches = 0;
        
        for(int j = 0; j < copied; j++)
        {
            if(MathAbs(rates[j].high - m_levels[i].price) < tolerance ||
               MathAbs(rates[j].low - m_levels[i].price) < tolerance)
            {
                touches++;
            }
        }
        
        m_levels[i].touches = MathMax(1, touches);
    }
}

//+------------------------------------------------------------------+
//| Update                                                           |
//+------------------------------------------------------------------+
void CSupportResistanceDetector::Update()
{
    DetectLevels(200);  // Reduced to 200 for proper scaling and removing stale lines
}

//+------------------------------------------------------------------+
//| Get Level at Index                                               |
//+------------------------------------------------------------------+
bool CSupportResistanceDetector::GetLevel(int index, SSupportResistance &level)
{
    if(index < 0 || index >= m_levelCount)
        return false;
    
    level = m_levels[index];
    return true;
}

//+------------------------------------------------------------------+
//| Find Nearest Level                                               |
//+------------------------------------------------------------------+
int CSupportResistanceDetector::FindNearestLevel(double price, double tolerancePips)
{
    double tolerance = tolerancePips * SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    double minDistance = DBL_MAX;
    int nearestIndex = -1;
    
    for(int i = 0; i < m_levelCount; i++)
    {
        double distance = MathAbs(price - m_levels[i].price);
        if(distance < tolerance && distance < minDistance)
        {
            minDistance = distance;
            nearestIndex = i;
        }
    }
    
    return nearestIndex;
}

//+------------------------------------------------------------------+
//| Find Nearest Support                                             |
//+------------------------------------------------------------------+
int CSupportResistanceDetector::FindNearestSupport(double price)
{
    double minDistance = DBL_MAX;
    int nearestIndex = -1;
    
    for(int i = 0; i < m_levelCount; i++)
    {
        if(m_levels[i].price < price)
        {
            double distance = price - m_levels[i].price;
            if(distance < minDistance)
            {
                minDistance = distance;
                nearestIndex = i;
            }
        }
    }
    
    return nearestIndex;
}

//+------------------------------------------------------------------+
//| Find Nearest Resistance                                          |
//+------------------------------------------------------------------+
int CSupportResistanceDetector::FindNearestResistance(double price)
{
    double minDistance = DBL_MAX;
    int nearestIndex = -1;
    
    for(int i = 0; i < m_levelCount; i++)
    {
        if(m_levels[i].price > price)
        {
            double distance = m_levels[i].price - price;
            if(distance < minDistance)
            {
                minDistance = distance;
                nearestIndex = i;
            }
        }
    }
    
    return nearestIndex;
}

//+------------------------------------------------------------------+
//| Check if at Support Level                                        |
//+------------------------------------------------------------------+
bool CSupportResistanceDetector::IsAtSupportLevel(double price, double tolerancePips)
{
    int idx = FindNearestLevel(price, tolerancePips);
    return (idx >= 0 && m_levels[idx].isSupport);
}

//+------------------------------------------------------------------+
//| Check if at Resistance Level                                     |
//+------------------------------------------------------------------+
bool CSupportResistanceDetector::IsAtResistanceLevel(double price, double tolerancePips)
{
    int idx = FindNearestLevel(price, tolerancePips);
    return (idx >= 0 && !m_levels[idx].isSupport);
}

//+------------------------------------------------------------------+
//| Detect Breakout                                                  |
//+------------------------------------------------------------------+
bool CSupportResistanceDetector::DetectBreakout(double price, int &brokenLevelIndex)
{
    double tolerance = 5 * SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    if(CopyRates(m_symbol, m_timeframe, 0, 3, rates) < 3)
        return false;
    
    for(int i = 0; i < m_levelCount; i++)
    {
        if(m_levels[i].isBroken)
            continue;
        
        // Resistance breakout
        if(!m_levels[i].isSupport)
        {
            if(rates[0].close > m_levels[i].price + tolerance &&
               rates[1].close < m_levels[i].price)
            {
                m_levels[i].isBroken = true;
                brokenLevelIndex = i;
                return true;
            }
        }
        // Support breakout
        else
        {
            if(rates[0].close < m_levels[i].price - tolerance &&
               rates[1].close > m_levels[i].price)
            {
                m_levels[i].isBroken = true;
                brokenLevelIndex = i;
                return true;
            }
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Check Role Reversal                                              |
//+------------------------------------------------------------------+
bool CSupportResistanceDetector::HasRoleReversed(double price)
{
    for(int i = 0; i < m_levelCount; i++)
    {
        if(m_levels[i].isBroken && !m_levels[i].roleReversed)
        {
            double tolerance = 10 * SymbolInfoDouble(m_symbol, SYMBOL_POINT);
            
            if(MathAbs(price - m_levels[i].price) < tolerance)
            {
                m_levels[i].roleReversed = true;
                m_levels[i].isSupport = !m_levels[i].isSupport;
                return true;
            }
        }
    }
    
    return false;
}

#endif // __SR_SUPPORT_RESISTANCE_DETECTOR_MQH__
