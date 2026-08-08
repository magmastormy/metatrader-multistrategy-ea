//+------------------------------------------------------------------+
//| DiagnosticsManager.mqh                                            |
//| Encapsulates heartbeat/diagnostics logging extracted from          |
//| MultiStrategyAutonomousEA.mq5 OnTick heartbeat block              |
//| Blueprint Section 10.1 — Monolith Decomposition (R6b)            |
//| Consolidated: Includes consensus diagnostics from DiagnosticsCollector (Phase 2 debloating)
//+------------------------------------------------------------------+
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

// Forward declarations for AI modules
class CNeuralNetworkStrategy;

// AI type enumeration for vote tracking
enum ENUM_AI_VOTE_TYPE
{
    AI_VOTE_NEURAL_NET = 0,
    AI_VOTE_TRANSFORMER = 1,
    AI_VOTE_ENSEMBLE = 2,
    AI_VOTE_ONNX = 3,
    AI_VOTE_COUNT = 4
};

//+------------------------------------------------------------------+
//| Consensus Diagnostics Snapshot Struct (moved from DiagnosticsCollector)
//+------------------------------------------------------------------+
struct SConsensusDiagnosticsSnapshot
{
    // Root level counters
    ulong rawNone;
    ulong filteredOut;
    ulong quorumFailed;
    ulong intrabarNotEligible;
    ulong signalsGenerated;
    ulong signalsAfterPipeline;
    ulong signalsAfterQuorum;
    ulong voteSuppressed;
    ulong rolePrimarySignals;
    ulong roleFeatureSignals;
    ulong roleShadowSignals;
    ulong clusterTrendSignals;
    ulong clusterMeanReversionSignals;
    ulong clusterStructureSignals;
    ulong clusterNoneSignals;
    ulong momentumNone;
    ulong momentumCooldown;
    ulong momentumLowVolatility;
    ulong momentumNoCrossover;
    ulong momentumTrendMisaligned;
    ulong momentumNotReady;
    ulong uictNone;
    ulong uictNeutralBias;
    ulong uictOtherFilters;
    
    // Root baseline
    ulong rootBaselineRawNone;
    ulong rootBaselineFilteredOut;
    ulong rootBaselineQuorumFailed;
    ulong rootBaselineIntrabarNotEligible;
    ulong rootBaselineSignalsGenerated;
    ulong rootBaselineSignalsAfterPipeline;
    ulong rootBaselineSignalsAfterQuorum;
    ulong rootBaselineVoteSuppressed;
    ulong rootBaselineRolePrimarySignals;
    ulong rootBaselineRoleFeatureSignals;
    ulong rootBaselineRoleShadowSignals;
    ulong rootBaselineClusterTrendSignals;
    ulong rootBaselineClusterMeanReversionSignals;
    ulong rootBaselineClusterStructureSignals;
    ulong rootBaselineClusterNoneSignals;
    ulong rootBaselineMomentumNone;
    ulong rootBaselineMomentumCooldown;
    ulong rootBaselineMomentumLowVolatility;
    ulong rootBaselineMomentumNoCrossover;
    ulong rootBaselineMomentumTrendMisaligned;
    ulong rootBaselineMomentumNotReady;
    ulong rootBaselineUICTNone;
    ulong rootBaselineUICTNeutralBias;
    ulong rootBaselineUICTOtherFilters;
    
    // Snapshot baseline
    ulong snapshotBaselineRawNone;
    ulong snapshotBaselineFilteredOut;
    ulong snapshotBaselineQuorumFailed;
    ulong snapshotBaselineIntrabarNotEligible;
    ulong snapshotBaselineSignalsGenerated;
    ulong snapshotBaselineSignalsAfterPipeline;
    ulong snapshotBaselineSignalsAfterQuorum;
    ulong snapshotBaselineVoteSuppressed;
    ulong snapshotBaselineRolePrimarySignals;
    ulong snapshotBaselineRoleFeatureSignals;
    ulong snapshotBaselineRoleShadowSignals;
    ulong snapshotBaselineClusterTrendSignals;
    ulong snapshotBaselineClusterMeanReversionSignals;
    ulong snapshotBaselineClusterStructureSignals;
    ulong snapshotBaselineClusterNoneSignals;
    ulong snapshotBaselineMomentumNone;
    ulong snapshotBaselineMomentumCooldown;
    ulong snapshotBaselineMomentumLowVolatility;
    ulong snapshotBaselineMomentumNoCrossover;
    ulong snapshotBaselineMomentumTrendMisaligned;
    ulong snapshotBaselineMomentumNotReady;
    ulong snapshotBaselineUICTNone;
    ulong snapshotBaselineUICTNeutralBias;
    ulong snapshotBaselineUICTOtherFilters;
    
    SConsensusDiagnosticsSnapshot()
    {
        ZeroMemory(this);
    }
};

//+------------------------------------------------------------------+
//| DiagnosticsManager — replaces the inline heartbeat block in       |
//| MultiStrategyAutonomousEA.mq5.                                    |
//|                                                                   |
//| Counter values are passed in via UpdateCounters() each heartbeat  |
//| cycle. MQL5 does not support pointers to primitives (ulong*), so  |
//| the main EA pushes snapshot values before calling EmitHeartbeat().|
//+------------------------------------------------------------------+
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

            // Heartbeat state
    int      m_heartbeatIntervalSec;
    datetime m_lastHeartbeatTime;
    datetime m_lastNoSignalAlertTime;
    datetime m_lastNNHealthLogTime;

    // Current counter snapshot (pushed by main EA)
    ulong m_hbScansAttempted;
    ulong m_hbIntrabarScansExecuted;
    ulong m_hbNoSignalCount;
    ulong m_hbValidatorRejects;
    ulong m_hbRiskRejects;
    ulong m_hbTradesOpened;
    ulong m_hbSyntheticSpikeEvents;
    ulong m_hbSignalsGenerated;
    ulong m_hbSignalsAfterPipeline;
    ulong m_hbSignalsAfterQuorum;
    ulong m_hbSignalsValidated;
    ulong m_hbSignalsRiskApproved;
    ulong m_hbSignalsSent;
    ulong m_hbEntryBlocked;
    ulong m_hbSizingRejects;
    ulong m_hbQuietNoNewBar;
    ulong m_hbQuietCadenceHold;
    ulong m_hbQuietMissingManager;

    // Previous-window snapshots (updated at end of each heartbeat)
    ulong m_prevScansAttempted;
    ulong m_prevNoSignalCount;
    ulong m_prevSignalsGenerated;
    ulong m_prevSignalsAfterPipeline;
    ulong m_prevSignalsAfterQuorum;
    ulong m_prevSignalsValidated;
    ulong m_prevSignalsRiskApproved;
    ulong m_prevSignalsSent;

    // Consensus diagnostics counters (moved from DiagnosticsCollector)
    ulong m_diagRawNone;
    ulong m_diagFilteredOut;
    ulong m_diagQuorumFailed;
    ulong m_diagIntrabarNotEligible;
    ulong m_diagSignalsGenerated;
    ulong m_diagSignalsAfterPipeline;
    ulong m_diagSignalsAfterQuorum;
    ulong m_diagVoteSuppressed;
    ulong m_diagRolePrimarySignals;
    ulong m_diagRoleFeatureSignals;
    ulong m_diagRoleShadowSignals;
    ulong m_diagClusterTrendSignals;
    ulong m_diagClusterMeanReversionSignals;
    ulong m_diagClusterStructureSignals;
    ulong m_diagClusterNoneSignals;
    ulong m_diagMomentumNone;
    ulong m_diagMomentumCooldown;
    ulong m_diagMomentumLowVolatility;
    ulong m_diagMomentumNoCrossover;
    ulong m_diagMomentumTrendMisaligned;
    ulong m_diagMomentumNotReady;
    ulong m_diagUICTNone;
    ulong m_diagUICTNeutralBias;
    ulong m_diagUICTOtherFilters;
    ulong m_diagRootBaselineRawNone;
    ulong m_diagRootBaselineFilteredOut;
    ulong m_diagRootBaselineQuorumFailed;
    ulong m_diagRootBaselineIntrabarNotEligible;
    ulong m_diagRootBaselineSignalsGenerated;
    ulong m_diagRootBaselineSignalsAfterPipeline;
    ulong m_diagRootBaselineSignalsAfterQuorum;
    ulong m_diagRootBaselineVoteSuppressed;
    ulong m_diagRootBaselineRolePrimarySignals;
    ulong m_diagRootBaselineRoleFeatureSignals;
    ulong m_diagRootBaselineRoleShadowSignals;
    ulong m_diagRootBaselineClusterTrendSignals;
    ulong m_diagRootBaselineClusterMeanReversionSignals;
    ulong m_diagRootBaselineClusterStructureSignals;
    ulong m_diagRootBaselineClusterNoneSignals;
    ulong m_diagRootBaselineMomentumNone;
    ulong m_diagRootBaselineMomentumCooldown;
    ulong m_diagRootBaselineMomentumLowVolatility;
    ulong m_diagRootBaselineMomentumNoCrossover;
    ulong m_diagRootBaselineMomentumTrendMisaligned;
    ulong m_diagRootBaselineMomentumNotReady;
    ulong m_diagRootBaselineUICTNone;
    ulong m_diagRootBaselineUICTNeutralBias;
    ulong m_diagRootBaselineUICTOtherFilters;
    ulong m_diagSnapshotBaselineRawNone;
    ulong m_diagSnapshotBaselineFilteredOut;
    ulong m_diagSnapshotBaselineQuorumFailed;
    ulong m_diagSnapshotBaselineIntrabarNotEligible;
    ulong m_diagSnapshotBaselineSignalsGenerated;
    ulong m_diagSnapshotBaselineSignalsAfterPipeline;
    ulong m_diagSnapshotBaselineSignalsAfterQuorum;
    ulong m_diagSnapshotBaselineVoteSuppressed;
    ulong m_diagSnapshotBaselineRolePrimarySignals;
    ulong m_diagSnapshotBaselineRoleFeatureSignals;
    ulong m_diagSnapshotBaselineRoleShadowSignals;
    ulong m_diagSnapshotBaselineClusterTrendSignals;
    ulong m_diagSnapshotBaselineClusterMeanReversionSignals;
    ulong m_diagSnapshotBaselineClusterStructureSignals;
    ulong m_diagSnapshotBaselineClusterNoneSignals;
    ulong m_diagSnapshotBaselineMomentumNone;
    ulong m_diagSnapshotBaselineMomentumCooldown;
    ulong m_diagSnapshotBaselineMomentumLowVolatility;
    ulong m_diagSnapshotBaselineMomentumNoCrossover;
    ulong m_diagSnapshotBaselineMomentumTrendMisaligned;
    ulong m_diagSnapshotBaselineMomentumNotReady;
    ulong m_diagSnapshotBaselineUICTNone;
    ulong m_diagSnapshotBaselineUICTNeutralBias;
    ulong m_diagSnapshotBaselineUICTOtherFilters;
    datetime m_lastDiagLogTime;
    int m_diagLogIntervalSec;

    // AI config for NN health checks
        bool  m_aiEnabled;
        bool  m_nnEnabled;
        bool  m_nnOnlineTraining;
        // AI type enablement for vote tracking [L11-004]
        bool  m_transformerEnabled;
        bool  m_ensembleEnabled;
        bool  m_onnxEnabled;

        // Risk tier for conditional diagnostics
    ENUM_RISK_TIER m_riskTier;

    // Trading paused state (updated each tick by main EA)
    bool  m_tradingPaused;

    // Enterprise managers for consensus diagnostics
        CEnterpriseStrategyManager* m_managers[];
        int                         m_managerCount;
        string                      m_symbols[];
        int                         m_symbolCount;

        // AI vote heartbeat tracking [L11-004]
        // Track last [AI-VOTE] log timestamp per symbol per AI type
        datetime m_aiVoteLastActivity[];  // 2D: [symbolIndex * AI_VOTE_COUNT + aiType]
        bool     m_aiVoteTrackingEnabled; // Enable/disable AI vote monitoring

    //+------------------------------------------------------------------+
    //| Collect aggregated consensus diagnostics from all managers        |
    //+------------------------------------------------------------------+
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
        rawNone = 0;
        filteredOut = 0;
        quorumFailed = 0;
        intrabarNotEligible = 0;
        signalsGenerated = 0;
        signalsAfterPipeline = 0;
        signalsAfterQuorum = 0;
        momentumNone = 0;
        momentumCooldown = 0;
        momentumLowVolatility = 0;
        momentumNoCrossover = 0;
        momentumTrendMisaligned = 0;
        momentumNotReady = 0;
        uictNone = 0;
        uictNeutralBias = 0;
        uictOtherFilters = 0;
        reasonTotal = 0;

        for(int i = 0; i < m_managerCount; i++)
        {
            CEnterpriseStrategyManager* manager = m_managers[i];
            if(manager == NULL)
                continue;

            ulong managerRawNone = 0;
            ulong managerFilteredOut = 0;
            ulong managerQuorumFailed = 0;
            ulong managerIntrabarNotEligible = 0;
            ulong managerSignalsGenerated = 0;
            ulong managerSignalsAfterPipeline = 0;
            ulong managerSignalsAfterQuorum = 0;
            ulong managerMomentumNone = 0;
            ulong managerMomentumCooldown = 0;
            ulong managerMomentumLowVolatility = 0;
            ulong managerMomentumNoCrossover = 0;
            ulong managerMomentumTrendMisaligned = 0;
            ulong managerMomentumNotReady = 0;
            ulong managerUICTNone = 0;
            ulong managerUICTNeutralBias = 0;
            ulong managerUICTOtherFilters = 0;
            ulong managerReasonTotal = 0;
            manager.GetConsensusDiagnosticsSnapshot(managerRawNone,
                                                   managerFilteredOut,
                                                   managerQuorumFailed,
                                                   managerIntrabarNotEligible,
                                                   managerSignalsGenerated,
                                                   managerSignalsAfterPipeline,
                                                   managerSignalsAfterQuorum,
                                                   managerMomentumNone,
                                                   managerMomentumCooldown,
                                                   managerMomentumLowVolatility,
                                                   managerMomentumNoCrossover,
                                                   managerMomentumTrendMisaligned,
                                                   managerMomentumNotReady,
                                                   managerUICTNone,
                                                   managerUICTNeutralBias,
                                                   managerUICTOtherFilters,
                                                   managerReasonTotal);

            rawNone += managerRawNone;
            filteredOut += managerFilteredOut;
            quorumFailed += managerQuorumFailed;
            intrabarNotEligible += managerIntrabarNotEligible;
            signalsGenerated += managerSignalsGenerated;
            signalsAfterPipeline += managerSignalsAfterPipeline;
            signalsAfterQuorum += managerSignalsAfterQuorum;
            momentumNone += managerMomentumNone;
            momentumCooldown += managerMomentumCooldown;
            momentumLowVolatility += managerMomentumLowVolatility;
            momentumNoCrossover += managerMomentumNoCrossover;
            momentumTrendMisaligned += managerMomentumTrendMisaligned;
            momentumNotReady += managerMomentumNotReady;
            uictNone += managerUICTNone;
            uictNeutralBias += managerUICTNeutralBias;
            uictOtherFilters += managerUICTOtherFilters;
            reasonTotal += managerReasonTotal;
        }
    }

