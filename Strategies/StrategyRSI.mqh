//+------------------------------------------------------------------+
//| StrategyRSI.mqh                                                  |
//| Implements an RSI-based trading strategy.                        |
//+------------------------------------------------------------------+
#ifndef __STRATEGY_RSI_MQH__
#define __STRATEGY_RSI_MQH__

#include "../Core/StrategyBase.mqh" // FIXED: Inherit from CStrategyBase
#include <Indicators/Indicators.mqh> // For CiRSI

//+------------------------------------------------------------------+
//| CStrategyRSI Class                                               |
//+------------------------------------------------------------------+
class CStrategyRSI : public CStrategyBase
{
private:
    // --- Strategy Parameters ---
    int                m_rsi_period;
    double             m_overbought;
    double             m_oversold;
    double             m_minTrendStrength;   // Trend filter

    // --- Indicators ---
    CiRSI              m_rsi;
    int                m_trendHandle;        // 50 EMA for trend filter

public:
    // --- Constructor / Destructor ---
    CStrategyRSI(const string name = "RSI Strategy", int magic = 0);
    virtual ~CStrategyRSI();

    // --- IStrategy Implementation (Overrides) ---
    virtual bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeMgr, void* posSizer) override;
    virtual void Deinit() override;
    virtual void Update(const string symbol, const ENUM_TIMEFRAMES timeframe);
    virtual ENUM_TRADE_SIGNAL GetSignal(double &confidence) override;
    virtual ENUM_STRATEGY_TYPE GetType() const override { return STRATEGY_RSI; }
    
    // --- Configuration ---
    void SetParameters(int rsi_period, double overbought, double oversold);
    
    // --- Trend Filter Validation ---
    bool ValidateTrendAlignment(ENUM_TRADE_SIGNAL signal, double &confidence);

private:
    double GetSignalValue(const string symbol, const ENUM_TIMEFRAMES timeframe, double &confidence);
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CStrategyRSI::CStrategyRSI(const string name, int magic) : 
    CStrategyBase(name, magic),
    m_rsi_period(14),
    m_overbought(70.0),
    m_oversold(30.0),
    m_minTrendStrength(0.55),    // 55% trend strength required
    m_trendHandle(INVALID_HANDLE)
{
    // Initialize any other member variables here
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CStrategyRSI::~CStrategyRSI()
{
    Deinit();
}

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
bool CStrategyRSI::Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeMgr, void* posSizer)
{
    // --- Call Base Class Init ---
    if(!CStrategyBase::Init(symbol, timeframe, tradeMgr, posSizer))
    {
        return false;
    }
    
    // Initialize trend filter (50 EMA)
    m_trendHandle = iMA(m_symbol, m_timeframe, 50, 0, MODE_EMA, PRICE_CLOSE);
    if(m_trendHandle == INVALID_HANDLE)
    {
        Print(StringFormat("%s: Failed to create trend filter EMA for %s", GetName(), m_symbol));
        return false;
    }

    // Initialize RSI indicator
    if(!m_rsi.Create(m_symbol, m_timeframe, m_rsi_period, PRICE_CLOSE))
    {
        Print(StringFormat("%s: Failed to create RSI indicator for %s", GetName(), m_symbol));
        return false;
    }
    
    Print(StringFormat("%s initialized for %s.", GetName(), m_symbol));
    m_is_initialized = true;
    return true;
}

//+------------------------------------------------------------------+
//| Deinitialization                                                 |
//+------------------------------------------------------------------+
void CStrategyRSI::Deinit()
{
    // --- Release Indicators ---
    if(m_trendHandle != INVALID_HANDLE)
    {
        IndicatorRelease(m_trendHandle);
        m_trendHandle = INVALID_HANDLE;
    }
    
    // --- Call Base Class Deinit ---
    CStrategyBase::Deinit();
}

//+------------------------------------------------------------------+
//| Set Strategy Parameters                                          |
//+------------------------------------------------------------------+
void CStrategyRSI::SetParameters(int rsi_period, double overbought, double oversold)
{
    m_rsi_period = rsi_period;
    m_overbought = overbought;
    m_oversold = oversold;
}

