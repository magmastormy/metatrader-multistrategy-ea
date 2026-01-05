//+------------------------------------------------------------------+
//| OrderBlocks.mqh                                                  |
//| Corrected Order Block Detection for SMC Strategy                 |
//| OB = Last OPPOSITE candle before displacement                    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Multi-Strategy EA"
#property version   "2.00"
#property strict

#ifndef __SMC_ORDER_BLOCKS_MQH__
#define __SMC_ORDER_BLOCKS_MQH__

#include <Arrays/ArrayObj.mqh>

//+------------------------------------------------------------------+
//| Order Block Structure                                            |
//+------------------------------------------------------------------+
struct SOrderBlock
{
    double      top;
    double      bottom;
    datetime    time;
    int         barIndex;
    bool        isBullish;
    bool        isBreaker;       // Previously broken OB acting as opposite
    int         touches;         // Untested = strongest (0 touches)
    double      score;
    bool        mitigated;
    
    // ICT Components
    bool        hasImbalance;    // FVG inside OB
    bool        atPremium;       // Above 50% of range (for sells)
    bool        atDiscount;      // Below 50% of range (for buys)
    double      displacementSize; // Size of displacement candle
    
    // Identification
    string      id;
    
    SOrderBlock() : top(0), bottom(0), time(0), barIndex(0), isBullish(false),
                    isBreaker(false), touches(0), score(0), mitigated(false),
                    hasImbalance(false), atPremium(false), atDiscount(false),
                    displacementSize(0), id("") {}
};

//+------------------------------------------------------------------+
//| Order Block Detection Class                                      |
//+------------------------------------------------------------------+
class CSMCOrderBlocks
{
private:
    string              m_symbol;
    ENUM_TIMEFRAMES     m_timeframe;
    
    // Order blocks storage
    SOrderBlock         m_orderBlocks[];
    int                 m_maxBlocks;
    int                 m_blockCount;
    
    // Configuration
    double              m_momentumFactor;    // Displacement = X * avg body
    int                 m_lookbackBars;      // Bars to calculate avg body
    int                 m_maxAge;            // Max age in bars before removal
    double              m_minScore;          // Minimum score threshold
    
    // Internal methods
    double              GetAvgBodySize(int bars);
    bool                IsDisplacementCandle(int barIndex, double avgBody);
    int                 FindLastOppositeCandle(int displacementIndex, bool isBullishDisplacement);
    double              ScoreOrderBlock(const SOrderBlock &ob);
    bool                HasFVGNearby(int barIndex, bool isBullish);
    
public:
                        CSMCOrderBlocks();
                       ~CSMCOrderBlocks();
    
    // Initialization
    bool                Initialize(const string symbol, ENUM_TIMEFRAMES timeframe,
                                  double momentumFactor = 2.0, int lookback = 20);
    
    // Detection
    void                ScanForOrderBlocks(int scanBars = 50);
    void                UpdateOrderBlocks();
    void                RemoveOldBlocks();
    
    // Getters
    int                 GetOrderBlockCount() const { return m_blockCount; }
    bool                GetOrderBlockAt(int index, SOrderBlock &ob);
    bool                GetBestBullishOB(SOrderBlock &ob);
    bool                GetBestBearishOB(SOrderBlock &ob);
    
    // Zone interaction
    bool                IsPriceAtOrderBlock(double price, SOrderBlock &activeOB);
    bool                IsPriceInBullishOB(double price);
    bool                IsPriceInBearishOB(double price);
    void                MarkAsMitigated(int index);
    void                IncrementTouches(int index);
    
