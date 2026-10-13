// Momentum strategy: EMA crossover with ATR / RSI / MACD / ADX / volume filters.
#ifndef SIMPLE_MOMENTUM_STRATEGY_MQH
#define SIMPLE_MOMENTUM_STRATEGY_MQH

#include "../Core/Strategy/StrategyBase.mqh"
// Pre-trade gating: ValidateWithRiskManager() delegates to CUnifiedRiskManager. It returns true when
// none was injected, but registration refuses such a strategy (StrategyRegistryState.mqh:122).
#include "../Utilities/SafeCopyBuffer.mqh"
#include "../Core/Risk/UnifiedRiskManager.mqh"

class CSimpleMomentumStrategy : public CStrategyBase
{
private:
    int     m_fastPeriod;
    int     m_slowPeriod;
    double  m_thresholdPoints;
    int     m_fastHandle;
    int     m_slowHandle;
    int     m_atrHandle;           // volatility filter
    int     m_rsiHandle;          // exhaustion filter
    int     m_macdHandle;         // histogram confirmation - soft, never a hard gate
    int     m_adxHandle;          // trend strength gate
    int     m_volumeHandle;       // volume surge
    int     m_crossoverBar;       // bar index of the last crossover; feeds freshness/staleness
    double  m_lastDiff;
    datetime m_lastSignalBar;      // shift-1 time of the last signal
    int      m_signalsGenerated;
    bool     m_enableScalping;     // rapid re-signalling; bypasses the one-signal-per-bar guard
    int      m_scalpCooldownSeconds;
    double   m_minVolatility;      // absolute ATR floor; re-scaled by symbol digits in Init
    double   m_atrThresholdMult;   // crossover gap must exceed this fraction of ATR
    datetime m_lastSignalTimestamp;     // wall-clock anchor for the cooldown

    int      m_minConfirmationBars; // hysteresis: bars the crossover must hold

    double   m_rsiOverbought;      // overbought rejection level
    double   m_rsiOversold;        // oversold rejection level
    double   m_adxThreshold;       // minimum ADX counted as "trending"

    ENUM_TIMEFRAMES m_minScalpTimeframe;  // scalping is only valid inside these bounds
    ENUM_TIMEFRAMES m_maxScalpTimeframe;  // outside them ValidateTimeframeSuitability warns

// Hysteresis gate: the crossover must hold for minBars closed bars or it is noise.
// direction +1 = fast above slow, -1 = fast below; threshold is the minimum MA gap.
    bool ValidateCrossoverWithHysteresis(const int direction, const double threshold, const int minBars)
    {
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
        
        // Non-series copies land OLDEST-first: the cross bar is maxBars-1, older bars walk
        // backwards. Indexing up from 0 reads pre-cross bars and rejects every valid cross.
        for(int k = 0; k < minBars; k++)
        {
            int idx = maxBars - 1 - k;
            double diff = fastBuffer[idx] - slowBuffer[idx];

            if(direction > 0) // Bullish: fast must be above slow + threshold
            {
                if(diff <= threshold)
                {
                    PrintFormat("[MOMENTUM] Crossover validation FAILED at bar %d: diff=%.5f <= threshold=%.5f",
                               k, diff, threshold);
                    return false;
                }
            }
            else // Bearish: fast must be below slow - threshold
            {
                if(diff >= -threshold)
                {
                    PrintFormat("[MOMENTUM] Crossover validation FAILED at bar %d: diff=%.5f >= -threshold=%.5f",
                               k, diff, -threshold);
                    return false;
                }
            }
        }
        
        PrintFormat("[MOMENTUM] Crossover CONFIRMED for %d bars (direction=%s)", 
                   minBars, direction > 0 ? "BULLISH" : "BEARISH");
        return true;
    }

