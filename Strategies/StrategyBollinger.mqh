//+------------------------------------------------------------------+
//| Bollinger Bands Strategy Module                                  |
//+------------------------------------------------------------------+
#ifndef __STRATEGY_BOLLINGER_MQH__
#define __STRATEGY_BOLLINGER_MQH__

#include "../Core/StrategyBase.mqh"
#include "../Core/ErrorHandling.mqh"

// Import required MQL5 functions
#include <Trade/Trade.mqh>
#include "../Core/TradeManager.mqh"
#include "../Core/PositionSizer.mqh"

//+------------------------------------------------------------------+
//| Bollinger Bands Strategy Class                                   |
//+------------------------------------------------------------------+
class CStrategyBollinger : public CStrategyBase
{
private:
    // Bollinger Bands parameters
    int m_bbPeriod;             // Period for Bollinger Bands
    double m_bbDeviation;        // Standard deviation for Bollinger Bands
    int m_bbShift;              // Shift for Bollinger Bands
    ENUM_APPLIED_PRICE m_appliedPrice; // Price type for calculations
    
    // Indicator handles
    int m_bbHandle;             // Bollinger Bands indicator handle
    int m_maHandle;             // Moving Average handle (for trend confirmation)
    
    // Indicator buffers
    double m_upperBand[];       // Upper band values
    double m_middleBand[];      // Middle band (SMA) values
    double m_lowerBand[];       // Lower band values
    double m_maBuffer[];        // Moving average buffer
    
    // State variables
    ENUM_TRADE_SIGNAL m_lastSignalValue;    // Last signal value
    double m_lastConfidence;    // Last signal confidence (0-1)
    
    // Helper methods
    void CleanupIndicators();
    void UpdateBollingerBands();
    
public:
    CStrategyBollinger(const string name = "Bollinger Bands Strategy", int magic = 0);
    virtual ~CStrategyBollinger();
    
    // IStrategy implementation
    virtual bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeManager, void* positionSizer) override;
    virtual void Deinit() override;
    virtual ENUM_TRADE_SIGNAL GetSignal(double &confidence) override;
    virtual ENUM_STRATEGY_TYPE GetType() const override { return STRATEGY_TYPE_CUSTOM; } // Or specific type if available
    virtual void OnTick() override;
    virtual void OnNewBar(const string symbol, const ENUM_TIMEFRAMES timeframe) override;
    
    // Configuration methods
    void SetPeriod(int period) { m_bbPeriod = MathMax(2, period); }
    void SetDeviation(double deviation) { m_bbDeviation = MathMax(0.1, deviation); }
    void SetShift(int shift) { m_bbShift = shift; }
    void SetAppliedPrice(ENUM_APPLIED_PRICE price) { m_appliedPrice = price; }
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CStrategyBollinger::CStrategyBollinger(const string name, int magic) :
    CStrategyBase(name, magic),
    m_bbPeriod(20),
    m_bbDeviation(2.0),
    m_bbShift(0),
    m_appliedPrice(PRICE_CLOSE),
    m_bbHandle(INVALID_HANDLE),
    m_maHandle(INVALID_HANDLE),
    m_lastSignalValue(TRADE_SIGNAL_NONE),
    m_lastConfidence(0.0)
{
    // Initialize arrays as series
    ArraySetAsSeries(m_upperBand, true);
    ArraySetAsSeries(m_middleBand, true);
    ArraySetAsSeries(m_lowerBand, true);
    ArraySetAsSeries(m_maBuffer, true);
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CStrategyBollinger::~CStrategyBollinger()
{
    Deinit();
}

//+------------------------------------------------------------------+
//| Initialize indicator handles and resources                       |
//+------------------------------------------------------------------+
bool CStrategyBollinger::Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeMgr, void* posSizer)
{
    // Clean up any existing handles
    CleanupIndicators();
    
    if(!CStrategyBase::Init(symbol, timeframe, tradeMgr, posSizer))
        return false;

    // Initialize indicators
    UpdateBollingerBands();
    
    return true;
}

//+------------------------------------------------------------------+
//| Clean up indicator handles and resources                         |
//+------------------------------------------------------------------+
void CStrategyBollinger::Deinit()
{
    CleanupIndicators();
    
    // Clear buffers
    ArrayFree(m_upperBand);
    ArrayFree(m_middleBand);
    ArrayFree(m_lowerBand);
    ArrayFree(m_maBuffer);
    
    CStrategyBase::Deinit();
}

//+------------------------------------------------------------------+
//| Clean up indicator handles                                       |
//+------------------------------------------------------------------+
void CStrategyBollinger::CleanupIndicators()
{
    if(m_bbHandle != INVALID_HANDLE) {
        IndicatorRelease(m_bbHandle);
        m_bbHandle = INVALID_HANDLE;
    }
    
    if(m_maHandle != INVALID_HANDLE) {
        IndicatorRelease(m_maHandle);
        m_maHandle = INVALID_HANDLE;
    }
}

