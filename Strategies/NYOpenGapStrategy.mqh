// NY Open Gap: NDOG fade with FVG confluence during NY open
// Trades the gap-fill tendency at 13:30-14:00 UTC
// (= 09:30-10:00 NY local during US daylight time; shift +1h for
// US standard time). Window is evaluated in GMT, NOT broker time.
// Batch 103: Session-specific strategy for forex/metals/indices
#ifndef NY_OPEN_GAP_STRATEGY_MQH
#define NY_OPEN_GAP_STRATEGY_MQH

#include "../Core/Strategy/StrategyBase.mqh"
// Risk Manager for AGENTS.md invariant #1
#include "../Core/Risk/UnifiedRiskManager.mqh"
#include "../Core/Utils/Instruments.mqh"
#include "../IndicatorManager.mqh"
#include "UnifiedICTFiles/SessionGapDetector.mqh"
#include "UnifiedICTFiles/ImbalanceDetector.mqh"

// CNYOpenGapStrategy trades the NDOG fade with FVG confluence during NY open.
// Targets gap-fill tendency at 13:30-14:00 UTC (NY 09:30-10:00 local in US DST).
class CNYOpenGapStrategy : public CStrategyBase
{
private:
    CSessionGapDetector*  m_sessionGapDetector;
    CImbalanceDetector*   m_imbalanceDetector;

protected:
    virtual void HandleNewBar() override { RefreshForNewBar(); }
    virtual void OnRefreshComponents() override
    {
        if(m_sessionGapDetector != NULL) m_sessionGapDetector.Update();
        if(m_imbalanceDetector != NULL)  m_imbalanceDetector.Update();
    }

public:
    CNYOpenGapStrategy(const string name = "NY Open Gap") :
        CStrategyBase(name, 0),
        m_sessionGapDetector(NULL),
        m_imbalanceDetector(NULL)
    {
        OverrideMinConfidence(0.50);
    }

    virtual ~CNYOpenGapStrategy()
    {
        Deinit();
    }

