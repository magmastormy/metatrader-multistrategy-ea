//+------------------------------------------------------------------+
//| Swing Trading Strategy Module                                   |
//| Uses MA(20), MA(50), and RSI(14)                                 |
//+------------------------------------------------------------------+

#ifndef __STRATEGY_SWING_MQH__
#define __STRATEGY_SWING_MQH__

#include "../Core/Strategy/StrategyBase.mqh"
#include "../Core/Trading/OrderInfo.mqh"
#include "../Core/Trading/HistoryOrderInfo.mqh"
#include "../Core/Trading/PositionInfo.mqh"
#include "../Core/Trading/DealInfo.mqh"
#include "../Core/Trading/Trade.mqh"
#include "../Core/Signals/SignalDiagnostics.mqh"
#include "../Core/Signals/TimeframeConsistency.mqh"



//+------------------------------------------------------------------+
//| Swing Trading Strategy Class                                    |
//+------------------------------------------------------------------+
class CStrategySwing : public CStrategyBase
{
private:
    int m_maFastPeriod;     // Fast MA period
    int m_maSlowPeriod;     // Slow MA period
    int m_rsiPeriod;        // RSI period
    double m_lastSignal;    // Last signal value
    double m_lastConfidence; // Last confidence value
    
    // Diagnostic systems
    CSignalDiagnostics* m_diagnostics;
    CTimeframeConsistency* m_tfConsistency;
    
    // Statistics
    int m_signalsGenerated;
    int m_crossoversDetected;
    
    // Swing point detection
    double m_lastSwingHigh;
    double m_lastSwingLow;
    int m_swingHighBar;
    int m_swingLowBar;

    int m_maFastHandle;
    int m_maSlowHandle;
    int m_rsiHandle;

    void CleanupIndicators()
    {
        if(m_maFastHandle != INVALID_HANDLE) { IndicatorRelease(m_maFastHandle); m_maFastHandle = INVALID_HANDLE; }
        if(m_maSlowHandle != INVALID_HANDLE) { IndicatorRelease(m_maSlowHandle); m_maSlowHandle = INVALID_HANDLE; }
        if(m_rsiHandle != INVALID_HANDLE) { IndicatorRelease(m_rsiHandle); m_rsiHandle = INVALID_HANDLE; }
    }

    bool UpdateIndicators(const string &symbol, const ENUM_TIMEFRAMES timeframe)
    {
        if(symbol == "" || timeframe == 0)
            return false;

        if(m_maFastHandle == INVALID_HANDLE)
            m_maFastHandle = iMA(symbol, timeframe, m_maFastPeriod, 0, MODE_EMA, PRICE_CLOSE);
        if(m_maSlowHandle == INVALID_HANDLE)
            m_maSlowHandle = iMA(symbol, timeframe, m_maSlowPeriod, 0, MODE_EMA, PRICE_CLOSE);
        if(m_rsiHandle == INVALID_HANDLE)
            m_rsiHandle = iRSI(symbol, timeframe, m_rsiPeriod, PRICE_CLOSE);

        return (m_maFastHandle != INVALID_HANDLE && m_maSlowHandle != INVALID_HANDLE && m_rsiHandle != INVALID_HANDLE);
    }
    
