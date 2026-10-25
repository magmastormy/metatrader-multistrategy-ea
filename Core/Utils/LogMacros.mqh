// Log signature format strings for the heartbeat block, which emits the same payload to
// CJsonLogger and to the journal. Every macro here has a call site; the tags the rest of the
// EA prints are literal in their own PrintFormat call.
#ifndef CORE_UTILS_LOG_MACROS_MQH
#define CORE_UTILS_LOG_MACROS_MQH

#include "Enums.mqh"
#include "JsonLogger.mqh"

//--- Core heartbeat format strings
#define FMT_HEARTBEAT "[HEARTBEAT] scans=%I64u | no_signal=%I64u | validator_reject=%I64u | spike_events=%I64u | pause_active=%s"
#define FMT_HEARTBEAT_FUNNEL "[HEARTBEAT-FUNNEL] signals_generated=%I64u | signals_validated=%I64u | signals_sent=%I64u"

#define FMT_COMPOUNDING_TIER_HEARTBEAT "[COMPOUNDING-TIER-HEARTBEAT] %s"
#define FMT_SESSION_WEIGHT_HEARTBEAT "[SESSION-WEIGHT-HEARTBEAT] %s"
#define FMT_SKEW_STEP_HEARTBEAT "[SKEW-STEP-HEARTBEAT] %s"
#define FMT_FAMILY_WEIGHT_MATRIX "[FAMILY-WEIGHT-MATRIX] %s"
#define FMT_PYTHON_BRIDGE_DASHBOARD "[PYTHON-BRIDGE-DASHBOARD] %s"

#define FMT_CONVERSION_RATES "[CONVERSION-RATES] window_scans=%I64u | generated=%I64u | validated=%.1f%% | sent=%.1f%% | no_signal=%.1f%%"

#define FMT_NO_SIGNAL_ALERT "[NO-SIGNAL-ALERT] window_scans=%I64u | no_signal=%I64u (%.1f%%)"

#define FMT_RISK_BUDGET "[RISK-BUDGET] effective=%.2f/%.2f | entry=%.2f | mtm=%.2f | open_exposure=%.2f | conservative=%s | emergency=%s"

#define FMT_HEARTBEAT_POSITIONS "[HEARTBEAT-POSITIONS] total=%d | grid_recovery=%d | atr_scalp=%d"

#define FMT_HEARTBEAT_ASSET_CLASS "[HEARTBEAT-ASSET-CLASS] symbol=%s | class=%s | atrSL=%.2f | atrTP=%.2f | risk=%.2f%% | scalp=%s | grid=%s | breakout=%s"

#define FMT_HEARTBEAT_FAMILY "[HEARTBEAT-FAMILY] symbol=%s | family=%s"

#endif // CORE_UTILS_LOG_MACROS_MQH
