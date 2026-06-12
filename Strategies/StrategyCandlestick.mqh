//+------------------------------------------------------------------+
//|                                         StrategyCandlestick.mqh  |
//|                                  Candlestick Pattern Strategy    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property strict

#include "../Core/Strategy/StrategyBase.mqh"
#include "../Core/Visualization/ChartDrawingManager.mqh"
#include "../Core/Risk/UnifiedRiskManager.mqh"
#include "CandlestickFiles/CandleAnalyzer.mqh"
#include "CandlestickFiles/PinBarDetector.mqh"
#include "CandlestickFiles/EngulfingDetector.mqh"

class CStrategyCandlestick : public CStrategyBase
{
private:
    CCandleAnalyzer   m_analyzer;
    CPinBarDetector   m_pinBar;
    CEngulfingDetector m_engulfing;

    bool              m_requireTrendAlignment;
    CChartDrawingManager* m_drawingManager;
    int               m_atrHandle;
    int               m_ema50Handle;
    int               m_ema200Handle;

public:
    CStrategyCandlestick(int magic = 0) : CStrategyBase("Candlestick Patterns", magic),
        m_requireTrendAlignment(true),
        m_drawingManager(NULL),
        m_atrHandle(INVALID_HANDLE),
        m_ema50Handle(INVALID_HANDLE),
        m_ema200Handle(INVALID_HANDLE),
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
        if(m_pinBar.DetectPinBar(barIndex, pinBar))
        {
            // Quick strength filter: only return if pattern is strong enough
            if(pinBar.strength >= 0.60)
            {
                if(pinBar.type == PIN_BAR_BULLISH)
                    return TRADE_SIGNAL_BUY;
                if(pinBar.type == PIN_BAR_BEARISH)
                    return TRADE_SIGNAL_SELL;
            }
        }

