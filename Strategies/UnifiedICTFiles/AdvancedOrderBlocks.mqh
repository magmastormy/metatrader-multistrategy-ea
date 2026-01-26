//+------------------------------------------------------------------+
//| AdvancedOrderBlocks.mqh                                          |
//| Source, Continuation, and Breaker Block Detection                |
//| For Unified ICT/SMC Strategy                                     |
//| Copyright 2025, Multi-Strategy EA                                |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Multi-Strategy EA"
#property version   "1.00"
#property strict

#ifndef __UICT_ADVANCED_ORDER_BLOCKS_MQH__
#define __UICT_ADVANCED_ORDER_BLOCKS_MQH__

//+------------------------------------------------------------------+
//| Order Block Type Enum                                            |
//+------------------------------------------------------------------+
enum ENUM_ORDER_BLOCK_TYPE
{
    OB_NONE = 0,
    OB_SOURCE_BULLISH,
    OB_SOURCE_BEARISH,
    OB_CONTINUATION_BULL,
    OB_CONTINUATION_BEAR,
    OB_BREAKER_BULL,
    OB_BREAKER_BEAR
};

//+------------------------------------------------------------------+
//| Order Block Structure                                            |
//+------------------------------------------------------------------+
struct SAdvancedOrderBlock
{
    ENUM_ORDER_BLOCK_TYPE type;
    datetime time;
    double top;
    double bottom;
    double open;
    double close;
    double midpoint;
    
    bool isValidated;
    bool isMitigated;
    bool isTested;
    int testCount;
    
    double bodySize;
    double range;
    double bodyPercent;
    double strength;
    
    ENUM_TIMEFRAMES timeframe;
    bool atSupportResistance;
    bool hasImbalance;
    
    SAdvancedOrderBlock() : type(OB_NONE), time(0), top(0), bottom(0), open(0), close(0),
                           midpoint(0), isValidated(false), isMitigated(false), isTested(false),
                           testCount(0), bodySize(0), range(0), bodyPercent(0), strength(0.5),
                           timeframe(PERIOD_CURRENT), atSupportResistance(false), hasImbalance(false) {}
};

//+------------------------------------------------------------------+
//| Advanced Order Block Detector Class                              |
//+------------------------------------------------------------------+
class CAdvancedOrderBlockDetector
{
private:
    string              m_symbol;
    ENUM_TIMEFRAMES     m_timeframe;
    
    SAdvancedOrderBlock m_orderBlocks[];
    int                 m_obCount;
    int                 m_maxOBs;
    
    // Internal methods
    bool                IsNearSupportLevel(double price);
    bool                IsNearResistanceLevel(double price);
    int                 FindMostRecentSwingHigh(int lookback = 50);
    int                 FindMostRecentSwingLow(int lookback = 50);
    double              FindOldLow(int startBar, int endBar);
    double              FindOldHigh(int startBar, int endBar);
    
public:
                        CAdvancedOrderBlockDetector();
                       ~CAdvancedOrderBlockDetector();
    
    bool                Initialize(const string symbol, ENUM_TIMEFRAMES timeframe);
    void                Update();
    void                ScanForOrderBlocks(int lookback = 50);
    
    // Source OB Detection
    bool                DetectBullishSourceOB(SAdvancedOrderBlock &ob);
    bool                DetectBearishSourceOB(SAdvancedOrderBlock &ob);
    
    // Continuation OB Detection
    bool                DetectBullishOB(SAdvancedOrderBlock &ob);
    bool                DetectBearishOB(SAdvancedOrderBlock &ob);
    
    // Breaker Block Detection
    bool                DetectBullishBreakerBlock(SAdvancedOrderBlock &ob);
    bool                DetectBearishBreakerBlock(SAdvancedOrderBlock &ob);
    
    // Validation
    bool                ValidateOrderBlock(SAdvancedOrderBlock &ob);
    bool                CheckMitigation(SAdvancedOrderBlock &ob);
    
