//+------------------------------------------------------------------+
//| Bollinger Breakout Strategy Module                                |
//+------------------------------------------------------------------+
#ifndef __STRATEGY_BOLLINGER_BREAKOUT_MQH__
#define __STRATEGY_BOLLINGER_BREAKOUT_MQH__

#include "../Core/StrategyBase.mqh"
#include "../Core/TradeManager.mqh"
#include "../Core/PositionSizer.mqh"
#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| Bollinger Breakout Strategy Class                                |
//+------------------------------------------------------------------+
class CStrategyBollingerBreakout : public CStrategyBase
{
private:
    // --- Parameters ---
    int    m_bb_period;
    double m_bb_deviation;
    double m_min_volatility; // Minimum ATR for breakout

    // --- Indicator Handles and Buffers ---
    int    m_bb_handle;
    int    m_atr_handle;
    double m_upper_band[];
    double m_middle_band[];
    double m_lower_band[];

    // --- State ---
    datetime m_lastSignalTime;

public:
    // --- Constructor / Destructor ---
    CStrategyBollingerBreakout(const string name = "Bollinger Breakout", int magic = 0);
    virtual ~CStrategyBollingerBreakout();

    // --- IStrategy Implementation ---
    virtual bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeManager, void* positionSizer) override;
    virtual void Deinit() override;
    virtual ENUM_TRADE_SIGNAL GetSignal(double &confidence) override;
    virtual ENUM_STRATEGY_TYPE GetType() const override { return STRATEGY_TYPE_CUSTOM; }
    virtual void OnTick() override;
    virtual void OnNewBar(const string symbol, const ENUM_TIMEFRAMES timeframe) override;
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CStrategyBollingerBreakout::CStrategyBollingerBreakout(const string name, int magic)
    : CStrategyBase(name, magic),
      m_bb_period(20),
      m_bb_deviation(2.0),
      m_min_volatility(0.0005),
      m_bb_handle(INVALID_HANDLE),
      m_atr_handle(INVALID_HANDLE),
      m_lastSignalTime(0)
{
    ArraySetAsSeries(m_upper_band, true);
    ArraySetAsSeries(m_middle_band, true);
    ArraySetAsSeries(m_lower_band, true);
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CStrategyBollingerBreakout::~CStrategyBollingerBreakout()
{
    Deinit();
}

//+------------------------------------------------------------------+
//| Initialize Strategy                                              |
//+------------------------------------------------------------------+
bool CStrategyBollingerBreakout::Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeManager, void* positionSizer)
{
    if(!CStrategyBase::Init(symbol, timeframe, tradeManager, positionSizer))
        return false;

    if(m_bb_handle != INVALID_HANDLE) IndicatorRelease(m_bb_handle);
    if(m_atr_handle != INVALID_HANDLE) IndicatorRelease(m_atr_handle);

    m_bb_handle = iBands(m_symbol, m_timeframe, m_bb_period, 0, m_bb_deviation, PRICE_CLOSE);
    m_atr_handle = iATR(m_symbol, m_timeframe, 14);

    if(m_bb_handle == INVALID_HANDLE || m_atr_handle == INVALID_HANDLE)
    {
        PrintFormat("Error creating indicators for %s %s. Code: %d", m_symbol, EnumToString(m_timeframe), GetLastError());
        return false;
    }
    
    // Adjust min volatility based on symbol digits
    if(SymbolInfoInteger(symbol, SYMBOL_DIGITS) <= 3) // JPY pairs or Indices
        m_min_volatility = 0.05; 
    else
        m_min_volatility = 0.0005;

    return true;
}

//+------------------------------------------------------------------+
//| Deinitialize Strategy                                            |
//+------------------------------------------------------------------+
void CStrategyBollingerBreakout::Deinit()
{
    if(m_bb_handle != INVALID_HANDLE) { IndicatorRelease(m_bb_handle); m_bb_handle = INVALID_HANDLE; }
    if(m_atr_handle != INVALID_HANDLE) { IndicatorRelease(m_atr_handle); m_atr_handle = INVALID_HANDLE; }
    CStrategyBase::Deinit();
}

//+------------------------------------------------------------------+
//| Get Signal                                                       |
//+------------------------------------------------------------------+
ENUM_TRADE_SIGNAL CStrategyBollingerBreakout::GetSignal(double &confidence)
{
    confidence = 0.0;
    if(!m_is_enabled || !m_is_initialized) return TRADE_SIGNAL_NONE;
    if(m_bb_handle == INVALID_HANDLE || m_atr_handle == INVALID_HANDLE) return TRADE_SIGNAL_NONE;

    // Copy Bollinger data to buffers
    if(CopyBuffer(m_bb_handle, 1, 0, 3, m_upper_band) < 3 || // Upper band is buffer 1
       CopyBuffer(m_bb_handle, 0, 0, 3, m_middle_band) < 3 || // Middle band is buffer 0
       CopyBuffer(m_bb_handle, 2, 0, 3, m_lower_band) < 3)   // Lower band is buffer 2
    {
        return TRADE_SIGNAL_NONE;
    }
    
    // Check Volatility
    double atrBuffer[1];
    if(CopyBuffer(m_atr_handle, 0, 0, 1, atrBuffer) < 1) return TRADE_SIGNAL_NONE;
    if(atrBuffer[0] < m_min_volatility) return TRADE_SIGNAL_NONE; // Too quiet for breakout

    // Get price data
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    if(CopyRates(m_symbol, m_timeframe, 0, 3, rates) < 3)
    {
        return TRADE_SIGNAL_NONE;
    }

    // --- Breakout Logic ---
    double current_close = rates[0].close;
    double prev_close = rates[1].close;
    
    double upper_band_current = m_upper_band[0];
    double upper_band_prev = m_upper_band[1];
    
    double lower_band_current = m_lower_band[0];
    double lower_band_prev = m_lower_band[1];

    // Bullish breakout: Close above upper band
    if(current_close > upper_band_current && prev_close <= upper_band_prev)
    {
        // Confirm with strong candle body
        double bodySize = MathAbs(rates[0].close - rates[0].open);
        double totalSize = rates[0].high - rates[0].low;
        if(totalSize > 0 && bodySize / totalSize > 0.6) // Strong bullish candle
        {
            confidence = 0.8; 
            return TRADE_SIGNAL_BUY;
        }
    }

    // Bearish breakout: Close below lower band
    if(current_close < lower_band_current && prev_close >= lower_band_prev)
    {
        // Confirm with strong candle body
        double bodySize = MathAbs(rates[0].close - rates[0].open);
        double totalSize = rates[0].high - rates[0].low;
        if(totalSize > 0 && bodySize / totalSize > 0.6) // Strong bearish candle
        {
            confidence = 0.8; 
            return TRADE_SIGNAL_SELL;
        }
    }

    return TRADE_SIGNAL_NONE;
}

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void CStrategyBollingerBreakout::OnTick()
{
    // Check for new bar
    static datetime lastBarTime = 0;
    datetime currentTime = iTime(m_symbol, m_timeframe, 0);
    if(currentTime != lastBarTime) {
        lastBarTime = currentTime;
        OnNewBar(m_symbol, m_timeframe);
    }
}

//+------------------------------------------------------------------+
//| OnNewBar                                                         |
//+------------------------------------------------------------------+
void CStrategyBollingerBreakout::OnNewBar(const string symbol, const ENUM_TIMEFRAMES timeframe)
{
    // Logic for new bar events can be added here
}

#endif // __STRATEGY_BOLLINGER_BREAKOUT_MQH__
