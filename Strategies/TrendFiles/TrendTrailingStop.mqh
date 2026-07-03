//+------------------------------------------------------------------+
//| TrendTrailingStop.mqh                                            |
//| Dynamic Trailing Stop System for Trend Strategy                  |
//| Implements EMA-based and ATR-based trailing                      |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Multi-Strategy EA"
#property version   "2.00"
#property strict

#ifndef TREND_TRAILING_STOP_MQH
#define TREND_TRAILING_STOP_MQH

#include "MultiEMASystem.mqh"
#include "../../IndicatorManager.mqh"

//+------------------------------------------------------------------+
//| Trailing Method                                                  |
//+------------------------------------------------------------------+
enum ENUM_TRAILING_METHOD
{
    TRAIL_EMA21,            // Trail below/above 21 EMA
    TRAIL_EMA8,             // Trail below/above 8 EMA (tighter)
    TRAIL_ATR,              // Trail by ATR multiple
    TRAIL_STRUCTURE,        // Trail by swing points
    TRAIL_HYBRID            // Combination of EMA and ATR
};

//+------------------------------------------------------------------+
//| Trade Info Structure                                             |
//+------------------------------------------------------------------+
struct STradeTrailInfo
{
    ulong           ticket;
    double          entryPrice;
    double          currentSL;
    double          highestPrice;     // For buy trades
    double          lowestPrice;      // For sell trades
    bool            isBuy;
    bool            atBreakeven;
    ENUM_TRAILING_METHOD method;
    datetime        openTime;
    
    STradeTrailInfo() : ticket(0), entryPrice(0), currentSL(0), highestPrice(0),
                        lowestPrice(DBL_MAX), isBuy(true), atBreakeven(false),
                        method(TRAIL_EMA21), openTime(0) {}
};

//+------------------------------------------------------------------+
//| Trend Trailing Stop Class                                        |
//+------------------------------------------------------------------+
class CTrendTrailingStop
{
private:
    string              m_symbol;
    ENUM_TIMEFRAMES     m_timeframe;
    
    // Reference to EMA system
    CMultiEMASystem*    m_emaSystem;
    bool                m_ownEmaSystem;
    
    // Configuration
    double              m_breakEvenRR;          // R:R to move to breakeven (e.g., 1.0)
    double              m_breakEvenBuffer;      // Pips buffer above/below entry
    double              m_emaBuffer;            // Pips buffer from EMA
    double              m_atrMultiplier;        // ATR multiplier for trailing
    
    // Internal methods
    double              GetATR(int period = 14);
    double              CalculateNewSL(const STradeTrailInfo &trade);
    bool                ShouldMoveToBreakeven(const STradeTrailInfo &trade);
    
public:
                        CTrendTrailingStop();
                       ~CTrendTrailingStop();
    
    // Initialization
    bool                Initialize(string symbol, ENUM_TIMEFRAMES timeframe,
                                  CMultiEMASystem* emaSystem = NULL);
    void                Deinit();
    
    // Trailing stop calculation
    double              CalculateTrailingStop(STradeTrailInfo &trade);
    double              CalculateBreakevenStop(const STradeTrailInfo &trade);
    
    // Check for early exit
    bool                ShouldExitEarly(const STradeTrailInfo &trade);
    
    // Configuration
    void                SetBreakEvenRR(double rr) { m_breakEvenRR = rr; }
    void                SetBreakEvenBuffer(double pips) { m_breakEvenBuffer = pips; }
    void                SetEMABuffer(double pips) { m_emaBuffer = pips; }
    void                SetATRMultiplier(double mult) { m_atrMultiplier = mult; }
    void                SetTrailingMethod(STradeTrailInfo &tradeInfo, ENUM_TRAILING_METHOD method) 
                        { tradeInfo.method = method; }
    
    // EMA-based stops
    double              GetEMA21TrailStop(bool isBuy);
    double              GetEMA8TrailStop(bool isBuy);
    
