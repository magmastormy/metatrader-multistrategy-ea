//+------------------------------------------------------------------+
//| StrategyCandlestick.mqh                                          |
//| Candlestick Pattern Strategy - Multi-pattern detection and       |
//| confluence scoring for institutional-grade pattern trading        |
//+------------------------------------------------------------------+
#ifndef STRATEGY_CANDLESTICK_MQH
#define STRATEGY_CANDLESTICK_MQH

#property copyright "Copyright 2024"
#property strict

#include "../Core/Strategy/StrategyBase.mqh"
#include "../Core/Visualization/ChartDrawingManager.mqh"
#include "../Core/Risk/UnifiedRiskManager.mqh"
#include "CandlestickFiles/CandleAnalyzer.mqh"
#include "CandlestickFiles/PinBarDetector.mqh"
#include "CandlestickFiles/EngulfingDetector.mqh"
#include "CandlestickFiles/DojiDetector.mqh"
#include "CandlestickFiles/HammerDetector.mqh"
#include "CandlestickFiles/StarDetector.mqh"
#include "CandlestickFiles/HaramiDetector.mqh"
#include "CandlestickFiles/ThreeSoldiersDetector.mqh"
#include "CandlestickFiles/PiercingDetector.mqh"
#include "CandlestickFiles/CandleConfluenceScorer.mqh"

//+------------------------------------------------------------------+
//| Candle Pattern Types (v2.0 - 15 patterns)                       |
//+------------------------------------------------------------------+
enum ENUM_CANDLE_PATTERN
{
    PATTERN_NONE = 0,
    PATTERN_PINBAR_BULL,
    PATTERN_PINBAR_BEAR,
    PATTERN_ENGULFING_BULL,
    PATTERN_ENGULFING_BEAR,
    PATTERN_DOJI_STANDARD,
    PATTERN_DOJI_DRAGONFLY,
    PATTERN_DOJI_GRAVESTONE,
    PATTERN_HAMMER,
    PATTERN_INVERTED_HAMMER,
    PATTERN_SHOOTING_STAR,
    PATTERN_MORNING_STAR,
    PATTERN_EVENING_STAR,
    PATTERN_HARAMI_BULL,
    PATTERN_HARAMI_BEAR,
    PATTERN_THREE_WHITE_SOLDIERS,
    PATTERN_THREE_BLACK_CROWS,
    PATTERN_PIERCING_LINE,
    PATTERN_DARK_CLOUD
};

// CStrategyCandlestick implements multi-pattern candlestick detection with
// confluence scoring for institutional-grade pattern trading.
class CStrategyCandlestick : public CStrategyBase
{
private:
    CCandleAnalyzer   m_analyzer;
    CPinBarDetector   m_pinBar;
    CEngulfingDetector m_engulfing;
    CDojiDetector          m_doji;
    CHammerDetector        m_hammer;
    CStarDetector          m_star;
    CHaramiDetector        m_harami;
    CThreeSoldiersDetector m_threeSoldiers;
    CPiercingDetector      m_piercing;
    CCandleConfluenceScorer m_confluence;

    int               m_ema8Handle;
    int               m_ema21Handle;

    bool              m_requireTrendAlignment;
    CChartDrawingManager* m_drawingManager;
    bool              m_drawOnChartSymbolOnly;  // Only draw when strategy symbol matches chart symbol
    int               m_atrHandle;
    int               m_ema50Handle;
    int               m_ema200Handle;

public:
    CStrategyCandlestick(int magic = 0) : CStrategyBase("Candlestick Patterns", magic),
        m_requireTrendAlignment(true),
        m_drawingManager(NULL),
        m_drawOnChartSymbolOnly(true),
        m_atrHandle(INVALID_HANDLE),
        m_ema50Handle(INVALID_HANDLE),
        m_ema200Handle(INVALID_HANDLE),
        m_ema8Handle(INVALID_HANDLE),
        m_ema21Handle(INVALID_HANDLE),
        m_lastRejectReasonTag(""),
        m_lastRejectLogTime(0)
    {
        m_weight = 1.5;
        OverrideMinConfidence(0.60);
        m_lastDecisionReasonTag = "CANDLE_UNSET";
    }
    ~CStrategyCandlestick() { if(m_drawingManager != NULL) { delete m_drawingManager; m_drawingManager = NULL; } }

