# metatrader-multistrategy-ea

## Document Metadata
- Last Updated: 2026-03-25
- Status: Active baseline
- Primary Runtime: `MultiStrategyAutonomousEA.mq5`

Autonomous multi-strategy MetaTrader 5 EA with enterprise-style signal management, unified risk authority, and AI-assisted strategy voters (Neural Network, Transformer, Ensemble) integrated into the runtime consensus path.

## System Snapshot
- Per-symbol strategy managers generate consensus signals.
- Hybrid cadence supports new-bar and intrabar scanning.
- Pre-trade decision gate is centralized in `CUnifiedRiskManager`.
- Execution is centralized in `CTradeManager`.
- Position lifecycle is centralized in `CAdvancedPositionManager`.
- Shadow mode (`InpShadowMode`) runs full stack without sending real orders.
- Retired standalone strategy artifacts and their commented stubs are removed from runtime sources.
- Legacy `Config/StrategyConfig.mqh` (removed-strategy config surface) has been deleted from runtime inventory.

## Core Architecture
- Entrypoint: `MultiStrategyAutonomousEA.mq5`
- Strategy consensus: `Core/Management/EnterpriseStrategyManager.mqh`
- Signal filtering pipeline: `Core/Pipeline/UnifiedSignalPipeline.mqh`
- AI orchestration: `Core/AI/AIStrategyOrchestrator.mqh`
- Risk authority: `Core/Risk/UnifiedRiskManager.mqh`
- Execution: `Core/Trading/TradeManager.mqh`
- Position management: `Core/Trading/AdvancedPositionManager.mqh`
- Indicator cache lifecycle: `IndicatorManager.mqh`

## Runtime Behavior

### Decision cadence
- New-bar scans use conservative consensus behavior.
- Intrabar scans run on timer intervals when enabled.
- Intrabar scope can be chart-only or all managed symbols.
- Startup now reconstructs the last EA trade timestamp from EA-owned history and open positions so cooldown state survives restart/re-attach scenarios.
- Startup emits `[ACCOUNT-CAPACITY]` min-lot affordability diagnostics for each configured symbol before live execution begins.
- Post-trade cooldown, total-position caps, unprotected-position vetoes, and per-symbol capacity now pause entry only; signal generation and validator telemetry continue running while the EA is blocked from sending.
- Validator spread-shock state is symbol-scoped, so one symbol's transient spread event no longer poisons validator spread decisions on the rest of the portfolio.
- Quorum uses normalized weighted conviction pooling (`InpQuorumThreshold`, `InpMinLiveVoters`, per-strategy weights, readiness participation, rolling strategy health) instead of binary voter counts.
- Curated core strategies now have explicit intrabar eligibility controls (`InpIntrabarEligibilityMomentum`, `InpIntrabarEligibilityUnifiedICT`) plus opt-in smoke-test toggles for Fibonacci and Support/Resistance (`InpIntrabarEligibilityFibonacci`, `InpIntrabarEligibilitySupportResistance`).
- Non-AI strategy throughput is controlled by dedicated pipeline confidence and validator profile inputs (confidence + confluence + quality) instead of the AI threshold (`InpPipelineMinConfidence`, `InpValidatorNewBarMinConfidence`, `InpValidatorIntrabarMinConfidence`, `InpValidator*MinConfluence`, `InpValidator*MinQuality`).
- Consensus vote admission now reuses the pipeline's effective confidence floor for the current evaluation, so regime-relaxed pipeline passes are not discarded before quorum.
- Pipeline engine work is now cached per symbol/timeframe/bar and converted into a shared evidence snapshot (`readiness`, `context`, `cost`), reducing duplicate hot-path indicator/structure churn across strategies.
- Pipeline and validator both support bounded soft-pass behavior for near-threshold signals when readiness, context, and conviction are strong, so more valid trades survive to consensus without widening bad-signal admission.
- Consensus is now readiness-aware and reliability-aware: live vote weight is adjusted by role, rolling strategy health, ready-live weight share, and a directional deadband before a side is allowed to win.
- Strategy governance is now continuous rather than purely binary: role/cluster metadata still exists, but live vote impact is modulated by rolling `healthScore` and reliability multipliers instead of treating every enabled strategy as equally trusted at all times.
- The runtime now scans the full symbol set, stages all risk-approved candidates, ranks them by quality/conviction/context/readiness/cost/diversity, and only then selects the best trade for the cycle.
- Live execution now produces an execution receipt (`requested`, `filled`, `retcode`, `requestId`, retries) and daily risk usage is registered against actual fill ratio instead of always charging the requested size.
- Post-quorum nullification now emits `[CONSENSUS-VETO]` so timeframe-resolution and single-voter safety drops are visible without inferring them from a `signal=NONE` quorum line.
- `CRegimeEngine` can temporarily reuse its most recent valid same-context snapshot on transient warmup / `CopyBuffer` / handle-init faults, and self-resets handles after repeated data faults.

