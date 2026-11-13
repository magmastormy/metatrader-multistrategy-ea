// NY Open Gap: NDOG fade with FVG confluence during NY open
// Trades the gap-fill tendency at 13:30-14:00 UTC
// (= 09:30-10:00 NY local during US daylight time; shift +1h for
// US standard time). Window is evaluated in GMT, NOT broker time.
// Session-specific strategy for forex/metals/indices
#ifndef NY_OPEN_GAP_STRATEGY_MQH
#define NY_OPEN_GAP_STRATEGY_MQH

#include "../Core/Strategy/StrategyBase.mqh"
#include "../Core/Utils/SignalGuards.mqh"
// Risk Manager for AGENTS.md invariant #1
#include "../Core/Risk/UnifiedRiskManager.mqh"
#include "../Core/Utils/Instruments.mqh"
#include "../IndicatorManager.mqh"
#include "UnifiedICTFiles/SessionGapDetector.mqh"
#include "UnifiedICTFiles/ImbalanceDetector.mqh"

// CNYOpenGapStrategy trades the NDOG fade with FVG confluence during NY open.
// US DST: second Sunday of March (2:00 AM local) to first Sunday of November (2:00 AM local).
// `when` is a GMT datetime (UTC seconds). The transition hour is honoured by comparing against
// the exact UTC timestamps of the 2:00 AM local transitions, so a bar exactly on the transition
// date is classified by its time of day, not just its date.
bool NYOpenIsUSDaylightTime(const datetime when)
{
    MqlDateTime dt;
    TimeToStruct(when, dt);
    int year = dt.year;

    // DST start: second Sunday of March at 2:00 AM local time.
    MqlDateTime marchStart;
    marchStart.year = year; marchStart.mon = 3; marchStart.day = 1;
    marchStart.hour = 2; marchStart.min = 0; marchStart.sec = 0;
    datetime marchStartTime = StructToTime(marchStart);
    MqlDateTime marchProbe;
    TimeToStruct(marchStartTime, marchProbe);
    int marchDow = marchProbe.day_of_week;
    int firstSundayMarch = (marchDow == 0) ? 1 : (8 - marchDow);
    int secondSundayMarch = firstSundayMarch + 7;

    MqlDateTime dstStartStruct;
    dstStartStruct.year = year; dstStartStruct.mon = 3; dstStartStruct.day = secondSundayMarch;
    dstStartStruct.hour = 2; dstStartStruct.min = 0; dstStartStruct.sec = 0;
    datetime dstStart = StructToTime(dstStartStruct);

    // DST end: first Sunday of November at 2:00 AM local time.
    MqlDateTime novemberStart;
    novemberStart.year = year; novemberStart.mon = 11; novemberStart.day = 1;
    novemberStart.hour = 2; novemberStart.min = 0; novemberStart.sec = 0;
    datetime novemberStartTime = StructToTime(novemberStart);
    MqlDateTime novemberProbe;
    TimeToStruct(novemberStartTime, novemberProbe);
    int novemberDow = novemberProbe.day_of_week;
    int firstSundayNovember = (novemberDow == 0) ? 1 : (8 - novemberDow);

    MqlDateTime dstEndStruct;
    dstEndStruct.year = year; dstEndStruct.mon = 11; dstEndStruct.day = firstSundayNovember;
    dstEndStruct.hour = 2; dstEndStruct.min = 0; dstEndStruct.sec = 0;
    datetime dstEnd = StructToTime(dstEndStruct);

    return (when >= dstStart && when < dstEnd);
}

