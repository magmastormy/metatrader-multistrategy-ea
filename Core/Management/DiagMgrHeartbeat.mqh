// Stateless emitters for the individual heartbeat sub-blocks plus
// the windowed-delta / conversion-rate arithmetic.
// Every log tag, format string and field order is byte-identical to
// the original inline EmitHeartbeat() body. The caller retains all
// control flow (verbosity gates, guards, ordering) so the emitted
// heartbeat stream is directly comparable to prior regression logs.
#ifndef DIAG_MGR_HEARTBEAT_MQH
#define DIAG_MGR_HEARTBEAT_MQH

#include "../Utils/Enums.mqh"
#include "../Utils/JsonLogger.mqh"
#include "../Utils/LogMacros.mqh"
#include "../Risk/UnifiedRiskManager.mqh"
#include "../Risk/CompoundingTierManager.mqh"
#include "../Engines/SessionWeightManager.mqh"
#include "../Engines/SkewStepAnalyzer.mqh"
#include "../Engines/FamilyStrategyWeightMatrix.mqh"
#include "../Processing/DerivAssetProfiler.mqh"
#include "../Processing/MultiAssetProfiler.mqh"
#include "../../IndicatorManager.mqh"

// CDiagMgrHeartbeat �?stateless heartbeat emitters and math
class CDiagMgrHeartbeat
{
public:
// Windowed delta mirroring EmitHeartbeat()'s arithmetic: on counter underflow this
// returns the CURRENT value, not zero.
    static ulong WindowDelta(const ulong current, const ulong previous)
    {
        return (current >= previous) ? (current - previous) : current;
    }

// Percentage ratio with divide-by-zero guard
    static double Ratio(const ulong numerator, const ulong denominator)
    {
        return (denominator > 0) ? (100.0 * (double)numerator / (double)denominator) : 0.0;
    }

    static void EmitCoreLines(const ulong scansAttempted,
                              const ulong noSignalCount,
                              const ulong validatorRejects,
                              const ulong syntheticSpikeEvents,
                              const bool tradingPaused,
                              const ulong signalsGenerated,
                              const ulong signalsValidated,
                              const ulong signalsSent,
                              const string corrId)
    {
        string pauseFlag = tradingPaused ? "true" : "false";
        PrintFormat(FMT_HEARTBEAT, scansAttempted, noSignalCount,
                    validatorRejects, syntheticSpikeEvents, pauseFlag);
        CJsonLogger::LogInfo("Heartbeat",
            StringFormat("scans=%I64u | no_signal=%I64u | validator_reject=%I64u | spike_events=%I64u | pause_active=%s",
                    scansAttempted, noSignalCount,
                    validatorRejects, syntheticSpikeEvents, pauseFlag), corrId);

        PrintFormat(FMT_HEARTBEAT_FUNNEL, signalsGenerated, signalsValidated, signalsSent);
        CJsonLogger::LogInfo("HeartbeatFunnel",
            StringFormat("signals_generated=%I64u | signals_validated=%I64u | signals_sent=%I64u",
            signalsGenerated, signalsValidated, signalsSent), corrId);
    }

// Compounding tier / session weight / skew step / family weight
// heartbeat diagnostics
    static void EmitModuleHeartbeats(CCompoundingTierManager* compoundingTierManager,
                                     CSessionWeightManager* sessionWeightManager,
                                     CSkewStepAnalyzer* skewStepAnalyzer,
                                     CFamilyStrategyWeightMatrix* familyWeightMatrix,
                                     const string corrId)
    {
        if(compoundingTierManager != NULL && compoundingTierManager.IsInitialized())
        {
            string diag = compoundingTierManager.GetHeartbeatString();
            CJsonLogger::LogInfo("CompoundingTierHeartbeat", diag, corrId);
            // AGENTS.md §6: [COMPOUNDING-TIER-HEARTBEAT] log signature
            PrintFormat(FMT_COMPOUNDING_TIER_HEARTBEAT, diag);
        }

        //--- Session weight heartbeat diagnostics
        if(sessionWeightManager != NULL && sessionWeightManager.IsInitialized())
        {
            string swHb = sessionWeightManager.GetHeartbeatString();
            CJsonLogger::LogInfo("SessionWeightHeartbeat", swHb, corrId);
            // AGENTS.md §6: [SESSION-WEIGHT-HEARTBEAT] log signature
            PrintFormat(FMT_SESSION_WEIGHT_HEARTBEAT, swHb);
        }

        //--- Skew step heartbeat diagnostics
        if(skewStepAnalyzer != NULL && skewStepAnalyzer.IsInitialized())
        {
            string ssHb = skewStepAnalyzer.GetHeartbeatString();
            CJsonLogger::LogInfo("SkewStepHeartbeat", ssHb, corrId);
            // AGENTS.md §6: [SKEW-STEP-HEARTBEAT] log signature
            PrintFormat(FMT_SKEW_STEP_HEARTBEAT, ssHb);
        }

        //--- Family weight matrix heartbeat diagnostics
        if(familyWeightMatrix != NULL && familyWeightMatrix.IsInitialized())
        {
            string fwHb = familyWeightMatrix.GetHeartbeatString();
            CJsonLogger::LogInfo("FamilyWeightMatrix", fwHb, corrId);
            // AGENTS.md §6: [FAMILY-WEIGHT-MATRIX] log signature
            PrintFormat(FMT_FAMILY_WEIGHT_MATRIX, fwHb);
        }
    }

// Per-symbol family / asset-class detection diagnostics
// Caller keeps the outer (derivProfiler != NULL && count > 0) guard.
    static void EmitSymbolProfileDiagnostics(CDerivAssetProfiler* derivProfiler,
                                             CMultiAssetProfiler* multiAssetProfiler,
                                             string &symbols[],
                                             const int symbolCount,
                                             const bool logVerbose,
                                             const string corrId)
    {
        for(int i = 0; i < symbolCount; i++)
        {
            if(multiAssetProfiler != NULL && !multiAssetProfiler.IsDerivSymbol(symbols[i]))
            {
                if(logVerbose)
                {
                    string assetClassName = multiAssetProfiler.GetAssetClassName(symbols[i]);
                    SAssetProfile profile = multiAssetProfiler.GetProfile(symbols[i]);
                    PrintFormat(FMT_HEARTBEAT_ASSET_CLASS, symbols[i], assetClassName,
                        profile.atrMultiplierSL, profile.atrMultiplierTP, profile.riskPerTrade,
                        profile.enableScalpEngine ? "Y" : "N",
                        profile.enableGridRecovery ? "Y" : "N",
                        profile.enableBreakoutEngine ? "Y" : "N");
                    CJsonLogger::LogDebug("HeartbeatAssetClass",
                        StringFormat("symbol=%s | class=%s | atrSL=%.2f | atrTP=%.2f | risk=%.2f%% | scalp=%s | grid=%s | breakout=%s",
                            symbols[i], assetClassName,
                            profile.atrMultiplierSL, profile.atrMultiplierTP,
                            profile.riskPerTrade,
                            profile.enableScalpEngine ? "Y" : "N",
                            profile.enableGridRecovery ? "Y" : "N",
                            profile.enableBreakoutEngine ? "Y" : "N"), corrId);
                }
            }
            else
            {
                string familyName = derivProfiler.GetFamilyName(symbols[i]);
                if(logVerbose)
                {
                    PrintFormat(FMT_HEARTBEAT_FAMILY, symbols[i], familyName);
                    CJsonLogger::LogDebug("HeartbeatFamily",
                        StringFormat("symbol=%s | family=%s", symbols[i], familyName), corrId);
                }
            }
        }
    }

// Grid-recovery and scalp position counts
    static void EmitPositionCounts(const string corrId)
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
        PrintFormat(FMT_HEARTBEAT_POSITIONS, totalPositions, gridRecoveryCount, atrScalpCount);
        CJsonLogger::LogInfo("HeartbeatPositions",
            StringFormat("total=%d | grid_recovery=%d | atr_scalp=%d",
                totalPositions, gridRecoveryCount, atrScalpCount), corrId);
    }

    static void EmitConversionRates(const ulong windowScans,
                                    const ulong windowGenerated,
                                    const double rateValidated,
                                    const double rateSent,
                                    const double noSignalRate,
                                    const string corrId)
    {
        PrintFormat(FMT_CONVERSION_RATES, windowScans, windowGenerated,
            rateValidated, rateSent, noSignalRate);
        CJsonLogger::LogInfo("ConversionRates",
            StringFormat("window_scans=%I64u | generated=%I64u | validated=%.1f%% | sent=%.1f%% | no_signal=%.1f%%",
                windowScans, windowGenerated,
                rateValidated, rateSent, noSignalRate), corrId);
    }

