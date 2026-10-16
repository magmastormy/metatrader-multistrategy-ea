# Runtime Decision Graph

## Document Metadata
- Last Updated: 2026-10-09
- Last Architecture Sync: 2026-08-23
- Scope: Runtime signal-to-execution flow
- Source: `Core/Orchestration/EAOrchestrator.mqh`
 - Current Batch: 170

## Purpose
Defines the authoritative runtime decision path and ownership boundaries between signal generation, validation, risk veto, execution, and post-trade feedback.

## Ownership Map
- Orchestration: `Core/Orchestration/EAOrchestrator.mqh` (primary) → thin EA entry point `MultiStrategyAutonomousEA.mq5`
- **Testing EA**: `MultiStrategyTestingEA.mq5` — Standalone testing entry point with Complete Test Profile System (45 profiles)
- Registry Access: `CRegistryAggregator` (unified access to mathematical, institutional, neural net, drawing, scan, symbol state, strategy registries)
- Magic Number Allocation: `Core/Utils/MagicRange.mqh` (single authority; `CMagicNumberAllocator` deleted in Batch 197 - a parallel offset table with no call site)
- Fast-Path Tick Processing: inline in `EAOrchestrator` (`ProcessTickSafetyLoop`; TickProcessor.mqh deleted in Batch 151 - zero callers)
- Heavy Timer Processing: inline in `EAOrchestrator` (`OnTimer` -> `ProcessTradingLogic`; TimerProcessor.mqh deleted in Batch 151 - zero callers)
- Signal Generation: `Core/Orchestration/SignalGenerator.mqh`
- Multi-Tier Validation: `Core/Orchestration/SignalValidator.mqh`
- Candidate Building: `Core/Orchestration/CandidateBuilder.mqh`
- Trade Execution: `Core/Orchestration/TradeExecutor.mqh`
- Live Authority Resolution: `Core/Orchestration/LiveAuthorityResolver.mqh`
- Consensus: `CEnterpriseStrategyManager` (per-symbol)
- Filtering: `CUnifiedSignalPipeline`
- AI adaptation/weights: `CAIEngine` + symbol-scoped AI adapters (implementing `IAIStrategy`)
- AI modules:
  - `CNeuralCore` - Core activations, loss functions, gradients
  - `CNeuralTrainingDataManager` - Training examples and barrier buffer
  - `CNeuralCheckpointManager` - Atomic checkpoint operations
  - `CSymbolEmbedding` - Learnable symbol embeddings in transformer
- Risk veto: `CUnifiedRiskManager`
- Execution: `CTradeManager`
- Position lifecycle: `CPositionLifecycleManager` (via EAOrchestrator loop) + `CTradeManager::ManageAllPositions(...)` + `Core/Position/PositionManager.mqh`
- Indicator cache lifecycle: `CIndicatorManager`
- Python bridge integration: `CPythonBridge` in `Core/Utils/PythonBridge.mqh`
- Shared engine & scalability: `CSharedEngineManager` (Batch 91)
- Error aggregation & verbosity: `CEnhancedErrorHandler` (enhanced in Batch 91)
- Bar processing & multi-timeframe: inline per-symbol bar gating in `EAOrchestrator::ProcessNewBars` via `CScanSchedulerRegistry` (BarProcessor.mqh deleted in Batch 151 - zero callers)
- Scalping engine: `CFastScalpEngine` + `CScalpSignalCache` (Batch 97)
- Scalp signal rules in `CFastScalpSignal` (the three scalp *strategy* classes Batch 97 documented were never all three real - see Scalping Fast Path, corrected Batch 216)
- Position lifecycle: `CPositionLifecycleManager` (Batch 98)
- Diagnostics/heartbeat: `CDiagnosticsManager` (Batch 98)
- Unprotected position tracking: `CUnprotectedPositionTracker` (Batch 98)
- Synthetic spike monitoring: `CSyntheticSpikeMonitor` (Batch 98)
- Trade attribution: `CTradeAttributionManager` (Batch 98)
- Symbol scan scheduling: `CScanSchedulerRegistry` (Batch 121)
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
- Compounding tier manager: `CCompoundingTierManager` (Batch 106)
- Family strategy weight matrix: `CFamilyStrategyWeightMatrix` (Batch 106)
- Session weight manager: `CSessionWeightManager` (Batch 106)
- Skew step analyzer: `CSkewStepAnalyzer` (Batch 106)
- Per-family position limits: `CUnifiedRiskManager` family position check (Batch 106)
- ADX lot modifier: `CADXLotModifier` in position sizer chain (Batch 106)
- **Batch 121 Registries**: `CMathematicalEngineRegistry`, `CInstitutionalEngineRegistry`, `CNeuralNetRegistry`, `CDrawingManagerRegistry`, `CScanSchedulerRegistry`, `CSymbolStateTracker`
- **Batch 122 Orchestration**: `EAOrchestrator`, `CTickProcessor`, `CTimerProcessor`, `SignalGenerator`, `SignalValidator`, `CandidateBuilder`, `TradeExecutor`, `LiveAuthorityResolver`, `PositionManager`, `StrategyFactory`

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
  
  %% Pipeline Filter Chain (Layer 4 - Batch 129)
  %% Filter execution order is configurable via SignalFilterSettings.order.filterOrder[]
  %% Default order: RegimeCostGate -> Trend -> Volatility -> Liquidity -> Structure -> Time -> Session
  %% Each filter can be enabled/disabled via grouped settings:
  %% - regimeCostGate.enabled (RegimeCostGateSettings)
  %% - trend.enabled (TrendFilterSettings)
  %% - volatility.enabled (VolatilityFilterSettings)
  %% - liquidity.enabled (LiquidityFilterSettings)
  %% - structure.enabled (StructureFilterSettings)
  %% - session.enableTimeFilter (SessionFilterSettings)
  %% - session.enableSessionFilter (SessionFilterSettings)
  %% Early-exit on first filter failure, disabled filters are skipped entirely
  
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
  V --> VC[CVaR tail-risk veto gate ACTIVE - IsCVaRLimitExceeded checked in pipeline pre-approval, reservation released on reject; minute-gated UpdateEquityCurve fed from RefreshRuntimeState Batch 151]
  VC --> W{Pass?}
  W -->|No| T
  W -->|Yes| X[Reserve virtual risk and stage approved candidate - Batch 151: reservation books provisional risk then syncs final adjusted risk]

  X --> X1{More symbols?}
  X1 -->|Yes| E4
  X1 -->|No| X2[Sort approved candidates by ranking]
  X2 --> X2A[Resolve LIVE-AUTHORITY and authority risk scale]
  X2A --> X2B[Register/maintain authority forward trials]
  X2B --> X2C[Walk ranked list up to InpMaxTradeSendsPerCycle]
  X2C --> X3{Global shadow or candidate lacks live authority?}

  X3 -->|Yes| Y[Log AUTHORITY-REJECT + AUTHORITY-TRIAL]
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
- `SScalpIndicatorCache` struct (trimmed in Batch 216): `emaFast/emaFastPrev/emaSlow/emaSlowPrev`, `atrValue`, `rsiValue`, tick-level `spreadPoints`, `lastBarTime`, `isValid`, four handle references. Its former BB/ADX/volume/ATR-history fields were computed per symbol per bar and read by nobody.
- `CScalpSignalCache` class: fixed-size array for 20 symbols
- `UpdateOnNewBar()`: CopyBuffer path (runs only on new bar formation)
- `UpdateTickValues()`: SymbolInfoDouble-only path (runs every tick, minimal computation)
- All handles sourced from `CIndicatorManager::Instance()` singleton
- `isValid` covers only `emaFast / emaSlow / atrValue`, so a failed RSI or ADX copy leaves `0.0` in a field a
  consumer may test as a reading. Since Batch 214 the BUY/SELL RSI check refuses at `rsiValue <= 0.0` rather
  than reading "no data" as "not overbought".
- `CFastScalpIndicators` (the slow path's one-slot ATR/RSI cache) commits only after all its reads succeed:
  a partial write would leave one symbol's values tagged as another's, and the new-bar test cannot tell.

### Async Order Execution
- `InpScalpAsyncMode`: enables `OrderSendAsync()` for scalp entries
- `SScalpPendingAsync` struct tracks async order state
- `OnAsyncOrderSent()` / `OnDealConfirmed()` callbacks for order lifecycle
- `CheckPendingAsyncOrders()` timeout handling via `InpScalpMaxLatencyMs`
- `OnTradeTransaction()` routes scalp async confirmations to `CFastScalpEngine`

### Scalp Strategies - no strategy object is on this path (corrected in Batch 216)
The three bullets this section used to carry (`ScalpMomentum`, `ScalpSpread`, `ScalpVolatilityBreakout`) describe
classes two of which have no file in the repository and one of which is not `#include`d by anything, so none of
them is in the binary. The live fast-scalp entry rule is `CFastScalpSignal::EvaluateFromCache` /
`EvaluateSlowPath`: M1 EMA 5/13 crossover, RSI(7) not at its OB/OS limit, spread <= 0.30 x ATR, then
`CFastScalpSizing` for confidence and `CFastScalpEntry::ValidateRiskAndAdjust` for the single pre-trade gate call.
`SScalpConfig` carries those five numbers; `SetScalpSetup`'s `setupType` (0=none, 1=momentum, 2=spread,
3=breakout) was the ghost of the three-strategy design and is deleted in Batch 216 - nothing read it.

- Manager consensus resolves mixed-timeframe conflicts via `TimeframeConsistency` before final vote selection.
- OnInit is two-tiered: mandatory trade/risk/runtime bootstrap remains fatal, while auxiliary AI brain/orchestrator/adaptation modules degrade behind readiness flags and do not abort the EA.
- Strategy `OnNewBar(...)` handlers are state-refresh only; manager consensus owns the single authoritative `GetSignal(...)` call for each strategy evaluation cycle.
- Pending new-bar work is durable across cycles: symbols that miss the current evaluation budget stay queued ahead of intrabar work until they are processed.
- Cold-start cadence is now deterministic:
  - validate active symbols and emit startup account-capacity diagnostics before live execution
  - build the active-only strategy registry and register only enabled strategies and enabled AI adapters, ensuring experimental AI families (Transformer, Ensemble) receive non-zero weights from the AI multiplier during registry bootstrap to allow live participation
  - **Corrected in Batch 215:** there is no cadence-scheduler rebuild routine and `[SCHEDULER-STATE]` has never been printed. Per-symbol bar state is one `CScanSchedulerRegistry` slot per symbol (`symbol` + `lastBarTime`), advanced by `CheckNewBar` from `ProcessNewBars`; the `CSymbolScanScheduler` class this bullet described was never instantiated, and it and its duplicate `CSymbolStateTracker` are deleted in this batch. Intrabar timers, pending-new-bar flags and scan backoff were fields of those two classes with no caller and no reader.
- Per-symbol manager profiles now branch by instrument class before registration: synthetic symbols can use a lean structure-heavy roster and lighter context engines, while FX symbols retain the broader balanced roster.
- `[RUNTIME-FINGERPRINT]` now reports both `RequestedMode` and effective `EAMode`; `20260515.log` / `20260516.log` style `AI_ONLY` sessions should not be read as indicator or hybrid evidence. `20260517.log` confirms actual `INDICATOR_ONLY` and `AI_ASSISTED` participation, but those sessions died after pipeline/quorum rather than from missing registration.
- `EA_MODE_HYBRID` is indicator-led for ordinary packets, but high-confidence AI-only packets can pass through `InpAllowHybridAIStandalone` and then must satisfy the live-authority gate.
- `EA_MODE_AI_ONLY` is now strict execution mode when AI adapters are enabled: indicator-based strategies are filtered out of the strategy registry, and AI adapters are the sole tradable family on both new-bar and timed intrabar paths.
- **Documentation error, corrected in Batch 215:** neither `[MODE-MASK]` nor `[AI-TOPOLOGY]` has ever been printed by this repository - both strings appear in no source file. The two bullets above them are true of the code (AI-only mode filters indicator families out of the registry, and the AI families differ in what they vote on), but the operator-facing evidence they promised does not exist. What actually shows the same facts at init: `[CATALOG]` rows and `[STRATEGY-REGISTRY]` for who was registered, `[ENGINE-STATUS]` for engines with no tick caller, and `[CURATION] Effective strategy set` for the roster consensus will read.
- AI strategy adapters now support a unified `SetConfidenceThreshold(double)` interface, allowing the EA to propagate the system-wide `InpAIConfidenceThreshold` authoritative floor directly into the strategy evaluation loop, eliminating legacy hardcoded confidence caps.
- The effective AI runtime floor is now clamped to at least `0.70`, and transformer/ensemble defaults start disabled until intentionally retrained/re-enabled.
- Strategy and AI registration is active-only: disabled modules remain compiled in source but do not enter manager pools, orchestrator identity maps, or denominator math.
- Pipeline-filtered strategies now surface the rejecting filter chain in consensus summaries, and warmup/unavailable infrastructure abstentions are discounted before ready-live-weight math.
- Consensus denominator math now discounts abstention classes before support ratios are calculated: infrastructure/warmup abstentions carry minimal denominator weight, pipeline-filtered packets carry partial weight, and ordinary raw-none cycles carry reduced weight instead of drowning the few strategies that actually generated direction.
- `Momentum` can run a configured scalp-continuation lane with short wall-clock cooldown while retaining the same consensus, validation, risk, and execution path as all other entries.
- `Momentum` and `Candlestick` can register on explicit lower timeframes (`InpMomentumScalpTimeframe`, `InpCandlestickIntrabarTimeframe`) when the attached chart timeframe is higher, so timed intrabar scans can evaluate faster bars instead of repeatedly asking H1 logic for scalp entries.
- `CMarketAnalysis` can now reuse bounded last-valid trend/volatility/momentum/ATR snapshots on transient `4806/4807` data faults, preventing short sync gaps from collapsing upstream market-state evidence to zeros.
- The scan loop now reserves the current best candidate inside `CUnifiedRiskManager` while later symbols are still being evaluated, so projected daily and portfolio utilization remain authoritative during end-of-cycle ranking.
- Batch 78 source defaults are live-capable (`InpShadowMode=false`) while `InpEnableLiveAuthorityGate=true` shadows individual unproven candidates and promotes/demotes families from forward R evidence. **Corrected in Batch 179: that input defaults to `false` in both `MultiStrategyAutonomousEA.mq5:216` and `MultiStrategyTestingEA.mq5:228`, and it gates only an init print — `Resolve()` and the lot scaling run regardless. `[AUTHORITY-GATE]` now says so at startup.**
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
- Each symbol is evaluated at most once per bar of the chart's timeframe (`SignalGenerator.mqh:352-357`, unconditional since it was written). `InpSignalScanOnNewBarOnly` and the `[CADENCE-WARNING]` line documented around it are **removed in Batch 212**: the input reached no reader, and between-bar consensus evaluation was never implemented, so both its values described the same EA.
- Total heavy evaluations per cycle are bounded by `InpMaxSignalEvaluationsPerCycle` - **from Batch 212 onward**; before it, `CSignalGenerator` used its own literal 8 and the input bound nothing. There is no new-bar/intrabar budget split any more because only one mode is ever run.
- Intrabar scans are now budgeted per cycle and ranked by symbol yield instead of simple full-set round-robin.
- Symbols back off after repeated `raw_none` / `zero_voter` intrabar outcomes and recover on the next new bar.
- Intrabar/new-bar consensus behavior is manager-controlled.

## Batch 216: The Scalp Cache Stopped Computing Six Series Nobody Reads (2026-10-17)

- **Edge after the change:** `ProcessScalpFastPath -> UpdateOnNewBar(4 CopyBuffer) -> UpdateTickValues(spread
  only) -> ShouldEnterScalp -> EvaluateFromCache`. The decision set is identical; the work that produced it
  dropped to a quarter of its buffer reads.
