# Runtime Decision Graph

## Document Metadata
- Last Updated: 2026-06-18
- Scope: Runtime signal-to-execution flow
- Source: `MultiStrategyAutonomousEA.mq5`
- Current Batch: 104 - SL/BE/Trailing + Chart Drawing Bug Fixes

## Purpose
Defines the authoritative runtime decision path and ownership boundaries between signal generation, validation, risk veto, execution, and post-trade feedback.

## Ownership Map
- Orchestration: `MultiStrategyAutonomousEA.mq5`
- Consensus: `CEnterpriseStrategyManager`
- Multi-Tier Validation: `CTieredSignalValidator` (Batch 60)
- Filtering: `CUnifiedSignalPipeline`
- AI adaptation/weights: `CAIEngine` + symbol-scoped AI adapters (implementing `IAIStrategy`)
- AI modules:
  - `CNeuralCore` - Core activations, loss functions, gradients
  - `CNeuralTrainingDataManager` - Training examples and barrier buffer
  - `CNeuralCheckpointManager` - Atomic checkpoint operations
  - `CSymbolEmbedding` - Learnable symbol embeddings in transformer
- Live authority: `MultiStrategyAutonomousEA.mq5` candidate authority gate
- Risk veto: `CUnifiedRiskManager`
- Execution: `CTradeManager`
- Position lifecycle: `MultiStrategyAutonomousEA.mq5` + `CTradeManager::ManageAllPositions(...)`
- Indicator cache lifecycle: `CIndicatorManager`
- Python bridge integration: `CPythonBridge` in `Core/Utils/PythonBridge.mqh`
- Shared engine & scalability: `CSharedEngineManager` (Batch 91)
- Error aggregation & verbosity: `CEnhancedErrorHandler` (enhanced in Batch 91)
- Bar processing & multi-timeframe: `CBarProcessor` (enhanced in Batch 91)
- Scalping engine: `CFastScalpEngine` + `CScalpSignalCache` (Batch 97)
- Scalp strategies: `CScalpMomentumStrategy`, `CScalpSpreadStrategy`, `CScalpVolatilityBreakout` (Batch 97)
- Position lifecycle: `CPositionLifecycleManager` (Batch 98)
- Diagnostics/heartbeat: `CDiagnosticsManager` (Batch 98)
- Unprotected position tracking: `CUnprotectedPositionTracker` (Batch 98)
- Synthetic spike monitoring: `CSyntheticSpikeMonitor` (Batch 98)
- Trade attribution: `CTradeAttributionManager` (Batch 98)
- Symbol scan scheduling: `CSymbolScanScheduler` (Batch 98)
- Position sizing (stateless): `CPositionSizer::CalculateSize()` → `CalculateOptimalPositionSizeCore()` (Batch 98)
- AI calibration: `IAIStrategy::GetCalibratedWeight()` (Batch 99)
- Equity curve: `CEquityCurveManager` (Batch 99)
- CVaR risk: `CPortfolioRiskManager::IsCVaRLimitExceeded()` (Batch 99)
- Commission-aware scalp: `CFastScalpEngine::IsScalpCostViable()` (Batch 99)
- Async execution: `CTradeManager::SendTradeAsync()` + `ProcessTradeTransaction()` (Batch 99)
- Bayesian Kelly: `CBayesianKellyModifier` (Batch 99)
- Spike hunting: `CSpikeHunterEngine` (Batch 100)
- Hurst persistence engine: `CHurstEngine` (Batch 101)
- OU mean-reversion engine: `COrnsteinUhlenbeckEngine` (Batch 101)
- OFI proxy engine: `COrderFlowImbalanceEngine` (Batch 101)
- VPIN toxicity filter: `CVPINFilter` (Batch 101)
- Deriv asset profiler: `CDerivAssetProfiler` (Batch 102)
- Grid recovery engine: `CGridRecoveryEngine` (Batch 102)
- ATR scalping engine: `CATRScalpingEngine` (Batch 102)
- SpikeHunter family overrides: `SSpikeHunterFamilyOverrides` (Batch 102)
- Family risk overrides: `SSymbolRiskOverride` in `CUnifiedRiskManager` (Batch 102)
- Multi-asset class profiler: `CMultiAssetProfiler` (Batch 103)
- Asset-class engine weights: `CEnterpriseStrategyManager::ApplyAssetClassEngineWeights()` (Batch 103)
- Asset-class heartbeat: `CDiagnosticsManager` `[HEARTBEAT-ASSET-CLASS]` (Batch 103)
- Partial close management: `CPartialCloseManager` (Batch 103)
- Multi-timeframe confluence: `CTimeframeConfluence` (Batch 103)
- FVG Scalper strategy: `CFVGScalperStrategy` (Batch 103)
- Turtle Soup strategy: `CTurtleSoupStrategy` (Batch 103)
- Breaker Block strategy: `CBreakerBlockStrategy` (Batch 103)
- NY Open Gap strategy: `CNYOpenGapStrategy` (Batch 103)
- Asian Range Break strategy: `CAsianRangeBreakStrategy` (Batch 103)
- Candlestick confluence scorer: `CCandleConfluenceScorer` (Batch 103)
- Statistical Arbitrage strategy: `CStatisticalArbitrageStrategy` (Batch 103)
- VPIN toxicity consensus gate: `CEnterpriseStrategyManager` VPIN integration (Batch 103)
- OFI regime weight adjustment: `CEnterpriseStrategyManager` OFI integration (Batch 103)
- Consensus scoring (0-100): `CEnterpriseStrategyManager` graduated scoring (Batch 103)
- Regime weight wiring: `CEnterpriseStrategyManager` → `CRegimeEngine::GetRegimeCategoryMultiplier()` (Batch 103)

## End-to-End Flow

```mermaid
flowchart TD
  A[OnInit] --> B[Initialize mandatory trade and risk systems]
  B --> B0[Initialize optional AI subsystems and shared transformer service behind readiness flags]
  B0 --> B1[Validate symbols + log ACCOUNT-CAPACITY]
  B1 --> B1A{Spread > 1000 points?}
  B1A -->|Yes| B1B[Reject symbol - extreme spread]
  B1A -->|No| B2
  B1 --> B2[Recover TRADE-STATE from history and open positions]
  B2 --> B3[Initialize Python Bridge (if enabled) + check version compatibility]
  B3 --> C[Build active-only strategy registry, resolve strategy timeframes, and register enabled core or AI adapters]
  C --> C0[Initialize per-symbol managers]
  C0 --> C1[Rebuild scheduler state and prime pending new-bar work for every validated symbol]
  C1 --> D0[OnTick ProcessTickSafetyLoop]
  C1 --> D[OnTimer ProcessTradingLogic]

  D0 --> D0A[Validate tick and trading permissions]
  D0A --> D0B[Refresh runtime metrics, remediate unprotected positions, manage open positions]
  D0B --> D0B1[g_unprotectedTracker.AttemptRemediation]
  D0B1 --> D0C{Synthetic tick spike?}
  D0C -->|Yes| D0D[Flatten positions and activate temporary trading pause]
  D0C -->|No| D0E[Continue]
  D0E --> D0F{Emergency drawdown breach?}
  D0F -->|Yes| D0G[Flatten and halt trading]
  D0F -->|No| D0H[Return]

  D0H --> D0I{Spike hunter enabled?}
  D0I -->|Yes| D0J[CSpikeHunterEngine EvaluateTick]
  D0I -->|No| D0K[Continue]
  D0J --> D0L{2/3 spike confluence?}
  D0L -->|Yes| D0M[Open spike trade - log SPIKE-HUNT-TRADE]
  D0L -->|No| D0N[Log SPIKE-HUNT-SKIP]
  D0M --> D0O{Spike cooldown active?}
  D0O -->|Yes| D0P[Delay long-term entry - log SPIKE-COOLDOWN]
  D0O -->|No| D0K
  D0N --> D0K

  D --> D1{Terminal connected?}
  D1 -->|No| D2[Skip evaluation, wait reconnect]
  D1 -->|Yes| D_MGMT[g_lifecycleManager.ManagePositions]
  D_MGMT --> D_EXIT{SRE Configured?}
  D_EXIT -- Yes --> D_REV[Check Consensus Reversal]
  D_REV --> D_CONF{Reversal > 0.58 Conf?}
  D_CONF -- Yes --> D_PROFIT{Profit Guard Pass?}
  D_PROFIT -- Yes --> D_ZONE{Last Stand Zone?}
  D_ZONE -- No --> D_CLOSE[Close Position]
  D_EXIT -- No --> D_LIFECYCLE[g_lifecycleManager.ManageBreakevenAndTrailing]
  D_LIFECYCLE --> D_ATR[ATR-Based Trailing/BE]
  D_CLOSE --> D_LIFECYCLE
  D_ATR --> E{Signal eval second already used?}
  E -->|Yes| E2[Skip duplicate evaluation]
  E -->|No| E3[Continue]
  E3 --> E3A[Rotate symbol evaluation start index]
  E3A --> E3B[Mark pending new-bar symbols and compute cycle evaluation budget]
  E3B --> E3C[Select pending new-bar work first and spend remaining budget on intrabar work]
  E3C --> E4{Selected for evaluation this cycle?}
  E4 -->|No| I[Defer symbol to later cycle]
  E4 -->|Yes| E5{New-bar selection?}
  E5 -->|Yes| F[Evaluate NEW_BAR mode]
  E5 -->|No| G[Evaluate INTRABAR mode]

  F --> J[Manager consensus + confluence + timeframe consistency]
  G --> J
  J --> J0[Strategy role/cluster governance applied]
  J0 --> J1[Pipeline regime + cost viability gate + filter attribution]
  J1 --> J1A{AI direction ratio > 0.80?}
  J1A -->|Yes| J1B[Reduce AI weight 50% - log AI-CALIBRATION-WARNING]
  J1A -->|No| J2
  J1B --> J2[Multi-Tier Signal Validation & Conflict Resolution]
  J2 --> J2A{OFI contradicts consensus?}
  J2A -->|Yes| J2B[Reject signal - log SIGNAL-REJECTED reason=ofi_contradiction]
  J2A -->|No| J3[Weighted Decision considering Setup Quality & Reliability]
  J3 --> J3A{TREND_BEARISH_STRONG + BUY?}
  J3A -->|Yes| J3B[Raise quorum to 0.70 - log CONSENSUS-TREND-BIAS]
  J3A -->|No| K
  J3B --> K{Signal NONE?}
  K -->|Yes| L[Increment no-signal telemetry]
  K -->|No| M[Resolve ATR then run exogenous validation: spread/time/session/volatility/cost]

  M --> M1{Breakeven WR > 70%?}
  M1 -->|Yes| M2[Reject scalp - log SCALP-COST-REJECTED]
  M1 -->|No| N
  M2 --> O[Log SIGNAL-REJECTED]
  N{Validator pass?}
  N -->|No| O[Log SIGNAL-REJECTED]
  N -->|Yes| P{Entry gate open?}
  P -->|No| P2[Log ENTERPRISE-BLOCKED]
  P -->|Yes| Q[Build ATR SL/TP + risk request with role/cluster/contributors]

  Q --> Q1{VPIN extreme toxicity?}
  Q1 -->|Yes| Q2[Block new position - log VPIN-BLOCK]
  Q1 -->|No| R[UnifiedRisk pre-size validation]
  Q2 --> T[Risk rejection]

  R --> R1{Profitable position?}
  R1 -->|Yes| R2[Reduce used risk - log RISK-BUDGET-PNL-ADJUSTED]
  R1 -->|No| S
  R2 --> S{Pass?}
  S -->|No| T[Risk rejection]
  S -->|Yes| U[Position sizing]

  U --> U0[Apply VPIN position size multiplier 1.0 to 0.0 based on toxicity]

  U0 --> U1{Lot > margin limit?}
  U1 -->|Yes| U2[Cap lot to margin limit - log SCALP-LOT-CAPPED]
  U1 -->|No| V
  U2 --> V[UnifiedRisk post-size validation]
  V --> V1{CVaR limit exceeded?}
  V1 -->|Yes| V2[Block trade - log CVAR-CHECK]
  V1 -->|No| W
  V2 --> T[Risk rejection]
  W{Pass?}
  W -->|No| T
  W -->|Yes| X[Reserve virtual risk and stage approved candidate]

  X --> X1{More symbols?}
  X1 -->|Yes| E4
  X1 -->|No| X2[Sort approved candidates by ranking]
  X2 --> X2A[Resolve LIVE-AUTHORITY and authority risk scale]
  X2A --> X2B[Register/maintain authority forward trials]
  X2B --> X2C[Walk ranked list up to InpMaxTradeSendsPerCycle]
  X2C --> X3{Global shadow or candidate lacks live authority?}

  X3 -->|Yes| Y[Log SHADOW-TRADE + AUTHORITY-TRIAL]
  X3 -->|No| Z0[TradeManager hard spread/drift preflight]
  Z0 -->|Fail| AB
  Z0 -->|Pass| Z[TradeManager OpenPosition]

  Z --> AA{Execution success?}
  AA -->|No| AB[Trade error path]
  AA -->|Yes| AC[Register executed risk by fill ratio + cooldown + AUTHORITY-TRIAL]

  AC --> AD[OnTradeTransaction feedback]
  AD --> AE[Manager and orchestrator performance updates]
  AD --> AF[NN attribution mapping and labeling]

  D --> AH[Periodic HEARTBEAT, RISK-BUDGET, CONSENSUS-DIAG, AI-FEEDBACK, AUTHORITY-RESULT, PYTHON-BRIDGE-DASHBOARD]
```

