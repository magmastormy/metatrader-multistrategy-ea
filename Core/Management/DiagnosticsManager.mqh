//+------------------------------------------------------------------+
//| DiagnosticsManager.mqh                                            |
//| Encapsulates heartbeat/diagnostics logging extracted from          |
//| MultiStrategyAutonomousEA.mq5 OnTick heartbeat block              |
//| Blueprint Section 10.1 — Monolith Decomposition (R6b)            |
//+------------------------------------------------------------------+
#ifndef __DIAGNOSTICS_MANAGER_MQH__
#define __DIAGNOSTICS_MANAGER_MQH__

#include "../Utils/Enums.mqh"
#include "../Risk/UnifiedRiskManager.mqh"
#include "../Risk/RiskTierManager.mqh"
#include "../Utils/DiagnosticsLogger.mqh"
#include "../Scalp/FastScalpEngine.mqh"
#include "../Risk/FullMarginMode.mqh"
#include "../Risk/SafeModeConfig.mqh"
#include "../Monitoring/PerformanceAnalytics.mqh"
#include "../../IndicatorManager.mqh"
#include "EnterpriseStrategyManager.mqh"

// Forward declarations for AI modules
class CNeuralNetworkStrategy;

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
    bool                     m_initialized;

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
    ulong m_hbShadowTrades;
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

    // AI config for NN health checks
    bool  m_aiEnabled;
    bool  m_nnEnabled;
    bool  m_nnOnlineTraining;

    // Risk tier for conditional diagnostics
    ENUM_RISK_TIER m_riskTier;

    // Shadow mode flag
    bool  m_shadowMode;

    // Trading paused state (updated each tick by main EA)
    bool  m_tradingPaused;

    // Enterprise managers for consensus diagnostics
    CEnterpriseStrategyManager* m_managers[];
    int                         m_managerCount;

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
                                             ulong &shadowSignals,
                                             ulong &voteSuppressed,
                                             ulong &trendClusterSignals,
                                             ulong &meanReversionClusterSignals,
                                             ulong &structureClusterSignals,
                                             ulong &noneClusterSignals)
    {
        primarySignals = 0;
        featureSignals = 0;
        shadowSignals = 0;
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
            ulong managerShadow = 0;
            ulong managerSuppressed = 0;
            ulong managerTrend = 0;
            ulong managerMeanRev = 0;
            ulong managerStructure = 0;
            ulong managerNone = 0;

            manager.GetRoleClusterDiagnosticsTotals(managerPrimary,
                                                    managerFeature,
                                                    managerShadow,
                                                    managerSuppressed,
                                                    managerTrend,
                                                    managerMeanRev,
                                                    managerStructure,
                                                    managerNone);

            primarySignals += managerPrimary;
            featureSignals += managerFeature;
            shadowSignals += managerShadow;
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
        m_initialized(false),
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
        m_hbShadowTrades(0),
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
        m_aiEnabled(false),
        m_nnEnabled(false),
        m_nnOnlineTraining(false),
        m_riskTier(RISK_TIER_MODERATE),
        m_shadowMode(true),
        m_tradingPaused(false),
        m_managerCount(0)
    {}

    ~CDiagnosticsManager() {}

    //+------------------------------------------------------------------+
    //| Initialize — must be called before EmitHeartbeat()               |
    //+------------------------------------------------------------------+
    bool Initialize(CUnifiedRiskManager* rm, CRiskTierManager* rtm, int heartbeatInterval)
    {
        if(rm == NULL || rtm == NULL)
            return false;
        m_riskManager = rm;
        m_riskTierManager = rtm;
        m_heartbeatIntervalSec = MathMax(30, heartbeatInterval);
        m_initialized = true;
        return true;
    }

    //+------------------------------------------------------------------+
    //| Push current counter values from main EA globals                  |
    //| Call this before EmitHeartbeat() each heartbeat cycle             |
    //+------------------------------------------------------------------+
    void UpdateCounters(ulong scans, ulong intrabar, ulong noSignal,
                        ulong validatorReject, ulong riskReject,
                        ulong tradesOpened, ulong shadowTrades, ulong spikeEvents,
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
        m_hbShadowTrades         = shadowTrades;
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
    void SetAIConfig(bool aiEnabled, bool nnEnabled, bool nnTraining)
    {
        m_aiEnabled = aiEnabled;
        m_nnEnabled = nnEnabled;
        m_nnOnlineTraining = nnTraining;
    }
    void SetRiskTier(ENUM_RISK_TIER tier)  { m_riskTier = tier; }
    void SetShadowMode(bool shadow)        { m_shadowMode = shadow; }
    void SetTradingPaused(bool paused)     { m_tradingPaused = paused; }
    void SetManagers(CEnterpriseStrategyManager* &managers[], int count)
    {
        ArrayResize(m_managers, count);
        for(int i = 0; i < count; i++)
            m_managers[i] = managers[i];
        m_managerCount = count;
    }

    //+------------------------------------------------------------------+
    //| Windowed-value getters — use the correctly-maintained m_prev*     |
    //| snapshots instead of stale EA globals                             |
    //+------------------------------------------------------------------+
    ulong GetWindowScans() const
    {
        return m_hbScansAttempted - m_prevScansAttempted;
    }

    ulong GetWindowNoSignal() const
    {
        return m_hbNoSignalCount - m_prevNoSignalCount;
    }

    double GetNoSignalRate() const
    {
        ulong ws = m_hbScansAttempted - m_prevScansAttempted;
        ulong wn = m_hbNoSignalCount - m_prevNoSignalCount;
        return (ws > 0) ? (100.0 * (double)wn / (double)ws) : 0.0;
    }

    bool IsInitialized() const { return m_initialized; }

    //+------------------------------------------------------------------+
    //| Main entry point — replaces the inline heartbeat block            |
    //+------------------------------------------------------------------+
    void EmitHeartbeat()
    {
        if(!m_initialized)
            return;

        datetime heartbeatNow = TimeCurrent();
        if(m_lastHeartbeatTime != 0 && (heartbeatNow - m_lastHeartbeatTime) < m_heartbeatIntervalSec)
            return;

        //--- Core heartbeat line
        PrintFormat("[HEARTBEAT] scans=%I64u | intrabar=%I64u | no_signal=%I64u | validator_reject=%I64u | risk_reject=%I64u | trades_opened=%I64u | shadow_trades=%I64u | spike_events=%I64u | pause_active=%s",
                    m_hbScansAttempted, m_hbIntrabarScansExecuted, m_hbNoSignalCount,
                    m_hbValidatorRejects, m_hbRiskRejects, m_hbTradesOpened, m_hbShadowTrades,
                    m_hbSyntheticSpikeEvents,
                    m_tradingPaused ? "true" : "false");

        PrintFormat("[HEARTBEAT-FUNNEL] signals_generated=%I64u | signals_after_pipeline=%I64u | signals_after_quorum=%I64u | signals_validated=%I64u | signals_risk_approved=%I64u | shadow_or_live_sent=%I64u",
                    m_hbSignalsGenerated, m_hbSignalsAfterPipeline, m_hbSignalsAfterQuorum,
                    m_hbSignalsValidated, m_hbSignalsRiskApproved, m_hbSignalsSent);

        //--- Scalp engine heartbeat diagnostics
        if(m_scalpEngine != NULL && m_scalpEngine.IsInitialized())
            m_scalpEngine.PrintDiagnostics();

        //--- Full-margin / safe mode heartbeat diagnostics
        if(m_riskTier == RISK_TIER_FULL_MARGIN && m_fullMarginMode != NULL && m_fullMarginMode.IsInitialized())
            m_fullMarginMode.PrintDiagnostics();
        if(m_riskTier == RISK_TIER_CONSERVATIVE && m_safeMode != NULL && m_safeMode.IsInitialized())
            m_safeMode.PrintDiagnostics();

        // NOTE: Consensus diagnostics are now handled by EmitConsensusDiagnostics()
        // which is called from the main EA's heartbeat cycle.

        //--- Windowed conversion rates
        ulong windowScans        = m_hbScansAttempted - m_prevScansAttempted;
        ulong windowNoSignal     = m_hbNoSignalCount - m_prevNoSignalCount;
        ulong windowGenerated    = m_hbSignalsGenerated - m_prevSignalsGenerated;
        ulong windowAfterPipeline = m_hbSignalsAfterPipeline - m_prevSignalsAfterPipeline;
        ulong windowAfterQuorum  = m_hbSignalsAfterQuorum - m_prevSignalsAfterQuorum;
        ulong windowValidated    = m_hbSignalsValidated - m_prevSignalsValidated;
        ulong windowRiskApproved = m_hbSignalsRiskApproved - m_prevSignalsRiskApproved;
        ulong windowSent         = m_hbSignalsSent - m_prevSignalsSent;

        double rateAfterPipeline = (windowGenerated > 0)    ? (100.0 * (double)windowAfterPipeline / (double)windowGenerated) : 0.0;
        double rateAfterQuorum   = (windowAfterPipeline > 0) ? (100.0 * (double)windowAfterQuorum / (double)windowAfterPipeline) : 0.0;
        double rateValidated     = (windowAfterQuorum > 0)  ? (100.0 * (double)windowValidated / (double)windowAfterQuorum) : 0.0;
        double rateRiskApproved  = (windowValidated > 0)    ? (100.0 * (double)windowRiskApproved / (double)windowValidated) : 0.0;
        double rateSent          = (windowRiskApproved > 0) ? (100.0 * (double)windowSent / (double)windowRiskApproved) : 0.0;
        double noSignalRate      = (windowScans > 0)        ? (100.0 * (double)windowNoSignal / (double)windowScans) : 0.0;

        PrintFormat("[CONVERSION-RATES] window_scans=%I64u | generated=%I64u | after_pipeline=%.1f%% | after_quorum=%.1f%% | validated=%.1f%% | risk_approved=%.1f%% | sent=%.1f%% | no_signal=%.1f%%",
                    windowScans, windowGenerated,
                    rateAfterPipeline, rateAfterQuorum, rateValidated,
                    rateRiskApproved, rateSent, noSignalRate);

        //--- No-signal alert
        if(windowScans >= 20 && noSignalRate >= 80.0 &&
           (m_lastNoSignalAlertTime == 0 || (heartbeatNow - m_lastNoSignalAlertTime) >= m_heartbeatIntervalSec))
        {
            PrintFormat("[NO-SIGNAL-ALERT] window_scans=%I64u | no_signal=%I64u (%.1f%%) | no_new_bar=%I64u | cadence_hold=%I64u | missing_manager=%I64u",
                        windowScans, windowNoSignal, noSignalRate,
                        m_hbQuietNoNewBar, m_hbQuietCadenceHold, m_hbQuietMissingManager);
            m_lastNoSignalAlertTime = heartbeatNow;
        }

        //--- Risk budget snapshot
        if(m_riskManager != NULL)
        {
            SUnifiedRiskSnapshot heartbeatRisk = m_riskManager.GetSnapshot();
            PrintFormat("[RISK-BUDGET] effective=%.2f/%.2f | entry=%.2f | mtm=%.2f | open_exposure=%.2f | conservative=%s | emergency=%s",
                        heartbeatRisk.dailyRiskUsedPercent,
                        heartbeatRisk.maxDailyRiskPercent,
                        heartbeatRisk.dailyEntryRiskUsedPercent,
                        heartbeatRisk.dailyMarkToMarketLossPercent,
                        heartbeatRisk.openExposureRiskPercent,
                        heartbeatRisk.conservativeMode ? "true" : "false",
                        heartbeatRisk.emergencyMode ? "true" : "false");
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

        m_lastHeartbeatTime = heartbeatNow;
    }

    //+------------------------------------------------------------------+
    //| NN health sub-check                                               |
    //+------------------------------------------------------------------+
    void EmitNNHealthCheck(CNeuralNetworkStrategy* &strategies[])
    {
        if(!m_aiEnabled || !m_nnEnabled || !m_nnOnlineTraining)
            return;

        datetime heartbeatNow = TimeCurrent();
        if(m_lastNNHealthLogTime != 0 && (heartbeatNow - m_lastNNHealthLogTime) < m_heartbeatIntervalSec)
            return;

        for(int nnIdx = 0; nnIdx < ArraySize(strategies); nnIdx++)
        {
            CNeuralNetworkStrategy* nnHealth = strategies[nnIdx];
            if(nnHealth == NULL)
                continue;

            // The actual NN health logging is kept minimal here.
            // Detailed NN health is handled by the main EA's existing NN health path
            // which has access to the full strategy objects.
            PrintFormat("[NN-HEALTH] idx=%d | active", nnIdx);
        }

        m_lastNNHealthLogTime = heartbeatNow;
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
                                  datetime heartbeatNow)
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
                                            roleShadowSignals,
                                            roleVoteSuppressed,
                                            clusterTrendSignals,
                                            clusterMeanReversionSignals,
                                            clusterStructureSignals,
                                            clusterNoneSignals);

        PrintFormat("[CONSENSUS-SNAPSHOT] generated=%I64u | after_pipeline=%I64u | after_quorum=%I64u | raw_none=%I64u | filtered_out=%I64u | quorum_failed=%I64u | intrabar_not_eligible=%I64u | reason_total=%I64u",
                    diagSignalsGenerated,
                    diagSignalsAfterPipeline,
                    diagSignalsAfterQuorum,
                    diagRawNone,
                    diagFilteredOut,
                    diagQuorumFailed,
                    diagIntrabarNotEligible,
                    diagReasonTotal);
        PrintFormat("[STRATEGY-REJECTS] momentum_none=%I64u | momentum_cooldown=%I64u | momentum_low_vol=%I64u | momentum_no_crossover=%I64u | momentum_trend_misaligned=%I64u | momentum_not_ready=%I64u | uict_none=%I64u | uict_neutral_bias=%I64u | uict_other_filters=%I64u",
                    diagMomentumNone,
                    diagMomentumCooldown,
                    diagMomentumLowVolatility,
                    diagMomentumNoCrossover,
                    diagMomentumTrendMisaligned,
                    diagMomentumNotReady,
                    diagUICTNone,
                    diagUICTNeutralBias,
                    diagUICTOtherFilters);
        PrintFormat("[ROLE-CLUSTER] primary=%I64u | feature=%I64u | shadow=%I64u | suppressed=%I64u | trend=%I64u | mean_reversion=%I64u | structure=%I64u | none=%I64u",
                    rolePrimarySignals,
                    roleFeatureSignals,
                    roleShadowSignals,
                    roleVoteSuppressed,
                    clusterTrendSignals,
                    clusterMeanReversionSignals,
                    clusterStructureSignals,
                    clusterNoneSignals);
        PrintFormat("[QUIET-REASONS] no_new_bar=%I64u | cadence_hold=%I64u | missing_manager=%I64u | no_signal=%I64u | validator=%I64u | risk=%I64u | entry_blocked=%I64u | sizing=%I64u",
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
           (m_lastNoSignalAlertTime == 0 || (heartbeatNow - m_lastNoSignalAlertTime) >= m_heartbeatIntervalSec))
        {
            PrintFormat("[NO-SIGNAL-ALERT-CONSENSUS] window_scans=%I64u | no_signal=%I64u (%.1f%%) | dominant=%s | raw_none=%I64u | filtered_out=%I64u | quorum_failed=%I64u | intrabar_not_eligible=%I64u | reason_total=%I64u | momentum_none=%I64u | uict_none=%I64u | uict_neutral_bias=%I64u",
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
            m_lastNoSignalAlertTime = heartbeatNow;
        }
    }
};

#endif // __DIAGNOSTICS_MANAGER_MQH__
