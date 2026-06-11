//+------------------------------------------------------------------+
//| SyntheticSpikeMonitor.mqh - Synthetic tick spike detection        |
//| Encapsulates spike detection, trading pause, and emergency        |
//| drawdown stop logic extracted from MultiStrategyAutonomousEA.mq5  |
//+------------------------------------------------------------------+
#ifndef __SYNTHETIC_SPIKE_MONITOR_MQH__
#define __SYNTHETIC_SPIKE_MONITOR_MQH__

#include "..\Utils\Instruments.mqh"
#include "..\Trading\TradeManager.mqh"
#include "..\Risk\UnifiedRiskManager.mqh"
#include "..\..\IndicatorManager.mqh"
#include "TickSafetyMonitor.mqh"

// Magic number range constants (must match main EA definitions)
#define SPIKE_MAGIC_SYMBOL_MULTIPLIER 100
#define SPIKE_MAGIC_MAX_CLUSTER_CODE  99

//+------------------------------------------------------------------+
//| Synthetic Spike Monitor Class                                     |
//+------------------------------------------------------------------+
class CSyntheticSpikeMonitor
{
private:
    // --- Spike detection state ---
    datetime m_tickRateWindowStart;
    int      m_tickRateWindowCount;
    double   m_tickRateBaseline;
    datetime m_spikeConfirmStart;
    int      m_spikeConfirmCount;

    // --- Trading pause state ---
    bool     m_tradingPaused;
    datetime m_tradingPauseUntil;

    // --- External dependencies ---
    CTradeManager*       m_tradeManager;
    CUnifiedRiskManager* m_riskManager;
    CTickSafetyMonitor*  m_tickSafetyMonitor;

    // --- Magic number range for EA ownership check ---
    int      m_magicNumber;
    int      m_symbolCount;

    // --- Spike event counter ---
    ulong    m_spikeEventCount;

public:
    CSyntheticSpikeMonitor() :
        m_tickRateWindowStart(0),
        m_tickRateWindowCount(0),
        m_tickRateBaseline(0.0),
        m_spikeConfirmStart(0),
        m_spikeConfirmCount(0),
        m_tradingPaused(false),
        m_tradingPauseUntil(0),
        m_tradeManager(NULL),
        m_riskManager(NULL),
        m_tickSafetyMonitor(NULL),
        m_magicNumber(0),
        m_symbolCount(1),
        m_spikeEventCount(0)
    {
    }

    ~CSyntheticSpikeMonitor() {}

    //--- Initialization
    void Initialize(CTradeManager& tradeMgr, CUnifiedRiskManager& riskMgr, CTickSafetyMonitor& tickSafety)
    {
        m_tradeManager       = &tradeMgr;
        m_riskManager        = &riskMgr;
        m_tickSafetyMonitor  = &tickSafety;
    }

    //--- Magic number configuration (call from OnInit)
    void SetMagicNumber(int magicNumber) { m_magicNumber = magicNumber; }
    void SetSymbolCount(int symbolCount) { m_symbolCount = (symbolCount > 0) ? symbolCount : 1; }

    //--- Check if a magic number falls within this EA's ownership range
    bool IsEAOwnedMagic(long magic) const
    {
        int maxMagic = m_magicNumber + m_symbolCount * SPIKE_MAGIC_SYMBOL_MULTIPLIER + SPIKE_MAGIC_MAX_CLUSTER_CODE;
        return (magic >= m_magicNumber && magic <= maxMagic);
    }

    //--- Trading pause methods
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

        datetime now = TimeCurrent();
        if(now < m_tradingPauseUntil)
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

    datetime GetPauseUntilTime() const { return m_tradingPauseUntil; }

    //--- Emergency drawdown stop (renamed from HandleEmergencyDrawdownStop)
    // Returns true if emergency was triggered; caller must set tradingEnabled=false
    bool HandleEmergencyDrawdown(const string reasonTag,
                                  const double spikeCurrentDD,
                                  const double spikeMaxDD,
                                  const bool flattenAllAccountPositions)
    {
        if(spikeCurrentDD <= spikeMaxDD)
            return false;

        // Check market volatility before closing positions
        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket == 0 || !PositionSelectByTicket(ticket))
                continue;

