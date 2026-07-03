//+------------------------------------------------------------------+
//| SessionGapDetector.mqh                                           |
//| NDOG (New Day Opening Gap) & NWOG (New Week Opening Gap)        |
//| P2-A: Detects session gaps and tracks fill status               |
//| Copyright 2025, Multi-Strategy EA                                |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Multi-Strategy EA"
#property version   "1.00"
#property strict

#ifndef SESSION_GAP_DETECTOR_MQH
#define SESSION_GAP_DETECTOR_MQH

//+------------------------------------------------------------------+
//| Gap Type Enum                                                    |
//+------------------------------------------------------------------+
enum ENUM_GAP_TYPE
{
    GAP_NONE   = 0,
    GAP_NDOG,       // New Day Opening Gap
    GAP_NWOG        // New Week Opening Gap
};

//+------------------------------------------------------------------+
//| Session Gap Structure                                            |
//+------------------------------------------------------------------+
struct SSessionGap
{
    ENUM_GAP_TYPE   type;
    datetime        openTime;       // When the session opened (new day / new week)
    double          prevClose;      // Close price of the last candle before the gap
    double          openPrice;      // Open price of the first candle after the gap
    double          gapTop;         // Upper boundary of the gap zone
    double          gapBottom;      // Lower boundary of the gap zone
    double          midpoint;       // CE = (gapTop + gapBottom) / 2
    bool            isBullishGap;   // Open > prevClose = gap up (bullish gap)
    bool            isFilled;       // Gap fully filled (price closed back through entire gap)
    bool            isMitigated;    // Price traded to the midpoint at minimum
    double          fillPercent;    // % of gap that has been filled
    double          size;           // Gap size in price
    bool            isValid;        // Minimum size filter passed

    SSessionGap() : type(GAP_NONE), openTime(0), prevClose(0), openPrice(0),
                   gapTop(0), gapBottom(0), midpoint(0), isBullishGap(false),
                   isFilled(false), isMitigated(false), fillPercent(0),
                   size(0), isValid(false) {}
};

//+------------------------------------------------------------------+
//| Session Gap Detector Class                                       |
//+------------------------------------------------------------------+
class CSessionGapDetector
{
private:
    string          m_symbol;
    ENUM_TIMEFRAMES m_timeframe;    // Should be D1 or M1 for gap detection

    SSessionGap     m_ndog;         // Most recent New Day Opening Gap
    SSessionGap     m_nwog;         // Most recent New Week Opening Gap
    SSessionGap     m_history[];    // Historical gaps (for stats)
    int             m_historyCount;

    double          m_minGapSize;   // Minimum gap size to track (ATR multiple)

    // Internal helpers
    bool            DetectNDOG();
    bool            DetectNWOG();
    void            UpdateFillStatus(SSessionGap &gap);
    double          GetATR(int period);
    bool            IsNewDay();
    bool            IsNewWeek();
    int             FindBarAtTime(datetime t);

public:
                    CSessionGapDetector();
                   ~CSessionGapDetector();

    bool            Initialize(const string symbol, ENUM_TIMEFRAMES timeframe = PERIOD_D1);
    void            Update();

    // Gap access
    bool            GetNDOG(SSessionGap &gap);
    bool            GetNWOG(SSessionGap &gap);
    bool            IsInNDOG(double price);
    bool            IsInNWOG(double price);
    bool            IsInAnyGap(double price);

    // Confluence use: is price near an unfilled gap midpoint?
    bool            IsNearGapMidpoint(double price, double tolerancePct = 0.10);