## De-Monolithized Manager Delegation Map

The main EA delegates to the following extracted managers instead of inline logic:

| Manager | File | Replaces (inline) | Key Methods |
|---------|------|-------------------|-------------|
| `CPositionLifecycleManager` | `Core/Management/PositionLifecycleManager.mqh` | `ManageOpenPositionsIfNeeded()` SRE + lifecycle | `ManagePositions()`, `CheckSignalReversalExit()`, `ManageBreakevenAndTrailing()` |
| `CDiagnosticsManager` | `Core/Management/DiagnosticsManager.mqh` | Heartbeat block + consensus diagnostics | `EmitHeartbeat()`, `EmitConsensusDiagnostics()` |
| `CUnprotectedPositionTracker` | `Core/Risk/UnprotectedPositionTracker.mqh` | `AttemptUnprotectedPositionRemediation()` + helpers | `AttemptRemediation()` |
| `CSyntheticSpikeMonitor` | `Core/Processing/SyntheticSpikeMonitor.mqh` | Spike alarm + trading pause + emergency drawdown | `ProcessTickSafety()`, `EvaluateSpike()`, `IsPaused()` |
| `CTradeAttributionManager` | `Core/Trading/TradeAttributionManager.mqh` | 27+ prediction/attribution/NN functions | `UpsertPredictionPositionMap()`, `ConsumeAIPendingRequestMap()`, `NNDiagPrintSummary()` |
| `CSymbolScanScheduler` | `Core/Processing/SymbolScanScheduler.mqh` | 8 intrabar scoring/scheduling functions | `ScoreSymbolForIntrabar()`, `UpdateSymbolScanStateAfterDecision()` |

## Scalping Fast Path (Batch 97)

### Dual-Path Processing
- `OnTick()` runs two parallel paths:
  1. **Safety Loop** (existing): tick validation, runtime metrics refresh, unprotected position remediation, synthetic spike detection, emergency drawdown
  2. **Scalp Fast Path** (new): `ProcessScalpFastPath()` reads from `CScalpSignalCache` for zero-computation indicator access, evaluates scalp strategies at tick level
- `OnTimer()` retains full consensus logic (pipeline → manager → validator → risk → execution)
- Scalp fast path entries still pass through `CUnifiedRiskManager` pre-trade gating

### Scalp Signal Cache Architecture
- `SScalpIndicatorCache` struct: 13 indicator values + tick-level bid/ask/spread + state tracking + 7 handle references
- `CScalpSignalCache` class: fixed-size array for 20 symbols
- `UpdateOnNewBar()`: CopyBuffer path (runs only on new bar formation)
- `UpdateTickValues()`: SymbolInfoDouble-only path (runs every tick, minimal computation)
- All handles sourced from `CIndicatorManager::Instance()` singleton

### Async Order Execution
- `InpScalpAsyncMode`: enables `OrderSendAsync()` for scalp entries
- `SScalpPendingAsync` struct tracks async order state
- `OnAsyncOrderSent()` / `OnDealConfirmed()` callbacks for order lifecycle
- `CheckPendingAsyncOrders()` timeout handling via `InpScalpMaxLatencyMs`
- `OnTradeTransaction()` routes scalp async confirmations to `CFastScalpEngine`

### Scalp Strategies
- **ScalpMomentum**: EMA trend + pullback (0.5 ATR) + ATR expanding + spread < 0.3 ATR + RSI 40-60; SL=0.75×ATR, TP=1.5×ATR (1:2 R:R); SCALP_CLUSTER
- **ScalpSpread**: Wide spread returning + price near EMA + RSI filter; SL=0.06×ATR, TP=0.3×ATR; MEAN_REVERSION_CLUSTER
- **ScalpVolatilityBreakout**: ATR at 20-bar low + BB breakout + strong bar + RSI confirmation; SL=BB middle, TP=2×ATR; SCALP_CLUSTER

- Manager consensus resolves mixed-timeframe conflicts via `TimeframeConsistency` before final vote selection.
- OnInit is two-tiered: mandatory trade/risk/runtime bootstrap remains fatal, while auxiliary AI brain/orchestrator/adaptation modules degrade behind readiness flags and do not abort the EA.
- Strategy `OnNewBar(...)` handlers are state-refresh only; manager consensus owns the single authoritative `GetSignal(...)` call for each strategy evaluation cycle.
- Pending new-bar work is durable across cycles: symbols that miss the current evaluation budget stay queued ahead of intrabar work until they are processed.
- Cold-start cadence is now deterministic:
  - validate active symbols and emit startup account-capacity diagnostics before live execution
  - build the active-only strategy registry and register only enabled strategies and enabled AI adapters, ensuring experimental AI families (Transformer, Ensemble) receive non-zero weights from the AI multiplier during registry bootstrap to allow live participation
  - rebuild cadence scheduler state as one unit after manager bootstrap so symbol-bar times, intrabar timers, pending new-bar work, and scan-state backoff cannot drift out of sync with `g_activePairs`; runtime now rebuilds and logs `[SCHEDULER-STATE]` before resuming evaluation if that contract is broken.
- Per-symbol manager profiles now branch by instrument class before registration: synthetic symbols can use a lean structure-heavy roster and lighter context engines, while FX symbols retain the broader balanced roster.
- `[RUNTIME-FINGERPRINT]` now reports both `RequestedMode` and effective `EAMode`; `20260515.log` / `20260516.log` style `AI_ONLY` sessions should not be read as indicator or hybrid evidence. `20260517.log` confirms actual `INDICATOR_ONLY` and `AI_ASSISTED` participation, but those sessions died after pipeline/quorum rather than from missing registration.
- `EA_MODE_HYBRID` is indicator-led for ordinary packets, but high-confidence AI-only packets can pass through `InpAllowHybridAIStandalone` and then must satisfy the live-authority gate.
- `EA_MODE_AI_ONLY` is now strict execution mode when AI adapters are enabled: indicator-based strategies are filtered out of the strategy registry, and AI adapters are the sole tradable family on both new-bar and timed intrabar paths.
- When `EA_MODE_AI_ONLY` filters configured indicator families out of the active registry, runtime now emits `[MODE-MASK]` so operators can distinguish "inactive by mode" from "active but underperforming."
- Runtime startup now emits `[AI-TOPOLOGY]` to distinguish:
  - MT5-native live voters (`Neural Network AI`, `Transformer AI`, `Ensemble AI`)
  - Python-trained live voting via `ONNX AI`
  - `CNextGenStrategyBrain` as local feature/dashboard context only
  - Python bridge endpoint inputs as operator telemetry only
  - external LLM reasoning as non-voting adaptation support
- AI strategy adapters now support a unified `SetConfidenceThreshold(double)` interface, allowing the EA to propagate the system-wide `InpAIConfidenceThreshold` authoritative floor directly into the strategy evaluation loop, eliminating legacy hardcoded confidence caps.
- The effective AI runtime floor is now clamped to at least `0.70`, and transformer/ensemble defaults start disabled until intentionally retrained/re-enabled.
- Strategy and AI registration is active-only: disabled modules remain compiled in source but do not enter manager pools, orchestrator identity maps, or denominator math.
- Pipeline-filtered strategies now surface the rejecting filter chain in consensus summaries, and warmup/unavailable infrastructure abstentions are discounted before ready-live-weight math.
- Consensus denominator math now discounts abstention classes before support ratios are calculated: infrastructure/warmup abstentions carry minimal denominator weight, pipeline-filtered packets carry partial weight, and ordinary raw-none cycles carry reduced weight instead of drowning the few strategies that actually generated direction.
- `Momentum` can run a configured scalp-continuation lane with short wall-clock cooldown while retaining the same consensus, validation, risk, and execution path as all other entries.
- `Momentum` and `Candlestick` can register on explicit lower timeframes (`InpMomentumScalpTimeframe`, `InpCandlestickIntrabarTimeframe`) when the attached chart timeframe is higher, so timed intrabar scans can evaluate faster bars instead of repeatedly asking H1 logic for scalp entries.
- `CMarketAnalysis` can now reuse bounded last-valid trend/volatility/momentum/ATR snapshots on transient `4806/4807` data faults, preventing short sync gaps from collapsing upstream market-state evidence to zeros.
- The scan loop now reserves the current best candidate inside `CUnifiedRiskManager` while later symbols are still being evaluated, so projected daily and portfolio utilization remain authoritative during end-of-cycle ranking.
- Batch 78 source defaults are live-capable (`InpShadowMode=false`) while `InpEnableLiveAuthorityGate=true` shadows individual unproven candidates and promotes/demotes families from forward R evidence.
- Synthetic-symbol safety now includes a tick-velocity shock detector that can flatten positions and pause new entries for `InpSyntheticSpikePauseSeconds`.
- **Multi-Tier Validation Path (Batch 60):**
  - **Tiered Evaluation**: Votes are grouped into Tier 1 (Institutional), Tier 2 (Structure), and Tier 3 (Indicators).
  - **Conflict Resolution**: Logic handles contradictions between tiers (e.g., T2/T3 vs T1) using priority rules and combined weight overrides.
  - **Setup Quality Weighting**: Signal confidence is modulated by setup quality (0-1) and historical tier-level accuracy.
  - **Reliability Scoring**: Real-time reliability is calculated based on historical success rates of the contributing tiers.
- **AI Feature Path Changes (Batch 58):**
  - Neural network feature extraction now produces 44-dimensional vectors (25 original + 19 pattern-specific features)
  - Pattern-specific features include: Higher Highs/Lower Lows sequences, Support/Resistance touch counts, Fibonacci Retracement proximity, Pivot Point proximity, volume profile features, market structure features
  - Weight matrix dimensions updated to `W1[44][32]` to accommodate expanded input
  - All array allocations and loop bounds updated consistently to prevent array out of range errors
  - External LLM integration provides optional signal synthesis, trade explanation, risk assessment, and strategy weight reasoning via Ollama API
  - External LLM is configuration-driven via `useExternalLLM` flag (default `false`) and can be toggled at runtime via `SetExternalLLMEnabled(bool)`
  - External LLM reasoning is now a live, throttled adaptation-time path with explicit `[EXT-LLM]` query and status telemetry instead of a silent helper surface
  - Multi-scale attention infrastructure enables per-head scaling, time window sizes, and learning rates for differential pattern detection
  - Pattern classifier head provides 10-class pattern classification alongside 3-class BUY/SELL/NONE predictions

