//+------------------------------------------------------------------+
//| SimpleMomentumStrategy.mqh                                       |
//| Basic momentum strategy using EMA crossover                      |
//| Simplified version: 4 indicators (fast/slow MA, ATR, RSI)       |
//+------------------------------------------------------------------+
#ifndef __SIMPLE_MOMENTUM_STRATEGY_MQH__
#define __SIMPLE_MOMENTUM_STRATEGY_MQH__

#include "../Core/Strategy/StrategyBase.mqh"
// Risk Manager for AGENTS.md invariant #1
#include "../Core/Risk/UnifiedRiskManager.mqh"

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
    int     m_macdHandle;         // MACD histogram confirmation (v2.0)
    int     m_adxHandle;          // ADX trend strength filter (v2.0)
    int     m_volumeHandle;       // Volume surge detection (v2.0)
    int     m_crossoverBar;       // Bar index of last crossover (for freshness)
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
    
    // Risk Management (AGENTS.md invariant #1)
    CUnifiedRiskManager* m_riskManager;
    int                  m_signalsGenerated;
    
    // Timeframe validation bounds for scalping mode
    ENUM_TIMEFRAMES m_minScalpTimeframe;  // Minimum allowed timeframe for scalping (default: M1)
    ENUM_TIMEFRAMES m_maxScalpTimeframe;  // Maximum allowed timeframe for scalping (default: M15)

    bool SafeCopyBuffer(int handle, int bufferIndex, int startPos, int count, double &buffer[])
    {
        for(int attempt = 0; attempt < 3; attempt++)
        {
            if(CopyBuffer(handle, bufferIndex, startPos, count, buffer) >= count)
                return true;
            Sleep(10);  // 10ms wait for indicator calculation
        }
        return false;
    }

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
        
        if(!SafeCopyBuffer(m_fastHandle, 0, 1, maxBars, fastBuffer) ||
           !SafeCopyBuffer(m_slowHandle, 0, 1, maxBars, slowBuffer))
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
    
    // ENHANCEMENT: RSI Divergence Detection (Batch 93 - Week 1)
    // Detects bearish/bullish divergence to filter false breakouts
    bool HasRSIDivergence(ENUM_TRADE_SIGNAL signal)
    {
        // Need at least 5 bars for divergence detection
        double priceBuffer[6], rsiBuffer[6];
        if(CopyClose(m_symbol, m_timeframe, 1, 6, priceBuffer) < 6 ||
           !SafeCopyBuffer(m_rsiHandle, 0, 1, 6, rsiBuffer))
            return false; // Skip on data error
        
        // Look for divergence over last 3-5 bars
        for(int lookback = 3; lookback <= 5; lookback++)
        {
            // Bullish Divergence: Price makes lower low, RSI makes higher low
            if(signal == TRADE_SIGNAL_BUY)
            {
                bool priceLowerLow = (priceBuffer[0] < priceBuffer[lookback]);
                bool rsiHigherLow = (rsiBuffer[0] > rsiBuffer[lookback]);
                
                if(priceLowerLow && rsiHigherLow)
                {
                    PrintFormat("[MOMENTUM-DIV] Bullish divergence detected | Price: %.5f -> %.5f | RSI: %.1f -> %.1f",
                               priceBuffer[lookback], priceBuffer[0], rsiBuffer[lookback], rsiBuffer[0]);
                    return true;
                }
            }
            
            // Bearish Divergence: Price makes higher high, RSI makes lower high
            if(signal == TRADE_SIGNAL_SELL)
            {
                bool priceHigherHigh = (priceBuffer[0] > priceBuffer[lookback]);
                bool rsiLowerHigh = (rsiBuffer[0] < rsiBuffer[lookback]);
                
                if(priceHigherHigh && rsiLowerHigh)
                {
                    PrintFormat("[MOMENTUM-DIV] Bearish divergence detected | Price: %.5f -> %.5f | RSI: %.1f -> %.1f",
                               priceBuffer[lookback], priceBuffer[0], rsiBuffer[lookback], rsiBuffer[0]);
                    return true;
                }
            }
        }
        
        return false;
    }

    // MACD Histogram Confirmation (v2.0)
    // Returns true if MACD histogram confirms the signal direction
    bool MACDConfirmed(ENUM_TRADE_SIGNAL signal)
    {
        if(m_macdHandle == INVALID_HANDLE)
            return true;  // No MACD = don't block

        double macdMain[2], macdSignal[2];
        if(!SafeCopyBuffer(m_macdHandle, 0, 1, 2, macdMain) ||
           !SafeCopyBuffer(m_macdHandle, 1, 1, 2, macdSignal))
            return true;  // Data unavailable = don't block

        double histNow = macdMain[0] - macdSignal[0];
        double histPrev = macdMain[1] - macdSignal[1];

        if(signal == TRADE_SIGNAL_BUY)
            return (histNow > 0 && histNow > histPrev);  // Rising positive histogram
        else
            return (histNow < 0 && histNow < histPrev);  // Falling negative histogram
    }

    // ADX Trend Strength Filter (v2.0)
    // Returns true if ADX indicates a trending market (ADX > 20)
    bool StrongTrend()
    {
        if(m_adxHandle == INVALID_HANDLE)
            return true;  // No ADX = don't block

        double adxBuffer[1];
        if(!SafeCopyBuffer(m_adxHandle, 0, 1, 1, adxBuffer))
            return true;

        return adxBuffer[0] > 20.0;
    }

    // Pullback Entry Detection (v2.0)
    // Crossover confirmed + price pulled back to EMA21 + rejection candle
    bool PullbackEntry(ENUM_TRADE_SIGNAL signal)
    {
        if(m_slowHandle == INVALID_HANDLE || m_atrHandle == INVALID_HANDLE)
            return false;

        // Get EMA21 value
        double ema21[1];
        if(!SafeCopyBuffer(m_slowHandle, 0, 1, 1, ema21))
            return false;

        double atr[1];
        if(!SafeCopyBuffer(m_atrHandle, 0, 1, 1, atr))
            return false;

        double low1 = iLow(m_symbol, m_timeframe, 1);
        double high1 = iHigh(m_symbol, m_timeframe, 1);
        double close1 = iClose(m_symbol, m_timeframe, 1);
        double open1 = iOpen(m_symbol, m_timeframe, 1);

        // Price near EMA21 (within 0.2 * ATR)
        bool atEMA21 = false;
        if(signal == TRADE_SIGNAL_BUY)
            atEMA21 = (MathAbs(low1 - ema21[0]) < atr[0] * 0.2);
        else
            atEMA21 = (MathAbs(high1 - ema21[0]) < atr[0] * 0.2);

        if(!atEMA21)
            return false;

        // Rejection candle: close near high for buy, near low for sell
        double bodySize = MathAbs(close1 - open1);
        double totalRange = high1 - low1;
        if(totalRange <= 0) return false;

        if(signal == TRADE_SIGNAL_BUY)
            return (close1 - low1) > 2.0 * (high1 - close1);  // Close near high
        else
            return (high1 - close1) > 2.0 * (close1 - low1);  // Close near low
    }

    // Momentum Freshness + Volume Surge Confidence (v2.0)
    // Returns confidence modifier based on crossover freshness and volume
    double GetMomentumFreshnessConfidence(ENUM_TRADE_SIGNAL signal)
    {
        double confidenceMod = 1.0;

        // Fresh crossover (< 3 bars since crossover) = +15%
        int currentBar = iBars(m_symbol, m_timeframe);
        if(m_crossoverBar > 0 && (currentBar - m_crossoverBar) < 3)
            confidenceMod *= 1.15;

        // Volume surge on crossover bar
        if(m_volumeHandle != INVALID_HANDLE)
        {
            double volBuffer[11];
            if(SafeCopyBuffer(m_volumeHandle, 0, 1, 11, volBuffer))
            {
                double currentVol = volBuffer[0];
                double avgVol = 0;
                for(int i = 1; i < 11; i++)
                    avgVol += volBuffer[i];
                avgVol /= 10.0;

                if(avgVol > 0 && currentVol > avgVol * 1.5)
                {
                    confidenceMod *= 1.10;  // Volume surge = +10%
                    PrintFormat("[MOMENTUM-ENHANCED] Volume surge | Vol=%.0f Avg=%.0f Ratio=%.2f",
                               currentVol, avgVol, currentVol / avgVol);
                }
            }
        }

        return confidenceMod;
    }

    bool CreateHandles()
    {
        m_fastHandle = CIndicatorManager::Instance().GetMAHandle(m_symbol, m_timeframe, m_fastPeriod, 0, MODE_EMA, PRICE_CLOSE);
        m_slowHandle = CIndicatorManager::Instance().GetMAHandle(m_symbol, m_timeframe, m_slowPeriod, 0, MODE_EMA, PRICE_CLOSE);
        m_atrHandle = CIndicatorManager::Instance().GetATRHandle(m_symbol, m_timeframe, 14);
        m_rsiHandle = CIndicatorManager::Instance().GetRSIHandle(m_symbol, m_timeframe, 14, PRICE_CLOSE);
        m_macdHandle = CIndicatorManager::Instance().GetMACDHandle(m_symbol, m_timeframe, 12, 26, 9, PRICE_CLOSE);
        m_adxHandle = CIndicatorManager::Instance().GetADXHandle(m_symbol, m_timeframe, 14);
        m_volumeHandle = CIndicatorManager::Instance().GetVolumesHandle(m_symbol, m_timeframe, VOLUME_TICK);

        if(m_fastHandle == INVALID_HANDLE || m_slowHandle == INVALID_HANDLE ||
           m_atrHandle == INVALID_HANDLE || m_rsiHandle == INVALID_HANDLE ||
           m_macdHandle == INVALID_HANDLE || m_adxHandle == INVALID_HANDLE ||
           m_volumeHandle == INVALID_HANDLE)
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
        if(!SafeCopyBuffer(m_fastHandle, 0, 1, 2, fastBuffer)) return false;
        if(!SafeCopyBuffer(m_slowHandle, 0, 1, 2, slowBuffer)) return false;

        fastNow = fastBuffer[0];
        fastPrev = fastBuffer[1];
        slowNow = slowBuffer[0];
        slowPrev = slowBuffer[1];
        return true;
    }

    // Fetch 3 bars of fast EMA for rate-of-change acceleration detection
    bool FetchFastEMA3(double &emaNow, double &emaPrev, double &emaPrev2)
    {
        double fastBuffer[3];

        // Closed-bar values: shift 1 (current signal), shift 2 (previous), shift 3 (2-bars-ago)
        if(!SafeCopyBuffer(m_fastHandle, 0, 1, 3, fastBuffer)) return false;

        emaNow = fastBuffer[0];
        emaPrev = fastBuffer[1];
        emaPrev2 = fastBuffer[2];
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
        m_macdHandle(INVALID_HANDLE),
        m_adxHandle(INVALID_HANDLE),
        m_volumeHandle(INVALID_HANDLE),
        m_crossoverBar(0),
        m_minConfirmationBars(1),  // Conservative: require 1 bar of confirmation
        m_minScalpTimeframe(PERIOD_M1),  // Minimum timeframe for scalping mode
        m_maxScalpTimeframe(PERIOD_M15),   // Maximum timeframe for scalping mode
        m_riskManager(NULL),
        m_signalsGenerated(0)
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
        m_macdHandle(INVALID_HANDLE),
        m_adxHandle(INVALID_HANDLE),
        m_volumeHandle(INVALID_HANDLE),
        m_crossoverBar(0),
        m_minConfirmationBars(MathMax(1, minConfirmationBars)),  // Hysteresis: min bars for crossover confirmation
        m_minScalpTimeframe(PERIOD_M1),  // Minimum timeframe for scalping mode
        m_maxScalpTimeframe(PERIOD_M15),   // Maximum timeframe for scalping mode
        m_signalsGenerated(0)
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

    virtual bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeMgr, void* posSizer, void* unifiedRiskMgr = NULL) override
    {
        if(m_fastPeriod >= m_slowPeriod)
            m_fastPeriod = MathMax(3, m_slowPeriod - 2);

        if(!SymbolSelect(symbol, true))
        {
            PrintFormat("[MOMENTUM-STRATEGY] Failed to select symbol %s", symbol);
            return false;
        }

        if(!CStrategyBase::Init(symbol, timeframe, tradeMgr, posSizer, unifiedRiskMgr))
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

        // ARCHITECTURAL FIX: Risk manager is now properly injected via Init() signature
        m_riskManager = GetUnifiedRiskManager();
        if(m_riskManager != NULL)
            Print("[MOMENTUM] UnifiedRiskManager successfully injected - trades will pass through validation gate");
        else
            Print("[MOMENTUM] WARNING: UnifiedRiskManager not provided - risk validation bypassed!");

        return CreateHandles();
    }

    virtual void Deinit() override
    {
        // Handles are managed by CIndicatorManager — no IndicatorRelease needed
        m_fastHandle = INVALID_HANDLE;
        m_slowHandle = INVALID_HANDLE;
        m_atrHandle = INVALID_HANDLE;
        m_rsiHandle = INVALID_HANDLE;
        m_macdHandle = INVALID_HANDLE;
        m_adxHandle = INVALID_HANDLE;
        m_volumeHandle = INVALID_HANDLE;
        // Risk manager is not owned by this strategy - do NOT delete
        m_riskManager = NULL;
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
        if(!SafeCopyBuffer(m_atrHandle, 0, 1, 2, atrWindow))
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
        if(!SafeCopyBuffer(m_rsiHandle, 0, 1, 1, rsiBuffer))
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

        // --- RATE-OF-CHANGE ACCELERATION DETECTION (Phase 3.4) ---
        // If crossover detected, check whether momentum is accelerating or decelerating
        double rocMultiplier = 1.0;
        if(signal != TRADE_SIGNAL_NONE)
        {
            double emaNow, emaPrev, emaPrev2;
            if(FetchFastEMA3(emaNow, emaPrev, emaPrev2))
            {
                // Calculate current ROC: (ema8_now - ema8_prev) / ema8_prev * 100
                // Calculate previous ROC: (ema8_prev - ema8_prev2) / ema8_prev2 * 100
                if(emaPrev != 0.0 && emaPrev2 != 0.0)
                {
                    double currentROC = (emaNow - emaPrev) / emaPrev * 100.0;
                    double previousROC = (emaPrev - emaPrev2) / emaPrev2 * 100.0;
                    double absCurrentROC = MathAbs(currentROC);
                    double absPreviousROC = MathAbs(previousROC);

                    // If |current ROC| > |previous ROC| * 1.2 → momentum is accelerating
                    if(absPreviousROC > 0.0 && absCurrentROC > absPreviousROC * 1.2)
                    {
                        rocMultiplier = 1.3;  // Accelerating → boost confidence
                        PrintFormat("[MOMENTUM-ROC] Accelerating | CurrROC=%.4f PrevROC=%.4f | Boost=1.3x",
                                   currentROC, previousROC);
                    }
                    else
                    {
                        rocMultiplier = 0.7;  // Not accelerating → reduce confidence
                        PrintFormat("[MOMENTUM-ROC] Decelerating | CurrROC=%.4f PrevROC=%.4f | Reduce=0.7x",
                                   currentROC, previousROC);
                    }
                }
            }
        }

        if(signal == TRADE_SIGNAL_NONE)
            return RejectSignal("MOMENTUM_NO_CROSSOVER");
        
        // ENHANCEMENT: RSI Divergence Filter (Batch 93 - Week 1)
        // Reject signals with bearish/bullish divergence (exhaustion warning)
        if(HasRSIDivergence(signal))
            return RejectSignal("MOMENTUM_DIVERGENCE_DETECTED");
            
        if(signal == TRADE_SIGNAL_BUY && rsi > 72.0)
            return RejectSignal("MOMENTUM_RSI_OVERBOUGHT");
        
        if(signal == TRADE_SIGNAL_SELL && rsi < 28.0)
            return RejectSignal("MOMENTUM_RSI_OVERSOLD");

        // === v2.0 ENHANCEMENTS ===

        // ADX Trend Strength Filter: require trending market for standard entries
        if(!StrongTrend())
        {
            // Weak trend: only allow pullback entries or very strong momentum
            if(!PullbackEntry(signal) && MathAbs(diffNow) < threshold * 2.0)
                return RejectSignal("MOMENTUM_ADX_WEAK_TREND");
        }

        // MACD Histogram Confirmation
        if(!MACDConfirmed(signal))
        {
            // MACD doesn't confirm: reduce confidence but don't block
            // (MACD is a confirmation filter, not a hard gate)
            PrintFormat("[MOMENTUM-ENHANCED] MACD not confirmed for %s | Confidence reduced",
                       signal == TRADE_SIGNAL_BUY ? "BUY" : "SELL");
        }

        // Track crossover bar for freshness calculation
        if(crossedUp || crossedDown)
            m_crossoverBar = iBars(m_symbol, m_timeframe);

        if(signal != TRADE_SIGNAL_NONE)
        {
            // Simplified confidence calculation
            double momentumConfidence = MathMin(1.0, MathAbs(diffNow) / (threshold * 2.5));
            
            // ENHANCEMENT: Volatility-Adjusted Confidence (Batch 93 - Week 1)
            // Reduce confidence during extreme volatility (uncertainty)
            double atrRatio = atrWindow[0] / m_minVolatility;
            if(atrRatio > 3.0) // Extreme volatility
            {
                momentumConfidence *= 0.6; // Reduce by 40%
                PrintFormat("[MOMENTUM-VOL] High volatility detected | ATR ratio=%.2f | Confidence reduced to %.1f%%",
                           atrRatio, momentumConfidence * 100);
            }
            else if(atrRatio > 2.0) // Elevated volatility
            {
                momentumConfidence *= 0.8; // Reduce by 20%
                PrintFormat("[MOMENTUM-VOL] Elevated volatility | ATR ratio=%.2f | Confidence adjusted to %.1f%%",
                           atrRatio, momentumConfidence * 100);
            }
            
            // ENHANCEMENT: ROC Acceleration Multiplier (Phase 3.4)
            // Boost confidence if momentum accelerating, reduce if decelerating
            momentumConfidence *= rocMultiplier;

            // v2.0: Momentum freshness + volume surge confidence modifier
            double freshnessMod = GetMomentumFreshnessConfidence(signal);
            momentumConfidence *= freshnessMod;

            // v2.0: MACD confirmation bonus/penalty
            if(MACDConfirmed(signal))
                momentumConfidence *= 1.10;  // MACD confirmed = +10%
            else
                momentumConfidence *= 0.85;  // MACD unconfirmed = -15%

            confidence = MathMin(1.0, MathMax(0.0, momentumConfidence));
            
            // Calculate ATR-based stop loss for risk validation
            double atrBuffer[2];
            double atr = 0.0;
            if(SafeCopyBuffer(m_atrHandle, 0, 1, 2, atrBuffer))
                atr = atrBuffer[0];
            double currentPrice = (signal == TRADE_SIGNAL_BUY) ? SymbolInfoDouble(m_symbol, SYMBOL_ASK) : SymbolInfoDouble(m_symbol, SYMBOL_BID);
            double slDistance = (atr > 0) ? (atr * 2.0) : (currentPrice * 0.01); // 2x ATR or 1% fallback
            double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
            double slPips = (point > 0) ? (slDistance / point) : 0;
            
            // CRITICAL: Validate through UnifiedRiskManager (AGENTS.md invariant #1)
            if(m_riskManager != NULL)
            {
                // Calculate lot size using position sizer with full normalization pipeline
                // (CalculateSize clamps to SYMBOL_VOLUME_MAX, applies margin checks, etc.)
                double calculatedLot = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
                if(m_positionSizer != NULL)
                {
                    SPositionSizingParams sizerParams = m_positionSizer.GetParameters();
                    ENUM_ORDER_TYPE orderType = (signal == TRADE_SIGNAL_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
                    calculatedLot = m_positionSizer.CalculateSize(m_symbol, orderType, slPips, sizerParams.riskPercent, confidence);
                    if(calculatedLot <= 0.0)
                        calculatedLot = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);  // Fallback to broker min
                }

                STradeValidationRequest request;
                request.symbol = m_symbol;
                request.orderType = (signal == TRADE_SIGNAL_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
                request.lotSize = calculatedLot;
                request.stopLossPips = slPips;
                request.takeProfitPips = slPips * 2.0; // 1:2 R:R ratio
                request.confidence = confidence;
                request.strategy = GetName();
                request.clusterCode = "";
                
                CUnifiedRiskManager* riskMgr = m_riskManager;
                SValidationResult result;
                ZeroMemory(result);
                if(riskMgr != NULL)
                    result = (*riskMgr).ValidateTradeRequest(request, "MOMENTUM");
                if(!result.approved)
                {
                    SetDecisionReasonTag("MOMENTUM_RISK_REJECTED");
                    PrintFormat("[MOMENTUM] Risk rejected %s Conf=%.1f%% Reason=%s",
                               signal == TRADE_SIGNAL_BUY ? "BUY" : "SELL",
                               confidence * 100,
                               result.message);
                    return TRADE_SIGNAL_NONE;
                }
                confidence *= result.confidenceMultiplier;
            }
            
            m_lastSignalBar = iTime(m_symbol, m_timeframe, 1);
            m_lastSignalTimestamp = TimeCurrent();
            m_signalsGenerated++;
            RecordSignal();
            SetDecisionReasonTag(signal == TRADE_SIGNAL_BUY ? "MOMENTUM_SIGNAL_BUY" : "MOMENTUM_SIGNAL_SELL");
            
            // CONSENSUS LOGGING (AGENTS.md requirement)
            PrintFormat("[CONSENSUS-DIAG] %s | %s | Cross: %.1f pts | RSI: %.1f | MACD: %s | ADX: %s | Conf: %.1f%% | Weight: %.2f | Reason: %s",
                       m_symbol,
                       signal == TRADE_SIGNAL_BUY ? "BUY" : "SELL",
                       diffNow / point,
                       rsi,
                       MACDConfirmed(signal) ? "YES" : "NO",
                       StrongTrend() ? "STRONG" : "WEAK",
                       confidence * 100,
                       m_weight,
                       m_lastDecisionReasonTag);
            
            PrintFormat("[MOMENTUM] %s: %s | Diff: %.1f pts | RSI: %.1f | Conf: %.1f%%",
                       m_symbol,
                       signal == TRADE_SIGNAL_BUY ? "BUY" : "SELL",
                       diffNow / point,
                       rsi,
                       confidence * 100);
        }

        return signal;
    }

    virtual ENUM_STRATEGY_TYPE GetType(void) const override
    {
        return STRATEGY_MOMENTUM;
    }

    //+------------------------------------------------------------------+
    //| Quick-probe signal: fast EMA crossover check (O(1) cached)       |
    //| Tier 1 fast-path for two-tier consensus evaluation.              |
    //| Uses already-cached indicator handles — no new handle creation,   |
    //| no full confidence pipeline, no risk validation.                  |
    //+------------------------------------------------------------------+
    virtual ENUM_TRADE_SIGNAL GetQuickProbeSignal() override
    {
        if(!m_is_enabled || !m_is_initialized)
            return TRADE_SIGNAL_NONE;

        // Handles must be valid (created during Init)
        if(m_fastHandle == INVALID_HANDLE || m_slowHandle == INVALID_HANDLE)
            return TRADE_SIGNAL_NONE;

        // Fetch 2 bars of fast/slow EMA (closed-bar, shift 1 and 2)
        double fastNow, fastPrev, slowNow, slowPrev;
        if(!FetchAverages(fastNow, fastPrev, slowNow, slowPrev))
            return TRADE_SIGNAL_NONE;

        double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
        if(point <= 0.0) point = 0.0001;

        double diffNow = fastNow - slowNow;
        double diffPrev = fastPrev - slowPrev;
        double threshold = m_thresholdPoints * point;

        // Quick crossover detection — no ATR, no RSI, no hysteresis, no risk gate
        if(diffNow > threshold && diffPrev <= threshold)
            return TRADE_SIGNAL_BUY;
        if(diffNow < -threshold && diffPrev >= -threshold)
            return TRADE_SIGNAL_SELL;

        return TRADE_SIGNAL_NONE;
    }
};

#endif // __SIMPLE_MOMENTUM_STRATEGY_MQH__