    // ATR-based stops
    double              GetATRTrailStop(bool isBuy, double highestOrLowest);
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CTrendTrailingStop::CTrendTrailingStop() :
    m_symbol(""),
    m_timeframe(PERIOD_CURRENT),
    m_emaSystem(NULL),
    m_ownEmaSystem(false),
    m_breakEvenRR(1.5),
    m_breakEvenBuffer(5.0),
    m_emaBuffer(10.0),
    m_atrMultiplier(2.0)
{
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CTrendTrailingStop::~CTrendTrailingStop()
{
    Deinit();
}

//+------------------------------------------------------------------+
//| Initialize                                                       |
//+------------------------------------------------------------------+
bool CTrendTrailingStop::Initialize(string symbol, ENUM_TIMEFRAMES timeframe,
                                    CMultiEMASystem* emaSystem)
{
    m_symbol = symbol;
    m_timeframe = timeframe;
    
    if(emaSystem != NULL)
    {
        m_emaSystem = emaSystem;
        m_ownEmaSystem = false;
    }
    else
    {
        m_emaSystem = new CMultiEMASystem();
        if(m_emaSystem != NULL)
        {
            m_emaSystem.Initialize(symbol, timeframe);
            m_ownEmaSystem = true;
        }
    }
    
    return (m_emaSystem != NULL);
}

//+------------------------------------------------------------------+
//| Deinitialize                                                     |
//+------------------------------------------------------------------+
void CTrendTrailingStop::Deinit()
{
    if(m_ownEmaSystem && m_emaSystem != NULL)
    {
        delete m_emaSystem;
        m_emaSystem = NULL;
    }
}

//+------------------------------------------------------------------+
//| Get ATR                                                          |
//+------------------------------------------------------------------+
double CTrendTrailingStop::GetATR(int period)
{
    int handle = CIndicatorManager::Instance().GetATRHandle(m_symbol, m_timeframe, period);
    if(handle == INVALID_HANDLE) return 0;

    double atr[];
    ArraySetAsSeries(atr, true);
    if(CopyBuffer(handle, 0, 0, 1, atr) <= 0)
        return 0;

    return atr[0];
}

//+------------------------------------------------------------------+
//| Should Move To Breakeven                                         |
//+------------------------------------------------------------------+
bool CTrendTrailingStop::ShouldMoveToBreakeven(const STradeTrailInfo &tradeInfo)
{
    if(tradeInfo.atBreakeven) return false;
    
    double lastPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);
    double riskDistance = MathAbs(tradeInfo.entryPrice - tradeInfo.currentSL);
    
    if(riskDistance <= 0) return false;
    
    double profitDistance;
    
    if(tradeInfo.isBuy)
        profitDistance = lastPrice - tradeInfo.entryPrice;
    else
        profitDistance = tradeInfo.entryPrice - lastPrice;
    
    double currentRR = profitDistance / riskDistance;
    
    return (currentRR >= m_breakEvenRR);
}

//+------------------------------------------------------------------+
//| Calculate Breakeven Stop                                         |
//+------------------------------------------------------------------+
double CTrendTrailingStop::CalculateBreakevenStop(const STradeTrailInfo &tradeInfo)
{
    double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    if(point <= 0) point = 0.0001;
    
    double buffer = m_breakEvenBuffer * point;
    
    if(tradeInfo.isBuy)
        return tradeInfo.entryPrice + buffer;
    else
        return tradeInfo.entryPrice - buffer;
}

//+------------------------------------------------------------------+
//| Get EMA21 Trail Stop                                             |
//+------------------------------------------------------------------+
double CTrendTrailingStop::GetEMA21TrailStop(bool isBuy)
{
    if(m_emaSystem == NULL) return 0;
    
    double ema21 = m_emaSystem.GetEMA21(0);
    double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    if(point <= 0) point = 0.0001;
    
    double buffer = m_emaBuffer * point;
    
    if(isBuy)
        return ema21 - buffer;
    else
        return ema21 + buffer;
}

//+------------------------------------------------------------------+
//| Get EMA8 Trail Stop                                              |
//+------------------------------------------------------------------+
double CTrendTrailingStop::GetEMA8TrailStop(bool isBuy)
{
    if(m_emaSystem == NULL) return 0;
    
    double ema8 = m_emaSystem.GetEMA8(0);
    double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    if(point <= 0) point = 0.0001;
    
    double buffer = (m_emaBuffer * 0.5) * point;  // Tighter buffer for 8 EMA
    
    if(isBuy)
        return ema8 - buffer;
    else
        return ema8 + buffer;
}

//+------------------------------------------------------------------+
//| Get ATR Trail Stop                                               |
//+------------------------------------------------------------------+
double CTrendTrailingStop::GetATRTrailStop(bool isBuy, double highestOrLowest)
{
    double atr = GetATR(14);
    
    if(isBuy)
        return highestOrLowest - (m_atrMultiplier * atr);
    else
        return highestOrLowest + (m_atrMultiplier * atr);
}

//+------------------------------------------------------------------+
//| Calculate New Stop Loss                                          |
//+------------------------------------------------------------------+
double CTrendTrailingStop::CalculateNewSL(const STradeTrailInfo &tradeInfo)
{
    double newSL = tradeInfo.currentSL;
    
    switch(tradeInfo.method)
    {
        case TRAIL_EMA21:
            newSL = GetEMA21TrailStop(tradeInfo.isBuy);
            break;
            
        case TRAIL_EMA8:
            newSL = GetEMA8TrailStop(tradeInfo.isBuy);
            break;
            
        case TRAIL_ATR:
            if(tradeInfo.isBuy)
                newSL = GetATRTrailStop(true, tradeInfo.highestPrice);
            else
                newSL = GetATRTrailStop(false, tradeInfo.lowestPrice);
            break;
            
        case TRAIL_HYBRID:
            {
                // Use the better of EMA21 or ATR trailing
                double emaSL = GetEMA21TrailStop(tradeInfo.isBuy);
                double atrSL;
                
                if(tradeInfo.isBuy)
                {
                    atrSL = GetATRTrailStop(true, tradeInfo.highestPrice);
                    newSL = MathMax(emaSL, atrSL);  // Higher SL for buy
                }
                else
                {
                    atrSL = GetATRTrailStop(false, tradeInfo.lowestPrice);
                    newSL = MathMin(emaSL, atrSL);  // Lower SL for sell
                }
            }
            break;
            
        case TRAIL_STRUCTURE:
            // For structure trailing, we need swing points
            // This would require integration with structure engine
            newSL = GetEMA21TrailStop(tradeInfo.isBuy);  // Fallback to EMA21
            break;
    }
    
    return newSL;
}

//+------------------------------------------------------------------+
//| Calculate Trailing Stop                                          |
//+------------------------------------------------------------------+
double CTrendTrailingStop::CalculateTrailingStop(STradeTrailInfo &tradeInfo)
{
    double lastPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);
    
