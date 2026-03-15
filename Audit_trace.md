# Audit Trace

## Document Metadata
- Last Updated: 2026-03-07
- Scope: execution-safety remediation status after code fixes
- Evidence base: static audit, `test1.log`, and post-change compile verification

## Executive Summary
The latest `test1.log` changes the no-trade diagnosis. Consensus deadlock was a real earlier issue and remains fixed, but the current runtime stall is now upstream of validator, risk, and execution: generated signals are being zeroed by the pipeline confidence gate, and the visible generated signals are mostly coming from a shadow-only strategy rather than the primary live voters.

The biggest execution and reliability fixes now implemented are:

1. Intrabar dynamic quorum is contributor-aware instead of being pinned by silent eligible voters.
2. `CTradeManager` no longer defaults to asynchronous market sends.
3. Market orders are repriced at send time and stops are recalculated from the current market price on each attempt.
4. `PositionSizer` now uses the same contract-spec-aware risk math and equity-aware denominator as the risk gate.
5. `PerformanceAnalytics` is initialized and updated from confirmed close transactions instead of being effectively inert.
6. `AdvancedPositionManager` now reconstructs partial-close and breakeven state for already-open positions.
7. Startup now rejects unsupported non-hedging account models instead of running with unsafe ownership assumptions.
8. Pipeline/validator/execution confidence floors are now decoupled from the AI confidence input.
9. Pipeline thresholding now uses `CRegimeEngine` state instead of inferring weak regime from `TrendEngine` warmup/neutral output.
10. `Trend` strategy now emits explicit reject reasons so primary-live starvation is diagnosable in logs.

`./sync_and_compile.ps1 -MirrorSync` passed with `0 errors, 0 warnings` after the remediation batch.

## Runtime Diagnosis From `test1.log`
The supplied log now shows a different blocker than the earlier session: consensus is no longer the immediate failure point, but the pipeline is still removing every generated signal before validation.

Strong evidence:
- `test1.log:648` `[HEARTBEAT] scans=30 | intrabar=24 | no_signal=30 | validator_reject=0 | risk_reject=0 | trades_opened=0 | shadow_trades=0`
- `test1.log:649` `[HEARTBEAT-FUNNEL] signals_generated=20 | signals_after_pipeline=0 | signals_after_quorum=0 | signals_validated=0 | signals_risk_approved=0 | shadow_or_live_sent=0`
- `test1.log:362` `[PIPELINE-THRESHOLD] base=0.60 | effective=0.69 | regime=REGIME_NONE | cap=0.00 | intrabar=false`
- `test1.log:358` `[COST-GATE] Jump 10 Index.0 | regime=TREND | spread_atr=0.0000/0.2500 | cooldown=false | z=0.063/2.500`
- `test1.log:363` `[Pipeline] ConfidenceFilter: FAILED - REGIME_NONE | Confidence 0.54 below minimum 0.60 (effective: 0.69)`
- `test1.log:100-106` governance keeps `Fibonacci` shadow-only while primary live voters are `Momentum`, `Trend`, and `Unified ICT`

Interpretation:
- pipeline confidence was the immediate blocker
- the pipeline threshold was using the wrong state source (`REGIME_NONE`) while the regime engine had valid market-state data
- the non-AI strategy stack was incorrectly coupled to `InpAIConfidenceThreshold`
- the only consistently visible generated signals in this log were from `Fibonacci`, which is intentionally shadow-only in the current governance profile
- `Momentum` and `Unified ICT` were alive but mostly self-rejecting, while `Trend` had no reject telemetry and therefore poor diagnosability

## Fixed This Batch

### 1. Intrabar deadlock
- Status: fixed
- Change: `EnterpriseStrategyManager` now derives intrabar dynamic quorum from actual live contributors in the current cycle.
- Effect: a single strong intrabar contributor is no longer blocked by multiple silent eligible voters when the single-voter confidence gate is already satisfied.

### 1b. Non-AI confidence thresholds were incorrectly AI-coupled
- Status: fixed
- Change: `MultiStrategyAutonomousEA.mq5` now uses dedicated non-AI inputs for pipeline and validator confidence floors instead of reusing `InpAIConfidenceThreshold`.
- Effect: human strategies are no longer blocked by an AI-specific confidence policy.

### 1c. Regime-aware thresholding was using the wrong engine state
- Status: fixed
- Change: `CUnifiedSignalPipeline` now sources threshold adjustments from `CRegimeEngine` snapshot state rather than `TrendEngine` neutral/warmup output.
- Effect: `[PIPELINE-THRESHOLD]` now reflects real regime context, and weak-regime uplift is no longer applied because of an unrelated trend-engine neutral state.

### 1d. Fallback execution approval was also AI-coupled
- Status: fixed
- Change: validator-fallback approval now uses profile-aware validator confidence floors instead of `InpAIConfidenceThreshold`.
- Effect: the execution path no longer reintroduces the same AI-threshold coupling after consensus.

### 1e. Live strategy starvation is now more diagnosable
- Status: improved
- Change: `StrategyTrend` now tags and logs explicit reject reasons like the `Momentum` path already did.
- Effect: a fresh run can now distinguish "Trend is silent because no setup exists" from "Trend is broken or blocked."

### 2. Async send / false execution confirmation risk
- Status: mitigated
- Change: `CTradeManager` now initializes in synchronous mode instead of async mode.
- Effect: `OpenPosition(...)` no longer returns success before the broker response path is complete, which removes the most dangerous mismatch with immediate EA-side success accounting.