- **What was removed:** `atrPrev`, `bbUpper/bbLower/bbMiddle`, `adxValue`, `volumeCurrent/volumeAvg` - computed
  per symbol per M1 bar (a 6-bar ATR series, three Bollinger buffers, ADX, a 21-bar volume read plus a summation
  loop) and read by nothing. On 13 symbols that is 78 `CopyBuffer` calls and 13 loops a minute inside the tick
  path. The three handles feeding them (`GetBandsHandle`, `GetADXHandle`, `GetVolumesHandle`) are no longer
  acquired per symbol, and `CopyBufferN` went with its only two users.
- **Also gone:** `bidPrice`/`askPrice` (written every tick, read only by the next line of the same function, so
  spread is now computed from locals), and the uncalled `HasNewBar`, `EnsureInitialized`, `GetCacheCount`,
  `IsInitialized`, `SetScalpSetup`.
- **Refused wiring:** `SetPeriods` was the only way to change the cache's EMA/ATR/RSI periods, and
  `SScalpConfig`'s are separate literals (`EAOrchestrator.mqh:1303`). The two agree today only because neither
  moves; calling `SetPeriods` would let them diverge, which would mean the fast path and the slow path evaluate
  different EMAs on one symbol. Deleted, with the reason recorded - if the periods become inputs, one place must
  feed both.
- **Doc fiction corrected:** the "three scalp strategies" in §2.17 and the Scalping Fast Path section. Two of
  them have never had a file; `CScalpVolatilityBreakout` exists as 233 complete lines but is not `#include`d, has
  no catalog row, no `SI_*` slot and no enable input, so it is not in the binary. Kept and listed in §4 as
  wireable-but-unregistered rather than deleted or silently activated.
- **§3 invariants:** unchanged. The one pre-trade gate call on the shipped lot is untouched.

## Batch 215: Two Symbol-State Holders With No Writer, Three Inputs With No Reader, and the Tag Sweep That Found Them (2026-10-17)

- **Edge after the change:** none. `ProcessNewBars -> CScanSchedulerRegistry::CheckNewBar` still decides which
  symbols get a new-bar pass, and `CSignalGenerator` still owns dormancy. What changed is that the two classes
  which claimed to hold that state no longer exist to be mistaken for it.
- **`CSymbolStateTracker`:** allocated, `Initialize`-d, printed in the shutdown report - and its seven state
  methods had zero callers, so `[SCALP-BLACKLIST]` could never print and its report asserted
  `scalpBlacklisted=false, dormant=none` for every symbol from a class with no way to learn otherwise.
- **`CSymbolScanScheduler`:** never instantiated (`new` appears nowhere); the only path to it,
  `GetScanScheduler`, returned `NULL` and had no caller. Whole file deleted, with the eight accessor-backed
  fields of `CScanSchedulerRegistry` it duplicated. The registry now holds `symbol + lastBarTime` only.
- **`pendingNewBarScan` was a one-way latch:** `CheckNewBar` set it `true` and nothing cleared it, so the status
  report printed `pending=Y` for every symbol after its first bar. Deleted with its readers.
- **Three inputs stop lying about the EA:** `InpIntrabarScanSeconds`, `InpMaxIntrabarSymbolsPerCycle`,
  `InpIntrabarBackoffMaxSeconds` wrote config fields read only by the dead scheduler's uncalled
  `SetInputParams`. They are removed rather than wired - wiring them would build a second cadence authority, and
  Batch 212 already settled that consensus runs once per chart bar.
- **`GetTotalRegisteredCount`**, the six `Is*Ready()` probes and the nine per-symbol `Get*(symbol)` conveniences
  deleted. The aggregator's own comment had already named those conveniences dead; a bare-name grep appeared to
  contradict it until each hit was traced to its owner (`pipeline.`, `m_mathEngineHub.`, `m_infra.` - never the
  aggregator), so the comment was correct and the code it described is gone. The class now exposes only getters
  that have callers.
- **Documentation:** the Diagnostics and Observability sections are now restricted to tags verified against
  `Print`/`PrintFormat` call sites. `[SCHEDULER-STATE]`, `[CADENCE-WARNING]`, `[MODE-MASK]`, `[AI-TOPOLOGY]`,
  `[CONSENSUS-ACTIVE]`, `[CONSENSUS-SPARSE]`, `[CONSENSUS-NEARMISS]`, `[INTRABAR-BACKOFF]`, `[SCAN-PRIME]`,
  `[SCAN-CANDIDATE]`, `[SCAN-DECISION]`, `[TRADE-CONFIRMED]`, `[ACCOUNT-CAPACITY]`, `[TRADE-STATE]`,
  `[NN-MUTATION]` and the rest of the set never existed; two more (`[CONSENSUS-VETO]`, `[TRADE-CONFIRMED]`)
  were misnames of `[CONSENSUS-VETOED]` and `[ASYNC-TRADE-CONFIRMED]`.
- **§3 invariants:** unchanged. Pre-trade gating, `CTradeManager` ownership, EA-loop lifecycle, symbol-scoped
  consensus and `DestroyInstance()` on deinit are untouched by a deletion of unreachable state.

## Batch 214: The Scalp Indicator Cache Commits Per Symbol and Each Refusal Names Its Gate (2026-10-17)

- **Edge after the fix:** `ProcessScalpFastPath -> ShouldEnterScalp -> [entry gates] -> EvaluateScalpSignal
  (cache fast path, else RefreshIndicators slow path) -> confidence -> lot -> cost gate -> CUnifiedRiskManager
  -> send`. The signal step now also returns *which* gate refused.
- **The money defect:** `RefreshIndicators` wrote each member as its own read succeeded and restamped the
  symbol/bar tag only at the end, so a mid-sequence `INVALID_HANDLE` or short `CopyBuffer` left the **new**
  symbol's ATR/EMAs/RSI in a cache that still **named the previous symbol**. One engine instance is driven
  across the whole universe in one pass, so the new-bar test then served those foreign numbers back to the
  previous symbol for the rest of its bar - into the spread/ATR cost gate, the momentum-burst body test, the
  `spread/ATR < 0.15` confidence bonus and (with no symbol argument at all) the RSI OB/OS confirmation. An
  FX scalp could thus clear a gold-denominated ATR test and take a trade whose spread eats its TP. Reads now
  land in locals and commit only when every one succeeds; a failure leaves the cache stale but truthful.
- **The asymmetric gate:** `UpdateOnNewBar` zeroes a field whose copy fails and keeps RSI out of `isValid`,
  and `EvaluateFromCache` tested that zero as a reading - `0 >= 70` false admits every BUY, `0 <= 30` true
  refuses every SELL. It now refuses at `rsiValue <= 0.0` like the slow path already did, so one missing
  number no longer means one direction.
- **New refusals:** `[SCALP-SIGNAL-REJECT] <symbol> | gate=spread_vs_atr | rsi_overbought | rsi_oversold |
  rsi_unavailable | indicator_refresh_failed | ema_handles_failed | no_atr_or_point` and
  `[SCALP-SIZING] <symbol> | sizer returned lot 0.0000 | ...`. `gate=` is empty for "no crossover this bar",
  which stays silent on purpose - it is the market's normal state, not a refusal.
- **`[SCALP-GATE]` is now per symbol.** Its throttle was one EA-wide `static datetime`, so the first symbol
  refused in a 60 s window muted the other twelve; its `usedRisk`/`cooldownLeftMs` were always engine-wide.
- **Deleted:** six `GetCached*` accessors with no caller, and `m_cachedFastEMA` / `m_cachedSlowEMA`, which
  had no reader because a crossover needs two bars and `GetEMACrossover` reads its pair statelessly. Two
  `CopyBuffer` calls per refresh go with them, and `SetCachedValues` loses the matching parameters.
- **Unchanged by choice:** the shared `m_lastScalpTime` and scalp risk budget (one scalp stream for the whole
  EA is the design, not a bug), and the `"SFX Vol"`/`"FX Vol"` conditions that `"Vol"` already covers.
- **§3 invariants:** unchanged - the scalp path still runs `ValidateTradeRequest` once on the lot it ships.

## Batch 213: ADX Tiers Multiply Once and VPIN Toxicity Reaches the Lot (2026-10-16)

- **Edge after the fix:** `sizer.CalculatePositionSizeWithRisk -> [modifiers] -> candidate.lotSize -> per-trade cap clamp (consensus only) -> CUnifiedRiskManager gate -> send`. The modifier chain is now `VolatilityTarget?, EquityCurve?, VPIN, Kelly, EquityCurveLot, ADX` - one ADX instance instead of two.
- **What the duplicate did:** each `CADXLotModifier` holds its own iADX handle and multiplies the lot by its tier, so strong (1.3) and very strong (1.5) shipped 1.69x / 2.25x the computed lot. On the consensus path the cap clamp at `CandidateBuilder.mqh:506-530` pulled it back, which is why the visible symptom there was `[RISK-GATE-ADJUST]` churn and a tier ladder permanently pinned at the ceiling; the five callers that go straight to the sizer (`ATRScalpEntry:89`, `FastScalpSizing:68`, `GridRecoveryEngine:320`, `SpikeHunterExecutor:155`, `SimpleMomentumStrategy:749`) run no such clamp and shipped the doubled lot.
- **What the unfed VPIN filter did:** `AdjustLotSize` returned `baseLot` at the `!IsWarmedUp()` branch forever, with no log, because the filter it read was one it created itself and nothing feeds ticks to a filter outside the math hub. The toxicity shrink (0.10-1.00x, blended by confidence) has therefore never been applied: `InpEnableVPINFilter` gated the veto and the strategies, never the size. The modifier now reads the hub's per-symbol filter, registered in the engine-injection loop next to the strategies' own `SetVPINFilter`.
- **Both fixes reduce lots.** Neither widens risk: one removes a doubled boost, the other re-arms a protection whose own documentation claimed it was active.
- **New init line:** `[SIZING-CHAIN] modifiers=VPIN,Kelly,EquityCurve,ADX | vpin_filters=N | kelly=inert(no UpdateTradeResult caller)` - the chain by name, so a sizing input reaching no multiplier is visible - plus a once-per-symbol `[VPIN-MODIFIER] <symbol> | no hub VPIN filter registered | lot unchanged` so an unfiltered symbol is a stated answer rather than a silent pass-through.
- **Declined, with the reason recorded in `SYSTEM_STRUCTURE.md`:** wiring `m_riskReductionFactor` (the tuner's drawdown factor and the profit-credit factor are two quantities sharing one field name), and wiring `UpdateTradeResult` into Bayesian Kelly (the modifier multiplies an already risk-sized lot by a bankroll fraction, which would cut every trade to roughly 1/13-1/40 of intended size on one closed trade's evidence).
- **§3 invariants:** unchanged - every entry still passes `CUnifiedRiskManager` pre-trade gating; only the lot reaching it moved toward what the design intended.

## Batch 212: The Scan Cadence Controls Bind; a Parked Symbol Costs Nothing but Its Own Scan (2026-10-16)

- **Edge:** `OnTick -> RunSignalEvaluationCycle -> GenerateSignals(EVAL_MODE_NEW_BAR) -> SelectSymbolsForEval(budget) -> EvaluateSymbol[per-bar gate] -> consensus`. Two of those controls were operator-visible but disconnected, and one was a constant wearing an input's name.
- **Budget:** `evalBudget` is now `config.maxSignalEvaluationsPerCycle` (`InpMaxSignalEvaluationsPerCycle`, default 8 = the old private literal). Before it, the input wrote a config field with no reader and `SYSTEM_STRUCTURE.md` said the value capped evaluations.
- **Dormancy:** `DORMANT_THRESHOLD`/`DORMANT_COOLDOWN_MIN` (3 bars / 30 minutes) became `InpDormancyStrikeBars` / `InpDormancyCooldownMinutes` with the same defaults. The park is a *time* penalty earned in *bars of the chart timeframe*: 3 quiet minutes on M1 bought a 30-minute evaluation blackout, which is 10x the entry chances lost, while the same numbers on H1 are a mild backoff. It is now the operator's number, and `[SCAN-POLICY]` prints it once.
- **Selection:** parked symbols are skipped during selection instead of holding a slot the scan loop then passed over, so a cycle reaches its budget of *scannable* symbols; the rotation advances by symbols examined, not by `budget`, which used to step past symbols whenever fewer than `budget` were selectable.
- **Deleted:** `InpSignalScanOnNewBarOnly` + `config.signalScanOnNewBarOnly` (no reader; both values described the same EA), `m_intrabarBudgetPerCycle`, and the duplicated `EVAL_MODE_NEW_BAR`/else branches in `SelectSymbolsForEval`.
- **New refusal log:** `[ENTRY-GATE] entries held this cycle | refused by=trade_cooldown position_limit unprotected_positions spike_pause profit_guard_halt basket_equity_halt | eaPositions=n/m | secondsSinceLastTrade=n`, throttled to 15s. Six independent holds were fused into one `continue` with no output.
- **Left alone, on purpose:** `EVAL_MODE_INTRABAR` still binds only on the exit side (`PositionLifecycleManager.mqh:261-264`), because passing it on the entry path would move admission two ways at once (solo confidence 0.70 over 0.65, quality floor 0.68 under 0.70, plus the `eligibleLiveVoterCount < 3` gate) with no journal newer than 2026-09-23 to judge it, and because sub-bar evaluation would let one quiet bar earn dormancy strikes several times over and park symbols by the minute.

## Batch 211: Engine Injection Reports Per Symbol at Init (2026-10-16)

- **Edge unchanged:** `InitializeEnterpriseManagers -> GetStrategyByName(row name) -> dynamic_cast -> SetHurstEngine / SetVPINFilter / SetOUEngine / SetPythonBridge`, then the strategy's own regime gate reads the pointer. Same setters, same order, same pointers.
- **What was invisible:** all five `[WIRE]` prints sat behind `m_config.logLevel >= 3` while `InpLogLevel` defaults to 1, so no journal has ever confirmed that a strategy received its engine. A failed `dynamic_cast` was indistinguishable from "not on this roster": the strategy registers, votes and trades with `m_hurstEngine == NULL`, and `MeanRevertingRegime()` answers **true** on a NULL engine (`MeanReversionStrategy.mqh:492`), i.e. Mean Reversion keeps its band entries in a confirmed trend with no lockout and no output.
- **New output:** `[WIRE-STATUS] <symbol> | Trend=… S/R=… MeanRev=… StatArb=… | hurst=… ou=… vpin=… ofi=…` once per symbol, unconditional, with `wired` / `NO-ENGINE` / `not-registered` / `CAST-FAILED` per strategy and `on` / `OFF` per engine, plus `[WIRE-CAST-FAIL] <symbol> | ...` when a registered strategy is not the class its row names.
- **Read it as:** `NO-ENGINE` means an operator input switched the engine off (the strategy runs its unfiltered branch by design); `CAST-FAILED` means the catalog row and the class disagree, which is the §4.4 identity contract failing at the injection path.
- **§3 invariants:** unchanged. No gate, veto, size or exit moved.

## Batch 210: The Factory Builds AI Adapters Only; the Unreachable Indicator Path Is Deleted (2026-10-16)

- **Edge unchanged:** `CAT_KIND_AI rows -> CStrategyFactory::Create(factoryName) -> PrepareCatalogAIAdapter(k, adapter, symbol, tf) -> RegisterCatalogAIAdapter(symbol::name)`, and `CAT_KIND_INDICATOR rows -> g_strategyCatalogCreators[i]() -> ConfigureBeforeInit -> Init`. What changed is that the first edge no longer has a dead branch pointing at indicator classes.
- **Deleted, all unreachable:** twelve indicator creators and their `RegisterInternal` lines; `SStrategyConfig` (seventeen fields, read by nobody among the five surviving creators); the eight `cfg.*` assignments at the only call site; `IsRegistered` / `GetRegisteredNames` / `GetCount` / `BuildConfigFromEA` (zero call sites); fourteen includes.
- **Signature:** `Create(const string name)`, `typedef IStrategy* (*CreatorFunc)()`.
- **Log change operators will see:** `[StrategyFactory] Initialized with 5 strategy creators` (was 17).
- **Failure mode added by removal:** pointing a `factoryName` at an indicator now prints `[StrategyFactory] ERROR: Unknown strategy '<name>'` rather than building a second instance with none of the `ConfigureBeforeInit` inputs applied - the exact half-wiring Batch 194 had to work around.
- **§3 invariants:** unchanged. No entry, sizing, risk or lifecycle path moved.

