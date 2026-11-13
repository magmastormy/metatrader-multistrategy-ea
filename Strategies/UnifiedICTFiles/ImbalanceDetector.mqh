// Fair Value Gap / Imbalance Detection for Unified ICT
// Copyright 2025, Multi-Strategy EA
#property copyright "Copyright 2025, Multi-Strategy EA"
#property version   "2.00"
#property strict

#ifndef UICT_IMBALANCE_DETECTOR_MQH
#define UICT_IMBALANCE_DETECTOR_MQH

struct SImbalance
{
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

    bool                DetectBullishImbalance(int startBar, SImbalance &imb);
    bool                DetectBearishImbalance(int startBar, SImbalance &imb);

    bool                CheckRebalance(SImbalance &imb);
    void                CheckForIFVG();

    int                 GetImbalanceCount() const { return m_imbCount; }
    bool                GetImbalance(int index, SImbalance &imb);
    int                 FindActiveImbalanceAtPrice(double price);
    int                 FindBestBullishImbalance();
    int                 FindBestBearishImbalance();

    bool                HasUnfilledImbalance(bool bullish);
    bool                IsInImbalance(double price);
};

CImbalanceDetector::CImbalanceDetector() :
    m_symbol(""),
    m_timeframe(PERIOD_CURRENT),
    m_imbCount(0),
    m_maxImbalances(30)
{
    ArrayResize(m_imbalances, 0);
}

CImbalanceDetector::~CImbalanceDetector()
{
    ArrayFree(m_imbalances);
}

bool CImbalanceDetector::Initialize(const string symbol, ENUM_TIMEFRAMES timeframe)
{
    m_symbol = symbol;
    m_timeframe = timeframe;
    m_imbCount = 0;

    return true;
}

void CImbalanceDetector::Update()
{
    ScanForImbalances(50);

    for(int i = 0; i < m_imbCount; i++)
    {
        CheckRebalance(m_imbalances[i]);
    }

    CheckForIFVG();
}

void CImbalanceDetector::ScanForImbalances(int lookback)
{
    m_imbCount = 0;
    ArrayResize(m_imbalances, 0);

    for(int i = 2; i < lookback - 2 && m_imbCount < m_maxImbalances; i++)
    {
        SImbalance bullImb;
        if(DetectBullishImbalance(i, bullImb) && bullImb.isValid)
        {
            ArrayResize(m_imbalances, m_imbCount + 1);
            m_imbalances[m_imbCount] = bullImb;
            m_imbCount++;
        }

        SImbalance bearImb;
        if(DetectBearishImbalance(i, bearImb) && bearImb.isValid)
        {
            ArrayResize(m_imbalances, m_imbCount + 1);
            m_imbalances[m_imbCount] = bearImb;
            m_imbCount++;
        }
    }
}

