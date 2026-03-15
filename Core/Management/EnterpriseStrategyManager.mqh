//+------------------------------------------------------------------+
//| Enterprise Strategy Manager - Production Grade                   |
//| Central manager for all strategies with unified pipeline        |
//+------------------------------------------------------------------+
#ifndef ENTERPRISE_STRATEGY_MANAGER_MQH
#define ENTERPRISE_STRATEGY_MANAGER_MQH

#include "../Pipeline/UnifiedSignalPipeline.mqh"
#include "../Visualization/DrawingCoordinator.mqh"
#include "../../Interfaces/IStrategy.mqh"

// Retained production strategy inventory (7 kept in codebase)
#include "../../Strategies/SimpleMomentumStrategy.mqh"
#include "../../Strategies/StrategyTrend.mqh"
#include "../../Strategies/StrategyFibonacci.mqh"
#include "../../Strategies/StrategyElliottWaveEnhanced.mqh"
#include "../../Strategies/StrategySupportResistance.mqh"
#include "../../Strategies/StrategyUnifiedICT.mqh"
#include "../../Strategies/StrategyCandlestick.mqh"

// Forward declarations
class CEnhancedErrorHandler;
class CUtilities;
class CHedgingProtection;
class CMarketAnalysis;
class CModeManager;
class CNextGenStrategyBrain;
class CTransformerBrain;
struct SPredictionWithUncertainty;
class CPositionSizer;
class CStrategyManager;
class CTradeManager;
class CPerformanceAnalytics;

//+------------------------------------------------------------------+
//| Strategy Registration Entry                                     |
//+------------------------------------------------------------------+
struct StrategyEntry
{
    IStrategy* strategy;
    string name;
    bool enabled;
    bool intrabarEligible;
    bool liveVotingEnabled;
    bool shadowOnly;
    int role;
    int cluster;
    double weight;
    ENUM_TIMEFRAMES timeframe;
    int successCount;
    int failCount;
    double avgConfidence;
    ENUM_TRADE_SIGNAL lastSignal;
    double lastSignalConfidence;
    datetime lastEvaluationTime;
};

enum ENUM_SIGNAL_EVAL_MODE
{
    EVAL_MODE_NEW_BAR = 0,
    EVAL_MODE_INTRABAR = 1
};

enum ENUM_STRATEGY_ROLE
{
    PRIMARY_ALPHA = 0,
    CONTEXT_FEATURE = 1,
    SHADOW_RESEARCH = 2
};

enum ENUM_STRATEGY_CLUSTER
{
    STRATEGY_CLUSTER_NONE = 0,
    TREND_CLUSTER = 1,
    MEAN_REVERSION_CLUSTER = 2,
    STRUCTURE_CLUSTER = 3
};

string StrategyRoleToString(const ENUM_STRATEGY_ROLE role)
{
    switch(role)
    {
        case PRIMARY_ALPHA: return "PRIMARY_ALPHA";
        case CONTEXT_FEATURE: return "CONTEXT_FEATURE";
        case SHADOW_RESEARCH: return "SHADOW_RESEARCH";
        default: return "PRIMARY_ALPHA";
    }
}

string StrategyClusterToString(const ENUM_STRATEGY_CLUSTER cluster)
{
    switch(cluster)
    {
        case TREND_CLUSTER: return "TREND_CLUSTER";
        case MEAN_REVERSION_CLUSTER: return "MEAN_REVERSION_CLUSTER";
        case STRUCTURE_CLUSTER: return "STRUCTURE_CLUSTER";
        case STRATEGY_CLUSTER_NONE:
        default:
            return "NONE";
    }
}

string StrategyClusterShortCode(const ENUM_STRATEGY_CLUSTER cluster)
{
    switch(cluster)
    {
        case TREND_CLUSTER: return "T";
        case MEAN_REVERSION_CLUSTER: return "R";
        case STRUCTURE_CLUSTER: return "S";
        case STRATEGY_CLUSTER_NONE:
        default:
            return "N";
    }
}

//+------------------------------------------------------------------+
//| Enterprise Strategy Manager Class                               |
//+------------------------------------------------------------------+
class CEnterpriseStrategyManager
{
private:
    CUnifiedSignalPipeline* m_pipeline;
    CTradeManager* m_tradeManager;  // CRITICAL FIX: Store for strategy initialization
    CPositionSizer* m_positionSizer; // CRITICAL FIX: Store for strategy initialization
    
    StrategyEntry m_strategies[];
    int m_strategyCount;
    
    string m_symbol;
    ENUM_TIMEFRAMES m_baseTimeframe;
    long m_managedMagic;
    
    bool m_initialized;
    bool m_usePipeline;
    int  m_minQuorum;       // Minimum number of strategies that must agree
    int  m_intrabarMinQuorum; // Intrabar quorum floor when multiple strategies are active
    bool m_intrabarDynamicQuorumEnabled;
    double m_intrabarSingleVoterMinConfidence;
    
    // Statistics
    int m_totalSignals;
    int m_successfulSignals;
    double m_avgConfidence;

    // Last orchestrated decision context for basic trade attribution
    string m_lastSignalContributors[];
    int m_lastContributorCount;
    string m_lastSignalSymbol;
    datetime m_lastSignalTime;
    string m_lastSignalRole;
    string m_lastSignalCluster;
    string m_lastSignalClusterCode;

    // Consensus diagnostics counters
    ulong m_diagRawNone;
    ulong m_diagFilteredOut;
    ulong m_diagQuorumFailed;
    ulong m_diagIntrabarNotEligible;
    ulong m_diagSignalsGenerated;
    ulong m_diagSignalsAfterPipeline;
    ulong m_diagSignalsAfterQuorum;
    ulong m_diagVoteSuppressed;
    ulong m_diagRolePrimarySignals;
    ulong m_diagRoleFeatureSignals;
    ulong m_diagRoleShadowSignals;
    ulong m_diagClusterTrendSignals;
    ulong m_diagClusterMeanReversionSignals;
    ulong m_diagClusterStructureSignals;
    ulong m_diagClusterNoneSignals;
    ulong m_diagMomentumNone;
    ulong m_diagMomentumCooldown;
    ulong m_diagMomentumLowVolatility;
    ulong m_diagMomentumNoCrossover;
    ulong m_diagMomentumTrendMisaligned;
    ulong m_diagMomentumNotReady;
    ulong m_diagUICTNone;
    ulong m_diagUICTNeutralBias;
    ulong m_diagUICTOtherFilters;
    ulong m_diagRootBaselineRawNone;
    ulong m_diagRootBaselineFilteredOut;
    ulong m_diagRootBaselineQuorumFailed;
    ulong m_diagRootBaselineIntrabarNotEligible;
    ulong m_diagRootBaselineSignalsGenerated;
    ulong m_diagRootBaselineSignalsAfterPipeline;
    ulong m_diagRootBaselineSignalsAfterQuorum;
    ulong m_diagRootBaselineVoteSuppressed;
    ulong m_diagRootBaselineRolePrimarySignals;
    ulong m_diagRootBaselineRoleFeatureSignals;
    ulong m_diagRootBaselineRoleShadowSignals;
    ulong m_diagRootBaselineClusterTrendSignals;
    ulong m_diagRootBaselineClusterMeanReversionSignals;
    ulong m_diagRootBaselineClusterStructureSignals;
    ulong m_diagRootBaselineClusterNoneSignals;
    ulong m_diagRootBaselineMomentumNone;
    ulong m_diagRootBaselineMomentumCooldown;
    ulong m_diagRootBaselineMomentumLowVolatility;
    ulong m_diagRootBaselineMomentumNoCrossover;
    ulong m_diagRootBaselineMomentumTrendMisaligned;
    ulong m_diagRootBaselineMomentumNotReady;
    ulong m_diagRootBaselineUICTNone;
    ulong m_diagRootBaselineUICTNeutralBias;
    ulong m_diagRootBaselineUICTOtherFilters;
    ulong m_diagSnapshotBaselineRawNone;
    ulong m_diagSnapshotBaselineFilteredOut;
    ulong m_diagSnapshotBaselineQuorumFailed;
    ulong m_diagSnapshotBaselineIntrabarNotEligible;
    ulong m_diagSnapshotBaselineSignalsGenerated;
    ulong m_diagSnapshotBaselineSignalsAfterPipeline;
    ulong m_diagSnapshotBaselineSignalsAfterQuorum;
    ulong m_diagSnapshotBaselineVoteSuppressed;
    ulong m_diagSnapshotBaselineRolePrimarySignals;
    ulong m_diagSnapshotBaselineRoleFeatureSignals;
    ulong m_diagSnapshotBaselineRoleShadowSignals;
    ulong m_diagSnapshotBaselineClusterTrendSignals;
    ulong m_diagSnapshotBaselineClusterMeanReversionSignals;
    ulong m_diagSnapshotBaselineClusterStructureSignals;
    ulong m_diagSnapshotBaselineClusterNoneSignals;
    ulong m_diagSnapshotBaselineMomentumNone;
    ulong m_diagSnapshotBaselineMomentumCooldown;
    ulong m_diagSnapshotBaselineMomentumLowVolatility;
    ulong m_diagSnapshotBaselineMomentumNoCrossover;
    ulong m_diagSnapshotBaselineMomentumTrendMisaligned;
    ulong m_diagSnapshotBaselineMomentumNotReady;
    ulong m_diagSnapshotBaselineUICTNone;
    ulong m_diagSnapshotBaselineUICTNeutralBias;
    ulong m_diagSnapshotBaselineUICTOtherFilters;
    datetime m_lastDiagLogTime;
    int m_diagLogIntervalSec;

    // Last-cycle funnel snapshot (for EA-level heartbeat conversion metrics)
    int m_lastCycleSignalsGenerated;
    int m_lastCycleSignalsAfterPipeline;
    bool m_lastCycleSignalAfterQuorum;

    // Position-level contributor attribution
    ulong m_attributionPositionIds[];
    string m_attributionContributorCsv[];
    string m_closedTradeContributors[];
    double m_closedTradeNetProfit;
    bool m_hasClosedTradeAttribution;

    bool IsPositionIdStillOpen(const ulong positionId) const;
    int FindStrategyIndexByName(const string name) const;
    void MaybeLogConsensusDiagnostics(const string symbol);
    int FindAttributionIndexByPositionId(const ulong positionId) const;
    string JoinContributors(const string &contributors[]) const;
    string JoinContributorsWithContext(const int &strategyIndices[]) const;
    void SplitContributors(const string csv, string &contributors[]) const;
    void UpsertPositionAttribution(const ulong positionId, const string &contributors[]);
    bool PopPositionAttribution(const ulong positionId, string &contributors[]);
    ENUM_STRATEGY_ROLE ResolveDominantRole(const int &strategyIndices[]) const;
    ENUM_STRATEGY_CLUSTER ResolveDominantCluster(const int &strategyIndices[]) const;
    bool IsStrategyLiveVoter(const int strategyIndex) const;
    void AccumulateRoleClusterSignalDiagnostics(const int strategyIndex, const bool signalGenerated);
    
public:
    CEnterpriseStrategyManager();
    ~CEnterpriseStrategyManager();
    
