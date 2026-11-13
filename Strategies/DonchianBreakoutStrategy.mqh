// Donchian channel breakout: the classic trend-following entry (Turtle System 2 shape) reduced
// to a single voter. A closed bar that closes beyond the highest high / lowest low of the previous
// N bars, in the direction of the long-term EMA and with ADX confirming a trend, is the only thing
// this class ever emits.
//
// Why this shape and not another band test:
//   - The channel is built from BARS 2..N+1, i.e. it excludes the bar being judged. A breakout
//     test that includes the judged bar can never be false once the bar closes above its own high.
//   - The extension cap keeps the voter out of a move that is already 1.5 ATR past the channel;
//     that is chase risk, not breakout risk, and the existing Volatility Breakout / Range
//     Compression voters already cover the squeeze-release case this would otherwise duplicate.
//   - Stops and targets are ATR multiples so the R:R is fixed by construction (1.5 ATR stop /
//     3.0 ATR target = 2R) instead of inheriting whatever the risk gate would size around.
#ifndef DONCHIAN_BREAKOUT_STRATEGY_MQH
#define DONCHIAN_BREAKOUT_STRATEGY_MQH

#include "../Core/Strategy/StrategyBase.mqh"
#include "../Core/Utils/SignalGuards.mqh"

class CDonchianBreakoutStrategy : public CStrategyBase
{
private:
    int    m_channelPeriod;    // bars the breakout channel is built from, excluding the judged bar
    int    m_atrPeriod;
    double m_atrStopMult;      // stop distance in ATRs
    double m_rewardMultiple;   // target distance as a multiple of the stop distance
    int    m_adxPeriod;
    double m_adxFloor;         // below this the channel break is noise in a flat market
    int    m_trendMaPeriod;    // long-term EMA the close must agree with
    double m_minBreakPct;      // break must clear the channel by this fraction of ATR
    double m_maxExtensionAtr;  // beyond this the move is already gone - do not chase

    int    m_atrHandle;
    int    m_adxHandle;
    int    m_maHandle;

    datetime m_lastSignalBar;

    double PointSize() const
    {
        double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
        return (point > 0.0 ? point : 0.0);
    }

    // Channel over bars 2..N+1, deliberately excluding bar 1 (the bar whose close is judged).
    bool BuildChannel(double &channelHigh, double &channelLow)
    {
        double highs[], lows[];
        ArraySetAsSeries(highs, true);
        ArraySetAsSeries(lows, true);

        const int needed = m_channelPeriod + 1;
        if(CopyHigh(m_symbol, m_timeframe, 1, needed, highs) != needed)
            return false;
        if(CopyLow(m_symbol, m_timeframe, 1, needed, lows) != needed)
            return false;

        channelHigh = highs[1];
        channelLow  = lows[1];
        for(int i = 2; i < needed; i++)
        {
            if(highs[i] > channelHigh) channelHigh = highs[i];
            if(lows[i]  < channelLow)  channelLow  = lows[i];
        }
        return (channelHigh > 0.0 && channelLow > 0.0 && channelHigh > channelLow);
    }

protected:
    virtual void HandleNewBar() override { RefreshForNewBar(); }

public:
    CDonchianBreakoutStrategy() :
        CStrategyBase("Donchian Breakout", 0),
        m_channelPeriod(20),
        m_atrPeriod(14),
        m_atrStopMult(1.5),
        m_rewardMultiple(2.0),
        m_adxPeriod(14),
        m_adxFloor(18.0),
        m_trendMaPeriod(100),
        m_minBreakPct(0.15),
        m_maxExtensionAtr(1.5),
        m_atrHandle(INVALID_HANDLE),
        m_adxHandle(INVALID_HANDLE),
        m_maHandle(INVALID_HANDLE),
        m_lastSignalBar(0)
    {
        m_strategyPrefix = "DONCHIAN";
        OverrideMinConfidence(0.58);
    }

