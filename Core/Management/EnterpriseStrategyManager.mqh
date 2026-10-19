// Symbol-scoped strategy manager: roster, consensus entry points and the validator boundary for one managed symbol
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

// Required here: the modules included below need the concrete strategy types.
#include "../Strategy/StrategyCatalog.mqh"

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
class CFourStateRegimeDetector;

#include "../Strategy/StrategyRegistry.mqh"

class CStrategyRegistry;

// Must sit after the registry include and before the module includes: they need struct StrategyEntry and the enum->text helpers.
#include "EntStrategyTypes.mqh"

// Held by value as members, so these types must be complete here; their bodies resolve the manager type later.
#include "StrategyStateReporter.mqh"
#include "AttributionDelegator.mqh"
#include "PostConsensusValidator.mqh"
#include "ConsensusWeightingConfig.mqh"
#include "StrategyPerformanceHealth.mqh"
#include "StrategyLifecycle.mqh"
#include "IntrabarPolicy.mqh"
#include "StrategyRegistryState.mqh"
#include "ConsensusEngine.mqh"

// Include order is load-bearing: StrategyMgrInfrastructure::Initialize() takes CEntStrategyQuorumConfig by reference,
// StrategyMgrRoster stores StrategyEntry[], EntStrategySignalContext takes CAttributionDelegator by const reference.
#include "EntStrategyQuorumConfig.mqh"
#include "EntStrategySignalContext.mqh"   // last-signal + cycle telemetry
#include "StrategyMgrRoster.mqh"
#include "StrategyMgrInfrastructure.mqh"
#include "StrategyMgrTradeFeedback.mqh"   // magic ownership window + trade feedback

class CEnterpriseStrategyManager
{
private:
    CStrategyStateReporter m_stateReporter;      // read-only telemetry / JSON reporting
    CAttributionDelegator  m_attributionDelegator;

    CPostConsensusValidator  m_postConsensusValidator;
    CConsensusWeightingConfig m_weightingConfig;

    CStrategyPerformanceHealth m_performanceHealth;
    CStrategyLifecycle         m_lifecycle;          // enable/disable lifecycle, per-bar transitions

    CIntrabarPolicy        m_intrabarPolicy;
    CStrategyRegistryState m_registryState;

    CConsensusEngine       m_consensusEngine;        // consensus core; owns m_lastDecisionContext

    // All state lives in these value-owned collaborators; the manager itself holds no data.
    CEntStrategyQuorumConfig   m_quorumConfig;
    CEntStrategySignalContext  m_signalContext;
    CStrategyMgrRoster         m_roster;
    CStrategyMgrInfrastructure m_infra;
    CStrategyMgrTradeFeedback  m_tradeFeedback;      // magic ownership window + trade feedback

    // Inputs a strategy's Init reads for itself, so they have to be applied before RegisterStrategy calls
    // Init; the dependency pass that runs after registration is too late for these. Defaults are the
    // values the strategy classes carry today, so an unset manager behaves as it did.
    struct SConstructionInputs
    {
        bool candlestickRequireTrend;
        bool momentumScalping;
        int  momentumScalpCooldownSec;
        SConstructionInputs() : candlestickRequireTrend(true), momentumScalping(false), momentumScalpCooldownSec(20) {}
    };
    SConstructionInputs m_constructionInputs;

    void ConfigureBeforeInit(IStrategy* strategy, const string name);

    bool IsPositionIdStillOpen(const ulong positionId) const;
    int FindStrategyIndexByName(const string name) const;
    int FindAttributionIndexByPositionId(const ulong positionId) const;
    string JoinContributors(const string &contributors[]) const;
    void SplitContributors(const string csv, string &contributors[]) const;
    void UpsertPositionAttribution(const ulong positionId, const string &contributors[]);
    bool PopPositionAttribution(const ulong positionId, string &contributors[]);
    //--- CStrategyStateReporter consumes this via GetStrategyIsLiveVoter().
    bool IsStrategyLiveVoter(const int strategyIndex) const;

    static string ConsensusDecisionClassToString(ENUM_CONSENSUS_DECISION_CLASS decisionClass);

    //--- Result type must be the top-level SPostConsensusValidation: a nested SValidationResult would
    //--- shadow the unrelated global SValidationResult from Core/Utils/Enums.mqh.
public:
    SPostConsensusValidation ValidateSignal(const string symbol, ENUM_TRADE_SIGNAL signal, double confidence,
                                            int confluence, ENUM_SIGNAL_EVAL_MODE evalMode,
                                            const SConsensusDecisionContext& ctx,
                                            ulong scanCycleId, const string corrId = "");
    string GetValidationStatusReport() const;

