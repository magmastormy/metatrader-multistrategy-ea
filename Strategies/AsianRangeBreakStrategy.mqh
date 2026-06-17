//+------------------------------------------------------------------+
//| AsianRangeBreakStrategy.mqh                                      |
//| Asian Range Break: London-open breakout of Asian session range    |
//| Tight Asian range + London expansion = high-probability breakout  |
//|                                                                  |
//| Batch 103: Session-specific strategy for forex/metals/indices     |
//+------------------------------------------------------------------+
#ifndef __ASIAN_RANGE_BREAK_STRATEGY_MQH__
#define __ASIAN_RANGE_BREAK_STRATEGY_MQH__

#include "../Core/Strategy/StrategyBase.mqh"
// Risk Manager for AGENTS.md invariant #1
#include "../Core/Risk/UnifiedRiskManager.mqh"
#include "../Core/Utils/Instruments.mqh"
#include "SMCFiles/KillZones.mqh"
#include "UnifiedICTFiles/MarketStructureAnalyzer.mqh"

class CAsianRangeBreakStrategy : public CStrategyBase
{
private:
    CICTKillZones*             m_killZones;
    CMarketStructureAnalyzer*  m_structureAnalyzer;
    int                        m_lastBarCount;

    // Risk Management (AGENTS.md invariant #1)
    CUnifiedRiskManager*       m_riskManager;

    bool RefreshForNewBar()
    {
        int barCount = iBars(m_symbol, m_timeframe);
        if(barCount <= 0 || barCount == m_lastBarCount)
            return false;

        m_lastBarCount = barCount;
        if(m_killZones != NULL) m_killZones.IsInKillZone();  // Refresh session state
        if(m_structureAnalyzer != NULL) m_structureAnalyzer.Update();
        return true;
    }

public:
    CAsianRangeBreakStrategy(const string name = "Asian Range Break") :
        CStrategyBase(name, 0),
        m_killZones(NULL),
        m_structureAnalyzer(NULL),
        m_lastBarCount(0),
        m_riskManager(NULL)
    {
        OverrideMinConfidence(0.50);
    }

    virtual ~CAsianRangeBreakStrategy()
    {
        Deinit();
    }

