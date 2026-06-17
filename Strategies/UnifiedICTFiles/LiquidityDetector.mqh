//+------------------------------------------------------------------+
//| LiquidityDetector.mqh                                            |
//| Liquidity Pool and Sweep Detection for Unified ICT               |
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
    UICT_LIQ_WEEKLY_LOW,
    UICT_LIQ_MONTHLY_HIGH,
    UICT_LIQ_MONTHLY_LOW,
    UICT_LIQ_MIDNIGHT_OPEN,
    UICT_LIQ_QUARTERLY_OPEN,
    UICT_LIQ_QUARTERLY_HIGH,
    UICT_LIQ_QUARTERLY_LOW
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

struct STurtleSoupSignal
{
    bool detected;
    bool bullish;
    double referencePrice;
    double sweepPrice;
    double reclaimClose;
    datetime eventTime;
    double confidence;

    STurtleSoupSignal() : detected(false), bullish(false), referencePrice(0.0),
                          sweepPrice(0.0), reclaimClose(0.0), eventTime(0), confidence(0.0) {}
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
    void                AddLiquidityLevel(const ENUM_UICT_LIQUIDITY_TYPE type,
                                          const datetime time,
                                          const double price,
                                          const double strength,
                                          const ENUM_TIMEFRAMES timeframe,
                                          const bool engineered = false);
    void                DetectInstitutionalLevels();
    bool                IsUSDSTime(const datetime when) const;
    datetime            BuildNewYorkTimestampGMT(const int year,
                                                 const int mon,
                                                 const int day,
                                                 const int hour,
                                                 const int minute,
                                                 const int second) const;
    double              FindTimeRangeExtreme(const datetime startTime,
                                             const datetime endTime,
                                             const bool wantHigh) const;
    
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
    bool                DetectTurtleSoup(STurtleSoupSignal &signal, const int maxBarsAgo = 3);
    
    // Getters
    int                 GetPoolCount() const { return m_poolCount; }
    bool                GetPool(int index, SLiquidityPool &pool);
    int                 FindNearestLiquidity(double price, bool above);
    int                 FindSweptLiquidity();
    
    // Checks
    bool                IsNearLiquidity(double price, double tolerancePips = 20);
    bool                HasBuysideLiquidity(double price);
    bool                HasSellsideLiquidity(double price);

    // Batch 103: External swing liquidity mapping
    struct SExternalLiquidityPool
    {
        double price;
        double strength;        // 0.0-1.0
        bool   isHigh;          // true = swing high liquidity, false = swing low
        bool   isSwept;
        int    barAge;          // Bars since the swing formed

        SExternalLiquidityPool() : price(0), strength(0), isHigh(false), isSwept(false), barAge(0) {}
    };

    int                 DetectExternalSwingLiquidity(SExternalLiquidityPool &pools[], int maxPools = 10, int lookback = 100);
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
    DetectInstitutionalLevels();
    
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
    double dailyHigh = iHigh(m_symbol, PERIOD_D1, 1);
    double dailyLow = iLow(m_symbol, PERIOD_D1, 1);
    double weeklyHigh = iHigh(m_symbol, PERIOD_W1, 1);
    double weeklyLow = iLow(m_symbol, PERIOD_W1, 1);

    AddLiquidityLevel(UICT_LIQ_DAILY_HIGH,  iTime(m_symbol, PERIOD_D1, 1), dailyHigh, 0.85, PERIOD_D1);
    AddLiquidityLevel(UICT_LIQ_DAILY_LOW,   iTime(m_symbol, PERIOD_D1, 1), dailyLow,  0.85, PERIOD_D1);
    AddLiquidityLevel(UICT_LIQ_WEEKLY_HIGH, iTime(m_symbol, PERIOD_W1, 1), weeklyHigh, 0.90, PERIOD_W1);
    AddLiquidityLevel(UICT_LIQ_WEEKLY_LOW,  iTime(m_symbol, PERIOD_W1, 1), weeklyLow,  0.90, PERIOD_W1);
}

void CLiquidityDetector::AddLiquidityLevel(const ENUM_UICT_LIQUIDITY_TYPE type,
                                           const datetime time,
                                           const double price,
                                           const double strength,
                                           const ENUM_TIMEFRAMES timeframe,
                                           const bool engineered)
{
    if(price <= 0.0)
        return;

    ArrayResize(m_liquidityPools, m_poolCount + 1);
    m_liquidityPools[m_poolCount] = SLiquidityPool();
    m_liquidityPools[m_poolCount].type = type;
    m_liquidityPools[m_poolCount].time = time;
    m_liquidityPools[m_poolCount].price = price;
    m_liquidityPools[m_poolCount].touchCount = 1;
    m_liquidityPools[m_poolCount].strength = strength;
    m_liquidityPools[m_poolCount].timeframe = timeframe;
    m_liquidityPools[m_poolCount].isEngineered = engineered;
    m_poolCount++;
}

