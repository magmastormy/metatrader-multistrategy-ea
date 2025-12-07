#ifndef __STRATEGY_MEANREVERSION_MQH__
#define __STRATEGY_MEANREVERSION_MQH__

#include "../Core/Strategy/StrategyBase.mqh"
#include <Indicators/Trend.mqh>
#include "../Include/Indicators/Oscillators.mqh"

//+------------------------------------------------------------------+
//| Mean-Reversion Strategy                                          |
//| Uses Bollinger Bands and RSI to identify overbought/oversold     |
//| conditions for potential reversal trades                         |
//+------------------------------------------------------------------+
class CStrategyMeanReversion : public CStrategyBase
{
private:
    // Strategy parameters
    int m_bb_period;        // Bollinger Bands period
    double m_bb_deviation;  // Bollinger Bands deviation
    int m_rsi_period;       // RSI period
    int m_rsi_oversold;     // RSI oversold level
    int m_rsi_overbought;   // RSI overbought level
    double m_confidence;    // Last calculated confidence level
    double m_minTrendStrength; // Trend filter

    // Indicator handles
    int m_bb_handle;        // Bollinger Bands handle
    int m_rsi_handle;       // RSI handle
    int m_trendHandle;      // 50 EMA for trend filter

public:
    //--- Constructor/Destructor
    CStrategyMeanReversion(const string name = "Mean Reversion Strategy", int magic = 0) :
        CStrategyBase(name, magic),
        m_bb_period(20),
        m_bb_deviation(2.0),
        m_rsi_period(14),
        m_rsi_oversold(30),
        m_rsi_overbought(70),
        m_confidence(0.0),
        m_minTrendStrength(0.50),  // 50% for mean reversion (works in ranging markets)
        m_bb_handle(INVALID_HANDLE),
        m_rsi_handle(INVALID_HANDLE),
        m_trendHandle(INVALID_HANDLE) {}
        
    ~CStrategyMeanReversion() 
    { 
        if(m_bb_handle != INVALID_HANDLE) IndicatorRelease(m_bb_handle);
        if(m_rsi_handle != INVALID_HANDLE) IndicatorRelease(m_rsi_handle);
        if(m_trendHandle != INVALID_HANDLE) IndicatorRelease(m_trendHandle);
    }
    
    //--- Initialization
    virtual bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeMgr, void* posSizer) override
    {
        // Call base init first
        if(!CStrategyBase::Init(symbol, timeframe, tradeMgr, posSizer))
            return false;
            
        // Initialize indicators
        m_bb_handle = iBands(m_symbol, m_timeframe, m_bb_period, 0, m_bb_deviation, PRICE_CLOSE);
        m_rsi_handle = iRSI(m_symbol, m_timeframe, m_rsi_period, PRICE_CLOSE);
        m_trendHandle = iMA(m_symbol, m_timeframe, 50, 0, MODE_EMA, PRICE_CLOSE);
        
        if(m_bb_handle == INVALID_HANDLE || m_rsi_handle == INVALID_HANDLE || m_trendHandle == INVALID_HANDLE)
        {
            Print("Failed to create indicators for Mean Reversion Strategy");
            return false;
        }
        return true;
    }
    
    //--- Deinitialization
    virtual void Deinit() override
    {
        if(m_bb_handle != INVALID_HANDLE) IndicatorRelease(m_bb_handle);
        if(m_rsi_handle != INVALID_HANDLE) IndicatorRelease(m_rsi_handle);
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
            
        // Get Bollinger Bands values
        double upper[1], middle[1], lower[1];
        if(CopyBuffer(m_bb_handle, 1, 0, 1, upper) != 1 ||
           CopyBuffer(m_bb_handle, 0, 0, 1, middle) != 1 ||
           CopyBuffer(m_bb_handle, 2, 0, 1, lower) != 1)
        {
            confidence = 0.0;
            return TRADE_SIGNAL_NONE;
        }
        // Get RSI value
        double rsi[1];
        if(CopyBuffer(m_rsi_handle, 0, 0, 1, rsi) != 1)
        {
            confidence = 0.0;
            return TRADE_SIGNAL_NONE;
        }
        // Get current price
        double price = iClose(m_symbol, m_timeframe, 0);
        
        // Check for oversold condition (potential buy)
        if(price <= lower[0] && rsi[0] < m_rsi_oversold)
        {
            // Calculate confidence based on how far price is below the lower band
            double band_width = upper[0] - lower[0];
            if(band_width > 0)
                confidence = MathMin((lower[0] - price) / (band_width * 0.5), 1.0);
            else
                confidence = 0.5;
            m_confidence = confidence; // Store for later retrieval
            return TRADE_SIGNAL_BUY;
        }
        // Check for overbought condition (potential sell)
        else if(price >= upper[0] && rsi[0] > m_rsi_overbought)
        {
            // Calculate confidence based on how far price is above the upper band
            double band_width = upper[0] - lower[0];
            if(band_width > 0)
                confidence = MathMin((price - upper[0]) / (band_width * 0.5), 1.0);
            else
                confidence = 0.5;
            m_confidence = confidence; // Store for later retrieval
            return TRADE_SIGNAL_SELL;
        }
        
        confidence = 0.0;
        m_confidence = confidence;
        return TRADE_SIGNAL_NONE;
    }
    
    virtual ENUM_STRATEGY_TYPE GetType() const override { return STRATEGY_MEAN_REVERSION; }
    
    //--- Calculate confidence level (0.0 to 1.0) - helper method
    double CalculateConfidence()
    {
        return m_confidence;
    }
};

#endif // __STRATEGY_MEANREVERSION_MQH__
