//+------------------------------------------------------------------+
//| MACD Strategy Module                                              |
//+------------------------------------------------------------------+
#ifndef __STRATEGY_MACD_MQH__
#define __STRATEGY_MACD_MQH__

#include "../Core/StrategyBase.mqh"
#include <Arrays/ArrayObj.mqh>

// MACD Strategy - Uses MACD (Moving Average Convergence Divergence) for trend detection
// and signal generation with advanced filtering

// MACD event class for tracking signal quality
class SMACDEvent : public CObject {
public:
    datetime time;
    double macdValue;
    double signalValue;
    double histogram;
    bool isValid;
    int direction; // 1 for bullish, -1 for bearish, 0 for neutral
    double strength; // Signal strength 0.0-1.0
    
    // Default constructor
    SMACDEvent() : time(0), macdValue(0), signalValue(0), histogram(0), isValid(false), direction(0), strength(0) {}
};

//+------------------------------------------------------------------+
//| MACD Strategy Factory Function                                   |
//+------------------------------------------------------------------+


//+------------------------------------------------------------------+
//| MACD Strategy Class                                              |
//+------------------------------------------------------------------+
class CStrategyMACD : public CStrategyBase
{
private:
    // MACD parameters
    int               m_fastEMA;     // Fast EMA period
    int               m_slowEMA;     // Slow EMA period
    int               m_signalEMA;   // Signal line EMA period
    int               m_macdHandle;  // MACD indicator handle
    double            m_macdBuffer[];
    double            m_signalBuffer[];
    double            m_histogramBuffer[];
    CArrayObj*        m_macdEvents;  // Array of MACD events
    
    // Helper methods
    void CleanupIndicators();
    void UpdateMACD(const string symbol, const ENUM_TIMEFRAMES timeframe);
    
public:
    CStrategyMACD(const string name = "MACD Strategy", int magic = 0);
    virtual ~CStrategyMACD();
    
    // IStrategy implementation
    virtual bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeManager, void* positionSizer) override;
    virtual void Deinit() override;
    virtual ENUM_TRADE_SIGNAL GetSignal(double &confidence) override;
    virtual string GetName() const override { return m_name; }
    virtual bool IsEnabled() const override { return m_is_enabled; }
    virtual void SetEnabled(const bool enabled) override { m_is_enabled = enabled; }
    virtual void OnTick() override;
    virtual void OnNewBar(const string symbol, const ENUM_TIMEFRAMES timeframe) override;
    virtual ENUM_STRATEGY_TYPE GetType() const override { return STRATEGY_MACD; }
    
    // Configuration methods
    void SetParameters(int fastEMA, int slowEMA, int signalEMA);
};

// Static variables for MACD strategy
static int macdFastEMA = 12;
static int macdSlowEMA = 26;
static int macdSignalEMA = 9;

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CStrategyMACD::CStrategyMACD(const string name, int magic) :
    CStrategyBase(name, magic),
    m_fastEMA(12),
    m_slowEMA(26),
    m_signalEMA(9),
    m_macdHandle(INVALID_HANDLE)
{
    m_macdEvents = new CArrayObj();
    // CArrayObj defaults to owning objects
    
    // Initialize buffers
    ArraySetAsSeries(m_macdBuffer, true);
    ArraySetAsSeries(m_signalBuffer, true);
    ArraySetAsSeries(m_histogramBuffer, true);
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CStrategyMACD::~CStrategyMACD()
{
    Deinit();
    if(CheckPointer(m_macdEvents) == POINTER_DYNAMIC) {
        delete m_macdEvents;
        m_macdEvents = NULL;
    }
}

//+------------------------------------------------------------------+
//| Initialize indicator handles and resources                       |
//+------------------------------------------------------------------+
bool CStrategyMACD::Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeMgr, void* posSizer)
{
    Print("Initializing MACD Strategy");
    
    // Clean up any existing handles
    CleanupIndicators();
    
    // Reset event tracking
    if(m_macdEvents != NULL) {
        m_macdEvents.Clear();
    }
    
    return CStrategyBase::Init(symbol, timeframe, tradeMgr, posSizer);
}

//+------------------------------------------------------------------+
//| Clean up indicator handles and resources                         |
//+------------------------------------------------------------------+
void CStrategyMACD::Deinit()
{
    CleanupIndicators();
    
    // Clear buffers
    ArrayFree(m_macdBuffer);
    ArrayFree(m_signalBuffer);
    ArrayFree(m_histogramBuffer);
    
    // Clear events
    if(m_macdEvents != NULL) {
        m_macdEvents.Clear();
    }
    
    CStrategyBase::Deinit();
    Print("MACD Strategy deinitialized");
}

//+------------------------------------------------------------------+
//| Clean up indicator handles                                       |
//+------------------------------------------------------------------+
void CStrategyMACD::CleanupIndicators()
{
    if(m_macdHandle != INVALID_HANDLE) {
        IndicatorRelease(m_macdHandle);
        m_macdHandle = INVALID_HANDLE;
    }
}

