//+------------------------------------------------------------------+
//| RiskCircuitBreaker.mqh                                           |
//| Drawdown / daily-loss circuit breakers plus graduated            |
//| auto-recovery and emergency-close escalation state.              |
//|                                                                  |
//| Extracted verbatim from CUnifiedRiskManager (Phase E2, E-F):     |
//|   m_tradingEnabled, m_peakEquity, m_maxDrawdownFromPeak,         |
//|   m_drawdownBreachCount, m_dailyLossHaltActive,                  |
//|   m_dailyLossHaltDate, m_cbTriggeredAt, m_cbRecoveryAttempts,    |
//|   m_cbMaxRecoveryAttempts, m_cbRecoveryCooldownMin,              |
//|   m_cbLastRecoverySuccessTime, m_cbRecoveryLevel,                |
//|   m_emergencyCloseRequested                                      |
//|                                                                  |
//|   CUnifiedRiskManager::CheckDrawdownCircuitBreaker               |
//|   CUnifiedRiskManager::CheckCircuitBreakerRecovery               |
//|   CUnifiedRiskManager::CheckDailyLossLimit (P&L half)            |
//|   CUnifiedRiskManager::ResetCircuitBreaker                       |
//|   CUnifiedRiskManager::RestoreCircuitBreakerState                |
//|   + all circuit-breaker getters                                  |
//|                                                                  |
//| Behaviour is byte-identical to the original member functions;    |
//| CUnifiedRiskManager keeps thin forwarders with the original      |
//| signatures so that all call sites remain unchanged.              |
//|                                                                  |
//| OWNERSHIP NOTES (deliberately NOT moved here, to avoid           |
//| back-pointers and to keep behaviour identical):                  |
//|  * m_config           -> thresholds are passed in as arguments.  |
//|  * m_initialized      -> the `if(!m_initialized)` guards stay in |
//|                          the forwarders.                         |
//|  * m_conservativeMode -> shared with adaptive sizing / snapshot; |
//|                          passed in by reference where mutated.   |
//|  * m_dailyStartEquity -> shared with daily budget accounting;    |
//|                          passed in by value / by reference.      |
//|  * IsNewTradingDay()  -> mutates m_lastTradingDayKey, so it must |
//|                          keep its original short-circuit         |
//|                          evaluation order in the owner.          |
//+------------------------------------------------------------------+
#ifndef CORE_RISK_RISK_CIRCUIT_BREAKER_MQH
#define CORE_RISK_RISK_CIRCUIT_BREAKER_MQH

#include "../Utils/MagicRange.mqh"

//+------------------------------------------------------------------+
//| Circuit breaker state holder (stateful, owned by value)          |
//+------------------------------------------------------------------+
class CRiskCircuitBreaker
{
private:
    // Drawdown circuit breaker (Batch 93 - Week 1)
    bool     m_tradingEnabled;           // Master switch for trading
    double   m_peakEquity;               // Highest equity reached
    double   m_maxDrawdownFromPeak;      // Current max drawdown from peak
    int      m_drawdownBreachCount;      // Number of times drawdown limit hit

    // Daily P&L Loss Limit circuit breaker
    bool     m_dailyLossHaltActive;      // Daily loss halt is active
    datetime m_dailyLossHaltDate;        // Date when halt was triggered (for reset on new day)

    // Circuit Breaker Auto-Recovery (Phase 2.4)
    datetime m_cbTriggeredAt;            // When circuit breaker was triggered
    int      m_cbRecoveryAttempts;       // Number of auto-recovery attempts made
    int      m_cbMaxRecoveryAttempts;    // Max auto-recovery attempts (default 3)
    int      m_cbRecoveryCooldownMin;    // Cooldown in minutes before recovery attempt (default 30)
    datetime m_cbLastRecoverySuccessTime;// When last successful recovery occurred (for reset after stable period)
    int      m_cbRecoveryLevel;          // Graduated recovery level: 0=halted, 1=partial(75%), 2=full(50%)

