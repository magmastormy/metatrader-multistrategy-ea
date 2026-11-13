// Failed-breakout fade at the previous day's high/low: the same level as the breakout row, used the
// other way round.
//
// This exists because a level-break breakout system loses exactly on the breaks that do not hold,
// and that loss is the fade's edge. The two rows are mutually exclusive by construction - the
// breakout row needs a close BEYOND the level, this one needs a bar that went beyond it and closed
// back INSIDE - so the same bar can never feed both votes, and no double-count of one event reaches
// consensus.
//
// Shape:
//   - The pierce must be on the last closed bar (bar 1), so the failure is fresh.
//   - The pierce depth is capped at 1.0 ATR: deeper than that is a trend day, not a false break.
//   - The close must be back inside by 0.2 ATR, so a close sitting exactly on the level is not a fade.
//   - The stop sits 0.5 ATR beyond the spike extreme, so the risk is defined by the thing that failed.
#ifndef DAILY_LEVEL_FADE_STRATEGY_MQH
#define DAILY_LEVEL_FADE_STRATEGY_MQH

#include "../Core/Strategy/StrategyBase.mqh"
#include "../Core/Utils/SignalGuards.mqh"

class CDailyLevelFadeStrategy : public CStrategyBase
{
private:
    int    m_atrPeriod;
    double m_reclaimAtr;       // how far back inside the level the close must be
    double m_maxPierceAtr;     // deeper than this and it is a trend day, not a failed break
    double m_stopBufferAtr;    // stop distance beyond the spike extreme
    double m_rewardMultiple;

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
    CDailyLevelFadeStrategy() :
        CStrategyBase("Daily Level Fade", 0),
        m_atrPeriod(14),
        m_reclaimAtr(0.20),
        m_maxPierceAtr(1.0),
        m_stopBufferAtr(0.5),
        m_rewardMultiple(1.8),
        m_atrHandle(INVALID_HANDLE),
        m_lastSignalBar(0)
    {
        m_strategyPrefix = "PDL-FADE";
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
            PrintFormat("[PDL-FADE] Init failed | %s %s | atr=%d",
                        symbol, EnumToString(timeframe), m_atrHandle);
            return false;
        }

        if(GetUnifiedRiskManager() == NULL)
            Print("[PDL-FADE] WARNING: UnifiedRiskManager not provided - trades will bypass validation!");

