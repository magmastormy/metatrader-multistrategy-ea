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
#include "EnterpriseStrategyManager.mqh"
#include "../Processing/DerivAssetProfiler.mqh"
#include "../Processing/MultiAssetProfiler.mqh"
#include "../Engines/SessionWeightManager.mqh"
#include "../Engines/SkewStepAnalyzer.mqh"
#include "../Engines/FamilyStrategyWeightMatrix.mqh"

//--- DiagMgr* modules (by-value members / static helpers): keep these last and in this
//--- order - include-resolution order is what the earlier headers see.
#include "DiagMgrCounters.mqh"          // CDiagMgrCounters, SConsensusDiagnosticsSnapshot
#include "DiagMgrAggregator.mqh"        // CDiagMgrAggregator
#include "DiagMgrAIVote.mqh"            // CDiagMgrAIVoteTracker, ENUM_AI_VOTE_TYPE
#include "DiagMgrHeartbeat.mqh"         // CDiagMgrHeartbeat
#include "DiagMgrConsensusReport.mqh"   // CDiagMgrConsensusReport

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
    CDiagMgrCounters m_counters;

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

        // AI vote heartbeat tracking [L11-004]
        CDiagMgrAIVoteTracker m_aiVoteTracker;

    void GetAggregatedConsensusDiagnostics(ulong &rawNone,
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
                                           ulong &reasonTotal)
    {
        CDiagMgrAggregator::GetAggregatedConsensusDiagnostics(m_managers, m_managerCount,
                                                              rawNone, filteredOut, quorumFailed, intrabarNotEligible,
                                                              signalsGenerated, signalsAfterPipeline, signalsAfterQuorum,
                                                              momentumNone, momentumCooldown, momentumLowVolatility,
                                                              momentumNoCrossover, momentumTrendMisaligned, momentumNotReady,
                                                              uictNone, uictNeutralBias, uictOtherFilters, reasonTotal);
    }

    void GetAggregatedRoleClusterDiagnostics(ulong &primarySignals,
                                             ulong &featureSignals,
                                             ulong &voteSuppressed,
                                             ulong &trendClusterSignals,
                                             ulong &meanReversionClusterSignals,
                                             ulong &structureClusterSignals,
                                             ulong &noneClusterSignals)
    {
        CDiagMgrAggregator::GetAggregatedRoleClusterDiagnostics(m_managers, m_managerCount,
                                                                primarySignals, featureSignals, voteSuppressed,
                                                                trendClusterSignals, meanReversionClusterSignals,
                                                                structureClusterSignals, noneClusterSignals);
    }

    string GetDominantConsensusCause(const ulong rawNone,
                                     const ulong filteredOut,
                                     const ulong quorumFailed,
                                     const ulong intrabarNotEligible)
    {
        return CDiagMgrAggregator::GetDominantConsensusCause(rawNone, filteredOut, quorumFailed, intrabarNotEligible);
    }

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

