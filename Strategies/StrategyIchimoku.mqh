//+------------------------------------------------------------------+
//| Ichimoku Cloud Strategy Module                                    |
//+------------------------------------------------------------------+
#ifndef __STRATEGY_ICHIMOKU_MQH__
#define __STRATEGY_ICHIMOKU_MQH__

// Ichimoku Cloud Strategy - Uses Ichimoku Kinko Hyo indicator for trend identification,
// support/resistance levels, and momentum signals

// Ichimoku event structure for tracking signal quality
struct IchimokuEvent {
    datetime time;
    double tenkan;      // Conversion Line (Tenkan-sen)
    double kijun;       // Base Line (Kijun-sen)
    double senkouspanA; // Leading Span A (Senkou Span A)
    double senkouspanB; // Leading Span B (Senkou Span B)
    double chikou;      // Lagging Span (Chikou Span)
    double price;       // Current price
    int direction;      // 1 for bullish, -1 for bearish, 0 for neutral
    double strength;    // Signal strength 0.0-1.0
    bool isValid;
};

//+------------------------------------------------------------------+
//| Ichimoku Cloud Strategy Class                                     |
//+------------------------------------------------------------------+
class CStrategyIchimoku : public CStrategyBase {
private:
    IchimokuEvent m_events[100]; // Circular buffer for events
    int m_eventCount;
    int m_tenkan_period;
    int m_kijun_period;
    int m_senkou_span_b_period;
    int m_handle;

    void UpdateEvents();

public:
    CStrategyIchimoku(const string name = "Ichimoku Strategy", int magic = 0);
    virtual ~CStrategyIchimoku();

    virtual bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeMgr, void* posSizer) override;
    virtual void Deinit() override;
    virtual ENUM_TRADE_SIGNAL GetSignal(double &confidence) override;
    virtual ENUM_STRATEGY_TYPE GetType() const override { return STRATEGY_ICHIMOKU; }
    
    // Configuration
    void SetPeriods(int tenkan, int kijun, int senkouB) {
        m_tenkan_period = tenkan;
        m_kijun_period = kijun;
        m_senkou_span_b_period = senkouB;
    }
};

CStrategyIchimoku::CStrategyIchimoku(const string name, int magic)
    : CStrategyBase(name, magic),
      m_eventCount(0),
      m_tenkan_period(9),
      m_kijun_period(26),
      m_senkou_span_b_period(52),
      m_handle(INVALID_HANDLE) {}

CStrategyIchimoku::~CStrategyIchimoku() {
    Deinit();
}

bool CStrategyIchimoku::Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeMgr, void* posSizer) {
    if(!CStrategyBase::Init(symbol, timeframe, tradeMgr, posSizer)) return false;
    
    m_handle = iIchimoku(m_symbol, m_timeframe, m_tenkan_period, m_kijun_period, m_senkou_span_b_period);
    if(m_handle == INVALID_HANDLE) {
        Print("Failed to create Ichimoku indicator handle for ", m_symbol);
        return false;
    }
    
    return true;
}

void CStrategyIchimoku::Deinit() {
    if(m_handle != INVALID_HANDLE) {
        IndicatorRelease(m_handle);
        m_handle = INVALID_HANDLE;
    }
    CStrategyBase::Deinit();
}

