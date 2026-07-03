//+------------------------------------------------------------------+
//| ImbalanceDetector.mqh                                            |
//| Fair Value Gap / Imbalance Detection for Unified ICT             |
//| Copyright 2025, Multi-Strategy EA                                |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Multi-Strategy EA"
#property version   "2.00"
#property strict

#ifndef UICT_IMBALANCE_DETECTOR_MQH
#define UICT_IMBALANCE_DETECTOR_MQH

//+------------------------------------------------------------------+
//| Imbalance Structure                                              |
//+------------------------------------------------------------------+
struct SImbalance
{
    // --- EXISTING FIELDS (keep unchanged) ---
    datetime time;
    double top;
    double bottom;
    double midpoint;
    bool isBullish;
    ENUM_TIMEFRAMES timeframe;
    int candle1Index;
    int candle2Index;
    int candle3Index;
    double size;
    double sizePct;
    bool hasRebalanced;
    double fillPercent;
    bool isValid;
    double strength;

    // --- NEW FIELDS ---
    double ce;              // Consequent Encroachment level = exact midpoint of gap
    bool isInverse;         // true = this FVG has been violated and flipped (IFVG)
    bool isTested;          // price has returned to this FVG at least once
    int testCount;          // how many times price has touched this FVG
    datetime lastTestedTime;// time of most recent test
    double displacementSize;// ATR multiple of the move that created this FVG (larger = stronger)
    bool createdInKillZone; // was this FVG created during a kill zone session

    SImbalance() : time(0), top(0), bottom(0), midpoint(0), isBullish(false),
                  timeframe(PERIOD_CURRENT), candle1Index(0), candle2Index(0),
                  candle3Index(0), size(0), sizePct(0), hasRebalanced(false),
                  fillPercent(0), isValid(false), strength(0.5),
                  ce(0), isInverse(false), isTested(false), testCount(0),
                  lastTestedTime(0), displacementSize(0), createdInKillZone(false) {}
};

//+------------------------------------------------------------------+
//| Imbalance Detector Class                                         |
//+------------------------------------------------------------------+
class CImbalanceDetector
{
private:
    string              m_symbol;
    ENUM_TIMEFRAMES     m_timeframe;

    SImbalance          m_imbalances[];
    int                 m_imbCount;
    int                 m_maxImbalances;

    double              GetATR(int period);
    double              CalculateImbalanceStrength(SImbalance &imb);

public:
                        CImbalanceDetector();
                       ~CImbalanceDetector();

    bool                Initialize(const string symbol, ENUM_TIMEFRAMES timeframe);
    void                Update();
    void                ScanForImbalances(int lookback = 50);

    // Detection
    bool                DetectBullishImbalance(int startBar, SImbalance &imb);
    bool                DetectBearishImbalance(int startBar, SImbalance &imb);

    // Rebalance & IFVG
    bool                CheckRebalance(SImbalance &imb);
    void                CheckForIFVG();

    // Getters
    int                 GetImbalanceCount() const { return m_imbCount; }
    bool                GetImbalance(int index, SImbalance &imb);
    int                 FindActiveImbalanceAtPrice(double price);
    int                 FindBestBullishImbalance();
    int                 FindBestBearishImbalance();

