# Full Log Forensic Addendum — `20260224.log`

Date: 2026.02.24

This document is an evidence-only forensic addendum based on the full MT5 runtime log `20260224.log` (UTF-16 / contains null bytes). It exists to answer one operational question:

- **Why did the EA run for ~12 hours with zero trades (and often zero shadow trades), despite frequent strategy-layer BUY signals?**

---

## 1) Evidence: the EA is alive and scanning continuously

The heartbeat counters prove the EA is processing and scanning at high frequency.

Examples:

- `00:00:37.573` — `[HEARTBEAT] scans=6974 | intrabar=6972 | no_signal=6972 | validator_reject=0 | risk_reject=0 | trades_opened=0 | shadow_trades=2`
- `12:03:20.559` — `[HEARTBEAT] scans=159594 | intrabar=159450 | no_signal=159594 | validator_reject=0 | risk_reject=0 | trades_opened=0 | shadow_trades=0`
- `12:06:21.731` — `[HEARTBEAT] scans=160296 | intrabar=160152 | no_signal=160296 | validator_reject=0 | risk_reject=0 | trades_opened=0 | shadow_trades=0`

Interpretation:

- `scans` increases steadily over 12 hours.
- `intrabar` is essentially equal to `scans`, so almost all processing cycles are intrabar evaluations.
- `no_signal == scans` late in the run means **enterprise consensus returned `TRADE_SIGNAL_NONE` on essentially every scan**.
- `validator_reject == 0` and `risk_reject == 0` show the EA is **not reaching** validator/risk gates for most scans.

---

## 2) Evidence: the system *can* trade (shadow) when it reaches a committed enterprise candidate

The log includes validated signals and shadow execution early in the session:

- `00:00:01.496` — `[SIGNAL-VALIDATED] Step Index.0 | Signal: BUY | Confidence: 0.809027... | Confluence: 2 | Quality: 0.705416...`
- `00:00:01.505` — `[SHADOW-TRADE] Step Index.0 | BUY | lot=0.31 | conf=0.71 | confluence=2 | contributors=Unified ICT/SMC,Transformer AI | SL=... | TP=...`

It repeats later:

- `00:16:18.243` — `[SIGNAL-VALIDATED] Step Index.0 | Signal: BUY | Confidence: 0.809027... | Confluence: 2 | Quality: 0.705416...`
- `00:16:18.245` — `[SHADOW-TRADE] Step Index.0 | BUY | lot=0.31 | conf=0.71 | confluence=2 | contributors=Unified ICT/SMC,Transformer AI | SL=... | TP=...`

Interpretation:

- This proves the end-to-end path exists and works (consensus -> validator -> sizing -> execution branch).
- Therefore, the 12-hour starvation is not “broker rejects everything” and not “TradeManager broken.”

---

## 3) Primary blocking layer: enterprise consensus deadlock during intrabar

The manager’s diagnostics explicitly show the failure mode in the same session:

- `00:02:01.063` — `[CONSENSUS-DIAG] Step Index.0 | raw_none=41 | filtered_out=0 | quorum_failed=19 | intrabar_not_eligible=38`
- `00:02:01.408` — `[CONSENSUS-DIAG] Jump 10 Index.0 | raw_none=40 | filtered_out=20 | quorum_failed=20 | intrabar_not_eligible=40`
- `00:03:00.657` — `[CONSENSUS-DIAG] Step Index.0 | raw_none=80 | filtered_out=0 | quorum_failed=40 | intrabar_not_eligible=80`
- `00:04:01.192` — `[CONSENSUS-DIAG] Step Index.0 | raw_none=78 | filtered_out=0 | quorum_failed=39 | intrabar_not_eligible=78`

Interpretation:

- **`intrabar_not_eligible` rising** means most enabled strategies do not participate during intrabar scans.
- **`quorum_failed` rising** means the remaining eligible strategies fail to reach the quorum threshold.
- Combined, this yields `enterpriseSignal == NONE` and causes the EA loop to skip validator/execution.

This aligns with the heartbeat signature:

