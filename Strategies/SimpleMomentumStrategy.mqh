//+------------------------------------------------------------------+
//| SimpleMomentumStrategy.mqh                                       |
//| Basic momentum strategy using EMA crossover                      |
//| Simplified version: 4 indicators (fast/slow MA, ATR, RSI)       |
//+------------------------------------------------------------------+
#ifndef __SIMPLE_MOMENTUM_STRATEGY_MQH__
#define __SIMPLE_MOMENTUM_STRATEGY_MQH__

#include "../Core/Strategy/StrategyBase.mqh"

//+------------------------------------------------------------------+
//| Momentum strategy for multi-instrument orchestration             |
//+------------------------------------------------------------------+
class CSimpleMomentumStrategy : public CStrategyBase
{
private:
    int     m_fastPeriod;
    int     m_slowPeriod;
    double  m_thresholdPoints;
    int     m_fastHandle;
    int     m_slowHandle;
    int     m_atrHandle;           // Volatility filter
    int     m_rsiHandle;          // RSI for momentum trap filter
    double  m_lastDiff;
    datetime m_lastSignalBar;      // Track last bar where signal was generated
    bool     m_enableScalping;     // Allow rapid signals
    int      m_scalpCooldownSeconds;
    double   m_minVolatility;      // Minimum volatility threshold
    double   m_atrThresholdMult;   // Dynamic threshold multiplier
    datetime m_lastSignalTimestamp;     // Track absolute time of last signal
    string   m_lastRejectReasonTag;
    datetime m_lastRejectLogTime;
    int      m_minConfirmationBars; // Minimum bars for crossover confirmation (hysteresis)
    
    // Timeframe validation bounds for scalping mode
    ENUM_TIMEFRAMES m_minScalpTimeframe;  // Minimum allowed timeframe for scalping (default: M1)
    ENUM_TIMEFRAMES m_maxScalpTimeframe;  // Maximum allowed timeframe for scalping (default: M15)

    void LogRejectEvent(const string reasonTag)
    {
        datetime nowTime = TimeCurrent();
        if(reasonTag == m_lastRejectReasonTag && (nowTime - m_lastRejectLogTime) <= 15)
            return;
        if((nowTime - m_lastRejectLogTime) < 5)
            return;

        PrintFormat("[MOMENTUM] Filtered: %s | Symbol=%s | TF=%s",
                    reasonTag, m_symbol, EnumToString(m_timeframe));
        m_lastRejectReasonTag = reasonTag;
        m_lastRejectLogTime = nowTime;
    }

    //+------------------------------------------------------------------+
    //| ValidateCrossoverWithHysteresis                                   |
    //| Purpose: Verify crossover persists for minimum bars to filter     |
    //|         false signals during volatile periods                     |
    //|                                                                  |
    //| Parameters:                                                      |
    //|   direction: +1 for bullish crossover, -1 for bearish crossover   |
    //|   threshold: Minimum gap between fast and slow MAs                |
    //|   minBars: Number of bars crossover must persist (hysteresis)    |
    //|                                                                  |
    //| Returns: true if crossover is confirmed, false if it's just noise |
    //+------------------------------------------------------------------+
    bool ValidateCrossoverWithHysteresis(const int direction, const double threshold, const int minBars)
    {
        // Need at least minBars + 1 bars of historical data (including current)
        int requiredBars = minBars + 1;
        int maxBars = MathMax(requiredBars, 5); // Fetch extra for safety
        
        double fastBuffer[];
        double slowBuffer[];
        
        if(CopyBuffer(m_fastHandle, 0, 1, maxBars, fastBuffer) < requiredBars ||
           CopyBuffer(m_slowHandle, 0, 1, maxBars, slowBuffer) < requiredBars)
        {
            PrintFormat("[MOMENTUM] Failed to fetch %d bars for crossover validation", maxBars);
            return false;
        }
        
        // direction: +1 = bullish (fast crosses above slow)
        // direction: -1 = bearish (fast crosses below slow)
        for(int i = 0; i < minBars; i++)
        {
            double diff = fastBuffer[i] - slowBuffer[i];
            
            if(direction > 0) // Bullish: fast must be above slow + threshold
            {
                if(diff <= threshold)
                {
                    PrintFormat("[MOMENTUM] Crossover validation FAILED at bar %d: diff=%.5f <= threshold=%.5f", 
                               i, diff, threshold);
                    return false;
                }
            }
            else // Bearish: fast must be below slow - threshold
            {
                if(diff >= -threshold)
                {
                    PrintFormat("[MOMENTUM] Crossover validation FAILED at bar %d: diff=%.5f >= -threshold=%.5f", 
                               i, diff, -threshold);
                    return false;
                }
            }
        }
        
        PrintFormat("[MOMENTUM] Crossover CONFIRMED for %d bars (direction=%s)", 
                   minBars, direction > 0 ? "BULLISH" : "BEARISH");
        return true;
    }

