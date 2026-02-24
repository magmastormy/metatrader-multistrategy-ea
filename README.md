# metatrader-multistrategy-ea

## Document Metadata
- Last Updated: 2026-02-23
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

### AI participation
- Runtime AI adapters can vote as strategies when enabled:
  - Neural Network adapter
  - Transformer adapter
  - Ensemble adapter
- Per-symbol strategy names are registered into orchestrator using `<symbol>::<strategy>` naming.
- Weight adaptation is synchronized back into manager strategy weights.

### Telemetry
- `[HEARTBEAT]`: global runtime counters.
- `[CONSENSUS-DIAG]`: per-symbol consensus failure reasons.
- `[SIGNAL-REJECTED]`: validator rejection reason.
- `[AI-VOTE]`: adapter liveness and vote counts.
- `[SHADOW-TRADE]`: shadow execution events.

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
