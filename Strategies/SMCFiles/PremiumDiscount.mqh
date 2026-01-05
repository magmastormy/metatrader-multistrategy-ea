//+------------------------------------------------------------------+
//| PremiumDiscount.mqh                                              |
//| Premium/Discount Arrays & OTE Zone Detection                     |
//| ICT Concepts: Trade buys in discount, sells in premium           |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Multi-Strategy EA"
#property version   "2.00"
#property strict

#ifndef __SMC_PREMIUM_DISCOUNT_MQH__
#define __SMC_PREMIUM_DISCOUNT_MQH__

//+------------------------------------------------------------------+
//| Zone Type                                                        |
//+------------------------------------------------------------------+
enum ENUM_PRICE_ZONE
{
    ZONE_EXTREME_PREMIUM,    // Above 78.6%
    ZONE_PREMIUM,            // 50% - 78.6% (look for sells)
    ZONE_EQUILIBRIUM,        // Around 50%
    ZONE_DISCOUNT,           // 21.4% - 50% (look for buys)
    ZONE_EXTREME_DISCOUNT    // Below 21.4%
};

//+------------------------------------------------------------------+
//| OTE (Optimal Trade Entry) Zone                                   |
//+------------------------------------------------------------------+
struct SOTEZone
{
    double      high;        // Top of OTE (61.8%)
    double      low;         // Bottom of OTE (78.6%)
    double      swingHigh;   // Reference swing high
    double      swingLow;    // Reference swing low
    bool        isBullish;   // OTE for buys or sells
    bool        isActive;
    datetime    createdTime;
    double      score;
    
    SOTEZone() : high(0), low(0), swingHigh(0), swingLow(0),
                 isBullish(false), isActive(false), createdTime(0), score(0) {}
};

//+------------------------------------------------------------------+
//| Premium/Discount Class                                           |
//+------------------------------------------------------------------+
class CSMCPremiumDiscount
{
private:
    string              m_symbol;
    ENUM_TIMEFRAMES     m_timeframe;
    
    // Range tracking
    double              m_rangeHigh;
    double              m_rangeLow;
    double              m_rangeMid;
    int                 m_rangeLookback;
    
    // OTE zones
    SOTEZone            m_bullishOTE;
    SOTEZone            m_bearishOTE;
    
    // Internal methods
    void                CalculateRange();
    void                CalculateOTEZones();
    
public:
                        CSMCPremiumDiscount();
                       ~CSMCPremiumDiscount();
    
    // Initialization
    bool                Initialize(const string symbol, ENUM_TIMEFRAMES timeframe,
                                  int rangeLookback = 100);
    
    // Update
    void                Update();
    
    // Premium/Discount checks
    bool                IsPremium(double price);
    bool                IsDiscount(double price);
    bool                IsExtremePremium(double price);
    bool                IsExtremeDiscount(double price);
    bool                IsEquilibrium(double price);
    ENUM_PRICE_ZONE     GetPriceZone(double price);
    
    // OTE Zone checks
    bool                IsInBullishOTE(double price);
    bool                IsInBearishOTE(double price);
    bool                GetBullishOTE(SOTEZone &ote);
    bool                GetBearishOTE(SOTEZone &ote);
    
    // Getters
    double              GetRangeHigh() const { return m_rangeHigh; }
    double              GetRangeLow() const { return m_rangeLow; }
    double              GetRangeMid() const { return m_rangeMid; }
    double              GetEquilibriumPrice() const { return m_rangeMid; }
    