### AI participation
- Runtime AI adapters can vote as strategies when enabled:
  - Neural Network adapter
  - Transformer adapter
  - Ensemble adapter
- Per-symbol strategy names are registered into orchestrator using `<symbol>::<strategy>` naming.
- Weight adaptation is synchronized back into manager strategy weights.

### Telemetry
- `[HEARTBEAT]`: global runtime counters.
- `[EXECUTION-MODE]`: startup execution mode (`SHADOW_ONLY` vs `LIVE_SEND`).
- `[ACCOUNT-CAPACITY]`: startup free-margin vs minimum-lot affordability per active symbol.
- `[TRADE-STATE]`: startup recovery of last EA trade/cooldown timing from history and open positions.
- `[CONSENSUS-QUORUM]`: per-evaluation weighted quorum scores and direction result.
- `[CONSENSUS-VETO]`: explicit post-quorum veto reason when timeframe resolution or single-voter safety nulls a candidate.
- `[CONSENSUS-SNAPSHOT]`: EA-interval aggregate consensus counters.
- `[CONSENSUS-DIAG]`: per-symbol consensus failure reasons.
- `[CONSENSUS-ROOT]`: dominant deadlock/rejection cause with interval percentages.
- `[CONSENSUS-STRATEGY]`: per-symbol strategy-level none-reason counters (Momentum/Unified ICT buckets).
- `[STRATEGY-REJECTS]`: heartbeat aggregate strategy-level reject counters.
- `[SIGNAL-REJECTED]`: validator rejection reason.
- `[SCAN-CANDIDATE]`: risk-approved candidate staged for end-of-cycle ranking.
- `[SCAN-DECISION]`: top-ranked candidate selected for shadow/live execution.
- `[ENTERPRISE-BLOCKED]`: approved signal suppressed by cooldown, capacity, or protection gates before risk/execution.
- `[RISK-CONTRACT]`: authoritative pre-trade risk rejection reason with preserved portfolio veto detail.
- `[AI-VOTE]`: adapter liveness and vote counts.
- `[SHADOW-TRADE]`: shadow execution events.
- `[TRADE-CONFIRMED]`: confirmed deal lifecycle events from `OnTradeTransaction`.
- `[EXECUTION-RECEIPT]`: broker execution receipt including requested/fill volume, retcode, and retry count.
- `[FILL-DIFF]`: partial-fill delta between requested and executed size.
- `[PIPELINE-THRESHOLD]`: confidence-threshold source (`REGIME_RANGE`, `REGIME_TREND_RELAX`, `REGIME_BREAKOUT_RELAX`, `REGIME_CHAOS`, `REGIME_ENGINE_WARMUP`) with effective values.
- `[REGIME-STATE]`: regime state, transient-fault reuse (`REUSE_LAST_VALID`), and repeated-fault handle self-heal (`HANDLE_RESET`).
- `[TrendEngine][READINESS-FAULT]`: mature-series indicator readiness fault with bounded indicator-set reinitialization.
- `[HEARTBEAT-FUNNEL]`: conversion funnel counters (`signals_generated` -> `shadow_or_live_sent`).
- `[CONVERSION-RATES]`: window-normalized conversion rates for throughput tracking.
- `[NO-SIGNAL-ALERT]`: dominant no-signal cause when no-signal ratio is elevated.

## Operating Workflow

### Preferred terminal mode
- Use persistent terminal sessions (normal or `/portable`).
- Avoid repeated `/config` relaunch loops for manual testing.