    // Emergency close flag for circuit breaker 2nd+ breach
    bool     m_emergencyCloseRequested;

public:
    //--- Constructor performs the zero-init that used to live in the
    //--- CUnifiedRiskManager initialiser list (identical values).
    CRiskCircuitBreaker() :
        m_tradingEnabled(true),
        m_peakEquity(0.0),
        m_maxDrawdownFromPeak(0.0),
        m_drawdownBreachCount(0),
        m_dailyLossHaltActive(false),
        m_dailyLossHaltDate(0),
        m_cbTriggeredAt(0),
        m_cbRecoveryAttempts(0),
        m_cbMaxRecoveryAttempts(3),
        m_cbRecoveryCooldownMin(5),
        m_cbLastRecoverySuccessTime(0),
        m_cbRecoveryLevel(0),
        m_emergencyCloseRequested(false)
    {
    }

    ~CRiskCircuitBreaker()
    {
        // No owned resources.
    }

    //+--------------------------------------------------------------+
    //| Lifecycle                                                     |
    //+--------------------------------------------------------------+

    //--- Re-arm the breaker at CUnifiedRiskManager::Initialize time.
    //--- Mirrors the original inline block verbatim.
    void InitializeState(const double dailyStartEquity)
    {
        // ENHANCEMENT: Initialize drawdown circuit breaker (Batch 93 - Week 1)
        m_peakEquity = dailyStartEquity;
        m_maxDrawdownFromPeak = 0.0;
        m_drawdownBreachCount = 0;
        m_tradingEnabled = true;
        m_cbTriggeredAt = 0;
        m_cbRecoveryAttempts = 0;
        m_cbRecoveryLevel = 0;

        // Daily P&L Loss Limit circuit breaker
        m_dailyLossHaltActive = false;
        m_dailyLossHaltDate = 0;
    }

    //--- Peak / drawdown refresh performed on every runtime cycle.
    //--- Mirrors the original inline block in RefreshRuntimeState verbatim.
    void RefreshPeakAndDrawdown()
    {
        // Update peak equity and drawdown from peak - ensures m_maxDrawdownFromPeak is always current
        double equityNow = AccountInfoDouble(ACCOUNT_EQUITY);
        if(equityNow > m_peakEquity)
        {
            m_peakEquity = equityNow;
            m_maxDrawdownFromPeak = 0.0;
        }
        else if(m_peakEquity > 0 && equityNow > 0)
        {
            m_maxDrawdownFromPeak = ((m_peakEquity - equityNow) / m_peakEquity) * 100.0;
        }
    }

    //--- Reset the auto-recovery counter when a new trading day starts.
    //--- Mirrors the original inline block in CheckAndResetDailyLimits verbatim.
    void ResetRecoveryCounterForNewDay()
    {
        // Reset circuit breaker recovery counter on new trading day
        if(m_cbRecoveryAttempts > 0)
        {
            PrintFormat("[RISK-UNIFIED] Daily reset: circuit breaker recovery counter %d->0", m_cbRecoveryAttempts);
            m_cbRecoveryAttempts = 0;
            m_cbLastRecoverySuccessTime = 0;
        }
    }

    //+--------------------------------------------------------------+
    //| Drawdown circuit breaker                                      |
    //+--------------------------------------------------------------+