// Targets gap-fill tendency at the 09:30 New York open (13:30 UTC in US DST, 14:30 UTC otherwise).
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
        // umbrella check - the old 4-family test let DEX and the
        // other Deriv families through into NY-open logic that is meaningless
        // on 24/7 synthetics (including weekend "gaps").
        if(IsSyntheticIndexSymbolName(m_symbol))
        {
            SetDecisionReasonTag("NYGAP_SYNTHETIC_SKIP");
            return TRADE_SIGNAL_NONE;
        }

        // --- Time filter: 30 minutes after the 09:30 New York open, in UTC ---
        // Evaluated in GMT: TimeCurrent() is broker-local and would shift the window on non-UTC brokers.
        const datetime gmtNow = TimeGMT();
        MqlDateTime nowDt;
        TimeGMT(nowDt);
        const bool dstNow = NYOpenIsUSDaylightTime(gmtNow);
        int windowStartMin = dstNow ? (13 * 60 + 30) : (14 * 60 + 30);
        int nowMin = nowDt.hour * 60 + nowDt.min;
        bool inWindow = (nowMin >= windowStartMin && nowMin <= windowStartMin + 30);
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

        // --- Detect gap: open of the NY-open M30 bar vs close of the M30 bar ending at the prior NY close ---
        // Both bars are located by GMT time converted to broker time. The broker offset is computed per
        // candidate from the bar's own GMT time (DST-aware) instead of being reused from TimeCurrent(),
        // so DST transition weekends and seasonal broker offsets cannot shift the session boundary by an hour.
        const datetime gmtDay = gmtNow - (gmtNow % 86400);
        const int brokerOffsetNow = (int)MathRound((double)(TimeCurrent() - gmtNow) / 1800.0) * 1800;
        const int standardOffset  = brokerOffsetNow - (dstNow ? 3600 : 0);

        const datetime nyOpenGmt = gmtDay + windowStartMin * 60;
        const int brokerOffsetOpen = standardOffset + (NYOpenIsUSDaylightTime(nyOpenGmt) ? 3600 : 0);
        const datetime nyOpenServer = nyOpenGmt + brokerOffsetOpen;

        datetime priorNyCloseGmt = 0;
        for(int back = 1; back <= 4 && priorNyCloseGmt == 0; back++)
        {
            datetime candidate = gmtDay - back * 86400 + (windowStartMin + 390) * 60;
            MqlDateTime candidateDt;
            TimeToStruct(candidate, candidateDt);
            if(candidateDt.day_of_week != 0 && candidateDt.day_of_week != 6)
                priorNyCloseGmt = candidate;
        }
        if(priorNyCloseGmt == 0)
        {
            SetDecisionReasonTag("NYGAP_NO_PRIOR_SESSION");
            return TRADE_SIGNAL_NONE;
        }

        const int brokerOffsetClose = standardOffset + (NYOpenIsUSDaylightTime(priorNyCloseGmt) ? 3600 : 0);
        const datetime nyPriorCloseBarOpen = priorNyCloseGmt - 1800 + brokerOffsetClose;
        const int openShift  = iBarShift(m_symbol, PERIOD_M30, nyOpenServer, false);
        const int closeShift = iBarShift(m_symbol, PERIOD_M30, nyPriorCloseBarOpen, false);
        if(openShift < 0 || closeShift < 0 ||
           iTime(m_symbol, PERIOD_M30, openShift) != nyOpenServer ||
           iTime(m_symbol, PERIOD_M30, closeShift) != nyPriorCloseBarOpen)
        {
            SetDecisionReasonTag("NYGAP_SESSION_BARS_MISSING");
            return TRADE_SIGNAL_NONE;
        }

        double prevDayClose = iClose(m_symbol, PERIOD_M30, closeShift);
        double todayOpen    = iOpen(m_symbol,  PERIOD_M30, openShift);

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
        // Fade the gap: gap UP â†?SELL, gap DOWN â†?BUY
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

        long spreadPoints = SymbolInfoInteger(m_symbol, SYMBOL_SPREAD);
        double spreadPrice = (point > 0) ? (double)spreadPoints * point : 0.0;

        if(!CSignalGuards::IsSignalTradable(currentPrice, slPrice, tpPrice, spreadPrice))
        {
            SetDecisionReasonTag("NYGAP_NOT_TRADABLE");
            return TRADE_SIGNAL_NONE;
        }

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

