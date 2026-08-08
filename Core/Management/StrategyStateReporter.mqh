//+------------------------------------------------------------------+
//| Strategy State Reporter (Phase C, Slice 1 - C1)                  |
//| Read-only telemetry / JSON serialization extracted from          |
//| CEnterpriseStrategyManager.                                      |
//|                                                                  |
//| Holds a const back-pointer to the owning manager and reads its    |
//| state exclusively through the manager's minimal const accessor    |
//| surface, so every emitted string is byte-for-byte identical to    |
//| the original implementation.                                      |
//|                                                                  |
//| NOTE: this header is an implementation detail of                  |
//| EnterpriseStrategyManager.mqh and is included from there (after   |
//| the shared free helpers, before the manager class). It is not     |
//| intended to be included standalone.                               |
//+------------------------------------------------------------------+
#ifndef STRATEGY_STATE_REPORTER_MQH
#define STRATEGY_STATE_REPORTER_MQH

#include "../Utils/Enums.mqh"                    // enums, SConsensusDecisionContext, EscapeJsonString
#include "../Pipeline/UnifiedSignalPipeline.mqh" // CUnifiedSignalPipeline (pipeline stats)
#include "DiagnosticsManager.mqh"                // CDiagnosticsManager, SConsensusDiagnosticsSnapshot

class CEnterpriseStrategyManager;   // forward: held only as a const pointer

//+------------------------------------------------------------------+
//| Read-only reporting facade over CEnterpriseStrategyManager        |
//+------------------------------------------------------------------+
class CStrategyStateReporter
{
private:
    const CEnterpriseStrategyManager* m_src;

public:
    CStrategyStateReporter() : m_src(NULL) {}

    void SetSource(const CEnterpriseStrategyManager* src) { m_src = src; }