### 3. Stale pre-send price for SL/TP
- Status: fixed
- Change: `TradeManager` now reprices market orders at submit time and recalculates SL/TP from the current market price on each retry attempt.
- Effect: stops are no longer built off a stale snapshot while the actual market order is submitted at an unrelated broker-side price.

### 4. Inconsistent sizing math
- Status: fixed
- Change: `PositionSizer` now uses tick-size/tick-value risk-per-lot math and `min(balance,equity)` denominator alignment.
- Effect: sizing, risk validation, and portfolio-risk accounting are materially closer to one economic-risk model across FX, metals, indices, and synthetics.

### 5. Restart-unsafe partial close / breakeven state
- Status: fixed
- Change: `AdvancedPositionManager` now reconstructs open-position state from `POSITION_IDENTIFIER`, live SL placement, and history-derived entry volume.
- Effect: restarts no longer blindly reclassify already-managed positions as fresh state.

### 6. Adaptive analytics dead path
- Status: fixed
- Change: `PerformanceAnalytics` is initialized in `OnInit`, closed-trade analytics are recorded from `OnTradeTransaction`, and `RecordClosedTrade(...)` now updates trade counts, wins/losses, recent returns, and consecutive-loss state.
- Effect: adaptive-risk inputs are now close-driven instead of effectively empty.

### 7. Broker/account compatibility hardening
- Status: partially fixed
- Change: startup now fails fast on unsupported non-hedging account models, and symbol validation now rejects close-only symbols plus invalid volume-step specs.
- Effect: the EA no longer silently runs on the most obviously unsafe ownership model.

### 8. Freeze-level / stale-symbol / log-flood code smells
- Status: fixed
- Changes:
  - stop validation now considers freeze level as well as stop level
  - the stale-symbol references in `TradeManager` management helpers were corrected
  - `PositionSizer` no longer logs symbol volume metadata on every normalization
  - the dormant `IsNewBar(...)` helper is now symbol/timeframe scoped

## Remaining High-Risk Items

### 1. Execution truth is still not fully transaction-owned
- Status: partially fixed, not fully closed
- What remains: disabling async mode removes the worst mismatch, but the EA still increments some runtime counters immediately after `OpenPosition(...)` rather than deriving all execution state from confirmed transaction/deal events.
- Recommended next step: promote a full request/deal state machine keyed by request ID and position ID.

### 2. External/manual position governance is still policy-heavy
- Status: unresolved by design
- What remains: non-EA positions can still influence capacity and unprotected-position blocking behavior.
- Recommended next step: either keep it and document it as explicit account-wide governance, or narrow those gates to EA-owned positions only.

### 3. AI strategy governance normalization is still incomplete
- Status: partially addressed
- What remains: AI adapters participate correctly in consensus, but their governance metadata is still less explicit than the curated human strategy set.
- Recommended next step: normalize AI adapters under the same role/cluster policy model used for curated strategies.

## Strategy Improvement Status
This batch improved strategy throughput and decision reliability indirectly by fixing the execution/governance layer around them:

1. contributor-aware intrabar quorum now lets real signals survive consensus
2. transaction-driven analytics now provide usable closed-trade feedback
3. broker-aware send logic reduces false rejects that previously made strategies look inactive
4. non-AI strategy thresholds are now controlled by dedicated pipeline/validator inputs instead of the AI floor
5. regime-aware thresholding now aligns with the regime/cost engine that already decides market-state viability

I still did not promote `Fibonacci` into live voting or blindly loosen `Momentum`/`Unified ICT` rules. The new log shows those are governance/strategy decisions, not hidden execution bugs. They should be tuned only after the next run proves whether the primary live set starts surfacing valid post-pipeline signals.

## Testing Strategy

### Required next runtime validation
1. Re-run the EA and verify startup emits `[EXECUTION-MODE]`.
2. Confirm `[PIPELINE-THRESHOLD]` now reports regime-driven tags like `REGIME_TREND_RELAX`, `REGIME_BREAKOUT_RELAX`, `REGIME_RANGE`, or `REGIME_ENGINE_WARMUP` instead of the old false `REGIME_NONE` path.
3. Confirm `signals_after_pipeline` becomes non-zero on at least one managed symbol.
4. Confirm `Trend` now emits reject telemetry when it does not produce a signal.
5. Confirm new transaction logs appear for EA-owned deals:
   - `[TRADE-CONFIRMED]`
   - `[TRADE-SUCCESS]`
   - `[TRADE-ERROR]`
6. Confirm shadow sessions produce `[SHADOW-TRADE]` instead of silent no-trade behavior when consensus passes.
7. Confirm `PerformanceAnalytics` metrics change after confirmed closes.

### Edge-case simulations
1. one strong intrabar AI voter with all other live voters silent
2. close-only symbol in configured symbol list
3. netting account startup
4. restart with already partially closed positions
5. transient broker reject / retry path under high volatility
6. freeze-level-restricted symbol while stop modifications are attempted

## Outcome
The main issues from the earlier audit snapshot were not ignored, and the new runtime evidence has now been folded into the code path. The code compiles cleanly and the most important hidden coupling bugs are removed, but the repository still needs one fresh MT5 session to prove whether the remaining no-trade condition is now genuinely strategy/governance driven rather than infrastructure driven.