    void SetValidatorConfig(double intrabarMinQuality, double newBarMinQuality, double hardSpreadCutoff,
                           bool spikeHunterEnabled, bool enableOFI, bool enableVPIN,
                           double baseSpreadATRRatio, double syntheticSpreadATRRatio);

public:
    CEnterpriseStrategyManager();
    ~CEnterpriseStrategyManager();
    
    CDiagnosticsManager* GetDiagnostics() { return m_infra.GetDiagnostics(); }
    void SetDiagnosticsManager(CDiagnosticsManager* diagnostics) { m_infra.SetDiagnosticsManager(diagnostics); }
    CTradeAttributionManager* GetAttribution() { return m_infra.GetAttribution(); }
    void SetAttributionManager(CTradeAttributionManager* attribution)
         { m_infra.SetAttributionManager(attribution); m_attributionDelegator.SetAttribution(m_infra.GetAttribution()); }
    CStrategyHealthMonitor* GetHealthMonitor() { return m_infra.GetHealthMonitor(); }

    //--- Read-only accessors: how CStrategyStateReporter observes the manager.
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

    //--- Last-signal contributor telemetry read by CStrategyMgrTradeFeedback through its m_src back-pointer.
    void IncrementSuccessfulSignals()         { m_signalContext.IncrementSuccessfulSignals(); }
    void ResetLastContributorContext()        { m_signalContext.ResetContributorContext(); }

    //--- Called by the consensus engine when a decision is accepted. Names come from the roster so
    //--- the attribution keys match GetStrategyIndexByName; role/cluster tags are the engine's.
    void SetLastSignalContributors(const int &indices[], const string roleTag,
                                   const string clusterTag, const string clusterCodeTag)
    {
        string names[];
        ArrayResize(names, 0);
        for(int i = 0; i < ArraySize(indices); i++)
        {
            string name = m_roster.GetStrategyName(indices[i]);
            if(name == "") continue;
            int n = ArraySize(names);
            ArrayResize(names, n + 1);
            names[n] = name;
        }
        m_signalContext.SetContributors(names, indices, GetManagedSymbol(), TimeCurrent(),
                                        roleTag, clusterTag, clusterCodeTag);
    }

    //--- Attribute the fill the EA actually got, keyed by its positionId. The cached contributor
    //--- list belongs to whichever decision ran last, so the send-time indices are the only key
    //--- that cannot drift by a cycle.
    void AttributeExecutedPosition(const ulong positionId, const int &indices[])
    {
        string names[];
        ArrayResize(names, 0);
        for(int i = 0; i < ArraySize(indices); i++)
        {
            string name = m_roster.GetStrategyName(indices[i]);
            if(name == "") continue;
            int n = ArraySize(names);
            ArrayResize(names, n + 1);
            names[n] = name;
        }
        if(ArraySize(names) == 0)
            return;
        m_attributionDelegator.UpsertPositionAttribution(positionId, names);
        // Denominator of the "Success Rate" the state reporter prints, so it counts the trades that
        // can close - a decision refused between here and the send would inflate it.
        m_signalContext.IncrementTotalSignals();
        PrintFormat("[TRADE-ATTRIBUTION] %s | position=%I64u | contributors=%s",
                    GetManagedSymbol(), positionId, m_attributionDelegator.JoinContributors(names));
    }

    //--- Read-only accessors consumed by CPostConsensusValidator and CConsensusWeightingConfig.
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

    //--- Narrow raw weight mutator: writes the entry weight and pushes it to the strategy object,
    //--- deliberately NOT touching the health monitor (UpdateStrategyWeightByName does that).
    void   ApplyRawStrategyWeight(const int index, const double weight)
           { m_roster.ApplyRawStrategyWeight(index, weight); }

    //--- Accessor surface consumed by CStrategyPerformanceHealth and CStrategyLifecycle.

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

    //--- Field writers; all bounds-checked.
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
    //--- Writes ONLY the entry flag; deliberately does NOT push to the IStrategy object, unlike
    //--- EnableStrategy/DisableStrategy which push it themselves via GetStrategyPtr().
    void SetStrategyEnabledFlag(const int index, const bool value)
         { m_roster.SetStrategyEnabledFlag(index, value); }
    //--- Slot bound is the fixed recentTrades[20] capacity; m_rollingWindowSize is fixed at 20 (no setter).
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

    //--- Accessors consumed by CConsensusEngine: it READS the enable / live-voting / intrabar-policy
    //--- flags here but does NOT own them.
    CTimeframeConsistency* GetTFConsistencyConst() const   { return m_infra.GetTFConsistency(); }
    CStrategyRegistry*     GetStrategyRegistryConst() const { return m_infra.GetStrategyRegistry(); }
    ENUM_TIMEFRAMES        GetBaseTimeframe() const         { return m_infra.GetBaseTimeframe(); }

