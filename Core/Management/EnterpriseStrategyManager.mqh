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

// Batch 145: the whole production strategy inventory now lives in ONE
// data-driven catalog. StrategyCatalog.mqh pulls in every concrete strategy
// class header itself, so it is included at the exact position the 12 direct
// includes occupied and downstream modules still see the concrete types.
#include "../Strategy/StrategyCatalog.mqh"

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
//| Phase G / G1: struct StrategyEntry and the shared enum->text free  |
//| helpers (StrategyRoleToString, StrategyClusterToString,            |
//| StrategyClusterShortCode, IntrabarPolicyToString,                  |
//| TradeSignalToString, IsInfrastructureNoSignalReasonTag,            |
//| ClampUnitValue) moved verbatim into EntStrategyTypes.mqh. It is    |
//| included at the exact position the originals occupied: after the   |
//| strategy-registry include, before the slice-module includes, so    |
//| every collaborator still sees them BEFORE its own definition.      |
//+------------------------------------------------------------------+
#include "EntStrategyTypes.mqh"

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

// Phase G extracted collaborators. Same rationale as the Phase C slices:
// each is held BY VALUE by the manager, so its complete type must be visible
// here. Include order is load-bearing:
//   EntStrategyQuorumConfig  -> StrategyMgrInfrastructure::Initialize() takes it
//                               by reference;
//   EntStrategyTypes (above) -> StrategyMgrRoster stores StrategyEntry[];
//   AttributionDelegator (above) -> EntStrategySignalContext takes it by
//                               const reference.
#include "EntStrategyQuorumConfig.mqh"    // G2: quorum / adaptation config store
#include "EntStrategySignalContext.mqh"   // G3: last-signal + cycle telemetry
#include "StrategyMgrRoster.mqh"          // G4: registered-strategy roster
#include "StrategyMgrInfrastructure.mqh"  // G5: collaborator plumbing + lifecycle
#include "StrategyMgrTradeFeedback.mqh"   // G6: magic ownership + trade feedback

//+------------------------------------------------------------------+
//| Enterprise Strategy Manager Class                               |
//+------------------------------------------------------------------+
class CEnterpriseStrategyManager
{
private:
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

    // Phase G extracted collaborators (owned by value, no lifetime management).
    // Together they hold ALL of the manager's former loose state: the
    // collaborator pointers / symbol / init flags (G5), the registered-strategy
    // roster (G4), the consensus-quorum configuration (G2), the last-signal and
    // cycle telemetry (G3) and the magic-ownership window (G6). The manager
    // itself is now stateless apart from these members.
    CEntStrategyQuorumConfig   m_quorumConfig;   // G2: quorum / adaptation config
    CEntStrategySignalContext  m_signalContext;  // G3: last-signal + cycle telemetry
    CStrategyMgrRoster         m_roster;         // G4: registered-strategy roster
    CStrategyMgrInfrastructure m_infra;          // G5: collaborator plumbing + lifecycle
    CStrategyMgrTradeFeedback  m_tradeFeedback;  // G6: magic ownership + trade feedback

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
    
    // L1-007: Component accessors (Phase G / G5: storage lives in m_infra)
    CDiagnosticsManager* GetDiagnostics() { return m_infra.GetDiagnostics(); }
    void SetDiagnosticsManager(CDiagnosticsManager* diagnostics) { m_infra.SetDiagnosticsManager(diagnostics); }
    CTradeAttributionManager* GetAttribution() { return m_infra.GetAttribution(); }
    void SetAttributionManager(CTradeAttributionManager* attribution)
         { m_infra.SetAttributionManager(attribution); m_attributionDelegator.SetAttribution(m_infra.GetAttribution()); }
    CStrategyHealthMonitor* GetHealthMonitor() { return m_infra.GetHealthMonitor(); }

    //--- Phase C / Slice 1: minimal read-only accessor surface consumed by
    //--- CStrategyStateReporter. These expose existing state verbatim; they add
    //--- no logic and are the only way the reporter observes this manager.
    int    GetStrategyCount() const { return m_roster.GetStrategyCount(); }
    bool   IsStrategyEnabled(const int index) const
           { return m_roster.IsStrategyEnabled(index); }
    IStrategy* GetStrategyPtr(const int index) const
           { return m_roster.GetStrategyPtr(index); }
    string GetStrategyName(const int index) const
           { return m_roster.GetStrategyName(index); }
    double GetStrategyWeight(const int index) const
           { return m_roster.GetStrategyWeight(index); }
    int    GetStrategyRole(const int index) const
           { return m_roster.GetStrategyRole(index); }
    int    GetStrategyCluster(const int index) const
           { return m_roster.GetStrategyCluster(index); }
    bool   IsStrategyLiveVotingEnabled(const int index) const
           { return m_roster.IsStrategyLiveVotingEnabled(index); }
    int    GetStrategySuccessCount(const int index) const
           { return m_roster.GetStrategySuccessCount(index); }
    int    GetStrategyFailCount(const int index) const
           { return m_roster.GetStrategyFailCount(index); }
    double GetStrategyAvgConfidence(const int index) const
           { return m_roster.GetStrategyAvgConfidence(index); }
    double GetStrategyParticipationScore(const int index) const
           { return m_roster.GetStrategyParticipationScore(index); }
    double GetStrategyHealthScore(const int index) const
           { return m_roster.GetStrategyHealthScore(index); }
    double GetStrategyRecentWinRate(const int index) const
           { return m_roster.GetStrategyRecentWinRate(index); }
    bool   GetStrategyIsLiveVoter(const int index) const { return IsStrategyLiveVoter(index); }
    CUnifiedSignalPipeline* GetPipelineConst() const { return m_infra.GetPipeline(); }
    CDiagnosticsManager*    GetDiagnosticsConst() const { return m_infra.GetDiagnostics(); }
    string GetManagedSymbol() const { return m_infra.GetManagedSymbol(); }
    int    GetTotalSignals() const { return m_signalContext.GetTotalSignals(); }
    int    GetSuccessfulSignals() const { return m_signalContext.GetSuccessfulSignals(); }
    void   GetLastDecisionContextValue(SConsensusDecisionContext &out) const
           { m_consensusEngine.GetLastDecisionContextValue(out); }
    int    GetLastCycleSignalsGeneratedValue() const { return m_signalContext.GetLastCycleSignalsGenerated(); }
    int    GetLastCycleSignalsAfterPipelineValue() const { return m_signalContext.GetLastCycleSignalsAfterPipeline(); }
    bool   GetLastCycleSignalAfterQuorumValue() const { return m_signalContext.GetLastCycleSignalAfterQuorum(); }

