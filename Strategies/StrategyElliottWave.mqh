//+------------------------------------------------------------------+
//| Elliott Wave Strategy Module                                    |
//+------------------------------------------------------------------+
#ifndef __STRATEGY_ELLIOTTWAVE_MQH__
#define __STRATEGY_ELLIOTTWAVE_MQH__

#include "../Core/Strategy/StrategyBase.mqh"
#include <Arrays/ArrayObj.mqh>
#include <Math/Stat/Math.mqh>

//+------------------------------------------------------------------+
//| Wave Point Class (extends CObject for use with CArrayObj)       |
//+------------------------------------------------------------------+
enum ENUM_WAVE_TYPE
{
    WAVE_TYPE_UNKNOWN = 0,
    WAVE_TYPE_1 = 1,     // Impulse wave 1
    WAVE_TYPE_2 = 2,     // Corrective wave 2
    WAVE_TYPE_3 = 3,     // Impulse wave 3 (typically the strongest)
    WAVE_TYPE_4 = 4,     // Corrective wave 4
    WAVE_TYPE_5 = 5,     // Final impulse wave 5
    WAVE_TYPE_A = 6,     // Corrective wave A
    WAVE_TYPE_B = 7,     // Corrective wave B
    WAVE_TYPE_C = 8      // Corrective wave C
};

class CElliottWavePoint : public CObject
{
public:
    datetime      m_time;        // Time of the wave point
    double        m_price;       // Price level of the wave point
    ENUM_WAVE_TYPE m_waveType;   // Type of wave
    int           m_degree;      // Degree of the wave
    
    CElliottWavePoint() : m_time(0), m_price(0), m_waveType(WAVE_TYPE_UNKNOWN), m_degree(5) {}
    CElliottWavePoint(datetime _time, double _price, ENUM_WAVE_TYPE _type, int _degree) :
        m_time(_time), m_price(_price), m_waveType(_type), m_degree(_degree) {}
};

//+------------------------------------------------------------------+
//| Elliott Wave Analyzer Class                                     |
//+------------------------------------------------------------------+
class CElliottWaveAnalyzer
{
private:
    CArrayObj     m_wavePoints;   // Array of wave points
    int           m_degree;       // Current wave degree
    
public:
    CElliottWaveAnalyzer() : m_degree(5) { m_wavePoints.FreeMode(true); }
    ~CElliottWaveAnalyzer() { m_wavePoints.Clear(); }
    
    // Wave identification methods
    bool IdentifyWaves(const MqlRates &rates[], int count);
    
    // Getters
    int GetWaveCount() const { return m_wavePoints.Total(); }
    CElliottWavePoint* GetWavePoint(int index) { return (CElliottWavePoint*)m_wavePoints.At(index); }
    void Clear() { m_wavePoints.Clear(); }
};

//+------------------------------------------------------------------+
//| Elliott Wave Strategy Class                                     |
//+------------------------------------------------------------------+
class CStrategyElliottWave : public CStrategyBase
{
private:
    CElliottWaveAnalyzer  m_analyzer;      // Elliott Wave analyzer
    int                   m_lookback;       // Number of bars to analyze
    double                m_minWaveSize;    // Minimum wave size in points
    int                   m_minWaveBars;    // Minimum number of bars in a wave
    
    // Helper methods
    bool AnalyzeWaves(const string symbol, const ENUM_TIMEFRAMES timeframe);
    void DrawWaveLabels(const string symbol);
    double CalculateWaveProjection(CElliottWavePoint* wave1, CElliottWavePoint* wave2, double ratio);
    
public:
    CStrategyElliottWave();
    virtual ~CStrategyElliottWave() {}
    
    // IStrategy implementation
    virtual bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeMgr, void* posSizer) override;
    virtual void Deinit() override;
    virtual ENUM_TRADE_SIGNAL GetSignal(double &confidence) override;
    virtual string GetName() const override { return "Elliott Wave Strategy"; }
    virtual ENUM_STRATEGY_TYPE GetType() const override { return STRATEGY_ELLIOTT; }
    
    // Configuration methods
    void SetLookback(int lookback) { m_lookback = lookback; }
    void SetMinWaveSize(double points) { m_minWaveSize = points; }
    void SetMinWaveBars(int bars) { m_minWaveBars = bars; }
};