        // Priority 2: Engulfing — two-candle, O(1)
        SEngulfingPattern engulfing;
        if(m_engulfing.DetectEngulfing(barIndex, engulfing))
        {
            if(engulfing.strength >= 0.60)
            {
                if(engulfing.isBullish)
                    return TRADE_SIGNAL_BUY;
                else
                    return TRADE_SIGNAL_SELL;
            }
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

        // Priority 1: Pin Bar (highest single-candle reliability)
        SPinBar pinBar;
        if(m_pinBar.DetectPinBar(barIndex, pinBar))
        {
            bool isBullishPin = (pinBar.type == PIN_BAR_BULLISH);
            if(ValidatePattern(pinBar.nosePrice, isBullishPin, barIndex))
            {
                confidence = pinBar.strength;
                DrawPatternSignal(pinBar.time, pinBar.nosePrice, pinBar.strength, pinBar.type == PIN_BAR_BULLISH, "Pin Bar");

                // Validate SL before proceeding (regardless of risk manager availability)
                double atr = GetATR(barIndex);
                double sl = CalculateStopLoss(isBullishPin ? TRADE_SIGNAL_BUY : TRADE_SIGNAL_SELL, pinBar.nosePrice, atr);
                if(sl <= 0.0 || sl == pinBar.nosePrice)
                    return RejectSignal("CANDLE_SL_INVALID");

                // Validate through UnifiedRiskManager before returning signal
                CUnifiedRiskManager* riskMgr = GetUnifiedRiskManager();
                if(riskMgr != NULL)
                {
                    double tp = CalculateTakeProfit(isBullishPin ? TRADE_SIGNAL_BUY : TRADE_SIGNAL_SELL, pinBar.nosePrice, sl);

                    STradeValidationRequest request;
                    request.symbol = m_symbol;
                    request.orderType = (isBullishPin) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
                    request.lotSize = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
                    request.stopLossPips = (sl > 0) ? MathAbs(pinBar.nosePrice - sl) / SymbolInfoDouble(m_symbol, SYMBOL_POINT) : 0;
                    request.takeProfitPips = (tp > 0) ? MathAbs(tp - pinBar.nosePrice) / SymbolInfoDouble(m_symbol, SYMBOL_POINT) : 0;
                    request.confidence = confidence;
                    request.strategy = GetName();
                    request.clusterCode = "";

                    SValidationResult result;
                    ZeroMemory(result);
                    result = riskMgr.ValidateTradeRequest(request, "CANDLE");
                    if(!result.approved)
                    {
                        m_lastDecisionReasonTag = "CANDLE_RISK_REJECTED";
                        PrintFormat("[CANDLESTICK] Risk rejected Pin Bar at %.5f", pinBar.nosePrice);
                        return TRADE_SIGNAL_NONE;
                    }
                    confidence *= result.confidenceMultiplier;
                }

                // Log to consensus protocol
                PrintFormat("[CONSENSUS-DIAG] %s | %s | Pattern: Pin Bar | Conf: %.1f%% | Weight: %.2f | Reason: %s",
                           m_symbol,
                           isBullishPin ? "BUY" : "SELL",
                           confidence * 100.0,
                           m_weight,
                           m_lastDecisionReasonTag);

                if(isBullishPin)
                {
                    m_lastDecisionReasonTag = "CANDLE_SIGNAL_BUY";
                    return TRADE_SIGNAL_BUY;
                }
                else if(pinBar.type == PIN_BAR_BEARISH)
                {
                    m_lastDecisionReasonTag = "CANDLE_SIGNAL_SELL";
                    return TRADE_SIGNAL_SELL;
                }
            }
            else
            {
                m_lastDecisionReasonTag = "CANDLE_PINBAR_FILTERED";
            }
        }

        // Priority 2: Engulfing (strong reversal)
        SEngulfingPattern engulfing;
        if(m_engulfing.DetectEngulfing(barIndex, engulfing))
        {
            if(ValidatePattern(engulfing.engulfingClose, engulfing.isBullish, barIndex))
            {
                confidence = engulfing.strength;
                DrawPatternSignal(engulfing.time, engulfing.engulfingClose, engulfing.strength, engulfing.isBullish, "Engulfing");

                // Validate SL before proceeding (regardless of risk manager availability)
                double atr = GetATR(barIndex);
                double sl = CalculateStopLoss(engulfing.isBullish ? TRADE_SIGNAL_BUY : TRADE_SIGNAL_SELL, engulfing.engulfingClose, atr);
                if(sl <= 0.0 || sl == engulfing.engulfingClose)
                    return RejectSignal("CANDLE_SL_INVALID");

                // Validate through UnifiedRiskManager before returning signal
                CUnifiedRiskManager* riskMgr = GetUnifiedRiskManager();
                if(riskMgr != NULL)
                {
                    double tp = CalculateTakeProfit(engulfing.isBullish ? TRADE_SIGNAL_BUY : TRADE_SIGNAL_SELL, engulfing.engulfingClose, sl);

                    STradeValidationRequest request;
                    request.symbol = m_symbol;
                    request.orderType = (engulfing.isBullish) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
                    request.lotSize = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
                    request.stopLossPips = (sl > 0) ? MathAbs(engulfing.engulfingClose - sl) / SymbolInfoDouble(m_symbol, SYMBOL_POINT) : 0;
                    request.takeProfitPips = (tp > 0) ? MathAbs(tp - engulfing.engulfingClose) / SymbolInfoDouble(m_symbol, SYMBOL_POINT) : 0;
                    request.confidence = confidence;
                    request.strategy = GetName();
                    request.clusterCode = "";

                    SValidationResult result;
                    ZeroMemory(result);
                    result = riskMgr.ValidateTradeRequest(request, "CANDLE");
                    if(!result.approved)
                    {
                        m_lastDecisionReasonTag = "CANDLE_RISK_REJECTED";
                        PrintFormat("[CANDLESTICK] Risk rejected Engulfing at %.5f", engulfing.engulfingClose);
                        return TRADE_SIGNAL_NONE;
                    }
                    confidence *= result.confidenceMultiplier;
                }

                // Log to consensus protocol
                PrintFormat("[CONSENSUS-DIAG] %s | %s | Pattern: Engulfing | Conf: %.1f%% | Weight: %.2f | Reason: %s",
                           m_symbol,
                           engulfing.isBullish ? "BUY" : "SELL",
                           confidence * 100.0,
                           m_weight,
                           m_lastDecisionReasonTag);

                m_lastDecisionReasonTag = engulfing.isBullish ? "CANDLE_SIGNAL_BUY" : "CANDLE_SIGNAL_SELL";
                return engulfing.isBullish ? TRADE_SIGNAL_BUY : TRADE_SIGNAL_SELL;
            }
            else
            {
                m_lastDecisionReasonTag = "CANDLE_ENGULFING_FILTERED";
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

    bool ValidatePattern(double patternPrice, bool isBullish, int barIndex)
    {
        // Pattern price parameter reserved for future validation

        // --- ATR NORMALIZATION CHECK ---
        // Ensures only substantial candles (≥80% of ATR) generate signals
        if(m_atrHandle != INVALID_HANDLE)
        {
            double atrBuffer[1];
            if(CopyBuffer(m_atrHandle, 0, barIndex, 1, atrBuffer) > 0)
            {
                double high = iHigh(m_symbol, m_timeframe, barIndex);
                double low = iLow(m_symbol, m_timeframe, barIndex);
                double candleSize = high - low;

                // Reject weak patterns that don't show conviction
                if(candleSize < atrBuffer[0] * 0.8)
                    return false;
            }
        }

        if(m_requireTrendAlignment)
        {
            if(!CheckTrendAlignment(isBullish, barIndex))
                return false;
        }

        return true;
    }

    bool CheckTrendAlignment(bool isBullish, int barIndex) { if(m_ema50Handle == INVALID_HANDLE || m_ema200Handle == INVALID_HANDLE) return true; double ema50[1], ema200[1]; if(CopyBuffer(m_ema50Handle, 0, barIndex, 1, ema50) <= 0 || CopyBuffer(m_ema200Handle, 0, barIndex, 1, ema200) <= 0) return true; bool uptrend = (ema50[0] > ema200[0]); bool downtrend = (ema50[0] < ema200[0]); return isBullish ? uptrend : downtrend; }

    void DrawPatternSignal(datetime time, double price, double strength, bool isBullish, const string patternName)
    {
        if(m_drawingManager == NULL)
            return;

        m_drawingManager.DrawEntrySignal(time, price, isBullish, strength, "Candlestick", patternName);
    }
};

