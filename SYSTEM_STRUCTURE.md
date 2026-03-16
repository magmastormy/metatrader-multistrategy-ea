# SYSTEM_STRUCTURE.md

## Document Metadata
- Last Updated: 2026-03-16
- Scope: Full structural description of runtime system
- Source of Truth: Current repository implementation

## 1. System Goal
Provide autonomous, multi-strategy trade decisions with clear ownership boundaries:
- signal generation and consensus
- pre-trade risk veto
- execution
- post-trade feedback and adaptation

The system prioritizes deterministic control flow, explicit diagnostics, and shadow-first rollout capability.

## 2. Top-Level Runtime Topology

### 2.1 Entrypoint and orchestration
- File: `MultiStrategyAutonomousEA.mq5`
- Responsibilities:
  - initialize all runtime subsystems
  - maintain cadence loops (new-bar/intrabar)
  - dispatch per-symbol evaluations
  - own the non-AI confidence policy inputs for pipeline and validator stages
  - coordinate validator/risk/execution path
  - handle runtime telemetry and deinitialization

### 2.2 Per-symbol strategy domain
- Class: `CEnterpriseStrategyManager`
- One manager per managed symbol.
- Responsibilities:
  - hold registered strategies (core + AI adapters)
  - execute strategy voting and confidence aggregation
  - resolve cross-timeframe vote conflicts via `CTimeframeConsistency`
  - dispatch `OnNewBar` to each strategy using its registered timeframe
  - apply quorum rules by evaluation mode (strict new-bar, contributor-aware dynamic intrabar when enabled)
  - enforce single-voter intrabar confidence floor
  - expose per-cycle funnel snapshots and interval consensus diagnostics snapshots
  - emit consensus diagnostics
  - retain last-contributor context for attribution

### 2.3 Pipeline domain
- Class: `CUnifiedSignalPipeline`
- Responsibilities:
  - apply trend/volatility/liquidity/structure/confidence filters
  - apply deterministic regime + cost viability pre-gate via `CRegimeEngine`
  - apply bounded weak-regime intrabar confidence threshold uplift (`min(base+cap, base*multiplier)`) using `CRegimeEngine` snapshot state as the authority
  - emit threshold-source telemetry (`[PIPELINE-THRESHOLD]`)
  - emit regime/cost veto telemetry (`[REGIME-STATE]`, `[COST-GATE]`, `[ENTRY-VETO]`)
  - normalize decision hygiene before final consensus acceptance

### 2.4 AI adaptation domain
- Class: `CAIStrategyOrchestrator`
- Responsibilities:
  - register qualified strategy identities (`symbol::name`)
  - maintain performance and weight state
  - adapt weights and feed updates back to managers

### 2.5 Risk domain
- Class: `CUnifiedRiskManager`
- Responsibilities:
  - single pre-trade veto authority
  - two-phase validation (`pre-size`, `post-size`)
  - daily/portfolio risk budgeting and drawdown controls
  - mark-to-market aware daily budget enforcement
  - hard veto on unprotected (no-SL) open positions
  - enforce cluster-aware governance (same-symbol opposing-cluster mutex + per-cluster caps) through `CRiskValidationGate`
  - split budget telemetry (`entry`, `mtm`, `open_exposure`, `effective`) for operator clarity
  - expose unprotected-position state for runtime remediation workflows
  - executed-risk registration after successful synchronous sends

### 2.6 Execution domain
- Class: `CTradeManager`
- Responsibilities:
  - convert approved intent into actual order send
  - run synchronous market execution by default
  - enforce execution-level safety checks
  - configurable broker fill policy (IOC/FOK/RETURN)
  - bounded retries for transient broker retcodes
  - single bounded retry behavior for `LOCKED` / `FROZEN` retcodes
  - reprice market orders at submit time and rebuild protective SL/TP from the current market price
  - emergency-aware protective modification flow
  - expose ticket/result status for post-send handling