    //--- Phase G / G3: last-signal contributor telemetry consumed by
    //--- CStrategyMgrTradeFeedback (G6) through its m_src back-pointer. The
    //--- storage moved into CEntStrategySignalContext, so these four are the
    //--- manager-side handles the trade-feedback module reads/writes through.
    int  GetLastContributorCountValue() const { return m_signalContext.GetLastContributorCount(); }
    int  GetLastContributorArraySize() const  { return m_signalContext.GetContributorArraySize(); }
    void IncrementSuccessfulSignals()         { m_signalContext.IncrementSuccessfulSignals(); }
    void ResetLastContributorContext()        { m_signalContext.ResetContributorContext(); }

    //--- Phase C / Slice 2: additional read-only accessors consumed by
    //--- CPostConsensusValidator (C3) and CConsensusWeightingConfig (C4).
    //--- Same contract as the Slice 1 block: expose existing state verbatim,
    //--- add no logic.
    COrderFlowImbalanceEngine*   GetOFIEngineConst() const          { return m_infra.GetOFIEngine(); }
    CVPINFilter*                 GetVPINFilterConst() const         { return m_infra.GetVPINFilter(); }
    CMultiAssetProfiler*         GetMultiAssetProfilerConst() const { return m_infra.GetMultiAssetProfiler(); }
    CDerivAssetProfiler*         GetDerivProfilerConst() const      { return m_infra.GetDerivProfiler(); }
    CFamilyStrategyWeightMatrix* GetFamilyWeightMatrixConst() const { return m_infra.GetFamilyWeightMatrix(); }
    double GetStrategyAvgProfit(const int index) const
           { return m_roster.GetStrategyAvgProfit(index); }
    double GetStrategyOriginalWeight(const int index) const
           { return m_roster.GetStrategyOriginalWeight(index); }
    int    GetStrategyIndexByName(const string name) const { return FindStrategyIndexByName(name); }

    //--- Narrow raw weight mutator for C4. Mirrors exactly what
    //--- UpdateStrategyWeights() used to do inline: write the entry weight and
    //--- push it to the strategy object, WITHOUT touching the health monitor
    //--- (that is UpdateStrategyWeightByName's behaviour, deliberately distinct).
    void   ApplyRawStrategyWeight(const int index, const double weight)
           { m_roster.ApplyRawStrategyWeight(index, weight); }

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
             { return m_roster.GetStrategyTotalTrades(index); }
    int      GetStrategyWinningTrades(const int index) const
             { return m_roster.GetStrategyWinningTrades(index); }
    double   GetStrategyWinRate(const int index) const
             { return m_roster.GetStrategyWinRate(index); }
    double   GetStrategyAvgLoss(const int index) const
             { return m_roster.GetStrategyAvgLoss(index); }
    int      GetStrategyConsecutiveWins(const int index) const
             { return m_roster.GetStrategyConsecutiveWins(index); }
    int      GetStrategyConsecutiveLosses(const int index) const
             { return m_roster.GetStrategyConsecutiveLosses(index); }
    int      GetStrategyMaxConsecutiveLosses(const int index) const
             { return m_roster.GetStrategyMaxConsecutiveLosses(index); }
    int      GetStrategyRecentTradeIndex(const int index) const
             { return m_roster.GetStrategyRecentTradeIndex(index); }
    int      GetStrategyRecentTradeCount(const int index) const
             { return m_roster.GetStrategyRecentTradeCount(index); }
    double   GetStrategyRecentTrade(const int index, const int slot) const
             { return m_roster.GetStrategyRecentTrade(index, slot); }
    bool     IsStrategyTemporarilyDisabled(const int index) const
             { return m_roster.IsStrategyTemporarilyDisabled(index); }
    datetime GetStrategyDisabledUntil(const int index) const
             { return m_roster.GetStrategyDisabledUntil(index); }
    ENUM_TIMEFRAMES GetStrategyTimeframe(const int index) const
             { return m_roster.GetStrategyTimeframe(index, m_infra.GetBaseTimeframe()); }
    double   GetMinWinRateThreshold() const      { return m_quorumConfig.GetMinWinRateThreshold(); }
    int      GetMaxConsecutiveLossesLimit() const { return m_quorumConfig.GetMaxConsecutiveLossesLimit(); }
    int      GetRollingWindowSize() const        { return m_quorumConfig.GetRollingWindowSize(); }
    bool     IsManagerInitialized() const        { return m_infra.IsManagerInitialized(); }
    CFourStateRegimeDetector* GetFourStateRegimeDetectorConst() const { return m_infra.GetFourStateRegimeDetector(); }
    bool     IsRegimeDetectorInitialized() const { return m_infra.IsRegimeDetectorInitialized(); }

