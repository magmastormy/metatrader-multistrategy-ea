//+------------------------------------------------------------------+
//| FibLevelsCalculator.mqh                                          |
//| Fibonacci Retracements and Extensions Calculator                 |
//| Includes all standard levels plus projections                    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Multi-Strategy EA"
#property version   "2.00"
#property strict

#ifndef __FIB_LEVELS_CALCULATOR_MQH__
#define __FIB_LEVELS_CALCULATOR_MQH__

#include "FibSwingDetector.mqh"

//+------------------------------------------------------------------+
//| Fibonacci Level Structure                                        |
//+------------------------------------------------------------------+
struct SFibLevel
{
    double      price;
    double      ratio;
    string      name;
    bool        isRetracement;
    bool        isExtension;
    bool        isTested;
    int         touchCount;
    double      score;
    
    SFibLevel() : price(0), ratio(0), name(""), isRetracement(false),
                  isExtension(false), isTested(false), touchCount(0), score(0) {}
};

//+------------------------------------------------------------------+
//| Fibonacci Setup Structure                                        |
//+------------------------------------------------------------------+
struct SFibSetup
{
    double      swingHigh;
    double      swingLow;
    datetime    highTime;
    datetime    lowTime;
    bool        isBullish;      // True if low→high (buy retracements)
    
    // Retracement levels (for entries)
    double      fib236;
    double      fib382;
    double      fib500;
    double      fib618;
    double      fib786;
    
    // Extension levels (for targets)
    double      ext1272;
    double      ext1618;
    double      ext2000;
    double      ext2618;
    
    // All levels
    SFibLevel   levels[];
    int         levelCount;
    
    // Metadata
    double      range;
    bool        isValid;
    double      overallScore;
    
    SFibSetup() : swingHigh(0), swingLow(0), highTime(0), lowTime(0),
                  isBullish(false), fib236(0), fib382(0), fib500(0), fib618(0), fib786(0),
                  ext1272(0), ext1618(0), ext2000(0), ext2618(0), levelCount(0),
                  range(0), isValid(false), overallScore(0) {}
};

//+------------------------------------------------------------------+
//| Fibonacci Levels Calculator Class                                |
//+------------------------------------------------------------------+
class CFibLevelsCalculator
{
private:
    string              m_symbol;
    ENUM_TIMEFRAMES     m_timeframe;
    
    // Fibonacci setups
    SFibSetup           m_setups[];
    int                 m_setupCount;
    int                 m_maxSetups;
    
    // Standard Fibonacci ratios
    double              m_retracementRatios[5];
    double              m_extensionRatios[4];
    
    // Configuration
    double              m_levelTolerance;   // Pips tolerance for level tests
    
    // Internal methods
    void                InitializeRatios();
    void                CalculateLevels(SFibSetup &setup);
    void                ScoreSetup(SFibSetup &setup);
    void                CheckLevelTests(SFibSetup &setup);
    
public:
                        CFibLevelsCalculator();
                       ~CFibLevelsCalculator();
    
    // Initialization
    bool                Initialize(const string symbol, ENUM_TIMEFRAMES timeframe);
    
    // Level calculation
    SFibSetup           CalculateFibLevels(double high, double low, bool isBullish);
    SFibSetup           CalculateFromSwingPair(const SFibSwingPair &pair);
    void                CalculateMultipleSetups(CFibSwingDetector* swingDetector);
    
    // Level management
    void                UpdateLevelTests();
    void                InvalidateTestedLevels(double price);
    
    // Getters
    int                 GetSetupCount() const { return m_setupCount; }
    bool                GetSetupAt(int index, SFibSetup &setup);
    bool                GetBestBullishSetup(SFibSetup &setup);
    bool                GetBestBearishSetup(SFibSetup &setup);
    
    // Level checks
    bool                IsPriceAtFibLevel(double price, SFibLevel &activeLevel);
    bool                IsPriceAt618(double price, SFibSetup &setup);
    bool                IsPriceAt500(double price, SFibSetup &setup);
    bool                IsPriceAt382(double price, SFibSetup &setup);
    
