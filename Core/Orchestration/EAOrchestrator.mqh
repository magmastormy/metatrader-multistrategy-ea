//+------------------------------------------------------------------+
//| EAOrchestrator.mqh                                               |
//| Main coordination class - replaces monolithic EA logic           |
//+------------------------------------------------------------------+
#property strict

#ifndef CORE_ORCHESTRATION_EA_ORCHESTRATOR_MQH
#define CORE_ORCHESTRATION_EA_ORCHESTRATOR_MQH

#include "SignalGenerator.mqh"
#include "SignalValidator.mqh"
#include "CandidateBuilder.mqh"
#include "TradeExecutor.mqh"
#include "LiveAuthorityResolver.mqh"
#include "../Position/PositionManager.mqh"
#include "../../Core/Registry/MathematicalEngineRegistry.mqh"
#include "../../Core/Registry/InstitutionalEngineRegistry.mqh"
#include "../../Core/Registry/NeuralNetRegistry.mqh"
#include "../../Core/Registry/DrawingManagerRegistry.mqh"
#include "../../Core/Registry/ScanSchedulerRegistry.mqh"
#include "../../Core/Registry/SymbolStateTracker.mqh"
#include "../../Core/Management/EnterpriseStrategyManager.mqh"
#include "../../Core/Risk/UnifiedRiskManager.mqh"
#include "../../Core/Risk/PositionSizer.mqh"
#include "../../Core/Trading/TradeManager.mqh"
#include "../../Core/Engines/RegimeEngine.mqh"
#include "../../Core/Risk/RiskTierManager.mqh"
#include "../../Core/Risk/SafeModeConfig.mqh"
#include "../../Core/Risk/FullMarginMode.mqh"
#include "../../Core/Processing/TickSafetyMonitor.mqh"
#include "../../Core/Processing/SyntheticSpikeMonitor.mqh"
#include "../../Core/Processing/SymbolScanScheduler.mqh"
#include "../../Core/Trading/PositionStateManager.mqh"
#include "../../Core/Trading/TradeAttributionManager.mqh"
#include "../../Core/Engines/AIEngine.mqh"
#include "../../Core/AI/AIPerformanceFeedback.mqh"
#include "../../Core/Utils/PythonBridge.mqh"
#include "../../Core/Utils/DiagnosticsLogger.mqh"
#include "../../Core/Cache/ConsensusCache.mqh"
#include "../../AIModules/NextGenStrategyBrain.mqh"
#include "../../AIModules/NeuralNetworkStrategy.mqh"
#include "../../Core/Visualization/VisualDashboard.mqh"
#include "../../Core/Risk/CompoundingTierManager.mqh"
#include "../../Core/Engines/FamilyStrategyWeightMatrix.mqh"
#include "../../Core/Engines/SessionWeightManager.mqh"
#include "../../Core/Engines/SkewStepAnalyzer.mqh"
#include "../../Core/Risk/UnprotectedPositionTracker.mqh"
#include "../../Core/Utils/ErrorHandling.mqh"

class CEAOrchestrator
{
private:
    // Core components
    CSignalGenerator          m_signalGenerator;
    CSignalValidator          m_signalValidator;
    CCandidateBuilder         m_candidateBuilder;
    CTradeExecutor            m_tradeExecutor;
    CLiveAuthorityResolver    m_liveAuthority;
    CPositionManager          m_positionManager;
    
    // Registries
    CMathematicalEngineRegistry   m_mathRegistry;
    CInstitutionalEngineRegistry  m_instRegistry;
    CNeuralNetRegistry            m_nnRegistry;
    CDrawingManagerRegistry       m_drawingRegistry;
    CScanSchedulerRegistry        m_scanScheduler;
    CSymbolStateTracker           m_symbolState;
    
