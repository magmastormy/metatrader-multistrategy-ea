// Drawdown / daily-loss circuit breakers, graduated auto-recovery and emergency-close escalation state.
// CUnifiedRiskManager keeps the initialized guards and the shared conservative-mode / daily-start-equity
// fields; thresholds arrive as arguments so this class holds no back-pointers.
#ifndef CORE_RISK_RISK_CIRCUIT_BREAKER_MQH
#define CORE_RISK_RISK_CIRCUIT_BREAKER_MQH

#include "../Utils/MagicRange.mqh"

// Circuit breaker state holder (stateful, owned by value)
class CRiskCircuitBreaker
{
private:
    bool     m_tradingEnabled;           // false = halted, gates every new entry
    double   m_peakEquity;               // Highest ACCOUNT_EQUITY seen
    double   m_maxDrawdownFromPeak;      // Percent 0-100 measured against peak equity
    int      m_drawdownBreachCount;      // >=2 triggers the emergency flatten

    bool     m_dailyLossHaltActive;      // Latched until the next trading day
    datetime m_dailyLossHaltDate;

    datetime m_cbTriggeredAt;            // 0 = no halt outstanding
    int      m_cbRecoveryAttempts;
    int      m_cbMaxRecoveryAttempts;
    int      m_cbRecoveryCooldownMin;    // Compared against bars, not minutes; wall clock is fallback only
    datetime m_cbLastRecoverySuccessTime;// Starts the stable window that clears m_cbRecoveryAttempts
    int      m_cbRecoveryLevel;          // 0=halted, 1=partial(75%), 2=full(50%)

