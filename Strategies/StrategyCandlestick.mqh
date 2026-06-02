//+------------------------------------------------------------------+
//|                                         StrategyCandlestick.mqh  |
//|                                  Candlestick Pattern Strategy    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property strict

#include "../Interfaces/IStrategy.mqh"
#include "../Core/Visualization/ChartDrawingManager.mqh"
#include "../Core/Risk/UnifiedRiskManager.mqh"
#include "CandlestickFiles/CandleAnalyzer.mqh"
#include "CandlestickFiles/PinBarDetector.mqh"
#include "CandlestickFiles/EngulfingDetector.mqh"

class CStrategyCandlestick : public IStrategy
{
private:
    string            m_symbol;
    ENUM_TIMEFRAMES   m_timeframe;
    
    CCandleAnalyzer   m_analyzer;
    CPinBarDetector   m_pinBar;
    CEngulfingDetector m_engulfing;
    
    double            m_minConfidence;
    bool              m_requireTrendAlignment;
    bool              m_enabled;
    double            m_weight;
    datetime          m_lastSignalTime;
    int               m_totalSignals;
    int               m_successfulSignals;
    double            m_avgConfidence;
    string            m_lastDecisionReasonTag;
    CChartDrawingManager* m_drawingManager;
    CUnifiedRiskManager* m_riskManager;
    int               m_atrHandle;
    int               m_ema50Handle;
    int               m_ema200Handle;
    
public:
    CStrategyCandlestick(int magic = 0) : m_minConfidence(0.60), m_requireTrendAlignment(true), m_enabled(true), m_weight(1.5), m_lastSignalTime(0), m_totalSignals(0), m_successfulSignals(0), m_avgConfidence(0.0), m_lastDecisionReasonTag("CANDLE_UNSET"), m_drawingManager(NULL), m_riskManager(NULL), m_atrHandle(INVALID_HANDLE), m_ema50Handle(INVALID_HANDLE), m_ema200Handle(INVALID_HANDLE)
    {
        // Magic number not used in this strategy
    }
    ~CStrategyCandlestick() { if(m_drawingManager != NULL) { delete m_drawingManager; m_drawingManager = NULL; } }
    