    // Update highest/lowest
    if(tradeInfo.isBuy)
        tradeInfo.highestPrice = MathMax(tradeInfo.highestPrice, lastPrice);
    else
        tradeInfo.lowestPrice = MathMin(tradeInfo.lowestPrice, lastPrice);
    
    // Check for breakeven first
    if(!tradeInfo.atBreakeven && ShouldMoveToBreakeven(tradeInfo))
    {
        double beStop = CalculateBreakevenStop(tradeInfo);
        
        if((tradeInfo.isBuy && beStop > tradeInfo.currentSL) || (!tradeInfo.isBuy && beStop < tradeInfo.currentSL))
        {
            tradeInfo.atBreakeven = true;
            return beStop;
        }
    }
    
    // Calculate trailing stop
    double newSL = CalculateNewSL(tradeInfo);
    
    // Only move stop in favor of trade
    if(tradeInfo.isBuy)
    {
        if(newSL > tradeInfo.currentSL)
            return newSL;
    }
    else
    {
        if(newSL < tradeInfo.currentSL)
            return newSL;
    }
    
    return tradeInfo.currentSL;  // No change
}

//+------------------------------------------------------------------+
//| Should Exit Early                                                |
//+------------------------------------------------------------------+
bool CTrendTrailingStop::ShouldExitEarly(const STradeTrailInfo &tradeInfo)
{
    if(m_emaSystem == NULL) return false;
    
    // Exit early if fast EMA crosses medium EMA (trend weakening)
    if(tradeInfo.isBuy)
    {
        // Exit buy if 8 EMA crosses below 21 EMA
        return m_emaSystem.HasDeathCross8_21();
    }
    else
    {
        // Exit sell if 8 EMA crosses above 21 EMA
        return m_emaSystem.HasGoldenCross8_21();
    }
}

#endif // __TREND_TRAILING_STOP_MQH__
