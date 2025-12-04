//+------------------------------------------------------------------+
//| Order Block Strategy Module                                     |
//+------------------------------------------------------------------+
#ifndef __STRATEGY_ORDERBLOCK_MQH__
#define __STRATEGY_ORDERBLOCK_MQH__

#include "../Core/StrategyBase.mqh"
#include <Arrays/ArrayObj.mqh>

// Forward declarations
double NormalizeSignal(double value, double min_val, double max_val);

//+------------------------------------------------------------------+
//| Order Block Class                                                |
//+------------------------------------------------------------------+
class SOrderBlock : public CObject
{
public:
    datetime time;           // Time of the order block
    double   price;          // Price level of the order block
    double   high;           // High of the order block candle
    double   low;            // Low of the order block candle
    bool     isBullish;      // True for bullish order block
    int      timeframe;      // Timeframe where the block was formed
    int      strength;       // Strength of the order block (1-5)
    
    // Default constructor
    SOrderBlock() : time(0), price(0), high(0), low(0), isBullish(false), timeframe(0), strength(3) {}
    
    // Parameterized constructor
    SOrderBlock(datetime _time, double _price, double _high, double _low, bool _isBullish, int _timeframe, int _strength = 3) :
        time(_time), price(_price), high(_high), low(_low), isBullish(_isBullish), timeframe(_timeframe), strength(_strength) {}
};

//+------------------------------------------------------------------+
//| Order Block Strategy Class                                       |
//+------------------------------------------------------------------+
class CStrategyOrderBlock : public CStrategyBase
{
private:
    CArrayObj* m_orderBlocks;     // Array of order blocks
    int        m_lookback;        // Number of bars to look back for order blocks
    int        m_minStrength;     // Minimum strength required for a valid order block
    double     m_deviation;       // Price deviation for order block activation
    
    // Helper methods
    bool FindOrderBlocks(const string symbol, const ENUM_TIMEFRAMES timeframe);
    void DrawOrderBlock(const SOrderBlock &block, const string symbol, int index);
    bool IsValidOrderBlock(const MqlRates &rates[], int index);
    
public:
    CStrategyOrderBlock(const string name = "Order Block Strategy", int magic = 0);
    virtual ~CStrategyOrderBlock();
    
    // IStrategy implementation
    virtual bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeMgr, void* posSizer) override;
    virtual void Deinit() override;
    virtual void OnTick() override;
    virtual void OnNewBar(const string symbol, const ENUM_TIMEFRAMES timeframe) override;
    virtual ENUM_TRADE_SIGNAL GetSignal(double &confidence) override;
    virtual string GetName() const override { return m_name; }
    virtual ENUM_STRATEGY_TYPE GetType() const override { return STRATEGY_ORDER_BLOCK; }
    
    // Configuration methods
    void SetLookback(int lookback) { m_lookback = lookback; }
    void SetMinStrength(int strength) { m_minStrength = strength; }
    void SetDeviation(double deviation) { m_deviation = deviation; }
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CStrategyOrderBlock::CStrategyOrderBlock(const string name, int magic) :
    CStrategyBase(name, magic),
    m_lookback(50),
    m_minStrength(2),
    m_deviation(10 * Point())
{
    m_orderBlocks = new CArrayObj();
    if(m_orderBlocks != NULL) {
        m_orderBlocks.FreeMode(true);
    }
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CStrategyOrderBlock::~CStrategyOrderBlock()
{
    Deinit();
    if(m_orderBlocks != NULL) {
        delete m_orderBlocks;
        m_orderBlocks = NULL;
    }
}

//+------------------------------------------------------------------+
//| Initialize strategy                                              |
//+------------------------------------------------------------------+
bool CStrategyOrderBlock::Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeMgr, void* posSizer)
{
    if(!CStrategyBase::Init(symbol, timeframe, tradeMgr, posSizer)) return false;
    if(CheckPointer(m_orderBlocks) != POINTER_INVALID) m_orderBlocks.Clear();
    return true;
}

//+------------------------------------------------------------------+
//| Deinitialize strategy                                            |
//+------------------------------------------------------------------+
void CStrategyOrderBlock::Deinit()
{
    if(CheckPointer(m_orderBlocks) != POINTER_INVALID) m_orderBlocks.Clear();
    CStrategyBase::Deinit();
}

void CStrategyOrderBlock::OnTick()
{
    static datetime lastBarTime = 0;
    datetime currentTime = iTime(m_symbol, m_timeframe, 0);
    if(currentTime != lastBarTime) {
        lastBarTime = currentTime;
        OnNewBar(m_symbol, m_timeframe);
    }
}

void CStrategyOrderBlock::OnNewBar(const string symbol, const ENUM_TIMEFRAMES timeframe)
{
    // No periodic work beyond GetSignal; placeholder for future per-bar updates
}