// No-signal alert (heartbeat variant)
// Caller owns the trigger condition and the alert-time bookkeeping.
    static void EmitNoSignalAlert(const ulong windowScans,
                                  const ulong windowNoSignal,
                                  const double noSignalRate,
                                  const string corrId)
    {
        PrintFormat(FMT_NO_SIGNAL_ALERT, windowScans, windowNoSignal, noSignalRate);
        CJsonLogger::LogWarning("NoSignalAlert",
            StringFormat("window_scans=%I64u | no_signal=%I64u (%.1f%%)",
                windowScans, windowNoSignal, noSignalRate), corrId);
    }

    static void EmitRiskBudget(CUnifiedRiskManager* riskManager, const string corrId)
    {
        if(riskManager != NULL)
        {
            SUnifiedRiskSnapshot heartbeatRisk = riskManager.GetSnapshot();
            PrintFormat(FMT_RISK_BUDGET, heartbeatRisk.dailyRiskUsedPercent, heartbeatRisk.maxDailyRiskPercent,
                heartbeatRisk.dailyEntryRiskUsedPercent, heartbeatRisk.dailyMarkToMarketLossPercent,
                heartbeatRisk.openExposureRiskPercent,
                heartbeatRisk.conservativeMode ? "true" : "false",
                heartbeatRisk.emergencyMode ? "true" : "false");
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

    static void ReleaseUnusedIndicators()
    {
        // Deliberately empty. Most consumers fetch a handle once in Init and keep the number in a
        // member; an idle sweep that releases "unused" rows frees handles those members still read,
        // and the terminal reuses the number for a different indicator. The table is bounded by
        // symbols x timeframes x parameters (about 400 rows on the 13-symbol roster) and is freed
        // by CIndicatorManager::DestroyInstance() at deinit.
    }
};

#endif // DIAG_MGR_HEARTBEAT_MQH