## Intrabar Policy
- New-bar and intrabar paths are explicit evaluation modes.
- Intrabar eligibility respects symbol scope and cadence interval.
- `InpSignalScanOnNewBarOnly=false` is now the default cadence posture so timed intrabar scheduling stays active during live synthetic verification; setting it back to `true` still acts as a hard global override that disables timed intrabar scheduling even when manager governance shows strategies as intrabar `LIVE`.
- Total heavy evaluations are bounded by `InpMaxSignalEvaluationsPerCycle`; new-bar selections consume the budget first and intrabar only uses the remainder.
- Intrabar scans are now budgeted per cycle and ranked by symbol yield instead of simple full-set round-robin.
- Symbols back off after repeated `raw_none` / `zero_voter` intrabar outcomes and recover on the next new bar.
- Intrabar/new-bar consensus behavior is manager-controlled.
- Cooldown, total-position, unprotected-position, and per-symbol capacity checks are entry gates, not scan gates; the EA keeps evaluating symbols while blocked from sending.
- Vote admission into timeframe consistency and quorum uses the pipeline's effective confidence floor for that evaluation, not just the static base pipeline minimum.
- Quorum uses normalized weighted conviction pooling (intrabar eligibility defines the active live-voter pool for intrabar scans):
  - adjusted live weight = `base strategy weight x role multiplier x healthScore reliability multiplier`
  - denominator weight = adjusted live weight reduced by abstention class (`raw-none`, `pipeline-filtered`, `infrastructure/warmup`, or other neutral)
  - ready live weight = `denominator weight x pipeline readinessScore`
  - conviction score = confidence shaped by pipeline `contextScore`, `readinessScore`, and `costScore`
  - per-direction score = `sum(ready live weight x conviction score)` for agreeing live voters
  - directional quality = `direction score / direction weight`
  - support ratio = `direction weight / total ready live weight`
  - direction passes full quorum if directional quality clears the **adaptive** quorum threshold, support clears the scan-mode floor, agreeing voters clear the effective minimum, and ready-live participation stays above `InpConsensusMinReadyWeightRatio`
  - **Adaptive quorum thresholds** (Batch 41): consensus now adjusts required directional quality and support floors based on actual active voter count to prevent denominator dilution:
    - **1 active voter**: directional quality ≥ 0.40, support ≥ 0.15 (was impossible 0.55 / 0.35)
    - **2 active voters**: directional quality ≥ 0.48, support ≥ 0.30 (was 0.55 / 0.35)
    - **3+ active voters**: directional quality ≥ 0.55, support ≥ 0.35 (standard `InpQuorumThreshold` / floor inputs)
    - Eliminates zero-score vetoes for legitimate single/dual-voter consensus by adjusting thresholds to the actual voter pool
    - Single- and dual-voter quality gates are now clamped against the current base quorum, so lowering `InpQuorumThreshold` intentionally also relaxes the adaptive one-/two-voter path instead of being silently overridden by harder fixed fallback thresholds
  - **Single-voter hardening** (Batch 77/78): low-voter ecosystems no longer bypass `InpMinLiveVoters` unless the configured floor is explicitly `1`; AI-only HYBRID packets use the explicit live-authority gate instead of hidden quorum bypass.
  - **Dynamic weight decay** (Batch 41): strategies that filter ≥ 3 consecutive cycles have their live weight decayed by `m_strategyActivityDecayRate` per additional cycle, reducing the denominator as dormant strategies fall out of contribution; weight recovers when the strategy produces a vote again
- If both directions qualify inside the configured deadband, consensus is vetoed instead of forcing a weak winner.
- Intrabar sparse one-voter admission is disabled by default through `InpAllowSparseIntrabarSingleVoter=false`; high-confidence AI-only packets are handled by live authority, not sparse admission.
- Synthetic lean symbols now use dedicated sparse intrabar thresholds for one-voter admission, so structure-first synthetic rosters are no longer evaluated against the same sparse-quality floor used by broader FX/balanced rosters.
- Pipeline confidence policy remains separate from AI thresholds so non-AI strategies are not gated by AI policy.
- Structural admission is now manager-owned: once manager consensus admits a packet, validator no longer re-judges confidence, confluence, directional quality, or support in normal runtime.
- Validator now operates in `EXOGENOUS_ONLY` mode during normal runtime, limiting post-consensus checks to spread, time, session, volatility, and cost-viability sanity.
- Validator profile inputs (confidence + confluence + quality) remain logged and configurable as telemetry/fallback surfaces, but they are no longer a second structural veto authority when manager-owned admission is enabled.
- Validator still consumes manager quorum evidence (`effectiveMinVoters`, `directionalQuality`, `supportRatio`) so exogenous validation telemetry and any legacy fallback mode stay aligned with the already-authoritative manager decision.
- Strategy overrides that bypass base-class `GetSignal(...)` must emit explicit last-decision tags; manager now downgrades any remaining placeholder abstentions instead of treating them as fully ready neutral voters.
- Protective lifecycle thresholds are now risk-relative: breakeven, trailing, and partial-close activation must clear both the configured pip floor and a fraction of the trade's original stop distance.
- Protective stop modifications are validated against executable quote side with extra stop/freeze cushion and one widened retry on `TRADE_RETCODE_INVALID_STOPS`.
- The EA-level generic breakeven/trailing loop is now opt-in via `InpEnablePositionLifecycleManager`; when left off, only strategy-defined SL/TP and risk/execution protections manage the trade.

## Strategy Governance Policy
- Manager-level strategy metadata controls live-vote authority:
  - role: `PRIMARY_ALPHA`, `CONTEXT_FEATURE`, `SHADOW_RESEARCH`
  - cluster: `TREND_CLUSTER`, `MEAN_REVERSION_CLUSTER`, `STRUCTURE_CLUSTER`, `NONE`
- Default policy:
  - all enabled retained strategies are registered as `PRIMARY_ALPHA` and vote live
  - per-strategy inputs gate registration (disabled strategies are not registered into the pool)
  - curated mode is now a baseline/default profile only; explicit strategy enables remain authoritative for runtime registration
- Intrabar policy is explicit per strategy:
  - `LIVE`: full quorum participant during intrabar scans
  - `PROBE`: evaluated intrabar but only eligible for sparse admission
  - `OFF`: skipped before pipeline work
- Current runtime mapping promotes intrabar-enabled manual strategies into `LIVE`, so `intrabar=true` means real intrabar voting rather than a hidden probe-only path.
- Elliott Wave can contribute to consensus, but Elliott-only packets are candidate-level shadow unless authority evidence and independent confluence justify live send.
- Synthetic lean profiles are the deliberate exception: `Fibonacci`, `Elliott Wave`, `Support/Resistance`, and `Unified ICT` remain intrabar `LIVE`, `Candlestick` is retained as intrabar `PROBE`, and `Momentum` / `Trend` are removed from the local synthetic manager roster when structure-capable strategies are already enabled.
- Governance startup logs now mark disabled strategies as `INACTIVE` in the intrabar summary instead of implying they are live because a separate profile leaves the raw input toggles enabled.
- Governance is continuous, not only binary:
  - closed-trade outcomes update rolling `healthScore`
  - reliability multipliers scale live vote impact without bypassing role/cluster controls
- Intrabar participation remains explicit and operator-driven: the curated default starts lean, but any explicitly enabled strategy remains active, and any enabled strategy with intrabar eligibility set to `true` participates as a live intrabar voter.
- Instrument class now shapes governance:
  - FX: balanced roster, full trend filter, default higher-timeframe mapping
  - synthetics: structure-first roster, no ADX-dependent trend engine path, lighter higher-timeframe mapping for ICT/Elliott alignment, and a narrower intrabar live roster to keep M1 synthetic quorum from becoming a 7-strategy noise funnel

## Strategy Intelligence (Batch 97)

### Advanced Mathematical Engines (Batch 101)

#### Multi-Asset Class Detection & Routing (Batch 103)

- `CMultiAssetProfiler::DetectAssetClass(symbol)` runs during OnInit for each managed symbol
- Detection priority: Deriv first (via `IsSyntheticIndexSymbolName()`), then Metals (`IsMetalsSymbolName()`), Indices (`IsIndicesSymbolName()`), Energies (`IsEnergiesSymbolName()`), Forex (`IsForexPairSymbolName()`), Universal fallback
- Result: `ENUM_ASSET_CLASS` value (10 classes: FOREX through UNIVERSAL)
- `SAssetProfile` provides per-class parameters: ATR SL/TP multipliers, risk/drawdown limits, engine enable flags, feature set size, magic offset
- For Deriv symbols (asset_class 4-8): delegates to `CDerivAssetProfiler` for fine-grained 18-family detection, then maps to coarse Deriv asset class via `DerivFamilyToAssetClass()`
- Engine routing based on class:
  - **Forex**: Trend 1.3x, VolBreakout 1.2x, MeanRevert 0.7x weight multipliers
  - **Metals**: VolBreakout 1.5x, MeanRevert 0.5x weight multipliers
  - **Indices**: MeanRevert 1.5x, VolBreakout 0.5x, Trend 0.8x weight multipliers
  - **Energies**: VolBreakout 1.4x, Trend 1.2x weight multipliers
  - **Deriv**: delegates to existing `ApplyFamilyEngineWeights()` for 18-family granularity
- Python bridge routing: `DetectAssetClassId()` + `GetAssetClassName()` → `PredictMultiAsset()` → server routes asset_class 0-3 to asset-class models, 4-8 to Deriv family models, -1 to universal
- `CDiagnosticsManager` emits `[HEARTBEAT-ASSET-CLASS]` for non-Deriv symbols (class name, ATR SL/TP, risk%, engine enables)
- Emit `[ASSET-CLASS-WEIGHT]` with class name and applied weight multipliers

#### Trend Strategy Signal Path (Batch 103 cont.)

```
CStrategyTrend::GetSignal()
  ├─ Hurst filter: H < 0.50 → REJECT "TREND_HURST_MEAN_REVERTING"
  ├─ VPIN filter: VPIN > 0.5 → REJECT "TREND_VPIN_TOXIC"
  ├─ ADX sizing: InitForAssetClass() sets per-class thresholds
  │   ├─ Forex/Metals: 20/25/30/35
  │   ├─ Deriv: 15/20/25/30
  │   └─ Indices: 18/23/28/33
  ├─ EMA momentum: HasEMAMomentum() → confidence × 1.10
  ├─ Freshness: GetTrendFreshnessMultiplier()
  │   ├─ consistency < 10 → × 1.15
  │   └─ consistency > 50 → × 0.90
  └─ Signal output → consensus pipeline
```

- Trailing stop lifecycle: breakeven at 1R (5 pip buffer), then `CTrendTrailingStop::CalculateTrailingStop()` with TRAIL_HYBRID method; SL only moves in favorable direction
- Engine injection: `SetHurstEngine()`/`SetVPINFilter()` wired in EA OnInit via `GetStrategyByName("Trend")` + `dynamic_cast<CStrategyTrend*>`

#### S/R Strategy Signal Path (Batch 103 cont.)

```
CStrategySupportResistance::GetSignal()
  ├─ Hurst filter: H > 0.55 + SR_MODE_BOUNCE → REJECT "SR_HURST_TRENDING_NO_BOUNCE"
  ├─ VPIN filter: VPIN > 0.5 → REJECT "SR_VPIN_TOXIC"
  ├─ Bounce sub-strategy (CSRSignalScorer):
  │   ├─ AddPriceAtLevel(30) + AddCandleRejection(25) + AddEMAAligned(20)
  │   ├─ + AddTrendlineConfluence(15) + AddMultipleTouches(10)
  │   └─ Score ≥ 60/100 → signal (confidence = score/100.0)
  ├─ Breakout sub-strategy:
  │   ├─ FalseBreakoutDetected() → counter-signal (0.70 confidence)
  │   └─ Standard breakout with retest confirmation
  └─ Signal output → consensus pipeline
```