    int    GetActiveStrategyCount() const;
    int    GetActiveBrainStrategyCount() const;
    string GetStrategyReport() const;
    string GetStrategyWeightsJSON() const;
    string GetStrategyListJSON() const;
    string GetConsensusContextJSON() const;
    static string ConsensusDecisionClassToString(ENUM_CONSENSUS_DECISION_CLASS decisionClass);
    string GetRegisteredStrategyName(const int index) const;
    double GetRegisteredStrategyWeight(const int index) const;
    string GetRegisteredStrategyRole(const int index) const;
    string GetRegisteredStrategyCluster(const int index) const;
    bool   IsRegisteredStrategyLiveVotingEnabled(const int index) const;
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

//+------------------------------------------------------------------+
//| Get Active Strategy Count                                        |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Get Active Brain Strategy Count                                  |
//+------------------------------------------------------------------+
int CStrategyStateReporter::GetActiveBrainStrategyCount() const
{
    if(m_src == NULL)
        return 0;

    int count = 0;
    for(int i = 0; i < m_src.GetStrategyCount(); i++)
    {
        if(!m_src.IsStrategyEnabled(i) || m_src.GetStrategyPtr(i) == NULL)
            continue;

        ENUM_STRATEGY_TYPE strategyType = m_src.GetStrategyPtr(i).GetType();
        if(strategyType == STRATEGY_BRAIN || strategyType == STRATEGY_AI_ENHANCED)
            count++;
    }

    return count;
}

//+------------------------------------------------------------------+
//| Get Strategy Report                                              |
//+------------------------------------------------------------------+
string CStrategyStateReporter::GetStrategyReport() const
{
    if(m_src == NULL)
        return "";

    string report = "=== Enterprise Strategy Report ===\n";
    report += StringFormat("Total Strategies: %d | Active: %d\n", 
                         m_src.GetStrategyCount(), GetActiveStrategyCount());
    report += StringFormat("Total Signals: %d | Success Rate: %.1f%%\n",
                         m_src.GetTotalSignals(), 
                         m_src.GetTotalSignals() > 0 ? (double)m_src.GetSuccessfulSignals()/m_src.GetTotalSignals()*100 : 0);
    
    report += "\nStrategy Performance:\n";
    for(int i = 0; i < m_src.GetStrategyCount(); i++)
    {
        int total = m_src.GetStrategySuccessCount(i) + m_src.GetStrategyFailCount(i);
        double winRate = total > 0 ? (double)m_src.GetStrategySuccessCount(i)/total*100 : 0;
        
        report += StringFormat("- %s: %s | Role: %s | Cluster: %s | LiveVote: %s | Trades: %d | Win Rate: %.1f%% | Avg Conf: %.2f | Participation: %.2f\n",
                             m_src.GetStrategyName(i),
                             m_src.IsStrategyEnabled(i) ? "ON" : "OFF",
                             StrategyRoleToString((ENUM_STRATEGY_ROLE)m_src.GetStrategyRole(i)),
                             StrategyClusterToString((ENUM_STRATEGY_CLUSTER)m_src.GetStrategyCluster(i)),
                             m_src.GetStrategyIsLiveVoter(i) ? "YES" : "NO",
                             total, winRate, m_src.GetStrategyAvgConfidence(i), m_src.GetStrategyParticipationScore(i));
    }
    
    CUnifiedSignalPipeline* pipeline = m_src.GetPipelineConst();
    if(pipeline != NULL)
    {
        report += StringFormat("\nPipeline Stats: Processed: %d | Filtered: %d | Filter Rate: %.1f%%\n",
                             pipeline.GetSignalsProcessed(),
                             pipeline.GetSignalsFiltered(),
                             pipeline.GetFilterRate() * 100);
    }
    
    return report;
}

//+------------------------------------------------------------------+
//| Get Strategy Weights JSON                                        |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Get Strategy List JSON                                           |
//+------------------------------------------------------------------+
string CStrategyStateReporter::GetStrategyListJSON() const
{
    if(m_src == NULL)
        return "[]";

    string symbol = m_src.GetManagedSymbol();

    string json = "[";
    for(int i = 0; i < m_src.GetStrategyCount(); i++)
    {
        if(i > 0)
            json += ",";
        string name = m_src.GetStrategyName(i);
        json += "{";
        json += "\"name\":\"" + EscapeJsonString(name) + "\",";
        json += "\"symbol\":\"" + EscapeJsonString(symbol) + "\",";
        json += "\"role\":\"" + StrategyRoleToString((ENUM_STRATEGY_ROLE)m_src.GetStrategyRole(i)) + "\",";
        json += "\"mode\":\"" + (m_src.IsStrategyEnabled(i) && m_src.IsStrategyLiveVotingEnabled(i) ? "ACTIVE" : "DISABLED") + "\",";
        json += "\"weight\":" + DoubleToString(m_src.GetStrategyWeight(i), 2) + ",";
        json += "\"health_score\":" + DoubleToString(m_src.GetStrategyHealthScore(i), 2) + ",";
        json += "\"win_rate\":" + DoubleToString(m_src.GetStrategyRecentWinRate(i), 2) + ",";
        json += "\"cluster\":\"" + StrategyClusterToString((ENUM_STRATEGY_CLUSTER)m_src.GetStrategyCluster(i)) + "\"";
        json += "}";
    }
    json += "]";
    return json;
}

//+------------------------------------------------------------------+
//| Get Consensus Context JSON                                       |
//+------------------------------------------------------------------+
string CStrategyStateReporter::GetConsensusContextJSON() const
{
    if(m_src == NULL)
        return "{}";

    SConsensusDecisionContext ctx;
    m_src.GetLastDecisionContextValue(ctx);
    string json = "{";
    json += "\"symbol\":\"" + EscapeJsonString(ctx.symbol) + "\",";
    json += "\"signal\":\"" + TradeSignalToString(ctx.signal) + "\",";
    json += "\"confidence\":" + DoubleToString(ctx.confidence, 3) + ",";
    json += "\"buy_score\":" + DoubleToString(ctx.buyScore, 3) + ",";
    json += "\"sell_score\":" + DoubleToString(ctx.sellScore, 3) + ",";
    json += "\"quorum_met\":" + (ctx.signal != TRADE_SIGNAL_NONE ? "true" : "false") + ",";
    json += "\"veto_code\":\"" + EscapeJsonString(ctx.vetoCode) + "\",";
    json += "\"active_strategies\":" + IntegerToString(m_src.GetStrategyCount()) + ",";
    json += "\"voted_strategies\":" + IntegerToString(ctx.eligibleLiveVoterCount) + ",";
    json += "\"dominant_cluster\":\"" + StrategyClusterToString(ctx.dominantCluster) + "\",";
    json += "\"quorum_mode\":\"" + EscapeJsonString(ctx.quorumMode) + "\",";
    json += "\"confluence\":" + IntegerToString(ctx.confluence) + ",";
    json += "\"reason\":\"" + EscapeJsonString(ctx.reason) + "\"";
    json += "}";
    return json;
}

//+------------------------------------------------------------------+
//| Consensus Decision Class to String Conversion                    |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Registered strategy field readers                                |
//+------------------------------------------------------------------+
string CStrategyStateReporter::GetRegisteredStrategyName(const int index) const
{
    if(m_src == NULL)
        return "";
    if(index < 0 || index >= m_src.GetStrategyCount())
        return "";
    return m_src.GetStrategyName(index);
}

double CStrategyStateReporter::GetRegisteredStrategyWeight(const int index) const
{
    if(m_src == NULL)
        return 0.0;
    if(index < 0 || index >= m_src.GetStrategyCount())
        return 0.0;
    return m_src.GetStrategyWeight(index);
}

string CStrategyStateReporter::GetRegisteredStrategyRole(const int index) const
{
    if(m_src == NULL)
        return "";
    if(index < 0 || index >= m_src.GetStrategyCount())
        return "";
    return StrategyRoleToString((ENUM_STRATEGY_ROLE)m_src.GetStrategyRole(index));
}

string CStrategyStateReporter::GetRegisteredStrategyCluster(const int index) const
{
    if(m_src == NULL)
        return "";
    if(index < 0 || index >= m_src.GetStrategyCount())
        return "";
    return StrategyClusterToString((ENUM_STRATEGY_CLUSTER)m_src.GetStrategyCluster(index));
}

bool CStrategyStateReporter::IsRegisteredStrategyLiveVotingEnabled(const int index) const
{
    if(m_src == NULL)
        return false;
    if(index < 0 || index >= m_src.GetStrategyCount())
        return false;
    return m_src.IsStrategyLiveVotingEnabled(index);
}

//+------------------------------------------------------------------+
//| Last decision context                                            |
//+------------------------------------------------------------------+
bool CStrategyStateReporter::GetLastDecisionContext(SConsensusDecisionContext &context) const
{
    if(m_src == NULL)
        return false;
    m_src.GetLastDecisionContextValue(context);
    return (context.signal != TRADE_SIGNAL_NONE);
}

//+------------------------------------------------------------------+
//| Role / cluster diagnostics totals                                |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Last cycle funnel                                                |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Consensus diagnostics snapshot (interval deltas)                 |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Get Registered Strategy Count                                    |
//+------------------------------------------------------------------+
int CStrategyStateReporter::GetRegisteredStrategyCount() const
{
    if(m_src == NULL)
        return 0;
    return m_src.GetStrategyCount();
}

//+------------------------------------------------------------------+
//| Get Ensemble Confidence                                          |
//+------------------------------------------------------------------+
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