    // Getters
    int                 GetOBCount() const { return m_obCount; }
    bool                GetOrderBlock(int index, SAdvancedOrderBlock &ob);
    int                 FindActiveOBAtPrice(double price, double tolerance);
    int                 FindBestBullishOB();
    int                 FindBestBearishOB();
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CAdvancedOrderBlockDetector::CAdvancedOrderBlockDetector() :
    m_symbol(""),
    m_timeframe(PERIOD_CURRENT),
    m_obCount(0),
    m_maxOBs(100)  // Expanded from 20 for historical memory
{
    ArrayResize(m_orderBlocks, 0);
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CAdvancedOrderBlockDetector::~CAdvancedOrderBlockDetector()
{
    ArrayFree(m_orderBlocks);
}

//+------------------------------------------------------------------+
//| Initialize                                                       |
//+------------------------------------------------------------------+
bool CAdvancedOrderBlockDetector::Initialize(const string symbol, ENUM_TIMEFRAMES timeframe)
{
    m_symbol = symbol;
    m_timeframe = timeframe;
    m_obCount = 0;
    
    return true;
}

//+------------------------------------------------------------------+
//| Update                                                           |
//+------------------------------------------------------------------+
void CAdvancedOrderBlockDetector::Update()
{
    ScanForOrderBlocks(500);  // Expanded from 50 for historical memory
    
    // Update mitigation status
    for(int i = 0; i < m_obCount; i++)
    {
        CheckMitigation(m_orderBlocks[i]);
    }
}

//+------------------------------------------------------------------+
//| Scan For Order Blocks                                            |
//+------------------------------------------------------------------+
void CAdvancedOrderBlockDetector::ScanForOrderBlocks(int lookback)
{
    m_obCount = 0;
    ArrayResize(m_orderBlocks, 0);
    
    // Detect Source OBs
    SAdvancedOrderBlock bullSOB;
    if(DetectBullishSourceOB(bullSOB))
    {
        ArrayResize(m_orderBlocks, m_obCount + 1);
        m_orderBlocks[m_obCount] = bullSOB;
        m_obCount++;
    }
    
    SAdvancedOrderBlock bearSOB;
    if(DetectBearishSourceOB(bearSOB))
    {
        ArrayResize(m_orderBlocks, m_obCount + 1);
        m_orderBlocks[m_obCount] = bearSOB;
        m_obCount++;
    }
    
    // Detect Continuation OBs
    SAdvancedOrderBlock bullOB;
    if(DetectBullishOB(bullOB))
    {
        ArrayResize(m_orderBlocks, m_obCount + 1);
        m_orderBlocks[m_obCount] = bullOB;
        m_obCount++;
    }
    
    SAdvancedOrderBlock bearOB;
    if(DetectBearishOB(bearOB))
    {
        ArrayResize(m_orderBlocks, m_obCount + 1);
        m_orderBlocks[m_obCount] = bearOB;
        m_obCount++;
    }
    
    // Detect Breaker Blocks
    SAdvancedOrderBlock bullBreaker;
    if(DetectBullishBreakerBlock(bullBreaker))
    {
        ArrayResize(m_orderBlocks, m_obCount + 1);
        m_orderBlocks[m_obCount] = bullBreaker;
        m_obCount++;
    }
    
    SAdvancedOrderBlock bearBreaker;
    if(DetectBearishBreakerBlock(bearBreaker))
    {
        ArrayResize(m_orderBlocks, m_obCount + 1);
        m_orderBlocks[m_obCount] = bearBreaker;
        m_obCount++;
    }
}

//+------------------------------------------------------------------+
//| Detect Bullish Source OB                                         |
//+------------------------------------------------------------------+
bool CAdvancedOrderBlockDetector::DetectBullishSourceOB(SAdvancedOrderBlock &ob)
{
    int lookback = 50;
    int lowestBar = -1;
    double lowestPrice = DBL_MAX;
    
    for(int i = 5; i < lookback; i++)
    {
        double low = iLow(m_symbol, m_timeframe, i);
        if(low < lowestPrice)
        {
            lowestPrice = low;
            lowestBar = i;
        }
    }
    
    if(lowestBar == -1) return false;
    
    double open = iOpen(m_symbol, m_timeframe, lowestBar);
    double close = iClose(m_symbol, m_timeframe, lowestBar);
    
    // Must be bearish candle
    if(close >= open) return false;
    
    // Find candle with most range near the low
    int bestCandle = lowestBar;
    double bestRange = 0;
    
    for(int i = lowestBar - 2; i <= lowestBar + 2; i++)
    {
        if(i < 0) continue;
        
        double candleOpen = iOpen(m_symbol, m_timeframe, i);
        double candleClose = iClose(m_symbol, m_timeframe, i);
        
        if(candleClose >= candleOpen) continue;
        
        double bodyRange = candleOpen - candleClose;
        if(bodyRange > bestRange)
        {
            bestRange = bodyRange;
            bestCandle = i;
        }
    }
    
    double candleLow = iLow(m_symbol, m_timeframe, bestCandle);
    if(!IsNearSupportLevel(candleLow))
        return false;
    
    ob.type = OB_SOURCE_BULLISH;
    ob.time = iTime(m_symbol, m_timeframe, bestCandle);
    ob.top = iHigh(m_symbol, m_timeframe, bestCandle);
    ob.bottom = iLow(m_symbol, m_timeframe, bestCandle);
    ob.open = iOpen(m_symbol, m_timeframe, bestCandle);
    ob.close = iClose(m_symbol, m_timeframe, bestCandle);
    ob.midpoint = (ob.top + ob.bottom) / 2.0;
    ob.bodySize = MathAbs(ob.open - ob.close);
    ob.range = ob.top - ob.bottom;
    ob.bodyPercent = (ob.range > 0) ? ob.bodySize / ob.range : 0;
    ob.timeframe = m_timeframe;
    ob.strength = 0.85;
    ob.atSupportResistance = true;
    
    return true;
}

//+------------------------------------------------------------------+
//| Detect Bearish Source OB                                         |
//+------------------------------------------------------------------+
bool CAdvancedOrderBlockDetector::DetectBearishSourceOB(SAdvancedOrderBlock &ob)
{
    int lookback = 50;
    int highestBar = -1;
    double highestPrice = 0;
    
    for(int i = 5; i < lookback; i++)
    {
        double high = iHigh(m_symbol, m_timeframe, i);
        if(high > highestPrice)
        {
            highestPrice = high;
            highestBar = i;
        }
    }
    
    if(highestBar == -1) return false;
    
    double open = iOpen(m_symbol, m_timeframe, highestBar);
    double close = iClose(m_symbol, m_timeframe, highestBar);
    
    // Must be bullish candle
    if(close <= open) return false;
    
    int bestCandle = highestBar;
    double bestRange = 0;
    
    for(int i = highestBar - 2; i <= highestBar + 2; i++)
    {
        if(i < 0) continue;
        
        double candleOpen = iOpen(m_symbol, m_timeframe, i);
        double candleClose = iClose(m_symbol, m_timeframe, i);
        
        if(candleClose <= candleOpen) continue;
        
        double bodyRange = candleClose - candleOpen;
        if(bodyRange > bestRange)
        {
            bestRange = bodyRange;
            bestCandle = i;
        }
    }
    
    double candleHigh = iHigh(m_symbol, m_timeframe, bestCandle);
    if(!IsNearResistanceLevel(candleHigh))
        return false;
    
    ob.type = OB_SOURCE_BEARISH;
    ob.time = iTime(m_symbol, m_timeframe, bestCandle);
    ob.top = iHigh(m_symbol, m_timeframe, bestCandle);
    ob.bottom = iLow(m_symbol, m_timeframe, bestCandle);
    ob.open = iOpen(m_symbol, m_timeframe, bestCandle);
    ob.close = iClose(m_symbol, m_timeframe, bestCandle);
    ob.midpoint = (ob.top + ob.bottom) / 2.0;
    ob.bodySize = MathAbs(ob.open - ob.close);
    ob.range = ob.top - ob.bottom;
    ob.bodyPercent = (ob.range > 0) ? ob.bodySize / ob.range : 0;
    ob.timeframe = m_timeframe;
    ob.strength = 0.85;
    ob.atSupportResistance = true;
    
    return true;
}

//+------------------------------------------------------------------+
//| Detect Bullish Continuation OB                                   |
//+------------------------------------------------------------------+
bool CAdvancedOrderBlockDetector::DetectBullishOB(SAdvancedOrderBlock &ob)
{
    int swingHighBar = FindMostRecentSwingHigh();
    if(swingHighBar == -1) return false;
    
    int bestCandle = -1;
    double bestBody = 0;
    
    for(int i = swingHighBar - 5; i <= swingHighBar + 5; i++)
    {
        if(i < 1) continue;
        
        double open = iOpen(m_symbol, m_timeframe, i);
        double close = iClose(m_symbol, m_timeframe, i);
        
        if(close >= open) continue; // Must be bearish
        
        double body = open - close;
        if(body > bestBody)
        {
            bestBody = body;
            bestCandle = i;
        }
    }
    
    if(bestCandle == -1) return false;
    
    // Verify upward movement after OB
    bool hasUpwardMove = false;
    double obTop = iHigh(m_symbol, m_timeframe, bestCandle);
    
    for(int i = bestCandle - 1; i >= 0; i--)
    {
        double close = iClose(m_symbol, m_timeframe, i);
        if(close > obTop)
        {
            hasUpwardMove = true;
            break;
        }
    }
    
    if(!hasUpwardMove) return false;
    
    ob.type = OB_CONTINUATION_BULL;
    ob.time = iTime(m_symbol, m_timeframe, bestCandle);
    ob.top = iHigh(m_symbol, m_timeframe, bestCandle);
    ob.bottom = iLow(m_symbol, m_timeframe, bestCandle);
    ob.open = iOpen(m_symbol, m_timeframe, bestCandle);
    ob.close = iClose(m_symbol, m_timeframe, bestCandle);
    ob.midpoint = (ob.top + ob.bottom) / 2.0;
    ob.strength = 0.70;
    ob.timeframe = m_timeframe;
    
    return true;
}

//+------------------------------------------------------------------+
//| Detect Bearish Continuation OB                                   |
//+------------------------------------------------------------------+
bool CAdvancedOrderBlockDetector::DetectBearishOB(SAdvancedOrderBlock &ob)
{
    int swingLowBar = FindMostRecentSwingLow();
    if(swingLowBar == -1) return false;
    
    int bestCandle = -1;
    double bestBody = 0;
    
    for(int i = swingLowBar - 5; i <= swingLowBar + 5; i++)
    {
        if(i < 1) continue;
        
        double open = iOpen(m_symbol, m_timeframe, i);
        double close = iClose(m_symbol, m_timeframe, i);
        
        if(close <= open) continue; // Must be bullish
        
        double body = close - open;
        if(body > bestBody)
        {
            bestBody = body;
            bestCandle = i;
        }
    }
    
    if(bestCandle == -1) return false;
    
    bool hasDownwardMove = false;
    double obBottom = iLow(m_symbol, m_timeframe, bestCandle);
    
    for(int i = bestCandle - 1; i >= 0; i--)
    {
        double close = iClose(m_symbol, m_timeframe, i);
        if(close < obBottom)
        {
            hasDownwardMove = true;
            break;
        }
    }
    
    if(!hasDownwardMove) return false;
    
    ob.type = OB_CONTINUATION_BEAR;
    ob.time = iTime(m_symbol, m_timeframe, bestCandle);
    ob.top = iHigh(m_symbol, m_timeframe, bestCandle);
    ob.bottom = iLow(m_symbol, m_timeframe, bestCandle);
    ob.open = iOpen(m_symbol, m_timeframe, bestCandle);
    ob.close = iClose(m_symbol, m_timeframe, bestCandle);
    ob.midpoint = (ob.top + ob.bottom) / 2.0;
    ob.strength = 0.70;
    ob.timeframe = m_timeframe;
    
    return true;
}

//+------------------------------------------------------------------+
//| Detect Bullish Breaker Block                                     |
//+------------------------------------------------------------------+
bool CAdvancedOrderBlockDetector::DetectBullishBreakerBlock(SAdvancedOrderBlock &ob)
{
    int swingHighBar = FindMostRecentSwingHigh();
    if(swingHighBar == -1) return false;
    
    double oldLow = FindOldLow(swingHighBar + 1, swingHighBar + 50);
    if(oldLow == 0) return false;
    
    bool oldLowBroken = false;
    for(int i = swingHighBar - 1; i >= 0; i--)
    {
        double close = iClose(m_symbol, m_timeframe, i);
        if(close < oldLow)
        {
            oldLowBroken = true;
            break;
        }
    }
    
    if(!oldLowBroken) return false;
    
    int breakerCandle = -1;
    double bestBody = 0;
    
    for(int i = swingHighBar - 3; i <= swingHighBar + 3; i++)
    {
        if(i < 0) continue;
        
        double open = iOpen(m_symbol, m_timeframe, i);
        double close = iClose(m_symbol, m_timeframe, i);
        
        if(close <= open) continue; // Must be bullish
        
        double body = close - open;
        if(body > bestBody)
        {
            bestBody = body;
            breakerCandle = i;
        }
    }
    
    if(breakerCandle == -1) return false;
    
    ob.type = OB_BREAKER_BULL;
    ob.time = iTime(m_symbol, m_timeframe, breakerCandle);
    ob.top = iHigh(m_symbol, m_timeframe, breakerCandle);
    ob.bottom = iLow(m_symbol, m_timeframe, breakerCandle);
    ob.midpoint = (ob.top + ob.bottom) / 2.0;
    ob.strength = 0.80;
    ob.timeframe = m_timeframe;
    
    return true;
}

//+------------------------------------------------------------------+
//| Detect Bearish Breaker Block                                     |
//+------------------------------------------------------------------+
bool CAdvancedOrderBlockDetector::DetectBearishBreakerBlock(SAdvancedOrderBlock &ob)
{
    int swingLowBar = FindMostRecentSwingLow();
    if(swingLowBar == -1) return false;
    
    double oldHigh = FindOldHigh(swingLowBar + 1, swingLowBar + 50);
    if(oldHigh == 0) return false;
    
    bool oldHighBroken = false;
    for(int i = swingLowBar - 1; i >= 0; i--)
    {
        double close = iClose(m_symbol, m_timeframe, i);
        if(close > oldHigh)
        {
            oldHighBroken = true;
            break;
        }
    }
    
    if(!oldHighBroken) return false;
    
    int breakerCandle = -1;
    double bestBody = 0;
    
    for(int i = swingLowBar - 3; i <= swingLowBar + 3; i++)
    {
        if(i < 0) continue;
        
        double open = iOpen(m_symbol, m_timeframe, i);
        double close = iClose(m_symbol, m_timeframe, i);
        
        if(close >= open) continue; // Must be bearish
        
        double body = open - close;
        if(body > bestBody)
        {
            bestBody = body;
            breakerCandle = i;
        }
    }
    
    if(breakerCandle == -1) return false;
    
    ob.type = OB_BREAKER_BEAR;
    ob.time = iTime(m_symbol, m_timeframe, breakerCandle);
    ob.top = iHigh(m_symbol, m_timeframe, breakerCandle);
    ob.bottom = iLow(m_symbol, m_timeframe, breakerCandle);
    ob.midpoint = (ob.top + ob.bottom) / 2.0;
    ob.strength = 0.80;
    ob.timeframe = m_timeframe;
    
    return true;
}

//+------------------------------------------------------------------+
//| Validate Order Block                                             |
//+------------------------------------------------------------------+
bool CAdvancedOrderBlockDetector::ValidateOrderBlock(SAdvancedOrderBlock &ob)
{
    if(ob.isValidated) return true;
    
    for(int i = 0; i < 50; i++)
    {
        datetime barTime = iTime(m_symbol, m_timeframe, i);
        if(barTime <= ob.time) break;
        
        double close = iClose(m_symbol, m_timeframe, i);
        
        if(ob.type == OB_SOURCE_BULLISH || ob.type == OB_CONTINUATION_BULL || ob.type == OB_BREAKER_BULL)
        {
            if(close > ob.top)
            {
                ob.isValidated = true;
                return true;
            }
        }
        else
        {
            if(close < ob.bottom)
            {
                ob.isValidated = true;
                return true;
            }
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Check Mitigation                                                 |
//+------------------------------------------------------------------+
bool CAdvancedOrderBlockDetector::CheckMitigation(SAdvancedOrderBlock &ob)
{
    if(ob.isMitigated) return true;
    
    double lastPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);
    
    // 50% fill = mitigated
    if(ob.type == OB_SOURCE_BULLISH || ob.type == OB_CONTINUATION_BULL || ob.type == OB_BREAKER_BULL)
    {
        if(lastPrice < ob.midpoint)
        {
            ob.isMitigated = true;
            return true;
        }
    }
    else
    {
        if(lastPrice > ob.midpoint)
        {
            ob.isMitigated = true;
            return true;
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Find Most Recent Swing High                                      |
//+------------------------------------------------------------------+
int CAdvancedOrderBlockDetector::FindMostRecentSwingHigh(int lookback)
{
    for(int i = 3; i < lookback - 3; i++)
    {
        double high = iHigh(m_symbol, m_timeframe, i);
        
        if(high > iHigh(m_symbol, m_timeframe, i-1) &&
           high > iHigh(m_symbol, m_timeframe, i+1) &&
           high > iHigh(m_symbol, m_timeframe, i-2) &&
           high > iHigh(m_symbol, m_timeframe, i+2))
        {
            return i;
        }
    }
    return -1;
}

//+------------------------------------------------------------------+
//| Find Most Recent Swing Low                                       |
//+------------------------------------------------------------------+
int CAdvancedOrderBlockDetector::FindMostRecentSwingLow(int lookback)
{
    for(int i = 3; i < lookback - 3; i++)
    {
        double low = iLow(m_symbol, m_timeframe, i);
        
        if(low < iLow(m_symbol, m_timeframe, i-1) &&
           low < iLow(m_symbol, m_timeframe, i+1) &&
           low < iLow(m_symbol, m_timeframe, i-2) &&
           low < iLow(m_symbol, m_timeframe, i+2))
        {
            return i;
        }
    }
    return -1;
}

//+------------------------------------------------------------------+
//| Find Old Low                                                     |
//+------------------------------------------------------------------+
double CAdvancedOrderBlockDetector::FindOldLow(int startBar, int endBar)
{
    double lowestLow = DBL_MAX;
    
    for(int i = startBar; i < endBar; i++)
    {
        double low = iLow(m_symbol, m_timeframe, i);
        if(low < lowestLow)
            lowestLow = low;
    }
    
    return (lowestLow == DBL_MAX) ? 0 : lowestLow;
}

//+------------------------------------------------------------------+
//| Find Old High                                                    |
//+------------------------------------------------------------------+
double CAdvancedOrderBlockDetector::FindOldHigh(int startBar, int endBar)
{
    double highestHigh = 0;
    
    for(int i = startBar; i < endBar; i++)
    {
        double high = iHigh(m_symbol, m_timeframe, i);
        if(high > highestHigh)
            highestHigh = high;
    }
    
    return highestHigh;
}

//+------------------------------------------------------------------+
//| Is Near Support Level                                            |
//+------------------------------------------------------------------+
bool CAdvancedOrderBlockDetector::IsNearSupportLevel(double price)
{
    double tolerance = 20 * SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    
    double yesterdayLow = iLow(m_symbol, PERIOD_D1, 1);
    if(MathAbs(price - yesterdayLow) < tolerance) return true;
    
    double lastWeekLow = iLow(m_symbol, PERIOD_W1, 1);
    if(MathAbs(price - lastWeekLow) < tolerance) return true;
    
    return false;
}

//+------------------------------------------------------------------+
//| Is Near Resistance Level                                         |
//+------------------------------------------------------------------+
bool CAdvancedOrderBlockDetector::IsNearResistanceLevel(double price)
{
    double tolerance = 20 * SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    
    double yesterdayHigh = iHigh(m_symbol, PERIOD_D1, 1);
    if(MathAbs(price - yesterdayHigh) < tolerance) return true;
    
    double lastWeekHigh = iHigh(m_symbol, PERIOD_W1, 1);
    if(MathAbs(price - lastWeekHigh) < tolerance) return true;
    
    return false;
}

//+------------------------------------------------------------------+
//| Get Order Block                                                  |
//+------------------------------------------------------------------+
bool CAdvancedOrderBlockDetector::GetOrderBlock(int index, SAdvancedOrderBlock &ob)
{
    if(index < 0 || index >= m_obCount) return false;
    ob = m_orderBlocks[index];
    return true;
}

//+------------------------------------------------------------------+
//| Find Active OB at Price                                          |
//+------------------------------------------------------------------+
int CAdvancedOrderBlockDetector::FindActiveOBAtPrice(double price, double tolerance)
{
    for(int i = 0; i < m_obCount; i++)
    {
        if(m_orderBlocks[i].isMitigated) continue;
        
        if(price >= m_orderBlocks[i].bottom - tolerance &&
           price <= m_orderBlocks[i].top + tolerance)
        {
            return i;
        }
    }
    return -1;
}

//+------------------------------------------------------------------+
//| Find Best Bullish OB                                             |
//+------------------------------------------------------------------+
int CAdvancedOrderBlockDetector::FindBestBullishOB()
{
    int bestIndex = -1;
    double bestStrength = 0;
    
    for(int i = 0; i < m_obCount; i++)
    {
        if(m_orderBlocks[i].isMitigated) continue;
        
        if(m_orderBlocks[i].type == OB_SOURCE_BULLISH ||
           m_orderBlocks[i].type == OB_CONTINUATION_BULL ||
           m_orderBlocks[i].type == OB_BREAKER_BULL)
        {
            if(m_orderBlocks[i].strength > bestStrength)
            {
                bestStrength = m_orderBlocks[i].strength;
                bestIndex = i;
            }
        }
    }
    
    return bestIndex;
}

//+------------------------------------------------------------------+
//| Find Best Bearish OB                                             |
//+------------------------------------------------------------------+
int CAdvancedOrderBlockDetector::FindBestBearishOB()
{
    int bestIndex = -1;
    double bestStrength = 0;
    
    for(int i = 0; i < m_obCount; i++)
    {
        if(m_orderBlocks[i].isMitigated) continue;
        
        if(m_orderBlocks[i].type == OB_SOURCE_BEARISH ||
           m_orderBlocks[i].type == OB_CONTINUATION_BEAR ||
           m_orderBlocks[i].type == OB_BREAKER_BEAR)
        {
            if(m_orderBlocks[i].strength > bestStrength)
            {
                bestStrength = m_orderBlocks[i].strength;
                bestIndex = i;
            }
        }
    }
    
    return bestIndex;
}

#endif // __UICT_ADVANCED_ORDER_BLOCKS_MQH__