    int    GetStrategyIntrabarPolicyRaw(const int index) const
           { return m_roster.GetStrategyIntrabarPolicyRaw(index); }

    int    GetIntrabarMinQuorum() const              { return m_quorumConfig.GetIntrabarMinQuorum(); }
    bool   IsIntrabarDynamicQuorumEnabled() const    { return m_quorumConfig.IsIntrabarDynamicQuorumEnabled(); }
    double GetQuorumThreshold() const                { return m_quorumConfig.GetQuorumThreshold(); }
    double GetPipelineMinConfidence() const          { return m_quorumConfig.GetPipelineMinConfidence(); }
    double GetConflictDeadband() const               { return m_quorumConfig.GetConflictDeadband(); }
    double GetMinReadyWeightRatio() const            { return m_quorumConfig.GetMinReadyWeightRatio(); }
    double GetSupportFloorNewBar() const             { return m_quorumConfig.GetSupportFloorNewBar(); }
    double GetSupportFloorIntrabar() const           { return m_quorumConfig.GetSupportFloorIntrabar(); }

    double GetParticipationFormulaBase() const       { return m_quorumConfig.GetParticipationFormulaBase(); }
    double GetParticipationFormulaCoeff() const      { return m_quorumConfig.GetParticipationFormulaCoeff(); }
    double GetParticipationFormulaMin() const        { return m_quorumConfig.GetParticipationFormulaMin(); }
    double GetParticipationFormulaMax() const        { return m_quorumConfig.GetParticipationFormulaMax(); }

    bool Initialize(const string symbol, ENUM_TIMEFRAMES timeframe, 
                   bool usePipeline = true,
                   CTradeManager* tradeManagerPtr = NULL, CPositionSizer* positionSizerPtr = NULL,
                   CUnifiedRiskManager* unifiedRiskManagerPtr = NULL,
                   const long managedMagic = 0);
    
    void SetStrategyRegistry(CStrategyRegistry* registry) { m_infra.SetStrategyRegistry(registry); }
    
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
    
    ENUM_TRADE_SIGNAL GetConsensusSignalForSymbolWithConfluenceMode(const string symbol, double &confidence, int &confluence, ENUM_SIGNAL_EVAL_MODE evalMode);

    void SetPipelineFilters(SignalFilterSettings &settings);
    void SetOrchestratorMode(double minWinRate, int maxLosses);
    void SetMinQuorum(int quorum);
    void SetManagedMagicRangeMax(long rangeMax) { m_tradeFeedback.SetManagedMagicRangeMax(rangeMax); }
    void SetStrategyConstructionInputs(const bool candlestickRequireTrend,
                                       const bool momentumScalping,
                                       const int momentumScalpCooldownSec)
    {
        m_constructionInputs.candlestickRequireTrend = candlestickRequireTrend;
        m_constructionInputs.momentumScalping = momentumScalping;
        m_constructionInputs.momentumScalpCooldownSec = momentumScalpCooldownSec;
    }
    bool IsEAOwnedMagic(long magic) const;
    void SetQuorumThreshold(const double threshold);
    void SetIntrabarMinQuorum(int quorum);
    void SetIntrabarDynamicQuorumEnabled(const bool enabled);
    void SetConflictDeadband(const double deadband);
    void SetMinReadyWeightRatio(const double ratio);
    void SetSupportFloors(const double newBarFloor, const double intrabarFloor);
    
    void SetStrategyIntrabarPolicyConfig(int strategyIndex, ENUM_INTRABAR_POLICY policy);
    ENUM_INTRABAR_POLICY GetStrategyIntrabarPolicyConfig(int strategyIndex) const;

    //--- Per-field accessors consumed by CStrategyRegistryState / CIntrabarPolicy via their m_src back-pointers.
    int    GetMaxStrategies() const { return m_roster.GetMaxStrategies(); }
    CTradeManager*        GetTradeManagerConst() const { return m_infra.GetTradeManager(); }
    CPositionSizer*       GetPositionSizerConst() const { return m_infra.GetPositionSizer(); }
    CUnifiedRiskManager*  GetUnifiedRiskManagerConst() const { return m_infra.GetUnifiedRiskManager(); }
    bool   IsPythonBridgeConnected() const { return (g_pythonBridge != NULL && g_pythonBridge.IsConnected()); }

    void SetStrategyRole(int index, int role);
    void SetStrategyCluster(int index, int cluster);
    void SetStrategyLiveVotingEnabled(int index, bool enabled);
    void SetStrategyIntrabarPolicyRaw(int index, int policy);