    //--- write half (dumb field writers, all bounds-checked)
    void SetStrategyTotalTrades(const int index, const int value)
         { m_roster.SetStrategyTotalTrades(index, value); }
    void SetStrategySuccessCount(const int index, const int value)
         { m_roster.SetStrategySuccessCount(index, value); }
    void SetStrategyFailCount(const int index, const int value)
         { m_roster.SetStrategyFailCount(index, value); }
    void SetStrategyWinningTrades(const int index, const int value)
         { m_roster.SetStrategyWinningTrades(index, value); }
    void SetStrategyConsecutiveWins(const int index, const int value)
         { m_roster.SetStrategyConsecutiveWins(index, value); }
    void SetStrategyConsecutiveLosses(const int index, const int value)
         { m_roster.SetStrategyConsecutiveLosses(index, value); }
    void SetStrategyMaxConsecutiveLosses(const int index, const int value)
         { m_roster.SetStrategyMaxConsecutiveLosses(index, value); }
    void SetStrategyAvgProfit(const int index, const double value)
         { m_roster.SetStrategyAvgProfit(index, value); }
    void SetStrategyAvgLoss(const int index, const double value)
         { m_roster.SetStrategyAvgLoss(index, value); }
    void SetStrategyWinRate(const int index, const double value)
         { m_roster.SetStrategyWinRate(index, value); }
    void SetStrategyProfitFactor(const int index, const double value)
         { m_roster.SetStrategyProfitFactor(index, value); }
    void SetStrategySharpeRatio(const int index, const double value)
         { m_roster.SetStrategySharpeRatio(index, value); }
    void SetStrategyRecentWinRate(const int index, const double value)
         { m_roster.SetStrategyRecentWinRate(index, value); }
    void SetStrategyHealthScore(const int index, const double value)
         { m_roster.SetStrategyHealthScore(index, value); }
    void SetStrategyLastUpdate(const int index, const datetime value)
         { m_roster.SetStrategyLastUpdate(index, value); }
    void SetStrategyTemporarilyDisabled(const int index, const bool value)
         { m_roster.SetStrategyTemporarilyDisabled(index, value); }
    void SetStrategyDisabledUntil(const int index, const datetime value)
         { m_roster.SetStrategyDisabledUntil(index, value); }
    //--- Writes ONLY the entry flag. It deliberately does NOT push the value to
    //--- the IStrategy object: CheckStrategyDisabling/ReEnabling never did, and
    //--- EnableStrategy/DisableStrategy push it themselves via GetStrategyPtr().
    void SetStrategyEnabledFlag(const int index, const bool value)
         { m_roster.SetStrategyEnabledFlag(index, value); }
    //--- slot bound is the fixed recentTrades[20] capacity; unreachable in
    //--- practice because m_rollingWindowSize is fixed at 20 (no setter).
    void SetStrategyRecentTrade(const int index, const int slot, const double value)
         { m_roster.SetStrategyRecentTrade(index, slot, value); }
    void SetStrategyRecentTradeIndex(const int index, const int value)
         { m_roster.SetStrategyRecentTradeIndex(index, value); }
    void SetStrategyRecentTradeCount(const int index, const int value)
         { m_roster.SetStrategyRecentTradeCount(index, value); }
    void SetStrategyLastSignal(const int index, const ENUM_TRADE_SIGNAL value)
         { m_roster.SetStrategyLastSignal(index, value); }
    void SetStrategyLastSignalConfidence(const int index, const double value)
         { m_roster.SetStrategyLastSignalConfidence(index, value); }

    //--- Phase C / Slice 5: accessor surface consumed by CConsensusEngine (C9).
    //--- Same contract as Slice 1/2/3: every accessor exposes exactly one
    //--- existing field verbatim and adds no logic. The consensus core READS
    //--- the enable / live-voting / intrabar-policy flags through here; it does
    //--- NOT own them (they are written by registration, lifecycle and the
    //--- governance setters, all of which stay in this manager). The single
    //--- mutator, SetAdxHandleCached, exists only because IsTrendingRegime()
    //--- lazily caches the ADX handle exactly as the original inline body did.
    CTimeframeConsistency* GetTFConsistencyConst() const   { return m_infra.GetTFConsistency(); }
    CStrategyRegistry*     GetStrategyRegistryConst() const { return m_infra.GetStrategyRegistry(); }
    ENUM_TIMEFRAMES        GetBaseTimeframe() const         { return m_infra.GetBaseTimeframe(); }