//+------------------------------------------------------------------+
//| Update MACD indicator values                                     |
//+------------------------------------------------------------------+
void CStrategyMACD::UpdateMACD(const string symbol, const ENUM_TIMEFRAMES timeframe)
{
    if(symbol == "" || timeframe == 0) return;
    
    // Create or update MACD handle
    if(m_macdHandle == INVALID_HANDLE) {
        m_macdHandle = iMACD(symbol, timeframe, m_fastEMA, m_slowEMA, m_signalEMA, PRICE_CLOSE);
        if(m_macdHandle == INVALID_HANDLE) {
            PrintFormat("Failed to create MACD indicator for %s %s", symbol, EnumToString(timeframe));
            return;
        }
    }
    
    // Ensure we have enough data
    int barsNeeded = MathMax(m_slowEMA, m_signalEMA) * 3;
    if(BarsCalculated(m_macdHandle) < barsNeeded) {
        return;
    }
    
    // Copy MACD data to buffers
    if(CopyBuffer(m_macdHandle, 0, 0, 10, m_macdBuffer) <= 0 ||
       CopyBuffer(m_macdHandle, 1, 0, 10, m_signalBuffer) <= 0 ||
       CopyBuffer(m_macdHandle, 2, 0, 10, m_histogramBuffer) <= 0) {
        return;
    }
}

//+------------------------------------------------------------------+
//| Get trading signal from MACD                                     |
//+------------------------------------------------------------------+
ENUM_TRADE_SIGNAL CStrategyMACD::GetSignal(double &confidence)
{
    if(!IsEnabled() || !m_is_initialized) {
        confidence = 0.0;
        return TRADE_SIGNAL_NONE;
    }
    
    confidence = 0.0;
    
    // Update MACD values
    UpdateMACD(m_symbol, m_timeframe);
    
    // Check if we have enough data
    if(ArraySize(m_macdBuffer) < 3 || ArraySize(m_signalBuffer) < 3 || ArraySize(m_histogramBuffer) < 3) {
        return TRADE_SIGNAL_NONE;
    }
    
    // Create new MACD event
    SMACDEvent *newEvent = new SMACDEvent();
    if(newEvent == NULL) {
        return TRADE_SIGNAL_NONE;
    }
    
    newEvent.time = TimeCurrent();
    newEvent.macdValue = m_macdBuffer[0];
    newEvent.signalValue = m_signalBuffer[0];
    newEvent.histogram = m_histogramBuffer[0];
    newEvent.isValid = true;
    
    // Determine signal direction and strength
    bool crossAbove = m_macdBuffer[1] <= m_signalBuffer[1] && m_macdBuffer[0] > m_signalBuffer[0];
    bool crossBelow = m_macdBuffer[1] >= m_signalBuffer[1] && m_macdBuffer[0] < m_signalBuffer[0];
    
    // Calculate signal strength based on histogram size and trend consistency
    double histogramStrength = MathAbs(m_histogramBuffer[0]) / 0.001; // Normalize
    histogramStrength = MathMin(histogramStrength, 1.0); // Cap at 1.0
    
    // Check for trend consistency (are the last 3 histogram bars in the same direction?)
    bool consistentBullish = m_histogramBuffer[0] > 0 && m_histogramBuffer[1] > 0 && m_histogramBuffer[2] > 0;
    bool consistentBearish = m_histogramBuffer[0] < 0 && m_histogramBuffer[1] < 0 && m_histogramBuffer[2] < 0;
    double consistencyBonus = (consistentBullish || consistentBearish) ? 0.3 : 0.0;
    
    // Determine final signal
    ENUM_TRADE_SIGNAL signal = TRADE_SIGNAL_NONE;
    
    if(crossAbove || (m_histogramBuffer[0] > 0 && m_histogramBuffer[0] > m_histogramBuffer[1])) {
        // Bullish signal
        newEvent.direction = 1;
        newEvent.strength = 0.5 + histogramStrength * 0.3 + consistencyBonus;
        signal = TRADE_SIGNAL_BUY;
        confidence = newEvent.strength;
    }
    else if(crossBelow || (m_histogramBuffer[0] < 0 && m_histogramBuffer[0] < m_histogramBuffer[1])) {
        // Bearish signal
        newEvent.direction = -1;
        newEvent.strength = 0.5 + histogramStrength * 0.3 + consistencyBonus;
        signal = TRADE_SIGNAL_SELL;
        confidence = newEvent.strength;
    }
    else {
        // No clear signal
        newEvent.direction = 0;
        newEvent.strength = 0.0;
        signal = TRADE_SIGNAL_NONE;
        confidence = 0.0;
    }
    
    // Add event to history
    if(m_macdEvents != NULL) {
        m_macdEvents.Add(newEvent);
        
        // Keep only the last 100 events
        while(m_macdEvents.Total() > 100) {
            m_macdEvents.Delete(0);
        }
    } else {
        delete newEvent;
    }
    
    return signal;
}

//+------------------------------------------------------------------+
//| Handle tick event                                                |
//+------------------------------------------------------------------+
void CStrategyMACD::OnTick()
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
void CStrategyMACD::OnNewBar(const string symbol, const ENUM_TIMEFRAMES timeframe)
{
    if(!IsEnabled() || symbol == "" || timeframe == 0) return;
    
    // Update MACD on new bar
    UpdateMACD(symbol, timeframe);
}

//+------------------------------------------------------------------+
//| Set MACD parameters                                              |
//+------------------------------------------------------------------+
void CStrategyMACD::SetParameters(int fastEMA, int slowEMA, int signalEMA)
{
    if(fastEMA > 0) m_fastEMA = fastEMA;
    if(slowEMA > 0) m_slowEMA = slowEMA;
    if(signalEMA > 0) m_signalEMA = signalEMA;
}

#endif // __STRATEGY_MACD_MQH__