//+------------------------------------------------------------------+
//| Collect aggregated role/cluster diagnostics from all managers     |
//+------------------------------------------------------------------+
void GetAggregatedRoleClusterDiagnostics(ulong &primarySignals,
                                         ulong &featureSignals,
                                         ulong &voteSuppressed,
                                         ulong &trendClusterSignals,
                                         ulong &meanReversionClusterSignals,
                                         ulong &structureClusterSignals,
                                         ulong &noneClusterSignals)
{
    primarySignals = 0;
    featureSignals = 0;
    voteSuppressed = 0;
    trendClusterSignals = 0;
    meanReversionClusterSignals = 0;
    structureClusterSignals = 0;
    noneClusterSignals = 0;

        for(int i = 0; i < m_managerCount; i++)
        {
            CEnterpriseStrategyManager* manager = m_managers[i];
            if(manager == NULL)
                continue;

            ulong managerPrimary = 0;
            ulong managerFeature = 0;
            ulong managerSuppressed = 0;
            ulong managerTrend = 0;
            ulong managerMeanRev = 0;
            ulong managerStructure = 0;
            ulong managerNone = 0;

            manager.GetRoleClusterDiagnosticsTotals(managerPrimary,
                                                    managerFeature,
                                                    managerSuppressed,
                                                    managerTrend,
                                                    managerMeanRev,
                                                    managerStructure,
                                                    managerNone);

            primarySignals += managerPrimary;
            featureSignals += managerFeature;
            voteSuppressed += managerSuppressed;
            trendClusterSignals += managerTrend;
            meanReversionClusterSignals += managerMeanRev;
            structureClusterSignals += managerStructure;
            noneClusterSignals += managerNone;
        }
    }

    //+------------------------------------------------------------------+
    //| Determine which consensus cause is dominant                       |
    //+------------------------------------------------------------------+
    string GetDominantConsensusCause(const ulong rawNone,
                                     const ulong filteredOut,
                                     const ulong quorumFailed,
                                     const ulong intrabarNotEligible)
    {
        string dominant = "none";
        ulong maxCount = 0;

        if(intrabarNotEligible > maxCount)
        {
            maxCount = intrabarNotEligible;
            dominant = "intrabar_not_eligible";
        }
        if(quorumFailed > maxCount)
        {
            maxCount = quorumFailed;
            dominant = "quorum_failed";
        }
        if(filteredOut > maxCount)
        {
            maxCount = filteredOut;
            dominant = "filtered_out";
        }
        if(rawNone > maxCount)
        {
            maxCount = rawNone;
            dominant = "raw_none";
        }

        return dominant;
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
                m_lastNNHealthLogTime(0),
        m_hbScansAttempted(0),
        m_hbIntrabarScansExecuted(0),
        m_hbNoSignalCount(0),
        m_hbValidatorRejects(0),
        m_hbRiskRejects(0),
        m_hbTradesOpened(0),
        m_hbSyntheticSpikeEvents(0),
        m_hbSignalsGenerated(0),
        m_hbSignalsAfterPipeline(0),
        m_hbSignalsAfterQuorum(0),
        m_hbSignalsValidated(0),
        m_hbSignalsRiskApproved(0),
        m_hbSignalsSent(0),
        m_hbEntryBlocked(0),
        m_hbSizingRejects(0),
        m_hbQuietNoNewBar(0),
        m_hbQuietCadenceHold(0),
        m_hbQuietMissingManager(0),
        m_prevScansAttempted(0),
        m_prevNoSignalCount(0),
        m_prevSignalsGenerated(0),
        m_prevSignalsAfterPipeline(0),
        m_prevSignalsAfterQuorum(0),
        m_prevSignalsValidated(0),
        m_prevSignalsRiskApproved(0),
        m_prevSignalsSent(0),
        // Consensus diagnostics counters
        m_diagRawNone(0),
        m_diagFilteredOut(0),
        m_diagQuorumFailed(0),
        m_diagIntrabarNotEligible(0),
        m_diagSignalsGenerated(0),
        m_diagSignalsAfterPipeline(0),
        m_diagSignalsAfterQuorum(0),
        m_diagVoteSuppressed(0),
        m_diagRolePrimarySignals(0),
        m_diagRoleFeatureSignals(0),
        m_diagRoleShadowSignals(0),
        m_diagClusterTrendSignals(0),
        m_diagClusterMeanReversionSignals(0),
        m_diagClusterStructureSignals(0),
        m_diagClusterNoneSignals(0),
        m_diagMomentumNone(0),
        m_diagMomentumCooldown(0),
        m_diagMomentumLowVolatility(0),
        m_diagMomentumNoCrossover(0),
        m_diagMomentumTrendMisaligned(0),
        m_diagMomentumNotReady(0),
        m_diagUICTNone(0),
        m_diagUICTNeutralBias(0),
        m_diagUICTOtherFilters(0),
        m_diagRootBaselineRawNone(0),
        m_diagRootBaselineFilteredOut(0),
        m_diagRootBaselineQuorumFailed(0),
        m_diagRootBaselineIntrabarNotEligible(0),
        m_diagRootBaselineSignalsGenerated(0),
        m_diagRootBaselineSignalsAfterPipeline(0),
        m_diagRootBaselineSignalsAfterQuorum(0),
        m_diagRootBaselineVoteSuppressed(0),
        m_diagRootBaselineRolePrimarySignals(0),
        m_diagRootBaselineRoleFeatureSignals(0),
        m_diagRootBaselineRoleShadowSignals(0),
        m_diagRootBaselineClusterTrendSignals(0),
        m_diagRootBaselineClusterMeanReversionSignals(0),
        m_diagRootBaselineClusterStructureSignals(0),
        m_diagRootBaselineClusterNoneSignals(0),
        m_diagRootBaselineMomentumNone(0),
        m_diagRootBaselineMomentumCooldown(0),
        m_diagRootBaselineMomentumLowVolatility(0),
        m_diagRootBaselineMomentumNoCrossover(0),
        m_diagRootBaselineMomentumTrendMisaligned(0),
        m_diagRootBaselineMomentumNotReady(0),
        m_diagRootBaselineUICTNone(0),
        m_diagRootBaselineUICTNeutralBias(0),
        m_diagRootBaselineUICTOtherFilters(0),
        m_diagSnapshotBaselineRawNone(0),
        m_diagSnapshotBaselineFilteredOut(0),
        m_diagSnapshotBaselineQuorumFailed(0),
        m_diagSnapshotBaselineIntrabarNotEligible(0),
        m_diagSnapshotBaselineSignalsGenerated(0),
        m_diagSnapshotBaselineSignalsAfterPipeline(0),
        m_diagSnapshotBaselineSignalsAfterQuorum(0),
        m_diagSnapshotBaselineVoteSuppressed(0),
        m_diagSnapshotBaselineRolePrimarySignals(0),
        m_diagSnapshotBaselineRoleFeatureSignals(0),
        m_diagSnapshotBaselineRoleShadowSignals(0),
        m_diagSnapshotBaselineClusterTrendSignals(0),
        m_diagSnapshotBaselineClusterMeanReversionSignals(0),
        m_diagSnapshotBaselineClusterStructureSignals(0),
        m_diagSnapshotBaselineClusterNoneSignals(0),
        m_diagSnapshotBaselineMomentumNone(0),
        m_diagSnapshotBaselineMomentumCooldown(0),
        m_diagSnapshotBaselineMomentumLowVolatility(0),
        m_diagSnapshotBaselineMomentumNoCrossover(0),
        m_diagSnapshotBaselineMomentumTrendMisaligned(0),
        m_diagSnapshotBaselineMomentumNotReady(0),
        m_diagSnapshotBaselineUICTNone(0),
        m_diagSnapshotBaselineUICTNeutralBias(0),
        m_diagSnapshotBaselineUICTOtherFilters(0),
        m_lastDiagLogTime(0),
        m_diagLogIntervalSec(60),
        m_aiEnabled(false),
                m_nnEnabled(false),
                m_nnOnlineTraining(false),
                m_transformerEnabled(false),
                m_ensembleEnabled(false),
                m_onnxEnabled(false),
                m_riskTier(RISK_TIER_MODERATE),
                m_tradingPaused(false),
                m_managerCount(0),
                m_symbolCount(0),
                m_aiVoteTrackingEnabled(false)
            {}

    ~CDiagnosticsManager() {}

    //+------------------------------------------------------------------+
        //| Initialize — must be called before EmitHeartbeat()               |
        //+------------------------------------------------------------------+
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

    //+------------------------------------------------------------------+
    //| Push current counter values from main EA globals                  |
    //| Call this before EmitHeartbeat() each heartbeat cycle             |
    //+------------------------------------------------------------------+
void UpdateCounters(ulong scans, ulong intrabar, ulong noSignal,
                        ulong validatorReject, ulong riskReject,
                        ulong tradesOpened, ulong spikeEvents,
                        ulong sigGenerated, ulong sigAfterPipeline, ulong sigAfterQuorum,
                        ulong sigValidated, ulong sigRiskApproved, ulong sigSent,
                        ulong entryBlocked, ulong sizingRejects,
                        ulong quietNoNewBar, ulong quietCadenceHold, ulong quietMissingManager)
    {
        m_hbScansAttempted       = scans;
        m_hbIntrabarScansExecuted = intrabar;
        m_hbNoSignalCount        = noSignal;
        m_hbValidatorRejects     = validatorReject;
        m_hbRiskRejects          = riskReject;
        m_hbTradesOpened         = tradesOpened;
        m_hbSyntheticSpikeEvents = spikeEvents;
        m_hbSignalsGenerated     = sigGenerated;
        m_hbSignalsAfterPipeline = sigAfterPipeline;
        m_hbSignalsAfterQuorum   = sigAfterQuorum;
        m_hbSignalsValidated     = sigValidated;
        m_hbSignalsRiskApproved  = sigRiskApproved;
        m_hbSignalsSent          = sigSent;
        m_hbEntryBlocked         = entryBlocked;
        m_hbSizingRejects        = sizingRejects;
        m_hbQuietNoNewBar        = quietNoNewBar;
        m_hbQuietCadenceHold     = quietCadenceHold;
        m_hbQuietMissingManager  = quietMissingManager;
    }

    //+------------------------------------------------------------------+
    //| Dependency setters                                                |
    //+------------------------------------------------------------------+
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
        
                    // Initialize AI vote tracking array [L11-004]
                    // 2D array: [symbolIndex * AI_VOTE_COUNT + aiType]
                    if(m_symbolCount > 0)
                    {
                        ArrayResize(m_aiVoteLastActivity, m_symbolCount * AI_VOTE_COUNT);
                        ArrayInitialize(m_aiVoteLastActivity, 0);
                        m_aiVoteTrackingEnabled = true;
                    }
                }

                //+------------------------------------------------------------------+
                //| Update AI vote activity timestamp [L11-004]                      |
                //| Call this when an AI adapter logs an [AI-VOTE] heartbeat         |
                //+------------------------------------------------------------------+
                void UpdateAIVoteActivity(const string symbol, const string aiType)
                {
                    if(!m_aiVoteTrackingEnabled || m_symbolCount == 0)
                        return;
        
                    // Find symbol index
                    int symbolIndex = -1;
                    for(int i = 0; i < m_symbolCount; i++)
                    {
                        if(m_symbols[i] == symbol)
                        {
                            symbolIndex = i;
                            break;
                        }
                    }
                    if(symbolIndex < 0)
                        return;
        
                    // Map AI type string to enum
                    int aiTypeIndex = -1;
                    if(aiType == "NeuralNet" || aiType == "Neural Network AI")
                        aiTypeIndex = AI_VOTE_NEURAL_NET;
                    else if(aiType == "Transformer" || aiType == "Transformer AI")
                        aiTypeIndex = AI_VOTE_TRANSFORMER;
                    else if(aiType == "Ensemble" || aiType == "Ensemble AI")
                        aiTypeIndex = AI_VOTE_ENSEMBLE;
                    else if(aiType == "ONNX" || aiType == "ONNX AI")
                        aiTypeIndex = AI_VOTE_ONNX;
                    else
                        return;
        
                    // Update timestamp
                    int arrayIndex = symbolIndex * AI_VOTE_COUNT + aiTypeIndex;
                    m_aiVoteLastActivity[arrayIndex] = TimeCurrent();
                }

    //+------------------------------------------------------------------+
    //| Windowed-value getters — use the correctly-maintained m_prev*     |
    //| snapshots instead of stale EA globals                             |
    //+------------------------------------------------------------------+
    ulong GetWindowScans() const
    {
        // Batch 118: underflow guard for unsigned subtraction
        return (m_hbScansAttempted >= m_prevScansAttempted) ? (m_hbScansAttempted - m_prevScansAttempted) : 0;
    }

    ulong GetWindowNoSignal() const
    {
        // Batch 118: underflow guard for unsigned subtraction
        return (m_hbNoSignalCount >= m_prevNoSignalCount) ? (m_hbNoSignalCount - m_prevNoSignalCount) : 0;
    }

    double GetNoSignalRate() const
    {
        ulong ws = GetWindowScans();
        ulong wn = GetWindowNoSignal();
        return (ws > 0) ? (100.0 * (double)wn / (double)ws) : 0.0;
    }

    bool IsInitialized() const { return m_initialized; }

        //+------------------------------------------------------------------+
        //| Verbosity gating helpers                                        |
        //+------------------------------------------------------------------+
        bool ShouldLogNormal() const { return m_verbosity >= VERBOSITY_NORMAL; }
        bool ShouldLogVerbose() const { return m_verbosity >= VERBOSITY_VERBOSE; }
        bool ShouldLogDebug() const { return m_verbosity >= VERBOSITY_DEBUG; }

        //+------------------------------------------------------------------+
        //| Main entry point — replaces the inline heartbeat block            |
        //+------------------------------------------------------------------+
        void EmitHeartbeat()
    {
        if(!m_initialized)
            return;

        datetime hbNow = TimeCurrent();
        if(m_lastHeartbeatTime != 0 && (hbNow - m_lastHeartbeatTime) < m_heartbeatIntervalSec)
            return;

        // Get current correlation ID from JsonLogger
        string corrId = CJsonLogger::GetCorrelationId();
        
        //--- Core heartbeat line
                if(ShouldLogNormal())
                {
                        CJsonLogger::LogInfo("Heartbeat", 
                            StringFormat("scans=%I64u | intrabar=%I64u | no_signal=%I64u | validator_reject=%I64u | risk_reject=%I64u | trades_opened=%I64u | spike_events=%I64u | pause_active=%s",
                                    m_hbScansAttempted, m_hbIntrabarScansExecuted, m_hbNoSignalCount,
                                    m_hbValidatorRejects, m_hbRiskRejects, m_hbTradesOpened, m_hbSyntheticSpikeEvents,
                                    m_tradingPaused ? "true" : "false"), corrId);

                CJsonLogger::LogInfo("HeartbeatFunnel",
                            StringFormat("signals_generated=%I64u | signals_after_pipeline=%I64u | signals_after_quorum=%I64u | signals_validated=%I64u | signals_risk_approved=%I64u | signals_sent=%I64u",
                            m_hbSignalsGenerated, m_hbSignalsAfterPipeline, m_hbSignalsAfterQuorum,
                            m_hbSignalsValidated, m_hbSignalsRiskApproved, m_hbSignalsSent), corrId);
                }

        //--- Scalp engine heartbeat diagnostics
        if(m_scalpEngine != NULL && m_scalpEngine.IsInitialized())
            m_scalpEngine.PrintDiagnostics();

        //--- Compounding tier heartbeat diagnostics (L5-013 / L9-003)
                if(ShouldLogNormal())
                {
                        if(m_compoundingTierManager != NULL && m_compoundingTierManager.IsInitialized())
                        {
                            string diag = m_compoundingTierManager.GetHeartbeatString();
                            CJsonLogger::LogInfo("CompoundingTierHeartbeat", diag, corrId);
                            // AGENTS.md §6: [COMPOUNDING-TIER-HEARTBEAT] log signature
                            PrintFormat(FMT_COMPOUNDING_TIER_HEARTBEAT, diag);
                        }

                        //--- Session weight heartbeat diagnostics (L9-001)
                                if(m_sessionWeightManager != NULL && m_sessionWeightManager.IsInitialized())
                                {
                                    string swHb = m_sessionWeightManager.GetHeartbeatString();
                                    CJsonLogger::LogInfo("SessionWeightHeartbeat", swHb, corrId);
                                    // AGENTS.md §6: [SESSION-WEIGHT-HEARTBEAT] log signature
                                    PrintFormat(FMT_SESSION_WEIGHT_HEARTBEAT, swHb);
                                }

                                //--- Skew step heartbeat diagnostics (L9-002)
                                                                                if(m_skewStepAnalyzer != NULL && m_skewStepAnalyzer.IsInitialized())
                                                                                {
                                                                                    string ssHb = m_skewStepAnalyzer.GetHeartbeatString();
                                                                                    CJsonLogger::LogInfo("SkewStepHeartbeat", ssHb, corrId);
                                                                                    // AGENTS.md §6: [SKEW-STEP-HEARTBEAT] log signature
                                                                                    PrintFormat(FMT_SKEW_STEP_HEARTBEAT, ssHb);
                                                                                }

                                                                                //--- Family weight matrix heartbeat diagnostics (L9-004)
                                                                                if(m_familyWeightMatrix != NULL && m_familyWeightMatrix.IsInitialized())
                                                                                {
                                                                                    string fwHb = m_familyWeightMatrix.GetHeartbeatString();
                                                                                    CJsonLogger::LogInfo("FamilyWeightMatrix", fwHb, corrId);
                                                                                    // AGENTS.md §6: [FAMILY-WEIGHT-MATRIX] log signature
                                                                                    PrintFormat(FMT_FAMILY_WEIGHT_MATRIX, fwHb);
                                                                                }

                                                                                //--- AI vote heartbeat monitoring [L11-004]
                                                                                // Check if AI adapters are logging [AI-VOTE] heartbeats
                                                                                if(m_aiEnabled && m_aiVoteTrackingEnabled && m_symbolCount > 0)
                                                                                {
                                                                                    for(int symIdx = 0; symIdx < m_symbolCount; symIdx++)
                                                                                    {
                                                                                        // Check each AI type that should be active
                                                                                        // Neural Network AI
                                                                                        if(m_nnEnabled)
                                                                                        {
                                                                                            int arrayIdx = symIdx * AI_VOTE_COUNT + AI_VOTE_NEURAL_NET;
                                                                                            datetime lastVote = m_aiVoteLastActivity[arrayIdx];
                                                                                            if(lastVote == 0 || (hbNow - lastVote) > 30)
                                                                                                                                                                                                                {
                                                                                                                                                                                                                    CJsonLogger::LogWarning("AIVoteMissing",
                                                                                                                                                                                                                        StringFormat("symbol=%s | type=NeuralNet | last=%s | secs_ago=%d",
                                                                                                                                                                                                                            m_symbols[symIdx], lastVote == 0 ? "NEVER" : TimeToString(lastVote),
                                                                                                                                                                                                                            lastVote == 0 ? -1 : (int)(hbNow - lastVote)), corrId);
                                                                                                                                                                                                                }
                                                                                        }
                                                                                        // Transformer AI
                                                                                        if(m_transformerEnabled)
                                                                                        {
                                                                                            int arrayIdx = symIdx * AI_VOTE_COUNT + AI_VOTE_TRANSFORMER;
                                                                                            datetime lastVote = m_aiVoteLastActivity[arrayIdx];
                                                                                            if(lastVote == 0 || (hbNow - lastVote) > 30)
                                                                                                                                                                                                                {
                                                                                                                                                                                                                    CJsonLogger::LogWarning("AIVoteMissing",
                                                                                                                                                                                                                        StringFormat("symbol=%s | type=Transformer | last=%s | secs_ago=%d",
                                                                                                                                                                                                                            m_symbols[symIdx], lastVote == 0 ? "NEVER" : TimeToString(lastVote),
                                                                                                                                                                                                                            lastVote == 0 ? -1 : (int)(hbNow - lastVote)), corrId);
                                                                                                                                                                                                                }
                                                                                        }
                                                                                        // Ensemble AI
                                                                                        if(m_ensembleEnabled)
                                                                                        {
                                                                                            int arrayIdx = symIdx * AI_VOTE_COUNT + AI_VOTE_ENSEMBLE;
                                                                                            datetime lastVote = m_aiVoteLastActivity[arrayIdx];
                                                                                            if(lastVote == 0 || (hbNow - lastVote) > 30)
                                                                                                                                                                                                                {
                                                                                                                                                                                                                    CJsonLogger::LogWarning("AIVoteMissing",
                                                                                                                                                                                                                        StringFormat("symbol=%s | type=Ensemble | last=%s | secs_ago=%d",
                                                                                                                                                                                                                            m_symbols[symIdx], lastVote == 0 ? "NEVER" : TimeToString(lastVote),
                                                                                                                                                                                                                            lastVote == 0 ? -1 : (int)(hbNow - lastVote)), corrId);
                                                                                                                                                                                                                }
                                                                                        }
                                                                                        // ONNX AI
                                                                                        if(m_onnxEnabled)
                                                                                        {
                                                                                            int arrayIdx = symIdx * AI_VOTE_COUNT + AI_VOTE_ONNX;
                                                                                            datetime lastVote = m_aiVoteLastActivity[arrayIdx];
                                                                                            if(lastVote == 0 || (hbNow - lastVote) > 30)
                                                                                                                                                                                                                {
                                                                                                                                                                                                                    CJsonLogger::LogWarning("AIVoteMissing",
                                                                                                                                                                                                                        StringFormat("symbol=%s | type=ONNX | last=%s | secs_ago=%d",
                                                                                                                                                                                                                            m_symbols[symIdx], lastVote == 0 ? "NEVER" : TimeToString(lastVote),
                                                                                                                                                                                                                            lastVote == 0 ? -1 : (int)(hbNow - lastVote)), corrId);
                                                                                                                                                                                                                }
                                                                                        }
                                                                                    }
                                                                                }
                }

        //--- Full-margin / safe mode heartbeat diagnostics
        if(m_riskTier == RISK_TIER_FULL_MARGIN && m_fullMarginMode != NULL && m_fullMarginMode.IsInitialized())
            m_fullMarginMode.PrintDiagnostics();
        if(m_riskTier == RISK_TIER_CONSERVATIVE && m_safeMode != NULL && m_safeMode.IsInitialized())
            m_safeMode.PrintDiagnostics();

        //--- Per-symbol family detection diagnostics
                if(m_derivProfiler != NULL && m_symbolCount > 0)
                {
                    for(int i = 0; i < m_symbolCount; i++)
                    {
                        if(m_multiAssetProfiler != NULL && !m_multiAssetProfiler.IsDerivSymbol(m_symbols[i]))
                        {
                            // Non-Deriv symbol: log asset class info
                            if(ShouldLogVerbose())
                            {
                                string assetClassName = m_multiAssetProfiler.GetAssetClassName(m_symbols[i]);
                                SAssetProfile profile = m_multiAssetProfiler.GetProfile(m_symbols[i]);
                                CJsonLogger::LogDebug("HeartbeatAssetClass",
                                    StringFormat("symbol=%s | class=%s | atrSL=%.2f | atrTP=%.2f | risk=%.2f%% | scalp=%s | grid=%s | breakout=%s",
                                        m_symbols[i], assetClassName,
                                        profile.atrMultiplierSL, profile.atrMultiplierTP,
                                        profile.riskPerTrade,
                                        profile.enableScalpEngine ? "Y" : "N",
                                        profile.enableGridRecovery ? "Y" : "N",
                                        profile.enableBreakoutEngine ? "Y" : "N"), corrId);
                            }
                        }
                        else
                        {
                                        // Deriv synthetic: log family info
                                        string familyName = m_derivProfiler.GetFamilyName(m_symbols[i]);
                                        if(ShouldLogVerbose())
                                        {
                                            CJsonLogger::LogDebug("HeartbeatFamily",
                                                StringFormat("symbol=%s | family=%s", m_symbols[i], familyName), corrId);
                                        }
                                                }
                                            }

                                                //--- Full-margin / safe mode heartbeat diagnostics
                            //--- Grid-recovery and scalp position counts
                            if(ShouldLogNormal())
                            {
                                int gridRecoveryCount = 0;
                                int atrScalpCount = 0;
                                int totalPositions = PositionsTotal();
                                for(int posIdx = 0; posIdx < totalPositions; posIdx++)
                                {
                                    ulong ticket = PositionGetTicket(posIdx);
                                    if(ticket == 0)
                                        continue;
                                    string comment = PositionGetString(POSITION_COMMENT);
                                    if(StringFind(comment, "GRID-RECOVERY") >= 0)
                                        gridRecoveryCount++;
                                    if(StringFind(comment, "ATR-SCALP") >= 0)
                                        atrScalpCount++;
                                }
                                CJsonLogger::LogInfo("HeartbeatPositions",
                                    StringFormat("total=%d | grid_recovery=%d | atr_scalp=%d",
                                        totalPositions, gridRecoveryCount, atrScalpCount), corrId);
                            }

        // NOTE: Consensus diagnostics are now handled by EmitConsensusDiagnostics()
        // which is called from the main EA's heartbeat cycle.

        //--- Windowed conversion rates (guard against underflow on reinit)
        ulong windowScans        = (m_hbScansAttempted >= m_prevScansAttempted)       ? (m_hbScansAttempted - m_prevScansAttempted)       : m_hbScansAttempted;
        ulong windowNoSignal     = (m_hbNoSignalCount >= m_prevNoSignalCount)        ? (m_hbNoSignalCount - m_prevNoSignalCount)        : m_hbNoSignalCount;
        ulong windowGenerated    = (m_hbSignalsGenerated >= m_prevSignalsGenerated)  ? (m_hbSignalsGenerated - m_prevSignalsGenerated)  : m_hbSignalsGenerated;
        ulong windowAfterPipeline = (m_hbSignalsAfterPipeline >= m_prevSignalsAfterPipeline) ? (m_hbSignalsAfterPipeline - m_prevSignalsAfterPipeline) : m_hbSignalsAfterPipeline;
        ulong windowAfterQuorum  = (m_hbSignalsAfterQuorum >= m_prevSignalsAfterQuorum)   ? (m_hbSignalsAfterQuorum - m_prevSignalsAfterQuorum)   : m_hbSignalsAfterQuorum;
        ulong windowValidated    = (m_hbSignalsValidated >= m_prevSignalsValidated)   ? (m_hbSignalsValidated - m_prevSignalsValidated)   : m_hbSignalsValidated;
        ulong windowRiskApproved = (m_hbSignalsRiskApproved >= m_prevSignalsRiskApproved) ? (m_hbSignalsRiskApproved - m_prevSignalsRiskApproved) : m_hbSignalsRiskApproved;
        ulong windowSent         = (m_hbSignalsSent >= m_prevSignalsSent)            ? (m_hbSignalsSent - m_prevSignalsSent)            : m_hbSignalsSent;

        double rateAfterPipeline = (windowGenerated > 0)    ? (100.0 * (double)windowAfterPipeline / (double)windowGenerated) : 0.0;
        double rateAfterQuorum   = (windowAfterPipeline > 0) ? (100.0 * (double)windowAfterQuorum / (double)windowAfterPipeline) : 0.0;
        double rateValidated     = (windowAfterQuorum > 0)  ? (100.0 * (double)windowValidated / (double)windowAfterQuorum) : 0.0;
        double rateRiskApproved  = (windowValidated > 0)    ? (100.0 * (double)windowRiskApproved / (double)windowValidated) : 0.0;
        double rateSent          = (windowRiskApproved > 0) ? (100.0 * (double)windowSent / (double)windowRiskApproved) : 0.0;
        double noSignalRate      = (windowScans > 0)        ? (100.0 * (double)windowNoSignal / (double)windowScans) : 0.0;

                if(ShouldLogNormal())
                {
                    CJsonLogger::LogInfo("ConversionRates",
                        StringFormat("window_scans=%I64u | generated=%I64u | after_pipeline=%.1f%% | after_quorum=%.1f%% | validated=%.1f%% | risk_approved=%.1f%% | sent=%.1f%% | no_signal=%.1f%%",
                            windowScans, windowGenerated,
                            rateAfterPipeline, rateAfterQuorum, rateValidated,
                            rateRiskApproved, rateSent, noSignalRate), corrId);
                }

                //--- No-signal alert
        if(windowScans >= 20 && noSignalRate >= 80.0 &&
           (m_lastNoSignalAlertTime == 0 || (hbNow - m_lastNoSignalAlertTime) >= m_heartbeatIntervalSec))
        {
            CJsonLogger::LogWarning("NoSignalAlert",
                StringFormat("window_scans=%I64u | no_signal=%I64u (%.1f%%) | no_new_bar=%I64u | cadence_hold=%I64u | missing_manager=%I64u",
                    windowScans, windowNoSignal, noSignalRate,
                    m_hbQuietNoNewBar, m_hbQuietCadenceHold, m_hbQuietMissingManager), corrId);
            m_lastNoSignalAlertTime = hbNow;
        }

        //--- Risk budget snapshot
                if(ShouldLogNormal())
                {
                        if(m_riskManager != NULL)
                        {
                            SUnifiedRiskSnapshot heartbeatRisk = m_riskManager.GetSnapshot();
                            CJsonLogger::LogInfo("RiskBudget",
                                StringFormat("effective=%.2f/%.2f | entry=%.2f | mtm=%.2f | open_exposure=%.2f | conservative=%s | emergency=%s",
                                    heartbeatRisk.dailyRiskUsedPercent,
                                    heartbeatRisk.maxDailyRiskPercent,
                                    heartbeatRisk.dailyEntryRiskUsedPercent,
                                    heartbeatRisk.dailyMarkToMarketLossPercent,
                                    heartbeatRisk.openExposureRiskPercent,
                                    heartbeatRisk.conservativeMode ? "true" : "false",
                                    heartbeatRisk.emergencyMode ? "true" : "false"), corrId);
                        }
                }

        //--- Indicator manager cleanup
        CIndicatorManager* indicatorManager = CIndicatorManager::Instance();
        if(indicatorManager != NULL)
            indicatorManager.ReleaseUnused(300);

        //--- Update previous-window snapshots
        m_prevScansAttempted       = m_hbScansAttempted;
        m_prevNoSignalCount        = m_hbNoSignalCount;
        m_prevSignalsGenerated     = m_hbSignalsGenerated;
        m_prevSignalsAfterPipeline = m_hbSignalsAfterPipeline;
        m_prevSignalsAfterQuorum   = m_hbSignalsAfterQuorum;
        m_prevSignalsValidated     = m_hbSignalsValidated;
        m_prevSignalsRiskApproved  = m_hbSignalsRiskApproved;
        m_prevSignalsSent          = m_hbSignalsSent;

        m_lastHeartbeatTime = hbNow;
    }
    }

    //+------------------------------------------------------------------+
    //| NN health sub-check                                               |
    //+------------------------------------------------------------------+
    void EmitNNHealthCheck(CNeuralNetworkStrategy* &strategies[])
    {
        if(!m_aiEnabled || !m_nnEnabled || !m_nnOnlineTraining)
            return;

        datetime hbNow = TimeCurrent();
        if(m_lastNNHealthLogTime != 0 && (hbNow - m_lastNNHealthLogTime) < m_heartbeatIntervalSec)
            return;

        for(int nnIdx = 0; nnIdx < ArraySize(strategies); nnIdx++)
        {
            CNeuralNetworkStrategy* nnHealth = strategies[nnIdx];
            if(nnHealth == NULL)
                continue;

            // The actual NN health logging is kept minimal here.
            // Detailed NN health is handled by the main EA's existing NN health path
            // which has access to the full strategy objects.
            LOG_IF1(LOG_LEVEL_DEBUG, "[NN-HEALTH] idx=%d | active", nnIdx);
        }

        m_lastNNHealthLogTime = hbNow;
    }

    //+------------------------------------------------------------------+
    //| Update trading paused state (called from main EA each tick)       |
    //+------------------------------------------------------------------+
    void UpdateTradingPaused(bool paused) { m_tradingPaused = paused; }

    //+------------------------------------------------------------------+
    //| Emit consensus diagnostics — replaces inline block in main EA     |
    //| Parameters: quiet-reason counters and windowed scan/no-signal     |
    //| values passed from the main EA's globals.                         |
    //+------------------------------------------------------------------+
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

        LOG_IF8(LOG_LEVEL_DEBUG, "[CONSENSUS-SNAPSHOT] generated=%I64u | after_pipeline=%I64u | after_quorum=%I64u | raw_none=%I64u | filtered_out=%I64u | quorum_failed=%I64u | intrabar_not_eligible=%I64u | reason_total=%I64u",
                    diagSignalsGenerated,
                    diagSignalsAfterPipeline,
                    diagSignalsAfterQuorum,
                    diagRawNone,
                    diagFilteredOut,
                    diagQuorumFailed,
                    diagIntrabarNotEligible,
                    diagReasonTotal);
        LOG_IF9(LOG_LEVEL_DEBUG, "[STRATEGY-REJECTS] momentum_none=%I64u | momentum_cooldown=%I64u | momentum_low_vol=%I64u | momentum_no_crossover=%I64u | momentum_trend_misaligned=%I64u | momentum_not_ready=%I64u | uict_none=%I64u | uict_neutral_bias=%I64u | uict_other_filters=%I64u",
                    diagMomentumNone,
                    diagMomentumCooldown,
                    diagMomentumLowVolatility,
                    diagMomentumNoCrossover,
                    diagMomentumTrendMisaligned,
                    diagMomentumNotReady,
                    diagUICTNone,
                    diagUICTNeutralBias,
                    diagUICTOtherFilters);
        LOG_IF8(LOG_LEVEL_DEBUG, "[ROLE-CLUSTER] primary=%I64u | feature=%I64u | shadow=%I64u | suppressed=%I64u | trend=%I64u | mean_reversion=%I64u | structure=%I64u | none=%I64u",
                    rolePrimarySignals,
                    roleFeatureSignals,
                    roleShadowSignals,
                    roleVoteSuppressed,
                    clusterTrendSignals,
                    clusterMeanReversionSignals,
                    clusterStructureSignals,
                    clusterNoneSignals);
        LOG_IF8(LOG_LEVEL_DEBUG, "[QUIET-REASONS] no_new_bar=%I64u | cadence_hold=%I64u | missing_manager=%I64u | no_signal=%I64u | validator=%I64u | risk=%I64u | entry_blocked=%I64u | sizing=%I64u",
                    quietNoNewBar,
                    quietCadenceHold,
                    quietMissingManager,
                    noSignalCount,
                    validatorRejects,
                    riskRejects,
                    entryBlocked,
                    sizingRejects);

        // Enhanced no-signal alert with dominant consensus cause
        string dominantConsensusCause = GetDominantConsensusCause(diagRawNone,
                                                                  diagFilteredOut,
                                                                  diagQuorumFailed,
                                                                  diagIntrabarNotEligible);
        if(windowScans >= 20 &&
           noSignalRate >= 80.0 &&
           (m_lastNoSignalAlertTime == 0 || (hbNow - m_lastNoSignalAlertTime) >= m_heartbeatIntervalSec))
        {
            LOG_IF12(LOG_LEVEL_WARN, "[NO-SIGNAL-ALERT-CONSENSUS] window_scans=%I64u | no_signal=%I64u (%.1f%%) | dominant=%s | raw_none=%I64u | filtered_out=%I64u | quorum_failed=%I64u | intrabar_not_eligible=%I64u | reason_total=%I64u | momentum_none=%I64u | uict_none=%I64u | uict_neutral_bias=%I64u",
                        windowScans,
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

    //+------------------------------------------------------------------+
    //| Consensus Diagnostics — moved from DiagnosticsCollector          |
    //+------------------------------------------------------------------+
    // Configuration
    void SetLogIntervalSeconds(const int seconds) { m_diagLogIntervalSec = MathMax(10, seconds); }

    // Counter accessors - Raw counts
    ulong GetRawNone() const { return m_diagRawNone; }
    ulong GetFilteredOut() const { return m_diagFilteredOut; }
    ulong GetQuorumFailed() const { return m_diagQuorumFailed; }
    ulong GetIntrabarNotEligible() const { return m_diagIntrabarNotEligible; }
    ulong GetSignalsGenerated() const { return m_diagSignalsGenerated; }
    ulong GetSignalsAfterPipeline() const { return m_diagSignalsAfterPipeline; }
    ulong GetSignalsAfterQuorum() const { return m_diagSignalsAfterQuorum; }
    ulong GetVoteSuppressed() const { return m_diagVoteSuppressed; }

    // Counter accessors - Role breakdown
    ulong GetRolePrimarySignals() const { return m_diagRolePrimarySignals; }
    ulong GetRoleFeatureSignals() const { return m_diagRoleFeatureSignals; }
    ulong GetRoleShadowSignals() const { return m_diagRoleShadowSignals; }

    // Counter accessors - Cluster breakdown
    ulong GetClusterTrendSignals() const { return m_diagClusterTrendSignals; }
    ulong GetClusterMeanReversionSignals() const { return m_diagClusterMeanReversionSignals; }
    ulong GetClusterStructureSignals() const { return m_diagClusterStructureSignals; }
    ulong GetClusterNoneSignals() const { return m_diagClusterNoneSignals; }

    // Counter accessors - Strategy-specific rejections
    ulong GetMomentumNone() const { return m_diagMomentumNone; }
    ulong GetMomentumCooldown() const { return m_diagMomentumCooldown; }
    ulong GetMomentumLowVolatility() const { return m_diagMomentumLowVolatility; }
    ulong GetMomentumNoCrossover() const { return m_diagMomentumNoCrossover; }
    ulong GetMomentumTrendMisaligned() const { return m_diagMomentumTrendMisaligned; }
    ulong GetMomentumNotReady() const { return m_diagMomentumNotReady; }
    ulong GetUICTNone() const { return m_diagUICTNone; }
    ulong GetUICTNeutralBias() const { return m_diagUICTNeutralBias; }
    ulong GetUICTOtherFilters() const { return m_diagUICTOtherFilters; }

    // Root baseline accessors
    ulong GetRootBaselineRawNone() const { return m_diagRootBaselineRawNone; }
    ulong GetRootBaselineFilteredOut() const { return m_diagRootBaselineFilteredOut; }
    ulong GetRootBaselineQuorumFailed() const { return m_diagRootBaselineQuorumFailed; }
    ulong GetRootBaselineIntrabarNotEligible() const { return m_diagRootBaselineIntrabarNotEligible; }
    ulong GetRootBaselineSignalsGenerated() const { return m_diagRootBaselineSignalsGenerated; }
    ulong GetRootBaselineSignalsAfterPipeline() const { return m_diagRootBaselineSignalsAfterPipeline; }
    ulong GetRootBaselineSignalsAfterQuorum() const { return m_diagRootBaselineSignalsAfterQuorum; }
    ulong GetRootBaselineVoteSuppressed() const { return m_diagRootBaselineVoteSuppressed; }
    ulong GetRootBaselineRolePrimarySignals() const { return m_diagRootBaselineRolePrimarySignals; }
    ulong GetRootBaselineRoleFeatureSignals() const { return m_diagRootBaselineRoleFeatureSignals; }
    ulong GetRootBaselineRoleShadowSignals() const { return m_diagRootBaselineRoleShadowSignals; }
    ulong GetRootBaselineClusterTrendSignals() const { return m_diagRootBaselineClusterTrendSignals; }
    ulong GetRootBaselineClusterMeanReversionSignals() const { return m_diagRootBaselineClusterMeanReversionSignals; }
    ulong GetRootBaselineClusterStructureSignals() const { return m_diagRootBaselineClusterStructureSignals; }
    ulong GetRootBaselineClusterNoneSignals() const { return m_diagRootBaselineClusterNoneSignals; }
    ulong GetRootBaselineMomentumNone() const { return m_diagRootBaselineMomentumNone; }
    ulong GetRootBaselineMomentumCooldown() const { return m_diagRootBaselineMomentumCooldown; }
    ulong GetRootBaselineMomentumLowVolatility() const { return m_diagRootBaselineMomentumLowVolatility; }
    ulong GetRootBaselineMomentumNoCrossover() const { return m_diagRootBaselineMomentumNoCrossover; }
    ulong GetRootBaselineMomentumTrendMisaligned() const { return m_diagRootBaselineMomentumTrendMisaligned; }
    ulong GetRootBaselineMomentumNotReady() const { return m_diagRootBaselineMomentumNotReady; }
    ulong GetRootBaselineUICTNone() const { return m_diagRootBaselineUICTNone; }
    ulong GetRootBaselineUICTNeutralBias() const { return m_diagRootBaselineUICTNeutralBias; }
    ulong GetRootBaselineUICTOtherFilters() const { return m_diagRootBaselineUICTOtherFilters; }

    // Snapshot baseline accessors
    ulong GetSnapshotBaselineRawNone() const { return m_diagSnapshotBaselineRawNone; }
    ulong GetSnapshotBaselineFilteredOut() const { return m_diagSnapshotBaselineFilteredOut; }
    ulong GetSnapshotBaselineQuorumFailed() const { return m_diagSnapshotBaselineQuorumFailed; }
    ulong GetSnapshotBaselineIntrabarNotEligible() const { return m_diagSnapshotBaselineIntrabarNotEligible; }
    ulong GetSnapshotBaselineSignalsGenerated() const { return m_diagSnapshotBaselineSignalsGenerated; }
    ulong GetSnapshotBaselineSignalsAfterPipeline() const { return m_diagSnapshotBaselineSignalsAfterPipeline; }
    ulong GetSnapshotBaselineSignalsAfterQuorum() const { return m_diagSnapshotBaselineSignalsAfterQuorum; }
    ulong GetSnapshotBaselineVoteSuppressed() const { return m_diagSnapshotBaselineVoteSuppressed; }
    ulong GetSnapshotBaselineRolePrimarySignals() const { return m_diagSnapshotBaselineRolePrimarySignals; }
    ulong GetSnapshotBaselineRoleFeatureSignals() const { return m_diagSnapshotBaselineRoleFeatureSignals; }
    ulong GetSnapshotBaselineRoleShadowSignals() const { return m_diagSnapshotBaselineRoleShadowSignals; }
    ulong GetSnapshotBaselineClusterTrendSignals() const { return m_diagSnapshotBaselineClusterTrendSignals; }
    ulong GetSnapshotBaselineClusterMeanReversionSignals() const { return m_diagSnapshotBaselineClusterMeanReversionSignals; }
    ulong GetSnapshotBaselineClusterStructureSignals() const { return m_diagSnapshotBaselineClusterStructureSignals; }
    ulong GetSnapshotBaselineClusterNoneSignals() const { return m_diagSnapshotBaselineClusterNoneSignals; }
    ulong GetSnapshotBaselineMomentumNone() const { return m_diagSnapshotBaselineMomentumNone; }
    ulong GetSnapshotBaselineMomentumCooldown() const { return m_diagSnapshotBaselineMomentumCooldown; }
    ulong GetSnapshotBaselineMomentumLowVolatility() const { return m_diagSnapshotBaselineMomentumLowVolatility; }
    ulong GetSnapshotBaselineMomentumNoCrossover() const { return m_diagSnapshotBaselineMomentumNoCrossover; }
    ulong GetSnapshotBaselineMomentumTrendMisaligned() const { return m_diagSnapshotBaselineMomentumTrendMisaligned; }
    ulong GetSnapshotBaselineMomentumNotReady() const { return m_diagSnapshotBaselineMomentumNotReady; }
    ulong GetSnapshotBaselineUICTNone() const { return m_diagSnapshotBaselineUICTNone; }
    ulong GetSnapshotBaselineUICTNeutralBias() const { return m_diagSnapshotBaselineUICTNeutralBias; }
    ulong GetSnapshotBaselineUICTOtherFilters() const { return m_diagSnapshotBaselineUICTOtherFilters; }

    // Increment methods
    void IncrementRawNone() { m_diagRawNone++; }
    void IncrementFilteredOut() { m_diagFilteredOut++; }
    void IncrementQuorumFailed() { m_diagQuorumFailed++; }
    void IncrementIntrabarNotEligible() { m_diagIntrabarNotEligible++; }
    void IncrementSignalsGenerated() { m_diagSignalsGenerated++; }
    void IncrementSignalsAfterPipeline() { m_diagSignalsAfterPipeline++; }
    void IncrementSignalsAfterQuorum() { m_diagSignalsAfterQuorum++; }
    void IncrementVoteSuppressed() { m_diagVoteSuppressed++; }
    void IncrementRolePrimarySignals() { m_diagRolePrimarySignals++; }
    void IncrementRoleFeatureSignals() { m_diagRoleFeatureSignals++; }
    void IncrementRoleShadowSignals() { m_diagRoleShadowSignals++; }
    void IncrementClusterTrendSignals() { m_diagClusterTrendSignals++; }
    void IncrementClusterMeanReversionSignals() { m_diagClusterMeanReversionSignals++; }
    void IncrementClusterStructureSignals() { m_diagClusterStructureSignals++; }
    void IncrementClusterNoneSignals() { m_diagClusterNoneSignals++; }
    void IncrementMomentumNone() { m_diagMomentumNone++; }
    void IncrementMomentumCooldown() { m_diagMomentumCooldown++; }
    void IncrementMomentumLowVolatility() { m_diagMomentumLowVolatility++; }
    void IncrementMomentumNoCrossover() { m_diagMomentumNoCrossover++; }
    void IncrementMomentumTrendMisaligned() { m_diagMomentumTrendMisaligned++; }
    void IncrementMomentumNotReady() { m_diagMomentumNotReady++; }
    void IncrementUICTNone() { m_diagUICTNone++; }
    void IncrementUICTNeutralBias() { m_diagUICTNeutralBias++; }
    void IncrementUICTOtherFilters() { m_diagUICTOtherFilters++; }

    // Root baseline increments
    void IncrementRootBaselineRawNone() { m_diagRootBaselineRawNone++; }
    void IncrementRootBaselineFilteredOut() { m_diagRootBaselineFilteredOut++; }
    void IncrementRootBaselineQuorumFailed() { m_diagRootBaselineQuorumFailed++; }
    void IncrementRootBaselineIntrabarNotEligible() { m_diagRootBaselineIntrabarNotEligible++; }
    void IncrementRootBaselineSignalsGenerated() { m_diagRootBaselineSignalsGenerated++; }
    void IncrementRootBaselineSignalsAfterPipeline() { m_diagRootBaselineSignalsAfterPipeline++; }
    void IncrementRootBaselineSignalsAfterQuorum() { m_diagRootBaselineSignalsAfterQuorum++; }
    void IncrementRootBaselineVoteSuppressed() { m_diagRootBaselineVoteSuppressed++; }
    void IncrementRootBaselineRolePrimarySignals() { m_diagRootBaselineRolePrimarySignals++; }
    void IncrementRootBaselineRoleFeatureSignals() { m_diagRootBaselineRoleFeatureSignals++; }
    void IncrementRootBaselineRoleShadowSignals() { m_diagRootBaselineRoleShadowSignals++; }
    void IncrementRootBaselineClusterTrendSignals() { m_diagRootBaselineClusterTrendSignals++; }
    void IncrementRootBaselineClusterMeanReversionSignals() { m_diagRootBaselineClusterMeanReversionSignals++; }
    void IncrementRootBaselineClusterStructureSignals() { m_diagRootBaselineClusterStructureSignals++; }
    void IncrementRootBaselineClusterNoneSignals() { m_diagRootBaselineClusterNoneSignals++; }
    void IncrementRootBaselineMomentumNone() { m_diagRootBaselineMomentumNone++; }
    void IncrementRootBaselineMomentumCooldown() { m_diagRootBaselineMomentumCooldown++; }
    void IncrementRootBaselineMomentumLowVolatility() { m_diagRootBaselineMomentumLowVolatility++; }
    void IncrementRootBaselineMomentumNoCrossover() { m_diagRootBaselineMomentumNoCrossover++; }
    void IncrementRootBaselineMomentumTrendMisaligned() { m_diagRootBaselineMomentumTrendMisaligned++; }
    void IncrementRootBaselineMomentumNotReady() { m_diagRootBaselineMomentumNotReady++; }
    void IncrementRootBaselineUICTNone() { m_diagRootBaselineUICTNone++; }
    void IncrementRootBaselineUICTNeutralBias() { m_diagRootBaselineUICTNeutralBias++; }
    void IncrementRootBaselineUICTOtherFilters() { m_diagRootBaselineUICTOtherFilters++; }

    // Snapshot baseline increments
    void IncrementSnapshotBaselineRawNone() { m_diagSnapshotBaselineRawNone++; }
    void IncrementSnapshotBaselineFilteredOut() { m_diagSnapshotBaselineFilteredOut++; }
    void IncrementSnapshotBaselineQuorumFailed() { m_diagSnapshotBaselineQuorumFailed++; }
    void IncrementSnapshotBaselineIntrabarNotEligible() { m_diagSnapshotBaselineIntrabarNotEligible++; }
    void IncrementSnapshotBaselineSignalsGenerated() { m_diagSnapshotBaselineSignalsGenerated++; }
    void IncrementSnapshotBaselineSignalsAfterPipeline() { m_diagSnapshotBaselineSignalsAfterPipeline++; }
    void IncrementSnapshotBaselineSignalsAfterQuorum() { m_diagSnapshotBaselineSignalsAfterQuorum++; }
    void IncrementSnapshotBaselineVoteSuppressed() { m_diagSnapshotBaselineVoteSuppressed++; }
    void IncrementSnapshotBaselineRolePrimarySignals() { m_diagSnapshotBaselineRolePrimarySignals++; }
    void IncrementSnapshotBaselineRoleFeatureSignals() { m_diagSnapshotBaselineRoleFeatureSignals++; }
    void IncrementSnapshotBaselineRoleShadowSignals() { m_diagSnapshotBaselineRoleShadowSignals++; }
    void IncrementSnapshotBaselineClusterTrendSignals() { m_diagSnapshotBaselineClusterTrendSignals++; }
    void IncrementSnapshotBaselineClusterMeanReversionSignals() { m_diagSnapshotBaselineClusterMeanReversionSignals++; }
    void IncrementSnapshotBaselineClusterStructureSignals() { m_diagSnapshotBaselineClusterStructureSignals++; }
    void IncrementSnapshotBaselineClusterNoneSignals() { m_diagSnapshotBaselineClusterNoneSignals++; }
    void IncrementSnapshotBaselineMomentumNone() { m_diagSnapshotBaselineMomentumNone++; }
    void IncrementSnapshotBaselineMomentumCooldown() { m_diagSnapshotBaselineMomentumCooldown++; }
    void IncrementSnapshotBaselineMomentumLowVolatility() { m_diagSnapshotBaselineMomentumLowVolatility++; }
    void IncrementSnapshotBaselineMomentumNoCrossover() { m_diagSnapshotBaselineMomentumNoCrossover++; }
    void IncrementSnapshotBaselineMomentumTrendMisaligned() { m_diagSnapshotBaselineMomentumTrendMisaligned++; }
    void IncrementSnapshotBaselineMomentumNotReady() { m_diagSnapshotBaselineMomentumNotReady++; }
    void IncrementSnapshotBaselineUICTNone() { m_diagSnapshotBaselineUICTNone++; }
    void IncrementSnapshotBaselineUICTNeutralBias() { m_diagSnapshotBaselineUICTNeutralBias++; }
    void IncrementSnapshotBaselineUICTOtherFilters() { m_diagSnapshotBaselineUICTOtherFilters++; }

    // Role/Cluster diagnostic accumulation
    void AccumulateRoleClusterSignalDiagnostics(const int strategyIndex, const bool signalGenerated);

    // Snapshot methods
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
                     ulong &clusterNoneSignals) const;

    // Full diagnostics snapshot for logging
    void GetFullDiagnosticsSnapshot(SConsensusDiagnosticsSnapshot &snapshot) const;

    // Logging
    void MaybeLogDiagnostics(const string symbol);
    void LogDiagnostics(const string symbol);

    // Reset
    void ResetConsensusDiagnostics();

    // Convenience method to set snapshot baselines (called at start of new logging interval)
    void SetSnapshotBaselines();
};