//+------------------------------------------------------------------+
//| Update State                                                     |
//+------------------------------------------------------------------+
void CStrategyRSI::Update(const string symbol, const ENUM_TIMEFRAMES timeframe)
{
    if(!IsEnabled() || !m_is_initialized || m_symbol != symbol || m_timeframe != timeframe)
    {
        return;
    }
    // The GetSignal method will fetch the latest RSI value when needed.
}

//+------------------------------------------------------------------+
//| Get Signal (Override from base class)                           |
//+------------------------------------------------------------------+
ENUM_TRADE_SIGNAL CStrategyRSI::GetSignal(double &confidence)
{
    if(!IsEnabled() || !m_is_initialized || m_trendHandle == INVALID_HANDLE) {
        confidence = 0.0;
        return TRADE_SIGNAL_NONE;
    }
        
    double signalValue = GetSignalValue(m_symbol, m_timeframe, confidence);
    
    if(signalValue > 0.5)
    {
        // BUY signal - validate with trend filter
        if(!ValidateTrendAlignment(TRADE_SIGNAL_BUY, confidence))
            return TRADE_SIGNAL_NONE;
        return TRADE_SIGNAL_BUY;
    }
    else if(signalValue < -0.5)
    {
        // SELL signal - validate with trend filter
        if(!ValidateTrendAlignment(TRADE_SIGNAL_SELL, confidence))
            return TRADE_SIGNAL_NONE;
        return TRADE_SIGNAL_SELL;
    }
    else
        return TRADE_SIGNAL_NONE;
}

//+------------------------------------------------------------------+
//| Validate Trend Alignment (RSI)                                   |
//+------------------------------------------------------------------+
bool CStrategyRSI::ValidateTrendAlignment(ENUM_TRADE_SIGNAL signal, double &confidence)
{
    // Get current price and trend EMA
    double priceForTrend = SymbolInfoDouble(m_symbol, SYMBOL_BID);
    double trendBuffer[1];
    
    if(CopyBuffer(m_trendHandle, 0, 0, 1, trendBuffer) < 1)
        return false;
    
    double trendMA = trendBuffer[0];
    
    // Calculate trend strength
    double trendStrength = 0.5;
    if(priceForTrend > 0 && trendMA > 0)
    {
        double priceAboveTrend = (priceForTrend - trendMA) / trendMA;
        trendStrength = 0.5 + (priceAboveTrend * 10.0);
        trendStrength = MathMax(0.0, MathMin(1.0, trendStrength));
    }
    
    // Validate trend alignment
    bool trendAligned = false;
    if(signal == TRADE_SIGNAL_BUY && trendStrength >= m_minTrendStrength)
        trendAligned = true;
    else if(signal == TRADE_SIGNAL_SELL && trendStrength <= (1.0 - m_minTrendStrength))
        trendAligned = true;
    
    if(!trendAligned)
    {
        return false;
    }
    
    // Adjust confidence with trend
    double trendConfidence = (signal == TRADE_SIGNAL_BUY) ? trendStrength : (1.0 - trendStrength);
    confidence = (confidence * 0.7) + (trendConfidence * 0.3);
    
    return true;
}

//+------------------------------------------------------------------+
//| Get Signal Value (with symbol and timeframe parameters)         |
//+------------------------------------------------------------------+
double CStrategyRSI::GetSignalValue(const string symbol, const ENUM_TIMEFRAMES timeframe, double &confidence)
{
    confidence = 0.0;
    if(!m_is_initialized || m_symbol != symbol || m_timeframe != timeframe)
    {
        return 0.0; // No signal
    }

    // Get the last two completed RSI values
    double rsi_values[2];
    if(m_rsi.GetData(1, 0, 2, rsi_values) < 1)
    {
        return 0.0; // Not enough data
    }
    
    double current_rsi = rsi_values[0];
    double previous_rsi = rsi_values[1];

    // --- Sell Signal (Crossing down from overbought) ---
    if(previous_rsi >= m_overbought && current_rsi < m_overbought)
    {
        confidence = 1.0; // High confidence
        return -1.0; // Sell signal
    }
    
    // --- Buy Signal (Crossing up from oversold) ---
    if(previous_rsi <= m_oversold && current_rsi > m_oversold)
    {
        confidence = 1.0; // High confidence
        return 1.0; // Buy signal
    }

    return 0.0; // No signal
}

#endif // __STRATEGY_RSI_MQH__