    // Dependencies
    CEnterpriseStrategyManager*   m_managers[];
    string                        m_symbols[];
    int                           m_managerCount;
    CUnifiedRiskManager*          m_riskManager;
    CPositionSizer*               m_positionSizer;
    CTradeManager*                m_tradeManager;
    CRegimeEngine*                m_regimeEngine;
    CRiskTierManager*             m_riskTierManager;
    CSafeMode*                    m_safeMode;
    CFullMarginMode*              m_fullMarginMode;
    CIntelligentSLGuard*          m_slGuard;
    CTickSafetyMonitor*           m_tickSafetyMonitor;
    CSyntheticSpikeMonitor*       m_spikeMonitor;
    CSymbolScanScheduler*         m_symbolScanScheduler;
    CPositionStateManager*        m_positionStateManager;
    CTradeAttributionManager*     m_attributionManager;
    CAIEngine*                    m_aiEngine;
    CAIPerformanceFeedback*       m_aiFeedback;
    CPythonBridge*                m_pythonBridge;
    CDiagnosticsLogger*           m_diagLogger;
    CConsensusCache*              m_consensusCache;
    CNextGenStrategyBrain*        m_nextGenBrain;
    CNeuralNetworkStrategy*       m_neuralNetStrategy;
    CVisualDashboard*             m_dashboard;
    CCompoundingTierManager*      m_compoundingTierManager;
    CFamilyStrategyWeightMatrix*  m_familyWeightMatrix;
    CSessionWeightManager*        m_sessionWeightManager;
    CSkewStepAnalyzer*            m_skewStepAnalyzer;
    CUnprotectedPositionTracker*  m_unprotectedTracker;
    
    // State
    bool m_systemInitialized;
    bool m_tradingEnabled;
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
    ulong m_hbScansAttempted;
    ulong m_hbIntrabarScansExecuted;
    ulong m_hbNoSignalCount;
    ulong m_hbSignalsGenerated;
    ulong m_hbSignalsAfterPipeline;
    ulong m_hbSignalsAfterQuorum;
    ulong m_hbSignalsValidated;
    ulong m_hbSignalsRiskApproved;
    ulong m_hbSignalsSent;
    ulong m_hbEntryBlocked;
    ulong m_hbValidatorRejects;
    ulong m_hbSizingRejects;
    ulong m_hbQuietCadenceHold;
    ulong m_hbQuietNoNewBar;
    ulong m_hbQuietMissingManager;
    
    // Call counter for diagnostics
    int m_callCount;
    
    // Input parameters (would be set from EA)
    int m_minSecondsBetweenTrades;
    int m_maxPositionsTotal;
    double m_baseRiskPerTradePercent;
    double m_maxDailyRiskPercent;
    double m_maxPortfolioRiskPercent;
    double m_dailyProfitTargetPercent;
    double m_profitTrailFactor;
    double m_profitTargetHardFloorRatio;
    int m_dailyHaltCooldownMinutes;
    bool m_enableAutoModeSwitch;
    ENUM_RISK_TIER m_riskTier;
    bool m_enableScalpEngine;
    bool m_spikeHunterEnabled;
    bool m_enableAIMode;
    bool m_enableNeuralNetwork;
    bool m_enableNNOnlineTraining;
    bool m_enableNNPseudoLabeling;
    double m_aiWeightMultiplier;
    bool m_useSignalPipeline;
    int m_logLevel;
    
public:
    CEAOrchestrator() : m_systemInitialized(false), m_tradingEnabled(false),
                        m_managerCount(0), m_riskManager(NULL), m_positionSizer(NULL),
                        m_tradeManager(NULL), m_regimeEngine(NULL), m_riskTierManager(NULL),
                        m_safeMode(NULL), m_fullMarginMode(NULL), m_slGuard(NULL),
                        m_tickSafetyMonitor(NULL), m_spikeMonitor(NULL), m_symbolScanScheduler(NULL),
                        m_positionStateManager(NULL), m_attributionManager(NULL), m_aiEngine(NULL),
                        m_aiFeedback(NULL), m_pythonBridge(NULL), m_diagLogger(NULL), m_consensusCache(NULL),
                        m_nextGenBrain(NULL), m_neuralNetStrategy(NULL), m_dashboard(NULL),
                        m_compoundingTierManager(NULL), m_familyWeightMatrix(NULL),
                        m_sessionWeightManager(NULL), m_skewStepAnalyzer(NULL), m_unprotectedTracker(NULL),
                        m_lastProfitTargetDay(0), m_dailyProfitTargetReached(false), m_dailyProfitPeakPct(0),
                        m_trailingProfitFloor(0), m_dailyTradingHalt(false), m_dailyTradingHaltStartTime(0),
                        m_lastTradeTime(0), m_scanCycleSequence(0), m_cyclesSinceIndicatorSignal(0),
                        m_hybridGateRelaxed(false), m_hbScansAttempted(0), m_hbIntrabarScansExecuted(0),
                        m_hbNoSignalCount(0), m_hbSignalsGenerated(0), m_hbSignalsAfterPipeline(0),
                        m_hbSignalsAfterQuorum(0), m_hbSignalsValidated(0), m_hbSignalsRiskApproved(0),
                        m_hbSignalsSent(0), m_hbEntryBlocked(0), m_hbValidatorRejects(0),
                        m_hbSizingRejects(0), m_hbQuietCadenceHold(0), m_hbQuietNoNewBar(0),
                        m_hbQuietMissingManager(0), m_callCount(0)
    {
        ArrayResize(m_managers, 0);
        ArrayResize(m_symbols, 0);
    }
    
