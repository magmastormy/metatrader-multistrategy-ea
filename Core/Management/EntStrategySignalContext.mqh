// Enterprise Strategy Signal Context (Phase G - G3)
// Owns the "last decided signal" bookkeeping and the cycle/lifetime
// signal counters that used to be loose members of
// / m_lastContributorCount
// / m_lastCycleSignalAfterQuorum   (EA heartbeat funnel)
// - m_totalSignals / m_successfulSignals / m_avgConfidence
// BEHAVIOUR NOTE (verified against the pre-extraction source):
// every one of these fields is WRITE-ONCE-AT-CONSTRUCTION in the
// current codebase except m_lastContributorCount /
// (reset by the trade-close path) and m_successfulSignals
// (incremented by the trade-close path). The relocation therefore
// reproduces the original observable values exactly:
// - the three contributor stores start empty (ArrayResize(...,0)
// in the manager constructor, mirrored here);
// - the role / cluster / cluster-code / symbol strings start ""
// and have no writer, so GetLastSignalExecutionContext() keeps
// returning empty tags exactly as before;
// - the funnel counters and the market regime keep MQL5's
// zero-initialised values, which is what the manager exposed.
// The module owns NO back-pointer. The only collaborator it needs
// is the attribution delegator's JoinContributors() (a read-only
// helper it does not own), which is therefore passed in by const
// reference exactly like CStrategyMgrRoster takes the health
// monitor. This avoids reaching into the manager's PRIVATE
// JoinContributors() and keeps the module a leaf value object.
// NOTE: this header is an implementation detail of
// EnterpriseStrategyManager.mqh and is included from there (after
// the shared free helpers, before the manager class). It is not
// intended to be included standalone.
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

    // Statistics
    int    m_totalSignals;
    int    m_successfulSignals;
    double m_avgConfidence;

    ENUM_MARKET_REGIME m_currentMarketRegime;

public:
    CEntStrategySignalContext();

    //--- contributor context -------------------------------------------------
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

    int  GetLastContributorCount() const  { return m_lastContributorCount; }
    int  GetContributorArraySize() const  { return ArraySize(m_lastSignalContributors); }

    //--- reset performed by the trade-close path (verbatim relocation)
    void ResetContributorContext();

    //--- statistics ----------------------------------------------------------
    int    GetTotalSignals() const      { return m_totalSignals; }
    int    GetSuccessfulSignals() const { return m_successfulSignals; }
    double GetAvgConfidence() const     { return m_avgConfidence; }
    void   IncrementSuccessfulSignals() { m_successfulSignals++; }

    //--- last-cycle funnel ---------------------------------------------------
    int  GetLastCycleSignalsGenerated() const     { return m_lastCycleSignalsGenerated; }
    int  GetLastCycleSignalsAfterPipeline() const { return m_lastCycleSignalsAfterPipeline; }
    bool GetLastCycleSignalAfterQuorum() const    { return m_lastCycleSignalAfterQuorum; }

    ENUM_MARKET_REGIME GetCurrentMarketRegime() const { return m_currentMarketRegime; }
};

// Constructor - mirrors the manager's constructor initialisation
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

// Copy the cached contributor names out (verbatim)
void CEntStrategySignalContext::GetLastSignalContributors(string &contributors[]) const
{
    ArrayCopy(contributors, m_lastSignalContributors);
}

// Copy the cached contributor indices out (verbatim)
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

// Reset cached contributor context after close
void CEntStrategySignalContext::ResetContributorContext()
{
    m_lastContributorCount = 0;
    ArrayResize(m_lastSignalContributors, 0);
    ArrayResize(m_lastSignalContributorIndices, 0);
}

#endif // ENT_STRATEGY_SIGNAL_CONTEXT_MQH
