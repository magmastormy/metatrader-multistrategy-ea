//+------------------------------------------------------------------+
//| PositionMgrLossGuard.mqh                                         |
//| Extracted from PositionManager.mqh (Phase I decomposition)       |
//|                                                                  |
//| STATEFUL module: owns loss-minimization configuration plus the   |
//| consecutive-loss / daily-loss accounting state, and enforces the |
//| per-position loss limit. Bodies are copied verbatim from         |
//| CPositionManager - zero behaviour change.                        |
//+------------------------------------------------------------------+
#property strict

#ifndef CORE_POSITION_POSITION_MGR_LOSS_GUARD_MQH
#define CORE_POSITION_POSITION_MGR_LOSS_GUARD_MQH

#include "../Trading/TradeManager.mqh"     // CTradeManager (complete type, called by pointer)
#include "PositionMgrMagicFilter.mqh"      // CPositionMgrMagicFilter::IsEAOwnedMagic

//+------------------------------------------------------------------+
//| CPositionMgrLossGuard                                            |
//+------------------------------------------------------------------+
class CPositionMgrLossGuard
{
private:
    // Loss minimization config
    bool                    m_adverseMomentumExitEnabled;
    double                  m_adverseMomentumATRMultiplier;
    int                     m_consecutiveLossLimit;
    int                     m_consecutiveLossCooldownSec;
    double                  m_dailyLossCircuitBreakerPercent;
    double                  m_positionLossLimitPercent;

    // Loss tracking
    int                     m_consecutiveLossCount;
    datetime                m_lastLossTime;
    datetime                m_consecutiveLossCooldownUntil;
    double                  m_dailyLossAmount;
    double                  m_dailyRiskBudget;
    datetime                m_dailyResetTime;

public:
    CPositionMgrLossGuard() :
        m_adverseMomentumExitEnabled(false), m_adverseMomentumATRMultiplier(0.5),
        m_consecutiveLossLimit(3), m_consecutiveLossCooldownSec(1800),
        m_dailyLossCircuitBreakerPercent(50.0), m_positionLossLimitPercent(75.0),
        m_consecutiveLossCount(0), m_lastLossTime(0), m_consecutiveLossCooldownUntil(0),
        m_dailyLossAmount(0.0), m_dailyRiskBudget(0.0), m_dailyResetTime(0)
    {
    }

    ~CPositionMgrLossGuard()
    {
    }

    //--- Mirrors CPositionManager::ConfigureLossMinimization()
    void Configure(bool adverseExit, double adverseMult, int consecLimit, int consecCooldown, double dailyCB, double posLimit)
    {
        m_adverseMomentumExitEnabled = adverseExit; m_adverseMomentumATRMultiplier = adverseMult;
        m_consecutiveLossLimit = consecLimit; m_consecutiveLossCooldownSec = consecCooldown;
        m_dailyLossCircuitBreakerPercent = dailyCB; m_positionLossLimitPercent = posLimit;
    }

    //--- Mirrors CPositionManager::SetDailyRiskBudget()
    void SetDailyRiskBudget(double budget)
    {
        m_dailyRiskBudget = budget;
        m_dailyResetTime = StringToTime(TimeToString(TimeCurrent() + 86400, TIME_DATE));
    }

    //--- Daily rollover block lifted verbatim out of ManagePositions()
    void ResetDailyIfNeeded(const datetime now)
    {
        if(now >= m_dailyResetTime)
        {
            m_dailyLossAmount = 0.0;
            m_dailyResetTime = StringToTime(TimeToString(now + 86400, TIME_DATE));
        }
    }

    //--- Gate condition lifted verbatim out of ManagePositions()
    bool ShouldRunLossMinimization() const
    {
        return (m_adverseMomentumExitEnabled || m_consecutiveLossLimit > 0);
    }

    bool IsAdverseMomentumExitEnabled() const { return m_adverseMomentumExitEnabled; }

    int GetConsecutiveLossCount() const { return m_consecutiveLossCount; }

    double GetDailyLossAmount() const { return m_dailyLossAmount; }

    // --- Loss Minimization ---
    void ManageLossMinimization(CTradeManager* tradeManager, const int magicNumber)
    {
        if(!m_adverseMomentumExitEnabled && m_consecutiveLossLimit <= 0) return;

        datetime now = TimeCurrent();

        // Check consecutive loss cooldown
        if(m_consecutiveLossCooldownUntil > 0 && now < m_consecutiveLossCooldownUntil)
            return;

        // Check daily loss circuit breaker
        if(m_dailyRiskBudget > 0 && m_dailyLossAmount >= m_dailyRiskBudget * (m_dailyLossCircuitBreakerPercent / 100.0))
        {
            PrintFormat("[LOSS-MIN] Daily loss circuit breaker triggered: %.2f%% of budget used",
                        m_dailyLossAmount / m_dailyRiskBudget * 100.0);
            return;
        }

        // Check consecutive losses
        if(m_consecutiveLossCount >= m_consecutiveLossLimit)
        {
            PrintFormat("[LOSS-MIN] Consecutive loss limit reached (%d). Cooling down for %d sec",
                        m_consecutiveLossCount, m_consecutiveLossCooldownSec);
            m_consecutiveLossCooldownUntil = now + m_consecutiveLossCooldownSec;
            return;
        }

        // Check individual position loss limits
        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
            if(!CPositionMgrMagicFilter::IsEAOwnedMagic(PositionGetInteger(POSITION_MAGIC), magicNumber)) continue;

            double profit = PositionGetDouble(POSITION_PROFIT);
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
            double slPrice = PositionGetDouble(POSITION_SL);

            if(slPrice > 0)
            {
                double slDistance = MathAbs(openPrice - slPrice);
                double currentDrawdown = MathAbs(openPrice - currentPrice);
                double lossPercent = (slDistance > 0) ? (currentDrawdown / slDistance) * 100.0 : 0;

                if(lossPercent >= m_positionLossLimitPercent)
                {
                    string sym = PositionGetString(POSITION_SYMBOL);
                    PrintFormat("[LOSS-MIN] Position %d on %s hit position loss limit: %.1f%% > %.1f%%",
                                ticket, sym, lossPercent, m_positionLossLimitPercent);
                    tradeManager.ClosePosition(ticket, "Position Loss Limit");
                }
            }
        }
    }

    // Record closed trade for loss tracking
    void RecordClosedTrade(double profit)
    {
        if(profit < 0)
        {
            m_consecutiveLossCount++;
            m_lastLossTime = TimeCurrent();
            m_dailyLossAmount += MathAbs(profit);
        }
        else
        {
            m_consecutiveLossCount = 0;
        }
    }
};

#endif // CORE_POSITION_POSITION_MGR_LOSS_GUARD_MQH
