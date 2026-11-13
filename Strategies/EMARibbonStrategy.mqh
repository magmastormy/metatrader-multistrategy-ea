// EMA ribbon pullback: continuation inside an aligned stack, not a crossover.
//
// Trend (slot 1) already votes on an EMA crossover plus ADX and multi-timeframe alignment, so this
// row deliberately answers a different question: has the stack ALIGNED (8 > 21 > 55 > 200) and has
// price just pulled back into it and resumed? A crossover fires once per leg and often at the worst
// moment; an aligned stack with a shallow pullback is the structure a trend trader actually enters.
//
// Shape:
//   - The stack must be ordered on the closed bar, all four averages.
//   - Bar 1 must have traded into the 21-EMA (its low <= EMA21 for a long) and closed back beyond it,
//     which is the reset-and-resume rather than a fresh extension.
//   - The pullback must not be deep: the close stays within 1.0 ATR of the 21-EMA.
//   - Stop 1.2 ATR, target 2.4 ATR: 2R by construction.
#ifndef EMA_RIBBON_STRATEGY_MQH
#define EMA_RIBBON_STRATEGY_MQH

#include "../Core/Strategy/StrategyBase.mqh"
#include "../Core/Utils/SignalGuards.mqh"

class CEMARibbonStrategy : public CStrategyBase
{
private:
    int    m_fastPeriod;        // 8
    int    m_midPeriod;         // 21 - the pullback line
    int    m_slowPeriod;        // 55
    int    m_trendPeriod;       // 200
    int    m_atrPeriod;
    double m_maxPullbackAtr;    // how far from the 21-EMA the resume may be
    double m_atrStopMult;
    double m_rewardMultiple;

    int    m_fastHandle;
    int    m_midHandle;
    int    m_slowHandle;
    int    m_trendHandle;
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
    CEMARibbonStrategy() :
        CStrategyBase("EMA Ribbon Pullback", 0),
        m_fastPeriod(8),
        m_midPeriod(21),
        m_slowPeriod(55),
        m_trendPeriod(200),
        m_atrPeriod(14),
        m_maxPullbackAtr(1.0),
        m_atrStopMult(1.2),
        m_rewardMultiple(2.0),
        m_fastHandle(INVALID_HANDLE),
        m_midHandle(INVALID_HANDLE),
        m_slowHandle(INVALID_HANDLE),
        m_trendHandle(INVALID_HANDLE),
        m_atrHandle(INVALID_HANDLE),
        m_lastSignalBar(0)
    {
        m_strategyPrefix = "RIBBON";
        OverrideMinConfidence(0.58);
    }

