//+------------------------------------------------------------------+
//| Enterprise Strategy Manager - Production Grade                   |
//| Central manager for all strategies with unified pipeline        |
//+------------------------------------------------------------------+
#ifndef ENTERPRISE_STRATEGY_MANAGER_MQH
#define ENTERPRISE_STRATEGY_MANAGER_MQH

#include "../Pipeline/UnifiedSignalPipeline.mqh"
#include "../Signals/TimeframeConsistency.mqh"
#include "../Processing/DerivAssetProfiler.mqh"
#include "../Processing/MultiAssetProfiler.mqh"
#include "../Risk/VPINFilter.mqh"
#include "../Engines/OrderFlowImbalanceEngine.mqh"
#include "../Engines/FamilyStrategyWeightMatrix.mqh"
#include "../Engines/FourStateRegimeDetector.mqh"
#include "../Utils/Enums.mqh"
#include "../Utils/RankingMatrix.mqh"
#include "../../Interfaces/IStrategy.mqh"
#include "../../Interfaces/IAIStrategy.mqh"
#include "DiagnosticsManager.mqh"
#include "StrategyHealthMonitor.mqh"
#include "../../Core/Trading/TradeAttributionManager.mqh"
#include "../../Core/AI/AIPerformanceFeedback.mqh"
#include "../../Core/Utils/JsonLogger.mqh"

// Retained production strategy inventory (7 kept in codebase)
#include "../../Strategies/SimpleMomentumStrategy.mqh"
#include "../../Strategies/StrategyTrend.mqh"
#include "../../Strategies/StrategySupportResistance.mqh"
#include "../../Strategies/StrategyCandlestick.mqh"
#include "../../Strategies/MeanReversionStrategy.mqh"
#include "../../Strategies/VolatilityBreakoutStrategy.mqh"
#include "../../Strategies/StatisticalArbitrageStrategy.mqh"

// Batch 103: New ICT/SMC strategies
#include "../../Strategies/FVGScalperStrategy.mqh"
#include "../../Strategies/TurtleSoupStrategy.mqh"
#include "../../Strategies/BreakerBlockStrategy.mqh"
#include "../../Strategies/NYOpenGapStrategy.mqh"
#include "../../Strategies/AsianRangeBreakStrategy.mqh"

// Forward declarations
class CEnhancedErrorHandler;
class CUtilities;
class CMarketAnalysis;
class CNextGenStrategyBrain;
class CTransformerBrain;
struct SPredictionWithUncertainty;
class CPositionSizer;
class CTradeManager;
class CPerformanceAnalytics;
class CPythonBridge;
class CFourStateRegimeDetector;  // Forward declaration for market regime detection

// Include StrategyRegistry for full class definition (needed for extern instance declaration)
#include "../Strategy/StrategyRegistry.mqh"

// Forward declaration (fallback if include guard prevents inclusion)
class CStrategyRegistry;

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

    // Consensus component scores (populated by pipeline/consensus engine)
    double participation;        // Participation multiplier [0-1]
    double readinessScore;       // Readiness score [0-1]
    double contextScore;         // Context score [0-1]
    double costScore;            // Cost score [0-1]
    bool isProbeEligible;        // Eligible for intrabar probe voting

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

// Clamp value to [0.0, 1.0] range
inline double ClampUnitValue(const double value)
{
    return MathMax(0.0, MathMin(1.0, value));
}

// Phase C / Slice 1 extracted collaborators. Included here (after the shared
// free helpers above, before the manager class) so that:
//   - CStrategyStateReporter / CAttributionDelegator are complete types and can
//     be held BY VALUE as members of CEnterpriseStrategyManager;
//   - the reporter's out-of-line bodies may reference the still-incomplete
//     CEnterpriseStrategyManager (resolved later in this same translation unit).
#include "StrategyStateReporter.mqh"
#include "AttributionDelegator.mqh"
// Phase C / Slice 2 extracted collaborators (same rationale as Slice 1).
#include "PostConsensusValidator.mqh"
#include "ConsensusWeightingConfig.mqh"
// Phase C / Slice 3 extracted collaborators (same rationale as Slice 1).
#include "StrategyPerformanceHealth.mqh"
#include "StrategyLifecycle.mqh"
// Phase C / Slice 4 extracted collaborators (same rationale as Slice 1).
#include "IntrabarPolicy.mqh"
#include "StrategyRegistryState.mqh"
// Phase C / Slice 5 extracted collaborator (same rationale as Slice 1):
// C9, the consensus decision core, moved wholesale into CConsensusEngine.
#include "ConsensusEngine.mqh"

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
    CDerivAssetProfiler* m_derivProfiler;      // Deriv family profiler for engine weighting
    CMultiAssetProfiler* m_multiAssetProfiler;  // Multi-asset profiler (Batch 103)
    CChartDrawingManager* m_drawingManager; // Central drawing manager for the symbol
    CVPINFilter* m_vpinFilter;        // VPIN toxicity filter for consensus (Batch 104)
    COrderFlowImbalanceEngine* m_ofiEngine;  // OFI for regime integration (Batch 104)
    CFamilyStrategyWeightMatrix* m_familyWeightMatrix;  // I1: Per-family cluster weight multipliers
    CFourStateRegimeDetector* m_fourStateRegimeDetector; // Four-state regime detector
    CStrategyRegistry* m_strategyRegistry;                // L1-004: Injected registry (no global singleton)
    ENUM_MARKET_REGIME m_currentMarketRegime;
    bool m_regimeDetectorInitialized;
    
    // L1-007: Component delegation
    CDiagnosticsManager* m_diagnostics;
    CTradeAttributionManager* m_attribution;
    CStrategyHealthMonitor* m_healthMonitor;

    // Phase C / Slice 1: extracted collaborators (owned by value, no lifetime management)
    CStrategyStateReporter m_stateReporter;      // C1: read-only telemetry / JSON reporting
    CAttributionDelegator  m_attributionDelegator; // C2: attribution forwarders

    // Phase C / Slice 2: extracted collaborators (owned by value, no lifetime management)
    CPostConsensusValidator  m_postConsensusValidator; // C3: post-consensus validation + its config
    CConsensusWeightingConfig m_weightingConfig;       // C4: weighting / quorum profiles

    // Phase C / Slice 3: extracted collaborators (owned by value, no lifetime management)
    CStrategyPerformanceHealth m_performanceHealth;    // C5: performance accounting / health scoring
    CStrategyLifecycle         m_lifecycle;            // C7: enable/disable lifecycle, per-bar transitions

    // Phase C / Slice 4: extracted collaborators (owned by value, no lifetime management)
    CIntrabarPolicy        m_intrabarPolicy; // C6: intrabar policy table + eligibility gating
    CStrategyRegistryState m_registryState;  // C8: registry bookkeeping + enable-state queries

    // Phase C / Slice 5: extracted collaborator (owned by value, no lifetime management)
    CConsensusEngine       m_consensusEngine; // C9: consensus decision core (owns m_lastDecisionContext)
    
    StrategyEntry m_strategies[];
    int m_strategyCount;
    int m_maxStrategies; // Max strategy limit
    
    string m_symbol;
    ENUM_TIMEFRAMES m_baseTimeframe;
    long m_managedMagic;
    long m_managedMagicRangeMax;
    
    bool m_initialized;
    bool m_usePipeline;
    int  m_adxHandleCached;    // Cached ADX handle for IsTrendingRegime() (Batch 116)
    
    // Statistics
    int m_totalSignals;
    int m_successfulSignals;
    double m_avgConfidence;

    // L1-007: Health monitor configuration (mirrored for fallback when m_healthMonitor == NULL)
    double m_minWinRateThreshold;
    int m_maxConsecutiveLosses_Limit;
    int m_rollingWindowSize;

    // Consensus configuration (mirrored for internal consensus logic)
    int m_minQuorum;
    int m_intrabarMinQuorum;
    bool m_intrabarDynamicQuorumEnabled;
    double m_intrabarSingleVoterMinConfidence;
    double m_quorumThreshold;
    double m_pipelineMinConfidence;
    double m_conflictDeadband;
    double m_minReadyWeightRatio;
    double m_supportFloorNewBar;
    double m_supportFloorIntrabar;
    double m_sparseIntrabarMinQuality;
    double m_sparseIntrabarMinSupportRatio;
    double m_sparseIntrabarMinReadyCoverage;
    double m_sparseIntrabarConfidencePenalty;
    bool m_allowSparseIntrabarSingleVoter;
    bool m_adaptiveQuorumEnabled;
    double m_adaptiveQualityThreshold_1voter;
    double m_adaptiveSupportFloor_1voter;
    double m_adaptiveQualityThreshold_2voters;
    double m_adaptiveSupportFloor_2voters;
    double m_adaptiveQualityThreshold_3plus;
    double m_adaptiveSupportFloor_3plus;
    double m_strategyActivityDecayRate;
    int m_strategyInactiveCounterThreshold;
    bool m_regimeRelaxActive;
    double m_regimeRelaxFactor;
    double m_performanceDecayFactor;
    double m_maxDrawdownLimit;

    // Post-consensus validation configuration: Phase C / Slice 2 (C3) moved this
    // block into CPostConsensusValidator, which now owns it. No reader remained
    // outside the validator methods.

    // Participation score multiplier formula parameters (L6-008)
    double m_participationFormulaBase;
    double m_participationFormulaCoeff;
    double m_participationFormulaMin;
    double m_participationFormulaMax;

    // Intrabar policy configuration per strategy index (L6-007)
    ENUM_INTRABAR_POLICY m_intrabarPolicyConfig[32];

    // Last orchestrated decision context for basic trade attribution
        string m_lastSignalContributors[];
        int m_lastSignalContributorIndices[];
        int m_lastContributorCount;
        string m_lastSignalSymbol;
        datetime m_lastSignalTime;
        string m_lastSignalRole;
        string m_lastSignalCluster;
        string m_lastSignalClusterCode;
        // Phase C / Slice 5 (C9): m_lastDecisionContext moved into CConsensusEngine,
        // which is its single writer. GetLastDecisionContextValue() now forwards there.

    // Last-cycle funnel snapshot (for EA-level heartbeat conversion metrics)
    int m_lastCycleSignalsGenerated;
    int m_lastCycleSignalsAfterPipeline;
    bool m_lastCycleSignalAfterQuorum;

    bool IsPositionIdStillOpen(const ulong positionId) const;
    int FindStrategyIndexByName(const string name) const;
    int FindAttributionIndexByPositionId(const ulong positionId) const;
    string JoinContributors(const string &contributors[]) const;
    void SplitContributors(const string csv, string &contributors[]) const;
    void UpsertPositionAttribution(const ulong positionId, const string &contributors[]);
    bool PopPositionAttribution(const ulong positionId, string &contributors[]);
    //--- Phase C / Slice 5 (C9): retained as a one-line forwarder because the
    //--- public read-only accessor GetStrategyIsLiveVoter() (consumed by
    //--- CStrategyStateReporter) is defined in terms of it. The implementation
    //--- lives in CConsensusEngine.
    bool IsStrategyLiveVoter(const int strategyIndex) const;

    // Fallback solo signal when all strategies abstain.
    // Phase C / Slice 5 (C9): forwarder; implementation in CConsensusEngine.
    ENUM_TRADE_SIGNAL TryFallbackSoloSignal(const string symbol, ENUM_SIGNAL_EVAL_MODE evalMode, double &outConfidence, int &outConfluence, string &outReason);

    // Consensus decision class to string conversion. Already a shim over
    // CStrategyStateReporter (Phase C / Slice 1); left in place.
    static string ConsensusDecisionClassToString(ENUM_CONSENSUS_DECISION_CLASS decisionClass);

    //--- Phase C / Slice 5 (C9): the consensus evaluation core
    //--- (EvaluateConsensusInternal, EvaluateConsensusTwoTierInternal,
    //--- EvaluateConsensusProbeOnlyInternal, TryFallbackSoloSignalInternal,
    //--- CalculateEffectiveQuorumParamsInternal) and its vote/weighting helpers
    //--- (GetStrategyReliabilityMultiplier, GetStrategyParticipationMultiplier,
    //--- GetStrategyRoleVoteMultiplier, GetRegimeCategoryMultiplier,
    //--- CalculateDirectionDiversityScore, CalculateAverageStrategyMetric,
    //--- ClampUnitValue, GetStrategyIntrabarPolicy,
    //--- IsStrategyIntrabarLiveEligible, IsStrategyIntrabarProbeEligible,
    //--- IsTrendingRegime, ResolveDominantRole, ResolveDominantCluster,
    //--- JoinContributorsWithContext, AccumulateRoleClusterSignalDiagnostics,
    //--- MaybeLogConsensusDiagnostics) moved wholesale into CConsensusEngine.
    //--- None of them had a caller outside the consensus core, so no forwarder
    //--- is retained for them.

    //--- Post-consensus validation: Phase C / Slice 2 (C3).
    //--- Implementation lives in CPostConsensusValidator; the manager keeps only
    //--- forwarders for the externally-consumed entry points. The result type is
    //--- now the top-level struct SPostConsensusValidation (was the nested
    //--- SValidationResult, which shadowed the unrelated global SValidationResult
    //--- declared in Core/Utils/Enums.mqh).
    //--- The internal leaf checks (CheckHardSpreadCutoff, CheckExogenousFilters,
    //--- CheckOFIConfirmation, CheckVPINFilter, GetATRDirect,
    //--- GetATRCrisisThreshold, IsSyntheticSymbolForValidation,
    //--- GetAdaptiveQualityThreshold) had zero callers outside ValidateSignal and
    //--- moved wholesale - no forwarder is retained for them.
