// Runtime heartbeat / signal-funnel counters for the orchestrator.
// Accumulates per-cycle funnel counts and hands them to CDiagnosticsManager on each heartbeat tick.
// WRITE-ONLY telemetry: no control flow anywhere in the EA branches on these values.
#property strict

#ifndef CORE_ORCHESTRATION_HEARTBEAT_TELEMETRY_MQH
#define CORE_ORCHESTRATION_HEARTBEAT_TELEMETRY_MQH

#include "../Management/DiagnosticsManager.mqh"

// Counters mirror CDiagnosticsManager::UpdateCounters' argument set. Funnel order:
// signalsGenerated -> Validated -> Sent. Every counter here has a writer; the seven that had none
// (intrabar scans, risk rejects, entry blocked, sizing rejects, the three quiet-cycle reasons,
// after-pipeline, after-quorum, risk-approved and trades-opened) are deleted rather than left
// printing a zero that reads as a measurement.
class CHeartbeatTelemetry
{
private:
    ulong m_scansAttempted;

    ulong m_noSignalCount;
    ulong m_validatorRejects;

    ulong m_signalsGenerated;
    ulong m_signalsValidated;
    ulong m_signalsSent;

    ulong m_syntheticSpikeEvents;

    // Scan-cost accumulator. The orchestrator already measures each cycle's wall time in microseconds
    // (`GenerateAndProcessSignals_Total_us`) and writes it as one journal line per cycle; that is
    // 15,876 lines per session for a number nobody aggregates. Accumulating here and printing one
    // summary per heartbeat makes "is the scan fast?" a reading instead of a search.
    ulong m_scanUsTotal;
    ulong m_scanUsMax;
    ulong m_scanCostSamples;

public:
    CHeartbeatTelemetry()
    {
        Reset();
    }

    ~CHeartbeatTelemetry() {}

    void Reset()
    {
        m_scansAttempted       = 0;
        m_noSignalCount        = 0;
        m_validatorRejects     = 0;
        m_signalsGenerated     = 0;
        m_signalsValidated     = 0;
        m_signalsSent          = 0;
        m_syntheticSpikeEvents = 0;
        m_scanUsTotal          = 0;
        m_scanUsMax            = 0;
        m_scanCostSamples      = 0;
    }

    void IncScansAttempted()        { m_scansAttempted++; }
    void IncNoSignalCount()         { m_noSignalCount++; }
    void IncValidatorRejects()      { m_validatorRejects++; }
    void IncSignalsGenerated()      { m_signalsGenerated++; }
    void IncSignalsValidated()      { m_signalsValidated++; }
    void IncSignalsSent()           { m_signalsSent++; }
    void IncSyntheticSpikeEvents(const ulong count = 1) { m_syntheticSpikeEvents += count; }

    void IncScanCost(const ulong elapsedUs)
    {
        m_scanUsTotal += elapsedUs;
        if(elapsedUs > m_scanUsMax)
            m_scanUsMax = elapsedUs;
        m_scanCostSamples++;
    }

    ulong GetScanCostSamples() const { return m_scanCostSamples; }
    ulong GetScanCostMaxUs()   const { return m_scanUsMax; }
    ulong GetScanCostAvgUs()   const { return (m_scanCostSamples > 0) ? (m_scanUsTotal / m_scanCostSamples) : 0; }
    void  ResetScanCost()            { m_scanUsTotal = 0; m_scanUsMax = 0; m_scanCostSamples = 0; }

// UpdateCounters takes 7 positional arguments: the order below must match the
// manager's parameter list exactly. NULL diag is tolerated (no-op). tradingPaused comes
// from CSyntheticSpikeMonitor, the only holder of that state.
    void Emit(CDiagnosticsManager* diag, const bool tradingPaused) const
    {
        if(diag == NULL)
            return;

        diag.SetTradingPaused(tradingPaused);

        diag.UpdateCounters(
            m_scansAttempted, m_noSignalCount, m_validatorRejects,
            m_signalsGenerated, m_signalsValidated, m_signalsSent,
            m_syntheticSpikeEvents
        );
        diag.EmitHeartbeat();
    }
};

#endif // CORE_ORCHESTRATION_HEARTBEAT_TELEMETRY_MQH
