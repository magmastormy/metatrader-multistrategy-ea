# metatrader-multistrategy-ea

## Document Metadata
- Last Updated: 2026-03-07
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
- Intrabar quorum supports contributor-aware dynamic mode (`InpIntrabarDynamicQuorumEnabled`) using actual live contributors in the current cycle, with configurable single-voter confidence floor (`InpIntrabarSingleVoterMinConfidence`).
- Curated core strategies now have explicit intrabar eligibility controls (`InpIntrabarEligibilityMomentum`, `InpIntrabarEligibilityUnifiedICT`).
- Non-AI strategy throughput is controlled by dedicated pipeline and validator confidence inputs (`InpPipelineMinConfidence`, `InpValidatorNewBarMinConfidence`, `InpValidatorIntrabarMinConfidence`) instead of the AI threshold.

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
- `[CONSENSUS-SNAPSHOT]`: EA-interval aggregate consensus counters.
- `[CONSENSUS-DIAG]`: per-symbol consensus failure reasons.
- `[CONSENSUS-ROOT]`: dominant deadlock/rejection cause with interval percentages.
- `[CONSENSUS-STRATEGY]`: per-symbol strategy-level none-reason counters (Momentum/Unified ICT buckets).
- `[STRATEGY-REJECTS]`: heartbeat aggregate strategy-level reject counters.
- `[SIGNAL-REJECTED]`: validator rejection reason.
- `[AI-VOTE]`: adapter liveness and vote counts.
- `[SHADOW-TRADE]`: shadow execution events.
- `[TRADE-CONFIRMED]`: confirmed deal lifecycle events from `OnTradeTransaction`.
- `[PIPELINE-THRESHOLD]`: confidence-threshold source (`REGIME_RANGE`, `REGIME_TREND_RELAX`, `REGIME_BREAKOUT_RELAX`, `REGIME_CHAOS`, `REGIME_ENGINE_WARMUP`) with effective values.
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

## Institutional Strategy Betterment Update (2026-02-24)
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
