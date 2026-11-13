// RSI(2) pullback: the short-horizon mean-reversion entry, trend-filtered.
//
// The shape is deliberate and narrow, because this is the one voter that trades AGAINST the last
// one or two bars while still requiring the higher-timeframe direction to agree:
//   - RSI(2) measures a two-bar impulse, so the signal fires while the pullback is still fresh
//     rather than after the market has already turned.
//   - The 200-period SMA is the trend authority: an oversold reading below it is a downtrend
//     continuing, not a dip, and that is the failure mode this filter exists to remove.
//   - The distance cap (4 ATR) refuses a price that is already far from the mean, where a "dip"
//     is a trend leg and mean reversion loses its edge.
//   - Stops and targets are ATR multiples (1.2 / 2.1 ATR, `m_rewardMultiple` 1.75), so R:R is fixed
//     by construction and the voter cannot be sized into a trade whose target does not cover its stop.
#ifndef RSI2_PULLBACK_STRATEGY_MQH
#define RSI2_PULLBACK_STRATEGY_MQH

#include "../Core/Strategy/StrategyBase.mqh"
#include "../Core/Utils/SignalGuards.mqh"

class CRSI2PullbackStrategy : public CStrategyBase
{
private:
    int    m_rsiPeriod;        // 2 bars: the impulse length being faded
    int    m_smaPeriod;        // trend authority
    int    m_atrPeriod;
    double m_atrStopMult;
    double m_rewardMultiple;
    double m_oversoldLevel;
    double m_overboughtLevel;
    double m_maxDistanceAtr;   // beyond this the "dip" is a trend leg

    int    m_rsiHandle;
    int    m_smaHandle;
    int    m_atrHandle;

    datetime m_lastSignalBar;

    double PointSize() const
    {
        double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
        return (point > 0.0 ? point : 0.0);
    }

protected:
    virtual void HandleNewBar() override { RefreshForNewBar(); }

public:
    CRSI2PullbackStrategy() :
        CStrategyBase("RSI2 Pullback", 0),
        m_rsiPeriod(2),
        m_smaPeriod(200),
        m_atrPeriod(14),
        m_atrStopMult(1.2),
        m_rewardMultiple(1.75),
        m_oversoldLevel(10.0),
        m_overboughtLevel(90.0),
        m_maxDistanceAtr(4.0),
        m_rsiHandle(INVALID_HANDLE),
        m_smaHandle(INVALID_HANDLE),
        m_atrHandle(INVALID_HANDLE),
        m_lastSignalBar(0)
    {
        m_strategyPrefix = "RSI2";
        OverrideMinConfidence(0.56);
    }

