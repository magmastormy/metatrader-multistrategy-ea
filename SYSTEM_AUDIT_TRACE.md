# System Audit Trace

## Document Metadata
- Last Updated: 2026-05-13
- Scope: Runtime lifecycle and ownership trace
- Current Batch: 80 - Fix Hardcoded Zero Weights for Experimental AI Families

## Scope
- Entry point: `MultiStrategyAutonomousEA.mq5`
- Symbol decision manager: `Core/Management/EnterpriseStrategyManager.mqh`
- Multi-tier validator: `Core/Signals/TieredSignalValidator.mqh` (Batch 60)
- Filter pipeline: `Core/Pipeline/UnifiedSignalPipeline.mqh`
- AI runtime control: `Core/Engines/AIEngine.mqh`
- AI adapters:
  - `Core/Strategy/AIStrategyAdapter.mqh`
  - `Core/Strategy/TransformerAIStrategyAdapter.mqh`
  - `Core/Strategy/EnsembleAIStrategyAdapter.mqh`
  - `Core/Strategy/OnnxAIStrategyAdapter.mqh`
- Risk authority: `Core/Risk/UnifiedRiskManager.mqh`
- Execution authority: `Core/Trading/TradeManager.mqh`
- Position authority: EA lifecycle loop via `CTradeManager::ManageAllPositions(...)`

## Runtime Lifecycle

### 1. OnInit
- Validate terminal and trading permissions.
- Initialize mandatory execution/risk/runtime systems.
- Emit explicit `[EXECUTION-MODE]` startup telemetry for shadow vs live posture.
- Start from live-capable authority-gated defaults: AI/ONNX enabled, global live execution allowed, high-confidence AI/ONNX warm-start enabled, two-voter ordinary quorum, and sparse one-voter intrabar admission disabled.
- Reject unsupported non-hedging account models before runtime ownership is established.
- Apply execution safety controls (fill mode, slippage, protective modify cooldown) before trade-manager bootstrap.
- Apply hard execution-cost controls (max pre-send spread and max signal-price drift) before trade-manager bootstrap.
- Initialize optional AI subsystems conditionally by flags and convert failures into readiness-state degradation instead of fatal startup aborts.
- Emit `[AI-TOPOLOGY]` so MT5-native voters, ONNX live voting, Python bridge expectations, and external LLM reasoning posture are visible from init logs.
- Bootstrap the shared universal transformer service before AI brains/adapters start symbol registration, while keeping the service lazy-safe for indirect runtime callers.
- Load ONNX scaler parameters from Common files when available so runtime normalization stays aligned with Python training.
- Initialize performance analytics before unified-risk bootstrap.
- Validate active symbols and emit `[ACCOUNT-CAPACITY]` affordability diagnostics before the first scan.
- Reject symbols with extreme spreads (>1000 points) during symbol validation to prevent wasted evaluation cycles.
- Build the active-only strategy registry, then create per-symbol managers and register only enabled strategies and enabled AI adapters.
- Build symbol-class-specific strategy flags before manager bootstrap so synthetic symbols can use a leaner live roster than FX without violating per-symbol consensus ownership.
- Rebuild scheduler state only after manager bootstrap so symbol-bar times, intrabar timers, pending new-bar work, and scan-state backoff remain a single aligned authority.
- Treat curated mode as a baseline/default profile only; explicit strategy enables remain authoritative instead of being rewritten away at runtime.
- Registered AI strategies (Neural Network, Transformer, Ensemble, ONNX) now receive non-zero weights from `InpAIWeightMultiplier` during registry bootstrap, ensuring they can participate in live voting when enabled instead of being suppressed by zero weight.
- Reconstruct `[TRADE-STATE]` / cooldown timing from EA-owned history and open positions.
- Initialize `CTieredSignalValidator` and manager-side AI voting surfaces for multi-tier signal hierarchy.
- Prime one pending new-bar scan per validated symbol so startup cannot produce a fully idle manager fleet with zero first-pass evaluations.

### 2. Tick/Timer cycle
- Run `ProcessTickSafetyLoop()` on every tick.
- Run `ProcessTradingLogic()` on timer cadence as the heavy evaluation owner.
- Maintain NN learning cycle with explicit mutation-gate evaluation so pseudo labels can update health metrics without automatically mutating weights.
- Enforce terminal connectivity gate before signal evaluation.
- Enforce deterministic separation between the tick-owned safety loop and the timer-owned heavy scan loop.
- Run deterministic unprotected-position remediation sweep before entry evaluation.
- Refresh runtime equity/drawdown metrics on both safety and timer paths.
- Manage open positions once per second through `tradeManager.ManageAllPositions(...)`.
- Gate the generic EA-level lifecycle manager behind `InpEnablePositionLifecycleManager` so hidden tiny-point breakeven/trailing logic cannot prematurely close wider-structure trades by default.
- Detect synthetic-index tick-rate spikes and, on alarm, flatten positions plus activate a temporary trading pause.
- Keep symbol evaluation active during cooldown/capacity veto windows so blocked-entry behavior remains observable.
- Rotate symbol evaluation start index each cycle to reduce fixed-order concentration.
- Self-reconcile cadence scheduler state if any scheduler array drifts away from the active symbol set before new-bar detection.
- Detect new-bar events per symbol.
- Carry pending new-bar work across cycles and spend the per-cycle heavy-evaluation budget on those symbols before any intrabar work.
- Reserve the cycle-best candidate as a virtual position inside `CUnifiedRiskManager` while scan-time ranking is still active, then release that reservation after the cycle winner is executed or discarded.
- Run intrabar scans when eligible.
- Hybrid cadence is now the default live posture: `InpSignalScanOnNewBarOnly=false` keeps timed intrabar scans active unless operators explicitly force strict new-bar-only mode, and startup still emits `[CADENCE-WARNING]` when that override is active.
- The default intrabar symbol budget is widened to `4` so live synthetic verification spends more of the available cadence budget each cycle without fully unbounding scan cost.
- Batch 78 raises intrabar cadence/throughput further (`5s` scans, wider per-cycle budgets) so the EA behaves like a faster automated system while still preserving execution-cost and authority gates.
- Budget intrabar scans by symbol yield and apply per-symbol backoff after repeated low-yield or readiness-faulted intrabar passes.
- Emit heartbeat funnel and conversion-rate telemetry at configured diagnostics interval.

