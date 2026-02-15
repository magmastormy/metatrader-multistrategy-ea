//+------------------------------------------------------------------+
//| Breakout Trading Strategy                                        |
//| Donchian Channel (20-bar) breakout                               |
//+------------------------------------------------------------------+
#ifndef _STRATEGY_BREAKOUT_MQH_
#define _STRATEGY_BREAKOUT_MQH_

#include "../Core/Strategy/StrategyBase.mqh"
#include <Trade/Trade.mqh>

class CStrategyBreakout : public CStrategyBase
{
private:
    int m_donchian_period;  // Donchian Channel period
    
public:
    //--- Constructor/Destructor
    CStrategyBreakout(const string name = "Breakout Strategy", int magic = 0) : 
        CStrategyBase(name, magic),
        m_donchian_period(20) {}
        
    ~CStrategyBreakout() {}
    
    //--- Initialization
    bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeMgr, void* posSizer) override
    {
        return CStrategyBase::Init(symbol, timeframe, tradeMgr, posSizer);
    }
    
    //--- Override method from base class
    virtual ENUM_TRADE_SIGNAL GetSignal(double &confidence) override
    {
        if(!IsEnabled() || !m_is_initialized) {
            confidence = 0.0;
            return TRADE_SIGNAL_NONE;
        }

        // Use iHighest and iLowest for efficiency
        // Use closed-bar confirmation:
        // signal bar = shift 1, comparison window = shifts 2..(period+1)
        int highestIndex = iHighest(m_symbol, m_timeframe, MODE_HIGH, m_donchian_period, 2);
        int lowestIndex = iLowest(m_symbol, m_timeframe, MODE_LOW, m_donchian_period, 2);
        
        if(highestIndex == -1 || lowestIndex == -1) {
            confidence = 0.0;
            return TRADE_SIGNAL_NONE;
        }

        double highest = iHigh(m_symbol, m_timeframe, highestIndex);
        double lowest = iLow(m_symbol, m_timeframe, lowestIndex);
        double price = iClose(m_symbol, m_timeframe, 1);
        
        ENUM_TRADE_SIGNAL signal = TRADE_SIGNAL_NONE;
        confidence = 0.0;
        
        if(price > highest)
        {
            signal = TRADE_SIGNAL_BUY;
            // Calculate confidence based on breakout strength
            double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
            double breakoutMagnitude = (point > 0.0) ? (price - highest) / point : 0.0;
            confidence = MathMin(1.0, breakoutMagnitude / 100.0); // Normalize: 100 points = 100% confidence
            confidence = MathMax(0.5, confidence); // Minimum confidence for a breakout
        }
        else if(price < lowest)
        {
            signal = TRADE_SIGNAL_SELL;
            double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
            double breakoutMagnitude = (point > 0.0) ? (lowest - price) / point : 0.0;
            confidence = MathMin(1.0, breakoutMagnitude / 100.0);
            confidence = MathMax(0.5, confidence);
        }
        
        if(signal != TRADE_SIGNAL_NONE) {
            RecordSignal();
        }
        
        return signal;
    }

    virtual ENUM_STRATEGY_TYPE GetType() const override { return STRATEGY_BREAKOUT; }
};

// Factory function for creating Breakout strategy
CStrategyBase* CreateBreakoutStrategy(const string name = "Breakout Strategy", int magic = 0)
{
    return new CStrategyBreakout(name, magic);
}

#endif //_STRATEGY_BREAKOUT_MQH_