    ENUM_TRADE_SIGNAL RejectSignal(const string reasonTag)
    {
        SetDecisionReasonTag(reasonTag);
        LogRejectEvent(reasonTag);
        return TRADE_SIGNAL_NONE;
    }

    bool CreateHandles()
    {
        if(m_fastHandle != INVALID_HANDLE) IndicatorRelease(m_fastHandle);
        if(m_slowHandle != INVALID_HANDLE) IndicatorRelease(m_slowHandle);
        if(m_atrHandle != INVALID_HANDLE) IndicatorRelease(m_atrHandle);
        if(m_rsiHandle != INVALID_HANDLE) IndicatorRelease(m_rsiHandle);

        m_fastHandle = iMA(m_symbol, m_timeframe, m_fastPeriod, 0, MODE_EMA, PRICE_CLOSE);
        m_slowHandle = iMA(m_symbol, m_timeframe, m_slowPeriod, 0, MODE_EMA, PRICE_CLOSE);
        m_atrHandle = iATR(m_symbol, m_timeframe, 14); // Standard 14-period ATR
        m_rsiHandle = iRSI(m_symbol, m_timeframe, 14, PRICE_CLOSE);

        if(m_fastHandle == INVALID_HANDLE || m_slowHandle == INVALID_HANDLE || 
           m_atrHandle == INVALID_HANDLE || m_rsiHandle == INVALID_HANDLE)
        {
            PrintFormat("[MOMENTUM-STRATEGY] Failed to create indicator handles for %s", m_symbol);
            return false;
        }
        return true;
    }

    bool FetchAverages(double &fastNow, double &fastPrev, double &slowNow, double &slowPrev)
    {
        double fastBuffer[2];
        double slowBuffer[2];

        // Closed-bar values: current signal bar = shift 1, previous = shift 2
        if(CopyBuffer(m_fastHandle, 0, 1, 2, fastBuffer) < 2) return false;
        if(CopyBuffer(m_slowHandle, 0, 1, 2, slowBuffer) < 2) return false;

        fastNow = fastBuffer[0];
        fastPrev = fastBuffer[1];
        slowNow = slowBuffer[0];
        slowPrev = slowBuffer[1];
        return true;
    }

public:
    // Default constructor for Enterprise Manager
    CSimpleMomentumStrategy() :
        CStrategyBase("Momentum"),
        m_fastPeriod(8),
        m_slowPeriod(21),
        m_thresholdPoints(12.0),
        m_fastHandle(INVALID_HANDLE),
        m_slowHandle(INVALID_HANDLE),
        m_atrHandle(INVALID_HANDLE),
        m_lastDiff(0.0),
        m_lastSignalBar(0),
        m_lastSignalTimestamp(0),
        m_lastRejectReasonTag(""),
        m_lastRejectLogTime(0),
        m_enableScalping(false),
        m_scalpCooldownSeconds(20),
        m_minVolatility(0.0005),
        m_atrThresholdMult(0.20),
        m_rsiHandle(INVALID_HANDLE),
        m_minConfirmationBars(1),  // Conservative: require 1 bar of confirmation
        m_minScalpTimeframe(PERIOD_M1),  // Minimum timeframe for scalping mode
        m_maxScalpTimeframe(PERIOD_M15)   // Maximum timeframe for scalping mode
    {
    }

