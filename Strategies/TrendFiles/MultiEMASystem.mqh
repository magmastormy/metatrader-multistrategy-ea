//+------------------------------------------------------------------+
//| MultiEMASystem.mqh                                               |
//| Multi-Speed EMA System for Trend Strategy                        |
//| Uses 8, 21, 50, 200 EMAs for multi-level trend analysis          |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Multi-Strategy EA"
#property version   "2.00"
#property strict

#ifndef __TREND_MULTI_EMA_SYSTEM_MQH__
#define __TREND_MULTI_EMA_SYSTEM_MQH__

//+------------------------------------------------------------------+
//| Trend State Structure                                            |
//+------------------------------------------------------------------+
struct STrendState
{
    bool        isUptrend;
    bool        isDowntrend;
    bool        isRanging;
    double      strength;           // ADX value
    double      slope;              // EMA slope
    int         consistency;        // Bars maintaining trend
    double      momentum;           // Short-term momentum
    
    STrendState() : isUptrend(false), isDowntrend(false), isRanging(true),
                    strength(0), slope(0), consistency(0), momentum(0) {}
};

//+------------------------------------------------------------------+
//| EMA Alignment State                                              |
//+------------------------------------------------------------------+
enum ENUM_EMA_ALIGNMENT
{
    EMA_PERFECT_BULL,       // 8 > 21 > 50 > 200 (all rising)
    EMA_STRONG_BULL,        // 8 > 21 > 50 > 200 (some rising)
    EMA_WEAK_BULL,          // 8 > 21, but mixed lower
    EMA_NEUTRAL,            // No clear alignment
    EMA_WEAK_BEAR,          // 8 < 21, but mixed lower
    EMA_STRONG_BEAR,        // 8 < 21 < 50 < 200 (some falling)
    EMA_PERFECT_BEAR        // 8 < 21 < 50 < 200 (all falling)
};

//+------------------------------------------------------------------+
//| Multi-EMA System Class                                           |
//+------------------------------------------------------------------+
class CMultiEMASystem
{
private:
    string              m_symbol;
    ENUM_TIMEFRAMES     m_timeframe;
    
    // EMA handles
    int                 m_ema8Handle;       // Momentum EMA
    int                 m_ema21Handle;      // Swing trend EMA
    int                 m_ema50Handle;      // Intermediate trend EMA
    int                 m_ema200Handle;     // Major trend EMA
    int                 m_adxHandle;        // ADX for strength
    
    // EMA values (current and previous for crossover detection)
    double              m_ema8[3];
    double              m_ema21[3];
    double              m_ema50[3];
    double              m_ema200[3];
    double              m_adx[2];
    double              m_plusDI[1];
    double              m_minusDI[1];
    
    // State
    STrendState         m_currentTrend;
    ENUM_EMA_ALIGNMENT  m_alignment;
    int                 m_consistentBars;
    
    // Internal methods
    bool                UpdateEMAValues();
    void                CalculateTrendState();
    void                CalculateAlignment();
    
public:
                        CMultiEMASystem();
                       ~CMultiEMASystem();
    
    // Initialization
    bool                Initialize(string symbol, ENUM_TIMEFRAMES timeframe);
    void                Deinit();
    
    // Update
    void                Update();
    
    // Getters
    STrendState         GetTrendState() const { return m_currentTrend; }
    ENUM_EMA_ALIGNMENT  GetAlignment() const { return m_alignment; }
    
    // EMA values
    double              GetEMA8(int shift = 0) const { return (shift < 3) ? m_ema8[shift] : 0; }
    double              GetEMA21(int shift = 0) const { return (shift < 3) ? m_ema21[shift] : 0; }
    double              GetEMA50(int shift = 0) const { return (shift < 3) ? m_ema50[shift] : 0; }
    double              GetEMA200(int shift = 0) const { return (shift < 3) ? m_ema200[shift] : 0; }
    double              GetADX() const { return m_adx[0]; }
    double              GetPlusDI() const { return m_plusDI[0]; }
    double              GetMinusDI() const { return m_minusDI[0]; }
    