    virtual bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeMgr, void* posSizer, void* unifiedRiskMgr = NULL) override
    {
        if(!CStrategyBase::Init(symbol, timeframe, tradeMgr, posSizer, unifiedRiskMgr))
            return false;

        m_killZones = new CICTKillZones();
        m_structureAnalyzer = new CMarketStructureAnalyzer();
        if(m_killZones == NULL || m_structureAnalyzer == NULL)
            return false;

        if(!m_killZones.Initialize(2, true) ||
           !m_structureAnalyzer.Initialize(symbol, timeframe, 3))
        {
            return false;
        }

        m_lastBarCount = 0;

        // ARCHITECTURAL FIX: Risk manager is now properly injected via Init() signature
        m_riskManager = GetUnifiedRiskManager();
        if(m_riskManager == NULL)
            Print("[ASIANRB] WARNING: UnifiedRiskManager not provided - trades will bypass validation!");

        return true;
    }

    virtual void Deinit() override
    {
        if(m_killZones != NULL) { delete m_killZones; m_killZones = NULL; }
        if(m_structureAnalyzer != NULL) { delete m_structureAnalyzer; m_structureAnalyzer = NULL; }
        // Risk manager is not owned by this strategy - do NOT delete
        m_riskManager = NULL;
        CStrategyBase::Deinit();
    }

    virtual void OnTick() override {}
    virtual void OnNewBar(const string symbol, const ENUM_TIMEFRAMES timeframe) override
    {
        if(symbol == m_symbol && timeframe == m_timeframe)
            RefreshForNewBar();
    }

    virtual ENUM_TRADE_SIGNAL GetSignal(double &confidence) override
    {
        confidence = 0.0;
        SetDecisionReasonTag("ASIANRB_UNSET");

        // Step 1: Check enabled and initialized
        if(!IsEnabled() || !m_is_initialized)
        {
            SetDecisionReasonTag("ASIANRB_DISABLED_OR_UNINIT");
            return TRADE_SIGNAL_NONE;
        }

        // Step 2: Synthetic symbol filter - this strategy ONLY works on forex/metals/indices
        if(IsVolatilitySyntheticSymbolName(m_symbol) ||
           IsBoomCrashSyntheticSymbolName(m_symbol) ||
           IsJumpSyntheticSymbolName(m_symbol) ||
           IsStepSyntheticSymbolName(m_symbol))
        {
            SetDecisionReasonTag("ASIANRB_SYNTHETIC_SKIP");
            return TRADE_SIGNAL_NONE;
        }

        // Step 3: Time filter - only trade during London open window 07:00-07:30 UTC
        MqlDateTime dt;
        TimeToStruct(TimeGMT(), dt);
        if(dt.hour != 7 || dt.min > 30)
        {
            SetDecisionReasonTag("ASIANRB_OUTSIDE_LONDON_OPEN");
            return TRADE_SIGNAL_NONE;
        }

        // Step 4: Refresh for new bar
        RefreshForNewBar();

        // Step 5: Check components not NULL
        if(m_killZones == NULL || m_structureAnalyzer == NULL)
        {
            SetDecisionReasonTag("ASIANRB_COMPONENTS_NOT_READY");
            return TRADE_SIGNAL_NONE;
        }

        // Step 6: Measure Asian session range (00:00-06:00 UTC) on M5
        // 6 hours of M5 bars = 72 bars, starting from bar 1 (completed bars)
        int asianBars = 72;  // 6 hours * 12 bars/hour on M5
        int highestBar = iHighest(m_symbol, PERIOD_M5, MODE_HIGH, asianBars, 1);
        int lowestBar  = iLowest(m_symbol, PERIOD_M5, MODE_LOW, asianBars, 1);

        if(highestBar < 0 || lowestBar < 0)
        {
            SetDecisionReasonTag("ASIANRB_RANGE_DATA_UNAVAILABLE");
            return TRADE_SIGNAL_NONE;
        }

        double asianHigh = iHigh(m_symbol, PERIOD_M5, highestBar);
        double asianLow  = iLow(m_symbol, PERIOD_M5, lowestBar);

        if(asianHigh <= 0 || asianLow <= 0 || asianHigh <= asianLow)
        {
            SetDecisionReasonTag("ASIANRB_INVALID_RANGE");
            return TRADE_SIGNAL_NONE;
        }

        double asianRange = asianHigh - asianLow;

        // Step 7: Range filter - only trade if range < 0.8 * ATR(14) (tight range = more likely to break)
        double atr = m_structureAnalyzer.GetATR(14);
        if(atr <= 0)
        {
            SetDecisionReasonTag("ASIANRB_ATR_UNAVAILABLE");
            return TRADE_SIGNAL_NONE;
        }

        if(asianRange >= 0.8 * atr)
        {
            SetDecisionReasonTag("ASIANRB_RANGE_TOO_WIDE");
            return TRADE_SIGNAL_NONE;
        }

        // Step 8: Breakout confirmation
        double currentClose = iClose(m_symbol, m_timeframe, 0);
        if(currentClose <= 0)
        {
            SetDecisionReasonTag("ASIANRB_PRICE_UNAVAILABLE");
            return TRADE_SIGNAL_NONE;
        }

        bool bullishBreakout = (currentClose > asianHigh);
        bool bearishBreakout = (currentClose < asianLow);

        if(!bullishBreakout && !bearishBreakout)
        {
            SetDecisionReasonTag("ASIANRB_NO_BREAKOUT");
            return TRADE_SIGNAL_NONE;
        }

        // Step 9: Confidence calculation
        double score = 0.50;

        // Range compression boost: tighter range = stronger signal
        if(asianRange < 0.5 * atr)
            score += 0.10;

        // Structure alignment boost
        bool structureAligned = bullishBreakout ? m_structureAnalyzer.IsBullishStructure()
                                                : m_structureAnalyzer.IsBearishStructure();
        if(structureAligned)
            score += 0.08;

        // Fast CHOCH boost (recent structure shift confirms breakout direction)
        if(m_structureAnalyzer.DetectFastCHOCH())
            score += 0.07;

        confidence = MathMin(0.95, score);

        if(confidence < m_minConfidence)
        {
            SetDecisionReasonTag("ASIANRB_CONFIDENCE_BELOW_FLOOR");
            confidence = 0.0;
            return TRADE_SIGNAL_NONE;
        }

        // Step 10: Determine signal and SL/TP
        ENUM_TRADE_SIGNAL signal = bullishBreakout ? TRADE_SIGNAL_BUY : TRADE_SIGNAL_SELL;
        double currentPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);

        // SL at opposite range boundary, TP at 2x range size
        double slPrice = bullishBreakout ? asianLow : asianHigh;
        double slDistance = MathAbs(currentPrice - slPrice);
        double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
        double slPips = (point > 0 && slDistance > 0) ? (slDistance / point) : 0.0;
        double tpPips = (point > 0 && asianRange > 0) ? ((2.0 * asianRange) / point) : 0.0;

        if(slPips <= 0)
        {
            SetDecisionReasonTag("ASIANRB_INVALID_SL");
            return TRADE_SIGNAL_NONE;
        }

        // Step 11: CRITICAL - Validate through UnifiedRiskManager (AGENTS.md invariant #1)
        if(m_riskManager != NULL)
        {
            STradeValidationRequest request;
            request.symbol = m_symbol;
            request.orderType = bullishBreakout ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
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
                result = (*riskMgr).ValidateTradeRequest(request, "ASIANRB");
            if(!result.approved)
            {
                SetDecisionReasonTag("ASIANRB_RISK_REJECTED");
                PrintFormat("[ASIANRB] Risk rejected %s at %.5f Conf=%.1f%%",
                           signal == TRADE_SIGNAL_BUY ? "BUY" : "SELL",
                           currentPrice, confidence * 100);
                return TRADE_SIGNAL_NONE;
            }
            confidence *= result.confidenceMultiplier;
        }

        SetDecisionReasonTag(bullishBreakout ? "ASIANRB_SIGNAL_BUY" : "ASIANRB_SIGNAL_SELL");
        RecordSignal();

        // CONSENSUS LOGGING (AGENTS.md requirement)
        PrintFormat("[CONSENSUS-DIAG] %s | %s | Range: %.5f | ATR: %.5f | Conf: %.1f%% | Weight: %.2f | Reason: %s",
                   m_symbol,
                   signal == TRADE_SIGNAL_BUY ? "BUY" : "SELL",
                   asianRange,
                   atr,
                   confidence * 100,
                   m_weight,
                   m_lastDecisionReasonTag);

        PrintFormat("[ASIANRB] %s: %s | Asian Range: %.5f-%.5f | Range/ATR: %.2f | Structure: %s | Conf: %.1f%%",
                   m_symbol,
                   signal == TRADE_SIGNAL_BUY ? "BUY" : "SELL",
                   asianLow, asianHigh,
                   asianRange / atr,
                   structureAligned ? "Aligned" : "Neutral",
                   confidence * 100);

        return signal;
    }

    virtual string GetName() const override { return "Asian Range Break"; }
    virtual ENUM_STRATEGY_TYPE GetType() const override { return STRATEGY_ASIAN_RANGE_BREAK; }
};

#endif