    // Helper method to calculate the signal
    int CalculateSignal(const string &symbol, const ENUM_TIMEFRAMES timeframe, double &outConfidence)
    {
        outConfidence = 0.0;
        
        // Initialize arrays
        double maFast[2], maSlow[2], rsi[1];
        // Note: ArraySetAsSeries cannot be used with static arrays

        if(!UpdateIndicators(symbol, timeframe))
        {
            Print("Failed to create indicator handles");
            return 0;
        }
        
        // Wait for indicators to initialize and copy MA values
        int attempts = 0;
        bool dataReady = false;
        while(attempts < 10 && !dataReady)
        {
            // 🛡�?BEAST MODE: Removed Sleep(100) - indicators initialize properly without delays
            if(CopyBuffer(m_maFastHandle, 0, 0, 2, maFast) == 2 &&
               CopyBuffer(m_maSlowHandle, 0, 0, 2, maSlow) == 2)
            {
                dataReady = true;
            }
            attempts++;
        }
        
        if(!dataReady)
        {
            if(m_diagnostics != NULL)
                m_diagnostics.LogStrategyError("Swing", "MA_BUFFER_FAILED", 
                                              StringFormat("Failed to copy MA buffer data after %d attempts for %s", attempts, symbol));
            return 0;
        }
        
        // Wait for RSI indicator to initialize
        attempts = 0;
        dataReady = false;
        while(attempts < 10 && !dataReady)
        {
            // 🛡�?BEAST MODE: Removed Sleep(100) - indicators initialize properly without delays
            if(CopyBuffer(m_rsiHandle, 0, 0, 1, rsi) == 1)
            {
                dataReady = true;
            }
            attempts++;
        }
        
        if(!dataReady)
        {
            if(m_diagnostics != NULL)
                m_diagnostics.LogStrategyError("Swing", "RSI_BUFFER_FAILED", 
                                              StringFormat("Failed to copy RSI buffer data after %d attempts for %s", attempts, symbol));
            return 0;
        }
        
        // Calculate signal based on MA crossover and RSI
        int signal = 0;
        double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
        
        if(point <= 0) // Prevent division by zero
            point = 0.00001;
            
        // Check for MA crossover and RSI confirmation
        bool bullishCross = maFast[0] > maSlow[0] && maFast[1] <= maSlow[1];
        bool bearishCross = maFast[0] < maSlow[0] && maFast[1] >= maSlow[1];
        
        if(bullishCross || bearishCross)
        {
            // Note: crossover detected but not incrementing counter in this const method
            if(m_diagnostics != NULL)
            {
                m_diagnostics.LogSMCDetection(
                    bullishCross ? "BULLISH_CROSS" : "BEARISH_CROSS",
                    m_symbol,
                    maFast[0],
                    maFast[0],
                    maSlow[0],
                    bullishCross,
                    60.0
                );
            }
        }
        
        if(maFast[0] > maSlow[0] && rsi[0] > 50)
        {
            signal = 1;  // Buy signal
            outConfidence = MathMin(1.0, (maFast[0] - maSlow[0]) / (point * 10)); // Normalize confidence
            
            // Enhance confidence with RSI strength
            double rsiStrength = (rsi[0] - 50) / 50.0;  // 0 to 1 for RSI 50-100
            outConfidence = (outConfidence + rsiStrength) / 2.0;
        }
        else if(maFast[0] < maSlow[0] && rsi[0] < 50)
        {
            signal = -1; // Sell signal
            outConfidence = MathMin(1.0, (maSlow[0] - maFast[0]) / (point * 10)); // Normalize confidence
            
            // Enhance confidence with RSI strength
            double rsiStrength = (50 - rsi[0]) / 50.0;  // 0 to 1 for RSI 0-50
            outConfidence = (outConfidence + rsiStrength) / 2.0;
        }
        
        return signal;
    }
    
public:
    CStrategySwing(const string name = "Swing Trading Strategy", int magic = 0) : 
        CStrategyBase(name, magic),
        m_maFastPeriod(20),
        m_maSlowPeriod(50),
        m_rsiPeriod(14),
        m_lastSignal(0),
        m_lastConfidence(0),
        m_diagnostics(NULL),
        m_tfConsistency(NULL),
        m_signalsGenerated(0),
        m_crossoversDetected(0),
        m_lastSwingHigh(0),
        m_lastSwingLow(0),
        m_swingHighBar(0),
        m_swingLowBar(0),
        m_maFastHandle(INVALID_HANDLE),
        m_maSlowHandle(INVALID_HANDLE),
        m_rsiHandle(INVALID_HANDLE)
    {
        // Initialize diagnostics
        m_diagnostics = new CSignalDiagnostics();
        if(m_diagnostics != NULL)
            m_diagnostics.Initialize(500, 3);
            
        // Initialize TF consistency
        m_tfConsistency = new CTimeframeConsistency();
        if(m_tfConsistency != NULL)
            m_tfConsistency.Initialize(CONFLICT_RES_WEIGHTED, 0.6, false);
    }
    
    virtual ~CStrategySwing()
    {
        Deinit();
        
        if(m_diagnostics != NULL)
        {
            delete m_diagnostics;
            m_diagnostics = NULL;
        }
        
        if(m_tfConsistency != NULL)
        {
            delete m_tfConsistency;
            m_tfConsistency = NULL;
        }
    }
    