## Batch 209: The Enable Roster Comes From the Catalog Row (2026-10-16)

- **Edge rewritten:** `g_strategyCatalog indicator rows -> (CatalogEnableSlot + ConfigEnableForSlot switch + curatedEnable) -> strategyFlags[] -> {AutoRegisterStrategies, BuildStrategyRegistry, BuildEnabledStrategyList, CountEffectiveIndicatorStrategiesForSymbol}`. Before it, the writer was fifteen hand-written assignments and the two reporting paths read the array by raw index.
- **The `[CURATION]` edge was broken, not the gate.** `BuildEnabledStrategyList` cast each set flag index to `ENUM_STRATEGY_TYPE`; the two enums number the same strategies differently and the type enum has gaps, so Mean Reversion printed as `STRATEGY_CANDLESTICK`, Liquidity Sweep as `17`, Momentum as `0`. The decision itself was correct - only the evidence line was wrong, which is what makes it worth fixing on a live book.
- **The skip guard's number was low.** `CountEffectiveIndicatorStrategiesForSymbol` summed all set flags then subtracted flag slots `17/18/19/20` as "AI", which are Liquidity Sweep, Range Compression and Exit Optimizer; no AI adapter owns a flag slot. `EAOrchestrator.mqh:1624` tests that count against zero before it gives a symbol a manager, and the corrected count is two *higher* on the default roster (its `+1` Exit Optimizer entry cancelled its own `-1`), so the guard got looser, not stricter.
- **`SI_EXIT_OPTIMIZER` deleted.** Its only readers were that decrement and the `[CURATION]` cast. `InpEnableExitOptimizer` still gates the math engine at `OrchestratorMathEngineHub.mqh:272,440`, which is where it always worked.
- **New loud failure:** a catalog row whose `siIndex` has no `ConfigEnableForSlot` case prints `[CATALOG] <name> | enable slot N has no operator input - it stays off unless curated`. Previously such a row would have been written by nobody and registered by nobody with no output at all.
- **Unchanged:** every flag value for the fourteen existing rows, the curated set (twelve rows, now marked in the row rather than listed in the builder), per-symbol suppression in `BuildStrategyFlagsForSymbol`, registration, weights, intrabar policies, consensus, authority and risk gates.

## Batch 208: Contributor Kind Comes From the Catalog Row (2026-10-15)

- **Edge rewritten:** `consensus contributors (row names) -> CatalogContributorIsIndicator / IsAI / IsAIKind (g_strategyCatalog[].kind, .aiKind) -> candidate.hasIndicatorContributor / indicatorContributorCount / hasAIContributor / hasONNXContributor / hasNeuralNetContributor -> CLiveAuthorityResolver::Resolve -> authorityScore -> riskMult -> lot`, plus `hasNeuralNetContributor -> Batch 203's label reservation`.
- **What the replaced substrings did:** `MeanReversion`, `StatArb`, `NYOpen`, `AsianRange` never matched the row names `Mean Reversion`, `Statistical Arbitrage`, `NY Open Gap`, `Asian Range Break`; `Liquidity Sweep`, `Range Compression` and `Python Bridge AI` had no token at all. Six of fourteen indicator rows and one of five AI adapters were not counted.
- **Gate-by-gate direction:**

| Consumer | Before | After |
|---|---|---|
| `authorityScore += 0.20 * min(1, count/2)` | those six rows' trades earned nothing | earned when an indicator actually voted |
| `minConfidence = 0.55` with indicator support | AI-standalone 0.65 applied to indicator-only decisions | the indicator bar applies where it is designed to |
| `hasAIContributor && !hasIndicatorContributor` bootstrap cap | Python Bridge AI never entered it | capped until it proves out, and it now earns the `+0.25` AI term |
| `hasONNXContributor` (`+0.30`) | matched on `"ONNX"` | matched on `aiKind == CAT_AI_ONNX` |
| `hasNeuralNetContributor` (label gate, Batch 203) | matched on `"Neural"` | matched on `aiKind == CAT_AI_NEURAL_NET` |

- **Precondition verified first:** contributor strings are row names because `RegisterStrategy` (`EnterpriseStrategyManager.mqh:844`) and `RegisterCatalogAIAdapter` (`EAOrchestrator.mqh:2409`) both pass `g_strategyCatalog[i].name`. Matching is containment, so a qualified `symbol::name` still resolves, and no row name is a substring of another.
- **Plug-and-play effect:** a new row is classified correctly without touching `CandidateBuilder`, which removes the fifth hand-maintained per-strategy list.

## Batch 207: Three Phantom Strategy Slots Removed (2026-10-15)

- **No decision path changed.** `SI_UNIFIED_ICT` / `SI_UNICORN_MODEL` / `SI_POWER_OF_THREE` had no catalog row, so no strategy ever occupied them, no `InpEnable*` flag was ever written to them, and `GetRegimeCategoryMultiplier`'s three corresponding `case` labels were unreachable (no `GetType()` returns those values).
- **Dead input chain removed:** `InpIntrabarEligibilityUnifiedICT/UnicornModel/PowerOfThree` → `config.intrabarEligibility*` → `strategyTimeframeConfigs[3]/[5]/[6]` + `strategyIntrabarConfigs[3]/[5]/[6]`. A catalog row selects its policy slot through `CatalogPolicySlot(i)`, and no row declares 3, 5 or 6, so those writes had no reader.
- **Slot numbering deliberately not compacted:** both enums keep explicit values, so `CatalogEnableSlot` / `siPolicyIndex` pairs on surviving rows are unchanged and `[CATALOG-AUDIT]` output should be identical before and after.
- **Kept:** `SI_EXIT_OPTIMIZER` (real class, parked for the second-exit-authority reason) and the testing EA's profile vocabulary.

## Batch 206: The Minimum R:R Stops Capping the Take-Profit (2026-10-15)

- **Edge changed:** `CalculateStops` -> `takeProfitPips = MathMax(proposedTP, stopLossPips * minRR)` (was `MathMin`). The TP edge into `CheckExecutionCost`, `TradeExecutor` and the order request is the same edge; its value is now a floor rather than a ceiling.
- **Two suppressions removed:** a strategy's wider designed target no longer collapses to `minRR` (which cut the profit side of every entry), and because the execution-cost gate tests `spread / TP` against `InpMaxSpreadToTpRatio`, the shrunken TP was itself raising the ratio those entries were refused on. When the spread floor widens the stop, TP now rises with it, so the shipped trade cannot sit below the configured R:R.
- **Untouched:** `stopLossPips` and therefore lot size, per-trade risk, every risk gate and the exit authority. This changes where a winner is taken out, not how big the position is.
- **Sweep result recorded:** five candidate over-restrictions were checked to the line and ruled out (triple-counted spread floor dominated by the policy term; the safe-mode per-symbol cap latch has no reachable stale case because MT5 inputs cannot change mid-run; two unreachable arms of `GetAdaptiveQualityThreshold`; the min-lot correlation refusal, which is the stated anti-round-up rule; the fail-closed SL-less portfolio poison, recomputed each pass).
- **Deferred with reason:** all ATR reads (`PostConsensusValidator::GetATRDirect` via `Period()`, `CalculateStops` via `PERIOD_CURRENT`) resolve to the chart window because `EAOrchestrator.mqh:1790` initializes every manager with `Period()` as its base timeframe, while each strategy carries its own catalog timeframe. Fixing it means choosing a per-symbol operating timeframe - a policy decision, not an arithmetic correction.

## Batch 205: The Authority Ladder Is Fed Measurements Instead of Zeros (2026-10-15)

- **New edge:** `pipeline.ProcessSignal(voter) -> SPipelineEvidenceSnapshot -> per-direction mean over the winning side -> SConsensusDecisionContext.convictionScore/readinessScore/contextScore/costScore (+ readyLiveWeight/totalLiveWeight) -> CandidateBuilder.mqh:383-386 -> CLiveAuthorityResolver::Resolve -> authorityScore -> riskMult rung -> lot`.
- **What the path did before:** the four measured inputs reached `Resolve` as `0.0` on every consensus candidate, so the `+0.08 conviction`, `+0.07 readiness`, `+0.05 context` and `+0.05 cost` bonuses never fired. `authorityScore` was the kind/confluence/quality sum only, and `riskMult` (`>=0.80 1.0`, `>=0.65 0.85`, `>=0.50 0.70`, `>=0.35 0.50`) sat one to two rungs below what the ladder computes from a measured signal. `InpAuthorityMinReadinessScore`, `InpAuthorityMinContextScore` and `InpAuthorityMinCostScore` had no effect.
- **Aggregation chosen:** unweighted mean over the winning side's voters, captured per voter right after its own `ProcessSignal` (which resets then fills the snapshot, so a voter never reads another's evidence). `convictionScore` is mean raw `stratConf`; `qualityScore`/`directionalQuality` stays mean `stratConf x weight` - two different bonuses, two different measurements, no double-counting of one value.
- **Fail-closed:** with no pipeline the values stay `0.0` and pay no bonus. Nothing was substituted for a missing measurement on a sizing path.
- **Loudness:** `reasons` now appends `QUALITY`, `CONVICTION`, `READINESS`, `CONTEXT`, `COST` for each earned bonus, so `[AUTHORITY-REDUCED] ... reason=` identifies which measurement moved the lot.
- **Unchanged:** `result.allowed`, the `LOW_CONFIDENCE` refusal, the BOOTSTRAP/PROVEN_AI caps, every risk gate, the ladder's reduction direction, and the four engine send paths (which never consult live authority). Per-trade risk rises toward the configured ceiling, not past it.

## Batch 204: A Regime Veto Removes the Vote Itself (2026-10-15)

- **Before:** `RegimeStateHardGate(state, type)` returning `0.0` zeroed the *score* only, and `ConsensusEngine.mqh:439` said so. The strategy still incremented `buyVotes`/`sellVotes`, still entered `buyContributorIndices`, still contributed its weight to `votedWeight`, still counted in `totalVotesCast` and in `conflictRatio`, and still got charged the trade outcome through `SetLastSignalContributors`.
- **Now:** the category multiplier is read before the accumulations and a value `<= 0.0` skips the strategy outright. `[CONSENSUS-REGIME-VETO] <symbol> | N vote(s) hard-gated by regime | excluded weight=W | counted votes B buy / S sell` reports it once per scan; a fully vetoed field reaches `[CONSENSUS-ABSTAIN]` instead of `[CONSENSUS-TIE] buyScore=0.000 sellScore=0.000`.
- **Gate-by-gate direction:**

| Gate | Before | After |
|---|---|---|
| `readyWeightRatio` | vetoed weight in the denominator, no score in the numerator: the veto tightened it | vetoed strategies absent from both |
| `winningVotes >= effectiveMinVoters` | a forbidden vote helped reach the two-voter minimum | only permitted votes count |
| `quorumRatio = winningVotes / totalVotesCast` | vetoed votes on both sides moved the ratio | reflects only real support |
| `[CONSENSUS-VETOED] conflictRatio` | vetoed opposition could veto a direction it was forbidden to oppose | losing votes are permitted voters only |
| `winningQuality` / `effectiveQualityThreshold` | per-side quality averaged in zero-score participants | averaged over actual contributors |
| `winningContributors` -> attribution, `[TRADE-ATTRIBUTION]`, `[AUTHORITY-LEARN]`, `m_strategyHealthScore`, cluster tag and `clusterCode` | a regime-forbidden strategy was credited/blamed for a position it could not open, and that error fed its own future reliability | contributors are permitted voters only |

- **Unchanged:** the deweights. Breakout reversion at 0.25 and Chaos at 0.40 multiply the score and still vote, because `RegimeComposite.mqh:246-250` clamps every category weight to `>= 0.01` and the confidence factors to `0.30`/`0.55` - so `0.0` is reachable only through the hard gate. `eligibleLiveVoterCount` still counts every live voter, because it measures the size of the field for `SPARSE_INTRABAR`, not who spoke.
- **Supersedes** the Batch 195 note "A zeroed score still counts as a vote for the minimum-voter test".
- No change to risk gating, lot math, stops, sends or exit authority; the veto table itself is untouched.

## Batch 203: Realized Trade Results Reach the Neural Net (2026-10-14)

- **New edges (learning only):** `send -> ReservePredictionForSignal(symbol::NN) -> candidate.predictionId -> Execute -> UpsertPredictionPositionMap(positionId, id) -> close deal -> AccumulatePendingCloseProfit(positionId, net) -> ProcessClosedPositionsForNNTraining -> GetPendingCloseProfits (id from the map) -> UpdateTradeResultByPredictionId`. Five of those links had no writer, and the sixth (the comment-based id read) could never resolve because a closed position is not selectable.
- **Reservation is deliberately last-minute:** taken immediately before `m_tradeExecutor.Execute` and released if the fill does not resolve to a position, so a validator, risk, authority or preflight refusal cannot leave a trade-tagged barrier entry behind for a trade that never existed.
- **New gate on labelling:** `candidate.hasNeuralNetContributor` (`ContributorsIncludeNeuralNet`) - a trade the net did not advocate cannot be credited to it. That flag is what keeps the wiring from manufacturing labels.
- **Drain semantics fixed:** every pending row is consumed, linked or not. Rows used to persist and be re-read each cycle, and indicator trades have no consumer at all.
- **Comment shape:** `|N:<id>` is appended only when it fits the broker's 31-character cap; previously an over-long id produced a truncated `|N:` fragment that replaced the base comment and could not be parsed back. The map is the authoritative binding.
- **Not changed:** no entry, exit, lot, stop, magic or send decision path. `UpdateTradeResultByPredictionId` tags and counts; it does not set a training target, and the meta-labeler keeps the barrier's directional sample - switching that mid-dataset would mix two label semantics in one training set.
- **§3 invariants:** all five untouched. §3.4: the symbol-scoped decision still names the voters, and now also decides whether a net label may be taken.

## Batch 202: The Heartbeat's Pause Field Comes From the Monitor That Pauses Trading (2026-10-14)

- **New edge:** `CSyntheticSpikeMonitor.IsPaused() -> CHeartbeatTelemetry::Emit -> CDiagnosticsManager::SetTradingPaused -> [HEARTBEAT] paused=`. Nothing was removed from the decision graph: no gate, cap or branch reads that field.
- **What it replaces:** a constant. The field had two writers and neither had a caller, so `paused=` printed `false` for the repository's whole life, including while the spike monitor was actively refusing new positions (its own `IsPaused()` gate at `EAOrchestrator.mqh:3445` was doing the work).
- **§3 invariants:** untouched. `IsPaused()` also expires the pause, but the cycle gate already calls it, so no extra state advance per tick beyond what already happened.

## Batch 201: The AI Confidence Threshold Now Moves With the Market Regime (2026-10-14)

