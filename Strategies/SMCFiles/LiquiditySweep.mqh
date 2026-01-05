//+------------------------------------------------------------------+
//| LiquiditySweep.mqh                                               |
//| Liquidity Sweep Detection for SMC Strategy                       |
//| Identifies stop hunts and false breakouts                        |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Multi-Strategy EA"
#property version   "2.00"
#property strict

#ifndef __SMC_LIQUIDITY_SWEEP_MQH__
#define __SMC_LIQUIDITY_SWEEP_MQH__

//+------------------------------------------------------------------+
//| Liquidity Type                                                   |
//+------------------------------------------------------------------+
enum ENUM_LIQUIDITY_TYPE
{
    LIQ_BUYSIDE,    // Swing highs (stops above - swept for sells)
    LIQ_SELLSIDE    // Swing lows (stops below - swept for buys)
};

//+------------------------------------------------------------------+
//| Liquidity Sweep Structure                                        |
//+------------------------------------------------------------------+
struct SLiquiditySweep
{
    double          swingLevel;
    datetime        swingTime;
    datetime        sweepTime;
    int             sweepBar;
    bool            isBullish;      // Sweep of lows = bullish opportunity
    bool            confirmed;      // Closed back above/below level
    double          wickSize;       // Large wick = stronger rejection
    double          sweepDepth;     // How far beyond swing
    double          score;
    
    // Confluence
    bool            hasOrderBlock;
    bool            hasFVG;
    bool            atPremiumDiscount;
    
    // Identification
    string          id;
    
    SLiquiditySweep() : swingLevel(0), swingTime(0), sweepTime(0), sweepBar(0),
                        isBullish(false), confirmed(false), wickSize(0), sweepDepth(0),
                        score(0), hasOrderBlock(false), hasFVG(false),
                        atPremiumDiscount(false), id("") {}
};

//+------------------------------------------------------------------+
//| Liquidity Sweep Detection Class                                  |
//+------------------------------------------------------------------+
class CSMCLiquiditySweep
{
private:
    string              m_symbol;
    ENUM_TIMEFRAMES     m_timeframe;
    
    // Sweep storage
    SLiquiditySweep     m_sweeps[];
    int                 m_maxSweeps;
    int                 m_sweepCount;
    
    // Swing tracking
    double              m_swingHighs[];
    datetime            m_swingHighTimes[];
    double              m_swingLows[];
    datetime            m_swingLowTimes[];
    int                 m_swingCount;
    
    // Configuration
    int                 m_swingStrength;     // Bars for swing validation
    double              m_minWickRatio;      // Min wick/body ratio for rejection
    int                 m_lookback;          // Bars to scan for swings
    
    // Internal methods
    void                DetectSwingPoints();
    bool                IsSweepConfirmed(int barIndex, double swingLevel, bool isBuyside);
    double              ScoreSweep(const SLiquiditySweep &sweep);
    
public:
                        CSMCLiquiditySweep();
                       ~CSMCLiquiditySweep();
    
    // Initialization
    bool                Initialize(const string symbol, ENUM_TIMEFRAMES timeframe,
                                  int swingStrength = 3, double minWickRatio = 1.5);
    
    // Detection
    void                ScanForSweeps(int scanBars = 5);
    void                UpdateSweeps();
    
    // Getters
    int                 GetSweepCount() const { return m_sweepCount; }
    bool                GetSweepAt(int index, SLiquiditySweep &sweep);
    bool                GetLatestBullishSweep(SLiquiditySweep &sweep);
    bool                GetLatestBearishSweep(SLiquiditySweep &sweep);
    
    // Detection checks
    bool                HasRecentBullishSweep(int barsAgo = 5);
    bool                HasRecentBearishSweep(int barsAgo = 5);
    