// Bullish FVG = candle[startBar+1].high < candle[startBar-1].low: the up-move never traded that range back.
// Outer candles carry no colour or body-size rule; only the middle (impulse) candle must be bullish.
bool CImbalanceDetector::DetectBullishImbalance(int startBar, SImbalance &imb)
{
    if(startBar < 1 || startBar + 2 >= iBars(m_symbol, m_timeframe))
        return false;

    // series index: startBar is the impulse candle; candle1 = startBar-1 (newest), candle3 = startBar+1 (oldest)

    double candle1Low  = iLow(m_symbol,  m_timeframe, startBar - 1);
    double candle3High = iHigh(m_symbol, m_timeframe, startBar + 1);

    // bullish gap runs from candle3High (bottom) up to candle1Low (top)
    double gapBottom = candle3High;
    double gapTop    = candle1Low;

    if(gapTop <= gapBottom)
        return false;

    double gapSize = gapTop - gapBottom;
    double point   = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    double atr     = GetATR(14);

    // floors: 5 points always, 5% of ATR only when ATR is available (GetATR returns 0 on failure)
    if(gapSize < 5.0 * point)
        return false;
    if(atr > 0 && gapSize < atr * 0.05)
        return false;

    // impulse direction must match the FVG direction
    double midOpen  = iOpen(m_symbol,  m_timeframe, startBar);
    double midClose = iClose(m_symbol, m_timeframe, startBar);
    if(midClose <= midOpen)
        return false;  // Middle candle must be bullish for a bullish FVG

    double midBody = midClose - midOpen;
    double displacementMult = (atr > 0) ? (midBody / atr) : 0.0;

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

// Bearish FVG = candle[startBar+1].low > candle[startBar-1].high: the down-move never traded that range back.
// Same outer-candle rule as the bullish side: only the middle (impulse) candle must be bearish.
bool CImbalanceDetector::DetectBearishImbalance(int startBar, SImbalance &imb)
{
    if(startBar < 1 || startBar + 2 >= iBars(m_symbol, m_timeframe))
        return false;

    double candle1High = iHigh(m_symbol, m_timeframe, startBar - 1);
    double candle3Low  = iLow(m_symbol,  m_timeframe, startBar + 1);

    // bearish gap runs from candle1High (bottom) up to candle3Low (top)
    double gapBottom = candle1High;
    double gapTop    = candle3Low;

    if(gapTop <= gapBottom)
        return false;

    double gapSize = gapTop - gapBottom;
    double point   = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    double atr     = GetATR(14);

    if(gapSize < 5.0 * point)
        return false;
    if(atr > 0 && gapSize < atr * 0.05)
        return false;

    // impulse direction must match the FVG direction
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

// Mitigation: a bullish FVG is filled when a bar CLOSES below its bottom; a bearish one when a bar closes above its top.
// A 100% wick fill (fillPercent >= 100) counts as filled even without a closing break.
bool CImbalanceDetector::CheckRebalance(SImbalance &imb)
{
    if(imb.hasRebalanced) return true;

    // closed bars only (loop starts at shift 1): intrabar pokes used to latch mitigation off unclosed candles
    for(int i = 1; i < 100; i++)
    {
        datetime barTime = iTime(m_symbol, m_timeframe, i);
        if(barTime <= imb.time) break;

        double high  = iHigh(m_symbol,  m_timeframe, i);
        double low   = iLow(m_symbol,   m_timeframe, i);
        double close = iClose(m_symbol, m_timeframe, i);

        // a test is any bar whose high/low range overlaps the gap
        if(high >= imb.bottom && low <= imb.top)
        {
            if(!imb.isTested)
            {
                imb.isTested = true;
                imb.lastTestedTime = barTime;
            }
            imb.testCount++;
        }

        double filledTop    = MathMin(high, imb.top);
        double filledBottom = MathMax(low, imb.bottom);
        double filledRange  = MathMax(0.0, filledTop - filledBottom);
        if(imb.size > 0)
            imb.fillPercent = MathMax(imb.fillPercent, (filledRange / imb.size) * 100.0);  // keep deepest penetration, not the oldest bar's

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

// IFVG: once price has closed fully through an FVG, returning into the old zone flips it into support/resistance.
void CImbalanceDetector::CheckForIFVG()
{
    for(int i = 0; i < m_imbCount; i++)
    {
        if(m_imbalances[i].isInverse) continue;  // Already classified as IFVG

        if(!m_imbalances[i].hasRebalanced) continue;

        double lastPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);

        if(m_imbalances[i].isBullish)
        {
            // filled bullish FVG: bid back under its top = resistance
            bool priceBelowFormerTop = (lastPrice < m_imbalances[i].top && lastPrice > m_imbalances[i].bottom * 0.995);
            if(priceBelowFormerTop)
            {
                m_imbalances[i].isInverse = true;
            }
        }
        else
        {
            // filled bearish FVG: bid back over its bottom = support
            bool priceAboveFormerBottom = (lastPrice > m_imbalances[i].bottom && lastPrice < m_imbalances[i].top * 1.005);
            if(priceAboveFormerBottom)
            {
                m_imbalances[i].isInverse = true;
            }
        }
    }
}

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

    if(!imb.hasRebalanced)  strength += 0.10;

    if(imb.createdInKillZone)  strength += 0.08;

    return MathMin(1.0, strength);
}

bool CImbalanceDetector::GetImbalance(int index, SImbalance &imb)
{
    if(index < 0 || index >= m_imbCount) return false;
    imb = m_imbalances[index];
    return true;
}

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

bool CImbalanceDetector::IsInImbalance(double price)
{
    return (FindActiveImbalanceAtPrice(price) >= 0);
}

#endif // __UICT_IMBALANCE_DETECTOR_MQH__

