// Read-only status-text aggregation, extracted verbatim from CEAOrchestrator::GetStatusReport(). It reads no
// orchestrator state it does not receive and mutates nothing. The volatile per-cycle counters (call count,
// live position count) cannot be captured by pointer in MQL5, so they arrive per call.
#property strict

#ifndef CORE_ORCHESTRATION_ORCHESTRATOR_STATUS_REPORTER_MQH
#define CORE_ORCHESTRATION_ORCHESTRATOR_STATUS_REPORTER_MQH

#include "LiveAuthorityResolver.mqh"
#include "../Registry/RegistryAggregator.mqh"
#include "../Registry/MathematicalEngineRegistry.mqh"
#include "../Registry/InstitutionalEngineRegistry.mqh"
#include "../Registry/NeuralNetRegistry.mqh"
#include "../Registry/DrawingManagerRegistry.mqh"
#include "../Registry/ScanSchedulerRegistry.mqh"
#include "../Management/EnterpriseStrategyManager.mqh"

// Aggregates the status text of the orchestrator's collaborators.
// Holds borrowed pointers only - it owns nothing and deletes
// nothing.
class COrchestratorStatusReporter
{
private:
    // Borrowed collaborators (owned by CEAOrchestrator).
    CRegistryAggregator*        m_registryAggregator;
    CLiveAuthorityResolver*     m_liveAuthority;
    CEnterpriseStrategyManager* m_primaryManager;

public:
    COrchestratorStatusReporter()
        : m_registryAggregator(NULL),
          m_liveAuthority(NULL),
          m_primaryManager(NULL)
    {
    }

    ~COrchestratorStatusReporter() {}

// Injects the borrowed collaborators. Called once from
// CEAOrchestrator::WireAndValidateDependencies().
// registryAggregator - registry hub (math/inst/neural/draw/scan)
// liveAuthority      - AI-vs-indicator authority resolver
// primaryManager     - enterprise manager slot 0, may be NULL
    void SetManagers(CRegistryAggregator*        registryAggregator,
                     CLiveAuthorityResolver*     liveAuthority,
                     CEnterpriseStrategyManager* primaryManager)
    {
        m_registryAggregator = registryAggregator;
        m_liveAuthority      = liveAuthority;
        m_primaryManager     = primaryManager;
    }

// Drops the borrowed enterprise-manager pointer. Called from
// CEAOrchestrator::ReleaseEnterpriseManagers() so the cached
// pointer cannot outlive the object it refers to; this mirrors
// the original code, which re-read m_enterpriseManagers[0] on
// every call and skipped the section once it was NULL.
    void ClearEnterpriseManager()
    {
        m_primaryManager = NULL;
    }

// Assembles the heartbeat status text. Body moved verbatim from CEAOrchestrator::GetStatusReport(); the value
// members it read directly are borrowed pointers now, hence the NULL guards on two formerly unconditional
// lines, and the per-cycle counters arrive as arguments.
    string GetStatusReport(const bool  systemInitialized,
                           const bool  tradingEnabled,
                           const int   managerCount,
                           const int   callCount,
                           const ulong scansAttempted,
                           const ulong signalsValidated,
                           const ulong signalsSent,
                           const int   eaPositionCount,
                           const int   maxPositionsTotal) const
    {
        string report = "[EAOrchestrator] ";
        report += "Initialized=" + (systemInitialized ? "Y" : "N");
        report += " | Trading=" + (tradingEnabled ? "Y" : "N");
        report += " | Managers=" + IntegerToString(managerCount);
        report += " | Cycle=" + IntegerToString(callCount);
        report += " | Scans=" + IntegerToString(scansAttempted);
        report += " | Validated=" + IntegerToString(signalsValidated);
        report += " | Sent=" + IntegerToString(signalsSent);
        report += " | Positions=" + IntegerToString(eaPositionCount) + "/" + IntegerToString(maxPositionsTotal) + "\n";

        // report += m_signalGenerator.GetStatusReport(); // Method not found on CSignalGenerator
        if(m_primaryManager != NULL)
            report += m_primaryManager.GetValidationStatusReport();
        if(m_liveAuthority != NULL)
            report += m_liveAuthority.GetStatusReport();
        if(m_registryAggregator == NULL)
            return report;

        CMathematicalEngineRegistry* mathRegReport = m_registryAggregator.GetMathRegistry();
        if(mathRegReport != NULL)
        report += mathRegReport.GetStatusReport();
        CInstitutionalEngineRegistry* instRegReport = m_registryAggregator.GetInstitutionalRegistry();
        if(instRegReport != NULL)
        report += instRegReport.GetStatusReport();
        CNeuralNetRegistry* neuralRegReport = m_registryAggregator.GetNeuralNetRegistry();
        if(neuralRegReport != NULL)
        report += neuralRegReport.GetStatusReport();
        CDrawingManagerRegistry* drawRegReport = m_registryAggregator.GetDrawingRegistry();
        if(drawRegReport != NULL)
        report += drawRegReport.GetStatusReport();
        CScanSchedulerRegistry* scanRegReport = m_registryAggregator.GetScanRegistry();
        if(scanRegReport != NULL)
        report += scanRegReport.GetStatusReport();

        return report;
    }
};

#endif // CORE_ORCHESTRATION_ORCHESTRATOR_STATUS_REPORTER_MQH
