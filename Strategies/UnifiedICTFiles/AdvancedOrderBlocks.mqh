//+------------------------------------------------------------------+
//| AdvancedOrderBlocks.mqh                                          |
//| Source, Continuation, and Breaker Block Detection                |
//| For Unified ICT Strategy                                         |
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
    OB_BREAKER_BEAR,
    OB_PROPULSION_BULL,
    OB_PROPULSION_BEAR,
    OB_REJECTION_BULL,
    OB_REJECTION_BEAR,
    OB_VACUUM_BULL,
    OB_VACUUM_BEAR
};

//+------------------------------------------------------------------+
//| Order Block Structure                                            |
//+------------------------------------------------------------------+
struct SAdvancedOrderBlock
{
    // --- EXISTING FIELDS (keep all unchanged) ---
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

    // --- NEW FIELDS (P0-B) ---
    double ce;              // Consequent Encroachment = midpoint (used as entry/TP target, NOT mitigation)
    bool isFresh;           // Has price NOT yet returned to this OB (true = never tested)
    int timesRejected;      // How many times price bounced FROM this OB (more = stronger)
    datetime firstTestedTime;   // When price first entered the OB zone
    double mitigationLevel; // The price level that triggers mitigation (below bottom for bull, above top for bear)
    bool shadowUsedForSL;   // Whether the OB wick/shadow extends the mitigation level

    SAdvancedOrderBlock() : type(OB_NONE), time(0), top(0), bottom(0), open(0), close(0),
                           midpoint(0), isValidated(false), isMitigated(false), isTested(false),
                           testCount(0), bodySize(0), range(0), bodyPercent(0), strength(0.5),
                           timeframe(PERIOD_CURRENT), atSupportResistance(false), hasImbalance(false),
                           ce(0), isFresh(true), timesRejected(0), firstTestedTime(0),
                           mitigationLevel(0), shadowUsedForSL(false) {}
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
    int                 FindImpulseStart(bool bullish, int lookback = 30);  // P1-A helper
    double              GetATRValue(int period = 14);
    long                GetAverageVolume(int startBar, int window);
    bool                IsBullishType(const ENUM_ORDER_BLOCK_TYPE type) const;
    bool                IsBearishType(const ENUM_ORDER_BLOCK_TYPE type) const;
    
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
    bool                DetectBullishPropulsionBlock(SAdvancedOrderBlock &ob);
    bool                DetectBearishPropulsionBlock(SAdvancedOrderBlock &ob);
    bool                DetectBullishRejectionBlock(SAdvancedOrderBlock &ob);
    bool                DetectBearishRejectionBlock(SAdvancedOrderBlock &ob);
    bool                DetectBullishVacuumBlock(SAdvancedOrderBlock &ob);
    bool                DetectBearishVacuumBlock(SAdvancedOrderBlock &ob);
    
    // Validation
    bool                ValidateOrderBlock(SAdvancedOrderBlock &ob);
    bool                CheckMitigation(SAdvancedOrderBlock &ob);
    
    // Getters
    int                 GetOBCount() const { return m_obCount; }
    bool                GetOrderBlock(int index, SAdvancedOrderBlock &ob);
    int                 FindActiveOBAtPrice(double price, double tolerance);
    int                 FindBestBullishOB();
    int                 FindBestBearishOB();
    double              GetFreshness(int obIndex);  // Batch 103: OB freshness decay 0.0-1.0
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

    SAdvancedOrderBlock bullPropulsion;
    if(DetectBullishPropulsionBlock(bullPropulsion))
    {
        ArrayResize(m_orderBlocks, m_obCount + 1);
        m_orderBlocks[m_obCount] = bullPropulsion;
        m_obCount++;
    }

    SAdvancedOrderBlock bearPropulsion;
    if(DetectBearishPropulsionBlock(bearPropulsion))
    {
        ArrayResize(m_orderBlocks, m_obCount + 1);
        m_orderBlocks[m_obCount] = bearPropulsion;
        m_obCount++;
    }