    ~CEAOrchestrator() {}
    
    // ============ Initialization ============
    
    bool Initialize(CEnterpriseStrategyManager* &managers[], string &symbols[], int count,
                    CUnifiedRiskManager* risk, CPositionSizer* sizer, CTradeManager* trade,
                    CRegimeEngine* regime, CRiskTierManager* riskTierManager, CSafeMode* safeMode,
                    CFullMarginMode* fullMargin, CIntelligentSLGuard* slGuard,
                    CTickSafetyMonitor* tickSafety, CSyntheticSpikeMonitor* spikeMonitor,
                    CSymbolScanScheduler* symbolScheduler, CPositionStateManager* posStateManager,
                    CTradeAttributionManager* attribManager, CAIEngine* aiEngine,
                    CAIPerformanceFeedback* aiFeedback, CPythonBridge* pythonBridge,
                    CDiagnosticsLogger* diagLogger, CConsensusCache* consensusCache,
                    CNextGenStrategyBrain* nextGenBrain, CNeuralNetworkStrategy* neuralNetStrategy,
                    CVisualDashboard* dashboard, CCompoundingTierManager* compoundingTierManager,
                    CFamilyStrategyWeightMatrix* familyWeightMatrix, CSessionWeightManager* sessionWeightManager,
                    CSkewStepAnalyzer* skewStepAnalyzer, CUnprotectedPositionTracker* unprotectedTracker,
                    // Input parameters
                    int minSecondsBetweenTrades, int maxPositionsTotal, double baseRiskPerTrade,
                    double maxDailyRisk, double maxPortfolioRisk, double dailyProfitTarget,
                    double profitTrailFactor, double profitTargetHardFloorRatio,
                    int dailyHaltCooldownMinutes, bool enableAutoModeSwitch, ENUM_RISK_TIER riskTierParam,
                    bool enableScalpEngine, bool spikeHunterEnabled, bool enableAIMode,
                    bool enableNeuralNetwork, bool enableNNOnlineTraining, bool enableNNPseudoLabeling,
                    double aiWeightMultiplier, bool useSignalPipeline, int logLevel)
    {
        // Store dependencies
        m_managerCount = count;
        ArrayResize(m_managers, count);
        ArrayResize(m_symbols, count);
        for(int i = 0; i < count; i++)
        {
            m_managers[i] = managers[i];
            m_symbols[i] = symbols[i];
        }
        
        m_riskManager = risk;
        m_positionSizer = sizer;
        m_tradeManager = trade;
        m_regimeEngine = regime;
        m_riskTierManager = riskTierManager;
        m_safeMode = safeMode;
        m_fullMarginMode = fullMargin;
        m_slGuard = slGuard;
        m_tickSafetyMonitor = tickSafety;
        m_spikeMonitor = spikeMonitor;
        m_symbolScanScheduler = symbolScheduler;
        m_positionStateManager = posStateManager;
        m_attributionManager = attribManager;
        m_aiEngine = aiEngine;
        m_aiFeedback = aiFeedback;
        m_pythonBridge = pythonBridge;
        m_diagLogger = diagLogger;
        m_consensusCache = consensusCache;
        m_nextGenBrain = nextGenBrain;
        m_neuralNetStrategy = neuralNetStrategy;
        m_dashboard = dashboard;
        m_compoundingTierManager = compoundingTierManager;
        m_familyWeightMatrix = familyWeightMatrix;
        m_sessionWeightManager = sessionWeightManager;
        m_skewStepAnalyzer = skewStepAnalyzer;
        m_unprotectedTracker = unprotectedTracker;
        
        // Store input parameters
        m_minSecondsBetweenTrades = minSecondsBetweenTrades;
        m_maxPositionsTotal = maxPositionsTotal;
        m_baseRiskPerTradePercent = baseRiskPerTrade;
        m_maxDailyRiskPercent = maxDailyRisk;
        m_maxPortfolioRiskPercent = maxPortfolioRisk;
        m_dailyProfitTargetPercent = dailyProfitTarget;
        m_profitTrailFactor = profitTrailFactor;
        m_profitTargetHardFloorRatio = profitTargetHardFloorRatio;
        m_dailyHaltCooldownMinutes = dailyHaltCooldownMinutes;
        m_enableAutoModeSwitch = enableAutoModeSwitch;
        m_riskTier = riskTierParam;
        m_enableScalpEngine = enableScalpEngine;
        m_spikeHunterEnabled = spikeHunterEnabled;
        m_enableAIMode = enableAIMode;
        m_enableNeuralNetwork = enableNeuralNetwork;
        m_enableNNOnlineTraining = enableNNOnlineTraining;
        m_enableNNPseudoLabeling = enableNNPseudoLabeling;
        m_aiWeightMultiplier = aiWeightMultiplier;
        m_useSignalPipeline = useSignalPipeline;
        m_logLevel = logLevel;
        
        // Initialize sub-components
        if(!InitializeComponents())
            return false;
        
        m_systemInitialized = true;
        m_tradingEnabled = true;
        
        Print("[EAOrchestrator] Initialized with ", count, " symbol managers");
        return true;
    }
    