    virtual bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe,
                      void* tradeMgr, void* posSizer, void* unifiedRiskMgr = NULL) override
    {
        if(!CStrategyBase::Init(symbol, timeframe, tradeMgr, posSizer, unifiedRiskMgr))
            return false;

        m_fastHandle  = iMA(symbol, timeframe, m_fastPeriod,  0, MODE_EMA, PRICE_CLOSE);
        m_midHandle   = iMA(symbol, timeframe, m_midPeriod,   0, MODE_EMA, PRICE_CLOSE);
        m_slowHandle  = iMA(symbol, timeframe, m_slowPeriod,  0, MODE_EMA, PRICE_CLOSE);
        m_trendHandle = iMA(symbol, timeframe, m_trendPeriod, 0, MODE_EMA, PRICE_CLOSE);
        m_atrHandle   = iATR(symbol, timeframe, m_atrPeriod);

        if(m_fastHandle == INVALID_HANDLE || m_midHandle == INVALID_HANDLE ||
           m_slowHandle == INVALID_HANDLE || m_trendHandle == INVALID_HANDLE || m_atrHandle == INVALID_HANDLE)
        {
            PrintFormat("[RIBBON] Init failed | %s %s | ema=%d/%d/%d/%d atr=%d",
                        symbol, EnumToString(timeframe), m_fastHandle, m_midHandle,
                        m_slowHandle, m_trendHandle, m_atrHandle);
            return false;
        }

        if(GetUnifiedRiskManager() == NULL)
            Print("[RIBBON] WARNING: UnifiedRiskManager not provided - trades will bypass validation!");

        return true;
    }

    virtual void Deinit() override
    {
        if(m_fastHandle  != INVALID_HANDLE) { IndicatorRelease(m_fastHandle);  m_fastHandle  = INVALID_HANDLE; }
        if(m_midHandle   != INVALID_HANDLE) { IndicatorRelease(m_midHandle);   m_midHandle   = INVALID_HANDLE; }
        if(m_slowHandle  != INVALID_HANDLE) { IndicatorRelease(m_slowHandle);  m_slowHandle  = INVALID_HANDLE; }
        if(m_trendHandle != INVALID_HANDLE) { IndicatorRelease(m_trendHandle); m_trendHandle = INVALID_HANDLE; }
        if(m_atrHandle   != INVALID_HANDLE) { IndicatorRelease(m_atrHandle);   m_atrHandle   = INVALID_HANDLE; }
        CStrategyBase::Deinit();
    }

    virtual ~CEMARibbonStrategy() { Deinit(); }

    virtual void OnTick() override
    {
        // New-bar evaluation only; consensus polls GetSignal().
    }

    virtual ENUM_STRATEGY_TYPE GetType() const override { return (ENUM_STRATEGY_TYPE)STRATEGY_TREND; }

    virtual ENUM_TRADE_SIGNAL ExecuteSignal(double &confidence) override
    {
        confidence = 0.0;
        SetDecisionReasonTag("RIBBON_UNSET");

        if(!m_is_initialized)
            return RejectSignal("RIBBON_UNINITIALIZED");
        if(m_fastHandle == INVALID_HANDLE || m_midHandle == INVALID_HANDLE ||
           m_slowHandle == INVALID_HANDLE || m_trendHandle == INVALID_HANDLE || m_atrHandle == INVALID_HANDLE)
            return RejectSignal("RIBBON_INVALID_HANDLES");

        datetime barTime = iTime(m_symbol, m_timeframe, 1);
        if(barTime == m_lastSignalBar)
            return RejectSignal("RIBBON_SAME_BAR");

        double fast[1], mid[1], slow[1], trend[1], atr[1];
        if(CopyBuffer(m_fastHandle, 0, 1, 1, fast) != 1 || fast[0] <= 0.0)
            return RejectSignal("RIBBON_NO_FAST");
        if(CopyBuffer(m_midHandle, 0, 1, 1, mid) != 1 || mid[0] <= 0.0)
            return RejectSignal("RIBBON_NO_MID");
        if(CopyBuffer(m_slowHandle, 0, 1, 1, slow) != 1 || slow[0] <= 0.0)
            return RejectSignal("RIBBON_NO_SLOW");
        if(CopyBuffer(m_trendHandle, 0, 1, 1, trend) != 1 || trend[0] <= 0.0)
            return RejectSignal("RIBBON_NO_TREND");
        if(CopyBuffer(m_atrHandle, 0, 1, 1, atr) != 1 || atr[0] <= 0.0)
            return RejectSignal("RIBBON_NO_ATR");

        double barLow[1], barHigh[1], barClose[1];
        if(CopyLow(m_symbol, m_timeframe, 1, 1, barLow) != 1)
            return RejectSignal("RIBBON_NO_BAR_LOW");
        if(CopyHigh(m_symbol, m_timeframe, 1, 1, barHigh) != 1)
            return RejectSignal("RIBBON_NO_BAR_HIGH");
        if(CopyClose(m_symbol, m_timeframe, 1, 1, barClose) != 1)
            return RejectSignal("RIBBON_NO_BAR_CLOSE");

        const bool stackUp   = (fast[0] > mid[0] && mid[0] > slow[0] && slow[0] > trend[0]);
        const bool stackDown = (fast[0] < mid[0] && mid[0] < slow[0] && slow[0] < trend[0]);
        if(!stackUp && !stackDown)
            return RejectSignal("RIBBON_NO_STACK");

        // Bar 1 must have tested the 21-EMA and closed back on the trend side of it.
        const bool touchedUp   = stackUp   && barLow[0]  <= mid[0] && barClose[0] > mid[0];
        const bool touchedDown = stackDown && barHigh[0] >= mid[0] && barClose[0] < mid[0];
        if(!touchedUp && !touchedDown)
            return RejectSignal("RIBBON_NO_RESUME");

        if(MathAbs(barClose[0] - mid[0]) > atr[0] * m_maxPullbackAtr)
            return RejectSignal("RIBBON_TOO_FAR");

        const bool isBuy = touchedUp;
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
            return RejectSignal("RIBBON_NOT_TRADABLE");

        confidence = 0.60;
        // Fan width: a wide stack that stays ordered is a stronger alignment than four lines in a knot.
        const double fanWidth = MathAbs(fast[0] - trend[0]);
        if(fanWidth >= atr[0] * 1.5) confidence += 0.08;
        // The pullback barely reached the ribbon: the shallowest reset.
        if(MathAbs(barClose[0] - mid[0]) <= atr[0] * 0.5) confidence += 0.04;
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
        if(!ValidateWithRiskManager(request, "RIBBON", confidence))
            return TRADE_SIGNAL_NONE;

        m_lastSignalBar = barTime;
        SetDecisionReasonTag(isBuy ? "RIBBON_PULLBACK_BUY" : "RIBBON_PULLBACK_SELL");

        PrintFormat("[RIBBON] %s | %s | 8=%.5f 21=%.5f 55=%.5f 200=%.5f ATR=%.5f | stop=%.5f tp=%.5f | Conf=%.1f%%",
                    m_symbol, (isBuy ? "BUY" : "SELL"), fast[0], mid[0], slow[0], trend[0], atr[0],
                    stop, target, confidence * 100.0);
        LogConsensusDiag(isBuy ? TRADE_SIGNAL_BUY : TRADE_SIGNAL_SELL, "EMARibbon", confidence, "");

        return (isBuy ? TRADE_SIGNAL_BUY : TRADE_SIGNAL_SELL);
    }
};

#endif // EMA_RIBBON_STRATEGY_MQH