    // Initialization
    bool Initialize(const string symbol, ENUM_TIMEFRAMES timeframe, 
                   bool usePipeline = true,
                   CTradeManager* tradeManagerPtr = NULL, CPositionSizer* positionSizerPtr = NULL,
                   const long managedMagic = 0);
    
    // Strategy management
    bool RegisterStrategy(IStrategy* strategy, const string name, 
                         bool enabled = true, double weight = 1.0,
                         ENUM_TIMEFRAMES tf = PERIOD_CURRENT,
                         bool intrabarEligible = false,
                         ENUM_STRATEGY_ROLE role = PRIMARY_ALPHA,
                         ENUM_STRATEGY_CLUSTER cluster = STRATEGY_CLUSTER_NONE,
                         bool liveVotingEnabled = true,
                         bool shadowOnly = false);
    bool EnableStrategy(const string name);
    bool DisableStrategy(const string name);
    void EnableAllStrategies();
    void DisableAllStrategies();
    
    // Signal generation
    ENUM_TRADE_SIGNAL GetConsensusSignal(double &confidence);
    ENUM_TRADE_SIGNAL GetConsensusSignalForSymbol(const string symbol, double &confidence);
    ENUM_TRADE_SIGNAL GetConsensusSignalWithConfluence(double &confidence, int &confluence);
    ENUM_TRADE_SIGNAL GetConsensusSignalForSymbolWithConfluence(const string symbol, double &confidence, int &confluence);
    ENUM_TRADE_SIGNAL GetConsensusSignalForSymbolWithConfluenceMode(const string symbol, double &confidence, int &confluence, ENUM_SIGNAL_EVAL_MODE evalMode);
    ENUM_TRADE_SIGNAL GetOrchestratedSignal(const string symbol, ENUM_TIMEFRAMES timeframe, double &confidence);
    ENUM_TRADE_SIGNAL GetFilteredSignal(IStrategy* strategy, double &confidence);
    
    // Configuration
    void SetPipelineFilters(SignalFilterSettings &settings);
    void SetOrchestratorMode(double minWinRate, int maxLosses);
    void SetMinQuorum(int quorum) { m_minQuorum = MathMax(1, quorum); }  // Solo Mode support
    void SetIntrabarMinQuorum(int quorum) { m_intrabarMinQuorum = MathMax(1, quorum); }
    void SetIntrabarDynamicQuorumEnabled(const bool enabled) { m_intrabarDynamicQuorumEnabled = enabled; }
    void SetIntrabarSingleVoterMinConfidence(const double minConfidence)
    {
        m_intrabarSingleVoterMinConfidence = MathMax(0.0, MathMin(1.0, minConfidence));
    }
    void SetConsensusDiagnosticsIntervalSeconds(const int seconds) { m_diagLogIntervalSec = MathMax(10, seconds); }
    int  GetMinQuorum() const { return m_minQuorum; }
    bool UpdateStrategyWeightByName(const string name, const double weight);
    bool SetStrategyIntrabarEligibilityByName(const string name, bool enabled);
    bool SetStrategyRoleByName(const string name, ENUM_STRATEGY_ROLE role);
    bool SetStrategyClusterByName(const string name, ENUM_STRATEGY_CLUSTER cluster);
    bool SetStrategyLiveVotingEligibilityByName(const string name, const bool enabled);
    bool SetStrategyShadowModeByName(const string name, const bool enabled);
    bool SetStrategyGovernanceByName(const string name,
                                     ENUM_STRATEGY_ROLE role,
                                     ENUM_STRATEGY_CLUSTER cluster,
                                     const bool liveVotingEnabled,
                                     const bool shadowOnly);
    int GetRegisteredStrategyCount() const { return m_strategyCount; }
    string GetRegisteredStrategyName(const int index) const;
    double GetRegisteredStrategyWeight(const int index) const;
    string GetRegisteredStrategyRole(const int index) const;
    string GetRegisteredStrategyCluster(const int index) const;
    bool IsRegisteredStrategyLiveVotingEnabled(const int index) const;
    bool IsRegisteredStrategyShadowOnly(const int index) const;
    void GetLastSignalContributors(string &contributors[]) const;
    bool GetLastSignalExecutionContext(string &roleTag,
                                       string &clusterTag,
                                       string &clusterCode,
                                       string &contributorsCsv) const;
    void GetRoleClusterDiagnosticsTotals(ulong &primarySignals,
                                         ulong &featureSignals,
                                         ulong &shadowSignals,
                                         ulong &voteSuppressed,
                                         ulong &trendClusterSignals,
                                         ulong &meanReversionClusterSignals,
                                         ulong &structureClusterSignals,
                                         ulong &noneClusterSignals) const;
    void GetLastCycleFunnel(int &signalsGenerated, int &signalsAfterPipeline, bool &signalAfterQuorum) const;
    void GetConsensusDiagnosticsSnapshot(ulong &rawNone,
                                         ulong &filteredOut,
                                         ulong &quorumFailed,
                                         ulong &intrabarNotEligible,
                                         ulong &signalsGenerated,
                                         ulong &signalsAfterPipeline,
                                         ulong &signalsAfterQuorum,
                                         ulong &momentumNone,
                                         ulong &momentumCooldown,
                                         ulong &momentumLowVolatility,
                                         ulong &momentumNoCrossover,
                                         ulong &momentumTrendMisaligned,
                                         ulong &momentumNotReady,
                                         ulong &uictNone,
                                         ulong &uictNeutralBias,
                                         ulong &uictOtherFilters,
                                         ulong &intervalReasonTotal);
    bool PopClosedTradeAttribution(string &contributors[], double &netProfit);
    
    // Utility
    int GetActiveStrategyCount() const;
    int GetActiveBrainStrategyCount() const;
    string GetStrategyReport() const;
    void UpdatePerformance(const string strategyName, bool success);
    
    // New bar processing - CRITICAL for zone scanning and drawing
    void OnNewBar(const string symbol, ENUM_TIMEFRAMES timeframe);
    
    // Trade Feedback - manager-owned trade outcome tracking
    void OnTradeTransaction(const MqlTradeTransaction& trans, const MqlTradeRequest& request, const MqlTradeResult& result);
    