    // Configuration
    void                SetMomentumFactor(double factor) { m_momentumFactor = factor; }
    void                SetMaxAge(int age) { m_maxAge = age; }
    void                SetMinScore(double score) { m_minScore = score; }
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CSMCOrderBlocks::CSMCOrderBlocks() :
    m_symbol(""),
    m_timeframe(PERIOD_CURRENT),
    m_maxBlocks(30),
    m_blockCount(0),
    m_momentumFactor(2.0),
    m_lookbackBars(20),
    m_maxAge(500),
    m_minScore(40.0)
{
    ArrayResize(m_orderBlocks, 0);
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CSMCOrderBlocks::~CSMCOrderBlocks()
{
    ArrayFree(m_orderBlocks);
}

//+------------------------------------------------------------------+
//| Initialize                                                       |
//+------------------------------------------------------------------+
bool CSMCOrderBlocks::Initialize(const string symbol, ENUM_TIMEFRAMES timeframe,
                                 double momentumFactor, int lookback)
{
    m_symbol = symbol;
    m_timeframe = timeframe;
    m_momentumFactor = momentumFactor;
    m_lookbackBars = lookback;
    
    ArrayResize(m_orderBlocks, 0);
    m_blockCount = 0;
    
    return true;
}

//+------------------------------------------------------------------+
//| Get Average Body Size                                            |
//+------------------------------------------------------------------+
double CSMCOrderBlocks::GetAvgBodySize(int bars)
{
    double sum = 0;
    for(int i = 1; i <= bars; i++)
    {
        sum += MathAbs(iOpen(m_symbol, m_timeframe, i) - iClose(m_symbol, m_timeframe, i));
    }
    return (bars > 0) ? sum / bars : 0;
}

//+------------------------------------------------------------------+
//| Is Displacement Candle                                           |
//+------------------------------------------------------------------+
bool CSMCOrderBlocks::IsDisplacementCandle(int barIndex, double avgBody)
{
    double body = MathAbs(iOpen(m_symbol, m_timeframe, barIndex) - 
                         iClose(m_symbol, m_timeframe, barIndex));
    return (body >= m_momentumFactor * avgBody);
}

//+------------------------------------------------------------------+
//| Find Last Opposite Candle (CORRECTED OB DETECTION)               |
//| For Bullish Displacement: Find last RED candle before it         |
//| For Bearish Displacement: Find last GREEN candle before it       |
//+------------------------------------------------------------------+
int CSMCOrderBlocks::FindLastOppositeCandle(int displacementIndex, bool isBullishDisplacement)
{
    // Look back from displacement to find opposite color candle
    for(int i = displacementIndex + 1; i < displacementIndex + 10; i++)
    {
        double open = iOpen(m_symbol, m_timeframe, i);
        double close = iClose(m_symbol, m_timeframe, i);
        
        bool isBullishCandle = (close > open);
        bool isBearishCandle = (close < open);
        
        // For bullish displacement, find bearish (red) candle
        if(isBullishDisplacement && isBearishCandle)
            return i;
        
        // For bearish displacement, find bullish (green) candle
        if(!isBullishDisplacement && isBullishCandle)
            return i;
    }
    
    // Fallback: use candle immediately before displacement
    return displacementIndex + 1;
}

//+------------------------------------------------------------------+
//| Check for FVG Near Order Block                                   |
//+------------------------------------------------------------------+
bool CSMCOrderBlocks::HasFVGNearby(int barIndex, bool isBullish)
{
    // Check 3 candles around the OB for FVG
    for(int i = barIndex - 2; i <= barIndex + 2; i++)
    {
        if(i < 1) continue;
        
        double highA = iHigh(m_symbol, m_timeframe, i + 2);
        double lowA = iLow(m_symbol, m_timeframe, i + 2);
        double highC = iHigh(m_symbol, m_timeframe, i);
        double lowC = iLow(m_symbol, m_timeframe, i);
        
        // Bullish FVG: gap up
        if(isBullish && lowA > highC)
            return true;
        
        // Bearish FVG: gap down
        if(!isBullish && highA < lowC)
            return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Score Order Block                                                |
//+------------------------------------------------------------------+
double CSMCOrderBlocks::ScoreOrderBlock(const SOrderBlock &ob)
{
    double score = 50.0; // Base score
    
    // Untested bonus (first touch is best)
    if(ob.touches == 0)
        score += 25.0;
    else if(ob.touches == 1)
        score += 10.0;
    else
        score -= (ob.touches - 1) * 5.0;
    
    // FVG confluence bonus
    if(ob.hasImbalance)
        score += 15.0;
    
    // Displacement size bonus
    double avgBody = GetAvgBodySize(m_lookbackBars);
    if(avgBody > 0 && ob.displacementSize > avgBody * 3.0)
        score += 10.0;
    else if(avgBody > 0 && ob.displacementSize > avgBody * 2.5)
        score += 5.0;
    
    // Premium/Discount alignment
    if((ob.isBullish && ob.atDiscount) || (!ob.isBullish && ob.atPremium))
        score += 10.0;
    
    // Age penalty
    int age = Bars(m_symbol, m_timeframe, ob.time, TimeCurrent());
    if(age > 200)
        score -= 10.0;
    else if(age > 100)
        score -= 5.0;
    
    return MathMax(0, MathMin(100, score));
}

//+------------------------------------------------------------------+
//| Scan for Order Blocks                                            |
//+------------------------------------------------------------------+
void CSMCOrderBlocks::ScanForOrderBlocks(int scanBars)
{
    int bars = iBars(m_symbol, m_timeframe);
    if(bars < m_lookbackBars + 10) return;
    
    double avgBody = GetAvgBodySize(m_lookbackBars);
    if(avgBody <= 0) return;
    
    // Calculate premium/discount zone
    double rangeHigh = 0, rangeLow = DBL_MAX;
    for(int i = 0; i < MathMin(100, bars); i++)
    {
        rangeHigh = MathMax(rangeHigh, iHigh(m_symbol, m_timeframe, i));
        rangeLow = MathMin(rangeLow, iLow(m_symbol, m_timeframe, i));
    }
    double rangeMid = (rangeHigh + rangeLow) / 2.0;
    
    // Scan for displacement candles
    for(int i = 1; i < scanBars && i < bars - 10; i++)
    {
        if(!IsDisplacementCandle(i, avgBody))
            continue;
        
        double displacementOpen = iOpen(m_symbol, m_timeframe, i);
        double displacementClose = iClose(m_symbol, m_timeframe, i);
        bool isBullishDisplacement = (displacementClose > displacementOpen);
        
        // Find the last opposite candle (THIS IS THE ORDER BLOCK)
        int obIndex = FindLastOppositeCandle(i, isBullishDisplacement);
        
        // Create order block from the opposite candle
        SOrderBlock ob;
        ob.top = iHigh(m_symbol, m_timeframe, obIndex);
        ob.bottom = iLow(m_symbol, m_timeframe, obIndex);
        ob.time = iTime(m_symbol, m_timeframe, obIndex);
        ob.barIndex = obIndex;
        ob.isBullish = isBullishDisplacement; // OB direction matches displacement
        ob.displacementSize = MathAbs(displacementClose - displacementOpen);
        ob.hasImbalance = HasFVGNearby(obIndex, isBullishDisplacement);
        ob.atPremium = ((ob.top + ob.bottom) / 2.0 > rangeMid);
        ob.atDiscount = ((ob.top + ob.bottom) / 2.0 < rangeMid);
        ob.id = StringFormat("OB_%d_%d", (int)ob.time, (int)ob.isBullish);
        
        // Score the order block
        ob.score = ScoreOrderBlock(ob);
        
        // Only add if meets minimum score
        if(ob.score >= m_minScore)
        {
            // Check for duplicates
            bool exists = false;
            for(int j = 0; j < m_blockCount; j++)
            {
                if(m_orderBlocks[j].time == ob.time)
                {
                    exists = true;
                    break;
                }
            }
            
            if(!exists && m_blockCount < m_maxBlocks)
            {
                ArrayResize(m_orderBlocks, m_blockCount + 1);
                m_orderBlocks[m_blockCount++] = ob;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Update Order Blocks                                              |
//+------------------------------------------------------------------+
void CSMCOrderBlocks::UpdateOrderBlocks()
{
    double lastPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);
    
    for(int i = 0; i < m_blockCount; i++)
    {
        // Check for mitigation (price passed through zone)
        if(m_orderBlocks[i].isBullish)
        {
            // Bullish OB mitigated if price closes below
            double close1 = iClose(m_symbol, m_timeframe, 1);
            double close2 = iClose(m_symbol, m_timeframe, 2);
            if(close1 < m_orderBlocks[i].bottom && close2 < m_orderBlocks[i].bottom)
            {
                m_orderBlocks[i].mitigated = true;
            }
        }
        else
        {
            // Bearish OB mitigated if price closes above
            double close1 = iClose(m_symbol, m_timeframe, 1);
            double close2 = iClose(m_symbol, m_timeframe, 2);
            if(close1 > m_orderBlocks[i].top && close2 > m_orderBlocks[i].top)
            {
                m_orderBlocks[i].mitigated = true;
            }
        }
        
        // Re-score
        m_orderBlocks[i].score = ScoreOrderBlock(m_orderBlocks[i]);
    }
}

//+------------------------------------------------------------------+
//| Remove Old Blocks                                                |
//+------------------------------------------------------------------+
void CSMCOrderBlocks::RemoveOldBlocks()
{
    for(int i = m_blockCount - 1; i >= 0; i--)
    {
        int age = Bars(m_symbol, m_timeframe, m_orderBlocks[i].time, TimeCurrent());
        
        if(age > m_maxAge || m_orderBlocks[i].mitigated)
        {
            // Shift array
            for(int j = i; j < m_blockCount - 1; j++)
            {
                m_orderBlocks[j] = m_orderBlocks[j + 1];
            }
            m_blockCount--;
        }
    }
    
    ArrayResize(m_orderBlocks, m_blockCount);
}

//+------------------------------------------------------------------+
//| Get Order Block At Index                                         |
//+------------------------------------------------------------------+
bool CSMCOrderBlocks::GetOrderBlockAt(int index, SOrderBlock &ob)
{
    if(index < 0 || index >= m_blockCount) return false;
    ob = m_orderBlocks[index];
    return true;
}

//+------------------------------------------------------------------+
//| Get Best Bullish OB                                              |
//+------------------------------------------------------------------+
bool CSMCOrderBlocks::GetBestBullishOB(SOrderBlock &ob)
{
    double bestScore = 0;
    int bestIndex = -1;
    
    for(int i = 0; i < m_blockCount; i++)
    {
        if(m_orderBlocks[i].isBullish && !m_orderBlocks[i].mitigated &&
           m_orderBlocks[i].score > bestScore)
        {
            bestScore = m_orderBlocks[i].score;
            bestIndex = i;
        }
    }
    
    if(bestIndex >= 0)
    {
        ob = m_orderBlocks[bestIndex];
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Get Best Bearish OB                                              |
//+------------------------------------------------------------------+
bool CSMCOrderBlocks::GetBestBearishOB(SOrderBlock &ob)
{
    double bestScore = 0;
    int bestIndex = -1;
    
    for(int i = 0; i < m_blockCount; i++)
    {
        if(!m_orderBlocks[i].isBullish && !m_orderBlocks[i].mitigated &&
           m_orderBlocks[i].score > bestScore)
        {
            bestScore = m_orderBlocks[i].score;
            bestIndex = i;
        }
    }
    
    if(bestIndex >= 0)
    {
        ob = m_orderBlocks[bestIndex];
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Is Price At Order Block                                          |
//+------------------------------------------------------------------+
bool CSMCOrderBlocks::IsPriceAtOrderBlock(double price, SOrderBlock &activeOB)
{
    for(int i = 0; i < m_blockCount; i++)
    {
        if(m_orderBlocks[i].mitigated) continue;
        
        if(price >= m_orderBlocks[i].bottom && price <= m_orderBlocks[i].top)
        {
            activeOB = m_orderBlocks[i];
            return true;
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Is Price In Bullish OB                                           |
//+------------------------------------------------------------------+
bool CSMCOrderBlocks::IsPriceInBullishOB(double price)
{
    for(int i = 0; i < m_blockCount; i++)
    {
        if(m_orderBlocks[i].isBullish && !m_orderBlocks[i].mitigated &&
           price >= m_orderBlocks[i].bottom && price <= m_orderBlocks[i].top)
        {
            return true;
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Is Price In Bearish OB                                           |
//+------------------------------------------------------------------+
bool CSMCOrderBlocks::IsPriceInBearishOB(double price)
{
    for(int i = 0; i < m_blockCount; i++)
    {
        if(!m_orderBlocks[i].isBullish && !m_orderBlocks[i].mitigated &&
           price >= m_orderBlocks[i].bottom && price <= m_orderBlocks[i].top)
        {
            return true;
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Mark As Mitigated                                                |
//+------------------------------------------------------------------+
void CSMCOrderBlocks::MarkAsMitigated(int index)
{
    if(index >= 0 && index < m_blockCount)
    {
        m_orderBlocks[index].mitigated = true;
    }
}

//+------------------------------------------------------------------+
//| Increment Touches                                                |
//+------------------------------------------------------------------+
void CSMCOrderBlocks::IncrementTouches(int index)
{
    if(index >= 0 && index < m_blockCount)
    {
        m_orderBlocks[index].touches++;
        m_orderBlocks[index].score = ScoreOrderBlock(m_orderBlocks[index]);
    }
}

#endif // __SMC_ORDER_BLOCKS_MQH__