ENUM_TRADE_SIGNAL CStrategyIchimoku::GetSignal(double &confidence) {
    if(!IsEnabled() || !m_is_initialized || m_handle == INVALID_HANDLE) {
        confidence = 0.0;
        return TRADE_SIGNAL_NONE;
    }

    confidence = 0.0;
    
    // Define dynamic buffers for Ichimoku values
    double tenkanBuffer[];     // Conversion Line (Tenkan-sen)
    double kijunBuffer[];      // Base Line (Kijun-sen)
    double spanABuffer[];      // Leading Span A (Senkou Span A)
    double spanBBuffer[];      // Leading Span B (Senkou Span B)
    double chikouBuffer[];     // Lagging Span (Chikou Span) - need history
    double close[];            // Close prices
    
    // Set arrays as series before CopyBuffer (most recent data at index 0)
    ArraySetAsSeries(tenkanBuffer, true);
    ArraySetAsSeries(kijunBuffer, true);
    ArraySetAsSeries(spanABuffer, true);
    ArraySetAsSeries(spanBBuffer, true);
    ArraySetAsSeries(chikouBuffer, true);
    ArraySetAsSeries(close, true);
    
    // Copy Ichimoku data to buffers
    if(CopyBuffer(m_handle, 0, 0, 2, tenkanBuffer) <= 0 ||
       CopyBuffer(m_handle, 1, 0, 2, kijunBuffer) <= 0 ||
       CopyBuffer(m_handle, 2, 0, 2, spanABuffer) <= 0 ||
       CopyBuffer(m_handle, 3, 0, 2, spanBBuffer) <= 0 ||
       CopyBuffer(m_handle, 4, 0, 27, chikouBuffer) <= 0) {
        return TRADE_SIGNAL_NONE;
    }
    
    // Get price data
    if(CopyClose(m_symbol, m_timeframe, 0, 27, close) <= 0) {
        return TRADE_SIGNAL_NONE;
    }
    
    // Signal components
    bool priceAboveCloud = close[0] > spanABuffer[0] && close[0] > spanBBuffer[0];
    bool priceBelowCloud = close[0] < spanABuffer[0] && close[0] < spanBBuffer[0];
    bool bullishCloud = spanABuffer[0] > spanBBuffer[0];
    bool bearishCloud = spanABuffer[0] < spanBBuffer[0];
    
    // Tenkan/Kijun Cross (TK Cross)
    bool tkCrossBull = tenkanBuffer[1] <= kijunBuffer[1] && tenkanBuffer[0] > kijunBuffer[0];
    bool tkCrossBear = tenkanBuffer[1] >= kijunBuffer[1] && tenkanBuffer[0] < kijunBuffer[0];
    
    // Chikou Span analysis (Lagging Span) - checks 26 periods ago
    bool chikouAbovePrice = chikouBuffer[26] > close[26]; 
    bool chikouBelowPrice = chikouBuffer[26] < close[26];
    
    // Price/Kumo breakout
    bool priceBreakingAboveCloud = close[1] <= MathMax(spanABuffer[1], spanBBuffer[1]) && close[0] > MathMax(spanABuffer[0], spanBBuffer[0]);
    bool priceBreakingBelowCloud = close[1] >= MathMin(spanABuffer[1], spanBBuffer[1]) && close[0] < MathMin(spanABuffer[0], spanBBuffer[0]);
    
    // Calculate signal strength based on multiple factors
    double cloudStrength = bullishCloud ? 0.2 : (bearishCloud ? -0.2 : 0.0);
    double tkCrossStrength = tkCrossBull ? 0.3 : (tkCrossBear ? -0.3 : 0.0);
    double chikouStrength = chikouAbovePrice ? 0.2 : (chikouBelowPrice ? -0.2 : 0.0);
    double pricePositionStrength = priceAboveCloud ? 0.2 : (priceBelowCloud ? -0.2 : 0.0);
    double breakoutStrength = priceBreakingAboveCloud ? 0.3 : (priceBreakingBelowCloud ? -0.3 : 0.0);
    
    // Combine all factors for final signal
    double totalStrength = cloudStrength + tkCrossStrength + chikouStrength + pricePositionStrength + breakoutStrength;
    
    // Strong bullish signal
    if((tkCrossBull && priceAboveCloud) || priceBreakingAboveCloud || 
       (tenkanBuffer[0] > kijunBuffer[0] && priceAboveCloud && chikouAbovePrice)) {
        confidence = 0.5 + MathAbs(totalStrength);
        return TRADE_SIGNAL_BUY;
    }
    // Strong bearish signal
    else if((tkCrossBear && priceBelowCloud) || priceBreakingBelowCloud || 
            (tenkanBuffer[0] < kijunBuffer[0] && priceBelowCloud && chikouBelowPrice)) {
        confidence = 0.5 + MathAbs(totalStrength);
        return TRADE_SIGNAL_SELL;
    }
    // Weaker signals
    else if(totalStrength > 0.3) {
        confidence = 0.3 + totalStrength;
        return TRADE_SIGNAL_BUY;
    }
    else if(totalStrength < -0.3) {
        confidence = 0.3 + MathAbs(totalStrength);
        return TRADE_SIGNAL_SELL;
    }
    
    return TRADE_SIGNAL_NONE;
}

#endif // __STRATEGY_ICHIMOKU_MQH__