    // Gap counts
    int             GetHistoryCount() const { return m_historyCount; }
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CSessionGapDetector::CSessionGapDetector() :
    m_symbol(""),
    m_timeframe(PERIOD_D1),
    m_historyCount(0),
    m_minGapSize(0.05)  // Min 5% of ATR for gap to be tracked
{
    ArrayResize(m_history, 0);
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CSessionGapDetector::~CSessionGapDetector()
{
    ArrayFree(m_history);
}

//+------------------------------------------------------------------+
//| Initialize                                                       |
//+------------------------------------------------------------------+
bool CSessionGapDetector::Initialize(const string symbol, ENUM_TIMEFRAMES timeframe)
{
    m_symbol    = symbol;
    m_timeframe = timeframe;
    m_historyCount = 0;

    return true;
}

//+------------------------------------------------------------------+
//| Get ATR                                                          |
//+------------------------------------------------------------------+
double CSessionGapDetector::GetATR(int period)
{
    int handle = iATR(m_symbol, m_timeframe, period);
    if(handle == INVALID_HANDLE) return 0;

    double buf[1];
    if(CopyBuffer(handle, 0, 0, 1, buf) > 0)
    {
        IndicatorRelease(handle);
        return buf[0];
    }
    IndicatorRelease(handle);
    return 0;
}

//+------------------------------------------------------------------+
//| Update                                                           |
//+------------------------------------------------------------------+
void CSessionGapDetector::Update()
{
    DetectNDOG();
    DetectNWOG();

    if(m_ndog.isValid) UpdateFillStatus(m_ndog);
    if(m_nwog.isValid) UpdateFillStatus(m_nwog);
}

//+------------------------------------------------------------------+
//| Detect New Day Opening Gap                                       |
//+------------------------------------------------------------------+
// NDOG: Gap between yesterday's close and today's open.
// On daily bars: bar 1 = yesterday, bar 0 = today (if closed) or current day.
// Gap zone: from Min(prevClose, todayOpen) to Max(prevClose, todayOpen).
bool CSessionGapDetector::DetectNDOG()
{
    if(iBars(m_symbol, PERIOD_D1) < 3) return false;

    double prevClose = iClose(m_symbol, PERIOD_D1, 1);
    double todayOpen  = iOpen(m_symbol,  PERIOD_D1, 0);

    double gapSize = MathAbs(todayOpen - prevClose);
    double atr = GetATR(14);
    double minSize = (atr > 0) ? atr * m_minGapSize : SymbolInfoDouble(m_symbol, SYMBOL_POINT) * 5;

    if(gapSize < minSize) return false;

    m_ndog.type          = GAP_NDOG;
    m_ndog.openTime      = iTime(m_symbol, PERIOD_D1, 0);
    m_ndog.prevClose     = prevClose;
    m_ndog.openPrice     = todayOpen;
    m_ndog.isBullishGap  = (todayOpen > prevClose);
    m_ndog.gapTop        = MathMax(prevClose, todayOpen);
    m_ndog.gapBottom     = MathMin(prevClose, todayOpen);
    m_ndog.midpoint      = (m_ndog.gapTop + m_ndog.gapBottom) / 2.0;
    m_ndog.size          = gapSize;
    m_ndog.isFilled      = false;
    m_ndog.isMitigated   = false;
    m_ndog.fillPercent   = 0.0;
    m_ndog.isValid       = true;

    return true;
}

//+------------------------------------------------------------------+
//| Detect New Week Opening Gap                                      |
//+------------------------------------------------------------------+
// NWOG: Gap between Friday's close and Monday's open.
bool CSessionGapDetector::DetectNWOG()
{
    if(iBars(m_symbol, PERIOD_W1) < 3) return false;

    double prevWeekClose = iClose(m_symbol, PERIOD_W1, 1);
    double thisWeekOpen  = iOpen(m_symbol,  PERIOD_W1, 0);

    double gapSize = MathAbs(thisWeekOpen - prevWeekClose);
    double atr = GetATR(14);
    double minSize = (atr > 0) ? atr * m_minGapSize : SymbolInfoDouble(m_symbol, SYMBOL_POINT) * 10;

    if(gapSize < minSize) return false;

    m_nwog.type          = GAP_NWOG;
    m_nwog.openTime      = iTime(m_symbol, PERIOD_W1, 0);
    m_nwog.prevClose     = prevWeekClose;
    m_nwog.openPrice     = thisWeekOpen;
    m_nwog.isBullishGap  = (thisWeekOpen > prevWeekClose);
    m_nwog.gapTop        = MathMax(prevWeekClose, thisWeekOpen);
    m_nwog.gapBottom     = MathMin(prevWeekClose, thisWeekOpen);
    m_nwog.midpoint      = (m_nwog.gapTop + m_nwog.gapBottom) / 2.0;
    m_nwog.size          = gapSize;
    m_nwog.isFilled      = false;
    m_nwog.isMitigated   = false;
    m_nwog.fillPercent   = 0.0;
    m_nwog.isValid       = true;

    return true;
}

//+------------------------------------------------------------------+
//| Update Fill Status                                               |
//+------------------------------------------------------------------+
// Fill: close back THROUGH the entire gap (close past prevClose in gap direction).
// Mitigated: price traded to the midpoint.
void CSessionGapDetector::UpdateFillStatus(SSessionGap &gap)
{
    if(gap.isFilled || !gap.isValid) return;

    // Check last 50 bars (on current timeframe) for fill
    for(int i = 0; i < 50; i++)
    {
        datetime barTime = iTime(m_symbol, m_timeframe, i);
        if(barTime < gap.openTime) break;

        double high  = iHigh(m_symbol,  m_timeframe, i);
        double low   = iLow(m_symbol,   m_timeframe, i);
        double close = iClose(m_symbol, m_timeframe, i);

        double filledTop    = MathMin(high, gap.gapTop);
        double filledBottom = MathMax(low,  gap.gapBottom);
        double filled       = MathMax(0.0, filledTop - filledBottom);

        if(gap.size > 0)
            gap.fillPercent = MathMin(100.0, (filled / gap.size) * 100.0);

        // Mitigated: price reached midpoint
        if(!gap.isMitigated && ((gap.isBullishGap && low <= gap.midpoint) ||
                                (!gap.isBullishGap && high >= gap.midpoint)))
        {
            gap.isMitigated = true;
        }

        // Fully filled: close through the far side
        if(gap.isBullishGap && close < gap.gapBottom)
        {
            gap.isFilled = true;
            break;
        }
        if(!gap.isBullishGap && close > gap.gapTop)
        {
            gap.isFilled = true;
            break;
        }
    }
}

//+------------------------------------------------------------------+
//| Gap Getters                                                      |
//+------------------------------------------------------------------+
bool CSessionGapDetector::GetNDOG(SSessionGap &gap)
{
    if(!m_ndog.isValid) return false;
    gap = m_ndog;
    return true;
}

bool CSessionGapDetector::GetNWOG(SSessionGap &gap)
{
    if(!m_nwog.isValid) return false;
    gap = m_nwog;
    return true;
}

bool CSessionGapDetector::IsInNDOG(double price)
{
    if(!m_ndog.isValid || m_ndog.isFilled) return false;
    return (price >= m_ndog.gapBottom && price <= m_ndog.gapTop);
}

bool CSessionGapDetector::IsInNWOG(double price)
{
    if(!m_nwog.isValid || m_nwog.isFilled) return false;
    return (price >= m_nwog.gapBottom && price <= m_nwog.gapTop);
}

bool CSessionGapDetector::IsInAnyGap(double price)
{
    return IsInNDOG(price) || IsInNWOG(price);
}

//+------------------------------------------------------------------+
//| Is Near Gap Midpoint                                             |
//+------------------------------------------------------------------+
bool CSessionGapDetector::IsNearGapMidpoint(double price, double tolerancePct)
{
    // NDOG check
    if(m_ndog.isValid && !m_ndog.isFilled)
    {
        double tolerance = m_ndog.size * tolerancePct;
        if(MathAbs(price - m_ndog.midpoint) <= tolerance) return true;
    }

    // NWOG check
    if(m_nwog.isValid && !m_nwog.isFilled)
    {
        double tolerance = m_nwog.size * tolerancePct;
        if(MathAbs(price - m_nwog.midpoint) <= tolerance) return true;
    }

    return false;
}

int CSessionGapDetector::FindBarAtTime(datetime t)
{
    for(int i = 0; i < 200; i++)
    {
        if(iTime(m_symbol, m_timeframe, i) <= t) return i;
    }
    return -1;
}

#endif // __SESSION_GAP_DETECTOR_MQH__