- Level decay: `CalculateStrength()` applies `0.99^barsOld` (capped at 500 bars)
- Drawing throttle: chart updates every 5 bars (m_drawBarCounter % 5)
- Engine injection: `SetHurstEngine()`/`SetVPINFilter()` wired in EA OnInit via `GetStrategyByName("Support/Resistance")` + `dynamic_cast<CStrategySupportResistance*>`

#### FVG Scalper Signal Path (Batch 103 cont.)

```
CFVGScalperStrategy::GetSignal()
  ├─ CImbalanceDetector: find strongest FVG zone
  ├─ Price inside FVG? → No → REJECT "FVG_SCALPER_PRICE_OUTSIDE_FVG"
  ├─ Rejection candle: bullish wick (BUY) or bearish wick (SELL)
  │   ├─ No bull rejection → REJECT "FVG_SCALPER_NO_BULL_REJECTION"
  │   └─ No bear rejection → REJECT "FVG_SCALPER_NO_BEAR_REJECTION"
  ├─ Confidence: base 0.55 + structure alignment (+0.08) + fast CHOCH (+0.07) + CISD displacement (+0.05)
  ├─ SL: 0.5×ATR beyond FVG boundary
  ├─ TP: 1.5R
  └─ Signal output → consensus pipeline (Tier 2, STRUCTURE_CLUSTER, weight 1.8)
```

- Log: `[FVG-SCALPER]`

#### Turtle Soup Signal Path (Batch 103 cont.)

```
CTurtleSoupStrategy::GetSignal()
  ├─ CLiquidityDetector::DetectTurtleSoup() → no signal → REJECT "TURTLE_NO_SIGNAL"
  ├─ Structure alignment OR fast CHOCH required
  │   └─ Neither confirmed → REJECT "TURTLE_STRUCTURE_NOT_ALIGNED"
  ├─ Confidence: base 0.50 + turtleSoup.confidence×0.15 + structure (+0.10) + FVG (+0.08) + CHOCH (+0.07)
  ├─ SL: beyond sweep extreme + 0.3×ATR
  ├─ TP: 2R
  └─ Signal output → consensus pipeline (Tier 2, STRUCTURE_CLUSTER, weight 1.6)
```

- Log: `[TURTLE-SOUP]`

#### Breaker Block Signal Path (Batch 103 cont.)

```
CBreakerBlockStrategy::GetSignal()
  ├─ CAdvancedOrderBlockDetector: scan for OB_BREAKER_BULL/OB_BREAKER_BEAR
  ├─ Price retest of breaker zone? → No → REJECT "BREAKER_NO_BREAKER_RETEST"
  ├─ Confidence: base 0.55 + freshness > 0.7 (+0.08) + FVG confluence (+0.10) + CISD (+0.05) + structure (+0.07)
  ├─ SL: 0.5×ATR beyond breaker boundary
  ├─ TP: 2R
  └─ Signal output → consensus pipeline (Tier 2, STRUCTURE_CLUSTER, weight 1.7)
```

- Log: `[BREAKER-BLOCK]`

#### NY Open Gap Signal Path (Batch 103 cont.)

```
CNYOpenGapStrategy::GetSignal()
  ├─ Synthetic symbol filter: Volatility/Boom/Crash/Jump/Step → REJECT "NYGAP_SYNTHETIC_SKIP"
  ├─ Session window: 13:30-14:00 UTC only → outside → REJECT "NYGAP_OUTSIDE_WINDOW"
  ├─ CSessionGapDetector: gap between prev close and current open
  │   └─ Gap size < 0.5×ATR(14,D1) → REJECT "NYGAP_GAP_TOO_SMALL"
  ├─ Direction: gap up → SELL (fade), gap down → BUY (fade)
  ├─ Confidence: base 0.50 + FVG confluence (+0.10) + large gap >1.0×ATR (+0.08) + near gap level (+0.07)
  ├─ SL: beyond gap extreme + 0.5×ATR
  ├─ TP: at previous close (gap fill target)
  └─ Signal output → consensus pipeline (Tier 3, STRUCTURE_CLUSTER, weight 1.3)
```

- Log: `[NYGAP]`

#### Asian Range Break Signal Path (Batch 103 cont.)

```
CAsianRangeBreakStrategy::GetSignal()
  ├─ Synthetic symbol filter: Volatility/Boom/Crash/Jump/Step → REJECT "ASIANRB_SYNTHETIC_SKIP"
  ├─ Session window: London open 07:00-07:30 UTC only → outside → REJECT "ASIANRB_OUTSIDE_LONDON_OPEN"
  ├─ CICTKillZones: measure Asian range (00:00-06:00 UTC)
  │   └─ Range > 0.8×ATR → REJECT "ASIANRB_RANGE_TOO_WIDE"
  ├─ Breakout: price above Asian high → BUY, below Asian low → SELL
  │   └─ No breakout → REJECT "ASIANRB_NO_BREAKOUT"
  ├─ Confidence: base 0.50 + range compression < 0.5×ATR (+0.10) + structure (+0.08) + fast CHOCH (+0.07)
  ├─ SL: opposite range boundary
  ├─ TP: 2× range size
  └─ Signal output → consensus pipeline (Tier 3, STRUCTURE_CLUSTER, weight 1.3)
```

- Log: `[ASIANRB]`

#### Partial Close Manager Lifecycle (Batch 103 cont.)

```
CPartialCloseManager::ManagePosition(ticket)
  ├─ Find or auto-register position in SPartialCloseState[]
  ├─ Step 1: profit ≥ 1R → close 50% volume (respect SYMBOL_VOLUME_MIN/STEP)
  │   └─ Log [PARTIAL-CLOSE] with ticket, volume, profit
  ├─ Step 2: after 1R hit → move SL to entry + 0.1% buffer
  │   └─ Validate against SYMBOL_TRADE_STOPS_LEVEL
  └─ Step 3: profit ≥ 2R → trail SL at 1.5×ATR(M5,14) from price
      └─ SL only moves in favorable direction
```

- Periodic cleanup: every 5 minutes, compact closed positions from state array (max 50 tracked)

#### Timeframe Confluence Scoring (Batch 103 cont.)

```
CTimeframeConfluence::GetAlignmentScore(direction)
  ├─ H1 CMarketStructureAnalyzer: bullish/bearish → 40 points
  ├─ M15 CMarketStructureAnalyzer: bullish/bearish → 30 points
  ├─ M5 CMarketStructureAnalyzer: bullish/bearish → 30 points
  └─ Total: 0-100 (all 3 aligned = 100)
```

- `IsMajorityAligned(bullish)`: true if ≥2/3 timeframes aligned in given direction
- Per-bar caching: `STFAlignmentCache` invalidated when `iTime(tf, 0)` changes

#### Mean Reversion v2.0 Signal Path (Batch 103 cont.)

```
CStrategyMeanReversion::GetSignal()
  ├─ Hurst regime lockout: H < 0.45 → REJECT "MR_HURST_NOT_MEAN_REVERTING"
  ├─ Stochastic extreme confirmation:
  │   ├─ BUY: Stoch < 20 (oversold)
  │   └─ SELL: Stoch > 80 (overbought)
  │   └─ Neither extreme → REJECT "MR_STOCH_NOT_EXTREME"
  ├─ BB width filter: BB width < 20th percentile required
  │   └─ BB width too wide → REJECT "MR_BB_WIDTH_HIGH"
  ├─ No-divergence check: price vs indicator divergence → REJECT "MR_DIVERGENCE_DETECTED"
  ├─ Dynamic TP: TP adjusts by BB width percentile (tighter BB → smaller TP)
  ├─ Confidence: base 0.55 + Stoch depth (+0.10) + BB compression (+0.08)
  └─ Signal output → consensus pipeline (MEAN_REVERSION_CLUSTER, weight 1.4)
```

- Engine injection: `SetHurstEngine()` wired in EA OnInit via `GetStrategyByName("Mean Reversion")` + `dynamic_cast<CStrategyMeanReversion*>`
- Log: `[MR-HURST-NOT-MEAN-REVERTING]`, `[MR-STOCH-NOT-EXTREME]`, `[MR-BB-WIDTH-HIGH]`, `[MR-DIVERGENCE-DETECTED]`

#### Statistical Arbitrage Signal Path (Batch 103 cont.)

```
CStatisticalArbitrageStrategy::GetSignal()
  ├─ Python Bridge connected? → No → REJECT "STATARB_NO_PYTHON_BRIDGE"
  ├─ OU engine available? → No → REJECT "STATARB_NO_OU_ENGINE"
  ├─ OU half-life filter: half-life < 50 bars required
  │   └─ half-life ≥ 50 → REJECT "STATARB_HALFLIFE_TOO_LONG"
  ├─ Z-score detection:
  │   ├─ Entry: |z-score| > 2.0
  │   └─ Exit: |z-score| < 0.5
  │   └─ |z-score| between 0.5 and 2.0 → REJECT "STATARB_ZSCORE_NEUTRAL"
  ├─ Direction: z-score > 2.0 → SELL (mean reversion down), z-score < -2.0 → BUY (mean reversion up)
  ├─ Confidence: base 0.55 + OU quality bonus (+0.10) + half-life speed bonus (+0.08)
  └─ Signal output → consensus pipeline (MEAN_REVERSION_CLUSTER, weight 1.5)
```

- Engine injection: `SetOUEngine()` wired in EA OnInit via `GetStrategyByName("Statistical Arbitrage")` + `dynamic_cast<CStatisticalArbitrageStrategy*>`
- Conditionally registered when Python Bridge is connected
- Log: `[STATARB]`

#### Candlestick v2.0 Signal Path (Batch 103 cont.)

```
CStrategyCandlestick::GetSignal()
  ├─ CCandleConfluenceScorer: aggregate all pattern detectors
  │   ├─ CDojiDetector: Doji pattern (body/shadow ratio)
  │   ├─ CHammerDetector: Hammer/Inverted Hammer
  │   ├─ CStarDetector: Morning/Evening Star
  │   ├─ CHaramiDetector: Bullish/Bearish Harami
  │   ├─ CThreeSoldiersDetector: Three White Soldiers/Three Black Crows
  │   └─ CPiercingDetector: Piercing/Dark Cloud Cover
  ├─ Confluence score ≥ 70/100 required
  │   └─ Score < 70 → REJECT "CANDLE_CONFLUENCE_LOW"
  ├─ Confidence = confluenceScore / 100.0
  └─ Signal output → consensus pipeline (NONE cluster, weight 1.0)
```

- Log: `[CANDLE_CONFLUENCE]`

#### Volatility Breakout v2.0 Signal Path (Batch 103 cont.)

```
CVolatilityBreakoutStrategy::GetSignal()
  ├─ TTM Squeeze detection: BB inside KC → squeeze active
  │   └─ No squeeze → REJECT "VB_NO_SQUEEZE"
  ├─ Breakout: price exits BB on squeeze release
  │   └─ No breakout → REJECT "VB_NO_BREAKOUT"
  ├─ ADX rising filter: ADX slope > 0 required
  │   └─ ADX falling → REJECT "VB_ADX_NOT_RISING"
  ├─ Breakout retest: price retests breakout level before entry
  │   └─ No retest → reduced confidence (-0.10)
  ├─ Breakout failure reversal: failed breakout → counter-direction at 0.65 confidence
  ├─ Confidence: base 0.55 + squeeze strength (+0.10) + ADX rising (+0.08) + retest confirmed (+0.07)
  └─ Signal output → consensus pipeline (SCALP_CLUSTER, weight 1.3)
```

- Log: `[TTM_SQUEEZE]`, `[BREAKOUT_RETEST]`, `[BREAKOUT_FAILURE_REVERSAL]`

#### Momentum v2.0 Signal Path (Batch 103 cont.)

