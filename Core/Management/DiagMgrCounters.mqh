//+------------------------------------------------------------------+
//| DiagMgrCounters.mqh                                               |
//| Extracted from DiagnosticsManager.mqh (God-Object decomposition)  |
//| Owns the consensus-diagnostics counter bank: raw counts, root     |
//| baselines, snapshot baselines, plus interval-gated logging.       |
//|                                                                   |
//| Behaviour is byte-identical to the original inline implementation:|
//| identical field semantics, identical log strings, identical       |
//| interval gating. CDiagnosticsManager keeps a by-value member of   |
//| CDiagMgrCounters and forwards each public method one-to-one.      |
//+------------------------------------------------------------------+
#ifndef DIAG_MGR_COUNTERS_MQH
#define DIAG_MGR_COUNTERS_MQH

//+------------------------------------------------------------------+
//| Consensus Diagnostics Snapshot Struct (moved from DiagnosticsCollector)
//+------------------------------------------------------------------+
struct SConsensusDiagnosticsSnapshot
{
    // Root level counters
    ulong rawNone;
    ulong filteredOut;
    ulong quorumFailed;
    ulong intrabarNotEligible;
    ulong signalsGenerated;
    ulong signalsAfterPipeline;
    ulong signalsAfterQuorum;
    ulong voteSuppressed;
    ulong rolePrimarySignals;
    ulong roleFeatureSignals;
    ulong roleShadowSignals;
    ulong clusterTrendSignals;
    ulong clusterMeanReversionSignals;
    ulong clusterStructureSignals;
    ulong clusterNoneSignals;
    ulong momentumNone;
    ulong momentumCooldown;
    ulong momentumLowVolatility;
    ulong momentumNoCrossover;
    ulong momentumTrendMisaligned;
    ulong momentumNotReady;
    ulong uictNone;
    ulong uictNeutralBias;
    ulong uictOtherFilters;

    // Root baseline
    ulong rootBaselineRawNone;
    ulong rootBaselineFilteredOut;
    ulong rootBaselineQuorumFailed;
    ulong rootBaselineIntrabarNotEligible;
    ulong rootBaselineSignalsGenerated;
    ulong rootBaselineSignalsAfterPipeline;
    ulong rootBaselineSignalsAfterQuorum;
    ulong rootBaselineVoteSuppressed;
    ulong rootBaselineRolePrimarySignals;
    ulong rootBaselineRoleFeatureSignals;
    ulong rootBaselineRoleShadowSignals;
    ulong rootBaselineClusterTrendSignals;
    ulong rootBaselineClusterMeanReversionSignals;
    ulong rootBaselineClusterStructureSignals;
    ulong rootBaselineClusterNoneSignals;
    ulong rootBaselineMomentumNone;
    ulong rootBaselineMomentumCooldown;
    ulong rootBaselineMomentumLowVolatility;
    ulong rootBaselineMomentumNoCrossover;
    ulong rootBaselineMomentumTrendMisaligned;
    ulong rootBaselineMomentumNotReady;
    ulong rootBaselineUICTNone;
    ulong rootBaselineUICTNeutralBias;
    ulong rootBaselineUICTOtherFilters;

    // Snapshot baseline
    ulong snapshotBaselineRawNone;
    ulong snapshotBaselineFilteredOut;
    ulong snapshotBaselineQuorumFailed;
    ulong snapshotBaselineIntrabarNotEligible;
    ulong snapshotBaselineSignalsGenerated;
    ulong snapshotBaselineSignalsAfterPipeline;
    ulong snapshotBaselineSignalsAfterQuorum;
    ulong snapshotBaselineVoteSuppressed;
    ulong snapshotBaselineRolePrimarySignals;
    ulong snapshotBaselineRoleFeatureSignals;
    ulong snapshotBaselineRoleShadowSignals;
    ulong snapshotBaselineClusterTrendSignals;
    ulong snapshotBaselineClusterMeanReversionSignals;
    ulong snapshotBaselineClusterStructureSignals;
    ulong snapshotBaselineClusterNoneSignals;
    ulong snapshotBaselineMomentumNone;
    ulong snapshotBaselineMomentumCooldown;
    ulong snapshotBaselineMomentumLowVolatility;
    ulong snapshotBaselineMomentumNoCrossover;
    ulong snapshotBaselineMomentumTrendMisaligned;
    ulong snapshotBaselineMomentumNotReady;
    ulong snapshotBaselineUICTNone;
    ulong snapshotBaselineUICTNeutralBias;
    ulong snapshotBaselineUICTOtherFilters;

    SConsensusDiagnosticsSnapshot()
    {
        ZeroMemory(this);
    }
};

//+------------------------------------------------------------------+
//| CDiagMgrCounters — consensus diagnostics counter bank             |
//+------------------------------------------------------------------+
class CDiagMgrCounters
{
private:
    // Raw counters
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

    // Root baselines
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

    // Snapshot baselines
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

