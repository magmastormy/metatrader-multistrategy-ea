//+------------------------------------------------------------------+
//| TimerProcessor.mqh                                               |
//| Heavy processing on timer (1s) - signal gen, risk, execution    |
//+------------------------------------------------------------------+
#property strict

#ifndef CORE_ORCHESTRATION_TIMER_PROCESSOR_MQH
#define CORE_ORCHESTRATION_TIMER_PROCESSOR_MQH

#include "EAOrchestrator.mqh"
#include "../../Core/Management/EnterpriseStrategyManager.mqh"
#include "../../Core/Risk/UnifiedRiskManager.mqh"
#include "../../Core/Engines/AIEngine.mqh"
#include "../../Core/AI/AIPerformanceFeedback.mqh"
#include "../../Core/Risk/CompoundingTierManager.mqh"
#include "../../Core/Engines/FamilyStrategyWeightMatrix.mqh"
#include "../../Core/Engines/SessionWeightManager.mqh"
#include "../../Core/Engines/SkewStepAnalyzer.mqh"
#include "../../Core/Risk/UnprotectedPositionTracker.mqh"
#include "../../Core/Processing/SymbolScanScheduler.mqh"
#include "../../Core/Utils/Enums.mqh"
#include "../../Core/Trading/TradeManager.mqh"
#include "../../Core/Trading/PositionStateManager.mqh"

class CTimerProcessor
{
private:
    CEAOrchestrator*          m_orchestrator;
    CUnifiedRiskManager*      m_riskManager;
    CTradeManager*            m_tradeManager;
    CPositionStateManager*    m_positionStateManager;
    CAIEngine*                m_aiEngine;
    CAIPerformanceFeedback*   m_aiFeedback;
    CCompoundingTierManager*  m_compoundingTierManager;
    CFamilyStrategyWeightMatrix* m_familyWeightMatrix;
    CSessionWeightManager*    m_sessionWeightManager;
    CSkewStepAnalyzer*        m_skewStepAnalyzer;
    CUnprotectedPositionTracker* m_unprotectedTracker;
    CSymbolScanScheduler*     m_scanScheduler;
    
    // State
    datetime m_lastProfitTargetDay;
    bool m_dailyProfitTargetReached;
    double m_dailyProfitPeakPct;
    double m_trailingProfitFloor;
    bool m_dailyTradingHalt;
    datetime m_dailyTradingHaltStartTime;
    datetime m_lastTradeTime;
    ulong m_scanCycleSequence;
    int m_cyclesSinceIndicatorSignal;
    bool m_hybridGateRelaxed;
    
    // Call counter for diagnostics
    int m_callCount;
    
    // Config
    int m_minSecondsBetweenTrades;
    int m_maxPositionsTotal;
    double m_dailyProfitTargetPercent;
    double m_profitTrailFactor;
    double m_profitTargetHardFloorRatio;
    int m_dailyHaltCooldownMinutes;
    bool m_enableAutoModeSwitch;
    ENUM_RISK_TIER m_riskTier;
    int m_logLevel;
    int m_heartbeatInterval;

public:
    CTimerProcessor() : m_orchestrator(NULL), m_riskManager(NULL), m_tradeManager(NULL), m_positionStateManager(NULL),
                        m_aiEngine(NULL), m_aiFeedback(NULL), m_compoundingTierManager(NULL), m_familyWeightMatrix(NULL),
                        m_sessionWeightManager(NULL), m_skewStepAnalyzer(NULL), m_unprotectedTracker(NULL),
                        m_scanScheduler(NULL), m_lastProfitTargetDay(0), m_dailyProfitTargetReached(false),
                        m_dailyProfitPeakPct(0), m_trailingProfitFloor(0), m_dailyTradingHalt(false),
                        m_dailyTradingHaltStartTime(0), m_lastTradeTime(0), m_scanCycleSequence(0),
                        m_cyclesSinceIndicatorSignal(0), m_hybridGateRelaxed(false), m_callCount(0),
                        m_minSecondsBetweenTrades(2), m_maxPositionsTotal(10), m_dailyProfitTargetPercent(0),
                        m_profitTrailFactor(0.8), m_profitTargetHardFloorRatio(0.5), m_dailyHaltCooldownMinutes(60),
                        m_enableAutoModeSwitch(false), m_riskTier(ENUM_RISK_TIER(0)), m_logLevel(2), m_heartbeatInterval(30) {}
    
