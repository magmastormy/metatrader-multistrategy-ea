#ifndef __STRATEGY_VOLATILITY_MQH__
#define __STRATEGY_VOLATILITY_MQH__

#include "../Core/Strategy/StrategyBase.mqh"
#include <Indicators/Trend.mqh>

//+------------------------------------------------------------------+
//| Volatility Breakout Strategy                                     |
//| Uses ATR(14) to detect volatility breakouts                      |
//+------------------------------------------------------------------+
class CStrategyVolatility : public CStrategyBase
{
private:
    int m_atr_period;     // ATR period
    double m_atr_multiplier;  // ATR multiplier for stop loss/take profit
    int m_atr_handle;     // ATR indicator handle
    double m_confidence;  // Last calculated confidence level

public:
    //--- Constructor/Destructor
    CStrategyVolatility(const string name = "Volatility Strategy", int magic = 0) :
        CStrategyBase(name, magic),
        m_atr_period(14),
        m_atr_multiplier(2.0),
        m_atr_handle(INVALID_HANDLE),
        m_confidence(0.0) {}
        
    ~CStrategyVolatility() 
    { 
        if(m_atr_handle != INVALID_HANDLE) 
            IndicatorRelease(m_atr_handle); 
    }
    
    //--- Initialization
    virtual bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeMgr, void* posSizer) override
    {
        if(!CStrategyBase::Init(symbol, timeframe, tradeMgr, posSizer))
            return false;
            
        // Initialize ATR indicator
        m_atr_handle = iATR(m_symbol, m_timeframe, m_atr_period);
        if(m_atr_handle == INVALID_HANDLE)
        {
            Print("Failed to create ATR indicator");
            return false;
        }
        return true;
    }
    
    //--- Deinitialization
    virtual void Deinit() override
    {
        if(m_atr_handle != INVALID_HANDLE) 
            IndicatorRelease(m_atr_handle);
        CStrategyBase::Deinit();
    }
    
    //--- Override method from base class
    virtual ENUM_TRADE_SIGNAL GetSignal(double &confidence) override
    {
        if(!IsEnabled() || !m_is_initialized) {
            confidence = 0.0;
            return TRADE_SIGNAL_NONE;
        }
            
        double signalValue = GetSignalValue(m_symbol, m_timeframe, confidence);
        
        if(signalValue > 0.5)
            return TRADE_SIGNAL_BUY;
        else if(signalValue < -0.5)
            return TRADE_SIGNAL_SELL;
        else
            return TRADE_SIGNAL_NONE;
    }
    
    virtual ENUM_STRATEGY_TYPE GetType() const override { return STRATEGY_VOLATILITY; }
    
    //--- Get trading signal value (used for strategy scoring)
    double GetSignalValue(const string symbol, const ENUM_TIMEFRAMES timeframe, double &confidence)
    {
        double atr[1];
        int atr_handle = m_atr_handle;
        if(atr_handle == INVALID_HANDLE)
            atr_handle = iATR(symbol, timeframe, m_atr_period);
        if(CopyBuffer(atr_handle, 0, 0, 1, atr) != 1)
        {
            confidence = 0.0;
            return 0.0;
        }
        double close = iClose(symbol, timeframe, 0);
        double prev_close = iClose(symbol, timeframe, 1);
        double atr_value = atr[0];
        double price_change = MathAbs(close - prev_close);
        confidence = MathMin(price_change / (atr_value * 0.5), 1.0);
        if(price_change > atr_value * 1.5)
        {
            return (close > prev_close) ? 1.0 : -1.0;
        }
        return 0.0;
    }
    
    //--- Calculate confidence level (0.0 to 1.0)
    double CalculateConfidence()
    {
        return m_confidence;
    }
};

// Factory function for creating volatility strategy
CStrategyBase* CreateVolatilityStrategy(const string name = "Volatility Strategy", int magic = 0)
{
    return new CStrategyVolatility(name, magic);
}

//+------------------------------------------------------------------+
//| StrategyVolatility - Implementation of the Volatility strategy function |
//+------------------------------------------------------------------+
void StrategyVolatility(double &confidence)
{
    static CStrategyVolatility strategy("Volatility Strategy");
    
    // Initialize if needed
    if(!strategy.IsInitialized())
    {
        if(!strategy.Initialize())
        {
            confidence = 0.0;
            return;
        }
    }
    
    // Get the current signal
    double signal = 0.0;
    confidence = 0.0;

    // Calculate signal using the strategy
    signal = strategy.GetSignal(confidence);

    // Normalize confidence to 0-1 range
    confidence = MathMin(1.0, MathMax(0.0, confidence));
}

#endif // __STRATEGY_VOLATILITY_MQH__