    //--- ENHANCEMENT: Drawdown Circuit Breaker (Batch 93 - Week 1)
    //--- Checks if drawdown from peak equity exceeds limits.
    //--- Returns: true if trading is allowed, false if circuit breaker hit.
    //--- `conservativeMode` is the owner's shared conservative-mode flag.
    bool CheckDrawdownCircuitBreaker(const double drawdownWarningPercent,
                                     const double drawdownCriticalPercent,
                                     bool &conservativeMode)
    {
        double equityNow = AccountInfoDouble(ACCOUNT_EQUITY);

        // Update peak equity tracking
        if(equityNow > m_peakEquity)
        {
            m_peakEquity = equityNow;
            m_maxDrawdownFromPeak = 0.0;
        }

        // Calculate current drawdown from peak
        if(m_peakEquity > 0)
        {
            m_maxDrawdownFromPeak = ((m_peakEquity - equityNow) / m_peakEquity) * 100.0;  // Blueprint 10.4: * 100.0 converts fraction to 0-100 scale
        }

        // Check critical drawdown limit - HARD STOP
        if(m_maxDrawdownFromPeak >= drawdownCriticalPercent)
        {
            if(m_tradingEnabled)
            {
                m_tradingEnabled = false;
                m_drawdownBreachCount++;
                m_cbTriggeredAt = TimeCurrent();
                m_cbRecoveryLevel = 0; // Reset graduated recovery level on new halt

                PrintFormat("[RISK-CIRCUIT-BREAKER] CRITICAL BREACH | Drawdown=%.2f%% >= Limit=%.2f%% | Trading HALTED",
                           m_maxDrawdownFromPeak, drawdownCriticalPercent);
                PrintFormat("[RISK-CIRCUIT-BREAKER] Peak Equity=%.2f | Current Equity=%.2f | Loss=%.2f",
                           m_peakEquity, equityNow, m_peakEquity - equityNow);
                PrintFormat("[RISK-CIRCUIT-BREAKER] Breach count: %d | Auto-recovery will be attempted after %d min cooldown (max %d attempts)",
                           m_drawdownBreachCount, m_cbRecoveryCooldownMin, m_cbMaxRecoveryAttempts);

                // P1: On 2nd or subsequent breach, close all positions to stop bleeding
                if(m_drawdownBreachCount >= 2)
                {
                    PrintFormat("[RISK-CIRCUIT-BREAKER] SECOND+ BREACH - EMERGENCY CLOSING ALL POSITIONS!");
                    m_emergencyCloseRequested = true;
                }

                // P1: Emergency exit trigger - if drawdown exceeds 2x critical threshold, close everything
                double emergencyThreshold = drawdownCriticalPercent * 2.0;
                if(m_maxDrawdownFromPeak >= emergencyThreshold)
                {
                    PrintFormat("[RISK-EMERGENCY-EXIT] Drawdown %.2f%% exceeds 2x critical %.2f%% - EMERGENCY CLOSING ALL POSITIONS!",
                               m_maxDrawdownFromPeak, drawdownCriticalPercent);
                    m_emergencyCloseRequested = true;
                    m_tradingEnabled = false;
                }
            }
            return false;
        }

        // Check warning drawdown limit - Reduce position sizes by 50%
        if(m_maxDrawdownFromPeak >= drawdownWarningPercent && m_maxDrawdownFromPeak < drawdownCriticalPercent)
        {
            if(conservativeMode == false)
            {
                conservativeMode = true;

                PrintFormat("[RISK-CIRCUIT-BREAKER] WARNING | Drawdown=%.2f%% >= Warning=%.2f%% | Position sizes reduced 50%%",
                           m_maxDrawdownFromPeak, drawdownWarningPercent);
                PrintFormat("[RISK-CIRCUIT-BREAKER] Peak Equity=%.2f | Current Equity=%.2f",
                           m_peakEquity, equityNow);
            }
            // Still allow trading but in conservative mode
            return true;
        }

        // Reset conservative mode if drawdown recovers below 60% of critical (closes gap with 50% trading-resume threshold)
        if(m_maxDrawdownFromPeak < drawdownCriticalPercent * 0.6 && conservativeMode)
        {
            conservativeMode = false;
            PrintFormat("[RISK-CIRCUIT-BREAKER] Recovery | Drawdown=%.2f%% < threshold=%.2f%% | Normal mode restored",
                       m_maxDrawdownFromPeak, drawdownCriticalPercent * 0.6);
        }

        // Reset recovery counter after stable period - equity must stay below warning for 60 minutes
        if(m_cbRecoveryAttempts > 0 && m_cbLastRecoverySuccessTime > 0 &&
           m_maxDrawdownFromPeak < drawdownWarningPercent * 0.5)
        {
            int stableMinutes = (int)((TimeCurrent() - m_cbLastRecoverySuccessTime) / 60);
            if(stableMinutes >= 60)
            {
                PrintFormat("[RISK-CIRCUIT-BREAKER] Recovery counter reset | Stable for %d min (>=60) | Attempts %d->0",
                           stableMinutes, m_cbRecoveryAttempts);
                m_cbRecoveryAttempts = 0;
                m_cbLastRecoverySuccessTime = 0;
            }
        }

        return true;
    }

    //--- Manually reset circuit breaker (after review).
    void ResetCircuitBreaker(bool &conservativeMode)
    {
        m_tradingEnabled = true;
        conservativeMode = false;
        m_drawdownBreachCount = 0;
        m_cbTriggeredAt = 0;
        m_cbRecoveryAttempts = 0;
        m_cbRecoveryLevel = 0;
        m_cbLastRecoverySuccessTime = 0;

        // Reset peak to current equity
        m_peakEquity = AccountInfoDouble(ACCOUNT_EQUITY);
        m_maxDrawdownFromPeak = 0.0;

        Print("[RISK-CIRCUIT-BREAKER] Manually reset by operator | Trading resumed");
    }

