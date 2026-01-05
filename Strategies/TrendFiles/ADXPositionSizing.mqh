//+------------------------------------------------------------------+
//| ADXPositionSizing.mqh                                            |
//| ADX-Based Adaptive Position Sizing                               |
//| Adjusts lot size based on trend strength                         |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Multi-Strategy EA"
#property version   "2.00"
#property strict

#ifndef __TREND_ADX_POSITION_SIZING_MQH__
#define __TREND_ADX_POSITION_SIZING_MQH__

//+------------------------------------------------------------------+
//| ADX Tier Enum                                                    |
//+------------------------------------------------------------------+
enum ENUM_ADX_TIER
{
    ADX_NO_TREND,       // ADX < 20 - no trade
    ADX_WEAK_TREND,     // ADX 20-25 - half size
    ADX_NORMAL_TREND,   // ADX 25-35 - full size
    ADX_STRONG_TREND,   // ADX 35-45 - 1.3x size
    ADX_VERY_STRONG     // ADX > 45 - 1.5x size
};

//+------------------------------------------------------------------+
//| ADX Position Sizing Class                                        |
//+------------------------------------------------------------------+
class CADXPositionSizing
{
private:
    string              m_symbol;
    ENUM_TIMEFRAMES     m_timeframe;
    
    // ADX handle
    int                 m_adxHandle;
    
    // Configuration
    double              m_baseRiskPercent;      // Base risk per trade (e.g., 1%)
    double              m_weakTrendMultiplier;  // 0.5x for weak trends
    double              m_normalMultiplier;     // 1.0x for normal trends
    double              m_strongMultiplier;     // 1.3x for strong trends
    double              m_veryStrongMultiplier; // 1.5x for very strong
    
    // ADX thresholds
    double              m_noTrendThreshold;     // Below this = no trade
    double              m_weakThreshold;        // 20-25
    double              m_normalThreshold;      // 25-35
    double              m_strongThreshold;      // 35-45
    
    // Internal methods
    double              GetADX();
    ENUM_ADX_TIER       GetADXTier(double adx);
    
public:
                        CADXPositionSizing();
                       ~CADXPositionSizing();
    
    // Initialization
    bool                Initialize(const string symbol, ENUM_TIMEFRAMES timeframe);
    void                Deinit();
    
    // Position sizing
    double              GetPositionSizeMultiplier();
    double              GetAdjustedRiskPercent();
    double              CalculateLotSize(double stopLossPips);
    bool                ShouldTrade();
    
    // Getters
    ENUM_ADX_TIER       GetCurrentTier();
    double              GetCurrentADX() { return GetADX(); }
    string              GetTierName();
    