    bool InitializeComponents()
    {
        // Initialize signal generator
        m_signalGenerator.Initialize(m_managers, m_symbols, m_managerCount, m_consensusCache);
        m_signalGenerator.SetEvalBudget(8, 3);
        
        // Initialize signal validator
        m_signalValidator.SetDependencies(&m_mathRegistry, &m_instRegistry, NULL, m_safeMode, m_spikeMonitor, m_fullMarginMode);
        m_signalValidator.Configure(0.65, 0.70, 1000.0, m_spikeHunterEnabled, true, true, 0.30, 0.50);
        
        // Initialize candidate builder
        m_candidateBuilder.SetDependencies(m_riskManager, m_positionSizer, m_tradeManager, NULL, NULL);
        m_candidateBuilder.Configure(2.0, 1.5, 5.0, 0.15, 1.5, 0.2, true, 0, 0, 5, 0.65, 0.55);
        
        // Initialize trade executor
        // m_tradeExecutor.SetDependencies(...);
        
        // Initialize live authority resolver
        m_liveAuthority.Configure(EA_MODE_HYBRID, 0.65, 0.5, 2, 0.3);
        
        // Initialize position manager
        if(!m_positionManager.Initialize(m_tradeManager, m_regimeEngine, m_riskTierManager, m_safeMode, m_fullMarginMode, m_slGuard, 0))
            return false;
        
        // Initialize registries
        // m_mathRegistry, m_instRegistry, etc. - initialized on demand per symbol
        
        return true;
    }
    