    virtual bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeManagerPtr, void* positionSizerPtr, void* unifiedRiskManagerPtr = NULL) override
    {
        // Call base class Init (handles symbol, timeframe, trade manager, position sizer, unified risk manager)
        if(!CStrategyBase::Init(symbol, timeframe, tradeManagerPtr, positionSizerPtr, unifiedRiskManagerPtr))
        {
            m_lastDecisionReasonTag = "CANDLE_INIT_FAILED";
            return false;
        }

        // Create ATR handle for pattern normalization via CIndicatorManager
        m_atrHandle = CIndicatorManager::Instance().GetATRHandle(m_symbol, m_timeframe, 14);
        if(m_atrHandle == INVALID_HANDLE)
        {
            Print("[CANDLESTICK] Failed to create ATR handle");
            m_lastDecisionReasonTag = "CANDLE_INIT_FAILED";
            return false;
        }

        // Create EMA handles for trend alignment (if enabled) via CIndicatorManager
        if(m_requireTrendAlignment)
        {
            m_ema50Handle = CIndicatorManager::Instance().GetMAHandle(m_symbol, m_timeframe, 50, 0, MODE_EMA, PRICE_CLOSE);
            m_ema200Handle = CIndicatorManager::Instance().GetMAHandle(m_symbol, m_timeframe, 200, 0, MODE_EMA, PRICE_CLOSE);

            if(m_ema50Handle == INVALID_HANDLE || m_ema200Handle == INVALID_HANDLE)
            {
                Print("[CANDLESTICK] Failed to create EMA handles");
                m_atrHandle = INVALID_HANDLE;
                m_lastDecisionReasonTag = "CANDLE_INIT_FAILED";
                return false;
            }
        }

        // Create EMA8/EMA21 for short-term trend alignment (confluence scoring)
        m_ema8Handle = CIndicatorManager::Instance().GetMAHandle(m_symbol, m_timeframe, 8, 0, MODE_EMA, PRICE_CLOSE);
        m_ema21Handle = CIndicatorManager::Instance().GetMAHandle(m_symbol, m_timeframe, 21, 0, MODE_EMA, PRICE_CLOSE);

        if(!m_analyzer.Initialize(m_symbol, m_timeframe))
        {
            m_lastDecisionReasonTag = "CANDLE_INIT_FAILED";
            Print("[CANDLESTICK] Failed to initialize candle analyzer");

            // Cleanup on failure — handles managed by CIndicatorManager
            m_atrHandle = INVALID_HANDLE;
            m_ema50Handle = INVALID_HANDLE;
            m_ema200Handle = INVALID_HANDLE;
            return false;
        }

        m_pinBar.SetAnalyzer(&m_analyzer);
        m_engulfing.SetAnalyzer(&m_analyzer);
        m_doji.SetAnalyzer(&m_analyzer);
        m_hammer.SetAnalyzer(&m_analyzer);
        m_star.SetAnalyzer(&m_analyzer);
        m_harami.SetAnalyzer(&m_analyzer);
        m_threeSoldiers.SetAnalyzer(&m_analyzer);
        m_piercing.SetAnalyzer(&m_analyzer);

        m_drawingManager = new CChartDrawingManager();
        if(m_drawingManager != NULL)
        {
            m_drawingManager.Initialize(m_symbol, m_timeframe, "CANDLE");
            // Default config sufficient - signal markers enabled automatically
        }

        PrintFormat("[CANDLESTICK] Strategy initialized for %s on %s (ATR: %d, EMA50: %d, EMA200: %d)",
                   m_symbol, EnumToString(m_timeframe), m_atrHandle, m_ema50Handle, m_ema200Handle);
        m_lastDecisionReasonTag = "CANDLE_INITIALIZED";
        return true;
    }

    virtual void Deinit() override
    {
        // Handles are managed by CIndicatorManager — no IndicatorRelease needed
        m_atrHandle = INVALID_HANDLE;
        m_ema50Handle = INVALID_HANDLE;
        m_ema200Handle = INVALID_HANDLE;
        m_ema8Handle = INVALID_HANDLE;
        m_ema21Handle = INVALID_HANDLE;

        // Cleanup drawing objects
        if(m_drawingManager != NULL)
            m_drawingManager.CleanupAll();

        // Call base class Deinit
        CStrategyBase::Deinit();

        m_lastDecisionReasonTag = "CANDLE_DEINIT";
    }

    virtual void OnNewBar(const string symbol, const ENUM_TIMEFRAMES timeframe) override
    {
        // Drawing cleanup for any symbol/timeframe
        if(m_drawingManager != NULL)
            m_drawingManager.CleanupOldObjects();
        // Call base for standard handling (checks match, calls HandleNewBar)
        CStrategyBase::OnNewBar(symbol, timeframe);
    }

    virtual double CalculateStopLoss(ENUM_TRADE_SIGNAL signal, double entryPrice, double atr)
    {
        // ATR availability guard: when ATR=0 (indicator not ready), use stops level as fallback
        if(atr <= 0.0)
        {
            double stopsLevel = (double)SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL);
            double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
            if(stopsLevel > 0 && point > 0)
                atr = stopsLevel * point * 3.0;  // 3x stops level as ATR proxy
            else
            {
                // No ATR and no stops level -- reject signal
                return 0.0;  // Will be caught by SL > 0 check downstream
            }
        }

        int barIndex = 1;

        // Use array-based CopyLow for efficiency instead of manual loop
        double prices[5];
        if(CopyLow(m_symbol, m_timeframe, 1, 5, prices) < 5)
        {
            double sl = (signal == TRADE_SIGNAL_BUY) ? entryPrice - (atr * 2.0) : entryPrice + (atr * 2.0);
            // Final validation: SL must be different from entry price
            if(signal == TRADE_SIGNAL_BUY && sl >= entryPrice)
                return 0.0;
            if(signal == TRADE_SIGNAL_SELL && sl <= entryPrice)
                return 0.0;
            return sl;
        }

        double slDistance = atr * 1.5;

        if(signal == TRADE_SIGNAL_BUY)
        {
            // Find swing low using ArrayMinimum
            int minIdx = ArrayMinimum(prices);
            double swingLow = prices[minIdx];

            double sl = swingLow - (SymbolInfoDouble(m_symbol, SYMBOL_POINT) * 10);

            // Cap SL distance to 3x ATR to prevent excessive risk
            if(entryPrice - sl > atr * 3.0)
                sl = entryPrice - (atr * 2.0);

            // Final validation: SL must be below entry price for BUY
            if(sl >= entryPrice)
                return 0.0;

            return sl;
        }
        else if(signal == TRADE_SIGNAL_SELL)
        {
            // Find swing high using ArrayMaximum
            double highPrices[5];
            if(CopyHigh(m_symbol, m_timeframe, 1, 5, highPrices) < 5)
            {
                double sl = entryPrice + (atr * 2.0);
                if(sl <= entryPrice)
                    return 0.0;
                return sl;
            }

            int maxIdx = ArrayMaximum(highPrices);
            double swingHigh = highPrices[maxIdx];

            double sl = swingHigh + (SymbolInfoDouble(m_symbol, SYMBOL_POINT) * 10);

            // Cap SL distance to 3x ATR
            if(sl - entryPrice > atr * 3.0)
                sl = entryPrice + (atr * 2.0);

            // Final validation: SL must be above entry price for SELL
            if(sl <= entryPrice)
                return 0.0;

            return sl;
        }

        return 0.0;
    }

    virtual double CalculateTakeProfit(ENUM_TRADE_SIGNAL signal, double entryPrice, double sl)
    {
        double slDistance = MathAbs(entryPrice - sl);
        double riskReward = 2.5;

        if(signal == TRADE_SIGNAL_BUY)
            return entryPrice + (slDistance * riskReward);
        else if(signal == TRADE_SIGNAL_SELL)
            return entryPrice - (slDistance * riskReward);

        return 0.0;
    }

    virtual ENUM_STRATEGY_TYPE GetType() const override
    {
        return STRATEGY_CANDLESTICK;
    }

    //+------------------------------------------------------------------+
    //| Quick-probe signal: fast pin bar / engulfing check (O(1) cached) |
    //| Tier 1 fast-path for two-tier consensus evaluation.              |
    //| Uses already-initialized analyzer — no new handle creation,       |
    //| no full validation pipeline, no risk gate, no drawing.           |
    //+------------------------------------------------------------------+
    virtual ENUM_TRADE_SIGNAL GetQuickProbeSignal() override
    {
        if(!m_is_enabled || !m_is_initialized)
            return TRADE_SIGNAL_NONE;

        int barIndex = 1;

        // Priority 1: Pin Bar — single-candle, O(1)
        SPinBar pinBar;
        if(m_pinBar.DetectPinBar(barIndex, pinBar) && pinBar.strength >= 0.60)
        {
            if(pinBar.type == PIN_BAR_BULLISH) return TRADE_SIGNAL_BUY;
            if(pinBar.type == PIN_BAR_BEARISH) return TRADE_SIGNAL_SELL;
        }

        // Priority 2: Engulfing — two-candle, O(1)
        SEngulfingPattern engulfing;
        if(m_engulfing.DetectEngulfing(barIndex, engulfing) && engulfing.strength >= 0.60)
        {
            if(engulfing.isBullish) return TRADE_SIGNAL_BUY;
            else return TRADE_SIGNAL_SELL;
        }

        // Priority 3: Hammer / Shooting Star
        SHammerPattern hammer;
        if(m_hammer.DetectHammer(barIndex, hammer) && hammer.strength >= 0.60)
        {
            if(hammer.isBullish) return TRADE_SIGNAL_BUY;
            else return TRADE_SIGNAL_SELL;
        }

        // Priority 4: Doji (Dragonfly/Gravestone only for probe)
        SDojiPattern doji;
        if(m_doji.DetectDoji(barIndex, doji) && doji.strength >= 0.65 && doji.type != DOJI_STANDARD)
        {
            if(doji.isBullish) return TRADE_SIGNAL_BUY;
            else return TRADE_SIGNAL_SELL;
        }

        return TRADE_SIGNAL_NONE;
    }

    void SetMinConfidence(double conf) { m_minConfidence = conf; }
    void SetRequireTrendAlignment(bool req) { m_requireTrendAlignment = req; }

