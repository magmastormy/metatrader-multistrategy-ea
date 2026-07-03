//+------------------------------------------------------------------+
//| TrendSignalEnhancers.mqh                                         |
//| EMA Slope Detection & Trend Freshness Scoring                    |
//| Batch 103: Signal quality boosters for Trend Strategy             |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Multi-Strategy EA"
#property version   "1.00"
#property strict

#ifndef TREND_SIGNAL_ENHANCERS_MQH
#define TREND_SIGNAL_ENHANCERS_MQH

#include "MultiEMASystem.mqh"
#include "../../IndicatorManager.mqh"

//+------------------------------------------------------------------+
//| Trend Signal Enhancer Class                                      |
//| Provides EMA slope momentum detection and trend freshness scoring|
//+------------------------------------------------------------------+
class CTrendSignalEnhancer
{
private:
    string              m_symbol;
    ENUM_TIMEFRAMES     m_timeframe;
    CMultiEMASystem*    m_emaSystem;
    int                 m_atrHandle;

    double              GetATR();

public:
                        CTrendSignalEnhancer();
                       ~CTrendSignalEnhancer();

    bool                Initialize(const string symbol, ENUM_TIMEFRAMES tf, CMultiEMASystem* emaSystem);

    // EMA slope momentum: slope > 0.1*ATR = strong directional momentum
    bool                HasEMAMomentum(ENUM_TRADE_SIGNAL direction);

    // Trend freshness: new trends get +15%, mature trends get -10%
    double              GetTrendFreshnessMultiplier();
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CTrendSignalEnhancer::CTrendSignalEnhancer() :
    m_symbol(""),
    m_timeframe(PERIOD_CURRENT),
    m_emaSystem(NULL),
    m_atrHandle(INVALID_HANDLE)
{
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CTrendSignalEnhancer::~CTrendSignalEnhancer()
{
    // ATR handle managed by CIndicatorManager
    m_atrHandle = INVALID_HANDLE;
}

//+------------------------------------------------------------------+
//| Initialize                                                       |
//+------------------------------------------------------------------+
bool CTrendSignalEnhancer::Initialize(const string symbol, ENUM_TIMEFRAMES tf, CMultiEMASystem* emaSystem)
{
    m_symbol = symbol;
    m_timeframe = tf;
    m_emaSystem = emaSystem;

    m_atrHandle = CIndicatorManager::Instance().GetATRHandle(m_symbol, m_timeframe, 14);

    return (m_emaSystem != NULL);
}

//+------------------------------------------------------------------+
//| Get ATR Value                                                    |
//+------------------------------------------------------------------+
double CTrendSignalEnhancer::GetATR()
{
    if(m_atrHandle == INVALID_HANDLE)
        m_atrHandle = CIndicatorManager::Instance().GetATRHandle(m_symbol, m_timeframe, 14);
    if(m_atrHandle == INVALID_HANDLE) return 0;

    double atrBuf[1];
    if(CopyBuffer(m_atrHandle, 0, 0, 1, atrBuf) > 0)
        return atrBuf[0];

    return 0;
}

//+------------------------------------------------------------------+
//| Check EMA Slope Momentum                                         |
//| Slope of EMA8 over 3 bars > 0.1*ATR = strong momentum           |
//+------------------------------------------------------------------+
bool CTrendSignalEnhancer::HasEMAMomentum(ENUM_TRADE_SIGNAL direction)
{
    if(m_emaSystem == NULL) return false;

    double slope = m_emaSystem.GetEMASlope(8, 3);
    double atr = GetATR();
    if(atr <= 0) return false;

    // Slope is ATR-change per bar; threshold = 0.1 * ATR
    if(direction == TRADE_SIGNAL_BUY)
        return slope > 0.1;
    if(direction == TRADE_SIGNAL_SELL)
        return slope < -0.1;

    return false;
}

//+------------------------------------------------------------------+
//| Get Trend Freshness Multiplier                                   |
//| New trends (consistency < 10) = +15% confidence                  |
//| Mature trends (consistency > 50) = -10% confidence               |
//+------------------------------------------------------------------+
double CTrendSignalEnhancer::GetTrendFreshnessMultiplier()
{
    if(m_emaSystem == NULL) return 1.0;

    STrendState state = m_emaSystem.GetTrendState();

    if(state.consistency < 10)
        return 1.15;   // New trend: +15% confidence
    if(state.consistency > 50)
        return 0.90;   // Mature trend: -10% confidence

    return 1.0;
}

#endif // __TREND_SIGNAL_ENHANCERS_MQH__