bool CLiquidityDetector::IsUSDSTime(const datetime when) const
{
    MqlDateTime dt;
    TimeToStruct(when, dt);
    int year = dt.year;

    MqlDateTime marchStart;
    marchStart.year = year;
    marchStart.mon = 3;
    marchStart.day = 1;
    marchStart.hour = 2;
    marchStart.min = 0;
    marchStart.sec = 0;
    datetime marchStartTime = StructToTime(marchStart);
    MqlDateTime marchProbe;
    TimeToStruct(marchStartTime, marchProbe);
    int marchDow = marchProbe.day_of_week;
    int firstSundayMarch = (marchDow == 0) ? 1 : (8 - marchDow);
    int secondSundayMarch = firstSundayMarch + 7;

    MqlDateTime dstStartStruct = marchStart;
    dstStartStruct.day = secondSundayMarch;
    datetime dstStart = StructToTime(dstStartStruct);

    MqlDateTime novemberStart;
    novemberStart.year = year;
    novemberStart.mon = 11;
    novemberStart.day = 1;
    novemberStart.hour = 2;
    novemberStart.min = 0;
    novemberStart.sec = 0;
    datetime novemberStartTime = StructToTime(novemberStart);
    MqlDateTime novemberProbe;
    TimeToStruct(novemberStartTime, novemberProbe);
    int novemberDow = novemberProbe.day_of_week;
    int firstSundayNovember = (novemberDow == 0) ? 1 : (8 - novemberDow);

    MqlDateTime dstEndStruct = novemberStart;
    dstEndStruct.day = firstSundayNovember;
    datetime dstEnd = StructToTime(dstEndStruct);

    return (when >= dstStart && when < dstEnd);
}

datetime CLiquidityDetector::BuildNewYorkTimestampGMT(const int year,
                                                      const int mon,
                                                      const int day,
                                                      const int hour,
                                                      const int minute,
                                                      const int second) const
{
    MqlDateTime nyStruct;
    nyStruct.year = year;
    nyStruct.mon = mon;
    nyStruct.day = day;
    nyStruct.hour = hour;
    nyStruct.min = minute;
    nyStruct.sec = second;

    datetime approxGmt = StructToTime(nyStruct) + (5 * 3600);
    int offset = IsUSDSTime(approxGmt) ? -4 : -5;
    return StructToTime(nyStruct) - (offset * 3600);
}

double CLiquidityDetector::FindTimeRangeExtreme(const datetime rangeStartTime,
                                                const datetime rangeEndTime,
                                                const bool wantHigh) const
{
    int olderShift = iBarShift(m_symbol, PERIOD_D1, rangeStartTime, false);
    int recentShift = iBarShift(m_symbol, PERIOD_D1, rangeEndTime, false);
    if(olderShift < 0 || recentShift < 0)
        return 0.0;

    if(recentShift > olderShift)
    {
        int tmp = recentShift;
        recentShift = olderShift;
        olderShift = tmp;
    }

    double extreme = wantHigh ? -DBL_MAX : DBL_MAX;
    for(int i = recentShift; i <= olderShift; i++)
    {
        double value = wantHigh ? iHigh(m_symbol, PERIOD_D1, i) : iLow(m_symbol, PERIOD_D1, i);
        if(value <= 0.0)
            continue;

        if(wantHigh)
            extreme = MathMax(extreme, value);
        else
            extreme = MathMin(extreme, value);
    }

    if(wantHigh && extreme <= -DBL_MAX / 2.0)
        return 0.0;
    if(!wantHigh && extreme >= DBL_MAX / 2.0)
        return 0.0;

    return extreme;
}