    int    GetStrategyIntrabarPolicyRaw(const int index) const
           { return m_roster.GetStrategyIntrabarPolicyRaw(index); }
    bool   GetStrategyIntrabarEligible(const int index) const
           { return m_roster.GetStrategyIntrabarEligible(index); }
    bool   IsStrategyProbeEligible(const int index) const
           { return m_roster.IsStrategyProbeEligible(index); }
    double GetStrategyReadinessScore(const int index) const
           { return m_roster.GetStrategyReadinessScore(index); }
    double GetStrategyContextScore(const int index) const
           { return m_roster.GetStrategyContextScore(index); }
    double GetStrategyCostScore(const int index) const
           { return m_roster.GetStrategyCostScore(index); }

    //--- consensus configuration (GetMinQuorum() already exists above)
    int    GetIntrabarMinQuorum() const              { return m_quorumConfig.GetIntrabarMinQuorum(); }
    bool   IsIntrabarDynamicQuorumEnabled() const    { return m_quorumConfig.IsIntrabarDynamicQuorumEnabled(); }
    double GetQuorumThreshold() const                { return m_quorumConfig.GetQuorumThreshold(); }
    double GetPipelineMinConfidence() const          { return m_quorumConfig.GetPipelineMinConfidence(); }
    double GetConflictDeadband() const               { return m_quorumConfig.GetConflictDeadband(); }
    double GetMinReadyWeightRatio() const            { return m_quorumConfig.GetMinReadyWeightRatio(); }
    double GetSupportFloorNewBar() const             { return m_quorumConfig.GetSupportFloorNewBar(); }
    double GetSupportFloorIntrabar() const           { return m_quorumConfig.GetSupportFloorIntrabar(); }
    double GetSparseIntrabarMinQuality() const       { return m_quorumConfig.GetSparseIntrabarMinQuality(); }
    double GetSparseIntrabarMinSupportRatio() const  { return m_quorumConfig.GetSparseIntrabarMinSupportRatio(); }

    //--- participation score formula parameters (L6-008)
    double GetParticipationFormulaBase() const       { return m_quorumConfig.GetParticipationFormulaBase(); }
    double GetParticipationFormulaCoeff() const      { return m_quorumConfig.GetParticipationFormulaCoeff(); }
    double GetParticipationFormulaMin() const        { return m_quorumConfig.GetParticipationFormulaMin(); }
    double GetParticipationFormulaMax() const        { return m_quorumConfig.GetParticipationFormulaMax(); }

    //--- cached ADX handle (Batch 116) read/write half for IsTrendingRegime()
    int    GetAdxHandleCached() const                { return m_infra.GetAdxHandleCached(); }
    void   SetAdxHandleCached(const int handle)      { m_infra.SetAdxHandleCached(handle); }

    // Initialization
    bool Initialize(const string symbol, ENUM_TIMEFRAMES timeframe, 
                   bool usePipeline = true,
                   CTradeManager* tradeManagerPtr = NULL, CPositionSizer* positionSizerPtr = NULL,
                   CUnifiedRiskManager* unifiedRiskManagerPtr = NULL,
                   const long managedMagic = 0);
    
