//+------------------------------------------------------------------+
//| Fair Value Gap Strategy Module                                  |
//+------------------------------------------------------------------+
#ifndef __STRATEGY_FAIRVALUEGAP_MQH__
#define __STRATEGY_FAIRVALUEGAP_MQH__

#include "../Core/StrategyBase.mqh"
#include <Arrays/ArrayObj.mqh>

// Forward declarations
double NormalizeSignal(double value, double min_val, double max_val);

//+------------------------------------------------------------------+
//| Fair Value Gap Structure                                        |
//+------------------------------------------------------------------+
struct SFairValueGap
{
    datetime time1;         // Start time of the gap
    datetime time2;         // End time of the gap
    double   high;          // High of the gap
    double   low;           // Low of the gap
    bool     isBullish;     // True for bullish FVG, false for bearish
    int      timeframe;     // Timeframe where the FVG was identified
    int      strength;      // Strength of the FVG (1-5)
    bool     isFilled;     // Whether the gap has been filled
    
    // Default constructor
    SFairValueGap() : time1(0), time2(0), high(0), low(0), isBullish(false), 
                     timeframe(0), strength(3), isFilled(false) {}
    
    // Parameterized constructor
    SFairValueGap(datetime _time1, datetime _time2, double _high, double _low, 
                 bool _isBullish, int _timeframe, int _strength = 3) :
        time1(_time1), time2(_time2), high(_high), low(_low), 
        isBullish(_isBullish), timeframe(_timeframe), 
        strength(_strength), isFilled(false) {}
};

//+------------------------------------------------------------------+
//| Fair Value Gap Strategy Class                                   |
//+------------------------------------------------------------------+
class CStrategyFairValueGap : public CStrategyBase
{
private:
    CArrayObj* m_fvgs;         // Array of fair value gaps
    int        m_lookback;     // Number of bars to look back for FVGs
    double     m_minGapSize;   // Minimum size of a gap to consider (in points)
    int        m_maxBarsToFill; // Maximum number of bars to wait for gap to fill
    
    // Helper methods
    bool FindFairValueGaps(const string symbol, const ENUM_TIMEFRAMES timeframe);
    void DrawFVG(const SFairValueGap &fvg, const string symbol, int index);
    bool IsValidFVG(const MqlRates &curr, const MqlRates &prev1, const MqlRates &prev2);
    void CheckAndMarkFilledGaps(const string symbol);
    
public:
    CStrategyFairValueGap(const string name = "Fair Value Gap Strategy", int magic = 0);
    virtual ~CStrategyFairValueGap();
    
    // IStrategy implementation
    virtual bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeMgr, void* posSizer) override;
    virtual void Deinit() override;
    virtual void OnTick() override;
    virtual void OnNewBar(const string symbol, const ENUM_TIMEFRAMES timeframe) override;
    virtual ENUM_TRADE_SIGNAL GetSignal(double &confidence) override;
    virtual string GetName() const override { return m_name; }
    virtual ENUM_STRATEGY_TYPE GetType() const override { return STRATEGY_FAIR_VALUE_GAP; }
    
    // Configuration methods
    void SetLookback(int lookback) { m_lookback = lookback; }
    void SetMinGapSize(double points) { m_minGapSize = points; }
    void SetMaxBarsToFill(int bars) { m_maxBarsToFill = bars; }
    
private:
    double NormalizeSignal(double value, double min_val, double max_val) {
        if (max_val <= min_val) return 0.0;
        double normalized = (value - min_val) / (max_val - min_val);
        return MathMin(1.0, MathMax(0.0, normalized));
    }
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CStrategyFairValueGap::CStrategyFairValueGap(const string name, int magic) :
    CStrategyBase(name, magic),
    m_lookback(50),
    m_minGapSize(5.0),  // 5 pips minimum gap size
    m_maxBarsToFill(20)  // 20 bars maximum to wait for gap fill
{
    m_fvgs = new CArrayObj();
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CStrategyFairValueGap::~CStrategyFairValueGap()
{
    Deinit();
    delete m_fvgs;
}

//+------------------------------------------------------------------+
//| Initialize strategy                                              |
//+------------------------------------------------------------------+
bool CStrategyFairValueGap::Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeMgr, void* posSizer)
{
    if(!CStrategyBase::Init(symbol, timeframe, tradeMgr, posSizer)) return false;
    if(CheckPointer(m_fvgs) != POINTER_INVALID) m_fvgs.Clear();
    return true;
}

//+------------------------------------------------------------------+
//| Deinitialize strategy                                            |
//+------------------------------------------------------------------+
void CStrategyFairValueGap::Deinit()
{
    // Clean up any chart objects
    ObjectsDeleteAll(0, "FVG_");
    if(CheckPointer(m_fvgs) != POINTER_INVALID) m_fvgs.Clear();
    CStrategyBase::Deinit();
}