    virtual bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeManagerPtr, void* positionSizerPtr, void* unifiedRiskManagerPtr = NULL) override
    {
        m_symbol = symbol;
        m_timeframe = timeframe;
        
        // Cast risk manager from void pointer (use dedicated parameter if provided, fallback to tradeManagerPtr for backward compatibility)
        if(unifiedRiskManagerPtr != NULL)
            m_riskManager = (CUnifiedRiskManager*)unifiedRiskManagerPtr;
        else
            m_riskManager = (CUnifiedRiskManager*)tradeManagerPtr;
        if(m_riskManager == NULL)
        {
            Print("[CANDLESTICK] WARNING: Risk manager not provided");
        }
        
        // Create ATR handle for pattern normalization
        m_atrHandle = iATR(m_symbol, m_timeframe, 14);
        if(m_atrHandle == INVALID_HANDLE)
        {
            Print("[CANDLESTICK] Failed to create ATR handle");
            m_lastDecisionReasonTag = "CANDLE_INIT_FAILED";
            return false;
        }
        
        // Create EMA handles for trend alignment (if enabled)
        if(m_requireTrendAlignment)
        {
            m_ema50Handle = iMA(m_symbol, m_timeframe, 50, 0, MODE_EMA, PRICE_CLOSE);
            m_ema200Handle = iMA(m_symbol, m_timeframe, 200, 0, MODE_EMA, PRICE_CLOSE);
            
            if(m_ema50Handle == INVALID_HANDLE || m_ema200Handle == INVALID_HANDLE)
            {
                Print("[CANDLESTICK] Failed to create EMA handles");
                IndicatorRelease(m_atrHandle);
                m_atrHandle = INVALID_HANDLE;
                m_lastDecisionReasonTag = "CANDLE_INIT_FAILED";
                return false;
            }
        }
        
        if(!m_analyzer.Initialize(symbol, timeframe))
        {
            m_lastDecisionReasonTag = "CANDLE_INIT_FAILED";
            Print("[CANDLESTICK] Failed to initialize candle analyzer");
            
            // Cleanup on failure
            IndicatorRelease(m_atrHandle);
            m_atrHandle = INVALID_HANDLE;
            if(m_ema50Handle != INVALID_HANDLE)
            {
                IndicatorRelease(m_ema50Handle);
                m_ema50Handle = INVALID_HANDLE;
            }
            if(m_ema200Handle != INVALID_HANDLE)
            {
                IndicatorRelease(m_ema200Handle);
                m_ema200Handle = INVALID_HANDLE;
            }
            return false;
        }
        
        m_pinBar.SetAnalyzer(&m_analyzer);
        m_engulfing.SetAnalyzer(&m_analyzer);
        
        m_drawingManager = new CChartDrawingManager();
        if(m_drawingManager != NULL)
        {
            m_drawingManager.Initialize(symbol, timeframe, "CANDLE");
            // Default config sufficient - signal markers enabled automatically
        }
        
        PrintFormat("[CANDLESTICK] Strategy initialized for %s on %s (ATR: %d, EMA50: %d, EMA200: %d)", 
                   symbol, EnumToString(timeframe), m_atrHandle, m_ema50Handle, m_ema200Handle);
        m_lastDecisionReasonTag = "CANDLE_INITIALIZED";
        return true;
    }
    
    virtual void Deinit() override
    {
        // Release indicator handles
        if(m_atrHandle != INVALID_HANDLE)
        {
            IndicatorRelease(m_atrHandle);
            m_atrHandle = INVALID_HANDLE;
        }
        if(m_ema50Handle != INVALID_HANDLE)
        {
            IndicatorRelease(m_ema50Handle);
            m_ema50Handle = INVALID_HANDLE;
        }
        if(m_ema200Handle != INVALID_HANDLE)
        {
            IndicatorRelease(m_ema200Handle);
            m_ema200Handle = INVALID_HANDLE;
        }
        
        // Cleanup drawing objects
        if(m_drawingManager != NULL)
            m_drawingManager.CleanupAll();
        
        m_lastDecisionReasonTag = "CANDLE_DEINIT";
    }
    
    virtual void OnNewBar() override
    {
        // Called when new bar forms on strategy's timeframe
    }
    
    virtual void OnNewBar(const string symbol, const ENUM_TIMEFRAMES timeframe) override
    {
        // Called when new bar forms on any timeframe
        if(m_drawingManager != NULL)
            m_drawingManager.CleanupOldObjects();
    }
    
    virtual ENUM_TRADE_SIGNAL GetSignal(double &confidence) override
    {
        confidence = 0.0;
        m_lastDecisionReasonTag = "CANDLE_UNSET";
        int barIndex = 1;

        if(!m_enabled)
        {
            m_lastDecisionReasonTag = "CANDLE_DISABLED";
            return TRADE_SIGNAL_NONE;
        }
        
        // Priority 1: Pin Bar (highest single-candle reliability)
        SPinBar pinBar;
        if(m_pinBar.DetectPinBar(barIndex, pinBar))
        {
            bool isBullishPin = (pinBar.type == PIN_BAR_BULLISH);
            if(ValidatePattern(pinBar.nosePrice, isBullishPin, barIndex))
            {
                confidence = pinBar.strength;
                DrawPatternSignal(pinBar.time, pinBar.nosePrice, pinBar.strength, pinBar.type == PIN_BAR_BULLISH, "Pin Bar");
                RecordPatternSignal(confidence);
                
                // Validate through UnifiedRiskManager before returning signal
                if(m_riskManager != NULL)
                {
                    double atr = GetATR(barIndex);
                    double sl = CalculateStopLoss(isBullishPin ? TRADE_SIGNAL_BUY : TRADE_SIGNAL_SELL, pinBar.nosePrice, atr);
                    double tp = CalculateTakeProfit(isBullishPin ? TRADE_SIGNAL_BUY : TRADE_SIGNAL_SELL, pinBar.nosePrice, sl);
                    
                    STradeValidationRequest request;
                    request.symbol = m_symbol;
                    request.orderType = (isBullishPin) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
                    request.lotSize = 0.01;
                    request.stopLossPips = (sl > 0) ? MathAbs(pinBar.nosePrice - sl) / SymbolInfoDouble(m_symbol, SYMBOL_POINT) : 0;
                    request.takeProfitPips = (tp > 0) ? MathAbs(tp - pinBar.nosePrice) / SymbolInfoDouble(m_symbol, SYMBOL_POINT) : 0;
                    request.confidence = confidence;
                    request.strategy = GetName();
                    request.clusterCode = "";
                    
                    CUnifiedRiskManager* riskMgr = m_riskManager;
                    SValidationResult result;
                    ZeroMemory(result);
                    if(riskMgr != NULL)
                        result = (*riskMgr).ValidateTradeRequest(request, "CANDLE");
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
                RecordPatternSignal(confidence);
                
                // Validate through UnifiedRiskManager before returning signal
                if(m_riskManager != NULL)
                {
                    double atr = GetATR(barIndex);
                    double sl = CalculateStopLoss(engulfing.isBullish ? TRADE_SIGNAL_BUY : TRADE_SIGNAL_SELL, engulfing.engulfingClose, atr);
                    double tp = CalculateTakeProfit(engulfing.isBullish ? TRADE_SIGNAL_BUY : TRADE_SIGNAL_SELL, engulfing.engulfingClose, sl);
                    
                    STradeValidationRequest request;
                    request.symbol = m_symbol;
                    request.orderType = (engulfing.isBullish) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
                    request.lotSize = 0.01;
                    request.stopLossPips = (sl > 0) ? MathAbs(engulfing.engulfingClose - sl) / SymbolInfoDouble(m_symbol, SYMBOL_POINT) : 0;
                    request.takeProfitPips = (tp > 0) ? MathAbs(tp - engulfing.engulfingClose) / SymbolInfoDouble(m_symbol, SYMBOL_POINT) : 0;
                    request.confidence = confidence;
                    request.strategy = GetName();
                    request.clusterCode = "";
                    
                    CUnifiedRiskManager* riskMgr = m_riskManager;
                    SValidationResult result;
                    ZeroMemory(result);
                    if(riskMgr != NULL)
                        result = (*riskMgr).ValidateTradeRequest(request, "CANDLE");
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
    
    virtual double CalculateStopLoss(ENUM_TRADE_SIGNAL signal, double entryPrice, double atr)
    {
        int barIndex = 1;
        
        // Use array-based CopyLow for efficiency instead of manual loop
        double prices[5];
        if(CopyLow(m_symbol, m_timeframe, 1, 5, prices) < 5)
            return (signal == TRADE_SIGNAL_BUY) ? entryPrice - (atr * 2.0) : entryPrice + (atr * 2.0);
        
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
            
            return sl;
        }
        else if(signal == TRADE_SIGNAL_SELL)
        {
            // Find swing high using ArrayMaximum
            double highPrices[5];
            if(CopyHigh(m_symbol, m_timeframe, 1, 5, highPrices) < 5)
                return entryPrice + (atr * 2.0);
            
            int maxIdx = ArrayMaximum(highPrices);
            double swingHigh = highPrices[maxIdx];
            
            double sl = swingHigh + (SymbolInfoDouble(m_symbol, SYMBOL_POINT) * 10);
            
            // Cap SL distance to 3x ATR
            if(sl - entryPrice > atr * 3.0)
                sl = entryPrice + (atr * 2.0);
            
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
    
    virtual string GetName() const override
    {
        return "Candlestick Patterns";
    }
    
    virtual bool IsEnabled() const override { return m_enabled; }
    virtual void SetEnabled(const bool enabled) override { m_enabled = enabled; }
    virtual double GetWeight() const override { return m_weight; }
    virtual void SetWeight(const double weight) override { m_weight = weight; }
    virtual bool ValidateParameters() override { return true; }
    virtual datetime GetLastSignalTime() const override { return m_lastSignalTime; }
    virtual void GetStatistics(int &signals, int &successful, double &accuracy) override
    {
        signals = m_totalSignals;
        successful = m_successfulSignals;
        accuracy = (m_totalSignals > 0) ? ((double)m_successfulSignals / (double)m_totalSignals) * 100.0 : 0.0;
    }
    virtual string GetLastDecisionReasonTag(void) const override { return m_lastDecisionReasonTag; }
    
    virtual ENUM_STRATEGY_TYPE GetType() const override
    {
        return STRATEGY_CANDLESTICK;
    }
    
    void SetMinConfidence(double conf) { m_minConfidence = conf; }
    void SetRequireTrendAlignment(bool req) { m_requireTrendAlignment = req; }
    
private:
    void RecordPatternSignal(const double signalConfidence)
    {
        m_totalSignals++;
        m_lastSignalTime = TimeCurrent();
        if(m_totalSignals == 1)
            m_avgConfidence = signalConfidence;
        else
            m_avgConfidence = ((m_avgConfidence * (m_totalSignals - 1)) + signalConfidence) / m_totalSignals;
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