    bool     m_emergencyCloseRequested;  // Owner must flatten, not just stop new entries

public:
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
    }


    //--- Re-arm at CUnifiedRiskManager::Initialize.
    void InitializeState(const double dailyStartEquity)
    {
        m_peakEquity = dailyStartEquity;
        m_maxDrawdownFromPeak = 0.0;
        m_drawdownBreachCount = 0;
        m_tradingEnabled = true;
        m_cbTriggeredAt = 0;
        m_cbRecoveryAttempts = 0;
        m_cbRecoveryLevel = 0;

        m_dailyLossHaltActive = false;
        m_dailyLossHaltDate = 0;
    }

    //--- Called every runtime cycle so m_maxDrawdownFromPeak stays current.
    void RefreshPeakAndDrawdown()
    {
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

    //--- New trading day clears the auto-recovery attempt counter.
    void ResetRecoveryCounterForNewDay()
    {
        if(m_cbRecoveryAttempts > 0)
        {
            PrintFormat("[RISK-UNIFIED] Daily reset: circuit breaker recovery counter %d->0", m_cbRecoveryAttempts);
            m_cbRecoveryAttempts = 0;
            m_cbLastRecoverySuccessTime = 0;
        }
    }


    //--- Returns: true if trading is allowed, false if circuit breaker hit.
    //--- `conservativeMode` is the owner's shared conservative-mode flag.
    bool CheckDrawdownCircuitBreaker(const double drawdownWarningPercent,
                                     const double drawdownCriticalPercent,
                                     bool &conservativeMode)
    {
        double equityNow = AccountInfoDouble(ACCOUNT_EQUITY);

        if(equityNow > m_peakEquity)
        {
            m_peakEquity = equityNow;
            m_maxDrawdownFromPeak = 0.0;
        }

        if(m_peakEquity > 0)
        {
            m_maxDrawdownFromPeak = ((m_peakEquity - equityNow) / m_peakEquity) * 100.0;
        }

        // Critical threshold: hard halt, no new entries
        if(m_maxDrawdownFromPeak >= drawdownCriticalPercent)
        {
            if(m_tradingEnabled)
            {
                m_tradingEnabled = false;
                m_drawdownBreachCount++;
                m_cbTriggeredAt = TimeCurrent();
                m_cbRecoveryLevel = 0;

                PrintFormat("[RISK-CIRCUIT-BREAKER] CRITICAL BREACH | Drawdown=%.2f%% >= Limit=%.2f%% | Trading HALTED",
                           m_maxDrawdownFromPeak, drawdownCriticalPercent);
                PrintFormat("[RISK-CIRCUIT-BREAKER] Peak Equity=%.2f | Current Equity=%.2f | Loss=%.2f",
                           m_peakEquity, equityNow, m_peakEquity - equityNow);
                PrintFormat("[RISK-CIRCUIT-BREAKER] Breach count: %d | Auto-recovery will be attempted after %d min cooldown (max %d attempts)",
                           m_drawdownBreachCount, m_cbRecoveryCooldownMin, m_cbMaxRecoveryAttempts);

                // 2nd+ breach: flatten, halting new entries alone is not enough
                if(m_drawdownBreachCount >= 2)
                {
                    PrintFormat("[RISK-CIRCUIT-BREAKER] SECOND+ BREACH - EMERGENCY CLOSING ALL POSITIONS!");
                    m_emergencyCloseRequested = true;
                }

                // Emergency exit: drawdown >= 2x critical closes everything
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

        // Warning band: conservative mode halves position size
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
            // Trading continues, halved
            return true;
        }

        // Reset conservative mode if drawdown recovers below 60% of critical (closes gap with 50% trading-resume threshold)
        if(m_maxDrawdownFromPeak < drawdownCriticalPercent * 0.6 && conservativeMode)
        {
            conservativeMode = false;
            PrintFormat("[RISK-CIRCUIT-BREAKER] Recovery | Drawdown=%.2f%% < threshold=%.2f%% | Normal mode restored",
                       m_maxDrawdownFromPeak, drawdownCriticalPercent * 0.6);
        }

        // Stable period: 60 minutes with drawdown under half the warning level clears the attempt counter
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

    //--- Operator reset: re-arms trading and re-baselines peak to current equity.
    void ResetCircuitBreaker(bool &conservativeMode)
    {
        m_tradingEnabled = true;
        conservativeMode = false;
        m_drawdownBreachCount = 0;
        m_cbTriggeredAt = 0;
        m_cbRecoveryAttempts = 0;
        m_cbRecoveryLevel = 0;
        m_cbLastRecoverySuccessTime = 0;

        m_peakEquity = AccountInfoDouble(ACCOUNT_EQUITY);
        m_maxDrawdownFromPeak = 0.0;

        Print("[RISK-CIRCUIT-BREAKER] Manually reset by operator | Trading resumed");
    }

    //--- Restore circuit breaker state from crash recovery file.
    //--- `dailyStartEquity` is the owner's shared daily-start equity field.
    //--- Halt flags must be restored: a restart that clears them re-arms an earned daily-loss halt and
    //--- frees a second full daily budget.
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


    //--- Re-enables trading once the bar-based cooldown has elapsed and drawdown has recovered.
    bool CheckCircuitBreakerRecovery(const double drawdownCriticalPercent,
                                     bool &conservativeMode)
    {
        if(m_tradingEnabled)
            return false;

        if(m_cbTriggeredAt <= 0)
            return false;

        // Bar-based cooldown: keeps the wait correct across weekends and session breaks
        int barsSinceTrigger = iBarShift(_Symbol, PERIOD_CURRENT, m_cbTriggeredAt, false);
        if(barsSinceTrigger < 0)
        {
            // Wall-clock fallback when the bar shift fails
            int elapsedMinutes = (int)((TimeCurrent() - m_cbTriggeredAt) / 60);
            if(elapsedMinutes < m_cbRecoveryCooldownMin)
                return false;
        }
        else if(barsSinceTrigger < m_cbRecoveryCooldownMin)
        {
            return false;
        }

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

        // Graduated re-arm: L1 DD < critical*0.75 trades ultra-conservative, L2 DD < critical*0.50 restores normal mode
        double currentDD = m_maxDrawdownFromPeak;
        double level1Threshold = drawdownCriticalPercent * 0.75;
        double level2Threshold = drawdownCriticalPercent * 0.50;

        if(m_cbRecoveryLevel >= 1 && currentDD < level2Threshold)
        {
            m_cbRecoveryLevel = 2;
            m_cbRecoveryAttempts++;
            m_tradingEnabled = true;
            conservativeMode = false;
            m_cbTriggeredAt = 0;
            m_cbLastRecoverySuccessTime = TimeCurrent();

            // Peak re-baselines only on a new all-time high; keeping the original peak stops an immediate re-trigger
            double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
            if(currentEquity > m_peakEquity)
            {
                m_peakEquity = currentEquity;
                m_maxDrawdownFromPeak = 0.0;
            }

            PrintFormat("[RISK-CIRCUIT-BREAKER] AUTO-RECOVERY L2 | Normal mode restored | DD=%.2f%% < threshold=%.2f%% | Attempt %d/%d",
                       currentDD, level2Threshold, m_cbRecoveryAttempts, m_cbMaxRecoveryAttempts);
            return true;
        }

        if(currentDD < level1Threshold)
        {
            m_cbRecoveryLevel = 1;
            m_cbRecoveryAttempts++;
            m_tradingEnabled = true;
            conservativeMode = true;
            m_cbTriggeredAt = 0;
            m_cbLastRecoverySuccessTime = TimeCurrent();

            // Peak re-baselines only on a new all-time high
            double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
            if(currentEquity > m_peakEquity)
            {
                m_peakEquity = currentEquity;
                m_maxDrawdownFromPeak = 0.0;
            }

            PrintFormat("[RISK-CIRCUIT-BREAKER] AUTO-RECOVERY L1 | Trading re-enabled ultra-conservative | DD=%.2f%% < threshold=%.2f%% | Attempt %d/%d",
                       currentDD, level1Threshold, m_cbRecoveryAttempts, m_cbMaxRecoveryAttempts);
            return true;
        }

        return false;
    }

    //--- Clears the daily-loss halt.
    //--- Caller must invoke it only after its side-effecting IsNewTradingDay() check has run,
    //--- so the owner's original short-circuit evaluation order is preserved.
    void ResetDailyLossHalt()
    {
        m_dailyLossHaltActive = false;
        m_dailyLossHaltDate = 0;
        Print("[RISK-DAILY-LOSS] Daily loss halt RESET — new trading day");
    }

    //--- Blocks trading once daily realized + floating loss exceeds dailyLossLimitPercent, measured
    //--- against daily starting equity. Returns true when trading may continue.
    bool EvaluateDailyLossLimit(const datetime nowTime,
                                const double dailyLossLimitPercent,
                                const double dailyStartEquity)
    {
        // Halt latches for the rest of the day
        if(m_dailyLossHaltActive)
            return false;

        // Daily P&L = today's realized deals + floating P&L, scoped to this EA's magic; account-wide sums let a user's
        // manual profits mask EA losses. With no ownership configured it counts everything, since excluding rows fails open.
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
            // OUT_BY closes a hedging-account position by offset; its P&L is realized P&L too
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

        // Denominator is daily starting equity, never peak equity
        double riskDailyStartEquity = dailyStartEquity;
        if(riskDailyStartEquity <= 0.0)
            riskDailyStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);

        double dailyPLPercent = 0.0;
        if(riskDailyStartEquity > 0.0)
            dailyPLPercent = (dailyPL / riskDailyStartEquity) * 100.0;

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

    //--- Hard halt requested by the margin-health monitor when the account
    //--- margin level breaches the emergency threshold.
    void HaltForMarginEmergency()
    {
        m_tradingEnabled = false;
        m_cbTriggeredAt = TimeCurrent();
    }


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
