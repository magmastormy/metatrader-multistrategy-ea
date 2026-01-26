//+------------------------------------------------------------------+
//| TrendlineDetector.mqh                                            |
//| Trendline Detection and Validation Engine                        |
//| Copyright 2025, Multi-Strategy EA                                |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Multi-Strategy EA"
#property version   "1.00"
#property strict

#ifndef __SR_TRENDLINE_DETECTOR_MQH__
#define __SR_TRENDLINE_DETECTOR_MQH__

//+------------------------------------------------------------------+
//| Trendline Type Enum                                              |
//+------------------------------------------------------------------+
enum ENUM_TRENDLINE_TYPE
{
    TRENDLINE_SUPPORT,
    TRENDLINE_RESISTANCE,
    TRENDLINE_CHANNEL_UPPER,
    TRENDLINE_CHANNEL_LOWER
};

//+------------------------------------------------------------------+
//| Swing Point Structure                                            |
//+------------------------------------------------------------------+
struct SSwingPoint
{
    datetime time;
    double   price;
    int      barIndex;
    bool     isHigh;
    
    SSwingPoint() : time(0), price(0), barIndex(0), isHigh(false) {}
};

//+------------------------------------------------------------------+
//| Trendline Structure                                              |
//+------------------------------------------------------------------+
struct STrendline
{
    ENUM_TRENDLINE_TYPE type;
    datetime point1Time;
    double   point1Price;
    datetime point2Time;
    double   point2Price;
    datetime point3Time;
    double   point3Price;
    double   slope;
    int      touches;
    double   strength;
    bool     isBroken;
    bool     isValid;
    
    STrendline() : type(TRENDLINE_SUPPORT), point1Time(0), point1Price(0),
                  point2Time(0), point2Price(0), point3Time(0), point3Price(0),
                  slope(0), touches(2), strength(0.5), isBroken(false), isValid(false) {}
};

//+------------------------------------------------------------------+
//| Trendline Detector Class                                         |
//+------------------------------------------------------------------+
class CTrendlineDetector
{
private:
    string              m_symbol;
    ENUM_TIMEFRAMES     m_timeframe;
    
    SSwingPoint         m_swingHighs[];
    SSwingPoint         m_swingLows[];
    int                 m_swingHighCount;
    int                 m_swingLowCount;
    
    STrendline          m_trendlines[];
    int                 m_trendlineCount;
    int                 m_maxTrendlines;
    
    int                 m_swingStrength;
    double              m_tolerancePips;
    
    // Internal methods
    void                FindSwingPoints(int lookback);
    void                FindSupportTrendlines();
    void                FindResistanceTrendlines();
    int                 ValidateTrendline(SSwingPoint &p1, SSwingPoint &p2, double slope, bool isSupport);
    double              CalculateTrendlineStrength(int touches, double slope);
    
public:
                        CTrendlineDetector();
                       ~CTrendlineDetector();
    
    bool                Initialize(const string symbol, ENUM_TIMEFRAMES timeframe,
                                  int swingStrength = 3, double tolerancePips = 10);
    
    void                DetectTrendlines(int lookback = 100);
    void                Update();
    
    // Getters
    int                 GetTrendlineCount() const { return m_trendlineCount; }
    bool                GetTrendline(int index, STrendline &trendline);
    int                 FindActiveTrendlineAtPrice(double price);
    
    // Projection
    double              ProjectTrendline(STrendline &trendline, datetime targetTime);
    
    // Checks
    bool                IsAtTrendline(double price, int &touchedLineIndex);
    bool                IsTrendlineBroken(STrendline &trendline);
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CTrendlineDetector::CTrendlineDetector() :
    m_symbol(""),
    m_timeframe(PERIOD_CURRENT),
    m_swingHighCount(0),
    m_swingLowCount(0),
    m_trendlineCount(0),
    m_maxTrendlines(50),
    m_swingStrength(3),
    m_tolerancePips(10)
{
    ArrayResize(m_swingHighs, 0);
    ArrayResize(m_swingLows, 0);
    ArrayResize(m_trendlines, 0);
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CTrendlineDetector::~CTrendlineDetector()
{
    ArrayFree(m_swingHighs);
    ArrayFree(m_swingLows);
    ArrayFree(m_trendlines);
}

//+------------------------------------------------------------------+
//| Initialize                                                       |
//+------------------------------------------------------------------+
bool CTrendlineDetector::Initialize(const string symbol, ENUM_TIMEFRAMES timeframe,
                                   int swingStrength, double tolerancePips)
{
    m_symbol = symbol;
    m_timeframe = timeframe;
    m_swingStrength = swingStrength;
    m_tolerancePips = tolerancePips;
    
    return true;
}

//+------------------------------------------------------------------+
//| Detect All Trendlines                                            |
//+------------------------------------------------------------------+
void CTrendlineDetector::DetectTrendlines(int lookback)
{
    m_trendlineCount = 0;
    ArrayResize(m_trendlines, 0);
    
    // Find swing points
    FindSwingPoints(lookback);
    
    // Connect swing lows (support trendlines)
    FindSupportTrendlines();
    
    // Connect swing highs (resistance trendlines)
    FindResistanceTrendlines();
}

//+------------------------------------------------------------------+
//| Find Swing Points                                                |
//+------------------------------------------------------------------+
void CTrendlineDetector::FindSwingPoints(int lookback)
{
    m_swingHighCount = 0;
    m_swingLowCount = 0;
    ArrayResize(m_swingHighs, 0);
    ArrayResize(m_swingLows, 0);
    
    double high[], low[];
    datetime time[];
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(time, true);
    
    if(CopyHigh(m_symbol, m_timeframe, 0, lookback, high) <= 0) return;
    if(CopyLow(m_symbol, m_timeframe, 0, lookback, low) <= 0) return;
    if(CopyTime(m_symbol, m_timeframe, 0, lookback, time) <= 0) return;
    
    int str = m_swingStrength;
    
    // Find swing highs
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
            ArrayResize(m_swingHighs, m_swingHighCount + 1);
            m_swingHighs[m_swingHighCount].time = time[i];
            m_swingHighs[m_swingHighCount].price = high[i];
            m_swingHighs[m_swingHighCount].barIndex = i;
            m_swingHighs[m_swingHighCount].isHigh = true;
            m_swingHighCount++;
        }
    }
    
