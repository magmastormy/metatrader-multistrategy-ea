//+------------------------------------------------------------------+
//| Enterprise Strategy Manager - Production Grade                   |
//| Central manager for all strategies with unified pipeline        |
//+------------------------------------------------------------------+
#ifndef ENTERPRISE_STRATEGY_MANAGER_MQH
#define ENTERPRISE_STRATEGY_MANAGER_MQH

#include "../Pipeline/UnifiedSignalPipeline.mqh"
#include "../Visualization/DrawingCoordinator.mqh"
#include "../Signals/TimeframeConsistency.mqh"
#include "../../Interfaces/IStrategy.mqh"

// Retained production strategy inventory (7 kept in codebase)
#include "../../Strategies/SimpleMomentumStrategy.mqh"
#include "../../Strategies/StrategyTrend.mqh"
// FIBONACCI REMOVED - Include deleted
// ELLIOTT WAVE REMOVED - Include deleted
#include "../../Strategies/StrategySupportResistance.mqh"
#include "../../Strategies/StrategyUnifiedICT.mqh"
#include "../../Strategies/StrategyCandlestick.mqh"
#include "../../Strategies/CUnicornModelStrategy.mqh"
#include "../../Strategies/CPowerOfThreeStrategy.mqh"
#include "../../Strategies/MeanReversionStrategy.mqh"
#include "../../Strategies/VolatilityBreakoutStrategy.mqh"

// Forward declarations
class CEnhancedErrorHandler;
class CUtilities;
class CHedgingProtection;
class CMarketAnalysis;
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
    int intrabarPolicy;
    bool liveVotingEnabled;
    bool shadowOnly;
    int role;
    int cluster;
    ENUM_STRATEGY_TIER tier;             // Strategy Tier (Ranking Matrix)
    double weight;
    double originalWeight;              // Track original weight for decay recovery
    ENUM_TIMEFRAMES timeframe;
    int successCount;
    int failCount;
    double healthScore;
    double participationScore;
    double avgConfidence;
    ENUM_TRADE_SIGNAL lastSignal;
    double lastSignalConfidence;
    datetime lastEvaluationTime;
    int consecutiveFilterCount;         // Count consecutive no-signal cycles for decay

    // Performance metrics ported from AISO
    int totalTrades;
    int winningTrades;
    double winRate;
    double avgProfit;
    double avgLoss;
    double profitFactor;
    double sharpeRatio;
    
    // Recent performance tracking (20-trade rolling window)
    double recentTrades[20];
    int recentTradeIndex;
    int recentTradeCount;
    double recentWinRate;
    
    // Consecutive performance tracking
    int consecutiveLosses;
    int maxConsecutiveLosses;
    int consecutiveWins;
    
    // Adaptation flags
    bool temporarilyDisabled;       
    datetime disabledUntil;         
    datetime lastUpdate;            
    
    // Market regime performance
    double regimePerformance[5];    
    int regimeTrades[5];            
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
        case SCALP_CLUSTER: return "SCALP_CLUSTER";
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
        case SCALP_CLUSTER: return "X";
        case STRATEGY_CLUSTER_NONE:
        default:
            return "N";
    }
}

string IntrabarPolicyToString(const ENUM_INTRABAR_POLICY policy)
{
    switch(policy)
    {
        case INTRABAR_POLICY_OFF: return "OFF";
        case INTRABAR_POLICY_PROBE: return "PROBE";
        case INTRABAR_POLICY_LIVE: return "LIVE";
        default: return "OFF";
    }
}

string ConsensusDecisionClassToString(const ENUM_CONSENSUS_DECISION_CLASS decisionClass)
{
    switch(decisionClass)
    {
        case CONSENSUS_DECISION_FULL_QUORUM: return "FULL_QUORUM";
        case CONSENSUS_DECISION_SPARSE_INTRABAR: return "SPARSE_INTRABAR";
        case CONSENSUS_DECISION_VETOED: return "VETOED";
        case CONSENSUS_DECISION_NONE:
        default:
            return "NONE";
    }
}

string TradeSignalToString(const ENUM_TRADE_SIGNAL signal)
{
    switch(signal)
    {
        case TRADE_SIGNAL_BUY: return "BUY";
        case TRADE_SIGNAL_SELL: return "SELL";
        case TRADE_SIGNAL_NONE: return "NONE";
        default: return "UNKNOWN";
    }
}

bool IsInfrastructureNoSignalReasonTag(const string reasonTag)
{
    if(reasonTag == "")
        return false;

    return (StringFind(reasonTag, "_WARMING_UP") >= 0 ||
            StringFind(reasonTag, "_UNAVAILABLE") >= 0 ||
            StringFind(reasonTag, "_DISABLED_OR_UNAVAILABLE") >= 0 ||
            StringFind(reasonTag, "_DISABLED_OR_UNINIT") >= 0 ||
            StringFind(reasonTag, "_INVALID_HANDLES") >= 0 ||
            StringFind(reasonTag, "_INIT_FAILED") >= 0 ||
            StringFind(reasonTag, "_FEATURES_UNAVAILABLE") >= 0 ||
            StringFind(reasonTag, "_SCALER_APPLY_FAILED") >= 0 ||
            StringFind(reasonTag, "_INFERENCE_FAILED") >= 0 ||
            StringFind(reasonTag, "_MODEL_UNAVAILABLE") >= 0);
}

//+------------------------------------------------------------------+
//| Enterprise Strategy Manager Class                               |
//+------------------------------------------------------------------+
class CEnterpriseStrategyManager
{
private:
    CUnifiedSignalPipeline* m_pipeline;
    CTimeframeConsistency* m_tfConsistency;
    CTradeManager* m_tradeManager;   // CRITICAL FIX: Store for strategy initialization
    CPositionSizer* m_positionSizer; // CRITICAL FIX: Store for strategy initialization
    CUnifiedRiskManager* m_unifiedRiskManager; // Unified risk validation gate (injected)
    CChartDrawingManager* m_drawingManager; // Central drawing manager for the symbol
    
    StrategyEntry m_strategies[];
    int m_strategyCount;
    int m_maxStrategies; // Max strategy limit
    
    string m_symbol;
    ENUM_TIMEFRAMES m_baseTimeframe;
    long m_managedMagic;
    long m_managedMagicRangeMax;
    
    bool m_initialized;
    bool m_usePipeline;
    int  m_minQuorum;       // Minimum number of agreeing live voters (floor safety)
    int  m_intrabarMinQuorum; // Intrabar quorum floor when multiple strategies are active
    bool m_intrabarDynamicQuorumEnabled;
    double m_intrabarSingleVoterMinConfidence;
    double m_quorumThreshold;       // Normalized weighted quorum threshold (0..1)
    double m_pipelineMinConfidence; // Pipeline base confidence floor used for quorum eligibility
    double m_conflictDeadband;      // Deadband between buy/sell conviction before forcing direction
    double m_minReadyWeightRatio;   // Minimum ready-live-weight share required to trade
    double m_supportFloorNewBar;
    double m_supportFloorIntrabar;
    double m_sparseIntrabarMinQuality;
    double m_sparseIntrabarMinSupportRatio;
    double m_sparseIntrabarMinReadyCoverage;
    double m_sparseIntrabarConfidencePenalty;
    bool m_allowSparseIntrabarSingleVoter;

    // Adaptive quorum settings (adjust thresholds based on active voter count)
    bool m_adaptiveQuorumEnabled;
    double m_adaptiveQualityThreshold_1voter;     // Quality threshold for 1 active voter
    double m_adaptiveSupportFloor_1voter;          // Support floor for 1 active voter
    double m_adaptiveQualityThreshold_2voters;     // Quality threshold for 2 active voters
    double m_adaptiveSupportFloor_2voters;         // Support floor for 2 active voters
    double m_adaptiveQualityThreshold_3plus;       // Quality threshold for 3+ active voters (standard)
    double m_adaptiveSupportFloor_3plus;           // Support floor for 3+ active voters (standard)
    double m_strategyActivityDecayRate;            // How fast inactive strategy weight decays (0.0-1.0)
    int m_strategyInactiveCounterThreshold;        // After N consecutive filters, apply weight decay

    // Ported Orchestrator Parameters
    double m_minWinRateThreshold;                       // Minimum win rate (default 40%)
    int m_maxConsecutiveLosses_Limit;                   // Max consecutive losses (default 5)
    double m_performanceDecayFactor;                    // Performance decay factor
    int m_rollingWindowSize;                            // Rolling window size (default 20)
    double m_maxDrawdownLimit;                          // Drawdown fraction for lot-size tapering (internal param)

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
    SConsensusDecisionContext m_lastDecisionContext;

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
    double GetStrategyReliabilityMultiplier(const int strategyIndex) const;
    double GetStrategyParticipationMultiplier(const int strategyIndex) const;
    double GetStrategyRoleVoteMultiplier(const int strategyIndex) const;
    double CalculateDirectionDiversityScore(const int &strategyIndices[]) const;
    double ClampUnitValue(const double value) const;
    ENUM_INTRABAR_POLICY GetStrategyIntrabarPolicy(const int strategyIndex) const;
    bool IsStrategyIntrabarLiveEligible(const int strategyIndex) const;
    bool IsStrategyIntrabarProbeEligible(const int strategyIndex) const;
    double CalculateAverageStrategyMetric(const int &strategyIndices[], const double &metrics[]) const;
    bool IsTrendingRegime() const;
    
public:
    CEnterpriseStrategyManager();
    ~CEnterpriseStrategyManager();
    
    // Initialization
    bool Initialize(const string symbol, ENUM_TIMEFRAMES timeframe, 
                   bool usePipeline = true,
                   CTradeManager* tradeManagerPtr = NULL, CPositionSizer* positionSizerPtr = NULL,
                   CUnifiedRiskManager* unifiedRiskManagerPtr = NULL,
                   const long managedMagic = 0);
    
    // Strategy management
    bool RegisterStrategy(IStrategy* strategy, const string name, 
                         bool enabled = true, double weight = 1.0,
                         ENUM_STRATEGY_TIER tier = STRATEGY_TIER_3,
                         ENUM_TIMEFRAMES tf = PERIOD_CURRENT,
                         bool intrabarEligible = false,
                         ENUM_STRATEGY_ROLE role = PRIMARY_ALPHA,
                         ENUM_STRATEGY_CLUSTER cluster = STRATEGY_CLUSTER_NONE,
                         bool liveVotingEnabled = true,
                         bool shadowOnly = false);
    bool EnableStrategy(const string name);
    bool DisableStrategy(const string name);
    
    // Signal generation
    ENUM_TRADE_SIGNAL GetConsensusSignal(double &confidence);
    ENUM_TRADE_SIGNAL GetConsensusSignalForSymbol(const string symbol, double &confidence);
    ENUM_TRADE_SIGNAL GetConsensusSignalWithConfluence(double &confidence, int &confluence);
    ENUM_TRADE_SIGNAL GetConsensusSignalForSymbolWithConfluence(const string symbol, double &confidence, int &confluence);
    ENUM_TRADE_SIGNAL GetConsensusSignalForSymbolWithConfluenceMode(const string symbol, double &confidence, int &confluence, ENUM_SIGNAL_EVAL_MODE evalMode);

    // Two-tier consensus: Tier 1 quick-probe fast path, Tier 2 full evaluation fallback
    ENUM_TRADE_SIGNAL EvaluateConsensusTwoTier(const string symbol, double &confidence, int &confluence, ENUM_SIGNAL_EVAL_MODE evalMode);
    
    // Configuration
    void SetPipelineFilters(SignalFilterSettings &settings);
    void SetOrchestratorMode(double minWinRate, int maxLosses);
    void SetMinQuorum(int quorum) { m_minQuorum = MathMax(1, quorum); }  // Solo Mode support
    void SetManagedMagicRangeMax(long rangeMax) { m_managedMagicRangeMax = rangeMax; }
    bool IsEAOwnedMagic(long magic) const { return (m_managedMagicRangeMax > m_managedMagic) ? (magic >= m_managedMagic && magic <= m_managedMagicRangeMax) : (magic == m_managedMagic); }
    void SetQuorumThreshold(const double threshold)
    {
        m_quorumThreshold = MathMax(0.0, MathMin(1.0, threshold));
    }
    void SetIntrabarMinQuorum(int quorum) { m_intrabarMinQuorum = MathMax(1, quorum); }
    void SetIntrabarDynamicQuorumEnabled(const bool enabled) { m_intrabarDynamicQuorumEnabled = enabled; }
    void SetIntrabarSingleVoterMinConfidence(const double minConfidence)
    {
        m_intrabarSingleVoterMinConfidence = MathMax(0.0, MathMin(1.0, minConfidence));
    }
    void SetConflictDeadband(const double deadband) { m_conflictDeadband = MathMax(0.0, MathMin(0.50, deadband)); }
    void SetMinReadyWeightRatio(const double ratio) { m_minReadyWeightRatio = MathMax(0.10, MathMin(1.0, ratio)); }
    void SetSupportFloors(const double newBarFloor, const double intrabarFloor)
    {
        m_supportFloorNewBar = MathMax(0.05, MathMin(1.0, newBarFloor));
        m_supportFloorIntrabar = MathMax(0.05, MathMin(1.0, intrabarFloor));
    }
    void SetSparseIntrabarThresholds(const double minQuality,
                                     const double minSupportRatio,
                                     const double minReadyCoverage)
    {
        m_sparseIntrabarMinQuality = MathMax(0.0, MathMin(1.0, minQuality));
        m_sparseIntrabarMinSupportRatio = MathMax(0.0, MathMin(1.0, minSupportRatio));
        m_sparseIntrabarMinReadyCoverage = MathMax(0.0, MathMin(1.0, minReadyCoverage));
    }
    void SetAllowSparseIntrabarSingleVoter(const bool enabled) { m_allowSparseIntrabarSingleVoter = enabled; }
    