- **New edge:** `EvaluateConsensusInternal -> RefreshMarketRegime -> pipeline.GetRegimeEngine(symbol).GetSnapshot() -> m_currentMarketRegime -> CAIEngine::AdaptToRegime / explanations / reasoning logs`. Before this the field had four readers and no writer, so `AdaptToRegime` reached its `default:` branch on every cycle and the 0.9 / 1.1 / 1.2 per-regime confidence factors never applied to any AI strategy.
- **Mapping, and the conservative case:** `REGIME_TREND -> TRENDING`, `REGIME_RANGE -> RANGING`, `REGIME_BREAKOUT`/`REGIME_CHAOS -> VOLATILE`, invalid or warming-up snapshot -> `MARKET_REGIME_UNKNOWN` (no adaptation). Both the vote weighting and the AI threshold now read the *same* `CRegimeEngine` snapshot, so they cannot disagree about the market.
- **Visible by design:** `[MARKET-REGIME] <symbol> | old -> new | valid=` prints only on a change. If a journal shows AI trades with no such line, the regime engine never validated a snapshot for that symbol - which is a statement about data, not about this wiring.
- **Not wired, with the reason:** consensus participation (its 0.35 "no signal" target would permanently discount strategies that are supposed to fire rarely) and the lifecycle's ranging-regime trailing pause (`ManageAllPositions` has no symbol filter, so routing per symbol means changing the exit authority - not attempted without a live attach).
- **§3 invariants:** §3.1 untouched - the unified risk gate still runs before every entry at the same ceilings. §3.2/§3.3 untouched: no send, no exit path, no stop moved. §3.4 served: the decision point remains the single place the market state is published.

## Batch 200: No Decision Path Moved; Four Dormant Ones Are Now Documented Instead of Hidden (2026-10-14)

