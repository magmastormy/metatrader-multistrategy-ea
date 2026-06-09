# Runtime Decision Graph

## Document Metadata
- Last Updated: 2026-06-05
- Scope: Runtime signal-to-execution flow
- Source: `MultiStrategyAutonomousEA.mq5`
- Current Batch: 96 - Execution Profitability Recovery

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
  D0B --> D0C{Synthetic tick spike?}
  D0C -->|Yes| D0D[Flatten positions and activate temporary trading pause]
  D0C -->|No| D0E[Continue]
  D0E --> D0F{Emergency drawdown breach?}
  D0F -->|Yes| D0G[Flatten and halt trading]
  D0F -->|No| D0H[Return]

  D --> D1{Terminal connected?}
  D1 -->|No| D2[Skip evaluation, wait reconnect]
  D1 -->|Yes| D_MGMT[ManageOpenPositionsIfNeeded]
  D_MGMT --> D_EXIT{SignalReversalExit Enabled?}
  D_EXIT -- Yes --> D_REV[Check Consensus Reversal]
  D_REV --> D_CONF{Reversal > 0.58 Conf?}
  D_CONF -- Yes --> D_PROFIT{Profit Guard Pass?}
  D_PROFIT -- Yes --> D_ZONE{Last Stand Zone?}
  D_ZONE -- No --> D_CLOSE[Close Position]
  D_EXIT -- No --> D_LIFECYCLE[PositionLifecycleManager]
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
  J1 --> J2[Multi-Tier Signal Validation & Conflict Resolution]
  J2 --> J3[Weighted Decision considering Setup Quality & Reliability]
  J3 --> K{Signal NONE?}
  K -->|Yes| L[Increment no-signal telemetry]
  K -->|No| M[Resolve ATR then run exogenous validation: spread/time/session/volatility/cost]

  M --> N{Validator pass?}
  N -->|No| O[Log SIGNAL-REJECTED]
  N -->|Yes| P{Entry gate open?}
  P -->|No| P2[Log ENTERPRISE-BLOCKED]
  P -->|Yes| Q[Build ATR SL/TP + risk request with role/cluster/contributors]

  Q --> R[UnifiedRisk pre-size validation]
  R --> S{Pass?}
  S -->|No| T[Risk rejection]
  S -->|Yes| U[Position sizing]

  U --> V[UnifiedRisk post-size validation]
  V --> W{Pass?}
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