    // Quorum preset profiles
    enum ENUM_QUORUM_PROFILE
    {
        QUORUM_CONSERVATIVE,
        QUORUM_BALANCED,
        QUORUM_AGGRESSIVE
    };
    void ApplyQuorumProfile(ENUM_QUORUM_PROFILE profile);
    void SetConsensusDiagnosticsIntervalSeconds(const int seconds) { m_diagLogIntervalSec = MathMax(10, seconds); }
    int  GetMinQuorum() const { return m_minQuorum; }
    bool UpdateStrategyWeightByName(const string name, const double weight);
    bool SetStrategyIntrabarEligibilityByName(const string name, bool enabled);
    bool SetStrategyIntrabarPolicyByName(const string name, ENUM_INTRABAR_POLICY policy);
    bool SetStrategyRoleByName(const string name, ENUM_STRATEGY_ROLE role);
    bool SetStrategyClusterByName(const string name, ENUM_STRATEGY_CLUSTER cluster);
    bool SetStrategyLiveVotingEligibilityByName(const string name, const bool enabled);
    bool SetStrategyShadowModeByName(const string name, const bool enabled);
    bool SetStrategyGovernanceByName(const string name,
                                     ENUM_STRATEGY_ROLE role,
                                     ENUM_STRATEGY_CLUSTER cluster,
                                     const bool liveVotingEnabled,
                                     const bool shadowOnly);
    bool SetStrategyConfidenceThresholdByName(const string name, const double threshold);
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
    CUnifiedSignalPipeline* GetPipeline() { return m_pipeline; }
    bool GetLastDecisionContext(SConsensusDecisionContext &context) const;
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
    void UpdatePerformance(const string strategyName, double netProfit);

    // Manager-owned orchestration/adaptation API (AISO consolidation)
    bool UpdateStrategyWeight(const string strategyName, const double newWeight)
    {
        return UpdateStrategyWeightByName(strategyName, newWeight);
    }
    double GetEnsembleConfidence() const
    {
        return MathMax(0.0, MathMin(1.0, m_lastDecisionContext.confidence));
    }
    ENUM_MARKET_REGIME GetCurrentMarketRegime() const
    {
        return MARKET_REGIME_UNKNOWN;
    }
    string GetStrategyWeightsJSON() const;
    void UpdateStrategyWeights();
    void CheckStrategyDisabling();
    void CheckStrategyReEnabling();
    
    // Ported adaptation helpers
    double CalculateRecentWinRate(const int index);
    double CalculateSharpeRatio(const int index);
    void UpdateRegimePerformance(const int index, int regime, const double result);
    void CalculateStrategyMetrics(const int index);
    bool ShouldDisableStrategy(const int index);
    bool ShouldReEnableStrategy(const int index);
    void UpdateRecentPerformance(const int index, const double result);
    
    // Visualization
    void SetDrawingManager(CChartDrawingManager* drawingManager) { m_drawingManager = drawingManager; }
    CChartDrawingManager* GetDrawingManager() { return m_drawingManager; }
    
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
    m_tfConsistency(NULL),
    m_tradeManager(NULL),
    m_positionSizer(NULL),
    m_strategyCount(0),
    m_maxStrategies(20),
    m_managedMagic(0),
    m_managedMagicRangeMax(0),
    m_initialized(false),
    m_usePipeline(true),
    m_minQuorum(2),         // Minimum agreeing live voters floor (overridden by EA input)
    m_intrabarMinQuorum(1),
    m_intrabarDynamicQuorumEnabled(true),
    m_intrabarSingleVoterMinConfidence(0.65),
    m_quorumThreshold(0.55),
    m_pipelineMinConfidence(0.40),
    m_conflictDeadband(0.05),
    m_minReadyWeightRatio(0.45),
    m_supportFloorNewBar(0.35),
    m_supportFloorIntrabar(0.20),
    m_sparseIntrabarMinQuality(0.62),
    m_sparseIntrabarMinSupportRatio(0.20),
    m_sparseIntrabarMinReadyCoverage(0.60),
    m_sparseIntrabarConfidencePenalty(0.92),
    m_allowSparseIntrabarSingleVoter(false),
    m_adaptiveQuorumEnabled(true),
    m_adaptiveQualityThreshold_1voter(0.40),      // 1 voter: 40% quality OK
    m_adaptiveSupportFloor_1voter(0.12),          // 1 voter: 12% support OK (relaxed from 0.15)
    m_adaptiveQualityThreshold_2voters(0.48),     // 2 voters: 48% quality OK
    m_adaptiveSupportFloor_2voters(0.25),         // 2 voters: 25% support OK (relaxed from 0.30)
    m_adaptiveQualityThreshold_3plus(0.55),       // 3+ voters: standard 55% quality
    m_adaptiveSupportFloor_3plus(0.35),           // 3+ voters: standard 35% support
    m_strategyActivityDecayRate(0.05),            // Weight decay rate per inactive cycle (reduced from 0.15)
    m_strategyInactiveCounterThreshold(15),        // After 15 filters, start decay (increased from 3)
    m_minWinRateThreshold(0.40),
    m_maxConsecutiveLosses_Limit(5),
    m_performanceDecayFactor(0.95),
    m_rollingWindowSize(20),
    m_maxDrawdownLimit(0.20),
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
            m_strategies[i].strategy.Deinit();
            delete m_strategies[i].strategy;
            m_strategies[i].strategy = NULL;
        }
    }
    
    if(m_pipeline != NULL)
    {
        delete m_pipeline;
        m_pipeline = NULL;
    }

    if(m_tfConsistency != NULL)
    {
        delete m_tfConsistency;
        m_tfConsistency = NULL;
    }
}

//+------------------------------------------------------------------+
//| Initialize Manager                                              |
//+------------------------------------------------------------------+
bool CEnterpriseStrategyManager::Initialize(const string symbol, ENUM_TIMEFRAMES timeframe,
                                           bool usePipeline,
                                           CTradeManager* tradeManagerPtr, CPositionSizer* positionSizerPtr,
                                           CUnifiedRiskManager* unifiedRiskManagerPtr,
                                           const long managedMagic)
{
    m_symbol = symbol;
    m_baseTimeframe = timeframe;
    m_managedMagic = managedMagic;
    m_managedMagicRangeMax = managedMagic; // Default: exact match; EA will update after symbol universe is built
    m_usePipeline = usePipeline;
    m_tradeManager = tradeManagerPtr;   // CRITICAL FIX: Store for strategy initialization
    m_positionSizer = positionSizerPtr; // CRITICAL FIX: Store for strategy initialization
    m_unifiedRiskManager = unifiedRiskManagerPtr; // ARCHITECTURAL FIX: Inject unified risk manager
    
    // Initialize pipeline
    if(m_usePipeline)
    {
        m_pipeline = new CUnifiedSignalPipeline();
        if(m_pipeline != NULL)
        {
            SignalFilterSettings filters;
            if(!m_pipeline.Initialize(filters))
            {
                Print("[EnterpriseStrategyManager] ERROR: Pipeline initialization failed for ", symbol);
                delete m_pipeline;
                m_pipeline = NULL;
                return false;
            }
        }
        else
        {
            Print("[EnterpriseStrategyManager] ERROR: Pipeline allocation failed for ", symbol);
            return false;
        }
    }

    if(m_tfConsistency != NULL)
    {
        delete m_tfConsistency;
        m_tfConsistency = NULL;
    }

    m_tfConsistency = new CTimeframeConsistency();
    if(m_tfConsistency == NULL)
    {
        Print("[EnterpriseStrategyManager] ERROR: TimeframeConsistency allocation failed for ", symbol);
        return false;
    }
    if(!m_tfConsistency.Initialize(CONFLICT_RES_WEIGHTED, 0.6, false))
    {
        Print("[EnterpriseStrategyManager] ERROR: TimeframeConsistency initialization failed for ", symbol);
        delete m_tfConsistency;
        m_tfConsistency = NULL;
        return false;
    }
    
    m_initialized = true;
    m_drawingManager = NULL;
    
    Print("[EnterpriseStrategyManager] Initialized for ", symbol, " on ", EnumToString(timeframe));
    Print("[EnterpriseStrategyManager] Pipeline: ", m_usePipeline ? "ENABLED" : "DISABLED");
    
    return true;
}