### Strategy Tester
1. Open MT5 persistent session.
2. `Ctrl+R` -> Strategy Tester.
3. Expert: `MultiStrategyAutonomousEA`.
4. Start symbol: `EURUSD.0`.
5. Period: `M1`.
6. Load inputs from `shadow_session.set`.
7. Keep `InpShadowMode=true` during burn-in.
8. Start and monitor logs.

## Known Issues and Mitigations

### WebView2 login crash
- Symptom: `msedgewebview2.exe - Application Error` during account login dialog.
- Mitigation: use persistent logged-in session (especially `/portable`) and avoid re-login loops during test cycles.

### Synthetic history gaps
- Symptom: history sync `Not found` on some synthetic indices.
- Mitigation: use stable tester start symbol (`EURUSD.0`) and include synthetics only where broker history is available.

## Active Config Files
- `shadow_session_open.ini`
- `shadow_session.ini`
- `shadow_session_mt5_tester.ini`
- `shadow_session_inputs.ini`
- `shadow_session.set`

## Code Quality & Safety
- **Memory Management**: AI adapters implement proper RAII with safe cleanup of transformer models
- **Error Handling**: Comprehensive input validation and bounds checking across all AI components
- **Constants**: Standardized configuration constants eliminate magic numbers throughout the codebase
- **Compilation**: Maintains 0 errors, 0 warnings with continuous integration verification

## Institutional Remediation Status (2026-02-23)
- **Deterministic cadence control**: Signal evaluation is now second-gated to prevent duplicate decision runs when `OnTick` and `OnTimer` overlap.
- **Portfolio hard veto on missing SL**: Any open position without a protective stop is treated as a risk-governance breach that blocks new entries.
- **Mark-to-market daily budgeting**: Daily risk usage now tracks max of entry budget, equity drawdown from daily baseline, and open portfolio stop risk.
- **Execution resilience**: Fill mode is configurable (IOC default), transient broker retcodes are retried with bounded backoff, and protective SL/TP updates support emergency bypass.
- **AI governance lock-down**: NN online training, pseudo-labeling, and weight mutation are disabled by default and cannot bypass unified risk controls.
- **Unprotected position remediation**: Runtime now attempts deterministic SL restoration for EA-owned unprotected positions, with bounded retries and forced-close fallback after configured attempts.
- **Operator risk clarity**: Heartbeat now emits `[RISK-BUDGET]` split telemetry (`entry`, `mtm`, `open_exposure`, `effective`) to distinguish daily budget consumption vs exposure cap pressure.
- **Symbol fairness controls**: Per-cycle symbol evaluation now rotates start index to neutralize deterministic first-symbol bias under one-trade-per-cycle behavior.
- **External-capacity diagnostics**: `[CAPACITY-EXTERNAL]` explicitly reports when non-EA positions consume per-symbol capacity.
- **Execution retry hardening**: `LOCKED`/`FROZEN` retcodes now use single bounded retry instead of full exponential retry path.

## Institutional Throughput/Integrity Update (2026-02-24)
- **Intrabar deadlock conversion**: `EnterpriseStrategyManager` now computes intrabar effective quorum from actual live contributors in the current cycle (`<=1 => quorum=1`, else bounded by configured intrabar floor).
- **Deadlock attribution visibility**: consensus diagnostics now include `[CONSENSUS-ROOT]`, `[CONSENSUS-STRATEGY]`, and snapshot APIs consumed by runtime `[CONSENSUS-SNAPSHOT]`/`[NO-SIGNAL-ALERT]`.
- **ADX fail-safe hardening**: `TrendEngine` now validates ADX/DI domains, neutral-degrades on copy/value faults, and performs bounded ADX-handle self-heal after consecutive failures.
- **Threshold governance**: pipeline weak-regime intrabar threshold uplift is capped (`InpPipelineIntrabarConfidenceCap`) and logged with source tag via `[PIPELINE-THRESHOLD]`.
- **Threshold decoupling**: non-AI strategy pipeline/validator floors are now configured separately from `InpAIConfidenceThreshold`, preventing AI policy from suppressing curated human strategy flow.
- **Throughput observability**: runtime heartbeat now emits funnel counters/rates (`[HEARTBEAT-FUNNEL]`, `[CONVERSION-RATES]`) to quantify conversion recovery without bypassing validator/risk gates.