    // L1-004: Set strategy registry (replaces global singleton)
    void SetStrategyRegistry(CStrategyRegistry* registry) { m_infra.SetStrategyRegistry(registry); }
    
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
    void SetManagedMagicRangeMax(long rangeMax) { m_tradeFeedback.SetManagedMagicRangeMax(rangeMax); }
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
    int    GetMaxStrategies() const { return m_roster.GetMaxStrategies(); }
    CTradeManager*        GetTradeManagerConst() const { return m_infra.GetTradeManager(); }
    CPositionSizer*       GetPositionSizerConst() const { return m_infra.GetPositionSizer(); }
    CUnifiedRiskManager*  GetUnifiedRiskManagerConst() const { return m_infra.GetUnifiedRiskManager(); }
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
//--- Phase G: the whole initialiser list moved with the state it initialised.
//--- Every former scalar now lives in the module that owns it and is set by
//--- that module's own constructor, VERBATIM:
//---   CStrategyMgrInfrastructure() - collaborator pointers, m_symbol,
//---       m_baseTimeframe, m_initialized, m_usePipeline, m_adxHandleCached,
//---       m_diagnostics, m_attribution, m_healthMonitor, m_drawingManager;
//---   CStrategyMgrRoster()         - m_strategyCount(0), m_maxStrategies(25)
//---                                  and ArrayResize(m_strategies, 0);
//---   CEntStrategyQuorumConfig()   - the entire quorum / adaptation /
//---       participation block, INCLUDING the [PROFIT-02] conflict deadband
//---       (0.35) and the two [PROFIT-11] support floors (0.30 / 0.25), which
//---       are carried over byte-for-byte together with their marker comments;
//---   CEntStrategySignalContext()  - m_totalSignals, m_successfulSignals,
//---       m_avgConfidence, m_currentMarketRegime, the last-signal tags and
//---       ArrayResize of both contributor arrays;
//---   CStrategyMgrTradeFeedback()  - m_managedMagic, m_managedMagicRangeMax;
//---   CIntrabarPolicy()            - the 32-slot policy table reset to
//---                                  INTRABAR_POLICY_OFF.
//--- Phase C / Slice 2: the post-consensus validator config block (including
//--- the 15000-pt hard spread cutoff bugfix default) is likewise initialised by
//--- CPostConsensusValidator's own constructor.
CEnterpriseStrategyManager::CEnterpriseStrategyManager()
{
    // L1-007: Create component instances. m_diagnostics / m_attribution stay
    // NULL (injected from EAOrchestrator); the health monitor is allocated by
    // the infrastructure module exactly as the inline constructor used to do.
    m_infra.AllocateHealthMonitor();

    // Phase C / Slice 1: bind extracted collaborators at the earliest safe point.
    // The reporter observes this manager read-only; the delegator mirrors the
    // (still NULL) attribution pointer and is re-bound by SetAttributionManager().
    m_stateReporter.SetSource(GetPointer(this));
    m_attributionDelegator.SetAttribution(m_infra.GetAttribution());

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

    // Phase C / Slice 4: same binding site. Both were previously left unbound
    // because the manager still carried the inline bodies; now that those
    // bodies are forwarders, the back-pointers must be live.
    m_intrabarPolicy.SetSource(GetPointer(this));
    m_registryState.SetSource(GetPointer(this));

    // Phase C / Slice 5: same binding site. The consensus engine re-reads the
    // pipeline / registry / diagnostics from this manager on every call and
    // mirrors no injected pointer, so it needs no re-sync on Deinit either.
    m_consensusEngine.SetSource(GetPointer(this));

    // Phase G / G6: the trade-feedback module reads the manager's symbol,
    // attribution, health monitor and contributor telemetry through m_src.
    m_tradeFeedback.SetSource(GetPointer(this));
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CEnterpriseStrategyManager::~CEnterpriseStrategyManager()
{
    // Phase G / G4: the strategy teardown loop moved to the roster (identical
    // in both call sites). Note the destructor deliberately does NOT reset
    // m_strategyCount / resize the array afterwards - only Deinit() did that,
    // so ClearRoster() is intentionally not called here.
    m_roster.DeleteAllStrategies();

    // Phase G / G5: pipeline, cached ADX handle, FourStateRegimeDetector,
    // TimeframeConsistency and the health monitor are released in the exact
    // original order. m_diagnostics / m_attribution are injected from
    // EAOrchestrator and are deliberately NOT deleted here.
    m_infra.ReleaseOnDestruct();
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
    // Phase G / G6: Initialize() seeded BOTH magic fields from the same
    // argument (m_managedMagic = m_managedMagicRangeMax = managedMagic);
    // SetManagedMagic() reproduces that exactly.
    m_tradeFeedback.SetManagedMagic(managedMagic);

    // Phase G / G5: the two-phase bring-up (symbol/timeframe/pipeline flag and
    // the injected trade manager, position sizer and unified risk manager;
    // Phase 1 pipeline + TimeframeConsistency with their rollback paths;
    // health-monitor re-allocation seeded from the quorum config; Phase 2
    // FourStateRegimeDetector) moved verbatim into the infrastructure module.
    // The quorum config is passed by reference because the health monitor is
    // seeded from GetMinWinRateThreshold / GetMaxConsecutiveLossesLimit /
    // GetPerformanceDecayFactor / GetRollingWindowSize / GetMaxDrawdownLimit /
    // GetStrategyActivityDecayRate / GetStrategyInactiveCounterThreshold.
    return m_infra.Initialize(symbol, timeframe, usePipeline,
                              tradeManagerPtr, positionSizerPtr, unifiedRiskManagerPtr,
                              m_quorumConfig);
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
    // Phase C / Slice 4 (C8): the whole registration sequence (initialized
    // guard, registry mode-filter override, max-strategy cap, strategy Init /
    // InitializeAI / ValidateRiskManagerInjection, enabled+weight push, the
    // 35-field append via AppendRegisteredStrategyEntry and the summary Print)
    // moved verbatim into CStrategyRegistryState::RegisterStrategy().
    return m_registryState.RegisterStrategy(strategy, name, enabled, weight, tier, tf,
                                            intrabarPolicy, role, cluster, liveVotingEnabled);
}

//+------------------------------------------------------------------+
//| Configuration Setters - Store in mirrored config variables       |
//+------------------------------------------------------------------+
void CEnterpriseStrategyManager::SetMinQuorum(int quorum)
{
    m_quorumConfig.SetMinQuorum(quorum);
}

void CEnterpriseStrategyManager::SetIntrabarMinQuorum(int quorum)
{
    m_quorumConfig.SetIntrabarMinQuorum(quorum);
}

void CEnterpriseStrategyManager::SetIntrabarDynamicQuorumEnabled(const bool enabled)
{
    m_quorumConfig.SetIntrabarDynamicQuorumEnabled(enabled);
}

void CEnterpriseStrategyManager::SetIntrabarSingleVoterMinConfidence(const double minConfidence)
{
    m_quorumConfig.SetIntrabarSingleVoterMinConfidence(minConfidence);
}

void CEnterpriseStrategyManager::SetQuorumThreshold(const double threshold)
{
    m_quorumConfig.SetQuorumThreshold(threshold);
}

void CEnterpriseStrategyManager::SetConflictDeadband(const double deadband)
{
    m_quorumConfig.SetConflictDeadband(deadband);
}

void CEnterpriseStrategyManager::SetMinReadyWeightRatio(const double ratio)
{
    m_quorumConfig.SetMinReadyWeightRatio(ratio);
}

void CEnterpriseStrategyManager::SetSupportFloors(const double newBarFloor, const double intrabarFloor)
{
    m_quorumConfig.SetSupportFloors(newBarFloor, intrabarFloor);
}

void CEnterpriseStrategyManager::SetSparseIntrabarThresholds(const double minQuality,
                                     const double minSupportRatio,
                                     const double minReadyCoverage)
{
    m_quorumConfig.SetSparseIntrabarThresholds(minQuality, minSupportRatio, minReadyCoverage);
}

void CEnterpriseStrategyManager::SetAllowSparseIntrabarSingleVoter(const bool enabled)
{
    m_quorumConfig.SetAllowSparseIntrabarSingleVoter(enabled);
}

// Intrabar policy configuration per strategy index (L6-007)
void CEnterpriseStrategyManager::SetStrategyIntrabarPolicyConfig(int strategyIndex, ENUM_INTRABAR_POLICY policy)
{
    // Phase C / Slice 4 (C6): the 32-slot policy table lives in CIntrabarPolicy.
    m_intrabarPolicy.SetStrategyIntrabarPolicyConfig(strategyIndex, policy);
}

ENUM_INTRABAR_POLICY CEnterpriseStrategyManager::GetStrategyIntrabarPolicyConfig(int strategyIndex) const
{
    // Phase C / Slice 4 (C6): bounds check + INTRABAR_POLICY_OFF default moved.
    return m_intrabarPolicy.GetStrategyIntrabarPolicyConfig(strategyIndex);
}

// Participation formula configuration (L6-008)
void CEnterpriseStrategyManager::SetParticipationFormulaBase(const double base)
{
    m_quorumConfig.SetParticipationFormulaBase(base);
}
void CEnterpriseStrategyManager::SetParticipationFormulaCoeff(const double coeff)
{
    m_quorumConfig.SetParticipationFormulaCoeff(coeff);
}
void CEnterpriseStrategyManager::SetParticipationFormulaMin(const double minVal)
{
    m_quorumConfig.SetParticipationFormulaMin(minVal);
}
void CEnterpriseStrategyManager::SetParticipationFormulaMax(const double maxVal)
{
    m_quorumConfig.SetParticipationFormulaMax(maxVal);
}

void CEnterpriseStrategyManager::SetConsensusDiagnosticsIntervalSeconds(const int seconds)
{
    m_infra.SetConsensusDiagnosticsIntervalSeconds(seconds);
}

int CEnterpriseStrategyManager::GetMinQuorum() const
{
    return m_quorumConfig.GetMinQuorum();
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
    // Phase C / Slice 4 (C6): table lookup + the idx 9/10 LIVE defaults moved.
    return m_intrabarPolicy.GetIntrabarPolicyHelper(idx);
}

// Batch 145: the hand-written if-chain is replaced by one pass over the
// shared catalog (Core/Strategy/StrategyCatalog.mqh). Gate order, weights,
// tiers, clusters, intrabar policies and both Statistical Arbitrage log
// lines are preserved exactly as the if-chain emitted them.
void CEnterpriseStrategyManager::AutoRegisterStrategies(bool &flags[])
{
    BuildStrategyCatalog();
    CatalogLogIndexAudit();

    const int    size     = ArraySize(flags);
    const bool   bridgeUp = (g_pythonBridge != NULL && g_pythonBridge.IsConnected());
    const string sym      = GetManagedSymbol();

    for(int i = 0; i < g_strategyCatalogCount; i++)
    {
        if(g_strategyCatalog[i].kind != CAT_KIND_INDICATOR)
            continue;
        if(!CatalogSymbolAllowed(i, sym))
            continue;

        // Hard prerequisite gate (Statistical Arbitrage needs the Python bridge)
        if(g_strategyCatalog[i].requiresPythonBridge)
        {
            if(!bridgeUp)
            {
                Print("[EnterpriseStrategyManager] Python Bridge not available - Skipping Statistical Arbitrage registration");
                continue;
            }
        }

        // Legacy enable-flag gate (literal indices preserved verbatim)
        const int fi = g_strategyCatalog[i].flagsIndex;
        if(fi >= 0 && !(size > fi && flags[fi]))
        {
            if(g_strategyCatalog[i].requiresPythonBridge)
                Print("[EnterpriseStrategyManager] Python Bridge available - Statistical Arbitrage strategy registered");
            continue;
        }

        IStrategy* s = NULL;
        if(g_strategyCatalogCreators[i] != NULL)
            s = g_strategyCatalogCreators[i]();
        if(s == NULL)
        {
            PrintFormat("[CATALOG] creator returned NULL for %s", g_strategyCatalog[i].name);
            continue;
        }

        const int pIdx = g_strategyCatalog[i].policyIndex;
        ENUM_INTRABAR_POLICY pol = (pIdx >= 0) ? GetIntrabarPolicyHelper(pIdx)
                                               : g_strategyCatalog[i].fixedPolicy;

        RegisterStrategy(s, g_strategyCatalog[i].name, true, g_strategyCatalog[i].weight,
                         g_strategyCatalog[i].tier, g_strategyCatalog[i].timeframe, pol,
                         g_strategyCatalog[i].role, g_strategyCatalog[i].cluster,
                         g_strategyCatalog[i].liveVoting);

        if(g_strategyCatalog[i].requiresPythonBridge)
            Print("[EnterpriseStrategyManager] Python Bridge available - Statistical Arbitrage strategy registered");
    }

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
    // Phase G / G2: cache pipeline base confidence floor for quorum eligibility
    // even if the pipeline is disabled (identical MathMax/MathMin clamp).
    m_quorumConfig.CachePipelineMinConfidence(settings.confidence.minConfidence);

    // Phase G / G5: the pipeline NULL-guard, SetFilters() call and the summary
    // Print moved verbatim into the infrastructure module.
    m_infra.ApplyPipelineFilters(settings);
}

//+------------------------------------------------------------------+
//| Set Orchestrator Mode                                            |
//+------------------------------------------------------------------+
void CEnterpriseStrategyManager::SetOrchestratorMode(double minWinRate, int maxLosses)
{
    // Phase G / G2: both adaptation thresholds and the summary PrintFormat
    // moved verbatim into the quorum-config module.
    m_quorumConfig.SetOrchestratorMode(minWinRate, maxLosses);
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
    // Phase G / G4: lookup, 0..10 weight clamp, entry + IStrategy::SetWeight
    // push and the health-monitor sync moved verbatim into the roster. The
    // health monitor is owned by G5, so it is passed in explicitly.
    return m_roster.UpdateStrategyWeightByName(name, weight, m_infra.GetHealthMonitor());
}

bool CEnterpriseStrategyManager::SetStrategyIntrabarEligibilityByName(const string name, bool enabled)
{
    // Phase C / Slice 4 (C6): same LIVE/OFF mapping, now inside CIntrabarPolicy.
    return m_intrabarPolicy.SetStrategyIntrabarEligibilityByName(name, enabled);
}

bool CEnterpriseStrategyManager::SetStrategyIntrabarPolicyByName(const string name, ENUM_INTRABAR_POLICY policy)
{
    // Phase C / Slice 4 (C6): lookup, raw-policy + eligibility write and the
    // PrintFormat moved verbatim into CIntrabarPolicy.
    return m_intrabarPolicy.SetStrategyIntrabarPolicyByName(name, policy);
}

bool CEnterpriseStrategyManager::SetStrategyRoleByName(const string name, ENUM_STRATEGY_ROLE role)
{
    // Phase C / Slice 4 (C8): lookup, role write and PrintFormat moved verbatim.
    return m_registryState.SetStrategyRoleByName(name, role);
}

bool CEnterpriseStrategyManager::SetStrategyClusterByName(const string name, ENUM_STRATEGY_CLUSTER cluster)
{
    // Phase C / Slice 4 (C8): lookup, cluster write and PrintFormat moved verbatim.
    return m_registryState.SetStrategyClusterByName(name, cluster);
}

bool CEnterpriseStrategyManager::SetStrategyLiveVotingEligibilityByName(const string name, const bool enabled)
{
    // Phase C / Slice 4 (C8): lookup, live-vote write and PrintFormat moved.
    return m_registryState.SetStrategyLiveVotingEligibilityByName(name, enabled);
}

//+------------------------------------------------------------------+
//| Phase C / Slice 4 (C8): per-field accessors for slice modules    |
//+------------------------------------------------------------------+
void CEnterpriseStrategyManager::SetStrategyRole(int index, int role)
{
    m_roster.SetStrategyRole(index, role);
}

void CEnterpriseStrategyManager::SetStrategyCluster(int index, int cluster)
{
    m_roster.SetStrategyCluster(index, cluster);
}

void CEnterpriseStrategyManager::SetStrategyLiveVotingEnabled(int index, bool enabled)
{
    m_roster.SetStrategyLiveVotingEnabled(index, enabled);
}

void CEnterpriseStrategyManager::SetStrategyIntrabarPolicyRaw(int index, int policy)
{
    m_roster.SetStrategyIntrabarPolicyRaw(index, policy);
}

void CEnterpriseStrategyManager::SetStrategyIntrabarEligible(int index, bool eligible)
{
    m_roster.SetStrategyIntrabarEligible(index, eligible);
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
    // Phase G / G4: the ArrayResize, all 35 StrategyEntry field writes, the three
    // ArrayInitialize calls and the m_strategyCount++ moved verbatim into the
    // roster. The health monitor is owned by G5, so it is passed in explicitly
    // (the roster performs the same NULL-guarded RegisterStrategy(weight) call).
    m_roster.AppendRegisteredStrategyEntry(strategy, name, enabled, weight, tier,
                                           resolvedTf, intrabarPolicy, role, cluster,
                                           liveVotingEnabled, m_infra.GetHealthMonitor());
}

bool CEnterpriseStrategyManager::SetStrategyConfidenceThresholdByName(const string name, const double threshold)
{
    // Phase G / G4: lookup, NULL-strategy guard and SetConfidenceThreshold moved.
    return m_roster.SetStrategyConfidenceThresholdByName(name, threshold);
}


bool CEnterpriseStrategyManager::SetStrategyGovernanceByName(const string name,
                                                             ENUM_STRATEGY_ROLE role,
                                                             ENUM_STRATEGY_CLUSTER cluster,
                                                             const bool liveVotingEnabled)
{
    // Phase C / Slice 4 (C8): lookup, the three governance writes and the
    // PrintFormat moved verbatim into CStrategyRegistryState.
    return m_registryState.SetStrategyGovernanceByName(name, role, cluster, liveVotingEnabled);
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
    m_signalContext.GetLastSignalContributors(contributors);
}

void CEnterpriseStrategyManager::GetLastSignalContributorIndices(int &indices[]) const
{
    m_signalContext.GetLastSignalContributorIndices(indices);
}

bool CEnterpriseStrategyManager::GetLastSignalExecutionContext(string &roleTag,
                                                               string &clusterTag,
                                                               string &clusterCode,
                                                               string &contributorsCsv) const
{
    // Phase G / G3: the role/cluster tags and contributor CSV live in the
    // signal-context module. JoinContributors() is itself a forwarder to
    // m_attributionDelegator, so the delegator is handed over directly.
    return m_signalContext.GetLastSignalExecutionContext(m_attributionDelegator,
                                                         roleTag, clusterTag,
                                                         clusterCode, contributorsCsv);
}

//+------------------------------------------------------------------+
//| Explicit Deinitialization                                        |
//| Called before destructor to ensure proper cleanup order          |
//+------------------------------------------------------------------+
void CEnterpriseStrategyManager::Deinit()
{
    // Phase G / G4: strategy teardown loop, then the Deinit-only roster reset
    // (m_strategyCount = 0; ArrayResize(m_strategies, 0)) the destructor omits.
    m_roster.DeleteAllStrategies();
    m_roster.ClearRoster();

    // Phase G / G5: pipeline, ADX handle, regime detector, TF consistency,
    // diagnostics and attribution - in the original order. Unlike the
    // destructor, Deinit() DOES delete the injected diagnostics/attribution.
    m_infra.ReleaseOnDeinit();

    // Phase C / Slice 1: keep the delegator's mirrored pointer from dangling.
    m_attributionDelegator.SetAttribution(m_infra.GetAttribution());

    // Phase G / G5: health monitor teardown + m_initialized = false.
    m_infra.FinishDeinit();
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
    // Phase G / G4: identical linear name scan, now over the roster's array.
    return m_roster.FindStrategyIndexByName(name);
}

//+------------------------------------------------------------------+
//| Get Strategy By Name �?Batch 103: returns strategy pointer       |
//+------------------------------------------------------------------+
IStrategy* CEnterpriseStrategyManager::GetStrategyByName(const string name)
{
    // Phase C / Slice 4 (C8): same lookup + bounds guard + pointer return.
    return m_registryState.GetStrategyByName(name);
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
    // Phase G / G6: the whole DEAL_ADD funnel (magic/symbol ownership guards,
    // entry-side UpsertPositionAttribution, the partial-close guard, the
    // net-profit computation, the per-contributor UpdatePerformance +
    // health-monitor RecordTradeResult loop, the contributor-context reset and
    // the "Trade Closed" PrintFormat) moved verbatim into the trade-feedback
    // module, which reads this manager back through its m_src back-pointer.
    m_tradeFeedback.OnTradeTransaction(trans, request, result);
}

bool CEnterpriseStrategyManager::IsPositionIdStillOpen(const ulong positionId) const
{
    // Phase G / G6: identical PositionsTotal() scan on POSITION_IDENTIFIER.
    return m_tradeFeedback.IsPositionIdStillOpen(positionId);
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
    // Phase G / G6: identical exact-match + [magic, rangeMax] window test.
    return m_tradeFeedback.IsEAOwnedMagic(magic);
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
    return m_infra.GetPipeline();
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
    return m_signalContext.GetCurrentMarketRegime();
}

//+------------------------------------------------------------------+
//| Set Drawing Manager                                              |
//+------------------------------------------------------------------+
void CEnterpriseStrategyManager::SetDrawingManager(CChartDrawingManager* drawingManager)
{
    m_infra.SetDrawingManager(drawingManager);
}

//+------------------------------------------------------------------+
//| Get Drawing Manager                                              |
//+------------------------------------------------------------------+
CChartDrawingManager* CEnterpriseStrategyManager::GetDrawingManager()
{
    return m_infra.GetDrawingManager();
}

//+------------------------------------------------------------------+
//| Set Deriv Profiler                                               |
//+------------------------------------------------------------------+
void CEnterpriseStrategyManager::SetDerivProfiler(CDerivAssetProfiler* profiler)
{
    m_infra.SetDerivProfiler(profiler);
}

//+------------------------------------------------------------------+
//| Set Family Weight Matrix                                         |
//+------------------------------------------------------------------+
void CEnterpriseStrategyManager::SetFamilyWeightMatrix(CFamilyStrategyWeightMatrix* famMatrix)
{
    m_infra.SetFamilyWeightMatrix(famMatrix);
}

//+------------------------------------------------------------------+
//| Set Multi-Asset Profiler                                         |
//+------------------------------------------------------------------+
void CEnterpriseStrategyManager::SetMultiAssetProfiler(CMultiAssetProfiler* profiler)
{
    m_infra.SetMultiAssetProfiler(profiler);
}

//+------------------------------------------------------------------+
//| Set VPIN Filter                                                  |
//+------------------------------------------------------------------+
void CEnterpriseStrategyManager::SetVPINFilter(CVPINFilter* vpin)
{
    m_infra.SetVPINFilter(vpin);
}

//+------------------------------------------------------------------+
//| Set OFI Engine                                                   |
//+------------------------------------------------------------------+
void CEnterpriseStrategyManager::SetOFIEngine(COrderFlowImbalanceEngine* ofi)
{
    m_infra.SetOFIEngine(ofi);
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
