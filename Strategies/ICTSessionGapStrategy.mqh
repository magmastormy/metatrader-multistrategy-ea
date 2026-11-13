// ICT session gap fill: trade back toward the gap's consequent encroachment (CE), on the day/week
// boundary rather than the NY session open.
//
// `NY Open Gap` fades the 09:30 session open and `Gap Continuation` needs a gap that HOLDS. This row
// asks the third question the same discontinuity offers: while price is inside a live New Day /
// New Week Opening Gap, is it being drawn back to the gap's midpoint? The gap midpoint is the level
// ICT treats as the balance point, and the detector already tracks whether the gap is still open.
//
// Shape:
//   - The gap must be valid by the detector's own minimum-size filter and must not be filled yet.
//   - Price must currently sit INSIDE the gap, and on the far side of the midpoint from where it is
//     being drawn - the entry is toward the midpoint, so it needs the midpoint ahead of it.
//   - Stop sits beyond the gap edge on the entry side by 0.2 ATR, not at a fixed distance: the gap
//     edge is the level that invalidates the premise, so it is the only honest invalidation price.
//   - Target is the midpoint itself. `CSignalGuards::IsSignalTradable` refuses the request when that
//     geometry does not cover the stop, which is exactly the deep-gap case where filling to CE is not
//     worth the risk.
//   - Category is `STRATEGY_SUPPORT_RESISTANCE` (regime-neutral): a gap fill is a level trade, and
//     `STRATEGY_MEAN_REVERSION` is hard-zeroed by `RegimeStateHardGate` in `REGIME_TREND` - the state
//     a gap most often forms in.
#ifndef ICT_SESSION_GAP_STRATEGY_MQH
#define ICT_SESSION_GAP_STRATEGY_MQH

#include "../Core/Strategy/StrategyBase.mqh"
#include "../Core/Utils/SignalGuards.mqh"
#include "UnifiedICTFiles/SessionGapDetector.mqh"

class CICTSessionGapStrategy : public CStrategyBase
{
private:
    CSessionGapDetector m_gapDetector;
    bool                m_detectorReady;

    int    m_atrPeriod;
    double m_edgeBufferAtr;
    double m_minGapAtr;         // refuse a gap too small to pay the spread
    double m_nearEdgeAtr;       // "entered from the edge" bonus band

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
    CICTSessionGapStrategy() :
        CStrategyBase("ICT Session Gap", 0),
        m_detectorReady(false),
        m_atrPeriod(14),
        m_edgeBufferAtr(0.2),
        m_minGapAtr(0.25),
        m_nearEdgeAtr(0.3),
        m_atrHandle(INVALID_HANDLE),
        m_lastSignalBar(0)
    {
        m_strategyPrefix = "ICTSG";
        OverrideMinConfidence(0.56);
    }

