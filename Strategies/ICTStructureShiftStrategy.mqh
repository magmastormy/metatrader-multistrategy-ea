// ICT market structure shift: enter the first displacement that confirms a break of structure.
//
// No row in the roster reads a *structural* level for its entry. `Support/Resistance` uses pivots and
// Fibonacci confluence, `Breaker Block` needs a failed order block, `FVG Scalper` needs an imbalance -
// all patterns. This row instead asks the question the structure analyzer already answers: has the
// last swing been broken (BOS = continuation, CHoCH = reversal), and did the break come with
// displacement rather than drift? A break with body is a change of who is in control; a break with a
// wick is a liquidity grab that the Turtle Soup row already trades.
//
// Shape:
//   - `CMarketStructureAnalyzer::Update()` runs first on every evaluated bar, and the break flags are
//     read after it - the analyzer resets them on each classification, so reading before would see the
//     previous bar's answer.
//   - The break must be recent (within 2 bars) and the structural direction must be known.
//   - A CISD (change in state of delivery) in the same direction within 3 bars is the confirmation:
//     it is what separates a displacement leg from a single oversized candle.
//   - Stop 1.2 ATR, target 2.4 ATR = 2R.
//   - Category `STRATEGY_SUPPORT_RESISTANCE` (regime-neutral) on purpose: the `ictWeightMult` group
//     is the operator's global dial for the existing ICT rows, and a new row silently inheriting
//     someone else's multiplier would make its weight unreadable from the catalog. The row is judged
//     by its own break-and-displacement gate instead.
#ifndef ICT_STRUCTURE_SHIFT_STRATEGY_MQH
#define ICT_STRUCTURE_SHIFT_STRATEGY_MQH

#include "../Core/Strategy/StrategyBase.mqh"
#include "../Core/Utils/SignalGuards.mqh"
#include "UnifiedICTFiles/MarketStructureAnalyzer.mqh"

class CICTStructureShiftStrategy : public CStrategyBase
{
private:
    CMarketStructureAnalyzer m_structure;
    bool        m_analyzerReady;

    int         m_atrPeriod;
    int         m_breakMaxBarsAgo;
    int         m_cisdMaxBarsAgo;
    double      m_atrStopMult;
    double      m_rewardMultiple;

    int         m_atrHandle;
    datetime    m_lastSignalBar;

    double PointSize() const
    {
        double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
        return (point > 0.0 ? point : 0.0);
    }

protected:
    virtual void HandleNewBar() override { RefreshForNewBar(); }

public:
    CICTStructureShiftStrategy() :
        CStrategyBase("ICT Structure Shift", 0),
        m_analyzerReady(false),
        m_atrPeriod(14),
        m_breakMaxBarsAgo(2),
        m_cisdMaxBarsAgo(3),
        m_atrStopMult(1.2),
        m_rewardMultiple(2.0),
        m_atrHandle(INVALID_HANDLE),
        m_lastSignalBar(0)
    {
        m_strategyPrefix = "ICTSHIFT";
        OverrideMinConfidence(0.58);
    }