    CSimpleMomentumStrategy(const string name, const int fastPeriod = 8, const int slowPeriod = 21, const double thresholdPoints = 12.0, const int minConfirmationBars = 1) :
        CStrategyBase(name),
        m_fastPeriod(fastPeriod),
        m_slowPeriod(slowPeriod),
        m_thresholdPoints(MathMax(1.0, thresholdPoints)),
        m_fastHandle(INVALID_HANDLE),
        m_slowHandle(INVALID_HANDLE),
        m_atrHandle(INVALID_HANDLE),
        m_lastDiff(0.0),
        m_lastSignalBar(0),
        m_lastSignalTimestamp(0),
        m_lastRejectReasonTag(""),
        m_lastRejectLogTime(0),
        m_enableScalping(false),      // SCALPING MODE: Disabled by default
        m_scalpCooldownSeconds(20),
        m_minVolatility(0.0005),     // VOLATILITY FILTER: Minimum ATR value (adjusted by point)
        m_atrThresholdMult(0.20),     // ADAPTIVE FILTER: Crossover gap must exceed 20% of ATR
        m_rsiHandle(INVALID_HANDLE),
        m_minConfirmationBars(MathMax(1, minConfirmationBars)),  // Hysteresis: min bars for crossover confirmation
        m_minScalpTimeframe(PERIOD_M1),  // Minimum timeframe for scalping mode
        m_maxScalpTimeframe(PERIOD_M15)   // Maximum timeframe for scalping mode
    {
    }

    virtual ~CSimpleMomentumStrategy()
    {
        Deinit();
    }

    void SetScalpingMode(const bool enabled, const int cooldownSeconds = 20)
    {
        m_enableScalping = enabled;
        m_scalpCooldownSeconds = MathMax(5, cooldownSeconds);
    }

    //+------------------------------------------------------------------+
    //| SetMinimumConfirmationBars                                        |
    //| Configure minimum bars for crossover hysteresis validation         |
    //|                                                                  |
    //| bars = 1: Conservative - verify crossover holds for 1 bar        |
    //| bars = 2: Stricter - verify crossover holds for 2 bars (default)  |
    //| bars = 3: Very strict - verify crossover holds for 3 bars         |
    //+------------------------------------------------------------------+
    void SetMinimumConfirmationBars(const int bars)
    {
        m_minConfirmationBars = MathMax(1, MathMin(bars, 5)); // Clamp to 1-5 range
        PrintFormat("[MOMENTUM] Minimum confirmation bars set to %d", m_minConfirmationBars);
    }

    int GetMinimumConfirmationBars() const { return m_minConfirmationBars; }

    //+------------------------------------------------------------------+
    //| SetScalpTimeframeBounds                                           |
    //| Configure allowed timeframe range for scalping mode                 |
    //|                                                                  |
    //| minTf: Minimum timeframe (e.g., PERIOD_M1)                         |
    //| maxTf: Maximum timeframe (e.g., PERIOD_M15)                       |
    //|                                                                  |
    //| Note: Scalping mode requires M1-M15 timeframes for appropriate     |
    //|       signal timing. Non-scalping mode requires M5 or higher.      |
    //+------------------------------------------------------------------+
    void SetScalpTimeframeBounds(const ENUM_TIMEFRAMES minTf, const ENUM_TIMEFRAMES maxTf)
    {
        m_minScalpTimeframe = minTf;
        m_maxScalpTimeframe = maxTf;
        PrintFormat("[MOMENTUM] Scalp timeframe bounds set: %s to %s", 
                   EnumToString(m_minScalpTimeframe), EnumToString(m_maxScalpTimeframe));
    }

    ENUM_TIMEFRAMES GetMinScalpTimeframe() const { return m_minScalpTimeframe; }
    ENUM_TIMEFRAMES GetMaxScalpTimeframe() const { return m_maxScalpTimeframe; }

