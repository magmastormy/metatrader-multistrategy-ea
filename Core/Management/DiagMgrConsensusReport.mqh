// Extracted from DiagnosticsManager.mqh (God-Object decomposition)
// Stateless emitters for the consensus diagnostics report lines
// produced during EmitConsensusDiagnostics().
// Log tags ([CONSENSUS-SNAPSHOT], [STRATEGY-REJECTS], [ROLE-CLUSTER]
// [QUIET-REASONS], [NO-SIGNAL-ALERT-CONSENSUS]), verbosity levels
// and argument order are byte-identical to the original inline body.
#ifndef DIAG_MGR_CONSENSUS_REPORT_MQH
#define DIAG_MGR_CONSENSUS_REPORT_MQH

#include "../Utils/Enums.mqh"
#include "../Utils/LogMacros.mqh"

// CDiagMgrConsensusReport — stateless consensus report emitters
class CDiagMgrConsensusReport
{
public:
    static void EmitConsensusSnapshotLine(const ulong signalsGenerated,
                                          const ulong signalsAfterPipeline,
                                          const ulong signalsAfterQuorum,
                                          const ulong rawNone,
                                          const ulong filteredOut,
                                          const ulong quorumFailed,
                                          const ulong intrabarNotEligible,
                                          const ulong reasonTotal)
    {
        LOG_IF8(LOG_LEVEL_DEBUG, "[CONSENSUS-SNAPSHOT] generated=%I64u | after_pipeline=%I64u | after_quorum=%I64u | raw_none=%I64u | filtered_out=%I64u | quorum_failed=%I64u | intrabar_not_eligible=%I64u | reason_total=%I64u",
                    signalsGenerated,
                    signalsAfterPipeline,
                    signalsAfterQuorum,
                    rawNone,
                    filteredOut,
                    quorumFailed,
                    intrabarNotEligible,
                    reasonTotal);
    }

    static void EmitStrategyRejectsLine(const ulong momentumNone,
                                        const ulong momentumCooldown,
                                        const ulong momentumLowVolatility,
                                        const ulong momentumNoCrossover,
                                        const ulong momentumTrendMisaligned,
                                        const ulong momentumNotReady,
                                        const ulong uictNone,
                                        const ulong uictNeutralBias,
                                        const ulong uictOtherFilters)
    {
        LOG_IF9(LOG_LEVEL_DEBUG, "[STRATEGY-REJECTS] momentum_none=%I64u | momentum_cooldown=%I64u | momentum_low_vol=%I64u | momentum_no_crossover=%I64u | momentum_trend_misaligned=%I64u | momentum_not_ready=%I64u | uict_none=%I64u | uict_neutral_bias=%I64u | uict_other_filters=%I64u",
                    momentumNone,
                    momentumCooldown,
                    momentumLowVolatility,
                    momentumNoCrossover,
                    momentumTrendMisaligned,
                    momentumNotReady,
                    uictNone,
                    uictNeutralBias,
                    uictOtherFilters);
    }

    static void EmitRoleClusterLine(const ulong rolePrimarySignals,
                                    const ulong roleFeatureSignals,
                                    const ulong roleShadowSignals,
                                    const ulong roleVoteSuppressed,
                                    const ulong clusterTrendSignals,
                                    const ulong clusterMeanReversionSignals,
                                    const ulong clusterStructureSignals,
                                    const ulong clusterNoneSignals)
    {
        LOG_IF8(LOG_LEVEL_DEBUG, "[ROLE-CLUSTER] primary=%I64u | feature=%I64u | shadow=%I64u | suppressed=%I64u | trend=%I64u | mean_reversion=%I64u | structure=%I64u | none=%I64u",
                    rolePrimarySignals,
                    roleFeatureSignals,
                    roleShadowSignals,
                    roleVoteSuppressed,
                    clusterTrendSignals,
                    clusterMeanReversionSignals,
                    clusterStructureSignals,
                    clusterNoneSignals);
    }

    static void EmitQuietReasonsLine(const ulong quietNoNewBar,
                                     const ulong quietCadenceHold,
                                     const ulong quietMissingManager,
                                     const ulong noSignalCount,
                                     const ulong validatorRejects,
                                     const ulong riskRejects,
                                     const ulong entryBlocked,
                                     const ulong sizingRejects)
    {
        LOG_IF8(LOG_LEVEL_DEBUG, "[QUIET-REASONS] no_new_bar=%I64u | cadence_hold=%I64u | missing_manager=%I64u | no_signal=%I64u | validator=%I64u | risk=%I64u | entry_blocked=%I64u | sizing=%I64u",
                    quietNoNewBar,
                    quietCadenceHold,
                    quietMissingManager,
                    noSignalCount,
                    validatorRejects,
                    riskRejects,
                    entryBlocked,
                    sizingRejects);
    }

// Caller owns the trigger condition and alert-time bookkeeping.
    static void EmitNoSignalAlertConsensus(const ulong windowScans,
                                           const ulong windowNoSignal,
                                           const double noSignalRate,
                                           const string dominantConsensusCause,
                                           const ulong rawNone,
                                           const ulong filteredOut,
                                           const ulong quorumFailed,
                                           const ulong intrabarNotEligible,
                                           const ulong reasonTotal,
                                           const ulong momentumNone,
                                           const ulong uictNone,
                                           const ulong uictNeutralBias)
    {
        LOG_IF12(LOG_LEVEL_WARN, "[NO-SIGNAL-ALERT-CONSENSUS] window_scans=%I64u | no_signal=%I64u (%.1f%%) | dominant=%s | raw_none=%I64u | filtered_out=%I64u | quorum_failed=%I64u | intrabar_not_eligible=%I64u | reason_total=%I64u | momentum_none=%I64u | uict_none=%I64u | uict_neutral_bias=%I64u",
                    windowScans,
                    windowNoSignal,
                    noSignalRate,
                    dominantConsensusCause,
                    rawNone,
                    filteredOut,
                    quorumFailed,
                    intrabarNotEligible,
                    reasonTotal,
                    momentumNone,
                    uictNone,
                    uictNeutralBias);
    }
};

#endif // DIAG_MGR_CONSENSUS_REPORT_MQH
