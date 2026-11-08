// TTM Squeeze breakout: BB inside Keltner marks compression, Hurst picks the direction.
#ifndef RANGE_COMPRESSION_BREAKOUT_MQH
#define RANGE_COMPRESSION_BREAKOUT_MQH

#include "../Core/Strategy/StrategyBase.mqh"
#include "../Core/Risk/UnifiedRiskManager.mqh"
#include "../Core/Engines/HurstEngine.mqh"
#include "../Utilities/SafeCopyBuffer.mqh"

struct SCompressionSignal
{
    ENUM_TRADE_SIGNAL direction;
    double entryPrice;
    double stopLoss;
    double takeProfit;
    double confidence;
    string reason;
    int    squeezeBars;          // bars the squeeze held before release
    double hurstValue;           // Hurst exponent sampled at breakout
    bool   isMomentumBreakout;   // H above m_hurstTrendThreshold: follow the break
    bool   isMeanRevFade;        // H below m_hurstMRThreshold: fade the break

    SCompressionSignal() :
        direction(TRADE_SIGNAL_NONE),
        entryPrice(0),
        stopLoss(0),
        takeProfit(0),
        confidence(0),
        reason(""),
        squeezeBars(0),
        hurstValue(0.5),
        isMomentumBreakout(false),
        isMeanRevFade(false) {}
};

// Enhanced squeeze detection with Hurst regime awareness
class CRangeCompressionBreakout : public CStrategyBase
{
private:
    int    m_bbPeriod;           // Bollinger Band period
    double m_bbDeviation;        // BB standard deviations
    int    m_kcPeriod;           // Keltner Channel EMA period
    double m_kcATRMultiple;      // KC band width in ATRs
    int    m_atrPeriod;
    int    m_minSqueezeBars;     // a squeeze shorter than this never fires
    double m_hurstTrendThreshold;  // H above this = trending, follow the break
    double m_hurstMRThreshold;     // H below this = mean-reverting, fade the break
    double m_volumeConfirmRatio;   // breakout volume must exceed ratio * average
    int    m_volumeLookback;       // bars behind the breakout in that average
    
    int    m_trendMaPeriod;        // EMA the breakout close is compared against
    bool   m_useTrendFilter;       // applies to momentum entries only, never to fades

    int m_bbHandle;
    int m_kcHandle;
    int m_atrHandle;
    int m_volumeHandle;
    int m_maHandle;      // stays INVALID_HANDLE while m_useTrendFilter is off

    CHurstEngine* m_hurstEngine;   // injected, not owned - never released here

    CUnifiedRiskManager* m_riskManager;

    bool   m_squeezeActive;
    int    m_squeezeBarCount;
    datetime m_squeezeCountedBar;
    double m_lastBBUpper;
    double m_lastBBLower;
    double m_lastKCUpper;
    double m_lastKCLower;
    datetime m_lastSignalBar;
    datetime m_lastBarTime;

    bool CheckSqueeze(double bbUpper, double bbLower, double kcUpper, double kcLower)
    {
        // Squeeze = Bollinger Bands entirely inside the Keltner Channel
        return (bbUpper < kcUpper && bbLower > kcLower);
    }

    bool CheckVolumeConfirmation()
    {
        long vol[];
        ArraySetAsSeries(vol, true);
        // vol[0] is the FORMING bar and its partial tick volume would skew the surge test,
        // so judge the last CLOSED bar (vol[1]) against the preceding full bars.
        int copied = CopyTickVolume(m_symbol, m_timeframe, 0, m_volumeLookback + 2, vol);
        if(copied < m_volumeLookback + 2)
            return false; // short history: no signal rather than a mis-scaled average

        double avgVol = 0;
        for(int i = 2; i <= m_volumeLookback + 1; i++)
            avgVol += (double)vol[i];
        avgVol /= (double)m_volumeLookback;

        return (avgVol > 0 && (double)vol[1] > avgVol * m_volumeConfirmRatio);
    }

public:
    CRangeCompressionBreakout() :
        CStrategyBase("RangeCompressionBreakout", 0),
        m_bbPeriod(20),
        m_bbDeviation(2.0),
        m_kcPeriod(20),
        m_kcATRMultiple(1.5),
        m_atrPeriod(14),
        m_minSqueezeBars(6),
        m_hurstTrendThreshold(0.55),
        m_hurstMRThreshold(0.45),
        m_volumeConfirmRatio(1.5),
        m_volumeLookback(20),
        m_trendMaPeriod(50),
        m_useTrendFilter(true),
        m_bbHandle(INVALID_HANDLE),
        m_kcHandle(INVALID_HANDLE),
        m_atrHandle(INVALID_HANDLE),
        m_volumeHandle(INVALID_HANDLE),
        m_maHandle(INVALID_HANDLE),
        m_hurstEngine(NULL),
        m_riskManager(NULL),
        m_squeezeActive(false),
        m_squeezeBarCount(0),
        m_squeezeCountedBar(0),
        m_lastBBUpper(0),
        m_lastBBLower(0),
        m_lastKCUpper(0),
        m_lastKCLower(0),
        m_lastSignalBar(0),
        m_lastBarTime(0)
    {
        m_strategyPrefix = "COMPRESSION";
    }