    // Checks
    bool                HasUnfilledImbalance(bool bullish);
    bool                IsInImbalance(double price);
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CImbalanceDetector::CImbalanceDetector() :
    m_symbol(""),
    m_timeframe(PERIOD_CURRENT),
    m_imbCount(0),
    m_maxImbalances(30)
{
    ArrayResize(m_imbalances, 0);
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CImbalanceDetector::~CImbalanceDetector()
{
    ArrayFree(m_imbalances);
}

//+------------------------------------------------------------------+
//| Initialize                                                       |
//+------------------------------------------------------------------+
bool CImbalanceDetector::Initialize(const string symbol, ENUM_TIMEFRAMES timeframe)
{
    m_symbol = symbol;
    m_timeframe = timeframe;
    m_imbCount = 0;

    return true;
}

//+------------------------------------------------------------------+
//| Update                                                           |
//+------------------------------------------------------------------+
void CImbalanceDetector::Update()
{
    ScanForImbalances(50);

    // Update rebalance status for all imbalances
    for(int i = 0; i < m_imbCount; i++)
    {
        CheckRebalance(m_imbalances[i]);
    }

    // P2-D: Check if any filled FVGs have become IFVGs
    CheckForIFVG();
}

//+------------------------------------------------------------------+
//| Scan For Imbalances                                              |
//+------------------------------------------------------------------+
void CImbalanceDetector::ScanForImbalances(int lookback)
{
    m_imbCount = 0;
    ArrayResize(m_imbalances, 0);

    for(int i = 2; i < lookback - 2 && m_imbCount < m_maxImbalances; i++)
    {
        // Check for bullish imbalance
        SImbalance bullImb;
        if(DetectBullishImbalance(i, bullImb) && bullImb.isValid)
        {
            ArrayResize(m_imbalances, m_imbCount + 1);
            m_imbalances[m_imbCount] = bullImb;
            m_imbCount++;
        }

        // Check for bearish imbalance
        SImbalance bearImb;
        if(DetectBearishImbalance(i, bearImb) && bearImb.isValid)
        {
            ArrayResize(m_imbalances, m_imbCount + 1);
            m_imbalances[m_imbCount] = bearImb;
            m_imbCount++;
        }
    }
}

//+------------------------------------------------------------------+
//| Detect Bullish Imbalance — P0-A Rewrite                         |
//+------------------------------------------------------------------+
// ICT Bullish FVG Rule:
// A gap exists when candle[startBar+1].high < candle[startBar-1].low
// (candle 3 high is below candle 1 low — price never covered that range going up)
// No color requirement. No body size requirement.
// Only the MIDDLE candle (impulse) must be bullish to confirm direction.
bool CImbalanceDetector::DetectBullishImbalance(int startBar, SImbalance &imb)
{
    if(startBar < 1 || startBar + 2 >= iBars(m_symbol, m_timeframe))
        return false;

    // Bar indexing: startBar = middle candle (candle 2 / the impulse)
    // candle1 = startBar - 1 (most recent of the three)
    // candle2 = startBar     (the impulse / middle candle)
    // candle3 = startBar + 1 (oldest of the three)

    double candle1Low  = iLow(m_symbol,  m_timeframe, startBar - 1);
    double candle3High = iHigh(m_symbol, m_timeframe, startBar + 1);

    // The gap is: from candle3High (bottom of gap) to candle1Low (top of gap)
    double gapBottom = candle3High;
    double gapTop    = candle1Low;

    // Must be a real gap (top > bottom)
    if(gapTop <= gapBottom)
        return false;

    double gapSize = gapTop - gapBottom;
    double point   = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    double atr     = GetATR(14);

    // Minimum size filter: gap must be at least 5 points AND at least 5% of ATR
    if(gapSize < 5.0 * point)
        return false;
    if(atr > 0 && gapSize < atr * 0.05)
        return false;

    // Verify the middle candle is bullish (displacement direction must match FVG direction)
    double midOpen  = iOpen(m_symbol,  m_timeframe, startBar);
    double midClose = iClose(m_symbol, m_timeframe, startBar);
    if(midClose <= midOpen)
        return false;  // Middle candle must be bullish for a bullish FVG

    // Calculate displacement size relative to ATR
    double midBody = midClose - midOpen;
    double displacementMult = (atr > 0) ? (midBody / atr) : 0.0;

    // Populate the struct
    imb.time          = iTime(m_symbol, m_timeframe, startBar);
    imb.top           = gapTop;
    imb.bottom        = gapBottom;
    imb.midpoint      = (gapTop + gapBottom) / 2.0;
    imb.ce            = imb.midpoint;  // CE = consequent encroachment = midpoint
    imb.isBullish     = true;
    imb.isInverse     = false;
    imb.isTested      = false;
    imb.testCount     = 0;
    imb.size          = gapSize;
    imb.sizePct       = (atr > 0) ? (gapSize / atr) * 100.0 : 0.0;
    imb.timeframe     = m_timeframe;
    imb.candle1Index  = startBar - 1;
    imb.candle2Index  = startBar;
    imb.candle3Index  = startBar + 1;
    imb.hasRebalanced = false;
    imb.fillPercent   = 0.0;
    imb.isValid       = true;
    imb.displacementSize = displacementMult;
    imb.createdInKillZone = false;  // Set externally if kill zone integration available
    imb.strength      = CalculateImbalanceStrength(imb);

    return true;
}

//+------------------------------------------------------------------+
//| Detect Bearish Imbalance — P0-A Rewrite                         |
//+------------------------------------------------------------------+
// ICT Bearish FVG Rule:
// A gap exists when candle[startBar+1].low > candle[startBar-1].high
// (candle 3 low is above candle 1 high — price never covered that range going down)
bool CImbalanceDetector::DetectBearishImbalance(int startBar, SImbalance &imb)
{
    if(startBar < 1 || startBar + 2 >= iBars(m_symbol, m_timeframe))
        return false;

    double candle1High = iHigh(m_symbol, m_timeframe, startBar - 1);
    double candle3Low  = iLow(m_symbol,  m_timeframe, startBar + 1);

    // The gap is: from candle1High (bottom of gap) to candle3Low (top of gap)
    double gapBottom = candle1High;
    double gapTop    = candle3Low;

    // Must be a real gap
    if(gapTop <= gapBottom)
        return false;

    double gapSize = gapTop - gapBottom;
    double point   = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    double atr     = GetATR(14);

    if(gapSize < 5.0 * point)
        return false;
    if(atr > 0 && gapSize < atr * 0.05)
        return false;

    // Middle candle must be bearish (impulse direction must match FVG direction)
    double midOpen  = iOpen(m_symbol,  m_timeframe, startBar);
    double midClose = iClose(m_symbol, m_timeframe, startBar);
    if(midClose >= midOpen)
        return false;

    double midBody = midOpen - midClose;
    double displacementMult = (atr > 0) ? (midBody / atr) : 0.0;

    imb.time          = iTime(m_symbol, m_timeframe, startBar);
    imb.top           = gapTop;
    imb.bottom        = gapBottom;
    imb.midpoint      = (gapTop + gapBottom) / 2.0;
    imb.ce            = imb.midpoint;
    imb.isBullish     = false;
    imb.isInverse     = false;
    imb.isTested      = false;
    imb.testCount     = 0;
    imb.size          = gapSize;
    imb.sizePct       = (atr > 0) ? (gapSize / atr) * 100.0 : 0.0;
    imb.timeframe     = m_timeframe;
    imb.candle1Index  = startBar - 1;
    imb.candle2Index  = startBar;
    imb.candle3Index  = startBar + 1;
    imb.hasRebalanced = false;
    imb.fillPercent   = 0.0;
    imb.isValid       = true;
    imb.displacementSize = displacementMult;
    imb.createdInKillZone = false;
    imb.strength      = CalculateImbalanceStrength(imb);

    return true;
}

//+------------------------------------------------------------------+
//| Check Rebalance — P0-A Corrected Mitigation Logic               |
//+------------------------------------------------------------------+
// A bullish FVG is mitigated when a candle CLOSES BELOW the FVG's bottom boundary.
// A bearish FVG is mitigated when a candle CLOSES ABOVE the FVG's top boundary.
// A 100% fill (candle body + wick covers entire gap) also counts.
bool CImbalanceDetector::CheckRebalance(SImbalance &imb)
{
    if(imb.hasRebalanced) return true;

    for(int i = 0; i < 100; i++)
    {
        datetime barTime = iTime(m_symbol, m_timeframe, i);
        if(barTime <= imb.time) break;

        double high  = iHigh(m_symbol,  m_timeframe, i);
        double low   = iLow(m_symbol,   m_timeframe, i);
        double close = iClose(m_symbol, m_timeframe, i);

        // Track touch count (price entering the gap zone)
        if(high >= imb.bottom && low <= imb.top)
        {
            if(!imb.isTested)
            {
                imb.isTested = true;
                imb.lastTestedTime = barTime;
            }
            imb.testCount++;
        }

        // Calculate fill percentage for partial fills
        double filledTop    = MathMin(high, imb.top);
        double filledBottom = MathMax(low, imb.bottom);
        double filledRange  = MathMax(0.0, filledTop - filledBottom);
        if(imb.size > 0)
            imb.fillPercent = (filledRange / imb.size) * 100.0;

        // CORRECTED MITIGATION RULE:
        // Bullish FVG mitigated when close < bottom (full break below)
        // Bearish FVG mitigated when close > top (full break above)
        // OR when fillPercent >= 100 (entire gap wicked through)
        if(imb.isBullish)
        {
            if(close < imb.bottom || imb.fillPercent >= 100.0)
            {
                imb.hasRebalanced = true;
                return true;
            }
        }
        else
        {
            if(close > imb.top || imb.fillPercent >= 100.0)
            {
                imb.hasRebalanced = true;
                return true;
            }
        }
    }

    return false;
}

//+------------------------------------------------------------------+
//| Check For IFVG — P2-D                                            |
//+------------------------------------------------------------------+
// An FVG becomes an IFVG when price CLOSES through it fully (hasRebalanced = true)
// and then price returns to the former FVG zone — acting as resistance/support.
void CImbalanceDetector::CheckForIFVG()
{
    for(int i = 0; i < m_imbCount; i++)
    {
        if(m_imbalances[i].isInverse) continue;  // Already classified as IFVG

        // An FVG becomes an IFVG only after it has been rebalanced (filled)
        if(!m_imbalances[i].hasRebalanced) continue;

        // Check: has price returned to the former FVG zone after filling it?
        // If so, the former FVG boundary becomes resistance/support
        double lastPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);

        if(m_imbalances[i].isBullish)
        {
            // Former bullish FVG is now flipped — its TOP becomes resistance
            bool priceBelowFormerTop = (lastPrice < m_imbalances[i].top && lastPrice > m_imbalances[i].bottom * 0.995);
            if(priceBelowFormerTop)
            {
                m_imbalances[i].isInverse = true;
                // The IFVG zone: same coordinates, now acts as resistance (for bearish plays)
            }
        }
        else
        {
            // Former bearish FVG flipped — its BOTTOM becomes support
            bool priceAboveFormerBottom = (lastPrice > m_imbalances[i].bottom && lastPrice < m_imbalances[i].top * 1.005);
            if(priceAboveFormerBottom)
            {
                m_imbalances[i].isInverse = true;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Get ATR                                                          |
//+------------------------------------------------------------------+
double CImbalanceDetector::GetATR(int period)
{
    int handle = iATR(m_symbol, m_timeframe, period);
    if(handle == INVALID_HANDLE) return 0;

    double value[1];
    if(CopyBuffer(handle, 0, 0, 1, value) > 0)
    {
        IndicatorRelease(handle);
        return value[0];
    }

    IndicatorRelease(handle);
    return 0;
}

//+------------------------------------------------------------------+
//| Calculate Imbalance Strength — P0-A Updated Scoring             |
//+------------------------------------------------------------------+
double CImbalanceDetector::CalculateImbalanceStrength(SImbalance &imb)
{
    double strength = 0.40;  // Base (reduced from 0.50 to allow more differentiation)

    // Displacement quality: larger impulse candle = stronger FVG
    if(imb.displacementSize >= 2.0)       strength += 0.20;
    else if(imb.displacementSize >= 1.0)  strength += 0.12;
    else if(imb.displacementSize >= 0.5)  strength += 0.06;

    // Size relative to ATR
    if(imb.sizePct >= 40.0)       strength += 0.15;
    else if(imb.sizePct >= 20.0)  strength += 0.08;
    else if(imb.sizePct >= 10.0)  strength += 0.04;

    // Higher timeframe = stronger
    if(imb.timeframe >= PERIOD_H4)       strength += 0.15;
    else if(imb.timeframe >= PERIOD_H1)  strength += 0.08;

    // Unfilled = stronger
    if(!imb.hasRebalanced)  strength += 0.10;

    // Created in kill zone = stronger
    if(imb.createdInKillZone)  strength += 0.08;

    return MathMin(1.0, strength);
}

//+------------------------------------------------------------------+
//| Get Imbalance                                                    |
//+------------------------------------------------------------------+
bool CImbalanceDetector::GetImbalance(int index, SImbalance &imb)
{
    if(index < 0 || index >= m_imbCount) return false;
    imb = m_imbalances[index];
    return true;
}

//+------------------------------------------------------------------+
//| Find Active Imbalance at Price                                   |
//+------------------------------------------------------------------+
int CImbalanceDetector::FindActiveImbalanceAtPrice(double price)
{
    for(int i = 0; i < m_imbCount; i++)
    {
        if(m_imbalances[i].hasRebalanced) continue;

        if(price >= m_imbalances[i].bottom && price <= m_imbalances[i].top)
        {
            return i;
        }
    }

    return -1;
}

//+------------------------------------------------------------------+
//| Find Best Bullish Imbalance                                      |
//+------------------------------------------------------------------+
int CImbalanceDetector::FindBestBullishImbalance()
{
    int bestIndex = -1;
    double bestStrength = 0;

    for(int i = 0; i < m_imbCount; i++)
    {
        if(m_imbalances[i].hasRebalanced) continue;
        if(!m_imbalances[i].isBullish) continue;

        if(m_imbalances[i].strength > bestStrength)
        {
            bestStrength = m_imbalances[i].strength;
            bestIndex = i;
        }
    }

    return bestIndex;
}

//+------------------------------------------------------------------+
//| Find Best Bearish Imbalance                                      |
//+------------------------------------------------------------------+
int CImbalanceDetector::FindBestBearishImbalance()
{
    int bestIndex = -1;
    double bestStrength = 0;

    for(int i = 0; i < m_imbCount; i++)
    {
        if(m_imbalances[i].hasRebalanced) continue;
        if(m_imbalances[i].isBullish) continue;

        if(m_imbalances[i].strength > bestStrength)
        {
            bestStrength = m_imbalances[i].strength;
            bestIndex = i;
        }
    }

    return bestIndex;
}

//+------------------------------------------------------------------+
//| Has Unfilled Imbalance                                           |
//+------------------------------------------------------------------+
bool CImbalanceDetector::HasUnfilledImbalance(bool bullish)
{
    for(int i = 0; i < m_imbCount; i++)
    {
        if(m_imbalances[i].hasRebalanced) continue;
        if(m_imbalances[i].isBullish == bullish)
            return true;
    }

    return false;
}

//+------------------------------------------------------------------+
//| Is In Imbalance                                                  |
//+------------------------------------------------------------------+
bool CImbalanceDetector::IsInImbalance(double price)
{
    return (FindActiveImbalanceAtPrice(price) >= 0);
}

#endif // __UICT_IMBALANCE_DETECTOR_MQH__