    // Interval-gated logging state
    datetime m_lastDiagLogTime;
    int      m_diagLogIntervalSec;

public:
    CDiagMgrCounters() :
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
        m_diagLogIntervalSec(60)
    {}

    ~CDiagMgrCounters() {}

    // Configuration
    void SetLogIntervalSeconds(const int seconds) { m_diagLogIntervalSec = MathMax(10, seconds); }

    // Counter accessors - Raw counts
    ulong GetRawNone() const { return m_diagRawNone; }
    ulong GetFilteredOut() const { return m_diagFilteredOut; }
    ulong GetQuorumFailed() const { return m_diagQuorumFailed; }
    ulong GetIntrabarNotEligible() const { return m_diagIntrabarNotEligible; }
    ulong GetSignalsGenerated() const { return m_diagSignalsGenerated; }
    ulong GetSignalsAfterPipeline() const { return m_diagSignalsAfterPipeline; }
    ulong GetSignalsAfterQuorum() const { return m_diagSignalsAfterQuorum; }
    ulong GetVoteSuppressed() const { return m_diagVoteSuppressed; }

    // Counter accessors - Role breakdown
    ulong GetRolePrimarySignals() const { return m_diagRolePrimarySignals; }
    ulong GetRoleFeatureSignals() const { return m_diagRoleFeatureSignals; }
    ulong GetRoleShadowSignals() const { return m_diagRoleShadowSignals; }

    // Counter accessors - Cluster breakdown
    ulong GetClusterTrendSignals() const { return m_diagClusterTrendSignals; }
    ulong GetClusterMeanReversionSignals() const { return m_diagClusterMeanReversionSignals; }
    ulong GetClusterStructureSignals() const { return m_diagClusterStructureSignals; }
    ulong GetClusterNoneSignals() const { return m_diagClusterNoneSignals; }

    // Counter accessors - Strategy-specific rejections
    ulong GetMomentumNone() const { return m_diagMomentumNone; }
    ulong GetMomentumCooldown() const { return m_diagMomentumCooldown; }
    ulong GetMomentumLowVolatility() const { return m_diagMomentumLowVolatility; }
    ulong GetMomentumNoCrossover() const { return m_diagMomentumNoCrossover; }
    ulong GetMomentumTrendMisaligned() const { return m_diagMomentumTrendMisaligned; }
    ulong GetMomentumNotReady() const { return m_diagMomentumNotReady; }
    ulong GetUICTNone() const { return m_diagUICTNone; }
    ulong GetUICTNeutralBias() const { return m_diagUICTNeutralBias; }
    ulong GetUICTOtherFilters() const { return m_diagUICTOtherFilters; }

    // Root baseline accessors
    ulong GetRootBaselineRawNone() const { return m_diagRootBaselineRawNone; }
    ulong GetRootBaselineFilteredOut() const { return m_diagRootBaselineFilteredOut; }
    ulong GetRootBaselineQuorumFailed() const { return m_diagRootBaselineQuorumFailed; }
    ulong GetRootBaselineIntrabarNotEligible() const { return m_diagRootBaselineIntrabarNotEligible; }
    ulong GetRootBaselineSignalsGenerated() const { return m_diagRootBaselineSignalsGenerated; }
    ulong GetRootBaselineSignalsAfterPipeline() const { return m_diagRootBaselineSignalsAfterPipeline; }
    ulong GetRootBaselineSignalsAfterQuorum() const { return m_diagRootBaselineSignalsAfterQuorum; }
    ulong GetRootBaselineVoteSuppressed() const { return m_diagRootBaselineVoteSuppressed; }
    ulong GetRootBaselineRolePrimarySignals() const { return m_diagRootBaselineRolePrimarySignals; }
    ulong GetRootBaselineRoleFeatureSignals() const { return m_diagRootBaselineRoleFeatureSignals; }
    ulong GetRootBaselineRoleShadowSignals() const { return m_diagRootBaselineRoleShadowSignals; }
    ulong GetRootBaselineClusterTrendSignals() const { return m_diagRootBaselineClusterTrendSignals; }
    ulong GetRootBaselineClusterMeanReversionSignals() const { return m_diagRootBaselineClusterMeanReversionSignals; }
    ulong GetRootBaselineClusterStructureSignals() const { return m_diagRootBaselineClusterStructureSignals; }
    ulong GetRootBaselineClusterNoneSignals() const { return m_diagRootBaselineClusterNoneSignals; }
    ulong GetRootBaselineMomentumNone() const { return m_diagRootBaselineMomentumNone; }
    ulong GetRootBaselineMomentumCooldown() const { return m_diagRootBaselineMomentumCooldown; }
    ulong GetRootBaselineMomentumLowVolatility() const { return m_diagRootBaselineMomentumLowVolatility; }
    ulong GetRootBaselineMomentumNoCrossover() const { return m_diagRootBaselineMomentumNoCrossover; }
    ulong GetRootBaselineMomentumTrendMisaligned() const { return m_diagRootBaselineMomentumTrendMisaligned; }
    ulong GetRootBaselineMomentumNotReady() const { return m_diagRootBaselineMomentumNotReady; }
    ulong GetRootBaselineUICTNone() const { return m_diagRootBaselineUICTNone; }
    ulong GetRootBaselineUICTNeutralBias() const { return m_diagRootBaselineUICTNeutralBias; }
    ulong GetRootBaselineUICTOtherFilters() const { return m_diagRootBaselineUICTOtherFilters; }