        return true;
    }

    virtual void Deinit() override
    {
        if(m_atrHandle != INVALID_HANDLE) { IndicatorRelease(m_atrHandle); m_atrHandle = INVALID_HANDLE; }
        CStrategyBase::Deinit();
    }

    virtual ~CDailyLevelFadeStrategy() { Deinit(); }

    virtual void OnTick() override
    {
        // New-bar evaluation only; consensus polls GetSignal().
    }

    // S/R category: regime-neutral. A fade has to be judged by its own reclaim, not zeroed by a
    // REGIME_TREND hard gate the way STRATEGY_MEAN_REVERSION would be.
    virtual ENUM_STRATEGY_TYPE GetType() const override { return (ENUM_STRATEGY_TYPE)STRATEGY_SUPPORT_RESISTANCE; }

    virtual ENUM_TRADE_SIGNAL ExecuteSignal(double &confidence) override
    {
        confidence = 0.0;
        SetDecisionReasonTag("PDLFADE_UNSET");

        if(!m_is_initialized)
            return RejectSignal("PDLFADE_UNINITIALIZED");
        if(m_atrHandle == INVALID_HANDLE)
            return RejectSignal("PDLFADE_INVALID_HANDLES");

        datetime barTime = iTime(m_symbol, m_timeframe, 1);
        if(barTime == m_lastSignalBar)
            return RejectSignal("PDLFADE_SAME_BAR");

        double atr[1], barHigh[1], barLow[1], barClose[1];
        if(CopyBuffer(m_atrHandle, 0, 1, 1, atr) != 1 || atr[0] <= 0.0)
            return RejectSignal("PDLFADE_NO_ATR");
        if(CopyHigh(m_symbol, m_timeframe, 1, 1, barHigh) != 1)
            return RejectSignal("PDLFADE_NO_BAR_HIGH");
        if(CopyLow(m_symbol, m_timeframe, 1, 1, barLow) != 1)
            return RejectSignal("PDLFADE_NO_BAR_LOW");
        if(CopyClose(m_symbol, m_timeframe, 1, 1, barClose) != 1)
            return RejectSignal("PDLFADE_NO_BAR_CLOSE");

        const double priorHigh = iHigh(m_symbol, PERIOD_D1, 1);
        const double priorLow  = iLow(m_symbol, PERIOD_D1, 1);
        if(priorHigh <= 0.0 || priorLow <= 0.0 || priorHigh <= priorLow)
            return RejectSignal("PDLFADE_NO_DAILY_LEVEL");

        const double reclaim = atr[0] * m_reclaimAtr;
        const double maxPierce = atr[0] * m_maxPierceAtr;

        bool fadeShort = false;
        bool fadeLong  = false;
        double extreme = 0.0;

        if(barHigh[0] > priorHigh)                       // pierced the prior high intrabar
        {
            const double pierce = barHigh[0] - priorHigh;
            if(pierce <= maxPierce && barClose[0] < priorHigh - reclaim)
            {
                fadeShort = true;
                extreme = barHigh[0];
            }
        }
        if(!fadeShort && barLow[0] < priorLow)           // pierced the prior low intrabar
        {
            const double pierce = priorLow - barLow[0];
            if(pierce <= maxPierce && barClose[0] > priorLow + reclaim)
            {
                fadeLong = true;
                extreme = barLow[0];
            }
        }

        if(!fadeShort && !fadeLong)
            return RejectSignal("PDLFADE_NO_FAILED_BREAK");

        const bool isBuy = fadeLong;

        double price = isBuy ? SymbolInfoDouble(m_symbol, SYMBOL_ASK) : SymbolInfoDouble(m_symbol, SYMBOL_BID);
        if(price <= 0.0)
            price = barClose[0];

        // The entry must still be near the level it is fading; if the market already ran, the fade is gone.
        const double level = isBuy ? priorLow : priorHigh;
        if(MathAbs(price - level) > atr[0] * 1.0)
            return RejectSignal("PDLFADE_PRICE_GONE");

        const double buffer = atr[0] * m_stopBufferAtr;
        const double stop = isBuy ? (extreme - buffer) : (extreme + buffer);
        const double stopDistance = MathAbs(price - stop);
        if(stopDistance <= 0.0)
            return RejectSignal("PDLFADE_ZERO_STOP");

        const double targetDistance = stopDistance * m_rewardMultiple;
        const double target = isBuy ? (price + targetDistance) : (price - targetDistance);

        const double point = PointSize();
        const long spreadPoints = SymbolInfoInteger(m_symbol, SYMBOL_SPREAD);
        const double spreadPrice = (point > 0.0) ? (double)spreadPoints * point : 0.0;

        if(!CSignalGuards::IsSignalTradable(price, stop, target, spreadPrice))
            return RejectSignal("PDLFADE_NOT_TRADABLE");

        confidence = 0.58;
        // A shallow pierce that closed far back inside is the cleaner failure.
        const double pierceDepth = MathAbs(extreme - level);
        if(pierceDepth <= atr[0] * 0.35) confidence += 0.06;
        if(MathAbs(barClose[0] - level) >= atr[0] * 0.5) confidence += 0.04;
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
        if(!ValidateWithRiskManager(request, "PDL-FADE", confidence))
            return TRADE_SIGNAL_NONE;

        m_lastSignalBar = barTime;
        SetDecisionReasonTag(isBuy ? "PDLFADE_RECLAIM_BUY" : "PDLFADE_REJECT_SELL");

        PrintFormat("[PDL-FADE] %s | %s | PDH=%.5f PDL=%.5f extreme=%.5f close=%.5f ATR=%.5f | stop=%.5f tp=%.5f | Conf=%.1f%%",
                    m_symbol, (isBuy ? "BUY" : "SELL"), priorHigh, priorLow, extreme, barClose[0], atr[0],
                    stop, target, confidence * 100.0);
        LogConsensusDiag(isBuy ? TRADE_SIGNAL_BUY : TRADE_SIGNAL_SELL, "DailyLevelFade", confidence, "");

        return (isBuy ? TRADE_SIGNAL_BUY : TRADE_SIGNAL_SELL);
    }
};

#endif // DAILY_LEVEL_FADE_STRATEGY_MQH