    //--- Single StrategyEntry append writer: only CStrategyRegistryState::RegisterStrategy() calls it via m_src.
    void AppendRegisteredStrategyEntry(IStrategy* strategy, const string name, bool enabled,
                                       double weight, ENUM_STRATEGY_TIER tier,
                                       ENUM_TIMEFRAMES resolvedTf,
                                       ENUM_INTRABAR_POLICY intrabarPolicy,
                                       ENUM_STRATEGY_ROLE role,
                                       ENUM_STRATEGY_CLUSTER cluster,
                                       bool liveVotingEnabled);

    ENUM_INTRABAR_POLICY GetIntrabarPolicyHelper(int idx);
    
    void SetParticipationFormulaBase(const double base);
    void SetParticipationFormulaCoeff(const double coeff);
    void SetParticipationFormulaMin(const double minVal);
    void SetParticipationFormulaMax(const double maxVal);
    
    enum ENUM_QUORUM_PROFILE
    {
        QUORUM_CONSERVATIVE,
        QUORUM_BALANCED,
        QUORUM_AGGRESSIVE
    };
    void ApplyQuorumProfile(ENUM_QUORUM_PROFILE profile);
    void SetConsensusDiagnosticsIntervalSeconds(const int seconds);
    int  GetMinQuorum() const;
    int  GetEnforcedMinVoters(const bool intrabar) const;
    bool UpdateStrategyWeightByName(const string name, const double weight);
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
    //--- SL/TP (pips) from the highest-priority contributor that stashed one; false when none did.
    bool GetConsensusProposedStops(ENUM_TRADE_SIGNAL signal, double &slPips, double &tpPips) const;
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

    int GetActiveStrategyCount() const;
    int GetActiveBrainStrategyCount() const;
    string GetStrategyReport() const;
    void UpdatePerformance(const string strategyName, double netProfit);
    
    void Deinit();

    bool UpdateStrategyWeight(const string strategyName, const double newWeight)
    {
        return UpdateStrategyWeightByName(strategyName, newWeight);
    }
    double GetEnsembleConfidence() const;
    ENUM_MARKET_REGIME GetCurrentMarketRegime() const;
    void RefreshMarketRegime();
    string GetStrategyWeightsJSON() const;
    string GetStrategyListJSON() const;
    string GetConsensusContextJSON() const;
    void UpdateStrategyWeights();
    void CheckStrategyDisabling();
    void CheckStrategyReEnabling();
    
    double CalculateRecentWinRate(const int index);
    double CalculateSharpeRatio(const int index);
    void CalculateStrategyMetrics(const int index);
    bool ShouldDisableStrategy(const int index);
    bool ShouldReEnableStrategy(const int index);
    void UpdateRecentPerformance(const int index, const double result);

    void SetDrawingManager(CChartDrawingManager* drawingManager);
    CChartDrawingManager* GetDrawingManager();
    
    void OnNewBar(const string symbol, ENUM_TIMEFRAMES timeframe);
    
    //--- Manager-owned trade outcome tracking.
    void OnTradeTransaction(const MqlTradeTransaction& trans, const MqlTradeRequest& request, const MqlTradeResult& result);
    
        void AutoRegisterStrategies(bool &enabledFlags[]);
        void SyncEnabledWithRegistry();

        void UpdateAIPerformanceMetrics(const string strategyName, const SAIModelMetrics &metrics);

    void SetDerivProfiler(CDerivAssetProfiler* profiler);
    void SetFamilyWeightMatrix(CFamilyStrategyWeightMatrix* famMatrix);
    void SetMultiAssetProfiler(CMultiAssetProfiler* profiler);
    void SetVPINFilter(CVPINFilter* vpin);
    void SetOFIEngine(COrderFlowImbalanceEngine* ofi);
    void ApplyFamilyEngineWeights(const string symbol);
    void ApplyAssetClassEngineWeights(const string symbol);
};

//--- Defaults live in the owning module constructors: deadband 0.35, support floors 0.30/0.25, m_maxStrategies 25,
//--- the 32-slot INTRABAR_POLICY_OFF table and the 15000-pt hard spread cutoff.
CEnterpriseStrategyManager::CEnterpriseStrategyManager()
{
    // m_diagnostics / m_attribution stay NULL: they are injected from EAOrchestrator.
    m_infra.AllocateHealthMonitor();

    // The delegator mirrors the still-NULL attribution pointer; SetAttributionManager() re-binds it.
    m_stateReporter.SetSource(GetPointer(this));
    m_attributionDelegator.SetAttribution(m_infra.GetAttribution());

    //--- These collaborators mirror no injected pointer, so they need no re-sync on Deinit.
    m_postConsensusValidator.SetSource(GetPointer(this));
    m_weightingConfig.SetSource(GetPointer(this));

    m_performanceHealth.SetSource(GetPointer(this));
    m_lifecycle.SetSource(GetPointer(this));

    m_intrabarPolicy.SetSource(GetPointer(this));
    m_registryState.SetSource(GetPointer(this));

    m_consensusEngine.SetSource(GetPointer(this));

    m_tradeFeedback.SetSource(GetPointer(this));
}