//+------------------------------------------------------------------+
//| Update Bollinger Bands indicator values                          |
//+------------------------------------------------------------------+
void CStrategyBollinger::UpdateBollingerBands()
{
    if(m_symbol == "" || m_timeframe == 0) return;
    
    // Create or update Bollinger Bands handle
    if(m_bbHandle == INVALID_HANDLE) {
        m_bbHandle = iBands(m_symbol, m_timeframe, m_bbPeriod, m_bbShift, m_bbDeviation, m_appliedPrice);
        if(m_bbHandle == INVALID_HANDLE) {
            PrintFormat("Failed to create Bollinger Bands indicator for %s", m_symbol);
            return;
        }
    }
    
    // Create or update Moving Average handle for trend confirmation
    if(m_maHandle == INVALID_HANDLE) {
        m_maHandle = iMA(m_symbol, m_timeframe, 200, 0, MODE_SMA, m_appliedPrice);
        if(m_maHandle == INVALID_HANDLE) {
            PrintFormat("Failed to create Moving Average indicator for %s", m_symbol);
            return;
        }
    }
}

//+------------------------------------------------------------------+
//| Handle tick event                                                |
//+------------------------------------------------------------------+
void CStrategyBollinger::OnTick()
{
    // Check for new bar
    static datetime lastBarTime = 0;
    datetime barTime = iTime(m_symbol, m_timeframe, 0);
    if(barTime != lastBarTime) {
        lastBarTime = barTime;
        OnNewBar(m_symbol, m_timeframe);
    }
}

//+------------------------------------------------------------------+
//| Handle new bar event                                             |
//+------------------------------------------------------------------+
void CStrategyBollinger::OnNewBar(const string symbol, const ENUM_TIMEFRAMES timeframe)
{
    if(!m_is_enabled || symbol == "" || timeframe == 0) return;
    
    // Update indicators on new bar if needed (though handles persist)
    if(m_bbHandle == INVALID_HANDLE || m_maHandle == INVALID_HANDLE)
        UpdateBollingerBands();
}

//+------------------------------------------------------------------+
//| Get trading signal from Bollinger Bands                          |
//+------------------------------------------------------------------+
ENUM_TRADE_SIGNAL CStrategyBollinger::GetSignal(double &confidence)
{
    confidence = 0.0;
    if(!m_is_enabled || !m_is_initialized) return TRADE_SIGNAL_NONE;
    
    // Ensure indicators are valid
    if(m_bbHandle == INVALID_HANDLE || m_maHandle == INVALID_HANDLE) {
        UpdateBollingerBands();
        if(m_bbHandle == INVALID_HANDLE || m_maHandle == INVALID_HANDLE) return TRADE_SIGNAL_NONE;
    }
    
    // Ensure we have enough data
    int barsNeeded = MathMax(m_bbPeriod * 3, 200);
    if(BarsCalculated(m_bbHandle) < barsNeeded || BarsCalculated(m_maHandle) < barsNeeded) {
        return TRADE_SIGNAL_NONE;
    }
    
    // Copy indicator data to buffers
    if(CopyBuffer(m_bbHandle, 1, 0, 3, m_upperBand) <= 0 ||
       CopyBuffer(m_bbHandle, 0, 0, 3, m_middleBand) <= 0 ||
       CopyBuffer(m_bbHandle, 2, 0, 3, m_lowerBand) <= 0 ||
       CopyBuffer(m_maHandle, 0, 0, 3, m_maBuffer) <= 0) {
        return TRADE_SIGNAL_NONE;
    }
    
    // Get current price
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    if(CopyRates(m_symbol, m_timeframe, 0, 2, rates) <= 0) {
        return TRADE_SIGNAL_NONE;
    }
    
    double closePrice = rates[0].close;
    ENUM_TRADE_SIGNAL signal = TRADE_SIGNAL_NONE;
    confidence = 0.0;
    
    // Check for Bollinger Bands signals
    // 1. Price breaks above upper band - Potential Reversal Sell or Breakout Buy?
    // Standard BB strategy: Reversal at bands
    if(closePrice > m_upperBand[0] && m_upperBand[0] > m_upperBand[1]) {
        // Price is pushing upper band
        // Check if it's a reversal candle (e.g., close < open)
        if(rates[0].close < rates[0].open) {
             signal = TRADE_SIGNAL_SELL;
             confidence = 0.6;
        }
    }
    else if(closePrice < m_lowerBand[0] && m_lowerBand[0] < m_lowerBand[1]) {
        // Price is pushing lower band
        // Check if it's a reversal candle
        if(rates[0].close > rates[0].open) {
            signal = TRADE_SIGNAL_BUY;
            confidence = 0.6;
        }
    }
    
    // Check trend confirmation with 200 MA
    if(signal != TRADE_SIGNAL_NONE) {
        if((signal == TRADE_SIGNAL_BUY && closePrice > m_maBuffer[0]) || 
           (signal == TRADE_SIGNAL_SELL && closePrice < m_maBuffer[0])) {
            // Signal aligns with trend - increase confidence
            confidence = MathMin(1.0, confidence + 0.2);
        } else {
            // Signal is counter-trend - decrease confidence
            confidence = MathMax(0.1, confidence - 0.2);
            // Optional: Filter out counter-trend signals if confidence is too low
            if(confidence < 0.5) signal = TRADE_SIGNAL_NONE;
        }
    }
    
    m_lastSignalValue = signal;
    m_lastConfidence = confidence;
    if(signal != TRADE_SIGNAL_NONE) m_lastSignalTime = TimeCurrent();
    
    return signal;
}

//+------------------------------------------------------------------+
#endif // __STRATEGY_BOLLINGER_MQH__