    // Find swing lows
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
            ArrayResize(m_swingLows, m_swingLowCount + 1);
            m_swingLows[m_swingLowCount].time = time[i];
            m_swingLows[m_swingLowCount].price = low[i];
            m_swingLows[m_swingLowCount].barIndex = i;
            m_swingLows[m_swingLowCount].isHigh = false;
            m_swingLowCount++;
        }
    }
}

//+------------------------------------------------------------------+
//| Find Support Trendlines                                          |
//+------------------------------------------------------------------+
void CTrendlineDetector::FindSupportTrendlines()
{
    for(int i = 0; i < m_swingLowCount - 1 && m_trendlineCount < m_maxTrendlines; i++)
    {
        for(int j = i + 1; j < m_swingLowCount && m_trendlineCount < m_maxTrendlines; j++)
        {
            // Check if point2 is higher than point1 (rising trendline)
            if(m_swingLows[j].price <= m_swingLows[i].price)
                continue;
            
            // j is older (higher bar index), i is newer
            if(m_swingLows[j].barIndex <= m_swingLows[i].barIndex)
                continue;
            
            // Calculate slope (price change per bar)
            double timeDiff = (double)(m_swingLows[i].time - m_swingLows[j].time);
            if(timeDiff == 0) continue;
            
            double slope = (m_swingLows[i].price - m_swingLows[j].price) / timeDiff;
            
            // Validate trendline
            int touches = ValidateTrendline(m_swingLows[j], m_swingLows[i], slope, true);
            
            if(touches >= 2)
            {
                ArrayResize(m_trendlines, m_trendlineCount + 1);
                
                m_trendlines[m_trendlineCount].type = TRENDLINE_SUPPORT;
                m_trendlines[m_trendlineCount].point1Time = m_swingLows[j].time;
                m_trendlines[m_trendlineCount].point1Price = m_swingLows[j].price;
                m_trendlines[m_trendlineCount].point2Time = m_swingLows[i].time;
                m_trendlines[m_trendlineCount].point2Price = m_swingLows[i].price;
                m_trendlines[m_trendlineCount].slope = slope;
                m_trendlines[m_trendlineCount].touches = touches;
                m_trendlines[m_trendlineCount].strength = CalculateTrendlineStrength(touches, slope);
                m_trendlines[m_trendlineCount].isValid = true;
                m_trendlineCount++;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Find Resistance Trendlines                                       |
//+------------------------------------------------------------------+
void CTrendlineDetector::FindResistanceTrendlines()
{
    for(int i = 0; i < m_swingHighCount - 1 && m_trendlineCount < m_maxTrendlines; i++)
    {
        for(int j = i + 1; j < m_swingHighCount && m_trendlineCount < m_maxTrendlines; j++)
        {
            // Check if point2 is lower than point1 (falling trendline)
            if(m_swingHighs[j].price >= m_swingHighs[i].price)
                continue;
            
            if(m_swingHighs[j].barIndex <= m_swingHighs[i].barIndex)
                continue;
            
            double timeDiff = (double)(m_swingHighs[i].time - m_swingHighs[j].time);
            if(timeDiff == 0) continue;
            
            double slope = (m_swingHighs[i].price - m_swingHighs[j].price) / timeDiff;
            
            int touches = ValidateTrendline(m_swingHighs[j], m_swingHighs[i], slope, false);
            
            if(touches >= 2)
            {
                ArrayResize(m_trendlines, m_trendlineCount + 1);
                
                m_trendlines[m_trendlineCount].type = TRENDLINE_RESISTANCE;
                m_trendlines[m_trendlineCount].point1Time = m_swingHighs[j].time;
                m_trendlines[m_trendlineCount].point1Price = m_swingHighs[j].price;
                m_trendlines[m_trendlineCount].point2Time = m_swingHighs[i].time;
                m_trendlines[m_trendlineCount].point2Price = m_swingHighs[i].price;
                m_trendlines[m_trendlineCount].slope = slope;
                m_trendlines[m_trendlineCount].touches = touches;
                m_trendlines[m_trendlineCount].strength = CalculateTrendlineStrength(touches, slope);
                m_trendlines[m_trendlineCount].isValid = true;
                m_trendlineCount++;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Validate Trendline                                               |
//+------------------------------------------------------------------+
int CTrendlineDetector::ValidateTrendline(SSwingPoint &p1, SSwingPoint &p2, double slope, bool isSupport)
{
    int touches = 2;
    double tolerance = m_tolerancePips * SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    
    int startBar = p1.barIndex;
    int endBar = p2.barIndex;
    
    for(int i = startBar - 1; i > endBar; i--)
    {
        datetime barTime = iTime(m_symbol, m_timeframe, i);
        double expectedPrice = p1.price + slope * (double)(barTime - p1.time);
        
        double barLow = iLow(m_symbol, m_timeframe, i);
        double barHigh = iHigh(m_symbol, m_timeframe, i);
        
        if(isSupport)
        {
            // Check if low touched trendline
            if(MathAbs(barLow - expectedPrice) < tolerance)
                touches++;
            
            // Check if price went below trendline (break)
            if(barLow < expectedPrice - tolerance * 2)
                return 0;
        }
        else
        {
            // Resistance trendline
            if(MathAbs(barHigh - expectedPrice) < tolerance)
                touches++;
            
            if(barHigh > expectedPrice + tolerance * 2)
                return 0;
        }
    }
    
    return touches;
}

//+------------------------------------------------------------------+
//| Calculate Trendline Strength                                     |
//+------------------------------------------------------------------+
double CTrendlineDetector::CalculateTrendlineStrength(int touches, double slope)
{
    double strength = 0.5;
    
    // More touches = stronger
    strength += (touches - 2) * 0.1;
    
    // Calculate angle from slope
    double slopeAngle = MathArctan(slope * 86400) * 180 / M_PI; // Convert to degrees
    
    // Moderate slope is better (not too steep)
    if(MathAbs(slopeAngle) >= 20 && MathAbs(slopeAngle) <= 60)
        strength += 0.2;
    else if(MathAbs(slopeAngle) > 70)
        strength -= 0.2;
    
    return MathMin(1.0, MathMax(0.3, strength));
}

//+------------------------------------------------------------------+
//| Update                                                           |
//+------------------------------------------------------------------+
void CTrendlineDetector::Update()
{
    DetectTrendlines(300);  // Expanded from 100 for historical memory
}

//+------------------------------------------------------------------+
//| Get Trendline at Index                                           |
//+------------------------------------------------------------------+
bool CTrendlineDetector::GetTrendline(int index, STrendline &trendline)
{
    if(index < 0 || index >= m_trendlineCount)
        return false;
    
    trendline = m_trendlines[index];
    return true;
}

//+------------------------------------------------------------------+
//| Project Trendline to Time                                        |
//+------------------------------------------------------------------+
double CTrendlineDetector::ProjectTrendline(STrendline &trendline, datetime targetTime)
{
    return trendline.point1Price + trendline.slope * (double)(targetTime - trendline.point1Time);
}

//+------------------------------------------------------------------+
//| Check if at Trendline                                            |
//+------------------------------------------------------------------+
bool CTrendlineDetector::IsAtTrendline(double price, int &touchedLineIndex)
{
    double tolerance = m_tolerancePips * SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    datetime localTime = TimeCurrent();
    
    for(int i = 0; i < m_trendlineCount; i++)
    {
        if(m_trendlines[i].isBroken || !m_trendlines[i].isValid)
            continue;
        
        double projectedPrice = ProjectTrendline(m_trendlines[i], localTime);
        
        if(MathAbs(price - projectedPrice) < tolerance)
        {
            touchedLineIndex = i;
            return true;
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Find Active Trendline at Price                                   |
//+------------------------------------------------------------------+
int CTrendlineDetector::FindActiveTrendlineAtPrice(double price)
{
    int idx = -1;
    if(IsAtTrendline(price, idx))
        return idx;
    return -1;
}

//+------------------------------------------------------------------+
//| Check if Trendline is Broken                                     |
//+------------------------------------------------------------------+
bool CTrendlineDetector::IsTrendlineBroken(STrendline &trendline)
{
    if(trendline.isBroken)
        return true;
    
    double tolerance = m_tolerancePips * SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    datetime localTime = TimeCurrent();
    double projectedPrice = ProjectTrendline(trendline, localTime);
    
    double close = iClose(m_symbol, m_timeframe, 0);
    
    if(trendline.type == TRENDLINE_SUPPORT)
    {
        if(close < projectedPrice - tolerance * 2)
        {
            trendline.isBroken = true;
            return true;
        }
    }
    else
    {
        if(close > projectedPrice + tolerance * 2)
        {
            trendline.isBroken = true;
            return true;
        }
    }
    
    return false;
}

#endif // __SR_TRENDLINE_DETECTOR_MQH__
