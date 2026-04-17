//+------------------------------------------------------------------+
//|                                         StrategyCandlestick.mqh  |
//|                                  Candlestick Pattern Strategy    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property strict

#include "../Interfaces/IStrategy.mqh"
#include "../Core/Visualization/ChartDrawingManager.mqh"
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
    int               m_atrHandle;
    int               m_ema50Handle;
    int               m_ema200Handle;
    
public:
    CStrategyCandlestick() : m_minConfidence(0.60), m_requireTrendAlignment(true), m_enabled(true), m_weight(1.5), m_lastSignalTime(0), m_totalSignals(0), m_successfulSignals(0), m_avgConfidence(0.0), m_lastDecisionReasonTag("CANDLE_UNSET"), m_drawingManager(NULL), m_atrHandle(INVALID_HANDLE), m_ema50Handle(INVALID_HANDLE), m_ema200Handle(INVALID_HANDLE) {}
    ~CStrategyCandlestick() { if(m_drawingManager != NULL) { delete m_drawingManager; m_drawingManager = NULL; } }
    
    virtual bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeManagerPtr, void* positionSizerPtr) override
    {
        m_symbol = symbol;
        m_timeframe = timeframe;
        
        if(!m_analyzer.Initialize(symbol, timeframe))
        {
            m_lastDecisionReasonTag = "CANDLE_INIT_FAILED";
            Print("[CANDLESTICK] Failed to initialize candle analyzer");
            return false;
        }
        
        m_pinBar.SetAnalyzer(&m_analyzer);
        m_engulfing.SetAnalyzer(&m_analyzer);
        
        m_drawingManager = new CChartDrawingManager();
        if(m_drawingManager != NULL)
        {
            m_drawingManager.Initialize(symbol, timeframe, "CANDLE");
            SDrawingConfig config = m_drawingManager.GetConfiguration();
            config.enableSupportResistance = false;
            config.enableStructure = false;
            config.enableOrderBlocks = false;
            config.enableSupplyDemand = false;
            config.enableFVG = false;
            config.enableSignalMarkers = true;
            config.enableTrendLines = false;
            m_drawingManager.SetConfiguration(config);
        }
        
        PrintFormat("[CANDLESTICK] Strategy initialized for %s on %s", symbol, EnumToString(timeframe));
        m_lastDecisionReasonTag = "CANDLE_INITIALIZED";
        return true;
    }
    
    virtual void Deinit() override
    {
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
        SCandleProperties candle = m_analyzer.AnalyzeCandle(barIndex);
        
        double slDistance = atr * 1.5;
        
        if(signal == TRADE_SIGNAL_BUY)
        {
            double swingLow = candle.low;
            for(int i = barIndex; i <= barIndex + 3; i++)
            {
                double low = iLow(m_symbol, m_timeframe, i);
                if(low < swingLow)
                    swingLow = low;
            }
            
            double sl = swingLow - (SymbolInfoDouble(m_symbol, SYMBOL_POINT) * 10);
            
            if(entryPrice - sl > atr * 3.0)
                sl = entryPrice - (atr * 2.0);
            
            return sl;
        }
        else if(signal == TRADE_SIGNAL_SELL)
        {
            double swingHigh = candle.high;
            for(int i = barIndex; i <= barIndex + 3; i++)
            {
                double high = iHigh(m_symbol, m_timeframe, i);
                if(high > swingHigh)
                    swingHigh = high;
            }
            
            double sl = swingHigh + (SymbolInfoDouble(m_symbol, SYMBOL_POINT) * 10);
            
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

    bool ValidatePattern(double patternPrice, bool isBullish, int barIndex)
    {
        patternPrice = patternPrice; // Reserved for future location-based validation

        // --- ATR NORMALIZATION CHECK ---
        if(m_atrHandle != INVALID_HANDLE)
        {
            double atrBuffer[1];
            if(CopyBuffer(m_atrHandle, 0, barIndex, 1, atrBuffer) > 0)
            {
                double high = iHigh(m_symbol, m_timeframe, barIndex);
                double low = iLow(m_symbol, m_timeframe, barIndex);
                double candleSize = high - low;
                
                // ATR Normalization: Candle must be substantial (at least 80% of current ATR)
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
        
        color textColor = isBullish ? clrLime : clrRed;
        string label = StringFormat("%s\nConf: %.0f%%", patternName, strength * 100.0);
        m_drawingManager.DrawTextLabel(time, price, label, textColor, 8, isBullish ? ANCHOR_LOWER : ANCHOR_UPPER);
    }
};

