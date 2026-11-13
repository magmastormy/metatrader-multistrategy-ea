// Previous-day high/low breakout: the multi-day level family the roster did not have.
//
// Why this is a separate voter rather than a parameter of the Donchian row: Donchian measures a
// rolling 20-bar channel on the chart timeframe, so on M15 it is a few hours of price. This one
// measures the level every desk quotes - yesterday's high and low - which is a level other market
// participants act on, not just a statistic of the last 20 bars. The two can agree, but they are
// answering different questions, and this one is the only row that reads a higher timeframe at all.
//
// Shape:
//   - Break must clear the level by 0.10 ATR, so a one-tick poke through a round number is not a break.
//   - ADX(14) >= 20 on the crossing bar: a level break without expansion is a level touch with slippage.
//   - A close already 1.5 ATR past the level is refused - that is chase risk, not breakout risk.
//   - Stop 1.6 ATR, target 2.8 ATR: 1.75R by construction.
#ifndef DAILY_LEVEL_BREAKOUT_STRATEGY_MQH
#define DAILY_LEVEL_BREAKOUT_STRATEGY_MQH

#include "../Core/Strategy/StrategyBase.mqh"
#include "../Core/Utils/SignalGuards.mqh"

class CDailyLevelBreakoutStrategy : public CStrategyBase
{
private:
    int    m_atrPeriod;
    int    m_adxPeriod;
    double m_adxFloor;
    double m_clearanceAtr;      // how far past the level the close must be
    double m_maxExtensionAtr;   // how far past the level it may already be before it is a chase
    double m_atrStopMult;
    double m_rewardMultiple;

    int    m_atrHandle;
    int    m_adxHandle;

    datetime m_lastSignalBar;

    double PointSize() const
    {
        double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
        return (point > 0.0 ? point : 0.0);
    }

protected:
    virtual void HandleNewBar() override { RefreshForNewBar(); }

public:
    CDailyLevelBreakoutStrategy() :
        CStrategyBase("Daily Level Breakout", 0),
        m_atrPeriod(14),
        m_adxPeriod(14),
        m_adxFloor(20.0),
        m_clearanceAtr(0.10),
        m_maxExtensionAtr(1.5),
        m_atrStopMult(1.6),
        m_rewardMultiple(1.75),
        m_atrHandle(INVALID_HANDLE),
        m_adxHandle(INVALID_HANDLE),
        m_lastSignalBar(0)
    {
        m_strategyPrefix = "PDL-BO";
        OverrideMinConfidence(0.58);
    }