public:
    SPostConsensusValidation ValidateSignal(const string symbol, ENUM_TRADE_SIGNAL signal, double confidence,
                                            int confluence, ENUM_SIGNAL_EVAL_MODE evalMode,
                                            const SConsensusDecisionContext& ctx,
                                            ulong scanCycleId, const string corrId = "");
    string GetValidationStatusReport() const;

    // Validator configuration setters
    void SetValidatorConfig(double intrabarMinQuality, double newBarMinQuality, double hardSpreadCutoff,
                           bool spikeHunterEnabled, bool enableOFI, bool enableVPIN,
                           double baseSpreadATRRatio, double syntheticSpreadATRRatio);

public:
    CEnterpriseStrategyManager();
    ~CEnterpriseStrategyManager();
    
    // L1-007: Component accessors
    CDiagnosticsManager* GetDiagnostics() { return m_diagnostics; }
    void SetDiagnosticsManager(CDiagnosticsManager* diagnostics) { m_diagnostics = diagnostics; }
    CTradeAttributionManager* GetAttribution() { return m_attribution; }
    void SetAttributionManager(CTradeAttributionManager* attribution)
         { m_attribution = attribution; m_attributionDelegator.SetAttribution(m_attribution); }
    CStrategyHealthMonitor* GetHealthMonitor() { return m_healthMonitor; }

    //--- Phase C / Slice 1: minimal read-only accessor surface consumed by
    //--- CStrategyStateReporter. These expose existing state verbatim; they add
    //--- no logic and are the only way the reporter observes this manager.
    int    GetStrategyCount() const { return m_strategyCount; }
    bool   IsStrategyEnabled(const int index) const
           { return (index >= 0 && index < m_strategyCount) ? m_strategies[index].enabled : false; }
    IStrategy* GetStrategyPtr(const int index) const
           { return (index >= 0 && index < m_strategyCount) ? m_strategies[index].strategy : NULL; }
    string GetStrategyName(const int index) const
           { return (index >= 0 && index < m_strategyCount) ? m_strategies[index].name : ""; }
    double GetStrategyWeight(const int index) const
           { return (index >= 0 && index < m_strategyCount) ? m_strategies[index].weight : 0.0; }
    int    GetStrategyRole(const int index) const
           { return (index >= 0 && index < m_strategyCount) ? m_strategies[index].role : 0; }
    int    GetStrategyCluster(const int index) const
           { return (index >= 0 && index < m_strategyCount) ? m_strategies[index].cluster : 0; }
    bool   IsStrategyLiveVotingEnabled(const int index) const
           { return (index >= 0 && index < m_strategyCount) ? m_strategies[index].liveVotingEnabled : false; }
    int    GetStrategySuccessCount(const int index) const
           { return (index >= 0 && index < m_strategyCount) ? m_strategies[index].successCount : 0; }
    int    GetStrategyFailCount(const int index) const
           { return (index >= 0 && index < m_strategyCount) ? m_strategies[index].failCount : 0; }
    double GetStrategyAvgConfidence(const int index) const
           { return (index >= 0 && index < m_strategyCount) ? m_strategies[index].avgConfidence : 0.0; }
    double GetStrategyParticipationScore(const int index) const
           { return (index >= 0 && index < m_strategyCount) ? m_strategies[index].participationScore : 0.0; }
    double GetStrategyHealthScore(const int index) const
           { return (index >= 0 && index < m_strategyCount) ? m_strategies[index].healthScore : 0.0; }
    double GetStrategyRecentWinRate(const int index) const
           { return (index >= 0 && index < m_strategyCount) ? m_strategies[index].recentWinRate : 0.0; }
    bool   GetStrategyIsLiveVoter(const int index) const { return IsStrategyLiveVoter(index); }
    CUnifiedSignalPipeline* GetPipelineConst() const { return m_pipeline; }
    CDiagnosticsManager*    GetDiagnosticsConst() const { return m_diagnostics; }
    string GetManagedSymbol() const { return m_symbol; }
    int    GetTotalSignals() const { return m_totalSignals; }
    int    GetSuccessfulSignals() const { return m_successfulSignals; }
    void   GetLastDecisionContextValue(SConsensusDecisionContext &out) const
           { m_consensusEngine.GetLastDecisionContextValue(out); }
    int    GetLastCycleSignalsGeneratedValue() const { return m_lastCycleSignalsGenerated; }
    int    GetLastCycleSignalsAfterPipelineValue() const { return m_lastCycleSignalsAfterPipeline; }
    bool   GetLastCycleSignalAfterQuorumValue() const { return m_lastCycleSignalAfterQuorum; }

    //--- Phase C / Slice 2: additional read-only accessors consumed by
    //--- CPostConsensusValidator (C3) and CConsensusWeightingConfig (C4).
    //--- Same contract as the Slice 1 block: expose existing state verbatim,
    //--- add no logic.
    COrderFlowImbalanceEngine*   GetOFIEngineConst() const          { return m_ofiEngine; }
    CVPINFilter*                 GetVPINFilterConst() const         { return m_vpinFilter; }
    CMultiAssetProfiler*         GetMultiAssetProfilerConst() const { return m_multiAssetProfiler; }
    CDerivAssetProfiler*         GetDerivProfilerConst() const      { return m_derivProfiler; }
    CFamilyStrategyWeightMatrix* GetFamilyWeightMatrixConst() const { return m_familyWeightMatrix; }
    double GetStrategyAvgProfit(const int index) const
           { return (index >= 0 && index < m_strategyCount) ? m_strategies[index].avgProfit : 0.0; }
    double GetStrategyOriginalWeight(const int index) const
           { return (index >= 0 && index < m_strategyCount) ? m_strategies[index].originalWeight : 0.0; }
    int    GetStrategyIndexByName(const string name) const { return FindStrategyIndexByName(name); }

    //--- Narrow raw weight mutator for C4. Mirrors exactly what
    //--- UpdateStrategyWeights() used to do inline: write the entry weight and
    //--- push it to the strategy object, WITHOUT touching the health monitor
    //--- (that is UpdateStrategyWeightByName's behaviour, deliberately distinct).
    void   ApplyRawStrategyWeight(const int index, const double weight)
    {
        if(index < 0 || index >= m_strategyCount)
            return;
        m_strategies[index].weight = weight;
        if(m_strategies[index].strategy != NULL)
            m_strategies[index].strategy.SetWeight(weight);
    }

    //--- Phase C / Slice 3: accessor surface consumed by
    //--- CStrategyPerformanceHealth (C5) and CStrategyLifecycle (C7).
    //--- Same contract as Slice 1/2: each accessor exposes exactly one
    //--- existing field verbatim and adds no logic. The mutators are the
    //--- narrow write half required because both collaborators (like C4)
    //--- change manager state; they are deliberately dumb field writers so
    //--- the resulting state transitions stay byte-for-byte identical to the
    //--- original inline bodies.

    //--- read half
    int      GetStrategyTotalTrades(const int index) const
             { return (index >= 0 && index < m_strategyCount) ? m_strategies[index].totalTrades : 0; }
    int      GetStrategyWinningTrades(const int index) const
             { return (index >= 0 && index < m_strategyCount) ? m_strategies[index].winningTrades : 0; }
    double   GetStrategyWinRate(const int index) const
             { return (index >= 0 && index < m_strategyCount) ? m_strategies[index].winRate : 0.0; }
    double   GetStrategyAvgLoss(const int index) const
             { return (index >= 0 && index < m_strategyCount) ? m_strategies[index].avgLoss : 0.0; }
    int      GetStrategyConsecutiveWins(const int index) const
             { return (index >= 0 && index < m_strategyCount) ? m_strategies[index].consecutiveWins : 0; }
    int      GetStrategyConsecutiveLosses(const int index) const
             { return (index >= 0 && index < m_strategyCount) ? m_strategies[index].consecutiveLosses : 0; }
    int      GetStrategyMaxConsecutiveLosses(const int index) const
             { return (index >= 0 && index < m_strategyCount) ? m_strategies[index].maxConsecutiveLosses : 0; }
    int      GetStrategyRecentTradeIndex(const int index) const
             { return (index >= 0 && index < m_strategyCount) ? m_strategies[index].recentTradeIndex : 0; }
    int      GetStrategyRecentTradeCount(const int index) const
             { return (index >= 0 && index < m_strategyCount) ? m_strategies[index].recentTradeCount : 0; }
    double   GetStrategyRecentTrade(const int index, const int slot) const
             { return (index >= 0 && index < m_strategyCount && slot >= 0 && slot < 20)
                      ? m_strategies[index].recentTrades[slot] : 0.0; }
    bool     IsStrategyTemporarilyDisabled(const int index) const
             { return (index >= 0 && index < m_strategyCount) ? m_strategies[index].temporarilyDisabled : false; }
    datetime GetStrategyDisabledUntil(const int index) const
             { return (index >= 0 && index < m_strategyCount) ? m_strategies[index].disabledUntil : 0; }
    ENUM_TIMEFRAMES GetStrategyTimeframe(const int index) const
             { return (index >= 0 && index < m_strategyCount) ? m_strategies[index].timeframe : m_baseTimeframe; }
    double   GetMinWinRateThreshold() const      { return m_minWinRateThreshold; }
    int      GetMaxConsecutiveLossesLimit() const { return m_maxConsecutiveLosses_Limit; }
    int      GetRollingWindowSize() const        { return m_rollingWindowSize; }
    bool     IsManagerInitialized() const        { return m_initialized; }
    CFourStateRegimeDetector* GetFourStateRegimeDetectorConst() const { return m_fourStateRegimeDetector; }
    bool     IsRegimeDetectorInitialized() const { return m_regimeDetectorInitialized; }

    //--- write half (dumb field writers, all bounds-checked)
    void SetStrategyTotalTrades(const int index, const int value)
         { if(index >= 0 && index < m_strategyCount) m_strategies[index].totalTrades = value; }
    void SetStrategySuccessCount(const int index, const int value)
         { if(index >= 0 && index < m_strategyCount) m_strategies[index].successCount = value; }
    void SetStrategyFailCount(const int index, const int value)
         { if(index >= 0 && index < m_strategyCount) m_strategies[index].failCount = value; }
    void SetStrategyWinningTrades(const int index, const int value)
         { if(index >= 0 && index < m_strategyCount) m_strategies[index].winningTrades = value; }
    void SetStrategyConsecutiveWins(const int index, const int value)
         { if(index >= 0 && index < m_strategyCount) m_strategies[index].consecutiveWins = value; }
    void SetStrategyConsecutiveLosses(const int index, const int value)
         { if(index >= 0 && index < m_strategyCount) m_strategies[index].consecutiveLosses = value; }
    void SetStrategyMaxConsecutiveLosses(const int index, const int value)
         { if(index >= 0 && index < m_strategyCount) m_strategies[index].maxConsecutiveLosses = value; }
    void SetStrategyAvgProfit(const int index, const double value)
         { if(index >= 0 && index < m_strategyCount) m_strategies[index].avgProfit = value; }
    void SetStrategyAvgLoss(const int index, const double value)
         { if(index >= 0 && index < m_strategyCount) m_strategies[index].avgLoss = value; }
    void SetStrategyWinRate(const int index, const double value)
         { if(index >= 0 && index < m_strategyCount) m_strategies[index].winRate = value; }
    void SetStrategyProfitFactor(const int index, const double value)
         { if(index >= 0 && index < m_strategyCount) m_strategies[index].profitFactor = value; }
    void SetStrategySharpeRatio(const int index, const double value)
         { if(index >= 0 && index < m_strategyCount) m_strategies[index].sharpeRatio = value; }
    void SetStrategyRecentWinRate(const int index, const double value)
         { if(index >= 0 && index < m_strategyCount) m_strategies[index].recentWinRate = value; }
    void SetStrategyHealthScore(const int index, const double value)
         { if(index >= 0 && index < m_strategyCount) m_strategies[index].healthScore = value; }
    void SetStrategyLastUpdate(const int index, const datetime value)
         { if(index >= 0 && index < m_strategyCount) m_strategies[index].lastUpdate = value; }
    void SetStrategyTemporarilyDisabled(const int index, const bool value)
         { if(index >= 0 && index < m_strategyCount) m_strategies[index].temporarilyDisabled = value; }
    void SetStrategyDisabledUntil(const int index, const datetime value)
         { if(index >= 0 && index < m_strategyCount) m_strategies[index].disabledUntil = value; }
    //--- Writes ONLY the entry flag. It deliberately does NOT push the value to
    //--- the IStrategy object: CheckStrategyDisabling/ReEnabling never did, and
    //--- EnableStrategy/DisableStrategy push it themselves via GetStrategyPtr().
    void SetStrategyEnabledFlag(const int index, const bool value)
         { if(index >= 0 && index < m_strategyCount) m_strategies[index].enabled = value; }
    //--- slot bound is the fixed recentTrades[20] capacity; unreachable in
    //--- practice because m_rollingWindowSize is fixed at 20 (no setter).
    void SetStrategyRecentTrade(const int index, const int slot, const double value)
         { if(index >= 0 && index < m_strategyCount && slot >= 0 && slot < 20)
               m_strategies[index].recentTrades[slot] = value; }
    void SetStrategyRecentTradeIndex(const int index, const int value)
         { if(index >= 0 && index < m_strategyCount) m_strategies[index].recentTradeIndex = value; }
    void SetStrategyRecentTradeCount(const int index, const int value)
         { if(index >= 0 && index < m_strategyCount) m_strategies[index].recentTradeCount = value; }
    void SetStrategyLastSignal(const int index, const ENUM_TRADE_SIGNAL value)
         { if(index >= 0 && index < m_strategyCount) m_strategies[index].lastSignal = value; }
    void SetStrategyLastSignalConfidence(const int index, const double value)
         { if(index >= 0 && index < m_strategyCount) m_strategies[index].lastSignalConfidence = value; }

    //--- Phase C / Slice 5: accessor surface consumed by CConsensusEngine (C9).
    //--- Same contract as Slice 1/2/3: every accessor exposes exactly one
    //--- existing field verbatim and adds no logic. The consensus core READS
    //--- the enable / live-voting / intrabar-policy flags through here; it does
    //--- NOT own them (they are written by registration, lifecycle and the
    //--- governance setters, all of which stay in this manager). The single
    //--- mutator, SetAdxHandleCached, exists only because IsTrendingRegime()
    //--- lazily caches the ADX handle exactly as the original inline body did.
    CTimeframeConsistency* GetTFConsistencyConst() const   { return m_tfConsistency; }
    CStrategyRegistry*     GetStrategyRegistryConst() const { return m_strategyRegistry; }
    ENUM_TIMEFRAMES        GetBaseTimeframe() const         { return m_baseTimeframe; }

    int    GetStrategyIntrabarPolicyRaw(const int index) const
           { return (index >= 0 && index < m_strategyCount) ? m_strategies[index].intrabarPolicy : (int)INTRABAR_POLICY_OFF; }
    bool   GetStrategyIntrabarEligible(const int index) const
           { return (index >= 0 && index < m_strategyCount) ? m_strategies[index].intrabarEligible : false; }
    bool   IsStrategyProbeEligible(const int index) const
           { return (index >= 0 && index < m_strategyCount) ? m_strategies[index].isProbeEligible : false; }
    double GetStrategyReadinessScore(const int index) const
           { return (index >= 0 && index < m_strategyCount) ? m_strategies[index].readinessScore : 0.0; }
    double GetStrategyContextScore(const int index) const
           { return (index >= 0 && index < m_strategyCount) ? m_strategies[index].contextScore : 0.0; }
    double GetStrategyCostScore(const int index) const
           { return (index >= 0 && index < m_strategyCount) ? m_strategies[index].costScore : 0.0; }

    //--- consensus configuration (GetMinQuorum() already exists above)
    int    GetIntrabarMinQuorum() const              { return m_intrabarMinQuorum; }
    bool   IsIntrabarDynamicQuorumEnabled() const    { return m_intrabarDynamicQuorumEnabled; }
    double GetQuorumThreshold() const                { return m_quorumThreshold; }
    double GetPipelineMinConfidence() const          { return m_pipelineMinConfidence; }
    double GetConflictDeadband() const               { return m_conflictDeadband; }
    double GetMinReadyWeightRatio() const            { return m_minReadyWeightRatio; }
    double GetSupportFloorNewBar() const             { return m_supportFloorNewBar; }
    double GetSupportFloorIntrabar() const           { return m_supportFloorIntrabar; }
    double GetSparseIntrabarMinQuality() const       { return m_sparseIntrabarMinQuality; }
    double GetSparseIntrabarMinSupportRatio() const  { return m_sparseIntrabarMinSupportRatio; }

    //--- participation score formula parameters (L6-008)
    double GetParticipationFormulaBase() const       { return m_participationFormulaBase; }
    double GetParticipationFormulaCoeff() const      { return m_participationFormulaCoeff; }
    double GetParticipationFormulaMin() const        { return m_participationFormulaMin; }
    double GetParticipationFormulaMax() const        { return m_participationFormulaMax; }

    //--- cached ADX handle (Batch 116) read/write half for IsTrendingRegime()
    int    GetAdxHandleCached() const                { return m_adxHandleCached; }
    void   SetAdxHandleCached(const int handle)      { m_adxHandleCached = handle; }

    // Initialization
    bool Initialize(const string symbol, ENUM_TIMEFRAMES timeframe, 
                   bool usePipeline = true,
                   CTradeManager* tradeManagerPtr = NULL, CPositionSizer* positionSizerPtr = NULL,
                   CUnifiedRiskManager* unifiedRiskManagerPtr = NULL,
                   const long managedMagic = 0);
    
    // L1-004: Set strategy registry (replaces global singleton)
    void SetStrategyRegistry(CStrategyRegistry* registry) { m_strategyRegistry = registry; }
    
    // Strategy management
    bool RegisterStrategy(IStrategy* strategy, const string name, 
                             bool enabled = true, double weight = 1.0,
                             ENUM_STRATEGY_TIER tier = STRATEGY_TIER_3,
                             ENUM_TIMEFRAMES tf = PERIOD_CURRENT,
                             ENUM_INTRABAR_POLICY intrabarPolicy = INTRABAR_POLICY_OFF,
                             ENUM_STRATEGY_ROLE role = PRIMARY_ALPHA,
                             ENUM_STRATEGY_CLUSTER cluster = STRATEGY_CLUSTER_NONE,
                             bool liveVotingEnabled = false);
    bool EnableStrategy(const string name);
    bool DisableStrategy(const string name);
    
    // Signal generation - internal consensus logic
    ENUM_TRADE_SIGNAL GetConsensusSignal(double &confidence);
    ENUM_TRADE_SIGNAL GetConsensusSignalForSymbol(const string symbol, double &confidence);
    ENUM_TRADE_SIGNAL GetConsensusSignalWithConfluence(double &confidence, int &confluence);
    ENUM_TRADE_SIGNAL GetConsensusSignalForSymbolWithConfluence(const string symbol, double &confidence, int &confluence);
    ENUM_TRADE_SIGNAL GetConsensusSignalForSymbolWithConfluenceMode(const string symbol, double &confidence, int &confluence, ENUM_SIGNAL_EVAL_MODE evalMode);

    // Two-tier consensus: Tier 1 quick-probe fast path, Tier 2 full evaluation fallback - internal consensus logic
    ENUM_TRADE_SIGNAL EvaluateConsensusTwoTier(const string symbol, double &confidence, int &confluence, ENUM_SIGNAL_EVAL_MODE evalMode);
    
    // Configuration - internal consensus logic
    void SetPipelineFilters(SignalFilterSettings &settings);
    void SetOrchestratorMode(double minWinRate, int maxLosses);
    void SetMinQuorum(int quorum);
    void SetManagedMagicRangeMax(long rangeMax) { m_managedMagicRangeMax = rangeMax; }
    bool IsEAOwnedMagic(long magic) const;
    void SetQuorumThreshold(const double threshold);
    void SetIntrabarMinQuorum(int quorum);
    void SetIntrabarDynamicQuorumEnabled(const bool enabled);
    void SetIntrabarSingleVoterMinConfidence(const double minConfidence);
    void SetConflictDeadband(const double deadband);
    void SetMinReadyWeightRatio(const double ratio);
    void SetSupportFloors(const double newBarFloor, const double intrabarFloor);
    void SetSparseIntrabarThresholds(const double minQuality,
                                     const double minSupportRatio,
                                     const double minReadyCoverage);
    void SetAllowSparseIntrabarSingleVoter(const bool enabled);
    
    // Intrabar policy configuration per strategy (L6-007)
    void SetStrategyIntrabarPolicyConfig(int strategyIndex, ENUM_INTRABAR_POLICY policy);
    ENUM_INTRABAR_POLICY GetStrategyIntrabarPolicyConfig(int strategyIndex) const;

    //--- Phase C / Slice 4 (C8): narrow per-field accessors consumed by
    //--- CStrategyRegistryState / CIntrabarPolicy back-pointers (m_src).
    //--- Each is a logic-free forwarder over existing members.
    int    GetMaxStrategies() const { return m_maxStrategies; }
    CTradeManager*        GetTradeManagerConst() const { return m_tradeManager; }
    CPositionSizer*       GetPositionSizerConst() const { return m_positionSizer; }
    CUnifiedRiskManager*  GetUnifiedRiskManagerConst() const { return m_unifiedRiskManager; }
    bool   IsPythonBridgeConnected() const { return (g_pythonBridge != NULL && g_pythonBridge.IsConnected()); }

    void SetStrategyRole(int index, int role);
    void SetStrategyCluster(int index, int cluster);
    void SetStrategyLiveVotingEnabled(int index, bool enabled);
    void SetStrategyIntrabarPolicyRaw(int index, int policy);
    void SetStrategyIntrabarEligible(int index, bool eligible);

    // 35-field StrategyEntry append — single writer behind the registry
    // state module's RegisterStrategy(). Mirrors the original RegisterStrategy
    // append block byte-for-byte (no registry/logic changes).
    void AppendRegisteredStrategyEntry(IStrategy* strategy, const string name, bool enabled,
                                       double weight, ENUM_STRATEGY_TIER tier,
                                       ENUM_TIMEFRAMES resolvedTf,
                                       ENUM_INTRABAR_POLICY intrabarPolicy,
                                       ENUM_STRATEGY_ROLE role,
                                       ENUM_STRATEGY_CLUSTER cluster,
                                       bool liveVotingEnabled);

    //--- Phase C / Slice 4 (C8): registration-time helper consumed by
    //--- CStrategyRegistryState::AutoRegisterStrategies(). Was private;
    //--- promoted to public because the slice module calls it via m_src.
    ENUM_INTRABAR_POLICY GetIntrabarPolicyHelper(int idx);
    
    // Participation formula configuration (L6-008)
    void SetParticipationFormulaBase(const double base);
    void SetParticipationFormulaCoeff(const double coeff);
    void SetParticipationFormulaMin(const double minVal);
    void SetParticipationFormulaMax(const double maxVal);
    
    // Quorum preset profiles - internal consensus logic
    enum ENUM_QUORUM_PROFILE
    {
        QUORUM_CONSERVATIVE,
        QUORUM_BALANCED,
        QUORUM_AGGRESSIVE
    };
    void ApplyQuorumProfile(ENUM_QUORUM_PROFILE profile);
    void SetConsensusDiagnosticsIntervalSeconds(const int seconds);
    int  GetMinQuorum() const;
    bool UpdateStrategyWeightByName(const string name, const double weight);
    bool SetStrategyIntrabarEligibilityByName(const string name, bool enabled);
    bool SetStrategyIntrabarPolicyByName(const string name, ENUM_INTRABAR_POLICY policy);
    bool SetStrategyRoleByName(const string name, ENUM_STRATEGY_ROLE role);
    bool SetStrategyClusterByName(const string name, ENUM_STRATEGY_CLUSTER cluster);
    bool SetStrategyLiveVotingEligibilityByName(const string name, const bool enabled);
    bool SetStrategyGovernanceByName(const string name,
                                     ENUM_STRATEGY_ROLE role,
                                     ENUM_STRATEGY_CLUSTER cluster,
                                     const bool liveVotingEnabled);
    bool SetStrategyConfidenceThresholdByName(const string name, const double threshold);
    int GetRegisteredStrategyCount() const;
    IStrategy* GetStrategyByName(const string name);
    string GetRegisteredStrategyName(const int index) const;
    double GetRegisteredStrategyWeight(const int index) const;
    string GetRegisteredStrategyRole(const int index) const;
    string GetRegisteredStrategyCluster(const int index) const;
    bool IsRegisteredStrategyLiveVotingEnabled(const int index) const;
    void GetLastSignalContributors(string &contributors[]) const;
    void GetLastSignalContributorIndices(int &indices[]) const;
    bool GetLastSignalExecutionContext(string &roleTag,
                                       string &clusterTag,
                                       string &clusterCode,
                                       string &contributorsCsv) const;
    CUnifiedSignalPipeline* GetPipeline();
    bool GetLastDecisionContext(SConsensusDecisionContext &context) const;
    void GetRoleClusterDiagnosticsTotals(ulong &primarySignals,
                                         ulong &featureSignals,
                                         ulong &voteSuppressed,
                                         ulong &trendClusterSignals,
                                         ulong &meanReversionClusterSignals,
                                         ulong &structureClusterSignals,
                                         ulong &noneClusterSignals) const;
    void GetLastCycleFunnel(int &signalsGenerated, int &signalsAfterPipeline, bool &signalAfterQuorum) const;
    
    // L1-007: Delegated to CDiagnosticsCollector
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
    
    // Explicit deinitialization
    void Deinit();

    // Manager-owned orchestration/adaptation API (AISO consolidation) - delegated to CStrategyHealthMonitor
    bool UpdateStrategyWeight(const string strategyName, const double newWeight)
    {
        return UpdateStrategyWeightByName(strategyName, newWeight);
    }
    double GetEnsembleConfidence() const;
    ENUM_MARKET_REGIME GetCurrentMarketRegime() const;
    string GetStrategyWeightsJSON() const;
    string GetStrategyListJSON() const;
    string GetConsensusContextJSON() const;
    void UpdateStrategyWeights();
    void CheckStrategyDisabling();
    void CheckStrategyReEnabling();
    
    // Ported adaptation helpers - delegated to CStrategyHealthMonitor
    double CalculateRecentWinRate(const int index);
    double CalculateSharpeRatio(const int index);
    void UpdateRegimePerformance(const int index, int regime, const double result);
    void CalculateStrategyMetrics(const int index);
    bool ShouldDisableStrategy(const int index);
    bool ShouldReEnableStrategy(const int index);
    void UpdateRecentPerformance(const int index, const double result);

    // Visualization
    void SetDrawingManager(CChartDrawingManager* drawingManager);
    CChartDrawingManager* GetDrawingManager();
    
    // New bar processing - CRITICAL for zone scanning and drawing
    void OnNewBar(const string symbol, ENUM_TIMEFRAMES timeframe);
    
    // Trade Feedback - manager-owned trade outcome tracking
    void OnTradeTransaction(const MqlTradeTransaction& trans, const MqlTradeRequest& request, const MqlTradeResult& result);
    
    // Auto-registration
        void AutoRegisterStrategies(bool &enabledFlags[]);
        // Reconcile enabled flags against the finalized registry (see SyncEnabledWithRegistry definition)
        void SyncEnabledWithRegistry();

        // AI Performance Feedback integration (L6-016)
        void UpdateAIPerformanceMetrics(const string strategyName, const SAIModelMetrics &metrics);

        // Deriv family-based engine weighting
    void SetDerivProfiler(CDerivAssetProfiler* profiler);
    void SetFamilyWeightMatrix(CFamilyStrategyWeightMatrix* famMatrix);
    void SetMultiAssetProfiler(CMultiAssetProfiler* profiler);
    void SetVPINFilter(CVPINFilter* vpin);
    void SetOFIEngine(COrderFlowImbalanceEngine* ofi);
    void ApplyFamilyEngineWeights(const string symbol);
    void ApplyAssetClassEngineWeights(const string symbol);
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CEnterpriseStrategyManager::CEnterpriseStrategyManager() :
    m_pipeline(NULL),
    m_tfConsistency(NULL),
    m_tradeManager(NULL),
    m_positionSizer(NULL),
    m_unifiedRiskManager(NULL),
    m_derivProfiler(NULL),
    m_multiAssetProfiler(NULL),
    m_vpinFilter(NULL),
    m_ofiEngine(NULL),
    m_familyWeightMatrix(NULL),
    m_fourStateRegimeDetector(NULL),
    m_strategyRegistry(NULL),                // L1-004: Injected registry
    m_regimeDetectorInitialized(false),
    m_strategyCount(0),
    m_maxStrategies(25),
    m_managedMagic(0),
    m_managedMagicRangeMax(0),
    m_initialized(false),
    m_usePipeline(true),
    m_adxHandleCached(INVALID_HANDLE),  // Batch 116: cached ADX handle
    m_diagnostics(NULL),
    m_attribution(NULL),
    m_healthMonitor(NULL),
    m_drawingManager(NULL),
    m_totalSignals(0),
    m_successfulSignals(0),
    m_avgConfidence(0.0),
    m_minWinRateThreshold(0.40),
    m_maxConsecutiveLosses_Limit(5),
    m_rollingWindowSize(20),
    m_minQuorum(1),
    m_intrabarMinQuorum(1),
    m_intrabarDynamicQuorumEnabled(true),
    m_intrabarSingleVoterMinConfidence(0.75),
    m_quorumThreshold(0.60),
    m_pipelineMinConfidence(0.40),
    m_conflictDeadband(0.35),         // [PROFIT-02] default deadband raised (audit: 0.30-0.35)
    m_minReadyWeightRatio(0.30),
    m_supportFloorNewBar(0.30),        // [PROFIT-11] ratio field, not a count
    m_supportFloorIntrabar(0.25),      // [PROFIT-11] ratio field, not a count
    m_sparseIntrabarMinQuality(0.65),
    m_sparseIntrabarMinSupportRatio(0.30),
    m_sparseIntrabarMinReadyCoverage(0.50),
    m_sparseIntrabarConfidencePenalty(0.10),
    m_allowSparseIntrabarSingleVoter(false),
    m_adaptiveQuorumEnabled(false),
    m_adaptiveQualityThreshold_1voter(0.80),
    m_adaptiveSupportFloor_1voter(1),
    m_adaptiveQualityThreshold_2voters(0.70),
    m_adaptiveSupportFloor_2voters(2),
    m_adaptiveQualityThreshold_3plus(0.60),
    m_adaptiveSupportFloor_3plus(3),
    m_strategyActivityDecayRate(0.95),
    m_strategyInactiveCounterThreshold(10),
    m_regimeRelaxActive(false),
    m_regimeRelaxFactor(0.80),
    m_performanceDecayFactor(0.95),
    m_maxDrawdownLimit(0.20),
    // Phase C / Slice 2: the post-consensus validator config block (including the
    // 15000-pt hard spread cutoff bugfix default) now lives in, and is initialised
    // by, CPostConsensusValidator's own constructor.
    m_participationFormulaBase(0.40),
    m_participationFormulaCoeff(0.65),
    m_participationFormulaMin(0.55),
    m_participationFormulaMax(1.05)
{
    ArrayResize(m_strategies, 0);
    ArrayResize(m_lastSignalContributors, 0);
    ArrayResize(m_lastSignalContributorIndices, 0);
    
    // L6-007: Initialize intrabar policy config with defaults
    for(int i = 0; i < 32; i++)
    {
        m_intrabarPolicyConfig[i] = INTRABAR_POLICY_OFF;
    }
    
    // L1-007: Create component instances
    m_diagnostics = NULL; // Injected from EAOrchestrator
    m_attribution = NULL; // Injected from EAOrchestrator
    // m_consensus removed - consensus logic moved into EnterpriseStrategyManager
    m_healthMonitor = new CStrategyHealthMonitor();

    // Phase C / Slice 1: bind extracted collaborators at the earliest safe point.
    // The reporter observes this manager read-only; the delegator mirrors the
    // (still NULL) attribution pointer and is re-bound by SetAttributionManager().
    m_stateReporter.SetSource(GetPointer(this));
    m_attributionDelegator.SetAttribution(m_attribution);

    // Phase C / Slice 2: same binding site. Both collaborators point at this
    // manager for its whole lifetime (unlike the attribution delegator, they
    // mirror no injected pointer, so they need no re-sync on Deinit).
    m_postConsensusValidator.SetSource(GetPointer(this));
    m_weightingConfig.SetSource(GetPointer(this));

    // Phase C / Slice 3: same binding site. Both collaborators mutate this
    // manager through its narrow per-field accessors and mirror no injected
    // pointer, so (like Slice 2) they need no re-sync on Deinit.
    m_performanceHealth.SetSource(GetPointer(this));
    m_lifecycle.SetSource(GetPointer(this));

    // Phase C / Slice 5: same binding site. The consensus engine re-reads the
    // pipeline / registry / diagnostics from this manager on every call and
    // mirrors no injected pointer, so it needs no re-sync on Deinit either.
    m_consensusEngine.SetSource(GetPointer(this));
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

    // Batch 116: Release cached ADX handle
    if(m_adxHandleCached != INVALID_HANDLE)
    {
        IndicatorRelease(m_adxHandleCached);
        m_adxHandleCached = INVALID_HANDLE;
    }

    // Clean up FourStateRegimeDetector
    if(m_fourStateRegimeDetector != NULL)
    {
        delete m_fourStateRegimeDetector;
        m_fourStateRegimeDetector = NULL;
    }

    if(m_tfConsistency != NULL)
    {
        delete m_tfConsistency;
        m_tfConsistency = NULL;
    }
    
    // L1-007: Clean up components
    // m_diagnostics is injected from EAOrchestrator - do not delete
    // m_attribution is injected from EAOrchestrator - do not delete
    // m_consensus removed - consensus logic moved into EnterpriseStrategyManager
    if(m_healthMonitor != NULL)
    {
        delete m_healthMonitor;
        m_healthMonitor = NULL;
    }
}