- `no_signal` grows at scan-rate while `validator_reject` and `risk_reject` remain 0.

---

## 4) Secondary blocker: confidence floor becomes effectively stricter than configured

The log proves an elevated effective confidence threshold is applied:

- `00:02:01.406` — `[Pipeline] ConfidenceFilter: FAILED - Confidence 0.57 below minimum 0.60 (effective: 0.69)`

Interpretation:

- Even when filters pass, confidence can still fail due to regime-based elevation.
- Fewer passing votes increases the probability of quorum failure.

---

## 5) ADX failure analysis (TrendEngine)

### 5.1 Buffer copy failures are frequent

Evidence:

- `00:02:01.064` — `[ERROR] TrendEngine | Type: ADX_BUFFER_COPY_FAILED | Details: Failed to copy ADX buffer data for Jump 10 Index.0 PERIOD_M30 (err=4806)`

The same error appears for multiple symbols throughout the session.

### 5.2 ADX magnitude can be absurd, indicating invalid data usage

Evidence:

- `00:02:01.413` — `[TrendEngine] Trend: TREND_NONE | Strength: 70.0 | Angle: -0.1 | ADX: 34124.2`

Interpretation:

- ADX should be within 0–100.
- A value like `34124.2` is evidence of invalid buffer reads (wrong buffer index, uninitialized output array, stale values after CopyBuffer failure, or series mis-handling).

### 5.3 Impact on trade starvation

- ADX malfunction is likely **amplifying** starvation by destabilizing regime classification and confidence dynamics.
- However, consensus diagnostics alone are sufficient to explain “enterpriseSignal stays NONE” starvation.

---

## 6) Final verdict (full-log)

- **Is the EA structurally blocking trades?**
  - Yes, via enterprise consensus in intrabar mode (eligibility suppression + quorum failure).

- **Are signals generated but filtered?**
  - Yes. Strategy-layer BUY signals exist, but they do not become committed enterprise candidates for most scans.

- **Is execution denied at risk/broker layer?**
  - No evidence of this as the dominant mode. The run is mostly not reaching risk/execution layers.

- **Is the system in logical deadlock?**
  - Yes: intrabar eligibility removes most contributors, quorum fails, and the EA never reaches validator/execution.

- **Will trades realistically occur without changes?**
  - Not reliably. Under the observed conditions, the probability of continued zero trades is extremely high.

---

## 7) Implementation recommendations (evidence-scoped)

### 7.1 Consensus conversion (highest ROI)

- Preserve new-bar strictness (`m_minQuorum=2`).
- Avoid intrabar deadlock by allowing intrabar quorum to drop to 1 **when only one intrabar-eligible strategy exists**, but keep the existing safety hardening:
  - when `effectiveQuorum == 1` in intrabar, require `finalConfidence >= 0.65`.

This is consistent with the institutional architecture:

- validator remains authoritative
- unified risk remains the sole veto

### 7.2 ADX robustness fix (required)

Implement all of the following in TrendEngine:

- If `CopyBuffer()` returns `< 1`, do not use the result.
- Check handle readiness:
  - handle is valid
  - `BarsCalculated(handle)` is sufficient
  - `Bars(symbol, tf)` is sufficient
- Ensure correct buffer index for ADX main line and consistent `ArraySetAsSeries` usage.
- Add a rate-limited diagnostic that prints:
  - `CopyBuffer return`, `GetLastError`, `Bars`, `BarsCalculated`, `symbol`, `tf`.

### 7.3 Confidence regime bounding

- Log the source of the `effective` minimum (why it rises to 0.69).
- Consider bounding the maximum elevated threshold to avoid “untradeable regime lock.”

### 7.4 Operator-facing deadlock attribution log

When `enterpriseSignal == NONE` for long stretches, print a rate-limited line attributing the dominant reason based on manager counters:

- `quorum_failed`
- `intrabar_not_eligible`
- `filtered_out`

This prevents the recurring operator confusion where `[SIGNAL] ... BUY` exists but `no_signal` increments forever.