### 2.7 Position lifecycle domain
- Class: `CAdvancedPositionManager`
- Responsibilities:
  - trailing/BE/partial-close lifecycle handling
  - reconstruct lifecycle milestones for already-open positions after restart
  - managed by EA magic scope

### 2.8 Shared indicator domain
- Class: `CIndicatorManager`
- Responsibilities:
  - indicator handle cache and shared access
  - periodic unused release
  - explicit singleton teardown on deinit

## 3. Managed Strategies

### 3.1 Core retained set
- Momentum
- Trend
- Fibonacci
- Elliott Wave
- Support/Resistance
- Unified ICT
- Candlestick

Retired standalone strategy families (RSI, Mean Reversion, Swing, Volatility, MACD, Bollinger, Ichimoku, Harmonic, legacy SMC wrapper) are removed from active runtime inventory.
The legacy strategy configuration module (`Config/StrategyConfig.mqh`) has also been removed to avoid stale retired-strategy references.

### 3.2 AI strategy adapters
- Neural Network adapter (`CAIStrategyAdapter`)
- Transformer adapter (`CTransformerAIStrategyAdapter`)
- Ensemble adapter (`CEnsembleAIStrategyAdapter`)

**Memory Safety**: All AI adapters implement RAII patterns with proper cleanup of transformer models and comprehensive error handling. Constants are used throughout to eliminate magic numbers.

### 3.3 Curated runtime profile
Curated mode can restrict runtime active set to a smaller operational profile while preserving full retained implementation in code.

### 3.4 Institutional governance roles
- Strategy registration now includes explicit governance metadata:
  - role: `PRIMARY_ALPHA`, `CONTEXT_FEATURE`, `SHADOW_RESEARCH`
  - cluster: `TREND_CLUSTER`, `MEAN_REVERSION_CLUSTER`, `STRUCTURE_CLUSTER`, `NONE`
- Default soft-quarantine policy:
  - live primary voters: `Momentum`, `Trend`, `Unified ICT`
  - feature/shadow contributors (loaded, diagnostics-on, live vote off by default): `Candlestick`, `Fibonacci`, `Elliott Wave`, `Support/Resistance`
- Manager-level controls are exposed by strategy name for role, cluster, live-vote eligibility, and shadow mode.

## 4. Decision Pipeline (Signal to Execution)

### 4.1 Cadence selection
- New-bar path: conservative scan cadence.
- Intrabar path: timer-driven scans when enabled.
- Symbol evaluation start index rotates each cycle to reduce deterministic first-symbol concentration.

### 4.2 Consensus
- Manager computes strategy votes and confidence.
- Mixed-timeframe conflicts are resolved with `CTimeframeConsistency` before final consensus acceptance.
- Intrabar effective quorum is contributor-aware:
  - actual live contributors this cycle `<=1`: effective quorum `1`
  - otherwise: `min(intrabar_min_quorum, actual_live_contributors_this_cycle)`
- Consensus may fail by:
  - raw no-vote
  - quorum miss
  - intrabar ineligibility
  - filter rejection

### 4.3 Validation
- `CAdvancedSignalValidator` applies profile-dependent gating.
- Rejected signals emit reasoned logs.
- Cost viability parameters are explicit (`spread/ATR`, spread-shock cooldown).

### 4.4 Risk gate
- Pre-size validation to accept/reject candidate conditions.
- Position sizing computes lot.
- Post-size validation with actual lot before execution.
- Unprotected-position remediation runs before new-entry scans; unresolved states pause new entries until resolved.
- Trade requests carry role/cluster/contributor context for cluster-aware risk governance.

### 4.5 Execution branch
- Shadow mode: logs virtual trade, no send.
- Live mode: send through `CTradeManager`.
- Startup emits `[EXECUTION-MODE]` so shadow/live posture is explicit before the first scan.
- Startup rejects unsupported non-hedging account models before runtime ownership becomes ambiguous.
- Live comment tagging carries compact cluster code (`K:T/R/S/N`) for deterministic open-position cluster attribution.