    // The catalog creator builds this class with no arguments and the manager calls Init(); handles
    // therefore have to be created here, not in a separate Initialize() the manager never calls.
    virtual bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe,
                      void* tradeMgr, void* posSizer, void* unifiedRiskMgr = NULL) override
    {
        if(!CStrategyBase::Init(symbol, timeframe, tradeMgr, posSizer, unifiedRiskMgr))
            return false;

        m_atrHandle = iATR(symbol, timeframe, m_atrPeriod);
        m_adxHandle = iADX(symbol, timeframe, m_adxPeriod);
        m_maHandle  = iMA(symbol, timeframe, m_trendMaPeriod, 0, MODE_EMA, PRICE_CLOSE);

        if(m_atrHandle == INVALID_HANDLE || m_adxHandle == INVALID_HANDLE || m_maHandle == INVALID_HANDLE)
        {
            PrintFormat("[DONCHIAN] Init failed | %s %s | atr=%d adx=%d ma=%d",
                        symbol, EnumToString(timeframe), m_atrHandle, m_adxHandle, m_maHandle);
            return false;
        }

        if(GetUnifiedRiskManager() == NULL)
            Print("[DONCHIAN] WARNING: UnifiedRiskManager not provided - trades will bypass validation!");

        return true;
    }

    virtual void Deinit() override
    {
        if(m_atrHandle != INVALID_HANDLE) { IndicatorRelease(m_atrHandle); m_atrHandle = INVALID_HANDLE; }
        if(m_adxHandle != INVALID_HANDLE) { IndicatorRelease(m_adxHandle); m_adxHandle = INVALID_HANDLE; }
        if(m_maHandle  != INVALID_HANDLE) { IndicatorRelease(m_maHandle);  m_maHandle  = INVALID_HANDLE; }
        CStrategyBase::Deinit();
    }

    virtual ~CDonchianBreakoutStrategy() { Deinit(); }

    virtual void OnTick() override
    {
        // Evaluated on new bars only; consensus polls GetSignal().
    }

    // Regime classification reuses the breakout family: the type is a category label for the
    // regime/volatility multipliers, not an identity, and no new enum value is needed for that.
    virtual ENUM_STRATEGY_TYPE GetType() const override { return (ENUM_STRATEGY_TYPE)STRATEGY_VOLATILITY_BREAKOUT; }

    virtual ENUM_TRADE_SIGNAL ExecuteSignal(double &confidence) override
    {
        confidence = 0.0;
        SetDecisionReasonTag("DONCHIAN_UNSET");

        if(!m_is_initialized)
            return RejectSignal("DONCHIAN_UNINITIALIZED");
        if(m_atrHandle == INVALID_HANDLE || m_adxHandle == INVALID_HANDLE || m_maHandle == INVALID_HANDLE)
            return RejectSignal("DONCHIAN_INVALID_HANDLES");

        // One evaluation per closed bar: a second poll inside the same bar would re-vote the same break.
        datetime barTime = iTime(m_symbol, m_timeframe, 1);
        if(barTime == m_lastSignalBar)
            return RejectSignal("DONCHIAN_SAME_BAR");

        double atr[1], adx[1], ma[1], close[1];
        if(CopyBuffer(m_atrHandle, 0, 1, 1, atr) != 1 || atr[0] <= 0.0)
            return RejectSignal("DONCHIAN_NO_ATR");
        if(CopyBuffer(m_adxHandle, 0, 1, 1, adx) != 1)
            return RejectSignal("DONCHIAN_NO_ADX");
        if(CopyBuffer(m_maHandle, 0, 1, 1, ma) != 1 || ma[0] <= 0.0)
            return RejectSignal("DONCHIAN_NO_MA");
        if(CopyClose(m_symbol, m_timeframe, 1, 1, close) != 1)
            return RejectSignal("DONCHIAN_NO_CLOSE");

        double channelHigh = 0.0, channelLow = 0.0;
        if(!BuildChannel(channelHigh, channelLow))
            return RejectSignal("DONCHIAN_NO_HISTORY");

        if(adx[0] < m_adxFloor)
            return RejectSignal("DONCHIAN_ADX_FLAT");

        const double minBreak = atr[0] * m_minBreakPct;
        const double maxExtension = atr[0] * m_maxExtensionAtr;

        ENUM_TRADE_SIGNAL direction = TRADE_SIGNAL_NONE;
        double breakDistance = 0.0;

        if(close[0] > channelHigh + minBreak && close[0] > ma[0])
        {
            breakDistance = close[0] - channelHigh;
            if(breakDistance <= maxExtension)
                direction = TRADE_SIGNAL_BUY;
        }
        else if(close[0] < channelLow - minBreak && close[0] < ma[0])
        {
            breakDistance = channelLow - close[0];
            if(breakDistance <= maxExtension)
                direction = TRADE_SIGNAL_SELL;
        }

        if(direction == TRADE_SIGNAL_NONE)
            return RejectSignal("DONCHIAN_NO_BREAK");

        const bool isBuy = (direction == TRADE_SIGNAL_BUY);
        const double stopDistance = atr[0] * m_atrStopMult;
        const double targetDistance = stopDistance * m_rewardMultiple;

        double price = isBuy ? SymbolInfoDouble(m_symbol, SYMBOL_ASK) : SymbolInfoDouble(m_symbol, SYMBOL_BID);
        if(price <= 0.0)
            price = close[0];

        double stop = isBuy ? (price - stopDistance) : (price + stopDistance);
        double target = isBuy ? (price + targetDistance) : (price - targetDistance);

        const double point = PointSize();
        const long spreadPoints = SymbolInfoInteger(m_symbol, SYMBOL_SPREAD);
        const double spreadPrice = (point > 0.0) ? (double)spreadPoints * point : 0.0;

        // A channel break whose stop is thinner than the spread, or whose target does not cover the
        // stop, is refused here rather than sized by the risk gate into an order nobody can fill.
        if(!CSignalGuards::IsSignalTradable(price, stop, target, spreadPrice))
            return RejectSignal("DONCHIAN_NOT_TRADABLE");

        // Confidence is published BEFORE the gate so the gate and its log read the real value.
        confidence = 0.60;
        if(adx[0] >= 25.0) confidence += 0.10;
        if(breakDistance >= atr[0] * 0.5) confidence += 0.05;
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
        if(!ValidateWithRiskManager(request, "DONCHIAN", confidence))
            return TRADE_SIGNAL_NONE;

        m_lastSignalBar = barTime;
        SetDecisionReasonTag(isBuy ? "DONCHIAN_BREAK_BUY" : "DONCHIAN_BREAK_SELL");

        PrintFormat("[DONCHIAN] %s | %s | close=%.5f ch=%.5f/%.5f | ATR=%.5f ADX=%.1f | stop=%.5f tp=%.5f | Conf=%.1f%%",
                    m_symbol, (isBuy ? "BUY" : "SELL"), close[0], channelLow, channelHigh,
                    atr[0], adx[0], stop, target, confidence * 100.0);
        LogConsensusDiag(direction, "DonchianBreakout", confidence, "");

        return direction;
    }
};

#endif // DONCHIAN_BREAKOUT_STRATEGY_MQH
