//+------------------------------------------------------------------+
//| RangeCompressionBreakout.mqh                                     |
//| Enhanced TTM Squeeze + Hurst Regime Breakout Strategy            |
//| Uses BB inside Keltner + Hurst to determine breakout direction  |
//| Batch 114: New strategy — does NOT replace existing strategies   |
//+------------------------------------------------------------------+
#ifndef RANGE_COMPRESSION_BREAKOUT_MQH
#define RANGE_COMPRESSION_BREAKOUT_MQH

#include "../Core/Strategy/StrategyBase.mqh"
#include "../Core/Risk/UnifiedRiskManager.mqh"
#include "../Core/Engines/HurstEngine.mqh"
#include "../Utilities/SafeCopyBuffer.mqh"

//+------------------------------------------------------------------+
//| Range Compression Signal Structure                               |
//+------------------------------------------------------------------+
struct SCompressionSignal
{
    ENUM_TRADE_SIGNAL direction;
    double entryPrice;
    double stopLoss;
    double takeProfit;
    double confidence;
    string reason;
    int    squeezeBars;          // How long the squeeze has been active
    double hurstValue;           // Hurst exponent at breakout
    bool   isMomentumBreakout;   // H > 0.6 → trend breakout
    bool   isMeanRevFade;        // H < 0.4 → fade the breakout

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

//+------------------------------------------------------------------+
//| CRangeCompressionBreakout                                        |
//| Enhanced squeeze detection with Hurst regime awareness           |
//+------------------------------------------------------------------+
class CRangeCompressionBreakout : public CStrategyBase
{
private:
    // Configuration
    int    m_bbPeriod;           // Bollinger Band period (default: 20)
    double m_bbDeviation;        // BB deviation (default: 2.0)
    int    m_kcPeriod;           // Keltner Channel period (default: 20)
    double m_kcATRMultiple;      // KC ATR multiple (default: 1.5)
    int    m_atrPeriod;          // ATR period (default: 14)
    int    m_minSqueezeBars;     // Minimum bars in squeeze (default: 6)
    double m_hurstTrendThreshold;  // H > this = trending (default: 0.55)
    double m_hurstMRThreshold;     // H < this = mean-reverting (default: 0.45)
    double m_volumeConfirmRatio;   // Volume must be > ratio * avg (default: 1.5)
    int    m_volumeLookback;       // Bars for average volume (default: 20)

    // Indicator handles
    int m_bbHandle;
    int m_kcHandle;
    int m_atrHandle;
    int m_volumeHandle;

    // Hurst engine (injected)
    CHurstEngine* m_hurstEngine;

    // Risk Manager
    CUnifiedRiskManager* m_riskManager;

    // State
    bool   m_squeezeActive;
    int    m_squeezeBarCount;
    double m_lastBBUpper;
    double m_lastBBLower;
    double m_lastKCUpper;
    double m_lastKCLower;
    datetime m_lastSignalBar;
    datetime m_lastBarTime;

    string m_lastRejectReasonTag;
    datetime m_lastRejectLogTime;

    //--- Check if squeeze is active (BB inside Keltner)
    bool CheckSqueeze(double bbUpper, double bbLower, double kcUpper, double kcLower)
    {
        // Squeeze: BB is inside Keltner Channel
        return (bbUpper < kcUpper && bbLower > kcLower);
    }

    //--- Check volume confirmation
    bool CheckVolumeConfirmation()
    {
        long vol[];
        ArraySetAsSeries(vol, true);
        int copied = CopyTickVolume(m_symbol, m_timeframe, 0, m_volumeLookback + 1, vol);
        if(copied < m_volumeLookback + 1)
            return false;

        double avgVol = 0;
        for(int i = 1; i <= m_volumeLookback; i++)
            avgVol += (double)vol[i];
        avgVol /= (double)m_volumeLookback;

        return (avgVol > 0 && vol[0] > avgVol * m_volumeConfirmRatio);
    }

    void LogRejectEvent(const string reasonTag)
    {
        datetime nowTime = TimeCurrent();
        if(reasonTag == m_lastRejectReasonTag && (nowTime - m_lastRejectLogTime) <= 15)
            return;
        if((nowTime - m_lastRejectLogTime) < 5)
            return;

        PrintFormat("[COMPRESSION] Filtered: %s | Symbol=%s | TF=%s",
                   reasonTag, m_symbol, EnumToString(m_timeframe));
        m_lastRejectReasonTag = reasonTag;
        m_lastRejectLogTime = nowTime;
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
        m_bbHandle(INVALID_HANDLE),
        m_kcHandle(INVALID_HANDLE),
        m_atrHandle(INVALID_HANDLE),
        m_volumeHandle(INVALID_HANDLE),
        m_hurstEngine(NULL),
        m_riskManager(NULL),
        m_squeezeActive(false),
        m_squeezeBarCount(0),
        m_lastBBUpper(0),
        m_lastBBLower(0),
        m_lastKCUpper(0),
        m_lastKCLower(0),
        m_lastSignalBar(0),
        m_lastBarTime(0),
        m_lastRejectReasonTag(""),
        m_lastRejectLogTime(0)
    {
    }

    ~CRangeCompressionBreakout()
    {
        if(m_bbHandle != INVALID_HANDLE) IndicatorRelease(m_bbHandle);
        if(m_kcHandle != INVALID_HANDLE) IndicatorRelease(m_kcHandle);
        if(m_atrHandle != INVALID_HANDLE) IndicatorRelease(m_atrHandle);
        if(m_volumeHandle != INVALID_HANDLE) IndicatorRelease(m_volumeHandle);
    }

    //--- Initialize
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

        // Keltner Channel: built manually via ATR (MT5 doesn't have native KC)
        // We'll compute it from ATR in the signal method

        return (m_bbHandle != INVALID_HANDLE && m_atrHandle != INVALID_HANDLE);
    }

