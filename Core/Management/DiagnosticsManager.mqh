// Heartbeat/diagnostics logging: the OnTick heartbeat block that used to sit inline in
// MultiStrategyAutonomousEA.mq5. This class is the coordinator; the emitting work lives
// in the DiagMgr* modules listed in the includes below.
// Emitted log strings and counter semantics are fixed on purpose - regression logs from
// different builds have to stay directly comparable.
#ifndef DIAGNOSTICS_MANAGER_MQH
#define DIAGNOSTICS_MANAGER_MQH

#include "../Utils/Enums.mqh"
#include "../Risk/UnifiedRiskManager.mqh"
#include "../Risk/RiskTierManager.mqh"
#include "../Risk/CompoundingTierManager.mqh"
#include "../Utils/DiagnosticsLogger.mqh"
#include "../Utils/JsonLogger.mqh"
#include "../Utils/LogMacros.mqh"
#include "../Scalp/FastScalpEngine.mqh"
#include "../Risk/FullMarginMode.mqh"
#include "../Risk/SafeModeConfig.mqh"
#include "../Monitoring/PerformanceAnalytics.mqh"
#include "../../IndicatorManager.mqh"
// The manager is held only as `CEnterpriseStrategyManager* m_managers[]` here, never dereferenced, so a
// forward declaration is the whole requirement. Including EnterpriseStrategyManager.mqh closed a cycle:
// it includes ConsensusEngine.mqh, which includes this file - and the cycle resolved only by include
// order (whichever of the three a translation unit happened to include first decided whether the type
// was complete when the other two needed it).
class CEnterpriseStrategyManager;
#include "../Processing/DerivAssetProfiler.mqh"
#include "../Processing/MultiAssetProfiler.mqh"
#include "../Engines/SessionWeightManager.mqh"
#include "../Engines/SkewStepAnalyzer.mqh"
#include "../Engines/FamilyStrategyWeightMatrix.mqh"

//--- DiagMgr* modules (by-value members / static helpers): keep these last and in this
//--- order - include-resolution order is what the earlier headers see.
#include "DiagMgrAIVote.mqh"            // CDiagMgrAIVoteTracker, ENUM_AI_VOTE_TYPE
#include "DiagMgrHeartbeat.mqh"         // CDiagMgrHeartbeat

class CNeuralNetworkStrategy;

// Counter values are pushed in via UpdateCounters() each heartbeat cycle: MQL5 has no
// pointer to a primitive (no ulong*), so the main EA supplies the snapshot itself.
class CDiagnosticsManager
{
private:
    CUnifiedRiskManager*     m_riskManager;
    CRiskTierManager*        m_riskTierManager;
    CFastScalpEngine*        m_scalpEngine;
    CFullMarginMode*         m_fullMarginMode;
    CSafeMode*               m_safeMode;
    CCompoundingTierManager* m_compoundingTierManager;
    CSessionWeightManager*   m_sessionWeightManager;
        CSkewStepAnalyzer*     m_skewStepAnalyzer;
        CFamilyStrategyWeightMatrix* m_familyWeightMatrix;
            CDerivAssetProfiler*     m_derivProfiler;
        CMultiAssetProfiler*     m_multiAssetProfiler;
        bool                     m_initialized;
            ENUM_LOG_VERBOSITY       m_verbosity;

    int      m_heartbeatIntervalSec;
    datetime m_lastHeartbeatTime;
    datetime m_lastNoSignalAlertTime;

    // Current counter snapshot (pushed by main EA)
    ulong m_hbScansAttempted;
    ulong m_hbNoSignalCount;
    ulong m_hbValidatorRejects;
    ulong m_hbSyntheticSpikeEvents;
    ulong m_hbSignalsGenerated;
    ulong m_hbSignalsValidated;
    ulong m_hbSignalsSent;

    // Previous-window snapshots (updated at end of each heartbeat)
    ulong m_prevScansAttempted;
    ulong m_prevNoSignalCount;
    ulong m_prevSignalsGenerated;
    ulong m_prevSignalsValidated;
    ulong m_prevSignalsSent;