//+------------------------------------------------------------------+
//| Consensus Diagnostics Implementation (moved from DiagnosticsCollector)
//+------------------------------------------------------------------+
void CDiagnosticsManager::ResetConsensusDiagnostics()
{
    m_diagRawNone = 0;
    m_diagFilteredOut = 0;
    m_diagQuorumFailed = 0;
    m_diagIntrabarNotEligible = 0;
    m_diagSignalsGenerated = 0;
    m_diagSignalsAfterPipeline = 0;
    m_diagSignalsAfterQuorum = 0;
    m_diagVoteSuppressed = 0;
    m_diagRolePrimarySignals = 0;
    m_diagRoleFeatureSignals = 0;
    m_diagRoleShadowSignals = 0;
    m_diagClusterTrendSignals = 0;
    m_diagClusterMeanReversionSignals = 0;
    m_diagClusterStructureSignals = 0;
    m_diagClusterNoneSignals = 0;
    m_diagMomentumNone = 0;
    m_diagMomentumCooldown = 0;
    m_diagMomentumLowVolatility = 0;
    m_diagMomentumNoCrossover = 0;
    m_diagMomentumTrendMisaligned = 0;
    m_diagMomentumNotReady = 0;
    m_diagUICTNone = 0;
    m_diagUICTNeutralBias = 0;
    m_diagUICTOtherFilters = 0;
    m_diagRootBaselineRawNone = 0;
    m_diagRootBaselineFilteredOut = 0;
    m_diagRootBaselineQuorumFailed = 0;
    m_diagRootBaselineIntrabarNotEligible = 0;
    m_diagRootBaselineSignalsGenerated = 0;
    m_diagRootBaselineSignalsAfterPipeline = 0;
    m_diagRootBaselineSignalsAfterQuorum = 0;
    m_diagRootBaselineVoteSuppressed = 0;
    m_diagRootBaselineRolePrimarySignals = 0;
    m_diagRootBaselineRoleFeatureSignals = 0;
    m_diagRootBaselineRoleShadowSignals = 0;
    m_diagRootBaselineClusterTrendSignals = 0;
    m_diagRootBaselineClusterMeanReversionSignals = 0;
    m_diagRootBaselineClusterStructureSignals = 0;
    m_diagRootBaselineClusterNoneSignals = 0;
    m_diagRootBaselineMomentumNone = 0;
    m_diagRootBaselineMomentumCooldown = 0;
    m_diagRootBaselineMomentumLowVolatility = 0;
    m_diagRootBaselineMomentumNoCrossover = 0;
    m_diagRootBaselineMomentumTrendMisaligned = 0;
    m_diagRootBaselineMomentumNotReady = 0;
    m_diagRootBaselineUICTNone = 0;
    m_diagRootBaselineUICTNeutralBias = 0;
    m_diagRootBaselineUICTOtherFilters = 0;
    m_diagSnapshotBaselineRawNone = 0;
    m_diagSnapshotBaselineFilteredOut = 0;
    m_diagSnapshotBaselineQuorumFailed = 0;
    m_diagSnapshotBaselineIntrabarNotEligible = 0;
    m_diagSnapshotBaselineSignalsGenerated = 0;
    m_diagSnapshotBaselineSignalsAfterPipeline = 0;
    m_diagSnapshotBaselineSignalsAfterQuorum = 0;
    m_diagSnapshotBaselineVoteSuppressed = 0;
    m_diagSnapshotBaselineRolePrimarySignals = 0;
    m_diagSnapshotBaselineRoleFeatureSignals = 0;
    m_diagSnapshotBaselineRoleShadowSignals = 0;
    m_diagSnapshotBaselineClusterTrendSignals = 0;
    m_diagSnapshotBaselineClusterMeanReversionSignals = 0;
    m_diagSnapshotBaselineClusterStructureSignals = 0;
    m_diagSnapshotBaselineClusterNoneSignals = 0;
    m_diagSnapshotBaselineMomentumNone = 0;
    m_diagSnapshotBaselineMomentumCooldown = 0;
    m_diagSnapshotBaselineMomentumLowVolatility = 0;
    m_diagSnapshotBaselineMomentumNoCrossover = 0;
    m_diagSnapshotBaselineMomentumTrendMisaligned = 0;
    m_diagSnapshotBaselineMomentumNotReady = 0;
    m_diagSnapshotBaselineUICTNone = 0;
    m_diagSnapshotBaselineUICTNeutralBias = 0;
    m_diagSnapshotBaselineUICTOtherFilters = 0;
    m_lastDiagLogTime = 0;
}

