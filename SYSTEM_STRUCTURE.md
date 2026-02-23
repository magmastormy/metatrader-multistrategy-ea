# SYSTEM_STRUCTURE.md

## Document Metadata
- Last Updated: 2026-02-22
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
  - coordinate validator/risk/execution path
  - handle runtime telemetry and deinitialization

### 2.2 Per-symbol strategy domain
- Class: `CEnterpriseStrategyManager`
- One manager per managed symbol.
- Responsibilities:
  - hold registered strategies (core + AI adapters)
  - execute strategy voting and confidence aggregation
  - apply quorum rules by evaluation mode
  - emit consensus diagnostics
  - retain last-contributor context for attribution

### 2.3 Pipeline domain
- Class: `CUnifiedSignalPipeline`
- Responsibilities:
  - apply trend/volatility/liquidity/structure/confidence filters
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
  - executed-risk registration after successful sends

### 2.6 Execution domain
- Class: `CTradeManager`
- Responsibilities:
  - convert approved intent into actual order send
  - enforce execution-level safety checks
  - expose ticket/result status for post-send handling

### 2.7 Position lifecycle domain
- Class: `CAdvancedPositionManager`
- Responsibilities:
  - trailing/BE/partial-close lifecycle handling
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
- Unified ICT/SMC
- Candlestick

### 3.2 AI strategy adapters
- Neural Network adapter (`CAIStrategyAdapter`)
- Transformer adapter (`CTransformerAIStrategyAdapter`)
- Ensemble adapter (`CEnsembleAIStrategyAdapter`)

### 3.3 Curated runtime profile
Curated mode can restrict runtime active set to a smaller operational profile while preserving full retained implementation in code.

## 4. Decision Pipeline (Signal to Execution)

### 4.1 Cadence selection
- New-bar path: conservative scan cadence.
- Intrabar path: timer-driven scans when enabled.

### 4.2 Consensus
- Manager computes strategy votes and confidence.
- Consensus may fail by:
  - raw no-vote
  - quorum miss
  - intrabar ineligibility
  - filter rejection

### 4.3 Validation
- `CAdvancedSignalValidator` applies profile-dependent gating.
- Rejected signals emit reasoned logs.

### 4.4 Risk gate
- Pre-size validation to accept/reject candidate conditions.
- Position sizing computes lot.
- Post-size validation with actual lot before execution.

### 4.5 Execution branch
- Shadow mode: logs virtual trade, no send.
- Live mode: send through `CTradeManager`.

### 4.6 Post-trade feedback
- Successful trades register executed risk usage.
- Close transactions feed manager/orchestrator adaptation.
- NN attribution maps prediction IDs through close labeling.

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
- Consensus diagnostics: `[CONSENSUS-DIAG]`
- Signal rejection reasons: `[SIGNAL-REJECTED]`
- AI liveness: `[AI-VOTE]`
- Shadow actions: `[SHADOW-TRADE]`
- Execution outcomes: `[TRADE-SUCCESS]`, `[TRADE-ERROR]`

### 7.2 Primary operational KPIs
- no-signal ratio
- validator rejection ratio
- risk rejection ratio
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
