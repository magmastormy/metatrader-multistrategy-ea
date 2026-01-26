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
    int     m_atrHandle;           // Volatility filter
    double  m_lastDiff;
    datetime m_lastSignalBar;      // Track last bar where signal was generated
    bool     m_enableScalping;     // Allow rapid signals
    double   m_minTrendStrength;   // Minimum trend strength for trades
    double   m_minVolatility;      // Minimum volatility threshold
    datetime m_lastSignalTime;     // Track absolute time of last signal

    bool CreateHandles()
    {
        if(m_fastHandle != INVALID_HANDLE) IndicatorRelease(m_fastHandle);
        if(m_slowHandle != INVALID_HANDLE) IndicatorRelease(m_slowHandle);
        if(m_trendHandle != INVALID_HANDLE) IndicatorRelease(m_trendHandle);
        if(m_atrHandle != INVALID_HANDLE) IndicatorRelease(m_atrHandle);

        m_fastHandle = iMA(m_symbol, m_timeframe, m_fastPeriod, 0, MODE_EMA, PRICE_CLOSE);
        m_slowHandle = iMA(m_symbol, m_timeframe, m_slowPeriod, 0, MODE_EMA, PRICE_CLOSE);
        m_trendHandle = iMA(m_symbol, m_timeframe, 50, 0, MODE_EMA, PRICE_CLOSE);  // Trend filter
        m_atrHandle = iATR(m_symbol, m_timeframe, 14); // Standard 14-period ATR

        if(m_fastHandle == INVALID_HANDLE || m_slowHandle == INVALID_HANDLE || 
           m_trendHandle == INVALID_HANDLE || m_atrHandle == INVALID_HANDLE)
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

        if(CopyBuffer(m_fastHandle, 0, 0, 2, fastBuffer) < 2) return false;
        if(CopyBuffer(m_slowHandle, 0, 0, 2, slowBuffer) < 2) return false;

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
        m_atrHandle(INVALID_HANDLE),
        m_lastDiff(0.0),
        m_lastSignalBar(0),
        m_lastSignalTime(0),
        m_enableScalping(false),
        m_minTrendStrength(0.55),
        m_minVolatility(0.0005)
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
        m_atrHandle(INVALID_HANDLE),
        m_lastDiff(0.0),
        m_lastSignalBar(0),
        m_lastSignalTime(0),
        m_enableScalping(false),      // SCALPING MODE: Disabled by default
        m_minTrendStrength(0.55),    // TREND FILTER: 55% minimum trend alignment
        m_minVolatility(0.0005)      // VOLATILITY FILTER: Minimum ATR value (adjusted by point)
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
        if(m_atrHandle != INVALID_HANDLE) { IndicatorRelease(m_atrHandle); m_atrHandle = INVALID_HANDLE; }
        CStrategyBase::Deinit();
    }

    virtual ENUM_TRADE_SIGNAL GetSignal(double &confidence) override
    {
        if(!IsEnabled() || !m_is_initialized) return TRADE_SIGNAL_NONE;
        
        // Ensure handles are valid
        if(m_fastHandle == INVALID_HANDLE || m_slowHandle == INVALID_HANDLE) return TRADE_SIGNAL_NONE;

        // COOLDOWN: Always enforce at least 60 seconds between signals per symbol
        if(TimeCurrent() - m_lastSignalTime < 60) return TRADE_SIGNAL_NONE;

        if(!m_enableScalping)
        {
            // Conservative mode: Only one signal per bar
            datetime currentBar = iTime(m_symbol, m_timeframe, 0);
            if(currentBar == m_lastSignalBar) return TRADE_SIGNAL_NONE;
        }

        double fastNow, fastPrev, slowNow, slowPrev;
        if(!FetchAverages(fastNow, fastPrev, slowNow, slowPrev)) return TRADE_SIGNAL_NONE;

        double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
        if(point <= 0.0) point = 0.0001;

        double diffNow = fastNow - slowNow;
        double diffPrev = fastPrev - slowPrev;
        double threshold = m_thresholdPoints * point;

        // --- VOLATILITY FILTER ---
        double atrBuffer[1];
        if(CopyBuffer(m_atrHandle, 0, 0, 1, atrBuffer) < 1) return TRADE_SIGNAL_NONE;
        if(atrBuffer[0] < m_minVolatility) 
        {
            // Market too quiet
            return TRADE_SIGNAL_NONE;
        }

        // --- TREND FILTER ---
        double priceForTrend = SymbolInfoDouble(m_symbol, SYMBOL_BID);
        double trendBuffer[1];
        if(CopyBuffer(m_trendHandle, 0, 0, 1, trendBuffer) < 1) return TRADE_SIGNAL_NONE;
        double trendMA = trendBuffer[0];

        // Calculate trend strength (0.0 = strong down, 0.5 = neutral, 1.0 = strong up)
        double trendStrength = 0.5;
        if(priceForTrend > 0 && trendMA > 0)
        {
            double priceAboveTrend = (priceForTrend - trendMA) / trendMA;
            trendStrength = 0.5 + (priceAboveTrend * 100.0); // Scale to 0-1 (adjusted scaling factor)
            trendStrength = MathMax(0.0, MathMin(1.0, trendStrength));
        }

        ENUM_TRADE_SIGNAL signal = TRADE_SIGNAL_NONE;
        
        // Momentum crossover detection
        if(diffNow > threshold && diffPrev <= threshold)
        {
            signal = TRADE_SIGNAL_BUY;
        }
        else if(diffNow < -threshold && diffPrev >= -threshold)
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

        if(signal != TRADE_SIGNAL_NONE)
        {
            // TREND FILTER: Validate signal against trend
            bool trendAligned = false;
            
            if(signal == TRADE_SIGNAL_BUY && trendStrength >= m_minTrendStrength)
                trendAligned = true;
            else if(signal == TRADE_SIGNAL_SELL && trendStrength <= (1.0 - m_minTrendStrength))
                trendAligned = true;

            if(!trendAligned)
            {
                // Reject signal: not aligned with trend
                return TRADE_SIGNAL_NONE;
            }

            // Calculate confidence based on momentum strength and trend alignment
            double momentumConfidence = MathMin(1.0, MathAbs(diffNow) / (threshold * 2.0));
            double trendConfidence = (signal == TRADE_SIGNAL_BUY) ? trendStrength : (1.0 - trendStrength);
            confidence = (momentumConfidence * 0.6) + (trendConfidence * 0.4); // 60% momentum, 40% trend
            
            m_lastSignalBar = iTime(m_symbol, m_timeframe, 0);
            m_lastSignalTime = TimeCurrent();
            RecordSignal();
        }

        return signal;
    }

    virtual ENUM_STRATEGY_TYPE GetType(void) const override
    {
        return STRATEGY_MOMENTUM;
    }
};

#endif // __SIMPLE_MOMENTUM_STRATEGY_MQH__
