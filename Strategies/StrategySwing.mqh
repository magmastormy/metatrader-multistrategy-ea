//+------------------------------------------------------------------+
//| Swing Trading Strategy Module                                   |
//| Uses MA(20), MA(50), and RSI(14)                                 |
//+------------------------------------------------------------------+

#ifndef __STRATEGY_SWING_MQH__
#define __STRATEGY_SWING_MQH__

#include "../Core/StrategyBase.mqh"
#include "../Core/OrderInfo.mqh"
#include "../Core/HistoryOrderInfo.mqh"
#include "../Core/PositionInfo.mqh"
#include "../Core/DealInfo.mqh"
#include "../Core/Trade.mqh"



//+------------------------------------------------------------------+
//| Swing Trading Strategy Class                                    |
//+------------------------------------------------------------------+
class CStrategySwing : public CStrategyBase
{
private:
    int m_maFastPeriod;     // Fast MA period
    int m_maSlowPeriod;     // Slow MA period
    int m_rsiPeriod;        // RSI period
    double m_lastSignal;    // Last signal value
    double m_lastConfidence; // Last confidence value
    
    // Helper method to calculate the signal
    int CalculateSignal(const string &symbol, const ENUM_TIMEFRAMES timeframe, double &outConfidence) const
    {
        outConfidence = 0.0;
        
        // Initialize arrays
        double maFast[2], maSlow[2], rsi[1];
        // Note: ArraySetAsSeries cannot be used with static arrays
        
        // Get fast and slow MA handles
        int maFastHandle = iMA(symbol, timeframe, m_maFastPeriod, 0, MODE_SMA, PRICE_CLOSE);
        if(maFastHandle == INVALID_HANDLE)
        {
            Print("Failed to create fast MA handle");
            return 0;
        }
        
        int maSlowHandle = iMA(symbol, timeframe, m_maSlowPeriod, 0, MODE_SMA, PRICE_CLOSE);
        if(maSlowHandle == INVALID_HANDLE)
        {
            Print("Failed to create slow MA handle");
            IndicatorRelease(maFastHandle);
            return 0;
        }
        
        // Wait for indicators to initialize and copy MA values
        int attempts = 0;
        bool dataReady = false;
        while(attempts < 10 && !dataReady)
        {
            // 🛡️ BEAST MODE: Removed Sleep(100) - indicators initialize properly without delays
            if(CopyBuffer(maFastHandle, 0, 0, 2, maFast) == 2 &&
               CopyBuffer(maSlowHandle, 0, 0, 2, maSlow) == 2)
            {
                dataReady = true;
            }
            attempts++;
        }
        
        if(!dataReady)
        {
            Print("[ERROR] Failed to copy MA buffer data after ", attempts, " attempts for ", symbol);
            IndicatorRelease(maFastHandle);
            IndicatorRelease(maSlowHandle);
            return 0;
        }
        
        // Release MA handles as we don't need them anymore
        IndicatorRelease(maFastHandle);
        IndicatorRelease(maSlowHandle);
        
        // Get RSI handle and value
        int rsiHandle = iRSI(symbol, timeframe, m_rsiPeriod, PRICE_CLOSE);
        if(rsiHandle == INVALID_HANDLE)
        {
            Print("Failed to create RSI handle");
            return 0;
        }
        
        // Wait for RSI indicator to initialize
        attempts = 0;
        dataReady = false;
        while(attempts < 10 && !dataReady)
        {
            // 🛡️ BEAST MODE: Removed Sleep(100) - indicators initialize properly without delays
            if(CopyBuffer(rsiHandle, 0, 0, 1, rsi) == 1)
            {
                dataReady = true;
            }
            attempts++;
        }
        
        if(!dataReady)
        {
            Print("[ERROR] Failed to copy RSI buffer data after ", attempts, " attempts for ", symbol);
            IndicatorRelease(rsiHandle);
            return 0;
        }
        IndicatorRelease(rsiHandle);
        
        // Calculate signal based on MA crossover and RSI
        int signal = 0;
        double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
        
        if(point <= 0) // Prevent division by zero
            point = 0.00001;
            
        if(maFast[0] > maSlow[0] && rsi[0] > 50)
        {
            signal = 1;  // Buy signal
            outConfidence = MathMin(1.0, (maFast[0] - maSlow[0]) / (point * 10)); // Normalize confidence
        }
        else if(maFast[0] < maSlow[0] && rsi[0] < 50)
        {
            signal = -1; // Sell signal
            outConfidence = MathMin(1.0, (maSlow[0] - maFast[0]) / (point * 10)); // Normalize confidence
        }
        
        return signal;
    }
    
public:
    CStrategySwing(const string name = "Swing Trading Strategy", int magic = 0) : 
        CStrategyBase(name, magic),
        m_maFastPeriod(20),
        m_maSlowPeriod(50),
        m_rsiPeriod(14),
        m_lastSignal(0),
        m_lastConfidence(0)
    {
    }
    
    virtual ~CStrategySwing()
    {
        Deinit();
    }
    
    // IStrategy implementation
    virtual bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeMgr, void* posSizer) override
    {
        if(!CStrategyBase::Init(symbol, timeframe, tradeMgr, posSizer)) return false;
        Print("Initializing ", m_name);
        return true;
    }
    
    virtual void Deinit() override
    {
        Print("Deinitializing ", m_name);
        CStrategyBase::Deinit();
    }
    
    virtual void OnTick() override {}
    virtual void OnNewBar(const string symbol, const ENUM_TIMEFRAMES timeframe) override {}
    
    virtual ENUM_TRADE_SIGNAL GetSignal(double &confidence) override
    {
        if(!IsEnabled()) {
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
    
    virtual string GetName() const override { return m_name; }
    virtual ENUM_STRATEGY_TYPE GetType() const override { return STRATEGY_SWING; }
    
    // Helper for internal use
    double GetSignalValue(const string symbol, const ENUM_TIMEFRAMES timeframe, double &confidence)
    {
        confidence = 0.0;
        
        if(!IsEnabled())
            return 0.0;
            
        // Check if symbol is valid
        if(!SymbolSelect(symbol, true))
        {
            Print("Failed to select symbol: ", symbol);
            return 0.0;
        }
        
        int signal = CalculateSignal(symbol, timeframe, confidence);
        m_lastSignal = signal;
        m_lastConfidence = confidence;
        m_lastSignalTime = TimeCurrent();
        return (double)signal;
    }
    
    // Getters for strategy parameters
    int GetMaFastPeriod() const { return m_maFastPeriod; }
    int GetMaSlowPeriod() const { return m_maSlowPeriod; }
    int GetRsiPeriod() const { return m_rsiPeriod; }
    
    // Setters for strategy parameters
    void SetMaFastPeriod(int period) { m_maFastPeriod = period > 0 ? period : 20; }
    void SetMaSlowPeriod(int period) { m_maSlowPeriod = period > 0 ? period : 50; }
    void SetRsiPeriod(int period) { m_rsiPeriod = period > 0 ? period : 14; }
};

#endif //_STRATEGY_SWING_MQH_