protected:
    virtual ENUM_TRADE_SIGNAL ExecuteSignal(double &confidence) override
    {
        confidence = 0.0;
        m_lastDecisionReasonTag = "CANDLE_UNSET";
        int barIndex = 1;

        // Collect all detected patterns with their scores
        // Priority: 3-candle > 2-candle > 1-candle patterns

        // === 3-CANDLE PATTERNS (highest reliability) ===

        // Morning Star / Evening Star
        SStarPattern star;
        if(m_star.DetectStar(barIndex, star))
        {
            int score = BuildConfluenceScore(true, star.patternPrice, star.isBullish, barIndex);
            if(m_confluence.HasSignal())
            {
                confidence = star.strength * m_confluence.GetConfidence();
                DrawPatternSignal(star.time, star.patternPrice, confidence, star.isBullish,
                                  star.type == STAR_MORNING ? "Morning Star" : "Evening Star");
                PrintFormat("[CANDLE-PATTERN] %s | %s | Score=%d/100 | %s",
                           m_symbol, star.isBullish ? "Morning Star" : "Evening Star",
                           score, m_confluence.GetBreakdown());
                return ValidateAndReturnSignal(star.isBullish, star.patternPrice, confidence, barIndex,
                                               star.isBullish ? "CANDLE_MORNING_STAR" : "CANDLE_EVENING_STAR");
            }
        }

        // Three White Soldiers / Three Black Crows
        SThreeSoldiersPattern soldiers;
        if(m_threeSoldiers.DetectThreeSoldiers(barIndex, soldiers))
        {
            int score = BuildConfluenceScore(true, soldiers.patternPrice, soldiers.isBullish, barIndex);
            if(m_confluence.HasSignal())
            {
                confidence = soldiers.strength * m_confluence.GetConfidence();
                DrawPatternSignal(soldiers.time, soldiers.patternPrice, confidence, soldiers.isBullish,
                                  soldiers.isBullish ? "Three White Soldiers" : "Three Black Crows");
                PrintFormat("[CANDLE-PATTERN] %s | %s | Score=%d/100 | %s",
                           m_symbol, soldiers.isBullish ? "Three White Soldiers" : "Three Black Crows",
                           score, m_confluence.GetBreakdown());
                return ValidateAndReturnSignal(soldiers.isBullish, soldiers.patternPrice, confidence, barIndex,
                                               soldiers.isBullish ? "CANDLE_THREE_SOLDIERS" : "CANDLE_THREE_CROWS");
            }
        }

        // === 2-CANDLE PATTERNS ===

        // Engulfing (existing, enhanced with confluence)
        SEngulfingPattern engulfing;
        if(m_engulfing.DetectEngulfing(barIndex, engulfing))
        {
            int score = BuildConfluenceScore(true, engulfing.engulfingClose, engulfing.isBullish, barIndex);
            if(m_confluence.HasSignal())
            {
                confidence = engulfing.strength * m_confluence.GetConfidence();
                DrawPatternSignal(engulfing.time, engulfing.engulfingClose, confidence, engulfing.isBullish, "Engulfing");
                PrintFormat("[CANDLE-PATTERN] %s | Engulfing %s | Score=%d/100 | %s",
                           m_symbol, engulfing.isBullish ? "BULL" : "BEAR",
                           score, m_confluence.GetBreakdown());
                return ValidateAndReturnSignal(engulfing.isBullish, engulfing.engulfingClose, confidence, barIndex,
                                               engulfing.isBullish ? "CANDLE_ENGULFING_BUY" : "CANDLE_ENGULFING_SELL");
            }
            else
            {
                m_lastDecisionReasonTag = "CANDLE_ENGULFING_LOW_CONFLUENCE";
            }
        }

        // Harami
        SHaramiPattern harami;
        if(m_harami.DetectHarami(barIndex, harami))
        {
            int score = BuildConfluenceScore(true, harami.patternPrice, harami.isBullish, barIndex);
            if(m_confluence.HasSignal())
            {
                confidence = harami.strength * m_confluence.GetConfidence();
                DrawPatternSignal(harami.time, harami.patternPrice, confidence, harami.isBullish,
                                  harami.isBullish ? "Bullish Harami" : "Bearish Harami");
                PrintFormat("[CANDLE-PATTERN] %s | Harami %s | Score=%d/100 | %s",
                           m_symbol, harami.isBullish ? "BULL" : "BEAR",
                           score, m_confluence.GetBreakdown());
                return ValidateAndReturnSignal(harami.isBullish, harami.patternPrice, confidence, barIndex,
                                               harami.isBullish ? "CANDLE_HARAMI_BUY" : "CANDLE_HARAMI_SELL");
            }
        }

        // Piercing Line / Dark Cloud Cover
        SPiercingPattern piercing;
        if(m_piercing.DetectPiercing(barIndex, piercing))
        {
            int score = BuildConfluenceScore(true, piercing.patternPrice, piercing.isBullish, barIndex);
            if(m_confluence.HasSignal())
            {
                confidence = piercing.strength * m_confluence.GetConfidence();
                DrawPatternSignal(piercing.time, piercing.patternPrice, confidence, piercing.isBullish,
                                  piercing.isBullish ? "Piercing Line" : "Dark Cloud Cover");
                PrintFormat("[CANDLE-PATTERN] %s | %s | Score=%d/100 | %s",
                           m_symbol, piercing.isBullish ? "Piercing Line" : "Dark Cloud",
                           score, m_confluence.GetBreakdown());
                return ValidateAndReturnSignal(piercing.isBullish, piercing.patternPrice, confidence, barIndex,
                                               piercing.isBullish ? "CANDLE_PIERCING_BUY" : "CANDLE_DARK_CLOUD_SELL");
            }
        }

        // === 1-CANDLE PATTERNS ===

        // Pin Bar (existing, enhanced with confluence)
        SPinBar pinBar;
        if(m_pinBar.DetectPinBar(barIndex, pinBar))
        {
            bool isBullishPin = (pinBar.type == PIN_BAR_BULLISH);
            int score = BuildConfluenceScore(true, pinBar.nosePrice, isBullishPin, barIndex);
            if(m_confluence.HasSignal())
            {
                confidence = pinBar.strength * m_confluence.GetConfidence();
                DrawPatternSignal(pinBar.time, pinBar.nosePrice, confidence, isBullishPin, "Pin Bar");
                PrintFormat("[CANDLE-PATTERN] %s | Pin Bar %s | Score=%d/100 | %s",
                           m_symbol, isBullishPin ? "BULL" : "BEAR",
                           score, m_confluence.GetBreakdown());
                return ValidateAndReturnSignal(isBullishPin, pinBar.nosePrice, confidence, barIndex,
                                               isBullishPin ? "CANDLE_PINBAR_BUY" : "CANDLE_PINBAR_SELL");
            }
            else
            {
                m_lastDecisionReasonTag = "CANDLE_PINBAR_LOW_CONFLUENCE";
            }
        }

        // Hammer / Shooting Star
        SHammerPattern hammer;
        if(m_hammer.DetectHammer(barIndex, hammer))
        {
            int score = BuildConfluenceScore(true, hammer.patternPrice, hammer.isBullish, barIndex);
            if(m_confluence.HasSignal())
            {
                confidence = hammer.strength * m_confluence.GetConfidence();
                DrawPatternSignal(hammer.time, hammer.patternPrice, confidence, hammer.isBullish,
                                  hammer.type == HAMMER_SHOOTING_STAR ? "Shooting Star" : "Hammer");
                PrintFormat("[CANDLE-PATTERN] %s | %s | Score=%d/100 | %s",
                           m_symbol, hammer.type == HAMMER_SHOOTING_STAR ? "Shooting Star" : "Hammer",
                           score, m_confluence.GetBreakdown());
                return ValidateAndReturnSignal(hammer.isBullish, hammer.patternPrice, confidence, barIndex,
                                               hammer.isBullish ? "CANDLE_HAMMER_BUY" : "CANDLE_SHOOTING_STAR_SELL");
            }
        }

        // Doji
        SDojiPattern doji;
        if(m_doji.DetectDoji(barIndex, doji))
        {
            int score = BuildConfluenceScore(true, doji.patternPrice, doji.isBullish, barIndex);
            if(m_confluence.HasSignal())
            {
                confidence = doji.strength * m_confluence.GetConfidence();
                DrawPatternSignal(doji.time, doji.patternPrice, confidence, doji.isBullish,
                                  doji.type == DOJI_DRAGONFLY ? "Dragonfly Doji" :
                                  doji.type == DOJI_GRAVESTONE ? "Gravestone Doji" : "Doji");
                PrintFormat("[CANDLE-PATTERN] %s | %s | Score=%d/100 | %s",
                           m_symbol, EnumToString(doji.type),
                           score, m_confluence.GetBreakdown());
                return ValidateAndReturnSignal(doji.isBullish, doji.patternPrice, confidence, barIndex,
                                               doji.isBullish ? "CANDLE_DOJI_BUY" : "CANDLE_DOJI_SELL");
            }
        }

        if(m_lastDecisionReasonTag == "CANDLE_UNSET")
            m_lastDecisionReasonTag = "CANDLE_NO_PATTERN";

        return TRADE_SIGNAL_NONE;
    }