    //+------------------------------------------------------------------+
    //| ValidateTimeframeSuitability                                      |
    //| Check if current timeframe is appropriate for configured mode      |
    //|                                                                  |
    //| Returns: true if timeframe is suitable, false otherwise            |
    //+------------------------------------------------------------------+
    bool ValidateTimeframeSuitability()
    {
        // Scalping mode: requires M1-M15 timeframes
        if(m_enableScalping)
        {
            if(m_timeframe < m_minScalpTimeframe || m_timeframe > m_maxScalpTimeframe)
            {
                PrintFormat("[MOMENTUM-WARNING] Scalping mode on %s timeframe may produce inconsistent signals. ",
                           EnumToString(m_timeframe));
                PrintFormat("  Recommended: %s to %s for scalping.", 
                           EnumToString(m_minScalpTimeframe), EnumToString(m_maxScalpTimeframe));
                return false;
            }
        }
        // Non-scalping mode: requires M5 or higher for trend following
        else
        {
            if(m_timeframe < PERIOD_M5)
            {
                PrintFormat("[MOMENTUM-WARNING] Trend-following mode on %s timeframe may produce false signals. ",
                           EnumToString(m_timeframe));
                PrintFormat("  Recommended: %s or higher for trend-following strategies.", 
                           EnumToString(PERIOD_M5));
                return false;
            }
        }
        return true;
    }