    //--- Configure
    void Configure(int bbPeriod = 20, double bbDev = 2.0, int kcPeriod = 20,
                   double kcATR = 1.5, int minSqueezeBars = 6,
                   double volRatio = 1.5)
    {
        m_bbPeriod = MathMax(10, bbPeriod);
        m_bbDeviation = MathMax(1.0, bbDev);
        m_kcPeriod = MathMax(10, kcPeriod);
        m_kcATRMultiple = MathMax(0.5, kcATR);
        m_minSqueezeBars = MathMax(3, minSqueezeBars);
        m_volumeConfirmRatio = MathMax(1.0, volRatio);
    }

    //--- Generate signal (called each bar)
    SCompressionSignal GetSignal()
    {
        SCompressionSignal signal;

        // Indicator checks
        if(m_bbHandle == INVALID_HANDLE || m_atrHandle == INVALID_HANDLE)
            return signal;

        // Get BB values
        double bbUpper[1], bbMiddle[1], bbLower[1];
        if(CopyBuffer(m_bbHandle, 1, 0, 1, bbUpper) != 1 ||
           CopyBuffer(m_bbHandle, 0, 0, 1, bbMiddle) != 1 ||
           CopyBuffer(m_bbHandle, 2, 0, 1, bbLower) != 1)
            return signal;

        // Get ATR for Keltner Channel
        double atr[1];
        if(CopyBuffer(m_atrHandle, 0, 0, 1, atr) != 1 || atr[0] <= 0)
            return signal;

        // Get close price
        double close[1];
        if(CopyClose(m_symbol, m_timeframe, 0, 1, close) != 1)
            return signal;

        // Compute Keltner Channel manually
        // KC Middle = EMA(20), KC Upper/Lower = EMA ± 1.5 * ATR
        double ema[];
        ArraySetAsSeries(ema, true);
        int copied = CopyClose(m_symbol, m_timeframe, 0, m_kcPeriod + 1, ema);
        if(copied < m_kcPeriod + 1)
            return signal;

        // EMA calculation: iterate from oldest to newest
        // ArraySetAsSeries: index 0 = most recent, index copied-1 = oldest
        double alpha = 2.0 / (double)(m_kcPeriod + 1);
        double emaVal = ema[copied - 1]; // Start with oldest value
        for(int i = copied - 2; i >= 0; i--)
            emaVal = alpha * ema[i] + (1.0 - alpha) * emaVal;

        double kcUpper = emaVal + m_kcATRMultiple * atr[0];
        double kcLower = emaVal - m_kcATRMultiple * atr[0];

        // Check squeeze state
        bool currentSqueeze = CheckSqueeze(bbUpper[0], bbLower[0], kcUpper, kcLower);

        if(currentSqueeze)
        {
            m_squeezeBarCount++;
            m_squeezeActive = true;
        }
        else
        {
            // Squeeze just released
            if(m_squeezeActive && m_squeezeBarCount >= m_minSqueezeBars)
            {
                // SQUEEZE BREAKOUT DETECTED
                m_squeezeActive = false;

                // Get Hurst exponent
                double hurst = 0.5;
                if(m_hurstEngine != NULL && m_hurstEngine.IsWarmedUp())
                    hurst = m_hurstEngine.GetHurstValue();

                // Determine breakout direction
                ENUM_TRADE_SIGNAL direction = TRADE_SIGNAL_NONE;
                bool isMomentum = false;
                bool isFade = false;

                if(close[0] > bbUpper[0])
                {
                    // Upside breakout
                    if(hurst > m_hurstTrendThreshold)
                    {
                        // Trending regime → follow the breakout
                        direction = TRADE_SIGNAL_BUY;
                        isMomentum = true;
                    }
                    else if(hurst < m_hurstMRThreshold)
                    {
                        // Mean-reverting regime → fade the breakout
                        direction = TRADE_SIGNAL_SELL;
                        isFade = true;
                    }
                    else
                    {
                        // Random walk → follow with lower confidence
                        direction = TRADE_SIGNAL_BUY;
                        isMomentum = true;
                    }
                }
                else if(close[0] < bbLower[0])
                {
                    // Downside breakout
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

                // Volume confirmation
                if(!CheckVolumeConfirmation())
                {
                    LogRejectEvent("NO_VOLUME_CONFIRM");
                    return signal;
                }

                // Same-bar filter
                datetime currentBarTime = iTime(m_symbol, m_timeframe, 1);
                if(currentBarTime == m_lastSignalBar)
                {
                    LogRejectEvent("SAME_BAR");
                    return signal;
                }

                // Build signal
                signal.direction = direction;
                signal.entryPrice = close[0];
                signal.squeezeBars = m_squeezeBarCount;
                signal.hurstValue = hurst;
                signal.isMomentumBreakout = isMomentum;
                signal.isMeanRevFade = isFade;

                // SL/TP based on breakout type
                if(isMomentum)
                {
                    // Momentum: wider SL below KC, target 2x squeeze range
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
                // Squeeze ended but too short
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

    //--- Standard interface
    ENUM_STRATEGY_TYPE GetStrategyType() const { return STRATEGY_MOMENTUM; }
    string GetStrategyName() const { return "RangeCompressionBreakout"; }
};

#endif // RANGE_COMPRESSION_BREAKOUT_MQH