    SAdvancedOrderBlock bullRejection;
    if(DetectBullishRejectionBlock(bullRejection))
    {
        ArrayResize(m_orderBlocks, m_obCount + 1);
        m_orderBlocks[m_obCount] = bullRejection;
        m_obCount++;
    }

    SAdvancedOrderBlock bearRejection;
    if(DetectBearishRejectionBlock(bearRejection))
    {
        ArrayResize(m_orderBlocks, m_obCount + 1);
        m_orderBlocks[m_obCount] = bearRejection;
        m_obCount++;
    }

    SAdvancedOrderBlock bullVacuum;
    if(DetectBullishVacuumBlock(bullVacuum))
    {
        ArrayResize(m_orderBlocks, m_obCount + 1);
        m_orderBlocks[m_obCount] = bullVacuum;
        m_obCount++;
    }

    SAdvancedOrderBlock bearVacuum;
    if(DetectBearishVacuumBlock(bearVacuum))
    {
        ArrayResize(m_orderBlocks, m_obCount + 1);
        m_orderBlocks[m_obCount] = bearVacuum;
        m_obCount++;
    }
}

double CAdvancedOrderBlockDetector::GetATRValue(int period)
{
    int atrHandle = iATR(m_symbol, m_timeframe, period);
    if(atrHandle == INVALID_HANDLE)
        return 0.0;

    double atrBuf[];
    ArraySetAsSeries(atrBuf, true);
    double atr = 0.0;
    if(CopyBuffer(atrHandle, 0, 0, 1, atrBuf) > 0)
        atr = atrBuf[0];
    IndicatorRelease(atrHandle);
    return atr;
}

long CAdvancedOrderBlockDetector::GetAverageVolume(int startBar, int window)
{
    if(window <= 0)
        return 0;

    long volumeSum = 0;
    int samples = 0;
    int totalBars = iBars(m_symbol, m_timeframe);
    for(int i = startBar; i < startBar + window && i < totalBars; i++)
    {
        long volume = iVolume(m_symbol, m_timeframe, i);
        if(volume <= 0)
            continue;

        volumeSum += volume;
        samples++;
    }

    return (samples > 0) ? (volumeSum / samples) : 0;
}

bool CAdvancedOrderBlockDetector::IsBullishType(const ENUM_ORDER_BLOCK_TYPE type) const
{
    return (type == OB_SOURCE_BULLISH ||
            type == OB_CONTINUATION_BULL ||
            type == OB_BREAKER_BULL ||
            type == OB_PROPULSION_BULL ||
            type == OB_REJECTION_BULL ||
            type == OB_VACUUM_BULL);
}

bool CAdvancedOrderBlockDetector::IsBearishType(const ENUM_ORDER_BLOCK_TYPE type) const
{
    return (type == OB_SOURCE_BEARISH ||
            type == OB_CONTINUATION_BEAR ||
            type == OB_BREAKER_BEAR ||
            type == OB_PROPULSION_BEAR ||
            type == OB_REJECTION_BEAR ||
            type == OB_VACUUM_BEAR);
}

//+------------------------------------------------------------------+
//| Find Impulse Start — P1-A Helper                                |
//+------------------------------------------------------------------+
// Returns the starting bar index of the most recent impulsive move in the given direction.
// An impulse is 3+ consecutive bars moving in the same direction with bodies >= 50% of range.
// Returns -1 if no impulse found within lookback.
int CAdvancedOrderBlockDetector::FindImpulseStart(bool bullish, int lookback)
{
    int consecutiveCount = 0;
    int impulseStartBar  = -1;

    for(int i = 1; i < lookback; i++)
    {
        double o = iOpen(m_symbol,  m_timeframe, i);
        double c = iClose(m_symbol, m_timeframe, i);
        double h = iHigh(m_symbol,  m_timeframe, i);
        double l = iLow(m_symbol,   m_timeframe, i);

        double body  = MathAbs(c - o);
        double range = h - l;
        bool strongBody = (range > 0 && body / range >= 0.50);

        bool directionMatch = bullish ? (c > o) : (c < o);

        if(directionMatch && strongBody)
        {
            consecutiveCount++;
            if(consecutiveCount >= 3)
            {
                // Found 3+ consecutive impulse candles
                // The impulse START is at bar i (oldest of the 3)
                impulseStartBar = i;
                break;
            }
        }
        else
        {
            consecutiveCount = 0;
        }
    }

    return impulseStartBar;
}