    // Snapshot baseline accessors
    ulong GetSnapshotBaselineRawNone() const { return m_diagSnapshotBaselineRawNone; }
    ulong GetSnapshotBaselineFilteredOut() const { return m_diagSnapshotBaselineFilteredOut; }
    ulong GetSnapshotBaselineQuorumFailed() const { return m_diagSnapshotBaselineQuorumFailed; }
    ulong GetSnapshotBaselineIntrabarNotEligible() const { return m_diagSnapshotBaselineIntrabarNotEligible; }
    ulong GetSnapshotBaselineSignalsGenerated() const { return m_diagSnapshotBaselineSignalsGenerated; }
    ulong GetSnapshotBaselineSignalsAfterPipeline() const { return m_diagSnapshotBaselineSignalsAfterPipeline; }
    ulong GetSnapshotBaselineSignalsAfterQuorum() const { return m_diagSnapshotBaselineSignalsAfterQuorum; }
    ulong GetSnapshotBaselineVoteSuppressed() const { return m_diagSnapshotBaselineVoteSuppressed; }
    ulong GetSnapshotBaselineRolePrimarySignals() const { return m_diagSnapshotBaselineRolePrimarySignals; }
    ulong GetSnapshotBaselineRoleFeatureSignals() const { return m_diagSnapshotBaselineRoleFeatureSignals; }
    ulong GetSnapshotBaselineRoleShadowSignals() const { return m_diagSnapshotBaselineRoleShadowSignals; }
    ulong GetSnapshotBaselineClusterTrendSignals() const { return m_diagSnapshotBaselineClusterTrendSignals; }
    ulong GetSnapshotBaselineClusterMeanReversionSignals() const { return m_diagSnapshotBaselineClusterMeanReversionSignals; }
    ulong GetSnapshotBaselineClusterStructureSignals() const { return m_diagSnapshotBaselineClusterStructureSignals; }
    ulong GetSnapshotBaselineClusterNoneSignals() const { return m_diagSnapshotBaselineClusterNoneSignals; }
    ulong GetSnapshotBaselineMomentumNone() const { return m_diagSnapshotBaselineMomentumNone; }
    ulong GetSnapshotBaselineMomentumCooldown() const { return m_diagSnapshotBaselineMomentumCooldown; }
    ulong GetSnapshotBaselineMomentumLowVolatility() const { return m_diagSnapshotBaselineMomentumLowVolatility; }
    ulong GetSnapshotBaselineMomentumNoCrossover() const { return m_diagSnapshotBaselineMomentumNoCrossover; }
    ulong GetSnapshotBaselineMomentumTrendMisaligned() const { return m_diagSnapshotBaselineMomentumTrendMisaligned; }
    ulong GetSnapshotBaselineMomentumNotReady() const { return m_diagSnapshotBaselineMomentumNotReady; }
    ulong GetSnapshotBaselineUICTNone() const { return m_diagSnapshotBaselineUICTNone; }
    ulong GetSnapshotBaselineUICTNeutralBias() const { return m_diagSnapshotBaselineUICTNeutralBias; }
    ulong GetSnapshotBaselineUICTOtherFilters() const { return m_diagSnapshotBaselineUICTOtherFilters; }

    // Increment methods
    void IncrementRawNone() { m_diagRawNone++; }
    void IncrementFilteredOut() { m_diagFilteredOut++; }
    void IncrementQuorumFailed() { m_diagQuorumFailed++; }
    void IncrementIntrabarNotEligible() { m_diagIntrabarNotEligible++; }
    void IncrementSignalsGenerated() { m_diagSignalsGenerated++; }
    void IncrementSignalsAfterPipeline() { m_diagSignalsAfterPipeline++; }
    void IncrementSignalsAfterQuorum() { m_diagSignalsAfterQuorum++; }
    void IncrementVoteSuppressed() { m_diagVoteSuppressed++; }
    void IncrementRolePrimarySignals() { m_diagRolePrimarySignals++; }
    void IncrementRoleFeatureSignals() { m_diagRoleFeatureSignals++; }
    void IncrementRoleShadowSignals() { m_diagRoleShadowSignals++; }
    void IncrementClusterTrendSignals() { m_diagClusterTrendSignals++; }
    void IncrementClusterMeanReversionSignals() { m_diagClusterMeanReversionSignals++; }
    void IncrementClusterStructureSignals() { m_diagClusterStructureSignals++; }
    void IncrementClusterNoneSignals() { m_diagClusterNoneSignals++; }
    void IncrementMomentumNone() { m_diagMomentumNone++; }
    void IncrementMomentumCooldown() { m_diagMomentumCooldown++; }
    void IncrementMomentumLowVolatility() { m_diagMomentumLowVolatility++; }
    void IncrementMomentumNoCrossover() { m_diagMomentumNoCrossover++; }
    void IncrementMomentumTrendMisaligned() { m_diagMomentumTrendMisaligned++; }
    void IncrementMomentumNotReady() { m_diagMomentumNotReady++; }
    void IncrementUICTNone() { m_diagUICTNone++; }
    void IncrementUICTNeutralBias() { m_diagUICTNeutralBias++; }
    void IncrementUICTOtherFilters() { m_diagUICTOtherFilters++; }

