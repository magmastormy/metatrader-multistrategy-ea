// Read-only telemetry over CEnterpriseStrategyManager: active-strategy counts, the weights JSON the AI
// adaptation loop reads, and the consensus diagnostics snapshot. Reads go through the manager's const
// accessors only.
// Implementation detail of EnterpriseStrategyManager.mqh - included from there, not standalone.
#ifndef STRATEGY_STATE_REPORTER_MQH
#define STRATEGY_STATE_REPORTER_MQH

#include "../Utils/Enums.mqh"   // enums, SConsensusDecisionContext
#include "DiagnosticsManager.mqh"                // CDiagnosticsManager, SConsensusDiagnosticsSnapshot

class CEnterpriseStrategyManager;   // forward: held only as a const pointer

// Read-only reporting facade over CEnterpriseStrategyManager
class CStrategyStateReporter
{
private:
    const CEnterpriseStrategyManager* m_src;

public:
    CStrategyStateReporter() : m_src(NULL) {}

    void SetSource(const CEnterpriseStrategyManager* src) { m_src = src; }

    int    GetActiveStrategyCount() const;
    string GetStrategyWeightsJSON() const;
    static string ConsensusDecisionClassToString(ENUM_CONSENSUS_DECISION_CLASS decisionClass);
    string GetRegisteredStrategyName(const int index) const;
    bool   GetLastDecisionContext(SConsensusDecisionContext &context) const;
    void   GetRoleClusterDiagnosticsTotals(ulong &primarySignals,
                                           ulong &featureSignals,
                                           ulong &voteSuppressed,
                                           ulong &trendClusterSignals,
                                           ulong &meanReversionClusterSignals,
                                           ulong &structureClusterSignals,
                                           ulong &noneClusterSignals) const;
    void   GetLastCycleFunnel(int &signalsGenerated, int &signalsAfterPipeline, bool &signalAfterQuorum) const;
    void   GetConsensusDiagnosticsSnapshot(ulong &rawNone,
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
    int    GetRegisteredStrategyCount() const;
    double GetEnsembleConfidence() const;
};

int CStrategyStateReporter::GetActiveStrategyCount() const
{
    if(m_src == NULL)
        return 0;

    int count = 0;
    for(int i = 0; i < m_src.GetStrategyCount(); i++)
    {
        if(m_src.IsStrategyEnabled(i))
            count++;
    }
    return count;
}

string CStrategyStateReporter::GetStrategyWeightsJSON() const
{
    if(m_src == NULL)
        return "{}";

    string json = "{";
    for(int i = 0; i < m_src.GetStrategyCount(); i++)
    {
        string key = m_src.GetStrategyName(i);
        StringReplace(key, "\\", "\\\\");
        StringReplace(key, "\"", "\\\"");
        json += StringFormat("\"%s\":%.4f", key, m_src.GetStrategyWeight(i));
        if(i < (m_src.GetStrategyCount() - 1))
            json += ",";
    }
    json += "}";
    return json;
}

string CStrategyStateReporter::ConsensusDecisionClassToString(ENUM_CONSENSUS_DECISION_CLASS decisionClass)
{
    switch(decisionClass)
    {
        case CONSENSUS_DECISION_NONE:
            return "NONE";
        case CONSENSUS_DECISION_FULL_QUORUM:
            return "FULL_QUORUM";
        case CONSENSUS_DECISION_SPARSE_INTRABAR:
            return "SPARSE_INTRABAR";
        case CONSENSUS_DECISION_VETOED:
            return "VETOED";
        case CONSENSUS_DECISION_MARGINAL_ADMIT:
            return "MARGINAL_ADMIT";
        case CONSENSUS_DECISION_SOLO_FALLBACK:
            return "SOLO_FALLBACK";
        default:
            return "UNKNOWN";
    }
}

string CStrategyStateReporter::GetRegisteredStrategyName(const int index) const
{
    if(m_src == NULL)
        return "";
    if(index < 0 || index >= m_src.GetStrategyCount())
        return "";
    return m_src.GetStrategyName(index);
}

bool CStrategyStateReporter::GetLastDecisionContext(SConsensusDecisionContext &context) const
{
    if(m_src == NULL)
        return false;
    m_src.GetLastDecisionContextValue(context);
    return (context.signal != TRADE_SIGNAL_NONE);
}

void CStrategyStateReporter::GetRoleClusterDiagnosticsTotals(ulong &primarySignals,
                                                             ulong &featureSignals,
                                                             ulong &voteSuppressed,
                                                             ulong &trendClusterSignals,
                                                             ulong &meanReversionClusterSignals,
                                                             ulong &structureClusterSignals,
                                                             ulong &noneClusterSignals) const
{
    CDiagnosticsManager* diagnostics = (m_src != NULL) ? m_src.GetDiagnosticsConst() : NULL;
    if(diagnostics != NULL)
    {
        primarySignals = diagnostics.GetRolePrimarySignals();
        featureSignals = diagnostics.GetRoleFeatureSignals();
        voteSuppressed = diagnostics.GetVoteSuppressed();
        trendClusterSignals = diagnostics.GetClusterTrendSignals();
        meanReversionClusterSignals = diagnostics.GetClusterMeanReversionSignals();
        structureClusterSignals = diagnostics.GetClusterStructureSignals();
        noneClusterSignals = diagnostics.GetClusterNoneSignals();
    }
    else
    {
        primarySignals = featureSignals = voteSuppressed = 0;
        trendClusterSignals = meanReversionClusterSignals = structureClusterSignals = noneClusterSignals = 0;
    }
}

void CStrategyStateReporter::GetLastCycleFunnel(int &signalsGenerated, int &signalsAfterPipeline, bool &signalAfterQuorum) const
{
    if(m_src == NULL)
    {
        signalsGenerated = 0;
        signalsAfterPipeline = 0;
        signalAfterQuorum = false;
        return;
    }
    signalsGenerated = m_src.GetLastCycleSignalsGeneratedValue();
    signalsAfterPipeline = m_src.GetLastCycleSignalsAfterPipelineValue();
    signalAfterQuorum = m_src.GetLastCycleSignalAfterQuorumValue();
}

// Consensus diagnostics snapshot (interval deltas)
void CStrategyStateReporter::GetConsensusDiagnosticsSnapshot(ulong &rawNone,
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
    CDiagnosticsManager* diagnostics = (m_src != NULL) ? m_src.GetDiagnosticsConst() : NULL;
    if(diagnostics == NULL)
    {
        rawNone = filteredOut = quorumFailed = intrabarNotEligible = 0;
        signalsGenerated = signalsAfterPipeline = signalsAfterQuorum = 0;
        momentumNone = momentumCooldown = momentumLowVolatility = momentumNoCrossover = 0;
        momentumTrendMisaligned = momentumNotReady = 0;
        uictNone = uictNeutralBias = uictOtherFilters = 0;
        intervalReasonTotal = 0;
        return;
    }

    // Get full snapshot from diagnostics collector
    SConsensusDiagnosticsSnapshot snapshot;
    diagnostics.GetFullDiagnosticsSnapshot(snapshot);

    // Calculate interval values (delta from snapshot baseline)
    rawNone = (snapshot.rawNone - snapshot.snapshotBaselineRawNone);
    filteredOut = (snapshot.filteredOut - snapshot.snapshotBaselineFilteredOut);
    quorumFailed = (snapshot.quorumFailed - snapshot.snapshotBaselineQuorumFailed);
    intrabarNotEligible = (snapshot.intrabarNotEligible - snapshot.snapshotBaselineIntrabarNotEligible);
    signalsGenerated = (snapshot.signalsGenerated - snapshot.snapshotBaselineSignalsGenerated);
    signalsAfterPipeline = (snapshot.signalsAfterPipeline - snapshot.snapshotBaselineSignalsAfterPipeline);
    signalsAfterQuorum = (snapshot.signalsAfterQuorum - snapshot.snapshotBaselineSignalsAfterQuorum);
    momentumNone = (snapshot.momentumNone - snapshot.snapshotBaselineMomentumNone);
    momentumCooldown = (snapshot.momentumCooldown - snapshot.snapshotBaselineMomentumCooldown);
    momentumLowVolatility = (snapshot.momentumLowVolatility - snapshot.snapshotBaselineMomentumLowVolatility);
    momentumNoCrossover = (snapshot.momentumNoCrossover - snapshot.snapshotBaselineMomentumNoCrossover);
    momentumTrendMisaligned = (snapshot.momentumTrendMisaligned - snapshot.snapshotBaselineMomentumTrendMisaligned);
    momentumNotReady = (snapshot.momentumNotReady - snapshot.snapshotBaselineMomentumNotReady);
    uictNone = (snapshot.uictNone - snapshot.snapshotBaselineUICTNone);
    uictNeutralBias = (snapshot.uictNeutralBias - snapshot.snapshotBaselineUICTNeutralBias);
    uictOtherFilters = (snapshot.uictOtherFilters - snapshot.snapshotBaselineUICTOtherFilters);
    intervalReasonTotal = rawNone + filteredOut + quorumFailed + intrabarNotEligible;
}

int CStrategyStateReporter::GetRegisteredStrategyCount() const
{
    if(m_src == NULL)
        return 0;
    return m_src.GetStrategyCount();
}

double CStrategyStateReporter::GetEnsembleConfidence() const
{
    if(m_src == NULL)
        return 0.0;

    double weightedSum = 0.0;
    double totalWeight = 0.0;
    for(int i = 0; i < m_src.GetStrategyCount(); i++)
    {
        if(!m_src.IsStrategyEnabled(i) || m_src.GetStrategyPtr(i) == NULL)
            continue;
        double weight = MathMax(0.0, m_src.GetStrategyWeight(i));
        double conf = MathMax(0.0, m_src.GetStrategyAvgConfidence(i));
        if(weight <= 0.0)
            continue;
        weightedSum += (conf * weight);
        totalWeight += weight;
    }
    if(totalWeight <= 0.0)
        return 0.0;
    return MathMax(0.0, MathMin(1.0, weightedSum / totalWeight));
}

#endif // STRATEGY_STATE_REPORTER_MQH