    // Consensus counter bank; every counter accessor below forwards to it

        bool  m_aiEnabled;
        bool  m_nnEnabled;
        bool  m_nnOnlineTraining;
        bool  m_transformerEnabled;
        bool  m_ensembleEnabled;
        bool  m_onnxEnabled;

        // Gates the full-margin / safe-mode diagnostic blocks
    ENUM_RISK_TIER m_riskTier;

    // Trading paused state, pushed with each heartbeat from CSyntheticSpikeMonitor::IsPaused()
    bool  m_tradingPaused;

        CEnterpriseStrategyManager* m_managers[];
        int                         m_managerCount;
        string                      m_symbols[];
        int                         m_symbolCount;

        // AI vote heartbeat tracking
        CDiagMgrAIVoteTracker m_aiVoteTracker;

public:
    CDiagnosticsManager() :
        m_riskManager(NULL),
        m_riskTierManager(NULL),
        m_scalpEngine(NULL),
        m_fullMarginMode(NULL),
        m_safeMode(NULL),
                m_derivProfiler(NULL),
                m_multiAssetProfiler(NULL),
                m_initialized(false),
                m_verbosity(VERBOSITY_NORMAL),
                m_heartbeatIntervalSec(60),
                m_lastHeartbeatTime(0),
                m_lastNoSignalAlertTime(0),
        m_hbScansAttempted(0),
        m_hbNoSignalCount(0),
        m_hbValidatorRejects(0),
        m_hbSyntheticSpikeEvents(0),
        m_hbSignalsGenerated(0),
        m_hbSignalsValidated(0),
        m_hbSignalsSent(0),
        m_prevScansAttempted(0),
        m_prevNoSignalCount(0),
        m_prevSignalsGenerated(0),
        m_prevSignalsValidated(0),
        m_prevSignalsSent(0),
        m_aiEnabled(false),
                m_nnEnabled(false),
                m_nnOnlineTraining(false),
                m_transformerEnabled(false),
                m_ensembleEnabled(false),
                m_onnxEnabled(false),
                m_riskTier(RISK_TIER_MODERATE),
                m_tradingPaused(false),
                m_managerCount(0),
                m_symbolCount(0)
            {}

    ~CDiagnosticsManager() {}

// Must run before EmitHeartbeat(); the heartbeat interval is floored at 30s to cap log volume
        bool Initialize(CUnifiedRiskManager* rm, CRiskTierManager* rtm,
                        CCompoundingTierManager* compoundingTierManager, int heartbeatInterval,
                        ENUM_LOG_VERBOSITY verbosity = VERBOSITY_NORMAL)
        {
            if(rm == NULL || rtm == NULL)
                return false;
            m_riskManager = rm;
            m_riskTierManager = rtm;
            m_compoundingTierManager = compoundingTierManager;
            m_heartbeatIntervalSec = MathMax(30, heartbeatInterval);
            m_verbosity = verbosity;
            m_initialized = true;
            return true;
        }

// Pushes the EA's counter snapshot; call before every EmitHeartbeat()
void UpdateCounters(ulong scans, ulong noSignal, ulong validatorReject,
                        ulong sigGenerated, ulong sigValidated, ulong sigSent,
                        ulong spikeEvents)
    {
        m_hbScansAttempted       = scans;
        m_hbNoSignalCount        = noSignal;
        m_hbValidatorRejects     = validatorReject;
        m_hbSignalsGenerated     = sigGenerated;
        m_hbSignalsValidated     = sigValidated;
        m_hbSignalsSent          = sigSent;
        m_hbSyntheticSpikeEvents = spikeEvents;
    }

