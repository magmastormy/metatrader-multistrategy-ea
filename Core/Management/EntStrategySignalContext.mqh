// Last-decided-signal bookkeeping and the cycle/lifetime signal counters, formerly loose members of
// CEnterpriseStrategyManager. Leaf value object: no back-pointer, and JoinContributors() is passed in because
// the attribution delegator owns it. Before Batch 199 the contributor fields had no writer, so attribution,
// authority learning, role/cluster tags and strategy health all read an empty list. The funnel counters still
// hold their construction values - nothing writes them.
// Implementation detail of EnterpriseStrategyManager.mqh - included from there, not standalone.
#ifndef ENT_STRATEGY_SIGNAL_CONTEXT_MQH
#define ENT_STRATEGY_SIGNAL_CONTEXT_MQH

#include "../Utils/Enums.mqh"      // ENUM_MARKET_REGIME
#include "AttributionDelegator.mqh" // CAttributionDelegator::JoinContributors

// Last-signal / cycle telemetry store
class CEntStrategySignalContext
{
private:
    // Last orchestrated decision context for basic trade attribution
    string   m_lastSignalContributors[];
    int      m_lastSignalContributorIndices[];
    int      m_lastContributorCount;
    string   m_lastSignalSymbol;
    datetime m_lastSignalTime;
    string   m_lastSignalRole;
    string   m_lastSignalCluster;
    string   m_lastSignalClusterCode;

    // Last-cycle funnel snapshot (for EA-level heartbeat conversion metrics)
    int  m_lastCycleSignalsGenerated;
    int  m_lastCycleSignalsAfterPipeline;
    bool m_lastCycleSignalAfterQuorum;

    int    m_totalSignals;
    int    m_successfulSignals;
    double m_avgConfidence;

    ENUM_MARKET_REGIME m_currentMarketRegime;

public:
    CEntStrategySignalContext();

    void GetLastSignalContributors(string &contributors[]) const;
    void GetLastSignalContributorIndices(int &indices[]) const;
    //--- `delegator` is the manager's m_attributionDelegator, i.e. exactly the
    //--- object the original inline body reached through its private
    //--- JoinContributors() forwarder (see BEHAVIOUR NOTE).
    bool GetLastSignalExecutionContext(const CAttributionDelegator &delegator,
                                       string &roleTag,
                                       string &clusterTag,
                                       string &clusterCode,
                                       string &contributorsCsv) const;

    //--- reset performed by the trade-close path (verbatim relocation)
    void ResetContributorContext();

    //--- The consensus decision is the only writer. Every reader of this class was waiting on it:
    //--- attribution, AI-authority outcome learning, cluster grouping and strategy health all
    //--- received an empty list while no setter existed.
    void SetContributors(const string &names[], const int &indices[],
                         const string symbolName, const datetime when,
                         const string roleTag, const string clusterTag, const string clusterCodeTag);

    void IncrementTotalSignals() { m_totalSignals++; }

    int    GetTotalSignals() const      { return m_totalSignals; }
    int    GetSuccessfulSignals() const { return m_successfulSignals; }
    double GetAvgConfidence() const     { return m_avgConfidence; }
    void   IncrementSuccessfulSignals() { m_successfulSignals++; }

    int  GetLastCycleSignalsGenerated() const     { return m_lastCycleSignalsGenerated; }
    int  GetLastCycleSignalsAfterPipeline() const { return m_lastCycleSignalsAfterPipeline; }
    bool GetLastCycleSignalAfterQuorum() const    { return m_lastCycleSignalAfterQuorum; }

    ENUM_MARKET_REGIME GetCurrentMarketRegime() const { return m_currentMarketRegime; }
    void SetCurrentMarketRegime(const ENUM_MARKET_REGIME regime) { m_currentMarketRegime = regime; }
};

CEntStrategySignalContext::CEntStrategySignalContext() :
    m_lastContributorCount(0),
    m_lastSignalSymbol(""),
    m_lastSignalTime(0),
    m_lastSignalRole(""),
    m_lastSignalCluster(""),
    m_lastSignalClusterCode(""),
    m_lastCycleSignalsGenerated(0),
    m_lastCycleSignalsAfterPipeline(0),
    m_lastCycleSignalAfterQuorum(false),
    m_totalSignals(0),
    m_successfulSignals(0),
    m_avgConfidence(0.0),
    m_currentMarketRegime((ENUM_MARKET_REGIME)0)
{
    ArrayResize(m_lastSignalContributors, 0);
    ArrayResize(m_lastSignalContributorIndices, 0);
}

void CEntStrategySignalContext::GetLastSignalContributors(string &contributors[]) const
{
    ArrayCopy(contributors, m_lastSignalContributors);
}

void CEntStrategySignalContext::GetLastSignalContributorIndices(int &indices[]) const
{
    ArrayCopy(indices, m_lastSignalContributorIndices);
}

// Role / cluster / contributor CSV of the last executed signal
// The CSV is produced by the manager's attribution delegator, which
// is exactly what the original inline body used.
bool CEntStrategySignalContext::GetLastSignalExecutionContext(const CAttributionDelegator &delegator,
                                                              string &roleTag,
                                                              string &clusterTag,
                                                              string &clusterCode,
                                                              string &contributorsCsv) const
{
    roleTag = m_lastSignalRole;
    clusterTag = m_lastSignalCluster;
    clusterCode = m_lastSignalClusterCode;
    contributorsCsv = delegator.JoinContributors(m_lastSignalContributors);
    return (m_lastContributorCount > 0 && ArraySize(m_lastSignalContributors) > 0);
}

void CEntStrategySignalContext::ResetContributorContext()
{
    m_lastContributorCount = 0;
    ArrayResize(m_lastSignalContributors, 0);
    ArrayResize(m_lastSignalContributorIndices, 0);
}

void CEntStrategySignalContext::SetContributors(const string &names[], const int &indices[],
                                                const string symbolName, const datetime when,
                                                const string roleTag, const string clusterTag,
                                                const string clusterCodeTag)
{
    int count = ArraySize(names);
    ArrayResize(m_lastSignalContributors, count);
    for(int i = 0; i < count; i++)
        m_lastSignalContributors[i] = names[i];

    int idxCount = ArraySize(indices);
    ArrayResize(m_lastSignalContributorIndices, idxCount);
    for(int i = 0; i < idxCount; i++)
        m_lastSignalContributorIndices[i] = indices[i];

    m_lastContributorCount = count;
    m_lastSignalSymbol = symbolName;
    m_lastSignalTime = when;
    m_lastSignalRole = roleTag;
    m_lastSignalCluster = clusterTag;
    m_lastSignalClusterCode = clusterCodeTag;
}

#endif // ENT_STRATEGY_SIGNAL_CONTEXT_MQH
