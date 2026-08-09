//+------------------------------------------------------------------+
//| OrchestratorProfitGuard.mqh                                      |
//| Phase F extraction from CEAOrchestrator (behaviour preserving).  |
//|                                                                  |
//| Owns the daily profit-target / trailing-profit-floor / trading   |
//| halt state machine that used to live as six loose members on     |
//| CEAOrchestrator:                                                 |
//|   m_lastProfitTargetDay, m_dailyProfitTargetReached,             |
//|   m_dailyProfitPeakPct, m_trailingProfitFloor,                   |
//|   m_dailyTradingHalt, m_dailyTradingHaltStartTime                |
//|                                                                  |
//| The orchestrator now holds one COrchestratorProfitGuard by value |
//| and forwards UpdateDailyProfitTarget() / CalculateDailyPnLPercent|
//| to it. The single external reader of the halt flag               |
//| (GenerateAndProcessSignals) uses IsTradingHalted().              |
//|                                                                  |
//| Constructor initialisers reproduce the original CEAOrchestrator  |
//| constructor list exactly.                                        |
//+------------------------------------------------------------------+
#property strict

#ifndef CORE_ORCHESTRATION_ORCHESTRATOR_PROFIT_GUARD_MQH
#define CORE_ORCHESTRATION_ORCHESTRATOR_PROFIT_GUARD_MQH

#include "OrchestratorConfig.mqh"

//+------------------------------------------------------------------+
//| COrchestratorProfitGuard                                         |
//+------------------------------------------------------------------+
class COrchestratorProfitGuard
{
private:
    // Portfolio profit target tracking (moved verbatim from CEAOrchestrator)
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

    //--- was CEAOrchestrator::CalculateDailyPnLPercent
    static double CalculateDailyPnLPercent()
    {
        double balance = AccountInfoDouble(ACCOUNT_BALANCE);
        double equity = AccountInfoDouble(ACCOUNT_EQUITY);
        if(balance <= 0) return 0;
        return (equity - balance) / balance * 100.0;
    }

    //--- was CEAOrchestrator::UpdateDailyProfitTarget
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
                    double hardFloor = config.dailyProfitTargetPercent * config.profitTargetHardFloorRatio;
                    // Would trigger selective close
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