CEnterpriseStrategyManager::~CEnterpriseStrategyManager()
{
    //--- No ClearRoster() here: resetting m_strategyCount and the array is Deinit()'s job alone.
    m_roster.DeleteAllStrategies();

    //--- m_diagnostics / m_attribution are injected from EAOrchestrator and are deliberately NOT deleted here.
    m_infra.ReleaseOnDestruct();
}

//--- Fail-closed: a pipeline or TimeframeConsistency failure aborts Initialize() and rolls back the pipeline.
//--- The regime detector is optional; OFI, VPIN and the family matrix are injected pointers, never deleted here.
bool CEnterpriseStrategyManager::Initialize(const string symbol, ENUM_TIMEFRAMES timeframe,
                                           bool usePipeline,
                                           CTradeManager* tradeManagerPtr, CPositionSizer* positionSizerPtr,
                                           CUnifiedRiskManager* unifiedRiskManagerPtr,
                                           const long managedMagic)
{
    //--- Seeds m_managedMagic and m_managedMagicRangeMax from one argument: exact-match ownership until SetManagedMagicRangeMax widens it.
    m_tradeFeedback.SetManagedMagic(managedMagic);

    //--- Passed by reference: Initialize() seeds the health monitor from this config's thresholds and decay values.
    return m_infra.Initialize(symbol, timeframe, usePipeline,
                              tradeManagerPtr, positionSizerPtr, unifiedRiskManagerPtr,
                              m_quorumConfig);
}

bool CEnterpriseStrategyManager::RegisterStrategy(IStrategy* strategy, const string name,
                                                 bool enabled, double weight,
                                                 ENUM_STRATEGY_TIER tier,
                                                 ENUM_TIMEFRAMES tf,
                                                 ENUM_INTRABAR_POLICY intrabarPolicy,
                                                 ENUM_STRATEGY_ROLE role,
                                                 ENUM_STRATEGY_CLUSTER cluster,
                                                 bool liveVotingEnabled)
{
    return m_registryState.RegisterStrategy(strategy, name, enabled, weight, tier, tf,
                                            intrabarPolicy, role, cluster, liveVotingEnabled);
}

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

void CEnterpriseStrategyManager::SetStrategyIntrabarPolicyConfig(int strategyIndex, ENUM_INTRABAR_POLICY policy)
{
    m_intrabarPolicy.SetStrategyIntrabarPolicyConfig(strategyIndex, policy);
}

// Catalog creators build each strategy bare, so the operator's per-strategy inputs have to be pushed here
// rather than in the after-registration dependency pass.
void CEnterpriseStrategyManager::ConfigureBeforeInit(IStrategy* strategy, const string name)
{
    if(strategy == NULL)
        return;

    if(name == "Candlestick")
    {
        CStrategyCandlestick* candlestick = dynamic_cast<CStrategyCandlestick*>(strategy);
        if(candlestick != NULL)
            candlestick.SetRequireTrendAlignment(m_constructionInputs.candlestickRequireTrend);
        else
            Print("[STRATEGY-CONFIG] Candlestick row did not yield a CStrategyCandlestick - InpCandlestickRequireTrend not applied");
        return;
    }

    if(name == "Momentum")
    {
        CSimpleMomentumStrategy* momentum = dynamic_cast<CSimpleMomentumStrategy*>(strategy);
        if(momentum != NULL)
        {
            momentum.SetScalpingMode(m_constructionInputs.momentumScalping,
                                     m_constructionInputs.momentumScalpCooldownSec);
        }
        else
            Print("[STRATEGY-CONFIG] Momentum row did not yield a CSimpleMomentumStrategy - its inputs were not applied");
    }
}

ENUM_INTRABAR_POLICY CEnterpriseStrategyManager::GetStrategyIntrabarPolicyConfig(int strategyIndex) const
{
    //--- Out-of-range indexes fall back to INTRABAR_POLICY_OFF.
    return m_intrabarPolicy.GetStrategyIntrabarPolicyConfig(strategyIndex);
}

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

int CEnterpriseStrategyManager::GetEnforcedMinVoters(const bool intrabar) const
{
    return m_consensusEngine.EnforcedMinVoters(intrabar);
}

//--- The consensus entry point; the decision core is CConsensusEngine.

