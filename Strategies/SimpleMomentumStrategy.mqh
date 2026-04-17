//+------------------------------------------------------------------+
//| SimpleMomentumStrategy.mqh                                       |
//| Basic momentum strategy using EMA crossover                      |
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
    int     m_trendHandle;         // Trend indicator (slower MA)
    int     m_stateSlowHandle;     // Regime state EMA (200)
    int     m_atrHandle;           // Volatility filter
    double  m_lastDiff;
    datetime m_lastSignalBar;      // Track last bar where signal was generated
    bool     m_enableScalping;     // Allow rapid signals
    double   m_minTrendStrength;   // Minimum trend strength for trades
    double   m_minVolatility;      // Minimum volatility threshold
    double   m_atrThresholdMult;   // Dynamic threshold multiplier
    int      m_rsiHandle;          // RSI for momentum trap filter
    int      m_volumeHandle;       // Tick volume confirmation
    datetime m_lastSignalTimestamp;     // Track absolute time of last signal
    string   m_lastRejectReasonTag;
    datetime m_lastRejectLogTime;

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
        if(m_trendHandle != INVALID_HANDLE) IndicatorRelease(m_trendHandle);
        if(m_stateSlowHandle != INVALID_HANDLE) IndicatorRelease(m_stateSlowHandle);
        if(m_atrHandle != INVALID_HANDLE) IndicatorRelease(m_atrHandle);
        if(m_rsiHandle != INVALID_HANDLE) IndicatorRelease(m_rsiHandle);
        if(m_volumeHandle != INVALID_HANDLE) IndicatorRelease(m_volumeHandle);

        m_fastHandle = iMA(m_symbol, m_timeframe, m_fastPeriod, 0, MODE_EMA, PRICE_CLOSE);
        m_slowHandle = iMA(m_symbol, m_timeframe, m_slowPeriod, 0, MODE_EMA, PRICE_CLOSE);
        m_trendHandle = iMA(m_symbol, m_timeframe, 50, 0, MODE_EMA, PRICE_CLOSE);  // Trend filter
        m_stateSlowHandle = iMA(m_symbol, m_timeframe, 200, 0, MODE_EMA, PRICE_CLOSE); // Regime state filter
        m_atrHandle = iATR(m_symbol, m_timeframe, 14); // Standard 14-period ATR
        m_rsiHandle = iRSI(m_symbol, m_timeframe, 14, PRICE_CLOSE);
        m_volumeHandle = iVolumes(m_symbol, m_timeframe, VOLUME_TICK);

        if(m_fastHandle == INVALID_HANDLE || m_slowHandle == INVALID_HANDLE || 
           m_trendHandle == INVALID_HANDLE || m_stateSlowHandle == INVALID_HANDLE || 
           m_atrHandle == INVALID_HANDLE || m_rsiHandle == INVALID_HANDLE || m_volumeHandle == INVALID_HANDLE)
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
        m_trendHandle(INVALID_HANDLE),
        m_stateSlowHandle(INVALID_HANDLE),
        m_atrHandle(INVALID_HANDLE),
        m_lastDiff(0.0),
        m_lastSignalBar(0),
        m_lastSignalTimestamp(0),
        m_lastRejectReasonTag(""),
        m_lastRejectLogTime(0),
        m_enableScalping(false),
        m_minTrendStrength(0.55),
        m_minVolatility(0.0005),
        m_atrThresholdMult(0.15),
        m_rsiHandle(INVALID_HANDLE),
        m_volumeHandle(INVALID_HANDLE)
    {
    }

    CSimpleMomentumStrategy(const string name, const int fastPeriod = 8, const int slowPeriod = 21, const double thresholdPoints = 12.0) :
        CStrategyBase(name),
        m_fastPeriod(fastPeriod),
        m_slowPeriod(slowPeriod),
        m_thresholdPoints(MathMax(1.0, thresholdPoints)),
        m_fastHandle(INVALID_HANDLE),
        m_slowHandle(INVALID_HANDLE),
        m_trendHandle(INVALID_HANDLE),
        m_stateSlowHandle(INVALID_HANDLE),
        m_atrHandle(INVALID_HANDLE),
        m_lastDiff(0.0),
        m_lastSignalBar(0),
        m_lastSignalTimestamp(0),
        m_lastRejectReasonTag(""),
        m_lastRejectLogTime(0),
        m_enableScalping(false),      // SCALPING MODE: Disabled by default
        m_minTrendStrength(0.55),    // TREND FILTER: 55% minimum trend alignment
        m_minVolatility(0.0005),     // VOLATILITY FILTER: Minimum ATR value (adjusted by point)
        m_atrThresholdMult(0.20),    // ADAPTIVE FILTER: Crossover gap must exceed 20% of ATR
        m_rsiHandle(INVALID_HANDLE),
        m_volumeHandle(INVALID_HANDLE)
    {
    }

    virtual ~CSimpleMomentumStrategy()
    {
        Deinit();
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
        if(m_trendHandle != INVALID_HANDLE) { IndicatorRelease(m_trendHandle); m_trendHandle = INVALID_HANDLE; }
        if(m_stateSlowHandle != INVALID_HANDLE) { IndicatorRelease(m_stateSlowHandle); m_stateSlowHandle = INVALID_HANDLE; }
        if(m_atrHandle != INVALID_HANDLE) { IndicatorRelease(m_atrHandle); m_atrHandle = INVALID_HANDLE; }
        if(m_rsiHandle != INVALID_HANDLE) { IndicatorRelease(m_rsiHandle); m_rsiHandle = INVALID_HANDLE; }
        if(m_volumeHandle != INVALID_HANDLE) { IndicatorRelease(m_volumeHandle); m_volumeHandle = INVALID_HANDLE; }
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
           m_trendHandle == INVALID_HANDLE || m_stateSlowHandle == INVALID_HANDLE || m_atrHandle == INVALID_HANDLE)
            return RejectSignal("MOMENTUM_INVALID_HANDLES");

        // COOLDOWN: Adaptive to chart timeframe — one full bar minimum.
        // On M1 this is 60s, on M5 it is 300s, on M30 it is 1800s, etc.
        // Minimum floor of 30s to prevent rapid re-entry on tick noise.
        int cooldownSeconds = MathMax(30, (int)PeriodSeconds(m_timeframe));
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
        double atrWindow[24];
        if(CopyBuffer(m_atrHandle, 0, 1, 24, atrWindow) < 24)
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
        
        // --- VOLUME CONFIRMATION ---
        double volBuffer[11];
        if(CopyBuffer(m_volumeHandle, 0, 1, 11, volBuffer) < 11)
            return RejectSignal("MOMENTUM_VOL_UNAVAILABLE");
        long currentVol = (long)volBuffer[0];
        long sumVol = 0;
        for(int v=1; v<=10; v++) sumVol += (long)volBuffer[v];
        long avgVol = MathMax((long)1, (long)(sumVol / 10));
        bool volumeConfirmed = currentVol > (avgVol * 1.1); // Need 10% volume bump

        double atrCompressionFloor = atrWindow[1];
        for(int a = 2; a < 24; a++)
        {
            if(atrWindow[a] < atrCompressionFloor)
                atrCompressionFloor = atrWindow[a];
        }
        bool compressionState = (atrCompressionFloor > 0.0 && atrWindow[0] <= (atrCompressionFloor * 1.20));
        bool volatilityExpansion = (atrWindow[1] > 0.0 && atrWindow[0] >= (atrWindow[1] * 1.05));

        // --- TREND FILTER ---
        double trendBuffer[1];
        double stateSlowBuffer[1];
        if(CopyBuffer(m_trendHandle, 0, 1, 1, trendBuffer) < 1)
            return RejectSignal("MOMENTUM_TREND_UNAVAILABLE");
        if(CopyBuffer(m_stateSlowHandle, 0, 1, 1, stateSlowBuffer) < 1)
            return RejectSignal("MOMENTUM_STATE_UNAVAILABLE");
        double trendMA = trendBuffer[0];
        double stateSlowMA = stateSlowBuffer[0];

        // SOFTENED EMA STACK: Count how many of 3 alignment criteria are met.
        // Old code required perfect 4-MA waterfall (8>21>50>200) — almost never seen on M1.
        // New code requires 2-of-3: fast>slow, slow>trend, trend>state.
        // This allows partial-trend entries on emerging moves.
        int bullScore = (fastNow > slowNow ? 1 : 0) +
                        (slowNow > trendMA  ? 1 : 0) +
                        (trendMA > stateSlowMA ? 1 : 0);
        int bearScore = (fastNow < slowNow ? 1 : 0) +
                        (slowNow < trendMA  ? 1 : 0) +
                        (trendMA < stateSlowMA ? 1 : 0);

        bool bullishState = (bullScore >= 2);
        bool bearishState = (bearScore >= 2);
        if(!bullishState && !bearishState)
            return RejectSignal("MOMENTUM_STATE_MISALIGNED");

        ENUM_TRADE_SIGNAL signal = TRADE_SIGNAL_NONE;
        
        // Trigger must come from compression-to-break, not pure crossover noise.
        bool crossedUp = (diffNow > threshold && diffPrev <= threshold);
        bool crossedDown = (diffNow < -threshold && diffPrev >= -threshold);
        if(crossedUp)
        {
            signal = TRADE_SIGNAL_BUY;
        }
        else if(crossedDown)
        {
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

        // Confirm crossover structure using advanced metrics
        if(!volumeConfirmed)
            return RejectSignal("MOMENTUM_LOW_VOLUME_BREAK");
            
        if(signal == TRADE_SIGNAL_BUY && rsi > 72.0)
            return RejectSignal("MOMENTUM_RSI_OVERBOUGHT");
        
        if(signal == TRADE_SIGNAL_SELL && rsi < 28.0)
            return RejectSignal("MOMENTUM_RSI_OVERSOLD");

        // FIX: Old code required BOTH compressionState AND volatilityExpansion simultaneously —
        // these are near-mutually exclusive (ATR can't be at 24-bar low AND expanding at once).
        // New logic: pass if EITHER condition is met (compression about to break, OR already breaking).
        if(!compressionState && !volatilityExpansion)
            return RejectSignal("MOMENTUM_NO_COMPRESSION_BREAK");

        if(signal != TRADE_SIGNAL_NONE)
        {
            bool stateAligned = ((signal == TRADE_SIGNAL_BUY && bullishState) ||
                                 (signal == TRADE_SIGNAL_SELL && bearishState));
            if(!stateAligned)
            {
                return RejectSignal("MOMENTUM_TREND_MISALIGNED");
            }

            double momentumConfidence = MathMin(1.0, MathAbs(diffNow) / (threshold * 2.5));
            double expansionConfidence = MathMin(1.0, atrWindow[0] / MathMax(atrWindow[1], m_minVolatility));
            double stateConfidence = 1.0;
            confidence = (momentumConfidence * 0.55) + (expansionConfidence * 0.30) + (stateConfidence * 0.15);
            confidence = MathMin(1.0, MathMax(0.0, confidence));
            
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