void CLiquidityDetector::DetectInstitutionalLevels()
{
    AddLiquidityLevel(UICT_LIQ_MONTHLY_HIGH, iTime(m_symbol, PERIOD_MN1, 1), iHigh(m_symbol, PERIOD_MN1, 1), 0.92, PERIOD_MN1, true);
    AddLiquidityLevel(UICT_LIQ_MONTHLY_LOW,  iTime(m_symbol, PERIOD_MN1, 1), iLow(m_symbol, PERIOD_MN1, 1),  0.92, PERIOD_MN1, true);

    datetime nowGmt = TimeGMT();
    int offset = IsUSDSTime(nowGmt) ? -4 : -5;
    datetime nowNy = nowGmt + (offset * 3600);
    MqlDateTime nyNow;
    TimeToStruct(nowNy, nyNow);

    datetime midnightGmt = BuildNewYorkTimestampGMT(nyNow.year, nyNow.mon, nyNow.day, 0, 0, 0);
    int midnightShift = iBarShift(m_symbol, PERIOD_M15, midnightGmt, false);
    if(midnightShift >= 0)
    {
        AddLiquidityLevel(UICT_LIQ_MIDNIGHT_OPEN,
                          iTime(m_symbol, PERIOD_M15, midnightShift),
                          iOpen(m_symbol, PERIOD_M15, midnightShift),
                          0.88,
                          PERIOD_M15,
                          true);
    }

    int quarterStartMonth = ((nyNow.mon - 1) / 3) * 3 + 1;
    datetime quarterOpenGmt = BuildNewYorkTimestampGMT(nyNow.year, quarterStartMonth, 1, 0, 0, 0);
    int quarterOpenShift = iBarShift(m_symbol, PERIOD_D1, quarterOpenGmt, false);
    if(quarterOpenShift >= 0)
    {
        AddLiquidityLevel(UICT_LIQ_QUARTERLY_OPEN,
                          iTime(m_symbol, PERIOD_D1, quarterOpenShift),
                          iOpen(m_symbol, PERIOD_D1, quarterOpenShift),
                          0.95,
                          PERIOD_D1,
                          true);
    }

    int prevQuarterMonth = quarterStartMonth - 3;
    int prevQuarterYear = nyNow.year;
    if(prevQuarterMonth <= 0)
    {
        prevQuarterMonth += 12;
        prevQuarterYear--;
    }

    datetime prevQuarterStartGmt = BuildNewYorkTimestampGMT(prevQuarterYear, prevQuarterMonth, 1, 0, 0, 0);
    datetime prevQuarterEndGmt = quarterOpenGmt - 60;
    double quarterHigh = FindTimeRangeExtreme(prevQuarterStartGmt, prevQuarterEndGmt, true);
    double quarterLow = FindTimeRangeExtreme(prevQuarterStartGmt, prevQuarterEndGmt, false);

    AddLiquidityLevel(UICT_LIQ_QUARTERLY_HIGH, prevQuarterStartGmt, quarterHigh, 0.95, PERIOD_D1, true);
    AddLiquidityLevel(UICT_LIQ_QUARTERLY_LOW,  prevQuarterStartGmt, quarterLow,  0.95, PERIOD_D1, true);
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
           pool.type == UICT_LIQ_DAILY_HIGH || pool.type == UICT_LIQ_WEEKLY_HIGH ||
           pool.type == UICT_LIQ_MONTHLY_HIGH || pool.type == UICT_LIQ_QUARTERLY_HIGH)
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
                pool.type == UICT_LIQ_DAILY_LOW || pool.type == UICT_LIQ_WEEKLY_LOW ||
                pool.type == UICT_LIQ_MONTHLY_LOW || pool.type == UICT_LIQ_QUARTERLY_LOW)
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
            // Check if sweep was recent (within last 15 bars — widened from 5 for synthetics
            // where liquidity sweeps may take more bars to develop on M15+)
            int barsAgo = iBarShift(m_symbol, m_timeframe, m_liquidityPools[i].sweptTime);
            if(barsAgo >= 0 && barsAgo <= 15)
            {
                isBuyside = (m_liquidityPools[i].type == UICT_LIQ_EQUAL_HIGHS ||
                            m_liquidityPools[i].type == UICT_LIQ_SWING_HIGH ||
                            m_liquidityPools[i].type == UICT_LIQ_DAILY_HIGH ||
                            m_liquidityPools[i].type == UICT_LIQ_WEEKLY_HIGH ||
                            m_liquidityPools[i].type == UICT_LIQ_MONTHLY_HIGH ||
                            m_liquidityPools[i].type == UICT_LIQ_QUARTERLY_HIGH);
                return true;
            }
        }
    }
    
    return false;
}