//+------------------------------------------------------------------+
//| Check if a candle is a valid order block                        |
//+------------------------------------------------------------------+
bool CStrategyOrderBlock::IsValidOrderBlock(const MqlRates &rates[], int index)
{
    if (index < 2 || index >= ArraySize(rates) - 1)
        return false;
        
    MqlRates current = rates[index];
    MqlRates next = rates[index + 1];
    
    // Check for bullish order block (bearish candle followed by bullish candle)
    if (current.close < current.open && next.close > next.open)
    {
        // The current candle is bearish and the next is bullish
        // Check if the current candle's range is not too small
        if ((current.high - current.low) > (current.close - current.open) * 2)
            return true;
    }
    // Check for bearish order block (bullish candle followed by bearish candle)
    else if (current.close > current.open && next.close < next.open)
    {
        // The current candle is bullish and the next is bearish
        // Check if the current candle's range is not too small
        if ((current.high - current.low) > (current.open - current.close) * 2)
            return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Find and store order blocks in the price history                |
//+------------------------------------------------------------------+
bool CStrategyOrderBlock::FindOrderBlocks(const string symbol, const ENUM_TIMEFRAMES timeframe)
{
    // Clear previous order blocks for this symbol/timeframe
    for (int i = m_orderBlocks.Total() - 1; i >= 0; i--)
    {
        SOrderBlock *block = (SOrderBlock*)m_orderBlocks.At(i);
        if (block != NULL && block.timeframe == timeframe)
            m_orderBlocks.Delete(i);
    }
    
    // Get price data
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    int copied = CopyRates(symbol, timeframe, 0, m_lookback, rates);
    if (copied <= 0)
    {
        return false;
    }
    
    // Find order blocks
    for (int i = 1; i < copied - 1; i++)
    {
        if (IsValidOrderBlock(rates, i))
        {
            bool isBullish = rates[i].close < rates[i].open;
            double price = isBullish ? rates[i].low : rates[i].high;
            
            // Create new order block
            SOrderBlock *block = new SOrderBlock(
                rates[i].time,
                price,
                rates[i].high,
                rates[i].low,
                isBullish,
                timeframe,
                3 // Default strength
            );
            
            m_orderBlocks.Add(block);
        }
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Draw order block on the chart                                    |
//+------------------------------------------------------------------+
void CStrategyOrderBlock::DrawOrderBlock(const SOrderBlock &block, const string symbol, int index)
{
    if (symbol != _Symbol)
        return;
        
    string name = StringFormat("OB_%d_%d", block.timeframe, index);
    
    // Create a rectangle for the order block
    datetime time1 = iTime(symbol, (ENUM_TIMEFRAMES)block.timeframe, 1);
    datetime time2 = iTime(symbol, (ENUM_TIMEFRAMES)block.timeframe, 0);
    
    if (ObjectFind(0, name) >= 0)
        ObjectDelete(0, name);
    
    if (!ObjectCreate(0, name, OBJ_RECTANGLE, 0, time1, block.high, time2, block.low))
    {
        return;
    }
    
    // Set object properties
    color clr = block.isBullish ? clrDodgerBlue : clrOrangeRed;
    
    ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
    ObjectSetInteger(0, name, OBJPROP_BACK, true);
    ObjectSetInteger(0, name, OBJPROP_FILL, true);
    ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
    ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
    ObjectSetInteger(0, name, OBJPROP_ZORDER, 0);
}

//+------------------------------------------------------------------+
//| Get trading signal                                               |
//+------------------------------------------------------------------
ENUM_TRADE_SIGNAL CStrategyOrderBlock::GetSignal(double &confidence)
{
    if (!IsEnabled() || !m_is_initialized) {
        confidence = 0.0;
        return TRADE_SIGNAL_NONE;
    }
        
    confidence = 0.0;
    
    // Find order blocks for this symbol/timeframe
    if (!FindOrderBlocks(m_symbol, m_timeframe))
        return TRADE_SIGNAL_NONE;
    
    // Get current price
    double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
    double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    if(point == 0) point = 0.0001;
    
    // Check for order block activations
    for (int i = 0; i < m_orderBlocks.Total(); i++)
    {
        SOrderBlock *block = (SOrderBlock*)m_orderBlocks.At(i);
        if (!block)
            continue;
            
        // Create local variables to simplify pointer access and debug errors
        int blockTimeframe = block.timeframe;
        bool blockIsBullish = block.isBullish;
        double blockHigh = block.high;
        double blockLow = block.low;
        double blockPrice = block.price;

        // Only check blocks for the current timeframe
        if (blockTimeframe != m_timeframe)
            continue;
            
        // Draw all order blocks on the chart
        if (m_symbol == _Symbol && m_timeframe == _Period)
            DrawOrderBlock(*block, m_symbol, i);
        
        // Check for activation of bullish order block (price retests from above)
        if (blockIsBullish && 
            bid >= (blockLow - m_deviation) && 
            bid <= (blockHigh + m_deviation))
        {
            // The closer to the order block, the higher the confidence
            double dist = MathAbs(bid - blockPrice) / point;
            confidence = (50.0 - dist) / 50.0;
            if(confidence < 0) confidence = 0;
            if(confidence > 1) confidence = 1;
            return TRADE_SIGNAL_BUY;
        }
        // Check for activation of bearish order block (price retests from below)
        else if (!blockIsBullish && 
                 ask <= (blockHigh + m_deviation) && 
                 ask >= (blockLow - m_deviation))
        {
            // The closer to the order block, the higher the confidence
            double dist = MathAbs(ask - blockPrice) / point;
            confidence = (50.0 - dist) / 50.0;
            if(confidence < 0) confidence = 0;
            if(confidence > 1) confidence = 1;
            return TRADE_SIGNAL_SELL;
        }
    }
    
    return TRADE_SIGNAL_NONE;
}

#endif // __STRATEGY_ORDERBLOCK_MQH__