    ~CRangeCompressionBreakout()
    {
        if(m_bbHandle != INVALID_HANDLE) IndicatorRelease(m_bbHandle);
        if(m_kcHandle != INVALID_HANDLE) IndicatorRelease(m_kcHandle);
        if(m_atrHandle != INVALID_HANDLE) IndicatorRelease(m_atrHandle);
        if(m_volumeHandle != INVALID_HANDLE) IndicatorRelease(m_volumeHandle);
        if(m_maHandle != INVALID_HANDLE) IndicatorRelease(m_maHandle);
    }

    bool Initialize(const string symbol, ENUM_TIMEFRAMES timeframe,
                    CHurstEngine* hurstEngine = NULL,
                    CUnifiedRiskManager* riskManager = NULL)
    {
        m_symbol = symbol;
        m_timeframe = timeframe;
        m_hurstEngine = hurstEngine;
        m_riskManager = riskManager;

        m_bbHandle = iBands(symbol, timeframe, m_bbPeriod, 0, m_bbDeviation, PRICE_CLOSE);
        m_atrHandle = iATR(symbol, timeframe, m_atrPeriod);
        m_volumeHandle = iVolumes(symbol, timeframe, VOLUME_TICK);
        
        // MA for the trend filter; stays INVALID_HANDLE when the filter is disabled
        if(m_useTrendFilter)
        {
            m_maHandle = iMA(symbol, timeframe, m_trendMaPeriod, 0, MODE_EMA, PRICE_CLOSE);
        }

        // MT5 has no native Keltner Channel, so it is computed from ATR in GetSignal

        return (m_bbHandle != INVALID_HANDLE && m_atrHandle != INVALID_HANDLE);
    }

    void Configure(int bbPeriod = 20, double bbDev = 2.0, int kcPeriod = 20,
                   double kcATR = 1.5, int minSqueezeBars = 6,
                   double volRatio = 1.5, int trendMaPeriod = 50, bool useTrendFilter = true)
    {
        m_bbPeriod = MathMax(10, bbPeriod);
        m_bbDeviation = MathMax(1.0, bbDev);
        m_kcPeriod = MathMax(10, kcPeriod);
        m_kcATRMultiple = MathMax(0.5, kcATR);
        m_minSqueezeBars = MathMax(3, minSqueezeBars);
        m_volumeConfirmRatio = MathMax(1.0, volRatio);
        m_trendMaPeriod = MathMax(20, trendMaPeriod);
        m_useTrendFilter = useTrendFilter;
    }