bool CLiquidityDetector::DetectTurtleSoup(STurtleSoupSignal &signal, const int maxBarsAgo)
{
    signal = STurtleSoupSignal();
    int limit = MathMax(1, maxBarsAgo);
    double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    if(point <= 0.0)
        point = 0.00001;

    for(int i = 0; i < m_poolCount; i++)
    {
        SLiquidityPool pool = m_liquidityPools[i];
        if(pool.price <= 0.0)
            continue;

        bool poolIsHigh =
            (pool.type == UICT_LIQ_EQUAL_HIGHS || pool.type == UICT_LIQ_SWING_HIGH ||
             pool.type == UICT_LIQ_DAILY_HIGH || pool.type == UICT_LIQ_WEEKLY_HIGH ||
             pool.type == UICT_LIQ_MONTHLY_HIGH || pool.type == UICT_LIQ_QUARTERLY_HIGH);
        bool poolIsLow =
            (pool.type == UICT_LIQ_EQUAL_LOWS || pool.type == UICT_LIQ_SWING_LOW ||
             pool.type == UICT_LIQ_DAILY_LOW || pool.type == UICT_LIQ_WEEKLY_LOW ||
             pool.type == UICT_LIQ_MONTHLY_LOW || pool.type == UICT_LIQ_QUARTERLY_LOW);
        if(!poolIsHigh && !poolIsLow)
            continue;

        for(int shift = 1; shift <= limit; shift++)
        {
            double high = iHigh(m_symbol, m_timeframe, shift);
            double low = iLow(m_symbol, m_timeframe, shift);
            double close = iClose(m_symbol, m_timeframe, shift);
            double open = iOpen(m_symbol, m_timeframe, shift);
            if(high <= 0.0 || low <= 0.0)
                continue;

            if(poolIsHigh && high > (pool.price + point) && close < pool.price && close < open)
            {
                signal.detected = true;
                signal.bullish = false;
                signal.referencePrice = pool.price;
                signal.sweepPrice = high;
                signal.reclaimClose = close;
                signal.eventTime = iTime(m_symbol, m_timeframe, shift);
                signal.confidence = MathMin(0.95, 0.60 + pool.strength * 0.25 + ((high - pool.price) / (10.0 * point)) * 0.05);
                return true;
            }

            if(poolIsLow && low < (pool.price - point) && close > pool.price && close > open)
            {
                signal.detected = true;
                signal.bullish = true;
                signal.referencePrice = pool.price;
                signal.sweepPrice = low;
                signal.reclaimClose = close;
                signal.eventTime = iTime(m_symbol, m_timeframe, shift);
                signal.confidence = MathMin(0.95, 0.60 + pool.strength * 0.25 + ((pool.price - low) / (10.0 * point)) * 0.05);
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

//+------------------------------------------------------------------+
//| Detect External Swing Liquidity — Batch 103                      |
//| Scans for swing highs/lows that align with daily/weekly levels   |
//| Returns count of pools found, fills the pools array              |
//+------------------------------------------------------------------+
int CLiquidityDetector::DetectExternalSwingLiquidity(SExternalLiquidityPool &pools[], int maxPools = 10, int lookback = 100)
{
    ArrayResize(pools, 0);
    int found = 0;

    // Scan for swing highs (external buy-side liquidity)
    for(int i = 2; i < lookback - 2 && found < maxPools; i++)
    {
        double h = iHigh(m_symbol, m_timeframe, i);
        double hLeft = iHigh(m_symbol, m_timeframe, i + 1);
        double hRight = iHigh(m_symbol, m_timeframe, i - 1);
        if(h <= 0 || hLeft <= 0 || hRight <= 0) continue;

        if(h > hLeft && h > hRight)
        {
            // Check if this swing high has been swept (current price above it)
            double currentPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);
            bool swept = (currentPrice > h);

            SExternalLiquidityPool pool;
            pool.price = h;
            pool.isHigh = true;
            pool.isSwept = swept;
            pool.barAge = i;
            // Strength based on how many touches near this level
            pool.strength = 0.5;
            // Check for equal highs (multiple bars near same price = stronger liquidity)
            for(int j = i + 2; j < MathMin(i + 20, lookback - 2); j++)
            {
                double h2 = iHigh(m_symbol, m_timeframe, j);
                if(h2 > 0 && MathAbs(h2 - h) < m_equalTolerance * SymbolInfoDouble(m_symbol, SYMBOL_POINT))
                {
                    pool.strength = MathMin(1.0, pool.strength + 0.15);
                    break;
                }
            }

            ArrayResize(pools, found + 1);
            pools[found] = pool;
            found++;
        }
    }

    // Scan for swing lows (external sell-side liquidity)
    for(int i = 2; i < lookback - 2 && found < maxPools; i++)
    {
        double l = iLow(m_symbol, m_timeframe, i);
        double lLeft = iLow(m_symbol, m_timeframe, i + 1);
        double lRight = iLow(m_symbol, m_timeframe, i - 1);
        if(l <= 0 || lLeft <= 0 || lRight <= 0) continue;

        if(l < lLeft && l < lRight)
        {
            double currentPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);
            bool swept = (currentPrice < l);

            SExternalLiquidityPool pool;
            pool.price = l;
            pool.isHigh = false;
            pool.isSwept = swept;
            pool.barAge = i;
            pool.strength = 0.5;
            for(int j = i + 2; j < MathMin(i + 20, lookback - 2); j++)
            {
                double l2 = iLow(m_symbol, m_timeframe, j);
                if(l2 > 0 && MathAbs(l2 - l) < m_equalTolerance * SymbolInfoDouble(m_symbol, SYMBOL_POINT))
                {
                    pool.strength = MathMin(1.0, pool.strength + 0.15);
                    break;
                }
            }

            ArrayResize(pools, found + 1);
            pools[found] = pool;
            found++;
        }
    }

    return found;
}

#endif // __UICT_LIQUIDITY_DETECTOR_MQH__