    //--- Restore circuit breaker state from crash recovery file.
    //--- `dailyStartEquity` is the owner's shared daily-start equity field.
    //--- Batch 168: the halt flags are now part of the restore. They were not
    //--- persisted at all, so any restart (recompile, param change, VPS reboot)
    //--- silently re-armed a daily-loss halt that had already been earned, letting
    //--- the EA trade a second full daily budget on the same day.
    void RestoreCircuitBreakerState(const double savedPeakEquity,
                                    const double savedDailyStartEquity,
                                    const int savedBreachCount,
                                    const double savedMaxDrawdown,
                                    const bool restoreDailyLossHalt,
                                    const bool restoreTradingHalt,
                                    double &dailyStartEquity)
    {
        if(savedPeakEquity > 0.0)
            m_peakEquity = savedPeakEquity;
        if(savedDailyStartEquity > 0.0)
            dailyStartEquity = savedDailyStartEquity;
        m_drawdownBreachCount = savedBreachCount;
        if(savedMaxDrawdown >= 0.0)
            m_maxDrawdownFromPeak = savedMaxDrawdown;

        if(restoreDailyLossHalt)
        {
            m_dailyLossHaltActive = true;
            m_dailyLossHaltDate   = TimeCurrent();
        }
        if(restoreTradingHalt)
        {
            m_tradingEnabled = false;
            m_cbTriggeredAt  = TimeCurrent();
        }

        PrintFormat("[RISK-CIRCUIT-BREAKER] Restored from crash recovery | peakEquity=%.2f | dailyStartEquity=%.2f | breachCount=%d | maxDD=%.2f%% | dailyHalt=%s | tradingHalted=%s",
                    m_peakEquity, dailyStartEquity, m_drawdownBreachCount, m_maxDrawdownFromPeak,
                    restoreDailyLossHalt ? "ACTIVE" : "clear",
                    m_tradingEnabled ? "enabled" : "HALTED");
    }

    //+--------------------------------------------------------------+
    //| Auto-recovery                                                 |
    //+--------------------------------------------------------------+

