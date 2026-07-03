//+------------------------------------------------------------------+
//| NYOpenGapStrategy.mqh                                            |
//| NY Open Gap: NDOG fade with FVG confluence during NY open       |
//| Trades the gap-fill tendency at 13:30-14:00 UTC (9:30-10 AM EST)|
//|                                                                  |
//| Batch 103: Session-specific strategy for forex/metals/indices     |
//+------------------------------------------------------------------+
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
// Targets gap-fill tendency at 13:30-14:00 UTC (9:30-10 AM EST).
class CNYOpenGapStrategy : public CStrategyBase
{
private:
    CSessionGapDetector*  m_sessionGapDetector;
    CImbalanceDetector*   m_imbalanceDetector;
    int                   m_lastBarCount;

    // Risk Management (AGENTS.md invariant #1)
    CUnifiedRiskManager*  m_riskManager;

    bool RefreshForNewBar()
    {
        int barCount = iBars(m_symbol, m_timeframe);
        if(barCount <= 0 || barCount == m_lastBarCount)
            return false;

        m_lastBarCount = barCount;
        if(m_sessionGapDetector != NULL) m_sessionGapDetector.Update();
        if(m_imbalanceDetector != NULL)  m_imbalanceDetector.Update();
        return true;
    }

public:
    CNYOpenGapStrategy(const string name = "NY Open Gap") :
        CStrategyBase(name, 0),
        m_sessionGapDetector(NULL),
        m_imbalanceDetector(NULL),
        m_lastBarCount(0),
        m_riskManager(NULL)
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

        m_lastBarCount = 0;

        // ARCHITECTURAL FIX: Risk manager is now properly injected via Init() signature
        m_riskManager = GetUnifiedRiskManager();
        if(m_riskManager == NULL)
            Print("[NYGAP] WARNING: UnifiedRiskManager not provided - trades will bypass validation!");

        return true;
    }

    virtual void Deinit() override
    {
        if(m_sessionGapDetector != NULL) { delete m_sessionGapDetector; m_sessionGapDetector = NULL; }
        if(m_imbalanceDetector != NULL)  { delete m_imbalanceDetector;  m_imbalanceDetector = NULL; }
        // Risk manager is not owned by this strategy - do NOT delete
        m_riskManager = NULL;
        CStrategyBase::Deinit();
    }

    virtual void OnTick() override
    {
        // Intentionally empty - strategy evaluates on new bar only via GetSignal()
    }
    virtual void OnNewBar(const string symbol, const ENUM_TIMEFRAMES timeframe) override
    {
        if(symbol == m_symbol && timeframe == m_timeframe)
            RefreshForNewBar();
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
        if(IsVolatilitySyntheticSymbolName(m_symbol) ||
           IsBoomCrashSyntheticSymbolName(m_symbol) ||
           IsJumpSyntheticSymbolName(m_symbol) ||
           IsStepSyntheticSymbolName(m_symbol))
        {
            SetDecisionReasonTag("NYGAP_SYNTHETIC_SKIP");
            return TRADE_SIGNAL_NONE;
        }

        // --- Time filter: only trade during 13:30-14:00 UTC (9:30-10:00 AM EST) ---
        MqlDateTime dt;
        TimeCurrent(dt);
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

        // --- Detect gap: current day open vs previous day close ---
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
        bool gapUp = (todayOpen > prevDayClose);  // Gap up = open > prev close
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

        // CRITICAL: Validate through UnifiedRiskManager (AGENTS.md invariant #1)
        if(m_riskManager != NULL)
        {
            STradeValidationRequest request;
            request.symbol = m_symbol;
            request.orderType = bullish ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
            request.lotSize = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
            request.stopLossPips = slPips;
            request.takeProfitPips = tpPips;
            request.confidence = confidence;
            request.strategy = GetName();
            request.clusterCode = "";

            CUnifiedRiskManager* riskMgr = m_riskManager;
            SValidationResult result;
            ZeroMemory(result);
            if(riskMgr != NULL)
                result = (*riskMgr).ValidateTradeRequest(request, "NYGAP");
            if(!result.approved)
            {
                SetDecisionReasonTag("NYGAP_RISK_REJECTED");
                PrintFormat("[NYGAP] Risk rejected %s at %.5f Conf=%.1f%%",
                           signal == TRADE_SIGNAL_BUY ? "BUY" : "SELL",
                           currentPrice, confidence * 100);
                return TRADE_SIGNAL_NONE;
            }
            confidence *= result.confidenceMultiplier;
        }

        SetDecisionReasonTag(bullish ? "NYGAP_SIGNAL_BUY" : "NYGAP_SIGNAL_SELL");
        RecordSignal();

        // CONSENSUS LOGGING (AGENTS.md requirement)
        PrintFormat("[CONSENSUS-DIAG] %s | %s | Gap: %s | FVG: %s | GapLvl: %s | Conf: %.1f%% | Weight: %.2f | Reason: %s",
                   m_symbol,
                   signal == TRADE_SIGNAL_BUY ? "BUY" : "SELL",
                   gapUp ? "Up" : "Down",
                   hasFVGConfluence ? "Yes" : "No",
                   nearGapLevel ? "Yes" : "No",
                   confidence * 100,
                   m_weight,
                   m_lastDecisionReasonTag);

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