//+------------------------------------------------------------------+
//| CElliottWaveAnalyzer Implementation                             |
//+------------------------------------------------------------------+
bool CElliottWaveAnalyzer::IdentifyWaves(const MqlRates &rates[], int count)
{
    if (count < 20) // Need at least 20 bars for meaningful wave analysis
        return false;
        
    // Clear previous wave points
    m_wavePoints.Clear();
    
    // Improved swing point detection with filtering
    // We need at least 5 bars to detect a fractal (2 left, 1 middle, 2 right)
    CArrayDouble swingPrices;
    CArrayObj swingPoints;
    swingPoints.FreeMode(true);
    
    for (int i = 2; i < count - 2; i++)
    {
        bool isHigh = rates[i].high > rates[i-1].high && rates[i].high > rates[i-2].high &&
                      rates[i].high > rates[i+1].high && rates[i].high > rates[i+2].high;
                      
        bool isLow = rates[i].low < rates[i-1].low && rates[i].low < rates[i-2].low &&
                     rates[i].low < rates[i+1].low && rates[i].low < rates[i+2].low;
                     
        if (isHigh)
        {
            CElliottWavePoint *point = new CElliottWavePoint(rates[i].time, rates[i].high, WAVE_TYPE_UNKNOWN, m_degree);
            if(point != NULL) swingPoints.Add(point);
        }
        else if (isLow)
        {
            CElliottWavePoint *point = new CElliottWavePoint(rates[i].time, rates[i].low, WAVE_TYPE_UNKNOWN, m_degree);
            if(point != NULL) swingPoints.Add(point);
        }
    }
    
    // Need at least 6 swing points for a 5-wave structure (0-1-2-3-4-5)
    if(swingPoints.Total() < 6)
        return false;
    
    // Try to identify valid 5-wave impulse pattern from recent swings
    // Work backwards from most recent swings
    int total = swingPoints.Total();
    
    for(int startIdx = total - 6; startIdx >= 0; startIdx--)
    {
        // Get 6 consecutive swing points (Wave 0 start, then 1-5)
        CElliottWavePoint *w0 = (CElliottWavePoint*)swingPoints.At(startIdx);
        CElliottWavePoint *w1 = (CElliottWavePoint*)swingPoints.At(startIdx + 1);
        CElliottWavePoint *w2 = (CElliottWavePoint*)swingPoints.At(startIdx + 2);
        CElliottWavePoint *w3 = (CElliottWavePoint*)swingPoints.At(startIdx + 3);
        CElliottWavePoint *w4 = (CElliottWavePoint*)swingPoints.At(startIdx + 4);
        CElliottWavePoint *w5 = (CElliottWavePoint*)swingPoints.At(startIdx + 5);
        
        if(w0 == NULL || w1 == NULL || w2 == NULL || w3 == NULL || w4 == NULL || w5 == NULL)
            continue;
        
        // Determine if bullish or bearish impulse
        bool isBullish = w1.m_price > w0.m_price;
        
        // Elliott Wave Validation Rules:
        // 1. Wave 2 retraces 38.2% - 78.6% of Wave 1 (commonly 50-61.8%)
        // 2. Wave 3 is typically 161.8% of Wave 1, must not be shortest
        // 3. Wave 4 retraces 23.6% - 50% of Wave 3
        // 4. Wave 4 cannot overlap Wave 1 price territory
        
        double wave1Length = MathAbs(w1.m_price - w0.m_price);
        double wave2Retrace = MathAbs(w2.m_price - w1.m_price);
        double wave3Length = MathAbs(w3.m_price - w2.m_price);
        double wave4Retrace = MathAbs(w4.m_price - w3.m_price);
        double wave5Length = MathAbs(w5.m_price - w4.m_price);
        
        // Avoid division by zero
        if(wave1Length == 0 || wave3Length == 0)
            continue;
        
        // Rule 1: Wave 2 retracement (38.2% - 78.6% of Wave 1)
        double w2RetraceRatio = wave2Retrace / wave1Length;
        if(w2RetraceRatio < 0.382 || w2RetraceRatio > 0.786)
            continue;
        
        // Rule 2: Wave 3 cannot be the shortest of 1, 3, 5
        if(wave3Length < wave1Length && wave3Length < wave5Length)
            continue;
        
        // Rule 3: Wave 4 retracement (23.6% - 61.8% of Wave 3)
        double w4RetraceRatio = wave4Retrace / wave3Length;
        if(w4RetraceRatio < 0.236 || w4RetraceRatio > 0.618)
            continue;
        
        // Rule 4: Wave 4 cannot overlap Wave 1 territory
        if(isBullish)
        {
            if(w4.m_price < w1.m_price) continue; // Wave 4 low below Wave 1 high = overlap
        }
        else
        {
            if(w4.m_price > w1.m_price) continue; // Wave 4 high above Wave 1 low = overlap
        }
        
        // Valid wave pattern found! Label the waves
        w1.m_waveType = WAVE_TYPE_1;
        w2.m_waveType = WAVE_TYPE_2;
        w3.m_waveType = WAVE_TYPE_3;
        w4.m_waveType = WAVE_TYPE_4;
        w5.m_waveType = WAVE_TYPE_5;
        
        // Copy valid waves to our main array
        CElliottWavePoint *p1 = new CElliottWavePoint(w1.m_time, w1.m_price, WAVE_TYPE_1, m_degree);
        CElliottWavePoint *p2 = new CElliottWavePoint(w2.m_time, w2.m_price, WAVE_TYPE_2, m_degree);
        CElliottWavePoint *p3 = new CElliottWavePoint(w3.m_time, w3.m_price, WAVE_TYPE_3, m_degree);
        CElliottWavePoint *p4 = new CElliottWavePoint(w4.m_time, w4.m_price, WAVE_TYPE_4, m_degree);
        CElliottWavePoint *p5 = new CElliottWavePoint(w5.m_time, w5.m_price, WAVE_TYPE_5, m_degree);
        
        if(p1) m_wavePoints.Add(p1);
        if(p2) m_wavePoints.Add(p2);
        if(p3) m_wavePoints.Add(p3);
        if(p4) m_wavePoints.Add(p4);
        if(p5) m_wavePoints.Add(p5);
        
        break; // Found valid pattern, stop searching
    }
    
    return (m_wavePoints.Total() >= 5);
}