```
CSimpleMomentumStrategy::GetSignal()
  ├─ EMA trend alignment (existing)
  ├─ MACD histogram confirmation: MACD line above signal → BUY confirmed
  │   └─ MACD not confirming → REJECT "MOM_MACD_NOT_CONFIRMING"
  ├─ ADX strong trend filter: ADX > 25 required for trend entries
  │   └─ ADX ≤ 25 → REJECT "MOM_ADX_WEAK"
  ├─ Pullback entry: EMA pullback within 0.5×ATR
  ├─ Freshness modifier: recent signal → confidence +10%
  ├─ Volume modifier: above-average volume → confidence +8%
  └─ Signal output → consensus pipeline (TREND_CLUSTER, weight 1.2)
```

#### VPIN Toxicity Gating in Consensus Flow (Batch 103 cont.)

```
CEnterpriseStrategyManager::EvaluateConsensus()
  ├─ ... existing quorum evaluation ...
  ├─ VPIN toxicity check (after quorum, before final consensus):
  │   ├─ VPIN_EXTREME → BLOCK all entries (consensus veto)
  │   │   └─ Log [VPIN-BLOCK] with VPIN value and toxicity level
  │   ├─ VPIN_HIGH → reduce all strategy weights by 50%
  │   │   └─ Log [VPIN-HIGH] with adjusted weights
  │   └─ VPIN_MEDIUM → reduce all strategy weights by 25%
  │       └─ Log [VPIN-MEDIUM] with adjusted weights
  └─ Continue to consensus scoring
```

- VPIN toxicity levels from `CVPINFilter::GetToxicityLevel()`: `VPIN_LOW`, `VPIN_MEDIUM`, `VPIN_HIGH`, `VPIN_EXTREME`
- Applied per-symbol in the consensus evaluation path

#### OFI Regime Weight Adjustment (Batch 103 cont.)

```
CEnterpriseStrategyManager::ApplyRegimeCategoryWeights()
  ├─ Get regime category multiplier from CRegimeEngine::GetRegimeCategoryMultiplier()
  ├─ OFI alignment check:
  │   ├─ OFI direction aligned with regime category → 1.2× boost
  │   │   └─ Log [OFI-REGIME-BOOST] with direction and multiplier
  │   └─ OFI direction contradicts regime category → 0.7× penalty
  │       └─ Log [OFI-REGIME-PENALTY] with direction and multiplier
  └─ Apply adjusted multiplier to strategy weights
```

- OFI direction from `COrderFlowImbalanceEngine::GetImbalanceDirection()`
- Applied after regime weight wiring, before consensus scoring

#### 0-100 Consensus Scoring (Batch 103 cont.)

```
CEnterpriseStrategyManager::ComputeConsensusScore()
  ├─ rawConsensusScore = directionalQuality × supportRatio × 100
  ├─ Score interpretation:
  │   ├─ < 60: consensus FAIL (no signal)
  │   ├─ 60-70: marginal consensus (position sizing × 0.75)
  │   ├─ 70-85: standard consensus (position sizing × 1.0)
  │   └─ 85+: strong consensus (position sizing × 1.0, priority ranking boost)
  ├─ Log [CONSENSUS-SCORE] with raw score, quality, support, and tier
  └─ Pass/fail replaces binary quorum threshold
```

- Threshold = 60/100 (configurable)
- Graduated scoring enables proportional position sizing based on consensus quality

- `CDerivAssetProfiler::DetectFamily(symbol)` runs during OnInit for each managed symbol
- Symbol name matched against 13 family-specific detection functions in `Instruments.mqh`
- Result: `ENUM_DERIV_FAMILY` value (18 families + UNKNOWN)
- `SDerivProfile` provides per-family parameters: engine enable flags, risk/drawdown limits, ATR multipliers, grid config, spike config
- Engine routing based on profile flags:
  - `enableSpikeHunter=true` → symbol added to `CSpikeHunterEngine` with family-specific overrides via `SSpikeHunterFamilyOverrides`
  - `enableGridRecovery=true` → symbol added to `CGridRecoveryEngine` with family-specific grid config via `SetFamilyConfig()`
  - ATR scalping enabled for Jump/DEX/Hybrid families → symbol added to `CATRScalpingEngine` with spike interval from `CSpikeHunterEngine`
  - `enableHurstRegime=true` → Hurst regime detection active for this family's grid recovery activation
  - `enableOUFilter=true` → OU filter active for this family's mean-reversion confirmation
- `CEnterpriseStrategyManager::ApplyFamilyEngineWeights()` adjusts strategy weights based on family profile
- `CUnifiedRiskManager` applies `SSymbolRiskOverride` per-family risk/drawdown scaling during pre-trade validation
- `CTradeManager` applies `SSymbolMagicOffset` per-family magic offset for position tracking
- Emit `[PROFILER-DETECT]` with detected family and enabled engines

#### Grid Recovery Activation Flow (Batch 102)

- Grid recovery only activates when Hurst exponent confirms mean-reversion regime:
  1. `CHurstEngine` computes Hurst exponent per symbol
  2. `CGridRecoveryEngine::SetHurstRegime(symbol, hurstValue)` receives updated Hurst value
  3. If `hurstValue < activationHurstThreshold` (0.45): grid entries permitted
  4. If `hurstValue >= activationHurstThreshold`: grid entries suppressed (market not mean-reverting)
- Grid level progression:
  - Modified Martingale: `lot = baseLot × factor^level` (factor=1.5)
  - Fibonacci: `lot = baseLot × fib(level)`
- Per-level SL = ATR × 1.5, TP = 0.5 × grid spacing
- Max 8 levels with 15% drawdown cap per family
- 30-second cooldown between grid entries
- Emit `[GRID-RECOVERY-ENTRY]`, `[GRID-RECOVERY-LEVEL]`, `[GRID-RECOVERY-CLOSE]`, `[GRID-RECOVERY-DRAWDOWN]`

#### ATR Scalping Spike Window Avoidance (Batch 102)

- ATR scalping trades only in calm periods between spikes/jumps:
  1. `CSpikeHunterEngine` detects spikes and calls `CATRScalpingEngine::NotifySpikeDetected(symbol)`
  2. `CATRScalpingEngine` learns spike intervals: `SetSpikeInterval(symbol, intervalSec)`
  3. Before each scalp entry, engine checks if current time is within `spikeWindowAvoidMinutes` (5) of expected next spike
  4. If within spike window: skip entry, emit `[ATR-SCALP-SPIKE-WINDOW]`
  5. If outside spike window: evaluate entry conditions (EMA trend + RSI + spread filter)
- Entry: EMA fast > slow (BUY) or fast < slow (SELL) + RSI 30-70 + spread < 0.3×ATR
- SL=1.5×ATR, TP=2.0×ATR
- Max 3 concurrent positions per symbol, 30-second cooldown
- Emit `[ATR-SCALP-ENTRY]`, `[ATR-SCALP-EXIT]`, `[ATR-SCALP-COOLDOWN]`

#### SpikeHunter Family Override Decision Path (Batch 102)

- Per-family spike parameters override defaults via `SSpikeHunterFamilyOverrides`:
  1. `CDerivAssetProfiler` provides family profile for each symbol
  2. `CSpikeHunterEngine::SetFamilyOverrides()` populates `m_familyOverrides[]` array
  3. Each detection/trade method calls `GetEffective*()` methods instead of raw constants:
     - `GetEffectiveVelocityMultiplier(idx)` — CrashBoom 2.8×, Jump 3.0×, Volatility 3.5× (vs default 2.5×)
     - `GetEffectiveMinConsecutiveTicks(idx)` — family-specific tick count threshold
     - `GetEffectiveATRCompressionRatio(idx)` — family-specific compression ratio
     - `GetEffectiveSLAtrMultiplier(idx)` — family-specific SL distance
     - `GetEffectiveTPAtrMultiplier(idx)` — family-specific TP distance
     - `GetEffectiveMagicOffset(idx)` — family-specific magic offset (9000-9900)
     - `GetEffectiveCooldownMs(idx)` — family-specific cooldown between spike trades
     - `GetEffectiveMinConfluence(idx)` — family-specific minimum confluence layers
  4. If no family override exists for a symbol, defaults are used
- SpikeHunter keeps direct execution (no CUnifiedRiskManager gating) per design decision

#### Hurst Persistence Engine
- `CHurstEngine` computes the Hurst exponent per symbol to classify persistence vs mean-reversion tendency
- After regime engine update, `ApplyHurstWeightModifiers()` adjusts regime-based strategy weights:
  - H > 0.6 (persistent/trending): boosts TREND_CLUSTER weights, suppresses MEAN_REVERSION_CLUSTER
  - H < 0.4 (anti-persistent/mean-reverting): boosts MEAN_REVERSION_CLUSTER weights, suppresses TREND_CLUSTER
  - 0.4 ≤ H ≤ 0.6 (random walk): no weight modification
- Applied after `CRegimeEngine` state update, before consensus quorum evaluation

#### OU Mean-Reversion Engine
- `COrnsteinUhlenbeckEngine` fits an Ornstein-Uhlenbeck process to estimate mean-reversion speed (θ), equilibrium level (μ), and volatility (σ)
- In `StatisticalArbitrageStrategy`, OU-adjusted z-score is blended with simple z-score when OU quality > 0.5:
  - blended z-score = `(1 - ouQuality) * simpleZScore + ouQuality * ouZScore`
  - OU quality derived from parameter estimation confidence and residual fit
- Provides more accurate mean-reversion entry/exit timing than simple Bollinger-based z-scores

#### OFI Proxy Engine
- `COrderFlowImbalanceEngine` estimates order flow imbalance from tick-level price and volume data as a proxy for Level 2 order book data
- OFI contradiction check runs after multi-tier signal validation:
  - If OFI signal direction contradicts consensus direction, signal is rejected
  - Logged as `[SIGNAL-REJECTED] reason=ofi_contradiction`
  - Prevents entries against detected institutional order flow pressure

#### VPIN Toxicity Filter
- `CVPINFilter` computes Volume-Synchronized Probability of Informed Trading (VPIN) to detect toxic order flow
- Two decision points in the execution path:
  1. **Pre-risk VPIN block**: if VPIN exceeds extreme toxicity threshold, new positions are blocked entirely — logged as `[VPIN-BLOCK]`
  2. **Post-sizing VPIN multiplier**: position size is scaled by VPIN-based multiplier (1.0 at low toxicity → 0.0 at extreme toxicity), applied after position sizing and before margin limit check

### Regime-Aware Strategy Weighting
- `CStrategyBase::GetRegimeConfidenceMultiplier()` scales confidence by regime alignment:
  - TREND_CLUSTER: 1.5x in strong trend, 0.3x in range
  - MEAN_REVERSION_CLUSTER: 1.5x in range, 0.2x in strong trend
  - STRUCTURE_CLUSTER: 1.0x (neutral)
- Applied in `GetSignal()` before returning to manager consensus

### Volatility Direction Awareness
- `GetVolatilityDirection()` classifies ATR as EXPANDING, CONTRACTING, or STABLE via ratio comparison
- `GetVolatilityDirectionMultiplier()` applies scaling: 1.2x expanding, 0.8x contracting, 1.0x stable
- Expanding volatility boosts trend/breakout confidence; contracting volatility boosts mean-reversion confidence

### Multi-Timeframe Confluence
- `IsAlignedWithHigherTF()` checks EMA50 alignment on the next higher timeframe
- Counter-trend entries filtered when higher-TF momentum opposes the signal direction
- `GetNextHigherTF()` resolves the next timeframe in the standard MT5 hierarchy

### Cross-Cluster Conflict Resolution
- `CEnterpriseStrategyManager` tracks per-cluster conviction:
  - trendClusterBuyConviction / trendClusterSellConviction
  - meanRevClusterBuyConviction / meanRevClusterSellConviction
- When trend and mean-reversion clusters oppose, the weaker cluster's conviction is subtracted (regime-weighted)
- `MathMax(0.0, ...)` guards prevent negative conviction from floating-point precision