    // Root baseline increments
    void IncrementRootBaselineRawNone() { m_diagRootBaselineRawNone++; }
    void IncrementRootBaselineFilteredOut() { m_diagRootBaselineFilteredOut++; }
    void IncrementRootBaselineQuorumFailed() { m_diagRootBaselineQuorumFailed++; }
    void IncrementRootBaselineIntrabarNotEligible() { m_diagRootBaselineIntrabarNotEligible++; }
    void IncrementRootBaselineSignalsGenerated() { m_diagRootBaselineSignalsGenerated++; }
    void IncrementRootBaselineSignalsAfterPipeline() { m_diagRootBaselineSignalsAfterPipeline++; }
    void IncrementRootBaselineSignalsAfterQuorum() { m_diagRootBaselineSignalsAfterQuorum++; }
    void IncrementRootBaselineVoteSuppressed() { m_diagRootBaselineVoteSuppressed++; }
    void IncrementRootBaselineRolePrimarySignals() { m_diagRootBaselineRolePrimarySignals++; }
    void IncrementRootBaselineRoleFeatureSignals() { m_diagRootBaselineRoleFeatureSignals++; }
    void IncrementRootBaselineRoleShadowSignals() { m_diagRootBaselineRoleShadowSignals++; }
    void IncrementRootBaselineClusterTrendSignals() { m_diagRootBaselineClusterTrendSignals++; }
    void IncrementRootBaselineClusterMeanReversionSignals() { m_diagRootBaselineClusterMeanReversionSignals++; }
    void IncrementRootBaselineClusterStructureSignals() { m_diagRootBaselineClusterStructureSignals++; }
    void IncrementRootBaselineClusterNoneSignals() { m_diagRootBaselineClusterNoneSignals++; }
    void IncrementRootBaselineMomentumNone() { m_diagRootBaselineMomentumNone++; }
    void IncrementRootBaselineMomentumCooldown() { m_diagRootBaselineMomentumCooldown++; }
    void IncrementRootBaselineMomentumLowVolatility() { m_diagRootBaselineMomentumLowVolatility++; }
    void IncrementRootBaselineMomentumNoCrossover() { m_diagRootBaselineMomentumNoCrossover++; }
    void IncrementRootBaselineMomentumTrendMisaligned() { m_diagRootBaselineMomentumTrendMisaligned++; }
    void IncrementRootBaselineMomentumNotReady() { m_diagRootBaselineMomentumNotReady++; }
    void IncrementRootBaselineUICTNone() { m_diagRootBaselineUICTNone++; }
    void IncrementRootBaselineUICTNeutralBias() { m_diagRootBaselineUICTNeutralBias++; }
    void IncrementRootBaselineUICTOtherFilters() { m_diagRootBaselineUICTOtherFilters++; }