//+------------------------------------------------------------------+
//| CStrategyElliottWave Implementation                             |
//+------------------------------------------------------------------+
CStrategyElliottWave::CStrategyElliottWave() :
    CStrategyBase("Elliott Wave Strategy", 0),
    m_lookback(100),
    m_minWaveSize(50.0),
    m_minWaveBars(5)
{
}

bool CStrategyElliottWave::Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeMgr, void* posSizer)
{
    if(!CStrategyBase::Init(symbol, timeframe, tradeMgr, posSizer))
        return false;
        
    return true;
}

void CStrategyElliottWave::Deinit()
{
    // Clean up any chart objects
    ObjectsDeleteAll(0, "EW_");
    m_analyzer.Clear();
    CStrategyBase::Deinit();
}

bool CStrategyElliottWave::AnalyzeWaves(const string symbol, const ENUM_TIMEFRAMES timeframe)
{
    // Get price data
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    int copied = CopyRates(symbol, timeframe, 0, m_lookback, rates);
    if (copied < 10) // Need minimum data
        return false;
    
    // Identify waves
    if (!m_analyzer.IdentifyWaves(rates, copied))
        return false;
        
    return true;
}

void CStrategyElliottWave::DrawWaveLabels(const string symbol)
{
    if (symbol != _Symbol)
        return;
        
    // Delete old labels
    ObjectsDeleteAll(0, "EW_");
    
    // Draw wave labels
    for (int i = 0; i < m_analyzer.GetWaveCount(); i++)
    {
        CElliottWavePoint *point = m_analyzer.GetWavePoint(i);
        if (point == NULL) continue;
        
        if(point.m_waveType == WAVE_TYPE_UNKNOWN) continue;
        
        string name = StringFormat("EW_%d_%d", i, (int)point.m_time);
        string text = "?";
        color clr = clrWhite;
        
        switch (point.m_waveType)
        {
            case WAVE_TYPE_1: text = "1"; clr = clrLime; break;
            case WAVE_TYPE_2: text = "2"; clr = clrRed; break;
            case WAVE_TYPE_3: text = "3"; clr = clrLime; break;
            case WAVE_TYPE_4: text = "4"; clr = clrRed; break;
            case WAVE_TYPE_5: text = "5"; clr = clrLime; break;
            case WAVE_TYPE_A: text = "A"; clr = clrRed; break;
            case WAVE_TYPE_B: text = "B"; clr = clrLime; break;
            case WAVE_TYPE_C: text = "C"; clr = clrRed; break;
            default: text = "?"; break;
        }
        
        // Create a label for the wave
        if (ObjectFind(0, name) < 0) {
            ObjectCreate(0, name, OBJ_TEXT, 0, point.m_time, point.m_price);
        }
            
        ObjectSetString(0, name, OBJPROP_TEXT, text);
        ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
        ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 10);
        ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_CENTER);
    }
}