    ~CTimerProcessor() {}
    
    void SetDependencies(CEAOrchestrator* orchestrator, CUnifiedRiskManager* riskManager,
                         CTradeManager* tradeManager, CPositionStateManager* positionStateManager,
                         CAIEngine* aiEngine, CAIPerformanceFeedback* aiFeedback,
                         CCompoundingTierManager* compoundingTierManager,
                         CFamilyStrategyWeightMatrix* familyWeightMatrix,
                         CSessionWeightManager* sessionWeightManager,
                         CSkewStepAnalyzer* skewStepAnalyzer,
                         CUnprotectedPositionTracker* unprotectedTracker,
                         CSymbolScanScheduler* scanScheduler)
    {
        m_orchestrator = orchestrator;
        m_riskManager = riskManager;
        m_tradeManager = tradeManager;
        m_positionStateManager = positionStateManager;
        m_aiEngine = aiEngine;
        m_aiFeedback = aiFeedback;
        m_compoundingTierManager = compoundingTierManager;
        m_familyWeightMatrix = familyWeightMatrix;
        m_sessionWeightManager = sessionWeightManager;
        m_skewStepAnalyzer = skewStepAnalyzer;
        m_unprotectedTracker = unprotectedTracker;
        m_scanScheduler = scanScheduler;
    }
    
    void Configure(int minSecondsBetweenTrades, int maxPositionsTotal, double dailyProfitTargetPercent,
                   double profitTrailFactor, double profitTargetHardFloorRatio, int dailyHaltCooldownMinutes,
                   bool enableAutoModeSwitch, ENUM_RISK_TIER riskTier, int logLevel, int heartbeatInterval)
    {
        m_minSecondsBetweenTrades = minSecondsBetweenTrades;
        m_maxPositionsTotal = maxPositionsTotal;
        m_dailyProfitTargetPercent = dailyProfitTargetPercent;
        m_profitTrailFactor = profitTrailFactor;
        m_profitTargetHardFloorRatio = profitTargetHardFloorRatio;
        m_dailyHaltCooldownMinutes = dailyHaltCooldownMinutes;
        m_enableAutoModeSwitch = enableAutoModeSwitch;
        m_riskTier = riskTier;
        m_logLevel = logLevel;
        m_heartbeatInterval = heartbeatInterval;
    }
    
    void Process()
    {
        m_callCount++;
        
        if(!m_orchestrator.GetSystemInitialized() || !m_orchestrator.GetTradingEnabled())
            return;
        
        // Update dashboard
        UpdateDashboard();
        
        // Periodic diagnostic logging
        if(m_callCount % 50 == 0 && m_logLevel >= 3)
            Print("[TIMER-PROCESS] Call #" + IntegerToString(m_callCount));
        
        // 1. Refresh risk state
        if(m_riskManager != NULL)
            m_riskManager.RefreshRuntimeState();
        
        // 2. Refresh account metrics
        RefreshAccountMetrics();
        
        // 3. Update live authority trials
        UpdateLiveAuthorityTrials();
        
        // 4. Daily profit target with trailing floor
        ProcessDailyProfitTarget();
        
        // 5. Daily halt cooldown
        ProcessDailyHaltCooldown();
        
        // 6. Auto mode switching
        if(m_enableAutoModeSwitch)
            ProcessAutoModeSwitch();
        
        // 7. Unprotected position remediation
        if(m_unprotectedTracker != NULL)
            m_unprotectedTracker.AttemptRemediation();
        
        // 8. Neural network online learning
        ProcessNNOnlineLearning();
        
        // 9. New bar detection and processing
        bool anyNewBar = ProcessNewBars();
        
        // 10. AI adaptation on new bars
        if(anyNewBar)
        {
            if(m_aiEngine != NULL)
                m_aiEngine.ProcessAdaptation();
            
            if(m_aiFeedback != NULL)
            {
                static datetime s_lastFeedback = 0;
                if(TimeCurrent() - s_lastFeedback >= 300)
                {
                    m_aiFeedback.CheckAutomaticRetraining();
                    s_lastFeedback = TimeCurrent();
                }
            }
        }
        
        // 11. Signal generation and execution
        ProcessSignalGenerationAndExecution();
        
        // 12. Heartbeat diagnostics
        if(m_callCount % (m_heartbeatInterval * 60) == 0 && m_logLevel >= 2)
        {
            Print("[HEARTBEAT] " + m_orchestrator.GetStatusReport());
        }
    }
    
