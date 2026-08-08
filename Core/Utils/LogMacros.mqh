//+------------------------------------------------------------------+
//| LogMacros.mqh                                                    |
//| Standardized log signature format strings for consistent logging |
//| Implements AGENTS.md §6 logging checklist                        |
//+------------------------------------------------------------------+
#ifndef CORE_UTILS_LOG_MACROS_MQH
#define CORE_UTILS_LOG_MACROS_MQH

#include "Enums.mqh"
#include "JsonLogger.mqh"

//--- Core heartbeat format strings
#define FMT_HEARTBEAT "[HEARTBEAT] scans=%I64u | intrabar=%I64u | no_signal=%I64u | validator_reject=%I64u | risk_reject=%I64u | trades_opened=%I64u | spike_events=%I64u | pause_active=%s"
#define FMT_HEARTBEAT_FUNNEL "[HEARTBEAT-FUNNEL] signals_generated=%I64u | signals_after_pipeline=%I64u | signals_after_quorum=%I64u | signals_validated=%I64u | signals_risk_approved=%I64u | signals_sent=%I64u"

//--- Consensus diagnostics
#define FMT_CONSENSUS_DIAG "[CONSENSUS-DIAG] %s"
#define FMT_CONSENSUS_ROOT "[CONSENSUS-ROOT] %s"
#define FMT_CONSENSUS_STRATEGY "[CONSENSUS-STRATEGY] %s"
#define FMT_CONSENSUS_ROLE "[CONSENSUS-ROLE] %s"
#define FMT_CONSENSUS_CLUSTER "[CONSENSUS-CLUSTER] %s"

//--- Signal rejection
#define FMT_SIGNAL_REJECTED "[SIGNAL-REJECTED] %s"

//--- AI voting
#define FMT_AI_VOTE "[AI-VOTE] %s"
#define FMT_AI_VOTE_MISSING "[AI-VOTE-MISSING] symbol=%s | type=%s | last_vote=%s | stale_seconds=%d"

//--- Compounding tier
#define FMT_COMPOUNDING_TIER_HEARTBEAT "[COMPOUNDING-TIER-HEARTBEAT] %s"
#define FMT_COMPOUNDING_TIER_MILESTONE "[COMPOUNDING-TIER-MILESTONE] %s"

//--- Family weight matrix
#define FMT_FAMILY_WEIGHT_MATRIX "[FAMILY-WEIGHT-MATRIX] %s"
#define FMT_FAMILY_WEIGHT_VOL "[FAMILY-WEIGHT-VOL] %s"

//--- Session weight
#define FMT_SESSION_WEIGHT_HEARTBEAT "[SESSION-WEIGHT-HEARTBEAT] %s"

//--- Skew step
#define FMT_SKEW_STEP_HEARTBEAT "[SKEW-STEP-HEARTBEAT] %s"

//--- Risk family position
#define FMT_RISK_FAMILY_POS "[RISK-FAMILY-POS] %s"

//--- ADX modifier
#define FMT_ADX_MODIFIER "[ADX-MODIFIER] %s"

//--- Authority reject (replaces SHADOW-TRADE)
#define FMT_AUTHORITY_REJECT "[AUTHORITY-REJECT] %s"
#define FMT_AUTHORITY_REDUCED "[AUTHORITY-REDUCED] %s"

//--- Python bridge dashboard
#define FMT_PYTHON_BRIDGE_DASHBOARD "[PYTHON-BRIDGE-DASHBOARD] %s"

//--- Conversion rates
#define FMT_CONVERSION_RATES "[CONVERSION-RATES] window_scans=%I64u | generated=%I64u | after_pipeline=%.1f%% | after_quorum=%.1f%% | validated=%.1f%% | risk_approved=%.1f%% | sent=%.1f%% | no_signal=%.1f%%"

//--- No signal alert
#define FMT_NO_SIGNAL_ALERT "[NO-SIGNAL-ALERT] window_scans=%I64u | no_signal=%I64u (%.1f%%) | no_new_bar=%I64u | cadence_hold=%I64u | missing_manager=%I64u"

//--- Risk budget
#define FMT_RISK_BUDGET "[RISK-BUDGET] effective=%.2f/%.2f | entry=%.2f | mtm=%.2f | open_exposure=%.2f | conservative=%s | emergency=%s"

//--- Heartbeat positions
#define FMT_HEARTBEAT_POSITIONS "[HEARTBEAT-POSITIONS] total=%d | grid_recovery=%d | atr_scalp=%d"

//--- Heartbeat asset class
#define FMT_HEARTBEAT_ASSET_CLASS "[HEARTBEAT-ASSET-CLASS] symbol=%s | class=%s | atrSL=%.2f | atrTP=%.2f | risk=%.2f%% | scalp=%s | grid=%s | breakout=%s"

//--- Heartbeat family
#define FMT_HEARTBEAT_FAMILY "[HEARTBEAT-FAMILY] symbol=%s | family=%s"

//--- NN health
#define FMT_NN_HEALTH "[NN-HEALTH] idx=%d | active"

//--- Candidate builder
#define FMT_CANDIDATE_BUILDER "[CANDIDATE-BUILDER] %s"

//--- Risk adapt
#define FMT_RISK_ADAPT "[RISK-ADAPT] %s"

//--- Momentum scale
#define FMT_MOMENTUM_SCALE "[MOMENTUM-SCALE] %s"

//--- Performance timing
#define LOG_PERFORMANCE(component, metric, duration_us, corrId) \
    CJsonLogger::LogPerformance(component, metric, duration_us, corrId)

//--- JSON structured logging - matching actual CJsonLogger method signatures
#define LOG_JSON_TRADE_OPEN(symbol, side, lot, price, sl, tp, magic, corrId) \
    CJsonLogger::LogTradeOpen(symbol, (side == TRADE_SIGNAL_BUY ? TRADE_SIGNAL_BUY : TRADE_SIGNAL_SELL), lot, price, "", corrId)

#define LOG_JSON_TRADE_CLOSE(ticket, symbol, side, lot, price, profit, magic, corrId) \
    CJsonLogger::LogTradeClose(symbol, profit, corrId, "")

#define LOG_JSON_SIGNAL(symbol, strategy, signal, confidence, confluence, corrId) \
    CJsonLogger::LogSignal(symbol, signal, confidence, strategy, corrId, "")

#define LOG_JSON_RISK_EVENT(event, riskPct, limitPct, action, corrId) \
    CJsonLogger::LogRiskEvent("", event, riskPct, corrId, "")

#define LOG_JSON_AI_EVENT(adapter, vote, weight, confidence, corrId) \
    CJsonLogger::LogAIEvent("", adapter, vote, confidence, corrId, "")

#define LOG_JSON_CONSENSUS(symbol, consensus, quorum, votes, corrId) \
    CJsonLogger::LogConsensus(symbol, consensus, quorum, votes, corrId, "")

#define LOG_JSON_ERROR(code, message, context, corrId) \
    CJsonLogger::LogError("", message, "", "", corrId, "")

#define LOG_JSON_DEBUG(component, message, corrId) \
    CJsonLogger::LogDebug(component, message, "", "", corrId, "")

#define LOG_JSON_INFO(component, message, corrId) \
    CJsonLogger::LogInfo(component, message, "", "", corrId, "")

#define LOG_JSON_WARN(component, message, corrId) \
    CJsonLogger::LogWarning(component, message, "", "", corrId, "")

//--- Correlation ID helpers
#define GENERATE_CORR_ID() \
    CCorrelationIdGenerator::Generate()


#endif // CORE_UTILS_LOG_MACROS_MQH