//+------------------------------------------------------------------+
//| OrchestratorStatusReporter.mqh                                   |
//| Read-only status-text aggregation for the EA orchestrator        |
//|                                                                  |
//| Extracted verbatim from CEAOrchestrator::GetStatusReport(). The   |
//| method is pure string assembly over collaborator status text: it  |
//| reads no orchestrator state it does not receive, mutates nothing, |
//| and is only consumed by the heartbeat log                         |
//|                                                                  |
//| Wiring: the orchestrator injects its collaborators once, from     |
//| WireAndValidateDependencies(). The volatile per-cycle counters    |
//| (call count, live position count, ...) cannot be captured by      |
//| pointer in MQL5, so they are passed per call - the assembled      |
//| string is therefore identical to the original, line for line.     |
//+------------------------------------------------------------------+
#property strict

#ifndef CORE_ORCHESTRATION_ORCHESTRATOR_STATUS_REPORTER_MQH
#define CORE_ORCHESTRATION_ORCHESTRATOR_STATUS_REPORTER_MQH

#include "LiveAuthorityResolver.mqh"
#include "../Position/PositionManager.mqh"
#include "../Registry/RegistryAggregator.mqh"
#include "../Registry/MathematicalEngineRegistry.mqh"
#include "../Registry/InstitutionalEngineRegistry.mqh"
#include "../Registry/NeuralNetRegistry.mqh"
#include "../Registry/DrawingManagerRegistry.mqh"
#include "../Registry/ScanSchedulerRegistry.mqh"
#include "../Registry/SymbolStateTracker.mqh"
#include "../Management/EnterpriseStrategyManager.mqh"

//+------------------------------------------------------------------+
//| COrchestratorStatusReporter                                      |
//|                                                                  |
//| Aggregates the status text of the orchestrator's collaborators.   |
//| Holds borrowed pointers only - it owns nothing and deletes        |
//| nothing.                                                          |
//+------------------------------------------------------------------+
class COrchestratorStatusReporter
{
private:
    // Borrowed collaborators (owned by CEAOrchestrator).
    CRegistryAggregator*        m_registryAggregator;
    CLiveAuthorityResolver*     m_liveAuthority;
    CPositionManager*           m_positionManager;
    CEnterpriseStrategyManager* m_primaryManager;   // == m_enterpriseManagers[0]

public:
    COrchestratorStatusReporter()
        : m_registryAggregator(NULL),
          m_liveAuthority(NULL),
          m_positionManager(NULL),
          m_primaryManager(NULL)
    {
    }

    ~COrchestratorStatusReporter() {}

    //+--------------------------------------------------------------+
    //| SetManagers                                                  |
    //|                                                              |
    //| Injects the borrowed collaborators. Called once from          |
    //| CEAOrchestrator::WireAndValidateDependencies().               |
    //|                                                              |
    //| registryAggregator - registry hub (math/inst/neural/draw/scan)|
    //| liveAuthority      - AI-vs-indicator authority resolver       |
    //| positionManager    - position lifecycle authority             |
    //| primaryManager     - enterprise manager slot 0, may be NULL   |
    //+--------------------------------------------------------------+
    void SetManagers(CRegistryAggregator*        registryAggregator,
                     CLiveAuthorityResolver*     liveAuthority,
                     CPositionManager*           positionManager,
                     CEnterpriseStrategyManager* primaryManager)
    {
        m_registryAggregator = registryAggregator;
        m_liveAuthority      = liveAuthority;
        m_positionManager    = positionManager;
        m_primaryManager     = primaryManager;
    }

    //+--------------------------------------------------------------+
    //| Init                                                         |
    //|                                                              |
    //| SetManagers + validity check, for callers that want a         |
    //| pass/fail result. Returns true when every non-optional        |
    //| collaborator is present (primaryManager is optional, exactly  |
    //| as the original NULL-guarded report section was).             |
    //+--------------------------------------------------------------+
    bool Init(CRegistryAggregator*        registryAggregator,
              CLiveAuthorityResolver*     liveAuthority,
              CPositionManager*           positionManager,
              CEnterpriseStrategyManager* primaryManager)
    {
        SetManagers(registryAggregator, liveAuthority, positionManager, primaryManager);
        return IsWired();
    }

    //+--------------------------------------------------------------+
    //| ClearEnterpriseManager                                       |
    //|                                                              |
    //| Drops the borrowed enterprise-manager pointer. Called from    |
    //| CEAOrchestrator::ReleaseEnterpriseManagers() so the cached    |
    //| pointer cannot outlive the object it refers to; this mirrors  |
    //| the original code, which re-read m_enterpriseManagers[0] on   |
    //| every call and skipped the section once it was NULL.          |
    //+--------------------------------------------------------------+
    void ClearEnterpriseManager()
    {
        m_primaryManager = NULL;
    }

    //+--------------------------------------------------------------+
    //| IsWired - true when the mandatory collaborators are present   |
    //+--------------------------------------------------------------+
    bool IsWired() const
    {
        return (m_registryAggregator != NULL &&
                m_liveAuthority      != NULL &&
                m_positionManager    != NULL);
    }

    //+--------------------------------------------------------------+
    //| GetStatusReport                                              |
    //|                                                              |
    //| Assembles the heartbeat status text. Body moved verbatim from |
    //| CEAOrchestrator::GetStatusReport(); the only change is that   |
    //| the value members it used to read directly are now borrowed   |
    //| pointers (hence the NULL guards on the two formerly           |
    //| unconditional lines) and the per-cycle counters arrive as     |
    //| arguments.                                                    |
    //|                                                              |
    //| systemInitialized - orchestrator init flag                    |
    //| tradingEnabled    - orchestrator trading flag                 |
    //| managerCount      - number of enterprise managers             |
    //| callCount         - orchestrator cycle counter                |
    //| scansAttempted    - heartbeat telemetry: scans attempted      |
    //| signalsValidated  - heartbeat telemetry: signals validated    |
    //| signalsSent       - heartbeat telemetry: signals sent         |
    //| eaPositionCount   - live EA-owned position count              |
    //| maxPositionsTotal - configured position cap                   |
    //| returns           - the assembled multi-line status report    |
    //+--------------------------------------------------------------+
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
        if(m_positionManager != NULL)
            report += m_positionManager.GetStatusReport();
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
        CSymbolStateTracker* trackerReport = m_registryAggregator.GetSymbolStateTracker();
        if(trackerReport != NULL)
        report += trackerReport.GetStatusReport();

        return report;
    }
};

#endif // CORE_ORCHESTRATION_ORCHESTRATOR_STATUS_REPORTER_MQH
