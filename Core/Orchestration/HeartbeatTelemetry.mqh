// Runtime heartbeat / signal-funnel counters for the orchestrator
// Phase B-2: extracted from CEAOrchestrator, which previously held
// 18 loose `ulong m_hbXxx` members. These are WRITE-ONLY telemetry:
// no control flow anywhere in the EA branches on their values, so
// relocating them cannot alter trading behaviour.
// Responsibility: accumulate per-cycle funnel counts and hand them
// to CDiagnosticsManager on each heartbeat tick.
#property strict

#ifndef CORE_ORCHESTRATION_HEARTBEAT_TELEMETRY_MQH
#define CORE_ORCHESTRATION_HEARTBEAT_TELEMETRY_MQH

#include "../Management/DiagnosticsManager.mqh"

// Counter semantics (mirrors CDiagnosticsManager::UpdateCounters):
// scan cadence : scansAttempted, intrabarScansExecuted
// funnel       : signalsGenerated -> AfterPipeline -> AfterQuorum
// -> Validated -> RiskApproved -> Sent
// rejections   : noSignal, validatorRejects, riskRejects,
// entryBlocked, sizingRejects
// quiet paths  : quietNoNewBar, quietCadenceHold,
// quietMissingManager
// outcomes     : tradesOpened, syntheticSpikeEvents
class CHeartbeatTelemetry
{
private:
    // Scan cadence
    ulong m_scansAttempted;
    ulong m_intrabarScansExecuted;

    // Rejection telemetry
    ulong m_noSignalCount;
    ulong m_validatorRejects;
    ulong m_riskRejects;
    ulong m_entryBlocked;
    ulong m_sizingRejects;

    // Quiet-cycle reasons
    ulong m_quietNoNewBar;
    ulong m_quietCadenceHold;
    ulong m_quietMissingManager;

    // Signal funnel
    ulong m_signalsGenerated;
    ulong m_signalsAfterPipeline;
    ulong m_signalsAfterQuorum;
    ulong m_signalsValidated;
    ulong m_signalsRiskApproved;
    ulong m_signalsSent;

    // Outcomes
    ulong m_tradesOpened;
    ulong m_syntheticSpikeEvents;

public:
// Constructor - all counters start at zero
    CHeartbeatTelemetry()
    {
        Reset();
    }

    ~CHeartbeatTelemetry() {}

// Reset every counter to zero
    void Reset()
    {
        m_scansAttempted        = 0;
        m_intrabarScansExecuted = 0;
        m_noSignalCount         = 0;
        m_validatorRejects      = 0;
        m_riskRejects           = 0;
        m_entryBlocked          = 0;
        m_sizingRejects         = 0;
        m_quietNoNewBar         = 0;
        m_quietCadenceHold      = 0;
        m_quietMissingManager   = 0;
        m_signalsGenerated      = 0;
        m_signalsAfterPipeline  = 0;
        m_signalsAfterQuorum    = 0;
        m_signalsValidated      = 0;
        m_signalsRiskApproved   = 0;
        m_signalsSent           = 0;
        m_tradesOpened          = 0;
        m_syntheticSpikeEvents  = 0;
    }

// Increment operations (one per counter)
    void IncScansAttempted()        { m_scansAttempted++; }
    void IncIntrabarScansExecuted() { m_intrabarScansExecuted++; }
    void IncNoSignalCount()         { m_noSignalCount++; }
    void IncValidatorRejects()      { m_validatorRejects++; }
    void IncRiskRejects()           { m_riskRejects++; }
    void IncEntryBlocked()          { m_entryBlocked++; }
    void IncSizingRejects()         { m_sizingRejects++; }
    void IncQuietNoNewBar()         { m_quietNoNewBar++; }
    void IncQuietCadenceHold()      { m_quietCadenceHold++; }
    void IncQuietMissingManager()   { m_quietMissingManager++; }
    void IncSignalsGenerated()      { m_signalsGenerated++; }
    void IncSignalsAfterPipeline()  { m_signalsAfterPipeline++; }
    void IncSignalsAfterQuorum()    { m_signalsAfterQuorum++; }
    void IncSignalsValidated()      { m_signalsValidated++; }
    void IncSignalsRiskApproved()   { m_signalsRiskApproved++; }
    void IncSignalsSent()           { m_signalsSent++; }
    void IncTradesOpened()          { m_tradesOpened++; }
    void IncSyntheticSpikeEvents()  { m_syntheticSpikeEvents++; }

// Accessors (read-only)
    ulong GetScansAttempted()        const { return m_scansAttempted; }
    ulong GetIntrabarScansExecuted() const { return m_intrabarScansExecuted; }
    ulong GetNoSignalCount()         const { return m_noSignalCount; }
    ulong GetValidatorRejects()      const { return m_validatorRejects; }
    ulong GetRiskRejects()           const { return m_riskRejects; }
    ulong GetEntryBlocked()          const { return m_entryBlocked; }
    ulong GetSizingRejects()         const { return m_sizingRejects; }
    ulong GetQuietNoNewBar()         const { return m_quietNoNewBar; }
    ulong GetQuietCadenceHold()      const { return m_quietCadenceHold; }
    ulong GetQuietMissingManager()   const { return m_quietMissingManager; }
    ulong GetSignalsGenerated()      const { return m_signalsGenerated; }
    ulong GetSignalsAfterPipeline()  const { return m_signalsAfterPipeline; }
    ulong GetSignalsAfterQuorum()    const { return m_signalsAfterQuorum; }
    ulong GetSignalsValidated()      const { return m_signalsValidated; }
    ulong GetSignalsRiskApproved()   const { return m_signalsRiskApproved; }
    ulong GetSignalsSent()           const { return m_signalsSent; }
    ulong GetTradesOpened()          const { return m_tradesOpened; }
    ulong GetSyntheticSpikeEvents()  const { return m_syntheticSpikeEvents; }

// Emit
// Pushes the current counter snapshot into the diagnostics
// manager and triggers a heartbeat emission. Argument order is
// identical to the previous inline 18-argument call site, so the
// emitted heartbeat is byte-for-byte unchanged.
// diag - diagnostics manager; NULL is tolerated (no-op).
    void Emit(CDiagnosticsManager* diag) const
    {
        if(diag == NULL)
            return;

        diag.UpdateCounters(
            m_scansAttempted, m_intrabarScansExecuted, m_noSignalCount,
            m_validatorRejects, m_riskRejects, m_tradesOpened, m_syntheticSpikeEvents,
            m_signalsGenerated, m_signalsAfterPipeline, m_signalsAfterQuorum,
            m_signalsValidated, m_signalsRiskApproved, m_signalsSent,
            m_entryBlocked, m_sizingRejects,
            m_quietNoNewBar, m_quietCadenceHold, m_quietMissingManager
        );
        diag.EmitHeartbeat();
    }
};

#endif // CORE_ORCHESTRATION_HEARTBEAT_TELEMETRY_MQH