    virtual bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe,
                      void* tradeMgr, void* posSizer, void* unifiedRiskMgr = NULL) override
    {
        if(!CStrategyBase::Init(symbol, timeframe, tradeMgr, posSizer, unifiedRiskMgr))
            return false;

        m_atrHandle = iATR(symbol, timeframe, m_atrPeriod);
        if(m_atrHandle == INVALID_HANDLE)
        {
            PrintFormat("[ICTSHIFT] Init failed | %s %s | atr=%d", symbol, EnumToString(timeframe), m_atrHandle);
            return false;
        }

        // swingStrength 3 = the analyzer's own default; the row does not retune structure detection,
        // it only reads the answer.
        m_analyzerReady = m_structure.Initialize(symbol, timeframe, 3);
        if(!m_analyzerReady)
            PrintFormat("[ICTSHIFT] WARNING: structure analyzer failed to initialise for %s - row will stay silent.", symbol);

        if(GetUnifiedRiskManager() == NULL)
            Print("[ICTSHIFT] WARNING: UnifiedRiskManager not provided - trades will bypass validation!");

        return true;
    }

    virtual void Deinit() override
    {
        if(m_atrHandle != INVALID_HANDLE) { IndicatorRelease(m_atrHandle); m_atrHandle = INVALID_HANDLE; }
        m_analyzerReady = false;
        CStrategyBase::Deinit();
    }

    virtual ~CICTStructureShiftStrategy() { Deinit(); }

    virtual void OnTick() override
    {
        // New-bar evaluation only; consensus polls GetSignal().
    }

    virtual ENUM_STRATEGY_TYPE GetType() const override { return (ENUM_STRATEGY_TYPE)STRATEGY_SUPPORT_RESISTANCE; }

    virtual ENUM_TRADE_SIGNAL ExecuteSignal(double &confidence) override
    {
        confidence = 0.0;
        SetDecisionReasonTag("ICTSHIFT_UNSET");

        if(!m_is_initialized)
            return RejectSignal("ICTSHIFT_UNINITIALIZED");
        if(m_atrHandle == INVALID_HANDLE)
            return RejectSignal("ICTSHIFT_INVALID_HANDLES");
        if(!m_analyzerReady)
            return RejectSignal("ICTSHIFT_NO_ANALYZER");

        datetime barTime = iTime(m_symbol, m_timeframe, 1);
        if(barTime == m_lastSignalBar)
            return RejectSignal("ICTSHIFT_SAME_BAR");

        double atr[1], barClose[1];
        if(CopyBuffer(m_atrHandle, 0, 1, 1, atr) != 1 || atr[0] <= 0.0)
            return RejectSignal("ICTSHIFT_NO_ATR");
        if(CopyClose(m_symbol, m_timeframe, 1, 1, barClose) != 1)
            return RejectSignal("ICTSHIFT_NO_BAR_CLOSE");

        // Classify first, read the flags second: the analyzer resets the break flags on every
        // classification pass, so a read before Update() answers from the previous bar.
        m_structure.Update();

        if(!m_structure.HasBMS(m_breakMaxBarsAgo))
            return RejectSignal("ICTSHIFT_NO_BREAK");

        const bool wasBos   = m_structure.WasLastBreakBOS();
        const bool wasChoch = m_structure.WasLastBreakCHoCH();
        if(!wasBos && !wasChoch)
            return RejectSignal("ICTSHIFT_NO_BREAK_FLAG");

        const bool bullish = m_structure.IsBullishStructure();
        const bool bearish = m_structure.IsBearishStructure();
        if(!bullish && !bearish)
            return RejectSignal("ICTSHIFT_NO_STRUCTURE");

        // Direction must agree with the structure the break happened in.
        if(wasBos)
        {
            if(bullish == bearish)
                return RejectSignal("ICTSHIFT_CONFLICT");
        }
        const bool isBuy = wasBos ? bullish : bearish;   // CHoCH trades the new side

        // Displacement confirmation: without it the break is a wick and the Turtle Soup row owns that.
        const bool cisdOk = isBuy ? m_structure.HasRecentBullishCISD(m_cisdMaxBarsAgo)
                                  : m_structure.HasRecentBearishCISD(m_cisdMaxBarsAgo);
        if(!cisdOk)
            return RejectSignal("ICTSHIFT_NO_CISD");

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
            return RejectSignal("ICTSHIFT_NOT_TRADABLE");

        // A BOS is continuation in an established structure; a CHoCH is the harder call - the first
        // break of a trend - so it is priced a little lower until the next BOS confirms it.
        confidence = wasBos ? 0.62 : 0.58;
        if(bullish == bearish) confidence += 0.04;   // trend confirmed in both directions' read
        if(m_structure.GetConsecutiveBMS() >= 2) confidence += 0.04;
        if(m_structure.DetectCISDDisplacement()) confidence += 0.04;
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
        if(!ValidateWithRiskManager(request, "ICTSHIFT", confidence))
            return TRADE_SIGNAL_NONE;

        m_lastSignalBar = barTime;
        SetDecisionReasonTag(isBuy ? (wasBos ? "ICTSHIFT_BOS_BUY" : "ICTSHIFT_CHOCH_BUY")
                                   : (wasBos ? "ICTSHIFT_BOS_SELL" : "ICTSHIFT_CHOCH_SELL"));

        PrintFormat("[ICTSHIFT] %s | %s | %s | ATR=%.5f | stop=%.5f tp=%.5f | Conf=%.1f%%",
                    m_symbol, (isBuy ? "BUY" : "SELL"), (wasBos ? "BOS" : "CHoCH"), atr[0],
                    stop, target, confidence * 100.0);
        LogConsensusDiag(isBuy ? TRADE_SIGNAL_BUY : TRADE_SIGNAL_SELL, "ICTStructureShift", confidence, "");

        return (isBuy ? TRADE_SIGNAL_BUY : TRADE_SIGNAL_SELL);
    }
};

#endif // ICT_STRUCTURE_SHIFT_STRATEGY_MQH
