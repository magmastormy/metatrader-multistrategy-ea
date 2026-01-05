//+------------------------------------------------------------------+
//| FairValueGap.mqh                                                 |
//| Enhanced FVG Detection with Displacement Validation              |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Multi-Strategy EA"
#property version   "2.00"
#property strict

#ifndef __SMC_FAIR_VALUE_GAP_MQH__
#define __SMC_FAIR_VALUE_GAP_MQH__

//+------------------------------------------------------------------+
//| FVG Structure                                                    |
//+------------------------------------------------------------------+
struct SFairValueGap
{
    double      top;
    double      bottom;
    datetime    time;
    int         barIndex;
    bool        isBullish;
    double      size;           // In ATR units
    bool        aligned;        // With order block direction
    int         timeframe;      // Higher TF = more important
    bool        mitigated;      // 50% filled = mitigated
    double      fillPercentage; // How much has been filled
    double      score;
    
    // Confluence
    bool        hasOrderBlock;
    bool        hasLiquiditySweep;
    bool        createdByDisplacement;
    
    // Identification
    string      id;
    
    SFairValueGap() : top(0), bottom(0), time(0), barIndex(0), isBullish(false),
                      size(0), aligned(false), timeframe(0), mitigated(false),
                      fillPercentage(0), score(0), hasOrderBlock(false),
                      hasLiquiditySweep(false), createdByDisplacement(false), id("") {}
};

//+------------------------------------------------------------------+
//| Fair Value Gap Detection Class                                   |
//+------------------------------------------------------------------+
class CSMCFairValueGap
{
private:
    string              m_symbol;
    ENUM_TIMEFRAMES     m_timeframe;
    
    // FVG storage
    SFairValueGap       m_fvgList[];
    int                 m_maxFVGs;
    int                 m_fvgCount;
    
    // Configuration
    double              m_minSizePips;       // Minimum FVG size in pips
    double              m_minSizeATR;        // Minimum FVG size in ATR
    double              m_displacementFactor; // Displacement = X * avg body
    int                 m_maxAge;            // Max age before removal
    
    // Internal methods
    double              GetATR(int period);
    double              GetAvgBodySize(int bars);
    bool                IsDisplacementCandle(int barIndex, double avgBody);
    double              ScoreFVG(const SFairValueGap &fvg);
    void                CheckMitigation();
    
public:
                        CSMCFairValueGap();
                       ~CSMCFairValueGap();
    
    // Initialization
    bool                Initialize(const string symbol, ENUM_TIMEFRAMES timeframe,
                                  double minPips = 5.0, double minATR = 0.3);
    
    // Detection
    void                ScanForFVGs(int scanBars = 50);
    void                UpdateFVGs();
    void                RemoveOldFVGs();
    
    // Getters
    int                 GetFVGCount() const { return m_fvgCount; }
    bool                GetFVGAt(int index, SFairValueGap &fvg);
    bool                GetBestBullishFVG(SFairValueGap &fvg);
    bool                GetBestBearishFVG(SFairValueGap &fvg);
    
    // Zone interaction
    bool                IsPriceAtFVG(double price, SFairValueGap &activeFVG);
    bool                IsPriceInBullishFVG(double price);
    bool                IsPriceInBearishFVG(double price);
    