### Conditional Diagnostic Logging
- `InpLogLevel` input (0-4) gates diagnostic verbosity:
  - 0: Silent (errors only)
  - 1: Basic (trade events)
  - 2: Normal (consensus + risk)
  - 3: Detailed (execution quality, sizing decisions)
  - 4: Verbose (all diagnostics)
- Applied in `CTradeManager`, `CPositionSizer`, and EA heartbeat paths

## AI Runtime Path
- `CNextGenStrategyBrain` now runs in a single local transformer mode; there is no runtime Python/cloud branch.
- The shared universal transformer service is now initialized at startup and remains lazy-safe for late callers, preventing registered-symbol / missing-encoder drift in the AI feature path.
- Neural online learning now separates "fit diagnostics" from "weight mutation": labeled samples can still contribute loss metrics, but weight updates remain locked until enough completed trade-linked labels exist to prevent pseudo-label-only drift.
- AI adapters avoid same-bar recomputation:
  - neural votes come from `GetNeuralSignalCached(...)`
  - transformer, ensemble, and ONNX adapters cache per-bar inference outcomes and reuse them until the bar changes
- `CNextGenStrategyBrain` and the AI adapters now source runtime features directly from the shared 55-feature `CAIFeatureVectorBuilder`, so the old `CMarketDataProcessor` wrapper is no longer in the live inference path.
- ONNX participation is manager-owned, not EA-side parallel voting: `COnnxAIStrategyAdapter` registers per symbol, consumes the embedded `Resources/model.onnx`, and can shadow-load a replacement model before promotion.
- `COnnxAIStrategyAdapter` now also loads and hot-reloads Python-exported `scaler.bin` parameters through `CPipelineScaler`, applying the same normalization contract used during offline training.
- Feature-build or inference failures are cached as `NONE` for the remainder of the bar, preventing repeated failed forward passes on unchanged data.
- Ensemble confidence is now derived from class probabilities returned by `GetPredictions(...)`, keeping the adapter path aligned with the transformer's classifier output semantics.
- AI adapters now emit explicit decision reason tags for abstain, disabled, feature-fault, inference-fault, and signal paths so consensus diagnostics can attribute AI silence without falling back to placeholder `UNTAGGED_*` buckets.
- `CAIEngine` now logs init, configuration, query lifecycle, feedback, and shutdown events under `[EXT-LLM]`, and `ProcessAdaptation()` can perform throttled external reasoning capture when the feature is enabled.
- The offline/on-disk training surface now lives in `Python/` (`data_pipeline.py`, `models.py`, `train_model.py`, `validate_model.py`), and it exports the same 55-feature / 3-class ONNX model that the runtime expects.

## Regime/Cost Pre-Gate
- `CRegimeEngine` runs before validator and can veto entries on:
  - spread-shock cooldown
  - spread/ATR ratio breach
  - late-entry z-score outlier
- **Module 7 Enhancements:**
  - Regime detection now tracks confidence (`regimeConfidence`: 0.0-1.0) and stability (`regimeStabilityBars`)
  - `confirmedState` requires 3+ consecutive bars in same state before confirming regime change
  - Prevents rapid regime flipping and reduces overfitting to noisy market data
  - Enhanced `[REGIME-STATE]` logging includes: `state`, `confirmed`, `confidence`, `stable_bars`
- The final EA admission path adds a second ATR-ratio safety contract: `ATR14/ATR50 > 2.0` rejects new trades and `> 1.5` halves proposed risk.
- `CVolatilityEngine` and `CRegimeEngine` now synthesize ATR/Bollinger inputs from raw rates when mature-series indicator buffers fault, preserving pipeline evidence instead of degrading to zero ATR context.
- `CVolatilityEngine` now includes `ValidateAtrCalculation()` for runtime ATR verification with `[ATR-VALIDATE]` telemetry.
- `UnifiedSignalPipeline` caches structural context per symbol/timeframe/bar and carries forward evidence scores:
  - `readinessScore`
  - `contextScore`
  - `costScore`
  - effective confidence floor
  - soft-threshold pass flag
- On transient warmup / handle-init / buffer-copy faults, `CRegimeEngine` can reuse a recent valid same-symbol/timeframe snapshot instead of forcing immediate neutral degradation.
- Final validator ATR acquisition now uses indicator-handle read first and raw-rate ATR as fallback, preventing `Invalid ATR: 0.00000` from re-vetoing a packet after consensus already succeeded.
- `CTrendEngine` now allows partial-readiness to proceed when the underlying series is mature, enabling MA/ATR fallback logic to attempt recovery instead of hard-failing, which reduces persistent readiness vetoes on synthetic indices where `BarsCalculated` may lag behind `Bars()`.
- Repeated regime data faults trigger bounded handle reset and retry eligibility instead of indefinite stale-handle behavior.
- Pipeline threshold adaptation now also consumes the regime snapshot, so confidence uplift/relaxation is aligned with the same market-state authority that drives the cost gate.
- Near-threshold signals may survive the pipeline when readiness/context evidence is strong; the gate remains bounded rather than becoming a blanket relaxation.
- Surviving packets keep their admitted confidence after threshold passage; readiness/context/cost remain separate downstream evidence channels instead of shaving the same packet a second time before quorum and validator.
- Gate telemetry:
  - `[REGIME-STATE]` (now includes confidence and stability metrics)
  - `[COST-GATE]`
  - `[ENTRY-VETO]`
  - `[PIPELINE-THRESHOLD]`
  - `[ATR-VALIDATE]` (new in Batch 86)

## Module 8 Python Bridge Integration
- **Batch 85 Implementation**: Complete overhaul of Python bridge reliability
  - **Connection timeout handling**: Added configurable HTTP request timeout (default 5000 ms) to `CPythonBridge`; Python server uses ZMQ poller with 5‑second timeout
  - **Reconnection logic with exponential backoff**: Implemented `AttemptReconnect()` with backoff from 2 s to max 30 s, configurable max attempts
  - **Heartbeat monitoring**: Periodic heartbeat checks via `/heartbeat` endpoint, configurable interval, tracks last heartbeat timestamp
  - **Local fallback mode**: If Python server is unavailable, bridge automatically falls back to local AI mode to avoid runtime failures
  - **Message serialization validation**: Added JSON structure validation before response parsing to prevent corrupted data issues
  - **Version compatibility check**: Added `/version` endpoint to Python server (returns `1.0.0`), bridge validates compatibility during `OnInit()`
  - **Health monitoring dashboard**: Real-time telemetry via `[PYTHON-BRIDGE-DASHBOARD]` with connection state, version, and request stats (total, success, error counts)
  - **HTTP server integration**: Added FastAPI HTTP server on port 8000 to `Python/zmq_server.py` (since MQL5 lacks native ZMQ support), endpoints:
    - `POST /predict`: Get predictions from ensemble/dual-adapt/maml-ppo models
    - `GET /health`: Check server health
    - `GET /heartbeat`: Periodic heartbeat
    - `GET /version`: Get version info
  - **Input parameters**: Added to `MultiStrategyAutonomousEA.mq5` for endpoint, timeout, heartbeat interval, max reconnect attempts, and backoff duration

## Visualization System Audit Fixes (Batch 90)
- **Batch 90 Implementation**: Complete overhaul of chart object management and visualization safety:
  - **Fixed hardcoded chart ID**: StrategyUnifiedICT used chart ID 0, causing cross-chart contamination; added `m_chartID` member initialized with `ChartID()`
  - **Standardized drawing pattern**: StrategyUnifiedICT now uses `CChartDrawingManager` methods (`DrawOrderBlock`, `DrawFVG`) instead of direct MT5 API calls; StrategyFibonacci now uses `DrawHorizontalLevel`
  - **Global object counter**: Added `m_globalObjectCount`, `m_lastAlertLevel`, `m_lastCountLogTime` to `CDrawingCoordinator`; tiered alerts at 800 (warning), 900 (critical), 950 (emergency)
  - **Periodic cleanup**: Reduced `maxObjectAge` from 500 to 150 bars; added 5-minute cleanup interval in StrategyUnifiedICT::OnTick calling `CleanupOldObjects()`; StrategyFibonacci and StrategySupportResistance also call periodic cleanup
  - **Debug logging**: Wrapped debug logging in `CChartDrawingManager` behind `m_config.enableDebugMode` flag
  - **Color consistency**: Replaced bitwise OR color operations with explicit RGB values
  - **Coordinate validation**: Added `ValidateTime`, `ValidatePrice`, and `ValidateCoordinates` methods; validates time > 0, time <= current + 1 day, price > 0, reasonable price ranges
  - **Safe deletion**: Added `SafeObjectsDeleteAll` with verification of deletion counts and discrepancy logging
  - **Per-strategy limits**: Added per-strategy object limit enforcement with `maxObjectsPerStrategy`
  - **Dirty-flag optimization**: Added `m_isDirty`, `SetDirty`, `IsDirty`, `ShouldRedraw` for performance optimization
  - **Statistics dashboard**: Integrated drawing statistics into `VisualDashboard` showing global/per-strategy counts, alert level

- **Telemetry additions**:
  - `[DRAWING-STATS]`: Periodic drawing statistics logging
  - `[DRAW-COORD]`: Drawing coordinator telemetry
  - Drawing statistics panel on VisualDashboard

## Risk Hardening
- **Module 4 Risk Management Fixes (Batch 85):**
  - Critical risk constants corrected: `MAX_RISK_PER_TRADE` (100.0 → 2.0%), `MAX_TOTAL_RISK` (100.0 → 10.0%)
  - Safe default risk limits: 2% per trade, 6% daily, 10% portfolio when config values are invalid
  - Currency-aware position sizing via `CPositionSizer::CalculateRiskPerLot()` conversion
  - 20% margin buffer (uses max 80% of free margin) for volatile period safety
  - Volatility adjustment uses minimum price threshold to prevent exaggerated ratios on low-priced symbols
  - Enhanced emergency drawdown stop with volatility checks and warnings
- Daily budget gate uses effective daily risk:
  - max(executed entry risk, mark-to-market equity loss from daily baseline, current open portfolio stop risk).
- Any open position without stop-loss protection is treated as a hard veto state.
- Runtime performs deterministic unprotected-position remediation (restore SL, then force-close EA-owned positions after bounded failed attempts).
- Risk validation remains two-phase (`pre-size`, `post-size`) through unified authority.
- Lot sizing is now drawdown-adaptive before the post-size recheck: `CAIStrategyOrchestrator::GetDrawdownMultiplier()` tapers size against peak-equity drawdown, and the adjusted size still must pass `CUnifiedRiskManager`.
- Operator telemetry now splits daily budget components: `entry`, `mtm`, `open_exposure`, `effective`.
- Risk gate now enforces cluster governance:
  - same-symbol opposing-cluster mutex
  - max concurrent positions per cluster
  - max projected cluster risk cap
- Portfolio correlation fallback uses bounded value (0.65, capped to `m_maxCorrelation`) when correlation data is unavailable, avoiding hard blocks while preserving safety
- Recommended per-trade risk is now progressively throttled as daily and portfolio utilization rise, producing `[RISK-THROTTLE]` before the final hard-cap path is reached.

## Risk Enhancement (Batch 97)

### Tiered Correlation Response
- `CUnifiedRiskManager` now applies a two-tier correlation response:
  - `correlationReduceThreshold` (default 0.4): position size reduced proportionally
  - `correlationBlockThreshold` (default 0.7): trade blocked entirely
- Replaces previous binary block-at-threshold behavior with graduated response

### Daily P&L Loss Limit
- `dailyLossLimitPercent` circuit breaker in `CUnifiedRiskManager`
- `CheckDailyLossLimit()` evaluates daily realized + unrealized loss against threshold
- `m_dailyLossHaltActive` state prevents new entries until the next trading day
- Resets at configurable `m_tradingDayStartHour` (default 0) for broker-consistent daily boundaries