    // Snapshot baseline increments
    void IncrementSnapshotBaselineRawNone() { m_diagSnapshotBaselineRawNone++; }
    void IncrementSnapshotBaselineFilteredOut() { m_diagSnapshotBaselineFilteredOut++; }
    void IncrementSnapshotBaselineQuorumFailed() { m_diagSnapshotBaselineQuorumFailed++; }
    void IncrementSnapshotBaselineIntrabarNotEligible() { m_diagSnapshotBaselineIntrabarNotEligible++; }
    void IncrementSnapshotBaselineSignalsGenerated() { m_diagSnapshotBaselineSignalsGenerated++; }
    void IncrementSnapshotBaselineSignalsAfterPipeline() { m_diagSnapshotBaselineSignalsAfterPipeline++; }
    void IncrementSnapshotBaselineSignalsAfterQuorum() { m_diagSnapshotBaselineSignalsAfterQuorum++; }
    void IncrementSnapshotBaselineVoteSuppressed() { m_diagSnapshotBaselineVoteSuppressed++; }
    void IncrementSnapshotBaselineRolePrimarySignals() { m_diagSnapshotBaselineRolePrimarySignals++; }
    void IncrementSnapshotBaselineRoleFeatureSignals() { m_diagSnapshotBaselineRoleFeatureSignals++; }
    void IncrementSnapshotBaselineRoleShadowSignals() { m_diagSnapshotBaselineRoleShadowSignals++; }
    void IncrementSnapshotBaselineClusterTrendSignals() { m_diagSnapshotBaselineClusterTrendSignals++; }
    void IncrementSnapshotBaselineClusterMeanReversionSignals() { m_diagSnapshotBaselineClusterMeanReversionSignals++; }
    void IncrementSnapshotBaselineClusterStructureSignals() { m_diagSnapshotBaselineClusterStructureSignals++; }
    void IncrementSnapshotBaselineClusterNoneSignals() { m_diagSnapshotBaselineClusterNoneSignals++; }
    void IncrementSnapshotBaselineMomentumNone() { m_diagSnapshotBaselineMomentumNone++; }
    void IncrementSnapshotBaselineMomentumCooldown() { m_diagSnapshotBaselineMomentumCooldown++; }
    void IncrementSnapshotBaselineMomentumLowVolatility() { m_diagSnapshotBaselineMomentumLowVolatility++; }
    void IncrementSnapshotBaselineMomentumNoCrossover() { m_diagSnapshotBaselineMomentumNoCrossover++; }
    void IncrementSnapshotBaselineMomentumTrendMisaligned() { m_diagSnapshotBaselineMomentumTrendMisaligned++; }
    void IncrementSnapshotBaselineMomentumNotReady() { m_diagSnapshotBaselineMomentumNotReady++; }
    void IncrementSnapshotBaselineUICTNone() { m_diagSnapshotBaselineUICTNone++; }
    void IncrementSnapshotBaselineUICTNeutralBias() { m_diagSnapshotBaselineUICTNeutralBias++; }
    void IncrementSnapshotBaselineUICTOtherFilters() { m_diagSnapshotBaselineUICTOtherFilters++; }

    // Role/Cluster diagnostic accumulation
    void AccumulateRoleClusterSignalDiagnostics(const int strategyIndex, const bool signalGenerated);

    // Snapshot methods
    void GetSnapshot(ulong &rawNone,
                     ulong &filteredOut,
                     ulong &quorumFailed,
                     ulong &intrabarNotEligible,
                     ulong &signalsGenerated,
                     ulong &signalsAfterPipeline,
                     ulong &signalsAfterQuorum,
                     ulong &voteSuppressed,
                     ulong &rolePrimarySignals,
                     ulong &roleFeatureSignals,
                     ulong &roleShadowSignals,
                     ulong &clusterTrendSignals,
                     ulong &clusterMeanReversionSignals,
                     ulong &clusterStructureSignals,
                     ulong &clusterNoneSignals) const;

    // Full diagnostics snapshot for logging
    void GetFullDiagnosticsSnapshot(SConsensusDiagnosticsSnapshot &snapshot) const;

    // Logging
    void MaybeLogDiagnostics(const string symbol);
    void LogDiagnostics(const string symbol);

    // Reset
    void ResetConsensusDiagnostics();

    // Convenience method to set snapshot baselines (called at start of new logging interval)
    void SetSnapshotBaselines();
};