//+------------------------------------------------------------------+
//| Initialize Manager                                              |
//| Two-Phase Initialization Pattern (L2-023):                      |
//|   Phase 1 (Required): Core infrastructure - Pipeline,            |
//|       TimeframeConsistency (must succeed or full init fails)    |
//|   Phase 2 (Optional): Enhancements - FourStateRegimeDetector,   |
//|       FamilyWeightMatrix, VPINFilter, OFIEngine (non-blocking)  |
//| This pattern ensures core consensus machinery is ready before   |
//| registering strategies, while allowing optional engines to      |
//| degrade gracefully without blocking the manager.                |
//| Ownership: Phase 1 objects owned by manager (deleted in dtor).  |
//| Phase 2 objects also owned but failure does not roll back Phase 1.|
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
        // L2-010: Clean up pipeline on allocation failure
        if(m_pipeline != NULL)
        {
            delete m_pipeline;
            m_pipeline = NULL;
        }
        return false;
    }
    if(!m_tfConsistency.Initialize(CONFLICT_RES_WEIGHTED, 0.6, false))
    {
        Print("[EnterpriseStrategyManager] ERROR: TimeframeConsistency initialization failed for ", symbol);
        delete m_tfConsistency;
        m_tfConsistency = NULL;
        // L2-010: Clean up pipeline on initialization failure
        if(m_pipeline != NULL)
        {
            delete m_pipeline;
            m_pipeline = NULL;
        }
        return false;
    }
    
    m_initialized = true;
    m_drawingManager = NULL;
    
    // L1-007: m_diagnostics is injected from EAOrchestrator - do not create here
    // m_diagnostics = new CDiagnosticsCollector();
    // if(m_diagnostics != NULL)
    //     {
    //         m_diagnostics.SetLogIntervalSeconds(60);
    //     }
    
    // L1-007: m_attribution is injected from EAOrchestrator - do not create here
    // m_attribution = new CAttributionTracker();
    
    // L1-007: Consensus logic moved into EnterpriseStrategyManager - no separate CConsensusEngine
    // m_consensus = new CConsensusEngine();
    // ... consensus configuration removed ...
    
    // LEAK-FIX: the constructor (line 724) already allocated m_healthMonitor.
    // Delete any pre-existing instance before re-allocating so the first one is not orphaned.
    if(m_healthMonitor != NULL)
    {
        delete m_healthMonitor;
        m_healthMonitor = NULL;
    }
    m_healthMonitor = new CStrategyHealthMonitor();
    if(m_healthMonitor != NULL)
    {
        m_healthMonitor.SetOrchestratorMode(m_minWinRateThreshold, m_maxConsecutiveLosses_Limit);
        m_healthMonitor.SetPerformanceDecayFactor(m_performanceDecayFactor);
        m_healthMonitor.SetRollingWindowSize(m_rollingWindowSize);
        m_healthMonitor.SetMaxDrawdownLimit(m_maxDrawdownLimit);
        m_healthMonitor.SetStrategyActivityDecayRate(m_strategyActivityDecayRate);
        m_healthMonitor.SetStrategyInactiveCounterThreshold(m_strategyInactiveCounterThreshold);
    }
    
    // L6-008: Health monitor is used directly by internal consensus logic
    // No separate consensus engine to wire
    
    // Initialize FourStateRegimeDetector
    m_fourStateRegimeDetector = new CFourStateRegimeDetector(m_symbol, m_baseTimeframe);
    if(m_fourStateRegimeDetector != NULL)
    {
        if(m_fourStateRegimeDetector.Initialize())
        {
            Print("[EnterpriseStrategyManager] FourStateRegimeDetector initialized for ", m_symbol);
            m_regimeDetectorInitialized = true;
        }
        else
        {
            Print("[EnterpriseStrategyManager] WARNING: FourStateRegimeDetector initialization failed for ", m_symbol);
            delete m_fourStateRegimeDetector;
            m_fourStateRegimeDetector = NULL;
            m_regimeDetectorInitialized = false;
        }
    }
    else
    {
        m_regimeDetectorInitialized = false;
    }
    
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
                                                 ENUM_INTRABAR_POLICY intrabarPolicy,
                                                 ENUM_STRATEGY_ROLE role,
                                                 ENUM_STRATEGY_CLUSTER cluster,
                                                 bool liveVotingEnabled)
{
    if(strategy == NULL || !m_initialized)
        return false;
        
    // L1-010: Check with StrategyRegistry if this strategy should be active in current mode
        // The 'enabled' parameter is advisory; registry is the single source of truth
        if(m_strategyRegistry != NULL)
        {
            // Check if strategy is registered and mode-permissive
            if(!m_strategyRegistry.IsStrategyActive(name))
            {
                PrintFormat("[ENTERPRISE] Strategy %s disabled by registry (mode filter or not registered)", name);
                enabled = false;  // Override: registry says this strategy is not active
            }
        }
    
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
    
    // L6-010: Initialize AI model after factory creation
    // This ensures AI adapters have proper symbol/timeframe/risk context
    if(!strategy.InitializeAI(m_symbol, resolvedTf, m_unifiedRiskManager))
    {
        Print("[EnterpriseStrategyManager] WARNING: Strategy ", name, " AI initialization failed. Continuing with base initialization.");
        // Don't fail registration - AI initialization failure is non-fatal for some adapters
    }
    
    // L6-001 CRITICAL FIX: Validate risk manager injection after initialization
        if(!strategy.ValidateRiskManagerInjection())
        {
            Print("[EnterpriseStrategyManager] CRITICAL: Strategy ", name, " failed risk manager injection validation. Strategy will bypass risk validation - rejecting registration.");
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
        m_strategies[m_strategyCount].intrabarEligible = (intrabarPolicy == INTRABAR_POLICY_LIVE);
        m_strategies[m_strategyCount].intrabarPolicy = (int)intrabarPolicy;
        m_strategies[m_strategyCount].liveVotingEnabled = liveVotingEnabled;
        m_strategies[m_strategyCount].role = (int)role;
        m_strategies[m_strategyCount].cluster = (int)cluster;
        m_strategies[m_strategyCount].tier = tier; // Store tier
        m_strategies[m_strategyCount].weight = weight;
        m_strategies[m_strategyCount].originalWeight = weight;  // Track for decay recovery
        m_strategies[m_strategyCount].timeframe = resolvedTf;
        m_strategies[m_strategyCount].successCount = 0;
        m_strategies[m_strategyCount].failCount = 0;
        m_strategies[m_strategyCount].healthScore = 0.75;
    m_strategies[m_strategyCount].participationScore = 0.90;
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
    
    // L1-007: Register with health monitor
    if(m_healthMonitor != NULL)
    {
        m_healthMonitor.RegisterStrategy(weight);
    }
    
    m_strategyCount++;
    
    Print("[EnterpriseStrategyManager] Registered strategy: ", name, 
          " | Enabled: ", enabled, " | Tier: ", (int)tier, " | Weight: ", weight,
          " | TF: ", EnumToString(resolvedTf),
          " | Intrabar: ", IntrabarPolicyToString((ENUM_INTRABAR_POLICY)m_strategies[m_strategyCount - 1].intrabarPolicy),
          " | Role: ", StrategyRoleToString(role),
          " | Cluster: ", StrategyClusterToString(cluster),
          " | LiveVote: ", liveVotingEnabled ? "YES" : "NO");
    
    return true;
}

//+------------------------------------------------------------------+
//| Configuration Setters - Store in mirrored config variables       |
//+------------------------------------------------------------------+
void CEnterpriseStrategyManager::SetMinQuorum(int quorum)
{
    m_minQuorum = MathMax(1, quorum);
}

void CEnterpriseStrategyManager::SetIntrabarMinQuorum(int quorum)
{
    m_intrabarMinQuorum = MathMax(1, quorum);
}

void CEnterpriseStrategyManager::SetIntrabarDynamicQuorumEnabled(const bool enabled)
{
    m_intrabarDynamicQuorumEnabled = enabled;
}

void CEnterpriseStrategyManager::SetIntrabarSingleVoterMinConfidence(const double minConfidence)
{
    m_intrabarSingleVoterMinConfidence = MathMax(0.0, MathMin(1.0, minConfidence));
}

void CEnterpriseStrategyManager::SetQuorumThreshold(const double threshold)
{
    m_quorumThreshold = MathMax(0.0, MathMin(1.0, threshold));
}

void CEnterpriseStrategyManager::SetConflictDeadband(const double deadband)
{
    m_conflictDeadband = MathMax(0.0, MathMin(0.5, deadband));
}

void CEnterpriseStrategyManager::SetMinReadyWeightRatio(const double ratio)
{
    m_minReadyWeightRatio = MathMax(0.0, MathMin(1.0, ratio));
}

void CEnterpriseStrategyManager::SetSupportFloors(const double newBarFloor, const double intrabarFloor)
{
    m_supportFloorNewBar = MathMax(0.0, MathMin(1.0, newBarFloor));
    m_supportFloorIntrabar = MathMax(0.0, MathMin(1.0, intrabarFloor));
}

void CEnterpriseStrategyManager::SetSparseIntrabarThresholds(const double minQuality,
                                     const double minSupportRatio,
                                     const double minReadyCoverage)
{
    m_sparseIntrabarMinQuality = MathMax(0.0, MathMin(1.0, minQuality));
    m_sparseIntrabarMinSupportRatio = MathMax(0.0, MathMin(1.0, minSupportRatio));
    m_sparseIntrabarMinReadyCoverage = MathMax(0.0, MathMin(1.0, minReadyCoverage));
}

void CEnterpriseStrategyManager::SetAllowSparseIntrabarSingleVoter(const bool enabled)
{
    m_allowSparseIntrabarSingleVoter = enabled;
}

// Intrabar policy configuration per strategy index (L6-007)
void CEnterpriseStrategyManager::SetStrategyIntrabarPolicyConfig(int strategyIndex, ENUM_INTRABAR_POLICY policy)
{
    if(strategyIndex >= 0 && strategyIndex < 32)
    {
        m_intrabarPolicyConfig[strategyIndex] = policy;
    }
}

ENUM_INTRABAR_POLICY CEnterpriseStrategyManager::GetStrategyIntrabarPolicyConfig(int strategyIndex) const
{
    if(strategyIndex >= 0 && strategyIndex < 32)
    {
        return m_intrabarPolicyConfig[strategyIndex];
    }
    return INTRABAR_POLICY_OFF;
}

// Participation formula configuration (L6-008)
void CEnterpriseStrategyManager::SetParticipationFormulaBase(const double base)
{
    m_participationFormulaBase = MathMax(0.0, MathMin(1.0, base));
}
void CEnterpriseStrategyManager::SetParticipationFormulaCoeff(const double coeff)
{
    m_participationFormulaCoeff = MathMax(0.0, MathMin(2.0, coeff));
}
void CEnterpriseStrategyManager::SetParticipationFormulaMin(const double minVal)
{
    m_participationFormulaMin = MathMax(0.0, MathMin(1.0, minVal));
}
void CEnterpriseStrategyManager::SetParticipationFormulaMax(const double maxVal)
{
    m_participationFormulaMax = MathMax(0.0, MathMin(2.0, maxVal));
}

void CEnterpriseStrategyManager::SetConsensusDiagnosticsIntervalSeconds(const int seconds)
{
    if(m_diagnostics != NULL)
        m_diagnostics.SetLogIntervalSeconds(seconds);
}

int CEnterpriseStrategyManager::GetMinQuorum() const
{
    return m_minQuorum;
}

//+------------------------------------------------------------------+
//| Consensus entry funnel                                           |
//|                                                                  |
//| Phase C / Slice 5 (C9): the whole consensus core moved into      |
//| CConsensusEngine. These public overloads are retained verbatim   |
//| as one-line forwarders because EAOrchestrator, SignalGenerator,  |
//| PositionLifecycleManager and TrainingDataExporter call them.     |
//+------------------------------------------------------------------+
ENUM_TRADE_SIGNAL CEnterpriseStrategyManager::GetConsensusSignal(double &confidence)
{
    return m_consensusEngine.GetConsensusSignal(confidence);
}

ENUM_TRADE_SIGNAL CEnterpriseStrategyManager::GetConsensusSignalWithConfluence(double &confidence, int &confluence)
{
    return m_consensusEngine.GetConsensusSignalWithConfluence(confidence, confluence);
}

ENUM_TRADE_SIGNAL CEnterpriseStrategyManager::GetConsensusSignalForSymbolWithConfluence(const string symbol, double &confidence, int &confluence)
{
    return m_consensusEngine.GetConsensusSignalForSymbolWithConfluence(symbol, confidence, confluence);
}

ENUM_TRADE_SIGNAL CEnterpriseStrategyManager::GetConsensusSignalForSymbolWithConfluenceMode(const string symbol,
                                                                                              double &confidence,
                                                                                              int &confluence,
                                                                                              ENUM_SIGNAL_EVAL_MODE evalMode)
{
    return m_consensusEngine.GetConsensusSignalForSymbolWithConfluenceMode(symbol, confidence, confluence, evalMode);
}

//+------------------------------------------------------------------+
//| Two-tier consensus evaluation - uses internal consensus logic   |
//+------------------------------------------------------------------+
ENUM_TRADE_SIGNAL CEnterpriseStrategyManager::EvaluateConsensusTwoTier(const string symbol, double &confidence, int &confluence, ENUM_SIGNAL_EVAL_MODE evalMode)
{
    return m_consensusEngine.EvaluateConsensusTwoTier(symbol, confidence, confluence, evalMode);
}

//+------------------------------------------------------------------+
//| Get Consensus Signal For Specific Symbol                        |
//+------------------------------------------------------------------+
ENUM_TRADE_SIGNAL CEnterpriseStrategyManager::GetConsensusSignalForSymbol(const string symbol, double &confidence)
{
    return m_consensusEngine.GetConsensusSignalForSymbol(symbol, confidence);
}

//+------------------------------------------------------------------+
//| Auto-register Strategies                                        |
//+------------------------------------------------------------------+
ENUM_INTRABAR_POLICY CEnterpriseStrategyManager::GetIntrabarPolicyHelper(int idx)
{
    if(idx >= 0 && idx < 32 && m_intrabarPolicyConfig[idx] != INTRABAR_POLICY_OFF)
        return m_intrabarPolicyConfig[idx];
    // Default policies per strategy (matching original hardcoded values)
    if(idx == 9 || idx == 10) return INTRABAR_POLICY_LIVE; // Mean Reversion, Volatility Breakout
    return INTRABAR_POLICY_OFF;
}

void CEnterpriseStrategyManager::AutoRegisterStrategies(bool &flags[])
{
    int size = ArraySize(flags);
    
    // 0: Momentum (live primary voter) - Tier 3
        if(size > 0 && flags[0]) RegisterStrategy(new CSimpleMomentumStrategy(), "Momentum", true, 1.0, STRATEGY_TIER_3, PERIOD_CURRENT, GetIntrabarPolicyHelper(0),
                                                         PRIMARY_ALPHA, TREND_CLUSTER, true);

                // 1: Trend (live primary voter) - Tier 2
                if(size > 1 && flags[1]) RegisterStrategy(new CStrategyTrend(), "Trend", true, 1.2, STRATEGY_TIER_2, PERIOD_CURRENT, GetIntrabarPolicyHelper(1),
                                                         PRIMARY_ALPHA, TREND_CLUSTER, true);

                // 2: Support/Resistance (live primary voter) - Tier 2
                        if(size > 4 && flags[4]) RegisterStrategy(new CStrategySupportResistance(), "Support/Resistance", true, 1.5, STRATEGY_TIER_2, PERIOD_CURRENT, GetIntrabarPolicyHelper(4),
                                                                 PRIMARY_ALPHA, MEAN_REVERSION_CLUSTER, true);

                        // 5: Unified ICT - REMOVED (over-engineered, 14+ modules, 1850 lines)

                        // 6: Candlestick (live primary voter) - Tier 2
                if(size > 6 && flags[6]) RegisterStrategy(new CStrategyCandlestick(), "Candlestick", true, 1.5, STRATEGY_TIER_2, PERIOD_CURRENT, GetIntrabarPolicyHelper(6),
                                                         PRIMARY_ALPHA, STRUCTURE_CLUSTER, true);

        // 9: Mean Reversion (live primary voter) - Tier 2 - MEAN_REVERSION_CLUSTER
        if(size > 9 && flags[9]) RegisterStrategy(new CMeanReversionStrategy(), "Mean Reversion", true, 1.8, STRATEGY_TIER_2, PERIOD_CURRENT, GetIntrabarPolicyHelper(9),
                                                 PRIMARY_ALPHA, MEAN_REVERSION_CLUSTER, true);

        // 10: Volatility Breakout (live primary voter) - Tier 1 - TREND_CLUSTER
        if(size > 10 && flags[10]) RegisterStrategy(new CVolatilityBreakoutStrategy(), "Volatility Breakout", true, 2.0, STRATEGY_TIER_1, PERIOD_CURRENT, GetIntrabarPolicyHelper(10),
                                                   PRIMARY_ALPHA, TREND_CLUSTER, true);

    // 11: Statistical Arbitrage - Requires Python Bridge for real-time correlation matrix
        // Conditionally registered only when Python bridge is available
        if(g_pythonBridge != NULL && g_pythonBridge.IsConnected())
        {
            if(size > 11 && flags[11]) RegisterStrategy(new CStatisticalArbitrageStrategy(), "Statistical Arbitrage", true, 1.8, STRATEGY_TIER_2, PERIOD_CURRENT, GetIntrabarPolicyHelper(11),
                                                        PRIMARY_ALPHA, MEAN_REVERSION_CLUSTER, true);
            Print("[EnterpriseStrategyManager] Python Bridge available - Statistical Arbitrage strategy registered");
        }
        else
        {
            Print("[EnterpriseStrategyManager] Python Bridge not available - Skipping Statistical Arbitrage registration");
        }

        // Batch 103: New ICT/SMC strategies
        // 12: FVG Scalper - Tier 2 - STRUCTURE_CLUSTER
        if(size > 12 && flags[12]) RegisterStrategy(new CFVGScalperStrategy(), "FVG Scalper", true, 1.8, STRATEGY_TIER_2, PERIOD_CURRENT, GetIntrabarPolicyHelper(12),
                                                    PRIMARY_ALPHA, STRUCTURE_CLUSTER, true);

        // 13: Turtle Soup - Tier 2 - STRUCTURE_CLUSTER
        if(size > 13 && flags[13]) RegisterStrategy(new CTurtleSoupStrategy(), "Turtle Soup", true, 1.6, STRATEGY_TIER_2, PERIOD_CURRENT, GetIntrabarPolicyHelper(13),
                                                    PRIMARY_ALPHA, STRUCTURE_CLUSTER, true);

        // 14: Breaker Block - Tier 2 - STRUCTURE_CLUSTER
        if(size > 14 && flags[14]) RegisterStrategy(new CBreakerBlockStrategy(), "Breaker Block", true, 1.7, STRATEGY_TIER_2, PERIOD_CURRENT, GetIntrabarPolicyHelper(14),
                                                    PRIMARY_ALPHA, STRUCTURE_CLUSTER, true);

        // 15: NY Open Gap - Tier 3 - STRUCTURE_CLUSTER (session-limited)
                if(size > 15 && flags[15]) RegisterStrategy(new CNYOpenGapStrategy(), "NY Open Gap", true, 1.3, STRATEGY_TIER_3, PERIOD_CURRENT, GetIntrabarPolicyHelper(15),
                                                            PRIMARY_ALPHA, STRUCTURE_CLUSTER, true);

                // 16: Asian Range Break - Tier 3 - STRUCTURE_CLUSTER (session-limited)
                if(size > 16 && flags[16]) RegisterStrategy(new CAsianRangeBreakStrategy(), "Asian Range Break", true, 1.3, STRATEGY_TIER_3, PERIOD_CURRENT, GetIntrabarPolicyHelper(16),
                                                            PRIMARY_ALPHA, STRUCTURE_CLUSTER, true);

    Print("[EnterpriseStrategyManager] Auto-registration complete. Active strategies: ",
          GetActiveStrategyCount());
}

//+------------------------------------------------------------------+
//| Reconcile enabled flags with the finalized registry            |
//| Strategies are auto-registered (AutoRegisterStrategies) BEFORE |
//| the orchestrator's BuildStrategyRegistry populates the shared  |
//| CStrategyRegistry with definitions. At that early point         |
//| IsStrategyActive() returns false (definition not found), so the|
//| override at RegisterStrategy() locks every strategy disabled.   |
//| After BuildStrategyRegistry finalizes the mode, this method     |
//| re-applies the registry's active state so the live strategy     |
//| objects actually participate in consensus.                      |
//+------------------------------------------------------------------+
void CEnterpriseStrategyManager::SyncEnabledWithRegistry()
{
    m_consensusEngine.SyncEnabledWithRegistry();
}


//+------------------------------------------------------------------+
//| Get Active Strategy Count                                       |
//+------------------------------------------------------------------+
int CEnterpriseStrategyManager::GetActiveStrategyCount() const
{
    return m_stateReporter.GetActiveStrategyCount();
}

//+------------------------------------------------------------------+
//| Get Active Brain Strategy Count                                  |
//+------------------------------------------------------------------+
int CEnterpriseStrategyManager::GetActiveBrainStrategyCount() const
{
    return m_stateReporter.GetActiveBrainStrategyCount();
}

//+------------------------------------------------------------------+
//| Get Strategy Report                                             |
//+------------------------------------------------------------------+
string CEnterpriseStrategyManager::GetStrategyReport() const
{
    return m_stateReporter.GetStrategyReport();
}

//+------------------------------------------------------------------+
//| Set Pipeline Filters                                             |
//+------------------------------------------------------------------+
void CEnterpriseStrategyManager::SetPipelineFilters(SignalFilterSettings &settings)
{
    // Cache pipeline base confidence floor for quorum eligibility even if the pipeline is disabled.
    m_pipelineMinConfidence = MathMax(0.0, MathMin(1.0, settings.confidence.minConfidence));

    if(m_pipeline != NULL)
    {
        // Apply runtime filter configuration without re-initializing pipeline engines.
        m_pipeline.SetFilters(settings);
        Print("[EnterpriseStrategyManager] Pipeline filters applied: TrendFilter=",
              settings.trend.enabled, " MinConf=", settings.confidence.minConfidence,
              " IntrabarCap=", settings.confidence.intrabarConfidenceCap,
              " RegimeCost=", settings.regimeCostGate.enabled,
              " MaxSpreadATR=", settings.regimeCostGate.maxSpreadToAtrRatio,
              " ShockCooldown=", settings.regimeCostGate.spreadShockCooldownSeconds,
              " MaxEntryZ=", settings.regimeCostGate.maxEntryRangeZScore,
              " MaxVol=", settings.volatility.maxVolatility,
              " StructureFilter=", settings.structure.enabled,
              " LiquidityFilter=", settings.liquidity.enabled);
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
    return m_stateReporter.GetStrategyWeightsJSON();
}

string CEnterpriseStrategyManager::GetStrategyListJSON() const
{
    return m_stateReporter.GetStrategyListJSON();
}

string CEnterpriseStrategyManager::GetConsensusContextJSON() const
{
    return m_stateReporter.GetConsensusContextJSON();
}

//+------------------------------------------------------------------+
//| Consensus Decision Class to String Conversion                    |
//+------------------------------------------------------------------+
string CEnterpriseStrategyManager::ConsensusDecisionClassToString(ENUM_CONSENSUS_DECISION_CLASS decisionClass)
{
    return CStrategyStateReporter::ConsensusDecisionClassToString(decisionClass);
}

// Phase C / Slice 2 (C4): implementation moved to CConsensusWeightingConfig.
void CEnterpriseStrategyManager::UpdateStrategyWeights()
{
    m_weightingConfig.UpdateStrategyWeights();
}

// Phase C / Slice 3 (C7): implementation moved to CStrategyLifecycle.
void CEnterpriseStrategyManager::CheckStrategyDisabling()
{
    m_lifecycle.CheckStrategyDisabling();
}

// Phase C / Slice 3 (C7): implementation moved to CStrategyLifecycle.
void CEnterpriseStrategyManager::CheckStrategyReEnabling()
{
    m_lifecycle.CheckStrategyReEnabling();
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

    // L1-007: Update health monitor
    if(m_healthMonitor != NULL)
        m_healthMonitor.SetStrategyWeight(index, sanitizedWeight);

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

//+------------------------------------------------------------------+
//| Phase C / Slice 4 (C8): per-field accessors for slice modules    |
//+------------------------------------------------------------------+
void CEnterpriseStrategyManager::SetStrategyRole(int index, int role)
{
    if(index >= 0 && index < m_strategyCount)
        m_strategies[index].role = role;
}

void CEnterpriseStrategyManager::SetStrategyCluster(int index, int cluster)
{
    if(index >= 0 && index < m_strategyCount)
        m_strategies[index].cluster = cluster;
}

void CEnterpriseStrategyManager::SetStrategyLiveVotingEnabled(int index, bool enabled)
{
    if(index >= 0 && index < m_strategyCount)
        m_strategies[index].liveVotingEnabled = enabled;
}

void CEnterpriseStrategyManager::SetStrategyIntrabarPolicyRaw(int index, int policy)
{
    if(index >= 0 && index < m_strategyCount)
        m_strategies[index].intrabarPolicy = policy;
}

void CEnterpriseStrategyManager::SetStrategyIntrabarEligible(int index, bool eligible)
{
    if(index >= 0 && index < m_strategyCount)
        m_strategies[index].intrabarEligible = eligible;
}

//+------------------------------------------------------------------+
//| Phase C / Slice 4 (C8): 35-field StrategyEntry append           |
//| Mirrors the original RegisterStrategy append block exactly.      |
//+------------------------------------------------------------------+
void CEnterpriseStrategyManager::AppendRegisteredStrategyEntry(IStrategy* strategy, const string name, bool enabled,
                                                              double weight, ENUM_STRATEGY_TIER tier,
                                                              ENUM_TIMEFRAMES resolvedTf,
                                                              ENUM_INTRABAR_POLICY intrabarPolicy,
                                                              ENUM_STRATEGY_ROLE role,
                                                              ENUM_STRATEGY_CLUSTER cluster,
                                                              bool liveVotingEnabled)
{
    int newSize = m_strategyCount + 1;
    ArrayResize(m_strategies, newSize);

    m_strategies[m_strategyCount].strategy = strategy;
    m_strategies[m_strategyCount].name = name;
    m_strategies[m_strategyCount].enabled = enabled;
    m_strategies[m_strategyCount].intrabarEligible = (intrabarPolicy == INTRABAR_POLICY_LIVE);
    m_strategies[m_strategyCount].intrabarPolicy = (int)intrabarPolicy;
    m_strategies[m_strategyCount].liveVotingEnabled = liveVotingEnabled;
    m_strategies[m_strategyCount].role = (int)role;
    m_strategies[m_strategyCount].cluster = (int)cluster;
    m_strategies[m_strategyCount].tier = tier;
    m_strategies[m_strategyCount].weight = weight;
    m_strategies[m_strategyCount].originalWeight = weight;
    m_strategies[m_strategyCount].timeframe = resolvedTf;
    m_strategies[m_strategyCount].successCount = 0;
    m_strategies[m_strategyCount].failCount = 0;
    m_strategies[m_strategyCount].healthScore = 0.75;
    m_strategies[m_strategyCount].participationScore = 0.90;
    m_strategies[m_strategyCount].avgConfidence = 0;
    m_strategies[m_strategyCount].lastSignal = TRADE_SIGNAL_NONE;
    m_strategies[m_strategyCount].lastSignalConfidence = 0.0;
    m_strategies[m_strategyCount].lastEvaluationTime = 0;
    m_strategies[m_strategyCount].consecutiveFilterCount = 0;

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

    if(m_healthMonitor != NULL)
        m_healthMonitor.RegisterStrategy(weight);

    m_strategyCount++;
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
                                                             const bool liveVotingEnabled)
{
    int index = FindStrategyIndexByName(name);
    if(index < 0)
        return false;

    m_strategies[index].role = (int)role;
    m_strategies[index].cluster = (int)cluster;
    m_strategies[index].liveVotingEnabled = liveVotingEnabled;

    PrintFormat("[EnterpriseStrategyManager] Governance updated: %s | role=%s | cluster=%s | live_vote=%s",
                name,
                StrategyRoleToString(role),
                StrategyClusterToString(cluster),
                liveVotingEnabled ? "ENABLED" : "DISABLED");
    return true;
}


string CEnterpriseStrategyManager::GetRegisteredStrategyName(const int index) const
{
    return m_stateReporter.GetRegisteredStrategyName(index);
}

double CEnterpriseStrategyManager::GetRegisteredStrategyWeight(const int index) const
{
    return m_stateReporter.GetRegisteredStrategyWeight(index);
}

string CEnterpriseStrategyManager::GetRegisteredStrategyRole(const int index) const
{
    return m_stateReporter.GetRegisteredStrategyRole(index);
}

string CEnterpriseStrategyManager::GetRegisteredStrategyCluster(const int index) const
{
    return m_stateReporter.GetRegisteredStrategyCluster(index);
}

bool CEnterpriseStrategyManager::IsRegisteredStrategyLiveVotingEnabled(const int index) const
{
    return m_stateReporter.IsRegisteredStrategyLiveVotingEnabled(index);
}

void CEnterpriseStrategyManager::GetLastSignalContributors(string &contributors[]) const
{
    ArrayCopy(contributors, m_lastSignalContributors);
}

void CEnterpriseStrategyManager::GetLastSignalContributorIndices(int &indices[]) const
{
    ArrayCopy(indices, m_lastSignalContributorIndices);
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

//+------------------------------------------------------------------+
//| Explicit Deinitialization                                        |
//| Called before destructor to ensure proper cleanup order          |
//+------------------------------------------------------------------+
void CEnterpriseStrategyManager::Deinit()
{
    // Clean up strategies with explicit Deinit call
    for(int i = 0; i < m_strategyCount; i++)
    {
        if(m_strategies[i].strategy != NULL)
        {
            m_strategies[i].strategy.Deinit();
            delete m_strategies[i].strategy;
            m_strategies[i].strategy = NULL;
        }
    }
    m_strategyCount = 0;
    ArrayResize(m_strategies, 0);
    
    // Clean up components
    if(m_pipeline != NULL)
    {
        delete m_pipeline;
        m_pipeline = NULL;
    }

    // Batch 116: Release cached ADX handle
    if(m_adxHandleCached != INVALID_HANDLE)
    {
        IndicatorRelease(m_adxHandleCached);
        m_adxHandleCached = INVALID_HANDLE;
    }

    // Clean up FourStateRegimeDetector
    if(m_fourStateRegimeDetector != NULL)
    {
        delete m_fourStateRegimeDetector;
        m_fourStateRegimeDetector = NULL;
    }

    if(m_tfConsistency != NULL)
    {
        delete m_tfConsistency;
        m_tfConsistency = NULL;
    }
    
    // L1-007: Clean up components
    if(m_diagnostics != NULL)
    {
        delete m_diagnostics;
        m_diagnostics = NULL;
    }
    
    if(m_attribution != NULL)
    {
        delete m_attribution;
        m_attribution = NULL;
    }
    // Phase C / Slice 1: keep the delegator's mirrored pointer from dangling.
    m_attributionDelegator.SetAttribution(m_attribution);
    
    if(m_healthMonitor != NULL)
    {
        delete m_healthMonitor;
        m_healthMonitor = NULL;
    }
    
    m_initialized = false;
}

bool CEnterpriseStrategyManager::GetLastDecisionContext(SConsensusDecisionContext &context) const
{
    return m_stateReporter.GetLastDecisionContext(context);
}

void CEnterpriseStrategyManager::GetRoleClusterDiagnosticsTotals(ulong &primarySignals,
                                                                 ulong &featureSignals,
                                                                 ulong &voteSuppressed,
                                                                 ulong &trendClusterSignals,
                                                                 ulong &meanReversionClusterSignals,
                                                                 ulong &structureClusterSignals,
                                                                 ulong &noneClusterSignals) const
{
    m_stateReporter.GetRoleClusterDiagnosticsTotals(primarySignals,
                                                    featureSignals,
                                                    voteSuppressed,
                                                    trendClusterSignals,
                                                    meanReversionClusterSignals,
                                                    structureClusterSignals,
                                                    noneClusterSignals);
}

void CEnterpriseStrategyManager::GetLastCycleFunnel(int &signalsGenerated, int &signalsAfterPipeline, bool &signalAfterQuorum) const
{
    m_stateReporter.GetLastCycleFunnel(signalsGenerated, signalsAfterPipeline, signalAfterQuorum);
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
    m_stateReporter.GetConsensusDiagnosticsSnapshot(rawNone,
                                                    filteredOut,
                                                    quorumFailed,
                                                    intrabarNotEligible,
                                                    signalsGenerated,
                                                    signalsAfterPipeline,
                                                    signalsAfterQuorum,
                                                    momentumNone,
                                                    momentumCooldown,
                                                    momentumLowVolatility,
                                                    momentumNoCrossover,
                                                    momentumTrendMisaligned,
                                                    momentumNotReady,
                                                    uictNone,
                                                    uictNeutralBias,
                                                    uictOtherFilters,
                                                    intervalReasonTotal);
}

bool CEnterpriseStrategyManager::PopClosedTradeAttribution(string &contributors[], double &netProfit)
{
    return m_attributionDelegator.PopClosedTradeAttribution(contributors, netProfit);
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

//+------------------------------------------------------------------+
//| Get Strategy By Name �?Batch 103: returns strategy pointer       |
//+------------------------------------------------------------------+
IStrategy* CEnterpriseStrategyManager::GetStrategyByName(const string name)
{
    int idx = FindStrategyIndexByName(name);
    if(idx < 0 || idx >= m_strategyCount)
        return NULL;
    return m_strategies[idx].strategy;
}






//+------------------------------------------------------------------+
//| Determine if current regime is trending for cross-cluster conflict |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| FALLBACK SOLO SIGNAL: When all strategies abstain, pick best     |
//| single strategy based on confidence and context quality          |
//| Prevents trading paralysis during low-signal periods             |
//+------------------------------------------------------------------+
ENUM_TRADE_SIGNAL CEnterpriseStrategyManager::TryFallbackSoloSignal(const string symbol,
                                       ENUM_SIGNAL_EVAL_MODE evalMode,
                                       double &outConfidence,
                                       int &outConfluence,
                                       string &outReason)
{
    return m_consensusEngine.TryFallbackSoloSignal(symbol, evalMode, outConfidence, outConfluence, outReason);
}



bool CEnterpriseStrategyManager::IsStrategyLiveVoter(const int strategyIndex) const
{
    return m_consensusEngine.IsStrategyLiveVoter(strategyIndex);
}











int CEnterpriseStrategyManager::FindAttributionIndexByPositionId(const ulong positionId) const
{
    return m_attributionDelegator.FindAttributionIndexByPositionId(positionId);
}

string CEnterpriseStrategyManager::JoinContributors(const string &contributors[]) const
{
    return m_attributionDelegator.JoinContributors(contributors);
}

void CEnterpriseStrategyManager::SplitContributors(const string csv, string &contributors[]) const
{
    m_attributionDelegator.SplitContributors(csv, contributors);
}

void CEnterpriseStrategyManager::UpsertPositionAttribution(const ulong positionId, const string &contributors[])
{
    m_attributionDelegator.UpsertPositionAttribution(positionId, contributors);
}

bool CEnterpriseStrategyManager::PopPositionAttribution(const ulong positionId, string &contributors[])
{
    return m_attributionDelegator.PopPositionAttribution(positionId, contributors);
}

//+------------------------------------------------------------------+
//| Performance / health accounting                                  |
//|                                                                  |
//| Phase C / Slice 3 (C5): the implementations moved wholesale into |
//| CStrategyPerformanceHealth. The manager keeps only forwarders    |
//| because every one of these is part of its public API (consumed   |
//| by EAOrchestrator, AIEngine and OnTradeTransaction below).       |
//+------------------------------------------------------------------+
void CEnterpriseStrategyManager::UpdatePerformance(const string strategyName, double netProfit)
{
    m_performanceHealth.UpdatePerformance(strategyName, netProfit);
}

void CEnterpriseStrategyManager::UpdateRecentPerformance(const int index, const double result)
{
    m_performanceHealth.UpdateRecentPerformance(index, result);
}

double CEnterpriseStrategyManager::CalculateRecentWinRate(const int index)
{
    return m_performanceHealth.CalculateRecentWinRate(index);
}

double CEnterpriseStrategyManager::CalculateSharpeRatio(const int index)
{
    return m_performanceHealth.CalculateSharpeRatio(index);
}

void CEnterpriseStrategyManager::CalculateStrategyMetrics(const int index)
{
    m_performanceHealth.CalculateStrategyMetrics(index);
}

bool CEnterpriseStrategyManager::ShouldDisableStrategy(const int index)
{
    return m_performanceHealth.ShouldDisableStrategy(index);
}

bool CEnterpriseStrategyManager::ShouldReEnableStrategy(const int index)
{
    return m_performanceHealth.ShouldReEnableStrategy(index);
}

void CEnterpriseStrategyManager::UpdateRegimePerformance(const int index, int regime, const double result)
{
    m_performanceHealth.UpdateRegimePerformance(index, regime, result);
}


//+------------------------------------------------------------------+
//| OnNewBar - CRITICAL for zone scanning and chart drawings         |
//| Must be called from main EA on each new bar                      |
//+------------------------------------------------------------------+
// Phase C / Slice 3 (C7): implementation moved to CStrategyLifecycle.
void CEnterpriseStrategyManager::OnNewBar(const string symbol, ENUM_TIMEFRAMES timeframe)
{
    m_lifecycle.OnNewBar(symbol, timeframe);
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
                if(m_attribution != NULL)
                {
                    m_attribution.UpsertPositionAttribution(positionId, m_lastSignalContributors);
                }
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

                // Pop position attribution from trade attribution manager
                string contributors[];
                if(positionId > 0 && m_attribution != NULL && m_attribution.PopPositionAttribution(positionId, contributors))
                {
                    // Store in closed trade attribution for PopClosedTradeAttribution
                    // The TradeAttributionManager handles this internally
                    for(int contributorIdx = 0; contributorIdx < ArraySize(contributors); contributorIdx++)
                    {
                        if(contributors[contributorIdx] == "")
                            continue;
                        UpdatePerformance(contributors[contributorIdx], netProfit);
                        // Also update health monitor
                        if(m_healthMonitor != NULL)
                        {
                            int stratIdx = FindStrategyIndexByName(contributors[contributorIdx]);
                            if(stratIdx >= 0)
                            {
                                m_healthMonitor.RecordTradeResult(stratIdx, netProfit);
                            }
                        }
                    }
                }

                // Reset cached contributor context after close in manager-only governance mode.
                                m_lastContributorCount = 0;
                                ArrayResize(m_lastSignalContributors, 0);
                                ArrayResize(m_lastSignalContributorIndices, 0);

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
// Phase C / Slice 2 (C4): implementation moved to CConsensusWeightingConfig.
// The nested ENUM_QUORUM_PROFILE stays here (it is a user-facing MT5 `input`
// type) and is forwarded as an int, whose ordinals match QUORUM_PROFILE_*.
void CEnterpriseStrategyManager::ApplyQuorumProfile(ENUM_QUORUM_PROFILE profile)
{
    m_weightingConfig.ApplyQuorumProfile((int)profile);
}

//+------------------------------------------------------------------+
//| Apply family-based engine weights for Deriv synthetic indices    |
//+------------------------------------------------------------------+
// Phase C / Slice 2 (C4): implementation moved to CConsensusWeightingConfig.
void CEnterpriseStrategyManager::ApplyFamilyEngineWeights(const string symbol)
{
    m_weightingConfig.ApplyFamilyEngineWeights(symbol);
}

//+------------------------------------------------------------------+
//| Apply asset-class-based engine weights using multi-asset profiler|
//+------------------------------------------------------------------+
// Phase C / Slice 2 (C4): implementation moved to CConsensusWeightingConfig.
void CEnterpriseStrategyManager::ApplyAssetClassEngineWeights(const string symbol)
{
    m_weightingConfig.ApplyAssetClassEngineWeights(symbol);
}

//+------------------------------------------------------------------+
//| Enable Strategy By Name                                         |
//+------------------------------------------------------------------+
bool CEnterpriseStrategyManager::EnableStrategy(const string name)
{
    // Phase C / Slice 3 (C7): implementation moved to CStrategyLifecycle.
    return m_lifecycle.EnableStrategy(name);
}

//+------------------------------------------------------------------+
//| Disable Strategy By Name                                        |
//+------------------------------------------------------------------+
bool CEnterpriseStrategyManager::DisableStrategy(const string name)
{
    // Phase C / Slice 3 (C7): implementation moved to CStrategyLifecycle.
    return m_lifecycle.DisableStrategy(name);
}

//+------------------------------------------------------------------+
//| Check if magic number is owned by this EA                        |
//+------------------------------------------------------------------+
bool CEnterpriseStrategyManager::IsEAOwnedMagic(long magic) const
{
    if(m_managedMagic <= 0)
        return false;
    if(magic == m_managedMagic)
        return true;
    if(magic > m_managedMagic && magic <= m_managedMagicRangeMax)
        return true;
    return false;
}

//+------------------------------------------------------------------+
//| Get Registered Strategy Count                                    |
//+------------------------------------------------------------------+
int CEnterpriseStrategyManager::GetRegisteredStrategyCount() const
{
    return m_stateReporter.GetRegisteredStrategyCount();
}

//+------------------------------------------------------------------+
//| Get Pipeline Pointer                                             |
//+------------------------------------------------------------------+
CUnifiedSignalPipeline* CEnterpriseStrategyManager::GetPipeline()
{
    return m_pipeline;
}

//+------------------------------------------------------------------+
//| Get Ensemble Confidence                                          |
//+------------------------------------------------------------------+
double CEnterpriseStrategyManager::GetEnsembleConfidence() const
{
    return m_stateReporter.GetEnsembleConfidence();
}

//+------------------------------------------------------------------+
//| Get Current Market Regime                                        |
//+------------------------------------------------------------------+
ENUM_MARKET_REGIME CEnterpriseStrategyManager::GetCurrentMarketRegime() const
{
    return m_currentMarketRegime;
}

//+------------------------------------------------------------------+
//| Set Drawing Manager                                              |
//+------------------------------------------------------------------+
void CEnterpriseStrategyManager::SetDrawingManager(CChartDrawingManager* drawingManager)
{
    m_drawingManager = drawingManager;
}

//+------------------------------------------------------------------+
//| Get Drawing Manager                                              |
//+------------------------------------------------------------------+
CChartDrawingManager* CEnterpriseStrategyManager::GetDrawingManager()
{
    return m_drawingManager;
}

//+------------------------------------------------------------------+
//| Set Deriv Profiler                                               |
//+------------------------------------------------------------------+
void CEnterpriseStrategyManager::SetDerivProfiler(CDerivAssetProfiler* profiler)
{
    m_derivProfiler = profiler;
}

//+------------------------------------------------------------------+
//| Set Family Weight Matrix                                         |
//+------------------------------------------------------------------+
void CEnterpriseStrategyManager::SetFamilyWeightMatrix(CFamilyStrategyWeightMatrix* famMatrix)
{
    m_familyWeightMatrix = famMatrix;
}

//+------------------------------------------------------------------+
//| Set Multi-Asset Profiler                                         |
//+------------------------------------------------------------------+
void CEnterpriseStrategyManager::SetMultiAssetProfiler(CMultiAssetProfiler* profiler)
{
    m_multiAssetProfiler = profiler;
}

//+------------------------------------------------------------------+
//| Set VPIN Filter                                                  |
//+------------------------------------------------------------------+
void CEnterpriseStrategyManager::SetVPINFilter(CVPINFilter* vpin)
{
    m_vpinFilter = vpin;
}

//+------------------------------------------------------------------+
//| Set OFI Engine                                                   |
//+------------------------------------------------------------------+
void CEnterpriseStrategyManager::SetOFIEngine(COrderFlowImbalanceEngine* ofi)
{
    m_ofiEngine = ofi;
}

//+------------------------------------------------------------------+
//| Update AI Performance Metrics for AI Strategies (L6-016)        |
//+------------------------------------------------------------------+
void CEnterpriseStrategyManager::UpdateAIPerformanceMetrics(const string strategyName, const SAIModelMetrics &metrics)
{
    // Phase C / Slice 3 (C5): implementation moved to CStrategyPerformanceHealth.
    m_performanceHealth.UpdateAIPerformanceMetrics(strategyName, metrics);
}

//+------------------------------------------------------------------+
//| Calculate Effective Quorum Parameters (Internal)                |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Evaluate Consensus Internal (Main Consensus Logic)              |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Evaluate Consensus Two-Tier Internal (Probe + Full)             |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Evaluate Consensus Probe Only Internal (Fast Path)              |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Try Fallback Solo Signal Internal (When All Strategies Abstain) |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Post-Consensus Signal Validation                                 |
//|                                                                  |
//| Phase C / Slice 2 (C3): the implementation and the whole         |
//| validator configuration block now live in CPostConsensusValidator.|
//| Only the externally-consumed entry points are forwarded here.    |
//+------------------------------------------------------------------+
SPostConsensusValidation CEnterpriseStrategyManager::ValidateSignal(const string symbol,
                                                                    ENUM_TRADE_SIGNAL signal,
                                                                    double confidence,
                                                                    int confluence,
                                                                    ENUM_SIGNAL_EVAL_MODE evalMode,
                                                                    const SConsensusDecisionContext& ctx,
                                                                    ulong scanCycleId,
                                                                    const string corrId)
{
    return m_postConsensusValidator.ValidateSignal(symbol, signal, confidence, confluence,
                                                   evalMode, ctx, scanCycleId, corrId);
}

string CEnterpriseStrategyManager::GetValidationStatusReport() const
{
    return m_postConsensusValidator.GetValidationStatusReport();
}

void CEnterpriseStrategyManager::SetValidatorConfig(double intrabarMinQuality,
                                                    double newBarMinQuality,
                                                    double hardSpreadCutoff,
                                                    bool spikeHunterEnabled,
                                                    bool enableOFI,
                                                    bool enableVPIN,
                                                    double baseSpreadATRRatio,
                                                    double syntheticSpreadATRRatio)
{
    m_postConsensusValidator.SetValidatorConfig(intrabarMinQuality, newBarMinQuality, hardSpreadCutoff,
                                                spikeHunterEnabled, enableOFI, enableVPIN,
                                                baseSpreadATRRatio, syntheticSpreadATRRatio);
}

#endif // ENTERPRISE_STRATEGY_MANAGER_MQH