### Kelly Criterion Position Sizing
- `POSITION_SIZE_KELLY` mode (enum value 5) in `CPositionSizer`
- `CalculateKellyFraction()`: half-Kelly fraction with 25% cap, computed from recent trade history win rate and avg win/loss ratio
- `CalculateCompoundingMultiplier()`: sqrt upside / linear downside scaling for asymmetric compounding

### Mandatory SL Gate
- `CTradeManager::ExecuteMarketOrder()` rejects any trade with `stopLossPips <= 0.0`
- Enforces stop-loss protection at the execution layer, complementing risk-level validation

### Min R:R Enforcement
- Default minimum R:R of 1:2 applied to all clusters
- MEAN_REVERSION_CLUSTER uses 1:5 minimum
- Signals below threshold rejected before risk sizing

### Portfolio Profit Target
- `InpDailyProfitTargetPercent`: daily profit target as percentage of starting equity
- `InpProfitTrailFactor`: trailing floor factor — once target reached, new entries halt but floor trails up with profit
- Existing positions remain managed (trailing, breakeven, etc.) during profit halt

### Auto Mode Switching
- `InpEnableAutoModeSwitch`: enables automatic risk mode switching
- Three modes: CONSERVATIVE, AGGRESSIVE, EMERGENCY
- Switching triggers: drawdown percentage and consecutive win streak
- Each mode has configurable risk parameters (`InpConservativeBaseRiskPct`, `InpAggressiveBaseRiskPct`, `InpModeSwitchDrawdownPct`, `InpModeSwitchWinStreak`)

## Execution Hardening
- Fill policy is configurable via EA input (`IOC` default).
- Market sends are synchronous by default.
- Transient retcodes use bounded retry with immediate refresh/reprice instead of sleep-based blocking.
- `LOCKED`/`FROZEN` retcodes use single bounded retry to avoid prolonged retry loops.
- Market orders rebuild execution price and protective stops at submit time.
- Protective stop modifications are throttled; the cooldown bypass is limited to missing stop-loss protection.
- Position lifecycle management is magic-filtered so `CTradeManager::ManageAllPositions(...)` does not modify unrelated manual or external positions.
- SELL breakeven moves to normalized entry price instead of above entry, and trailing stops require meaningful profit before tightening.
- Symbol scan order rotates each cycle to reduce first-symbol concentration when only one trade is allowed per cycle.
- The runtime no longer executes the first valid symbol blindly; it stages `[SCAN-CANDIDATE]` entries, sorts them, and emits ranked `[SCAN-DECISION]` attempts up to `InpMaxTradeSendsPerCycle`.
- `TradeManager` emits `[EXECUTION-RECEIPT]` with requested/fill size, retcode, request id, and retries; partial fills emit `[FILL-DIFF]`.
- `TradeManager` also emits `[EXECUTION-TELEMETRY]` with broker request/fill price, slippage points, and round-trip latency; the EA mirrors that into `[TRADE-EXECUTION]`.
- `UnifiedRiskManager` registers executed risk using fill ratio so daily risk usage matches actual exposure.

## Diagnostics
- Startup affordability emitted as `[ACCOUNT-CAPACITY]`.
- Startup cooldown recovery emitted as `[TRADE-STATE]`.
- Weighted quorum evaluation emitted as `[CONSENSUS-QUORUM]`.
- Post-quorum nullification emitted as `[CONSENSUS-VETO]` when timeframe consistency or intrabar single-voter safety clears a candidate.
- Per-evaluation contributor trace emitted as `[CONSENSUS-ACTIVE]`, listing active, voted, raw-none, filtered, and suppressed strategies for the current symbol evaluation.
- Sparse-admission success emitted as `[CONSENSUS-SPARSE]`; near-miss sparse/full-quorum failures emitted as `[CONSENSUS-NEARMISS]`.
- Scheduler budget and per-symbol backoff are emitted as `[SCAN-BUDGET]` and `[INTRABAR-BACKOFF]`.
- `[SCAN-BUDGET]` now includes `pending_newbar`, `selected_newbar`, `deferred_newbar`, `eval_budget`, and `intrabar_budget` so deferred-work pressure is visible from the log.
- Startup/runtime priming emits `[SCAN-PRIME]`, and cadence overrides emit `[CADENCE-WARNING]` when global new-bar-only mode suppresses otherwise-live intrabar policy.
- Scheduler repair emits `[SCHEDULER-STATE]` so silent cadence-array drift is visible immediately in the runtime log.
- Ranked approved candidates emitted as `[SCAN-CANDIDATE]`.
- Ranked cycle execution attempts emitted as `[SCAN-DECISION]`; per-cycle totals emitted as `[SCAN-DECISION-SUMMARY]`.
- Mode-filtered indicator absence emitted as `[MODE-MASK]`.
- External LLM lifecycle and reasoning emitted as `[EXT-LLM]`.
- Adaptive-training summary emitted as `[AI-FEEDBACK]`.
- Neural online-learning mutation gate state emitted as `[NN-MUTATION]`.
- Pre-cap pressure-based risk reduction emitted as `[RISK-THROTTLE]`.
- Consensus reason counters emitted as `[CONSENSUS-DIAG]`:
  - `raw_none`
  - `filtered_out`
  - `quorum_failed`
  - `intrabar_not_eligible`
- Startup execution posture emitted as `[EXECUTION-MODE]`.
- Confirmed deal lifecycle emitted as `[TRADE-CONFIRMED]`.
- Entry-suppressed approved signals emitted as `[ENTERPRISE-BLOCKED]`.
- Consensus dominant-cause attribution emitted as `[CONSENSUS-ROOT]`.
- Strategy-level none-reason attribution emitted as `[CONSENSUS-STRATEGY]`.
- Heartbeat aggregate consensus snapshots emitted as `[CONSENSUS-SNAPSHOT]`.
- **Detailed veto diagnostics** (Batch 41): consensus veto messages now explain the exact failure reason with concrete values:
  - `no_voters`: "No strategies produced votes in this evaluation cycle"
  - `insufficient_quality`: "quality=0.15 (need 0.40) | votes=1 | support=0.25" (shows actual vs required, voter count, support ratio)
  - `insufficient_support`: "support=0.25 (need 0.30) | votes=2 | quality=0.48" (shows actual vs required, voter count, quality)
  - `insufficient_readiness_weight`: "readyWeight=2.15 < minRequired=3.25" (shows ready vs minimum required weight)
  - `direction_quorum_not_met`: "buy=0.48|0.25 vs sell=0.52|0.30" (shows buy/sell quality and support for comparison)
  - Eliminates guesswork by always printing the numeric mismatch and failing condition
- Heartbeat aggregate strategy reject buckets emitted as `[STRATEGY-REJECTS]`.
- Confidence-threshold source emitted as `[PIPELINE-THRESHOLD]` with tags:
  - `REGIME_RANGE`
  - `REGIME_TREND_RELAX`
  - `REGIME_BREAKOUT_RELAX`
  - `REGIME_CHAOS`
  - `REGIME_ENGINE_WARMUP`
- Runtime conversion tracking emitted as `[HEARTBEAT-FUNNEL]` and `[CONVERSION-RATES]`.
- Prolonged no-signal dominance alert emitted as `[NO-SIGNAL-ALERT]`.
- Regime transient-fault reuse and repeated-fault reset are emitted under `[REGIME-STATE]`.
- No-vote scans now preserve aggregate readiness/context/cost from the ready live pool instead of zeroing those fields after consensus has already measured them.
- Trend indicator mature-series readiness faults and bounded set reinitialization are emitted under `[TrendEngine][READINESS-FAULT]`.
- Strategy-governance telemetry emitted as `[CONSENSUS-ROLE]`, `[CONSENSUS-CLUSTER]`, and heartbeat `[ROLE-CLUSTER]`.
- Cluster risk telemetry emitted as `[RISK-CLUSTER]` and `[RISK-MUTEX-BLOCK]`.
- Risk budget decomposition: `[RISK-BUDGET]`
- Unprotected remediation lifecycle: `[RISK-UNPROTECTED]`
- External position capacity blocks: `[CAPACITY-EXTERNAL]`
- Execution receipt telemetry: `[EXECUTION-RECEIPT]`, `[FILL-DIFF]`
- Execution latency/slippage telemetry: `[EXECUTION-TELEMETRY]`, `[TRADE-EXECUTION]`
- Per-scan no-trade attribution: `[SCAN-NO-TRADE]`
- Risk-budget sizing caps: `[RISK-CAP]`
- `[SIGNAL-VALIDATED]` now reports `exogenous_quality` separately from consensus confidence so logs distinguish manager admission from validator market-sanity pass.
- Execution preflight and ambiguous broker responses: `[EXECUTION-BLOCKED]`, `[EXECUTION-UNCONFIRMED]`
- `[COST-GATE]` now prints both raw spread/ATR values and the ratio so tiny non-zero spread conditions are distinguishable from true zero-cost states.
- Duplicate component-local `SignalDiagnostics` sinks have been removed from Elliott, pipeline, and orchestrator paths; manager/runtime logs are the authoritative observability surface.
- **Batch 99 log signatures:**
  - `[S/R-LOT-DEFERRED]` — S/R lot validation deferred to risk manager
  - `[CONSENSUS-TREND-BIAS]` — Trend bias raising quorum
  - `[ONNX-CPU-FALLBACK]` — ONNX using CPU instead of CUDA
  - `[AI-CALIBRATION-WARNING]` — Degenerate AI model detected
  - `[SCALP-LOT-CAPPED]` — Scalp lot capped by margin
  - `[SCALP-LOT-MIN]` — Scalp lot below minimum
  - `[SCALP-COST-REJECTED]` — Scalp cost too high
  - `[SCALP-COST-OK]` — Scalp cost viable
  - `[HYBRID-GATE-RELAXED]` — AI threshold lowered
  - `[HYBRID-GATE-RESTORED]` — AI threshold restored
  - `[RISK-BUDGET-PNL-ADJUSTED]` — Risk budget adjusted by P&L
  - `[KELLY-ADJUSTMENT]` — Bayesian Kelly lot adjustment
  - `[EQUITY-CURVE-BELOW]` — Equity below EMA
  - `[EQUITY-CURVE-ABOVE]` — Equity above EMA
  - `[CVAR-RECORD]` — Trade return recorded for CVaR
  - `[CVAR-CHECK]` — CVaR limit check
  - `[ASYNC-TRADE-SENT]` — Async trade submitted
  - `[ASYNC-TRADE-CONFIRMED]` — Async trade confirmed
  - `[ASYNC-TRADE-TIMEOUT]` — Async trade timed out
  - **Batch 100 log signatures:**
  - `[SPIKE-HUNT-DETECTED]` — 3-layer spike confluence detected on synthetic symbol
  - `[SPIKE-HUNT-TRADE]` — Spike trade opened with independent magic number
  - `[SPIKE-HUNT-SKIP]` — Spike detection failed confluence threshold
  - `[SPIKE-HUNT-ALERT]` — Push notification sent for spike detection
  - `[SPIKE-HUNT-ALERT-THROTTLED]` — Push alert suppressed by 120s throttle
  - `[SPIKE-COOLDOWN]` — Long-term entry delayed by spike cooldown
  - `[SPIKE-HUNTER-STATS]` — Periodic spike hunter statistics
  - `[SPIKE-HUNT-ENGINE]` — Spike hunter engine lifecycle events
  - **Batch 101 log signatures:**
    - `[SIGNAL-REJECTED] reason=ofi_contradiction` — OFI signal contradicts consensus direction
    - `[VPIN-BLOCK]` — VPIN extreme toxicity blocking new position
    - `[HURST-WEIGHT]` — Hurst weight modifier applied to strategy weights
    - `[OU-ZSCORE]` — OU-adjusted z-score blended in StatisticalArbitrageStrategy
    - `[OFI-SIGNAL]` — OFI proxy engine signal output
  - **Batch 102 log signatures:**
    - `[PROFILER-DETECT]` — Deriv family auto-detection result per symbol
    - `[GRID-RECOVERY-ENTRY]` — Grid recovery level entry
    - `[GRID-RECOVERY-LEVEL]` — Grid level progression detail
    - `[GRID-RECOVERY-CLOSE]` — Grid recovery position close
    - `[GRID-RECOVERY-DRAWDOWN]` — Grid drawdown cap reached
    - `[ATR-SCALP-ENTRY]` — ATR scalp trade entry
    - `[ATR-SCALP-EXIT]` — ATR scalp trade exit
    - `[ATR-SCALP-SPIKE-WINDOW]` — ATR scalp skipped due to spike window
    - `[ATR-SCALP-COOLDOWN]` — ATR scalp cooldown active
    - `[HEARTBEAT-FAMILY]` — Per-family engine status in heartbeat
  - **Batch 102 Python ML Stack log signatures:**
    - `[PYTHON-BRIDGE-DASHBOARD]` — Bridge state with family routing info (existing, now includes family_id when available)
  - **Batch 103 Enterprise Vision log signatures:**
    - `[CANDLE_CONFLUENCE]` — Candlestick confluence score details
    - `[MR-HURST-NOT-MEAN-REVERTING]` — Mean Reversion rejected (Hurst < 0.45)
    - `[MR-STOCH-NOT-EXTREME]` — Mean Reversion rejected (Stochastic not at extreme)
    - `[MR-BB-WIDTH-HIGH]` — Mean Reversion rejected (BB width above 20th percentile)
    - `[MR-DIVERGENCE-DETECTED]` — Mean Reversion rejected (price/indicator divergence)
    - `[STATARB]` — Statistical Arbitrage signal details
    - `[TTM_SQUEEZE]` — TTM Squeeze detection status
    - `[BREAKOUT_RETEST]` — Breakout retest entry confirmation
    - `[BREAKOUT_FAILURE_REVERSAL]` — Failed breakout reversal signal
    - `[CONSENSUS-SCORE]` — 0-100 consensus scoring result
    - `[VPIN-HIGH]` — VPIN high toxicity reducing strategy weights
    - `[VPIN-MEDIUM]` — VPIN medium toxicity reducing strategy weights
    - `[OFI-REGIME-BOOST]` — OFI aligned with regime, weight boost applied
    - `[OFI-REGIME-PENALTY]` — OFI contradicts regime, weight penalty applied