    // Price/RSI divergence is an exhaustion warning: it vetoes the entry.
    bool HasRSIDivergence(ENUM_TRADE_SIGNAL signal)
    {
        double priceBuffer[6], rsiBuffer[6];
        if(CopyClose(m_symbol, m_timeframe, 1, 6, priceBuffer) < 6 ||
           !SafeCopyBuffer(m_rsiHandle, 0, 1, 6, rsiBuffer))
            return false; // fail closed: needs 6 closed bars; short history gives no veto
        
        // Non-series copies land OLDEST-first: index 5 is the newest closed bar, so price
        // must make the fresh extreme at [5] against [5 - lookback], RSI the opposite.
        for(int lookback = 3; lookback <= 5; lookback++)
        {
            if(signal == TRADE_SIGNAL_BUY)
            {
                bool priceLowerLow = (priceBuffer[5] < priceBuffer[5 - lookback]);
                bool rsiHigherLow = (rsiBuffer[5] > rsiBuffer[5 - lookback]);

                if(priceLowerLow && rsiHigherLow)
                {
                    PrintFormat("[MOMENTUM-DIV] Bullish divergence detected | Price: %.5f -> %.5f | RSI: %.1f -> %.1f",
                               priceBuffer[5 - lookback], priceBuffer[5], rsiBuffer[5 - lookback], rsiBuffer[5]);
                    return true;
                }
            }

            if(signal == TRADE_SIGNAL_SELL)
            {
                bool priceHigherHigh = (priceBuffer[5] > priceBuffer[5 - lookback]);
                bool rsiLowerHigh = (rsiBuffer[5] < rsiBuffer[5 - lookback]);

                if(priceHigherHigh && rsiLowerHigh)
                {
                    PrintFormat("[MOMENTUM-DIV] Bearish divergence detected | Price: %.5f -> %.5f | RSI: %.1f -> %.1f",
                               priceBuffer[5 - lookback], priceBuffer[5], rsiBuffer[5 - lookback], rsiBuffer[5]);
                    return true;
                }
            }
        }
        
        return false;
    }

    bool MACDConfirmed(ENUM_TRADE_SIGNAL signal)
    {
        // Fail closed: an unavailable filter is not a passing filter.
        if(m_macdHandle == INVALID_HANDLE)
            return false;

        double macdMain[2], macdSignal[2];
        if(!SafeCopyBuffer(m_macdHandle, 0, 1, 2, macdMain) ||
           !SafeCopyBuffer(m_macdHandle, 1, 1, 2, macdSignal))
            return false;

        // Oldest-first: [1] newest closed bar, [0] the bar before; swapped, this "confirms" BUY on a falling histogram.
        double histNow = macdMain[1] - macdSignal[1];
        double histPrev = macdMain[0] - macdSignal[0];

        if(signal == TRADE_SIGNAL_BUY)
            return (histNow > 0 && histNow > histPrev);
        else
            return (histNow < 0 && histNow < histPrev);
    }

    bool StrongTrend()
    {
        // Fail closed: missing ADX must never read as "trend confirmed".
        if(m_adxHandle == INVALID_HANDLE)
            return false;

        double adxBuffer[1];
        if(!SafeCopyBuffer(m_adxHandle, 0, 1, 1, adxBuffer))
            return false;

        return adxBuffer[0] > m_adxThreshold;
    }

    // Pullback entry: price touched the slow EMA, then a rejection candle closed back off it.
    bool PullbackEntry(ENUM_TRADE_SIGNAL signal)
    {
        if(m_slowHandle == INVALID_HANDLE || m_atrHandle == INVALID_HANDLE)
            return false;

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

        // "Near" means within 0.2 * ATR of the slow EMA, measured from the bar extreme
        bool atEMA21 = false;
        if(signal == TRADE_SIGNAL_BUY)
            atEMA21 = (MathAbs(low1 - ema21[0]) < atr[0] * 0.2);
        else
            atEMA21 = (MathAbs(high1 - ema21[0]) < atr[0] * 0.2);

        if(!atEMA21)
            return false;

        // Rejection candle: buy needs a lower wick twice the upper one; sell mirrors it.
        double bodySize = MathAbs(close1 - open1);
        double totalRange = high1 - low1;
        if(totalRange <= 0) return false;

        if(signal == TRADE_SIGNAL_BUY)
            return (close1 - low1) > 2.0 * (high1 - close1);
        else
            return (high1 - close1) > 2.0 * (close1 - low1);
    }