    // Handles in Init(), never in a separate Initialize(): the catalog creator passes no arguments
    // and the registration path only ever calls Init().
    virtual bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe,
                      void* tradeMgr, void* posSizer, void* unifiedRiskMgr = NULL) override
    {
        if(!CStrategyBase::Init(symbol, timeframe, tradeMgr, posSizer, unifiedRiskMgr))
            return false;

        m_atrHandle = iATR(symbol, timeframe, m_atrPeriod);
        m_adxHandle = iADX(symbol, timeframe, m_adxPeriod);

        if(m_atrHandle == INVALID_HANDLE || m_adxHandle == INVALID_HANDLE)
        {
            PrintFormat("[PDL-BO] Init failed | %s %s | atr=%d adx=%d",
                        symbol, EnumToString(timeframe), m_atrHandle, m_adxHandle);
            return false;
        }

        if(GetUnifiedRiskManager() == NULL)
            Print("[PDL-BO] WARNING: UnifiedRiskManager not provided - trades will bypass validation!");

        return true;
    }

    virtual void Deinit() override
    {
        if(m_atrHandle != INVALID_HANDLE) { IndicatorRelease(m_atrHandle); m_atrHandle = INVALID_HANDLE; }
        if(m_adxHandle != INVALID_HANDLE) { IndicatorRelease(m_adxHandle); m_adxHandle = INVALID_HANDLE; }
        CStrategyBase::Deinit();
    }

    virtual ~CDailyLevelBreakoutStrategy() { Deinit(); }

    virtual void OnTick() override
    {
        // New-bar evaluation only; consensus polls GetSignal().
    }

    // Breakout category: RegimeStateHardGate never kills it in a trend, and its category multiplier
    // is the breakout one, which is where a level break belongs.
    virtual ENUM_STRATEGY_TYPE GetType() const override { return (ENUM_STRATEGY_TYPE)STRATEGY_VOLATILITY_BREAKOUT; }

    virtual ENUM_TRADE_SIGNAL ExecuteSignal(double &confidence) override
    {
        confidence = 0.0;
        SetDecisionReasonTag("PDLBO_UNSET");

        if(!m_is_initialized)
            return RejectSignal("PDLBO_UNINITIALIZED");
        if(m_atrHandle == INVALID_HANDLE || m_adxHandle == INVALID_HANDLE)
            return RejectSignal("PDLBO_INVALID_HANDLES");

        datetime barTime = iTime(m_symbol, m_timeframe, 1);
        if(barTime == m_lastSignalBar)
            return RejectSignal("PDLBO_SAME_BAR");

        double atr[1], adx[1], close[1];
        if(CopyBuffer(m_atrHandle, 0, 1, 1, atr) != 1 || atr[0] <= 0.0)
            return RejectSignal("PDLBO_NO_ATR");
        if(CopyBuffer(m_adxHandle, 0, 1, 1, adx) != 1 || adx[0] <= 0.0)
            return RejectSignal("PDLBO_NO_ADX");
        if(CopyClose(m_symbol, m_timeframe, 1, 1, close) != 1)
            return RejectSignal("PDLBO_NO_CLOSE");

        const double priorHigh = iHigh(m_symbol, PERIOD_D1, 1);
        const double priorLow  = iLow(m_symbol, PERIOD_D1, 1);
        if(priorHigh <= 0.0 || priorLow <= 0.0 || priorHigh <= priorLow)
            return RejectSignal("PDLBO_NO_DAILY_LEVEL");

        const double clearance = atr[0] * m_clearanceAtr;
        const bool brokeUp   = (close[0] > priorHigh + clearance);
        const bool brokeDown = (close[0] < priorLow - clearance);
        if(!brokeUp && !brokeDown)
            return RejectSignal("PDLBO_NO_BREAK");

        // Already far past the level: the break happened earlier and this is the chase.
        const double extension = brokeUp ? (close[0] - priorHigh) : (priorLow - close[0]);
        if(extension > atr[0] * m_maxExtensionAtr)
            return RejectSignal("PDLBO_TOO_EXTENDED");

        // A level break without expansion is a touch with slippage.
        if(adx[0] < m_adxFloor)
            return RejectSignal("PDLBO_ADX_FLAT");

        const bool isBuy = brokeUp;
        const double stopDistance = atr[0] * m_atrStopMult;
        const double targetDistance = stopDistance * m_rewardMultiple;

        double price = isBuy ? SymbolInfoDouble(m_symbol, SYMBOL_ASK) : SymbolInfoDouble(m_symbol, SYMBOL_BID);
        if(price <= 0.0)
            price = close[0];

        const double stop = isBuy ? (price - stopDistance) : (price + stopDistance);
        const double target = isBuy ? (price + targetDistance) : (price - targetDistance);

        const double point = PointSize();
        const long spreadPoints = SymbolInfoInteger(m_symbol, SYMBOL_SPREAD);
        const double spreadPrice = (point > 0.0) ? (double)spreadPoints * point : 0.0;

        if(!CSignalGuards::IsSignalTradable(price, stop, target, spreadPrice))
            return RejectSignal("PDLBO_NOT_TRADABLE");

        confidence = 0.60;
        if(adx[0] >= 30.0) confidence += 0.10;
        else if(adx[0] >= 25.0) confidence += 0.05;
        if(extension <= atr[0] * 0.5) confidence += 0.04;   // a freshly cleared level, not an old one
        confidence = MathMin(0.92, confidence);

        STradeValidationRequest request;
        request.symbol = m_symbol;
        request.orderType = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
        request.lotSize = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
        request.stopLossPips = (point > 0.0) ? (stopDistance / point) : 0.0;
        request.takeProfitPips = (point > 0.0) ? (targetDistance / point) : 0.0;
        request.confidence = confidence;
        request.strategy = GetName();
        request.clusterCode = "";

        SetProposedStops(request.stopLossPips, request.takeProfitPips);
        if(!ValidateWithRiskManager(request, "PDL-BO", confidence))
            return TRADE_SIGNAL_NONE;

        m_lastSignalBar = barTime;
        SetDecisionReasonTag(isBuy ? "PDLBO_BREAK_BUY" : "PDLBO_BREAK_SELL");

        PrintFormat("[PDL-BO] %s | %s | PDH=%.5f PDL=%.5f close=%.5f ATR=%.5f ADX=%.1f | stop=%.5f tp=%.5f | Conf=%.1f%%",
                    m_symbol, (isBuy ? "BUY" : "SELL"), priorHigh, priorLow, close[0], atr[0], adx[0],
                    stop, target, confidence * 100.0);
        LogConsensusDiag(isBuy ? TRADE_SIGNAL_BUY : TRADE_SIGNAL_SELL, "DailyLevelBreakout", confidence, "");

        return (isBuy ? TRADE_SIGNAL_BUY : TRADE_SIGNAL_SELL);
    }
};

#endif // DAILY_LEVEL_BREAKOUT_STRATEGY_MQH
