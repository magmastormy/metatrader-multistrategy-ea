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

#include "../../IndicatorManager.mqh"

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

    // Anchor points (at least 2, up to 3 for validation)
    datetime    point1Time;
    double      point1Price;
    datetime    point2Time;
    double      point2Price;

    // Quality metrics
    double      slope;              // Price change per second
    double      slopeDegrees;       // Angle in degrees (for human readability)
    int         touches;            // Confirmed candle touches (close or wick within tolerance)
    int         wickTouches;        // Wick-only touches (less significant)
    int         closeTouches;       // Close-price touches (more significant)
    double      strength;           // 0.0–1.0 composite score
    int         barSpan;            // Number of bars between P1 and P2
    double      minBarSpacing;      // Minimum bars between any two anchor points

    // State
    bool        isValid;
    bool        isBroken;
    bool        isExtended;         // Line has been extended beyond P2
    datetime    breakTime;          // When it broke
    double      breakPrice;         // Price at break
    int         barsSinceLastTouch; // Bars since price last tested this line (recency)

    // ATR context at time of formation
    double      atrAtFormation;     // ATR when trendline was first detected

    STrendline() : type(TRENDLINE_SUPPORT), point1Time(0), point1Price(0),
                  point2Time(0), point2Price(0), slope(0), slopeDegrees(0),
                  touches(2), wickTouches(0), closeTouches(0), strength(0.5),
                  barSpan(0), minBarSpacing(5), isValid(false), isBroken(false),
                  isExtended(false), breakTime(0), breakPrice(0),
                  barsSinceLastTouch(0), atrAtFormation(0) {}
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
    
    // NEW helpers
    double              GetATR(int period = 14);
    bool                IsValidSlopeAngle(double slopeDegrees, bool isSupport);
    int                 CountTouches(SSwingPoint &p1, SSwingPoint &p2, double slope,
                                     bool isSupport, int &wickTouches, int &closeTouches);
    bool                IsLineViable(SSwingPoint &p1, SSwingPoint &p2);
    void                DeduplicateTrendlines();
    void                UpdateBreakStatus();
    void                UpdateRecency();
    int                 FindBestLineIndex(bool isSupport);
    double              NormalizeSlope(double slope);  // converts to degrees
    
    double              CalculateTrendlineStrength(STrendline &tl);
    
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
    
    int                 FindBestSupportLine()    { return FindBestLineIndex(true); }
    int                 FindBestResistanceLine() { return FindBestLineIndex(false); }
    bool                GetBestSupport(STrendline &tl);
    bool                GetBestResistance(STrendline &tl);
    
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
//| Get ATR                                                          |
//+------------------------------------------------------------------+
double CTrendlineDetector::GetATR(int period)
{
    int handle = CIndicatorManager::Instance().GetATRHandle(m_symbol, m_timeframe, period);
    if(handle == INVALID_HANDLE) return 0;

    double atr[];
    ArraySetAsSeries(atr, true);
    double result = 0;
    if(CopyBuffer(handle, 0, 0, 1, atr) > 0)
        result = atr[0];

    return result;
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
    double atr = GetATR(14);
    double minSwingSize = atr * 0.30;
    
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
            // Check that this high is meaningfully above its immediate neighbors
            double neighborAvgHigh = (high[i-1] + high[i+1]) / 2.0;
            if((high[i] - neighborAvgHigh) >= minSwingSize)
            {
                ArrayResize(m_swingHighs, m_swingHighCount + 1);
                m_swingHighs[m_swingHighCount].time = time[i];
                m_swingHighs[m_swingHighCount].price = high[i];
                m_swingHighs[m_swingHighCount].barIndex = i;
                m_swingHighs[m_swingHighCount].isHigh = true;
                m_swingHighCount++;
            }
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
            double neighborAvgLow = (low[i-1] + low[i+1]) / 2.0;
            if((neighborAvgLow - low[i]) >= minSwingSize)
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
    
    // Remove swings that are too close together (< m_swingStrength * 2 bars apart)
    // Keep the highest high / lowest low in each cluster
    for(int i = 0; i < m_swingHighCount - 1; i++)
    {
        for(int j = i + 1; j < m_swingHighCount; j++)
        {
            if(MathAbs(m_swingHighs[i].barIndex - m_swingHighs[j].barIndex) < m_swingStrength * 2)
            {
                if(m_swingHighs[i].price >= m_swingHighs[j].price)
                {
                    for(int k = j; k < m_swingHighCount - 1; k++) m_swingHighs[k] = m_swingHighs[k+1];
                    m_swingHighCount--; j--;
                }
                else
                {
                    m_swingHighs[i] = m_swingHighs[j];
                    for(int k = j; k < m_swingHighCount - 1; k++) m_swingHighs[k] = m_swingHighs[k+1];
                    m_swingHighCount--; j--;
                }
            }
        }
    }
    
    for(int i = 0; i < m_swingLowCount - 1; i++)
    {
        for(int j = i + 1; j < m_swingLowCount; j++)
        {
            if(MathAbs(m_swingLows[i].barIndex - m_swingLows[j].barIndex) < m_swingStrength * 2)
            {
                if(m_swingLows[i].price <= m_swingLows[j].price)
                {
                    for(int k = j; k < m_swingLowCount - 1; k++) m_swingLows[k] = m_swingLows[k+1];
                    m_swingLowCount--; j--;
                }
                else
                {
                    m_swingLows[i] = m_swingLows[j];
                    for(int k = j; k < m_swingLowCount - 1; k++) m_swingLows[k] = m_swingLows[k+1];
                    m_swingLowCount--; j--;
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Helpers                                                          |
//+------------------------------------------------------------------+
bool CTrendlineDetector::IsValidSlopeAngle(double slopeDegrees, bool isSupport)
{
    double absAngle = MathAbs(slopeDegrees);
    if(absAngle < 5.0 || absAngle > 70.0) return false;
    if(isSupport && slopeDegrees <= 0) return false;
    if(!isSupport && slopeDegrees >= 0) return false;
    return true;
}

bool CTrendlineDetector::IsLineViable(SSwingPoint &p1, SSwingPoint &p2)
{
    if(p1.barIndex <= p2.barIndex) return false;
    int span = p1.barIndex - p2.barIndex;
    if(span < 10) return false;
    if(span > 250) return false;
    return true;
}

double CTrendlineDetector::NormalizeSlope(double slope)
{
    int periodSeconds = PeriodSeconds(m_timeframe);
    if(periodSeconds <= 0) return 0;

    double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    if(point <= 0) return 0;

    double slopePipsPerBar = (slope * periodSeconds) / (point * 10.0);
    double angleRad = MathArctan(slopePipsPerBar / 5.0);
    return angleRad * 180.0 / M_PI;
}

//+------------------------------------------------------------------+
//| Find Support Trendlines                                          |
//+------------------------------------------------------------------+
void CTrendlineDetector::FindSupportTrendlines()
{
    double atr = GetATR(14);

    // Outer loop: P1 (older anchor point)
    for(int i = 0; i < m_swingLowCount - 1 && m_trendlineCount < m_maxTrendlines; i++)
    {
        // Inner loop: P2 (newer anchor point, must be more recent than P1)
        for(int j = i + 1; j < m_swingLowCount && m_trendlineCount < m_maxTrendlines; j++)
        {
            SSwingPoint p1 = m_swingLows[i];  // Older (higher bar index)
            SSwingPoint p2 = m_swingLows[j];  // Newer (lower bar index)

            // P1 must be older (higher bar index in series)
            if(p1.barIndex <= p2.barIndex) continue;

            // Minimum and maximum span checks
            if(!IsLineViable(p1, p2)) continue;

            // Calculate slope
            double timeDiff = (double)(p2.time - p1.time);  // positive (p2 is newer)
            if(MathAbs(timeDiff) < 1) continue;

            double slope = (p2.price - p1.price) / timeDiff;

            // Convert to degrees for angle filtering
            double slopeDegrees = NormalizeSlope(slope);

            // ANGLE FILTER: Must be a proper upward-sloping support line
            if(!IsValidSlopeAngle(slopeDegrees, true)) continue;

            // Count touches (this also validates the line isn't broken)
            int wickTouches = 0, closeTouches = 0;
            int totalTouches = CountTouches(p1, p2, slope, true, wickTouches, closeTouches);

            // Require at least 2 anchors + at least 1 additional touch
            // (so minimum 3 total points on the line)
            if(totalTouches < 3) continue;

            // Build the trendline
            STrendline tl;
            tl.type         = TRENDLINE_SUPPORT;
            tl.point1Time   = p1.time;
            tl.point1Price  = p1.price;
            tl.point2Time   = p2.time;
            tl.point2Price  = p2.price;
            tl.slope        = slope;
            tl.slopeDegrees = slopeDegrees;
            tl.touches      = totalTouches;
            tl.wickTouches  = wickTouches;
            tl.closeTouches = closeTouches;
            tl.barSpan      = p1.barIndex - p2.barIndex;
            tl.isValid      = true;
            tl.isBroken     = false;
            tl.atrAtFormation = atr;
            tl.barsSinceLastTouch = p2.barIndex;  // Updated in UpdateRecency()
            tl.strength     = CalculateTrendlineStrength(tl);

            ArrayResize(m_trendlines, m_trendlineCount + 1);
            m_trendlines[m_trendlineCount] = tl;
            m_trendlineCount++;
        }
    }
}

//+------------------------------------------------------------------+
//| Find Resistance Trendlines                                       |
//+------------------------------------------------------------------+
void CTrendlineDetector::FindResistanceTrendlines()
{
    double atr = GetATR(14);

    for(int i = 0; i < m_swingHighCount - 1 && m_trendlineCount < m_maxTrendlines; i++)
    {
        for(int j = i + 1; j < m_swingHighCount && m_trendlineCount < m_maxTrendlines; j++)
        {
            SSwingPoint p1 = m_swingHighs[i];
            SSwingPoint p2 = m_swingHighs[j];

            if(p1.barIndex <= p2.barIndex) continue;
            if(!IsLineViable(p1, p2)) continue;

            double timeDiff = (double)(p2.time - p1.time);
            if(MathAbs(timeDiff) < 1) continue;

            double slope        = (p2.price - p1.price) / timeDiff;
            double slopeDegrees = NormalizeSlope(slope);

            // Resistance line must slope DOWNWARD
            if(!IsValidSlopeAngle(slopeDegrees, false)) continue;

            int wickTouches = 0, closeTouches = 0;
            int totalTouches = CountTouches(p1, p2, slope, false, wickTouches, closeTouches);

            if(totalTouches < 3) continue;

            STrendline tl;
            tl.type         = TRENDLINE_RESISTANCE;
            tl.point1Time   = p1.time;
            tl.point1Price  = p1.price;
            tl.point2Time   = p2.time;
            tl.point2Price  = p2.price;
            tl.slope        = slope;
            tl.slopeDegrees = slopeDegrees;
            tl.touches      = totalTouches;
            tl.wickTouches  = wickTouches;
            tl.closeTouches = closeTouches;
            tl.barSpan      = p1.barIndex - p2.barIndex;
            tl.isValid      = true;
            tl.isBroken     = false;
            tl.atrAtFormation = atr;
            tl.barsSinceLastTouch = p2.barIndex;
            tl.strength     = CalculateTrendlineStrength(tl);

            ArrayResize(m_trendlines, m_trendlineCount + 1);
            m_trendlines[m_trendlineCount] = tl;
            m_trendlineCount++;
        }
    }
}

//+------------------------------------------------------------------+
//| Count Touches and Validate Break                                 |
//+------------------------------------------------------------------+
int CTrendlineDetector::CountTouches(SSwingPoint &p1, SSwingPoint &p2, double slope,
                                      bool isSupport, int &wickTouches, int &closeTouches)
{
    wickTouches  = 0;
    closeTouches = 0;

    double atr       = GetATR(14);
    double point     = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    double tolerance = (atr > 0) ? atr * 0.15 : m_tolerancePips * point;

    // Walk BETWEEN the two anchor points (from P1 bar backward to P2 bar)
    int startBar = p1.barIndex;
    int endBar   = p2.barIndex;

    for(int i = startBar - 1; i > endBar; i--)
    {
        datetime barTime = iTime(m_symbol, m_timeframe, i);
        if(barTime == 0) break;

        // Project the trendline to this bar's time
        double expectedPrice = p1.price + slope * (double)(barTime - p1.time);

        double barLow   = iLow(m_symbol,   m_timeframe, i);
        double barHigh  = iHigh(m_symbol,  m_timeframe, i);
        double barClose = iClose(m_symbol, m_timeframe, i);

        if(isSupport)
        {
            // BREAK CONDITION: Close below the trendline (not a wick)
            // Give 2x tolerance for break to prevent false breaks
            if(barClose < expectedPrice - tolerance * 2.0)
                return 0;  // Line broken — invalid

            // Wick touch: low within tolerance of line
            if(MathAbs(barLow - expectedPrice) <= tolerance)
                wickTouches++;

            // Close touch: close within tolerance (more significant)
            if(MathAbs(barClose - expectedPrice) <= tolerance)
                closeTouches++;
        }
        else  // Resistance
        {
            // BREAK CONDITION: Close above the trendline
            if(barClose > expectedPrice + tolerance * 2.0)
                return 0;  // Broken

            if(MathAbs(barHigh - expectedPrice) <= tolerance)
                wickTouches++;

            if(MathAbs(barClose - expectedPrice) <= tolerance)
                closeTouches++;
        }
    }

    // Also check BEYOND P2 (to the right/more recent side of the chart)
    // The line should continue to hold after P2
    int checkBars = MathMin(20, p2.barIndex - 1);
    for(int i = p2.barIndex - 1; i >= MathMax(0, p2.barIndex - checkBars); i--)
    {
        datetime barTime = iTime(m_symbol, m_timeframe, i);
        if(barTime == 0) break;

        double expectedPrice = p1.price + slope * (double)(barTime - p1.time);
        double barClose = iClose(m_symbol, m_timeframe, i);
        double barLow   = iLow(m_symbol,  m_timeframe, i);
        double barHigh  = iHigh(m_symbol, m_timeframe, i);
        double atrTol   = (atr > 0) ? atr * 0.15 : m_tolerancePips * point;

        if(isSupport)
        {
            // If price has broken strongly below since P2, the line is already stale
            if(barClose < expectedPrice - atrTol * 2.0)
                return 0;

            if(MathAbs(barLow - expectedPrice) <= atrTol)
                wickTouches++;
            if(MathAbs(barClose - expectedPrice) <= atrTol)
                closeTouches++;
        }
        else
        {
            if(barClose > expectedPrice + atrTol * 2.0)
                return 0;

            if(MathAbs(barHigh - expectedPrice) <= atrTol)
                wickTouches++;
            if(MathAbs(barClose - expectedPrice) <= atrTol)
                closeTouches++;
        }
    }

    // Total touches = anchors (2) + intermediate touches
    return 2 + wickTouches + closeTouches;
}

//+------------------------------------------------------------------+
//| Calculate Trendline Strength                                     |
//+------------------------------------------------------------------+
double CTrendlineDetector::CalculateTrendlineStrength(STrendline &tl)
{
    double score = 0.30;  // Base

    // 1. TOUCH COUNT — more touches = more institutional respect (max 25pts)
    int extraTouches = MathMax(0, tl.touches - 2);  // touches beyond the 2 anchors
    score += MathMin(0.25, extraTouches * 0.07);

    // Weight close touches more than wick touches
    score += MathMin(0.10, tl.closeTouches * 0.04);

    // 2. SLOPE ANGLE — optimal range is 20°–45° (max 20pts)
    double absAngle = MathAbs(tl.slopeDegrees);
    if(absAngle >= 20.0 && absAngle <= 45.0)
        score += 0.20;  // Ideal slope
    else if(absAngle >= 10.0 && absAngle <= 60.0)
        score += 0.10;  // Acceptable slope
    else
        score += 0.00;  // Poor slope (still passed angle filter, but gets no bonus)

    // 3. BAR SPAN — longer span means more historical respect (max 15pts)
    if(tl.barSpan >= 80)       score += 0.15;
    else if(tl.barSpan >= 40)  score += 0.10;
    else if(tl.barSpan >= 20)  score += 0.05;

    // 4. RECENCY — line was tested recently (max 10pts)
    if(tl.barsSinceLastTouch <= 5)        score += 0.10;
    else if(tl.barsSinceLastTouch <= 15)  score += 0.05;
    else if(tl.barsSinceLastTouch > 50)   score -= 0.05;  // Stale

    return MathMin(1.0, MathMax(0.10, score));
}

//+------------------------------------------------------------------+
//| Deduplicate Trendlines                                           |
//+------------------------------------------------------------------+
void CTrendlineDetector::DeduplicateTrendlines()
{
    double atr   = GetATR(14);
    double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    double priceTol = (atr > 0) ? atr * 0.3 : 30.0 * point;  // 30% ATR proximity
    double angleTol = 3.0;  // 3° slope tolerance for "same line"

    for(int i = 0; i < m_trendlineCount - 1; i++)
    {
        if(!m_trendlines[i].isValid) continue;

        for(int j = i + 1; j < m_trendlineCount; j++)
        {
            if(!m_trendlines[j].isValid) continue;

            // Same type check
            if(m_trendlines[i].type != m_trendlines[j].type) continue;

            // Similar slope check
            bool sameSlope = MathAbs(m_trendlines[i].slopeDegrees - m_trendlines[j].slopeDegrees) < angleTol;
            if(!sameSlope) continue;

            // Project both lines to current time and check price proximity
            datetime now = TimeCurrent();
            double price_i = ProjectTrendline(m_trendlines[i], now);
            double price_j = ProjectTrendline(m_trendlines[j], now);

            if(MathAbs(price_i - price_j) < priceTol)
            {
                // They're the same line. Keep the stronger one.
                if(m_trendlines[i].strength >= m_trendlines[j].strength)
                    m_trendlines[j].isValid = false;  // Remove j
                else
                    m_trendlines[i].isValid = false;  // Remove i
            }
        }
    }

    // Compact the array: remove all invalid entries
    int newCount = 0;
    for(int i = 0; i < m_trendlineCount; i++)
    {
        if(m_trendlines[i].isValid)
        {
            m_trendlines[newCount] = m_trendlines[i];
            newCount++;
        }
    }
    m_trendlineCount = newCount;
    ArrayResize(m_trendlines, m_trendlineCount);
}

//+------------------------------------------------------------------+
//| Update Break Status                                              |
//+------------------------------------------------------------------+
void CTrendlineDetector::UpdateBreakStatus()
{
    double atr   = GetATR(14);
    double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    double breakTolerance = (atr > 0) ? atr * 0.20 : 15.0 * point;
    datetime now = TimeCurrent();

    for(int i = 0; i < m_trendlineCount; i++)
    {
        if(m_trendlines[i].isBroken) continue;

        double projectedPrice = ProjectTrendline(m_trendlines[i], now);
        double closePrice     = iClose(m_symbol, m_timeframe, 1);  // Use completed bar

        bool isBrokenNow = false;
        if(m_trendlines[i].type == TRENDLINE_SUPPORT)
            isBrokenNow = (closePrice < projectedPrice - breakTolerance);
        else
            isBrokenNow = (closePrice > projectedPrice + breakTolerance);

        if(isBrokenNow)
        {
            m_trendlines[i].isBroken  = true;
            m_trendlines[i].breakTime = iTime(m_symbol, m_timeframe, 1);
            m_trendlines[i].breakPrice = closePrice;
        }
    }
}

//+------------------------------------------------------------------+
//| Update Recency                                                   |
//+------------------------------------------------------------------+
void CTrendlineDetector::UpdateRecency()
{
    double atr   = GetATR(14);
    double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    double touchTolerance = (atr > 0) ? atr * 0.15 : 10.0 * point;

    for(int i = 0; i < m_trendlineCount; i++)
    {
        if(!m_trendlines[i].isValid || m_trendlines[i].isBroken) continue;

        // Count how many bars since the last touch
        int lastTouchBar = 999;
        for(int b = 0; b < 50; b++)
        {
            datetime barTime = iTime(m_symbol, m_timeframe, b);
            double projected = ProjectTrendline(m_trendlines[i], barTime);
            double barLow    = iLow(m_symbol,  m_timeframe, b);
            double barHigh   = iHigh(m_symbol, m_timeframe, b);

            bool touched = false;
            if(m_trendlines[i].type == TRENDLINE_SUPPORT)
                touched = (MathAbs(barLow - projected) <= touchTolerance);
            else
                touched = (MathAbs(barHigh - projected) <= touchTolerance);

            if(touched)
            {
                lastTouchBar = b;
                break;
            }
        }

        m_trendlines[i].barsSinceLastTouch = lastTouchBar;

        // Refresh strength based on updated recency
        m_trendlines[i].strength = CalculateTrendlineStrength(m_trendlines[i]);
    }
}

//+------------------------------------------------------------------+
//| Find Best Line Index                                             |
//+------------------------------------------------------------------+
int CTrendlineDetector::FindBestLineIndex(bool isSupport)
{
    int    bestIdx      = -1;
    double bestStrength = 0.0;

    for(int i = 0; i < m_trendlineCount; i++)
    {
        if(!m_trendlines[i].isValid || m_trendlines[i].isBroken) continue;

        bool typeMatch = (isSupport)
            ? (m_trendlines[i].type == TRENDLINE_SUPPORT)
            : (m_trendlines[i].type == TRENDLINE_RESISTANCE);
        if(!typeMatch) continue;

        if(m_trendlines[i].strength > bestStrength)
        {
            bestStrength = m_trendlines[i].strength;
            bestIdx = i;
        }
    }

    return bestIdx;
}

//+------------------------------------------------------------------+
//| Get Best Support / Resistance                                    |
//+------------------------------------------------------------------+
bool CTrendlineDetector::GetBestSupport(STrendline &tl)
{
    int idx = FindBestSupportLine();
    if(idx < 0) return false;
    tl = m_trendlines[idx];
    return true;
}

bool CTrendlineDetector::GetBestResistance(STrendline &tl)
{
    int idx = FindBestResistanceLine();
    if(idx < 0) return false;
    tl = m_trendlines[idx];
    return true;
}

//+------------------------------------------------------------------+
//| Update                                                           |
//+------------------------------------------------------------------+
void CTrendlineDetector::Update()
{
    // Full re-scan every update
    m_trendlineCount = 0;
    ArrayResize(m_trendlines, 0);

    FindSwingPoints(200);       // Reduced from 300 — use quality over quantity
    FindSupportTrendlines();
    FindResistanceTrendlines();
    DeduplicateTrendlines();    // NEW — remove near-duplicate lines
    UpdateBreakStatus();        // NEW — update break flags using closed bars
    UpdateRecency();            // NEW — update barsSinceLastTouch
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
    // Check cached break flag first
    if(trendline.isBroken) return true;

    double atr   = GetATR(14);
    double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    double tol   = (atr > 0) ? atr * 0.20 : 15.0 * point;

    // Use the completed bar (bar[1]), not the live bar[0]
    double closePrice     = iClose(m_symbol, m_timeframe, 1);
    datetime closedBarTime = iTime(m_symbol, m_timeframe, 1);
    double projectedPrice = ProjectTrendline(trendline, closedBarTime);

    bool broken = false;
    if(trendline.type == TRENDLINE_SUPPORT)
        broken = (closePrice < projectedPrice - tol);
    else
        broken = (closePrice > projectedPrice + tol);

    if(broken)
    {
        trendline.isBroken  = true;
        trendline.breakTime = closedBarTime;
        trendline.breakPrice = closePrice;
    }

    return broken;
}

#endif // __SR_TRENDLINE_DETECTOR_MQH__