    // Configuration
    void                SetMinSizePips(double pips) { m_minSizePips = pips; }
    void                SetMinSizeATR(double atr) { m_minSizeATR = atr; }
    void                SetMaxAge(int age) { m_maxAge = age; }
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CSMCFairValueGap::CSMCFairValueGap() :
    m_symbol(""),
    m_timeframe(PERIOD_CURRENT),
    m_maxFVGs(30),
    m_fvgCount(0),
    m_minSizePips(5.0),
    m_minSizeATR(0.3),
    m_displacementFactor(2.0),
    m_maxAge(300)
{
    ArrayResize(m_fvgList, 0);
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CSMCFairValueGap::~CSMCFairValueGap()
{
    ArrayFree(m_fvgList);
}

//+------------------------------------------------------------------+
//| Initialize                                                       |
//+------------------------------------------------------------------+
bool CSMCFairValueGap::Initialize(const string symbol, ENUM_TIMEFRAMES timeframe,
                                  double minPips, double minATR)
{
    m_symbol = symbol;
    m_timeframe = timeframe;
    m_minSizePips = minPips;
    m_minSizeATR = minATR;
    
    ArrayResize(m_fvgList, 0);
    m_fvgCount = 0;
    
    return true;
}

//+------------------------------------------------------------------+
//| Get ATR Value                                                    |
//+------------------------------------------------------------------+
double CSMCFairValueGap::GetATR(int period)
{
    int handle = iATR(m_symbol, m_timeframe, period);
    if(handle == INVALID_HANDLE) return 0;
    
    double atr[];
    ArraySetAsSeries(atr, true);
    if(CopyBuffer(handle, 0, 0, 1, atr) <= 0)
    {
        IndicatorRelease(handle);
        return 0;
    }
    
    IndicatorRelease(handle);
    return atr[0];
}

//+------------------------------------------------------------------+
//| Get Average Body Size                                            |
//+------------------------------------------------------------------+
double CSMCFairValueGap::GetAvgBodySize(int bars)
{
    double sum = 0;
    for(int i = 1; i <= bars; i++)
    {
        sum += MathAbs(iOpen(m_symbol, m_timeframe, i) - iClose(m_symbol, m_timeframe, i));
    }
    return (bars > 0) ? sum / bars : 0;
}

//+------------------------------------------------------------------+
//| Is Displacement Candle                                           |
//+------------------------------------------------------------------+
bool CSMCFairValueGap::IsDisplacementCandle(int barIndex, double avgBody)
{
    double body = MathAbs(iOpen(m_symbol, m_timeframe, barIndex) - 
                         iClose(m_symbol, m_timeframe, barIndex));
    return (body >= m_displacementFactor * avgBody);
}

//+------------------------------------------------------------------+
//| Score FVG                                                        |
//+------------------------------------------------------------------+
double CSMCFairValueGap::ScoreFVG(const SFairValueGap &fvg)
{
    double score = 40.0; // Base score
    
    // Size bonus (larger = better)
    if(fvg.size >= 1.0)
        score += 20.0;
    else if(fvg.size >= 0.5)
        score += 10.0;
    
    // Created by displacement bonus
    if(fvg.createdByDisplacement)
        score += 15.0;
    
    // Confluence bonuses
    if(fvg.hasOrderBlock)
        score += 15.0;
    if(fvg.hasLiquiditySweep)
        score += 10.0;
    
    // Fill percentage penalty (less filled = better)
    if(fvg.fillPercentage > 0.5)
        score -= 20.0;
    else if(fvg.fillPercentage > 0.25)
        score -= 10.0;
    
    // Age penalty
    int age = Bars(m_symbol, m_timeframe, fvg.time, TimeCurrent());
    if(age > 150)
        score -= 10.0;
    else if(age > 75)
        score -= 5.0;
    
    return MathMax(0, MathMin(100, score));
}

//+------------------------------------------------------------------+
//| Check Mitigation                                                 |
//+------------------------------------------------------------------+
void CSMCFairValueGap::CheckMitigation()
{
    for(int i = 0; i < m_fvgCount; i++)
    {
        if(m_fvgList[i].mitigated) continue;
        
        double high = iHigh(m_symbol, m_timeframe, 0);
        double low = iLow(m_symbol, m_timeframe, 0);
        double fvgSize = m_fvgList[i].top - m_fvgList[i].bottom;
        double fvgMid = (m_fvgList[i].top + m_fvgList[i].bottom) / 2.0;
        
        if(m_fvgList[i].isBullish)
        {
            // Bullish FVG: check how much price has dropped into it
            if(low <= m_fvgList[i].top)
            {
                double fillAmount = m_fvgList[i].top - MathMax(low, m_fvgList[i].bottom);
                m_fvgList[i].fillPercentage = fillAmount / fvgSize;
                
                // 50%+ fill = mitigated
                if(m_fvgList[i].fillPercentage >= 0.5)
                    m_fvgList[i].mitigated = true;
            }
        }
        else
        {
            // Bearish FVG: check how much price has risen into it
            if(high >= m_fvgList[i].bottom)
            {
                double fillAmount = MathMin(high, m_fvgList[i].top) - m_fvgList[i].bottom;
                m_fvgList[i].fillPercentage = fillAmount / fvgSize;
                
                if(m_fvgList[i].fillPercentage >= 0.5)
                    m_fvgList[i].mitigated = true;
            }
        }
        
        // Re-score
        m_fvgList[i].score = ScoreFVG(m_fvgList[i]);
    }
}

//+------------------------------------------------------------------+
//| Scan for FVGs                                                    |
//+------------------------------------------------------------------+
void CSMCFairValueGap::ScanForFVGs(int scanBars)
{
    int bars = iBars(m_symbol, m_timeframe);
    if(bars < scanBars) return;
    
    double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    if(point <= 0) point = 0.0001;
    
    double atr = GetATR(14);
    if(atr <= 0) atr = m_minSizePips * point;
    
    double avgBody = GetAvgBodySize(20);
    double minSize = MathMax(m_minSizePips * point, m_minSizeATR * atr);
    
    // 3-candle FVG pattern: A-B-C where B creates the imbalance
    for(int i = 1; i < scanBars - 2; i++)
    {
        double highA = iHigh(m_symbol, m_timeframe, i + 2);
        double lowA = iLow(m_symbol, m_timeframe, i + 2);
        double highB = iHigh(m_symbol, m_timeframe, i + 1);
        double lowB = iLow(m_symbol, m_timeframe, i + 1);
        double highC = iHigh(m_symbol, m_timeframe, i);
        double lowC = iLow(m_symbol, m_timeframe, i);
        
        // Bullish FVG: Low of A > High of C (gap up)
        if(lowA > highC)
        {
            double gapSize = lowA - highC;
            
            if(gapSize >= minSize)
            {
                SFairValueGap fvg;
                fvg.top = lowA;
                fvg.bottom = highC;
                fvg.time = iTime(m_symbol, m_timeframe, i + 1);
                fvg.barIndex = i + 1;
                fvg.isBullish = true;
                fvg.size = (atr > 0) ? gapSize / atr : 0;
                fvg.createdByDisplacement = IsDisplacementCandle(i + 1, avgBody);
                fvg.id = StringFormat("FVG_%d_BULL", (int)fvg.time);
                fvg.score = ScoreFVG(fvg);
                
                // Check for duplicates
                bool exists = false;
                for(int j = 0; j < m_fvgCount; j++)
                {
                    if(m_fvgList[j].time == fvg.time && m_fvgList[j].isBullish == fvg.isBullish)
                    {
                        exists = true;
                        break;
                    }
                }
                
                if(!exists && m_fvgCount < m_maxFVGs)
                {
                    ArrayResize(m_fvgList, m_fvgCount + 1);
                    m_fvgList[m_fvgCount++] = fvg;
                }
            }
        }
        
        // Bearish FVG: High of A < Low of C (gap down)
        if(highA < lowC)
        {
            double gapSize = lowC - highA;
            
            if(gapSize >= minSize)
            {
                SFairValueGap fvg;
                fvg.top = lowC;
                fvg.bottom = highA;
                fvg.time = iTime(m_symbol, m_timeframe, i + 1);
                fvg.barIndex = i + 1;
                fvg.isBullish = false;
                fvg.size = (atr > 0) ? gapSize / atr : 0;
                fvg.createdByDisplacement = IsDisplacementCandle(i + 1, avgBody);
                fvg.id = StringFormat("FVG_%d_BEAR", (int)fvg.time);
                fvg.score = ScoreFVG(fvg);
                
                // Check for duplicates
                bool exists = false;
                for(int j = 0; j < m_fvgCount; j++)
                {
                    if(m_fvgList[j].time == fvg.time && m_fvgList[j].isBullish == fvg.isBullish)
                    {
                        exists = true;
                        break;
                    }
                }
                
                if(!exists && m_fvgCount < m_maxFVGs)
                {
                    ArrayResize(m_fvgList, m_fvgCount + 1);
                    m_fvgList[m_fvgCount++] = fvg;
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Update FVGs                                                      |
//+------------------------------------------------------------------+
void CSMCFairValueGap::UpdateFVGs()
{
    CheckMitigation();
}

//+------------------------------------------------------------------+
//| Remove Old FVGs                                                  |
//+------------------------------------------------------------------+
void CSMCFairValueGap::RemoveOldFVGs()
{
    for(int i = m_fvgCount - 1; i >= 0; i--)
    {
        int age = Bars(m_symbol, m_timeframe, m_fvgList[i].time, TimeCurrent());
        
        if(age > m_maxAge || m_fvgList[i].mitigated)
        {
            // Shift array
            for(int j = i; j < m_fvgCount - 1; j++)
            {
                m_fvgList[j] = m_fvgList[j + 1];
            }
            m_fvgCount--;
        }
    }
    
    ArrayResize(m_fvgList, m_fvgCount);
}

//+------------------------------------------------------------------+
//| Get FVG At Index                                                 |
//+------------------------------------------------------------------+
bool CSMCFairValueGap::GetFVGAt(int index, SFairValueGap &fvg)
{
    if(index < 0 || index >= m_fvgCount) return false;
    fvg = m_fvgList[index];
    return true;
}

//+------------------------------------------------------------------+
//| Get Best Bullish FVG                                             |
//+------------------------------------------------------------------+
bool CSMCFairValueGap::GetBestBullishFVG(SFairValueGap &fvg)
{
    double bestScore = 0;
    int bestIndex = -1;
    
    for(int i = 0; i < m_fvgCount; i++)
    {
        if(m_fvgList[i].isBullish && !m_fvgList[i].mitigated &&
           m_fvgList[i].score > bestScore)
        {
            bestScore = m_fvgList[i].score;
            bestIndex = i;
        }
    }
    
    if(bestIndex >= 0)
    {
        fvg = m_fvgList[bestIndex];
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Get Best Bearish FVG                                             |
//+------------------------------------------------------------------+
bool CSMCFairValueGap::GetBestBearishFVG(SFairValueGap &fvg)
{
    double bestScore = 0;
    int bestIndex = -1;
    
    for(int i = 0; i < m_fvgCount; i++)
    {
        if(!m_fvgList[i].isBullish && !m_fvgList[i].mitigated &&
           m_fvgList[i].score > bestScore)
        {
            bestScore = m_fvgList[i].score;
            bestIndex = i;
        }
    }
    
    if(bestIndex >= 0)
    {
        fvg = m_fvgList[bestIndex];
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Is Price At FVG                                                  |
//+------------------------------------------------------------------+
bool CSMCFairValueGap::IsPriceAtFVG(double price, SFairValueGap &activeFVG)
{
    for(int i = 0; i < m_fvgCount; i++)
    {
        if(m_fvgList[i].mitigated) continue;
        
        if(price >= m_fvgList[i].bottom && price <= m_fvgList[i].top)
        {
            activeFVG = m_fvgList[i];
            return true;
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Is Price In Bullish FVG                                          |
//+------------------------------------------------------------------+
bool CSMCFairValueGap::IsPriceInBullishFVG(double price)
{
    for(int i = 0; i < m_fvgCount; i++)
    {
        if(m_fvgList[i].isBullish && !m_fvgList[i].mitigated &&
           price >= m_fvgList[i].bottom && price <= m_fvgList[i].top)
        {
            return true;
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Is Price In Bearish FVG                                          |
//+------------------------------------------------------------------+
bool CSMCFairValueGap::IsPriceInBearishFVG(double price)
{
    for(int i = 0; i < m_fvgCount; i++)
    {
        if(!m_fvgList[i].isBullish && !m_fvgList[i].mitigated &&
           price >= m_fvgList[i].bottom && price <= m_fvgList[i].top)
        {
            return true;
        }
    }
    return false;
}

#endif // __SMC_FAIR_VALUE_GAP_MQH__