### 4.6 Post-trade feedback
- Successful trades register executed risk usage.
- Close transactions feed manager/orchestrator adaptation and `PerformanceAnalytics`.
- NN attribution maps prediction IDs through close labeling.
- AI performance feedback records prediction/outcome pairs using position-mapped prediction times.

### 4.7 Deterministic event separation
- Tick and timer handlers share a second-level signal-evaluation gate.
- This prevents duplicate strategy consensus passes in the same wall-clock second.
- Connectivity gating blocks signal evaluation while terminal connection is down.

## 5. Data and Control Boundaries

### 5.1 What can veto a trade
- Validator failure.
- Unified risk rejection.
- Execution failure after approval.

### 5.2 What cannot bypass risk
- Strategy confidence alone does not bypass unified risk gate.
- AI strategy adapter votes do not bypass validator or risk stages.

### 5.3 Execution centralization
- Runtime decision path executes through `CTradeManager`.

## 6. Runtime Modes

### 6.1 Shadow mode
- Full stack decisioning, no live order send.
- Used for burn-in and diagnostics.

### 6.2 Live mode
- Full stack decisioning with real execution.
- Requires extra monitoring window post-activation.

## 7. Observability Model

### 7.1 Key log families
- Decision heartbeat: `[HEARTBEAT]`
- Conversion funnel: `[HEARTBEAT-FUNNEL]`, `[CONVERSION-RATES]`
- Risk budget split: `[RISK-BUDGET]`
- Unprotected remediation: `[RISK-UNPROTECTED]`
- External capacity denial: `[CAPACITY-EXTERNAL]`
- Consensus diagnostics: `[CONSENSUS-DIAG]`, `[CONSENSUS-ROOT]`, `[CONSENSUS-SNAPSHOT]`, `[CONSENSUS-STRATEGY]`
- Governance diagnostics: `[CONSENSUS-ROLE]`, `[CONSENSUS-CLUSTER]`, `[ROLE-CLUSTER]`
- Strategy reject attribution: `[STRATEGY-REJECTS]`
- Signal rejection reasons: `[SIGNAL-REJECTED]`
- Threshold source tracing: `[PIPELINE-THRESHOLD]`
- Regime/cost viability tracing: `[REGIME-STATE]`, `[COST-GATE]`, `[ENTRY-VETO]`
- No-signal deadlock alerting: `[NO-SIGNAL-ALERT]`
- Cluster risk governance tracing: `[RISK-CLUSTER]`, `[RISK-MUTEX-BLOCK]`
- AI liveness: `[AI-VOTE]`
- confirmed deals: `[TRADE-CONFIRMED]`
- Shadow actions: `[SHADOW-TRADE]`
- Execution outcomes: `[TRADE-SUCCESS]`, `[TRADE-ERROR]`

### 7.2 Primary operational KPIs
- no-signal ratio
- validator rejection ratio
- risk rejection ratio
- generated-to-send conversion rate
- quorum pass rate
- validated-to-risk-approved conversion rate
- AI vote activity per symbol per adapter
- shadow/live trade throughput

## 8. Configuration Surface

### 8.1 Runtime controls
- Symbol basket and cadence controls
- Strategy enable flags
- AI feature toggles
- risk limits and drawdown controls
- shadow mode toggle

### 8.2 Tester profiles
- `shadow_session_open.ini`
- `shadow_session.ini`
- `shadow_session_mt5_tester.ini`
- `shadow_session_inputs.ini`
- `shadow_session.set`

## 9. Lifecycle Safety

### 9.1 Init safety
- component initialization order ensures execution/risk dependencies are ready before runtime.

### 9.2 Deinit safety
- dynamic allocations released
- singleton indicator manager explicitly destroyed

### 9.3 Build artifact hygiene
- compile script is expected to clean generated compile `.log/.txt` artifacts after run unless explicitly preserved.

## 10. Future Change Rules (Structure-Level)
Any structural change must update all of:
- `SYSTEM_STRUCTURE.md`
- `RUNTIME_DECISION_GRAPH.md`
- `SYSTEM_AUDIT_TRACE.md`
- `README.md`
- `changelogs.md`