    // Crossover detection
    bool                HasGoldenCross8_21();    // 8 crosses above 21
    bool                HasDeathCross8_21();     // 8 crosses below 21
    bool                HasGoldenCross21_50();   // 21 crosses above 50
    bool                HasDeathCross21_50();    // 21 crosses below 50
    bool                HasGoldenCross50_200();  // 50 crosses above 200
    bool                HasDeathCross50_200();   // 50 crosses below 200
    
    // Trend checks
    bool                IsStrongUptrend();
    bool                IsStrongDowntrend();
    bool                IsPerfectBullAlignment();
    bool                IsPerfectBearAlignment();
    bool                IsAboveAllEMAs(double price);
    bool                IsBelowAllEMAs(double price);
    
    // Pullback detection
    bool                IsPullbackTo21EMA(double price, double tolerance = 10);
    bool                IsPullbackTo50EMA(double price, double tolerance = 10);
    
    // Slope calculation
    double              GetEMASlope(int emaPeriod, int barsBack = 3);
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CMultiEMASystem::CMultiEMASystem() :
    m_symbol(""),
    m_timeframe(PERIOD_CURRENT),
    m_ema8Handle(INVALID_HANDLE),
    m_ema21Handle(INVALID_HANDLE),
    m_ema50Handle(INVALID_HANDLE),
    m_ema200Handle(INVALID_HANDLE),
    m_adxHandle(INVALID_HANDLE),
    m_alignment(EMA_NEUTRAL),
    m_consistentBars(0)
{
    ArrayInitialize(m_ema8, 0);
    ArrayInitialize(m_ema21, 0);
    ArrayInitialize(m_ema50, 0);
    ArrayInitialize(m_ema200, 0);
    ArrayInitialize(m_adx, 0);
    ArrayInitialize(m_plusDI, 0);
    ArrayInitialize(m_minusDI, 0);
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CMultiEMASystem::~CMultiEMASystem()
{
    Deinit();
}

//+------------------------------------------------------------------+
//| Initialize                                                       |
//+------------------------------------------------------------------+
bool CMultiEMASystem::Initialize(string symbol, ENUM_TIMEFRAMES timeframe)
{
    m_symbol = symbol;
    m_timeframe = timeframe;
    
    // Create EMA handles
    m_ema8Handle = iMA(symbol, timeframe, 8, 0, MODE_EMA, PRICE_CLOSE);
    m_ema21Handle = iMA(symbol, timeframe, 21, 0, MODE_EMA, PRICE_CLOSE);
    m_ema50Handle = iMA(symbol, timeframe, 50, 0, MODE_EMA, PRICE_CLOSE);
    m_ema200Handle = iMA(symbol, timeframe, 200, 0, MODE_EMA, PRICE_CLOSE);
    m_adxHandle = iADX(symbol, timeframe, 14);
    
    if(m_ema8Handle == INVALID_HANDLE || m_ema21Handle == INVALID_HANDLE ||
       m_ema50Handle == INVALID_HANDLE || m_ema200Handle == INVALID_HANDLE ||
       m_adxHandle == INVALID_HANDLE)
    {
        Print("[MultiEMA] Failed to create indicator handles");
        return false;
    }
    
    // Initial update
    Update();
    
    return true;
}

//+------------------------------------------------------------------+
//| Deinitialize                                                     |
//+------------------------------------------------------------------+
void CMultiEMASystem::Deinit()
{
    if(m_ema8Handle != INVALID_HANDLE) { IndicatorRelease(m_ema8Handle); m_ema8Handle = INVALID_HANDLE; }
    if(m_ema21Handle != INVALID_HANDLE) { IndicatorRelease(m_ema21Handle); m_ema21Handle = INVALID_HANDLE; }
    if(m_ema50Handle != INVALID_HANDLE) { IndicatorRelease(m_ema50Handle); m_ema50Handle = INVALID_HANDLE; }
    if(m_ema200Handle != INVALID_HANDLE) { IndicatorRelease(m_ema200Handle); m_ema200Handle = INVALID_HANDLE; }
    if(m_adxHandle != INVALID_HANDLE) { IndicatorRelease(m_adxHandle); m_adxHandle = INVALID_HANDLE; }
}

//+------------------------------------------------------------------+
//| Update EMA Values                                                |
//+------------------------------------------------------------------+
bool CMultiEMASystem::UpdateEMAValues()
{
    if(CopyBuffer(m_ema8Handle, 0, 0, 3, m_ema8) < 3) return false;
    if(CopyBuffer(m_ema21Handle, 0, 0, 3, m_ema21) < 3) return false;
    if(CopyBuffer(m_ema50Handle, 0, 0, 3, m_ema50) < 3) return false;
    if(CopyBuffer(m_ema200Handle, 0, 0, 3, m_ema200) < 3) return false;
    if(CopyBuffer(m_adxHandle, 0, 0, 2, m_adx) < 2) return false;
    if(CopyBuffer(m_adxHandle, 1, 0, 1, m_plusDI) < 1) return false;
    if(CopyBuffer(m_adxHandle, 2, 0, 1, m_minusDI) < 1) return false;
    
    return true;
}

//+------------------------------------------------------------------+
//| Calculate Trend State                                            |
//+------------------------------------------------------------------+
void CMultiEMASystem::CalculateTrendState()
{
    STrendState prevState = m_currentTrend;
    
    // Perfect uptrend: 8 > 21 > 50 > 200 and all rising
    m_currentTrend.isUptrend = (
        m_ema8[0] > m_ema21[0] &&
        m_ema21[0] > m_ema50[0] &&
        m_ema50[0] > m_ema200[0] &&
        m_ema8[0] > m_ema8[1]  // 8 EMA rising
    );
    
    // Perfect downtrend: 8 < 21 < 50 < 200 and all falling
    m_currentTrend.isDowntrend = (
        m_ema8[0] < m_ema21[0] &&
        m_ema21[0] < m_ema50[0] &&
        m_ema50[0] < m_ema200[0] &&
        m_ema8[0] < m_ema8[1]  // 8 EMA falling
    );
    
    m_currentTrend.isRanging = (!m_currentTrend.isUptrend && !m_currentTrend.isDowntrend);
    
    // Trend strength from ADX
    m_currentTrend.strength = m_adx[0];
    
    // Calculate 21 EMA slope
    if(m_ema21[2] > 0)
        m_currentTrend.slope = (m_ema21[0] - m_ema21[2]) / m_ema21[2];
    else
        m_currentTrend.slope = 0;
    
    // Momentum (8 EMA direction)
    m_currentTrend.momentum = (m_ema8[0] - m_ema8[1]) / m_ema8[1];
    
    // Track consistency
    if((m_currentTrend.isUptrend && prevState.isUptrend) ||
       (m_currentTrend.isDowntrend && prevState.isDowntrend))
    {
        m_consistentBars++;
    }
    else
    {
        m_consistentBars = 0;
    }
    
    m_currentTrend.consistency = m_consistentBars;
}

//+------------------------------------------------------------------+
//| Calculate EMA Alignment                                          |
//+------------------------------------------------------------------+
void CMultiEMASystem::CalculateAlignment()
{
    bool ema8Rising = (m_ema8[0] > m_ema8[1]);
    bool ema21Rising = (m_ema21[0] > m_ema21[1]);
    bool ema50Rising = (m_ema50[0] > m_ema50[1]);
    
    // Perfect bull: all aligned and rising
    if(m_ema8[0] > m_ema21[0] && m_ema21[0] > m_ema50[0] && m_ema50[0] > m_ema200[0])
    {
        if(ema8Rising && ema21Rising && ema50Rising)
            m_alignment = EMA_PERFECT_BULL;
        else
            m_alignment = EMA_STRONG_BULL;
    }
    // Perfect bear: all aligned and falling
    else if(m_ema8[0] < m_ema21[0] && m_ema21[0] < m_ema50[0] && m_ema50[0] < m_ema200[0])
    {
        if(!ema8Rising && !ema21Rising && !ema50Rising)
            m_alignment = EMA_PERFECT_BEAR;
        else
            m_alignment = EMA_STRONG_BEAR;
    }
    // Weak bull: 8 > 21 but lower not aligned
    else if(m_ema8[0] > m_ema21[0])
    {
        m_alignment = EMA_WEAK_BULL;
    }
    // Weak bear: 8 < 21 but lower not aligned
    else if(m_ema8[0] < m_ema21[0])
    {
        m_alignment = EMA_WEAK_BEAR;
    }
    else
    {
        m_alignment = EMA_NEUTRAL;
    }
}

//+------------------------------------------------------------------+
//| Update                                                           |
//+------------------------------------------------------------------+
void CMultiEMASystem::Update()
{
    if(!UpdateEMAValues())
        return;
    
    CalculateTrendState();
    CalculateAlignment();
}

//+------------------------------------------------------------------+
//| Crossover Detection                                              |
//+------------------------------------------------------------------+
bool CMultiEMASystem::HasGoldenCross8_21()
{
    return (m_ema8[0] > m_ema21[0] && m_ema8[1] <= m_ema21[1]);
}

bool CMultiEMASystem::HasDeathCross8_21()
{
    return (m_ema8[0] < m_ema21[0] && m_ema8[1] >= m_ema21[1]);
}

bool CMultiEMASystem::HasGoldenCross21_50()
{
    return (m_ema21[0] > m_ema50[0] && m_ema21[1] <= m_ema50[1]);
}

bool CMultiEMASystem::HasDeathCross21_50()
{
    return (m_ema21[0] < m_ema50[0] && m_ema21[1] >= m_ema50[1]);
}

bool CMultiEMASystem::HasGoldenCross50_200()
{
    return (m_ema50[0] > m_ema200[0] && m_ema50[1] <= m_ema200[1]);
}

bool CMultiEMASystem::HasDeathCross50_200()
{
    return (m_ema50[0] < m_ema200[0] && m_ema50[1] >= m_ema200[1]);
}

//+------------------------------------------------------------------+
//| Trend Checks                                                     |
//+------------------------------------------------------------------+
bool CMultiEMASystem::IsStrongUptrend()
{
    return (m_currentTrend.isUptrend && m_currentTrend.strength > 25);
}

bool CMultiEMASystem::IsStrongDowntrend()
{
    return (m_currentTrend.isDowntrend && m_currentTrend.strength > 25);
}

bool CMultiEMASystem::IsPerfectBullAlignment()
{
    return (m_alignment == EMA_PERFECT_BULL);
}

bool CMultiEMASystem::IsPerfectBearAlignment()
{
    return (m_alignment == EMA_PERFECT_BEAR);
}

bool CMultiEMASystem::IsAboveAllEMAs(double price)
{
    return (price > m_ema8[0] && price > m_ema21[0] && 
            price > m_ema50[0] && price > m_ema200[0]);
}

bool CMultiEMASystem::IsBelowAllEMAs(double price)
{
    return (price < m_ema8[0] && price < m_ema21[0] && 
            price < m_ema50[0] && price < m_ema200[0]);
}

//+------------------------------------------------------------------+
//| Pullback Detection                                               |
//+------------------------------------------------------------------+
bool CMultiEMASystem::IsPullbackTo21EMA(double price, double tolerance)
{
    double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    double distance = MathAbs(price - m_ema21[0]) / point;
    return (distance <= tolerance);
}

bool CMultiEMASystem::IsPullbackTo50EMA(double price, double tolerance)
{
    double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    double distance = MathAbs(price - m_ema50[0]) / point;
    return (distance <= tolerance);
}

//+------------------------------------------------------------------+
//| Get EMA Slope                                                    |
//+------------------------------------------------------------------+
double CMultiEMASystem::GetEMASlope(int emaPeriod, int barsBack)
{
    double current = 0, past = 0;
    
    switch(emaPeriod)
    {
        case 8:  current = m_ema8[0]; past = m_ema8[MathMin(barsBack, 2)]; break;
        case 21: current = m_ema21[0]; past = m_ema21[MathMin(barsBack, 2)]; break;
        case 50: current = m_ema50[0]; past = m_ema50[MathMin(barsBack, 2)]; break;
        case 200: current = m_ema200[0]; past = m_ema200[MathMin(barsBack, 2)]; break;
        default: return 0;
    }
    
    if(past > 0)
        return (current - past) / past;
    
    return 0;
}

#endif // __TREND_MULTI_EMA_SYSTEM_MQH__