    void SetScalpEngine(CFastScalpEngine* engine)  { m_scalpEngine = engine; }
    void SetFullMarginMode(CFullMarginMode* mode)  { m_fullMarginMode = mode; }
    void SetSafeMode(CSafeMode* mode)              { m_safeMode = mode; }
    void SetAIConfig(bool aiEnabled, bool nnEnabled, bool nnTraining,
                             bool transformerEnabled, bool ensembleEnabled, bool onnxEnabled)
        {
            m_aiEnabled = aiEnabled;
            m_nnEnabled = nnEnabled;
            m_nnOnlineTraining = nnTraining;
            m_transformerEnabled = transformerEnabled;
            m_ensembleEnabled = ensembleEnabled;
            m_onnxEnabled = onnxEnabled;
        }
    void SetRiskTier(ENUM_RISK_TIER tier)  { m_riskTier = tier; }
    void SetTradingPaused(bool paused)     { m_tradingPaused = paused; }
    void SetManagers(CEnterpriseStrategyManager* &managers[], int count)
    {
        ArrayResize(m_managers, count);
        for(int i = 0; i < count; i++)
            m_managers[i] = managers[i];
        m_managerCount = count;
    }
    void SetDerivProfiler(CDerivAssetProfiler* profiler) { m_derivProfiler = profiler; }
    void SetMultiAssetProfiler(CMultiAssetProfiler* profiler) { m_multiAssetProfiler = profiler; }
    void SetSessionWeightManager(CSessionWeightManager* swm) { m_sessionWeightManager = swm; }
            void SetSkewStepAnalyzer(CSkewStepAnalyzer* ssa) { m_skewStepAnalyzer = ssa; }
            void SetFamilyWeightMatrix(CFamilyStrategyWeightMatrix* fwm) { m_familyWeightMatrix = fwm; }
            void SetSymbols(string &symbols[], int count)
                {
                    ArrayResize(m_symbols, count);
                    for(int i = 0; i < count; i++)
                        m_symbols[i] = symbols[i];
                    m_symbolCount = count;

                    m_aiVoteTracker.ConfigureSymbols(m_symbolCount);
                }

// Stamp AI-vote activity when an AI adapter logs an [AI-VOTE] heartbeat
                void UpdateAIVoteActivity(const string symbol, const string aiType)
                {
                    m_aiVoteTracker.UpdateActivity(m_symbols, m_symbolCount, symbol, aiType);
                }

// Windowed getters: read the m_prev* snapshots, not stale EA globals
    bool IsInitialized() const { return m_initialized; }