    // ============ Main Processing ============
    
    void OnTick()
    {
        ProcessTickSafetyLoop();
        
        // Feed microstructure engines
        FeedMicrostructureEngines();
        
        // Fast-path scalp evaluation
        if(m_enableScalpEngine)
            ProcessScalpFastPath();
    }
    
    void OnTimer()
    {
        m_callCount++;
        ProcessTradingLogic(true);
    }
    
    void ProcessTradingLogic(bool fromTimer)
    {
        if(!m_systemInitialized || !m_tradingEnabled) return;
        
        // Update risk state
        m_riskManager.RefreshRuntimeState();
        
        // Update daily profit target logic
        UpdateDailyProfitTarget();
        
        // Update auto mode switching
        UpdateAutoModeSwitch();
        
        // Check unprotected positions
        m_unprotectedTracker.AttemptRemediation();
        bool unprotectedActive = m_riskManager.HasUnprotectedPositions();
        
        // Neural network online learning
        if(m_enableAIMode && m_enableNeuralNetwork && m_enableNNOnlineTraining)
        {
            // m_nnRegistry.TickOnlineLearningAll(); // Method doesn't exist, use individual calls
            // Would iterate through symbols and call online learning per symbol
        }
        
        // AI engine adaptation
        if(m_enableAIMode && m_aiEngine != NULL)
        {
            m_aiEngine.ProcessAdaptation();
        }
        
        // AI feedback maintenance
        if(m_aiFeedback != NULL)
        {
            m_aiFeedback.CheckAutomaticRetraining();
        }
        
        // Process new bars
        ProcessNewBars();
        
        // Generate and validate signals
        GenerateAndProcessSignals();
        
        // Manage positions
        m_positionManager.ManagePositions();
    }
    
    void ProcessTickSafetyLoop()
    {
        // Would delegate to tick safety monitor
    }
    
    void FeedMicrostructureEngines()
    {
        static uint s_lastFeed = 0;
        uint nowMs = GetTickCount();
        if(nowMs - s_lastFeed >= 200)
        {
            for(int i = 0; i < m_managerCount; i++)
            {
                string sym = m_symbols[i];
                double price = SymbolInfoDouble(sym, SYMBOL_BID);
                double volume = (double)SymbolInfoInteger(sym, SYMBOL_VOLUME);
                double bid = SymbolInfoDouble(sym, SYMBOL_BID);
                double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
                
                m_mathRegistry.OnTickAll(sym, price, volume, bid, ask);
                m_instRegistry.OnTickAll(sym, price, volume, bid, ask);
            }
            s_lastFeed = nowMs;
        }
    }
    
    void ProcessScalpFastPath()
    {
        // Delegate to scalp engine
    }
    
    void UpdateDailyProfitTarget()
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
        
        if(m_dailyProfitTargetPercent > 0.0 && !m_dailyTradingHalt)
        {
            double dailyPnL = CalculateDailyPnLPercent();
            
            if(dailyPnL >= m_dailyProfitTargetPercent && !m_dailyProfitTargetReached)
            {
                m_dailyProfitTargetReached = true;
                m_dailyProfitPeakPct = dailyPnL;
                m_trailingProfitFloor = dailyPnL * m_profitTrailFactor;
            }
            
            if(m_dailyProfitTargetReached)
            {
                m_dailyProfitPeakPct = MathMax(m_dailyProfitPeakPct, dailyPnL);
                m_trailingProfitFloor = m_dailyProfitPeakPct * m_profitTrailFactor;
                
                if(dailyPnL < m_trailingProfitFloor)
                {
                    double hardFloor = m_dailyProfitTargetPercent * m_profitTargetHardFloorRatio;
                    // Would trigger selective close
                    m_dailyTradingHalt = true;
                    m_dailyTradingHaltStartTime = TimeCurrent();
                }
            }
        }
        