double CStrategyElliottWave::CalculateWaveProjection(CElliottWavePoint* wave1, CElliottWavePoint* wave2, double ratio)
{
    if(wave1 == NULL || wave2 == NULL) return 0.0;
    double priceDiff = wave2.m_price - wave1.m_price;
    return wave2.m_price + (priceDiff * ratio);
}

ENUM_TRADE_SIGNAL CStrategyElliottWave::GetSignal(double &confidence)
{
    if (!IsEnabled() || !m_is_initialized) {
        confidence = 0.0;
        return TRADE_SIGNAL_NONE;
    }
        
    confidence = 0.0;
    
    // Analyze the waves
    if (!AnalyzeWaves(m_symbol, m_timeframe))
        return TRADE_SIGNAL_NONE;
        
    // Draw wave labels on the chart
    if (m_symbol == _Symbol && m_timeframe == _Period)
        DrawWaveLabels(m_symbol);
    
    // Get current price and ATR for dynamic zone calculation
    double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
    double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    if(point <= 0) point = 0.0001;
    
    // Calculate ATR for dynamic zone sizing
    int atrHandle = iATR(m_symbol, m_timeframe, 14);
    double atrValue = 0.0;
    if(atrHandle != INVALID_HANDLE)
    {
        double atrBuffer[];
        ArraySetAsSeries(atrBuffer, true);
        if(CopyBuffer(atrHandle, 0, 0, 1, atrBuffer) > 0)
            atrValue = atrBuffer[0];
        IndicatorRelease(atrHandle);
    }
    
    // Use ATR-based zone, fallback to fixed points if ATR unavailable
    double zoneThreshold = (atrValue > 0) ? atrValue * 0.5 : (50 * point);
    
    int totalWaves = m_analyzer.GetWaveCount();
    if (totalWaves >= 5)
    {
        // Find all labeled waves
        CElliottWavePoint *wave1 = NULL;
        CElliottWavePoint *wave2 = NULL;
        CElliottWavePoint *wave3 = NULL;
        CElliottWavePoint *wave4 = NULL;
        CElliottWavePoint *wave5 = NULL;
        
        for(int i = 0; i < totalWaves; i++) {
            CElliottWavePoint *p = m_analyzer.GetWavePoint(i);
            if(p == NULL) continue;
            if(p.m_waveType == WAVE_TYPE_1) wave1 = p;
            if(p.m_waveType == WAVE_TYPE_2) wave2 = p;
            if(p.m_waveType == WAVE_TYPE_3) wave3 = p;
            if(p.m_waveType == WAVE_TYPE_4) wave4 = p;
            if(p.m_waveType == WAVE_TYPE_5) wave5 = p;
        }
        
        // Determine impulse direction
        bool isBullishImpulse = (wave1 != NULL && wave2 != NULL) ? (wave1.m_price > wave2.m_price ? false : true) : false;
        if(wave3 != NULL && wave4 != NULL)
            isBullishImpulse = wave3.m_price > wave4.m_price;
        
        // Scenario 1: Reversal at end of Wave 5 (Counter-trend)
        if (wave5 != NULL && wave3 != NULL)
        {
            // Check if price is near Wave 5 completion zone (ATR-based)
            if (MathAbs(bid - wave5.m_price) < zoneThreshold)
            {
                // Higher confidence if we have clear W3>W1 structure
                confidence = 0.72;
                return isBullishImpulse ? TRADE_SIGNAL_SELL : TRADE_SIGNAL_BUY;
            }
        }
        
        // Scenario 2: Trading Wave 5 start (at Wave 4 completion)
        if (wave4 != NULL && wave3 != NULL && wave5 == NULL)
        {
            // Check if price is bouncing off Wave 4 level (ATR-based zone)
            if (MathAbs(bid - wave4.m_price) < zoneThreshold)
            {
                confidence = 0.68;
                return isBullishImpulse ? TRADE_SIGNAL_BUY : TRADE_SIGNAL_SELL;
            }
        }
        
        // Scenario 3: Trading Wave 3 start (at Wave 2 completion) - Strongest wave
        if (wave2 != NULL && wave1 != NULL && wave3 == NULL)
        {
            // Wave 3 is typically the strongest - higher confidence entry
            if (MathAbs(bid - wave2.m_price) < zoneThreshold)
            {
                confidence = 0.75; // Higher confidence for W3 entry
                return isBullishImpulse ? TRADE_SIGNAL_BUY : TRADE_SIGNAL_SELL;
            }
        }
    }
    
    return TRADE_SIGNAL_NONE; // No signal
}

#endif // __STRATEGY_ELLIOTTWAVE_MQH__