    // Fibonacci levels within range
    double              GetFibLevel(double ratio);  // 0.0 = low, 1.0 = high
    double              Get236Level() { return GetFibLevel(0.236); }
    double              Get382Level() { return GetFibLevel(0.382); }
    double              Get500Level() { return GetFibLevel(0.500); }
    double              Get618Level() { return GetFibLevel(0.618); }
    double              Get786Level() { return GetFibLevel(0.786); }
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CSMCPremiumDiscount::CSMCPremiumDiscount() :
    m_symbol(""),
    m_timeframe(PERIOD_CURRENT),
    m_rangeHigh(0),
    m_rangeLow(0),
    m_rangeMid(0),
    m_rangeLookback(100)
{
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CSMCPremiumDiscount::~CSMCPremiumDiscount()
{
}

//+------------------------------------------------------------------+
//| Initialize                                                       |
//+------------------------------------------------------------------+
bool CSMCPremiumDiscount::Initialize(const string symbol, ENUM_TIMEFRAMES timeframe,
                                     int rangeLookback)
{
    m_symbol = symbol;
    m_timeframe = timeframe;
    m_rangeLookback = rangeLookback;
    
    CalculateRange();
    CalculateOTEZones();
    
    return true;
}

//+------------------------------------------------------------------+
//| Calculate Range                                                  |
//+------------------------------------------------------------------+
void CSMCPremiumDiscount::CalculateRange()
{
    int bars = iBars(m_symbol, m_timeframe);
    int lookback = MathMin(m_rangeLookback, bars - 1);
    
    m_rangeHigh = 0;
    m_rangeLow = DBL_MAX;
    
    for(int i = 0; i < lookback; i++)
    {
        double high = iHigh(m_symbol, m_timeframe, i);
        double low = iLow(m_symbol, m_timeframe, i);
        
        if(high > m_rangeHigh) m_rangeHigh = high;
        if(low < m_rangeLow) m_rangeLow = low;
    }
    
    m_rangeMid = (m_rangeHigh + m_rangeLow) / 2.0;
}

//+------------------------------------------------------------------+
//| Calculate OTE Zones                                              |
//+------------------------------------------------------------------+
void CSMCPremiumDiscount::CalculateOTEZones()
{
    double range = m_rangeHigh - m_rangeLow;
    if(range <= 0) return;
    
    // Bullish OTE: 61.8% to 78.6% retracement from high to low
    // Price zone to BUY in a bullish trend
    m_bullishOTE.swingHigh = m_rangeHigh;
    m_bullishOTE.swingLow = m_rangeLow;
    m_bullishOTE.high = m_rangeHigh - (range * 0.618);  // 61.8% retracement
    m_bullishOTE.low = m_rangeHigh - (range * 0.786);   // 78.6% retracement
    m_bullishOTE.isBullish = true;
    m_bullishOTE.isActive = true;
    m_bullishOTE.createdTime = TimeCurrent();
    m_bullishOTE.score = 70.0;
    
    // Bearish OTE: 61.8% to 78.6% retracement from low to high
    // Price zone to SELL in a bearish trend
    m_bearishOTE.swingHigh = m_rangeHigh;
    m_bearishOTE.swingLow = m_rangeLow;
    m_bearishOTE.low = m_rangeLow + (range * 0.618);   // 61.8% retracement
    m_bearishOTE.high = m_rangeLow + (range * 0.786);  // 78.6% retracement
    m_bearishOTE.isBullish = false;
    m_bearishOTE.isActive = true;
    m_bearishOTE.createdTime = TimeCurrent();
    m_bearishOTE.score = 70.0;
}

//+------------------------------------------------------------------+
//| Update                                                           |
//+------------------------------------------------------------------+
void CSMCPremiumDiscount::Update()
{
    CalculateRange();
    CalculateOTEZones();
}

//+------------------------------------------------------------------+
//| Is Premium                                                       |
//+------------------------------------------------------------------+
bool CSMCPremiumDiscount::IsPremium(double price)
{
    return (price > m_rangeMid);
}

//+------------------------------------------------------------------+
//| Is Discount                                                      |
//+------------------------------------------------------------------+
bool CSMCPremiumDiscount::IsDiscount(double price)
{
    return (price < m_rangeMid);
}

//+------------------------------------------------------------------+
//| Is Extreme Premium                                               |
//+------------------------------------------------------------------+
bool CSMCPremiumDiscount::IsExtremePremium(double price)
{
    double range = m_rangeHigh - m_rangeLow;
    double threshold = m_rangeLow + (range * 0.786);
    return (price > threshold);
}

//+------------------------------------------------------------------+
//| Is Extreme Discount                                              |
//+------------------------------------------------------------------+
bool CSMCPremiumDiscount::IsExtremeDiscount(double price)
{
    double range = m_rangeHigh - m_rangeLow;
    double threshold = m_rangeLow + (range * 0.214);
    return (price < threshold);
}

//+------------------------------------------------------------------+
//| Is Equilibrium                                                   |
//+------------------------------------------------------------------+
bool CSMCPremiumDiscount::IsEquilibrium(double price)
{
    double range = m_rangeHigh - m_rangeLow;
    double tolerance = range * 0.05; // 5% tolerance
    return (MathAbs(price - m_rangeMid) < tolerance);
}

//+------------------------------------------------------------------+
//| Get Price Zone                                                   |
//+------------------------------------------------------------------+
ENUM_PRICE_ZONE CSMCPremiumDiscount::GetPriceZone(double price)
{
    double range = m_rangeHigh - m_rangeLow;
    if(range <= 0) return ZONE_EQUILIBRIUM;
    
    double positionRatio = (price - m_rangeLow) / range;
    
    if(positionRatio >= 0.786)
        return ZONE_EXTREME_PREMIUM;
    else if(positionRatio >= 0.50)
        return ZONE_PREMIUM;
    else if(positionRatio >= 0.214)
        return ZONE_DISCOUNT;
    else
        return ZONE_EXTREME_DISCOUNT;
}

//+------------------------------------------------------------------+
//| Is In Bullish OTE                                                |
//+------------------------------------------------------------------+
bool CSMCPremiumDiscount::IsInBullishOTE(double price)
{
    if(!m_bullishOTE.isActive) return false;
    return (price >= m_bullishOTE.low && price <= m_bullishOTE.high);
}

//+------------------------------------------------------------------+
//| Is In Bearish OTE                                                |
//+------------------------------------------------------------------+
bool CSMCPremiumDiscount::IsInBearishOTE(double price)
{
    if(!m_bearishOTE.isActive) return false;
    return (price >= m_bearishOTE.low && price <= m_bearishOTE.high);
}

//+------------------------------------------------------------------+
//| Get Bullish OTE                                                  |
//+------------------------------------------------------------------+
bool CSMCPremiumDiscount::GetBullishOTE(SOTEZone &ote)
{
    if(!m_bullishOTE.isActive) return false;
    ote = m_bullishOTE;
    return true;
}

//+------------------------------------------------------------------+
//| Get Bearish OTE                                                  |
//+------------------------------------------------------------------+
bool CSMCPremiumDiscount::GetBearishOTE(SOTEZone &ote)
{
    if(!m_bearishOTE.isActive) return false;
    ote = m_bearishOTE;
    return true;
}

//+------------------------------------------------------------------+
//| Get Fibonacci Level                                              |
//+------------------------------------------------------------------+
double CSMCPremiumDiscount::GetFibLevel(double ratio)
{
    return m_rangeLow + ((m_rangeHigh - m_rangeLow) * ratio);
}

#endif // __SMC_PREMIUM_DISCOUNT_MQH__