    // Auto-registration
    void AutoRegisterStrategies(bool &enabledFlags[]);
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CEnterpriseStrategyManager::CEnterpriseStrategyManager() :
    m_pipeline(NULL),
    m_tradeManager(NULL),
    m_positionSizer(NULL),
    m_strategyCount(0),
    m_managedMagic(0),
    m_initialized(false),
    m_usePipeline(true),
    m_minQuorum(2),         // Require >=2 aligned contributors when multiple strategies are active
    m_intrabarMinQuorum(1),
    m_intrabarDynamicQuorumEnabled(true),
    m_intrabarSingleVoterMinConfidence(0.65),
    m_totalSignals(0),
    m_successfulSignals(0),
    m_avgConfidence(0),
    m_lastContributorCount(0),
    m_lastSignalSymbol(""),
    m_lastSignalTime(0),
    m_lastSignalRole("PRIMARY_ALPHA"),
    m_lastSignalCluster("NONE"),
    m_lastSignalClusterCode("N"),
    m_diagRawNone(0),
    m_diagFilteredOut(0),
    m_diagQuorumFailed(0),
    m_diagIntrabarNotEligible(0),
    m_diagSignalsGenerated(0),
    m_diagSignalsAfterPipeline(0),
    m_diagSignalsAfterQuorum(0),
    m_diagVoteSuppressed(0),
    m_diagRolePrimarySignals(0),
    m_diagRoleFeatureSignals(0),
    m_diagRoleShadowSignals(0),
    m_diagClusterTrendSignals(0),
    m_diagClusterMeanReversionSignals(0),
    m_diagClusterStructureSignals(0),
    m_diagClusterNoneSignals(0),
    m_diagMomentumNone(0),
    m_diagMomentumCooldown(0),
    m_diagMomentumLowVolatility(0),
    m_diagMomentumNoCrossover(0),
    m_diagMomentumTrendMisaligned(0),
    m_diagMomentumNotReady(0),
    m_diagUICTNone(0),
    m_diagUICTNeutralBias(0),
    m_diagUICTOtherFilters(0),
    m_diagRootBaselineRawNone(0),
    m_diagRootBaselineFilteredOut(0),
    m_diagRootBaselineQuorumFailed(0),
    m_diagRootBaselineIntrabarNotEligible(0),
    m_diagRootBaselineSignalsGenerated(0),
    m_diagRootBaselineSignalsAfterPipeline(0),
    m_diagRootBaselineSignalsAfterQuorum(0),
    m_diagRootBaselineVoteSuppressed(0),
    m_diagRootBaselineRolePrimarySignals(0),
    m_diagRootBaselineRoleFeatureSignals(0),
    m_diagRootBaselineRoleShadowSignals(0),
    m_diagRootBaselineClusterTrendSignals(0),
    m_diagRootBaselineClusterMeanReversionSignals(0),
    m_diagRootBaselineClusterStructureSignals(0),
    m_diagRootBaselineClusterNoneSignals(0),
    m_diagRootBaselineMomentumNone(0),
    m_diagRootBaselineMomentumCooldown(0),
    m_diagRootBaselineMomentumLowVolatility(0),
    m_diagRootBaselineMomentumNoCrossover(0),
    m_diagRootBaselineMomentumTrendMisaligned(0),
    m_diagRootBaselineMomentumNotReady(0),
    m_diagRootBaselineUICTNone(0),
    m_diagRootBaselineUICTNeutralBias(0),
    m_diagRootBaselineUICTOtherFilters(0),
    m_diagSnapshotBaselineRawNone(0),
    m_diagSnapshotBaselineFilteredOut(0),
    m_diagSnapshotBaselineQuorumFailed(0),
    m_diagSnapshotBaselineIntrabarNotEligible(0),
    m_diagSnapshotBaselineSignalsGenerated(0),
    m_diagSnapshotBaselineSignalsAfterPipeline(0),
    m_diagSnapshotBaselineSignalsAfterQuorum(0),
    m_diagSnapshotBaselineVoteSuppressed(0),
    m_diagSnapshotBaselineRolePrimarySignals(0),
    m_diagSnapshotBaselineRoleFeatureSignals(0),
    m_diagSnapshotBaselineRoleShadowSignals(0),
    m_diagSnapshotBaselineClusterTrendSignals(0),
    m_diagSnapshotBaselineClusterMeanReversionSignals(0),
    m_diagSnapshotBaselineClusterStructureSignals(0),
    m_diagSnapshotBaselineClusterNoneSignals(0),
    m_diagSnapshotBaselineMomentumNone(0),
    m_diagSnapshotBaselineMomentumCooldown(0),
    m_diagSnapshotBaselineMomentumLowVolatility(0),
    m_diagSnapshotBaselineMomentumNoCrossover(0),
    m_diagSnapshotBaselineMomentumTrendMisaligned(0),
    m_diagSnapshotBaselineMomentumNotReady(0),
    m_diagSnapshotBaselineUICTNone(0),
    m_diagSnapshotBaselineUICTNeutralBias(0),
    m_diagSnapshotBaselineUICTOtherFilters(0),
    m_lastDiagLogTime(0),
    m_diagLogIntervalSec(60),
    m_lastCycleSignalsGenerated(0),
    m_lastCycleSignalsAfterPipeline(0),
    m_lastCycleSignalAfterQuorum(false),
    m_closedTradeNetProfit(0.0),
    m_hasClosedTradeAttribution(false)
{
    ArrayResize(m_strategies, 0);
    ArrayResize(m_lastSignalContributors, 0);
    ArrayResize(m_attributionPositionIds, 0);
    ArrayResize(m_attributionContributorCsv, 0);
    ArrayResize(m_closedTradeContributors, 0);
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CEnterpriseStrategyManager::~CEnterpriseStrategyManager()
{
    // Clean up strategies
    for(int i = 0; i < m_strategyCount; i++)
    {
        if(m_strategies[i].strategy != NULL)
        {
            delete m_strategies[i].strategy;
            m_strategies[i].strategy = NULL;
        }
    }
    
    if(m_pipeline != NULL)
    {
        delete m_pipeline;
        m_pipeline = NULL;
    }
}

//+------------------------------------------------------------------+
//| Initialize Manager                                              |
//+------------------------------------------------------------------+
bool CEnterpriseStrategyManager::Initialize(const string symbol, ENUM_TIMEFRAMES timeframe,
                                           bool usePipeline,
                                           CTradeManager* tradeManagerPtr, CPositionSizer* positionSizerPtr,
                                           const long managedMagic)
{
    m_symbol = symbol;
    m_baseTimeframe = timeframe;
    m_managedMagic = managedMagic;
    m_usePipeline = usePipeline;
    m_tradeManager = tradeManagerPtr;   // CRITICAL FIX: Store for strategy initialization
    m_positionSizer = positionSizerPtr; // CRITICAL FIX: Store for strategy initialization
    
    // Initialize pipeline
    if(m_usePipeline)
    {
        m_pipeline = new CUnifiedSignalPipeline();
        if(m_pipeline != NULL)
        {
            SignalFilterSettings filters;
            m_pipeline.Initialize(filters);
        }
    }
    
    m_initialized = true;
    
    Print("[EnterpriseStrategyManager] Initialized for ", symbol, " on ", EnumToString(timeframe));
    Print("[EnterpriseStrategyManager] Pipeline: ", m_usePipeline ? "ENABLED" : "DISABLED");
    
    return true;
}

//+------------------------------------------------------------------+
//| Register Strategy                                               |
//+------------------------------------------------------------------+
bool CEnterpriseStrategyManager::RegisterStrategy(IStrategy* strategy, const string name,
                                                 bool enabled, double weight,
                                                 ENUM_TIMEFRAMES tf,
                                                 bool intrabarEligible,
                                                 ENUM_STRATEGY_ROLE role,
                                                 ENUM_STRATEGY_CLUSTER cluster,
                                                 bool liveVotingEnabled,
                                                 bool shadowOnly)
{
    if(strategy == NULL || !m_initialized)
        return false;
    
    // Initialize strategy with VALID pointers
    ENUM_TIMEFRAMES resolvedTf = (tf == PERIOD_CURRENT ? m_baseTimeframe : tf);
    bool initSuccess = strategy.Init(m_symbol, resolvedTf,
                                     m_tradeManager, m_positionSizer);
    
    if(!initSuccess)
    {
        Print("[EnterpriseStrategyManager] ERROR: Strategy ", name, " initialization failed. Skipping registration.");
        delete strategy;
        return false;
    }
    
    // CRITICAL FIX: Synchronize enabled state with strategy object
    strategy.SetEnabled(enabled);
    strategy.SetWeight(weight);
    
    // Add to array
    int newSize = m_strategyCount + 1;
    ArrayResize(m_strategies, newSize);
    
    m_strategies[m_strategyCount].strategy = strategy;
    m_strategies[m_strategyCount].name = name;
    m_strategies[m_strategyCount].enabled = enabled;
    m_strategies[m_strategyCount].intrabarEligible = intrabarEligible;
    m_strategies[m_strategyCount].liveVotingEnabled = liveVotingEnabled;
    m_strategies[m_strategyCount].shadowOnly = shadowOnly;
    m_strategies[m_strategyCount].role = (int)role;
    m_strategies[m_strategyCount].cluster = (int)cluster;
    m_strategies[m_strategyCount].weight = weight;
    m_strategies[m_strategyCount].timeframe = resolvedTf;
    m_strategies[m_strategyCount].successCount = 0;
    m_strategies[m_strategyCount].failCount = 0;
    m_strategies[m_strategyCount].avgConfidence = 0;
    m_strategies[m_strategyCount].lastSignal = TRADE_SIGNAL_NONE;
    m_strategies[m_strategyCount].lastSignalConfidence = 0.0;
    m_strategies[m_strategyCount].lastEvaluationTime = 0;
    
    m_strategyCount++;
    
    Print("[EnterpriseStrategyManager] Registered strategy: ", name, 
          " | Enabled: ", enabled, " | Weight: ", weight,
          " | Intrabar: ", intrabarEligible ? "YES" : "NO",
          " | Role: ", StrategyRoleToString(role),
          " | Cluster: ", StrategyClusterToString(cluster),
          " | LiveVote: ", liveVotingEnabled ? "YES" : "NO",
          " | Shadow: ", shadowOnly ? "YES" : "NO");
    
    return true;
}

//+------------------------------------------------------------------+
//| Get Consensus Signal (Enhanced with Confluence Tracking)        |
//+------------------------------------------------------------------+
ENUM_TRADE_SIGNAL CEnterpriseStrategyManager::GetConsensusSignal(double &confidence)
{
    int confluence = 0;
    return GetConsensusSignalWithConfluence(confidence, confluence);
}

//+------------------------------------------------------------------+
//| Get Consensus Signal With Confluence                            |
//+------------------------------------------------------------------+
ENUM_TRADE_SIGNAL CEnterpriseStrategyManager::GetConsensusSignalWithConfluence(double &confidence, int &confluence)
{
    return GetConsensusSignalForSymbolWithConfluence(m_symbol, confidence, confluence);
}

//+------------------------------------------------------------------+
//| Get Consensus Signal For Specific Symbol With Confluence        |
//+------------------------------------------------------------------+
ENUM_TRADE_SIGNAL CEnterpriseStrategyManager::GetConsensusSignalForSymbolWithConfluence(const string symbol, double &confidence, int &confluence)
{
    return GetConsensusSignalForSymbolWithConfluenceMode(symbol, confidence, confluence, EVAL_MODE_NEW_BAR);
}

ENUM_TRADE_SIGNAL CEnterpriseStrategyManager::GetConsensusSignalForSymbolWithConfluenceMode(const string symbol,
                                                                                              double &confidence,
                                                                                              int &confluence,
                                                                                              ENUM_SIGNAL_EVAL_MODE evalMode)
{
    confluence = 0;
    confidence = 0;

    if(!m_initialized || m_strategyCount == 0)
    {
        return TRADE_SIGNAL_NONE;
    }

    // Strategies are bound to the manager symbol; reject mismatched symbol requests.
    if(symbol != m_symbol)
    {
        PrintFormat("[CRITICAL] Cross-symbol request rejected in EnterpriseManager. Requested: %s, Bound: %s", symbol, m_symbol);
        return TRADE_SIGNAL_NONE;
    }
    
    int cycleRawNone = 0;
    int cycleFilteredOut = 0;
    int cycleQuorumFailed = 0;
    int cycleIntrabarNotEligible = 0;
    int cycleSignalsGenerated = 0;
    int cycleSignalsAfterPipeline = 0;
    int cycleSignalsAfterQuorum = 0;
    int cycleVoteSuppressed = 0;
    int intrabarEligibleActiveCount = 0;
    m_lastCycleSignalsGenerated = 0;
    m_lastCycleSignalsAfterPipeline = 0;
    m_lastCycleSignalAfterQuorum = false;

    // Store original symbol for restoration
    string originalSymbol = m_symbol;

    // Temporarily switch context to target symbol
    m_symbol = symbol;

    int buyVotes = 0, sellVotes = 0;
    double buyConf = 0, sellConf = 0;
    double buyWeightSum = 0.0, sellWeightSum = 0.0;
    int activeStrategies = 0;
    int activeLiveStrategies = 0;
    string buyContributors[];
    string sellContributors[];
    int buyContributorIndices[];
    int sellContributorIndices[];
    ArrayResize(buyContributors, 0);
    ArrayResize(sellContributors, 0);
    ArrayResize(buyContributorIndices, 0);
    ArrayResize(sellContributorIndices, 0);

    if(m_usePipeline && m_pipeline != NULL)
        m_pipeline.SetIntrabarContext(evalMode == EVAL_MODE_INTRABAR);

    for(int i = 0; i < m_strategyCount; i++)
    {
        if(!m_strategies[i].enabled)
            continue;

        bool liveVoter = IsStrategyLiveVoter(i);
        if(liveVoter)
        {
            activeLiveStrategies++;
            if(evalMode == EVAL_MODE_INTRABAR)
            {
                if(m_strategies[i].intrabarEligible)
                    intrabarEligibleActiveCount++;
                else
                    cycleIntrabarNotEligible++;
            }
        }

        double stratConf = 0.0;
        ENUM_TRADE_SIGNAL signal = TRADE_SIGNAL_NONE;

        // Get signal (filtered if pipeline enabled)
        if(m_usePipeline && m_pipeline != NULL)
        {
            signal = m_pipeline.ProcessSignal(m_strategies[i].strategy,
                                              symbol,
                                              m_strategies[i].timeframe,
                                              stratConf);
            bool rawNone = m_pipeline.WasLastSignalRawNone();
            bool filteredByPipeline = m_pipeline.WasLastSignalFilteredByPipeline();
            if(rawNone)
                cycleRawNone++;
            else
                cycleSignalsGenerated++;
            if(filteredByPipeline)
                cycleFilteredOut++;
            if(signal != TRADE_SIGNAL_NONE)
                cycleSignalsAfterPipeline++;
        }
        else
        {
            signal = m_strategies[i].strategy.GetSignal(stratConf);
            if(signal == TRADE_SIGNAL_NONE)
                cycleRawNone++;
            else
            {
                cycleSignalsGenerated++;
                cycleSignalsAfterPipeline++;
            }
        }

        string decisionReasonTag = m_strategies[i].strategy.GetLastDecisionReasonTag();
        if(signal == TRADE_SIGNAL_NONE)
        {
            if(m_strategies[i].name == "Momentum")
            {
                m_diagMomentumNone++;
                if(decisionReasonTag == "MOMENTUM_COOLDOWN" || decisionReasonTag == "MOMENTUM_SAME_BAR_GUARD")
                    m_diagMomentumCooldown++;
                else if(decisionReasonTag == "MOMENTUM_LOW_VOLATILITY")
                    m_diagMomentumLowVolatility++;
                else if(decisionReasonTag == "MOMENTUM_NO_CROSSOVER")
                    m_diagMomentumNoCrossover++;
                else if(decisionReasonTag == "MOMENTUM_TREND_MISALIGNED")
                    m_diagMomentumTrendMisaligned++;
                else
                    m_diagMomentumNotReady++;
            }
            else if(m_strategies[i].name == "Unified ICT")
            {
                m_diagUICTNone++;
                if(decisionReasonTag == "UICT_NEUTRAL_BIAS")
                    m_diagUICTNeutralBias++;
                else
                    m_diagUICTOtherFilters++;
            }
        }
        else
        {
            AccumulateRoleClusterSignalDiagnostics(i, true);
        }

        m_strategies[i].lastSignal = signal;
        m_strategies[i].lastSignalConfidence = stratConf;
        m_strategies[i].lastEvaluationTime = TimeCurrent();

        if(!liveVoter)
        {
            if(signal != TRADE_SIGNAL_NONE)
                cycleVoteSuppressed++;
            activeStrategies++;
            continue;
        }

        if(evalMode == EVAL_MODE_INTRABAR && !m_strategies[i].intrabarEligible)
        {
            activeStrategies++;
            continue;
        }

        double strategyWeight = MathMax(0.0, m_strategies[i].weight);
        if(strategyWeight <= 0.0)
            strategyWeight = 1.0;

        if(signal == TRADE_SIGNAL_BUY)
        {
            buyVotes++;
            buyConf += stratConf * strategyWeight;
            buyWeightSum += strategyWeight;

            int buySize = ArraySize(buyContributors);
            ArrayResize(buyContributors, buySize + 1);
            ArrayResize(buyContributorIndices, buySize + 1);
            buyContributors[buySize] = m_strategies[i].name;
            buyContributorIndices[buySize] = i;
        }
        else if(signal == TRADE_SIGNAL_SELL)
        {
            sellVotes++;
            sellConf += stratConf * strategyWeight;
            sellWeightSum += strategyWeight;

            int sellSize = ArraySize(sellContributors);
            ArrayResize(sellContributors, sellSize + 1);
            ArrayResize(sellContributorIndices, sellSize + 1);
            sellContributors[sellSize] = m_strategies[i].name;
            sellContributorIndices[sellSize] = i;
        }

        activeStrategies++;
    }

    // Restore original symbol
    m_symbol = originalSymbol;

    m_diagRawNone += (ulong)MathMax(0, cycleRawNone);
    m_diagFilteredOut += (ulong)MathMax(0, cycleFilteredOut);
    m_diagIntrabarNotEligible += (ulong)MathMax(0, cycleIntrabarNotEligible);
    m_diagSignalsGenerated += (ulong)MathMax(0, cycleSignalsGenerated);
    m_diagSignalsAfterPipeline += (ulong)MathMax(0, cycleSignalsAfterPipeline);
    m_diagVoteSuppressed += (ulong)MathMax(0, cycleVoteSuppressed);

    if(activeLiveStrategies == 0)
    {
        m_lastCycleSignalsGenerated = MathMax(0, cycleSignalsGenerated);
        m_lastCycleSignalsAfterPipeline = MathMax(0, cycleSignalsAfterPipeline);
        m_lastCycleSignalAfterQuorum = false;
        m_lastSignalRole = "PRIMARY_ALPHA";
        m_lastSignalCluster = "NONE";
        m_lastSignalClusterCode = "N";
        MaybeLogConsensusDiagnostics(symbol);
        return TRADE_SIGNAL_NONE;
    }

    int cycleLiveContributorCount = buyVotes + sellVotes;
    int effectiveQuorum = m_minQuorum;
    if(evalMode == EVAL_MODE_INTRABAR)
    {
        if(m_intrabarDynamicQuorumEnabled)
        {
            // Dynamic intrabar quorum must reflect actual live contributors this cycle,
            // not just the pool of eligible strategies, otherwise one strong voter can
            // be deadlocked by multiple silent voters.
            if(cycleLiveContributorCount <= 1)
                effectiveQuorum = 1;
            else
                effectiveQuorum = MathMin(m_intrabarMinQuorum,
                                          MathMin(intrabarEligibleActiveCount, cycleLiveContributorCount));
        }
        else
        {
            effectiveQuorum = m_intrabarMinQuorum;
        }
    }
    else if(activeLiveStrategies == 1)
        effectiveQuorum = 1;
    effectiveQuorum = MathMax(1, MathMin(effectiveQuorum, activeLiveStrategies));

    bool buyQuorumMet = (buyVotes >= effectiveQuorum);
    bool sellQuorumMet = (sellVotes >= effectiveQuorum);

    ENUM_TRADE_SIGNAL finalSignal = TRADE_SIGNAL_NONE;
    double finalConfidence = 0.0;
    int finalConfluence = 0;
    string selectedContributors[];
    int selectedContributorIndices[];
    ArrayResize(selectedContributors, 0);
    ArrayResize(selectedContributorIndices, 0);

    if(buyQuorumMet && (!sellQuorumMet || buyConf > sellConf))
    {
        finalSignal = TRADE_SIGNAL_BUY;
        finalConfluence = buyVotes;
        finalConfidence = (buyWeightSum > 0.0) ? (buyConf / buyWeightSum) : 0.0;
        ArrayCopy(selectedContributors, buyContributors);
        ArrayCopy(selectedContributorIndices, buyContributorIndices);
    }
    else if(sellQuorumMet && (!buyQuorumMet || sellConf > buyConf))
    {
        finalSignal = TRADE_SIGNAL_SELL;
        finalConfluence = sellVotes;
        finalConfidence = (sellWeightSum > 0.0) ? (sellConf / sellWeightSum) : 0.0;
        ArrayCopy(selectedContributors, sellContributors);
        ArrayCopy(selectedContributorIndices, sellContributorIndices);
    }
    else
    {
        if((buyVotes + sellVotes) > 0)
            cycleQuorumFailed++;
    }

    // Intrabar safety gate: single-voter signal requires stronger confidence.
    if(finalSignal != TRADE_SIGNAL_NONE &&
       evalMode == EVAL_MODE_INTRABAR &&
       effectiveQuorum == 1 &&
       finalConfidence < m_intrabarSingleVoterMinConfidence)
    {
        cycleQuorumFailed++;
        finalSignal = TRADE_SIGNAL_NONE;
        finalConfidence = 0.0;
        finalConfluence = 0;
        ArrayResize(selectedContributors, 0);
        ArrayResize(selectedContributorIndices, 0);
    }

    m_diagQuorumFailed += (ulong)MathMax(0, cycleQuorumFailed);

    if(finalSignal != TRADE_SIGNAL_NONE)
    {
        cycleSignalsAfterQuorum = 1;
        m_diagSignalsAfterQuorum += 1;
        confluence = finalConfluence;
        confidence = MathMax(0.0, MathMin(1.0, finalConfidence));
        m_totalSignals++;

        m_lastSignalSymbol = symbol;
        m_lastSignalTime = TimeCurrent();
        ArrayCopy(m_lastSignalContributors, selectedContributors);
        m_lastContributorCount = ArraySize(m_lastSignalContributors);
        ENUM_STRATEGY_ROLE dominantRole = ResolveDominantRole(selectedContributorIndices);
        ENUM_STRATEGY_CLUSTER dominantCluster = ResolveDominantCluster(selectedContributorIndices);
        m_lastSignalRole = StrategyRoleToString(dominantRole);
        m_lastSignalCluster = StrategyClusterToString(dominantCluster);
        m_lastSignalClusterCode = StrategyClusterShortCode(dominantCluster);
        m_lastCycleSignalsGenerated = MathMax(0, cycleSignalsGenerated);
        m_lastCycleSignalsAfterPipeline = MathMax(0, cycleSignalsAfterPipeline);
        m_lastCycleSignalAfterQuorum = true;

        MaybeLogConsensusDiagnostics(symbol);
        return finalSignal;
    }

    confidence = 0;
    confluence = 0;
    m_lastContributorCount = 0;
    ArrayResize(m_lastSignalContributors, 0);
    m_lastSignalRole = "PRIMARY_ALPHA";
    m_lastSignalCluster = "NONE";
    m_lastSignalClusterCode = "N";
    m_lastCycleSignalsGenerated = MathMax(0, cycleSignalsGenerated);
    m_lastCycleSignalsAfterPipeline = MathMax(0, cycleSignalsAfterPipeline);
    m_lastCycleSignalAfterQuorum = (cycleSignalsAfterQuorum > 0);
    MaybeLogConsensusDiagnostics(symbol);
    return TRADE_SIGNAL_NONE;
}

//+------------------------------------------------------------------+
//| Get Consensus Signal For Specific Symbol                        |
//+------------------------------------------------------------------+
ENUM_TRADE_SIGNAL CEnterpriseStrategyManager::GetConsensusSignalForSymbol(const string symbol, double &confidence)
{
    int confluence = 0;
    return GetConsensusSignalForSymbolWithConfluence(symbol, confidence, confluence);
}

//+------------------------------------------------------------------+
//| Get Orchestrated Signal                                         |
//+------------------------------------------------------------------+
ENUM_TRADE_SIGNAL CEnterpriseStrategyManager::GetOrchestratedSignal(const string symbol, ENUM_TIMEFRAMES timeframe, double &confidence)
{
    // Legacy compatibility method: the orchestrator path is retired.
    // Delegate to manager-owned consensus logic and preserve confluence/quorum behavior.
    int confluence = 0;
    ENUM_TRADE_SIGNAL signal = GetConsensusSignalForSymbolWithConfluence(symbol, confidence, confluence);
    if(signal == TRADE_SIGNAL_NONE)
        ArrayResize(m_lastSignalContributors, 0);
    return signal;
}

//+------------------------------------------------------------------+
//| Auto-register Strategies                                        |
//+------------------------------------------------------------------+
void CEnterpriseStrategyManager::AutoRegisterStrategies(bool &flags[])
{
    int size = ArraySize(flags);
    
    // 0: Momentum (primary trend voter)
    if(size > 0 && flags[0]) RegisterStrategy(new CSimpleMomentumStrategy(), "Momentum", true, 1.0, PERIOD_CURRENT, false,
                                             PRIMARY_ALPHA, TREND_CLUSTER, true, false);
    
    // 1: Trend (primary trend voter)
    if(size > 1 && flags[1]) RegisterStrategy(new CStrategyTrend(), "Trend", true, 1.2, PERIOD_CURRENT, false,
                                             PRIMARY_ALPHA, TREND_CLUSTER, true, false);
    
    // 2: Fibonacci (context feature by default)
    if(size > 2 && flags[2]) RegisterStrategy(new CStrategyFibonacci(), "Fibonacci", true, 1.2, PERIOD_CURRENT, false,
                                             CONTEXT_FEATURE, MEAN_REVERSION_CLUSTER, false, true);
    
    // 3: Elliott Wave (shadow research by default)
    if(size > 3 && flags[3]) RegisterStrategy(new CStrategyElliottWaveEnhanced(), "Elliott Wave", true, 2.0, PERIOD_CURRENT, false,
                                             SHADOW_RESEARCH, STRUCTURE_CLUSTER, false, true);
    
    // 4: Support/Resistance (shadow research by default)
    if(size > 4 && flags[4]) RegisterStrategy(new CStrategySupportResistance(), "Support/Resistance", true, 1.5, PERIOD_CURRENT, false,
                                             SHADOW_RESEARCH, MEAN_REVERSION_CLUSTER, false, true);
    
    // 5: Unified ICT (primary structure voter)
    if(size > 5 && flags[5]) RegisterStrategy(new CStrategyUnifiedICT(), "Unified ICT", true, 2.2, PERIOD_CURRENT, false,
                                             PRIMARY_ALPHA, STRUCTURE_CLUSTER, true, false);
    
    // 6: Candlestick (context feature by default)
    if(size > 6 && flags[6]) RegisterStrategy(new CStrategyCandlestick(), "Candlestick", true, 1.5, PERIOD_CURRENT, false,
                                             CONTEXT_FEATURE, STRUCTURE_CLUSTER, false, true);
    
    Print("[EnterpriseStrategyManager] Auto-registration complete. Active strategies: ", 
          GetActiveStrategyCount());
}

//+------------------------------------------------------------------+
//| Get Active Strategy Count                                       |
//+------------------------------------------------------------------+
int CEnterpriseStrategyManager::GetActiveStrategyCount() const
{
    int count = 0;
    for(int i = 0; i < m_strategyCount; i++)
    {
        if(m_strategies[i].enabled)
            count++;
    }
    return count;
}

//+------------------------------------------------------------------+
//| Get Active Brain Strategy Count                                  |
//+------------------------------------------------------------------+
int CEnterpriseStrategyManager::GetActiveBrainStrategyCount() const
{
    int count = 0;
    for(int i = 0; i < m_strategyCount; i++)
    {
        if(!m_strategies[i].enabled || m_strategies[i].strategy == NULL)
            continue;

        ENUM_STRATEGY_TYPE strategyType = m_strategies[i].strategy.GetType();
        if(strategyType == STRATEGY_BRAIN || strategyType == STRATEGY_AI_ENHANCED)
            count++;
    }

    return count;
}

//+------------------------------------------------------------------+
//| Get Strategy Report                                             |
//+------------------------------------------------------------------+
string CEnterpriseStrategyManager::GetStrategyReport() const
{
    string report = "=== Enterprise Strategy Report ===\n";
    report += StringFormat("Total Strategies: %d | Active: %d\n", 
                         m_strategyCount, GetActiveStrategyCount());
    report += StringFormat("Total Signals: %d | Success Rate: %.1f%%\n",
                         m_totalSignals, 
                         m_totalSignals > 0 ? (double)m_successfulSignals/m_totalSignals*100 : 0);
    
    report += "\nStrategy Performance:\n";
    for(int i = 0; i < m_strategyCount; i++)
    {
        int total = m_strategies[i].successCount + m_strategies[i].failCount;
        double winRate = total > 0 ? (double)m_strategies[i].successCount/total*100 : 0;
        
        report += StringFormat("- %s: %s | Role: %s | Cluster: %s | LiveVote: %s | Trades: %d | Win Rate: %.1f%% | Avg Conf: %.2f\n",
                             m_strategies[i].name,
                             m_strategies[i].enabled ? "ON" : "OFF",
                             StrategyRoleToString((ENUM_STRATEGY_ROLE)m_strategies[i].role),
                             StrategyClusterToString((ENUM_STRATEGY_CLUSTER)m_strategies[i].cluster),
                             IsStrategyLiveVoter(i) ? "YES" : "NO",
                             total, winRate, m_strategies[i].avgConfidence);
    }
    
    if(m_pipeline != NULL)
    {
        report += StringFormat("\nPipeline Stats: Processed: %d | Filtered: %d | Filter Rate: %.1f%%\n",
                             m_pipeline.GetSignalsProcessed(),
                             m_pipeline.GetSignalsFiltered(),
                             m_pipeline.GetFilterRate() * 100);
    }
    
    return report;
}

//+------------------------------------------------------------------+
//| Set Pipeline Filters                                             |
//+------------------------------------------------------------------+
void CEnterpriseStrategyManager::SetPipelineFilters(SignalFilterSettings &settings)
{
    if(m_pipeline != NULL)
    {
        // Apply runtime filter configuration without re-initializing pipeline engines.
        m_pipeline.SetFilters(settings);
        Print("[EnterpriseStrategyManager] Pipeline filters applied: TrendFilter=",
              settings.enableTrendFilter, " MinConf=", settings.minConfidence,
              " IntrabarCap=", settings.intrabarConfidenceCap,
              " RegimeCost=", settings.enableRegimeCostGate,
              " MaxSpreadATR=", settings.maxSpreadToAtrRatio,
              " ShockCooldown=", settings.spreadShockCooldownSeconds,
              " MaxEntryZ=", settings.maxEntryRangeZScore,
              " MaxVol=", settings.maxVolatility,
              " StructureFilter=", settings.enableStructureFilter,
              " LiquidityFilter=", settings.enableLiquidityFilter);
    }
}

//+------------------------------------------------------------------+
//| Set Orchestrator Mode                                            |
//+------------------------------------------------------------------+
void CEnterpriseStrategyManager::SetOrchestratorMode(double minWinRate, int maxLosses)
{
    double clampedWinRate = MathMax(0.0, MathMin(1.0, minWinRate));
    int clampedMaxLosses = MathMax(1, maxLosses);
    PrintFormat("[EnterpriseStrategyManager] SetOrchestratorMode ignored (manager-only governance mode) | Requested MinWinRate=%.2f | MaxConsecutiveLosses=%d",
                clampedWinRate, clampedMaxLosses);
}

bool CEnterpriseStrategyManager::UpdateStrategyWeightByName(const string name, const double weight)
{
    int index = FindStrategyIndexByName(name);
    if(index < 0)
        return false;

    double sanitizedWeight = MathMax(0.0, MathMin(10.0, weight));
    m_strategies[index].weight = sanitizedWeight;
    if(m_strategies[index].strategy != NULL)
        m_strategies[index].strategy.SetWeight(sanitizedWeight);

    return true;
}

bool CEnterpriseStrategyManager::SetStrategyIntrabarEligibilityByName(const string name, bool enabled)
{
    int index = FindStrategyIndexByName(name);
    if(index < 0)
        return false;

    m_strategies[index].intrabarEligible = enabled;
    PrintFormat("[EnterpriseStrategyManager] Intrabar eligibility updated: %s => %s",
                name, enabled ? "ENABLED" : "DISABLED");
    return true;
}

bool CEnterpriseStrategyManager::SetStrategyRoleByName(const string name, ENUM_STRATEGY_ROLE role)
{
    int index = FindStrategyIndexByName(name);
    if(index < 0)
        return false;

    m_strategies[index].role = (int)role;
    PrintFormat("[EnterpriseStrategyManager] Role updated: %s => %s",
                name, StrategyRoleToString(role));
    return true;
}

bool CEnterpriseStrategyManager::SetStrategyClusterByName(const string name, ENUM_STRATEGY_CLUSTER cluster)
{
    int index = FindStrategyIndexByName(name);
    if(index < 0)
        return false;

    m_strategies[index].cluster = (int)cluster;
    PrintFormat("[EnterpriseStrategyManager] Cluster updated: %s => %s",
                name, StrategyClusterToString(cluster));
    return true;
}

bool CEnterpriseStrategyManager::SetStrategyLiveVotingEligibilityByName(const string name, const bool enabled)
{
    int index = FindStrategyIndexByName(name);
    if(index < 0)
        return false;

    m_strategies[index].liveVotingEnabled = enabled;
    PrintFormat("[EnterpriseStrategyManager] Live voting updated: %s => %s",
                name, enabled ? "ENABLED" : "DISABLED");
    return true;
}

bool CEnterpriseStrategyManager::SetStrategyShadowModeByName(const string name, const bool enabled)
{
    int index = FindStrategyIndexByName(name);
    if(index < 0)
        return false;

    m_strategies[index].shadowOnly = enabled;
    if(enabled)
        m_strategies[index].liveVotingEnabled = false;

    PrintFormat("[EnterpriseStrategyManager] Shadow mode updated: %s => %s",
                name, enabled ? "ENABLED" : "DISABLED");
    return true;
}

bool CEnterpriseStrategyManager::SetStrategyGovernanceByName(const string name,
                                                             ENUM_STRATEGY_ROLE role,
                                                             ENUM_STRATEGY_CLUSTER cluster,
                                                             const bool liveVotingEnabled,
                                                             const bool shadowOnly)
{
    int index = FindStrategyIndexByName(name);
    if(index < 0)
        return false;

    m_strategies[index].role = (int)role;
    m_strategies[index].cluster = (int)cluster;
    m_strategies[index].shadowOnly = shadowOnly;
    m_strategies[index].liveVotingEnabled = (shadowOnly ? false : liveVotingEnabled);

    PrintFormat("[EnterpriseStrategyManager] Governance updated: %s | role=%s | cluster=%s | live_vote=%s | shadow=%s",
                name,
                StrategyRoleToString(role),
                StrategyClusterToString(cluster),
                m_strategies[index].liveVotingEnabled ? "ENABLED" : "DISABLED",
                shadowOnly ? "ENABLED" : "DISABLED");
    return true;
}

string CEnterpriseStrategyManager::GetRegisteredStrategyName(const int index) const
{
    if(index < 0 || index >= m_strategyCount)
        return "";
    return m_strategies[index].name;
}

double CEnterpriseStrategyManager::GetRegisteredStrategyWeight(const int index) const
{
    if(index < 0 || index >= m_strategyCount)
        return 0.0;
    return m_strategies[index].weight;
}

string CEnterpriseStrategyManager::GetRegisteredStrategyRole(const int index) const
{
    if(index < 0 || index >= m_strategyCount)
        return "";
    return StrategyRoleToString((ENUM_STRATEGY_ROLE)m_strategies[index].role);
}

string CEnterpriseStrategyManager::GetRegisteredStrategyCluster(const int index) const
{
    if(index < 0 || index >= m_strategyCount)
        return "";
    return StrategyClusterToString((ENUM_STRATEGY_CLUSTER)m_strategies[index].cluster);
}

bool CEnterpriseStrategyManager::IsRegisteredStrategyLiveVotingEnabled(const int index) const
{
    if(index < 0 || index >= m_strategyCount)
        return false;
    return m_strategies[index].liveVotingEnabled;
}

bool CEnterpriseStrategyManager::IsRegisteredStrategyShadowOnly(const int index) const
{
    if(index < 0 || index >= m_strategyCount)
        return false;
    return m_strategies[index].shadowOnly;
}

void CEnterpriseStrategyManager::GetLastSignalContributors(string &contributors[]) const
{
    ArrayCopy(contributors, m_lastSignalContributors);
}

bool CEnterpriseStrategyManager::GetLastSignalExecutionContext(string &roleTag,
                                                               string &clusterTag,
                                                               string &clusterCode,
                                                               string &contributorsCsv) const
{
    roleTag = m_lastSignalRole;
    clusterTag = m_lastSignalCluster;
    clusterCode = m_lastSignalClusterCode;
    contributorsCsv = JoinContributors(m_lastSignalContributors);
    return (m_lastContributorCount > 0 && ArraySize(m_lastSignalContributors) > 0);
}

void CEnterpriseStrategyManager::GetRoleClusterDiagnosticsTotals(ulong &primarySignals,
                                                                 ulong &featureSignals,
                                                                 ulong &shadowSignals,
                                                                 ulong &voteSuppressed,
                                                                 ulong &trendClusterSignals,
                                                                 ulong &meanReversionClusterSignals,
                                                                 ulong &structureClusterSignals,
                                                                 ulong &noneClusterSignals) const
{
    primarySignals = m_diagRolePrimarySignals;
    featureSignals = m_diagRoleFeatureSignals;
    shadowSignals = m_diagRoleShadowSignals;
    voteSuppressed = m_diagVoteSuppressed;
    trendClusterSignals = m_diagClusterTrendSignals;
    meanReversionClusterSignals = m_diagClusterMeanReversionSignals;
    structureClusterSignals = m_diagClusterStructureSignals;
    noneClusterSignals = m_diagClusterNoneSignals;
}

void CEnterpriseStrategyManager::GetLastCycleFunnel(int &signalsGenerated, int &signalsAfterPipeline, bool &signalAfterQuorum) const
{
    signalsGenerated = m_lastCycleSignalsGenerated;
    signalsAfterPipeline = m_lastCycleSignalsAfterPipeline;
    signalAfterQuorum = m_lastCycleSignalAfterQuorum;
}

void CEnterpriseStrategyManager::GetConsensusDiagnosticsSnapshot(ulong &rawNone,
                                                                 ulong &filteredOut,
                                                                 ulong &quorumFailed,
                                                                 ulong &intrabarNotEligible,
                                                                 ulong &signalsGenerated,
                                                                 ulong &signalsAfterPipeline,
                                                                 ulong &signalsAfterQuorum,
                                                                 ulong &momentumNone,
                                                                 ulong &momentumCooldown,
                                                                 ulong &momentumLowVolatility,
                                                                 ulong &momentumNoCrossover,
                                                                 ulong &momentumTrendMisaligned,
                                                                 ulong &momentumNotReady,
                                                                 ulong &uictNone,
                                                                 ulong &uictNeutralBias,
                                                                 ulong &uictOtherFilters,
                                                                 ulong &intervalReasonTotal)
{
    rawNone = (m_diagRawNone - m_diagSnapshotBaselineRawNone);
    filteredOut = (m_diagFilteredOut - m_diagSnapshotBaselineFilteredOut);
    quorumFailed = (m_diagQuorumFailed - m_diagSnapshotBaselineQuorumFailed);
    intrabarNotEligible = (m_diagIntrabarNotEligible - m_diagSnapshotBaselineIntrabarNotEligible);
    signalsGenerated = (m_diagSignalsGenerated - m_diagSnapshotBaselineSignalsGenerated);
    signalsAfterPipeline = (m_diagSignalsAfterPipeline - m_diagSnapshotBaselineSignalsAfterPipeline);
    signalsAfterQuorum = (m_diagSignalsAfterQuorum - m_diagSnapshotBaselineSignalsAfterQuorum);
    momentumNone = (m_diagMomentumNone - m_diagSnapshotBaselineMomentumNone);
    momentumCooldown = (m_diagMomentumCooldown - m_diagSnapshotBaselineMomentumCooldown);
    momentumLowVolatility = (m_diagMomentumLowVolatility - m_diagSnapshotBaselineMomentumLowVolatility);
    momentumNoCrossover = (m_diagMomentumNoCrossover - m_diagSnapshotBaselineMomentumNoCrossover);
    momentumTrendMisaligned = (m_diagMomentumTrendMisaligned - m_diagSnapshotBaselineMomentumTrendMisaligned);
    momentumNotReady = (m_diagMomentumNotReady - m_diagSnapshotBaselineMomentumNotReady);
    uictNone = (m_diagUICTNone - m_diagSnapshotBaselineUICTNone);
    uictNeutralBias = (m_diagUICTNeutralBias - m_diagSnapshotBaselineUICTNeutralBias);
    uictOtherFilters = (m_diagUICTOtherFilters - m_diagSnapshotBaselineUICTOtherFilters);
    intervalReasonTotal = rawNone + filteredOut + quorumFailed + intrabarNotEligible;

    m_diagSnapshotBaselineRawNone = m_diagRawNone;
    m_diagSnapshotBaselineFilteredOut = m_diagFilteredOut;
    m_diagSnapshotBaselineQuorumFailed = m_diagQuorumFailed;
    m_diagSnapshotBaselineIntrabarNotEligible = m_diagIntrabarNotEligible;
    m_diagSnapshotBaselineSignalsGenerated = m_diagSignalsGenerated;
    m_diagSnapshotBaselineSignalsAfterPipeline = m_diagSignalsAfterPipeline;
    m_diagSnapshotBaselineSignalsAfterQuorum = m_diagSignalsAfterQuorum;
    m_diagSnapshotBaselineVoteSuppressed = m_diagVoteSuppressed;
    m_diagSnapshotBaselineRolePrimarySignals = m_diagRolePrimarySignals;
    m_diagSnapshotBaselineRoleFeatureSignals = m_diagRoleFeatureSignals;
    m_diagSnapshotBaselineRoleShadowSignals = m_diagRoleShadowSignals;
    m_diagSnapshotBaselineClusterTrendSignals = m_diagClusterTrendSignals;
    m_diagSnapshotBaselineClusterMeanReversionSignals = m_diagClusterMeanReversionSignals;
    m_diagSnapshotBaselineClusterStructureSignals = m_diagClusterStructureSignals;
    m_diagSnapshotBaselineClusterNoneSignals = m_diagClusterNoneSignals;
    m_diagSnapshotBaselineMomentumNone = m_diagMomentumNone;
    m_diagSnapshotBaselineMomentumCooldown = m_diagMomentumCooldown;
    m_diagSnapshotBaselineMomentumLowVolatility = m_diagMomentumLowVolatility;
    m_diagSnapshotBaselineMomentumNoCrossover = m_diagMomentumNoCrossover;
    m_diagSnapshotBaselineMomentumTrendMisaligned = m_diagMomentumTrendMisaligned;
    m_diagSnapshotBaselineMomentumNotReady = m_diagMomentumNotReady;
    m_diagSnapshotBaselineUICTNone = m_diagUICTNone;
    m_diagSnapshotBaselineUICTNeutralBias = m_diagUICTNeutralBias;
    m_diagSnapshotBaselineUICTOtherFilters = m_diagUICTOtherFilters;
}

bool CEnterpriseStrategyManager::PopClosedTradeAttribution(string &contributors[], double &netProfit)
{
    if(!m_hasClosedTradeAttribution)
    {
        ArrayResize(contributors, 0);
        netProfit = 0.0;
        return false;
    }

    // Validate input arrays
    if(ArraySize(m_closedTradeContributors) <= 0)
    {
        Print("[EnterpriseStrategyManager] WARNING: PopClosedTradeAttribution called with empty contributors array");
        m_hasClosedTradeAttribution = false;
        ArrayResize(contributors, 0);
        netProfit = 0.0;
        return false;
    }

    // Copy contributors to output array
    int contributorCount = ArraySize(m_closedTradeContributors);
    ArrayResize(contributors, contributorCount);
    ArrayCopy(contributors, m_closedTradeContributors);
    
    netProfit = m_closedTradeNetProfit;

    // Clear the stored attribution
    ArrayResize(m_closedTradeContributors, 0);
    m_closedTradeNetProfit = 0.0;
    m_hasClosedTradeAttribution = false;
    
    return true;
}

int CEnterpriseStrategyManager::FindStrategyIndexByName(const string name) const
{
    for(int i = 0; i < m_strategyCount; i++)
    {
        if(m_strategies[i].name == name)
            return i;
    }
    return -1;
}

bool CEnterpriseStrategyManager::IsStrategyLiveVoter(const int strategyIndex) const
{
    if(strategyIndex < 0 || strategyIndex >= m_strategyCount)
        return false;
    if(!m_strategies[strategyIndex].enabled || m_strategies[strategyIndex].strategy == NULL)
        return false;
    if(m_strategies[strategyIndex].shadowOnly)
        return false;
    if(!m_strategies[strategyIndex].liveVotingEnabled)
        return false;
    return true;
}

void CEnterpriseStrategyManager::AccumulateRoleClusterSignalDiagnostics(const int strategyIndex, const bool signalGenerated)
{
    if(!signalGenerated)
        return;

    if(strategyIndex < 0 || strategyIndex >= m_strategyCount)
        return;

    ENUM_STRATEGY_ROLE role = (ENUM_STRATEGY_ROLE)m_strategies[strategyIndex].role;
    ENUM_STRATEGY_CLUSTER cluster = (ENUM_STRATEGY_CLUSTER)m_strategies[strategyIndex].cluster;

    if(role == PRIMARY_ALPHA)
        m_diagRolePrimarySignals++;
    else if(role == CONTEXT_FEATURE)
        m_diagRoleFeatureSignals++;
    else
        m_diagRoleShadowSignals++;

    if(cluster == TREND_CLUSTER)
        m_diagClusterTrendSignals++;
    else if(cluster == MEAN_REVERSION_CLUSTER)
        m_diagClusterMeanReversionSignals++;
    else if(cluster == STRUCTURE_CLUSTER)
        m_diagClusterStructureSignals++;
    else
        m_diagClusterNoneSignals++;
}

ENUM_STRATEGY_ROLE CEnterpriseStrategyManager::ResolveDominantRole(const int &strategyIndices[]) const
{
    double roleWeights[3];
    roleWeights[0] = 0.0;
    roleWeights[1] = 0.0;
    roleWeights[2] = 0.0;

    for(int i = 0; i < ArraySize(strategyIndices); i++)
    {
        int idx = strategyIndices[i];
        if(idx < 0 || idx >= m_strategyCount)
            continue;

        int role = m_strategies[idx].role;
        if(role < 0 || role > 2)
            role = 0;

        double weight = MathMax(0.0, m_strategies[idx].weight);
        if(weight <= 0.0)
            weight = 1.0;
        roleWeights[role] += weight;
    }

    int dominant = 0;
    if(roleWeights[1] > roleWeights[dominant])
        dominant = 1;
    if(roleWeights[2] > roleWeights[dominant])
        dominant = 2;

    return (ENUM_STRATEGY_ROLE)dominant;
}

ENUM_STRATEGY_CLUSTER CEnterpriseStrategyManager::ResolveDominantCluster(const int &strategyIndices[]) const
{
    double clusterWeights[4];
    clusterWeights[0] = 0.0;
    clusterWeights[1] = 0.0;
    clusterWeights[2] = 0.0;
    clusterWeights[3] = 0.0;

    for(int i = 0; i < ArraySize(strategyIndices); i++)
    {
        int idx = strategyIndices[i];
        if(idx < 0 || idx >= m_strategyCount)
            continue;

        int cluster = m_strategies[idx].cluster;
        if(cluster < 0 || cluster > 3)
            cluster = 0;

        double weight = MathMax(0.0, m_strategies[idx].weight);
        if(weight <= 0.0)
            weight = 1.0;
        clusterWeights[cluster] += weight;
    }

    int dominant = 0;
    if(clusterWeights[1] > clusterWeights[dominant])
        dominant = 1;
    if(clusterWeights[2] > clusterWeights[dominant])
        dominant = 2;
    if(clusterWeights[3] > clusterWeights[dominant])
        dominant = 3;

    return (ENUM_STRATEGY_CLUSTER)dominant;
}

string CEnterpriseStrategyManager::JoinContributorsWithContext(const int &strategyIndices[]) const
{
    string summary = "";
    for(int i = 0; i < ArraySize(strategyIndices); i++)
    {
        int idx = strategyIndices[i];
        if(idx < 0 || idx >= m_strategyCount)
            continue;

        if(StringLen(summary) > 0)
            summary += ",";

        string name = m_strategies[idx].name;
        ENUM_STRATEGY_ROLE role = (ENUM_STRATEGY_ROLE)m_strategies[idx].role;
        ENUM_STRATEGY_CLUSTER cluster = (ENUM_STRATEGY_CLUSTER)m_strategies[idx].cluster;
        summary += name + "[" + StrategyRoleToString(role) + "|" + StrategyClusterToString(cluster) + "]";
    }
    return summary;
}

void CEnterpriseStrategyManager::MaybeLogConsensusDiagnostics(const string symbol)
{
    datetime now = TimeCurrent();
    if(m_lastDiagLogTime == 0 || (now - m_lastDiagLogTime) >= m_diagLogIntervalSec)
    {
        ulong intervalRawNone = (m_diagRawNone - m_diagRootBaselineRawNone);
        ulong intervalFilteredOut = (m_diagFilteredOut - m_diagRootBaselineFilteredOut);
        ulong intervalQuorumFailed = (m_diagQuorumFailed - m_diagRootBaselineQuorumFailed);
        ulong intervalIntrabarNotEligible = (m_diagIntrabarNotEligible - m_diagRootBaselineIntrabarNotEligible);
        ulong intervalSignalsGenerated = (m_diagSignalsGenerated - m_diagRootBaselineSignalsGenerated);
        ulong intervalSignalsAfterPipeline = (m_diagSignalsAfterPipeline - m_diagRootBaselineSignalsAfterPipeline);
        ulong intervalSignalsAfterQuorum = (m_diagSignalsAfterQuorum - m_diagRootBaselineSignalsAfterQuorum);
        ulong intervalVoteSuppressed = (m_diagVoteSuppressed - m_diagRootBaselineVoteSuppressed);
        ulong intervalRolePrimarySignals = (m_diagRolePrimarySignals - m_diagRootBaselineRolePrimarySignals);
        ulong intervalRoleFeatureSignals = (m_diagRoleFeatureSignals - m_diagRootBaselineRoleFeatureSignals);
        ulong intervalRoleShadowSignals = (m_diagRoleShadowSignals - m_diagRootBaselineRoleShadowSignals);
        ulong intervalClusterTrendSignals = (m_diagClusterTrendSignals - m_diagRootBaselineClusterTrendSignals);
        ulong intervalClusterMeanReversionSignals = (m_diagClusterMeanReversionSignals - m_diagRootBaselineClusterMeanReversionSignals);
        ulong intervalClusterStructureSignals = (m_diagClusterStructureSignals - m_diagRootBaselineClusterStructureSignals);
        ulong intervalClusterNoneSignals = (m_diagClusterNoneSignals - m_diagRootBaselineClusterNoneSignals);
        ulong intervalMomentumNone = (m_diagMomentumNone - m_diagRootBaselineMomentumNone);
        ulong intervalMomentumCooldown = (m_diagMomentumCooldown - m_diagRootBaselineMomentumCooldown);
        ulong intervalMomentumLowVolatility = (m_diagMomentumLowVolatility - m_diagRootBaselineMomentumLowVolatility);
        ulong intervalMomentumNoCrossover = (m_diagMomentumNoCrossover - m_diagRootBaselineMomentumNoCrossover);
        ulong intervalMomentumTrendMisaligned = (m_diagMomentumTrendMisaligned - m_diagRootBaselineMomentumTrendMisaligned);
        ulong intervalMomentumNotReady = (m_diagMomentumNotReady - m_diagRootBaselineMomentumNotReady);
        ulong intervalUICTNone = (m_diagUICTNone - m_diagRootBaselineUICTNone);
        ulong intervalUICTNeutralBias = (m_diagUICTNeutralBias - m_diagRootBaselineUICTNeutralBias);
        ulong intervalUICTOtherFilters = (m_diagUICTOtherFilters - m_diagRootBaselineUICTOtherFilters);

        ulong reasonTotal = intervalRawNone + intervalFilteredOut + intervalQuorumFailed + intervalIntrabarNotEligible;
        double denom = (reasonTotal > 0) ? (double)reasonTotal : 1.0;
        double pctRawNone = ((double)intervalRawNone / denom) * 100.0;
        double pctFiltered = ((double)intervalFilteredOut / denom) * 100.0;
        double pctQuorum = ((double)intervalQuorumFailed / denom) * 100.0;
        double pctIntrabar = ((double)intervalIntrabarNotEligible / denom) * 100.0;

        string dominantCause = "none";
        ulong dominantCount = 0;
        if(intervalIntrabarNotEligible > dominantCount)
        {
            dominantCount = intervalIntrabarNotEligible;
            dominantCause = "intrabar_not_eligible";
        }
        if(intervalQuorumFailed > dominantCount)
        {
            dominantCount = intervalQuorumFailed;
            dominantCause = "quorum_failed";
        }
        if(intervalFilteredOut > dominantCount)
        {
            dominantCount = intervalFilteredOut;
            dominantCause = "filtered_out";
        }
        if(intervalRawNone > dominantCount)
        {
            dominantCount = intervalRawNone;
            dominantCause = "raw_none";
        }

        PrintFormat("[CONSENSUS-DIAG] %s | generated=%I64u | after_pipeline=%I64u | after_quorum=%I64u | vote_suppressed=%I64u | raw_none=%I64u | filtered_out=%I64u | quorum_failed=%I64u | intrabar_not_eligible=%I64u",
                    symbol,
                    intervalSignalsGenerated,
                    intervalSignalsAfterPipeline,
                    intervalSignalsAfterQuorum,
                    intervalVoteSuppressed,
                    intervalRawNone,
                    intervalFilteredOut,
                    intervalQuorumFailed,
                    intervalIntrabarNotEligible);
        PrintFormat("[CONSENSUS-ROOT] %s | dominant=%s | intrabar_not_eligible=%.1f%% (%I64u) | quorum_failed=%.1f%% (%I64u) | filtered_out=%.1f%% (%I64u) | raw_none=%.1f%% (%I64u) | total=%I64u",
                    symbol,
                    dominantCause,
                    pctIntrabar, intervalIntrabarNotEligible,
                    pctQuorum, intervalQuorumFailed,
                    pctFiltered, intervalFilteredOut,
                    pctRawNone, intervalRawNone,
                    reasonTotal);
        PrintFormat("[CONSENSUS-STRATEGY] %s | momentum_none=%I64u | momentum_cooldown=%I64u | momentum_low_vol=%I64u | momentum_no_crossover=%I64u | momentum_trend_misaligned=%I64u | momentum_not_ready=%I64u | uict_none=%I64u | uict_neutral_bias=%I64u | uict_other_filters=%I64u",
                    symbol,
                    intervalMomentumNone,
                    intervalMomentumCooldown,
                    intervalMomentumLowVolatility,
                    intervalMomentumNoCrossover,
                    intervalMomentumTrendMisaligned,
                    intervalMomentumNotReady,
                    intervalUICTNone,
                    intervalUICTNeutralBias,
                    intervalUICTOtherFilters);
        PrintFormat("[CONSENSUS-ROLE] %s | primary=%I64u | feature=%I64u | shadow=%I64u | suppressed=%I64u",
                    symbol,
                    intervalRolePrimarySignals,
                    intervalRoleFeatureSignals,
                    intervalRoleShadowSignals,
                    intervalVoteSuppressed);
        PrintFormat("[CONSENSUS-CLUSTER] %s | trend=%I64u | mean_reversion=%I64u | structure=%I64u | none=%I64u",
                    symbol,
                    intervalClusterTrendSignals,
                    intervalClusterMeanReversionSignals,
                    intervalClusterStructureSignals,
                    intervalClusterNoneSignals);

        m_diagRootBaselineRawNone = m_diagRawNone;
        m_diagRootBaselineFilteredOut = m_diagFilteredOut;
        m_diagRootBaselineQuorumFailed = m_diagQuorumFailed;
        m_diagRootBaselineIntrabarNotEligible = m_diagIntrabarNotEligible;
        m_diagRootBaselineSignalsGenerated = m_diagSignalsGenerated;
        m_diagRootBaselineSignalsAfterPipeline = m_diagSignalsAfterPipeline;
        m_diagRootBaselineSignalsAfterQuorum = m_diagSignalsAfterQuorum;
        m_diagRootBaselineVoteSuppressed = m_diagVoteSuppressed;
        m_diagRootBaselineRolePrimarySignals = m_diagRolePrimarySignals;
        m_diagRootBaselineRoleFeatureSignals = m_diagRoleFeatureSignals;
        m_diagRootBaselineRoleShadowSignals = m_diagRoleShadowSignals;
        m_diagRootBaselineClusterTrendSignals = m_diagClusterTrendSignals;
        m_diagRootBaselineClusterMeanReversionSignals = m_diagClusterMeanReversionSignals;
        m_diagRootBaselineClusterStructureSignals = m_diagClusterStructureSignals;
        m_diagRootBaselineClusterNoneSignals = m_diagClusterNoneSignals;
        m_diagRootBaselineMomentumNone = m_diagMomentumNone;
        m_diagRootBaselineMomentumCooldown = m_diagMomentumCooldown;
        m_diagRootBaselineMomentumLowVolatility = m_diagMomentumLowVolatility;
        m_diagRootBaselineMomentumNoCrossover = m_diagMomentumNoCrossover;
        m_diagRootBaselineMomentumTrendMisaligned = m_diagMomentumTrendMisaligned;
        m_diagRootBaselineMomentumNotReady = m_diagMomentumNotReady;
        m_diagRootBaselineUICTNone = m_diagUICTNone;
        m_diagRootBaselineUICTNeutralBias = m_diagUICTNeutralBias;
        m_diagRootBaselineUICTOtherFilters = m_diagUICTOtherFilters;
        m_lastDiagLogTime = now;
    }
}

int CEnterpriseStrategyManager::FindAttributionIndexByPositionId(const ulong positionId) const
{
    for(int i = 0; i < ArraySize(m_attributionPositionIds); i++)
    {
        if(m_attributionPositionIds[i] == positionId)
            return i;
    }
    return -1;
}

string CEnterpriseStrategyManager::JoinContributors(const string &contributors[]) const
{
    string csv = "";
    for(int i = 0; i < ArraySize(contributors); i++)
    {
        if(contributors[i] == "")
            continue;
        if(StringLen(csv) > 0)
            csv += ";";
        csv += contributors[i];
    }
    return csv;
}

void CEnterpriseStrategyManager::SplitContributors(const string csv, string &contributors[]) const
{
    ArrayResize(contributors, 0);
    if(csv == "")
        return;

    string parsed[];
    int count = StringSplit(csv, ';', parsed);
    if(count <= 0)
        return;

    ArrayResize(contributors, count);
    for(int i = 0; i < count; i++)
        contributors[i] = parsed[i];
}

void CEnterpriseStrategyManager::UpsertPositionAttribution(const ulong positionId, const string &contributors[])
{
    if(positionId == 0 || ArraySize(contributors) <= 0)
        return;

    string contributorCsv = JoinContributors(contributors);
    if(contributorCsv == "")
        return;

    int idx = FindAttributionIndexByPositionId(positionId);
    if(idx >= 0)
    {
        m_attributionContributorCsv[idx] = contributorCsv;
        return;
    }

    int size = ArraySize(m_attributionPositionIds);
    ArrayResize(m_attributionPositionIds, size + 1);
    ArrayResize(m_attributionContributorCsv, size + 1);
    m_attributionPositionIds[size] = positionId;
    m_attributionContributorCsv[size] = contributorCsv;
}

bool CEnterpriseStrategyManager::PopPositionAttribution(const ulong positionId, string &contributors[])
{
    int idx = FindAttributionIndexByPositionId(positionId);
    if(idx < 0)
        return false;

    SplitContributors(m_attributionContributorCsv[idx], contributors);

    int last = ArraySize(m_attributionPositionIds) - 1;
    if(last >= 0)
    {
        if(idx != last)
        {
            m_attributionPositionIds[idx] = m_attributionPositionIds[last];
            m_attributionContributorCsv[idx] = m_attributionContributorCsv[last];
        }
        ArrayResize(m_attributionPositionIds, last);
        ArrayResize(m_attributionContributorCsv, last);
    }

    return true;
}

//+------------------------------------------------------------------+
//| OnNewBar - CRITICAL for zone scanning and chart drawings         |
//| Must be called from main EA on each new bar                      |
//+------------------------------------------------------------------+
void CEnterpriseStrategyManager::OnNewBar(const string symbol, ENUM_TIMEFRAMES timeframe)
{
    if(!m_initialized || m_strategyCount == 0)
        return;

    datetime barTime = iTime(symbol, timeframe, 0);
    if(barTime <= 0)
        barTime = TimeCurrent();

    CDrawingCoordinator* drawingCoordinator = GetDrawingCoordinator();
    if(drawingCoordinator != NULL)
        drawingCoordinator.BeginBarCycle(symbol, timeframe, barTime);

    // Call OnNewBar and persist per-bar analysis snapshots
    for(int i = 0; i < m_strategyCount; i++)
    {
        if(m_strategies[i].strategy == NULL)
            continue;

        if(m_strategies[i].enabled)
        {
            m_strategies[i].strategy.OnNewBar(symbol, timeframe);
        }
        else
        {
            m_strategies[i].lastSignal = TRADE_SIGNAL_NONE;
            m_strategies[i].lastSignalConfidence = 0.0;
        }

        if(drawingCoordinator != NULL)
        {
            int totalSignals = 0;
            int successfulSignals = 0;
            double accuracy = 0.0;
            m_strategies[i].strategy.GetStatistics(totalSignals, successfulSignals, accuracy);

            drawingCoordinator.RecordStrategySnapshot(
                m_strategies[i].name,
                m_strategies[i].enabled,
                m_strategies[i].lastSignal,
                m_strategies[i].lastSignalConfidence,
                totalSignals,
                successfulSignals,
                accuracy,
                m_strategies[i].lastEvaluationTime > 0
                    ? m_strategies[i].lastEvaluationTime
                    : m_strategies[i].strategy.GetLastSignalTime()
            );
        }
    }

    if(drawingCoordinator != NULL)
        drawingCoordinator.EndBarCycle();
}

//+------------------------------------------------------------------+
//| OnTradeTransaction - Handle trade events for AI feedback        |
//+------------------------------------------------------------------+
void CEnterpriseStrategyManager::OnTradeTransaction(const MqlTradeTransaction& trans,
                                                   const MqlTradeRequest& request,
                                                   const MqlTradeResult& result)
{
    // Check for transaction adding a deal (trade execution)
    if(trans.type == TRADE_TRANSACTION_DEAL_ADD && trans.deal > 0)
    {
        ulong dealTicket = trans.deal;
        if(HistoryDealSelect(dealTicket))
        {
            long dealMagic = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
            if(m_managedMagic > 0 && dealMagic != m_managedMagic)
                return;

            string dealSymbol = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
            if(dealSymbol != "" && dealSymbol != m_symbol)
                return;

            ENUM_DEAL_ENTRY entryType = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
            ulong positionId = (ulong)HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);

            if((entryType == DEAL_ENTRY_IN || entryType == DEAL_ENTRY_INOUT) &&
               positionId > 0 &&
               m_lastContributorCount > 0 &&
               ArraySize(m_lastSignalContributors) > 0)
            {
                UpsertPositionAttribution(positionId, m_lastSignalContributors);
            }
            
            // We care about exits (deals that close a position) to meaningful profit/loss
            if(entryType == DEAL_ENTRY_OUT || entryType == DEAL_ENTRY_OUT_BY || entryType == DEAL_ENTRY_INOUT)
            {
                // Avoid double-counting partial closes; attribute only once when position is fully closed.
                if(positionId > 0 && IsPositionIdStillOpen(positionId))
                    return;

                double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
                double swap = HistoryDealGetDouble(dealTicket, DEAL_SWAP);
                double commission = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
                double netProfit = profit + swap + commission;
                
                bool success = (netProfit > 0);
                if(success)
                    m_successfulSignals++;

                m_hasClosedTradeAttribution = false;
                m_closedTradeNetProfit = 0.0;
                ArrayResize(m_closedTradeContributors, 0);

                string contributors[];
                if(positionId > 0 && PopPositionAttribution(positionId, contributors))
                {
                    ArrayCopy(m_closedTradeContributors, contributors);
                    m_closedTradeNetProfit = netProfit;
                    m_hasClosedTradeAttribution = (ArraySize(m_closedTradeContributors) > 0);
                }

                // Reset cached contributor context after close in manager-only governance mode.
                m_lastContributorCount = 0;
                ArrayResize(m_lastSignalContributors, 0);

                PrintFormat("[EnterpriseManager] Trade Closed | Symbol: %s | Ticket: %I64u | PositionID: %I64u | Net Profit: %.2f | Result: %s",
                           dealSymbol, dealTicket, positionId, netProfit, success ? "SUCCESS" : "FAILURE");
            }
        }
    }
}

bool CEnterpriseStrategyManager::IsPositionIdStillOpen(const ulong positionId) const
{
    if(positionId == 0)
        return false;

    for(int i = 0; i < PositionsTotal(); i++)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket == 0 || !PositionSelectByTicket(ticket))
            continue;

        ulong openPositionId = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
        if(openPositionId == positionId)
            return true;
    }

    return false;
}

#endif // ENTERPRISE_STRATEGY_MANAGER_MQH