//+------------------------------------------------------------------+
//| Detect Bullish Source OB — P1-A Rewrite                         |
//+------------------------------------------------------------------+
// Algorithm:
// 1. Find the most recent bullish impulse (3+ strong bullish candles)
// 2. Starting at the bar just BEFORE the impulse began, walk backward
// 3. Find the LAST bearish candle (close < open) before the impulse
// 4. That candle = Source OB (the last selling before institutions flipped bullish)
bool CAdvancedOrderBlockDetector::DetectBullishSourceOB(SAdvancedOrderBlock &ob)
{
    int impulseStartBar = FindImpulseStart(true, 50);
    if(impulseStartBar < 0) return false;

    // Walk forward from impulseStartBar to find the last bearish candle before the impulse.
    int sourceOBBar = -1;

    for(int i = impulseStartBar + 1; i < impulseStartBar + 20; i++)
    {
        if(i >= iBars(m_symbol, m_timeframe)) break;

        double o = iOpen(m_symbol,  m_timeframe, i);
        double c = iClose(m_symbol, m_timeframe, i);

        if(c < o)  // Bearish candle
        {
            sourceOBBar = i;
            // Do NOT break — keep looking for the LAST bearish candle
            // (we want the one closest to the impulse start)
        }
    }

    if(sourceOBBar < 0) return false;

    // Validate: the OB candle should have a meaningful body
    double o = iOpen(m_symbol,  m_timeframe, sourceOBBar);
    double c = iClose(m_symbol, m_timeframe, sourceOBBar);
    double h = iHigh(m_symbol,  m_timeframe, sourceOBBar);
    double l = iLow(m_symbol,   m_timeframe, sourceOBBar);

    double body = MathAbs(o - c);
    double atr  = 0;
    int atrHandle = iATR(m_symbol, m_timeframe, 14);
    if(atrHandle != INVALID_HANDLE)
    {
        double atrBuf[];
        ArraySetAsSeries(atrBuf, true);
        if(CopyBuffer(atrHandle, 0, 0, 1, atrBuf) > 0)
            atr = atrBuf[0];
        IndicatorRelease(atrHandle);
    }

    // Body must be at least 20% of ATR to qualify as a meaningful OB
    if(atr > 0 && body < atr * 0.20) return false;

    ob.type      = OB_SOURCE_BULLISH;
    ob.time      = iTime(m_symbol, m_timeframe, sourceOBBar);
    ob.top       = h;
    ob.bottom    = l;
    ob.open      = o;
    ob.close     = c;
    ob.midpoint  = (h + l) / 2.0;
    ob.ce        = ob.midpoint;
    ob.bodySize  = body;
    ob.range     = h - l;
    ob.bodyPercent = (ob.range > 0) ? body / ob.range : 0;
    ob.timeframe = m_timeframe;
    ob.strength  = 0.85;
    ob.isFresh   = true;
    ob.atSupportResistance = IsNearSupportLevel(l);

    return true;
}