- **Zero edge changes.** Every deletion had no call site, which the compile proves (MQL5 resolves every reference in all eight programs). Entries still flow `consensus -> validator -> unified risk -> builder -> authority -> executor`, exits still flow `OnTick -> ManageAllPositions` plus the lifecycle, and no gate, ceiling, lot, stop, magic or send was touched.
- **Deleted near live edges, so the copies stop attracting edits:** `FeedMicrostructureEngines` (a never-called twin of the `OnTick` VPIN/OFI + Skew Step feed - the same statement at `EAOrchestrator.mqh:2585` is the one that runs) and `CTradeExecutor::ExecuteBatch` (an uncalled batch-send loop with its own `[EXECUTION]` print, while the real sends come from the orchestrator's per-symbol loop).
- **Deleted never-reachable branches:** the closed-trade attribution API (`PopClosedTradeAttribution` and both forwarders - the flag was never set, so the pop always answered false), `UpdateRegimePerformance` in the manager and the health wrapper (`CStrategyHealthMonitor`'s same-named overload is a different method and stays live), `CPortfolioRiskManager`'s four cache hooks plus the private `Add/RemovePositionToCache` only they called (portfolio risk is a full rescan every 60 s and always has been), `ReenableONNXAI`/`Reset` (auto-retry in `ShouldAttemptInit` is the real recovery path), `GetTotalGridRisk`, `m_preRetrainTimestamp`, `ApplyStrategyWeights`, and `CDiagnosticsManager`'s NN-health check, no-signal-rate getters, duplicate `UpdateTradingPaused` and `m_lastNNHealthLogTime`.
- **Recorded as unwired rather than deleted, each a behaviour change:** consensus participation is a constant 0.985 for every vote (`UpdateParticipationScore` has no caller, the roster's 0.90 never moves); the lifecycle's ranging-regime trailing pause has no regime source (`SetRegimeEngine` uncalled, and one global pointer is the wrong shape for a multi-symbol book); the heartbeat's `paused` field printed false while `CSyntheticSpikeMonitor` held the truth (wired in Batch 202). The neural net's realized-trade-result path was the third item on this list and is wired as of Batch 203.
- **§3 invariants:** all five untouched - pre-trade gating, `CTradeManager`-owned execution, EA-loop-owned lifecycle, symbol-scoped consensus, and `DestroyInstance` on deinit.

## Batch 199: The Consensus Decision Now Publishes Its Voters, Which Starts Four Dead Loops (2026-10-14)

- **New edge:** `consensus accepted -> SetLastSignalContributors(winners, role, cluster, clusterCode)` (`ConsensusEngine.mqh:1007`) -> candidate tags, attribution, cluster governance and authority learning all read from it. Before this batch the writer did not exist, so every downstream consumer ran on an empty contributor list.
- **Second new edge:** `send executed -> positionId known -> AttributeExecutedPosition(positionId, winners)` (`EAOrchestrator.mqh:3544`). Attribution is keyed to the fill, not to whatever decision the cache holds at `DEAL_ENTRY_IN`; the old in-deal upsert is removed. Provenance now records every executed trade, not only AI ones (`[AUTHORITY-LEARN]` was unreachable because `hasAIContributor` was computed from the empty list).
- **Revived loop:** `close -> PopPositionAttribution -> UpdatePerformance -> successCount/failCount/totalTrades/healthScore -> GetStrategyReliabilityMultiplier`. Indicator strategies sat on the registration default (0.75 -> multiplier 1.025) for every vote forever; AI rows were the only ones that moved, via `UpdateAIPerformanceMetrics`. So the indicator book was immune to its own results while the AI book was not.
- **Revived gate:** `ValidateClusterGovernance` returned true at `NormalizeClusterCode("") == "N"` (`RiskValidationPipeline.mqh:949`), so per-cluster position and risk caps and the opposing-cluster mutex were skipped on every candidate. They now evaluate; `[RISK-CLUSTER]` prints the cluster it measured.
- **Tightened first:** `HasOpposingReservation` treated *same*-cluster opposing reservations as no conflict and *different*-cluster ones as a conflict - unreachable while every code was empty, and a loosening the moment codes arrived. The cluster term is removed: an opposing reservation on the same symbol is a conflict. The unused `clusterCode` parameter went with it.
- **Engine books excluded:** `OnTradeTransaction` now returns for a deal whose comment is an engine tag or whose magic is in a Batch 197 band, so a scalp fill can no longer be scored as the strategies in the cached context (the gap Batch 197 recorded rather than shipped).
- **Behaviour direction:** more refusals possible, never fewer; entry count can only drop, weighting quality is what improves. No ceiling, lot, stop, magic or send changed.
- **§3 invariants:** §3.1 preserved - the risk gate still runs before every entry and now has real cluster data to gate on. §3.2 and §3.3 untouched. §3.4 is served: the symbol-scoped consensus decision is now the thing that identifies the voters, rather than an unlabelled vote followed by a context that never existed.

## Batch 197: Magic Ownership Is Now Band-Scoped, and the Lifecycle Window Covers the Book (2026-10-14)

- **New edge at init:** `symbol universe built -> compose every consensus offset -> CMagicRange::IsEngineReservedOffset -> collide? refuse start : [MAGIC-LAYOUT]`. The assertion runs before `ValidateMagicOwnershipCoverage`, so the window is checked against the layout that has to fit inside it.
- **Send-time composition changed for five owners, not four.** `fast scalp = base + 6000` (both the async branch and the synchronous `OpenPosition` call, which previously left magic at 0 and let `TradeManager.mqh:1267` stamp the symbol's consensus magic; pending orders previously shipped the bare base), `ATR scalp = base + 6100`, `grid = base + 6200 + level`, `spike = base + 6300`. **Consensus composition also changed:** `SetMagicOffsetForSymbol` registered the asset offset alone, so every symbol in an asset class shipped the same magic (`base + 7000` for all forex pairs); it now registers `assetOffset + symbolIndex * 100`, one per symbol. New consensus positions therefore carry a different number than the ones already on the account.
- **Why that is safe to change:** every consumer of `POSITION_MAGIC` either tests the ownership *window* (`IsEAOwnedMagic` / `CMagicRange::IsOwned` / `IsLifecycleManaged`, seven sites) or filters by symbol before comparing (the grid's `GridRecoveryExecution.mqh:210`). No gate, cap, lot or exit reads an exact consensus magic, so the re-label moves no decision.
- **Why the bands sit under 7000:** asset-class offsets run 7000 (ASSET_FOREX) to 9999 (DERIV_UNKNOWN), so an engine can no longer reach a consensus number or the reverse. Only `ASSET_UNIVERSAL` (offset 0) composes below 7000, from slot 60 upward - which is what the init assertion refuses to trade rather than merge two books.
- **Attribution could not separate owners, and this batch did not fix attribution.** `CStrategyMgrTradeFeedback::OnTradeTransaction` gates a deal on `IsEAOwnedMagic(dealMagic)` - a window test, because `managedMagic` is seeded with the bare base at `EAOrchestrator.mqh:1791` - then on `DEAL_SYMBOL == manager's symbol`. A same-symbol fast scalp cleared both. What it then met was a contributor list nothing ever wrote, so no deal, strategy or scalp, was ever attributed at all; Batch 199 found that writer missing and installed it. The magic bands are what make the two owners distinguishable *now* that the loop runs, which is why the engine-book filter added in Batch 199 can name a scalp as one.
- **Grid restart edge added:** `init -> RecoverOpenGridLevels() -> for each open position whose comment starts with GRID-RECOVERY -> decode level from magic (new band, or legacy 8000 band via %100) -> refill slot`. Previously the level table started empty every session while the positions stayed open, so `CalculateGridDrawdownPercent`, `CloseAllGrids` and the next-level logic all acted on a grid the engine could not see.
- **Lifecycle gate widened:** `ManageSignalReversalExit` and the ranging-regime breakeven loop test `IsPositionLifecycleManaged()`, whose window was `base + symbolCount*100 + maxClusterCode` (`base + 1399` on the default 13-symbol universe) against magics shipped at `base + 7000..9400`. Twelve of thirteen symbols were excluded, so both exits never ran with `InpEnableSignalReversalExit = true`. The predicate now delegates to `CMagicRange::IsOwned(magic, base, MagicMax())`, the same authority `CTradeManager`, `CPositionMgrMagicFilter`, `SyntheticSpikeMonitor` and `UnprotectedPositionTracker` use.
- **Behaviour direction:** more exits, not fewer - signal reversal closes and breakeven SL moves now reach consensus positions. Both are bounded by their own inputs (`InpSignalReversalMinLossR`/`MaxLossR`/`MinTimeSec`, `InpSignalReversalProfitGuard`). No entry gate, risk ceiling, lot or stop distance changed.
- **Removed:** `CMagicNumberAllocator` and its `AddFamilyOffset` table, `[MAGIC-ALLOC]` init logs, `m_maxClusterCode`, and the `Initialize` parameter that carried it. The class was a parallel offset scheme (VOLATILITY 1000 / FOREX_MAJORS 5000 / CRYPTO 8000) with no call site; adopting it would renumber every open position.
- **§3 invariants:** §3.1 untouched (risk gating is unchanged; the grid's level-count guard rejects a level that cannot fit its band before the send, and still calls `PassesRiskValidation`). §3.2 holds - the engines still send through `CTradeManager`/`CTrade`, only with a different magic argument. §3.3 holds and is better served: the lifecycle loop now recognises the positions it was always meant to manage. §3.4/§3.5 unaffected.

## Batch 196: Fill Confirmation Now Resolves to an Owner (2026-10-14)
- **Edge changed on every send-failure reconciliation.** `send -> retcode says failed -> FindFreshPositionForSend(symbol, orderType, requestedVolume, ticket, volume [, expectedCommentPrefix]) -> match? treat as filled`. The match previously required only symbol + side + `IsMagicOwned` + `POSITION_TIME >= now-30s`, so any EA-owned position opened by any other owner in the window satisfied it, and `requestedVolume` was read nowhere in the body.
- **Why magic could not discriminate here.** `CTradeManager` composes market-order magic as `base + per-symbol offset` (`TradeManager.mqh:1267`); `FastScalpEntry`'s synchronous send goes through `CTradeManager::OpenPosition`, so a scalp fill and a consensus fill on the same symbol carry one magic. `ATRScalpEntry` composes `base + 7000 + symbolIndex`, and 7000 is also `ASSET_FOREX`'s offset in `CMultiAssetProfiler` - the overlap recorded as task #37 and deliberately not renumbered, because open positions are matched by that identity.
- **Owner resolution added.** Five engine sites pass the comment prefix they send with (`SCALP` at `FastScalpEntry.mqh:260` and both fallbacks in `FastScalpPendingOrders.mqh:67/69`, `GRID-RECOVERY`, `SPIKE-HUNT`, `ATR-SCALP`). The two consensus sites (`TradeMgrPreflight.mqh:254`, `TradeManager.mqh:1335`) pass none, and an unspecified owner now skips any position `HasEngineComment` claims. Prefix tests use `StringFind(...) == 0`, the same convention Batch 170 established for scalp exits, so `"ATR-SCALP|"` is not mistaken for `"SCALP"`.
- **Consequences that closed.** A grid level can no longer store a borrowed ticket and later `PositionClose` it. A scalp tracker slot can no longer be keyed to a position whose risk budget belongs to another owner. A consensus receipt can no longer report `filledVolume`/`partialFill` derived from a foreign lot. The transient-retcode dedup guard can no longer refuse a real entry because an engine filled on the same symbol moments earlier - and still dedups its own fills, since consensus comments are not engine prefixes.
- **What did not move:** no magic, comment, lot, SL/TP, ownership range or send path changed; §3.2 (execution owned by `CTradeManager`) and §3.3 (lifecycle owned by the EA loop) are untouched. Only the interpretation of an existing scan narrowed.
- **Open:** `requestedVolume` remains unread in the matcher (a volume filter would break the partial-fill case this helper exists for); the live fast-scalp path is the synchronous branch (`InpScalpAsyncMode = false`), and the async branch labels its positions `"AsyncTrade"` and returns before the confirm block, so it is unaffected.

## Batch 195: `GetType()` Restored on Two Strategies, Which Returns a Regime Veto (2026-10-14)
- **The vote-scoring path is unchanged; the value entering it was wrong.** `EvaluateConsensusInternal` computes `score = stratConf * weight * participation * reliability * GetRegimeCategoryMultiplier(symbol, entryStrategy.GetType())` (`ConsensusEngine.mqh:856`, `:1134`, `:1264`). `GetRegimeCategoryMultiplier` first calls `RegimeStateHardGate(snap.state, strategyType)`, which returns 0.0 for reversion-like types in `REGIME_TREND` and 0.25 in `REGIME_BREAKOUT`, and then selects a category weight by type. `CLiquiditySweepStrategy` and `CRangeCompressionBreakout` reported `STRATEGY_TYPE_CUSTOM` because they declare `GetStrategyType()` rather than overriding `GetType()`, so they matched no classification and took `default: 1.0`.
- **Restored edge:** Range Compression (a reversion-like type in the gate) now has its score zeroed in a confirmed trend regime and is deweighted to 0.25 in a breakout regime, and it is grouped with Volatility Breakout under `breakoutWeightMult`; Liquidity Sweep is grouped with the ICT family under `ictWeightMult`. A zeroed score still counted as a vote for the minimum-voter test and diluted `readyWeightRatio`, because its weight stayed in the `votedWeight` denominator while its score left the numerator - **both of those are fixed by Batch 204**, which drops a hard-gated strategy before any accumulation.
- **What did not move:** magic numbers, position comments, the ownership window, the risk gates, the lot, and every other `GetType()` consumer (five of them test only `STRATEGY_BRAIN`/`STRATEGY_AI_ENHANCED`; `LiveAuthorityResolver` uses it for a report). `CMagicNumberAllocator::GetStrategyOffset` does switch on strategy type, but the allocator has no call site, so no open position changes bucket (the allocator was deleted in Batch 197).
- **§3 invariants:** §3.1 and §3.2 untouched. §3.4 is served: a manager's consensus now weighs these two voters the way the regime engine intends.

## Batch 194: Three Strategy Inputs Reconnected to the Strategies (2026-10-14)
- **New edge in the registration path:** `CreateAndRegisterSymbolManager` -> `SetStrategyIntrabarPolicyConfig(...)` loop -> **`SetStrategyConstructionInputs(candlestickRequireTrend, enableMomentumScalping, momentumScalpCooldownSeconds)`** -> `AutoRegisterStrategies` -> per row: `creator()` -> **`ConfigureBeforeInit(s, row.name)`** -> `RegisterStrategy` -> `strategy.Init(...)`. The step sits before `Init` because both flags it carries are read *inside* `Init`, so the post-registration dependency pass could never have applied them.
- **Momentum:** `InpEnableMomentumScalping` (default **true**) and `InpMomentumScalpCooldownSeconds` (20) now reach `SetScalpingMode`. Scalping bypasses `MOMENTUM_SAME_BAR_GUARD` and adds a sustained-momentum entry (`|fast-slow| > 1.5 x threshold`), so it is gated by the strategy's own declared band: outside `m_minScalpTimeframe`..`m_maxScalpTimeframe` (M1-M15) `Init` clears the mode and prints `[MOMENTUM] Scalping input ON but ... outside the M1-M15 band`. Previously `ValidateTimeframeSuitability()`'s result was discarded, so the band was decoration.
- **Candlestick:** `InpCandlestickRequireTrend = false` now reaches `SetRequireTrendAlignment` before `Init`, which is where the flag decides whether the EMA50/EMA200 handles are created. The alignment requirement the operator disabled is gone; counter-trend patterns become eligible.
- **Mean Reversion:** `m_isSynthetic` had no live writer (its only assignment sat in the dead factory creator, whose `meanReversionSyntheticMode` source exists in no config struct). `Init` now sets it from `IsSyntheticIndexSymbolName(symbol)`, so `GetSignal()` routes synthetics to `GetSignalSynthetic()` (1.5-sigma bands + spike, no RSI/volume filter) instead of the FX path. `[MEANREV] Initialized ... path=` names the branch per symbol.
- **Deliberately not wired:** `InpTrendADXNoTrendThreshold` -> `SetADXThresholds(12, 20, 25, 35)`. `CStrategyTrend::Init` reads `m_adxNoTrendThreshold <= 0` as "use asset-class thresholds" and tunes all four per asset class; a wired constant would replace that tuning on every symbol. `Init` already prints `Source=ASSET_CLASS`, so the inert input is visible in the log rather than silently deciding anything.
- **§3 invariants:** unchanged. Signal *eligibility* moved; the two-voter consensus rule, the post-consensus validator, the pre-trade risk gate and the final lot gate did not.

## Batch 193: Four Suppressed Entry Paths Restored, and Registration Comes From the Catalog (2026-10-14)
- **Dormancy no longer re-arms itself.** `IsInDormantCooldown` returned `TimeCurrent() < m_dormantCooldownUntil[idx]` and nothing else touched the array, while `RecordDormancyWarning` fires on any `TRADE_SIGNAL_NONE`, its strike test is `>=`, and only a *signal* clears the counter. A symbol parked for three quiet evaluations therefore met `>= 3` on its first quiet bar after expiry and re-parked for another 30 minutes, indefinitely. Expiry now zeroes both `m_dormantCooldownUntil[idx]` and `m_dormantWarningCount[idx]` and prints `[DORMANT-COOLDOWN] ... cooldown expired, strikes reset`. On the new-bar cadence this restores roughly one evaluated bar per minute per quiet symbol in place of one per half hour.
- **Registry definitions come from the catalog row.** `BuildStrategyRegistry` had fourteen hand-written `enabled = (ArraySize(strategyFlags) > SI_X && strategyFlags[SI_X]); if(enabled) RegisterDefinition("X", STRATEGY_X, ...)` pairs, and Statistical Arbitrage was not among them, so `IsStrategyActive("Statistical Arbitrage")` was false, and `StrategyRegistryState::RegisterStrategy` disabled it with `[ENTERPRISE] Strategy ... disabled by registry` no matter how it was configured. It now loops `CAT_KIND_INDICATOR` rows, using the new `registryType` field, `CatalogEnableSlot(ci)` for the flag, and the row weight; a row with `registryType < 0` prints `[STRATEGY-REGISTRY] <name> has no registryType in its catalog row - it cannot pass the registry filter` instead of vanishing. AI rows stay explicit (their enabled flag is adapter availability, not an input).
- **`InpWeight*` reaches consensus.** `ApplyCatalogWeightOverrides()` runs between `m_registryAggregator.Initialize()` and `InitializeEnterpriseManagers()`, resolving each row through `StrategyConfigWeight(siIndex, rowDefault)` and writing it into `SStrategyDefinition.weight`, which is the value `AutoRegisterStrategies` hands `RegisterStrategy` -> `SetWeight` -> the roster `ConsensusEngine` reads. Previously the inputs reached only `m_descriptors[].weight`, read by `GetWeightByName` (one caller, the AI adapter path) and by the `[STRATEGY-REGISTRY]` report string. Five rows move at their defaults: Candlestick 1.5 -> 0.8, Support/Resistance 1.5 -> 1.8, Statistical Arbitrage 1.8 -> 1.5, Liquidity Sweep 1.5 -> 1.9, Range Compression 1.6 -> 1.7; each prints `[CATALOG] <name> | registration weight A -> B from operator input`.
- **The scalp budget is re-read, not latched.** `ShouldEnterScalp` refreshes `m_config.scalpRiskPct` from `GetScalpBudgetPct()` each cycle and `Initialize` no longer zeroes `maxScalpPositions` on a 0% tier. `PassesEntryGates` refusals print `[SCALP-GATE] symbol | entry refused | usedRisk=%.2f%% of budget=%.2f%% | maxPos=%d | cooldownLeftMs=%d`, throttled to one per minute; before this the gate refused with no output at all.
- **Momentum's cooldown is half a bar.** `cooldownSeconds = timeframeSeconds` was a wall-clock block measured from the moment the signal fired, so a signal at 10:37 in an M5 bar suppressed the 10:40 open's crossover. `m_lastSignalBar == currentBar` already limits the strategy to one signal per bar, so entries per unit time are unchanged except in the bar immediately after a signal.
- **Stop geometry: `maxSlPips = max(price cap, 3 x ATR)` and `takeProfitPips = min(tp, stopLossPips x minRR)`.** When the `max(broker*1.5, spread*3, 8)` floor exceeded a `%`-of-price ceiling, `maxSlPips` was lifted to the floor and TP became `3 x spread x minRR`, so `CheckExecutionCost`'s `spread / takeProfitPips` was `1 / (3 x minRR)` = 0.1667 against the 0.15 limit — a guaranteed veto whose value came from constants. A wider stop lowers the lot for the same currency risk; the per-trade cap, the final lot gate (Batch 190) and `[RISK-GATE-REJECT] ... reason=compliant_lot_below_min` still bind, so this raises entry count without raising risk.
- **§3 invariants:** unchanged. Entries still pass `CUnifiedRiskManager` pre-trade gating, execution is still `CTradeManager`-owned, lifecycle still EA-loop-owned, decisioning still symbol-scoped manager consensus, and `DestroyInstance()` is still the only place shared indicator handles are released.

## Batch 192: One Risk Reservation per Scalp, and the Tier Cannot Size Past the Envelope (2026-10-14)
- **Fast-scalp gate count: two -> one.** `ShouldEnterScalp` -> `CFastScalpEntry::ValidateRiskAndAdjust` (tag `"scalp"`) -> `FinalizeLotSize` (margin cap, can only shrink or refuse) -> `Execute`. The second `ValidateTradeRequest` inside `Execute` (tag `"scalp-pretrade"`) is gone; it repeated the same symbol/side/lot/stops check on a lot the first gate had already approved, and each approval keeps its own virtual reservation until the TTL prunes it, so one scalp double-counted portfolio and daily-budget risk and double-filed `RecordApproval`.
- **Why this one survived:** the entry-stage request sets `strategyRole`, `strategyCluster` and `clusterCode = "T"`; the pre-send request left them unset, so keeping the entry-stage call preserves cluster governance's grouping key.
- **Lot adoption is shrink-only and logged.** `if(result.adjustedLotSize > 0.0) lotSize = result.adjustedLotSize;` would have accepted the pipeline's round-up to `SYMBOL_VOLUME_MIN`; it now requires `< lotSize` and prints `[SCALP-RISK-ADJUSTED] ... lot A -> B | reason=...`.
- **Compounding tier -> sizer is clamped.** `ApplyTierToPositionSizer` now takes the risk manager and clamps the tier's `riskPerTradeOverride` to `GetActiveRiskPerTradePercent()`, which `UnifiedRiskManager.mqh:371` sets from the envelope-clamped base risk. Previously the raw tier number went into `CPositionSizer::SetParameters` (which clamps nothing) and the per-trade cap check refused the trade — a tier that looked active traded nothing, and the refusal looked like a signal drought. `[COMPOUNDING-TIER] Applied to PositionSizer` names the clamp when it binds.
- **`[RISK-ENVELOPE]` fires on a warning-only clamp.** The condition omitted `clampedDdWarning`, so an envelope cutting only the drawdown warning threshold applied silently.
- **Unreachable, recorded not wired:** FastScalp's `[AI-VOTE]` block at `FastScalpEntry.mqh:167` — the only `Initialize` call site leaves `aiAdapter` NULL, and inventing an adapter to produce the log would be fabricating the evidence AGENTS.md §4.2 asks for.
- **§3 invariants:** unchanged and better served — the scalp path still passes `CUnifiedRiskManager` (§3.1) once, on the lot it sends.

## Batch 190: The Risk Gate Now Sees the Lot It Is Approving (2026-10-14)
- **Decision order changed on the consensus path.** `CCandidateBuilder::BuildCandidate` ran `stops -> cost -> capacity -> proposedRisk -> pre-size gate at SYMBOL_VOLUME_MIN -> sizer -> daily-budget cap -> drawdown/momentum scaling -> min-lot round-up -> per-trade cap clamp -> candidate`. The gate is now the last step, after the clamp, and its `tradeReq.lotSize` is `candidate.lotSize`. Everything before it is unchanged.
- **Why one call and not two.** `RiskValidationPipeline.Run` reserves a virtual position for an approval (`:396`) with a microsecond-unique owner tag, and releases it on every rejection branch but **not** on approval; `ClearVirtualPositions()` has no caller, so an approval is counted by the portfolio and daily-budget gates until its TTL prunes it. A second `ValidateTradeRequest` per candidate would therefore count the same trade twice. Moving the one call keeps the reservation count at one and makes its lot correct.
- **New exits from the path, all loud.** `reason=final_lot_validation` when the full gate refuses the real lot; `reason=adjusted_lot_below_min` when the gate asks for a lot that cannot be expressed above `SYMBOL_VOLUME_MIN`; `[RISK-GATE-ADJUST]` when a smaller `adjustedLotSize` is adopted (floored to `SYMBOL_VOLUME_STEP`, never rounded up, shrink-only because the pipeline may raise it to the broker minimum).
- **Correlation REDUCE can now refuse.** A min-lot position reduced by 0.25 floors to 0.0 steps; the branch used to approve anyway and both consumers adopt `adjustedLotSize` only when `> 0.0`, so the discount vanished. It now returns `[RISK-GATE-REJECT] ... reason=correlation_reduce_below_min_lot` and releases the reservation.
- **`ValidateBasicParameters` can now reject on size.** Above `SYMBOL_VOLUME_MAX` it printed "caller must cap" and returned true; it returns false, guarded by `maxLot > 0.0` so a symbol reporting no maximum is not vetoed by an absent limit.
- **Stop distance is now volatility-aware, in one unit.** `CalculateStops` had `atrValue = 0` hard-wired beside a comment saying it "would be passed in real implementation", so the ATR branch never ran; ATR(14) now comes from `CTradeMgrPricing::CalculateATR` (shared handle cache, no per-call handle). The floor compared `GetMinimumStopDistance()`'s price units against raw `STOPS_LEVEL` points, roughly 1e5x too small on 5-digit FX; it is divided by `point` now.
- **The validator quality floor stopped testing itself.** `max(0.40, ctx.directionalQuality * 0.9)` compared to `ctx.directionalQuality` can only fail under the constant, so FULL_QUORUM and SPARSE_INTRABAR ignored the configured 0.68/0.70. The discount now applies to the configured floor: 0.612 new-bar, 0.63/0.595 intrabar. Expect more `filter=quality_gate` lines, not fewer trades than the operator asked for.
- **Untouched:** `ResolveLiveAuthority`'s always-authorize stub (the orchestrator overwrites the three fields from `CLiveAuthorityResolver`), `ApplyDrawdownScaling`'s tautological `floorMult` guard (its result stays below the caller's lot), and the double approval bookkeeping inside one `Run()`.

## Batch 179: The Scalp Budget That Refunded Itself, and Two Logs That Were Not True (2026-10-12)
- **New edge on the live scalp path:** `CFastScalpEntry` market send succeeds -> `CTradeMgrPreflight::FindFreshPositionForSend(symbol, orderType, lotSize, ticket, volume)` -> **hit**: register the tracker slot under the *position* ticket; **miss**: register nothing, `[SCALP-ENTRY] … ticket=0 | position not visible yet, sync will adopt it`, and `SyncScalpPositionTracking` adopts it by position ticket on the next pass.
- **The path this replaces:** the entry registered `CTradeManager::GetLastTicket()` (the *order* ticket) into a tracker keyed by *position* ticket. `SyncScalpPositionTracking` then failed `PositionSelectByTicket`, so `FreeScalpRiskBudget` -> `FreeForTicket` (which also cannot select it, leaving `lotSize = 0.0`) -> `ReleaseFallback()` -> `Release(riskPerTrade)`, and the same pass re-added the position with no `Add`. `m_usedScalpRiskPct` returned to ~0 with the trade open, so `PassesEntryGates`' `usedScalpRiskPct >= config.scalpRiskPct` (tier `scalpBudgetPct`, default 3.0) could only ever block inside the entry tick. `maxScalpPositions` was never defeated: it counts live positions by `SCALP` comment prefix.
- **Authority gate is not an input decision.** `m_liveAuthority.Resolve(...)` (`EAOrchestrator.mqh:3500`) and `ScaleLotByLiveAuthority` run for every risk-approved candidate. `InpEnableLiveAuthorityGate` (default `false` in both `.mq5`) had exactly one consumer, an init print, which is now the unconditional `[AUTHORITY-GATE] … InpEnableLiveAuthorityGate=%s is not consulted by the sizing path`. Making the flag gate the ladder was rejected: a chart holding the saved default would stop shrinking lots.
- **ATR crisis gate logs what it saw.** `result.atrRatio` is still clamped to 10.0 for the decision, but the veto message adds the pre-clamp `raw` value. In the last live session 46 of 71 vetoes printed an identical `10.000` for ratios spanning 10.58x (`54.34286 / 5.13826`) and 431x (`3419.82571 / 7.93232`) — the second is a data fault treated as a crisis, which is fail-safe, and is recorded rather than reclassified.
- **Runtime evidence, and what it can and cannot show:** the EA journals for 17-23 September confirm Batch 175 (no `quality_gate`/`hard_spread_cutoff`/`ofi_*`/`vpin_*` line ever appears; 71 `atr_ratio` lines) and Batch 178 (the three engines appear only as `Initialized`/`PARKED`/`Deinitialized`, `gridsOpened=0`; `[SCALP-ENTRY]` x6 on XAUUSD is the only engine traffic). Nothing after 23 September exists, so `[AUTHORITY-GATE]`, `[ENGINE-STATUS]`, `[VALIDATOR-CONFIG]` and this batch's ticket output are owed from the first attached session.
- **§3 invariants:** unchanged. Entry still passes `CUnifiedRiskManager`, still sends through `CTradeManager`, and position management is still driven from the EA loop.

## Batch 178: `[ENGINE-STATUS]` — Engines the Inputs Turn On That the Loop Never Reaches (2026-10-12)
- **Decision path, stated exactly:** `InitializeComponents` -> `m_spikeHunter.Init/AddSymbol` (`:1211`) / `m_gridRecovery.Init/AddSymbol` (`:1313`) / `m_atrScalping.Init/AddSymbol` (`:1360`) -> `Deinit` on shutdown. No `ProcessTick`, no entry evaluation, no send from any of the three, anywhere in the repository. Their enable inputs (`InpSpikeHunterEnabled`, `InpGridRecoveryEnabled`, `InpATRScalpingEnabled`) all default true, so the configuration says three trading strategies are on while the loop never asks them for a signal.
- **The only engine on the live path** is `CFastScalpEngine`: entry considered at `:2598`, position/pending management at `:3315-3327`, market sends through `CTradeManager` (so it inherits the main path's receipt, partial-fill handling and confirmation), pending-limit sends direct via `FastScalpPendingOrders::Place` (Batch 177 gave that path ticket recovery).
- **What was added:** one `[ENGINE-STATUS]` line at init listing the tick-loop driver and each parked engine with the input that enables it. The per-engine `PARKED` notes already existed; this makes the set legible in one place.
- **What was not done, and why it is not a wiring detail:** connecting the three engines to the loop. It would create exposure on paths that have never traded, at lots from sizing code that has never run — the only change in this audit that increases risk rather than removing it, so it belongs to the operator, not to a batch. Latent behind that same decision: grid restart state loss, and the ATR-scalp/multi-asset magic-band overlap.

## Batch 176-177 Log Truthfulness at the Gates, and Confirmation on the Engine Send Paths (2026-10-12)
- **Batch 176 changed no decision.** It removed a shadow field whose value the `[VPIN] Constructed` line was printing (`m_classificationMode`, never read by `ClassifyTick`), corrected a comment that called the margin gate's construction-fixed 80%/200% "configurable", dropped a README row for `InpCorrelationBlockThreshold` (an input that exists in no `.mq5`), and made `[ENTERPRISE-CONFIG]` name the validator arms that actually run instead of marking the validator `EXOGENOUS_ONLY` while listing confidence and confluence floors that gate nothing.
- **Batch 177 adds confirmation edges to four send paths.** ATR-scalp / spike-hunt / grid-recovery: send -> if the broker's response says failure, `FindFreshPositionForSend(symbol, direction, ...)` (symbol + direction + opened in the last 30 s + EA-owned magic) -> a hit means the fill exists, so `[...] FILL CONFIRMED BY POSITION`, the cooldown and counters arm, and the engine does not re-fire. Grid additionally resolves `ticketOut` from the position by magic (`base + offset + symbolIndex*100 + level`) because its own close path calls `PositionSelectByTicket`/`PositionClose`, which take a position ticket — the order ticket it used to store can never be found, and with `GRID-RECOVERY` comments excluded from lifecycle exits (Batch 170) that position would have no exit owner.
- **Fast-scalp pending**: `OrderSend` false on `TIMEOUT`/`CONNECTION`, or with a nonzero order in the result, now recovers the ticket from live orders by symbol+magic (then positions) and tracks it — `[SCALP-PENDING] PLACEMENT RECOVERED` — instead of returning false and letting the next scan place a second order behind the one the server already accepted.
- **Ownership unchanged, deliberately:** the engines still send on their own objects, so AGENTS.md §3.2 is still not literally met for these paths. The reason is on a live book: re-routing the send recomputes the magic and comment that existing positions are identified by.
- **Open, found this batch and not fixed:** grid level tickets are in-memory only, so a terminal restart leaves the engine holding no tickets for positions it still owns, and lifecycle management refuses engine comments. The positions run to their own SL/TP with no manager. A rescan-by-magic at init is the fix and is queued, not folded in.

## Batch 175 Post-Consensus Validator Plugged Into Its Configuration (2026-10-12)
- **The gap:** `CPostConsensusValidator::SetValidatorConfig(...)` is declared, defined and forwarded by the manager, and had no call site. Everything downstream of it ran on constructor defaults, so the decision path silently differed from the inputs dialog.
- **New edges into the existing gate order** (`consensus → ValidateSignal`: hard spread cutoff → exogenous ATR/spread → quality class → OFI confirmation → VPIN): OFI confirmation and the VPIN arm now execute when their inputs are enabled, both default ON, and the quality thresholds come from `InpValidator*MinQuality` instead of 0.72/0.75.
- **Spread cutoff stays floored.** `MathMax(InpHardSpreadCutoffPoints, InpMaxEntrySpreadPoints)` — the input's 200-point default sits below the 1,727-11,140-point spreads the synthetic book trades at, and the setter's own 1000-point guard is below them too. Passing the raw input would have vetoed every synthetic at init; the [BUGFIX] note in the constructor records that exact failure.
- **Safe mode tightens through existing owners** (conservative tier only, inert on the live `RISK_TIER_MODERATE`): voter floor and quorum threshold via the manager's quorum setters after `ApplyQuorumProfile`, spread/ATR via the pipeline's regime-cost gate, and `noStacking` via the builder's per-symbol position cap. No parallel counters were introduced.
- **What authority does not have:** `minConfluence` has no consensus knob; `tradeOnlyKillZones` is FX-session hours applied to 24/7 synthetics and is not enforced; `avoidNewsEvents` has no calendar feed. `[INIT] Conservative safe mode ENABLED | enforced: ... | not enforced: ...` prints the split so the operator reads it at attach.
- **Still decoration, recorded not fixed:** the spike-hunter arm inside `ValidateSignal` is an empty no-op branch, and `validator*MinConfidence` / `MinConfluence` are read only by the `[ENTERPRISE-CONFIG]` line.

## Batch 174 VPIN Veto Armed and the Post-Size Clamp Made Truthful (2026-10-12)
- **New veto edge:** `consensus → CPostConsensusValidator::ValidateSignal → CheckVPINFilter → false` when `CVPINFilter::ShouldBlockNewPositions()`. The `vpin_toxicity` reject branch existed in the caller and had no path into it; `CheckVPINFilter` returned true on all three of its arms. Result: no entry, per-candidate `[POST-CONSENSUS-FILTER] ... filter=vpin_extreme | VETO`.
- **Thresholds now read from the filter.** The old literals (0.95, 0.85) sat above the configured EXTREME line — `InpVPINExtremeThreshold` default 0.70, clamped 0.30..0.95 — so on default config the extreme arm was unreachable and everything under 0.85 was reported as if no filter had run. Regime comes from `GetToxicityRegime()` / `ShouldBlockNewPositions()` now.
- **Fail-open preserved on purpose.** A missing VPIN filter means the symbol has no traded volume (Batch 170 stopped building them for synthetic indices), not that order flow is toxic. Making that fail closed would have stopped all synthetic-index trading.
- **Post-size clamp path (`BuildCandidate`)**: risk over cap → lot scaled to cap → floored to `SYMBOL_VOLUME_STEP` → **if under `SYMBOL_VOLUME_MIN`, refuse** (`[RISK-GATE-REJECT] reason=compliant_lot_below_min` + `RiskGateReject` JSON). Before, this step rounded up to the minimum and then set `candidate.riskPercent = riskCap`, so the daily entry budget booked a risk the position did not carry.
- **Deleted from the sizing path:** `ApplySkewStepScaling`, `ApplyFullMarginStacking`, `ApplySafeModeRestrictions`, and the `EvaluateEAModeAdmission` call plus definition. Each returned its input untouched; the admission stub also made its rejection branch and confidence bonus unreachable.
- **Ownership restated:** mode admission is `CLiveAuthorityResolver`'s (`INDICATOR_ONLY` / `AI_ONLY_MODE_NO_AI`), VPIN size is `CVPINLotModifier`'s, VPIN veto is the validator's, and the entry-side of conservative-tier safe mode belongs to nobody yet — recorded in SYSTEM_STRUCTURE.md rather than papered over.

## Batch 173 Live-Authority Ladder Applied to Position Size (2026-10-11)
The Batch 172 scope limit above was closed by operator decision: "apply the full ladder, but don't make things fall silently."

- **New node in the entry path.** Between the authority `allowed` test and the send, `EAOrchestrator` (`EAOrchestrator.mqh:3517`) calls `CCandidateBuilder::ScaleLotByLiveAuthority(candidate, authority.riskMultiplier, cycleCorrId)`. Returning false drops the candidate exactly like a veto; returning true rewrites `candidate.lotSize` before `CTradeExecutor::Execute`.
- **Order matters and is preserved:** consensus → `CUnifiedRiskManager` pre-trade gate → lot sizing in `BuildCandidate` → authority resolve → authority scale → send. The ladder multiplies a size the risk manager already approved and can only shrink it (top rung 1.0; `PROVEN_AI`'s raise is clamped to the 0.75 promoted cap), so it cannot bypass AGENTS.md §3.1 or break the Batch 152 post-size re-gate.
- **Broker minimum is now a refusal, not a round-up.** The step floor is applied by hand against `SYMBOL_VOLUME_STEP` (8-digit normalization, `MathFloor(v/step + 1e-9)`), not through `CPositionSizer::NormalizeVolume`, which clamps *up* to `SYMBOL_VOLUME_MIN` (`PositionSizer.mqh:659`) and would silently return the entire reduction. A sub-minimum result logs `[AUTHORITY-REJECT]` twice, writes an `AuthorityReject` JSON event, and increments per-symbol and session counters.
- **Booked risk tracks the lot.** `candidate.riskPercent` is scaled by the same ratio before the send, so `RegisterExecutedTradeRisk` charges the daily entry budget for the risk actually taken rather than the pre-shrink intent.
- **Tags AGENTS.md §6 had been claiming since Batch 168 are now emitted:** `[AUTHORITY-REDUCED]` on every shrink and `[AUTHORITY-REJECT]` on every refusal. `FMT_AUTHORITY_REJECT` / `FMT_AUTHORITY_REDUCED` existed in `Core/Utils/LogMacros.mqh:41-42` with no writer.
- **Silence is now distinguishable from absence.** `[CandidateBuilder]` status prints `authorityLotRefusals total=N` plus a per-symbol breakdown; previously a symbol the ladder had sized out of existence looked identical to a symbol with no signals.
- **Still a veto-free ladder:** `result.allowed` remains `true` unconditionally at the end of `Resolve()`. Authority expresses itself through size, not through permission — the only vetoes are still the two mode checks, `LOW_CONFIDENCE`, and this batch's under-minimum refusals.

## Batch 172 Live Authority Thresholds Wired and Promotion Gate Made Reachable (2026-10-10)
- **`PROVEN_AI` could never fire.** `Resolve()` gated promotion on `m_strategyPerf[i].profitFactor >= 1.2`, but `RecordOutcome` only ever updated `totalTrades`, `winningTrades`, `expectancyR` and `consecutiveLosses`; `profitFactor` stayed at its constructor 0 for the life of the process. Every AI-only contributor was therefore pinned at the bootstrap cap no matter how it traded, and the `MathMax(riskMult, promoted)` branch was dead code. The Batch 154 docs describing "promotes to PROVEN_AI >= 0.75x after 30 trades with PF >= 1.2" described an intent that had never executed.
- **Profit factor is now computed** from the R-multiple stream already delivered to `RecordOutcome`: cumulative `grossWinR` / `grossLossR`, accumulated by the sign of `profitR` so a breakeven close enters neither side. A record with no losing trade reads as a perfect one (`999.0`) instead of dividing by zero. `maxDrawdownR`, a field with no writer and no reader, was removed.
- **The resolver's configuration surface was ignored, not merely mis-valued.** `EAOrchestrator` called `Configure(effectiveMode, m_config.aiStandaloneMinConfidence, 0.5, 2, 0.3)` — three literals, one of which (`0.3`) overrode `config.authorityMinExpectancyR` at 10x the configured `0.03`. Six `InpAuthority*` inputs (`authorityMinSamples`, `authorityMinProfitFactor`, `authorityMinCostScore`, `authorityMinReadinessScore`, `authorityMinContextScore`, `aiPromotedRiskMultiplier`) reached `config` and were read by nothing. `Configure` now takes every threshold, with no default arguments so a future call site cannot reintroduce a literal.
- **Configured values may tighten, never loosen.** The floors (`AUTHORITY_MIN_*` defines) are the documented design values: 30 samples, expectancyR 0.3, PF 1.2, cost 0.50, readiness 0.60, context 0.55, bootstrap cap 0.5, promoted cap 0.75. An input left at its declared default is silently looser than that in four places, so it is clamped upward at init and announced as `[AUTHORITY-CONFIG] clamped ...`. The effective set is always printed as `[AUTHORITY-CONFIG] effective: ...`. This mirrors the Batch 169/170 rule that an override may lower authorised risk but never raise it.
- **`costScore` authority bonus was inverted.** `if(costScore <= 0.3) authorityScore += 0.05; // Low cost` paid authority points to the most expensive trades: `costScore` is quality-shaped (`SignalPipelineWeighter` adds it into the weighted score as `costScore * 0.0543`), so higher means cheaper. Now `if(costScore >= m_authorityMinCostScore)`. Expensive trades no longer collect the bonus they were wrongly paid.
- **Readiness and context bonuses** use the configured floors instead of the literals 0.6 / 0.55.
- **Verification surface added:** `[LiveAuthorityResolver]` status now prints the effective thresholds plus per-strategy `pf=` and `eligible=Y|N`, so a live session can show whether the gate is armed rather than leaving it inferred from the absence of `PROVEN_AI`.
- **Scope limit found mid-batch, and not silently patched over:** the resolved multiplier reaches nothing. `authority.riskMultiplier` is copied to `candidate.liveAuthorityRiskMult` (`EAOrchestrator.mq5:3418`) and read by no code in the repository, and `result.allowed` is assigned `true` unconditionally at the end of `Resolve()` — so the only live authority effects are the `INDICATOR_ONLY` / `AI_ONLY_MODE_NO_AI` mode vetoes and `LOW_CONFIDENCE`. The score ladder, the bootstrap cap, `PROVEN_AI` and every bonus therefore change what is logged, not what is traded. Batch 172 makes the promotion branch reachable and its log honest about which branch was taken; making the magnitude act requires multiplying it into `CPositionSizer`, where `CVPINLotModifier` / `CADXLotModifier` / `CVolatilityTargetingModifier` already scale the same base size. That is a live-sizing decision, left open. **Closed by Batch 173 (section above).**
- **Still missing, not built here:** per-family demotion to shadow, and the trial-tracking the dead `authorityTrialHorizonSeconds` / `authorityMaxTrackedTrials` / `nonAIPromotedRiskMultiplier` inputs imply. `[LIVE-AUTHORITY]`, `[AUTHORITY-TRIAL]` and `[AUTHORITY-RESULT]` appear in no source file. Building trial windows and demotion rules would be inventing policy, so §2.9.1 of SYSTEM_STRUCTURE.md now states plainly what is implemented and what is not.

## Batch 170 Engine Send Governance, Min-Lot Ceiling, Volume Honesty (2026-10-09)
- **Stop gates reach the engine paths:** `CTradeMgrPricing::NormalizeAndValidateStops` now runs before every send in `ATRScalpEntry`, `GridRecoveryExecution`, `SpikeHunterExecutor` and `FastScalpPendingOrders`. Those paths build their own `CTrade`/`MqlTradeRequest`, so Batch 169's broker-minimum, stop-widening and target-expectancy checks did not reach them. Rejection logs `[ATR-SCALP] STOPS REJECTED` / `[GRID-RECOVERY] STOPS REJECTED` / `[SPIKE-HUNT] STOPS REJECTED` / `[SCALP-PENDING] STOPS REJECTED`.
- **Min-lot round-up capped:** `MAX_MIN_LOT_RISK_MULTIPLIER` (3.0) bounds how far a sub-minimum lot may be rounded up after the pre-trade gate approved it; the configured 15.0 is clamped with `[RISK-MINLOT]`.
- **Daily-loss breaker armed:** `CPosLifecycleLossGuard` budget was unwritable (`m_dailyRiskBudgetPercent` had no setter); now set from `m_config.maxDailyRisk` and evaluated against `min(balance, equity)` at check time.
- **One exit authority per book:** positions whose comment starts with `ATR-SCALP`, `GRID-RECOVERY`, `SPIKE-HUNT` or `SCALP|` are EA-**owned** (risk, exposure, daily loss still count them) but excluded from lifecycle exits via `CPosLifecycleMagicFilter::IsLifecycleManaged` / `CPositionLifecycleManager::IsPositionLifecycleManaged` / the tag test inside `CTradeManager::ManageAllPositions`. Before this, Batch 168's newly-live breakeven and trailing were fighting the fast-scalp engine's own 1R and partial closes.
- **Comment matching tightened:** `FastScalpExit` and `FastScalpPositionTracker` matched `"SCALP"` as a substring, which also matched `ATR-SCALP` — one engine was claiming another's positions. Both require index 0.
- **Volume-derived vetoes:** OFI and VPIN are no longer created for synthetic-index symbols (the exclusion Batch 107 already applied to VWAP/Volume Profile/CVD), and `[VOLUME-PROXY]` logs per symbol when the broker publishes no traded volume, so tick-volume-as-real-volume is labelled rather than assumed.
- **Two fake sizing steps deleted:** `ApplyVPINScaling` and `ApplyVolTargetScaling` were `return lotSize;` stubs under comments claiming they resized; the report's `LastVPINMultiplier` was never consumed.
- **Unchanged hazard, deliberately:** the engine paths still send outside `CTradeManager`, so they get no fill verification, retry dedup or journal entry. AGENTS.md §3.2 is still not literally satisfied for them.

## Batch 169 Execution Truthfulness and Cost-Aware Entry Gates (2026-10-08)
Second tier of the live-money audit; the decision path now verifies what it did and refuses trades that cannot pay for themselves.
- **Entry gate — quorum:** `effectiveMinVoters` floor raised from 1 to `MIN_CONSENSUS_VOTERS 2`. A single live voter no longer constitutes consensus; symbols with fewer than two eligible voters abstain instead of trading.
- **Entry gate — confirmers:** every indicator-absent / short-copy path in `SimpleMomentum.MACDConfirmed|StrongTrend`, `VolatilityBreakout.ADXRising`, `MeanReversion.StochasticExtreme|NoDivergence|SufficientBandWidth|MeanRevertingRegime`, `StrategyTrend.IsHTFTrendConfirmed`, `StrategyCandlestick.IsShortTermTrendAligned` and `StatArb.ValidHalfLife` flipped from `return true` to `return false`. `MeanReversion.GetADX` returns a `-1` sentinel that hard-rejects with `MEANREV_ADX_UNAVAILABLE` rather than `0.0` clearing the ADX lockout. Data loss now means "no trade", not "unvetted trade".
- **Entry gate — bar anchoring:** `VolatilityBreakout.CalculateFallbackBB|CalculateFallbackATR`, `LiquiditySweep.FindEqualLevels` + its ATR read, and `RangeCompressionBreakout`'s trend-filter MA all moved from the forming bar (shift 0) to the last closed bar. Stops and breakout levels no longer re-derive from the bar in progress.
- **Entry gate — expectancy:** `CTradeMgrPricing::NormalizeAndValidateStops` rejects when the take-profit distance is under `MIN_TP_COST_MULTIPLE` (4x) the round-trip spread cost. New `GetRoundTripCostPrice` is the single cost definition; `GetRoundTripCommissionCost` no longer double-counts the spread and no longer divides an already-points `SYMBOL_SPREAD` by `tickSize`.
- **Pre-trade risk gate:** `CUnifiedRiskManager` captures a configured-limits *envelope* before any compounding tier can write, and `ApplyTierOverrides` clamps risk per trade, daily, portfolio, drawdown warning/critical, daily-loss limit and same-base position caps to it (`[RISK-ENVELOPE] ... clamped`). Tier tables can reduce authorised risk, never raise it.
- **Execution confirmation:** a send is confirmed only by a live position matching symbol, direction and EA-owned magic within 30 s (`FindFreshPositionForSend`); `order = 0` logs `[EXECUTION-UNTRACKABLE]`; queue expiry logs `[EXECUTION-CONFIRMED-BY-POSITION]` or `[EXECUTION-UNCONFIRMED]` + `[RISK-UNRECONCILED]`.
- **Retry:** the transient-retcode retry loop checks for a fresh position first and stops with `[EXECUTION-DEDUP]` rather than resending into a fill it already has.
- **Stops:** `NormalizeAndValidateStops` can now reject (it previously always returned `true`); it captures the distance lots were sized at and refuses a broker-forced widening above 1.25x. `GetMinimumStopDistance` floors at max(stops level, freeze level, 1.5 spreads, 10 points), so a 0-point broker stops level no longer licenses a 1-point stop.
- **Send parameters:** filling mode is applied to the pooled per-symbol `CTrade` that actually sends (previously configured the unused instance), with `ORDER_FILLING_RETURN` as the fallback; per-send deviation honors the dynamic-slippage config and excess is logged.
- **Abstention:** `StatisticalArbitrageStrategy` returns `TRADE_SIGNAL_NONE` with `[STATARB-UNHEDGED]` because only one leg of its pair signal is executable.
- **Universe validation:** `symConfig.maxSpreadPoints` now reads `symbolMaxSpreadPoints` (1500; builder applies the documented 10x synthetic allowance) instead of the 15000-point send-time backstop that made the init filter a no-op.

## Batch 168 Magic Ownership Authority and Live Exit Wiring (2026-10-08)
- **One ownership predicate:** `Core/Utils/MagicRange.mqh` (`ConfigureMagicOwnership`/`IsMagicOwned`/`ValidateMagicOwnershipCoverage`) replaces five disagreeing windows. Because orders carry an asset-class magic offset of 7000..9999, most EA positions previously read as foreign, so trailing, breakeven, pyramiding, loss guards and no-SL remediation returned early *without logging*. Startup now asserts the shipped offset fits the window and aborts rather than trading an unmanaged book.
- **One exit authority:** `ManageOpenPositions()` calls `CPositionLifecycleManager::ManagePositions()` — the manager that actually receives `ConfigureSRE`/`ConfigureLifecycle`/`ConfigureMaxHoldTime` — replacing the never-configured `CPositionManager` path.
- **Position management from terminal state:** `CTradeManager::ManageAllPositions` scans `PositionsTotal()` through the ownership authority instead of an in-memory ticket cache, so positions that survive a restart or fill asynchronously are still managed.
- **Continuous breakers:** `CheckDrawdownCircuitBreaker()`/`CheckDailyLossLimit()` are called from `RefreshRuntimeState()`, not only from the pre-trade pipeline, so drawdown and daily-loss halts arm even when no candidate reaches the risk gate.
- **Emergency flatten is EA-scoped:** `CloseAllPositions` filters by ownership; account-wide flatten requires `emergencyFlattenAllAccountPositions`, whose default flipped to `false`.
- **Crash recovery:** risk state is applied *after* `CUnifiedRiskManager::Initialize` (previously always clobbered), written on a 30 s cadence via `GetTickCount()` so a stalled-tick crash still persists, and carries `halt_flags` + `trading_day_key` (version:2).
- **Daily loss is EA-scoped:** realized deals filtered by magic with `DEAL_ENTRY_OUT_BY` included, unrealized summed over EA-owned positions only.

## Batch 158 Signal-Suppression Audit Sweep — Unaudited Strategy Files (2026-08-28)
Final sweep of the signal-suppression audit campaign. Remaining unaudited strategy files and one efficiency defect in S/R strategy Fibonacci confluence helper:
- **TrendEntryTypes.mqh / TrendSignalEnhancers.mqh:** `GetATR()` forming-bar (shift 0) → closed-bar (shift 1). ATR normalization no longer flips range gates early each bar.
- **FourStateRegimeDetector.mqh:** KAMA trend slope and regime classification read `iClose(...,0)` → shift 1 (last closed bar). Regime state stable intrabar.
- **StatisticalArbitrageStrategy.mqh:** `CalculateSpreadStatistics()` static array oldest-first read → dynamic array with `ArraySetAsSeries(true)` so `[0]` = newest closed bar. Spread stats use correct bars.
- **BreakerBlockStrategy.mqh / FVGScalperStrategy.mqh / TurtleSoupStrategy.mqh:** FX-calibrated `SYMBOL_POINT` pip conversions → ATR-denominated scale-free pips (1 ATR = 1 unit). No FX calibration; entries no longer scale-distorted on synthetics.
- **StrategySupportResistance.mqh:** `ApplyFibConfluence()` per-call `iATR` create/release → cached shared handle via `CIndicatorManager::Instance().GetATRHandle()` in `Init()`. No handle churn per signal.
All 7 EAs compile 0 errors / 0 warnings.

## Batch 157 Scout-Findings Sweep Closure (2026-08-24)

## Batch 156 Detector-Layer Repairs (2026-08-24)
Decision inputs feeding strategy votes are now computed from closed bars and correctly anchored:
- **Candlestick chain:** hammer/pin-bar/doji/engulfing/star patterns evaluate the last CLOSED bar with fail-closed ATR sanity gates; inverted-hammer vs shooting-star decided by prior-trend context and scored on the dominant wick; pattern confidence = 50% pattern strength + 50% confluence (multiplicative deflation removed); SL padding floored at 0.15×ATR.
- **Closed-bar state latching:** SR rejection candles, breakout detection (levels are consumed only by closed-bar closes), OB mitigation, FVG rebalance, session-gap fill status and structure-break classification all ignore intrabar pokes — tradeable/untradeable sets can no longer flip tick-by-tick.
- **Trendlines:** anchor pairs ordered oldest→newest correctly (the detector previously built zero lines) and slope angles normalize ATR-relative, so angle gates behave identically on FX and synthetics.
- **ICT detectors:** Source OB = last opposite candle before the impulse (was the oldest in a 20-bar window → stale zone anchors every scan); external swing liquidity emits both sides under per-side budgets; BMS classification by PeriodSeconds revives H2–H12 charts; session-gap minimum size fails closed without ATR instead of accepting point-scale phantom gaps.
- **Trailing:** unwarmed EMA/ATR feeds yield "no trail"; TRAIL_HYBRID cannot emit a degenerate near-zero stop for sells.

## Batch 155 Strategy Emission-Path Repairs (2026-08-24)
- **Series-ordering corrections (decision-path effect):** static (non-series) buffers fill OLDEST-first under CopyBuffer; several strategies read them newest-first. Repairs that change live decisions: `VolatilityBreakout.ADXRising()` was inverted (gate demanded ADX falling → `VOLBREAK_ADX_NOT_RISING` rejected nearly all breakouts); `SimpleMomentum` MACD confirmation, volume-surge slot, ROC acceleration mapping, RSI-divergence window and crossover-hysteresis scan direction were all reversed (hysteresis ≥2 was a total kill-switch); `MultiEMASystem` buffers are reverse-mapped to `[k]=shift k+1` so StrategyTrend crosses/slope/alignment/consistency evaluate on recent closed bars instead of nine-bars-stale data; `StrategyTrend.MACDConfirmed` now/prev un-swapped; `MeanReversion` divergence window fixed and synthetic-mode band touches judged on shift-1 bands.
- **Scale corrections:** Momentum's absolute ATR floor (`m_minVolatility`) is capped at 1 basis point of price (M1 FX charts were permanently `MOMENTUM_LOW_VOLATILITY`) and the volatility confidence tax compares current ATR to the symbol's own 10-bar ATR average (was: ratio vs the FX-scale floor — ~100× on synthetics, permanent 40% haircut). TrendEntryTypes pullback tolerance widens to max(configured points, 0.25×ATR) — 15 points ≈ 1.5 pips made pullback entries unreachable.
- **Confidence economics:** MeanReversion RSI-only base 0.58→0.65 and BB-touch 0.60→0.70 with ×0.90 no-Stoch penalty — both tiers clear the 0.60 floor while staying below DOUBLE_SIGNAL. LiquiditySweep DAILY_HIGH/LOW sweeps earn +0.10 level bonus (were default-zero, maxing under the floor) and stops are placed beyond the swept wick extreme (level ∓ wick×1.1) instead of inside already-traded price.
- **Wiring:** Statistical Arbitrage receives the Python bridge in the orchestrator dependency-wiring pass (the catalog registration path never injected it — bridge-up registration still produced permanent `STATARB_PYTHON_BRIDGE_UNAVAILABLE` rejections).
- **Session/synthetic gates:** NYOpenGap + AsianRangeBreak skip the full `IsSyntheticIndexSymbolName` umbrella (DEX/RangeBreak/Trek/etc. previously ran meaningless session logic, weekend "gaps" included). AsianRangeBreak's exact=true M5 bar lookup relaxed to exact=false (one missing midnight bar no longer kills the day) and its tightness filter compares against a sqrt-of-time-scaled expected 6h range (per-bar chart-TF ATR was unsatisfiable on M1/M5, vacuous on H4/D1).
- **RangeCompression:** all reads moved to closed bars (shift 1; forming-bar close≈open made the breach test a timing lottery and partial tick volume biased volume confirm false); the counter-trend FADE branch is exempt from the trend filter (it fired counter-trend by design and was always `TREND_FILTER_REJECT`ed).
- **Deliberately unchanged:** consensus quorum/risk gating untouched; Turtle Soup (sweep+CISD conjunction), Breaker Block (single-zone rebuild) and FVG (strongest-zone-only) scarcity documented as design.

## Batch 154 Product Decisions Executed (2026-08-24)
- **Closed-trade feedback is live (behavior activation):** EA `OnTradeTransaction` → `ProcessManagerTradeTransactions`. Manager fan-out runs per-strategy attribution/health; full closes of EA-owned positions (partial closes excluded via `POSITION_IDENTIFIER` re-check) feed `CPerformanceAnalytics::RecordClosedTrade`, loss-guard accounting, and `CLiveAuthorityResolver::RecordOutcome`.
- **Governance loop:** strategy auto-disable (win-rate floor / consecutive-loss limit) removes a voter for a 1-hour cooldown; an orchestrator-owned 60s sweep in `ProcessTradingLogic` re-enables cooldown-served strategies regardless of AI mode. Recovery predicate fixed: serving the cooldown suffices (post-disable wins were unreachable), and the rolling sample resets on re-enable so stale losses cannot insta-redisable.
- **AI promotion path:** executed AI-contributed trades store provenance (position id → contributor summary + owning manager) at send time; on full close the resolver records the outcome (`[AUTHORITY-LEARN]`). At ≥30 tracked trades with expectancyR ≥0.3, PF ≥1.2, <4 consecutive losses, AI candidates promote from bootstrap cap to ≥0.75× risk (`PROVEN_AI`). Cap unchanged below that bar; R approximated as netProfit / (equity × maxRiskPerTrade/100).
- **Parked by decision:** SpikeHunter/GridRecovery/ATRScalping stay unwired — init logs now state `PARKED: not wired into the tick loop`; VPIN/institutional layer stays documented-dormant.

## Batch 153 Hygiene Closure (2026-08-24)
- **Heartbeat funnel counters are live:** the scan loop now writes `scans` (every symbol slot), `no_signal` (generator-empty slot) and `validator_reject` (`ValidateSignal` fail) into `CHeartbeatTelemetry`. `[HEARTBEAT] scans/no_signal/validator_reject` and the status report `Scans=` field were hard-zero before this batch because no writer existed — all-zero baselines in old logs are NOT expected values going forward. Decision semantics unchanged: these counters are observability only, nothing branches on them.
- **Attribution contributor split:** `RecordAttribution` splits the candidate's contributor CSV via `CTradeAttributionManager::SplitContributors`; attribution rows now list individual contributors instead of one malformed combined string.
- **Init-failure cleanup parity:** `CleanupOnInitFailure()` performs the same release sequence as `Shutdown()` (math hub -> EA-owned sizing modifiers -> neural nets/drawing managers -> Deriv-engine deinits -> TradeManager deinit -> scalp cache -> uncertainty -> registry -> AI subsystems -> error-handler singleton -> bridges), so a failed init after subsystem creation leaves no objects or indicator handles behind.
- **Dead code removed (zero callers):** `CErrorHandling` wrapper; `CPositionManager`/StateStore `RemoveStalePositionStates` / `GetAllPositionStateIds` / `IsPositionStateInitialized` / `PrintPositionStateDebugInfo` / `ClearAllPositionStateMaps(+ClearAllPositionStates)` chain; `CSignalGenerator::SetEvalBudget` / `GetLastDecisionContextFromManager`.
- **Documented unwired (product decision pending):** the closed-trade feedback loop — `CEnterpriseStrategyManager::OnTradeTransaction` (per-strategy performance/health/auto-disable), `CPerformanceAnalytics::RecordClosedTrade` (account win-rate/PF/momentum/drawdown feeding the momentum lot scale and URM snapshots) and `CPositionMgrLossGuard::RecordClosedTrade` (consecutive-loss accounting) have no call sites. All consumers treat "no data" as neutral today; wiring them ACTIVATES adaptive behavior and requires an explicit decision.

## Batch 152 Full Audit Closure (2026-08-23)
- **Sizing geometry (live behavior):** `CalculateRiskPerLot` now computes SL distance as `stopLossPips * point` — identical to where execution actually places stops. The former ×10 inflated risk-per-lot, so every fixed-risk entry sized ~10x below configured risk. Post-deploy lots are visibly larger by design; the post-size risk gate remains binding.
- **Magic routing:** explicit magic overrides (`OpenPosition(magic>0)`) ship verbatim via `m_pendingExplicitMagic`; zero still derives base+symbol-offset. SpikeHunter tickets are EA-owned again; manual-close restore gates use the same `IsEAOwnedMagic` range check.
- **Async send path** enforces the mandatory-SL invariant (block + `[EXECUTION-BLOCKED] reason=MandatoryStopLoss | path=async`), matching the sync gate.
- **Scalp fast path is self-sufficient per tick:** cache refresh at head (new-bar throttled), then sync-tracking -> manage -> pending-order/async checks; deal confirms arrive via `OnTradeTransaction`. Partial-profit exits are once-per-ticket latched.
- **Live-authority gates are configured:** resolver candidate gates read policy from `m_liveAuthority.Configure(...)` instead of defaults; spike-detector magics moved to offset 9150 (9000 collided with DERIV_CRASH_BOOM).
- **Symbol-budget path cost:** win-rate/profit-factor feed the allocation weight from a 60s memoized single-pass scan (was: full-history materialization twice per symbol per refresh).
- **Conservative flag ownership:** only the circuit breaker lowers conservative mode (bool& write-backs); analytics may raise it. No more next-validation wipe of breaker escalation.
- **Correlation queries are prune-safe:** both query symbols pinned across the internal matrix refresh; indices re-resolved after.
- **Margin health authority split (documented):** pre-trade free-margin/margin-level gate = pipeline Step 6 (live); periodic margin monitor = intentionally unwired so the circuit breaker stays the single reactive-flatten authority.

## Batch 150 Runtime Corrections (2026-08-23)
- `ProcessNewBars` now actually runs: it was gated behind `CRegistryAggregator::GetScanScheduler()` which always returned NULL, so no symbol ever received `OnNewBar` and the consensus cache was never invalidated on bar close. It is wired through `CScanSchedulerRegistry::CheckNewBar`.
- NEW_BAR signal evaluation is per-symbol bar-gated inside `CSignalGenerator` (`m_lastEvalBar[]`): a symbol's consensus is evaluated once per closed bar, not on every 1s timer pass. Dormancy warnings therefore accrue per bar, not per second.
- Signal results are stored by manager index (`results[managerIdx]`); the consumer in `GenerateAndProcessSignals` pairs each result with its own symbol/manager. Previously a densely appended result array caused wrong-symbol validation/execution.
- The min-seconds-between-trades cooldown is functional again: `m_lastTradeTime` is stamped on successful execution (it was declared but never written).
- Scalp fast path is throttled to 1s; five per-tick JSON performance logs were removed from `OnTick`.
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
- **Layer 6 Fix (Batch 130)**: Intrabar policy `PROBE` mode now fully wired through EA inputs → `SOrchestratorConfig` → `AutoRegisterStrategies()`. Strategies 15-16 (NY Open Gap, Asian Range Break) now use configured intrabar policies instead of hardcoded `INTRABAR_POLICY_OFF`.
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
- Structural admission is now manager-owned: once manager consensus admits a packet, the validator no longer re-judges confidence, confluence, or support ratio. `directionalQuality` is still re-judged by the quality gate, whose threshold for a `FULL_QUORUM` packet is `max(0.40, directionalQuality * 0.9)` — self-satisfying above 0.40, so the gate only ever rejects a quality below that absolute floor.
- The validator runs `spread_cutoff → exogenous_atr → quality → ofi → vpin` on every admitted packet (Batch 175 wired the OFI/VPIN arms to their inputs; before that the arms existed but no configuration call site reached them). The older `EXOGENOUS_ONLY` label in a pre-Batch-175 journal is stale text, not a mode switch — no runtime mode skips those arms.
- Validator profile inputs (confidence + confluence) remain logged and configurable as telemetry/fallback surfaces, but they are not a second structural veto authority when manager-owned admission is enabled.
- Validator still consumes manager quorum evidence (`effectiveMinVoters`, `directionalQuality`, `supportRatio`) so exogenous validation telemetry and any legacy fallback mode stay aligned with the already-authoritative manager decision.
- Strategy overrides that bypass base-class `GetSignal(...)` must emit explicit last-decision tags; manager now downgrades any remaining placeholder abstentions instead of treating them as fully ready neutral voters.
- Protective lifecycle thresholds are now risk-relative: breakeven, trailing, and partial-close activation must clear both the configured pip floor and a fraction of the trade's original stop distance.
- Protective stop modifications are validated against executable quote side with extra stop/freeze cushion and one widened retry on `TRADE_RETCODE_INVALID_STOPS`.
- The EA-level generic breakeven/trailing loop is now opt-in via `InpEnablePositionLifecycleManager`; when left off, only strategy-defined SL/TP and risk/execution protections manage the trade.

### Slot Resolution — which policy row a strategy actually reads (Batch 147, semantic-only)

Before Batch 146 the intrabar policy slot was resolved from the catalog's legacy `policyIndex`, which did not match the `StrategyConfigBuilder` slot table, and the always-LIVE fallback was hardcoded to slots `9/10`. Batch 146 made the scheme switchable; **Batch 147 removed the legacy scheme entirely**, so resolution is now unconditional semantic.

Resolution order:

1. `BuildStrategyFlags` writes `strategyFlags[]` at `SI_*` slots (sole producer; since Batch 209 it walks the catalog's indicator rows instead of naming strategies, and `ConfigEnableForSlot` is the one slot -> operator-input switch).
2. The policy loop pushes `strategyIntrabarConfigs[0..22]` into `CIntrabarPolicy::m_policyConfig` (32 slots).
3. `AutoRegisterStrategies` resolves each row's enable slot via `CatalogEnableSlot(i)` (→ `SI_*`) and its policy slot via `CatalogPolicySlot(i)` (→ the strategy's own `siPolicyIndex`). Both are unconditional.
4. `CIntrabarPolicy::GetIntrabarPolicyHelper(idx)` returns the configured policy if it is not `OFF`; otherwise it applies the always-LIVE fallback for the Mean Reversion / Volatility Breakout pair at fixed semantic slots `7/8`.

Enable-flag resolution: `CatalogEnableSlot(i)` returns the strategy's `SI_*` slot. Since `BuildStrategyFlags` is the only writer and writes `SI_*` slots, reader and writer agree by construction.

`[CATALOG-AUDIT]` lines are emitted at registration time on every boot: `slot_scheme=SEMANTIC (legacy literals removed in Batch 147)` plus each strategy's `enable_slot=` / `policy_slot=`. There are no MISMATCH or DEAD_SLOT lines because only one scheme exists.

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
- **Layer 6 Fix (Batch 130)**: `PROBE` mode now fully wired through config chain; `ENUM_INTRABAR_POLICY` replaces hardcoded boolean `intrabarEligible` at registration.
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
- Applied in `CTradeManager`, `CPositionSizer`, EA heartbeat paths, and via `LOG_IF` macro in `Core/Utils/Enums.mqh`
- `LOG_IF` macro (Batch 126) provides compile-time gating for verbose PrintFormat in hot paths:
  - `Core/Management/DiagnosticsManager.mqh` — heartbeat, consensus, conversion rates, risk budget, asset class/family diagnostics
  - `Core/Management/EnterpriseStrategyManager.mqh` — consensus diagnostics (CONSENSUS-DIAG, ROOT, STRATEGY, ROLE, CLUSTER, SCORE, RELAX, TREND-BIAS, TREND-FLIP, SOLO, MARGINAL-TIGHTEN, QUORUM, SPARSE, NEARMISS, VETO, ACTIVE), VPIN, family weights, AI uncertainty discount
  - `Core/Pipeline/UnifiedSignalPipeline.mqh` — cache, threshold, cost gate, entry veto, health check
- Log levels map: ERROR(0) → WARN(1) → INFO(2) → DEBUG(3) → VERBOSE(4) matching InpLogLevel

### Strategy Shared Helpers (Batch 140 — Phase 4 Debloat)
Strategy-side reject logging, risk validation, and consensus diagnostics are now routed through `CStrategyBase` protected virtual helpers instead of per-strategy duplicates:
- **Reject logging** — `CStrategyBase::LogRejectEvent()` / `RejectSignal()` emit `[SIGNAL-REJECTED]` with throttling via `m_lastRejectReasonTag` / `m_lastRejectLogTime`. Strategies call the base helper; per-strategy `m_strategyPrefix` disambiguates the source. 8 strategy files no longer carry their own copy.
- **Risk validation** — `CStrategyBase::ValidateWithRiskManager()` wraps the pre-trade `CUnifiedRiskManager` check that strategies perform before emitting a tradable signal. Consolidated into 11 of 12 strategies (StatisticalArbitrage retains its own pattern). Decision outcome (pass/reduce/block) is unchanged — only the call site is shared.
- **Consensus diagnostics** — `CStrategyBase::LogConsensusDiag()` emits the `[CONSENSUS-DIAG]` line strategies append to the manager's consensus trail. Consolidated into 9 of 12 strategies; 3 structural outliers retain local implementations.
- **New-bar refresh** — `CStrategyBase::RefreshForNewBar()` (guarded by `m_lastBarCount`) invokes the `OnRefreshComponents()` virtual hook; 5 strategies override `HandleNewBar()`/`OnRefreshComponents()` rather than re-implementing the new-bar guard.

No decision path or ownership boundary changed: strategies still vote through `CEnterpriseStrategyManager`, risk veto still belongs to `CUnifiedRiskManager`, and execution still belongs to `CTradeManager`. The helpers only remove duplicated boilerplate between the strategy class and its base.

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
- `POSITION_SIZE_KELLY` mode (enum value 2) in `CPositionSizer`
- **Consolidated to `CBayesianKellyModifier`** (L5-012): Beta-Binomial conjugate priors with quarter Kelly fraction (25%), uses confidence parameter as prior weight
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

Each line below was checked against a `Print`/`PrintFormat` call site in Batch 215. The tags this section used
to name that do not exist in the repository - `[ACCOUNT-CAPACITY]`, `[TRADE-STATE]`, `[CONSENSUS-VETO]`,
`[CONSENSUS-ACTIVE]`, `[CONSENSUS-SPARSE]`, `[CONSENSUS-NEARMISS]`, `[INTRABAR-BACKOFF]`, `[SCAN-PRIME]`,
`[SCHEDULER-STATE]`, `[SCAN-CANDIDATE]`, `[SCAN-DECISION]`, `[SCAN-DECISION-SUMMARY]`, `[MODE-MASK]`,
`[NN-MUTATION]`, `[CADENCE-WARNING]` - are gone, because a documented tag that no code prints sends the next
reader searching a journal for an answer that cannot exist.

- Weighted quorum evaluation emitted as `[CONSENSUS-QUORUM]`; a vetoed or emptied vote surfaces as
  `[CONSENSUS-VETOED]`, `[CONSENSUS-REGIME-VETO]` (Batch 204) or `[CONSENSUS-ABSTAIN]`.
- Selection and rejection detail: `[CONSENSUS-REJECT]`, `[CONSENSUS-TIE]`, `[CONSENSUS-SOLO-SELECT]`,
  `[CONSENSUS-SOLO-SKIP]`, `[CONSENSUS-FILTERED]`, `[CONSENSUS-PROBE]` / `[CONSENSUS-PROBE-DECISION]` /
  `[CONSENSUS-PROBE-REJECT]`, `[CONSENSUS-DECISION]`.
- Scan cadence: `[SCAN-POLICY]` once at init (Batch 212) and `[SCAN-BUDGET] mode= | evalBudget= | evaluations= |
  signalsGenerated= | pending=`, throttled inside `CSignalGenerator`. There is no intrabar budget split to log.
- Dormancy: `[DORMANT-COOLDOWN]` on the park and on its expiry, `[DORMANT-REMOVED]` when a symbol leaves the list.
- External LLM lifecycle and reasoning emitted as `[EXT-LLM]`; adaptive-training summary as `[AI-FEEDBACK]`.
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
12. `[AUTHORITY-REJECT]` / `[AUTHORITY-REDUCED]` or `[TRADE-SUCCESS]/[TRADE-ERROR]` plus `[TRADE-EXECUTION]` / `[EXECUTION-TELEMETRY]` for live-send broker details

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

### Phase 6-7 Debloat — Execution Flow + Hygiene (2026-08-06)
- **JSON parsing consolidation:** `CPythonBridge` now uses `ParseJsonDouble()` / `ParseJsonString()` / `ParseJsonInteger()` helpers for all JSON field extraction. No runtime behavior change — same find/extract/parse logic, just deduplicated. Affects `ParsePredictionResponse`, `GetPairCorrelation`, `FindBestCorrelatedPair`, `ParseVersionResponse`.
- **SignalValidator verification:** Confirmed already merged into `EnterpriseStrategyManager` — post-consensus spread/ATR/OFI/VPIN checks run within `GetConsensusSignalForSymbolWithConfluenceMode()`. No separate `SignalValidator.mqh` file exists.
- **TODO cleanup:** `EnsembleAIStrategyAdapter::TrainStep()` and `OnRegimeChange()` documented as intentional no-ops — `CEnsembleMetaLearner` method signatures require parameters not available in the adapter interface.
- **Dashboard fix:** `App.tsx` now imports real page components instead of rendering "Coming Soon" stubs. All 8 routes render actual page implementations.

### Phase 6.2 + 7.4 — Position Sizing Consolidation + Error Logging (2026-08-06)
- **Position sizing (6.2):** `UnifiedRiskManager` no longer re-implements min-lot round-up. The redundant `<minLot` branch was removed; the gate is now a single `if(request.lotSize > maxLot)` check against `SYMBOL_VOLUME_MAX`. `CPositionSizer` is the sole owner of min-lot round-up, using the restored 15x `minLotRiskMultiplier` tolerance (URM config default, `CPositionSizer` hard cap, and `SetMinLotRiskMultiplier` setter all relaxed from 1x → 15x). EA inputs `InpAllowMinLotRoundUp` / `InpMinLotRiskMultiplier` expose the policy.
- **Error logging (7.4):** 38 `PrintFormat("[DBG-RET0] %s:%d %s() return 0.0", __FILE__, __LINE__, __FUNCTION__)` debug lines were added to ambiguous `return 0.0` exit points across `CPythonBridge` (3), `CPositionSizer` (5), `CTradeManager` (14), and `CUnifiedRiskManager` (16). Pure observability — no decision path or trade behavior changed. Documented valid zero-result returns (hedging-mode, already-braced inline early-exits) were intentionally left unlogged.
