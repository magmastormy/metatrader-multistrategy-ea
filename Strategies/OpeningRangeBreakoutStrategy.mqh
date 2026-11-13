// Opening range breakout: the first hour of the day decides the range, the rest of it decides direction.
//
// `Asian Range Break` already trades a session range, but that is a fixed wall-clock window on a
// specific venue and it is evaluated as a range box; this row asks the different question a day
// trader asks: has the first `m_rangeMinutes` of TODAY formed a range, and has a closed bar now left
// it? The opening range is the only range in the day whose high and low were both set by participants
// who did not yet know the day's direction, which is why its break is a decision rather than a drift.
//
// Shape:
//   - The range is fixed at `m_rangeMinutes` after the day open, and only closed bars inside that
//     window contribute to it; nothing is evaluated before the window closes, so the range cannot
//     change under a signal already taken.
//   - The break must clear the range edge by 0.1 ATR (a one-tick poke is a touch, not a break) and
//     must not be more than 1.5 ATR past the edge (that is chase risk, already booked).
//   - ADX(14) >= 18 on the crossing bar: a break without expansion is a range extension that will
//     revert.
//   - Refuses more than `m_activeHours` hours after the range closes; by then the opening range is
//     history and the trade on offer belongs to the trend rows.
//   - Stop 1.2 ATR, target 2.4 ATR: 2R by construction.
#ifndef OPENING_RANGE_BREAKOUT_STRATEGY_MQH
#define OPENING_RANGE_BREAKOUT_STRATEGY_MQH

#include "../Core/Strategy/StrategyBase.mqh"
#include "../Core/Utils/SignalGuards.mqh"

class COpeningRangeBreakoutStrategy : public CStrategyBase
{
private:
    int    m_rangeMinutes;
    int    m_atrPeriod;
    int    m_adxPeriod;
    double m_adxFloor;
    double m_minBreakAtr;
    double m_maxExtensionAtr;
    double m_atrStopMult;
    double m_rewardMultiple;
    int    m_activeHours;

    int    m_atrHandle;
    int    m_adxHandle;

    datetime m_lastSignalBar;

    double PointSize() const
    {
        double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
        return (point > 0.0 ? point : 0.0);
    }

    // Range high/low of the day's opening window, built from closed bars only. Returns false when the
    // window is not yet complete or produced no bars.
    bool ComputeOpeningRange(double &rangeHigh, double &rangeLow, datetime &rangeEnd) const
    {
        rangeHigh = 0.0;
        rangeLow  = 0.0;

        const datetime dayOpen = iTime(m_symbol, PERIOD_D1, 0);
        if(dayOpen <= 0)
            return false;

        rangeEnd = dayOpen + (datetime)(m_rangeMinutes * 60);
        if(TimeCurrent() < rangeEnd)
            return false;   // window still forming

        const int shiftOpen = iBarShift(m_symbol, m_timeframe, dayOpen, false);
        if(shiftOpen < 1)
            return false;

        bool any = false;
        for(int i = shiftOpen; i >= 1; i--)
        {
            const datetime barTime = iTime(m_symbol, m_timeframe, i);
            if(barTime <= 0)
                break;
            if(barTime >= rangeEnd)
                break;      // this bar is already outside the window
            if(barTime < dayOpen)
                break;      // walked past the day open (gap in history)

            double h[1], l[1];
            if(CopyHigh(m_symbol, m_timeframe, i, 1, h) != 1)
                break;
            if(CopyLow(m_symbol, m_timeframe, i, 1, l) != 1)
                break;

            if(!any)
            {
                rangeHigh = h[0];
                rangeLow  = l[0];
                any = true;
            }
            else
            {
                if(h[0] > rangeHigh) rangeHigh = h[0];
                if(l[0] < rangeLow)  rangeLow  = l[0];
            }
        }
        return any;
    }

protected:
    virtual void HandleNewBar() override { RefreshForNewBar(); }

public:
    COpeningRangeBreakoutStrategy() :
        CStrategyBase("Opening Range Breakout", 0),
        m_rangeMinutes(60),
        m_atrPeriod(14),
        m_adxPeriod(14),
        m_adxFloor(18.0),
        m_minBreakAtr(0.10),
        m_maxExtensionAtr(1.5),
        m_atrStopMult(1.2),
        m_rewardMultiple(2.0),
        m_activeHours(8),
        m_atrHandle(INVALID_HANDLE),
        m_adxHandle(INVALID_HANDLE),
        m_lastSignalBar(0)
    {
        m_strategyPrefix = "ORB";
        OverrideMinConfidence(0.58);
    }