    // IStrategy implementation
    virtual bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeMgr, void* posSizer) override
    {
        CleanupIndicators();
        if(!CStrategyBase::Init(symbol, timeframe, tradeMgr, posSizer)) return false;

        UpdateIndicators(m_symbol, m_timeframe);
        
        if(m_diagnostics != NULL)
        {
            string msg = StringFormat("Swing Strategy initialized for %s on %s", 
                                    symbol, EnumToString(timeframe));
            Print("[Swing] ", msg);
        }
        
        return true;
    }
    
    virtual void Deinit() override
    {
        Print("Deinitializing ", m_name);
        CleanupIndicators();
        CStrategyBase::Deinit();
    }
    
    virtual void OnTick() override {}
    virtual void OnNewBar(const string symbol, const ENUM_TIMEFRAMES timeframe) override
    {
        if(!IsEnabled() || !m_is_initialized || symbol == "" || timeframe == 0)
            return;
        if(symbol != m_symbol || timeframe != m_timeframe)
            return;

        UpdateIndicators(symbol, timeframe);

        double tmp[1];
        if(m_maFastHandle != INVALID_HANDLE) CopyBuffer(m_maFastHandle, 0, 0, 1, tmp);
        if(m_maSlowHandle != INVALID_HANDLE) CopyBuffer(m_maSlowHandle, 0, 0, 1, tmp);
        if(m_rsiHandle != INVALID_HANDLE) CopyBuffer(m_rsiHandle, 0, 0, 1, tmp);
    }
    
    virtual ENUM_TRADE_SIGNAL GetSignal(double &confidence) override
    {
        if(!IsEnabled()) {
            confidence = 0.0;
            if(m_diagnostics != NULL)
                m_diagnostics.LogNoSignal("Swing", m_symbol, m_timeframe, "Strategy disabled");
            return TRADE_SIGNAL_NONE;
        }
        
        double signalValue = GetSignalValue(m_symbol, m_timeframe, confidence);
        ENUM_TRADE_SIGNAL signal = TRADE_SIGNAL_NONE;
        
        if(signalValue > 0.5)
        {
            signal = TRADE_SIGNAL_BUY;
            m_signalsGenerated++;
            
            if(m_diagnostics != NULL)
            {
                string reason = StringFormat("MA crossover bullish | SignalStrength: %.2f | Confidence: %.2f",
                                           signalValue, confidence);
                m_diagnostics.LogSignalGeneration("Swing", m_symbol, m_timeframe, 
                                                signal, confidence, reason);
            }
        }
        else if(signalValue < -0.5)
        {
            signal = TRADE_SIGNAL_SELL;
            m_signalsGenerated++;
            
            if(m_diagnostics != NULL)
            {
                string reason = StringFormat("MA crossover bearish | SignalStrength: %.2f | Confidence: %.2f",
                                           signalValue, confidence);
                m_diagnostics.LogSignalGeneration("Swing", m_symbol, m_timeframe, 
                                                signal, confidence, reason);
            }
        }
        else
        {
            if(m_diagnostics != NULL)
                m_diagnostics.LogNoSignal("Swing", m_symbol, m_timeframe, "No crossover or RSI confirmation");
        }
        
        return signal;
    }
    
    virtual string GetName() const override { return m_name; }
    virtual ENUM_STRATEGY_TYPE GetType() const override { return STRATEGY_SWING; }
    
    // Helper for internal use
    double GetSignalValue(const string symbol, const ENUM_TIMEFRAMES timeframe, double &confidence)
    {
        confidence = 0.0;
        
        if(!IsEnabled())
            return 0.0;
            
        // Check if symbol is valid
        if(!SymbolSelect(symbol, true))
        {
            Print("Failed to select symbol: ", symbol);
            return 0.0;
        }
        
        int signal = CalculateSignal(symbol, timeframe, confidence);
        m_lastSignal = signal;
        m_lastConfidence = confidence;
        m_lastSignalTime = TimeCurrent();
        return (double)signal;
    }
    
    // Getters for strategy parameters
    int GetMaFastPeriod() const { return m_maFastPeriod; }
    int GetMaSlowPeriod() const { return m_maSlowPeriod; }
    int GetRsiPeriod() const { return m_rsiPeriod; }
    
    // Setters for strategy parameters
    void SetMaFastPeriod(int period) { m_maFastPeriod = period > 0 ? period : 20; }
    void SetMaSlowPeriod(int period) { m_maSlowPeriod = period > 0 ? period : 50; }
    void SetRsiPeriod(int period) { m_rsiPeriod = period > 0 ? period : 14; }
};

#endif //_STRATEGY_SWING_MQH_