//+------------------------------------------------------------------+
//| Reset Consensus Diagnostics                                      |
//+------------------------------------------------------------------+
void CDiagMgrCounters::ResetConsensusDiagnostics()
{
    m_diagRawNone = 0;
    m_diagFilteredOut = 0;
    m_diagQuorumFailed = 0;
    m_diagIntrabarNotEligible = 0;
    m_diagSignalsGenerated = 0;
    m_diagSignalsAfterPipeline = 0;
    m_diagSignalsAfterQuorum = 0;
    m_diagVoteSuppressed = 0;
    m_diagRolePrimarySignals = 0;
    m_diagRoleFeatureSignals = 0;
    m_diagRoleShadowSignals = 0;
    m_diagClusterTrendSignals = 0;
    m_diagClusterMeanReversionSignals = 0;
    m_diagClusterStructureSignals = 0;
    m_diagClusterNoneSignals = 0;
    m_diagMomentumNone = 0;
    m_diagMomentumCooldown = 0;
    m_diagMomentumLowVolatility = 0;
    m_diagMomentumNoCrossover = 0;
    m_diagMomentumTrendMisaligned = 0;
    m_diagMomentumNotReady = 0;
    m_diagUICTNone = 0;
    m_diagUICTNeutralBias = 0;
    m_diagUICTOtherFilters = 0;
    m_diagRootBaselineRawNone = 0;
    m_diagRootBaselineFilteredOut = 0;
    m_diagRootBaselineQuorumFailed = 0;
    m_diagRootBaselineIntrabarNotEligible = 0;
    m_diagRootBaselineSignalsGenerated = 0;
    m_diagRootBaselineSignalsAfterPipeline = 0;
    m_diagRootBaselineSignalsAfterQuorum = 0;
    m_diagRootBaselineVoteSuppressed = 0;
    m_diagRootBaselineRolePrimarySignals = 0;
    m_diagRootBaselineRoleFeatureSignals = 0;
    m_diagRootBaselineRoleShadowSignals = 0;
    m_diagRootBaselineClusterTrendSignals = 0;
    m_diagRootBaselineClusterMeanReversionSignals = 0;
    m_diagRootBaselineClusterStructureSignals = 0;
    m_diagRootBaselineClusterNoneSignals = 0;
    m_diagRootBaselineMomentumNone = 0;
    m_diagRootBaselineMomentumCooldown = 0;
    m_diagRootBaselineMomentumLowVolatility = 0;
    m_diagRootBaselineMomentumNoCrossover = 0;
    m_diagRootBaselineMomentumTrendMisaligned = 0;
    m_diagRootBaselineMomentumNotReady = 0;
    m_diagRootBaselineUICTNone = 0;
    m_diagRootBaselineUICTNeutralBias = 0;
    m_diagRootBaselineUICTOtherFilters = 0;
    m_diagSnapshotBaselineRawNone = 0;
    m_diagSnapshotBaselineFilteredOut = 0;
    m_diagSnapshotBaselineQuorumFailed = 0;
    m_diagSnapshotBaselineIntrabarNotEligible = 0;
    m_diagSnapshotBaselineSignalsGenerated = 0;
    m_diagSnapshotBaselineSignalsAfterPipeline = 0;
    m_diagSnapshotBaselineSignalsAfterQuorum = 0;
    m_diagSnapshotBaselineVoteSuppressed = 0;
    m_diagSnapshotBaselineRolePrimarySignals = 0;
    m_diagSnapshotBaselineRoleFeatureSignals = 0;
    m_diagSnapshotBaselineRoleShadowSignals = 0;
    m_diagSnapshotBaselineClusterTrendSignals = 0;
    m_diagSnapshotBaselineClusterMeanReversionSignals = 0;
    m_diagSnapshotBaselineClusterStructureSignals = 0;
    m_diagSnapshotBaselineClusterNoneSignals = 0;
    m_diagSnapshotBaselineMomentumNone = 0;
    m_diagSnapshotBaselineMomentumCooldown = 0;
    m_diagSnapshotBaselineMomentumLowVolatility = 0;
    m_diagSnapshotBaselineMomentumNoCrossover = 0;
    m_diagSnapshotBaselineMomentumTrendMisaligned = 0;
    m_diagSnapshotBaselineMomentumNotReady = 0;
    m_diagSnapshotBaselineUICTNone = 0;
    m_diagSnapshotBaselineUICTNeutralBias = 0;
    m_diagSnapshotBaselineUICTOtherFilters = 0;
    m_lastDiagLogTime = 0;
}

//+------------------------------------------------------------------+
//| Accumulate Role/Cluster Signal Diagnostics                       |
//+------------------------------------------------------------------+
void CDiagMgrCounters::AccumulateRoleClusterSignalDiagnostics(const int strategyIndex, const bool signalGenerated)
{
    // Role/cluster signal attribution needs per-strategy role/cluster metadata, which is not
    // available at this call site (only strategyIndex + a boolean signal flag are passed). The
    // dedicated per-role / per-cluster tally methods in this class own that attribution; this
    // hook intentionally early-outs when no signal was generated.
    if(!signalGenerated)
        return;
}

//+------------------------------------------------------------------+
//| Get Snapshot                                                     |
//+------------------------------------------------------------------+
void CDiagMgrCounters::GetSnapshot(ulong &rawNone,
                                   ulong &filteredOut,
                                   ulong &quorumFailed,
                                   ulong &intrabarNotEligible,
                                   ulong &signalsGenerated,
                                   ulong &signalsAfterPipeline,
                                   ulong &signalsAfterQuorum,
                                   ulong &voteSuppressed,
                                   ulong &rolePrimarySignals,
                                   ulong &roleFeatureSignals,
                                   ulong &roleShadowSignals,
                                   ulong &clusterTrendSignals,
                                   ulong &clusterMeanReversionSignals,
                                   ulong &clusterStructureSignals,
                                   ulong &clusterNoneSignals) const
{
    rawNone = m_diagRawNone;
    filteredOut = m_diagFilteredOut;
    quorumFailed = m_diagQuorumFailed;
    intrabarNotEligible = m_diagIntrabarNotEligible;
    signalsGenerated = m_diagSignalsGenerated;
    signalsAfterPipeline = m_diagSignalsAfterPipeline;
    signalsAfterQuorum = m_diagSignalsAfterQuorum;
    voteSuppressed = m_diagVoteSuppressed;
    rolePrimarySignals = m_diagRolePrimarySignals;
    roleFeatureSignals = m_diagRoleFeatureSignals;
    roleShadowSignals = m_diagRoleShadowSignals;
    clusterTrendSignals = m_diagClusterTrendSignals;
    clusterMeanReversionSignals = m_diagClusterMeanReversionSignals;
    clusterStructureSignals = m_diagClusterStructureSignals;
    clusterNoneSignals = m_diagClusterNoneSignals;
}

