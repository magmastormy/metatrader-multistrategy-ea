//+------------------------------------------------------------------+
//| PosLifecycleLossGuard.mqh                                         |
//| Loss-minimisation guard (adverse-momentum exit, per-position loss |
//| limit, consecutive-loss cooldown, daily-loss circuit breaker)     |
//| extracted from PositionLifecycleManager.mqh                       |
//| (Phase H — God Object decomposition)                              |
//|                                                                   |
//| Owns: loss-minimisation configuration + loss tracking counters.   |
//| Behaviour preserved 1:1 — no logic changes.                       |
//+------------------------------------------------------------------+
#ifndef POS_LIFECYCLE_LOSS_GUARD_MQH
#define POS_LIFECYCLE_LOSS_GUARD_MQH

#include "..\Trading\TradeManager.mqh"
#include "PosLifecycleMagicFilter.mqh"
#include "PosLifecycleVolatility.mqh"   // CPosLifecycleVolatility::GetATR()

//+------------------------------------------------------------------+
//| CPosLifecycleLossGuard                                            |
//| Stateful module — held BY VALUE by CPositionLifecycleManager.     |
//+------------------------------------------------------------------+
class CPosLifecycleLossGuard
{
private:
    // EXECUTION REFINEMENT: Loss minimization config
    bool   m_adverseMomentumExitEnabled;
    double m_adverseMomentumATRMultiplier;
    int    m_consecutiveLossLimit;
    int    m_consecutiveLossCooldownSec;
    double m_dailyLossCircuitBreakerPercent;
    double m_positionLossLimitPercent;

    // EXECUTION REFINEMENT: Loss tracking
    int      m_consecutiveLossCount;
    datetime m_lastLossTime;
    datetime m_consecutiveLossCooldownUntil;
    double   m_dailyLossAmount;
    double   m_dailyRiskBudget;
    datetime m_dailyResetTime;

public:
    CPosLifecycleLossGuard() :
        m_adverseMomentumExitEnabled(false),
        m_adverseMomentumATRMultiplier(0.5),
        m_consecutiveLossLimit(3),
        m_consecutiveLossCooldownSec(1800),
        m_dailyLossCircuitBreakerPercent(50.0),
        m_positionLossLimitPercent(75.0),
        m_consecutiveLossCount(0),
        m_lastLossTime(0),
        m_consecutiveLossCooldownUntil(0),
        m_dailyLossAmount(0.0),
        m_dailyRiskBudget(0.0),
        m_dailyResetTime(0)
    {}

    //--- EXECUTION REFINEMENT: Configure loss minimization
    void Configure(bool adverseMomentumExit, double adverseMomentumATR,
                   int consecutiveLossLimit, int consecutiveLossCooldown,
                   double dailyLossCircuitBreaker, double positionLossLimit)
    {
        m_adverseMomentumExitEnabled = adverseMomentumExit;
        m_adverseMomentumATRMultiplier = adverseMomentumATR;
        m_consecutiveLossLimit = consecutiveLossLimit;
        m_consecutiveLossCooldownSec = consecutiveLossCooldown;
        m_dailyLossCircuitBreakerPercent = dailyLossCircuitBreaker;
        m_positionLossLimitPercent = positionLossLimit;
    }

    //--- Guard-clause accessors used by CPositionLifecycleManager::ManagePositions()
    bool IsAdverseMomentumExitEnabled() const { return m_adverseMomentumExitEnabled; }
    int  GetConsecutiveLossLimit()      const { return m_consecutiveLossLimit; }

