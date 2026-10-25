// Read-only telemetry over CEnterpriseStrategyManager: active-strategy counts, the weights JSON the AI
// adaptation loop reads, and the last-cycle funnel. Reads go through the manager's const accessors only.
// Implementation detail of EnterpriseStrategyManager.mqh - included from there, not standalone.
#ifndef STRATEGY_STATE_REPORTER_MQH
#define STRATEGY_STATE_REPORTER_MQH

#include "../Utils/Enums.mqh"   // enums, SConsensusDecisionContext

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
    void   GetLastCycleFunnel(int &signalsGenerated, int &signalsAfterPipeline, bool &signalAfterQuorum) const;
    int    GetRegisteredStrategyCount() const;
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

int CStrategyStateReporter::GetRegisteredStrategyCount() const
{
    if(m_src == NULL)
        return 0;
    return m_src.GetStrategyCount();
}

#endif // STRATEGY_STATE_REPORTER_MQH