//+------------------------------------------------------------------+
//| Get Full Diagnostics Snapshot                                    |
//+------------------------------------------------------------------+
void CDiagMgrCounters::GetFullDiagnosticsSnapshot(SConsensusDiagnosticsSnapshot &snapshot) const
{
    // Root baseline (summary)
    snapshot.rawNone = m_diagRawNone;
    snapshot.filteredOut = m_diagFilteredOut;
    snapshot.quorumFailed = m_diagQuorumFailed;
    snapshot.intrabarNotEligible = m_diagIntrabarNotEligible;
    snapshot.signalsGenerated = m_diagSignalsGenerated;
    snapshot.signalsAfterPipeline = m_diagSignalsAfterPipeline;
    snapshot.signalsAfterQuorum = m_diagSignalsAfterQuorum;
    snapshot.voteSuppressed = m_diagVoteSuppressed;
    snapshot.rolePrimarySignals = m_diagRolePrimarySignals;
    snapshot.roleFeatureSignals = m_diagRoleFeatureSignals;
    snapshot.roleShadowSignals = m_diagRoleShadowSignals;
    snapshot.clusterTrendSignals = m_diagClusterTrendSignals;
    snapshot.clusterMeanReversionSignals = m_diagClusterMeanReversionSignals;
    snapshot.clusterStructureSignals = m_diagClusterStructureSignals;
    snapshot.clusterNoneSignals = m_diagClusterNoneSignals;
    snapshot.momentumNone = m_diagMomentumNone;
    snapshot.momentumCooldown = m_diagMomentumCooldown;
    snapshot.momentumLowVolatility = m_diagMomentumLowVolatility;
    snapshot.momentumNoCrossover = m_diagMomentumNoCrossover;
    snapshot.momentumTrendMisaligned = m_diagMomentumTrendMisaligned;
    snapshot.momentumNotReady = m_diagMomentumNotReady;
    snapshot.uictNone = m_diagUICTNone;
    snapshot.uictNeutralBias = m_diagUICTNeutralBias;
    snapshot.uictOtherFilters = m_diagUICTOtherFilters;

    // Root baseline (full)
    snapshot.rootBaselineRawNone = m_diagRootBaselineRawNone;
    snapshot.rootBaselineFilteredOut = m_diagRootBaselineFilteredOut;
    snapshot.rootBaselineQuorumFailed = m_diagRootBaselineQuorumFailed;
    snapshot.rootBaselineIntrabarNotEligible = m_diagRootBaselineIntrabarNotEligible;
    snapshot.rootBaselineSignalsGenerated = m_diagRootBaselineSignalsGenerated;
    snapshot.rootBaselineSignalsAfterPipeline = m_diagRootBaselineSignalsAfterPipeline;
    snapshot.rootBaselineSignalsAfterQuorum = m_diagRootBaselineSignalsAfterQuorum;
    snapshot.rootBaselineVoteSuppressed = m_diagRootBaselineVoteSuppressed;
    snapshot.rootBaselineRolePrimarySignals = m_diagRootBaselineRolePrimarySignals;
    snapshot.rootBaselineRoleFeatureSignals = m_diagRootBaselineRoleFeatureSignals;
    snapshot.rootBaselineRoleShadowSignals = m_diagRootBaselineRoleShadowSignals;
    snapshot.rootBaselineClusterTrendSignals = m_diagRootBaselineClusterTrendSignals;
    snapshot.rootBaselineClusterMeanReversionSignals = m_diagRootBaselineClusterMeanReversionSignals;
    snapshot.rootBaselineClusterStructureSignals = m_diagRootBaselineClusterStructureSignals;
    snapshot.rootBaselineClusterNoneSignals = m_diagRootBaselineClusterNoneSignals;
    snapshot.rootBaselineMomentumNone = m_diagRootBaselineMomentumNone;
    snapshot.rootBaselineMomentumCooldown = m_diagRootBaselineMomentumCooldown;
    snapshot.rootBaselineMomentumLowVolatility = m_diagRootBaselineMomentumLowVolatility;
    snapshot.rootBaselineMomentumNoCrossover = m_diagRootBaselineMomentumNoCrossover;
    snapshot.rootBaselineMomentumTrendMisaligned = m_diagRootBaselineMomentumTrendMisaligned;
    snapshot.rootBaselineMomentumNotReady = m_diagRootBaselineMomentumNotReady;
    snapshot.rootBaselineUICTNone = m_diagRootBaselineUICTNone;
    snapshot.rootBaselineUICTNeutralBias = m_diagRootBaselineUICTNeutralBias;
    snapshot.rootBaselineUICTOtherFilters = m_diagRootBaselineUICTOtherFilters;

    // Snapshot baseline
    snapshot.snapshotBaselineRawNone = m_diagSnapshotBaselineRawNone;
    snapshot.snapshotBaselineFilteredOut = m_diagSnapshotBaselineFilteredOut;
    snapshot.snapshotBaselineQuorumFailed = m_diagSnapshotBaselineQuorumFailed;
    snapshot.snapshotBaselineIntrabarNotEligible = m_diagSnapshotBaselineIntrabarNotEligible;
    snapshot.snapshotBaselineSignalsGenerated = m_diagSnapshotBaselineSignalsGenerated;
    snapshot.snapshotBaselineSignalsAfterPipeline = m_diagSnapshotBaselineSignalsAfterPipeline;
    snapshot.snapshotBaselineSignalsAfterQuorum = m_diagSnapshotBaselineSignalsAfterQuorum;
    snapshot.snapshotBaselineVoteSuppressed = m_diagSnapshotBaselineVoteSuppressed;
    snapshot.snapshotBaselineRolePrimarySignals = m_diagSnapshotBaselineRolePrimarySignals;
    snapshot.snapshotBaselineRoleFeatureSignals = m_diagSnapshotBaselineRoleFeatureSignals;
    snapshot.snapshotBaselineRoleShadowSignals = m_diagSnapshotBaselineRoleShadowSignals;
    snapshot.snapshotBaselineClusterTrendSignals = m_diagSnapshotBaselineClusterTrendSignals;
    snapshot.snapshotBaselineClusterMeanReversionSignals = m_diagSnapshotBaselineClusterMeanReversionSignals;
    snapshot.snapshotBaselineClusterStructureSignals = m_diagSnapshotBaselineClusterStructureSignals;
    snapshot.snapshotBaselineClusterNoneSignals = m_diagSnapshotBaselineClusterNoneSignals;
    snapshot.snapshotBaselineMomentumNone = m_diagSnapshotBaselineMomentumNone;
    snapshot.snapshotBaselineMomentumCooldown = m_diagSnapshotBaselineMomentumCooldown;
    snapshot.snapshotBaselineMomentumLowVolatility = m_diagSnapshotBaselineMomentumLowVolatility;
    snapshot.snapshotBaselineMomentumNoCrossover = m_diagSnapshotBaselineMomentumNoCrossover;
    snapshot.snapshotBaselineMomentumTrendMisaligned = m_diagSnapshotBaselineMomentumTrendMisaligned;
    snapshot.snapshotBaselineMomentumNotReady = m_diagSnapshotBaselineMomentumNotReady;
    snapshot.snapshotBaselineUICTNone = m_diagSnapshotBaselineUICTNone;
    snapshot.snapshotBaselineUICTNeutralBias = m_diagSnapshotBaselineUICTNeutralBias;
    snapshot.snapshotBaselineUICTOtherFilters = m_diagSnapshotBaselineUICTOtherFilters;
}