    SCompressionSignal GetSignal()
    {
        SCompressionSignal signal;

        if(m_bbHandle == INVALID_HANDLE || m_atrHandle == INVALID_HANDLE)
            return signal;

        // Read CLOSED bars (start=1): the forming bar's close is near its open at evaluation
        // time, so start=0 made the band-breach test a timing lottery under once-per-bar polling.
        double bbUpper[1], bbMiddle[1], bbLower[1];
        if(CopyBuffer(m_bbHandle, 1, 1, 1, bbUpper) != 1 ||
           CopyBuffer(m_bbHandle, 0, 1, 1, bbMiddle) != 1 ||
           CopyBuffer(m_bbHandle, 2, 1, 1, bbLower) != 1)
            return signal;

        // ATR sizes the Keltner Channel, not the stop
        double atr[1];
        if(CopyBuffer(m_atrHandle, 0, 1, 1, atr) != 1 || atr[0] <= 0)
            return signal;

        double close[1];
        if(CopyClose(m_symbol, m_timeframe, 1, 1, close) != 1)
            return signal;

        // KC middle = EMA(m_kcPeriod); bands = middle +/- m_kcATRMultiple * ATR
        double ema[];
        ArraySetAsSeries(ema, true);
        int copied = CopyClose(m_symbol, m_timeframe, 1, m_kcPeriod + 1, ema);
        if(copied < m_kcPeriod + 1)
            return signal;

        // ArraySetAsSeries: index 0 = most recent, index copied-1 = oldest
        double alpha = 2.0 / (double)(m_kcPeriod + 1);
        double emaVal = ema[copied - 1]; // seeded from the oldest close
        for(int i = copied - 2; i >= 0; i--)
            emaVal = alpha * ema[i] + (1.0 - alpha) * emaVal;

        double kcUpper = emaVal + m_kcATRMultiple * atr[0];
        double kcLower = emaVal - m_kcATRMultiple * atr[0];

        bool currentSqueeze = CheckSqueeze(bbUpper[0], bbLower[0], kcUpper, kcLower);

        if(currentSqueeze)
        {
            // Repeated evaluations inside one closed bar must not satisfy the minimum squeeze length.
            datetime closedBarTime = iTime(m_symbol, m_timeframe, 1);
            if(closedBarTime != m_squeezeCountedBar)
            {
                m_squeezeBarCount++;
                m_squeezeCountedBar = closedBarTime;
            }
            m_squeezeActive = true;
        }
        else
        {
            // Squeeze just released
            if(m_squeezeActive && m_squeezeBarCount >= m_minSqueezeBars)
            {
                m_squeezeActive = false;

                // No engine or no warmup data leaves H at 0.5, i.e. the neutral path
                double hurst = 0.5;
                if(m_hurstEngine != NULL && m_hurstEngine.IsWarmedUp())
                    hurst = m_hurstEngine.GetHurstValue();

                ENUM_TRADE_SIGNAL direction = TRADE_SIGNAL_NONE;
                bool isMomentum = false;
                bool isFade = false;

                if(close[0] > bbUpper[0])
                {
                    if(hurst > m_hurstTrendThreshold)
                    {
                        // Trending regime: follow the breakout
                        direction = TRADE_SIGNAL_BUY;
                        isMomentum = true;
                    }
                    else if(hurst < m_hurstMRThreshold)
                    {
                        // Mean-reverting regime: fade the breakout
                        direction = TRADE_SIGNAL_SELL;
                        isFade = true;
                    }
                    else
                    {
                        // Between the thresholds: follow, the momentum path
                        direction = TRADE_SIGNAL_BUY;
                        isMomentum = true;
                    }
                }
                else if(close[0] < bbLower[0])
                {
                    if(hurst > m_hurstTrendThreshold)
                    {
                        direction = TRADE_SIGNAL_SELL;
                        isMomentum = true;
                    }
                    else if(hurst < m_hurstMRThreshold)
                    {
                        direction = TRADE_SIGNAL_BUY;
                        isFade = true;
                    }
                    else
                    {
                        direction = TRADE_SIGNAL_SELL;
                        isMomentum = true;
                    }
                }

                if(direction == TRADE_SIGNAL_NONE)
                    return signal;

                // The MA filter gates momentum entries only: a fade is counter-trend by
                // design, so gating it unconditionally rejected every fade signal.
                if(m_useTrendFilter && !isFade && m_maHandle != INVALID_HANDLE)
                {
                    double maVal[1];
                    // shift 1, matching the closed-bar close[0] it is compared against;
                    // every other read in this function is shift 1.
                    if(CopyBuffer(m_maHandle, 0, 1, 1, maVal) == 1 && maVal[0] > 0)
                    {
                        // BUY requires price above the MA, SELL below it
                        if(direction == TRADE_SIGNAL_BUY && close[0] < maVal[0])
                        {
                            PrintFormat("[COMPRESSION] Trend filter rejected BUY | price=%.5f < MA=%.5f",
                                        close[0], maVal[0]);
                            LogRejectEvent("TREND_FILTER_REJECT");
                            return signal;
                        }
                        else if(direction == TRADE_SIGNAL_SELL && close[0] > maVal[0])
                        {
                            PrintFormat("[COMPRESSION] Trend filter rejected SELL | price=%.5f > MA=%.5f",
                                        close[0], maVal[0]);
                            LogRejectEvent("TREND_FILTER_REJECT");
                            return signal;
                        }
                    }
                }

                if(!CheckVolumeConfirmation())
                {
                    LogRejectEvent("NO_VOLUME_CONFIRM");
                    return signal;
                }

                datetime currentBarTime = iTime(m_symbol, m_timeframe, 1);
                if(currentBarTime == m_lastSignalBar)
                {
                    LogRejectEvent("SAME_BAR");
                    return signal;
                }

                signal.direction = direction;
                signal.entryPrice = close[0];
                signal.squeezeBars = m_squeezeBarCount;
                signal.hurstValue = hurst;
                signal.isMomentumBreakout = isMomentum;
                signal.isMeanRevFade = isFade;

                if(isMomentum)
                {
                    // Momentum: SL at the far KC edge, TP at 2x the squeeze range
                    double squeezeRange = kcUpper - kcLower;
                    if(direction == TRADE_SIGNAL_BUY)
                    {
                        signal.stopLoss = kcLower;
                        signal.takeProfit = close[0] + squeezeRange * 2.0;
                    }
                    else
                    {
                        signal.stopLoss = kcUpper;
                        signal.takeProfit = close[0] - squeezeRange * 2.0;
                    }
                    signal.confidence = 0.65 + MathMin(0.2, (m_squeezeBarCount - m_minSqueezeBars) * 0.02);
                }
                else // isFade
                {
                    // Fade: tighter SL above/below the breakout, target back to middle
                    if(direction == TRADE_SIGNAL_BUY)
                    {
                        signal.stopLoss = bbLower[0] - atr[0] * 0.5;
                        signal.takeProfit = bbMiddle[0];
                    }
                    else
                    {
                        signal.stopLoss = bbUpper[0] + atr[0] * 0.5;
                        signal.takeProfit = bbMiddle[0];
                    }
                    signal.confidence = 0.55 + MathMin(0.15, (m_squeezeBarCount - m_minSqueezeBars) * 0.015);
                }

                signal.reason = StringFormat("SQUEEZE_BREAKOUT | bars=%d | H=%.3f | %s | vol_confirm=yes",
                                              m_squeezeBarCount, hurst,
                                              isMomentum ? "MOMENTUM" : "FADE");

                m_lastSignalBar = currentBarTime;
                m_squeezeBarCount = 0;

                PrintFormat("[COMPRESSION] SIGNAL | %s | %s | %s",
                           m_symbol,
                           direction == TRADE_SIGNAL_BUY ? "BUY" : "SELL",
                           signal.reason);

                return signal;
            }
            else
            {
                // Squeeze released before m_minSqueezeBars: reset, no signal
                m_squeezeActive = false;
                m_squeezeBarCount = 0;
            }
        }

        m_lastBBUpper = bbUpper[0];
        m_lastBBLower = bbLower[0];
        m_lastKCUpper = kcUpper;
        m_lastKCLower = kcLower;
        m_lastBarTime = iTime(m_symbol, m_timeframe, 0);

        return signal;
    }