    // Extension targets
    double              GetTP1(const SFibSetup &setup);  // Swing high/low
    double              GetTP2(const SFibSetup &setup);  // 127.2%
    double              GetTP3(const SFibSetup &setup);  // 161.8%
    double              GetTP4(const SFibSetup &setup);  // 200%
    
    // Configuration
    void                SetLevelTolerance(double pips) { m_levelTolerance = pips; }
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CFibLevelsCalculator::CFibLevelsCalculator() :
    m_symbol(""),
    m_timeframe(PERIOD_CURRENT),
    m_setupCount(0),
    m_maxSetups(10),
    m_levelTolerance(10.0)
{
    ArrayResize(m_setups, 0);
    InitializeRatios();
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CFibLevelsCalculator::~CFibLevelsCalculator()
{
    ArrayFree(m_setups);
}

//+------------------------------------------------------------------+
//| Initialize Ratios                                                |
//+------------------------------------------------------------------+
void CFibLevelsCalculator::InitializeRatios()
{
    // Retracement ratios
    m_retracementRatios[0] = 0.236;
    m_retracementRatios[1] = 0.382;
    m_retracementRatios[2] = 0.500;
    m_retracementRatios[3] = 0.618;
    m_retracementRatios[4] = 0.786;
    
    // Extension ratios
    m_extensionRatios[0] = 1.272;
    m_extensionRatios[1] = 1.618;
    m_extensionRatios[2] = 2.000;
    m_extensionRatios[3] = 2.618;
}

//+------------------------------------------------------------------+
//| Initialize                                                       |
//+------------------------------------------------------------------+
bool CFibLevelsCalculator::Initialize(const string symbol, ENUM_TIMEFRAMES timeframe)
{
    m_symbol = symbol;
    m_timeframe = timeframe;
    
    ArrayResize(m_setups, 0);
    m_setupCount = 0;
    
    return true;
}

//+------------------------------------------------------------------+
//| Calculate Levels                                                 |
//+------------------------------------------------------------------+
void CFibLevelsCalculator::CalculateLevels(SFibSetup &setup)
{
    double range = setup.swingHigh - setup.swingLow;
    setup.range = range;
    
    if(range <= 0)
    {
        setup.isValid = false;
        return;
    }
    
    // Clear existing levels
    ArrayResize(setup.levels, 0);
    setup.levelCount = 0;
    
    if(setup.isBullish)
    {
        // Bullish: measure from low to high, retracements below high
        setup.fib236 = setup.swingHigh - (range * 0.236);
        setup.fib382 = setup.swingHigh - (range * 0.382);
        setup.fib500 = setup.swingHigh - (range * 0.500);
        setup.fib618 = setup.swingHigh - (range * 0.618);
        setup.fib786 = setup.swingHigh - (range * 0.786);
        
        // Extensions above high
        setup.ext1272 = setup.swingHigh + (range * 0.272);
        setup.ext1618 = setup.swingHigh + (range * 0.618);
        setup.ext2000 = setup.swingHigh + (range * 1.000);
        setup.ext2618 = setup.swingHigh + (range * 1.618);
        
        // Add all levels to array
        ArrayResize(setup.levels, 9);
        
        setup.levels[0].price = setup.fib236; setup.levels[0].ratio = 0.236;
        setup.levels[0].name = "23.6%"; setup.levels[0].isRetracement = true;
        
        setup.levels[1].price = setup.fib382; setup.levels[1].ratio = 0.382;
        setup.levels[1].name = "38.2%"; setup.levels[1].isRetracement = true;
        
        setup.levels[2].price = setup.fib500; setup.levels[2].ratio = 0.500;
        setup.levels[2].name = "50%"; setup.levels[2].isRetracement = true;
        
        setup.levels[3].price = setup.fib618; setup.levels[3].ratio = 0.618;
        setup.levels[3].name = "61.8%"; setup.levels[3].isRetracement = true;
        
        setup.levels[4].price = setup.fib786; setup.levels[4].ratio = 0.786;
        setup.levels[4].name = "78.6%"; setup.levels[4].isRetracement = true;
        
        setup.levels[5].price = setup.ext1272; setup.levels[5].ratio = 1.272;
        setup.levels[5].name = "127.2%"; setup.levels[5].isExtension = true;
        
        setup.levels[6].price = setup.ext1618; setup.levels[6].ratio = 1.618;
        setup.levels[6].name = "161.8%"; setup.levels[6].isExtension = true;
        
        setup.levels[7].price = setup.ext2000; setup.levels[7].ratio = 2.000;
        setup.levels[7].name = "200%"; setup.levels[7].isExtension = true;
        
        setup.levels[8].price = setup.ext2618; setup.levels[8].ratio = 2.618;
        setup.levels[8].name = "261.8%"; setup.levels[8].isExtension = true;
        
        setup.levelCount = 9;
    }
    else
    {
        // Bearish: measure from high to low, retracements above low
        setup.fib236 = setup.swingLow + (range * 0.236);
        setup.fib382 = setup.swingLow + (range * 0.382);
        setup.fib500 = setup.swingLow + (range * 0.500);
        setup.fib618 = setup.swingLow + (range * 0.618);
        setup.fib786 = setup.swingLow + (range * 0.786);
        
        // Extensions below low
        setup.ext1272 = setup.swingLow - (range * 0.272);
        setup.ext1618 = setup.swingLow - (range * 0.618);
        setup.ext2000 = setup.swingLow - (range * 1.000);
        setup.ext2618 = setup.swingLow - (range * 1.618);
        
        // Add all levels to array
        ArrayResize(setup.levels, 9);
        
        setup.levels[0].price = setup.fib236; setup.levels[0].ratio = 0.236;
        setup.levels[0].name = "23.6%"; setup.levels[0].isRetracement = true;
        
        setup.levels[1].price = setup.fib382; setup.levels[1].ratio = 0.382;
        setup.levels[1].name = "38.2%"; setup.levels[1].isRetracement = true;
        
        setup.levels[2].price = setup.fib500; setup.levels[2].ratio = 0.500;
        setup.levels[2].name = "50%"; setup.levels[2].isRetracement = true;
        
        setup.levels[3].price = setup.fib618; setup.levels[3].ratio = 0.618;
        setup.levels[3].name = "61.8%"; setup.levels[3].isRetracement = true;
        
        setup.levels[4].price = setup.fib786; setup.levels[4].ratio = 0.786;
        setup.levels[4].name = "78.6%"; setup.levels[4].isRetracement = true;
        
        setup.levels[5].price = setup.ext1272; setup.levels[5].ratio = 1.272;
        setup.levels[5].name = "127.2%"; setup.levels[5].isExtension = true;
        
        setup.levels[6].price = setup.ext1618; setup.levels[6].ratio = 1.618;
        setup.levels[6].name = "161.8%"; setup.levels[6].isExtension = true;
        
        setup.levels[7].price = setup.ext2000; setup.levels[7].ratio = 2.000;
        setup.levels[7].name = "200%"; setup.levels[7].isExtension = true;
        
        setup.levels[8].price = setup.ext2618; setup.levels[8].ratio = 2.618;
        setup.levels[8].name = "261.8%"; setup.levels[8].isExtension = true;
        
        setup.levelCount = 9;
    }
    
    setup.isValid = true;
}

//+------------------------------------------------------------------+
//| Score Setup                                                      |
//+------------------------------------------------------------------+
void CFibLevelsCalculator::ScoreSetup(SFibSetup &setup)
{
    double score = 50.0;  // Base score
    
    // Range size bonus (larger = more significant)
    int atrHandle = iATR(m_symbol, m_timeframe, 14);
    double atr[];
    ArraySetAsSeries(atr, true);
    if(atrHandle != INVALID_HANDLE && CopyBuffer(atrHandle, 0, 0, 1, atr) > 0)
    {
        if(setup.range > atr[0] * 2.0)
            score += 15.0;
        else if(setup.range > atr[0])
            score += 8.0;
        
        IndicatorRelease(atrHandle);
    }
    
    // Level test penalty (tested levels are weaker)
    int testedCount = 0;
    for(int i = 0; i < setup.levelCount; i++)
    {
        if(setup.levels[i].isTested)
            testedCount++;
    }
    score -= testedCount * 3.0;
    
    // Recency bonus
    int age = Bars(m_symbol, m_timeframe, setup.highTime, TimeCurrent());
    if(age < 50)
        score += 10.0;
    else if(age > 200)
        score -= 10.0;
    
    setup.overallScore = MathMax(0, MathMin(100, score));
}

//+------------------------------------------------------------------+
//| Check Level Tests                                                |
//+------------------------------------------------------------------+
void CFibLevelsCalculator::CheckLevelTests(SFibSetup &setup)
{
    double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    if(point <= 0) point = 0.0001;
    
    double tolerance = m_levelTolerance * point;
    
    // Check recent price action against levels
    for(int bar = 1; bar <= 20; bar++)
    {
        double high = iHigh(m_symbol, m_timeframe, bar);
        double low = iLow(m_symbol, m_timeframe, bar);
        
        for(int i = 0; i < setup.levelCount; i++)
        {
            if(setup.levels[i].isTested) continue;
            
            if((high >= setup.levels[i].price - tolerance && 
                low <= setup.levels[i].price + tolerance))
            {
                setup.levels[i].isTested = true;
                setup.levels[i].touchCount++;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Calculate Fib Levels                                             |
//+------------------------------------------------------------------+
SFibSetup CFibLevelsCalculator::CalculateFibLevels(double high, double low, bool isBullish)
{
    SFibSetup setup;
    setup.swingHigh = high;
    setup.swingLow = low;
    setup.isBullish = isBullish;
    setup.highTime = TimeCurrent();
    setup.lowTime = TimeCurrent();
    
    CalculateLevels(setup);
    CheckLevelTests(setup);
    ScoreSetup(setup);
    
    return setup;
}

//+------------------------------------------------------------------+
//| Calculate From Swing Pair                                        |
//+------------------------------------------------------------------+
SFibSetup CFibLevelsCalculator::CalculateFromSwingPair(const SFibSwingPair &pair)
{
    SFibSetup setup;
    setup.swingHigh = pair.high.price;
    setup.swingLow = pair.low.price;
    setup.highTime = pair.high.time;
    setup.lowTime = pair.low.time;
    setup.isBullish = pair.isBullish;
    
    CalculateLevels(setup);
    CheckLevelTests(setup);
    ScoreSetup(setup);
    
    return setup;
}

//+------------------------------------------------------------------+
//| Calculate Multiple Setups                                        |
//+------------------------------------------------------------------+
void CFibLevelsCalculator::CalculateMultipleSetups(CFibSwingDetector* swingDetector)
{
    if(swingDetector == NULL) return;
    
    ArrayResize(m_setups, 0);
    m_setupCount = 0;
    
    int pairCount = swingDetector.GetSwingPairCount();
    
    for(int i = 0; i < pairCount && m_setupCount < m_maxSetups; i++)
    {
        SFibSwingPair pair;
        if(swingDetector.GetSwingPairAt(i, pair))
        {
            SFibSetup setup = CalculateFromSwingPair(pair);
            if(setup.isValid)
            {
                ArrayResize(m_setups, m_setupCount + 1);
                m_setups[m_setupCount++] = setup;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Get Setup At Index                                               |
//+------------------------------------------------------------------+
bool CFibLevelsCalculator::GetSetupAt(int index, SFibSetup &setup)
{
    if(index < 0 || index >= m_setupCount) return false;
    setup = m_setups[index];
    return true;
}

//+------------------------------------------------------------------+
//| Get Best Bullish Setup                                           |
//+------------------------------------------------------------------+
bool CFibLevelsCalculator::GetBestBullishSetup(SFibSetup &setup)
{
    double bestScore = 0;
    int bestIndex = -1;
    
    for(int i = 0; i < m_setupCount; i++)
    {
        if(m_setups[i].isBullish && m_setups[i].overallScore > bestScore)
        {
            bestScore = m_setups[i].overallScore;
            bestIndex = i;
        }
    }
    
    if(bestIndex >= 0)
    {
        setup = m_setups[bestIndex];
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Get Best Bearish Setup                                           |
//+------------------------------------------------------------------+
bool CFibLevelsCalculator::GetBestBearishSetup(SFibSetup &setup)
{
    double bestScore = 0;
    int bestIndex = -1;
    
    for(int i = 0; i < m_setupCount; i++)
    {
        if(!m_setups[i].isBullish && m_setups[i].overallScore > bestScore)
        {
            bestScore = m_setups[i].overallScore;
            bestIndex = i;
        }
    }
    
    if(bestIndex >= 0)
    {
        setup = m_setups[bestIndex];
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Is Price At Fib Level                                            |
//+------------------------------------------------------------------+
bool CFibLevelsCalculator::IsPriceAtFibLevel(double price, SFibLevel &activeLevel)
{
    double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    if(point <= 0) point = 0.0001;
    double tolerance = m_levelTolerance * point;
    
    for(int i = 0; i < m_setupCount; i++)
    {
        for(int j = 0; j < m_setups[i].levelCount; j++)
        {
            if(MathAbs(price - m_setups[i].levels[j].price) <= tolerance)
            {
                activeLevel = m_setups[i].levels[j];
                return true;
            }
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Is Price At 61.8%                                                |
//+------------------------------------------------------------------+
bool CFibLevelsCalculator::IsPriceAt618(double price, SFibSetup &setup)
{
    double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    if(point <= 0) point = 0.0001;
    double tolerance = m_levelTolerance * point;
    
    for(int i = 0; i < m_setupCount; i++)
    {
        if(MathAbs(price - m_setups[i].fib618) <= tolerance)
        {
            setup = m_setups[i];
            return true;
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Is Price At 50%                                                  |
//+------------------------------------------------------------------+
bool CFibLevelsCalculator::IsPriceAt500(double price, SFibSetup &setup)
{
    double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    if(point <= 0) point = 0.0001;
    double tolerance = m_levelTolerance * point;
    
    for(int i = 0; i < m_setupCount; i++)
    {
        if(MathAbs(price - m_setups[i].fib500) <= tolerance)
        {
            setup = m_setups[i];
            return true;
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Is Price At 38.2%                                                |
//+------------------------------------------------------------------+
bool CFibLevelsCalculator::IsPriceAt382(double price, SFibSetup &setup)
{
    double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    if(point <= 0) point = 0.0001;
    double tolerance = m_levelTolerance * point;
    
    for(int i = 0; i < m_setupCount; i++)
    {
        if(MathAbs(price - m_setups[i].fib382) <= tolerance)
        {
            setup = m_setups[i];
            return true;
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Get Take Profit Levels                                           |
//+------------------------------------------------------------------+
double CFibLevelsCalculator::GetTP1(const SFibSetup &setup)
{
    return setup.isBullish ? setup.swingHigh : setup.swingLow;
}

double CFibLevelsCalculator::GetTP2(const SFibSetup &setup)
{
    return setup.ext1272;
}

double CFibLevelsCalculator::GetTP3(const SFibSetup &setup)
{
    return setup.ext1618;
}

double CFibLevelsCalculator::GetTP4(const SFibSetup &setup)
{
    return setup.ext2000;
}

//+------------------------------------------------------------------+
//| Update Level Tests                                               |
//+------------------------------------------------------------------+
void CFibLevelsCalculator::UpdateLevelTests()
{
    for(int i = 0; i < m_setupCount; i++)
    {
        CheckLevelTests(m_setups[i]);
        ScoreSetup(m_setups[i]);
    }
}

//+------------------------------------------------------------------+
//| Invalidate Tested Levels                                         |
//+------------------------------------------------------------------+
void CFibLevelsCalculator::InvalidateTestedLevels(double price)
{
    double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    if(point <= 0) point = 0.0001;
    double tolerance = m_levelTolerance * point;
    
    for(int i = 0; i < m_setupCount; i++)
    {
        for(int j = 0; j < m_setups[i].levelCount; j++)
        {
            if(MathAbs(price - m_setups[i].levels[j].price) <= tolerance)
            {
                m_setups[i].levels[j].touchCount++;
                if(m_setups[i].levels[j].touchCount > 2)
                    m_setups[i].levels[j].isTested = true;
            }
        }
    }
}

#endif // __FIB_LEVELS_CALCULATOR_MQH__
