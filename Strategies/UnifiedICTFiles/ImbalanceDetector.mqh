//+------------------------------------------------------------------+
//| ImbalanceDetector.mqh                                            |
//| Fair Value Gap / Imbalance Detection for Unified ICT             |
//| Copyright 2025, Multi-Strategy EA                                |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Multi-Strategy EA"
#property version   "1.00"
#property strict

#ifndef __UICT_IMBALANCE_DETECTOR_MQH__
#define __UICT_IMBALANCE_DETECTOR_MQH__

//+------------------------------------------------------------------+
//| Imbalance Structure                                              |
//+------------------------------------------------------------------+
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
    
    SImbalance() : time(0), top(0), bottom(0), midpoint(0), isBullish(false),
                  timeframe(PERIOD_CURRENT), candle1Index(0), candle2Index(0),
                  candle3Index(0), size(0), sizePct(0), hasRebalanced(false),
                  fillPercent(0), isValid(false), strength(0.5) {}
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
    
    // Rebalance
    bool                CheckRebalance(SImbalance &imb);
    
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
    
    // Update rebalance status
    for(int i = 0; i < m_imbCount; i++)
    {
        CheckRebalance(m_imbalances[i]);
    }
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
//| Detect Bullish Imbalance                                         |
//+------------------------------------------------------------------+
bool CImbalanceDetector::DetectBullishImbalance(int startBar, SImbalance &imb)
{
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    
    if(CopyRates(m_symbol, m_timeframe, startBar, 3, rates) != 3)
        return false;
    
    // All 3 candles should be bullish
    bool allBullish = true;
    for(int i = 0; i < 3; i++)
    {
        if(rates[i].close <= rates[i].open)
            allBullish = false;
    }
    
    if(!allBullish) return false;
    
    // Middle candle (candle 2) should be largest
    double body0 = MathAbs(rates[0].close - rates[0].open);
    double body1 = MathAbs(rates[1].close - rates[1].open);
    double body2 = MathAbs(rates[2].close - rates[2].open);
    
    if(body1 <= body0 || body1 <= body2)
        return false;
    
    // Check for gap between candle 3 high and candle 1 low
    double gapTop = rates[0].low;      // Candle 1 (newest) low
    double gapBottom = rates[2].high;  // Candle 3 (oldest) high
    
    if(gapTop <= gapBottom)
        return false; // No gap
    
    double gapSize = gapTop - gapBottom;
    double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    double atr = GetATR(14);
    
    // Validate size
    if(gapSize < 5 * point || (atr > 0 && gapSize < atr * 0.10))
        return false;
    
    imb.time = rates[1].time;
    imb.top = gapTop;
    imb.bottom = gapBottom;
    imb.midpoint = (gapTop + gapBottom) / 2.0;
    imb.isBullish = true;
    imb.size = gapSize;
    imb.sizePct = (atr > 0) ? (gapSize / atr) * 100 : 0;
    imb.timeframe = m_timeframe;
    imb.candle1Index = startBar;
    imb.candle2Index = startBar + 1;
    imb.candle3Index = startBar + 2;
    imb.isValid = true;
    imb.hasRebalanced = false;
    imb.fillPercent = 0;
    imb.strength = CalculateImbalanceStrength(imb);
    
    return true;
}

//+------------------------------------------------------------------+
//| Detect Bearish Imbalance                                         |
//+------------------------------------------------------------------+
bool CImbalanceDetector::DetectBearishImbalance(int startBar, SImbalance &imb)
{
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    
    if(CopyRates(m_symbol, m_timeframe, startBar, 3, rates) != 3)
        return false;
    
    // All 3 candles should be bearish
    bool allBearish = true;
    for(int i = 0; i < 3; i++)
    {
        if(rates[i].close >= rates[i].open)
            allBearish = false;
    }
    
    if(!allBearish) return false;
    
    // Middle candle should be largest
    double body0 = MathAbs(rates[0].close - rates[0].open);
    double body1 = MathAbs(rates[1].close - rates[1].open);
    double body2 = MathAbs(rates[2].close - rates[2].open);
    
    if(body1 <= body0 || body1 <= body2)
        return false;
    
    // Check for gap between candle 3 low and candle 1 high
    double gapTop = rates[2].low;      // Candle 3 (oldest) low
    double gapBottom = rates[0].high;  // Candle 1 (newest) high
    
    if(gapTop <= gapBottom)
        return false;
    
    double gapSize = gapTop - gapBottom;
    double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    double atr = GetATR(14);
    
    if(gapSize < 5 * point || (atr > 0 && gapSize < atr * 0.10))
        return false;
    
    imb.time = rates[1].time;
    imb.top = gapTop;
    imb.bottom = gapBottom;
    imb.size = gapSize;
    imb.isBullish = false;
    imb.hasRebalanced = false;
    imb.midpoint = (gapTop + gapBottom) / 2.0;
    imb.timeframe = m_timeframe;
    imb.candle1Index = startBar;
    imb.candle2Index = startBar + 1;
    imb.candle3Index = startBar + 2;
    imb.isValid = true;
    imb.strength = CalculateImbalanceStrength(imb);
    imb.sizePct = (atr > 0) ? (gapSize / atr) * 100 : 0;
    imb.fillPercent = 0;
    
    return true;
}

//+------------------------------------------------------------------+
//| Check Rebalance                                                  |
//+------------------------------------------------------------------+
bool CImbalanceDetector::CheckRebalance(SImbalance &imb)
{
    if(imb.hasRebalanced) return true;
    
    for(int i = 0; i < 50; i++)
    {
        datetime barTime = iTime(m_symbol, m_timeframe, i);
        if(barTime <= imb.time) break;
        
        double high = iHigh(m_symbol, m_timeframe, i);
        double low = iLow(m_symbol, m_timeframe, i);
        
        // Calculate fill
        double filledTop = MathMin(high, imb.top);
        double filledBottom = MathMax(low, imb.bottom);
        double filledRange = MathMax(0, filledTop - filledBottom);
        
        if(imb.size > 0)
            imb.fillPercent = (filledRange / imb.size) * 100;
        
        if(imb.fillPercent >= 50)
        {
            imb.hasRebalanced = true;
            return true;
        }
    }
    
    return false;
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
//| Calculate Imbalance Strength                                     |
//+------------------------------------------------------------------+
double CImbalanceDetector::CalculateImbalanceStrength(SImbalance &imb)
{
    double strength = 0.50;
    
    // Larger imbalance = stronger
    if(imb.sizePct > 30)
        strength += 0.20;
    else if(imb.sizePct > 20)
        strength += 0.10;
    
    // Higher timeframe = stronger
    if(imb.timeframe >= PERIOD_H4)
        strength += 0.15;
    else if(imb.timeframe >= PERIOD_H1)
        strength += 0.10;
    
    // Unfilled = stronger
    if(!imb.hasRebalanced)
        strength += 0.15;
    
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