    virtual bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe,
                      void* tradeMgr, void* posSizer, void* unifiedRiskMgr = NULL) override
    {
        if(!CStrategyBase::Init(symbol, timeframe, tradeMgr, posSizer, unifiedRiskMgr))
            return false;

        m_atrHandle = iATR(symbol, timeframe, m_atrPeriod);
        m_adxHandle = iADX(symbol, timeframe, m_adxPeriod);

        if(m_atrHandle == INVALID_HANDLE || m_adxHandle == INVALID_HANDLE)
        {
            PrintFormat("[ORB] Init failed | %s %s | atr=%d adx=%d",
                        symbol, EnumToString(timeframe), m_atrHandle, m_adxHandle);
            return false;
        }

        if(GetUnifiedRiskManager() == NULL)
            Print("[ORB] WARNING: UnifiedRiskManager not provided - trades will bypass validation!");

        return true;
    }

    virtual void Deinit() override
    {
        if(m_atrHandle != INVALID_HANDLE) { IndicatorRelease(m_atrHandle); m_atrHandle = INVALID_HANDLE; }
        if(m_adxHandle != INVALID_HANDLE) { IndicatorRelease(m_adxHandle); m_adxHandle = INVALID_HANDLE; }
        CStrategyBase::Deinit();
    }

    virtual ~COpeningRangeBreakoutStrategy() { Deinit(); }

    virtual void OnTick() override
    {
        // New-bar evaluation only; consensus polls GetSignal().
    }

    virtual ENUM_STRATEGY_TYPE GetType() const override { return (ENUM_STRATEGY_TYPE)STRATEGY_VOLATILITY_BREAKOUT; }

    virtual ENUM_TRADE_SIGNAL ExecuteSignal(double &confidence) override
    {
        confidence = 0.0;
        SetDecisionReasonTag("ORB_UNSET");

        if(!m_is_initialized)
            return RejectSignal("ORB_UNINITIALIZED");
        if(m_atrHandle == INVALID_HANDLE || m_adxHandle == INVALID_HANDLE)
            return RejectSignal("ORB_INVALID_HANDLES");

        datetime barTime = iTime(m_symbol, m_timeframe, 1);
        if(barTime == m_lastSignalBar)
            return RejectSignal("ORB_SAME_BAR");

        double atr[1], adx[1], barClose[1];
        if(CopyBuffer(m_atrHandle, 0, 1, 1, atr) != 1 || atr[0] <= 0.0)
            return RejectSignal("ORB_NO_ATR");
        if(CopyBuffer(m_adxHandle, 0, 1, 1, adx) != 1)
            return RejectSignal("ORB_NO_ADX");
        if(CopyClose(m_symbol, m_timeframe, 1, 1, barClose) != 1)
            return RejectSignal("ORB_NO_BAR_CLOSE");

        double rangeHigh, rangeLow;
        datetime rangeEnd;
        if(!ComputeOpeningRange(rangeHigh, rangeLow, rangeEnd))
            return RejectSignal("ORB_NO_RANGE");

        if(TimeCurrent() - rangeEnd > (long)m_activeHours * 3600)
            return RejectSignal("ORB_STALE");

        if(adx[0] < m_adxFloor)
            return RejectSignal("ORB_ADX_FLAT");

        const double clearance = atr[0] * m_minBreakAtr;
        const bool brokeUp   = (barClose[0] >  rangeHigh + clearance);
        const bool brokeDown = (barClose[0] <  rangeLow  - clearance);
        if(!brokeUp && !brokeDown)
            return RejectSignal("ORB_NO_BREAK");

        // Already too far past the edge: that is a chase, not a breakout.
        if(brokeUp && (barClose[0] - rangeHigh) > atr[0] * m_maxExtensionAtr)
            return RejectSignal("ORB_TOO_EXTENDED");
        if(brokeDown && (rangeLow - barClose[0]) > atr[0] * m_maxExtensionAtr)
            return RejectSignal("ORB_TOO_EXTENDED");

        const bool isBuy = brokeUp;
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
            return RejectSignal("ORB_NOT_TRADABLE");

        const double rangeWidth = rangeHigh - rangeLow;
        confidence = 0.60;
        // A narrow opening range makes the same break a smaller move: reward it less.
        if(rangeWidth >= atr[0] * 1.5) confidence += 0.06;
        if(adx[0] >= 25.0) confidence += 0.10;
        else if(adx[0] >= 20.0) confidence += 0.04;
        if((isBuy ? (barClose[0] - rangeHigh) : (rangeLow - barClose[0])) >= atr[0] * 0.5) confidence += 0.04;
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
        if(!ValidateWithRiskManager(request, "ORB", confidence))
            return TRADE_SIGNAL_NONE;

        m_lastSignalBar = barTime;
        SetDecisionReasonTag(isBuy ? "ORB_BREAK_BUY" : "ORB_BREAK_SELL");

        PrintFormat("[ORB] %s | %s | range=%.5f-%.5f width=%.5f ATR=%.5f ADX=%.1f | stop=%.5f tp=%.5f | Conf=%.1f%%",
                    m_symbol, (isBuy ? "BUY" : "SELL"), rangeLow, rangeHigh, rangeWidth, atr[0], adx[0],
                    stop, target, confidence * 100.0);
        LogConsensusDiag(isBuy ? TRADE_SIGNAL_BUY : TRADE_SIGNAL_SELL, "OpeningRangeBreakout", confidence, "");

        return (isBuy ? TRADE_SIGNAL_BUY : TRADE_SIGNAL_SELL);
    }
};

#endif // OPENING_RANGE_BREAKOUT_STRATEGY_MQH