            string posSymbol = PositionGetString(POSITION_SYMBOL);
            double atr = 0;
            // Resolve ATR inline using CIndicatorManager (replaces global TryResolveAtrValue)
            {
                CIndicatorManager* indMgr = CIndicatorManager::Instance();
                int atrHandle = INVALID_HANDLE;
                if(indMgr != NULL)
                    atrHandle = indMgr.GetATRHandle(posSymbol, PERIOD_CURRENT, 14);
                double atrBuf[];
                ArraySetAsSeries(atrBuf, true);
                if(atrHandle != INVALID_HANDLE && CopyBuffer(atrHandle, 0, 0, 1, atrBuf) > 0 && atrBuf[0] > 0.0)
                    atr = atrBuf[0];
            }
            double currentPrice = SymbolInfoDouble(posSymbol, SYMBOL_BID);

            if(atr > 0 && currentPrice > 0)
            {
                double normalizedAtr = atr / currentPrice;
                if(normalizedAtr > 0.05) // 5% volatility is very high
                {
                    PrintFormat("[EMERGENCY-WARNING] High volatility detected for %s (ATR: %.2f%%)", posSymbol, normalizedAtr * 100);
                }
            }
        }

        Alert("[EMERGENCY] Maximum drawdown exceeded! Trading halted!");
        Comment("EMERGENCY STOP - Drawdown: ", NormalizeDouble(spikeCurrentDD, 2), "%");

        int closedCount = 0;
        int skippedCount = 0;
        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket == 0 || !PositionSelectByTicket(ticket))
                continue;

            bool shouldClose = flattenAllAccountPositions ||
                               IsEAOwnedMagic(PositionGetInteger(POSITION_MAGIC));
            if(shouldClose)
            {
                if(m_tradeManager.ClosePosition(ticket, "Emergency Stop"))
                    closedCount++;
            }
            else
            {
                skippedCount++;
            }
        }

        PrintFormat("[EMERGENCY] Flatten completed | reason=%s | closed=%d | skipped=%d | account_wide=%s",
                    reasonTag,
                    closedCount,
                    skippedCount,
                    flattenAllAccountPositions ? "true" : "false");
        return true;
    }

    //--- Spike alarm trigger (renamed from TriggerSyntheticSpikeAlarm)
    // Returns true if alarm was triggered; caller should increment g_hbSyntheticSpikeEvents
    bool TriggerSpikeAlarm(const double currentRate, const double baselineRate,
                            const double velocityMultiplier, const int pauseSeconds,
                            const bool flattenAllAccountPositions)
    {
        m_spikeEventCount++;
        PrintFormat("[SPIKE-ALARM] %s | rate=%.2f ticks/sec | baseline=%.2f | multiplier=%.2f",
                    _Symbol,
                    currentRate,
                    baselineRate,
                    velocityMultiplier);

        int closedCount = 0;
        int skippedCount = 0;
        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket == 0 || !PositionSelectByTicket(ticket))
                continue;

            string positionSymbol = PositionGetString(POSITION_SYMBOL);
            bool ownPosition = IsEAOwnedMagic(PositionGetInteger(POSITION_MAGIC));
            bool shouldClose = flattenAllAccountPositions ||
                               (ownPosition && positionSymbol == _Symbol);
            if(shouldClose)
            {
                if(m_tradeManager.ClosePosition(ticket, "Synthetic spike alarm"))
                    closedCount++;
            }
            else
            {
                skippedCount++;
            }
        }

        PrintFormat("[SPIKE-ALARM] Flatten completed | symbol=%s | closed=%d | skipped=%d | account_wide=%s",
                    _Symbol,
                    closedCount,
                    skippedCount,
                    flattenAllAccountPositions ? "true" : "false");

        ActivatePause("synthetic_spike_alarm", pauseSeconds);
        return true;
    }

    //--- Evaluate synthetic spike alarm (renamed from EvaluateSyntheticSpikeAlarm)
    void EvaluateSpike(const double velocityMultiplier, const int confirmWindows,
                        const int pauseSeconds, const bool flattenAllAccountPositions)
    {
        if(velocityMultiplier <= 0.0)
            return;

        if(!IsSyntheticIndexSymbolName(_Symbol))
            return;

        MqlTick tick;
        if(m_tickSafetyMonitor == NULL || !m_tickSafetyMonitor.ValidateTick(_Symbol, tick))
            return;

        datetime now = TimeCurrent();
        if(m_tickRateWindowStart == 0)
        {
            m_tickRateWindowStart = now;
            m_tickRateWindowCount = 0;
            m_tickRateBaseline = 0.0;
        }

        m_tickRateWindowCount++;
        int elapsedSeconds = (int)(now - m_tickRateWindowStart);
        if(elapsedSeconds < 1)
            return;

        double currentRate = (double)m_tickRateWindowCount / (double)MathMax(1, elapsedSeconds);
        double baselineRate = (m_tickRateBaseline > 0.0) ? m_tickRateBaseline : currentRate;
        double thresholdRate = MathMax(1.0, baselineRate) * MathMax(1.5, velocityMultiplier);

        m_tickRateBaseline = (m_tickRateBaseline <= 0.0)
                              ? currentRate
                              : ((m_tickRateBaseline * 0.85) + (currentRate * 0.15));
        m_tickRateWindowStart = now;
        m_tickRateWindowCount = 0;

        bool rateExceedsThreshold = (currentRate > thresholdRate);
        int requiredConfirmWindows = MathMax(1, confirmWindows);

        if(IsPaused())
        {
            m_spikeConfirmCount = 0;
            m_spikeConfirmStart = 0;
            return;
        }

        if(rateExceedsThreshold)
        {
            if(m_spikeConfirmCount == 0)
            {
                m_spikeConfirmStart = now;
                m_spikeConfirmCount = 1;
                PrintFormat("[SYNTHETIC-SPIKE] Potential spike detected | Rate: %.1f/sec | Threshold: %.1f/sec | Confirming (Window 1/%d)",
                            currentRate, thresholdRate, requiredConfirmWindows);
            }
            else
            {
                m_spikeConfirmCount++;
                if(m_spikeConfirmCount >= requiredConfirmWindows)
                {
                    PrintFormat("[SYNTHETIC-SPIKE] Spike confirmed! | Rate: %.1f/sec | Threshold: %.1f/sec | Consecutive windows: %d",
                                currentRate, thresholdRate, m_spikeConfirmCount);
                    TriggerSpikeAlarm(currentRate, MathMax(1.0, baselineRate),
                                      velocityMultiplier, pauseSeconds, flattenAllAccountPositions);
                    m_spikeConfirmCount = 0;
                    m_spikeConfirmStart = 0;
                }
                else
                {
                    PrintFormat("[SYNTHETIC-SPIKE] Continuing confirmation | Rate: %.1f/sec | Window %d/%d",
                                currentRate, m_spikeConfirmCount, requiredConfirmWindows);
                }
            }
        }
        else
        {
            if(m_spikeConfirmCount > 0)
            {
                PrintFormat("[SYNTHETIC-SPIKE] Confirmation reset | Rate: %.1f/sec | Below threshold: %.1f/sec",
                            currentRate, thresholdRate);
            }
            m_spikeConfirmCount = 0;
            m_spikeConfirmStart = 0;
        }
    }

    //--- Process tick safety (renamed from ProcessTickSafetyLoop)
    // Handles spike-specific tick safety: pause release, spike evaluation, emergency drawdown.
    // Returns true if emergency drawdown stop was triggered; caller must set tradingEnabled=false.
    // Non-spike operations (RefreshAccountRuntimeMetrics, CheckPendingConfirmations, etc.)
    // remain in the main EA's ProcessTickSafetyLoop() which calls this method.
    bool ProcessTickSafety(const double spikeCurrentDD,
                            const double spikeMaxDD,
                            const bool flattenAllAccountPositions,
                            const double velocityMultiplier,
                            const int confirmWindows,
                            const int pauseSeconds)
    {
        ReleasePauseIfExpired();

        if(m_tickSafetyMonitor == NULL || !m_tickSafetyMonitor.IsTradingAllowed())
            return false;

        MqlTick tick;
        if(!m_tickSafetyMonitor.ValidateTick(_Symbol, tick))
            return false;

        m_riskManager.RefreshRuntimeState();
        EvaluateSpike(velocityMultiplier, confirmWindows, pauseSeconds, flattenAllAccountPositions);

        if(HandleEmergencyDrawdown("tick", spikeCurrentDD, spikeMaxDD, flattenAllAccountPositions))
            return true;

        return false;
    }

    //--- Accessors
    ulong GetSpikeEventCount() const { return m_spikeEventCount; }
    void  ResetSpikeEventCount() { m_spikeEventCount = 0; }
};

#endif // __SYNTHETIC_SPIKE_MONITOR_MQH__