//+------------------------------------------------------------------+
//| Accumulate Role/Cluster Signal Diagnostics                       |
//+------------------------------------------------------------------+
void CDiagnosticsManager::AccumulateRoleClusterSignalDiagnostics(const int strategyIndex, const bool signalGenerated)
{
    if(!signalGenerated)
        return;
    // Note: Strategy-specific role/cluster tracking would need access to strategy metadata
    // This is a placeholder for when strategy info is available
}

//+------------------------------------------------------------------+
//| Get Snapshot                                                     |
//+------------------------------------------------------------------+
void CDiagnosticsManager::GetSnapshot(ulong &rawNone,
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
    rawNone = m_diagRawNone;
    filteredOut = m_diagFilteredOut;
    quorumFailed = m_diagQuorumFailed;
    intrabarNotEligible = m_diagIntrabarNotEligible;
    signalsGenerated = m_diagSignalsGenerated;
    signalsAfterPipeline = m_diagSignalsAfterPipeline;
    signalsAfterQuorum = m_diagSignalsAfterQuorum;
    voteSuppressed = m_diagVoteSuppressed;
    rolePrimarySignals = m_diagRolePrimarySignals;
    roleFeatureSignals = m_diagRoleFeatureSignals;
    roleShadowSignals = m_diagRoleShadowSignals;
    clusterTrendSignals = m_diagClusterTrendSignals;
    clusterMeanReversionSignals = m_diagClusterMeanReversionSignals;
    clusterStructureSignals = m_diagClusterStructureSignals;
    clusterNoneSignals = m_diagClusterNoneSignals;
}