    //--- Circuit Breaker Auto-Recovery (Phase 2.4).
    //--- Attempts to re-enable trading after cooldown if drawdown recovers.
    //--- L5-010 FIX: Uses bar-based cooldown instead of wall-clock minutes.
    bool CheckCircuitBreakerRecovery(const double drawdownCriticalPercent,
                                     bool &conservativeMode)
    {
        // Only attempt recovery if circuit breaker is active
        if(m_tradingEnabled)
            return false;

        // No trigger time recorded - nothing to recover from
        if(m_cbTriggeredAt <= 0)
            return false;

        // L5-010: Check if cooldown period has elapsed using BAR-BASED timing
        // This works correctly across weekends and session breaks
        int barsSinceTrigger = iBarShift(_Symbol, PERIOD_CURRENT, m_cbTriggeredAt, false);
        if(barsSinceTrigger < 0)
        {
            // Fallback to wall-clock if bar shift fails
            int elapsedMinutes = (int)((TimeCurrent() - m_cbTriggeredAt) / 60);
            if(elapsedMinutes < m_cbRecoveryCooldownMin)
                return false;
        }
        else if(barsSinceTrigger < m_cbRecoveryCooldownMin)
        {
            // Not enough bars have passed
            return false;
        }

        // Check if max recovery attempts exhausted
        if(m_cbRecoveryAttempts >= m_cbMaxRecoveryAttempts)
        {
            static datetime s_lastMaxAttemptLog = 0;
            datetime now = TimeCurrent();
            if(s_lastMaxAttemptLog == 0 || (now - s_lastMaxAttemptLog) >= 300)
            {
                PrintFormat("[RISK-CIRCUIT-BREAKER] Max recovery attempts reached (%d/%d) | Manual reset required",
                           m_cbRecoveryAttempts, m_cbMaxRecoveryAttempts);
                s_lastMaxAttemptLog = now;
            }
            return false;
        }

        // Graduated recovery: two levels to avoid impossible recovery targets
        // Level 1: DD < haltThreshold * 0.75 -> re-enable at ultra-conservative
        // Level 2: DD < haltThreshold * 0.50 -> full normal mode
        double currentDD = m_maxDrawdownFromPeak;
        double level1Threshold = drawdownCriticalPercent * 0.75;
        double level2Threshold = drawdownCriticalPercent * 0.50;

        // Level 2 check: full recovery - DD below 50% of halt threshold
        if(m_cbRecoveryLevel >= 1 && currentDD < level2Threshold)
        {
            m_cbRecoveryLevel = 2;
            m_cbRecoveryAttempts++;
            m_tradingEnabled = true;
            conservativeMode = false;
            m_cbTriggeredAt = 0;
            m_cbLastRecoverySuccessTime = TimeCurrent();

            // L5-003 FIX: Only reset peak equity if we made a new all-time high.
            // On recovery, keep original peak; track recovery peak separately if needed.
            double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
            if(currentEquity > m_peakEquity)
            {
                m_peakEquity = currentEquity;
                m_maxDrawdownFromPeak = 0.0;
            }
            // Otherwise keep original peak - a small drop won't re-trigger immediately

            PrintFormat("[RISK-CIRCUIT-BREAKER] AUTO-RECOVERY L2 | Normal mode restored | DD=%.2f%% < threshold=%.2f%% | Attempt %d/%d",
                       currentDD, level2Threshold, m_cbRecoveryAttempts, m_cbMaxRecoveryAttempts);
            return true;
        }

        // Level 1 check: partial recovery - DD below 75% of halt threshold
        if(currentDD < level1Threshold)
        {
            m_cbRecoveryLevel = 1;
            m_cbRecoveryAttempts++;
            m_tradingEnabled = true;
            conservativeMode = true;
            m_cbTriggeredAt = 0;
            m_cbLastRecoverySuccessTime = TimeCurrent();

            // L5-003 FIX: Only reset peak equity if we made a new all-time high
            double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
            if(currentEquity > m_peakEquity)
            {
                m_peakEquity = currentEquity;
                m_maxDrawdownFromPeak = 0.0;
            }
            // Otherwise keep original peak - a small drop won't re-trigger immediately

            PrintFormat("[RISK-CIRCUIT-BREAKER] AUTO-RECOVERY L1 | Trading re-enabled ultra-conservative | DD=%.2f%% < threshold=%.2f%% | Attempt %d/%d",
                       currentDD, level1Threshold, m_cbRecoveryAttempts, m_cbMaxRecoveryAttempts);
            return true;
        }

        return false;
    }

    //+--------------------------------------------------------------+
    //| Daily P&L loss limit                                          |
    //+--------------------------------------------------------------+

    //--- Clear the daily-loss halt (called by the owner only after its
    //--- IsNewTradingDay() side-effecting check has fired, preserving the
    //--- original short-circuit order).
    void ResetDailyLossHalt()
    {
        m_dailyLossHaltActive = false;
        m_dailyLossHaltDate = 0;
        Print("[RISK-DAILY-LOSS] Daily loss halt RESET — new trading day");
    }