        bool ShouldLogNormal() const { return m_verbosity >= VERBOSITY_NORMAL; }
        bool ShouldLogVerbose() const { return m_verbosity >= VERBOSITY_VERBOSE; }
        bool ShouldLogDebug() const { return m_verbosity >= VERBOSITY_DEBUG; }

// Heartbeat driver: emits at most once per m_heartbeatIntervalSec
        void EmitHeartbeat()
    {
        if(!m_initialized)
            return;

        datetime hbNow = TimeCurrent();
        if(m_lastHeartbeatTime != 0 && (hbNow - m_lastHeartbeatTime) < m_heartbeatIntervalSec)
            return;

        string corrId = CJsonLogger::GetCorrelationId();

        if(ShouldLogNormal())
        {
            CDiagMgrHeartbeat::EmitCoreLines(m_hbScansAttempted, m_hbNoSignalCount,
                                             m_hbValidatorRejects,
                                             m_hbSyntheticSpikeEvents, m_tradingPaused,
                                             m_hbSignalsGenerated, m_hbSignalsValidated, m_hbSignalsSent,
                                             corrId);
        }

        if(m_scalpEngine != NULL && m_scalpEngine.IsInitialized())
            m_scalpEngine.PrintDiagnostics();

        //--- compounding tier, session weight, skew step, family weight
        if(ShouldLogNormal())
        {
            CDiagMgrHeartbeat::EmitModuleHeartbeats(m_compoundingTierManager, m_sessionWeightManager,
                                                    m_skewStepAnalyzer, m_familyWeightMatrix, corrId);

            //--- Warn when an enabled AI adapter stops logging [AI-VOTE]
            if(m_aiEnabled && m_aiVoteTracker.IsTrackingEnabled() && m_symbolCount > 0)
            {
                m_aiVoteTracker.EmitMissingVoteWarnings(m_symbols, m_symbolCount,
                                                        m_nnEnabled, m_transformerEnabled,
                                                        m_ensembleEnabled, m_onnxEnabled,
                                                        hbNow, corrId);
            }
        }

        if(m_riskTier == RISK_TIER_FULL_MARGIN && m_fullMarginMode != NULL && m_fullMarginMode.IsInitialized())
            m_fullMarginMode.PrintDiagnostics();
        if(m_riskTier == RISK_TIER_CONSERVATIVE && m_safeMode != NULL && m_safeMode.IsInitialized())
            m_safeMode.PrintDiagnostics();

        //--- PRE-EXISTING NESTING, do NOT "fix" it: this guard wraps the rest of the
        //--- heartbeat, so position counts, conversion rates, the no-signal alert, the
        //--- risk budget, indicator cleanup, the window snapshots and the heartbeat
        //--- timestamp only run with a Deriv profiler attached and >=1 symbol configured.
        if(m_derivProfiler != NULL && m_symbolCount > 0)
        {
            CDiagMgrHeartbeat::EmitSymbolProfileDiagnostics(m_derivProfiler, m_multiAssetProfiler,
                                                            m_symbols, m_symbolCount,
                                                            ShouldLogVerbose(), corrId);

            if(ShouldLogNormal())
            {
                CDiagMgrHeartbeat::EmitPositionCounts(corrId);
            }

            //--- Windowed conversion rates (guard against underflow on reinit)
            ulong windowScans         = CDiagMgrHeartbeat::WindowDelta(m_hbScansAttempted, m_prevScansAttempted);
            ulong windowNoSignal      = CDiagMgrHeartbeat::WindowDelta(m_hbNoSignalCount, m_prevNoSignalCount);
            ulong windowGenerated     = CDiagMgrHeartbeat::WindowDelta(m_hbSignalsGenerated, m_prevSignalsGenerated);
            ulong windowValidated     = CDiagMgrHeartbeat::WindowDelta(m_hbSignalsValidated, m_prevSignalsValidated);
            ulong windowSent          = CDiagMgrHeartbeat::WindowDelta(m_hbSignalsSent, m_prevSignalsSent);

            double rateValidated     = CDiagMgrHeartbeat::Ratio(windowValidated, windowGenerated);
            double rateSent          = CDiagMgrHeartbeat::Ratio(windowSent, windowValidated);
            double noSignalRate      = CDiagMgrHeartbeat::Ratio(windowNoSignal, windowScans);

            if(ShouldLogNormal())
            {
                CDiagMgrHeartbeat::EmitConversionRates(windowScans, windowGenerated,
                                                       rateValidated, rateSent, noSignalRate, corrId);
            }

            if(windowScans >= 20 && noSignalRate >= 80.0 &&
               (m_lastNoSignalAlertTime == 0 || (hbNow - m_lastNoSignalAlertTime) >= m_heartbeatIntervalSec))
            {
                CDiagMgrHeartbeat::EmitNoSignalAlert(windowScans, windowNoSignal, noSignalRate,
                                                     corrId);
                m_lastNoSignalAlertTime = hbNow;
            }

            if(ShouldLogNormal())
            {
                CDiagMgrHeartbeat::EmitRiskBudget(m_riskManager, corrId);
            }

            CDiagMgrHeartbeat::ReleaseUnusedIndicators();

            m_prevScansAttempted       = m_hbScansAttempted;
            m_prevNoSignalCount        = m_hbNoSignalCount;
            m_prevSignalsGenerated     = m_hbSignalsGenerated;
            m_prevSignalsValidated     = m_hbSignalsValidated;
            m_prevSignalsSent          = m_hbSignalsSent;

            m_lastHeartbeatTime = hbNow;
        }
    }
};

#endif // DIAGNOSTICS_MANAGER_MQH

