//+------------------------------------------------------------------+
//| LiquidityDetector.mqh                                            |
//| Liquidity Pool and Sweep Detection for Unified ICT/SMC           |
//| Copyright 2025, Multi-Strategy EA                                |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Multi-Strategy EA"
#property version   "1.00"
#property strict

#ifndef __UICT_LIQUIDITY_DETECTOR_MQH__
#define __UICT_LIQUIDITY_DETECTOR_MQH__

//+------------------------------------------------------------------+
//| Liquidity Type Enum                                              |
//+------------------------------------------------------------------+
enum ENUM_UICT_LIQUIDITY_TYPE
{
    UICT_LIQ_NONE = 0,
    UICT_LIQ_EQUAL_HIGHS,
    UICT_LIQ_EQUAL_LOWS,
    UICT_LIQ_SWING_HIGH,
    UICT_LIQ_SWING_LOW,
    UICT_LIQ_SESSION_HIGH,
    UICT_LIQ_SESSION_LOW,
    UICT_LIQ_DAILY_HIGH,
    UICT_LIQ_DAILY_LOW,
    UICT_LIQ_WEEKLY_HIGH,
    UICT_LIQ_WEEKLY_LOW
};

//+------------------------------------------------------------------+
//| Liquidity Pool Structure                                         |
//+------------------------------------------------------------------+
struct SLiquidityPool
{
    ENUM_UICT_LIQUIDITY_TYPE type;
    datetime time;
    double price;
    int touchCount;
    bool isSwept;
    datetime sweptTime;
    bool confirmedReversal;
    double strength;
    ENUM_TIMEFRAMES timeframe;
    bool isEngineered;
    
    SLiquidityPool() : type(UICT_LIQ_NONE), time(0), price(0), touchCount(0),
                      isSwept(false), sweptTime(0), confirmedReversal(false),
                      strength(0.5), timeframe(PERIOD_CURRENT), isEngineered(false) {}
};

//+------------------------------------------------------------------+
//| Liquidity Detector Class                                         |
//+------------------------------------------------------------------+
class CLiquidityDetector
{
private:
    string              m_symbol;
    ENUM_TIMEFRAMES     m_timeframe;
    
    SLiquidityPool      m_liquidityPools[];
    int                 m_poolCount;
    int                 m_maxPools;
    
    double              m_equalTolerance;
    
    // Internal methods
    bool                IsAtPsychologicalLevel(double price);
    long                GetAverageVolume(int bars);
    double              CalculateLiquidityStrength(int bar1, int bar2);
    
public:
                        CLiquidityDetector();
                       ~CLiquidityDetector();
    
    bool                Initialize(const string symbol, ENUM_TIMEFRAMES timeframe, double equalTolerancePips = 5);
    void                Update();
    
    // Detection
    void                DetectEqualHighsLows(int lookback = 50);
    void                DetectSwingLiquidity(int lookback = 50);
    void                DetectSessionLiquidity();
    void                DetectTimeframeLiquidity();
    
    // Sweep Detection
    bool                DetectLiquiditySweep(SLiquidityPool &pool);
    bool                HasRecentSweep(bool &isBuyside);
    
    // Getters
    int                 GetPoolCount() const { return m_poolCount; }
    bool                GetPool(int index, SLiquidityPool &pool);
    int                 FindNearestLiquidity(double price, bool above);
    int                 FindSweptLiquidity();
    
