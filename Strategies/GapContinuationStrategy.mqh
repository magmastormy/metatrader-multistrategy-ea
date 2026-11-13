// Gap continuation: an opening gap that holds its direction.
//
// `NY Open Gap` already fades a gap, so this row is its deliberate counter-vote rather than a
// duplicate: the fade needs the gap to fail early, this needs the gap to hold and the trend to agree
// with it. Exactly one of the two can be right about the same session open, and consensus gets both
// opinions instead of one.
//
// Shape:
//   - The gap (today's open vs yesterday's close) must be at least 0.4 ATR - smaller is noise - and
//     at most 3 ATR, because a gap that large has already booked the move.
//   - The trend must agree: the last close is on the same side of EMA(50) as the gap.
//   - The gap must still hold: the last closed bar closed on the gap's side of today's open.
//   - Only inside the first `m_earlyHours` hours of the day; after that the continuation is a trend
//     trade the other rows already cover, and this row's premise (the open) is stale.
//   - Stop 1.5 ATR, target 3.0 ATR: 2R by construction.
#ifndef GAP_CONTINUATION_STRATEGY_MQH
#define GAP_CONTINUATION_STRATEGY_MQH

#include "../Core/Strategy/StrategyBase.mqh"
#include "../Core/Utils/SignalGuards.mqh"

class CGapContinuationStrategy : public CStrategyBase
{
private:
    int    m_atrPeriod;
    int    m_emaPeriod;
    double m_minGapAtr;
    double m_maxGapAtr;
    double m_atrStopMult;
    double m_rewardMultiple;
    int    m_earlyHours;

    int    m_atrHandle;
    int    m_emaHandle;

    datetime m_lastSignalBar;

    double PointSize() const
    {
        double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
        return (point > 0.0 ? point : 0.0);
    }

protected:
    virtual void HandleNewBar() override { RefreshForNewBar(); }

public:
    CGapContinuationStrategy() :
        CStrategyBase("Gap Continuation", 0),
        m_atrPeriod(14),
        m_emaPeriod(50),
        m_minGapAtr(0.4),
        m_maxGapAtr(3.0),
        m_atrStopMult(1.5),
        m_rewardMultiple(2.0),
        m_earlyHours(6),
        m_atrHandle(INVALID_HANDLE),
        m_emaHandle(INVALID_HANDLE),
        m_lastSignalBar(0)
    {
        m_strategyPrefix = "GAP-CONT";
        OverrideMinConfidence(0.56);
    }