private:
    string            m_lastRejectReasonTag;
    datetime          m_lastRejectLogTime;

    void LogRejectEvent(const string reasonTag)
    {
        datetime nowTime = TimeCurrent();
        if(reasonTag == m_lastRejectReasonTag && (nowTime - m_lastRejectLogTime) <= 15)
            return;
        if((nowTime - m_lastRejectLogTime) < 5)
            return;

        PrintFormat("[CANDLESTICK] Filtered: %s | Symbol=%s | TF=%s",
                    reasonTag, m_symbol, EnumToString(m_timeframe));
        m_lastRejectReasonTag = reasonTag;
        m_lastRejectLogTime = nowTime;
    }

    ENUM_TRADE_SIGNAL RejectSignal(const string reasonTag)
    {
        SetDecisionReasonTag(reasonTag);
        LogRejectEvent(reasonTag);
        return TRADE_SIGNAL_NONE;
    }

    // Common validation + signal return for all pattern types
    ENUM_TRADE_SIGNAL ValidateAndReturnSignal(bool isBullish, double patternPrice, double &confidence, int barIndex, const string reasonTag)
    {
        // Validate SL
        double atr = GetATR(barIndex);
        double sl = CalculateStopLoss(isBullish ? TRADE_SIGNAL_BUY : TRADE_SIGNAL_SELL, patternPrice, atr);
        if(sl <= 0.0 || sl == patternPrice)
            return RejectSignal("CANDLE_SL_INVALID");

        // Validate through UnifiedRiskManager
        CUnifiedRiskManager* riskMgr = GetUnifiedRiskManager();
        if(riskMgr != NULL)
        {
            double tp = CalculateTakeProfit(isBullish ? TRADE_SIGNAL_BUY : TRADE_SIGNAL_SELL, patternPrice, sl);

            STradeValidationRequest request;
            request.symbol = m_symbol;
            request.orderType = isBullish ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
            request.lotSize = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
            request.stopLossPips = (sl > 0) ? MathAbs(patternPrice - sl) / SymbolInfoDouble(m_symbol, SYMBOL_POINT) : 0;
            request.takeProfitPips = (tp > 0) ? MathAbs(tp - patternPrice) / SymbolInfoDouble(m_symbol, SYMBOL_POINT) : 0;
            request.confidence = confidence;
            request.strategy = GetName();
            request.clusterCode = "";

            SValidationResult result;
            ZeroMemory(result);
            result = riskMgr.ValidateTradeRequest(request, "CANDLE");
            if(!result.approved)
            {
                m_lastDecisionReasonTag = "CANDLE_RISK_REJECTED";
                PrintFormat("[CANDLESTICK] Risk rejected %s at %.5f", reasonTag, patternPrice);
                return TRADE_SIGNAL_NONE;
            }
            confidence *= result.confidenceMultiplier;
        }

        // Log to consensus protocol
        PrintFormat("[CONSENSUS-DIAG] %s | %s | Pattern: %s | Conf: %.1f%% | Weight: %.2f | Confluence: %d | Reason: %s",
                   m_symbol,
                   isBullish ? "BUY" : "SELL",
                   reasonTag,
                   confidence * 100.0,
                   m_weight,
                   m_confluence.GetScore(),
                   reasonTag);

        m_lastDecisionReasonTag = reasonTag;
        return isBullish ? TRADE_SIGNAL_BUY : TRADE_SIGNAL_SELL;
    }

    // Helper method to get current ATR value
    double GetATR(int barIndex)
    {
        if(m_atrHandle == INVALID_HANDLE)
            return 0.0;

        double atrBuffer[1];
        if(CopyBuffer(m_atrHandle, 0, barIndex, 1, atrBuffer) > 0)
            return atrBuffer[0];

        return 0.0;
    }

    bool CheckTrendAlignment(bool isBullish, int barIndex) { if(m_ema50Handle == INVALID_HANDLE || m_ema200Handle == INVALID_HANDLE) return true; double ema50[1], ema200[1]; if(CopyBuffer(m_ema50Handle, 0, barIndex, 1, ema50) <= 0 || CopyBuffer(m_ema200Handle, 0, barIndex, 1, ema200) <= 0) return true; bool uptrend = (ema50[0] > ema200[0]); bool downtrend = (ema50[0] < ema200[0]); return isBullish ? uptrend : downtrend; }

    void DrawPatternSignal(datetime time, double price, double strength, bool isBullish, const string patternName)
    {
        if(m_drawingManager == NULL)
            return;
        if(m_drawOnChartSymbolOnly && m_symbol != _Symbol)
            return;

        m_drawingManager.DrawEntrySignal(time, price, isBullish, strength, "Candlestick", patternName);
    }

    // Check if pattern price is at a key level (S/R, EMA, FVG)
    bool IsAtKeyLevel(double patternPrice, int barIndex)
    {
        double atr = GetATR(barIndex);
        if(atr <= 0) return false;

        // Check EMA proximity (EMA21 and EMA50)
        if(m_ema21Handle != INVALID_HANDLE)
        {
            double ema21[1];
            if(CopyBuffer(m_ema21Handle, 0, barIndex, 1, ema21) > 0)
            {
                if(MathAbs(patternPrice - ema21[0]) < atr * 0.3)
                    return true;
            }
        }

        if(m_ema50Handle != INVALID_HANDLE)
        {
            double ema50[1];
            if(CopyBuffer(m_ema50Handle, 0, barIndex, 1, ema50) > 0)
            {
                if(MathAbs(patternPrice - ema50[0]) < atr * 0.3)
                    return true;
            }
        }

        // Check recent swing highs/lows as S/R proxy
        double highs[20], lows[20];
        if(CopyHigh(m_symbol, m_timeframe, 1, 20, highs) >= 20 &&
           CopyLow(m_symbol, m_timeframe, 1, 20, lows) >= 20)
        {
            for(int i = 0; i < 20; i++)
            {
                if(MathAbs(patternPrice - highs[i]) < atr * 0.3)
                    return true;
                if(MathAbs(patternPrice - lows[i]) < atr * 0.3)
                    return true;
            }
        }

        return false;
    }

    // Check short-term trend alignment (EMA8 vs EMA21)
    bool IsShortTermTrendAligned(bool isBullish, int barIndex)
    {
        if(m_ema8Handle == INVALID_HANDLE || m_ema21Handle == INVALID_HANDLE)
            return true;  // No data = don't block

        double ema8[1], ema21[1];
        if(CopyBuffer(m_ema8Handle, 0, barIndex, 1, ema8) <= 0 ||
           CopyBuffer(m_ema21Handle, 0, barIndex, 1, ema21) <= 0)
            return true;

        if(isBullish)
            return ema8[0] > ema21[0];  // Bullish pattern in uptrend
        else
            return ema8[0] < ema21[0];  // Bearish pattern in downtrend
    }

    // Build confluence score for a detected pattern
    int BuildConfluenceScore(bool patternValid, double patternPrice, bool isBullish, int barIndex)
    {
        m_confluence.Reset();
        m_confluence.AddValidPattern(patternValid);
        m_confluence.AddAtKeyLevel(IsAtKeyLevel(patternPrice, barIndex));
        m_confluence.AddTrendAligned(IsShortTermTrendAligned(isBullish, barIndex));
        return m_confluence.GetScore();
    }
};

#endif // STRATEGY_CANDLESTICK_MQH