## Runtime No-Trade Recovery Update (2026-03-07)
- **Contributor-aware quorum**: silent but eligible live voters no longer keep intrabar quorum artificially at `2` when only one live contributor is actually signaling.
- **Operator mode clarity**: startup now emits `[EXECUTION-MODE]` so shadow sessions are obvious in the log before trade debugging begins.
- **Analytics bootstrap**: `PerformanceAnalytics` is now initialized explicitly before `CUnifiedRiskManager` consumes it.

## Execution Safety Hardening Update (2026-03-07)
- **Synchronous market sends**: `CTradeManager` no longer defaults to async execution, removing the most dangerous mismatch between broker confirmation and EA-side success accounting.
- **Repriced market protection**: market orders now resolve current execution price at send time and recalculate SL/TP from that price on each retry attempt.
- **Sizing consistency**: `PositionSizer` now uses tick-size/tick-value risk math and `min(balance,equity)` denominator alignment with the risk gate.
- **Restart-safe lifecycle reconstruction**: `AdvancedPositionManager` now reconstructs partial-close and breakeven state for already-open positions from position identifiers and history-derived entry volume.
- **Close-driven analytics**: confirmed close deals now update `PerformanceAnalytics` from `OnTradeTransaction`, and startup rejects unsupported non-hedging account models.

## Timeframe + AI Feedback Update (2026-03-16)
- **Timeframe-consistent consensus**: manager consensus now applies `TimeframeConsistency` to resolve conflicts across mixed strategy timeframes.
- **Correct OnNewBar dispatch**: strategy `OnNewBar` now receives its registered timeframe instead of the manager base timeframe.
- **AI feedback wiring**: AI prediction/outcome tracking now records live-trade predictions and closes with position-mapped outcomes.

## Quorum Admission Alignment + Smoke Controls Update (2026-03-24)
- **Consensus admission alignment**: `EnterpriseStrategyManager` now admits votes using the pipeline's last effective confidence floor, eliminating the mismatch where a signal could pass `[PIPELINE-THRESHOLD]` and still be excluded from quorum.
- **Smoke-test intrabar controls**: added opt-in intrabar eligibility inputs for `Fibonacci` and `Support/Resistance` so productive mean-reversion contributors can be widened for smoke tests without changing production defaults.

## Startup State Recovery + Capacity Diagnostics + Regime Fault Resilience Update (2026-03-24)
- **Restart-safe cooldown state**: startup now reconstructs `g_lastTradeTime` from EA-owned deal history and currently open EA positions, so inherited positions no longer leave the runtime in a false `Last trade: Never` posture.
- **Low-balance visibility**: startup now emits `[ACCOUNT-CAPACITY]` diagnostics showing whether free margin can support the symbol minimum lot, making underfunded smoke environments obvious before forced execution debugging.
- **Transient regime fault resilience**: `CRegimeEngine` can reuse a recent valid snapshot on warmup / buffer-copy / handle-init faults and performs bounded handle reset after repeated data faults, reducing avoidable throughput collapse without bypassing the pipeline.

## Entry Gate Decoupling Update (2026-03-24)
- **Scan-through-cooldown behavior**: cooldown and other entry blocks no longer short-circuit the symbol evaluation loop, so `[CONSENSUS-QUORUM]`, `[SIGNAL-VALIDATED]`, and heartbeat funnel telemetry continue after a live fill.
- **Entry-only suppression**: approved signals that cannot proceed because of cooldown, portfolio caps, unprotected positions, or per-symbol capacity now emit explicit `[ENTERPRISE-BLOCKED]` diagnostics instead of disappearing from the runtime path.