    virtual bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeMgr, void* posSizer, void* unifiedRiskMgr = NULL) override
    {
        if(!CStrategyBase::Init(symbol, timeframe, tradeMgr, posSizer, unifiedRiskMgr))
            return false;

        m_sessionGapDetector = new CSessionGapDetector();
        m_imbalanceDetector  = new CImbalanceDetector();
        if(m_sessionGapDetector == NULL || m_imbalanceDetector == NULL)
            return false;

        if(!m_sessionGapDetector.Initialize(symbol, PERIOD_D1) ||
           !m_imbalanceDetector.Initialize(symbol, timeframe))
        {
            return false;
        }

        return true;
    }

    virtual void Deinit() override
    {
        if(m_sessionGapDetector != NULL) { delete m_sessionGapDetector; m_sessionGapDetector = NULL; }
        if(m_imbalanceDetector != NULL)  { delete m_imbalanceDetector;  m_imbalanceDetector = NULL; }
        CStrategyBase::Deinit();
    }

    virtual void OnTick() override
    {
        // Intentionally empty - strategy evaluates on new bar only via GetSignal()
    }

    virtual ENUM_TRADE_SIGNAL GetSignal(double &confidence) override
    {
        confidence = 0.0;
        SetDecisionReasonTag("NYGAP_UNSET");
        if(!IsEnabled() || !m_is_initialized)
        {
            SetDecisionReasonTag("NYGAP_DISABLED_OR_UNINIT");
            return TRADE_SIGNAL_NONE;
        }

        // --- Synthetic symbol filter: NY Open Gap only works on forex/metals/indices ---
        // Batch 155: umbrella check - the old 4-family test let DEX and the
        // other Deriv families through into NY-open logic that is meaningless
        // on 24/7 synthetics (including weekend "gaps").
        if(IsSyntheticIndexSymbolName(m_symbol))
        {
            SetDecisionReasonTag("NYGAP_SYNTHETIC_SKIP");
            return TRADE_SIGNAL_NONE;
        }

        // --- Time filter: only trade during 13:30-14:00 UTC ---
        // FIX (2026-08-14): use TimeGMT(), not TimeCurrent(). TimeCurrent() is broker-local
        // time, so on a non-UTC broker the window would fire at the wrong clock hour (or never).
        // The window is defined in UTC, so it must be evaluated in GMT.
        MqlDateTime dt;
        TimeGMT(dt);
        bool inWindow = (dt.hour == 13 && dt.min >= 30) || (dt.hour == 14 && dt.min == 0);
        if(!inWindow)
        {
            SetDecisionReasonTag("NYGAP_OUTSIDE_WINDOW");
            return TRADE_SIGNAL_NONE;
        }

        RefreshForNewBar();
        if(m_sessionGapDetector == NULL || m_imbalanceDetector == NULL)
        {
            SetDecisionReasonTag("NYGAP_COMPONENTS_NOT_READY");
            return TRADE_SIGNAL_NONE;
        }

        // --- Detect gap: current day D1 open vs previous D1 close ---
        // NOTE (2026-08-14): this is a daily-gap PROXY. A true NDOG (New York Day Open Gap)
        // is the gap between the prior NY session close (~16:00 ET) and the current NY open
        // (~09:30 ET). D1 bars roll at broker midnight, not the NY session, so on a UTC broker
        // this measures the gap at ~19:00 ET, not 09:30 ET. The SessionGapDetector (m_sessionGapDetector)
        // already computes the proper NDOG for the nearGapLevel check. A full fix = derive the gap
        // from the H1 bar at the NY open (DST-aware). Documented as a follow-up (see STRATEGY_AUDIT_2026-08-14).
        if(iBars(m_symbol, PERIOD_D1) < 3)
        {
            SetDecisionReasonTag("NYGAP_INSUFFICIENT_D1_BARS");
            return TRADE_SIGNAL_NONE;
        }

        double prevDayClose = iClose(m_symbol, PERIOD_D1, 1);
        double todayOpen    = iOpen(m_symbol,  PERIOD_D1, 0);

        if(prevDayClose <= 0 || todayOpen <= 0)
        {
            SetDecisionReasonTag("NYGAP_INVALID_PRICES");
            return TRADE_SIGNAL_NONE;
        }

        double gapSize = MathAbs(todayOpen - prevDayClose);

        // --- Gap must be > 0.5 * ATR(14) to be significant ---
        double atr = 0;
        int atrHandle = CIndicatorManager::Instance().GetATRHandle(m_symbol, PERIOD_D1, 14);
        if(atrHandle != INVALID_HANDLE)
        {
            double atrBuf[];
            ArraySetAsSeries(atrBuf, true);
            if(CopyBuffer(atrHandle, 0, 0, 1, atrBuf) > 0)
                atr = atrBuf[0];
        }

        if(atr <= 0)
        {
            SetDecisionReasonTag("NYGAP_ATR_UNAVAILABLE");
            return TRADE_SIGNAL_NONE;
        }

        if(gapSize < 0.5 * atr)
        {
            SetDecisionReasonTag("NYGAP_GAP_TOO_SMALL");
            return TRADE_SIGNAL_NONE;
        }

        // --- Determine gap direction ---
        bool gapUp = (todayOpen > prevDayClose);
        // Fade the gap: gap UP → SELL, gap DOWN → BUY
        bool bullish = !gapUp;

        // --- Check FVG confluence in gap-fill direction ---
        int fvgIdx = bullish ? m_imbalanceDetector.FindBestBullishImbalance()
                             : m_imbalanceDetector.FindBestBearishImbalance();
        bool hasFVGConfluence = (fvgIdx >= 0);

        // --- Check session gap detector level proximity ---
        SSessionGap ndog;
        bool hasNDOG = m_sessionGapDetector.GetNDOG(ndog);
        bool nearGapLevel = false;
        double currentPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);
        if(hasNDOG && ndog.isValid && !ndog.isFilled)
        {
            nearGapLevel = m_sessionGapDetector.IsNearGapMidpoint(currentPrice, 0.15);
        }

        // --- Confidence calculation ---
        double score = 0.50;
        if(hasFVGConfluence)  score += 0.10;  // FVG confluence boost
        if(gapSize > 1.0 * atr) score += 0.08;  // Large gap boost
        if(nearGapLevel)      score += 0.07;  // Near session gap detector level

        confidence = MathMin(0.95, score);

        if(confidence < m_minConfidence)
        {
            SetDecisionReasonTag("NYGAP_CONFIDENCE_BELOW_FLOOR");
            confidence = 0.0;
            return TRADE_SIGNAL_NONE;
        }

        ENUM_TRADE_SIGNAL signal = bullish ? TRADE_SIGNAL_BUY : TRADE_SIGNAL_SELL;

        // --- SL/TP calculation ---
        // SL beyond gap extreme + 0.5*ATR
        double slPrice, tpPrice;
        if(bullish)
        {
            // BUY: SL below gap bottom - 0.5*ATR, TP at previous close (gap fill target)
            slPrice = MathMin(prevDayClose, todayOpen) - 0.5 * atr;
            tpPrice = prevDayClose;
        }
        else
        {
            // SELL: SL above gap top + 0.5*ATR, TP at previous close (gap fill target)
            slPrice = MathMax(prevDayClose, todayOpen) + 0.5 * atr;
            tpPrice = prevDayClose;
        }

        double slDistance = MathAbs(currentPrice - slPrice);
        double tpDistance = MathAbs(tpPrice - currentPrice);
        double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
        double slPips = (point > 0 && slDistance > 0) ? (slDistance / point) : 0.0;
        double tpPips = (point > 0 && tpDistance > 0) ? (tpDistance / point) : 0.0;

        if(slPips <= 0)
        {
            SetDecisionReasonTag("NYGAP_INVALID_SL");
            return TRADE_SIGNAL_NONE;
        }

        STradeValidationRequest request;
        request.symbol = m_symbol;
        request.orderType = bullish ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
        request.lotSize = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
        request.stopLossPips = slPips;
        request.takeProfitPips = tpPips;
        request.confidence = confidence;
        request.strategy = GetName();
        request.clusterCode = "";

        SetProposedStops(request.stopLossPips, request.takeProfitPips); // FINDING 0
        if(!ValidateWithRiskManager(request, "NYGAP", confidence))
            return TRADE_SIGNAL_NONE;

        SetDecisionReasonTag(bullish ? "NYGAP_SIGNAL_BUY" : "NYGAP_SIGNAL_SELL");
        RecordSignal();

        // CONSENSUS LOGGING (AGENTS.md requirement)
        LogConsensusDiag(signal, StringFormat("Gap: %s | FVG: %s | GapLvl: %s", gapUp ? "Up" : "Down", hasFVGConfluence ? "Yes" : "No", nearGapLevel ? "Yes" : "No"), confidence);

        PrintFormat("[NYGAP] %s: %s | GapSize: %.1f ATR | SL: %.5f | TP: %.5f | Conf: %.1f%%",
                   m_symbol,
                   signal == TRADE_SIGNAL_BUY ? "BUY" : "SELL",
                   gapSize / atr,
                   slPrice,
                   tpPrice,
                   confidence * 100);

        return signal;
    }

    virtual string GetName() const override { return "NY Open Gap"; }
    virtual ENUM_STRATEGY_TYPE GetType() const override { return STRATEGY_NY_OPEN_GAP; }
};

#endif