    // Configuration
    void                SetSwingStrength(int strength) { m_swingStrength = strength; }
    void                SetMinWickRatio(double ratio) { m_minWickRatio = ratio; }
    void                SetLookback(int bars) { m_lookback = bars; }
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CSMCLiquiditySweep::CSMCLiquiditySweep() :
    m_symbol(""),
    m_timeframe(PERIOD_CURRENT),
    m_maxSweeps(20),
    m_sweepCount(0),
    m_swingCount(20),
    m_swingStrength(3),
    m_minWickRatio(1.5),
    m_lookback(50)
{
    ArrayResize(m_sweeps, 0);
    ArrayResize(m_swingHighs, m_swingCount);
    ArrayResize(m_swingHighTimes, m_swingCount);
    ArrayResize(m_swingLows, m_swingCount);
    ArrayResize(m_swingLowTimes, m_swingCount);
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CSMCLiquiditySweep::~CSMCLiquiditySweep()
{
    ArrayFree(m_sweeps);
    ArrayFree(m_swingHighs);
    ArrayFree(m_swingHighTimes);
    ArrayFree(m_swingLows);
    ArrayFree(m_swingLowTimes);
}

//+------------------------------------------------------------------+
//| Initialize                                                       |
//+------------------------------------------------------------------+
bool CSMCLiquiditySweep::Initialize(const string symbol, ENUM_TIMEFRAMES timeframe,
                                    int swingStrength, double minWickRatio)
{
    m_symbol = symbol;
    m_timeframe = timeframe;
    m_swingStrength = swingStrength;
    m_minWickRatio = minWickRatio;
    
    ArrayResize(m_sweeps, 0);
    m_sweepCount = 0;
    
    // Initial swing detection
    DetectSwingPoints();
    
    return true;
}

//+------------------------------------------------------------------+
//| Detect Swing Points                                              |
//+------------------------------------------------------------------+
void CSMCLiquiditySweep::DetectSwingPoints()
{
    int bars = iBars(m_symbol, m_timeframe);
    if(bars < m_lookback) return;
    
    int highIndex = 0;
    int lowIndex = 0;
    
    ArrayInitialize(m_swingHighs, 0);
    ArrayInitialize(m_swingLows, 0);
    
    for(int i = m_swingStrength; i < m_lookback - m_swingStrength; i++)
    {
        double high = iHigh(m_symbol, m_timeframe, i);
        double low = iLow(m_symbol, m_timeframe, i);
        
        // Check swing high
        bool isSwingHigh = true;
        for(int j = 1; j <= m_swingStrength; j++)
        {
            if(iHigh(m_symbol, m_timeframe, i - j) >= high ||
               iHigh(m_symbol, m_timeframe, i + j) >= high)
            {
                isSwingHigh = false;
                break;
            }
        }
        
        if(isSwingHigh && highIndex < m_swingCount)
        {
            m_swingHighs[highIndex] = high;
            m_swingHighTimes[highIndex] = iTime(m_symbol, m_timeframe, i);
            highIndex++;
        }
        
        // Check swing low
        bool isSwingLow = true;
        for(int j = 1; j <= m_swingStrength; j++)
        {
            if(iLow(m_symbol, m_timeframe, i - j) <= low ||
               iLow(m_symbol, m_timeframe, i + j) <= low)
            {
                isSwingLow = false;
                break;
            }
        }
        
        if(isSwingLow && lowIndex < m_swingCount)
        {
            m_swingLows[lowIndex] = low;
            m_swingLowTimes[lowIndex] = iTime(m_symbol, m_timeframe, i);
            lowIndex++;
        }
    }
}

//+------------------------------------------------------------------+
//| Is Sweep Confirmed                                               |
//+------------------------------------------------------------------+
bool CSMCLiquiditySweep::IsSweepConfirmed(int barIndex, double swingLevel, bool isBuyside)
{
    double high = iHigh(m_symbol, m_timeframe, barIndex);
    double low = iLow(m_symbol, m_timeframe, barIndex);
    double close = iClose(m_symbol, m_timeframe, barIndex);
    double open = iOpen(m_symbol, m_timeframe, barIndex);
    
    if(isBuyside)
    {
        // Buyside sweep: price went above swing high, but closed below
        return (high > swingLevel && close < swingLevel);
    }
    else
    {
        // Sellside sweep: price went below swing low, but closed above
        return (low < swingLevel && close > swingLevel);
    }
}

//+------------------------------------------------------------------+
//| Score Sweep                                                      |
//+------------------------------------------------------------------+
double CSMCLiquiditySweep::ScoreSweep(const SLiquiditySweep &sweep)
{
    double score = 50.0; // Base score
    
    // Confirmation bonus
    if(sweep.confirmed)
        score += 20.0;
    
    // Large wick bonus (strong rejection)
    if(sweep.wickSize > 0)
    {
        double avgRange = 0;
        for(int i = 1; i <= 20; i++)
        {
            avgRange += iHigh(m_symbol, m_timeframe, i) - iLow(m_symbol, m_timeframe, i);
        }
        avgRange /= 20;
        
        if(sweep.wickSize > avgRange * 0.5)
            score += 15.0;
        else if(sweep.wickSize > avgRange * 0.3)
            score += 8.0;
    }
    
    // Confluence bonuses
    if(sweep.hasOrderBlock)
        score += 15.0;
    if(sweep.hasFVG)
        score += 10.0;
    if(sweep.atPremiumDiscount)
        score += 10.0;
    
    return MathMax(0, MathMin(100, score));
}

//+------------------------------------------------------------------+
//| Scan for Sweeps                                                  |
//+------------------------------------------------------------------+
void CSMCLiquiditySweep::ScanForSweeps(int scanBars)
{
    // Update swing points first
    DetectSwingPoints();
    
    int bars = iBars(m_symbol, m_timeframe);
    if(bars < scanBars + 5) return;
    
    // Scan recent bars for sweeps
    for(int i = 1; i <= scanBars; i++)
    {
        double high = iHigh(m_symbol, m_timeframe, i);
        double low = iLow(m_symbol, m_timeframe, i);
        double close = iClose(m_symbol, m_timeframe, i);
        double open = iOpen(m_symbol, m_timeframe, i);
        datetime barTime = iTime(m_symbol, m_timeframe, i);
        
        // Calculate wicks
        double upperWick = high - MathMax(open, close);
        double lowerWick = MathMin(open, close) - low;
        double body = MathAbs(close - open);
        
        // Check for buyside sweep (sweep of highs = bearish opportunity)
        for(int j = 0; j < m_swingCount; j++)
        {
            if(m_swingHighs[j] <= 0) continue;
            if(m_swingHighTimes[j] >= barTime) continue; // Swing must be before bar
            
            // Check if bar swept above swing high and closed below
            if(high > m_swingHighs[j] && close < m_swingHighs[j])
            {
                // Check for rejection (upper wick)
                if(upperWick >= body * m_minWickRatio || upperWick > lowerWick * 2)
                {
                    SLiquiditySweep sweep;
                    sweep.swingLevel = m_swingHighs[j];
                    sweep.swingTime = m_swingHighTimes[j];
                    sweep.sweepTime = barTime;
                    sweep.sweepBar = i;
                    sweep.isBullish = false; // Bearish opportunity after buyside sweep
                    sweep.confirmed = true;
                    sweep.wickSize = upperWick;
                    sweep.sweepDepth = high - m_swingHighs[j];
                    sweep.id = StringFormat("SWEEP_%d_BEAR", (int)barTime);
                    sweep.score = ScoreSweep(sweep);
                    
                    // Check for duplicates
                    bool exists = false;
                    for(int k = 0; k < m_sweepCount; k++)
                    {
                        if(m_sweeps[k].sweepTime == barTime && m_sweeps[k].swingLevel == sweep.swingLevel)
                        {
                            exists = true;
                            break;
                        }
                    }
                    
                    if(!exists && m_sweepCount < m_maxSweeps)
                    {
                        ArrayResize(m_sweeps, m_sweepCount + 1);
                        m_sweeps[m_sweepCount++] = sweep;
                    }
                    break;
                }
            }
        }
        
        // Check for sellside sweep (sweep of lows = bullish opportunity)
        for(int j = 0; j < m_swingCount; j++)
        {
            if(m_swingLows[j] <= 0) continue;
            if(m_swingLowTimes[j] >= barTime) continue;
            
            // Check if bar swept below swing low and closed above
            if(low < m_swingLows[j] && close > m_swingLows[j])
            {
                // Check for rejection (lower wick)
                if(lowerWick >= body * m_minWickRatio || lowerWick > upperWick * 2)
                {
                    SLiquiditySweep sweep;
                    sweep.swingLevel = m_swingLows[j];
                    sweep.swingTime = m_swingLowTimes[j];
                    sweep.sweepTime = barTime;
                    sweep.sweepBar = i;
                    sweep.isBullish = true; // Bullish opportunity after sellside sweep
                    sweep.confirmed = true;
                    sweep.wickSize = lowerWick;
                    sweep.sweepDepth = m_swingLows[j] - low;
                    sweep.id = StringFormat("SWEEP_%d_BULL", (int)barTime);
                    sweep.score = ScoreSweep(sweep);
                    
                    // Check for duplicates
                    bool exists = false;
                    for(int k = 0; k < m_sweepCount; k++)
                    {
                        if(m_sweeps[k].sweepTime == barTime && m_sweeps[k].swingLevel == sweep.swingLevel)
                        {
                            exists = true;
                            break;
                        }
                    }
                    
                    if(!exists && m_sweepCount < m_maxSweeps)
                    {
                        ArrayResize(m_sweeps, m_sweepCount + 1);
                        m_sweeps[m_sweepCount++] = sweep;
                    }
                    break;
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Update Sweeps                                                    |
//+------------------------------------------------------------------+
void CSMCLiquiditySweep::UpdateSweeps()
{
    // Remove old sweeps (older than 50 bars)
    for(int i = m_sweepCount - 1; i >= 0; i--)
    {
        int age = Bars(m_symbol, m_timeframe, m_sweeps[i].sweepTime, TimeCurrent());
        
        if(age > 50)
        {
            for(int j = i; j < m_sweepCount - 1; j++)
            {
                m_sweeps[j] = m_sweeps[j + 1];
            }
            m_sweepCount--;
        }
    }
    
    ArrayResize(m_sweeps, m_sweepCount);
}

//+------------------------------------------------------------------+
//| Get Sweep At Index                                               |
//+------------------------------------------------------------------+
bool CSMCLiquiditySweep::GetSweepAt(int index, SLiquiditySweep &sweep)
{
    if(index < 0 || index >= m_sweepCount) return false;
    sweep = m_sweeps[index];
    return true;
}

//+------------------------------------------------------------------+
//| Get Latest Bullish Sweep                                         |
//+------------------------------------------------------------------+
bool CSMCLiquiditySweep::GetLatestBullishSweep(SLiquiditySweep &sweep)
{
    datetime latestTime = 0;
    int latestIndex = -1;
    
    for(int i = 0; i < m_sweepCount; i++)
    {
        if(m_sweeps[i].isBullish && m_sweeps[i].sweepTime > latestTime)
        {
            latestTime = m_sweeps[i].sweepTime;
            latestIndex = i;
        }
    }
    
    if(latestIndex >= 0)
    {
        sweep = m_sweeps[latestIndex];
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Get Latest Bearish Sweep                                         |
//+------------------------------------------------------------------+
bool CSMCLiquiditySweep::GetLatestBearishSweep(SLiquiditySweep &sweep)
{
    datetime latestTime = 0;
    int latestIndex = -1;
    
    for(int i = 0; i < m_sweepCount; i++)
    {
        if(!m_sweeps[i].isBullish && m_sweeps[i].sweepTime > latestTime)
        {
            latestTime = m_sweeps[i].sweepTime;
            latestIndex = i;
        }
    }
    
    if(latestIndex >= 0)
    {
        sweep = m_sweeps[latestIndex];
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Has Recent Bullish Sweep                                         |
//+------------------------------------------------------------------+
bool CSMCLiquiditySweep::HasRecentBullishSweep(int barsAgo)
{
    datetime cutoff = iTime(m_symbol, m_timeframe, barsAgo);
    
    for(int i = 0; i < m_sweepCount; i++)
    {
        if(m_sweeps[i].isBullish && m_sweeps[i].sweepTime >= cutoff)
            return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Has Recent Bearish Sweep                                         |
//+------------------------------------------------------------------+
bool CSMCLiquiditySweep::HasRecentBearishSweep(int barsAgo)
{
    datetime cutoff = iTime(m_symbol, m_timeframe, barsAgo);
    
    for(int i = 0; i < m_sweepCount; i++)
    {
        if(!m_sweeps[i].isBullish && m_sweeps[i].sweepTime >= cutoff)
            return true;
    }
    
    return false;
}

#endif // __SMC_LIQUIDITY_SWEEP_MQH__
