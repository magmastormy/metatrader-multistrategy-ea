// Owns the daily profit-target / trailing-profit-floor / trading-halt state machine.
#property strict

#ifndef CORE_ORCHESTRATION_ORCHESTRATOR_PROFIT_GUARD_MQH
#define CORE_ORCHESTRATION_ORCHESTRATOR_PROFIT_GUARD_MQH

#include "OrchestratorConfig.mqh"

class COrchestratorProfitGuard
{
private:
    datetime m_lastProfitTargetDay;
    bool     m_dailyProfitTargetReached;
    double   m_dailyProfitPeakPct;
    double   m_trailingProfitFloor;
    bool     m_dailyTradingHalt;
    datetime m_dailyTradingHaltStartTime;

public:
    COrchestratorProfitGuard()
        : m_lastProfitTargetDay(0),
          m_dailyProfitTargetReached(false),
          m_dailyProfitPeakPct(0),
          m_trailingProfitFloor(0),
          m_dailyTradingHalt(false),
          m_dailyTradingHaltStartTime(0)
    {
    }

    //--- Single external reader of the halt flag (GenerateAndProcessSignals)
    bool IsTradingHalted() const { return m_dailyTradingHalt; }

    static double CalculateDailyPnLPercent()
    {
        double balance = AccountInfoDouble(ACCOUNT_BALANCE);
        double equity = AccountInfoDouble(ACCOUNT_EQUITY);
        if(balance <= 0) return 0;
        return (equity - balance) / balance * 100.0;
    }

    void UpdateDailyProfitTarget(const SOrchestratorConfig &config)
    {
        datetime today = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
        if(today != m_lastProfitTargetDay)
        {
            m_lastProfitTargetDay = today;
            m_dailyProfitTargetReached = false;
            m_dailyProfitPeakPct = 0.0;
            m_trailingProfitFloor = 0.0;
            m_dailyTradingHalt = false;
            m_dailyTradingHaltStartTime = 0;
        }

        if(config.dailyProfitTargetPercent > 0.0 && !m_dailyTradingHalt)
        {
            double dailyPnL = CalculateDailyPnLPercent();

            if(dailyPnL >= config.dailyProfitTargetPercent && !m_dailyProfitTargetReached)
            {
                m_dailyProfitTargetReached = true;
                m_dailyProfitPeakPct = dailyPnL;
                m_trailingProfitFloor = dailyPnL * config.profitTrailFactor;
            }

            if(m_dailyProfitTargetReached)
            {
                m_dailyProfitPeakPct = MathMax(m_dailyProfitPeakPct, dailyPnL);
                m_trailingProfitFloor = m_dailyProfitPeakPct * config.profitTrailFactor;

                if(dailyPnL < m_trailingProfitFloor)
                {
                    m_dailyTradingHalt = true;
                    m_dailyTradingHaltStartTime = TimeCurrent();
                }
            }
        }

        if(m_dailyTradingHalt && m_dailyTradingHaltStartTime > 0)
        {
            int elapsed = (int)(TimeCurrent() - m_dailyTradingHaltStartTime) / 60;
            if(elapsed >= config.dailyHaltCooldownMinutes)
            {
                m_dailyTradingHalt = false;
                m_dailyTradingHaltStartTime = 0;
                m_dailyProfitTargetReached = false;
                m_dailyProfitPeakPct = 0.0;
                m_trailingProfitFloor = 0.0;
            }
        }
    }
};

#endif // CORE_ORCHESTRATION_ORCHESTRATOR_PROFIT_GUARD_MQH