### 3. Signal path
- Manager consensus + confluence.
- Strategy `OnNewBar(...)` prepares per-bar state only; consensus owns the single authoritative `GetSignal(...)` invocation so bar-scoped signal state is not consumed twice.
- Manager applies role/cluster governance and evaluates quorum via normalized weighted conviction pooling.
- **Dynamic weight decay** (Batch 41): strategies filtering ≥ 3 consecutive cycles have live weight decayed to reduce denominator bloat; weight recovers when strategy votes again.
- Manager classifies intrabar strategies as `OFF`, `PROBE`, or `LIVE` before pipeline work is spent.
- Explicit intrabar eligibility now maps enabled strategies into real `LIVE` intrabar voting, so operator-facing `intrabar=true` settings match the runtime voter pool.
- Governance startup logs now mark disabled strategies as `INACTIVE` in the intrabar summary instead of implying they are live because a different profile left the raw input toggles enabled.
- Symbol-class profiles now shape live participation:
  - synthetic indices can suppress `Momentum` / `Trend` from the local manager roster when structure-capable strategies are enabled
  - the same synthetic lean profile keeps `Fibonacci` / `Elliott Wave` / `Support-Resistance` / `Unified ICT` intrabar `LIVE`, while `Candlestick` stays available for new-bar evaluation but is downgraded to intrabar `PROBE`
  - FX retains the broader balanced roster
  - synthetic ICT/Elliott higher-timeframe dependencies are lowered from FX-style `H4/D1` expectations to lighter `M15/H1/H4` ladders where appropriate
- Synthetic lean symbols now also receive dedicated sparse intrabar admission thresholds, so one-voter structure packets are evaluated against profile-aware quality floors instead of the same sparse-quality bar used for broader FX/balanced rosters.
- **Adaptive quorum thresholds** (Batch 41): manager calculates `effectiveQualityThreshold` and `supportFloor` based on actual active voter count:
  - 1 active voter: directional quality ≥ 0.40, support ≥ 0.15
  - 2 active voters: directional quality ≥ 0.48, support ≥ 0.30
  - 3+ active voters: directional quality ≥ standard threshold, support ≥ scan-mode floor
  - Prevents impossible quorum math where inactive strategies inflated weight pool and rejected legitimate votes.
  - Adaptive one-/two-voter quality thresholds now respect the current base quorum so user-lowered quorum profiles are not silently re-hardened by stale fixed fallback thresholds.
- Manager quorum requires directional quality, support-ratio floors, effective min voters, minimum ready-live-weight participation, and conflict-deadband separation.
- Manager can emit a separate `SPARSE_INTRABAR` decision class only when `InpAllowSparseIntrabarSingleVoter=true`; the default posture keeps this off and routes high-confidence AI-only packets through the live-authority gate instead.
- **Multi-Tier Signal Validation (Batch 60):**
  - Votes are processed through `CTieredSignalValidator` for tier-based hierarchy.
  - **Tiered Evaluation**: Groups strategies into Institutional (T1), Structure (T2), and Indicators (T3).
  - **Conflict Resolution**: Resolves tier-level contradictions (e.g., T2 agreement overriding T1 weak bias).
  - **Setup Quality & Reliability**: Integrates setup quality (0-1) and historical accuracy metrics into the final decision weight.