//+------------------------------------------------------------------+
//| Maybe Log Diagnostics                                            |
//+------------------------------------------------------------------+
void CDiagMgrCounters::MaybeLogDiagnostics(const string symbol)
{
    datetime now = TimeCurrent();
    if(now - m_lastDiagLogTime >= m_diagLogIntervalSec)
    {
        LogDiagnostics(symbol);
        m_lastDiagLogTime = now;
    }
}

//+------------------------------------------------------------------+
//| Log Diagnostics                                                  |
//+------------------------------------------------------------------+
void CDiagMgrCounters::LogDiagnostics(const string symbol)
{
    PrintFormat("[CONSENSUS-DIAG] Symbol=%s | Generated=%llu | AfterPipeline=%llu | AfterQuorum=%llu | RawNone=%llu | FilteredOut=%llu | QuorumFailed=%llu | IntrabarNotEligible=%llu | VoteSuppressed=%llu",
                symbol,
                m_diagSignalsGenerated,
                m_diagSignalsAfterPipeline,
                m_diagSignalsAfterQuorum,
                m_diagRawNone,
                m_diagFilteredOut,
                m_diagQuorumFailed,
                m_diagIntrabarNotEligible,
                m_diagVoteSuppressed);
    PrintFormat("[CONSENSUS-DIAG] Role: Primary=%llu Feature=%llu Shadow=%llu | Cluster: Trend=%llu MeanRev=%llu Struct=%llu None=%llu",
                m_diagRolePrimarySignals,
                m_diagRoleFeatureSignals,
                m_diagRoleShadowSignals,
                m_diagClusterTrendSignals,
                m_diagClusterMeanReversionSignals,
                m_diagClusterStructureSignals,
                m_diagClusterNoneSignals);
}

//+------------------------------------------------------------------+
//| Set Snapshot Baselines                                           |
//+------------------------------------------------------------------+
void CDiagMgrCounters::SetSnapshotBaselines()
{
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

#endif // DIAG_MGR_COUNTERS_MQH