    virtual bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe,
                      void* tradeMgr, void* posSizer, void* unifiedRiskMgr = NULL) override
    {
        if(!CStrategyBase::Init(symbol, timeframe, tradeMgr, posSizer, unifiedRiskMgr))
            return false;

        m_atrHandle = iATR(symbol, timeframe, m_atrPeriod);
        m_emaHandle = iMA(symbol, timeframe, m_emaPeriod, 0, MODE_EMA, PRICE_CLOSE);

        if(m_atrHandle == INVALID_HANDLE || m_emaHandle == INVALID_HANDLE)
        {
            PrintFormat("[GAP-CONT] Init failed | %s %s | atr=%d ema=%d",
                        symbol, EnumToString(timeframe), m_atrHandle, m_emaHandle);
            return false;
        }

        if(GetUnifiedRiskManager() == NULL)
            Print("[GAP-CONT] WARNING: UnifiedRiskManager not provided - trades will bypass validation!");

        return true;
    }

    virtual void Deinit() override
    {
        if(m_atrHandle != INVALID_HANDLE) { IndicatorRelease(m_atrHandle); m_atrHandle = INVALID_HANDLE; }
        if(m_emaHandle != INVALID_HANDLE) { IndicatorRelease(m_emaHandle); m_emaHandle = INVALID_HANDLE; }
        CStrategyBase::Deinit();
    }

    virtual ~CGapContinuationStrategy() { Deinit(); }

    virtual void OnTick() override
    {
        // New-bar evaluation only; consensus polls GetSignal().
    }

    // Momentum category: a gap that holds is momentum, and a range regime is the state it should
    // stop voting in - which the trend-like gate already applies.
    virtual ENUM_STRATEGY_TYPE GetType() const override { return (ENUM_STRATEGY_TYPE)STRATEGY_MOMENTUM; }

    virtual ENUM_TRADE_SIGNAL ExecuteSignal(double &confidence) override
    {
        confidence = 0.0;
        SetDecisionReasonTag("GAPCONT_UNSET");

        if(!m_is_initialized)
            return RejectSignal("GAPCONT_UNINITIALIZED");
        if(m_atrHandle == INVALID_HANDLE || m_emaHandle == INVALID_HANDLE)
            return RejectSignal("GAPCONT_INVALID_HANDLES");

        datetime barTime = iTime(m_symbol, m_timeframe, 1);
        if(barTime == m_lastSignalBar)
            return RejectSignal("GAPCONT_SAME_BAR");

        double atr[1], ema[1], barClose[1];
        if(CopyBuffer(m_atrHandle, 0, 1, 1, atr) != 1 || atr[0] <= 0.0)
            return RejectSignal("GAPCONT_NO_ATR");
        if(CopyBuffer(m_emaHandle, 0, 1, 1, ema) != 1 || ema[0] <= 0.0)
            return RejectSignal("GAPCONT_NO_EMA");
        if(CopyClose(m_symbol, m_timeframe, 1, 1, barClose) != 1)
            return RejectSignal("GAPCONT_NO_BAR_CLOSE");

        const double dayOpen   = iOpen(m_symbol, PERIOD_D1, 0);
        const double prevClose = iClose(m_symbol, PERIOD_D1, 1);
        const datetime dayOpenTime = iTime(m_symbol, PERIOD_D1, 0);
        if(dayOpen <= 0.0 || prevClose <= 0.0 || dayOpenTime <= 0)
            return RejectSignal("GAPCONT_NO_DAILY");

        // Stale premise: after the early window this is a trend trade, not a gap trade.
        if(TimeCurrent() - dayOpenTime > (long)m_earlyHours * 3600)
            return RejectSignal("GAPCONT_TOO_LATE");

        const double gap = dayOpen - prevClose;
        const double gapAbs = MathAbs(gap);
        if(gapAbs < atr[0] * m_minGapAtr)
            return RejectSignal("GAPCONT_NO_GAP");
        if(gapAbs > atr[0] * m_maxGapAtr)
            return RejectSignal("GAPCONT_GAP_TOO_BIG");

        const bool gapUp = (gap > 0.0);

        // The gap has to hold on the closed bar, and the trend has to agree with it.
        if(gapUp && !(barClose[0] > dayOpen && barClose[0] > ema[0]))
            return RejectSignal("GAPCONT_NOT_HOLDING");
        if(!gapUp && !(barClose[0] < dayOpen && barClose[0] < ema[0]))
            return RejectSignal("GAPCONT_NOT_HOLDING");

        const bool isBuy = gapUp;
        const double stopDistance = atr[0] * m_atrStopMult;
        const double targetDistance = stopDistance * m_rewardMultiple;

        double price = isBuy ? SymbolInfoDouble(m_symbol, SYMBOL_ASK) : SymbolInfoDouble(m_symbol, SYMBOL_BID);
        if(price <= 0.0)
            price = barClose[0];

        const double stop = isBuy ? (price - stopDistance) : (price + stopDistance);
        const double target = isBuy ? (price + targetDistance) : (price - targetDistance);

        const double point = PointSize();
        const long spreadPoints = SymbolInfoInteger(m_symbol, SYMBOL_SPREAD);
        const double spreadPrice = (point > 0.0) ? (double)spreadPoints * point : 0.0;

        if(!CSignalGuards::IsSignalTradable(price, stop, target, spreadPrice))
            return RejectSignal("GAPCONT_NOT_TRADABLE");

        // The gap has been held for at least one closed bar, so this is a holding gap not a print.
        confidence = 0.58;
        if(gapAbs >= atr[0] * 1.0) confidence += 0.06;                  // a meaningful gap, not a tick
        if(MathAbs(barClose[0] - ema[0]) >= atr[0] * 0.5) confidence += 0.04;   // trend has separation
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
        if(!ValidateWithRiskManager(request, "GAP-CONT", confidence))
            return TRADE_SIGNAL_NONE;

        m_lastSignalBar = barTime;
        SetDecisionReasonTag(isBuy ? "GAPCONT_UP_BUY" : "GAPCONT_DOWN_SELL");

        PrintFormat("[GAP-CONT] %s | %s | open=%.5f prevClose=%.5f gap=%.5f ATR=%.5f | stop=%.5f tp=%.5f | Conf=%.1f%%",
                    m_symbol, (isBuy ? "BUY" : "SELL"), dayOpen, prevClose, gap, atr[0],
                    stop, target, confidence * 100.0);
        LogConsensusDiag(isBuy ? TRADE_SIGNAL_BUY : TRADE_SIGNAL_SELL, "GapContinuation", confidence, "");

        return (isBuy ? TRADE_SIGNAL_BUY : TRADE_SIGNAL_SELL);
    }
};

#endif // GAP_CONTINUATION_STRATEGY_MQH