    double GetMomentumFreshnessConfidence(ENUM_TRADE_SIGNAL signal)
    {
        double confidenceMod = 1.0;

        int currentBar = iBars(m_symbol, m_timeframe);
        if(m_crossoverBar > 0 && (currentBar - m_crossoverBar) < 3)
            confidenceMod *= 1.15;

        // Stale crossover (> 3 bars) halves confidence instead of blocking the signal.
        if(m_crossoverBar > 0 && (currentBar - m_crossoverBar) > 3)
            confidenceMod *= 0.5;

        if(m_volumeHandle != INVALID_HANDLE)
        {
            double volBuffer[11];
            if(SafeCopyBuffer(m_volumeHandle, 0, 1, 11, volBuffer))
            {
                // Oldest-first: [10] is the newest closed bar, [0] is shift-11.
                double currentVol = volBuffer[10];
                double avgVol = 0;
                for(int i = 0; i < 10; i++)
                    avgVol += volBuffer[i];
                avgVol /= 10.0;

                if(avgVol > 0 && currentVol > avgVol * 1.5)
                {
                    confidenceMod *= 1.10;
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

// EMA recomputed from raw closes when the MA handle copy fails, preventing MOMENTUM_MA_UNAVAILABLE
// on a handle outage. SMA-seeded, period*3 warmup bars, outputs shift 1 and shift 2 - never shift 0.
    bool CalculateEmaFallback(const int period, double &emaNow, double &emaPrev)
    {
        if(period <= 0)
            return false;

        int requiredBars = period * 3;
        MqlRates rates[];
        ArraySetAsSeries(rates, false);  // oldest first for forward EMA calculation
        int copied = CopyRates(m_symbol, m_timeframe, 0, requiredBars, rates);
        if(copied < period + 2)  // Need at least period bars for SMA init + 2 for output
            return false;

        double multiplier = 2.0 / ((double)period + 1.0);
        double invMultiplier = 1.0 - multiplier;

        double smaSum = 0.0;
        for(int i = 0; i < period; i++)
            smaSum += rates[i].close;
        double ema = smaSum / (double)period;

        // rates[copied-1]=shift 0 (forming), [copied-2]=shift 1 -> emaNow, [copied-3]=shift 2 -> emaPrev
        for(int i = period; i < copied - 2; i++)
        {
            ema = multiplier * rates[i].close + invMultiplier * ema;
        }
        emaPrev = ema;

        ema = multiplier * rates[copied - 2].close + invMultiplier * ema;
        emaNow = ema;

        return true;
    }

    bool FetchAverages(double &fastNow, double &fastPrev, double &slowNow, double &slowPrev)
    {
        double fastBuffer[2];
        double slowBuffer[2];

        // Closed-bar values: current signal bar = shift 1, previous = shift 2
        bool fastOk = SafeCopyBuffer(m_fastHandle, 0, 1, 2, fastBuffer);
        bool slowOk = SafeCopyBuffer(m_slowHandle, 0, 1, 2, slowBuffer);

        bool fastFallback = false;
        bool slowFallback = false;

        if(fastOk)
        {
            // Static arrays are NOT as-series: start=1,count=2 gives [0]=shift 2 (prev), [1]=shift 1 (now).
            fastNow = fastBuffer[1];
            fastPrev = fastBuffer[0];
        }
        else
        {
            fastFallback = CalculateEmaFallback(m_fastPeriod, fastNow, fastPrev);
            if(fastFallback)
                PrintFormat("[MOMENTUM-MA-FALLBACK] Fast EMA(%d) fallback used | Symbol=%s | TF=%s",
                           m_fastPeriod, m_symbol, EnumToString(m_timeframe));
        }

        if(slowOk)
        {
            slowNow = slowBuffer[1];   // [1]=shift 1 (newer); see the fast-EMA note above
            slowPrev = slowBuffer[0];
        }
        else
        {
            slowFallback = CalculateEmaFallback(m_slowPeriod, slowNow, slowPrev);
            if(slowFallback)
                PrintFormat("[MOMENTUM-MA-FALLBACK] Slow EMA(%d) fallback used | Symbol=%s | TF=%s",
                           m_slowPeriod, m_symbol, EnumToString(m_timeframe));
        }

        // Fail only when neither the handle copy nor the fallback produced a value
        if(!fastOk && !fastFallback)
            return false;
        if(!slowOk && !slowFallback)
            return false;

        return true;
    }

    bool FetchFastEMA3(double &emaNow, double &emaPrev, double &emaPrev2)
    {
        double fastBuffer[3];

        // Closed bars, oldest-first: [0]=shift 3 .. [2]=shift 1; reversed history made ROC reward deceleration.
        if(!SafeCopyBuffer(m_fastHandle, 0, 1, 3, fastBuffer)) return false;

        emaNow = fastBuffer[2];
        emaPrev = fastBuffer[1];
        emaPrev2 = fastBuffer[0];
        return true;
    }

public:
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
        m_enableScalping(false),
        m_scalpCooldownSeconds(20),
        m_minVolatility(0.0005),
        m_atrThresholdMult(0.20),
        m_rsiHandle(INVALID_HANDLE),
                m_macdHandle(INVALID_HANDLE),
                m_adxHandle(INVALID_HANDLE),
                m_volumeHandle(INVALID_HANDLE),
                m_crossoverBar(0),
                m_minConfirmationBars(1),  // conservative: 1 closed bar of confirmation
                m_rsiOverbought(72.0),
                m_rsiOversold(28.0),
                m_adxThreshold(20.0),
                m_minScalpTimeframe(PERIOD_M1),
                m_maxScalpTimeframe(PERIOD_M15),
                m_signalsGenerated(0)
    {
        m_strategyPrefix = "MOMENTUM";
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
        m_enableScalping(false),
        m_scalpCooldownSeconds(20),
        m_minVolatility(0.0005),     // minimum ATR value; symbol scale applied in Init
        m_atrThresholdMult(0.20),     // crossover gap must exceed 20% of ATR
        m_rsiHandle(INVALID_HANDLE),
        m_macdHandle(INVALID_HANDLE),
        m_adxHandle(INVALID_HANDLE),
        m_volumeHandle(INVALID_HANDLE),
        m_crossoverBar(0),
        m_minConfirmationBars(MathMax(1, minConfirmationBars)),
        m_rsiOverbought(72.0),
        m_rsiOversold(28.0),
        m_adxThreshold(20.0),
        m_minScalpTimeframe(PERIOD_M1),
        m_maxScalpTimeframe(PERIOD_M15),
                m_signalsGenerated(0)
    {
        m_strategyPrefix = "MOMENTUM";
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

// Hysteresis depth: 1 is lenient, larger values demand a longer-held crossover.
    void SetMinimumConfirmationBars(const int bars)
    {
        m_minConfirmationBars = MathMax(1, MathMin(bars, 5));
        PrintFormat("[MOMENTUM] Minimum confirmation bars set to %d", m_minConfirmationBars);
    }

    int GetMinimumConfirmationBars() const { return m_minConfirmationBars; }

    void SetRSIThresholds(double overbought, double oversold)
    {
        m_rsiOverbought = MathMax(60.0, MathMin(90.0, overbought));
        m_rsiOversold = MathMax(10.0, MathMin(40.0, oversold));
    }

    void SetADXThreshold(double threshold)
    {
        m_adxThreshold = MathMax(10.0, MathMin(40.0, threshold));
    }

// Scalping must run M1-M15; trend-following needs M5 or higher to avoid false crosses.
    void SetScalpTimeframeBounds(const ENUM_TIMEFRAMES minTf, const ENUM_TIMEFRAMES maxTf)
    {
        m_minScalpTimeframe = minTf;
        m_maxScalpTimeframe = maxTf;
        PrintFormat("[MOMENTUM] Scalp timeframe bounds set: %s to %s", 
                   EnumToString(m_minScalpTimeframe), EnumToString(m_maxScalpTimeframe));
    }

    ENUM_TIMEFRAMES GetMinScalpTimeframe() const { return m_minScalpTimeframe; }
    ENUM_TIMEFRAMES GetMaxScalpTimeframe() const { return m_maxScalpTimeframe; }

    bool ValidateTimeframeSuitability()
    {
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

                ValidateTimeframeSuitability();

                // The ATR floor is an absolute price value, so it must match the symbol scale
                if(SymbolInfoInteger(symbol, SYMBOL_DIGITS) <= 3) // JPY pairs or Indices
                    m_minVolatility = 0.05; 
                else
                    m_minVolatility = 0.0005;

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
            CStrategyBase::Deinit();
        }

    virtual ENUM_TRADE_SIGNAL GetSignal(double &confidence) override
    {
        confidence = 0.0;
        SetDecisionReasonTag("MOMENTUM_UNSET");

        if(!IsEnabled() || !m_is_initialized)
            return RejectSignal("MOMENTUM_DISABLED_OR_UNINIT");
        
        if(m_fastHandle == INVALID_HANDLE || m_slowHandle == INVALID_HANDLE ||
           m_atrHandle == INVALID_HANDLE)
            return RejectSignal("MOMENTUM_INVALID_HANDLES");

        // Conservative cooldown is one full bar; scalping uses a wall-clock cooldown bounded by the timeframe.
        int timeframeSeconds = MathMax(30, (int)PeriodSeconds(m_timeframe));
        int cooldownSeconds = timeframeSeconds;
        if(m_enableScalping)
            cooldownSeconds = MathMax(5, MathMin(m_scalpCooldownSeconds, timeframeSeconds));
        if(TimeCurrent() - m_lastSignalTimestamp < cooldownSeconds)
            return RejectSignal("MOMENTUM_COOLDOWN");

        if(!m_enableScalping)
        {
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
        // The points threshold is a floor: ATR scaling may raise it but never lower it
        double staticThreshold = m_thresholdPoints * point;

        // Oldest-first 10-bar window: [9] is the newest closed bar.
        double atrWindow[10];
        if(!SafeCopyBuffer(m_atrHandle, 0, 1, 10, atrWindow))
            return RejectSignal("MOMENTUM_ATR_UNAVAILABLE");
        double curATR = atrWindow[9];
        double avgATR = 0.0;
        for(int i = 0; i < 9; i++)
            avgATR += atrWindow[i];
        avgATR /= 9.0;
        double close1Vol = iClose(m_symbol, m_timeframe, 1);
        double volFloor = MathMin(m_minVolatility, close1Vol * 0.0001);
        if(curATR < volFloor)
        {
            return RejectSignal("MOMENTUM_LOW_VOLATILITY");
        }

        double atrThreshold = curATR * m_atrThresholdMult;
        double threshold = MathMax(staticThreshold, atrThreshold);

        double rsiBuffer[1];
        if(!SafeCopyBuffer(m_rsiHandle, 0, 1, 1, rsiBuffer))
            return RejectSignal("MOMENTUM_RSI_UNAVAILABLE");
        double rsi = rsiBuffer[0];

        ENUM_TRADE_SIGNAL signal = TRADE_SIGNAL_NONE;
        bool crossedUp = (diffNow > threshold && diffPrev <= threshold);
        bool crossedDown = (diffNow < -threshold && diffPrev >= -threshold);
        
        if(crossedUp)
        {
            if(m_minConfirmationBars > 1)
            {
                if(!ValidateCrossoverWithHysteresis(+1, threshold, m_minConfirmationBars - 1))
                    return RejectSignal("MOMENTUM_HYSTERESIS_BULLISH_FAILED");
            }
            signal = TRADE_SIGNAL_BUY;
        }
        else if(crossedDown)
        {
            if(m_minConfirmationBars > 1)
            {
                if(!ValidateCrossoverWithHysteresis(-1, threshold, m_minConfirmationBars - 1))
                    return RejectSignal("MOMENTUM_HYSTERESIS_BEARISH_FAILED");
            }
            signal = TRADE_SIGNAL_SELL;
        }
        // Scalping also enters on sustained momentum, not only on the cross itself
        else if(m_enableScalping)
        {
            if(diffNow > threshold * 1.5)
                signal = TRADE_SIGNAL_BUY;
            else if(diffNow < -threshold * 1.5)
                signal = TRADE_SIGNAL_SELL;
        }

        // Rate-of-change: an accelerating crossover earns a confidence boost
        double rocMultiplier = 1.0;
        if(signal != TRADE_SIGNAL_NONE)
        {
            double emaNow, emaPrev, emaPrev2;
            if(FetchFastEMA3(emaNow, emaPrev, emaPrev2))
            {
                if(emaPrev != 0.0 && emaPrev2 != 0.0)
                {
                    double currentROC = (emaNow - emaPrev) / emaPrev * 100.0;
                    double previousROC = (emaPrev - emaPrev2) / emaPrev2 * 100.0;
                    double absCurrentROC = MathAbs(currentROC);
                    double absPreviousROC = MathAbs(previousROC);

                    // 1.2x band: without a margin the multiplier flips on a flat or noisy ROC
                    if(absPreviousROC > 0.0 && absCurrentROC > absPreviousROC * 1.2)
                    {
                        rocMultiplier = 1.3;
                        PrintFormat("[MOMENTUM-ROC] Accelerating | CurrROC=%.4f PrevROC=%.4f | Boost=1.3x",
                                   currentROC, previousROC);
                    }
                    else
                    {
                        rocMultiplier = 0.7;
                        PrintFormat("[MOMENTUM-ROC] Decelerating | CurrROC=%.4f PrevROC=%.4f | Reduce=0.7x",
                                   currentROC, previousROC);
                    }
                }
            }
        }

        if(signal == TRADE_SIGNAL_NONE)
            return RejectSignal("MOMENTUM_NO_CROSSOVER");
        
        if(HasRSIDivergence(signal))
            return RejectSignal("MOMENTUM_DIVERGENCE_DETECTED");
            
        if(signal == TRADE_SIGNAL_BUY && rsi > m_rsiOverbought)
            return RejectSignal("MOMENTUM_RSI_OVERBOUGHT");

        if(signal == TRADE_SIGNAL_SELL && rsi < m_rsiOversold)
            return RejectSignal("MOMENTUM_RSI_OVERSOLD");

        // Trending market required; without it only a pullback entry or 2x-threshold momentum passes
        if(!StrongTrend())
        {
            if(!PullbackEntry(signal) && MathAbs(diffNow) < threshold * 2.0)
                return RejectSignal("MOMENTUM_ADX_WEAK_TREND");
        }

        if(!MACDConfirmed(signal))
        {
            // MACD is soft confirmation, not a gate: reduce confidence, never block
            PrintFormat("[MOMENTUM-ENHANCED] MACD not confirmed for %s | Confidence reduced",
                       signal == TRADE_SIGNAL_BUY ? "BUY" : "SELL");
        }

        if(crossedUp || crossedDown)
            m_crossoverBar = iBars(m_symbol, m_timeframe);

        if(signal != TRADE_SIGNAL_NONE)
        {
            double momentumConfidence = MathMin(1.0, MathAbs(diffNow) / (threshold * 2.5));
            
            // curATR against this symbol's own recent ATR average; an FX-scale absolute floor read ~100x on synthetics.
            double atrRatio = (avgATR > 0.0) ? curATR / avgATR : 1.0;
            if(atrRatio > 2.0)
            {
                momentumConfidence *= 0.6;
                PrintFormat("[MOMENTUM-VOL] High volatility detected | ATR ratio=%.2f | Confidence reduced to %.1f%%",
                           atrRatio, momentumConfidence * 100);
            }
            else if(atrRatio > 1.5)
            {
                momentumConfidence *= 0.8;
                PrintFormat("[MOMENTUM-VOL] Elevated volatility | ATR ratio=%.2f | Confidence adjusted to %.1f%%",
                           atrRatio, momentumConfidence * 100);
            }
            
            momentumConfidence *= rocMultiplier;

            double freshnessMod = GetMomentumFreshnessConfidence(signal);
            momentumConfidence *= freshnessMod;

            if(MACDConfirmed(signal))
                momentumConfidence *= 1.10;
            else
                momentumConfidence *= 0.85;

            confidence = MathMin(1.0, MathMax(0.0, momentumConfidence));
            
            // ATR-based stop distance, handed to the risk manager below
            double atrBuffer[2];
            double atr = 0.0;
            if(SafeCopyBuffer(m_atrHandle, 0, 1, 2, atrBuffer))
                atr = atrBuffer[1]; // oldest-first layout: [1] is the newest closed bar
            double currentPrice = (signal == TRADE_SIGNAL_BUY) ? SymbolInfoDouble(m_symbol, SYMBOL_ASK) : SymbolInfoDouble(m_symbol, SYMBOL_BID);
            double slDistance = (atr > 0) ? (atr * 2.0) : (currentPrice * 0.01); // 2x ATR or 1% fallback
            double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
            double slPips = (point > 0) ? (slDistance / point) : 0;
            
            // CalculateSize clamps to SYMBOL_VOLUME_MAX and applies margin checks
            double calculatedLot = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
                            if(m_positionSizer != NULL)
                            {
                                SPositionSizingParams sizerParams = m_positionSizer.GetParameters();
                                calculatedLot = m_positionSizer.CalculatePositionSizeWithRisk(m_symbol, slPips, sizerParams.riskPercent, confidence);
                                if(calculatedLot <= 0.0)
                                    calculatedLot = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);  // broker minimum lot
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

            SetProposedStops(request.stopLossPips, request.takeProfitPips);
            if(!ValidateWithRiskManager(request, "MOMENTUM", confidence))
                return TRADE_SIGNAL_NONE;
            
            m_lastSignalBar = iTime(m_symbol, m_timeframe, 1);
            m_lastSignalTimestamp = TimeCurrent();
            m_signalsGenerated++;
            RecordSignal();
            SetDecisionReasonTag(signal == TRADE_SIGNAL_BUY ? "MOMENTUM_SIGNAL_BUY" : "MOMENTUM_SIGNAL_SELL");
            
            // [CONSENSUS-DIAG] is a mandated log signature (AGENTS.md section 6); do not drop it.
            LogConsensusDiag(signal, StringFormat("Cross: %.1f pts | RSI: %.1f | MACD: %s | ADX: %s", diffNow / point, rsi, MACDConfirmed(signal) ? "YES" : "NO", StrongTrend() ? "STRONG" : "WEAK"), confidence);
            
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
};

#endif // __SIMPLE_MOMENTUM_STRATEGY_MQH__