    //--- Daily P&L Loss Limit circuit breaker.
    //--- Halts all trading when daily realized + unrealized loss exceeds the
    //--- configured percentage of daily starting equity.
    //--- Returns true when trading may continue.
    bool EvaluateDailyLossLimit(const datetime nowTime,
                                const double dailyLossLimitPercent,
                                const double dailyStartEquity)
    {
        // If halt already active, keep blocking
        if(m_dailyLossHaltActive)
            return false;

        // Calculate daily P&L: realized deals today + current unrealized P&L.
        // Batch 168: EA-scoped. This previously summed every deal on the account
        // and took account-wide floating P&L, so a user's profitable manual trades
        // masked EA losses (the halt never fired) and, conversely, another EA's or
        // the user's loss could halt this EA for someone else's drawdown. When the
        // ownership authority is not yet configured it counts everything, because
        // excluding rows there would fail open.
        bool scopeToEA = IsMagicOwnershipConfigured();
        double dailyRealizedPL = 0.0;
        double unrealizedPL = 0.0;
        datetime dayStart = StringToTime(TimeToString(nowTime, TIME_DATE));
        HistorySelect(dayStart, nowTime);

        int totalDeals = HistoryDealsTotal();
        for(int i = 0; i < totalDeals; i++)
        {
            ulong dealTicket = HistoryDealGetTicket(i);
            if(dealTicket <= 0) continue;
            ENUM_DEAL_ENTRY dealEntry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
            // DEAL_ENTRY_OUT_BY closes a hedging-account position by offset; it was
            // omitted, so realized losses on hedging accounts were undercounted.
            if(dealEntry == DEAL_ENTRY_OUT || dealEntry == DEAL_ENTRY_INOUT || dealEntry == DEAL_ENTRY_OUT_BY)
            {
                if(scopeToEA &&
                   !IsMagicOwned(HistoryDealGetInteger(dealTicket, DEAL_MAGIC)))
                    continue;

                double dealProfit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
                double dealSwap = HistoryDealGetDouble(dealTicket, DEAL_SWAP);
                double dealCommission = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
                dailyRealizedPL += dealProfit + dealSwap + dealCommission;
            }
        }

        // Unrealized P&L across this EA's open positions only.
        if(scopeToEA)
        {
            for(int p = PositionsTotal() - 1; p >= 0; p--)
            {
                ulong ticket = PositionGetTicket(p);
                if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
                if(!IsMagicOwned(PositionGetInteger(POSITION_MAGIC))) continue;
                unrealizedPL += PositionGetDouble(POSITION_PROFIT)
                              + PositionGetDouble(POSITION_SWAP);
            }
        }
        else
        {
            unrealizedPL = AccountInfoDouble(ACCOUNT_EQUITY) - AccountInfoDouble(ACCOUNT_BALANCE);
        }

        double dailyPL = dailyRealizedPL + unrealizedPL;

        // L5-011 FIX: Use daily starting equity as denominator, not peak equity
        double riskDailyStartEquity = dailyStartEquity;
        if(riskDailyStartEquity <= 0.0)
            riskDailyStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);

        double dailyPLPercent = 0.0;
        if(riskDailyStartEquity > 0.0)
            dailyPLPercent = (dailyPL / riskDailyStartEquity) * 100.0;  // Blueprint 10.4: * 100.0 converts fraction to 0-100 scale

        // Check if daily loss exceeds limit
        if(dailyPLPercent <= -dailyLossLimitPercent)
        {
            m_dailyLossHaltActive = true;
            m_dailyLossHaltDate = nowTime;
            PrintFormat("[RISK-DAILY-LOSS] CRITICAL: Daily loss halt ACTIVATED | P&L=%.2f%% | Limit=-%.1f%% | Realized=%.2f | Unrealized=%.2f | DailyStartEquity=%.2f",
                        dailyPLPercent, dailyLossLimitPercent, dailyRealizedPL, unrealizedPL, riskDailyStartEquity);
            return false;
        }

        return true;
    }

    //+--------------------------------------------------------------+
    //| Cross-module escalation hooks                                 |
    //+--------------------------------------------------------------+

    //--- Hard halt requested by the margin-health monitor when the account
    //--- margin level breaches the emergency threshold. Mirrors the original
    //--- inline assignment pair in MonitorMarginHealth verbatim.
    void HaltForMarginEmergency()
    {
        m_tradingEnabled = false;
        m_cbTriggeredAt = TimeCurrent();
    }

    //+--------------------------------------------------------------+
    //| Accessors                                                     |
    //+--------------------------------------------------------------+

    bool IsTradingEnabled() const
    {
        return m_tradingEnabled;
    }

    bool IsEmergencyCloseRequested() const
    {
        return m_emergencyCloseRequested;
    }

    void ResetEmergencyCloseRequested()
    {
        m_emergencyCloseRequested = false;
    }

    bool IsDailyLossHaltActive() const
    {
        return m_dailyLossHaltActive;
    }

    datetime GetDailyLossHaltDate() const
    {
        return m_dailyLossHaltDate;
    }

    double GetPeakEquity() const
    {
        return m_peakEquity;
    }

    double GetMaxDrawdownFromPeak() const
    {
        return m_maxDrawdownFromPeak;
    }

    int GetDrawdownBreachCount() const
    {
        return m_drawdownBreachCount;
    }

    datetime GetTriggeredAt() const
    {
        return m_cbTriggeredAt;
    }

    int GetRecoveryAttempts() const
    {
        return m_cbRecoveryAttempts;
    }

    int GetRecoveryLevel() const
    {
        return m_cbRecoveryLevel;
    }
};

#endif // CORE_RISK_RISK_CIRCUIT_BREAKER_MQH