void CStrategyFairValueGap::OnTick()
{
    static datetime lastBarTime = 0;
    datetime currentTime = iTime(m_symbol, m_timeframe, 0);
    if(currentTime != lastBarTime) {
        lastBarTime = currentTime;
        OnNewBar(m_symbol, m_timeframe);
    }
}

void CStrategyFairValueGap::OnNewBar(const string symbol, const ENUM_TIMEFRAMES timeframe)
{
    // Periodic per-bar maintenance (e.g., update tracked gaps) can be added here
}

//+------------------------------------------------------------------+
//| Check if a valid Fair Value Gap exists between three candles     |
//+------------------------------------------------------------------+
bool CStrategyFairValueGap::IsValidFVG(const MqlRates &curr, const MqlRates &prev1, const MqlRates &prev2)
{
    // Check for bullish FVG (gap up)
    if (curr.low > prev1.high && prev1.low > prev2.high)
    {
        // The gap between prev1 high and current low is the FVG
        double gapSize = (curr.low - prev1.high) / Point();
        return (gapSize >= m_minGapSize);
    }
    // Check for bearish FVG (gap down)
    else if (curr.high < prev1.low && prev1.high < prev2.low)
    {
        // The gap between prev1 low and current high is the FVG
        double gapSize = (prev1.low - curr.high) / Point();
        return (gapSize >= m_minGapSize);
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Find and store Fair Value Gaps in the price history             |
//+------------------------------------------------------------------+
bool CStrategyFairValueGap::FindFairValueGaps(const string symbol, const ENUM_TIMEFRAMES timeframe)
{
    // Clear previous FVGs for this symbol/timeframe
    for (int i = m_fvgs.Total() - 1; i >= 0; i--)
    {
        SFairValueGap *fvg = (SFairValueGap*)m_fvgs.At(i);
        if (fvg && fvg.timeframe == timeframe)
            m_fvgs.Delete(i);
    }
    
    // Get price data (we need 3 more bars than lookback to check for FVGs)
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    int copied = CopyRates(symbol, timeframe, 0, m_lookback + 3, rates);
    if (copied <= 3)  // Need at least 3 bars to identify an FVG
    {
        return false;
    }
    
    // Find Fair Value Gaps
    for (int i = 2; i < copied - 1; i++)
    {
        if (IsValidFVG(rates[i], rates[i-1], rates[i-2]))
        {
            bool isBullish = (rates[i].low > rates[i-1].high);
            double fvgHigh = isBullish ? rates[i-1].high : rates[i-1].low;
            double fvgLow = isBullish ? rates[i].low : rates[i].high;
            
            // Create new FVG
            SFairValueGap *fvg = new SFairValueGap(
                rates[i-1].time,   // Start time (time of candle before the gap)
                rates[i].time,     // End time (time of candle after the gap)
                fvgHigh,           // High of the gap
                fvgLow,             // Low of the gap
                isBullish,          // Direction of the gap
                timeframe,          // Timeframe
                3                   // Default strength
            );
            
            m_fvgs.Add(fvg);
        }
    }
    
    return (m_fvgs.Total() > 0);
}

//+------------------------------------------------------------------+
//| Draw FVG on the chart                                           |
//+------------------------------------------------------------------+
void CStrategyFairValueGap::DrawFVG(const SFairValueGap &fvg, const string symbol, int index)
{
    if (symbol != _Symbol)
        return;
    
    string prefix = fvg.isBullish ? "FVG_Bull_" : "FVG_Bear_";
    string name = prefix + IntegerToString(fvg.timeframe) + "_" + IntegerToString(index);
    
    // Create a rectangle for the FVG
    datetime time1 = fvg.time1;
    datetime time2 = iTime(symbol, fvg.timeframe, 0); // Extend to current bar
    
    if (ObjectFind(0, name) >= 0)
        ObjectDelete(0, name);
    
    if (!ObjectCreate(0, name, OBJ_RECTANGLE, 0, time1, fvg.high, time2, fvg.low))
    {
        return;
    }
    
    // Set object properties
    color clr = fvg.isBullish ? clrDodgerBlue : clrOrangeRed;
    
    ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
    ObjectSetInteger(0, name, OBJPROP_BACK, true);
    ObjectSetInteger(0, name, OBJPROP_FILL, true);
    ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
    ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
    ObjectSetInteger(0, name, OBJPROP_ZORDER, 0);
    
    // Adjust opacity based on whether the gap has been filled
    if (fvg.isFilled)
        ObjectSetInteger(0, name, OBJPROP_COLOR, clrNONE);
}

//+------------------------------------------------------------------+
//| Check and mark filled gaps                                       |
//+------------------------------------------------------------------+
void CStrategyFairValueGap::CheckAndMarkFilledGaps(const string symbol)
{
    if (m_fvgs.Total() == 0)
        return;
        
    // Get current price
    double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
    double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
    
    for (int i = 0; i < m_fvgs.Total(); i++)
    {
        SFairValueGap *fvg = (SFairValueGap*)m_fvgs.At(i);
        if (!fvg || fvg.isFilled)
            continue;
            
        // Check if the gap has been filled
        if ((fvg.isBullish && bid <= fvg.low) ||  // Price came down to fill a bullish FVG
            (!fvg.isBullish && ask >= fvg.high))  // Price went up to fill a bearish FVG
        {
            fvg.isFilled = true;
            
            // Redraw the FVG to show it's been filled
            if (symbol == _Symbol)
                DrawFVG(*fvg, symbol, i);
        }
    }
}

//+------------------------------------------------------------------+
//| Get trading signal                                               |
//+------------------------------------------------------------------+
ENUM_TRADE_SIGNAL CStrategyFairValueGap::GetSignal(double &confidence)
{
    if (!IsEnabled() || !m_is_initialized) {
        confidence = 0.0;
        return TRADE_SIGNAL_NONE;
    }
        
    confidence = 0.0;
    
    // Find Fair Value Gaps
    if (!FindFairValueGaps(m_symbol, m_timeframe))
        return TRADE_SIGNAL_NONE;
    
    // Check for filled gaps
    CheckAndMarkFilledGaps(m_symbol);
    
    // Get current price data
    double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
    double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    
    // Check for trading opportunities based on FVGs
    for (int i = 0; i < m_fvgs.Total(); i++)
    {
        SFairValueGap *fvg = (SFairValueGap*)m_fvgs.At(i);
        if (!fvg || fvg.isFilled || fvg.timeframe != m_timeframe)
            continue;
            
        // Draw all FVGs on the chart
        if (m_symbol == _Symbol && m_timeframe == _Period)
            DrawFVG(*fvg, m_symbol, i);
        
        // Check for entry signals based on FVG interaction
        if (fvg.isBullish)
        {
            // For bullish FVG, look for price to pull back to the gap
            if (bid >= fvg.low && bid <= fvg.high)
            {
                // The closer to the bottom of the gap, the better the entry
                double gapRange = fvg.high - fvg.low;
                double distanceFromBottom = bid - fvg.low;
                double fillRatio = (gapRange > 0) ? (distanceFromBottom / gapRange) : 0.5;
                
                // Higher confidence if price is near the bottom of the gap
                confidence = NormalizeSignal(1.0 - fillRatio, 0.3, 0.9);
                
                // Look for bullish reversal patterns or other confirmation
                MqlRates rates[3];
                if (CopyRates(m_symbol, m_timeframe, 0, 3, rates) == 3)
                {
                    // Check for bullish pin bar or engulfing pattern
                    bool isBullishReversal = 
                        (rates[1].close > rates[1].open && rates[2].close < rates[2].open && 
                         rates[1].close > rates[2].open && rates[1].open < rates[2].close) ||
                        (rates[1].close > rates[1].open && 
                         (rates[1].close - rates[1].open) > 2 * (rates[1].open - rates[1].low));
                    
                    if (isBullishReversal)
                        return TRADE_SIGNAL_BUY;  // Buy signal
                }
            }
        }
        else // Bearish FVG
        {
            // For bearish FVG, look for price to rally back to the gap
            if (ask <= fvg.high && ask >= fvg.low)
            {
                // The closer to the top of the gap, the better the entry
                double gapRange = fvg.high - fvg.low;
                double distanceFromTop = fvg.high - ask;
                double fillRatio = (gapRange > 0) ? (distanceFromTop / gapRange) : 0.5;
                
                // Higher confidence if price is near the top of the gap
                confidence = NormalizeSignal(1.0 - fillRatio, 0.3, 0.9);
                
                // Look for bearish reversal patterns or other confirmation
                MqlRates rates[3];
                if (CopyRates(m_symbol, m_timeframe, 0, 3, rates) == 3)
                {
                    // Check for bearish pin bar or engulfing pattern
                    bool isBearishReversal = 
                        (rates[1].close < rates[1].open && rates[2].close > rates[2].open && 
                         rates[1].close < rates[2].open && rates[1].open > rates[2].close) ||
                        (rates[1].close < rates[1].open && 
                         (rates[1].open - rates[1].close) > 2 * (rates[1].high - rates[1].open));
                    
                    if (isBearishReversal)
                        return TRADE_SIGNAL_SELL;  // Sell signal
                }
            }
        }
    }
    
    return TRADE_SIGNAL_NONE; // No signal
}

#endif // __STRATEGY_FAIRVALUEGAP_MQH__
