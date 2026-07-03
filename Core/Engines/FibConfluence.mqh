//+------------------------------------------------------------------+
//| FibConfluence.mqh                                                |
//| Lightweight Fibonacci Confluence Module                          |
//| Provides Fibonacci level checking for S/R confluence             |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Multi-Strategy EA"
#property version   "1.00"
#property strict

#ifndef FIB_CONFLUENCE_MQH
#define FIB_CONFLUENCE_MQH

//+------------------------------------------------------------------+
//| Fibonacci Level Structure                                        |
//+------------------------------------------------------------------+
struct SFibLevel
{
    double price;
    double ratio;  // 0.382, 0.500, 0.618, etc.
    
    SFibLevel() : price(0), ratio(0) {}
};

//+------------------------------------------------------------------+
//| Fibonacci Confluence Helper Class                                |
//+------------------------------------------------------------------+
class CFibConfluence
{
private:
    string              m_symbol;
    ENUM_TIMEFRAMES     m_timeframe;
    
public:
                        CFibConfluence();
                       ~CFibConfluence();
    
    bool                Initialize(const string symbol, ENUM_TIMEFRAMES timeframe);
    
    // Calculate Fibonacci levels from swing pair
    void                CalculateLevels(double swingHigh, double swingLow, SFibLevel &levels[], int &count);
    
    // Check if price is near a Fibonacci level
    bool                IsNearFibLevel(double currentPrice, const SFibLevel &levels[], int count, 
                                      double tolerancePips, double &nearestRatio);
    
    // Get confidence boost based on Fib ratio importance
    double              GetConfidenceBoost(double fibRatio);
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CFibConfluence::CFibConfluence() :
    m_symbol(""),
    m_timeframe(PERIOD_CURRENT)
{
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CFibConfluence::~CFibConfluence()
{
}

//+------------------------------------------------------------------+
//| Initialize                                                       |
//+------------------------------------------------------------------+
bool CFibConfluence::Initialize(const string symbol, ENUM_TIMEFRAMES timeframe)
{
    m_symbol = symbol;
    m_timeframe = timeframe;
    return true;
}

//+------------------------------------------------------------------+
//| Calculate Fibonacci Levels                                       |
//+------------------------------------------------------------------+
void CFibConfluence::CalculateLevels(double swingHigh, double swingLow, SFibLevel &levels[], int &count)
{
    if(swingHigh <= swingLow || swingLow <= 0)
    {
        count = 0;
        return;
    }
    
    double range = swingHigh - swingLow;
    
    // Calculate only the 3 most important retracement levels
    count = 3;
    ArrayResize(levels, count);
    
    levels[0].price = swingLow + range * 0.382;
    levels[0].ratio = 0.382;
    
    levels[1].price = swingLow + range * 0.500;
    levels[1].ratio = 0.500;
    
    levels[2].price = swingLow + range * 0.618;
    levels[2].ratio = 0.618;
}

//+------------------------------------------------------------------+
//| Check if Price is Near Fibonacci Level                           |
//+------------------------------------------------------------------+
bool CFibConfluence::IsNearFibLevel(double currentPrice, const SFibLevel &levels[], int count,
                                   double tolerancePips, double &nearestRatio)
{
    if(count == 0) return false;
    
    double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    double tolerance = tolerancePips * point;
    
    double closestDistance = DBL_MAX;
    nearestRatio = 0.0;
    
    for(int i = 0; i < count; i++)
    {
        double distance = MathAbs(currentPrice - levels[i].price);
        if(distance < tolerance && distance < closestDistance)
        {
            closestDistance = distance;
            nearestRatio = levels[i].ratio;
        }
    }
    
    return (nearestRatio > 0);
}

//+------------------------------------------------------------------+
//| Get Confidence Boost Based on Fibonacci Ratio                    |
//+------------------------------------------------------------------+
double CFibConfluence::GetConfidenceBoost(double fibRatio)
{
    // Golden ratio gets highest boost
    if(fibRatio == 0.618)
        return 1.30;  // 30% boost
    
    // 50% retracement
    if(fibRatio == 0.500)
        return 1.15;  // 15% boost
    
    // 38.2% retracement
    if(fibRatio == 0.382)
        return 1.10;  // 10% boost
    
    return 1.0;  // No boost
}

#endif // __FIB_CONFLUENCE_MQH__