//+------------------------------------------------------------------+
//| Get Full Diagnostics Snapshot                                    |
//+------------------------------------------------------------------+
void CDiagnosticsManager::GetFullDiagnosticsSnapshot(SConsensusDiagnosticsSnapshot &snapshot) const
{
    // Root baseline (summary)
    snapshot.rawNone = m_diagRawNone;
    snapshot.filteredOut = m_diagFilteredOut;
    snapshot.quorumFailed = m_diagQuorumFailed;
    snapshot.intrabarNotEligible = m_diagIntrabarNotEligible;
    snapshot.signalsGenerated = m_diagSignalsGenerated;
    snapshot.signalsAfterPipeline = m_diagSignalsAfterPipeline;
    snapshot.signalsAfterQuorum = m_diagSignalsAfterQuorum;
    snapshot.voteSuppressed = m_diagVoteSuppressed;
    snapshot.rolePrimarySignals = m_diagRolePrimarySignals;
    snapshot.roleFeatureSignals = m_diagRoleFeatureSignals;
    snapshot.roleShadowSignals = m_diagRoleShadowSignals;
    snapshot.clusterTrendSignals = m_diagClusterTrendSignals;
    snapshot.clusterMeanReversionSignals = m_diagClusterMeanReversionSignals;
    snapshot.clusterStructureSignals = m_diagClusterStructureSignals;
    snapshot.clusterNoneSignals = m_diagClusterNoneSignals;
    snapshot.momentumNone = m_diagMomentumNone;
    snapshot.momentumCooldown = m_diagMomentumCooldown;
    snapshot.momentumLowVolatility = m_diagMomentumLowVolatility;
    snapshot.momentumNoCrossover = m_diagMomentumNoCrossover;
    snapshot.momentumTrendMisaligned = m_diagMomentumTrendMisaligned;
    snapshot.momentumNotReady = m_diagMomentumNotReady;
    snapshot.uictNone = m_diagUICTNone;
    snapshot.uictNeutralBias = m_diagUICTNeutralBias;
    snapshot.uictOtherFilters = m_diagUICTOtherFilters;
    
    // Root baseline (full)
    snapshot.rootBaselineRawNone = m_diagRootBaselineRawNone;
    snapshot.rootBaselineFilteredOut = m_diagRootBaselineFilteredOut;
    snapshot.rootBaselineQuorumFailed = m_diagRootBaselineQuorumFailed;
    snapshot.rootBaselineIntrabarNotEligible = m_diagRootBaselineIntrabarNotEligible;
    snapshot.rootBaselineSignalsGenerated = m_diagRootBaselineSignalsGenerated;
    snapshot.rootBaselineSignalsAfterPipeline = m_diagRootBaselineSignalsAfterPipeline;
    snapshot.rootBaselineSignalsAfterQuorum = m_diagRootBaselineSignalsAfterQuorum;
    snapshot.rootBaselineVoteSuppressed = m_diagRootBaselineVoteSuppressed;
    snapshot.rootBaselineRolePrimarySignals = m_diagRootBaselineRolePrimarySignals;
    snapshot.rootBaselineRoleFeatureSignals = m_diagRootBaselineRoleFeatureSignals;
    snapshot.rootBaselineRoleShadowSignals = m_diagRootBaselineRoleShadowSignals;
    snapshot.rootBaselineClusterTrendSignals = m_diagRootBaselineClusterTrendSignals;
    snapshot.rootBaselineClusterMeanReversionSignals = m_diagRootBaselineClusterMeanReversionSignals;
    snapshot.rootBaselineClusterStructureSignals = m_diagRootBaselineClusterStructureSignals;
    snapshot.rootBaselineClusterNoneSignals = m_diagRootBaselineClusterNoneSignals;
    snapshot.rootBaselineMomentumNone = m_diagRootBaselineMomentumNone;
    snapshot.rootBaselineMomentumCooldown = m_diagRootBaselineMomentumCooldown;
    snapshot.rootBaselineMomentumLowVolatility = m_diagRootBaselineMomentumLowVolatility;
    snapshot.rootBaselineMomentumNoCrossover = m_diagRootBaselineMomentumNoCrossover;
    snapshot.rootBaselineMomentumTrendMisaligned = m_diagRootBaselineMomentumTrendMisaligned;
    snapshot.rootBaselineMomentumNotReady = m_diagRootBaselineMomentumNotReady;
    snapshot.rootBaselineUICTNone = m_diagRootBaselineUICTNone;
    snapshot.rootBaselineUICTNeutralBias = m_diagRootBaselineUICTNeutralBias;
    snapshot.rootBaselineUICTOtherFilters = m_diagRootBaselineUICTOtherFilters;
    
    // Snapshot baseline
    snapshot.snapshotBaselineRawNone = m_diagSnapshotBaselineRawNone;
    snapshot.snapshotBaselineFilteredOut = m_diagSnapshotBaselineFilteredOut;
    snapshot.snapshotBaselineQuorumFailed = m_diagSnapshotBaselineQuorumFailed;
    snapshot.snapshotBaselineIntrabarNotEligible = m_diagSnapshotBaselineIntrabarNotEligible;
    snapshot.snapshotBaselineSignalsGenerated = m_diagSnapshotBaselineSignalsGenerated;
    snapshot.snapshotBaselineSignalsAfterPipeline = m_diagSnapshotBaselineSignalsAfterPipeline;
    snapshot.snapshotBaselineSignalsAfterQuorum = m_diagSnapshotBaselineSignalsAfterQuorum;
    snapshot.snapshotBaselineVoteSuppressed = m_diagSnapshotBaselineVoteSuppressed;
    snapshot.snapshotBaselineRolePrimarySignals = m_diagSnapshotBaselineRolePrimarySignals;
    snapshot.snapshotBaselineRoleFeatureSignals = m_diagSnapshotBaselineRoleFeatureSignals;
    snapshot.snapshotBaselineRoleShadowSignals = m_diagSnapshotBaselineRoleShadowSignals;
    snapshot.snapshotBaselineClusterTrendSignals = m_diagSnapshotBaselineClusterTrendSignals;
    snapshot.snapshotBaselineClusterMeanReversionSignals = m_diagSnapshotBaselineClusterMeanReversionSignals;
    snapshot.snapshotBaselineClusterStructureSignals = m_diagSnapshotBaselineClusterStructureSignals;
    snapshot.snapshotBaselineClusterNoneSignals = m_diagSnapshotBaselineClusterNoneSignals;
    snapshot.snapshotBaselineMomentumNone = m_diagSnapshotBaselineMomentumNone;
    snapshot.snapshotBaselineMomentumCooldown = m_diagSnapshotBaselineMomentumCooldown;
    snapshot.snapshotBaselineMomentumLowVolatility = m_diagSnapshotBaselineMomentumLowVolatility;
    snapshot.snapshotBaselineMomentumNoCrossover = m_diagSnapshotBaselineMomentumNoCrossover;
    snapshot.snapshotBaselineMomentumTrendMisaligned = m_diagSnapshotBaselineMomentumTrendMisaligned;
    snapshot.snapshotBaselineMomentumNotReady = m_diagSnapshotBaselineMomentumNotReady;
    snapshot.snapshotBaselineUICTNone = m_diagSnapshotBaselineUICTNone;
    snapshot.snapshotBaselineUICTNeutralBias = m_diagSnapshotBaselineUICTNeutralBias;
    snapshot.snapshotBaselineUICTOtherFilters = m_diagSnapshotBaselineUICTOtherFilters;
}