## Batch 102 Python ML Stack: Family-Aware Prediction Routing

### Decision Flow: MQL5 → Python → MQL5

```
1. Strategy/Engine calls GetFamilyPrediction(symbol, features[], size)
2. DetectFamilyId(symbol) → family_id (0-17) or -1
3. CPythonBridge::PredictFamily(features, size, family_id, symbol)
4. JSON payload: {"features":[...], "mode":"ensemble", "family_id":N, "symbol":"..."}
5. Python server receives /predict request
6. If family_id >= 0 and family_models[family_id] loaded:
   a. _predict_family(features, family_id, mode)
   b. Dynamic seq_len: 120 for Jump/DEX, 60 otherwise
   c. Dynamic feat_count: 83 for Deriv families
   d. ONNX inference → onnx_buy, onnx_sell
   e. GBDT inference (catboost/xgboost/lgbm) → {model}_buy, {model}_sell
   f. Stacking inference (if stacker available) → stacker_signal
   g. Return: {family_id, family_name, buy_prob, sell_prob, hold_prob, onnx_*, catboost_*, xgboost_*, lgbm_*, stacker_signal}
7. Else: fallback to universal model (57 features, seq_len=60)
8. MQL5 ParsePredictionResponse() → SPythonBridgeResponse with all fields
9. Response available for strategy voting integration (future)
```

### Feature Engineering Decision

```
Is symbol a Deriv synthetic? ──Yes──→ family_id = DetectFamilyId(symbol)
       │                                    │
       No                                   family_id >= 0?
       │                                    │         │
       ▼                                   Yes        No (unknown synthetic)
  Universal pipeline                  Deriv pipeline   │
  57 features                         83 features      ▼
                                      (57 + 8 signal   Universal pipeline
                                       + 18 one-hot)   57 features
```

### Training Script Selection

```
For each family_id (0-17):
  1. train_model.py --family-id N → {prefix}_patchtst.onnx
  2. train_deriv_catboost.py --family-id N → {prefix}_catboost.pkl
  3. train_deriv_xgboost.py --family-id N → {prefix}_xgboost.pkl
  4. train_deriv_lgbm.py --family-id N → {prefix}_lgbm.pkl
  5. train_deriv_stacker.py --family-id N --catboost-pkl ... --xgboost-pkl ... → {prefix}_stacker.pkl
```

## 2026-03-25 Decision-Path Refinement
- Same-bar structural cache reuse now preserves original engine readiness rather than forcing later scans to assume all engines are ready.
- Structural context reads are fail-soft:
  - ready engine => consume current/reused getters
  - not-ready engine => consume neutral defaults and lower readiness score
- Candidate construction now happens under a capped risk budget from `CUnifiedRiskManager`, so sizing aligns with remaining daily/portfolio headroom before post-size veto.
- Live execution success now requires a confirmed fill retcode or bounded history confirmation; a raw broker `Buy/Sell(...) == true` no longer qualifies on its own.

## 2026-03-31 AXIOM Runtime Refactor
- Optional AI bootstrap now degrades cleanly:
  - NextGen brain failure disables dashboard AI status only
  - orchestrator failure disables adaptation/weight sync only
  - AI engine failure disables adaptive engine processing only
- AI hot paths are now allocation-stable and bar-cached:
  - NextGen market data uses a ring buffer
  - uncertainty and NN training histories use ring buffers
  - transformer/ensemble/NN votes run once per bar instead of once per tick
- Clean detector ATR paths now reuse cached handles during repeated detection passes rather than creating indicator handles inside hot loops.

## 2026-04-01 Default Runtime Efficiency Path
- Baseline interpretation step:
  - `default.log` proved that saved MT5 runtime state can diverge from source defaults
  - operators should confirm `[EXECUTION-MODE]` and `[CADENCE-CONFIG]` before treating a run as a default baseline
- Trend-readiness path:
  - indicator handles available
  - ATR buffer read succeeds => normal trend/regime evidence
  - ATR buffer read fails but bounded fallback succeeds => degraded-but-valid evidence with readiness-state logging
  - fallback fails => reuse/neutral path with explicit degradation, not silent false-ready voting
- Scan-loop path:
  - detect new-bar work
  - compute intrabar selections
  - emit `[SCAN-BUDGET]` with `active_work`
  - if `active_work=false`, skip the symbol loop and attribute the idle cycle
  - otherwise continue through consensus -> validator -> risk -> execution
- Governance path:
  - `Support/Resistance` intrabar toggle now preserves probe semantics in manager governance logs and runtime behavior

## 12. 2026-03-30 Unified ICT Integration
- `StrategyUnifiedICT` pipeline replaces the prior counting gate with `ScoreConfluences(...)` (max 130 weighted points).
- Confidence limits are dynamically set by `ComputeEntryConfidence(...)` using MS Break type (CHoCH vs BOS) and `CAMDDetector` Distribution sweeps.
- Final entry `SICTEntrySetup` carries partial close sizes (`lot1Pct`, `lot2Pct`, `lot3Pct`) ready for the executor.
- Stop losses are automatically pushed to `breakevenPrice` when TP1 hits an opposing structural CE (Consequent Encroachment) defined by `CalculateTakeProfits(...)`.
- `CICTPositionSizer` injects localized risk-per-trade guard checks tied to dynamic equity-balance drawdowns.

## 13. 2026-03-30 Support/Resistance & Trendline Overhaul
- **Look-Ahead Blocking**: `CTrendEntryTypes`, `CSRBounceStrategy`, and `CSRBreakoutStrategy` evaluate historical and live signals explicitly against `bar[1]` (confirmed-bar completion) to prevent pseudo-signals drawn from open repainting wicks.
- **Dynamic Array Sorting**: Visual indicators emitted by `DrawLevels()` and `DrawTrendlines()` are governed by an internal strength-sorted bubble algorithm, isolating system rendering strictly to the most statistically resonant boundaries.
- **Explicit ATR Targeting**: Takes priority over fixed pips across `CADXPositionSizing` and strategy mappers. Position lot sizing explicitly resolves absolute market Tick Distance formulas against equity risk rather than arbitrary percentages.

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
- All scalp entries must pass `CUnifiedRiskManager` pre-trade gating (same as non-scalp entries).
- `CTradeManager` rejects any trade without a valid stop-loss (`stopLossPips <= 0.0`).
- Scalp signal cache handles are sourced exclusively from `CIndicatorManager::Instance()`.
- Removed strategy families are not represented in runtime registration paths.
- Unified ICT runtime labeling is normalized (no legacy `Unified ICT/SMC` path labels).

## Fast Debug Read Order
1. `[ACCOUNT-CAPACITY]` / `[TRADE-STATE]`
2. `[HEARTBEAT]`
3. `[HEARTBEAT-FUNNEL]` / `[CONVERSION-RATES]`
4. `[CONSENSUS-QUORUM]` / `[CONSENSUS-VETO]` / `[CONSENSUS-DIAG]` / `[CONSENSUS-ROOT]` / `[CONSENSUS-STRATEGY]`
5. `[CONSENSUS-SNAPSHOT]` / `[STRATEGY-REJECTS]`
6. `[PIPELINE-THRESHOLD]` / `[REGIME-STATE]` / `[TrendEngine][READINESS-FAULT]`
7. `[SIGNAL-REJECTED]`
8. `[RISK-BUDGET]`
9. `[RISK-UNPROTECTED]` / `[CAPACITY-EXTERNAL]` / `[RISK-VIRTUAL]`
10. `[AI-VOTE]`
11. `[NO-SIGNAL-ALERT]`
12. `[SHADOW-TRADE]` or `[TRADE-SUCCESS]/[TRADE-ERROR]` plus `[TRADE-EXECUTION]` / `[EXECUTION-TELEMETRY]` for live-send broker details

## 2026-04-01 Strategy Registry + AI Runtime Flow
- Startup now includes a registry-resolution stage before manager bootstrap:
  - build curated indicator roster
  - overlay AI availability
  - resolve `InpEAMode` to an effective mode
  - emit `[STRATEGY-REGISTRY]`
- Manager bootstrap now registers strategies from the registry roster instead of separate indicator vs AI branches.
- Candidate path now includes a mode-admission checkpoint between consensus and risk:
  - invalid mode/family combinations are rejected before risk sizing
  - `AI_ASSISTED` can add `[AI-MODE-BONUS]` to aligned indicator-primary candidates
- Hybrid cadence now has a bounded keepalive branch when primary intrabar scheduling yields zero selected symbols:
  - `[SCAN-BUDGET] ... intrabar_keepalive=true`
- Trend readiness path now distinguishes:
  - handle invalid
  - insufficient chart history
  - partial indicator readiness
  - MA manual fallback
  - ATR manual fallback
  - snapshot reuse

### Validation Off-Hours Overrides (2026-04-08)
- Synthetic Expansion: The pipeline incorporates PainX, SFX Vol, GainX, FX Vol, and FlipX as intrinsic 24/7 instruments within IsSyntheticSymbol, explicitly overriding MT5 session blocks and enabling non-stop execution logic for emergent indices.

- Batch 73 update:
  - `Unicorn Model` and `Power of Three` now enter the same manager-owned consensus path as other indicator strategies.
  - `StrategyUnifiedICT` now applies recent opposite-CISD vetoes before admission and adds CISD as a positive confluence score.

- Batch 79 update:
  - Account floor in `RiskValidationGate` lowered to `$1.00` to support $10 micro-account testing.
  - Runtime `maxRiskPerTradePercent` set to `100.0` to permit aggressive overrides when necessary.
  - Environment alignment for Weltrade MT5 installation in build/sync pipeline.