    void UpdateDashboard()
    {
        // Would update dashboard with current state
    }
    
    void RefreshAccountMetrics()
    {
        // Would refresh equity, balance, margin, etc.
    }
    
    void UpdateLiveAuthorityTrials()
    {
        // Would update authority trials
    }
    
    void ProcessDailyProfitTarget()
    {
        datetime today = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
        if(today != m_lastProfitTargetDay)
        {
            m_lastProfitTargetDay = today;
            m_dailyProfitTargetReached = false;
            m_dailyProfitPeakPct = 0;
            m_trailingProfitFloor = 0;
            m_dailyTradingHalt = false;
            m_dailyTradingHaltStartTime = 0;
            // Reset pipeline budget exhaustion
        }
        
        if(m_dailyProfitTargetPercent > 0 && !m_dailyTradingHalt)
        {
            double dailyPnL = CalculateDailyPnLPercent();
            
            if(dailyPnL >= m_dailyProfitTargetPercent && !m_dailyProfitTargetReached)
            {
                m_dailyProfitTargetReached = true;
                m_dailyProfitPeakPct = dailyPnL;
                m_trailingProfitFloor = dailyPnL * m_profitTrailFactor;
                Print("[PROFIT-TARGET] Target reached: " + DoubleToString(dailyPnL, 2) + "%");
            }
            
            if(m_dailyProfitTargetReached)
            {
                m_dailyProfitPeakPct = MathMax(m_dailyProfitPeakPct, dailyPnL);
                m_trailingProfitFloor = m_dailyProfitPeakPct * m_profitTrailFactor;
                
                if(dailyPnL < m_trailingProfitFloor)
                {
                    double hardFloor = m_dailyProfitTargetPercent * m_profitTargetHardFloorRatio;
                    Print("[PROFIT-TARGET] Trailing floor breached. Hard floor: " + DoubleToString(hardFloor, 2) + "%");
                    
                    // Would trigger selective close
                    bool allClosed = SelectiveCloseToRecoverFloor(hardFloor);
                    if(allClosed)
                    {
                        m_dailyTradingHalt = true;
                        m_dailyTradingHaltStartTime = TimeCurrent();
                    }
                }
            }
        }
    }
    
    void ProcessDailyHaltCooldown()
    {
        if(m_dailyTradingHalt && m_dailyTradingHaltStartTime > 0)
        {
            int elapsedMin = (int)(TimeCurrent() - m_dailyTradingHaltStartTime) / 60;
            if(elapsedMin >= m_dailyHaltCooldownMinutes)
            {
                m_dailyTradingHalt = false;
                m_dailyTradingHaltStartTime = 0;
                m_dailyProfitTargetReached = false;
                m_dailyProfitPeakPct = 0;
                m_trailingProfitFloor = 0;
                Print("[PROFIT-TARGET] Daily halt cooldown expired. Resuming trading.");
            }
        }
    }
    
    void ProcessAutoModeSwitch()
    {
        // Would determine trading mode based on drawdown
    }
    
    void ProcessNNOnlineLearning()
    {
        // Would call NN online learning
    }
    
    bool ProcessNewBars()
    {
        // Would check each symbol for new bar
        // Return true if any new bar detected
        return false;
    }
    
    void ProcessSignalGenerationAndExecution()
    {
        // Would generate signals, validate, build candidates, execute
    }
    
    double CalculateDailyPnLPercent() const
    {
        double balance = AccountInfoDouble(ACCOUNT_BALANCE);
        double equity = AccountInfoDouble(ACCOUNT_EQUITY);
        if(balance <= 0) return 0;
        return (equity - balance) / balance * 100.0;
    }
    