    //--- EXECUTION REFINEMENT: Loss minimization management
    void ManageLossMinimization(CTradeManager* tradeManager, const int magicBase, const int magicMax)
    {
        // Reset daily loss tracking at midnight
        datetime now = TimeCurrent();
        MqlDateTime dt;
        TimeToStruct(now, dt);
        datetime midnight = StringToTime(IntegerToString(dt.year) + "." + IntegerToString(dt.mon) + "." + IntegerToString(dt.day) + " 00:00:00");
        if(now >= midnight + 86400)  // Next day
        {
            m_dailyLossAmount = 0.0;
            m_dailyResetTime = midnight;
        }

        // Check consecutive loss cooldown
        if(m_consecutiveLossCooldownUntil > 0 && now < m_consecutiveLossCooldownUntil)
        {
            static datetime lastCooldownLog = 0;
            if(now - lastCooldownLog > 60)
            {
                PrintFormat("[LOSS-MIN] In consecutive loss cooldown | cooldown until %s", TimeToString(m_consecutiveLossCooldownUntil));
                lastCooldownLog = now;
            }
            return;  // Skip trading during cooldown
        }

        // Check daily loss circuit breaker
        if(m_dailyLossCircuitBreakerPercent > 0 && m_dailyRiskBudget > 0)
        {
            double dailyLossLimit = m_dailyRiskBudget * (m_dailyLossCircuitBreakerPercent / 100.0);
            if(m_dailyLossAmount >= dailyLossLimit)
            {
                static datetime lastCircuitLog = 0;
                if(now - lastCircuitLog > 60)
                {
                    PrintFormat("[LOSS-MIN] Daily loss circuit breaker triggered | loss=%.2f limit=%.2f | stopping trading",
                                m_dailyLossAmount, dailyLossLimit);
                    lastCircuitLog = now;
                }
                return;  // Stop trading for the day
            }
        }

        // Manage individual positions
        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
            if(!CPosLifecycleMagicFilter::IsOwned(PositionGetInteger(POSITION_MAGIC), magicBase, magicMax)) continue;

            string symbol = PositionGetString(POSITION_SYMBOL);
            ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
            double slPrice = PositionGetDouble(POSITION_SL);
            double currentProfit = PositionGetDouble(POSITION_PROFIT);

            // Adverse momentum exit
            if(m_adverseMomentumExitEnabled)
            {
                double atr = CPosLifecycleVolatility::GetATR(symbol, 14);
                if(atr > 0)
                {
                    double adverseThreshold = atr * m_adverseMomentumATRMultiplier;
                    double priceMove = 0.0;

                    if(type == POSITION_TYPE_BUY)
                        priceMove = openPrice - currentPrice;
                    else
                        priceMove = currentPrice - openPrice;

                    if(priceMove > adverseThreshold && currentProfit < 0)
                    {
                        PrintFormat("[LOSS-MIN] Adverse momentum exit | ticket=%d | move=%.5f threshold=%.5f",
                                    ticket, priceMove, adverseThreshold);
                        tradeManager.ClosePosition(ticket, "Adverse Momentum");
                        m_consecutiveLossCount++;
                        m_lastLossTime = now;
                        m_dailyLossAmount += MathAbs(currentProfit);
                        continue;
                    }
                }
            }

            // Position loss limit
            if(m_positionLossLimitPercent > 0 && slPrice > 0)
            {
                double slDistance = MathAbs(openPrice - slPrice);
                double currentDrawdownLocal = MathAbs(openPrice - currentPrice);
                double lossRatio = (slDistance > 0) ? (currentDrawdownLocal / slDistance) : 0.0;

                if(lossRatio > (m_positionLossLimitPercent / 100.0) && currentProfit < 0)
                {
                    PrintFormat("[LOSS-MIN] Position loss limit exit | ticket=%d | lossRatio=%.2f limit=%.2f",
                                ticket, lossRatio, m_positionLossLimitPercent / 100.0);
                    tradeManager.ClosePosition(ticket, "Position Loss Limit");
                    m_consecutiveLossCount++;
                    m_lastLossTime = now;
                    m_dailyLossAmount += MathAbs(currentProfit);
                    continue;
                }
            }
        }

        // Check consecutive loss limit
        if(m_consecutiveLossLimit > 0 && m_consecutiveLossCount >= m_consecutiveLossLimit)
        {
            m_consecutiveLossCooldownUntil = now + m_consecutiveLossCooldownSec;
            PrintFormat("[LOSS-MIN] Consecutive loss limit reached | count=%d | cooldown for %d seconds",
                        m_consecutiveLossCount, m_consecutiveLossCooldownSec);
            m_consecutiveLossCount = 0;  // Reset after triggering cooldown
        }
    }
};

#endif // POS_LIFECYCLE_LOSS_GUARD_MQH