    // Configuration
    void                SetBaseRiskPercent(double risk) { m_baseRiskPercent = risk; }
    void                SetMultipliers(double weak, double normal, double strong, double veryStrong);
    void                SetThresholds(double noTrend, double weak, double normal, double strong);
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CADXPositionSizing::CADXPositionSizing() :
    m_symbol(""),
    m_timeframe(PERIOD_CURRENT),
    m_adxHandle(INVALID_HANDLE),
    m_baseRiskPercent(1.0),
    m_weakTrendMultiplier(0.5),
    m_normalMultiplier(1.0),
    m_strongMultiplier(1.3),
    m_veryStrongMultiplier(1.5),
    m_noTrendThreshold(20.0),
    m_weakThreshold(25.0),
    m_normalThreshold(35.0),
    m_strongThreshold(45.0)
{
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CADXPositionSizing::~CADXPositionSizing()
{
    Deinit();
}

//+------------------------------------------------------------------+
//| Initialize                                                       |
//+------------------------------------------------------------------+
bool CADXPositionSizing::Initialize(const string symbol, ENUM_TIMEFRAMES timeframe)
{
    m_symbol = symbol;
    m_timeframe = timeframe;
    
    m_adxHandle = iADX(symbol, timeframe, 14);
    
    if(m_adxHandle == INVALID_HANDLE)
    {
        Print("[ADXSizing] Failed to create ADX handle");
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Deinitialize                                                     |
//+------------------------------------------------------------------+
void CADXPositionSizing::Deinit()
{
    if(m_adxHandle != INVALID_HANDLE)
    {
        IndicatorRelease(m_adxHandle);
        m_adxHandle = INVALID_HANDLE;
    }
}

//+------------------------------------------------------------------+
//| Get ADX Value                                                    |
//+------------------------------------------------------------------+
double CADXPositionSizing::GetADX()
{
    if(m_adxHandle == INVALID_HANDLE) return 0;
    
    double adx[];
    ArraySetAsSeries(adx, true);
    
    if(CopyBuffer(m_adxHandle, 0, 0, 1, adx) <= 0)
        return 0;
    
    return adx[0];
}

//+------------------------------------------------------------------+
//| Get ADX Tier                                                     |
//+------------------------------------------------------------------+
ENUM_ADX_TIER CADXPositionSizing::GetADXTier(double adx)
{
    if(adx < m_noTrendThreshold)
        return ADX_NO_TREND;
    else if(adx < m_weakThreshold)
        return ADX_WEAK_TREND;
    else if(adx < m_normalThreshold)
        return ADX_NORMAL_TREND;
    else if(adx < m_strongThreshold)
        return ADX_STRONG_TREND;
    else
        return ADX_VERY_STRONG;
}

//+------------------------------------------------------------------+
//| Get Current Tier                                                 |
//+------------------------------------------------------------------+
ENUM_ADX_TIER CADXPositionSizing::GetCurrentTier()
{
    return GetADXTier(GetADX());
}

//+------------------------------------------------------------------+
//| Get Tier Name                                                    |
//+------------------------------------------------------------------+
string CADXPositionSizing::GetTierName()
{
    ENUM_ADX_TIER tier = GetCurrentTier();
    
    switch(tier)
    {
        case ADX_NO_TREND:      return "No Trend (< 20)";
        case ADX_WEAK_TREND:    return "Weak Trend (20-25)";
        case ADX_NORMAL_TREND:  return "Normal Trend (25-35)";
        case ADX_STRONG_TREND:  return "Strong Trend (35-45)";
        case ADX_VERY_STRONG:   return "Very Strong (> 45)";
        default:                return "Unknown";
    }
}

//+------------------------------------------------------------------+
//| Should Trade                                                     |
//+------------------------------------------------------------------+
bool CADXPositionSizing::ShouldTrade()
{
    return (GetADX() >= m_noTrendThreshold);
}

//+------------------------------------------------------------------+
//| Get Position Size Multiplier                                     |
//+------------------------------------------------------------------+
double CADXPositionSizing::GetPositionSizeMultiplier()
{
    ENUM_ADX_TIER tier = GetCurrentTier();
    
    switch(tier)
    {
        case ADX_NO_TREND:      return 0.0;  // No trade
        case ADX_WEAK_TREND:    return m_weakTrendMultiplier;
        case ADX_NORMAL_TREND:  return m_normalMultiplier;
        case ADX_STRONG_TREND:  return m_strongMultiplier;
        case ADX_VERY_STRONG:   return m_veryStrongMultiplier;
        default:                return 0.0;
    }
}

//+------------------------------------------------------------------+
//| Get Adjusted Risk Percent                                        |
//+------------------------------------------------------------------+
double CADXPositionSizing::GetAdjustedRiskPercent()
{
    return m_baseRiskPercent * GetPositionSizeMultiplier();
}

//+------------------------------------------------------------------+
//| Calculate Lot Size                                               |
//+------------------------------------------------------------------+
double CADXPositionSizing::CalculateLotSize(double stopLossPips)
{
    if(stopLossPips <= 0) return 0;
    if(!ShouldTrade()) return 0;
    
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double adjustedRisk = GetAdjustedRiskPercent() / 100.0;
    double riskAmount = balance * adjustedRisk;
    
    // Get tick value and size
    double tickValue = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
    double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    
    if(tickValue <= 0 || tickSize <= 0 || point <= 0)
        return 0;
    
    // Convert stop loss pips to points
    double stopLossPoints = stopLossPips * 10;  // Assuming 5-digit broker
    
    // Calculate pip value per lot
    double pipValue = tickValue / tickSize * point * 10;  // 10 points per pip
    
    // Calculate lot size
    double lots = riskAmount / (stopLossPips * pipValue);
    
    // Normalize to broker's lot step
    double lotStep = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
    double minLot = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MAX);
    
    lots = MathFloor(lots / lotStep) * lotStep;
    lots = MathMax(minLot, MathMin(maxLot, lots));
    
    return lots;
}

//+------------------------------------------------------------------+
//| Set Multipliers                                                  |
//+------------------------------------------------------------------+
void CADXPositionSizing::SetMultipliers(double weak, double normal, double strong, double veryStrong)
{
    m_weakTrendMultiplier = weak;
    m_normalMultiplier = normal;
    m_strongMultiplier = strong;
    m_veryStrongMultiplier = veryStrong;
}

//+------------------------------------------------------------------+
//| Set Thresholds                                                   |
//+------------------------------------------------------------------+
void CADXPositionSizing::SetThresholds(double noTrend, double weak, double normal, double strong)
{
    m_noTrendThreshold = noTrend;
    m_weakThreshold = weak;
    m_normalThreshold = normal;
    m_strongThreshold = strong;
}

#endif // __TREND_ADX_POSITION_SIZING_MQH__
