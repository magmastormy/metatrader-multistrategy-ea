# Runtime Decision Graph

## Document Metadata
- Last Updated: 2026-02-23
- Scope: Runtime signal-to-execution flow
- Source: `MultiStrategyAutonomousEA.mq5`

## Purpose
Defines the authoritative runtime decision path and ownership boundaries between signal generation, validation, risk veto, execution, and post-trade feedback.

## Ownership Map
- Orchestration: `MultiStrategyAutonomousEA.mq5`
- Consensus: `CEnterpriseStrategyManager`
- Filtering: `CUnifiedSignalPipeline`
- AI adaptation/weights: `CAIStrategyOrchestrator`
- Risk veto: `CUnifiedRiskManager`
- Execution: `CTradeManager`
- Position lifecycle: `CAdvancedPositionManager`
- Indicator cache lifecycle: `CIndicatorManager`

## End-to-End Flow

```mermaid
flowchart TD
  A[OnInit] --> B[Initialize trade, risk, managers]
  B --> C[Register core and AI strategy adapters]
  C --> D[OnTick or OnTimer ProcessTradingLogic]

  D --> D1{Terminal connected?}
  D1 -->|No| D2[Skip evaluation, wait reconnect]
  D1 -->|Yes| D3[Remediate unprotected positions]
  D3 --> E{Signal eval second already used?}
  E -->|Yes| E2[Skip duplicate evaluation]
  E -->|No| E3[Continue]
  E3 --> E3A[Rotate symbol evaluation start index]
  E3A --> E4{New bar?}
  E4 -->|Yes| F[Evaluate NEW_BAR mode]
  E4 -->|No| G{Hybrid intrabar eligible?}
  G -->|Yes| H[Evaluate INTRABAR mode]
  G -->|No| I[Skip symbol]

  F --> J[Manager consensus + confluence]
  H --> J
  J --> K{Signal NONE?}
  K -->|Yes| L[Increment no-signal telemetry]
  K -->|No| M[Advanced signal validation]

  M --> N{Validator pass?}
  N -->|No| O[Log SIGNAL-REJECTED]
  N -->|Yes| P[Build ATR SL/TP + risk request]

  P --> Q[UnifiedRisk pre-size validation]
  Q --> R{Pass?}
  R -->|No| S[Risk rejection]
  R -->|Yes| T[Position sizing]

  T --> U[UnifiedRisk post-size validation]
  U --> V{Pass?}
  V -->|No| S
  V -->|Yes| W{Shadow mode?}

  W -->|Yes| X[Log SHADOW-TRADE]
  W -->|No| Y[TradeManager OpenPosition]

  Y --> Z{Execution success?}
  Z -->|No| AA[Trade error path]
  Z -->|Yes| AB[Register executed risk + cooldown]

  AB --> AC[OnTradeTransaction feedback]
  AC --> AD[Manager and orchestrator performance updates]
  AC --> AE[NN attribution mapping and labeling]

  D --> AF[Position manager lifecycle actions]
  D --> AG[Periodic HEARTBEAT, RISK-BUDGET, CONSENSUS-DIAG]
```

## Intrabar Policy
- New-bar and intrabar paths are explicit evaluation modes.
- Intrabar eligibility respects symbol scope and cadence interval.
- Intrabar/new-bar consensus behavior is manager-controlled.
- Intrabar quorum floor is explicitly configurable and bounded by active strategy count.

## Risk Hardening
- Daily budget gate uses effective daily risk:
  - max(executed entry risk, mark-to-market equity loss from daily baseline, current open portfolio stop risk).
- Any open position without stop-loss protection is treated as a hard veto state.
- Runtime performs deterministic unprotected-position remediation (restore SL, then force-close EA-owned positions after bounded failed attempts).
- Risk validation remains two-phase (`pre-size`, `post-size`) through unified authority.
- Operator telemetry now splits daily budget components: `entry`, `mtm`, `open_exposure`, `effective`.

## Execution Hardening
- Fill policy is configurable via EA input (`IOC` default).
- Transient retcodes use bounded retry with backoff.
- `LOCKED`/`FROZEN` retcodes use single bounded retry to avoid prolonged retry loops.
- Protective stop modifications are throttled but allow emergency bypass for missing/tightening protection.
- Symbol scan order rotates each cycle to reduce first-symbol concentration when only one trade is allowed per cycle.

## Diagnostics
- Consensus reason counters emitted as `[CONSENSUS-DIAG]`:
  - `raw_none`
  - `filtered_out`
  - `quorum_failed`
  - `intrabar_not_eligible`
- Risk budget decomposition: `[RISK-BUDGET]`
- Unprotected remediation lifecycle: `[RISK-UNPROTECTED]`
- External position capacity blocks: `[CAPACITY-EXTERNAL]`

## AI Runtime Evidence
- `[AI-VOTE][Transformer]`
- `[AI-VOTE][Ensemble]`
- NN health/labeling logs where enabled

## Invariants
- No direct ad-hoc order sends in decision path.
- Unified risk gate must approve before execution.
- Shadow mode executes full decision stack but does not send orders.
- `CIndicatorManager::DestroyInstance()` must run on deinit.

## Fast Debug Read Order
1. `[HEARTBEAT]`
2. `[RISK-BUDGET]`
3. `[CONSENSUS-DIAG]`
4. `[SIGNAL-REJECTED]`
5. `[RISK-UNPROTECTED]` / `[CAPACITY-EXTERNAL]`
6. `[AI-VOTE]`
7. `[SHADOW-TRADE]` or `[TRADE-SUCCESS]/[TRADE-ERROR]`
