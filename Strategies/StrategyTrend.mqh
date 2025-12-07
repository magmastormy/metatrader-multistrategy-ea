#ifndef __STRATEGY_TREND_MQH__
#define __STRATEGY_TREND_MQH__

#include "../Core/Strategy/StrategyBase.mqh"
#include <Indicators/Trend.mqh>

//+------------------------------------------------------------------+
//| Trend-Following Strategy                                         |
//| Uses SMA(50/200) crossover with ADX(14) filter                   |
//+------------------------------------------------------------------+
class CStrategyTrend : public CStrategyBase
{
private:
    int m_sma_fast_period;   // Fast SMA period
    int m_sma_slow_period;   // Slow SMA period
    int m_adx_period;        // ADX period
    double m_adx_threshold;  // ADX threshold for trend strength
    double m_minTrendStrength; // Trend filter (55%)
    
    int m_sma_fast_handle;  // Fast SMA indicator handle
    int m_sma_slow_handle;  // Slow SMA indicator handle
    int m_adx_handle;       // ADX indicator handle
    int m_trendHandle;      // 50 EMA for additional trend validation
    
public:
    //--- Constructor/Destructor
    CStrategyTrend(const string name = "Trend Strategy", int magic = 0) : 
        CStrategyBase(name, magic),
        m_sma_fast_period(50),
        m_sma_slow_period(200),
        m_adx_period(14),
        m_adx_threshold(20.0),
        m_minTrendStrength(0.55),
        m_sma_fast_handle(INVALID_HANDLE),
        m_sma_slow_handle(INVALID_HANDLE),
        m_adx_handle(INVALID_HANDLE),
        m_trendHandle(INVALID_HANDLE) {}
        
    ~CStrategyTrend() 
    { 
        if(m_sma_fast_handle != INVALID_HANDLE) IndicatorRelease(m_sma_fast_handle);
        if(m_sma_slow_handle != INVALID_HANDLE) IndicatorRelease(m_sma_slow_handle);
        if(m_adx_handle != INVALID_HANDLE) IndicatorRelease(m_adx_handle);
        if(m_trendHandle != INVALID_HANDLE) IndicatorRelease(m_trendHandle);
    }
    
    //--- Initialization
    virtual bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeMgr, void* posSizer) override
    {
        // Call base init first
        if(!CStrategyBase::Init(symbol, timeframe, tradeMgr, posSizer))
            return false;
            
        // Initialize indicators
        m_sma_fast_handle = iMA(symbol, timeframe, m_sma_fast_period, 0, MODE_SMA, PRICE_CLOSE);
        m_sma_slow_handle = iMA(symbol, timeframe, m_sma_slow_period, 0, MODE_SMA, PRICE_CLOSE);
        m_adx_handle = iADX(symbol, timeframe, m_adx_period);
        m_trendHandle = iMA(symbol, timeframe, 50, 0, MODE_EMA, PRICE_CLOSE);
        
        if(m_sma_fast_handle == INVALID_HANDLE || 
           m_sma_slow_handle == INVALID_HANDLE || 
           m_adx_handle == INVALID_HANDLE ||
           m_trendHandle == INVALID_HANDLE)
        {
            Print("Failed to create indicators for Trend Strategy");
            return false;
        }
        PrintFormat("[TREND] Strategy initialized for %s", symbol);
        return true;
    }

    //--- Deinitialization
    virtual void Deinit() override
    {
        if(m_sma_fast_handle != INVALID_HANDLE) IndicatorRelease(m_sma_fast_handle);
        if(m_sma_slow_handle != INVALID_HANDLE) IndicatorRelease(m_sma_slow_handle);
        if(m_adx_handle != INVALID_HANDLE) IndicatorRelease(m_adx_handle);
        if(m_trendHandle != INVALID_HANDLE) IndicatorRelease(m_trendHandle);
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
        {
            PrintFormat("[TREND] %s: BUY signal - Confidence: %.2f%%, ADX: strong trend",
                       m_symbol, confidence * 100);
            return TRADE_SIGNAL_BUY;
        }
        else if(signalValue < -0.5)
        {
            PrintFormat("[TREND] %s: SELL signal - Confidence: %.2f%%, ADX: strong trend",
                       m_symbol, confidence * 100);
            return TRADE_SIGNAL_SELL;
        }
        else
            return TRADE_SIGNAL_NONE;
    }
    
    virtual ENUM_STRATEGY_TYPE GetType() const override { return STRATEGY_TREND; }
    
    //--- Get trading signal
    double GetSignalValue(const string symbol, const ENUM_TIMEFRAMES timeframe, double &confidence)
    {
        if(m_sma_fast_handle == INVALID_HANDLE || m_sma_slow_handle == INVALID_HANDLE || m_adx_handle == INVALID_HANDLE)
        {
            confidence = 0.0;
            return 0.0;
        }

        double sma_fast[2], sma_slow[2];
        if(CopyBuffer(m_sma_fast_handle, 0, 1, 2, sma_fast) < 2 ||
           CopyBuffer(m_sma_slow_handle, 0, 1, 2, sma_slow) < 2)
        {
            confidence = 0.0;
            return 0.0;
        }

        double adx[1];
        if(CopyBuffer(m_adx_handle, 0, 1, 1, adx) < 1)
        {
            confidence = 0.0;
            return 0.0;
        }

        if(adx[0] > m_adx_threshold)
        {
            // Golden cross
            if(sma_fast[0] > sma_slow[0] && sma_fast[1] <= sma_slow[1])
            {
                confidence = 0.8; // High confidence for a clear crossover
                return 1.0; // Buy signal
            }
            // Death cross
            else if(sma_fast[0] < sma_slow[0] && sma_fast[1] >= sma_slow[1])
            {
                confidence = 0.8; // High confidence for a clear crossover
                return -1.0; // Sell signal
            }
        }

        confidence = 0.0;
        return 0.0;
    }
    
};



#endif // __STRATEGY_TREND_MQH__