ENUM_TRADE_SIGNAL CEnterpriseStrategyManager::GetConsensusSignalForSymbolWithConfluenceMode(const string symbol,
                                                                                              double &confidence,
                                                                                              int &confluence,
                                                                                              ENUM_SIGNAL_EVAL_MODE evalMode)
{
    return m_consensusEngine.GetConsensusSignalForSymbolWithConfluenceMode(symbol, confidence, confluence, evalMode);
}

ENUM_INTRABAR_POLICY CEnterpriseStrategyManager::GetIntrabarPolicyHelper(int idx)
{
    return m_intrabarPolicy.GetIntrabarPolicyHelper(idx);
}

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

        if(g_strategyCatalog[i].requiresPythonBridge)
        {
            if(!bridgeUp)
            {
                Print("[EnterpriseStrategyManager] Python Bridge not available - Skipping Statistical Arbitrage registration");
                continue;
            }
        }

        //--- fi is the semantic siIndex slot, written only by BuildStrategyFlags.
        const int fi = CatalogEnableSlot(i);
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
        ConfigureBeforeInit(s, g_strategyCatalog[i].name);

        //--- pIdx is this row's config-builder policy slot; CIntrabarPolicy's always-LIVE fallback is fixed to semantic slots 7/8.
        const int pIdx = CatalogPolicySlot(i);
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

//--- Auto-registration runs BEFORE the orchestrator fills the shared CStrategyRegistry, so IsStrategyActive() is
//--- false then and RegisterStrategy()'s mode filter locks every strategy disabled; this re-applies registry state.
void CEnterpriseStrategyManager::SyncEnabledWithRegistry()
{
    m_consensusEngine.SyncEnabledWithRegistry();
}

int CEnterpriseStrategyManager::GetActiveStrategyCount() const
{
    return m_stateReporter.GetActiveStrategyCount();
}

int CEnterpriseStrategyManager::GetActiveBrainStrategyCount() const
{
    return m_stateReporter.GetActiveBrainStrategyCount();
}

string CEnterpriseStrategyManager::GetStrategyReport() const
{
    return m_stateReporter.GetStrategyReport();
}

void CEnterpriseStrategyManager::SetPipelineFilters(SignalFilterSettings &settings)
{
    //--- Cached even when the pipeline is off: CConsensusEngine uses it as the quality threshold floor.
    m_quorumConfig.CachePipelineMinConfidence(settings.confidence.minConfidence);

    m_infra.ApplyPipelineFilters(settings);
}

