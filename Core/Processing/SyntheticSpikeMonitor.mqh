// SyntheticSpikeMonitor.mqh - synthetic-index tick-rate spikes and the entry pause they raise
// Detection only: flattening stays with CRiskCircuitBreaker and its CloseAllPositions call sites.
#ifndef SYNTHETIC_SPIKE_MONITOR_MQH
#define SYNTHETIC_SPIKE_MONITOR_MQH

#include "..\Utils\Instruments.mqh"

struct SSpikeSymbolWindow
{
    string   symbol;
    datetime windowStart;
    long     windowStartVolume;
    double   rateBaseline;
    int      confirmCount;
};

class CSyntheticSpikeMonitor
{
private:
    SSpikeSymbolWindow m_windows[];
    int      m_windowCount;

    bool     m_tradingPaused;
    datetime m_tradingPauseUntil;

public:
    CSyntheticSpikeMonitor() :
        m_windowCount(0),
        m_tradingPaused(false),
        m_tradingPauseUntil(0)
    {
    }

    //--- Trading pause
    void ActivatePause(const string reason, const int seconds)
    {
        int pauseSeconds = MathMax(5, seconds);
        m_tradingPaused = true;
        m_tradingPauseUntil = TimeCurrent() + pauseSeconds;
        PrintFormat("[SPIKE-PAUSE] Activated | reason=%s | pause_seconds=%d | until=%s",
                    reason,
                    pauseSeconds,
                    TimeToString(m_tradingPauseUntil, TIME_SECONDS));
    }

    void ReleasePauseIfExpired()
    {
        if(!m_tradingPaused)
            return;

        if(TimeCurrent() < m_tradingPauseUntil)
            return;

        m_tradingPaused = false;
        m_tradingPauseUntil = 0;
        Print("[SPIKE-PAUSE] Trading pause expired; new entries re-enabled");
    }

    bool IsPaused()
    {
        ReleasePauseIfExpired();
        return m_tradingPaused;
    }

    //--- Deriv synthetics only: their feed runs on a fixed tick cadence, so a rate jump is a data event.
    //--- FX and crypto tick volume tracks the session, so those symbols would alarm on every busy bar.
    void RegisterSymbol(const string symbol)
    {
        if(!IsSyntheticIndexSymbolName(symbol))
            return;

        for(int i = 0; i < m_windowCount; i++)
        {
            if(m_windows[i].symbol == symbol)
                return;
        }

        int n = m_windowCount;
        ArrayResize(m_windows, n + 1);
        m_windows[n].symbol = symbol;
        m_windows[n].windowStart = 0;
        m_windows[n].windowStartVolume = 0;
        m_windows[n].rateBaseline = 0.0;
        m_windows[n].confirmCount = 0;
        m_windowCount = n + 1;
    }

    //--- One pass over the registered symbols; returns how many alarms this pass raised.
    int EvaluateSpikes(const double velocityMultiplier, const int confirmWindows, const int pauseSeconds)
    {
        if(velocityMultiplier <= 0.0 || m_windowCount == 0)
            return 0;

        int requiredConfirmWindows = MathMax(1, confirmWindows);
        int alarms = 0;
        datetime now = TimeCurrent();

        for(int i = 0; i < m_windowCount; i++)
        {
            // M1 tick volume is the terminal's own tick count, so the delta between two reads is real
            // ticks even though only the chart symbol delivers an OnTick for each one.
            long barVolume = iVolume(m_windows[i].symbol, PERIOD_M1, 0);
            if(barVolume <= 0)
                continue;

            if(m_windows[i].windowStart == 0)
            {
                m_windows[i].windowStart = now;
                m_windows[i].windowStartVolume = barVolume;
                continue;
            }

            int elapsedSeconds = (int)(now - m_windows[i].windowStart);
            if(elapsedSeconds < 1)
                continue;

            long tickDelta = barVolume - m_windows[i].windowStartVolume;
            m_windows[i].windowStart = now;
            m_windows[i].windowStartVolume = barVolume;

            // A negative delta means the M1 bar rolled and the count restarted, so this window has no rate.
            // The baseline survives: a bar rolls every 60 s, and clearing it would leave a one-window seed.
            if(tickDelta < 0)
            {
                m_windows[i].confirmCount = 0;
                continue;
            }

            // A stalled loop (weekend gap, terminal restart) divides one bar's ticks by hours, so the rate
            // is not a cadence and the baseline has to be re-seeded or the next live second reads as a spike.
            if(elapsedSeconds > 5)
            {
                m_windows[i].confirmCount = 0;
                m_windows[i].rateBaseline = 0.0;
                continue;
            }

            double currentRate = (double)tickDelta / (double)elapsedSeconds;

            if(m_windows[i].rateBaseline <= 0.0)
                m_windows[i].rateBaseline = currentRate;
            else
                m_windows[i].rateBaseline = m_windows[i].rateBaseline * 0.85 + currentRate * 0.15;

            double thresholdRate = MathMax(1.0, m_windows[i].rateBaseline) * MathMax(1.5, velocityMultiplier);

            if(IsPaused())
            {
                m_windows[i].confirmCount = 0;
                continue;
            }

            if(currentRate <= thresholdRate)
            {
                if(m_windows[i].confirmCount > 0)
                    PrintFormat("[SYNTHETIC-SPIKE] %s | Confirmation reset | Rate: %.1f/sec | Below threshold: %.1f/sec",
                                m_windows[i].symbol, currentRate, thresholdRate);
                m_windows[i].confirmCount = 0;
                continue;
            }

            m_windows[i].confirmCount++;

            if(m_windows[i].confirmCount < requiredConfirmWindows)
            {
                PrintFormat("[SYNTHETIC-SPIKE] %s | Potential spike | Rate: %.1f/sec | Threshold: %.1f/sec | Confirming (Window %d/%d)",
                            m_windows[i].symbol, currentRate, thresholdRate,
                            m_windows[i].confirmCount, requiredConfirmWindows);
                continue;
            }

            PrintFormat("[SYNTHETIC-SPIKE] %s | Spike confirmed! | Rate: %.1f/sec | Threshold: %.1f/sec | Consecutive windows: %d",
                        m_windows[i].symbol, currentRate, thresholdRate, m_windows[i].confirmCount);
            PrintFormat("[SPIKE-ALARM] %s | rate=%.2f ticks/sec | baseline=%.2f | multiplier=%.2f | entries_paused=%ds | open_positions_untouched",
                        m_windows[i].symbol, currentRate, MathMax(1.0, m_windows[i].rateBaseline),
                        velocityMultiplier, MathMax(5, pauseSeconds));
            m_windows[i].confirmCount = 0;
            ActivatePause("synthetic_spike_alarm", pauseSeconds);
            alarms++;
        }

        return alarms;
    }

    int GetRegisteredSymbolCount() const { return m_windowCount; }
};

#endif // SYNTHETIC_SPIKE_MONITOR_MQH