//+------------------------------------------------------------------+
//| Maybe Log Diagnostics                                            |
//+------------------------------------------------------------------+
void CDiagnosticsManager::MaybeLogDiagnostics(const string symbol)
{
    datetime now = TimeCurrent();
    if(now - m_lastDiagLogTime >= m_diagLogIntervalSec)
    {
        LogDiagnostics(symbol);
        m_lastDiagLogTime = now;
    }
}

//+------------------------------------------------------------------+
//| Log Diagnostics                                                  |
//+------------------------------------------------------------------+
void CDiagnosticsManager::LogDiagnostics(const string symbol)
{
    PrintFormat("[CONSENSUS-DIAG] Symbol=%s | Generated=%llu | AfterPipeline=%llu | AfterQuorum=%llu | RawNone=%llu | FilteredOut=%llu | QuorumFailed=%llu | IntrabarNotEligible=%llu | VoteSuppressed=%llu",
                symbol,
                m_diagSignalsGenerated,
                m_diagSignalsAfterPipeline,
                m_diagSignalsAfterQuorum,
                m_diagRawNone,
                m_diagFilteredOut,
                m_diagQuorumFailed,
                m_diagIntrabarNotEligible,
                m_diagVoteSuppressed);
    PrintFormat("[CONSENSUS-DIAG] Role: Primary=%llu Feature=%llu Shadow=%llu | Cluster: Trend=%llu MeanRev=%llu Struct=%llu None=%llu",
                m_diagRolePrimarySignals,
                m_diagRoleFeatureSignals,
                m_diagRoleShadowSignals,
                m_diagClusterTrendSignals,
                m_diagClusterMeanReversionSignals,
                m_diagClusterStructureSignals,
                m_diagClusterNoneSignals);
}