void CEnterpriseStrategyManager::SetOrchestratorMode(double minWinRate, int maxLosses)
{
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

string CEnterpriseStrategyManager::ConsensusDecisionClassToString(ENUM_CONSENSUS_DECISION_CLASS decisionClass)
{
    return CStrategyStateReporter::ConsensusDecisionClassToString(decisionClass);
}

void CEnterpriseStrategyManager::UpdateStrategyWeights()
{
    m_weightingConfig.UpdateStrategyWeights();
}

void CEnterpriseStrategyManager::CheckStrategyDisabling()
{
    m_lifecycle.CheckStrategyDisabling();
}

void CEnterpriseStrategyManager::CheckStrategyReEnabling()
{
    m_lifecycle.CheckStrategyReEnabling();
}

bool CEnterpriseStrategyManager::UpdateStrategyWeightByName(const string name, const double weight)
{
    //--- 0..10 weight clamp, entry + IStrategy::SetWeight push, then the health-monitor sync
    //--- (the monitor lives in CStrategyMgrInfrastructure, so it is passed in explicitly).
    return m_roster.UpdateStrategyWeightByName(name, weight, m_infra.GetHealthMonitor());
}

bool CEnterpriseStrategyManager::SetStrategyRoleByName(const string name, ENUM_STRATEGY_ROLE role)
{
    return m_registryState.SetStrategyRoleByName(name, role);
}

bool CEnterpriseStrategyManager::SetStrategyClusterByName(const string name, ENUM_STRATEGY_CLUSTER cluster)
{
    return m_registryState.SetStrategyClusterByName(name, cluster);
}

bool CEnterpriseStrategyManager::SetStrategyLiveVotingEligibilityByName(const string name, const bool enabled)
{
    return m_registryState.SetStrategyLiveVotingEligibilityByName(name, enabled);
}

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

void CEnterpriseStrategyManager::AppendRegisteredStrategyEntry(IStrategy* strategy, const string name, bool enabled,
                                                              double weight, ENUM_STRATEGY_TIER tier,
                                                              ENUM_TIMEFRAMES resolvedTf,
                                                              ENUM_INTRABAR_POLICY intrabarPolicy,
                                                              ENUM_STRATEGY_ROLE role,
                                                              ENUM_STRATEGY_CLUSTER cluster,
                                                              bool liveVotingEnabled)
{
    //--- Roster writes every StrategyEntry field, registers the weight with the health monitor, then bumps m_strategyCount.
    m_roster.AppendRegisteredStrategyEntry(strategy, name, enabled, weight, tier,
                                           resolvedTf, intrabarPolicy, role, cluster,
                                           liveVotingEnabled, m_infra.GetHealthMonitor());
}

bool CEnterpriseStrategyManager::SetStrategyConfidenceThresholdByName(const string name, const double threshold)
{
    return m_roster.SetStrategyConfidenceThresholdByName(name, threshold);
}

bool CEnterpriseStrategyManager::SetStrategyGovernanceByName(const string name,
                                                             ENUM_STRATEGY_ROLE role,
                                                             ENUM_STRATEGY_CLUSTER cluster,
                                                             const bool liveVotingEnabled)
{
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

bool CEnterpriseStrategyManager::GetConsensusProposedStops(ENUM_TRADE_SIGNAL signal, double &slPips, double &tpPips) const
{
    int indices[];
    m_signalContext.GetLastSignalContributorIndices(indices);
    for(int i = 0; i < ArraySize(indices); i++)
    {
        int idx = indices[i];
        IStrategy* p = m_roster.GetStrategyPtr(idx);
        if(p != NULL && p.GetProposedStops(signal, slPips, tpPips))
            return true;
    }
    return false;
}

bool CEnterpriseStrategyManager::GetLastSignalExecutionContext(string &roleTag,
                                                               string &clusterTag,
                                                               string &clusterCode,
                                                               string &contributorsCsv) const
{
    return m_signalContext.GetLastSignalExecutionContext(m_attributionDelegator,
                                                         roleTag, clusterTag,
                                                         clusterCode, contributorsCsv);
}

//--- Explicit teardown before the destructor; releases the injected diagnostics/attribution as well.
void CEnterpriseStrategyManager::Deinit()
{
    //--- Strategy teardown, then the roster reset (count + array resize) the destructor omits.
    m_roster.DeleteAllStrategies();
    m_roster.ClearRoster();

    //--- Release order: pipeline, ADX handle, regime detector, TF consistency, then the injected diagnostics/attribution.
    //--- Unlike the destructor, Deinit() DOES delete those injected pointers; FinishDeinit() drops the health monitor.
    m_infra.ReleaseOnDeinit();

    //--- Re-bind the delegator so its mirrored attribution pointer cannot dangle.
    m_attributionDelegator.SetAttribution(m_infra.GetAttribution());

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

int CEnterpriseStrategyManager::FindStrategyIndexByName(const string name) const
{
    return m_roster.FindStrategyIndexByName(name);
}

IStrategy* CEnterpriseStrategyManager::GetStrategyByName(const string name)
{
    return m_registryState.GetStrategyByName(name);
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

//--- Called once per symbol per new bar by the orchestrator, gated on its own new-bar check.
void CEnterpriseStrategyManager::OnNewBar(const string symbol, ENUM_TIMEFRAMES timeframe)
{
    m_lifecycle.OnNewBar(symbol, timeframe);
}

void CEnterpriseStrategyManager::OnTradeTransaction(const MqlTradeTransaction& trans,
                                                   const MqlTradeRequest& request,
                                                   const MqlTradeResult& result)
{
    //--- DEAL_ADD funnel: magic/symbol ownership guards, the partial-close guard, then per-contributor UpdatePerformance.
    m_tradeFeedback.OnTradeTransaction(trans, request, result);
}

bool CEnterpriseStrategyManager::IsPositionIdStillOpen(const ulong positionId) const
{
    return m_tradeFeedback.IsPositionIdStillOpen(positionId);
}

//--- ENUM_QUORUM_PROFILE stays nested because it is a user-facing MT5 input type; it is forwarded as an int whose
//--- ordinals must keep matching QUORUM_PROFILE_* in CConsensusWeightingConfig.
void CEnterpriseStrategyManager::ApplyQuorumProfile(ENUM_QUORUM_PROFILE profile)
{
    m_weightingConfig.ApplyQuorumProfile((int)profile);
}

void CEnterpriseStrategyManager::ApplyFamilyEngineWeights(const string symbol)
{
    m_weightingConfig.ApplyFamilyEngineWeights(symbol);
}

void CEnterpriseStrategyManager::ApplyAssetClassEngineWeights(const string symbol)
{
    m_weightingConfig.ApplyAssetClassEngineWeights(symbol);
}

bool CEnterpriseStrategyManager::EnableStrategy(const string name)
{
    return m_lifecycle.EnableStrategy(name);
}

bool CEnterpriseStrategyManager::DisableStrategy(const string name)
{
    return m_lifecycle.DisableStrategy(name);
}

bool CEnterpriseStrategyManager::IsEAOwnedMagic(long magic) const
{
    //--- Exact match plus the [magic, rangeMax] ownership window test.
    return m_tradeFeedback.IsEAOwnedMagic(magic);
}

int CEnterpriseStrategyManager::GetRegisteredStrategyCount() const
{
    return m_stateReporter.GetRegisteredStrategyCount();
}

CUnifiedSignalPipeline* CEnterpriseStrategyManager::GetPipeline()
{
    return m_infra.GetPipeline();
}

double CEnterpriseStrategyManager::GetEnsembleConfidence() const
{
    return m_stateReporter.GetEnsembleConfidence();
}

ENUM_MARKET_REGIME CEnterpriseStrategyManager::GetCurrentMarketRegime() const
{
    return m_signalContext.GetCurrentMarketRegime();
}

//--- Before Batch 201 nothing wrote m_currentMarketRegime, so every reader acted on
//--- MARKET_REGIME_UNKNOWN: AIEngine::AdaptToRegime answers that with no threshold change at
//--- all, which is why AI regime adaptation looked configured and did nothing. Same source as
//--- the consensus regime gate, so a vote and an adaptation cannot disagree about the market.
void CEnterpriseStrategyManager::RefreshMarketRegime()
{
    CUnifiedSignalPipeline* pipeline = m_infra.GetPipeline();
    if(pipeline == NULL)
        return;

    CRegimeEngine* regime = pipeline.GetRegimeEngine(GetManagedSymbol());
    if(regime == NULL)
        return;

    SRegimeSnapshot snap = regime.GetSnapshot();

    // CRegimeEngine::Update otherwise runs only inside the pipeline's optional RegimeCostGate, so with
    // that filter off - or for a symbol whose voters are all dropped before it - no snapshot ever turns
    // valid, every voter takes the 0.30 stand-aside, and the ready-weight floor becomes unreachable.
    if(!snap.valid)
    {
        for(int i = 0; i < GetStrategyCount(); i++)
        {
            if(!IsStrategyEnabled(i) || GetStrategyPtr(i) == NULL || !IsStrategyLiveVotingEnabled(i))
                continue;
            if(regime.Update(GetManagedSymbol(), GetStrategyTimeframe(i)))
                snap = regime.GetSnapshot();
            break;
        }
    }

    ENUM_REGIME_STATE st = snap.state;
    ENUM_MARKET_REGIME mapped = MARKET_REGIME_UNKNOWN;
    if(snap.valid && st == REGIME_TREND)     mapped = MARKET_REGIME_TRENDING;
    else if(snap.valid && st == REGIME_RANGE) mapped = MARKET_REGIME_RANGING;
    else if(snap.valid && (st == REGIME_BREAKOUT || st == REGIME_CHAOS))
        mapped = MARKET_REGIME_VOLATILE;

    if(mapped == m_signalContext.GetCurrentMarketRegime())
        return;

    PrintFormat("[MARKET-REGIME] %s | %s -> %s | valid=%s",
                GetManagedSymbol(),
                EnumToString(m_signalContext.GetCurrentMarketRegime()),
                EnumToString(mapped),
                snap.valid ? "true" : "false");

    m_signalContext.SetCurrentMarketRegime(mapped);
}

void CEnterpriseStrategyManager::SetDrawingManager(CChartDrawingManager* drawingManager)
{
    m_infra.SetDrawingManager(drawingManager);
}

CChartDrawingManager* CEnterpriseStrategyManager::GetDrawingManager()
{
    return m_infra.GetDrawingManager();
}

void CEnterpriseStrategyManager::SetDerivProfiler(CDerivAssetProfiler* profiler)
{
    m_infra.SetDerivProfiler(profiler);
}

void CEnterpriseStrategyManager::SetFamilyWeightMatrix(CFamilyStrategyWeightMatrix* famMatrix)
{
    m_infra.SetFamilyWeightMatrix(famMatrix);
}

void CEnterpriseStrategyManager::SetMultiAssetProfiler(CMultiAssetProfiler* profiler)
{
    m_infra.SetMultiAssetProfiler(profiler);
}

void CEnterpriseStrategyManager::SetVPINFilter(CVPINFilter* vpin)
{
    m_infra.SetVPINFilter(vpin);
}

void CEnterpriseStrategyManager::SetOFIEngine(COrderFlowImbalanceEngine* ofi)
{
    m_infra.SetOFIEngine(ofi);
}

void CEnterpriseStrategyManager::UpdateAIPerformanceMetrics(const string strategyName, const SAIModelMetrics &metrics)
{
    m_performanceHealth.UpdateAIPerformanceMetrics(strategyName, metrics);
}

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