        if(m_dailyTradingHalt && m_dailyTradingHaltStartTime > 0)
        {
            int elapsed = (int)(TimeCurrent() - m_dailyTradingHaltStartTime) / 60;
            if(elapsed >= m_dailyHaltCooldownMinutes)
            {
                m_dailyTradingHalt = false;
                m_dailyTradingHaltStartTime = 0;
                m_dailyProfitTargetReached = false;
                m_dailyProfitPeakPct = 0.0;
                m_trailingProfitFloor = 0.0;
            }
        }
    }
    
    void UpdateAutoModeSwitch()
    {
        if(!m_enableAutoModeSwitch) return;
        
        // Would determine mode and apply risk parameters
    }
    
    void ProcessNewBars()
    {
        bool anyNewBar = false;
        
        for(int i = 0; i < m_managerCount; i++)
        {
            string symbol = m_symbols[i];
            datetime currentBar = iTime(symbol, (ENUM_TIMEFRAMES)Period(), 0);
            if(currentBar <= 0) continue;
            
            if(m_scanScheduler.CheckNewBar(symbol, currentBar))
            {
                anyNewBar = true;
                m_consensusCache.Invalidate(symbol);
                // m_scanScheduler.SetPendingNewBarScan(symbol, true); // CheckNewBar already sets this
                m_scanScheduler.ResetIntrabarBackoff(symbol);
                
                if(m_managers[i] != NULL)
                    m_managers[i].OnNewBar(symbol, (ENUM_TIMEFRAMES)Period());
                
                // AI engine adaptation
                if(m_enableAIMode && m_aiEngine != NULL)
                    m_aiEngine.ProcessAdaptation();
                
                // AI feedback
                if(m_aiFeedback != NULL)
                    m_aiFeedback.CheckAutomaticRetraining();
            }
        }
    }
    
    void GenerateAndProcessSignals()
    {
        // Check trading permissions
        if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
            return;
        
        // Check trading blocks
        int secondsSinceLastTrade = (int)(TimeCurrent() - m_lastTradeTime);
        bool cooldownBlocked = (secondsSinceLastTrade < m_minSecondsBetweenTrades && m_lastTradeTime > 0);
        int eaPositions = GetEAPositionCount();
        bool positionLimitBlocked = (eaPositions >= m_maxPositionsTotal);
        bool unprotectedBlocked = m_riskManager.HasUnprotectedPositions();
        bool spikePaused = m_spikeMonitor.IsPaused();
        
        bool canOpenNewTrades = !(cooldownBlocked || positionLimitBlocked || unprotectedBlocked || spikePaused || m_dailyTradingHalt);
        
        // Generate signals (new bar mode)
        CSignalGenerator::SSignalResult newBarSignals[];
        m_signalGenerator.GenerateSignals(EVAL_MODE_NEW_BAR, newBarSignals);
        
        // Validate and build candidates
        for(int i = 0; i < ArraySize(newBarSignals); i++)
        {
            if(!newBarSignals[i].valid) continue;
            
            string symbol = m_symbols[i];
            CEnterpriseStrategyManager* manager = m_managers[i];
            if(manager == NULL) continue;
            
            // Build candidate (declare at top of loop for scope)
            STradeCandidate candidate;
            bool candidateBuilt = false;
            
            // Validate
            CSignalValidator::SValidationResult validation = m_signalValidator.Validate(
                symbol, newBarSignals[i].signal, newBarSignals[i].confidence,
                newBarSignals[i].confluence, EVAL_MODE_NEW_BAR, newBarSignals[i].decisionContext,
                ++m_scanCycleSequence);
            
            if(!validation.passed) continue;
            
            // Build candidate
            if(!m_candidateBuilder.BuildCandidate(symbol, newBarSignals[i].signal, newBarSignals[i].confidence,
                                                  newBarSignals[i].confluence, newBarSignals[i].decisionContext,
                                                  manager, m_scanCycleSequence, candidate))
                continue;
            candidateBuilt = true;
            
            // Resolve live authority
            CLiveAuthorityResolver::SAuthorityResult authority;
            m_liveAuthority.Resolve(
                symbol, candidate.hasAIContributor, candidate.hasONNXContributor,
                candidate.hasIndicatorContributor, candidate.indicatorContributorCount,
                candidate.confluence, candidate.confidence, candidate.qualityScore,
                candidate.convictionScore, candidate.readinessScore, candidate.contextScore,
                candidate.costScore, candidate.contributorSummary, authority);
            
            candidate.liveAuthorityAllowed = authority.allowed;
            candidate.liveAuthorityRiskMult = authority.riskMultiplier;
            candidate.liveAuthorityReason = authority.reason;
            
            if(!authority.allowed) continue;
            
            // Check entry blocks
            if(!canOpenNewTrades) continue;
            
            // Execute trade
            // m_tradeExecutor.Execute(candidate);
            
            // Update heartbeat
            m_hbSignalsValidated++;
            m_hbSignalsRiskApproved++;
            m_hbSignalsSent++;
        }
    }
    
    // ============ Helpers ============
    
    int GetEAPositionCount() const
    {
        int count = 0;
        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
            if(IsEAOwnedMagic(PositionGetInteger(POSITION_MAGIC))) count++;
        }
        return count;
    }
    
    int GetEAPositionCountForSymbol(const string symbol, bool onlyThisEAMagic = true) const
    {
        if(symbol == "") return 0;
        
        int count = 0;
        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
            
            if(PositionGetString(POSITION_SYMBOL) != symbol)
                continue;
                
            if(onlyThisEAMagic && !IsEAOwnedMagic(PositionGetInteger(POSITION_MAGIC)))
                continue;
                
            count++;
        }
        return count;
    }
    
    bool IsEAOwnedMagic(long magic) const
    {
        // Simplified check
        return m_tradeManager.IsEAOwnedMagic(magic);
    }
    
    double CalculateDailyPnLPercent()
    {
        double balance = AccountInfoDouble(ACCOUNT_BALANCE);
        double equity = AccountInfoDouble(ACCOUNT_EQUITY);
        if(balance <= 0) return 0;
        return (equity - balance) / balance * 100.0;
    }
    
    // ============ Diagnostics ============
    
    string GetStatusReport() const
    {
        string report = "[EAOrchestrator] ";
        report += "Initialized=" + (m_systemInitialized ? "Y" : "N");
        report += " | Trading=" + (m_tradingEnabled ? "Y" : "N");
        report += " | Managers=" + IntegerToString(m_managerCount);
        report += " | Cycle=" + IntegerToString(m_callCount);
        report += " | Scans=" + IntegerToString(m_hbScansAttempted);
        report += " | Validated=" + IntegerToString(m_hbSignalsValidated);
        report += " | Sent=" + IntegerToString(m_hbSignalsSent);
        report += " | Positions=" + IntegerToString(GetEAPositionCount()) + "/" + IntegerToString(m_maxPositionsTotal) + "\n";
        
        report += m_signalGenerator.GetStatusReport();
        report += m_signalValidator.GetStatusReport();
        report += m_liveAuthority.GetStatusReport();
        report += m_positionManager.GetStatusReport();
        report += m_mathRegistry.GetStatusReport();
        report += m_instRegistry.GetStatusReport();
        report += m_nnRegistry.GetStatusReport();
        report += m_drawingRegistry.GetStatusReport();
        report += m_scanScheduler.GetStatusReport();
        report += m_symbolState.GetStatusReport();
        
        return report;
    }
    
    // ============ Accessors ============
    
    bool GetSystemInitialized() const { return m_systemInitialized; }
    bool GetTradingEnabled() const { return m_tradingEnabled; }
};

#endif // CORE_ORCHESTRATION_EA_ORCHESTRATOR_MQH