## Efficiency + Conviction Upgrade (2026-03-25)
- **Shared pipeline evidence**: `UnifiedSignalPipeline` now caches structural engine state per symbol/timeframe/bar and emits a reusable evidence snapshot (`readiness`, `context`, `cost`, effective confidence floor, soft-threshold pass) instead of recomputing the same context for every strategy vote.
- **Smarter consensus**: `EnterpriseStrategyManager` now computes directional conviction from adjusted strategy weight (`base weight x role multiplier x rolling healthScore`) and requires both weighted conviction and minimum ready-live-weight participation before a side wins.
- **Conflict handling without false neutralization**: timeframe resolution still owns mixed-timeframe conflict handling, but the old hot-path hedging neutralization no longer wipes out otherwise valid directional consensus before quorum can act.
- **Context-aware validator**: `AdvancedSignalValidator` now grades signals with consensus/path evidence (`conviction`, `readiness`, `context`, `cost`, `diversity`, `freshness`) and allows bounded soft passes near the profile floor when the broader setup is strong.
- **Cycle-level candidate ranking**: the EA no longer fires the first acceptable symbol; it stages all risk-approved opportunities, logs them as `[SCAN-CANDIDATE]`, and executes only the highest-ranked candidate via `[SCAN-DECISION]`.
- **Execution accounting fidelity**: `TradeManager` now emits `[EXECUTION-RECEIPT]`, partial fills emit `[FILL-DIFF]`, and `UnifiedRiskManager` registers consumed daily entry risk against actual fill ratio.
- **Lower telemetry overhead**: `SignalDiagnostics` now batches file flushes instead of forcing an on-disk flush on every write.

## Weighted Quorum + Live Strategy Promotion Update (2026-03-16)
- **Historical note**: this batch introduced weighted confidence quorum; the current runtime extends it further with readiness/health-based conviction weighting from the 2026-03-25 efficiency upgrade.
- **All retained strategies vote live**: every enabled retained strategy is registered as a live primary voter (no feature/shadow suppression).
- **Weighted quorum**: consensus now passes when normalized weighted confidence crosses `InpQuorumThreshold` and `InpMinLiveVoters` is satisfied; per-evaluation scores are emitted as `[CONSENSUS-QUORUM]`.
- **Operator tuning**: per-strategy weights are configurable via inputs (`InpWeight*`) without code changes.

## Institutional Strategy Betterment Update (2026-02-24)
- **Note:** This batch is historical; current default voting behavior is defined by the 2026-03-16 weighted quorum + live strategy promotion update above.
- **Soft quarantine strategy governance**: all retained strategy modules stay loaded for diagnostics, but default live-voting authority is constrained to `Momentum`, `Trend`, and `Unified ICT`; weaker legacy modules are feature/shadow by default.
- **Role/cluster metadata**: strategy registration now carries `PRIMARY_ALPHA`, `CONTEXT_FEATURE`, `SHADOW_RESEARCH` roles and cluster tags (`TREND_CLUSTER`, `MEAN_REVERSION_CLUSTER`, `STRUCTURE_CLUSTER`).
- **Regime + cost gate**: `UnifiedSignalPipeline` now runs deterministic regime/microstructure viability checks (`[REGIME-STATE]`, `[COST-GATE]`, `[ENTRY-VETO]`) before validator/risk.
- **Momentum anti-spam refactor**: momentum now requires state alignment + compression-to-break trigger, reducing crossover-only churn.
- **Unified ICT event tuple**: live signal path is constrained by falsifiable tuple checks (structure break + displacement + mitigation/retest) with bounded quality scoring and range-only counter-trend allowance.
- **Cluster-aware risk governance**: risk request now includes role/cluster/contributor context; risk gate enforces same-symbol opposing-cluster mutex and per-cluster position/risk caps (`[RISK-CLUSTER]`, `[RISK-MUTEX-BLOCK]`).
- **Role/cluster telemetry**: heartbeat now reports `[ROLE-CLUSTER]` counters and manager diagnostics report `[CONSENSUS-ROLE]` / `[CONSENSUS-CLUSTER]`.

## Documentation Index
- Full structure specification: `SYSTEM_STRUCTURE.md`
- Runtime decision path: `RUNTIME_DECISION_GRAPH.md`
- Lifecycle trace: `SYSTEM_AUDIT_TRACE.md`
- Forward maintenance protocol: `MAINTENANCE_PROTOCOL.md`
- Agent workflow contract: `AGENTS.md`
- Changelog: `changelogs.md`
- Audit scratchpad: `AUDIT_REPORT.md`

## Documentation Policy
- Any runtime behavior change must update:
  - `RUNTIME_DECISION_GRAPH.md` (decision path changes)
  - `SYSTEM_STRUCTURE.md` (component/ownership changes)
  - `changelogs.md` (dated batch)
  - `README.md` (operational impact)