    // Checks
    bool                IsNearLiquidity(double price, double tolerancePips = 20);
    bool                HasBuysideLiquidity(double price);
    bool                HasSellsideLiquidity(double price);
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CLiquidityDetector::CLiquidityDetector() :
    m_symbol(""),
    m_timeframe(PERIOD_CURRENT),
    m_poolCount(0),
    m_maxPools(50),
    m_equalTolerance(5)
{
    ArrayResize(m_liquidityPools, 0);
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CLiquidityDetector::~CLiquidityDetector()
{
    ArrayFree(m_liquidityPools);
}

//+------------------------------------------------------------------+
//| Initialize                                                       |
//+------------------------------------------------------------------+
bool CLiquidityDetector::Initialize(const string symbol, ENUM_TIMEFRAMES timeframe, double equalTolerancePips)
{
    m_symbol = symbol;
    m_timeframe = timeframe;
    m_equalTolerance = equalTolerancePips;
    m_poolCount = 0;
    
    return true;
}

//+------------------------------------------------------------------+
//| Update                                                           |
//+------------------------------------------------------------------+
void CLiquidityDetector::Update()
{
    m_poolCount = 0;
    ArrayResize(m_liquidityPools, 0);
    
    DetectEqualHighsLows(500);  // Expanded from 50 for historical memory
    DetectSwingLiquidity(500);  // Expanded from 50 for historical memory
    DetectTimeframeLiquidity();
    
    // Check for sweeps
    for(int i = 0; i < m_poolCount; i++)
    {
        DetectLiquiditySweep(m_liquidityPools[i]);
    }
}

//+------------------------------------------------------------------+
//| Detect Equal Highs/Lows                                          |
//+------------------------------------------------------------------+
void CLiquidityDetector::DetectEqualHighsLows(int lookback)
{
    double tolerance = m_equalTolerance * SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    
    double high[], low[];
    datetime time[];
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(time, true);
    
    if(CopyHigh(m_symbol, m_timeframe, 0, lookback, high) <= 0) return;
    if(CopyLow(m_symbol, m_timeframe, 0, lookback, low) <= 0) return;
    if(CopyTime(m_symbol, m_timeframe, 0, lookback, time) <= 0) return;
    
    // Find equal highs (buy-side liquidity)
    for(int i = 5; i < lookback - 5; i++)
    {
        double high1 = high[i];
        
        for(int j = i + 3; j < i + 20 && j < lookback; j++)
        {
            double high2 = high[j];
            
            if(MathAbs(high1 - high2) < tolerance)
            {
                ArrayResize(m_liquidityPools, m_poolCount + 1);
                
                m_liquidityPools[m_poolCount].type = UICT_LIQ_EQUAL_HIGHS;
                m_liquidityPools[m_poolCount].time = time[i];
                m_liquidityPools[m_poolCount].price = (high1 + high2) / 2.0;
                m_liquidityPools[m_poolCount].touchCount = 2;
                m_liquidityPools[m_poolCount].strength = CalculateLiquidityStrength(i, j);
                m_liquidityPools[m_poolCount].timeframe = m_timeframe;
                m_liquidityPools[m_poolCount].isEngineered = true;
                m_poolCount++;
                break;
            }
        }
    }
    
    // Find equal lows (sell-side liquidity)
    for(int i = 5; i < lookback - 5; i++)
    {
        double low1 = low[i];
        
        for(int j = i + 3; j < i + 20 && j < lookback; j++)
        {
            double low2 = low[j];
            
            if(MathAbs(low1 - low2) < tolerance)
            {
                ArrayResize(m_liquidityPools, m_poolCount + 1);
                
                m_liquidityPools[m_poolCount].type = UICT_LIQ_EQUAL_LOWS;
                m_liquidityPools[m_poolCount].time = time[i];
                m_liquidityPools[m_poolCount].price = (low1 + low2) / 2.0;
                m_liquidityPools[m_poolCount].touchCount = 2;
                m_liquidityPools[m_poolCount].strength = CalculateLiquidityStrength(i, j);
                m_liquidityPools[m_poolCount].timeframe = m_timeframe;
                m_liquidityPools[m_poolCount].isEngineered = true;
                m_poolCount++;
                break;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Detect Swing Liquidity                                           |
//+------------------------------------------------------------------+
void CLiquidityDetector::DetectSwingLiquidity(int lookback)
{
    double high[], low[];
    datetime time[];
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(time, true);
    
    if(CopyHigh(m_symbol, m_timeframe, 0, lookback, high) <= 0) return;
    if(CopyLow(m_symbol, m_timeframe, 0, lookback, low) <= 0) return;
    if(CopyTime(m_symbol, m_timeframe, 0, lookback, time) <= 0) return;
    
    // Find swing highs
    for(int i = 3; i < lookback - 3; i++)
    {
        if(high[i] > high[i-1] && high[i] > high[i+1] &&
           high[i] > high[i-2] && high[i] > high[i+2])
        {
            ArrayResize(m_liquidityPools, m_poolCount + 1);
            
            m_liquidityPools[m_poolCount].type = UICT_LIQ_SWING_HIGH;
            m_liquidityPools[m_poolCount].time = time[i];
            m_liquidityPools[m_poolCount].price = high[i];
            m_liquidityPools[m_poolCount].touchCount = 1;
            m_liquidityPools[m_poolCount].strength = 0.70;
            m_liquidityPools[m_poolCount].timeframe = m_timeframe;
            m_poolCount++;
        }
    }
    
    // Find swing lows
    for(int i = 3; i < lookback - 3; i++)
    {
        if(low[i] < low[i-1] && low[i] < low[i+1] &&
           low[i] < low[i-2] && low[i] < low[i+2])
        {
            ArrayResize(m_liquidityPools, m_poolCount + 1);
            
            m_liquidityPools[m_poolCount].type = UICT_LIQ_SWING_LOW;
            m_liquidityPools[m_poolCount].time = time[i];
            m_liquidityPools[m_poolCount].price = low[i];
            m_liquidityPools[m_poolCount].touchCount = 1;
            m_liquidityPools[m_poolCount].strength = 0.70;
            m_liquidityPools[m_poolCount].timeframe = m_timeframe;
            m_poolCount++;
        }
    }
}

//+------------------------------------------------------------------+
//| Detect Timeframe Liquidity                                       |
//+------------------------------------------------------------------+
void CLiquidityDetector::DetectTimeframeLiquidity()
{
    // Daily high/low
    double dailyHigh = iHigh(m_symbol, PERIOD_D1, 1);
    double dailyLow = iLow(m_symbol, PERIOD_D1, 1);
    
    if(dailyHigh > 0)
    {
        ArrayResize(m_liquidityPools, m_poolCount + 1);
        m_liquidityPools[m_poolCount].type = UICT_LIQ_DAILY_HIGH;
        m_liquidityPools[m_poolCount].price = dailyHigh;
        m_liquidityPools[m_poolCount].strength = 0.85;
        m_liquidityPools[m_poolCount].timeframe = PERIOD_D1;
        m_poolCount++;
    }
    
    if(dailyLow > 0)
    {
        ArrayResize(m_liquidityPools, m_poolCount + 1);
        m_liquidityPools[m_poolCount].type = UICT_LIQ_DAILY_LOW;
        m_liquidityPools[m_poolCount].price = dailyLow;
        m_liquidityPools[m_poolCount].strength = 0.85;
        m_liquidityPools[m_poolCount].timeframe = PERIOD_D1;
        m_poolCount++;
    }
    
    // Weekly high/low
    double weeklyHigh = iHigh(m_symbol, PERIOD_W1, 1);
    double weeklyLow = iLow(m_symbol, PERIOD_W1, 1);
    
    if(weeklyHigh > 0)
    {
        ArrayResize(m_liquidityPools, m_poolCount + 1);
        m_liquidityPools[m_poolCount].type = UICT_LIQ_WEEKLY_HIGH;
        m_liquidityPools[m_poolCount].price = weeklyHigh;
        m_liquidityPools[m_poolCount].strength = 0.90;
        m_liquidityPools[m_poolCount].timeframe = PERIOD_W1;
        m_poolCount++;
    }
    
    if(weeklyLow > 0)
    {
        ArrayResize(m_liquidityPools, m_poolCount + 1);
        m_liquidityPools[m_poolCount].type = UICT_LIQ_WEEKLY_LOW;
        m_liquidityPools[m_poolCount].price = weeklyLow;
        m_liquidityPools[m_poolCount].strength = 0.90;
        m_liquidityPools[m_poolCount].timeframe = PERIOD_W1;
        m_poolCount++;
    }
}

//+------------------------------------------------------------------+
//| Detect Liquidity Sweep                                           |
//+------------------------------------------------------------------+
bool CLiquidityDetector::DetectLiquiditySweep(SLiquidityPool &pool)
{
    if(pool.isSwept) return false;
    
    double tolerance = 3 * SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    
    for(int i = 0; i < 20; i++)
    {
        datetime barTime = iTime(m_symbol, m_timeframe, i);
        if(barTime <= pool.time) break;
        
        double high = iHigh(m_symbol, m_timeframe, i);
        double low = iLow(m_symbol, m_timeframe, i);
        double close = iClose(m_symbol, m_timeframe, i);
        
        if(pool.type == UICT_LIQ_EQUAL_HIGHS || pool.type == UICT_LIQ_SWING_HIGH ||
           pool.type == UICT_LIQ_DAILY_HIGH || pool.type == UICT_LIQ_WEEKLY_HIGH)
        {
            // Check if swept above
            if(high > pool.price + tolerance)
            {
                // Must close back below to confirm reversal
                if(close < pool.price)
                {
                    pool.isSwept = true;
                    pool.sweptTime = barTime;
                    pool.confirmedReversal = true;
                    return true;
                }
            }
        }
        else if(pool.type == UICT_LIQ_EQUAL_LOWS || pool.type == UICT_LIQ_SWING_LOW ||
                pool.type == UICT_LIQ_DAILY_LOW || pool.type == UICT_LIQ_WEEKLY_LOW)
        {
            // Check if swept below
            if(low < pool.price - tolerance)
            {
                // Must close back above
                if(close > pool.price)
                {
                    pool.isSwept = true;
                    pool.sweptTime = barTime;
                    pool.confirmedReversal = true;
                    return true;
                }
            }
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Has Recent Sweep                                                 |
//+------------------------------------------------------------------+
bool CLiquidityDetector::HasRecentSweep(bool &isBuyside)
{
    for(int i = 0; i < m_poolCount; i++)
    {
        if(m_liquidityPools[i].isSwept && m_liquidityPools[i].confirmedReversal)
        {
            // Check if sweep was recent (within last 5 bars)
            int barsAgo = iBarShift(m_symbol, m_timeframe, m_liquidityPools[i].sweptTime);
            if(barsAgo >= 0 && barsAgo <= 5)
            {
                isBuyside = (m_liquidityPools[i].type == UICT_LIQ_EQUAL_HIGHS ||
                            m_liquidityPools[i].type == UICT_LIQ_SWING_HIGH ||
                            m_liquidityPools[i].type == UICT_LIQ_DAILY_HIGH ||
                            m_liquidityPools[i].type == UICT_LIQ_WEEKLY_HIGH);
                return true;
            }
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Calculate Liquidity Strength                                     |
//+------------------------------------------------------------------+
double CLiquidityDetector::CalculateLiquidityStrength(int bar1, int bar2)
{
    double strength = 0.60;
    
    // Time between touches
    int barsBetween = bar2 - bar1;
    if(barsBetween >= 10)
        strength += 0.15;
    
    // Check if at psychological level
    double price = iHigh(m_symbol, m_timeframe, bar1);
    if(IsAtPsychologicalLevel(price))
        strength += 0.15;
    
    // Volume check
    long vol1 = iVolume(m_symbol, m_timeframe, bar1);
    long vol2 = iVolume(m_symbol, m_timeframe, bar2);
    long avgVol = GetAverageVolume(20);
    
    if(avgVol > 0 && (vol1 > avgVol * 1.5 || vol2 > avgVol * 1.5))
        strength += 0.10;
    
    return MathMin(1.0, strength);
}

//+------------------------------------------------------------------+
//| Is At Psychological Level                                        |
//+------------------------------------------------------------------+
bool CLiquidityDetector::IsAtPsychologicalLevel(double price)
{
    int digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
    
    if(digits == 5 || digits == 3)
    {
        double normalized = MathRound(price * 10000) / 10000;
        double fraction = normalized - MathFloor(normalized);
        
        if(MathAbs(fraction - 0.0000) < 0.0002) return true;
        if(MathAbs(fraction - 0.0050) < 0.0002) return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Get Average Volume                                               |
//+------------------------------------------------------------------+
long CLiquidityDetector::GetAverageVolume(int bars)
{
    long avgVol = 0;
    
    for(int i = 0; i < bars; i++)
        avgVol += iVolume(m_symbol, m_timeframe, i);
    
    return (bars > 0) ? avgVol / bars : 0;
}

//+------------------------------------------------------------------+
//| Get Pool                                                         |
//+------------------------------------------------------------------+
bool CLiquidityDetector::GetPool(int index, SLiquidityPool &pool)
{
    if(index < 0 || index >= m_poolCount) return false;
    pool = m_liquidityPools[index];
    return true;
}

//+------------------------------------------------------------------+
//| Find Nearest Liquidity                                           |
//+------------------------------------------------------------------+
int CLiquidityDetector::FindNearestLiquidity(double price, bool above)
{
    int nearestIndex = -1;
    double minDistance = DBL_MAX;
    
    for(int i = 0; i < m_poolCount; i++)
    {
        if(m_liquidityPools[i].isSwept) continue;
        
        if(above)
        {
            if(m_liquidityPools[i].price > price)
            {
                double dist = m_liquidityPools[i].price - price;
                if(dist < minDistance)
                {
                    minDistance = dist;
                    nearestIndex = i;
                }
            }
        }
        else
        {
            if(m_liquidityPools[i].price < price)
            {
                double dist = price - m_liquidityPools[i].price;
                if(dist < minDistance)
                {
                    minDistance = dist;
                    nearestIndex = i;
                }
            }
        }
    }
    
    return nearestIndex;
}

//+------------------------------------------------------------------+
//| Find Swept Liquidity                                             |
//+------------------------------------------------------------------+
int CLiquidityDetector::FindSweptLiquidity()
{
    for(int i = 0; i < m_poolCount; i++)
    {
        if(m_liquidityPools[i].isSwept && m_liquidityPools[i].confirmedReversal)
        {
            return i;
        }
    }
    
    return -1;
}

//+------------------------------------------------------------------+
//| Is Near Liquidity                                                |
//+------------------------------------------------------------------+
bool CLiquidityDetector::IsNearLiquidity(double price, double tolerancePips)
{
    double tolerance = tolerancePips * SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    
    for(int i = 0; i < m_poolCount; i++)
    {
        if(MathAbs(price - m_liquidityPools[i].price) < tolerance)
            return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Has Buyside Liquidity                                            |
//+------------------------------------------------------------------+
bool CLiquidityDetector::HasBuysideLiquidity(double price)
{
    return (FindNearestLiquidity(price, true) >= 0);
}

//+------------------------------------------------------------------+
//| Has Sellside Liquidity                                           |
//+------------------------------------------------------------------+
bool CLiquidityDetector::HasSellsideLiquidity(double price)
{
    return (FindNearestLiquidity(price, false) >= 0);
}

#endif // __UICT_LIQUIDITY_DETECTOR_MQH__