    bool SelectiveCloseToRecoverFloor(double hardFloorPct)
    {
        if(m_tradeManager == NULL) return false;
        
        // Collect all EA-owned positions with their profit
        ulong  posTickets[];
        double posProfits[];
        int posCount = 0;

        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket == 0 || !PositionSelectByTicket(ticket))
                continue;
            if(!m_tradeManager.IsEAOwnedMagic(PositionGetInteger(POSITION_MAGIC)))
                continue;

            posCount++;
            ArrayResize(posTickets, posCount);
            ArrayResize(posProfits, posCount);
            posTickets[posCount - 1] = ticket;
            posProfits[posCount - 1] = PositionGetDouble(POSITION_PROFIT)
                                      + PositionGetDouble(POSITION_SWAP);
        }

        if(posCount == 0)
            return true;  // No positions left

        // Sort by profit ascending (worst first) - simple insertion sort on parallel arrays
        for(int i = 1; i < posCount; i++)
        {
            double keyProfit = posProfits[i];
            ulong   keyTicket = posTickets[i];
            int j = i - 1;
            while(j >= 0 && posProfits[j] > keyProfit)
            {
                posProfits[j + 1] = posProfits[j];
                posTickets[j + 1] = posTickets[j];
                j--;
            }
            posProfits[j + 1] = keyProfit;
            posTickets[j + 1] = keyTicket;
        }

        // Close positions from worst to best until daily profit recovers above trailing floor
        // or until we hit the hard floor (must close everything)
        double dailyPct = CalculateDailyPnLPercent();

        for(int i = 0; i < posCount; i++)
        {
            // Check if daily profit is already above trailing floor
            if(dailyPct >= m_trailingProfitFloor)
            {
                PrintFormat("[PROFIT-TARGET] Trailing floor recovered at %.2f%% after selective closes. %d positions remaining.",
                            dailyPct, posCount - i);
                return false;  // Recovered, some positions still open
            }

            // Check hard floor: if below hard floor, must close everything
            if(dailyPct < hardFloorPct)
            {
                PrintFormat("[PROFIT-TARGET] Hard floor breached: %.2f%% < %.2f%%. Closing all remaining positions.",
                            dailyPct, hardFloorPct);
                datetime closeStart = TimeCurrent();
                m_tradeManager.CloseAllPositions("");
                if(TimeCurrent() - closeStart > 5)
                    PrintFormat("[EMERGENCY] CloseAllPositions took %d seconds (hard floor breach)",
                                (int)(TimeCurrent() - closeStart));
                return true;  // All closed, hard floor breach
            }

            // Close this worst position, capturing profit before close for P&L estimation
            double closedProfit = 0.0;
            if(PositionSelectByTicket(posTickets[i]))
            {
                string posSymbol = PositionGetString(POSITION_SYMBOL);
                closedProfit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
                PrintFormat("[PROFIT-TARGET] Selective close: Symbol=%s Profit=%.2f (trailing floor recovery)",
                            posSymbol, closedProfit);
                m_tradeManager.ClosePosition(posTickets[i]);
            }

            // Estimate P&L change: the closed position's profit+swap moves from unrealized
            // to realized in deal history (approximately net-zero on total P&L). The only
            // material change is the close commission (small negative). Approximate by
            // subtracting the closed position's P&L contribution from the cached percentage.
            // A full recalculation at the end of the loop corrects any estimation drift.
            double equity = AccountInfoDouble(ACCOUNT_EQUITY);
            if(equity > 1.0)
                dailyPct -= (closedProfit / equity) * 100.0;
        }

        // Full recalculation after all closes to verify final state
        dailyPct = CalculateDailyPnLPercent();

        // All positions closed
        return true;
    }
    
    string GetStatusReport() const
    {
        string report = "[TimerProcessor] ";
        report += "Calls=" + IntegerToString(m_callCount);
        report += " | DailyHalt=" + (m_dailyTradingHalt ? "Y" : "N");
        report += " | TargetReached=" + (m_dailyProfitTargetReached ? "Y" : "N");
        report += " | DailyPnL=" + DoubleToString(CalculateDailyPnLPercent(), 2) + "%";
        return report;
    }
};

#endif // CORE_ORCHESTRATION_TIMER_PROCESSOR_MQH