//+------------------------------------------------------------------+
//| Register Strategy                                               |
//+------------------------------------------------------------------+
bool CEnterpriseStrategyManager::RegisterStrategy(IStrategy* strategy, const string name,
                                                 bool enabled, double weight,
                                                 ENUM_STRATEGY_TIER tier,
                                                 ENUM_TIMEFRAMES tf,
                                                 bool intrabarEligible,
                                                 ENUM_STRATEGY_ROLE role,
                                                 ENUM_STRATEGY_CLUSTER cluster,
                                                 bool liveVotingEnabled,
                                                 bool shadowOnly)
{
    if(strategy == NULL || !m_initialized)
        return false;
        
    // Prevent unbounded strategy growth
    if(m_strategyCount >= m_maxStrategies)
    {
        Print("[EnterpriseStrategyManager] ERROR: Max strategy limit reached (", m_maxStrategies, ")");
        delete strategy;
        return false;
    }
    
    // Initialize strategy with VALID pointers (ARCHITECTURAL FIX: inject unified risk manager)
    ENUM_TIMEFRAMES resolvedTf = (tf == PERIOD_CURRENT ? m_baseTimeframe : tf);
    bool initSuccess = strategy.Init(m_symbol, resolvedTf,
                                     m_tradeManager, m_positionSizer, m_unifiedRiskManager);
    
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
    m_strategies[m_strategyCount].intrabarPolicy = intrabarEligible ? (int)INTRABAR_POLICY_LIVE : (int)INTRABAR_POLICY_OFF;
    m_strategies[m_strategyCount].liveVotingEnabled = liveVotingEnabled;
    m_strategies[m_strategyCount].shadowOnly = shadowOnly;
    m_strategies[m_strategyCount].role = (int)role;
    m_strategies[m_strategyCount].cluster = (int)cluster;
    m_strategies[m_strategyCount].tier = tier; // Store tier
    m_strategies[m_strategyCount].weight = weight;
    m_strategies[m_strategyCount].originalWeight = weight;  // Track for decay recovery
    m_strategies[m_strategyCount].timeframe = resolvedTf;
    m_strategies[m_strategyCount].successCount = 0;
    m_strategies[m_strategyCount].failCount = 0;
    m_strategies[m_strategyCount].healthScore = 0.75;
    m_strategies[m_strategyCount].participationScore = 0.75;
    m_strategies[m_strategyCount].avgConfidence = 0;
    m_strategies[m_strategyCount].lastSignal = TRADE_SIGNAL_NONE;
    m_strategies[m_strategyCount].lastSignalConfidence = 0.0;
    m_strategies[m_strategyCount].lastEvaluationTime = 0;
    m_strategies[m_strategyCount].consecutiveFilterCount = 0;  // Track filters for weight decay
    
    // Performance metrics ported from AISO
    m_strategies[m_strategyCount].totalTrades = 0;
    m_strategies[m_strategyCount].winningTrades = 0;
    m_strategies[m_strategyCount].winRate = 0.0;
    m_strategies[m_strategyCount].avgProfit = 0.0;
    m_strategies[m_strategyCount].avgLoss = 0.0;
    m_strategies[m_strategyCount].profitFactor = 0.0;
    m_strategies[m_strategyCount].sharpeRatio = 0.0;
    m_strategies[m_strategyCount].recentTradeIndex = 0;
    m_strategies[m_strategyCount].recentTradeCount = 0;
    m_strategies[m_strategyCount].recentWinRate = 0.0;
    m_strategies[m_strategyCount].consecutiveLosses = 0;
    m_strategies[m_strategyCount].maxConsecutiveLosses = 0;
    m_strategies[m_strategyCount].consecutiveWins = 0;
    m_strategies[m_strategyCount].temporarilyDisabled = false;
    m_strategies[m_strategyCount].disabledUntil = 0;
    m_strategies[m_strategyCount].lastUpdate = 0;
    
    ArrayInitialize(m_strategies[m_strategyCount].recentTrades, 0.0);
    ArrayInitialize(m_strategies[m_strategyCount].regimePerformance, 0.0);
    ArrayInitialize(m_strategies[m_strategyCount].regimeTrades, 0);
    
    m_strategyCount++;
    
    Print("[EnterpriseStrategyManager] Registered strategy: ", name, 
          " | Enabled: ", enabled, " | Tier: ", (int)tier, " | Weight: ", weight,
          " | TF: ", EnumToString(resolvedTf),
          " | Intrabar: ", IntrabarPolicyToString((ENUM_INTRABAR_POLICY)m_strategies[m_strategyCount - 1].intrabarPolicy),
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
    m_lastDecisionContext = SConsensusDecisionContext();
    m_lastDecisionContext.symbol = symbol;

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
    int eligibleLiveVoterCount = 0;
    m_lastCycleSignalsGenerated = 0;
    m_lastCycleSignalsAfterPipeline = 0;
    m_lastCycleSignalAfterQuorum = false;

    // Store original symbol for restoration
    string originalSymbol = m_symbol;

    // Temporarily switch context to target symbol
    m_symbol = symbol;

    int buyVotes = 0, sellVotes = 0;
    int probeBuyVotes = 0, probeSellVotes = 0;
    double buyConviction = 0.0, sellConviction = 0.0;
    double probeBuyConviction = 0.0, probeSellConviction = 0.0;
    double buyWeightSum = 0.0, sellWeightSum = 0.0;
    double probeBuyWeightSum = 0.0, probeSellWeightSum = 0.0;
    double buyContextSum = 0.0, sellContextSum = 0.0;
    double probeBuyContextSum = 0.0, probeSellContextSum = 0.0;
    double buyReadinessSum = 0.0, sellReadinessSum = 0.0;
    double probeBuyReadinessSum = 0.0, probeSellReadinessSum = 0.0;
    double buyCostSum = 0.0, sellCostSum = 0.0;
    double probeBuyCostSum = 0.0, probeSellCostSum = 0.0;
    double totalLiveWeight = 0.0;

    // Cross-cluster conflict resolution: per-cluster conviction tracking
    double trendClusterBuyConviction = 0.0;
    double trendClusterSellConviction = 0.0;
    double meanRevClusterBuyConviction = 0.0;
    double meanRevClusterSellConviction = 0.0;
    double readyLiveWeight = 0.0;
    double readyContextWeightedSum = 0.0;
    double readyCostWeightedSum = 0.0;
    double quorumMinConfidence = MathMax(0.0, MathMin(1.0, m_pipelineMinConfidence));
    int activeLiveStrategies = 0;
    string activeStrategySummary = "";
    string votedStrategySummary = "";
    string rawNoneStrategySummary = "";
    string filteredStrategySummary = "";
    string suppressedStrategySummary = "";
    string buyContributors[];
    string sellContributors[];
    string probeBuyContributors[];
    string probeSellContributors[];
    int buyContributorIndices[];
    int sellContributorIndices[];
    int probeBuyContributorIndices[];
    int probeSellContributorIndices[];
    ArrayResize(buyContributors, 0);
    ArrayResize(sellContributors, 0);
    ArrayResize(probeBuyContributors, 0);
    ArrayResize(probeSellContributors, 0);
    ArrayResize(buyContributorIndices, 0);
    ArrayResize(sellContributorIndices, 0);
    ArrayResize(probeBuyContributorIndices, 0);
    ArrayResize(probeSellContributorIndices, 0);

    if(m_usePipeline && m_pipeline != NULL)
        m_pipeline.SetIntrabarContext(evalMode == EVAL_MODE_INTRABAR);

    if(m_tfConsistency != NULL)
        m_tfConsistency.Reset();

    for(int i = 0; i < m_strategyCount; i++)
    {
        if(!m_strategies[i].enabled)
            continue;

        if(StringLen(activeStrategySummary) > 0)
            activeStrategySummary += ", ";
        activeStrategySummary += m_strategies[i].name;

        bool liveVoter = IsStrategyLiveVoter(i);
        ENUM_INTRABAR_POLICY intrabarPolicy = GetStrategyIntrabarPolicy(i);
        bool liveEligibleForThisEval = liveVoter;
        bool probeEligibleForThisEval = false;
        bool countInMainFunnel = true;
        if(evalMode == EVAL_MODE_INTRABAR)
        {
            if(intrabarPolicy == INTRABAR_POLICY_OFF)
            {
                cycleIntrabarNotEligible++;
                continue;
            }

            if(intrabarPolicy == INTRABAR_POLICY_PROBE)
            {
                liveEligibleForThisEval = false;
                probeEligibleForThisEval = true;
                countInMainFunnel = false;
            }

            if(liveVoter && liveEligibleForThisEval)
                eligibleLiveVoterCount++;
        }
        else if(liveVoter)
        {
            eligibleLiveVoterCount++;
        }

        double strategyWeight = 0.0;
        double adjustedStrategyWeight = 0.0;
        if(liveVoter)
        {
            strategyWeight = MathMax(0.0, m_strategies[i].weight);
            if(strategyWeight <= 0.0)
            {
                liveEligibleForThisEval = false;
                probeEligibleForThisEval = false;
                countInMainFunnel = false;
            }
                
            // Apply Tier Multiplier from Ranking Matrix
            double tierMultiplier = CRankingMatrix::GetTierMultiplier(m_strategies[i].tier);
            
            adjustedStrategyWeight = strategyWeight * tierMultiplier *
                                     GetStrategyRoleVoteMultiplier(i) *
                                     GetStrategyReliabilityMultiplier(i) *
                                     GetStrategyParticipationMultiplier(i);
                                     
            if(liveEligibleForThisEval)
            {
                activeLiveStrategies++;
            }
        }

        double stratConf = 0.0;
        ENUM_TRADE_SIGNAL signal = TRADE_SIGNAL_NONE;
        SPipelineEvidenceSnapshot pipelineEvidence;
        bool rawNone = false;
        bool filteredByPipeline = false;
        string pipelineFilterName = "";
        string pipelineFilterReason = "";

        // Get signal (filtered if pipeline enabled)
        if(m_usePipeline && m_pipeline != NULL)
        {
            signal = m_pipeline.ProcessSignal(m_strategies[i].strategy,
                                              symbol,
                                              m_strategies[i].timeframe,
                                              stratConf);
            m_pipeline.GetLastEvidenceSnapshot(pipelineEvidence);
            rawNone = m_pipeline.WasLastSignalRawNone();
            filteredByPipeline = m_pipeline.WasLastSignalFilteredByPipeline();
            pipelineFilterName = m_pipeline.GetLastFilterName();
            pipelineFilterReason = m_pipeline.GetLastFilterReason();
            if(countInMainFunnel)
            {
                if(rawNone)
                    cycleRawNone++;
                else
                    cycleSignalsGenerated++;
                if(filteredByPipeline)
                    cycleFilteredOut++;
                if(signal != TRADE_SIGNAL_NONE)
                    cycleSignalsAfterPipeline++;
            }
        }
        else
        {
            signal = m_strategies[i].strategy.GetSignal(stratConf);
            pipelineEvidence = SPipelineEvidenceSnapshot();
            pipelineEvidence.symbol = symbol;
            pipelineEvidence.timeframe = m_strategies[i].timeframe;
            pipelineEvidence.contextPrepared = true;
            pipelineEvidence.readinessScore = 1.0;
            pipelineEvidence.contextScore = 0.75;
            pipelineEvidence.costScore = 0.75;
            pipelineEvidence.effectiveMinConfidence = quorumMinConfidence;
            if(countInMainFunnel)
            {
                if(signal == TRADE_SIGNAL_NONE)
                    cycleRawNone++;
                else
                {
                    cycleSignalsGenerated++;
                    cycleSignalsAfterPipeline++;
                }
            }
        }
        
        // NEW: Tier-based confidence filtering with Special Confluence Bypass
        double minTierConf = CRankingMatrix::GetRequiredConfidence(m_strategies[i].tier);
        
        // SPECIAL BYPASS: Trend + Support/Resistance Reversal Override
        // If they have "good" confidence (>0.65), they bypass the tier floor 
        // to ensure reversals are heard even during strong Tier 1 (ICT) moves.
        // Fibonacci REMOVED — S/R now carries the confluence module
        bool bypassTierFloor = false;
        if(m_strategies[i].name == "Trend" || m_strategies[i].name == "Support/Resistance")
        {
            if(stratConf > 0.65)
                bypassTierFloor = true;
        }

        if(signal != TRADE_SIGNAL_NONE && !bypassTierFloor && stratConf < minTierConf)
        {
            // Signal suppressed due to low tier-confidence
            string suppressedEntry = StringFormat("%s:%s@%.2f[TIER-LOW]", 
                                                 m_strategies[i].name, 
                                                 TradeSignalToString(signal), 
                                                 stratConf);
            if(StringLen(suppressedStrategySummary) > 0)
                suppressedStrategySummary += ", ";
            suppressedStrategySummary += suppressedEntry;
            
            signal = TRADE_SIGNAL_NONE;
            cycleVoteSuppressed++;
        }

        double participationTarget = 0.45;
        if(signal != TRADE_SIGNAL_NONE)
            participationTarget = 1.0;
        else if(filteredByPipeline)
            participationTarget = 0.65;
        else if(rawNone)
            participationTarget = 0.35;

        double previousParticipation = m_strategies[i].participationScore;
        if(previousParticipation <= 0.0)
            previousParticipation = 0.75;
        m_strategies[i].participationScore = MathMax(0.35,
                                                     MathMin(1.0,
                                                             (previousParticipation * 0.85) +
                                                             (participationTarget * 0.15)));

        string decisionReasonTag = m_strategies[i].strategy.GetLastDecisionReasonTag();
        bool placeholderNoSignalReason = false;
        if(signal == TRADE_SIGNAL_NONE &&
           (decisionReasonTag == "" ||
            decisionReasonTag == "BASE_INITIALIZED" ||
            decisionReasonTag == "BASE_UNSET"))
        {
            placeholderNoSignalReason = true;
            decisionReasonTag = filteredByPipeline ? "UNTAGGED_FILTERED" : "UNTAGGED_NO_SIGNAL";
        }
        bool infrastructureNoSignalReason = (signal == TRADE_SIGNAL_NONE &&
                                             IsInfrastructureNoSignalReasonTag(decisionReasonTag));
        if(signal == TRADE_SIGNAL_NONE)
        {
            string noneEntry = m_strategies[i].name;
            if(filteredByPipeline)
            {
                string pipelineFilterTag = "PIPELINE";
                if(pipelineFilterName != "")
                    pipelineFilterTag = "PIPELINE:" + pipelineFilterName;
                if(pipelineFilterReason != "")
                {
                    string pipelineReasonSnippet = pipelineFilterReason;
                    if(StringLen(pipelineReasonSnippet) > 72)
                        pipelineReasonSnippet = StringSubstr(pipelineReasonSnippet, 0, 72) + "...";
                    pipelineFilterTag += ":" + pipelineReasonSnippet;
                }
                if(decisionReasonTag != "")
                    noneEntry += "[" + decisionReasonTag + "|" + pipelineFilterTag + "]";
                else
                    noneEntry += "[" + pipelineFilterTag + "]";
                if(StringLen(filteredStrategySummary) > 0)
                    filteredStrategySummary += ", ";
                filteredStrategySummary += noneEntry;
            }
            else
            {
                if(decisionReasonTag != "")
                    noneEntry += "[" + decisionReasonTag + "]";
                if(StringLen(rawNoneStrategySummary) > 0)
                    rawNoneStrategySummary += ", ";
                rawNoneStrategySummary += noneEntry;
            }
        }
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
        m_strategies[i].avgConfidence = (m_strategies[i].avgConfidence <= 0.0)
                                        ? stratConf
                                        : ((m_strategies[i].avgConfidence * 0.85) + (stratConf * 0.15));

        double signalConfidenceFloor = quorumMinConfidence;
        if(m_usePipeline && m_pipeline != NULL)
            signalConfidenceFloor = MathMax(0.0, MathMin(1.0, m_pipeline.GetLastEffectiveMinConfidence()));
        signalConfidenceFloor = MathMax(0.20, signalConfidenceFloor * 0.80);

        // Dynamic weight decay: track and reduce weight for persistently inactive strategies
        if(signal == TRADE_SIGNAL_NONE)
        {
            m_strategies[i].consecutiveFilterCount++;
            // Apply weight decay after threshold
            if(m_strategies[i].consecutiveFilterCount >= m_strategyInactiveCounterThreshold)
            {
                double decayedWeight = m_strategies[i].originalWeight *
                                     (1.0 - (m_strategyActivityDecayRate *
                                     (double)(m_strategies[i].consecutiveFilterCount - m_strategyInactiveCounterThreshold + 1)));
                m_strategies[i].weight = MathMax(0.1, MathMin(m_strategies[i].originalWeight, decayedWeight));
            }
        }
        else
        {
            // Reset filter counter when strategy produces a vote
            m_strategies[i].consecutiveFilterCount = 0;
            // Allow weight recovery toward original
            m_strategies[i].weight = MathMin(m_strategies[i].weight + (m_strategyActivityDecayRate * 0.05),
                                            m_strategies[i].originalWeight);
        }

        if(!liveVoter && !probeEligibleForThisEval)
        {
            if(signal != TRADE_SIGNAL_NONE)
            {
                cycleVoteSuppressed++;
                string suppressedEntry = StringFormat("%s:%s@%.2f",
                                                     m_strategies[i].name,
                                                     TradeSignalToString(signal),
                                                     stratConf);
                if(StringLen(suppressedStrategySummary) > 0)
                    suppressedStrategySummary += ", ";
                suppressedStrategySummary += suppressedEntry;
            }
            continue;
        }

        if(evalMode == EVAL_MODE_INTRABAR && !liveEligibleForThisEval && !probeEligibleForThisEval)
        {
            if(signal != TRADE_SIGNAL_NONE)
            {
                cycleVoteSuppressed++;
                string suppressedEntry = StringFormat("%s:%s@%.2f",
                                                     m_strategies[i].name,
                                                     TradeSignalToString(signal),
                                                     stratConf);
                if(StringLen(suppressedStrategySummary) > 0)
                    suppressedStrategySummary += ", ";
                suppressedStrategySummary += suppressedEntry;
            }
            continue;
        }

        double readinessScore = MathMax(0.35, MathMin(1.0, pipelineEvidence.readinessScore));
        double contextScore = MathMax(0.35, MathMin(1.0, pipelineEvidence.contextScore));
        double costScore = MathMax(0.25, MathMin(1.0, pipelineEvidence.costScore));
        double denominatorWeight = adjustedStrategyWeight;
        if(signal == TRADE_SIGNAL_NONE)
        {
            if(placeholderNoSignalReason || infrastructureNoSignalReason)
                denominatorWeight *= 0.15;
            else if(filteredByPipeline)
                denominatorWeight *= 0.55;
            else if(rawNone)
                denominatorWeight *= 0.35;
            else
                denominatorWeight *= 0.50;
        }

        if(placeholderNoSignalReason || infrastructureNoSignalReason)
        {
            // Unclassified or infrastructure no-signal states should not dilute live quorum
            // as if they had completed a real decision cycle with meaningful evidence.
            readinessScore = MathMin(readinessScore, 0.15);
            contextScore = MathMin(contextScore, 0.35);
            costScore = MathMin(costScore, 0.35);
        }
        double readyWeightContribution = denominatorWeight * readinessScore;
        if(liveVoter && liveEligibleForThisEval)
        {
            totalLiveWeight += denominatorWeight;
            readyLiveWeight += readyWeightContribution;
            readyContextWeightedSum += contextScore * readyWeightContribution;
            readyCostWeightedSum += costScore * readyWeightContribution;
        }

        if(signal != TRADE_SIGNAL_NONE)
        {
            string votedEntry = StringFormat("%s:%s@%.2f",
                                             m_strategies[i].name,
                                             TradeSignalToString(signal),
                                             stratConf);
            if(StringLen(votedStrategySummary) > 0)
                votedStrategySummary += ", ";
            votedStrategySummary += votedEntry;
        }

        if(m_tfConsistency != NULL && signal != TRADE_SIGNAL_NONE && stratConf >= signalConfidenceFloor && (liveEligibleForThisEval || probeEligibleForThisEval))
        {
            m_tfConsistency.AddTimeframeSignal(m_strategies[i].timeframe,
                                               signal,
                                               stratConf,
                                               m_strategies[i].name);
        }

        if(signal == TRADE_SIGNAL_BUY && stratConf >= signalConfidenceFloor)
        {
            double conviction = MathMax(0.0, MathMin(1.0, stratConf * (0.50 + (0.20 * contextScore) + (0.20 * readinessScore) + (0.10 * costScore))));
            if(liveVoter && liveEligibleForThisEval)
            {
                buyVotes++;
                buyConviction += conviction * readyWeightContribution;
                buyWeightSum += readyWeightContribution;
                buyContextSum += contextScore * readyWeightContribution;
                buyReadinessSum += readinessScore * readyWeightContribution;
                buyCostSum += costScore * readyWeightContribution;

                // Per-cluster conviction tracking for cross-cluster conflict resolution
                ENUM_STRATEGY_CLUSTER voteCluster = (ENUM_STRATEGY_CLUSTER)m_strategies[i].cluster;
                if(voteCluster == TREND_CLUSTER)
                    trendClusterBuyConviction += conviction * readyWeightContribution;
                else if(voteCluster == MEAN_REVERSION_CLUSTER)
                    meanRevClusterBuyConviction += conviction * readyWeightContribution;

                int buySize = ArraySize(buyContributors);
                ArrayResize(buyContributors, buySize + 1);
                ArrayResize(buyContributorIndices, buySize + 1);
                buyContributors[buySize] = m_strategies[i].name;
                buyContributorIndices[buySize] = i;
            }
            else if(probeEligibleForThisEval)
            {
                probeBuyVotes++;
                probeBuyConviction += conviction * readyWeightContribution;
                probeBuyWeightSum += readyWeightContribution;
                probeBuyContextSum += contextScore * readyWeightContribution;
                probeBuyReadinessSum += readinessScore * readyWeightContribution;
                probeBuyCostSum += costScore * readyWeightContribution;

                int probeBuySize = ArraySize(probeBuyContributors);
                ArrayResize(probeBuyContributors, probeBuySize + 1);
                ArrayResize(probeBuyContributorIndices, probeBuySize + 1);
                probeBuyContributors[probeBuySize] = m_strategies[i].name;
                probeBuyContributorIndices[probeBuySize] = i;
            }
        }
        else if(signal == TRADE_SIGNAL_SELL && stratConf >= signalConfidenceFloor)
        {
            double conviction = MathMax(0.0, MathMin(1.0, stratConf * (0.50 + (0.20 * contextScore) + (0.20 * readinessScore) + (0.10 * costScore))));
            if(liveVoter && liveEligibleForThisEval)
            {
                sellVotes++;
                sellConviction += conviction * readyWeightContribution;
                sellWeightSum += readyWeightContribution;
                sellContextSum += contextScore * readyWeightContribution;
                sellReadinessSum += readinessScore * readyWeightContribution;
                sellCostSum += costScore * readyWeightContribution;

                // Per-cluster conviction tracking for cross-cluster conflict resolution
                ENUM_STRATEGY_CLUSTER voteCluster = (ENUM_STRATEGY_CLUSTER)m_strategies[i].cluster;
                if(voteCluster == TREND_CLUSTER)
                    trendClusterSellConviction += conviction * readyWeightContribution;
                else if(voteCluster == MEAN_REVERSION_CLUSTER)
                    meanRevClusterSellConviction += conviction * readyWeightContribution;

                int sellSize = ArraySize(sellContributors);
                ArrayResize(sellContributors, sellSize + 1);
                ArrayResize(sellContributorIndices, sellSize + 1);
                sellContributors[sellSize] = m_strategies[i].name;
                sellContributorIndices[sellSize] = i;
            }
            else if(probeEligibleForThisEval)
            {
                probeSellVotes++;
                probeSellConviction += conviction * readyWeightContribution;
                probeSellWeightSum += readyWeightContribution;
                probeSellContextSum += contextScore * readyWeightContribution;
                probeSellReadinessSum += readinessScore * readyWeightContribution;
                probeSellCostSum += costScore * readyWeightContribution;

                int probeSellSize = ArraySize(probeSellContributors);
                ArrayResize(probeSellContributors, probeSellSize + 1);
                ArrayResize(probeSellContributorIndices, probeSellSize + 1);
                probeSellContributors[probeSellSize] = m_strategies[i].name;
                probeSellContributorIndices[probeSellSize] = i;
            }
        }

    }

    // Restore original symbol
    m_symbol = originalSymbol;

    m_diagRawNone += (ulong)MathMax(0, cycleRawNone);
    m_diagFilteredOut += (ulong)MathMax(0, cycleFilteredOut);
    m_diagIntrabarNotEligible += (ulong)MathMax(0, cycleIntrabarNotEligible);
    m_diagSignalsGenerated += (ulong)MathMax(0, cycleSignalsGenerated);
    m_diagSignalsAfterPipeline += (ulong)MathMax(0, cycleSignalsAfterPipeline);
    m_diagVoteSuppressed += (ulong)MathMax(0, cycleVoteSuppressed);

    //--- Cross-cluster conflict resolution ---
    // When trend and mean-reversion clusters disagree on direction,
    // the regime determines which cluster to trust.
    bool trendBuyActive = (trendClusterBuyConviction > 0.0);
    bool meanRevSellActive = (meanRevClusterSellConviction > 0.0);
    bool trendSellActive = (trendClusterSellConviction > 0.0);
    bool meanRevBuyActive = (meanRevClusterBuyConviction > 0.0);

    bool crossClusterConflict = (trendBuyActive && meanRevSellActive) ||
                                (trendSellActive && meanRevBuyActive);

    if(crossClusterConflict)
    {
        bool isTrendingRegime = IsTrendingRegime();

        if(isTrendingRegime)
        {
            // Trending regime: zero out mean-reversion votes
            buyConviction = MathMax(0.0, buyConviction - meanRevClusterBuyConviction);
            sellConviction = MathMax(0.0, sellConviction - meanRevClusterSellConviction);
        }
        else
        {
            // Ranging regime: zero out trend votes
            buyConviction = MathMax(0.0, buyConviction - trendClusterBuyConviction);
            sellConviction = MathMax(0.0, sellConviction - trendClusterSellConviction);
        }

        PrintFormat("[CONSENSUS-CONFLICT] %s: Cross-cluster conflict detected. Trend: Buy=%.2f/Sell=%.2f, MeanRev: Buy=%.2f/Sell=%.2f. Resolved using %s regime.",
                    symbol, trendClusterBuyConviction, trendClusterSellConviction,
                    meanRevClusterBuyConviction, meanRevClusterSellConviction,
                    isTrendingRegime ? "TRENDING" : "RANGING");
    }

    double minReadyWeight = totalLiveWeight * m_minReadyWeightRatio;
    bool readyWeightMet = (readyLiveWeight >= minReadyWeight);
    double readyCoverage = (totalLiveWeight > 0.0) ? ClampUnitValue(readyLiveWeight / totalLiveWeight) : 0.0;
    double quorumDenominator = (readyLiveWeight > 0.0) ? readyLiveWeight : totalLiveWeight;
    if(quorumDenominator <= 0.0)
        quorumDenominator = 1.0;

    double buyScore = ClampUnitValue(buyConviction / quorumDenominator);
    double sellScore = ClampUnitValue(sellConviction / quorumDenominator);
    double buyDirectionalQuality = (buyWeightSum > 0.0) ? ClampUnitValue(buyConviction / buyWeightSum) : 0.0;
    double sellDirectionalQuality = (sellWeightSum > 0.0) ? ClampUnitValue(sellConviction / sellWeightSum) : 0.0;
    double buySupportRatio = (readyLiveWeight > 0.0) ? ClampUnitValue(buyWeightSum / readyLiveWeight) : 0.0;
    double sellSupportRatio = (readyLiveWeight > 0.0) ? ClampUnitValue(sellWeightSum / readyLiveWeight) : 0.0;
    double buyAverageReadiness = (buyWeightSum > 0.0) ? ClampUnitValue(buyReadinessSum / buyWeightSum) : 0.0;
    double sellAverageReadiness = (sellWeightSum > 0.0) ? ClampUnitValue(sellReadinessSum / sellWeightSum) : 0.0;
    double buyAverageContext = (buyWeightSum > 0.0) ? ClampUnitValue(buyContextSum / buyWeightSum) : 0.0;
    double sellAverageContext = (sellWeightSum > 0.0) ? ClampUnitValue(sellContextSum / sellWeightSum) : 0.0;
    double buyAverageCost = (buyWeightSum > 0.0) ? ClampUnitValue(buyCostSum / buyWeightSum) : 0.0;
    double sellAverageCost = (sellWeightSum > 0.0) ? ClampUnitValue(sellCostSum / sellWeightSum) : 0.0;
    double overallReadyContext = (readyLiveWeight > 0.0) ? ClampUnitValue(readyContextWeightedSum / readyLiveWeight) : 0.0;
    double overallReadyCost = (readyLiveWeight > 0.0) ? ClampUnitValue(readyCostWeightedSum / readyLiveWeight) : 0.0;
    double supportFloor = (evalMode == EVAL_MODE_INTRABAR) ? m_supportFloorIntrabar : m_supportFloorNewBar;
    double effectiveQualityThreshold = m_quorumThreshold;
    double adaptiveQualityThreshold1 = MathMin(m_adaptiveQualityThreshold_1voter,
                                               MathMax(0.30, m_quorumThreshold - 0.05));
    double adaptiveQualityThreshold2 = MathMin(m_adaptiveQualityThreshold_2voters,
                                               MathMax(0.34, m_quorumThreshold - 0.02));

    // RECOVERY FIX: Pre-adapt quorum for low-voter ecosystems (AI-only mode).
    // When only 3 or fewer live strategies are registered, the standard 0.35
    // support floor is mathematically impossible for a single voter to meet.
    // Scale thresholds based on total registered live voters, not just active voters.
    if(m_adaptiveQuorumEnabled && activeLiveStrategies > 0 && activeLiveStrategies <= 3 && evalMode != EVAL_MODE_INTRABAR)
    {
        supportFloor = m_adaptiveSupportFloor_1voter;    // 0.15 — achievable with 1/3 voters
        effectiveQualityThreshold = adaptiveQualityThreshold1; // 0.40 — relaxed for sparse consensus
    }

    // Adaptive quorum: adjust thresholds based on actual active voter count
    if(m_adaptiveQuorumEnabled && (buyVotes + sellVotes) > 0)
    {
        int activeVoterCount = buyVotes + sellVotes;
        if(activeVoterCount == 1)
        {
            effectiveQualityThreshold = adaptiveQualityThreshold1;
            supportFloor = m_adaptiveSupportFloor_1voter;
        }
        else if(activeVoterCount == 2)
        {
            effectiveQualityThreshold = adaptiveQualityThreshold2;
            supportFloor = m_adaptiveSupportFloor_2voters;
        }
        // 3+ voters: use original thresholds (already set above)
    }

    int effectiveMinVoters = MathMax(1, m_minQuorum);
    
    // Single-voter quorum is only allowed when the configured live-voter floor permits it.
    if(activeLiveStrategies <= 3 && m_minQuorum <= 1)
    {
        effectiveMinVoters = 1;
    }
    
    if(evalMode == EVAL_MODE_INTRABAR)
    {
        int intrabarFloor = MathMax(1, m_intrabarMinQuorum);
        effectiveMinVoters = intrabarFloor;
        if(m_intrabarDynamicQuorumEnabled && eligibleLiveVoterCount >= 4 && effectiveMinVoters < 2)
            effectiveMinVoters = 2;
    }

    bool buyQuorumMet = (readyWeightMet &&
                         buyVotes >= effectiveMinVoters &&
                         buyDirectionalQuality >= effectiveQualityThreshold &&
                         buySupportRatio >= supportFloor);
    bool sellQuorumMet = (readyWeightMet &&
                          sellVotes >= effectiveMinVoters &&
                          sellDirectionalQuality >= effectiveQualityThreshold &&
                          sellSupportRatio >= supportFloor);

    ENUM_TRADE_SIGNAL finalSignal = TRADE_SIGNAL_NONE;
    ENUM_CONSENSUS_DECISION_CLASS decisionClass = CONSENSUS_DECISION_NONE;
    double finalConfidence = 0.0;
    double finalConvictionScore = 0.0;
    double finalDirectionalQuality = 0.0;
    double finalSupportRatio = 0.0;
    double finalDirectionalWeight = 0.0;
    double finalReadinessScore = 0.0;
    double finalContextScore = 0.0;
    double finalCostScore = 0.0;
    double finalStalenessPenalty = 0.0;
    int finalConfluence = 0;
    string selectedContributors[];
    int selectedContributorIndices[];
    string vetoCode = "";
    string vetoReason = "";
    bool selectedSparseFromProbe = false;
    ArrayResize(selectedContributors, 0);
    ArrayResize(selectedContributorIndices, 0);

    if(activeLiveStrategies <= 0 || totalLiveWeight <= 0.0)
    {
        vetoCode = "no_active_live_voters";
        vetoReason = "no_active_live_voters";
    }
    else if(buyQuorumMet && sellQuorumMet)
    {
        double scoreDelta = MathAbs(buyScore - sellScore);
        if(scoreDelta < m_conflictDeadband)
        {
            cycleQuorumFailed++;
            vetoCode = "deadband_conflict";
            vetoReason = StringFormat("buyScore=%.3f | sellScore=%.3f | deadband=%.3f",
                                      buyScore,
                                      sellScore,
                                      m_conflictDeadband);
        }
        else
        {
            finalSignal = (buyScore > sellScore) ? TRADE_SIGNAL_BUY : TRADE_SIGNAL_SELL;
        }
    }
    else if(buyQuorumMet)
    {
        finalSignal = TRADE_SIGNAL_BUY;
    }
    else if(sellQuorumMet)
    {
        finalSignal = TRADE_SIGNAL_SELL;
    }
    else
    {
        if((buyVotes + sellVotes) <= 0)
        {
            if(cycleSignalsGenerated > 0 || cycleSignalsAfterPipeline > 0 || cycleFilteredOut > 0)
            {
                vetoCode = "pipeline_filtered_all";
                vetoReason = StringFormat("All candidate signals were filtered/suppressed before quorum | generated=%d | after_pipeline=%d | filtered_out=%d | suppressed=%d",
                                          cycleSignalsGenerated,
                                          cycleSignalsAfterPipeline,
                                          cycleFilteredOut,
                                          cycleVoteSuppressed);
            }
            else
            {
                vetoCode = "no_voters";
                vetoReason = "No strategies produced votes in this evaluation cycle";
            }
        }
        else if(!readyWeightMet)
        {
            vetoCode = "readiness_weight";
            vetoReason = StringFormat("readyWeight=%.2f < minRequired=%.2f",
                                      readyLiveWeight, minReadyWeight);
        }
        else
        {
            // Provide detailed diagnostic for partial failures
            int activeVoterCount = buyVotes + sellVotes;
            double bestQuality = MathMax(buyDirectionalQuality, sellDirectionalQuality);
            double bestSupport = MathMax(buySupportRatio, sellSupportRatio);

            if(bestQuality < effectiveQualityThreshold)
            {
                vetoCode = "insufficient_quality";
                vetoReason = StringFormat("quality=%.3f (need %.3f) | votes=%d | support=%.3f",
                                          bestQuality, effectiveQualityThreshold,
                                          activeVoterCount, bestSupport);
            }
            else if(bestSupport < supportFloor)
            {
                vetoCode = "insufficient_support";
                vetoReason = StringFormat("support=%.3f (need %.3f) | votes=%d | quality=%.3f",
                                          bestSupport, supportFloor,
                                          activeVoterCount, bestQuality);
            }
            else
            {
                vetoCode = "direction_quorum_not_met";
                vetoReason = StringFormat("buy=%.3f|%.3f vs sell=%.3f|%.3f",
                                          buyDirectionalQuality, buySupportRatio,
                                          sellDirectionalQuality, sellSupportRatio);
            }
        }

        if((buyVotes + sellVotes) > 0)
            cycleQuorumFailed++;
    }

    if(finalSignal != TRADE_SIGNAL_NONE)
    {
        decisionClass = CONSENSUS_DECISION_FULL_QUORUM;
        if(finalSignal == TRADE_SIGNAL_BUY)
        {
            finalConfluence = buyVotes;
            finalDirectionalQuality = buyDirectionalQuality;
            finalSupportRatio = buySupportRatio;
            finalDirectionalWeight = buyWeightSum;
            finalReadinessScore = (buyWeightSum > 0.0) ? ClampUnitValue(buyReadinessSum / buyWeightSum) : 0.0;
            finalContextScore = (buyWeightSum > 0.0) ? ClampUnitValue(buyContextSum / buyWeightSum) : 0.0;
            finalCostScore = (buyWeightSum > 0.0) ? ClampUnitValue(buyCostSum / buyWeightSum) : 0.0;
            finalConvictionScore = buyScore;
            finalConfidence = ClampUnitValue((finalDirectionalQuality * 0.75) + (finalSupportRatio * 0.25));
            ArrayCopy(selectedContributors, buyContributors);
            ArrayCopy(selectedContributorIndices, buyContributorIndices);
        }
        else
        {
            finalConfluence = sellVotes;
            finalDirectionalQuality = sellDirectionalQuality;
            finalSupportRatio = sellSupportRatio;
            finalDirectionalWeight = sellWeightSum;
            finalReadinessScore = (sellWeightSum > 0.0) ? ClampUnitValue(sellReadinessSum / sellWeightSum) : 0.0;
            finalContextScore = (sellWeightSum > 0.0) ? ClampUnitValue(sellContextSum / sellWeightSum) : 0.0;
            finalCostScore = (sellWeightSum > 0.0) ? ClampUnitValue(sellCostSum / sellWeightSum) : 0.0;
            finalConvictionScore = sellScore;
            finalConfidence = ClampUnitValue((finalDirectionalQuality * 0.75) + (finalSupportRatio * 0.25));
            ArrayCopy(selectedContributors, sellContributors);
            ArrayCopy(selectedContributorIndices, sellContributorIndices);
        }
    }
    else if(evalMode == EVAL_MODE_INTRABAR && m_allowSparseIntrabarSingleVoter)
    {
        int totalBuyVotesAll = buyVotes + probeBuyVotes;
        int totalSellVotesAll = sellVotes + probeSellVotes;

        if(totalBuyVotesAll == 1 && totalSellVotesAll == 0)
        {
            bool useProbe = (buyVotes == 0 && probeBuyVotes == 1);
            double sparseDirectionalWeight = useProbe ? probeBuyWeightSum : buyWeightSum;
            double sparseDirectionalConviction = useProbe ? probeBuyConviction : buyConviction;
            double sparseDirectionalQuality = (sparseDirectionalWeight > 0.0)
                                              ? ClampUnitValue(sparseDirectionalConviction / sparseDirectionalWeight)
                                              : 0.0;
            double sparseSupportRatio = (readyLiveWeight > 0.0)
                                        ? ClampUnitValue(sparseDirectionalWeight / readyLiveWeight)
                                        : 0.0;
            double sparseReadiness = useProbe
                                     ? ((probeBuyWeightSum > 0.0) ? ClampUnitValue(probeBuyReadinessSum / probeBuyWeightSum) : 0.0)
                                     : ((buyWeightSum > 0.0) ? ClampUnitValue(buyReadinessSum / buyWeightSum) : 0.0);
            double sparseContext = useProbe
                                   ? ((probeBuyWeightSum > 0.0) ? ClampUnitValue(probeBuyContextSum / probeBuyWeightSum) : 0.0)
                                   : ((buyWeightSum > 0.0) ? ClampUnitValue(buyContextSum / buyWeightSum) : 0.0);
            double sparseCost = useProbe
                                ? ((probeBuyWeightSum > 0.0) ? ClampUnitValue(probeBuyCostSum / probeBuyWeightSum) : 0.0)
                                : ((buyWeightSum > 0.0) ? ClampUnitValue(buyCostSum / buyWeightSum) : 0.0);

            if(!readyWeightMet || readyCoverage < m_sparseIntrabarMinReadyCoverage)
                vetoCode = "readiness_coverage";
            else if(sparseReadiness < 0.80)
                vetoCode = "readiness_gate";
            else if(sparseContext < 0.70)
                vetoCode = "context_gate";
            else if(sparseCost < 0.70)
                vetoCode = "cost_gate";
            else if(sparseDirectionalQuality < MathMax(m_sparseIntrabarMinQuality, m_intrabarSingleVoterMinConfidence))
                vetoCode = "single_voter_confidence";
            else if(sparseSupportRatio < m_sparseIntrabarMinSupportRatio)
                vetoCode = "sparse_support";
            else
            {
                finalSignal = TRADE_SIGNAL_BUY;
                decisionClass = CONSENSUS_DECISION_SPARSE_INTRABAR;
                finalConfluence = 1;
                finalDirectionalQuality = sparseDirectionalQuality;
                finalSupportRatio = sparseSupportRatio;
                finalDirectionalWeight = sparseDirectionalWeight;
                finalReadinessScore = sparseReadiness;
                finalContextScore = sparseContext;
                finalCostScore = sparseCost;
                finalConvictionScore = ClampUnitValue(sparseDirectionalConviction / quorumDenominator);
                finalConfidence = ClampUnitValue(((finalDirectionalQuality * 0.75) + (finalSupportRatio * 0.25)) * m_sparseIntrabarConfidencePenalty);
                selectedSparseFromProbe = useProbe;
                if(useProbe)
                {
                    ArrayCopy(selectedContributors, probeBuyContributors);
                    ArrayCopy(selectedContributorIndices, probeBuyContributorIndices);
                }
                else
                {
                    ArrayCopy(selectedContributors, buyContributors);
                    ArrayCopy(selectedContributorIndices, buyContributorIndices);
                }
            }
        }
        else if(totalSellVotesAll == 1 && totalBuyVotesAll == 0)
        {
            bool useProbe = (sellVotes == 0 && probeSellVotes == 1);
            double sparseDirectionalWeight = useProbe ? probeSellWeightSum : sellWeightSum;
            double sparseDirectionalConviction = useProbe ? probeSellConviction : sellConviction;
            double sparseDirectionalQuality = (sparseDirectionalWeight > 0.0)
                                              ? ClampUnitValue(sparseDirectionalConviction / sparseDirectionalWeight)
                                              : 0.0;
            double sparseSupportRatio = (readyLiveWeight > 0.0)
                                        ? ClampUnitValue(sparseDirectionalWeight / readyLiveWeight)
                                        : 0.0;
            double sparseReadiness = useProbe
                                     ? ((probeSellWeightSum > 0.0) ? ClampUnitValue(probeSellReadinessSum / probeSellWeightSum) : 0.0)
                                     : ((sellWeightSum > 0.0) ? ClampUnitValue(sellReadinessSum / sellWeightSum) : 0.0);
            double sparseContext = useProbe
                                   ? ((probeSellWeightSum > 0.0) ? ClampUnitValue(probeSellContextSum / probeSellWeightSum) : 0.0)
                                   : ((sellWeightSum > 0.0) ? ClampUnitValue(sellContextSum / sellWeightSum) : 0.0);
            double sparseCost = useProbe
                                ? ((probeSellWeightSum > 0.0) ? ClampUnitValue(probeSellCostSum / probeSellWeightSum) : 0.0)
                                : ((sellWeightSum > 0.0) ? ClampUnitValue(sellCostSum / sellWeightSum) : 0.0);

            if(!readyWeightMet || readyCoverage < m_sparseIntrabarMinReadyCoverage)
                vetoCode = "readiness_coverage";
            else if(sparseReadiness < 0.80)
                vetoCode = "readiness_gate";
            else if(sparseContext < 0.70)
                vetoCode = "context_gate";
            else if(sparseCost < 0.70)
                vetoCode = "cost_gate";
            else if(sparseDirectionalQuality < MathMax(m_sparseIntrabarMinQuality, m_intrabarSingleVoterMinConfidence))
                vetoCode = "single_voter_confidence";
            else if(sparseSupportRatio < m_sparseIntrabarMinSupportRatio)
                vetoCode = "sparse_support";
            else
            {
                finalSignal = TRADE_SIGNAL_SELL;
                decisionClass = CONSENSUS_DECISION_SPARSE_INTRABAR;
                finalConfluence = 1;
                finalDirectionalQuality = sparseDirectionalQuality;
                finalSupportRatio = sparseSupportRatio;
                finalDirectionalWeight = sparseDirectionalWeight;
                finalReadinessScore = sparseReadiness;
                finalContextScore = sparseContext;
                finalCostScore = sparseCost;
                finalConvictionScore = ClampUnitValue(sparseDirectionalConviction / quorumDenominator);
                finalConfidence = ClampUnitValue(((finalDirectionalQuality * 0.75) + (finalSupportRatio * 0.25)) * m_sparseIntrabarConfidencePenalty);
                selectedSparseFromProbe = useProbe;
                if(useProbe)
                {
                    ArrayCopy(selectedContributors, probeSellContributors);
                    ArrayCopy(selectedContributorIndices, probeSellContributorIndices);
                }
                else
                {
                    ArrayCopy(selectedContributors, sellContributors);
                    ArrayCopy(selectedContributorIndices, sellContributorIndices);
                }
            }
        }
    }

    if(m_tfConsistency != NULL && m_tfConsistency.HasConflicts())
    {
        double resolvedConfidence = 0.0;
        string reasoning = "";
        ENUM_TRADE_SIGNAL resolvedSignal = m_tfConsistency.ResolveSignals(resolvedConfidence, reasoning);

        if(finalSignal == TRADE_SIGNAL_NONE)
        {
            vetoCode = "timeframe_conflict";
            vetoReason = (reasoning != "") ? reasoning : "timeframe_conflict";
        }
        else if(resolvedSignal == TRADE_SIGNAL_NONE || resolvedSignal != finalSignal)
        {
            cycleQuorumFailed++;
            vetoCode = "timeframe_conflict";
            vetoReason = (reasoning != "") ? reasoning : "timeframe_conflict";
            finalSignal = TRADE_SIGNAL_NONE;
            finalConfidence = 0.0;
            finalConvictionScore = 0.0;
            finalDirectionalQuality = 0.0;
            finalSupportRatio = 0.0;
            finalDirectionalWeight = 0.0;
            finalReadinessScore = 0.0;
            finalContextScore = 0.0;
            finalCostScore = 0.0;
            finalConfluence = 0;
            ArrayResize(selectedContributors, 0);
            ArrayResize(selectedContributorIndices, 0);
        }
        else if(resolvedConfidence > 0.0)
        {
            finalConfidence = MathMin(finalConfidence, ClampUnitValue(resolvedConfidence));
        }
    }

    m_diagQuorumFailed += (ulong)MathMax(0, cycleQuorumFailed);

    if(finalSignal != TRADE_SIGNAL_NONE)
    {
        if(selectedSparseFromProbe)
        {
            cycleSignalsGenerated++;
            cycleSignalsAfterPipeline++;
        }

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
        m_lastDecisionContext.symbol = symbol;
        m_lastDecisionContext.signal = finalSignal;
        m_lastDecisionContext.decisionClass = (int)decisionClass;
        m_lastDecisionContext.quorumMode = ConsensusDecisionClassToString(decisionClass);
        m_lastDecisionContext.confidence = confidence;
        m_lastDecisionContext.confluence = finalConfluence;
        m_lastDecisionContext.buyScore = buyScore;
        m_lastDecisionContext.sellScore = sellScore;
        m_lastDecisionContext.buySupport = buyWeightSum;
        m_lastDecisionContext.sellSupport = sellWeightSum;
        m_lastDecisionContext.readyLiveWeight = readyLiveWeight;
        m_lastDecisionContext.totalLiveWeight = totalLiveWeight;
        m_lastDecisionContext.readinessScore = finalReadinessScore;
        m_lastDecisionContext.contextScore = finalContextScore;
        m_lastDecisionContext.costScore = finalCostScore;
        m_lastDecisionContext.diversityScore = CalculateDirectionDiversityScore(selectedContributorIndices);
        m_lastDecisionContext.convictionScore = finalConvictionScore;
        m_lastDecisionContext.directionalQuality = finalDirectionalQuality;
        m_lastDecisionContext.supportRatio = finalSupportRatio;
        m_lastDecisionContext.directionalWeight = finalDirectionalWeight;
        m_lastDecisionContext.readyCoverage = readyCoverage;
        m_lastDecisionContext.quorumGap = 0.0;
        m_lastDecisionContext.stalenessPenalty = finalStalenessPenalty;
        m_lastDecisionContext.eligibleLiveVoterCount = eligibleLiveVoterCount;
        m_lastDecisionContext.effectiveMinVoters = effectiveMinVoters;
        m_lastDecisionContext.vetoCode = "";
        m_lastDecisionContext.reason = StringFormat("mode=%s | quality=%.3f | support=%.3f | readyCoverage=%.3f | contributors=%s",
                                                    m_lastDecisionContext.quorumMode,
                                                    finalDirectionalQuality,
                                                    finalSupportRatio,
                                                    readyCoverage,
                                                    JoinContributorsWithContext(selectedContributorIndices));

        PrintFormat("[CONSENSUS-QUORUM] %s | class=%s | buyScore=%.3f | sellScore=%.3f | buyQuality=%.3f | sellQuality=%.3f | supportFloor=%.2f | readyWeight=%.3f/%.3f | buyVoterCount=%d | sellVoterCount=%d | signal=%s",
                    symbol,
                    ConsensusDecisionClassToString(decisionClass),
                    buyScore,
                    sellScore,
                    buyDirectionalQuality,
                    sellDirectionalQuality,
                    supportFloor,
                    readyLiveWeight,
                    totalLiveWeight,
                    buyVotes,
                    sellVotes,
                    TradeSignalToString(finalSignal));
        if(decisionClass == CONSENSUS_DECISION_SPARSE_INTRABAR)
        {
            PrintFormat("[CONSENSUS-SPARSE] %s | signal=%s | quality=%.3f | support=%.3f | readyCoverage=%.3f | readiness=%.3f | context=%.3f | cost=%.3f | contributors=%s",
                        symbol,
                        TradeSignalToString(finalSignal),
                        finalDirectionalQuality,
                        finalSupportRatio,
                        readyCoverage,
                        finalReadinessScore,
                        finalContextScore,
                        finalCostScore,
                        JoinContributorsWithContext(selectedContributorIndices));
        }
        MaybeLogConsensusDiagnostics(symbol);
        return finalSignal;
    }

    double bestDirectionalQuality = MathMax(buyDirectionalQuality, sellDirectionalQuality);
    double bestSupportRatio = MathMax(buySupportRatio, sellSupportRatio);
    int bestVoterCount = MathMax(buyVotes, sellVotes);
    bool buyDominant = (buyDirectionalQuality > sellDirectionalQuality) ||
                       (buyDirectionalQuality == sellDirectionalQuality && buyScore >= sellScore);
    double dominantReadiness = buyDominant ? buyAverageReadiness : sellAverageReadiness;
    double dominantContext = buyDominant ? buyAverageContext : sellAverageContext;
    double dominantCost = buyDominant ? buyAverageCost : sellAverageCost;
    if(bestVoterCount <= 0)
    {
        dominantReadiness = readyCoverage;
        dominantContext = overallReadyContext;
        dominantCost = overallReadyCost;
    }
    double quorumGap = MathMax(0.0, effectiveQualityThreshold - bestDirectionalQuality);
    quorumGap = MathMax(quorumGap, MathMax(0.0, supportFloor - bestSupportRatio));
    if(effectiveMinVoters > 0 && bestVoterCount < effectiveMinVoters)
        quorumGap = MathMax(quorumGap, (double)(effectiveMinVoters - bestVoterCount) / (double)effectiveMinVoters);
    if(!readyWeightMet && totalLiveWeight > 0.0)
        quorumGap = MathMax(quorumGap, ClampUnitValue((minReadyWeight - readyLiveWeight) / totalLiveWeight));

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
    m_lastDecisionContext.symbol = symbol;
    m_lastDecisionContext.signal = TRADE_SIGNAL_NONE;
    m_lastDecisionContext.decisionClass = (int)((vetoCode != "") ? CONSENSUS_DECISION_VETOED : CONSENSUS_DECISION_NONE);
    m_lastDecisionContext.quorumMode = (vetoCode != "") ? "VETOED" : "NONE";
    m_lastDecisionContext.buyScore = buyScore;
    m_lastDecisionContext.sellScore = sellScore;
    m_lastDecisionContext.buySupport = buyWeightSum;
    m_lastDecisionContext.sellSupport = sellWeightSum;
    m_lastDecisionContext.readyLiveWeight = readyLiveWeight;
    m_lastDecisionContext.totalLiveWeight = totalLiveWeight;
    m_lastDecisionContext.readinessScore = dominantReadiness;
    m_lastDecisionContext.contextScore = dominantContext;
    m_lastDecisionContext.costScore = dominantCost;
    m_lastDecisionContext.convictionScore = MathMax(buyScore, sellScore);
    m_lastDecisionContext.directionalQuality = bestDirectionalQuality;
    m_lastDecisionContext.supportRatio = bestSupportRatio;
    m_lastDecisionContext.directionalWeight = MathMax(buyWeightSum, sellWeightSum);
    m_lastDecisionContext.readyCoverage = readyCoverage;
    m_lastDecisionContext.quorumGap = ClampUnitValue(quorumGap);
    m_lastDecisionContext.stalenessPenalty = 0.0;
    m_lastDecisionContext.eligibleLiveVoterCount = eligibleLiveVoterCount;
    m_lastDecisionContext.effectiveMinVoters = effectiveMinVoters;
    m_lastDecisionContext.vetoCode = (vetoCode != "") ? vetoCode : "direction_quorum_not_met";
    m_lastDecisionContext.reason = (vetoReason != "") ? vetoReason : m_lastDecisionContext.vetoCode;
    if((buyVotes + sellVotes + probeBuyVotes + probeSellVotes) > 0 && evalMode == EVAL_MODE_INTRABAR)
    {
        PrintFormat("[CONSENSUS-NEARMISS] %s | veto=%s | buyScore=%.3f | sellScore=%.3f | buyQuality=%.3f | sellQuality=%.3f | buyVotes=%d | sellVotes=%d | probeBuy=%d | probeSell=%d | readyCoverage=%.3f",
                    symbol,
                    m_lastDecisionContext.vetoCode,
                    buyScore,
                    sellScore,
                    buyDirectionalQuality,
                    sellDirectionalQuality,
                    buyVotes,
                    sellVotes,
                    probeBuyVotes,
                    probeSellVotes,
                    readyCoverage);
    }
    if(m_lastDecisionContext.reason != "")
    {
        PrintFormat("[CONSENSUS-VETO] %s | code=%s | reason=%s | buyScore=%.3f | sellScore=%.3f | buyQuality=%.3f | sellQuality=%.3f | supportFloor=%.2f | readyWeight=%.3f/%.3f | buyVoterCount=%d | sellVoterCount=%d",
                    symbol,
                    m_lastDecisionContext.vetoCode,
                    m_lastDecisionContext.reason,
                    buyScore,
                    sellScore,
                    buyDirectionalQuality,
                    sellDirectionalQuality,
                    supportFloor,
                    readyLiveWeight,
                    totalLiveWeight,
                    buyVotes,
                    sellVotes);
        PrintFormat("[CONSENSUS-ACTIVE] %s | active={%s} | voted={%s} | raw_none={%s} | filtered={%s} | suppressed={%s}",
                    symbol,
                    (StringLen(activeStrategySummary) > 0) ? activeStrategySummary : "None",
                    (StringLen(votedStrategySummary) > 0) ? votedStrategySummary : "None",
                    (StringLen(rawNoneStrategySummary) > 0) ? rawNoneStrategySummary : "None",
                    (StringLen(filteredStrategySummary) > 0) ? filteredStrategySummary : "None",
                    (StringLen(suppressedStrategySummary) > 0) ? suppressedStrategySummary : "None");
    }
    PrintFormat("[CONSENSUS-QUORUM] %s | class=%s | buyScore=%.3f | sellScore=%.3f | threshold=%.2f | supportFloor=%.2f | buyVoterCount=%d | sellVoterCount=%d | signal=%s",
                symbol,
                m_lastDecisionContext.quorumMode,
                buyScore,
                sellScore,
                effectiveQualityThreshold,
                supportFloor,
                buyVotes,
                sellVotes,
                TradeSignalToString(TRADE_SIGNAL_NONE));
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
//| Auto-register Strategies                                        |
//+------------------------------------------------------------------+
void CEnterpriseStrategyManager::AutoRegisterStrategies(bool &flags[])
{
    int size = ArraySize(flags);
    
    // 0: Momentum (live primary voter) - Tier 3
    if(size > 0 && flags[0]) RegisterStrategy(new CSimpleMomentumStrategy(), "Momentum", true, 1.0, STRATEGY_TIER_3, PERIOD_CURRENT, false,
                                             PRIMARY_ALPHA, TREND_CLUSTER, true, false);
    
    // 1: Trend (live primary voter) - Tier 2
    if(size > 1 && flags[1]) RegisterStrategy(new CStrategyTrend(), "Trend", true, 1.2, STRATEGY_TIER_2, PERIOD_CURRENT, false,
                                             PRIMARY_ALPHA, TREND_CLUSTER, true, false);
    
    // 2: Fibonacci REMOVED - Class deleted
    // if(size > 2 && flags[2]) RegisterStrategy(new CStrategyFibonacci(), "Fibonacci", true, 1.2, STRATEGY_TIER_2, PERIOD_CURRENT, false,
    //                                          PRIMARY_ALPHA, MEAN_REVERSION_CLUSTER, true, false);
    
    // ELLIOTT WAVE REMOVED - Registration deleted
    // 3: Elliott Wave (live primary voter) - Tier 1
    // if(size > 3 && flags[3]) RegisterStrategy(new CStrategyElliottWaveEnhanced(), "Elliott Wave", true, 2.0, STRATEGY_TIER_1, PERIOD_CURRENT, false,
    //                                          PRIMARY_ALPHA, STRUCTURE_CLUSTER, true, false);
    
    // 4: Support/Resistance (live primary voter) - Tier 2
    if(size > 4 && flags[4]) RegisterStrategy(new CStrategySupportResistance(), "Support/Resistance", true, 1.5, STRATEGY_TIER_2, PERIOD_CURRENT, false,
                                             PRIMARY_ALPHA, MEAN_REVERSION_CLUSTER, true, false);
    
    // 5: Unified ICT (live primary voter) - Tier 1
    if(size > 5 && flags[5]) RegisterStrategy(new CStrategyUnifiedICT(), "Unified ICT", true, 2.2, STRATEGY_TIER_1, PERIOD_CURRENT, false,
                                             PRIMARY_ALPHA, STRUCTURE_CLUSTER, true, false);
    
    // 6: Candlestick (live primary voter) - Tier 2
    if(size > 6 && flags[6]) RegisterStrategy(new CStrategyCandlestick(), "Candlestick", true, 1.5, STRATEGY_TIER_2, PERIOD_CURRENT, false,
                                             PRIMARY_ALPHA, STRUCTURE_CLUSTER, true, false);

    // 7: Unicorn Model (live primary voter) - Tier 1
    if(size > 7 && flags[7]) RegisterStrategy(new CUnicornModelStrategy(), "Unicorn Model", true, 2.4, STRATEGY_TIER_1, PERIOD_CURRENT, false,
                                             PRIMARY_ALPHA, STRUCTURE_CLUSTER, true, false);

    // 8: Power of Three / ICT 2025 (live primary voter) - Tier 1
    if(size > 8 && flags[8]) RegisterStrategy(new CPowerOfThreeStrategy(), "Power of Three", true, 2.3, STRATEGY_TIER_1, PERIOD_CURRENT, false,
                                             PRIMARY_ALPHA, STRUCTURE_CLUSTER, true, false);

    // 9: Mean Reversion (live primary voter) - Tier 2 - MEAN_REVERSION_CLUSTER
    if(size > 9 && flags[9]) RegisterStrategy(new CMeanReversionStrategy(), "Mean Reversion", true, 1.8, STRATEGY_TIER_2, PERIOD_CURRENT, true,
                                             PRIMARY_ALPHA, MEAN_REVERSION_CLUSTER, true, false);

    // 10: Volatility Breakout (live primary voter) - Tier 1 - TREND_CLUSTER
    if(size > 10 && flags[10]) RegisterStrategy(new CVolatilityBreakoutStrategy(), "Volatility Breakout", true, 2.0, STRATEGY_TIER_1, PERIOD_CURRENT, true,
                                               PRIMARY_ALPHA, TREND_CLUSTER, true, false);

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
        
        report += StringFormat("- %s: %s | Role: %s | Cluster: %s | LiveVote: %s | Trades: %d | Win Rate: %.1f%% | Avg Conf: %.2f | Participation: %.2f\n",
                             m_strategies[i].name,
                             m_strategies[i].enabled ? "ON" : "OFF",
                             StrategyRoleToString((ENUM_STRATEGY_ROLE)m_strategies[i].role),
                             StrategyClusterToString((ENUM_STRATEGY_CLUSTER)m_strategies[i].cluster),
                             IsStrategyLiveVoter(i) ? "YES" : "NO",
                             total, winRate, m_strategies[i].avgConfidence, m_strategies[i].participationScore);
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
    // Cache pipeline base confidence floor for quorum eligibility even if the pipeline is disabled.
    m_pipelineMinConfidence = MathMax(0.0, MathMin(1.0, settings.minConfidence));

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
    m_minWinRateThreshold = MathMax(0.0, MathMin(1.0, minWinRate));
    m_maxConsecutiveLosses_Limit = MathMax(1, maxLosses);
    PrintFormat("[EnterpriseStrategyManager] Adaptation thresholds updated | MinWinRate=%.2f | MaxConsecutiveLosses=%d",
                m_minWinRateThreshold,
                m_maxConsecutiveLosses_Limit);
}

string CEnterpriseStrategyManager::GetStrategyWeightsJSON() const
{
    string json = "{";
    for(int i = 0; i < m_strategyCount; i++)
    {
        string key = m_strategies[i].name;
        StringReplace(key, "\\", "\\\\");
        StringReplace(key, "\"", "\\\"");
        json += StringFormat("\"%s\":%.4f", key, m_strategies[i].weight);
        if(i < (m_strategyCount - 1))
            json += ",";
    }
    json += "}";
    return json;
}

void CEnterpriseStrategyManager::UpdateStrategyWeights()
{
    for(int i = 0; i < m_strategyCount; i++)
    {
        if(m_strategies[i].strategy == NULL)
            continue;

        // Performance-adaptive weight scaling using recent win rate.
        // This is intentionally conservative and bounded to prevent destabilizing consensus.
        double base = m_strategies[i].originalWeight > 0.0 ? m_strategies[i].originalWeight : m_strategies[i].weight;
        double wr = MathMax(0.0, MathMin(1.0, m_strategies[i].recentWinRate));
        double scale = 0.75 + (wr - 0.50); // 0.25..1.25 around 50% win rate
        scale = MathMax(0.50, MathMin(1.50, scale));
        double newWeight = MathMax(0.0, MathMin(10.0, base * scale));

        m_strategies[i].weight = newWeight;
        m_strategies[i].strategy.SetWeight(newWeight);
    }
}

void CEnterpriseStrategyManager::CheckStrategyDisabling()
{
    for(int i = 0; i < m_strategyCount; i++)
    {
        if(!m_strategies[i].enabled)
            continue;

        if(ShouldDisableStrategy(i))
        {
            m_strategies[i].temporarilyDisabled = true;
            m_strategies[i].disabledUntil = TimeCurrent() + 3600;
            m_strategies[i].enabled = false;
            PrintFormat("[Enterprise-Adaptation] Strategy %s disabled by governance | recent_winrate=%.2f | losses=%d",
                        m_strategies[i].name,
                        m_strategies[i].recentWinRate,
                        m_strategies[i].consecutiveLosses);
        }
    }
}

void CEnterpriseStrategyManager::CheckStrategyReEnabling()
{
    for(int i = 0; i < m_strategyCount; i++)
    {
        if(m_strategies[i].enabled)
            continue;
        if(!m_strategies[i].temporarilyDisabled)
            continue;

        if(ShouldReEnableStrategy(i))
        {
            m_strategies[i].temporarilyDisabled = false;
            m_strategies[i].disabledUntil = 0;
            m_strategies[i].enabled = true;
            PrintFormat("[Enterprise-Adaptation] Strategy %s re-enabled after cooldown",
                        m_strategies[i].name);
        }
    }
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
    return SetStrategyIntrabarPolicyByName(name, enabled ? INTRABAR_POLICY_LIVE : INTRABAR_POLICY_OFF);
}

bool CEnterpriseStrategyManager::SetStrategyIntrabarPolicyByName(const string name, ENUM_INTRABAR_POLICY policy)
{
    int index = FindStrategyIndexByName(name);
    if(index < 0)
        return false;

    m_strategies[index].intrabarPolicy = (int)policy;
    m_strategies[index].intrabarEligible = (policy == INTRABAR_POLICY_LIVE);
    PrintFormat("[EnterpriseStrategyManager] Intrabar policy updated: %s => %s",
                name, IntrabarPolicyToString(policy));
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

bool CEnterpriseStrategyManager::SetStrategyConfidenceThresholdByName(const string name, const double threshold)
{
    int index = FindStrategyIndexByName(name);
    if(index < 0)
        return false;

    if(m_strategies[index].strategy == NULL)
        return false;

    m_strategies[index].strategy.SetConfidenceThreshold(threshold);
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

bool CEnterpriseStrategyManager::GetLastDecisionContext(SConsensusDecisionContext &context) const
{
    context = m_lastDecisionContext;
    return (m_lastDecisionContext.signal != TRADE_SIGNAL_NONE);
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

double CEnterpriseStrategyManager::ClampUnitValue(const double value) const
{
    if(!MathIsValidNumber(value))
        return 0.0;
    return MathMax(0.0, MathMin(1.0, value));
}

ENUM_INTRABAR_POLICY CEnterpriseStrategyManager::GetStrategyIntrabarPolicy(const int strategyIndex) const
{
    if(strategyIndex < 0 || strategyIndex >= m_strategyCount)
        return INTRABAR_POLICY_OFF;

    int rawPolicy = m_strategies[strategyIndex].intrabarPolicy;
    if(rawPolicy < (int)INTRABAR_POLICY_OFF || rawPolicy > (int)INTRABAR_POLICY_LIVE)
        return m_strategies[strategyIndex].intrabarEligible ? INTRABAR_POLICY_LIVE : INTRABAR_POLICY_OFF;

    return (ENUM_INTRABAR_POLICY)rawPolicy;
}

bool CEnterpriseStrategyManager::IsStrategyIntrabarLiveEligible(const int strategyIndex) const
{
    return (GetStrategyIntrabarPolicy(strategyIndex) == INTRABAR_POLICY_LIVE);
}

bool CEnterpriseStrategyManager::IsStrategyIntrabarProbeEligible(const int strategyIndex) const
{
    return (GetStrategyIntrabarPolicy(strategyIndex) == INTRABAR_POLICY_PROBE);
}

double CEnterpriseStrategyManager::CalculateAverageStrategyMetric(const int &strategyIndices[], const double &metrics[]) const
{
    int samples = MathMin(ArraySize(strategyIndices), ArraySize(metrics));
    if(samples <= 0)
        return 0.0;

    double weightedSum = 0.0;
    double totalWeight = 0.0;
    for(int i = 0; i < samples; i++)
    {
        int idx = strategyIndices[i];
        if(idx < 0 || idx >= m_strategyCount)
            continue;

        double metric = ClampUnitValue(metrics[i]);
        double weight = MathMax(0.0, m_strategies[idx].weight);
        if(weight <= 0.0)
            continue;

        weightedSum += (metric * weight);
        totalWeight += weight;
    }

    if(totalWeight <= 0.0)
        return 0.0;

    return ClampUnitValue(weightedSum / totalWeight);
}

//+------------------------------------------------------------------+
//| Determine if current regime is trending for cross-cluster conflict |
//+------------------------------------------------------------------+
bool CEnterpriseStrategyManager::IsTrendingRegime() const
{
    // Primary: use RegimeEngine via pipeline if available
    if(m_pipeline != NULL)
    {
        CRegimeEngine* regimeEngine = m_pipeline.GetRegimeEngine();
        if(regimeEngine != NULL)
        {
            ENUM_REGIME_STATE state = regimeEngine.GetConfirmedState();
            return (state == REGIME_TREND);
        }
    }

    // Fallback: simple ADX-based check
    // ADX > 25 = trending, otherwise ranging
    int adxHandle = iADX(m_symbol, m_baseTimeframe, 14);
    if(adxHandle != INVALID_HANDLE)
    {
        double adxBuffer[];
        ArraySetAsSeries(adxBuffer, true);
        if(CopyBuffer(adxHandle, 0, 0, 1, adxBuffer) > 0)
        {
            IndicatorRelease(adxHandle);
            return (adxBuffer[0] > 25.0);
        }
        IndicatorRelease(adxHandle);
    }

    // Default: assume ranging (conservative)
    return false;
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

double CEnterpriseStrategyManager::GetStrategyReliabilityMultiplier(const int strategyIndex) const
{
    if(strategyIndex < 0 || strategyIndex >= m_strategyCount)
        return 0.75;

    double healthScore = m_strategies[strategyIndex].healthScore;
    if(healthScore <= 0.0)
        healthScore = 0.75;

    return MathMax(0.55, MathMin(1.15, 0.65 + (0.50 * healthScore)));
}

double CEnterpriseStrategyManager::GetStrategyParticipationMultiplier(const int strategyIndex) const
{
    if(strategyIndex < 0 || strategyIndex >= m_strategyCount)
        return 0.80;

    double participationScore = m_strategies[strategyIndex].participationScore;
    if(participationScore <= 0.0)
        participationScore = 0.75;

    return MathMax(0.55, MathMin(1.05, 0.40 + (0.65 * participationScore)));
}

double CEnterpriseStrategyManager::GetStrategyRoleVoteMultiplier(const int strategyIndex) const
{
    if(strategyIndex < 0 || strategyIndex >= m_strategyCount)
        return 1.0;

    ENUM_STRATEGY_ROLE role = (ENUM_STRATEGY_ROLE)m_strategies[strategyIndex].role;
    if(role == CONTEXT_FEATURE)
        return 0.85;
    if(role == SHADOW_RESEARCH)
        return 0.60;
    return 1.0;
}

double CEnterpriseStrategyManager::CalculateDirectionDiversityScore(const int &strategyIndices[]) const
{
    if(ArraySize(strategyIndices) <= 0)
        return 0.0;

    bool roleSeen[3];
    bool clusterSeen[4];
    roleSeen[0] = false;
    roleSeen[1] = false;
    roleSeen[2] = false;
    clusterSeen[0] = false;
    clusterSeen[1] = false;
    clusterSeen[2] = false;
    clusterSeen[3] = false;

    int roleCount = 0;
    int clusterCount = 0;
    for(int i = 0; i < ArraySize(strategyIndices); i++)
    {
        int idx = strategyIndices[i];
        if(idx < 0 || idx >= m_strategyCount)
            continue;

        int role = m_strategies[idx].role;
        if(role < 0 || role > 2)
            role = 0;
        if(!roleSeen[role])
        {
            roleSeen[role] = true;
            roleCount++;
        }

        int cluster = m_strategies[idx].cluster;
        if(cluster < 0 || cluster > 3)
            cluster = 0;
        if(!clusterSeen[cluster])
        {
            clusterSeen[cluster] = true;
            clusterCount++;
        }
    }

    double roleScore = MathMax(0.0, MathMin(1.0, (double)roleCount / 3.0));
    double clusterScore = MathMax(0.0, MathMin(1.0, (double)clusterCount / 4.0));
    return MathMax(0.0, MathMin(1.0, (roleScore * 0.55) + (clusterScore * 0.45)));
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
            continue;
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
            continue;
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
        int liveVoterCount = 0;
        int dormantLiveCount = 0;
        double liveParticipationSum = 0.0;
        string dormantStrategies = "";
        for(int i = 0; i < m_strategyCount; i++)
        {
            if(!IsStrategyLiveVoter(i))
                continue;

            liveVoterCount++;
            liveParticipationSum += m_strategies[i].participationScore;
            if(m_strategies[i].participationScore < 0.60)
            {
                dormantLiveCount++;
                if(dormantStrategies != "")
                    dormantStrategies += ", ";
                dormantStrategies += m_strategies[i].name + "(" + DoubleToString(m_strategies[i].participationScore, 2) + ")";
            }
        }
        double avgParticipation = (liveVoterCount > 0) ? ClampUnitValue(liveParticipationSum / liveVoterCount) : 0.0;

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
        PrintFormat("[CONSENSUS-ROLE] %s | primary=%I64u | feature=%I64u | shadow=%I64u | suppressed=%I64u | live_voters=%d | avg_participation=%.2f | dormant_live=%d | dormant_strategies=%s",
                    symbol,
                    intervalRolePrimarySignals,
                    intervalRoleFeatureSignals,
                    intervalRoleShadowSignals,
                    intervalVoteSuppressed,
                    liveVoterCount,
                    avgParticipation,
                    dormantLiveCount,
                    dormantStrategies);
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

void CEnterpriseStrategyManager::UpdatePerformance(const string strategyName, double netProfit)
{
    int idx = FindStrategyIndexByName(strategyName);
    if(idx < 0 || idx >= m_strategyCount)
        return;

    bool success = (netProfit > 0);
    
    // Update trade counts
    m_strategies[idx].totalTrades++;
    if(success)
    {
        m_strategies[idx].successCount++;
        m_strategies[idx].winningTrades++;
        m_strategies[idx].consecutiveWins++;
        m_strategies[idx].consecutiveLosses = 0;

        // Maintain rolling average profit per winning trade
        int wins = m_strategies[idx].winningTrades;
        if(wins > 0)
        {
            double prevTotalProfit = m_strategies[idx].avgProfit * (wins - 1);
            m_strategies[idx].avgProfit = (prevTotalProfit + netProfit) / wins;
        }
    }
    else
    {
        m_strategies[idx].failCount++;
        m_strategies[idx].consecutiveLosses++;
        m_strategies[idx].consecutiveWins = 0;

        // Maintain rolling average loss magnitude per losing trade
        int losses = m_strategies[idx].totalTrades - m_strategies[idx].winningTrades;
        if(losses > 0)
        {
            double absLoss = MathAbs(netProfit);
            double prevTotalLoss = m_strategies[idx].avgLoss * (losses - 1);
            m_strategies[idx].avgLoss = (prevTotalLoss + absLoss) / losses;
        }
        
        // Update max consecutive losses
        if(m_strategies[idx].consecutiveLosses > m_strategies[idx].maxConsecutiveLosses)
        {
            m_strategies[idx].maxConsecutiveLosses = m_strategies[idx].consecutiveLosses;
        }
    }

    // Update recent performance (rolling window)
    UpdateRecentPerformance(idx, netProfit);
    
    // Update regime-specific performance (placeholder for now, can be expanded)
    // UpdateRegimePerformance(idx, m_currentRegime, netProfit); 
    
    // Recalculate metrics (WinRate, ProfitFactor, Sharpe)
    CalculateStrategyMetrics(idx);
    
    // Health score update (original ESM logic blended with AISO metrics)
    int totalOutcomes = m_strategies[idx].successCount + m_strategies[idx].failCount;
    if(totalOutcomes > 0)
    {
        double realizedWinRate = (double)m_strategies[idx].successCount / (double)totalOutcomes;
        double sampleTrust = MathMin(1.0, (double)totalOutcomes / 20.0);
        double prior = 0.55;
        double blendedWinRate = (prior * (1.0 - sampleTrust)) + (realizedWinRate * sampleTrust);
        m_strategies[idx].healthScore = MathMax(0.35, MathMin(1.0, blendedWinRate));
    }
    
    m_strategies[idx].lastUpdate = TimeCurrent();

    // Check if strategy needs to be disabled
    if(ShouldDisableStrategy(idx))
    {
        m_strategies[idx].temporarilyDisabled = true;
        m_strategies[idx].disabledUntil = TimeCurrent() + 3600; // Disable for 1 hour
        PrintFormat("[Enterprise-Adaptation] Strategy %s DISABLED due to poor performance (WinRate: %.2f, Losses: %d)", 
                    strategyName, m_strategies[idx].winRate, m_strategies[idx].consecutiveLosses);
    }
}

void CEnterpriseStrategyManager::UpdateRecentPerformance(const int index, const double result)
{
    if(index < 0 || index >= m_strategyCount)
        return;
    
    // Add to circular buffer
    m_strategies[index].recentTrades[m_strategies[index].recentTradeIndex] = result;
    m_strategies[index].recentTradeIndex = (m_strategies[index].recentTradeIndex + 1) % m_rollingWindowSize;
    
    if(m_strategies[index].recentTradeCount < m_rollingWindowSize)
        m_strategies[index].recentTradeCount++;
}

double CEnterpriseStrategyManager::CalculateRecentWinRate(const int index)
{
    if(index < 0 || index >= m_strategyCount) return 0.0;
    if(m_strategies[index].recentTradeCount == 0) return 0.0;
    
    int wins = 0;
    for(int i = 0; i < m_strategies[index].recentTradeCount; i++)
    {
        if(m_strategies[index].recentTrades[i] > 0.0) wins++;
    }
    
    return (double)wins / m_strategies[index].recentTradeCount;
}

double CEnterpriseStrategyManager::CalculateSharpeRatio(const int index)
{
    if(index < 0 || index >= m_strategyCount) return 0.0;
    if(m_strategies[index].recentTradeCount < 5) return 0.0;
    
    double sum = 0;
    for(int i = 0; i < m_strategies[index].recentTradeCount; i++)
        sum += m_strategies[index].recentTrades[i];
    
    double mean = sum / m_strategies[index].recentTradeCount;
    
    double sq_sum = 0;
    for(int i = 0; i < m_strategies[index].recentTradeCount; i++)
        sq_sum += MathPow(m_strategies[index].recentTrades[i] - mean, 2);
    
    double stdev = MathSqrt(sq_sum / m_strategies[index].recentTradeCount);
    if(stdev == 0) return 0;
    
    return mean / stdev;
}

void CEnterpriseStrategyManager::CalculateStrategyMetrics(const int index)
{
    if(index < 0 || index >= m_strategyCount) return;
    
    // Calculate win rate
    if(m_strategies[index].totalTrades > 0)
        m_strategies[index].winRate = ((double)m_strategies[index].winningTrades / m_strategies[index].totalTrades);
    
    // Calculate profit factor
    if(m_strategies[index].avgLoss > 0.0)
        m_strategies[index].profitFactor = m_strategies[index].avgProfit / m_strategies[index].avgLoss;
    else if(m_strategies[index].avgProfit > 0.0)
        m_strategies[index].profitFactor = 2.0;
    else
        m_strategies[index].profitFactor = 0.0;
    
    m_strategies[index].sharpeRatio = CalculateSharpeRatio(index);
    m_strategies[index].recentWinRate = CalculateRecentWinRate(index);
}

bool CEnterpriseStrategyManager::ShouldDisableStrategy(const int index)
{
    if(index < 0 || index >= m_strategyCount) return false;
    
    // Only check if we have enough trades
    if(m_strategies[index].totalTrades < 10) return false;
    
    // Disable if win rate is too low
    if(m_strategies[index].recentWinRate < m_minWinRateThreshold) return true;
    
    // Disable if consecutive losses are too high
    if(m_strategies[index].consecutiveLosses >= m_maxConsecutiveLosses_Limit) return true;
    
    return false;
}

bool CEnterpriseStrategyManager::ShouldReEnableStrategy(const int index)
{
    if(index < 0 || index >= m_strategyCount) return false;
    if(!m_strategies[index].temporarilyDisabled) return true;
    
    return (TimeCurrent() >= m_strategies[index].disabledUntil);
}

//+------------------------------------------------------------------+
//| OnNewBar - CRITICAL for zone scanning and chart drawings         |
//| Must be called from main EA on each new bar                      |
//+------------------------------------------------------------------+
void CEnterpriseStrategyManager::OnNewBar(const string symbol, ENUM_TIMEFRAMES timeframe)
{
    if(!m_initialized || m_strategyCount == 0)
        return;

    if(m_drawingManager != NULL)
        m_drawingManager.CleanupOldObjects();

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
            m_strategies[i].strategy.OnNewBar(symbol, m_strategies[i].timeframe);
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
            if(m_managedMagic > 0 && !IsEAOwnedMagic(dealMagic))
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
                    for(int contributorIdx = 0; contributorIdx < ArraySize(contributors); contributorIdx++)
                    {
                        if(contributors[contributorIdx] == "")
                            continue;
                        UpdatePerformance(contributors[contributorIdx], netProfit);
                    }
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

//+------------------------------------------------------------------+
//| Apply Quorum Profile                                             |
//+------------------------------------------------------------------+
void CEnterpriseStrategyManager::ApplyQuorumProfile(ENUM_QUORUM_PROFILE profile)
{
    string profileName;
    
    switch(profile)
    {
        case QUORUM_CONSERVATIVE:
            // Conservative: High thresholds, more voters required
            m_minQuorum = 3;
            m_intrabarMinQuorum = 2;
            m_quorumThreshold = 0.70;
            m_pipelineMinConfidence = 0.50;
            m_intrabarSingleVoterMinConfidence = 0.80;
            m_minReadyWeightRatio = 0.60;
            m_supportFloorNewBar = 0.40;
            m_supportFloorIntrabar = 0.35;
            m_sparseIntrabarMinQuality = 0.85;
            m_sparseIntrabarMinSupportRatio = 0.80;
            m_sparseIntrabarMinReadyCoverage = 0.70;
            m_allowSparseIntrabarSingleVoter = false;
            
            // Adaptive quorum settings
            m_adaptiveQualityThreshold_1voter = 0.90;
            m_adaptiveSupportFloor_1voter = 0.80;
            m_adaptiveQualityThreshold_2voters = 0.80;
            m_adaptiveSupportFloor_2voters = 0.70;
            m_adaptiveQualityThreshold_3plus = 0.70;
            m_adaptiveSupportFloor_3plus = 0.60;
            profileName = "CONSERVATIVE";
            break;
            
        case QUORUM_BALANCED:
            // Balanced: Moderate thresholds
            m_minQuorum = 2;
            m_intrabarMinQuorum = 1;
            m_quorumThreshold = 0.55;
            m_pipelineMinConfidence = 0.40;
            m_intrabarSingleVoterMinConfidence = 0.65;
            m_minReadyWeightRatio = 0.40;
            m_supportFloorNewBar = 0.30;
            m_supportFloorIntrabar = 0.25;
            m_sparseIntrabarMinQuality = 0.65;
            m_sparseIntrabarMinSupportRatio = 0.55;
            m_sparseIntrabarMinReadyCoverage = 0.50;
            m_allowSparseIntrabarSingleVoter = true;
            
            // Adaptive quorum settings
            m_adaptiveQualityThreshold_1voter = 0.75;
            m_adaptiveSupportFloor_1voter = 0.60;
            m_adaptiveQualityThreshold_2voters = 0.65;
            m_adaptiveSupportFloor_2voters = 0.50;
            m_adaptiveQualityThreshold_3plus = 0.55;
            m_adaptiveSupportFloor_3plus = 0.40;
            profileName = "BALANCED";
            break;
            
        case QUORUM_AGGRESSIVE:
            // Aggressive: Lower thresholds, more signals passed
            m_minQuorum = 1;
            m_intrabarMinQuorum = 1;
            m_quorumThreshold = 0.40;
            m_pipelineMinConfidence = 0.30;
            m_intrabarSingleVoterMinConfidence = 0.50;
            m_minReadyWeightRatio = 0.25;
            m_supportFloorNewBar = 0.20;
            m_supportFloorIntrabar = 0.15;
            m_sparseIntrabarMinQuality = 0.50;
            m_sparseIntrabarMinSupportRatio = 0.40;
            m_sparseIntrabarMinReadyCoverage = 0.35;
            m_allowSparseIntrabarSingleVoter = true;
            
            // Adaptive quorum settings
            m_adaptiveQualityThreshold_1voter = 0.60;
            m_adaptiveSupportFloor_1voter = 0.40;
            m_adaptiveQualityThreshold_2voters = 0.50;
            m_adaptiveSupportFloor_2voters = 0.35;
            m_adaptiveQualityThreshold_3plus = 0.40;
            m_adaptiveSupportFloor_3plus = 0.30;
            profileName = "AGGRESSIVE";
            break;
    }
    
    PrintFormat("[QUORUM-PROFILE] Applied %s profile | minQuorum=%d | quorumThreshold=%.2f | pipelineMinConfidence=%.2f",
                profileName, m_minQuorum, m_quorumThreshold, m_pipelineMinConfidence);
}

#endif // ENTERPRISE_STRATEGY_MANAGER_MQH