//+------------------------------------------------------------------+
//| Detect Bearish Source OB — P1-A Rewrite                         |
//+------------------------------------------------------------------+
bool CAdvancedOrderBlockDetector::DetectBearishSourceOB(SAdvancedOrderBlock &ob)
{
    int impulseStartBar = FindImpulseStart(false, 50);  // false = bearish impulse
    if(impulseStartBar < 0) return false;

    int sourceOBBar = -1;

    for(int i = impulseStartBar + 1; i < impulseStartBar + 20; i++)
    {
        if(i >= iBars(m_symbol, m_timeframe)) break;

        double o = iOpen(m_symbol,  m_timeframe, i);
        double c = iClose(m_symbol, m_timeframe, i);

        if(c > o)  // Bullish candle — last one before bearish impulse = source OB
        {
            sourceOBBar = i;
        }
    }

    if(sourceOBBar < 0) return false;

    double o = iOpen(m_symbol,  m_timeframe, sourceOBBar);
    double c = iClose(m_symbol, m_timeframe, sourceOBBar);
    double h = iHigh(m_symbol,  m_timeframe, sourceOBBar);
    double l = iLow(m_symbol,   m_timeframe, sourceOBBar);
    double body = MathAbs(o - c);

    double atr = 0;
    int atrHandle = iATR(m_symbol, m_timeframe, 14);
    if(atrHandle != INVALID_HANDLE)
    {
        double atrBuf[];
        ArraySetAsSeries(atrBuf, true);
        if(CopyBuffer(atrHandle, 0, 0, 1, atrBuf) > 0)
            atr = atrBuf[0];
        IndicatorRelease(atrHandle);
    }

    if(atr > 0 && body < atr * 0.20) return false;

    ob.type      = OB_SOURCE_BEARISH;
    ob.time      = iTime(m_symbol, m_timeframe, sourceOBBar);
    ob.top       = h;
    ob.bottom    = l;
    ob.open      = o;
    ob.close     = c;
    ob.midpoint  = (h + l) / 2.0;
    ob.ce        = ob.midpoint;
    ob.bodySize  = body;
    ob.range     = h - l;
    ob.bodyPercent = (ob.range > 0) ? body / ob.range : 0;
    ob.timeframe = m_timeframe;
    ob.strength  = 0.85;
    ob.isFresh   = true;
    ob.atSupportResistance = IsNearResistanceLevel(h);

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

bool CAdvancedOrderBlockDetector::DetectBullishPropulsionBlock(SAdvancedOrderBlock &ob)
{
    double atr = GetATRValue(14);
    if(atr <= 0.0)
        return false;

    int totalBars = iBars(m_symbol, m_timeframe);
    int bestBar = -1;
    double bestScore = 0.0;

    for(int i = 1; i < 30 && i < totalBars - 10; i++)
    {
        double open = iOpen(m_symbol, m_timeframe, i);
        double close = iClose(m_symbol, m_timeframe, i);
        double high = iHigh(m_symbol, m_timeframe, i);
        double low = iLow(m_symbol, m_timeframe, i);
        double range = high - low;
        double body = close - open;

        if(body <= 0.0 || range <= 0.0)
            continue;
        if(body < atr * 0.40 || (body / range) < 0.60)
            continue;

        double priorHigh = -DBL_MAX;
        for(int j = i + 1; j <= i + 8 && j < totalBars; j++)
            priorHigh = MathMax(priorHigh, iHigh(m_symbol, m_timeframe, j));
        if(close <= priorHigh)
            continue;

        double breakoutScore = (close - priorHigh) / atr;
        if(breakoutScore > bestScore)
        {
            bestScore = breakoutScore;
            bestBar = i;
        }
    }

    if(bestBar < 0)
        return false;

    ob.type = OB_PROPULSION_BULL;
    ob.time = iTime(m_symbol, m_timeframe, bestBar);
    ob.open = iOpen(m_symbol, m_timeframe, bestBar);
    ob.close = iClose(m_symbol, m_timeframe, bestBar);
    ob.top = MathMax(ob.open, ob.close);
    ob.bottom = MathMin(ob.open, ob.close);
    ob.midpoint = (ob.top + ob.bottom) / 2.0;
    ob.ce = ob.midpoint;
    ob.bodySize = MathAbs(ob.close - ob.open);
    ob.range = iHigh(m_symbol, m_timeframe, bestBar) - iLow(m_symbol, m_timeframe, bestBar);
    ob.bodyPercent = (ob.range > 0.0) ? (ob.bodySize / ob.range) : 0.0;
    ob.strength = MathMin(1.0, 0.72 + MathMin(0.22, bestScore * 0.12));
    ob.timeframe = m_timeframe;
    ob.isFresh = true;
    ob.atSupportResistance = IsNearResistanceLevel(ob.top);
    return true;
}

bool CAdvancedOrderBlockDetector::DetectBearishPropulsionBlock(SAdvancedOrderBlock &ob)
{
    double atr = GetATRValue(14);
    if(atr <= 0.0)
        return false;

    int totalBars = iBars(m_symbol, m_timeframe);
    int bestBar = -1;
    double bestScore = 0.0;

    for(int i = 1; i < 30 && i < totalBars - 10; i++)
    {
        double open = iOpen(m_symbol, m_timeframe, i);
        double close = iClose(m_symbol, m_timeframe, i);
        double high = iHigh(m_symbol, m_timeframe, i);
        double low = iLow(m_symbol, m_timeframe, i);
        double range = high - low;
        double body = open - close;

        if(body <= 0.0 || range <= 0.0)
            continue;
        if(body < atr * 0.40 || (body / range) < 0.60)
            continue;

        double priorLow = DBL_MAX;
        for(int j = i + 1; j <= i + 8 && j < totalBars; j++)
            priorLow = MathMin(priorLow, iLow(m_symbol, m_timeframe, j));
        if(close >= priorLow)
            continue;

        double breakoutScore = (priorLow - close) / atr;
        if(breakoutScore > bestScore)
        {
            bestScore = breakoutScore;
            bestBar = i;
        }
    }

    if(bestBar < 0)
        return false;

    ob.type = OB_PROPULSION_BEAR;
    ob.time = iTime(m_symbol, m_timeframe, bestBar);
    ob.open = iOpen(m_symbol, m_timeframe, bestBar);
    ob.close = iClose(m_symbol, m_timeframe, bestBar);
    ob.top = MathMax(ob.open, ob.close);
    ob.bottom = MathMin(ob.open, ob.close);
    ob.midpoint = (ob.top + ob.bottom) / 2.0;
    ob.ce = ob.midpoint;
    ob.bodySize = MathAbs(ob.close - ob.open);
    ob.range = iHigh(m_symbol, m_timeframe, bestBar) - iLow(m_symbol, m_timeframe, bestBar);
    ob.bodyPercent = (ob.range > 0.0) ? (ob.bodySize / ob.range) : 0.0;
    ob.strength = MathMin(1.0, 0.72 + MathMin(0.22, bestScore * 0.12));
    ob.timeframe = m_timeframe;
    ob.isFresh = true;
    ob.atSupportResistance = IsNearSupportLevel(ob.bottom);
    return true;
}

bool CAdvancedOrderBlockDetector::DetectBullishRejectionBlock(SAdvancedOrderBlock &ob)
{
    int totalBars = iBars(m_symbol, m_timeframe);
    int bestBar = -1;
    double bestRatio = 0.0;
    double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    if(point <= 0.0)
        point = 0.00001;

    for(int i = 1; i < 25 && i < totalBars; i++)
    {
        double open = iOpen(m_symbol, m_timeframe, i);
        double close = iClose(m_symbol, m_timeframe, i);
        double high = iHigh(m_symbol, m_timeframe, i);
        double low = iLow(m_symbol, m_timeframe, i);
        double body = MathAbs(close - open);
        if(body <= point)
            continue;

        double lowerWick = MathMin(open, close) - low;
        double wickRatio = lowerWick / body;
        if(wickRatio < 3.0)
            continue;

        bool nearKeyLevel = IsNearSupportLevel(low) || FindMostRecentSwingLow(12) >= 0;
        if(!nearKeyLevel)
            continue;

        if(wickRatio > bestRatio)
        {
            bestRatio = wickRatio;
            bestBar = i;
        }
    }

    if(bestBar < 0)
        return false;

    ob.type = OB_REJECTION_BULL;
    ob.time = iTime(m_symbol, m_timeframe, bestBar);
    ob.open = iOpen(m_symbol, m_timeframe, bestBar);
    ob.close = iClose(m_symbol, m_timeframe, bestBar);
    ob.top = MathMin(ob.open, ob.close);
    ob.bottom = iLow(m_symbol, m_timeframe, bestBar);
    ob.midpoint = (ob.top + ob.bottom) / 2.0;
    ob.ce = ob.midpoint;
    ob.bodySize = MathAbs(ob.close - ob.open);
    ob.range = iHigh(m_symbol, m_timeframe, bestBar) - iLow(m_symbol, m_timeframe, bestBar);
    ob.bodyPercent = (ob.range > 0.0) ? (ob.bodySize / ob.range) : 0.0;
    ob.strength = MathMin(1.0, 0.70 + MathMin(0.20, (bestRatio - 3.0) * 0.05));
    ob.timeframe = m_timeframe;
    ob.shadowUsedForSL = true;
    ob.isFresh = true;
    ob.atSupportResistance = true;
    return true;
}

bool CAdvancedOrderBlockDetector::DetectBearishRejectionBlock(SAdvancedOrderBlock &ob)
{
    int totalBars = iBars(m_symbol, m_timeframe);
    int bestBar = -1;
    double bestRatio = 0.0;
    double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    if(point <= 0.0)
        point = 0.00001;

    for(int i = 1; i < 25 && i < totalBars; i++)
    {
        double open = iOpen(m_symbol, m_timeframe, i);
        double close = iClose(m_symbol, m_timeframe, i);
        double high = iHigh(m_symbol, m_timeframe, i);
        double low = iLow(m_symbol, m_timeframe, i);
        double body = MathAbs(close - open);
        if(body <= point)
            continue;

        double upperWick = high - MathMax(open, close);
        double wickRatio = upperWick / body;
        if(wickRatio < 3.0)
            continue;

        bool nearKeyLevel = IsNearResistanceLevel(high) || FindMostRecentSwingHigh(12) >= 0;
        if(!nearKeyLevel)
            continue;

        if(wickRatio > bestRatio)
        {
            bestRatio = wickRatio;
            bestBar = i;
        }
    }

    if(bestBar < 0)
        return false;

    ob.type = OB_REJECTION_BEAR;
    ob.time = iTime(m_symbol, m_timeframe, bestBar);
    ob.open = iOpen(m_symbol, m_timeframe, bestBar);
    ob.close = iClose(m_symbol, m_timeframe, bestBar);
    ob.top = iHigh(m_symbol, m_timeframe, bestBar);
    ob.bottom = MathMax(ob.open, ob.close);
    ob.midpoint = (ob.top + ob.bottom) / 2.0;
    ob.ce = ob.midpoint;
    ob.bodySize = MathAbs(ob.close - ob.open);
    ob.range = iHigh(m_symbol, m_timeframe, bestBar) - iLow(m_symbol, m_timeframe, bestBar);
    ob.bodyPercent = (ob.range > 0.0) ? (ob.bodySize / ob.range) : 0.0;
    ob.strength = MathMin(1.0, 0.70 + MathMin(0.20, (bestRatio - 3.0) * 0.05));
    ob.timeframe = m_timeframe;
    ob.shadowUsedForSL = true;
    ob.isFresh = true;
    ob.atSupportResistance = true;
    return true;
}

bool CAdvancedOrderBlockDetector::DetectBullishVacuumBlock(SAdvancedOrderBlock &ob)
{
    double atr = GetATRValue(14);
    if(atr <= 0.0)
        return false;

    int totalBars = iBars(m_symbol, m_timeframe);
    int bestBar = -1;
    double bestVoidRatio = 0.0;

    for(int i = 1; i < 30 && i < totalBars; i++)
    {
        double open = iOpen(m_symbol, m_timeframe, i);
        double close = iClose(m_symbol, m_timeframe, i);
        double high = iHigh(m_symbol, m_timeframe, i);
        double low = iLow(m_symbol, m_timeframe, i);
        double range = high - low;
        long barVolume = iVolume(m_symbol, m_timeframe, i);
        long avgVolume = GetAverageVolume(i + 1, 20);
        if(close <= open || range <= (atr * 1.5) || avgVolume <= 0)
            continue;
        if((double)barVolume >= ((double)avgVolume * 0.30))
            continue;

        double voidRatio = ((double)avgVolume - (double)barVolume) / (double)avgVolume;
        if(voidRatio > bestVoidRatio)
        {
            bestVoidRatio = voidRatio;
            bestBar = i;
        }
    }

    if(bestBar < 0)
        return false;

    ob.type = OB_VACUUM_BULL;
    ob.time = iTime(m_symbol, m_timeframe, bestBar);
    ob.open = iOpen(m_symbol, m_timeframe, bestBar);
    ob.close = iClose(m_symbol, m_timeframe, bestBar);
    ob.top = iHigh(m_symbol, m_timeframe, bestBar);
    ob.bottom = iLow(m_symbol, m_timeframe, bestBar);
    ob.midpoint = (ob.top + ob.bottom) / 2.0;
    ob.ce = ob.midpoint;
    ob.bodySize = MathAbs(ob.close - ob.open);
    ob.range = ob.top - ob.bottom;
    ob.bodyPercent = (ob.range > 0.0) ? (ob.bodySize / ob.range) : 0.0;
    ob.strength = MathMin(1.0, 0.68 + MathMin(0.25, bestVoidRatio * 0.30));
    ob.timeframe = m_timeframe;
    ob.isFresh = true;
    return true;
}

bool CAdvancedOrderBlockDetector::DetectBearishVacuumBlock(SAdvancedOrderBlock &ob)
{
    double atr = GetATRValue(14);
    if(atr <= 0.0)
        return false;

    int totalBars = iBars(m_symbol, m_timeframe);
    int bestBar = -1;
    double bestVoidRatio = 0.0;

    for(int i = 1; i < 30 && i < totalBars; i++)
    {
        double open = iOpen(m_symbol, m_timeframe, i);
        double close = iClose(m_symbol, m_timeframe, i);
        double high = iHigh(m_symbol, m_timeframe, i);
        double low = iLow(m_symbol, m_timeframe, i);
        double range = high - low;
        long barVolume = iVolume(m_symbol, m_timeframe, i);
        long avgVolume = GetAverageVolume(i + 1, 20);
        if(close >= open || range <= (atr * 1.5) || avgVolume <= 0)
            continue;
        if((double)barVolume >= ((double)avgVolume * 0.30))
            continue;

        double voidRatio = ((double)avgVolume - (double)barVolume) / (double)avgVolume;
        if(voidRatio > bestVoidRatio)
        {
            bestVoidRatio = voidRatio;
            bestBar = i;
        }
    }

    if(bestBar < 0)
        return false;

    ob.type = OB_VACUUM_BEAR;
    ob.time = iTime(m_symbol, m_timeframe, bestBar);
    ob.open = iOpen(m_symbol, m_timeframe, bestBar);
    ob.close = iClose(m_symbol, m_timeframe, bestBar);
    ob.top = iHigh(m_symbol, m_timeframe, bestBar);
    ob.bottom = iLow(m_symbol, m_timeframe, bestBar);
    ob.midpoint = (ob.top + ob.bottom) / 2.0;
    ob.ce = ob.midpoint;
    ob.bodySize = MathAbs(ob.close - ob.open);
    ob.range = ob.top - ob.bottom;
    ob.bodyPercent = (ob.range > 0.0) ? (ob.bodySize / ob.range) : 0.0;
    ob.strength = MathMin(1.0, 0.68 + MathMin(0.25, bestVoidRatio * 0.30));
    ob.timeframe = m_timeframe;
    ob.isFresh = true;
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
        
        if(IsBullishType(ob.type))
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
//| Check Mitigation — P0-B Rewrite                                 |
//+------------------------------------------------------------------+
// ICT Rule: OB is mitigated only when a candle CLOSES through the full boundary.
// Bullish OBs: mitigated when close < bottom.
// Bearish OBs: mitigated when close > top.
// CE (midpoint) is NOT a mitigation level — it is an entry refinement target.
bool CAdvancedOrderBlockDetector::CheckMitigation(SAdvancedOrderBlock &ob)
{
    if(ob.isMitigated) return true;

    // Set CE on first call if not set
    if(ob.ce == 0)
        ob.ce = (ob.top + ob.bottom) / 2.0;

    // Determine OB direction
    bool isBullishOB = IsBullishType(ob.type);

    ob.mitigationLevel = isBullishOB ? ob.bottom : ob.top;

    // Walk forward from OB formation time
    for(int i = 0; i < 200; i++)
    {
        datetime barTime = iTime(m_symbol, m_timeframe, i);
        if(barTime <= ob.time) break;

        double barHigh  = iHigh(m_symbol,  m_timeframe, i);
        double barLow   = iLow(m_symbol,   m_timeframe, i);
        double barClose = iClose(m_symbol, m_timeframe, i);

        // Track tests (price entering the OB body zone)
        bool priceInOB = (barHigh >= ob.bottom && barLow <= ob.top);
        if(priceInOB)
        {
            if(!ob.isTested)
            {
                ob.isTested = true;
                ob.isFresh  = false;
                ob.firstTestedTime = barTime;
            }
            ob.testCount++;
        }

        // Check for rejection (price entered OB but closed OUT of it in the OB's direction)
        if(isBullishOB && priceInOB && barClose > ob.top)
            ob.timesRejected++;
        if(!isBullishOB && priceInOB && barClose < ob.bottom)
            ob.timesRejected++;

        // MITIGATION CHECK — candle must CLOSE through the far boundary
        if(isBullishOB)
        {
            if(barClose < ob.bottom)
            {
                ob.isMitigated = true;
                return true;
            }
        }
        else
        {
            if(barClose > ob.top)
            {
                ob.isMitigated = true;
                return true;
            }
        }
    }

    // P0-B: Update strength based on freshness status
    if(ob.isFresh)
        ob.strength = MathMin(1.0, ob.strength + 0.10);  // Fresh OB = premium

    if(ob.timesRejected >= 2)
        ob.strength = MathMin(1.0, ob.strength + 0.08);  // Multiple rejections = proven zone

    if(ob.timesRejected >= 3)
        ob.isMitigated = true;  // OB exhausted after 3 rejections — treat as used up

    return ob.isMitigated;
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
        
        if(IsBullishType(m_orderBlocks[i].type))
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
        
        if(IsBearishType(m_orderBlocks[i].type))
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
//| Get Freshness — Batch 103: OB freshness decay 0.0-1.0            |
//| Fresh OBs (0-5 bars old) = 1.0, linear decay to 0.0 over 50 bars|
//+------------------------------------------------------------------+
double CAdvancedOrderBlockDetector::GetFreshness(int obIndex)
{
    if(obIndex < 0 || obIndex >= m_obCount)
        return 0.0;

    SAdvancedOrderBlock ob;
    if(!GetOrderBlock(obIndex, ob))
        return 0.0;

    int currentBar = iBars(m_symbol, m_timeframe);
    if(currentBar <= 0)
        return 0.5;  // Unknown — return neutral

    int obBar = iBarShift(m_symbol, m_timeframe, ob.time, false);
    if(obBar < 0)
        return 0.5;  // Cannot determine age

    int ageBars = obBar;  // How many bars since OB formed

    if(ageBars <= 5)
        return 1.0;   // Fresh — full weight
    if(ageBars >= 50)
        return 0.0;   // Stale — no weight

    // Linear decay: 1.0 at bar 5 → 0.0 at bar 50
    return 1.0 - ((double)(ageBars - 5) / 45.0);
}

#endif // __UICT_ADVANCED_ORDER_BLOCKS_MQH__