//+------------------------------------------------------------------+
//| Set Snapshot Baselines                                           |
//+------------------------------------------------------------------+
void CDiagnosticsManager::SetSnapshotBaselines()
{
    m_diagSnapshotBaselineRawNone = m_diagRawNone;
    m_diagSnapshotBaselineFilteredOut = m_diagFilteredOut;
    m_diagSnapshotBaselineQuorumFailed = m_diagQuorumFailed;
    m_diagSnapshotBaselineIntrabarNotEligible = m_diagIntrabarNotEligible;
    m_diagSnapshotBaselineSignalsGenerated = m_diagSignalsGenerated;
    m_diagSnapshotBaselineSignalsAfterPipeline = m_diagSignalsAfterPipeline;
    m_diagSnapshotBaselineSignalsAfterQuorum = m_diagSignalsAfterQuorum;
    m_diagSnapshotBaselineVoteSuppressed = m_diagVoteSuppressed;
    m_diagSnapshotBaselineRolePrimarySignals = m_diagRolePrimarySignals;
    m_diagSnapshotBaselineRoleFeatureSignals = m_diagRoleFeatureSignals;
    m_diagSnapshotBaselineRoleShadowSignals = m_diagRoleShadowSignals;
    m_diagSnapshotBaselineClusterTrendSignals = m_diagClusterTrendSignals;
    m_diagSnapshotBaselineClusterMeanReversionSignals = m_diagClusterMeanReversionSignals;
    m_diagSnapshotBaselineClusterStructureSignals = m_diagClusterStructureSignals;
    m_diagSnapshotBaselineClusterNoneSignals = m_diagClusterNoneSignals;
    m_diagSnapshotBaselineMomentumNone = m_diagMomentumNone;
    m_diagSnapshotBaselineMomentumCooldown = m_diagMomentumCooldown;
    m_diagSnapshotBaselineMomentumLowVolatility = m_diagMomentumLowVolatility;
    m_diagSnapshotBaselineMomentumNoCrossover = m_diagMomentumNoCrossover;
    m_diagSnapshotBaselineMomentumTrendMisaligned = m_diagMomentumTrendMisaligned;
    m_diagSnapshotBaselineMomentumNotReady = m_diagMomentumNotReady;
    m_diagSnapshotBaselineUICTNone = m_diagUICTNone;
    m_diagSnapshotBaselineUICTNeutralBias = m_diagUICTNeutralBias;
    m_diagSnapshotBaselineUICTOtherFilters = m_diagUICTOtherFilters;
}

#endif // __DIAGNOSTICS_MANAGER_MQH__
