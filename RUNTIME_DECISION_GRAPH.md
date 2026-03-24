# Runtime Decision Graph

## Document Metadata
- Last Updated: 2026-03-24
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

  F --> J[Manager consensus + confluence + timeframe consistency]
  H --> J
  J --> J0[Strategy role/cluster governance applied]
  J0 --> J1[Pipeline regime + cost viability gate]
  J1 --> K{Signal NONE?}
  K -->|Yes| L[Increment no-signal telemetry]
  K -->|No| M[Advanced signal validation]

  M --> N{Validator pass?}
  N -->|No| O[Log SIGNAL-REJECTED]
  N -->|Yes| P[Build ATR SL/TP + risk request with role/cluster/contributors]

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

- Manager consensus resolves mixed-timeframe conflicts via `TimeframeConsistency` before final vote selection.

## Intrabar Policy
- New-bar and intrabar paths are explicit evaluation modes.
- Intrabar eligibility respects symbol scope and cadence interval.
- Intrabar/new-bar consensus behavior is manager-controlled.
- Vote admission into timeframe consistency and quorum uses the pipeline's effective confidence floor for that evaluation, not just the static base pipeline minimum.
- Quorum uses normalized weighted confidence pooling (intrabar eligibility defines the active live-voter pool for intrabar scans):
  - per-direction score = `sum(weight_i * confidence_i)` for agreeing live voters (directional signal, confidence >= pipeline min)
  - normalized score = `score / total_weight(active_live_voters)` (not just agreeing ones)
  - direction passes quorum if `normalized_score >= InpQuorumThreshold` **and** agreeing voters `>= InpMinLiveVoters`
- Single-voter intrabar output still requires configured minimum confidence.
- Pipeline and validator profiles (confidence + confluence + quality) are configured separately from AI thresholds so non-AI strategies are not gated by AI policy.

## Strategy Governance Policy
- Manager-level strategy metadata controls live-vote authority:
  - role: `PRIMARY_ALPHA`, `CONTEXT_FEATURE`, `SHADOW_RESEARCH`
  - cluster: `TREND_CLUSTER`, `MEAN_REVERSION_CLUSTER`, `STRUCTURE_CLUSTER`, `NONE`
- Default policy:
  - all enabled retained strategies are registered as `PRIMARY_ALPHA` and vote live
  - per-strategy inputs gate registration (disabled strategies are not registered into the pool)
- Intrabar participation remains explicit: Momentum and Unified ICT are the default intrabar voters, while Fibonacci and Support/Resistance can be opted in for smoke tests via dedicated inputs.

## Regime/Cost Pre-Gate
- `CRegimeEngine` runs before validator and can veto entries on:
  - spread-shock cooldown
  - spread/ATR ratio breach
  - late-entry z-score outlier
- Pipeline threshold adaptation now also consumes the regime snapshot, so confidence uplift/relaxation is aligned with the same market-state authority that drives the cost gate.
- Gate telemetry:
  - `[REGIME-STATE]`
  - `[COST-GATE]`
  - `[ENTRY-VETO]`
  - `[PIPELINE-THRESHOLD]`

## Risk Hardening
- Daily budget gate uses effective daily risk:
  - max(executed entry risk, mark-to-market equity loss from daily baseline, current open portfolio stop risk).
- Any open position without stop-loss protection is treated as a hard veto state.
- Runtime performs deterministic unprotected-position remediation (restore SL, then force-close EA-owned positions after bounded failed attempts).
- Risk validation remains two-phase (`pre-size`, `post-size`) through unified authority.
- Operator telemetry now splits daily budget components: `entry`, `mtm`, `open_exposure`, `effective`.
- Risk gate now enforces cluster governance:
  - same-symbol opposing-cluster mutex
  - max concurrent positions per cluster
  - max projected cluster risk cap

## Execution Hardening
- Fill policy is configurable via EA input (`IOC` default).
- Market sends are synchronous by default.
- Transient retcodes use bounded retry with immediate refresh/reprice instead of sleep-based blocking.
- `LOCKED`/`FROZEN` retcodes use single bounded retry to avoid prolonged retry loops.
- Market orders rebuild execution price and protective stops at submit time.
- Protective stop modifications are throttled but allow emergency bypass for missing/tightening protection.
- Symbol scan order rotates each cycle to reduce first-symbol concentration when only one trade is allowed per cycle.

## Diagnostics
- Weighted quorum evaluation emitted as `[CONSENSUS-QUORUM]`.
- Consensus reason counters emitted as `[CONSENSUS-DIAG]`:
  - `raw_none`
  - `filtered_out`
  - `quorum_failed`
  - `intrabar_not_eligible`
- Startup execution posture emitted as `[EXECUTION-MODE]`.
- Confirmed deal lifecycle emitted as `[TRADE-CONFIRMED]`.
- Consensus dominant-cause attribution emitted as `[CONSENSUS-ROOT]`.
- Strategy-level none-reason attribution emitted as `[CONSENSUS-STRATEGY]`.
- Heartbeat aggregate consensus snapshots emitted as `[CONSENSUS-SNAPSHOT]`.
- Heartbeat aggregate strategy reject buckets emitted as `[STRATEGY-REJECTS]`.
- Confidence-threshold source emitted as `[PIPELINE-THRESHOLD]` with tags:
  - `REGIME_RANGE`
  - `REGIME_TREND_RELAX`
  - `REGIME_BREAKOUT_RELAX`
  - `REGIME_CHAOS`
  - `REGIME_ENGINE_WARMUP`
- Runtime conversion tracking emitted as `[HEARTBEAT-FUNNEL]` and `[CONVERSION-RATES]`.
- Prolonged no-signal dominance alert emitted as `[NO-SIGNAL-ALERT]`.
- Strategy-governance telemetry emitted as `[CONSENSUS-ROLE]`, `[CONSENSUS-CLUSTER]`, and heartbeat `[ROLE-CLUSTER]`.
- Cluster risk telemetry emitted as `[RISK-CLUSTER]` and `[RISK-MUTEX-BLOCK]`.
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
- Runtime requires hedging account semantics and rejects unsupported margin modes during startup.
- `CIndicatorManager::DestroyInstance()` must run on deinit.
- Removed strategy families are not represented in runtime registration paths.
- Unified ICT runtime labeling is normalized (no legacy `Unified ICT/SMC` path labels).

## Fast Debug Read Order
1. `[HEARTBEAT]`
2. `[HEARTBEAT-FUNNEL]` / `[CONVERSION-RATES]`
3. `[CONSENSUS-QUORUM]` / `[CONSENSUS-DIAG]` / `[CONSENSUS-ROOT]` / `[CONSENSUS-STRATEGY]`
4. `[CONSENSUS-SNAPSHOT]` / `[STRATEGY-REJECTS]`
5. `[PIPELINE-THRESHOLD]`
6. `[SIGNAL-REJECTED]`
7. `[RISK-BUDGET]`
8. `[RISK-UNPROTECTED]` / `[CAPACITY-EXTERNAL]`
9. `[AI-VOTE]`
10. `[NO-SIGNAL-ALERT]`
11. `[SHADOW-TRADE]` or `[TRADE-SUCCESS]/[TRADE-ERROR]`
