# Runtime Decision Graph

## Document Metadata
- Last Updated: 2026-02-22
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

  D --> E{New bar?}
  E -->|Yes| F[Evaluate NEW_BAR mode]
  E -->|No| G{Hybrid intrabar eligible?}
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
  D --> AG[Periodic HEARTBEAT and CONSENSUS-DIAG]
```

## Intrabar Policy
- New-bar and intrabar paths are explicit evaluation modes.
- Intrabar eligibility respects symbol scope and cadence interval.
- Intrabar/new-bar consensus behavior is manager-controlled.

## Diagnostics
- Consensus reason counters emitted as `[CONSENSUS-DIAG]`:
  - `raw_none`
  - `filtered_out`
  - `quorum_failed`
  - `intrabar_not_eligible`

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
2. `[CONSENSUS-DIAG]`
3. `[SIGNAL-REJECTED]`
4. `[AI-VOTE]`
5. `[SHADOW-TRADE]` or `[TRADE-SUCCESS]/[TRADE-ERROR]`