    // Handles are created here because the catalog creator cannot pass parameters and the manager
    // only ever calls Init(); a separate Initialize() overload would never run for a catalog row.
    virtual bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe,
                      void* tradeMgr, void* posSizer, void* unifiedRiskMgr = NULL) override
    {
        if(!CStrategyBase::Init(symbol, timeframe, tradeMgr, posSizer, unifiedRiskMgr))
            return false;

        m_rsiHandle = iRSI(symbol, timeframe, m_rsiPeriod, PRICE_CLOSE);
        m_smaHandle = iMA(symbol, timeframe, m_smaPeriod, 0, MODE_SMA, PRICE_CLOSE);
        m_atrHandle = iATR(symbol, timeframe, m_atrPeriod);

        if(m_rsiHandle == INVALID_HANDLE || m_smaHandle == INVALID_HANDLE || m_atrHandle == INVALID_HANDLE)
        {
            PrintFormat("[RSI2] Init failed | %s %s | rsi=%d sma=%d atr=%d",
                        symbol, EnumToString(timeframe), m_rsiHandle, m_smaHandle, m_atrHandle);
            return false;
        }

        if(GetUnifiedRiskManager() == NULL)
            Print("[RSI2] WARNING: UnifiedRiskManager not provided - trades will bypass validation!");

        return true;
    }

    virtual void Deinit() override
    {
        if(m_rsiHandle != INVALID_HANDLE) { IndicatorRelease(m_rsiHandle); m_rsiHandle = INVALID_HANDLE; }
        if(m_smaHandle != INVALID_HANDLE) { IndicatorRelease(m_smaHandle); m_smaHandle = INVALID_HANDLE; }
        if(m_atrHandle != INVALID_HANDLE) { IndicatorRelease(m_atrHandle); m_atrHandle = INVALID_HANDLE; }
        CStrategyBase::Deinit();
    }

    virtual ~CRSI2PullbackStrategy() { Deinit(); }

    virtual void OnTick() override
    {
        // New-bar evaluation only; consensus polls GetSignal().
    }

    // The regime gate hard-kills STRATEGY_MEAN_REVERSION in a confirmed trend, which is exactly the
    // state this voter trades (a dip inside an uptrend). The S/R category is regime-neutral there, so
    // the pullback is judged by its own SMA filter instead of being zeroed before it can vote.
    virtual ENUM_STRATEGY_TYPE GetType() const override { return (ENUM_STRATEGY_TYPE)STRATEGY_SUPPORT_RESISTANCE; }

    virtual ENUM_TRADE_SIGNAL ExecuteSignal(double &confidence) override
    {
        confidence = 0.0;
        SetDecisionReasonTag("RSI2_UNSET");

        if(!m_is_initialized)
            return RejectSignal("RSI2_UNINITIALIZED");
        if(m_rsiHandle == INVALID_HANDLE || m_smaHandle == INVALID_HANDLE || m_atrHandle == INVALID_HANDLE)
            return RejectSignal("RSI2_INVALID_HANDLES");

        datetime barTime = iTime(m_symbol, m_timeframe, 1);
        if(barTime == m_lastSignalBar)
            return RejectSignal("RSI2_SAME_BAR");

        double rsi[1], sma[1], atr[1], close[1];
        if(CopyBuffer(m_rsiHandle, 0, 1, 1, rsi) != 1)
            return RejectSignal("RSI2_NO_RSI");
        if(CopyBuffer(m_smaHandle, 0, 1, 1, sma) != 1 || sma[0] <= 0.0)
            return RejectSignal("RSI2_NO_SMA");
        if(CopyBuffer(m_atrHandle, 0, 1, 1, atr) != 1 || atr[0] <= 0.0)
            return RejectSignal("RSI2_NO_ATR");
        if(CopyClose(m_symbol, m_timeframe, 1, 1, close) != 1)
            return RejectSignal("RSI2_NO_CLOSE");

        // A dip in a downtrend is not a dip. The SMA is the authority, the RSI only times it.
        const bool trendUp   = (close[0] > sma[0]);
        const bool trendDown = (close[0] < sma[0]);
        if(!trendUp && !trendDown)
            return RejectSignal("RSI2_NO_TREND");

        if(MathAbs(close[0] - sma[0]) > atr[0] * m_maxDistanceAtr)
            return RejectSignal("RSI2_OVEREXTENDED");

        ENUM_TRADE_SIGNAL direction = TRADE_SIGNAL_NONE;
        if(trendUp && rsi[0] <= m_oversoldLevel)
            direction = TRADE_SIGNAL_BUY;
        else if(trendDown && rsi[0] >= m_overboughtLevel)
            direction = TRADE_SIGNAL_SELL;

        if(direction == TRADE_SIGNAL_NONE)
            return RejectSignal("RSI2_NO_EXTREME");

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

        if(!CSignalGuards::IsSignalTradable(price, stop, target, spreadPrice))
            return RejectSignal("RSI2_NOT_TRADABLE");

        // Published before the gate so the gate and its log read the real value.
        confidence = 0.60;
        if(isBuy && rsi[0] <= 5.0) confidence += 0.06;
        if(!isBuy && rsi[0] >= 95.0) confidence += 0.06;
        if(MathAbs(close[0] - sma[0]) <= atr[0] * 1.5) confidence += 0.04;
        confidence = MathMin(0.90, confidence);

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
        if(!ValidateWithRiskManager(request, "RSI2", confidence))
            return TRADE_SIGNAL_NONE;

        m_lastSignalBar = barTime;
        SetDecisionReasonTag(isBuy ? "RSI2_DIP_BUY" : "RSI2_RIP_SELL");

        PrintFormat("[RSI2] %s | %s | RSI=%.1f SMA=%.5f close=%.5f ATR=%.5f | stop=%.5f tp=%.5f | Conf=%.1f%%",
                    m_symbol, (isBuy ? "BUY" : "SELL"), rsi[0], sma[0], close[0], atr[0],
                    stop, target, confidence * 100.0);
        LogConsensusDiag(direction, "RSI2Pullback", confidence, "");

        return direction;
    }
};

#endif // RSI2_PULLBACK_STRATEGY_MQH