    virtual bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeMgr, void* posSizer) override
    {
        if(m_fastPeriod >= m_slowPeriod)
            m_fastPeriod = MathMax(3, m_slowPeriod - 2);

        if(!SymbolSelect(symbol, true))
        {
            PrintFormat("[MOMENTUM-STRATEGY] Failed to select symbol %s", symbol);
            return false;
        }

        if(!CStrategyBase::Init(symbol, timeframe, tradeMgr, posSizer))
            return false;

        //+------------------------------------------------------------------+
        //| TIMEFRAME VALIDATION - Issue 2.1.2 Fix                           |
        //| Validate timeframe suitability for configured mode (scalping/    |
        //| trend-following) and log warnings for inappropriate settings    |
        //+------------------------------------------------------------------+
        ValidateTimeframeSuitability();

        // Adjust min volatility based on symbol digits
        if(SymbolInfoInteger(symbol, SYMBOL_DIGITS) <= 3) // JPY pairs or Indices
            m_minVolatility = 0.05; 
        else
            m_minVolatility = 0.0005;

        return CreateHandles();
    }

    virtual void Deinit() override
    {
        if(m_fastHandle != INVALID_HANDLE) { IndicatorRelease(m_fastHandle); m_fastHandle = INVALID_HANDLE; }
        if(m_slowHandle != INVALID_HANDLE) { IndicatorRelease(m_slowHandle); m_slowHandle = INVALID_HANDLE; }
        if(m_atrHandle != INVALID_HANDLE) { IndicatorRelease(m_atrHandle); m_atrHandle = INVALID_HANDLE; }
        if(m_rsiHandle != INVALID_HANDLE) { IndicatorRelease(m_rsiHandle); m_rsiHandle = INVALID_HANDLE; }
        CStrategyBase::Deinit();
    }

    virtual ENUM_TRADE_SIGNAL GetSignal(double &confidence) override
    {
        confidence = 0.0;
        SetDecisionReasonTag("MOMENTUM_UNSET");

        if(!IsEnabled() || !m_is_initialized)
            return RejectSignal("MOMENTUM_DISABLED_OR_UNINIT");
        
        // Ensure handles are valid
        if(m_fastHandle == INVALID_HANDLE || m_slowHandle == INVALID_HANDLE ||
           m_atrHandle == INVALID_HANDLE)
            return RejectSignal("MOMENTUM_INVALID_HANDLES");

        // Conservative mode waits one full bar; scalping mode uses a short wall-clock
        // cooldown while portfolio/risk caps still prevent uncontrolled stacking.
        int timeframeSeconds = MathMax(30, (int)PeriodSeconds(m_timeframe));
        int cooldownSeconds = timeframeSeconds;
        if(m_enableScalping)
            cooldownSeconds = MathMax(5, MathMin(m_scalpCooldownSeconds, timeframeSeconds));
        if(TimeCurrent() - m_lastSignalTimestamp < cooldownSeconds)
            return RejectSignal("MOMENTUM_COOLDOWN");

        if(!m_enableScalping)
        {
            // Conservative mode: Only one signal per bar
            datetime currentBar = iTime(m_symbol, m_timeframe, 1);
            if(currentBar == m_lastSignalBar)
                return RejectSignal("MOMENTUM_SAME_BAR_GUARD");
        }

        double fastNow, fastPrev, slowNow, slowPrev;
        if(!FetchAverages(fastNow, fastPrev, slowNow, slowPrev))
            return RejectSignal("MOMENTUM_MA_UNAVAILABLE");

        double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
        if(point <= 0.0) point = 0.0001;

        double diffNow = fastNow - slowNow;
        double diffPrev = fastPrev - slowPrev;
        // ADAPTIVE: Base threshold points vs current volatility
        double staticThreshold = m_thresholdPoints * point;

        // --- VOLATILITY FILTER ---
        double atrWindow[2];
        if(CopyBuffer(m_atrHandle, 0, 1, 2, atrWindow) < 2)
            return RejectSignal("MOMENTUM_ATR_UNAVAILABLE");
        if(atrWindow[0] < m_minVolatility) 
        {
            // Market too quiet
            return RejectSignal("MOMENTUM_LOW_VOLATILITY");
        }
        
        // Calculate dynamic threshold using ATR
        double atrThreshold = atrWindow[0] * m_atrThresholdMult;
        double threshold = MathMax(staticThreshold, atrThreshold);

        // --- EXHAUSTION FILTER (RSI) ---
        double rsiBuffer[1];
        if(CopyBuffer(m_rsiHandle, 0, 1, 1, rsiBuffer) < 1)
            return RejectSignal("MOMENTUM_RSI_UNAVAILABLE");
        double rsi = rsiBuffer[0];

        // Check for crossovers
        ENUM_TRADE_SIGNAL signal = TRADE_SIGNAL_NONE;
        bool crossedUp = (diffNow > threshold && diffPrev <= threshold);
        bool crossedDown = (diffNow < -threshold && diffPrev >= -threshold);
        
        //+------------------------------------------------------------------+
        //| CROSSOVER VALIDATION WITH HYSTERESIS                              |
        //| Issue 2.1.1 Fix: Verify crossover persists for min bars         |
        //| Purpose: Filter false signals during volatile periods              |
        //+------------------------------------------------------------------+
        if(crossedUp)
        {
            // Validate bullish crossover holds for minimum confirmation bars
            if(m_minConfirmationBars > 1)
            {
                if(!ValidateCrossoverWithHysteresis(+1, threshold, m_minConfirmationBars - 1))
                    return RejectSignal("MOMENTUM_HYSTERESIS_BULLISH_FAILED");
            }
            signal = TRADE_SIGNAL_BUY;
        }
        else if(crossedDown)
        {
            // Validate bearish crossover holds for minimum confirmation bars
            if(m_minConfirmationBars > 1)
            {
                if(!ValidateCrossoverWithHysteresis(-1, threshold, m_minConfirmationBars - 1))
                    return RejectSignal("MOMENTUM_HYSTERESIS_BEARISH_FAILED");
            }
            signal = TRADE_SIGNAL_SELL;
        }
        // SCALPING: Also signal if momentum is strong (not just crossover)
        else if(m_enableScalping)
        {
            if(diffNow > threshold * 1.5)
                signal = TRADE_SIGNAL_BUY;
            else if(diffNow < -threshold * 1.5)
                signal = TRADE_SIGNAL_SELL;
        }

        if(signal == TRADE_SIGNAL_NONE)
            return RejectSignal("MOMENTUM_NO_CROSSOVER");
            
        if(signal == TRADE_SIGNAL_BUY && rsi > 72.0)
            return RejectSignal("MOMENTUM_RSI_OVERBOUGHT");
        
        if(signal == TRADE_SIGNAL_SELL && rsi < 28.0)
            return RejectSignal("MOMENTUM_RSI_OVERSOLD");

        if(signal != TRADE_SIGNAL_NONE)
        {
            // Simplified confidence calculation
            double momentumConfidence = MathMin(1.0, MathAbs(diffNow) / (threshold * 2.5));
            confidence = MathMin(1.0, MathMax(0.0, momentumConfidence));
            
            m_lastSignalBar = iTime(m_symbol, m_timeframe, 1);
            m_lastSignalTimestamp = TimeCurrent();
            RecordSignal();
            SetDecisionReasonTag(signal == TRADE_SIGNAL_BUY ? "MOMENTUM_SIGNAL_BUY" : "MOMENTUM_SIGNAL_SELL");
        }

        return signal;
    }

    virtual ENUM_STRATEGY_TYPE GetType(void) const override
    {
        return STRATEGY_MOMENTUM;
    }
};

#endif // __SIMPLE_MOMENTUM_STRATEGY_MQH__