    virtual bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe,
                      void* tradeMgr, void* posSizer, void* unifiedRiskMgr = NULL) override
    {
        if(!CStrategyBase::Init(symbol, timeframe, tradeMgr, posSizer, unifiedRiskMgr))
            return false;

        m_atrHandle = iATR(symbol, timeframe, m_atrPeriod);
        if(m_atrHandle == INVALID_HANDLE)
        {
            PrintFormat("[ICTSG] Init failed | %s %s | atr=%d", symbol, EnumToString(timeframe), m_atrHandle);
            return false;
        }

        // The detector reads day and week boundaries, so it is initialised on D1 regardless of the
        // chart timeframe; the chart timeframe only supplies the bar the signal is judged on.
        m_detectorReady = m_gapDetector.Initialize(symbol, PERIOD_D1);
        if(!m_detectorReady)
            PrintFormat("[ICTSG] WARNING: session gap detector failed to initialise for %s - row will stay silent.", symbol);

        if(GetUnifiedRiskManager() == NULL)
            Print("[ICTSG] WARNING: UnifiedRiskManager not provided - trades will bypass validation!");

        return true;
    }

    virtual void Deinit() override
    {
        if(m_atrHandle != INVALID_HANDLE) { IndicatorRelease(m_atrHandle); m_atrHandle = INVALID_HANDLE; }
        m_detectorReady = false;
        CStrategyBase::Deinit();
    }

    virtual ~CICTSessionGapStrategy() { Deinit(); }

    virtual void OnTick() override
    {
        // New-bar evaluation only; consensus polls GetSignal().
    }

    virtual ENUM_STRATEGY_TYPE GetType() const override { return (ENUM_STRATEGY_TYPE)STRATEGY_SUPPORT_RESISTANCE; }

    virtual ENUM_TRADE_SIGNAL ExecuteSignal(double &confidence) override
    {
        confidence = 0.0;
        SetDecisionReasonTag("ICTSG_UNSET");

        if(!m_is_initialized)
            return RejectSignal("ICTSG_UNINITIALIZED");
        if(m_atrHandle == INVALID_HANDLE)
            return RejectSignal("ICTSG_INVALID_HANDLES");
        if(!m_detectorReady)
            return RejectSignal("ICTSG_NO_DETECTOR");

        datetime barTime = iTime(m_symbol, m_timeframe, 1);
        if(barTime == m_lastSignalBar)
            return RejectSignal("ICTSG_SAME_BAR");

        double atr[1], barClose[1];
        if(CopyBuffer(m_atrHandle, 0, 1, 1, atr) != 1 || atr[0] <= 0.0)
            return RejectSignal("ICTSG_NO_ATR");
        if(CopyClose(m_symbol, m_timeframe, 1, 1, barClose) != 1)
            return RejectSignal("ICTSG_NO_BAR_CLOSE");

        // Refresh the detector once per evaluated bar, then take whichever live gap is present. NDOG
        // is the tighter premise, so it wins when both exist.
        m_gapDetector.Update();

        SSessionGap gap;
        bool haveGap = m_gapDetector.GetNDOG(gap);
        if(!haveGap)
            haveGap = m_gapDetector.GetNWOG(gap);
        if(!haveGap || !gap.isValid)
            return RejectSignal("ICTSG_NO_GAP");
        if(gap.isFilled)
            return RejectSignal("ICTSG_GAP_FILLED");
        if(gap.size < atr[0] * m_minGapAtr)
            return RejectSignal("ICTSG_GAP_TOO_SMALL");

        const double price = barClose[0];
        if(price > gap.gapTop || price < gap.gapBottom)
            return RejectSignal("ICTSG_OUTSIDE_GAP");

        // Direction is toward the midpoint, and the midpoint must be ahead of the price.
        const bool isBuy = (price < gap.midpoint);
        const double target = gap.midpoint;
        if(isBuy && target <= price)
            return RejectSignal("ICTSG_NO_ROOM");
        if(!isBuy && target >= price)
            return RejectSignal("ICTSG_NO_ROOM");

        const double buffer = atr[0] * m_edgeBufferAtr;
        const double stop = isBuy ? (gap.gapBottom - buffer) : (gap.gapTop + buffer);
        const double stopDistance = MathAbs(price - stop);
        const double targetDistance = MathAbs(target - price);
        if(stopDistance <= 0.0 || targetDistance <= 0.0)
            return RejectSignal("ICTSG_ZERO_DISTANCE");

        double entry = isBuy ? SymbolInfoDouble(m_symbol, SYMBOL_ASK) : SymbolInfoDouble(m_symbol, SYMBOL_BID);
        if(entry <= 0.0)
            entry = price;

        const double point = PointSize();
        const long spreadPoints = SymbolInfoInteger(m_symbol, SYMBOL_SPREAD);
        const double spreadPrice = (point > 0.0) ? (double)spreadPoints * point : 0.0;

        // The guard is the R:R gate for this row: gap geometry often does not cover the stop, and such
        // a request must be refused rather than widened into a target nobody asked for.
        if(!CSignalGuards::IsSignalTradable(entry, stop, target, spreadPrice))
            return RejectSignal("ICTSG_NOT_TRADABLE");

        confidence = 0.58;
        if(gap.size >= atr[0] * 1.0) confidence += 0.06;
        // Entered close to the edge: the whole gap is still ahead.
        const double distanceFromEdge = isBuy ? (price - gap.gapBottom) : (gap.gapTop - price);
        if(distanceFromEdge <= atr[0] * m_nearEdgeAtr) confidence += 0.04;
        if(gap.type == GAP_NWOG) confidence += 0.02;     // a weekly gap is the stronger premise
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
        if(!ValidateWithRiskManager(request, "ICTSG", confidence))
            return TRADE_SIGNAL_NONE;

        m_lastSignalBar = barTime;
        SetDecisionReasonTag(isBuy ? "ICTSG_FILL_BUY" : "ICTSG_FILL_SELL");

        PrintFormat("[ICTSG] %s | %s | gap=%s %.5f-%.5f ce=%.5f size=%.5f | entry=%.5f stop=%.5f tp=%.5f | Conf=%.1f%%",
                    m_symbol, (isBuy ? "BUY" : "SELL"), (gap.type == GAP_NWOG ? "NWOG" : "NDOG"),
                    gap.gapBottom, gap.gapTop, gap.midpoint, gap.size, entry, stop, target, confidence * 100.0);
        LogConsensusDiag(isBuy ? TRADE_SIGNAL_BUY : TRADE_SIGNAL_SELL, "ICTSessionGap", confidence, "");

        return (isBuy ? TRADE_SIGNAL_BUY : TRADE_SIGNAL_SELL);
    }
};

#endif // ICT_SESSION_GAP_STRATEGY_MQH