// [L11-004] Stamp AI-vote activity when an AI adapter logs an [AI-VOTE] heartbeat
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

        //--- L5-013 / L9-001..L9-004: compounding tier, session weight, skew step, family weight
        if(ShouldLogNormal())
        {
            CDiagMgrHeartbeat::EmitModuleHeartbeats(m_compoundingTierManager, m_sessionWeightManager,
                                                    m_skewStepAnalyzer, m_familyWeightMatrix, corrId);

            //--- [L11-004] Warn when an enabled AI adapter stops logging [AI-VOTE]
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

            // Consensus report lines come from EmitConsensusDiagnostics(), driven by the main EA

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

// Consensus report lines; the EA passes the quiet-reason and windowed counter values
    void EmitConsensusDiagnostics(ulong quietNoNewBar,
                                  ulong quietCadenceHold,
                                  ulong quietMissingManager,
                                  ulong noSignalCount,
                                  ulong validatorRejects,
                                  ulong riskRejects,
                                  ulong entryBlocked,
                                  ulong sizingRejects,
                                  ulong windowScans,
                                  ulong windowNoSignal,
                                  double noSignalRate,
                                  datetime hbNow)
    {
        if(m_managerCount == 0)
            return;

        ulong diagRawNone = 0;
        ulong diagFilteredOut = 0;
        ulong diagQuorumFailed = 0;
        ulong diagIntrabarNotEligible = 0;
        ulong diagSignalsGenerated = 0;
        ulong diagSignalsAfterPipeline = 0;
        ulong diagSignalsAfterQuorum = 0;
        ulong diagMomentumNone = 0;
        ulong diagMomentumCooldown = 0;
        ulong diagMomentumLowVolatility = 0;
        ulong diagMomentumNoCrossover = 0;
        ulong diagMomentumTrendMisaligned = 0;
        ulong diagMomentumNotReady = 0;
        ulong diagUICTNone = 0;
        ulong diagUICTNeutralBias = 0;
        ulong diagUICTOtherFilters = 0;
        ulong diagReasonTotal = 0;
        ulong rolePrimarySignals = 0;
        ulong roleFeatureSignals = 0;
        ulong roleShadowSignals = 0;
        ulong roleVoteSuppressed = 0;
        ulong clusterTrendSignals = 0;
        ulong clusterMeanReversionSignals = 0;
        ulong clusterStructureSignals = 0;
        ulong clusterNoneSignals = 0;

        GetAggregatedConsensusDiagnostics(diagRawNone,
                                          diagFilteredOut,
                                          diagQuorumFailed,
                                          diagIntrabarNotEligible,
                                          diagSignalsGenerated,
                                          diagSignalsAfterPipeline,
                                          diagSignalsAfterQuorum,
                                          diagMomentumNone,
                                          diagMomentumCooldown,
                                          diagMomentumLowVolatility,
                                          diagMomentumNoCrossover,
                                          diagMomentumTrendMisaligned,
                                          diagMomentumNotReady,
                                          diagUICTNone,
                                          diagUICTNeutralBias,
                                          diagUICTOtherFilters,
                                          diagReasonTotal);
        GetAggregatedRoleClusterDiagnostics(rolePrimarySignals,
                                            roleFeatureSignals,
                                            roleVoteSuppressed,
                                            clusterTrendSignals,
                                            clusterMeanReversionSignals,
                                            clusterStructureSignals,
                                            clusterNoneSignals);

        CDiagMgrConsensusReport::EmitConsensusSnapshotLine(diagSignalsGenerated,
                                                           diagSignalsAfterPipeline,
                                                           diagSignalsAfterQuorum,
                                                           diagRawNone,
                                                           diagFilteredOut,
                                                           diagQuorumFailed,
                                                           diagIntrabarNotEligible,
                                                           diagReasonTotal);
        CDiagMgrConsensusReport::EmitStrategyRejectsLine(diagMomentumNone,
                                                         diagMomentumCooldown,
                                                         diagMomentumLowVolatility,
                                                         diagMomentumNoCrossover,
                                                         diagMomentumTrendMisaligned,
                                                         diagMomentumNotReady,
                                                         diagUICTNone,
                                                         diagUICTNeutralBias,
                                                         diagUICTOtherFilters);
        CDiagMgrConsensusReport::EmitRoleClusterLine(rolePrimarySignals,
                                                     roleFeatureSignals,
                                                     roleShadowSignals,
                                                     roleVoteSuppressed,
                                                     clusterTrendSignals,
                                                     clusterMeanReversionSignals,
                                                     clusterStructureSignals,
                                                     clusterNoneSignals);
        CDiagMgrConsensusReport::EmitQuietReasonsLine(quietNoNewBar,
                                                      quietCadenceHold,
                                                      quietMissingManager,
                                                      noSignalCount,
                                                      validatorRejects,
                                                      riskRejects,
                                                      entryBlocked,
                                                      sizingRejects);

        // No-signal alert: >=20 window scans and >=80% no-signal rate, throttled by m_lastNoSignalAlertTime
        string dominantConsensusCause = GetDominantConsensusCause(diagRawNone,
                                                                  diagFilteredOut,
                                                                  diagQuorumFailed,
                                                                  diagIntrabarNotEligible);
        if(windowScans >= 20 &&
           noSignalRate >= 80.0 &&
           (m_lastNoSignalAlertTime == 0 || (hbNow - m_lastNoSignalAlertTime) >= m_heartbeatIntervalSec))
        {
            CDiagMgrConsensusReport::EmitNoSignalAlertConsensus(windowScans,
                                                                windowNoSignal,
                                                                noSignalRate,
                                                                dominantConsensusCause,
                                                                diagRawNone,
                                                                diagFilteredOut,
                                                                diagQuorumFailed,
                                                                diagIntrabarNotEligible,
                                                                diagReasonTotal,
                                                                diagMomentumNone,
                                                                diagUICTNone,
                                                                diagUICTNeutralBias);
            m_lastNoSignalAlertTime = hbNow;
        }
    }

//--- Everything below forwards to m_counters (CDiagMgrCounters)
    void SetLogIntervalSeconds(const int seconds) { m_counters.SetLogIntervalSeconds(seconds); }

    ulong GetRawNone() const { return m_counters.GetRawNone(); }
    ulong GetFilteredOut() const { return m_counters.GetFilteredOut(); }
    ulong GetQuorumFailed() const { return m_counters.GetQuorumFailed(); }
    ulong GetIntrabarNotEligible() const { return m_counters.GetIntrabarNotEligible(); }
    ulong GetSignalsGenerated() const { return m_counters.GetSignalsGenerated(); }
    ulong GetSignalsAfterPipeline() const { return m_counters.GetSignalsAfterPipeline(); }
    ulong GetSignalsAfterQuorum() const { return m_counters.GetSignalsAfterQuorum(); }
    ulong GetVoteSuppressed() const { return m_counters.GetVoteSuppressed(); }

    ulong GetRolePrimarySignals() const { return m_counters.GetRolePrimarySignals(); }
    ulong GetRoleFeatureSignals() const { return m_counters.GetRoleFeatureSignals(); }
    ulong GetRoleShadowSignals() const { return m_counters.GetRoleShadowSignals(); }

    ulong GetClusterTrendSignals() const { return m_counters.GetClusterTrendSignals(); }
    ulong GetClusterMeanReversionSignals() const { return m_counters.GetClusterMeanReversionSignals(); }
    ulong GetClusterStructureSignals() const { return m_counters.GetClusterStructureSignals(); }
    ulong GetClusterNoneSignals() const { return m_counters.GetClusterNoneSignals(); }

    ulong GetMomentumNone() const { return m_counters.GetMomentumNone(); }
    ulong GetMomentumCooldown() const { return m_counters.GetMomentumCooldown(); }
    ulong GetMomentumLowVolatility() const { return m_counters.GetMomentumLowVolatility(); }
    ulong GetMomentumNoCrossover() const { return m_counters.GetMomentumNoCrossover(); }
    ulong GetMomentumTrendMisaligned() const { return m_counters.GetMomentumTrendMisaligned(); }
    ulong GetMomentumNotReady() const { return m_counters.GetMomentumNotReady(); }
    ulong GetUICTNone() const { return m_counters.GetUICTNone(); }
    ulong GetUICTNeutralBias() const { return m_counters.GetUICTNeutralBias(); }
    ulong GetUICTOtherFilters() const { return m_counters.GetUICTOtherFilters(); }

    ulong GetRootBaselineRawNone() const { return m_counters.GetRootBaselineRawNone(); }
    ulong GetRootBaselineFilteredOut() const { return m_counters.GetRootBaselineFilteredOut(); }
    ulong GetRootBaselineQuorumFailed() const { return m_counters.GetRootBaselineQuorumFailed(); }
    ulong GetRootBaselineIntrabarNotEligible() const { return m_counters.GetRootBaselineIntrabarNotEligible(); }
    ulong GetRootBaselineSignalsGenerated() const { return m_counters.GetRootBaselineSignalsGenerated(); }
    ulong GetRootBaselineSignalsAfterPipeline() const { return m_counters.GetRootBaselineSignalsAfterPipeline(); }
    ulong GetRootBaselineSignalsAfterQuorum() const { return m_counters.GetRootBaselineSignalsAfterQuorum(); }
    ulong GetRootBaselineVoteSuppressed() const { return m_counters.GetRootBaselineVoteSuppressed(); }
    ulong GetRootBaselineRolePrimarySignals() const { return m_counters.GetRootBaselineRolePrimarySignals(); }
    ulong GetRootBaselineRoleFeatureSignals() const { return m_counters.GetRootBaselineRoleFeatureSignals(); }
    ulong GetRootBaselineRoleShadowSignals() const { return m_counters.GetRootBaselineRoleShadowSignals(); }
    ulong GetRootBaselineClusterTrendSignals() const { return m_counters.GetRootBaselineClusterTrendSignals(); }
    ulong GetRootBaselineClusterMeanReversionSignals() const { return m_counters.GetRootBaselineClusterMeanReversionSignals(); }
    ulong GetRootBaselineClusterStructureSignals() const { return m_counters.GetRootBaselineClusterStructureSignals(); }
    ulong GetRootBaselineClusterNoneSignals() const { return m_counters.GetRootBaselineClusterNoneSignals(); }
    ulong GetRootBaselineMomentumNone() const { return m_counters.GetRootBaselineMomentumNone(); }
    ulong GetRootBaselineMomentumCooldown() const { return m_counters.GetRootBaselineMomentumCooldown(); }
    ulong GetRootBaselineMomentumLowVolatility() const { return m_counters.GetRootBaselineMomentumLowVolatility(); }
    ulong GetRootBaselineMomentumNoCrossover() const { return m_counters.GetRootBaselineMomentumNoCrossover(); }
    ulong GetRootBaselineMomentumTrendMisaligned() const { return m_counters.GetRootBaselineMomentumTrendMisaligned(); }
    ulong GetRootBaselineMomentumNotReady() const { return m_counters.GetRootBaselineMomentumNotReady(); }
    ulong GetRootBaselineUICTNone() const { return m_counters.GetRootBaselineUICTNone(); }
    ulong GetRootBaselineUICTNeutralBias() const { return m_counters.GetRootBaselineUICTNeutralBias(); }
    ulong GetRootBaselineUICTOtherFilters() const { return m_counters.GetRootBaselineUICTOtherFilters(); }

    ulong GetSnapshotBaselineRawNone() const { return m_counters.GetSnapshotBaselineRawNone(); }
    ulong GetSnapshotBaselineFilteredOut() const { return m_counters.GetSnapshotBaselineFilteredOut(); }
    ulong GetSnapshotBaselineQuorumFailed() const { return m_counters.GetSnapshotBaselineQuorumFailed(); }
    ulong GetSnapshotBaselineIntrabarNotEligible() const { return m_counters.GetSnapshotBaselineIntrabarNotEligible(); }
    ulong GetSnapshotBaselineSignalsGenerated() const { return m_counters.GetSnapshotBaselineSignalsGenerated(); }
    ulong GetSnapshotBaselineSignalsAfterPipeline() const { return m_counters.GetSnapshotBaselineSignalsAfterPipeline(); }
    ulong GetSnapshotBaselineSignalsAfterQuorum() const { return m_counters.GetSnapshotBaselineSignalsAfterQuorum(); }
    ulong GetSnapshotBaselineVoteSuppressed() const { return m_counters.GetSnapshotBaselineVoteSuppressed(); }
    ulong GetSnapshotBaselineRolePrimarySignals() const { return m_counters.GetSnapshotBaselineRolePrimarySignals(); }
    ulong GetSnapshotBaselineRoleFeatureSignals() const { return m_counters.GetSnapshotBaselineRoleFeatureSignals(); }
    ulong GetSnapshotBaselineRoleShadowSignals() const { return m_counters.GetSnapshotBaselineRoleShadowSignals(); }
    ulong GetSnapshotBaselineClusterTrendSignals() const { return m_counters.GetSnapshotBaselineClusterTrendSignals(); }
    ulong GetSnapshotBaselineClusterMeanReversionSignals() const { return m_counters.GetSnapshotBaselineClusterMeanReversionSignals(); }
    ulong GetSnapshotBaselineClusterStructureSignals() const { return m_counters.GetSnapshotBaselineClusterStructureSignals(); }
    ulong GetSnapshotBaselineClusterNoneSignals() const { return m_counters.GetSnapshotBaselineClusterNoneSignals(); }
    ulong GetSnapshotBaselineMomentumNone() const { return m_counters.GetSnapshotBaselineMomentumNone(); }
    ulong GetSnapshotBaselineMomentumCooldown() const { return m_counters.GetSnapshotBaselineMomentumCooldown(); }
    ulong GetSnapshotBaselineMomentumLowVolatility() const { return m_counters.GetSnapshotBaselineMomentumLowVolatility(); }
    ulong GetSnapshotBaselineMomentumNoCrossover() const { return m_counters.GetSnapshotBaselineMomentumNoCrossover(); }
    ulong GetSnapshotBaselineMomentumTrendMisaligned() const { return m_counters.GetSnapshotBaselineMomentumTrendMisaligned(); }
    ulong GetSnapshotBaselineMomentumNotReady() const { return m_counters.GetSnapshotBaselineMomentumNotReady(); }
    ulong GetSnapshotBaselineUICTNone() const { return m_counters.GetSnapshotBaselineUICTNone(); }
    ulong GetSnapshotBaselineUICTNeutralBias() const { return m_counters.GetSnapshotBaselineUICTNeutralBias(); }
    ulong GetSnapshotBaselineUICTOtherFilters() const { return m_counters.GetSnapshotBaselineUICTOtherFilters(); }

    void IncrementRawNone() { m_counters.IncrementRawNone(); }
    void IncrementFilteredOut() { m_counters.IncrementFilteredOut(); }
    void IncrementQuorumFailed() { m_counters.IncrementQuorumFailed(); }
    void IncrementIntrabarNotEligible() { m_counters.IncrementIntrabarNotEligible(); }
    void IncrementSignalsGenerated() { m_counters.IncrementSignalsGenerated(); }
    void IncrementSignalsAfterPipeline() { m_counters.IncrementSignalsAfterPipeline(); }
    void IncrementSignalsAfterQuorum() { m_counters.IncrementSignalsAfterQuorum(); }
    void IncrementVoteSuppressed() { m_counters.IncrementVoteSuppressed(); }
    void IncrementRolePrimarySignals() { m_counters.IncrementRolePrimarySignals(); }
    void IncrementRoleFeatureSignals() { m_counters.IncrementRoleFeatureSignals(); }
    void IncrementRoleShadowSignals() { m_counters.IncrementRoleShadowSignals(); }
    void IncrementClusterTrendSignals() { m_counters.IncrementClusterTrendSignals(); }
    void IncrementClusterMeanReversionSignals() { m_counters.IncrementClusterMeanReversionSignals(); }
    void IncrementClusterStructureSignals() { m_counters.IncrementClusterStructureSignals(); }
    void IncrementClusterNoneSignals() { m_counters.IncrementClusterNoneSignals(); }
    void IncrementMomentumNone() { m_counters.IncrementMomentumNone(); }
    void IncrementMomentumCooldown() { m_counters.IncrementMomentumCooldown(); }
    void IncrementMomentumLowVolatility() { m_counters.IncrementMomentumLowVolatility(); }
    void IncrementMomentumNoCrossover() { m_counters.IncrementMomentumNoCrossover(); }
    void IncrementMomentumTrendMisaligned() { m_counters.IncrementMomentumTrendMisaligned(); }
    void IncrementMomentumNotReady() { m_counters.IncrementMomentumNotReady(); }
    void IncrementUICTNone() { m_counters.IncrementUICTNone(); }
    void IncrementUICTNeutralBias() { m_counters.IncrementUICTNeutralBias(); }
    void IncrementUICTOtherFilters() { m_counters.IncrementUICTOtherFilters(); }

    void IncrementRootBaselineRawNone() { m_counters.IncrementRootBaselineRawNone(); }
    void IncrementRootBaselineFilteredOut() { m_counters.IncrementRootBaselineFilteredOut(); }
    void IncrementRootBaselineQuorumFailed() { m_counters.IncrementRootBaselineQuorumFailed(); }
    void IncrementRootBaselineIntrabarNotEligible() { m_counters.IncrementRootBaselineIntrabarNotEligible(); }
    void IncrementRootBaselineSignalsGenerated() { m_counters.IncrementRootBaselineSignalsGenerated(); }
    void IncrementRootBaselineSignalsAfterPipeline() { m_counters.IncrementRootBaselineSignalsAfterPipeline(); }
    void IncrementRootBaselineSignalsAfterQuorum() { m_counters.IncrementRootBaselineSignalsAfterQuorum(); }
    void IncrementRootBaselineVoteSuppressed() { m_counters.IncrementRootBaselineVoteSuppressed(); }
    void IncrementRootBaselineRolePrimarySignals() { m_counters.IncrementRootBaselineRolePrimarySignals(); }
    void IncrementRootBaselineRoleFeatureSignals() { m_counters.IncrementRootBaselineRoleFeatureSignals(); }
    void IncrementRootBaselineRoleShadowSignals() { m_counters.IncrementRootBaselineRoleShadowSignals(); }
    void IncrementRootBaselineClusterTrendSignals() { m_counters.IncrementRootBaselineClusterTrendSignals(); }
    void IncrementRootBaselineClusterMeanReversionSignals() { m_counters.IncrementRootBaselineClusterMeanReversionSignals(); }
    void IncrementRootBaselineClusterStructureSignals() { m_counters.IncrementRootBaselineClusterStructureSignals(); }
    void IncrementRootBaselineClusterNoneSignals() { m_counters.IncrementRootBaselineClusterNoneSignals(); }
    void IncrementRootBaselineMomentumNone() { m_counters.IncrementRootBaselineMomentumNone(); }
    void IncrementRootBaselineMomentumCooldown() { m_counters.IncrementRootBaselineMomentumCooldown(); }
    void IncrementRootBaselineMomentumLowVolatility() { m_counters.IncrementRootBaselineMomentumLowVolatility(); }
    void IncrementRootBaselineMomentumNoCrossover() { m_counters.IncrementRootBaselineMomentumNoCrossover(); }
    void IncrementRootBaselineMomentumTrendMisaligned() { m_counters.IncrementRootBaselineMomentumTrendMisaligned(); }
    void IncrementRootBaselineMomentumNotReady() { m_counters.IncrementRootBaselineMomentumNotReady(); }
    void IncrementRootBaselineUICTNone() { m_counters.IncrementRootBaselineUICTNone(); }
    void IncrementRootBaselineUICTNeutralBias() { m_counters.IncrementRootBaselineUICTNeutralBias(); }
    void IncrementRootBaselineUICTOtherFilters() { m_counters.IncrementRootBaselineUICTOtherFilters(); }

    void IncrementSnapshotBaselineRawNone() { m_counters.IncrementSnapshotBaselineRawNone(); }
    void IncrementSnapshotBaselineFilteredOut() { m_counters.IncrementSnapshotBaselineFilteredOut(); }
    void IncrementSnapshotBaselineQuorumFailed() { m_counters.IncrementSnapshotBaselineQuorumFailed(); }
    void IncrementSnapshotBaselineIntrabarNotEligible() { m_counters.IncrementSnapshotBaselineIntrabarNotEligible(); }
    void IncrementSnapshotBaselineSignalsGenerated() { m_counters.IncrementSnapshotBaselineSignalsGenerated(); }
    void IncrementSnapshotBaselineSignalsAfterPipeline() { m_counters.IncrementSnapshotBaselineSignalsAfterPipeline(); }
    void IncrementSnapshotBaselineSignalsAfterQuorum() { m_counters.IncrementSnapshotBaselineSignalsAfterQuorum(); }
    void IncrementSnapshotBaselineVoteSuppressed() { m_counters.IncrementSnapshotBaselineVoteSuppressed(); }
    void IncrementSnapshotBaselineRolePrimarySignals() { m_counters.IncrementSnapshotBaselineRolePrimarySignals(); }
    void IncrementSnapshotBaselineRoleFeatureSignals() { m_counters.IncrementSnapshotBaselineRoleFeatureSignals(); }
    void IncrementSnapshotBaselineRoleShadowSignals() { m_counters.IncrementSnapshotBaselineRoleShadowSignals(); }
    void IncrementSnapshotBaselineClusterTrendSignals() { m_counters.IncrementSnapshotBaselineClusterTrendSignals(); }
    void IncrementSnapshotBaselineClusterMeanReversionSignals() { m_counters.IncrementSnapshotBaselineClusterMeanReversionSignals(); }
    void IncrementSnapshotBaselineClusterStructureSignals() { m_counters.IncrementSnapshotBaselineClusterStructureSignals(); }
    void IncrementSnapshotBaselineClusterNoneSignals() { m_counters.IncrementSnapshotBaselineClusterNoneSignals(); }
    void IncrementSnapshotBaselineMomentumNone() { m_counters.IncrementSnapshotBaselineMomentumNone(); }
    void IncrementSnapshotBaselineMomentumCooldown() { m_counters.IncrementSnapshotBaselineMomentumCooldown(); }
    void IncrementSnapshotBaselineMomentumLowVolatility() { m_counters.IncrementSnapshotBaselineMomentumLowVolatility(); }
    void IncrementSnapshotBaselineMomentumNoCrossover() { m_counters.IncrementSnapshotBaselineMomentumNoCrossover(); }
    void IncrementSnapshotBaselineMomentumTrendMisaligned() { m_counters.IncrementSnapshotBaselineMomentumTrendMisaligned(); }
    void IncrementSnapshotBaselineMomentumNotReady() { m_counters.IncrementSnapshotBaselineMomentumNotReady(); }
    void IncrementSnapshotBaselineUICTNone() { m_counters.IncrementSnapshotBaselineUICTNone(); }
    void IncrementSnapshotBaselineUICTNeutralBias() { m_counters.IncrementSnapshotBaselineUICTNeutralBias(); }
    void IncrementSnapshotBaselineUICTOtherFilters() { m_counters.IncrementSnapshotBaselineUICTOtherFilters(); }

    void AccumulateRoleClusterSignalDiagnostics(const int strategyIndex, const bool signalGenerated)
    {
        m_counters.AccumulateRoleClusterSignalDiagnostics(strategyIndex, signalGenerated);
    }

    void GetSnapshot(ulong &rawNone,
                     ulong &filteredOut,
                     ulong &quorumFailed,
                     ulong &intrabarNotEligible,
                     ulong &signalsGenerated,
                     ulong &signalsAfterPipeline,
                     ulong &signalsAfterQuorum,
                     ulong &voteSuppressed,
                     ulong &rolePrimarySignals,
                     ulong &roleFeatureSignals,
                     ulong &roleShadowSignals,
                     ulong &clusterTrendSignals,
                     ulong &clusterMeanReversionSignals,
                     ulong &clusterStructureSignals,
                     ulong &clusterNoneSignals) const
    {
        m_counters.GetSnapshot(rawNone, filteredOut, quorumFailed, intrabarNotEligible,
                               signalsGenerated, signalsAfterPipeline, signalsAfterQuorum, voteSuppressed,
                               rolePrimarySignals, roleFeatureSignals, roleShadowSignals,
                               clusterTrendSignals, clusterMeanReversionSignals,
                               clusterStructureSignals, clusterNoneSignals);
    }

    void GetFullDiagnosticsSnapshot(SConsensusDiagnosticsSnapshot &snapshot) const
    {
        m_counters.GetFullDiagnosticsSnapshot(snapshot);
    }

    void MaybeLogDiagnostics(const string symbol) { m_counters.MaybeLogDiagnostics(symbol); }
    void LogDiagnostics(const string symbol) { m_counters.LogDiagnostics(symbol); }

    void ResetConsensusDiagnostics() { m_counters.ResetConsensusDiagnostics(); }

    void SetSnapshotBaselines() { m_counters.SetSnapshotBaselines(); }
};

#endif // DIAGNOSTICS_MANAGER_MQH