    //--- Consensus vote path: adapts the struct-returning GetSignal to the double& interface.
    //--- Price-based stops become pips, consumed only when InpUseStrategyStops is enabled.
    virtual ENUM_TRADE_SIGNAL ExecuteSignal(double &confidence)
    {
        SCompressionSignal sig = GetSignal();
        confidence = sig.confidence;
        m_lastDecisionReasonTag = sig.reason;
        if(sig.direction != TRADE_SIGNAL_NONE && sig.entryPrice > 0)
        {
            double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
            if(point > 0)
                SetProposedStops(MathAbs(sig.entryPrice - sig.stopLoss) / point,
                                 MathAbs(sig.takeProfit - sig.entryPrice) / point);
        }
        return sig.direction;
    }

    // Must be GetType(): CStrategyBase::GetType() returns STRATEGY_TYPE_CUSTOM, so the regime gate never
    // saw this type. The catalog row and RegimeStateHardGate both name STRATEGY_RANGE_COMPRESSION, which
    // classifies it reversion-like: its vote is zeroed in a confirmed trend regime.
    virtual ENUM_STRATEGY_TYPE GetType() const override { return STRATEGY_RANGE_COMPRESSION; }

    void Deinit()
    {
        // This class owns its indicator handles, so both the destructor and Deinit release them
        if(m_bbHandle != INVALID_HANDLE)
        {
            IndicatorRelease(m_bbHandle);
            m_bbHandle = INVALID_HANDLE;
        }
        if(m_kcHandle != INVALID_HANDLE)
        {
            IndicatorRelease(m_kcHandle);
            m_kcHandle = INVALID_HANDLE;
        }
        if(m_atrHandle != INVALID_HANDLE)
        {
            IndicatorRelease(m_atrHandle);
            m_atrHandle = INVALID_HANDLE;
        }
        if(m_volumeHandle != INVALID_HANDLE)
        {
            IndicatorRelease(m_volumeHandle);
            m_volumeHandle = INVALID_HANDLE;
        }
        if(m_maHandle != INVALID_HANDLE)
        {
            IndicatorRelease(m_maHandle);
            m_maHandle = INVALID_HANDLE;
        }
        m_hurstEngine = NULL;
        m_riskManager = NULL;
    }
};

#endif // RANGE_COMPRESSION_BREAKOUT_MQH