- **Detailed veto diagnostics** (Batch 41): manager emits specific veto codes with numeric evidence instead of generic `zero_voter` / `single_voter_confidence` placeholders.
- Manager vote admission now uses the pipeline's effective confidence floor for the current evaluation, avoiding pipeline/quorum drift when regime-aware relaxation is active.
- Manager live vote influence is modulated by rolling strategy `healthScore` rather than treating every enabled strategy as equally trusted at all times.
- Manager emits consensus root-cause attribution snapshots for no-signal diagnostics.
- Manager emits strategy-level none-reason attribution for core curated contributors.
- Pipeline now includes deterministic regime/cost viability gate before validator.
- Pipeline caches structural engine state once per symbol/timeframe/bar and carries a shared evidence snapshot (`readiness`, `context`, `cost`, readiness class, reuse/staleness`) forward through consensus and validation.
- Pipeline and validator both support bounded soft-pass behavior for near-threshold candidates when the broader evidence profile is strong.
- Pipeline attenuates admitted confidence after threshold passage using readiness/context/staleness evidence so weak packets cannot preserve inflated confidence downstream.
- `CRegimeEngine` may reuse a recent valid same-context snapshot on transient warmup / copy / handle-init faults and performs bounded handle reset after repeated data faults.
- `CVolatilityEngine` and `CRegimeEngine` now recover ATR/Bollinger inputs from raw rates when indicator buffers fault against mature series, preventing the pipeline from degrading to zero ATR during transient `BB_BUFFER_COPY_FAILED` / warmup loops.
- `CTrendEngine` now allows mature-series partial-readiness to proceed so bounded MA/ATR fallback logic can attempt recovery; it may still reuse a bounded last-good trend snapshot on transient MA/ATR copy faults and emits `[READINESS-STATE]` reuse telemetry.
- `CTrendEngine` now branches by instrument class: FX keeps ADX-backed trend modeling, while synthetic indices bypass ADX handle creation and derive trend state from MA structure/angle only, removing synthetic-only ADX readiness churn without changing FX behavior.
- Pipeline threshold adaptation now uses `CRegimeEngine` snapshot state and dedicated non-AI confidence floors instead of AI-threshold coupling.
- `CMarketAnalysis` now keeps bounded last-valid trend/volatility/momentum/ATR snapshots and reuses them on transient `4806/4807` copy faults instead of silently dropping those metrics to zero.
- Validation is now split by ownership:
  - manager owns structural admission (`confidence`, `confluence`, directional `quality`, support, effective minimum voters)
  - validator owns only exogenous market sanity (`spread`, `time`, `session`, `volatility`, cost viability) when manager-owned admission mode is enabled
- Validator profile inputs still exist by scan mode (new-bar vs intrabar), but in normal runtime they are telemetry/fallback surfaces rather than a second structural veto layer.
- Validator still consumes manager quorum facts (`effectiveMinVoters`, `directionalQuality`, `supportRatio`) together with conviction/readiness/context/cost evidence so exogenous validation telemetry stays aligned with the already-authoritative manager decision.
- Strategy overrides that bypass base-class `GetSignal(...)` now emit explicit decision tags, and manager defensively downgrades any remaining placeholder abstentions so they cannot silently dilute ready-live quorum math.
- Entry gates (cooldown, total-position cap, unprotected-position veto, per-symbol capacity) now apply after validation and before unified risk so approved-but-blocked signals are still logged.
- Live authority is applied per candidate before live send: `[LIVE-AUTHORITY]` decides live vs candidate-level shadow and scales risk; `[AUTHORITY-TRIAL]` records forward evidence; `[AUTHORITY-RESULT]` updates AI/ONNX/indicator/Elliott family statistics for promotion or demotion.
- Final validator ATR acquisition now resolves from the shared indicator handle first and then a raw-rate ATR fallback, preventing transient copy misses from forcing `Invalid ATR: 0.00000` vetoes on otherwise-valid packets.
- Final EA admission also applies ATR-ratio crisis gating (`ATR14/ATR50`) so volatility shocks can reject or down-scale otherwise valid entries before risk sizing.
- AI vote generation is same-bar cached:
  - neural votes reuse `GetNeuralSignalCached(...)`
  - transformer and ensemble adapters reuse cached inference results until the bar changes
  - failed feature-build/inference results are cached as `NONE` for the rest of the bar
- AI adapters now emit explicit decision reason tags on disabled, abstain, feature-fault, inference-fault, and signal paths, removing the old `UNTAGGED_NO_SIGNAL` blind spot from AI-enabled consensus traces.
- AI strategy adapters now support a unified `SetConfidenceThreshold(double)` interface for dynamic authoritative thresholding from the EA orchestrator, and the system now respects `InpAIConfidenceThreshold` as the authoritative floor across all modes, eliminating legacy hardcoded confidence caps.
- AI_ONLY mode is now strict: indicator strategies are filtered out at the strategy registry level, ensuring no indicator-based votes participate when the EA is in AI-primary posture.
- When configured indicator families are filtered out by `AI_ONLY`, runtime now emits `[MODE-MASK]` so those sessions are not misread as "indicator strategies voted badly."
- Python-side AI semantics are now explicitly separated in runtime docs and logs:
  - ONNX is the only Python-trained live-voter path currently wired into manager consensus
  - Python bridge endpoint inputs are telemetry/expectation surfaces only
  - external LLM remains a reasoning/adaptation sidecar, not a direct voter
- The ONNX runtime path is now repository-native: `Resources/model.onnx` is embedded into the EA, `COnnxAIStrategyAdapter` participates in symbol-scoped manager consensus, and `COnnxBrain` can arm a shadow handle for hot-swap evaluation from Common files.
- The offline ONNX training/export pipeline now lives under `Python/`, aligned to the same 55-feature contract used by `CAIFeatureVectorBuilder`.
- `CPipelineScaler` now bridges Python `StandardScaler` exports into MQL runtime inference, and `TrainingDataExporter.mq5` can export the same 55 features for parity validation through `Python/feature_crosscheck.py`.
- The Python stack now also includes CPCV validation, IC-gated promotion, DER++ replay helpers, LightGBM/stacker training, regime/turbulence utilities, and a ZMQ bridge surface for deeper AI upgrade phases.
- `StrategyUnifiedICT` now treats institutional references as first-class runtime inputs: monthly/quarterly highs-lows, NY midnight/quarter opens, anchored VWAP, cumulative-delta pressure, and propulsion/rejection/vacuum order-block variants all feed the same scoring, POI, and stop/TP path instead of existing as detached helpers.
- `CICTPositionSizer` now includes half-Kelly sizing caps from recent symbol-specific EA close history, and Elliott Wave confidence can now gain a harmonic PRZ cross-validation bonus through `CHarmonicScanner`.
- AI intrabar policy is now explicit instead of globally hard-coded `OFF`: `Neural Network AI`, `Transformer AI`, `Ensemble AI`, and `ONNX AI` each have their own intrabar eligibility input, allowing `AI_ONLY` and `HYBRID` to be tested as real timed intrabar modes.
- `CNextGenStrategyBrain` now follows a single local-transformer path with direct `CAIFeatureVectorBuilder` sourcing and no dead Python/cloud bridge branch.
- Duplicate component-local `SignalDiagnostics` sinks have been removed from Elliott, pipeline, and orchestrator paths so manager/runtime telemetry stays authoritative.
- **AI Feature Lifecycle (Batch 58):**
  - Neural network feature extraction now produces 44-dimensional vectors (25 original + 19 pattern-specific features)
  - Pattern-specific features include: Higher Highs/Lower Lows sequences, Support/Resistance touch counts, Fibonacci Retracement proximity, Pivot Point proximity, volume profile features, market structure features
  - Weight matrix dimensions updated to `W1[44][32]` to accommodate expanded input
  - All array allocations and loop bounds updated consistently to prevent array out of range errors
  - Training example struct `STrainingExample` now uses `inputs[44]` instead of `inputs[25]`
  - File I/O for checkpoint save/load updated to handle 44-element feature vectors
- **External LLM Lifecycle (Batch 58):**
  - Optional external LLM support via `CAIEngine` with configuration flag `useExternalLLM` (default `false`)
  - HTTP client for Ollama API communication initialized during `ConfigureExternalLLM()`
  - External LLM can be toggled at runtime via `SetExternalLLMEnabled(bool)`
  - Signal synthesis, trade explanation, risk assessment, and strategy weight reasoning methods available when external LLM is enabled
  - Feedback loop via `ProvideFeedback()` sends trade results to external LLM for learning
  - External LLM failures are logged but do not abort the EA; system degrades gracefully to internal AI only
  - Adaptation now performs throttled external reasoning capture when enabled, and the full lifecycle is surfaced under `[EXT-LLM]` telemetry instead of remaining a silent helper path
- **Multi-scale Attention Lifecycle (Batch 58):**
  - Transformer brain now initializes per-head scaling factors, time window sizes, and learning rates
  - Head-specific parameters enable differential pattern detection across short/medium/long horizons
- **Pattern Classifier Lifecycle (Batch 58):**
  - 10-class pattern classifier head initialized with Xavier initialization
  - Cross-entropy loss training for pattern recognition
  - Pattern classification runs alongside 3-class BUY/SELL/NONE predictions
- **Chart Visualization Lifecycle (Batch 58):**
  - Elliott Wave strategy draws comprehensive Fib target levels for all waves (W1-W5) with multiple ratios
  - Trend lines use thin dashed style (STYLE_DOT, width 1) with muted colors for cleaner appearance
  - ICT drawing colors (OB, FVG, Liquidity, BOS, CHOCH) reduced in intensity using 0x909090 color mask
  - SupportResistance strategy trendlines aligned to thin dashed style for consistency
  - All chart drawing elements use consistent thin dashed styling for improved clarity
- Risk gating (pre-size then post-size).
- Drawdown-aware size tapering now happens between those two phases: the raw `CPositionSizer` output is scaled by `CAIStrategyOrchestrator::GetDrawdownMultiplier()`, then the adjusted lot is re-submitted to unified risk for final approval.
- Risk gate now evaluates cluster governance (mutex + caps) using request context and open-position cluster tags.
- Portfolio correlation fallback uses bounded value (0.65, capped to `m_maxCorrelation`) when correlation data is unavailable, avoiding hard blocks while preserving safety.
- Recommended per-trade risk is now pressure-throttled before the final hard cap as daily and portfolio utilization rise, producing `[RISK-THROTTLE]` evidence ahead of a hard veto.
- Pipeline confidence gate emits threshold-source metadata and uses bounded weak-regime intrabar uplift.
- Trend ADX failures degrade to neutral/ranging context with bounded ADX-handle self-heal.
- ATR stop-distance fallback when indicator read fails.
- Risk-approved opportunities are staged as ranked candidates across the full symbol scan before shadow or live execution.
- Live execution captures broker receipt state, price/slippage/latency telemetry, and risk registration scales consumed entry budget by actual fill ratio.
- Live execution now blocks before send when quote spread or signal-price drift exceeds configured hard limits, emitting `[EXECUTION-BLOCKED]`.
- Post-entry lifecycle management now scales BE/trailing/partial-close thresholds against original stop distance, eliminating the previous fixed-pip asymmetry where wide-stop synthetic winners were harvested almost immediately while losers still paid the full original stop.
- Protective stop modifications now validate against executable quote side and retry once with extra cushion on `TRADE_RETCODE_INVALID_STOPS`, reducing live-management churn on fast synthetic symbols.
- Per-symbol capacity checks include explicit external-position block telemetry.

### 4. Post-trade path
- Transaction callback updates manager/orchestrator performance.
- Transaction callback records confirmed close results into `PerformanceAnalytics`.
- NN attribution maps prediction IDs and labels closes (online-training gate controlled).
- Trade outcome is routed to `CTieredSignalValidator` to update historical accuracy metrics per tier.

### 5. Housekeeping
- Position manager lifecycle actions (check market hours before closure/modification, block only when SYMBOL_TRADE_MODE_DISABLED).
- Tick safety / synthetic spike telemetry and trading-pause lifecycle logs are emitted outside the heavy scan path.
- Periodic telemetry logs, including `[AI-FEEDBACK]` performance summaries for adaptive-training health.
- Indicator cache release policy.
- Shutdown now emits `[TERMINATION-SNAPSHOT]` with final heartbeat counters before deinit cleanup.

### 6. OnDeinit
- Release managers and dynamic strategy allocations.
- Managers explicitly deinitialize owned strategies before deleting them to avoid teardown drift at shutdown.
- Deinitialize subsystems.
- Explicit `CIndicatorManager::DestroyInstance()`.
- Orchestrator report emission is single-source (destructor-owned) to avoid duplicate shutdown reports.
- **Memory Safety**: AI adapters now properly clean up transformer models in destructors.
- **Error Handling**: Enhanced validation in feature vector construction and attribution systems. Proactive readiness checks (`IsDataReady`) and indicator warmup verification (`BarsCalculated`) prevent invalid feature generation during symbol startup.

## Observability Surface
- Decision: `[SIGNAL]`, `[SIGNAL-REJECTED]`, `[SIGNAL-VALIDATED]` (`exogenous_quality` logged separately from consensus confidence)
- Multi-Tier: `[TIERED-VOTE]`, `[CONFLICT-RESOLUTION]`, `[SETUP-QUALITY]`
- System telemetry: `[EXECUTION-MODE]`, `[ACCOUNT-CAPACITY]`, `[TRADE-STATE]`, `[HEARTBEAT]`, `[HEARTBEAT-FUNNEL]`, `[CONVERSION-RATES]`, `[RISK-BUDGET]`, `[RISK-THROTTLE]`, `[RISK-VIRTUAL]`, `[LIVE-AUTHORITY]`, `[AUTHORITY-TRIAL]`, `[AUTHORITY-RESULT]`, `[CONSENSUS-QUORUM]`, `[CONSENSUS-VETO]`, `[CONSENSUS-ACTIVE]`, `[CONSENSUS-DIAG]`, `[CONSENSUS-ROOT]`, `[CONSENSUS-SNAPSHOT]`, `[CONSENSUS-STRATEGY]`, `[CONSENSUS-ROLE]`, `[CONSENSUS-CLUSTER]`, `[ROLE-CLUSTER]`, `[STRATEGY-REJECTS]`, `[PIPELINE-THRESHOLD]`, `[REGIME-STATE]`, `[VOLATILITY-FAULT]`, `[ATR-FALLBACK]`, `[TrendEngine][READINESS-FAULT]`, `[MARKET-ANALYSIS]`, `[COST-GATE]`, `[ENTRY-VETO]`, `[ENTERPRISE-BLOCKED]`, `[EXECUTION-BLOCKED]`, `[QUIET-REASONS]`, `[NO-SIGNAL-ALERT]`, `[SCAN-BUDGET]`, `[SCAN-PRIME]`, `[SCHEDULER-STATE]`, `[CADENCE-WARNING]`, `[MODE-MASK]`, `[SPIKE-ALARM]`, `[SPIKE-PAUSE]`, `[SCAN-CANDIDATE]`, `[SCAN-DECISION]`, `[TRADE-CONFIRMED]`
- Risk remediation: `[RISK-UNPROTECTED]`, `[CAPACITY-EXTERNAL]`, `[RISK-CLUSTER]`, `[RISK-MUTEX-BLOCK]`
- AI: `[AI-VOTE]`, `[NN-HEALTH]`, `[NN-MUTATION]`, `[AI-FEEDBACK]`, `[EXT-LLM]`
- Trade: `[SHADOW-TRADE]`, `[TRADE-SUCCESS]`, `[TRADE-ERROR]`, `[TRADE-EXECUTION]`, `[EXECUTION-RECEIPT]`, `[EXECUTION-TELEMETRY]`, `[FILL-DIFF]`

## 2026-03-31 AXIOM Refactor Trace
- Removed dead AI/control-flow weight:
  - `CNextGenStrategyBrain` no longer carries the dormant Python/cloud branch or cloud-status labeling
  - stale no-op lifecycle methods were removed from the transformer/ensemble/brain surface
- Stabilized AI hot paths:
  - `CMarketDataProcessor` now uses a ring buffer instead of shifting arrays on every update
  - `CUncertaintyQuantifier` and `CNeuralNetworkStrategy` now use ring-buffered histories instead of `Delete(0)` or heap-per-sample patterns
  - AI adapters now gate inference to one pass per bar
- Tightened AI ownership/failure boundaries:
  - optional AI brain/orchestrator/engine failures no longer kill the EA
  - adaptation sync and dashboard AI state are now gated by explicit readiness flags
- Tightened indicator lifecycle in clean detector paths:
  - `CSupportResistanceDetector` now caches its ATR handle across repeated detection/touch passes instead of recreating it inside hot methods

## Current Operational Constraints
- Persistent terminal sessions are preferred.
- Start tester on stable history symbol (`EURUSD.0`) when synthetic history is uncertain.
- Emergency drawdown flattening can run account-wide when configured (`InpEmergencyFlattenAllAccountPositions=true`).

## Build Note
- Compile helper: `sync_and_compile.ps1`
- Compile artifacts should be auto-cleaned after runs unless explicitly retained.
- **Code Quality**: Recent fixes address memory leaks, null pointer safety, bounds checking, and standardized constants across AI components.
- **Compilation**: Verified 0 errors, 0 warnings with all improvements integrated.
- **Batch 60 Verification**: Multi-tier signal validation architecture confirmed with 0 compilation errors.

## 2026-03-30 Support/Resistance & Trendline System Overhaul Trace
- `CTrendlineDetector` and `CSupportResistanceDetector` rewritten to map points cleanly off normalized ATR levels instead of hardcoded minimum pip parameters.
- Look-ahead bias safely removed. All logic checks intersecting S/R lines and Trendlines now query `bar[1]` to ascertain completed chart realities and ignore active-wick repainting.
- Indicator MT5 Chart memory heavily hardened via dynamic array bubble sorting in `StrategySupportResistance`, drawing only the top 6/8 power tiers instead of saturating the frontend with stale ghost levels.
- Lot computations (`CADXPositionSizing`) explicitly refactored to consume Tick Size and Tick Value for hyper-accurate price distance conversion against the active risk profile.
- Obsolete fast-decay and price-averaging node cluster bugs isolated and resolved in S/R memory structures.

## 2026-03-25 Efficiency + Conviction Trace
- `Core/Pipeline/UnifiedSignalPipeline.mqh` now caches structural engine context per symbol/timeframe/bar and emits a reusable evidence snapshot carrying `readinessScore`, `contextScore`, `costScore`, effective confidence floor, and bounded soft-threshold state.
- `Core/Signals/TimeframeConsistency.mqh` no longer neutralizes directional consensus through hot-path hedging prevention; timeframe conflict resolution remains authoritative without pre-emptively zeroing otherwise valid mixed-strategy output.
- `Core/Management/EnterpriseStrategyManager.mqh` now computes directional conviction from adjusted live weight (`base weight x role multiplier x rolling healthScore`) and requires minimum ready-live-weight participation before a direction can pass quorum.
- `Core/Signals/AdvancedSignalValidator.mqh` now consumes upstream decision-path evidence (`conviction`, `readiness`, `context`, `cost`, `diversity`, `freshness`) and allows bounded soft passes near confidence/confluence floors when the setup quality is strong.
- `MultiStrategyAutonomousEA.mq5` now stages all risk-approved opportunities as ranked candidates, emits `[SCAN-CANDIDATE]` / `[SCAN-DECISION]`, and executes the best candidate per cycle instead of the first acceptable symbol.
- `Core/Trading/TradeManager.mqh` now exposes execution receipts and `Core/Risk/UnifiedRiskManager.mqh` scales executed-risk registration by fill ratio, so partial fills do not overstate daily entry-budget consumption.
- `Core/Signals/SignalDiagnostics.mqh` now batches flushes so diagnostic file output no longer forces a disk flush on every event.

## 2026-02-24 Cleanup Trace
- Removed dead commented strategy stubs from `MultiStrategyAutonomousEA.mq5`.
- Removed orphan harmonic strategy component files under `Strategies/HarmonicFiles/`.
- Removed dead wrapper files carrying legacy `StrategySwing` naming:
  - `Core/Utils/File.mqh`
  - `Core/Trading/DealInfo.mqh`
  - `Core/Trading/HistoryOrderInfo.mqh`
  - `Core/Trading/PositionInfo.mqh`
- Pruned retired strategy enum references from `Core/Utils/Enums.mqh`.
- Removed unused legacy strategy configuration module `Config/StrategyConfig.mqh`.
- Normalized Unified ICT helper comments/diagnostics to remove legacy SMC-era naming.

## 2026-02-24 Throughput-Recovery Trace
- Added intrabar dynamic quorum controls and single-voter confidence floor controls in `EnterpriseStrategyManager`.
- Added explicit strategy-level intrabar eligibility assignment path for curated core contributors.
- Added manager-level consensus funnel snapshots and dominant-cause diagnostics (`[CONSENSUS-ROOT]`).
- Added per-strategy reject attribution counters and heartbeat aggregation (`[CONSENSUS-STRATEGY]`, `[STRATEGY-REJECTS]`).
- Hardened `TrendEngine` ADX handling with readiness checks, value-domain sanitation, neutral degrade, and bounded ADX handle reinit.
- Extended pipeline confidence filtering with bounded weak-regime intrabar threshold cap plus source-tag logging.
- Extended heartbeat with conversion funnel counters/rates and no-signal dominance alerting tied to consensus diagnostics.

## 2026-03-07 No-Trade Recovery Trace
- Refined `EnterpriseStrategyManager` intrabar dynamic quorum so it now keys off actual live contributors in the current cycle rather than the entire eligible live pool.
- Added explicit `[EXECUTION-MODE]` startup telemetry in `MultiStrategyAutonomousEA.mq5` to prevent shadow-mode sessions from being mistaken for execution failures.
- Initialized `PerformanceAnalytics` explicitly before `CUnifiedRiskManager` bootstrap to remove cold-start ambiguity in adaptive-risk wiring.
- Split non-AI signal confidence policy away from `InpAIConfidenceThreshold` by introducing dedicated pipeline and validator confidence floors in `MultiStrategyAutonomousEA.mq5`.
- Rewired `CUnifiedSignalPipeline` threshold adaptation to use `CRegimeEngine` snapshot state rather than `TrendEngine` neutral/warmup output.
- Added explicit `Trend` reject telemetry so primary-live starvation can be diagnosed from runtime logs instead of remaining silent.

## 2026-03-07 Execution-Safety Trace
- Switched `CTradeManager` market sends to synchronous execution by default.
- Reworked market send path so execution price and protective SL/TP are recalculated from current market data at submit time.
- Moved confirmed close analytics updates into `OnTradeTransaction` and strengthened `PerformanceAnalytics::RecordClosedTrade(...)`.
- Reconstructed `AdvancedPositionManager` partial-close and breakeven state for already-open positions using `POSITION_IDENTIFIER` plus history-derived entry volume.
- Rejected unsupported non-hedging account modes at startup and tightened symbol validation for close-only symbols and invalid volume-step specs.

## 2026-03-16 Timeframe + AI Feedback Trace
- Manager consensus now resolves mixed-timeframe conflicts using `CTimeframeConsistency`.
- Strategy `OnNewBar` dispatch uses each strategy's registered timeframe to prevent cross-timeframe misalignment.
- AI performance feedback now records prediction/outcome pairs using request-to-position mapping on live trades.

## 2026-03-24 Quorum Admission Alignment + Smoke Controls Trace
- Aligned `EnterpriseStrategyManager` vote admission with `UnifiedSignalPipeline`'s effective confidence floor so pipeline-approved relaxed-threshold signals remain eligible for timeframe consistency and quorum.
- Added opt-in intrabar eligibility controls for `Fibonacci` and `Support/Resistance` to support smoke tests that need the chain to reach validator/risk/execution without broadening production defaults.

## 2026-03-24 Startup State Recovery + Capacity Diagnostics + Regime Fault Resilience Trace
- Added startup reconstruction of `g_lastTradeTime` in `MultiStrategyAutonomousEA.mq5` using EA-owned history and open positions so inherited positions preserve cooldown state after restart/re-attach.
- Added `[ACCOUNT-CAPACITY]` startup diagnostics that compare free margin with estimated minimum-lot margin for each active symbol and warn when live mode cannot afford any configured symbol.
- Hardened `Core/Engines/RegimeEngine.mqh` to reuse recent valid snapshots on transient warmup / buffer-copy / handle-init faults and to emit bounded `[REGIME-STATE] HANDLE_RESET` self-heal telemetry after repeated data faults.

## 2026-03-24 Entry Gate Decoupling Trace
- Moved cooldown/position/protection/capacity enforcement to the post-validation pre-risk stage in `MultiStrategyAutonomousEA.mq5` so signal generation keeps running during blocked-entry windows.
- Added explicit `[ENTERPRISE-BLOCKED]` logs for approved signals that are suppressed before risk/execution.

## 2026-03-24 Consensus Veto + Validator Spread-State + Trend Readiness Trace
- Added explicit `[CONSENSUS-VETO]` telemetry so post-quorum timeframe-conflict and single-voter nullification is visible without reconstructing it from downstream absence.
- Changed `Core/Signals/AdvancedSignalValidator.mqh` spread-shock state from shared global runtime state to symbol-scoped runtime state, preventing cross-symbol spread contamination in validator decisions.
- Hardened `Core/Engines/TrendEngine.mqh` against mature-series negative `BarsCalculated(...)` states by emitting `[TrendEngine][READINESS-FAULT]` and performing bounded full-indicator-set reinitialization after repeated readiness faults.
- Preserved exact `PortfolioRiskManager` veto reasons through `RiskValidationGate` so `[RISK-CONTRACT]` reports concrete correlation / position-cap style causes instead of flattening them to generic manager-blocked text.

## 2026-03-16 Weighted Quorum + Live Strategy Promotion Trace
- Promoted all retained strategies to live primary voters by default (per-strategy inputs gate registration).
- Replaced binary count-based quorum with normalized weighted confidence quorum (`InpQuorumThreshold`, `InpMinLiveVoters`, per-strategy `InpWeight*`).
- Added per-evaluation quorum telemetry via `[CONSENSUS-QUORUM]`.

## 2026-03-25 Runtime Integrity + Lifecycle Trace
- Corrected same-bar structural cache replay in `Core/Pipeline/UnifiedSignalPipeline.mqh` so cached evaluations preserve the original engine-ready flags and neutral defaults when engines are not ready.
- Hardened pipeline bootstrap so missing diagnostics/protection/core engines now fail startup rather than silently degrading to a hollow filter path.
- Localized symbol-specific engine state:
  - `Core/Engines/LiquidityEngine.mqh` now uses the requested symbol for point/tolerance math
  - `Core/Engines/RegimeEngine.mqh` now clears spread-shock cooldown state on symbol/timeframe switches
- Aligned sizing lifecycle with shared indicators by routing `Core/Risk/PositionSizer.mqh` ATR reads through `IndicatorManager` when available.
- Extended the scan lifecycle with cycle-scoped attribution:
  - `[SCAN-NO-TRADE]`
  - `[RISK-CAP]`
  - expanded `[QUIET-REASONS]`
- Tightened execution lifecycle in `Core/Trading/TradeManager.mqh`:
  - preflight viability check before send
  - confirmed-fill classification instead of raw submit success
  - explicit `[EXECUTION-BLOCKED]` / `[EXECUTION-UNCONFIRMED]` telemetry when safe execution cannot be proven
- Verification:
  - compile passed with `0 errors, 0 warnings`
  - bounded MT5 shadow-launch attempt completed, but no fresh EA-level tester artifacts were emitted in this environment

## 2026-02-24 Strategy Betterment Trace
- Note: the soft-quarantine defaults recorded in this batch are historical; current default voting behavior is defined by the 2026-03-16 weighted quorum + live strategy promotion update.
- Added institutional strategy governance metadata (role, cluster, live-vote eligibility, shadow mode) to `EnterpriseStrategyManager` and exposed setter APIs by strategy name.
- Added soft-quarantine defaults in EA initialization:
  - primary live voters: `Momentum`, `Trend`, `Unified ICT`
  - feature/shadow-only by default: `Candlestick`, `Fibonacci`, `Elliott Wave`, `Support/Resistance`
- Added deterministic `Core/Engines/RegimeEngine.mqh` and integrated it into `UnifiedSignalPipeline` as a pre-validator regime/cost viability gate.
- Extended `SignalFilterSettings` with regime/cost controls (`enableRegimeCostGate`, `maxSpreadToAtrRatio`, `spreadShockCooldownSeconds`, `maxEntryRangeZScore`).
- Refactored momentum strategy to state+trigger gating (EMA state alignment + compression-to-break trigger) to reduce crossover spam.
- Simplified Unified ICT live decision path to falsifiable event tuple checks (structure break, displacement, mitigation/retest) with bounded event-quality scoring.
- Extended `STradeValidationRequest` with role/cluster/contributor context and compact cluster code.
- Added cluster-aware risk governance in `RiskValidationGate`:
  - same-symbol opposing-cluster mutex
  - per-cluster concurrent position cap
  - per-cluster projected risk cap
- Added runtime cluster-tagged trade comments (`K:T/R/S/N`) for deterministic cluster attribution on open positions.

## 2026-04-01 Default Runtime Efficiency Trace
- `default.log` carried two valid runtime signals:
  - repeated `TrendEngine` ATR readiness faults
  - repeated idle scan-budget passes
- The same log also diverged from current code defaults, so the remediation batch split into two tracks:
  - real hot-path fixes
  - explicit operator guidance that saved runtime state must be verified from startup logs
- Trend trace:
  - mature-series ATR faults no longer hard-pin the engine in false warmup
  - bounded ATR fallback now runs before reuse/neutral degradation
  - readiness degradation remains explicit in logs
- Scan trace:
  - `[SCAN-BUDGET]` now includes `active_work`
  - fully idle cycles skip the per-symbol loop
  - quiet-cycle attribution remains visible in heartbeat counters
- Governance/build trace:
  - corrected `Support/Resistance` intrabar probe mapping
  - repaired `StrategyElliottWaveEnhanced` line-style enum usage
  - removed local min-confidence shadowing in Elliott Wave strategy
  - compile verification finished cleanly with `0 errors, 0 warnings`

## 2026-04-07 Scan Budget + Registry + Diagnostics Debloat Trace
- `MultiStrategyAutonomousEA.mq5` now caps heavy evaluations with `InpMaxSignalEvaluationsPerCycle`, persists pending new-bar symbols across cycles, and spends the cycle budget on deferred new-bar work before intrabar scans.
- The legacy `InpUseOrchestrator` surface has been removed; runtime registration now follows the active strategy registry only, so disabled curated strategies and disabled AI adapters do not enter manager pools, orchestrator identity maps, or weight summaries.
- `CTrendEngine` now distinguishes warmup, transient copy faults, handle faults, partial-readiness faults, and reused snapshots; partial readiness is allowed to proceed when the underlying series is mature, enabling MA/ATR fallback logic to attempt recovery instead of hard-failing, which reduces persistent readiness vetoes on synthetic indices where `BarsCalculated` may lag behind `Bars()`. cases.
- `Strategies/StrategyElliottWaveEnhanced.mqh`, `Core/Pipeline/UnifiedSignalPipeline.mqh`, and `Core/AI/AIStrategyOrchestrator.mqh` no longer allocate component-local `SignalDiagnostics` sinks; runtime observability is now concentrated in manager/runtime telemetry rather than duplicate per-component logs.

## 2026-04-01 Strategy Registry + AI Runtime Audit
- Added `ENUM_EA_MODE` and registry-backed activation via `CStrategyRegistry`.
- Startup now records the requested mode, resolved effective mode, and active indicator/AI family counts under `[STRATEGY-REGISTRY]`.
- Per-symbol manager construction is now registry-driven for:
  - retained indicator strategies
  - transformer adapter
  - ensemble adapter
  - neural adapter registration once the per-symbol NN exists
- Post-consensus audit trail now includes mode-specific admission:
  - candidate can be rejected for `hybrid_mode_alignment_missing`
  - candidate can be rejected for `indicator_confirmation_missing`
  - candidate can receive `[AI-MODE-BONUS]`
- Scheduler audit trail now includes bounded intrabar keepalive recovery so default hybrid cadence cannot permanently collapse to `intrabar_selected=0`.
- `CTrendEngine` audit trail now includes bounded MA fallback in addition to ATR fallback, keeping readiness degradation explicit without forcing repetitive full reinitialization.

### Batch 14: Synthetic Asset 24/7 Hardening (2026-04-08)
- Event: Expanded intrinsic synthetic filtering to PainX, SFX Vol, GainX, FX Vol, and FlipX.
- Implication: Core systems (AdvancedSignalValidator, TradeManager, MarketAnalysis) bypass native off-hours blocks to sustain execution on decentralized index regimes without false validation drops.

### Batch 64: Logical Error Audit & Defensive Programming Hardening (2026-04-15)
- **Risk Domain Hardening:** Fixed risk denominator calculation to handle negative balance/equity values in `RiskValidationGate.mqh`, preventing incorrect risk calculations during account drawdown. Added comprehensive parameter validation in `PositionSizer.mqh` for all sizing parameters (atrMultiplier, maxLotSize, minLotSize, correlationAdjustment). Implemented missing `ValidateClusterGovernance` method with proper cluster mutex and concurrent position validation.
- **Position Management Safety:** Fixed infinite loop risk in `AdvancedPositionManager::NormalizeCloseVolume` by adding iteration limit (100 iterations). Added handling for remaining volume below minimum lot size after partial close. Added validation for trailing stop distance and step to ensure positive values. Added validation for negative time values in time-based exit to ensure open time and max position hours are valid.
- **Indicator Management:** Increased MAX_INDICATOR_HANDLES from 200 to 500 to support multi-symbol setups. Added timeframe validation in `IsSymbolAvailable` to check if timeframe is within valid range (PERIOD_M1 to PERIOD_MN1). Added paramCount validation in handle methods to ensure correct parameter count is set before creating handles.
- **AI Module Robustness:** Added NaN validation in feature extraction in `NeuralNetworkStrategy.mqh`. Added handling for empty feature vectors with error logging. Added NaN handling in confidence calculations in `EnsembleMetaLearner.mqh`. Added null prediction handling in aggregation to prevent invalid predictions from affecting ensemble decisions. Cached MA handles in `AIFeatureVectorBuilder.mqh` to prevent duplicate handle creation.
- **Pipeline & Engine Reliability:** Added error handling for engine initialization failures in `UnifiedSignalPipeline.mqh` with logging for all engines. Added staleness validation in last good trend reuse logic in `TrendEngine.mqh` to prevent reusing trends from different symbol/timeframe contexts. Added symbol/timeframe mismatch validation in evidence caching to invalidate cache if context changed. Reset readiness fault counter on successful trend update.
- **Signal Validation:** Added input validation for confidence, quality score, and confluence in `AdvancedSignalValidator.mqh`. Added NaN and extreme value handling in quality score calculation. Removed redundant null check in `ValidateCorrelationLimits`.
- **Entry Point Robustness:** Added error handling for malformed symbol string parsing in `MultiStrategyAutonomousEA.mq5` with validation for empty input, split failure, and invalid symbol format.
- **Documentation Improvements:** Clarified MAX_RISK_PER_TRADE constant naming with comment explaining percent scale. Added documentation comment for GetRiskDenominator consistency across components.
- **Compile Verification:** All 34 fixes implemented with minimal, targeted changes preserving existing architecture. Generated comprehensive audit report at `AUDIT_REPORT.md`.
- **Files Modified:** 13 files across Risk, Trading, AI, Pipeline, Engines, Signals, Utils, and entry point.

### Batch 65: AI Diagnostic Recovery & Trade Activation (2026-04-16)
- **Root Cause Identified:** Traced lack of single-voter AI-only quorum to hardcoded thresholding, transformer bridge hard failure, and percentage/fraction mismatch in Drawdown and Risk configuration constraints.
- **Transformer Bridge Robustness:** Made transformer failures soft, utilizing 15 native technical features to sustain NN processing while reporting transformer failure statuses cleanly through `UniversalTransformerService.mqh`.
- **AI Threshold Adaptability:** Allowed `EnsembleAIStrategyAdapter.mqh` a specialized 0.15 exploration mode gate bridging initial zero-history model executions prior to adaptive training accumulation.
- **Manager Consensus Safety Net:** Introduced `effectiveMinVoters = 1` into the `CEnterpriseStrategyManager.mqh` logic strictly bounds by AI-only ecosystem footprints (`<= 3` strategies) blocking generic 2-voter hard floors from nullifying AI models.
- **Synthetic Symbol Volatility Exempted:** Resolved `0.70` ATR percentage checks universally vetoing extreme relative synthetic variations; synthetics now natively pierce volatility filter checks honoring organic Jump/Volatility index mechanics.
- **Risk Value Unification:** Hardened risk constants from literal `0.10/0.20` mappings to percentage mappings `10.0/20.0` explicitly satisfying percentage-expectant risk modules matching existing system patterns.
- **Compile Verification:** 0 errors, 0 warnings. Verified compilation via PS scripts confirming stable structure preservation.
- Batch 73 audit note:
  - Added two new manager-registered Tier-1 structure strategies: `CUnicornModelStrategy` and `CPowerOfThreeStrategy`.
  - Integrated `CISD` and `Turtle Soup` directly into the Unified ICT support stack.
  - Widened the canonical AI feature contract from 55 to 57 features; Python training now consumes exported MT5 feature columns when available so tick-derived features remain parity-safe.

### Batch 79: Weltrade Environment Consolidation & Micro-Account Support (2026-05-13)
- **Environment Discovery:** Hardened `sync_and_compile.ps1` to detect and prioritize `C:\Program Files\MT5 Weltrade` as the root directory, ensuring that `MetaEditor64.exe` and the standard MQL5 includes are mapped from the operator's active installation.
- **Risk Floor Lowering:** Adjusted `MIN_ACCOUNT_BALANCE` in `Core/Utils/Enums.mqh` from `$100.0` to `$1.0`. This modification allows the `RiskValidationGate` to process trades on $10 micro-accounts while still preserving a safety floor for margin calculation.
- **Aggressive-Ready Configuration:** Confirmed that `maxRiskPerTradePercent` is initialized to `100.0` in the EA orchestrator, allowing users to manually override conservative risk (0.75%) with aggressive settings (5-10%) suitable for $10 test accounts.
- **Validation:** Clean synchronization and compilation of `MultiStrategyAutonomousEA.mq5` and `TrainingDataExporter.mq5` to the Weltrade environment with 0 errors and 0 warnings.
