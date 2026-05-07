# SYSTEM_STRUCTURE.md

## Document Metadata
- Last Updated: 2026-04-27
- Scope: Full structural description of runtime system
- Source of Truth: Current repository implementation
- Current Batch: 76 - AI Control Surface Clarification, Lifecycle Safety & Candlestick Cleanup

## 1. System Goal
Provide autonomous, multi-strategy trade decisions with clear ownership boundaries:
- signal generation and consensus
- robust session-aware execution
- adaptive AI thresholding
- pre-trade risk veto
- execution
- post-trade feedback and adaptation

The system prioritizes deterministic control flow, explicit diagnostics, and shadow-first rollout capability.

## 2. Top-Level Runtime Topology

### 2.1 Entrypoint and orchestration
- File: `MultiStrategyAutonomousEA.mq5`
- Responsibilities:
  - initialize mandatory runtime subsystems first and isolate optional AI/bootstrap failures behind readiness flags
  - initialize the shared universal transformer service before optional AI brains register symbols, and keep the service lazy-safe for late callers
  - validate active symbols and emit startup account-capacity diagnostics before live execution
  - reject symbols with extreme spreads (>1000 points) during symbol validation to prevent wasted evaluation cycles
  - rebuild cadence scheduler state as one unit after manager bootstrap so symbol-bar times, intrabar timers, pending new-bar work, and scan-state backoff cannot drift out of sync
  - reconstruct cooldown/trade-timing state from EA-owned open positions and deal history on startup
  - keep `OnTimer()` as the single heavy-evaluation owner and keep `OnTick()` constrained to safety/lifecycle work
  - maintain cadence loops (new-bar/intrabar)
  - budget heavy signal evaluations across both new-bar and intrabar paths via `InpMaxSignalEvaluationsPerCycle`, carrying deferred new-bar symbols forward to later cycles
  - budget intrabar scans by symbol yield instead of blindly scanning the whole intrabar universe every cycle
  - apply per-symbol intrabar backoff after repeated low-yield or readiness-faulted scans
  - self-heal cadence scheduler state at runtime if any scheduler array drifts away from the active symbol set
  - dispatch per-symbol evaluations
  - rank approved candidates across symbols before execution
  - reserve and release the cycle-best candidate as a virtual position inside unified risk while scan-time ranking is still in progress
  - detect synthetic-index tick-velocity spikes and trigger flatten-plus-pause protection
  - register the `Unicorn Model` and `Power of Three` ICT expansion strategies as manager-owned Tier-1 participants
  - own the non-AI confidence policy inputs for pipeline and manager admission stages
  - adapt per-symbol runtime profiles (strategy roster, intrabar policy, and context posture) by instrument class when symbol-class profiles are enabled
  - emit explicit mode-mask diagnostics when indicator profile entries remain configured but the effective runtime mode filters them out of the active registry
  - emit explicit AI topology diagnostics so MT5-native voters, Python-trained ONNX runtime voting, Python sidecar expectations, and external LLM reasoning are not conflated
  - coordinate validator/risk/execution path
  - handle runtime telemetry and deinitialization

### 2.2 Per-symbol strategy domain
- Class: `CEnterpriseStrategyManager`
- One manager per managed symbol.
- Responsibilities:
  - hold registered strategies (core + AI adapters)
  - consume only registry-enabled descriptors so disabled strategies and disabled AI adapters do not enter live manager pools or denominator math
  - execute strategy voting and confidence aggregation
  - own the single authoritative `GetSignal(...)` call for each strategy evaluation so strategies do not pre-consume per-bar state ahead of consensus
  - resolve cross-timeframe vote conflicts via `CTimeframeConsistency`
  - dispatch `OnNewBar` to each strategy using its registered timeframe
  - apply normalized weighted quorum rules by evaluation mode (new-bar vs intrabar eligible pool)
- classify intrabar strategy participation as `OFF`, `PROBE`, or `LIVE` before pipeline work is spent
- modulate live vote influence by role multiplier and rolling strategy `healthScore`
- compute conviction using pipeline evidence (`readiness`, `context`, `cost`) rather than raw confidence alone
- require both directional quality and support-ratio floors before full quorum can pass
- allow a separately tagged `SPARSE_INTRABAR` lane for tightly gated one-sided single-voter packets
- apply symbol-profile-specific sparse intrabar thresholds so synthetic lean rosters can admit strong one-voter structure packets without lowering the same single-voter floor for FX and broader balanced rosters
- require minimum ready-live-weight participation and conflict deadband before directional selection
- admit votes using the active pipeline confidence floor for that evaluation (including regime-relaxed thresholds)
- expose unified `SetConfidenceThreshold(double)` interface for individual strategy sensitivity control
- remain the sole structural admission authority once a packet leaves pipeline screening (`confidence`, `confluence`, directional `quality`, support ratio, effective minimum voters)
  - expose veto codes (`zero_voter`, `single_voter_confidence`, `sparse_support`, `timeframe_conflict`, readiness-related gates) instead of generic quorum-miss text
  - expose per-cycle funnel snapshots and interval consensus diagnostics snapshots
  - emit consensus diagnostics
  - retain last-contributor context for attribution
  - host the new ICT expansion modules (`CUnicornModelStrategy`, `CPowerOfThreeStrategy`) alongside existing `Unified ICT`

### 2.3 Pipeline domain
- Class: `CUnifiedSignalPipeline`
- Responsibilities:
  - cache structural/indicator context once per symbol/timeframe/bar for reuse across strategy votes
  - apply symbol-class-aware context posture so synthetic indices can bypass FX-style ADX trend assumptions while FX keeps full trend filtering
  - apply trend/volatility/liquidity/structure/confidence filters
  - apply deterministic regime + cost viability pre-gate via `CRegimeEngine`
  - recover ATR/Bollinger inputs from raw `CopyRates(...)` data when volatility/regime indicator buffers fault or warm slowly despite mature price history
  - produce reusable evidence snapshot data (`readinessScore`, `contextScore`, `costScore`, effective confidence floor, soft-threshold pass`, readiness class, reuse/staleness flags)
  - allow bounded soft-threshold promotion when near-threshold confidence is supported by strong readiness/context evidence
  - preserve confidence after threshold admission instead of attenuating surviving packets a second time before quorum/validator stages
  - tolerate transient regime data faults by reusing a recent same-context valid snapshot when safe
  - allow trend partial-readiness to proceed when the underlying series is mature, enabling MA/ATR fallback logic to attempt recovery instead of hard-failing, which reduces persistent readiness vetoes on synthetic indices where `BarsCalculated` may lag behind `Bars()`
  - tolerate transient trend MA/ATR copy faults by reusing a bounded last-good trend snapshot instead of forcing full indicator-set churn
  - trigger bounded `CRegimeEngine` handle self-heal after repeated data faults
  - apply bounded weak-regime intrabar confidence threshold uplift (`min(base+cap, base*multiplier)`) using `CRegimeEngine` snapshot state as the authority
  - emit threshold-source telemetry (`[PIPELINE-THRESHOLD]`)
  - emit regime/cost veto telemetry (`[REGIME-STATE]`, `[COST-GATE]`, `[ENTRY-VETO]`)

### 2.4 Shared AI feature contract
- Class: `CAIFeatureVectorBuilder`
- The canonical runtime/training feature width is now `57`.
- Features `0..54` remain the original OHLCV/indicator-derived contract.
- Feature `55` adds tick-level Order Flow Imbalance (OFI) context.
- Feature `56` adds synthetic spike-recovery context (`time since last spike`, normalized) for synthetic-style symbols and defaults to `1.0` elsewhere.
- `TrainingDataExporter.mq5` can export the full 57-feature contract directly.
- `Python/data_pipeline.py` now prefers exported `feature_*` columns when present, preserving parity for tick-derived features that cannot be reconstructed faithfully from OHLCV alone.
  - normalize decision hygiene before final consensus acceptance without hot-path hedging neutralization
  - keep runtime diagnostics authoritative in the manager/runtime layer rather than spinning local `SignalDiagnostics` sinks per pipeline instance

### 2.4 AI adaptation domain
- Runtime owner: `CAIEngine`
- Strategy-vote owners: symbol-scoped adapters in `Core/Strategy/`
- Responsibilities:
  - register only enabled AI adapters; dormant adapter definitions stay out of runtime identity and weighting surfaces
  - keep the shared transformer encoder bootstrap idempotent so indirect callers cannot observe a registered symbol against an uninitialized encoder
  - maintain AI runtime configuration, telemetry, and adaptation state
  - adapt weights and feed updates back to managers through the current runtime control path
  - gate neural weight mutation behind real trade-linked labels so pseudo-label accumulation alone cannot drive online weight drift
  - capture throttled external-LLM reasoning during adaptation when enabled and keep that path fully observable through `[EXT-LLM]`
  - remain optional at runtime; orchestration/adaptation failure disables AI adaptation without violating trade/risk/execution ownership
  - avoid duplicate component-local diagnostics so AI observability remains concentrated in `[AI-VOTE]`, manager telemetry, and runtime heartbeat surfaces
  - enforce a `0.70` minimum runtime confidence floor for the hardened AI defaults
  - reload Python-exported ONNX scaler parameters (`scaler.bin`) before inference when updated in Common files
  - make runtime topology explicit:
    - `CNextGenStrategyBrain` / Universal Transformer = local feature brain, not a direct live voter
    - `Neural Network AI`, `Transformer AI`, `Ensemble AI` = MT5-native live-voter families
    - `ONNX AI` = Python-trained model executed inside MT5 as a live voter
    - `InpPythonBridgeMode` / `InpPythonBridgeEndpoint` = operator telemetry for sidecar expectations only; not a live consensus bridge today
    - external LLM = reasoning/adaptation sidecar only, not a direct live voter
- **Multi-Tier Signal Validation (Batch 60):** Comprehensive validation architecture implemented:
  - Class: `CTieredSignalValidator` (integrated into orchestrator)
  - Responsibilities:
    - Evaluate signals across Tier 1 (Institutional), Tier 2 (Structure), and Tier 3 (Indicators)
    - Analyze directional conflicts between tiers (e.g., T2/T3 vs T1)
    - Implement weighted decision-making considering setup quality and tier weights
    - Track historical accuracy and reliability by tier to inform voting
    - Provide conflict resolution protocols (e.g., Tier 1 dominance vs Tier 2+3 consensus)
- **AI Feature Engineering (Batch 58):** Neural network architecture expanded:
  - Feature vector dimension: 25 → 44 (19 pattern-specific features added)
  - Weight matrix dimensions: `W1[44][32]` to accommodate expanded input
  - Pattern-specific features include: Higher Highs/Lower Lows sequences, Support/Resistance touch counts, Fibonacci Retracement proximity, Pivot Point proximity, volume profile features, market structure features
- **Multi-scale Attention Infrastructure (Batch 58):** Transformer brain enhanced:
  - Per-head scaling factors (`m_headScales[]`) for differential attention scaling
  - Per-head time window sizes (`m_headTimeScales[]`) for short/medium/long horizon awareness
  - Per-head learning rates (`m_headLearningRates[]`) for differential training dynamics
- **Pattern Classification Head (Batch 58):** 10-class pattern classifier added:
  - New weight matrices: `m_patternWeights[10][m_dModel]` and biases `m_patternBiases[10]`
  - Cross-entropy loss training for pattern recognition
  - Xavier initialization for pattern head weights
  - Methods: `ComputePatternProbabilities()`, `UpdatePatternHead()`, `GetPatternPredictions()`, `TrainPatternStep()`
- **External LLM Integration (Batch 58):** Optional external LLM support via `CAIEngine`:
  - HTTP client for Ollama API communication (`http://localhost:11434/api/generate`)
  - Configuration flag: `useExternalLLM` in `SAIAdaptiveConfig` (default `false`)
  - Methods: `QueryExternalLLM()`, `SynthesizeSignals()`, `GenerateTradeExplanation()`, `AssessRisk()`, `ReasonStrategyWeights()`, `ProvideFeedback()`
  - Runtime control: `ConfigureExternalLLM()`, `SetExternalLLMEnabled(bool)`, `IsExternalLLMEnabled()`
  - Runtime observability: `[EXT-LLM]` now covers init, endpoint config, query start/success/failure, reasoning capture, feedback, and shutdown so "enabled but unused" states are visible from logs

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
  - executed-risk registration after successful synchronous sends, scaled by actual fill ratio
  - portfolio correlation fallback uses bounded value (0.65, capped to `m_maxCorrelation`) when correlation data is unavailable, avoiding hard blocks while preserving safety
  - progressively throttle recommended per-trade risk as daily and portfolio utilization rise, instead of waiting for the final hard-cap stage
  - maintain a scan-time `CVirtualPositionBook` so cycle-best reservations count against projected daily and portfolio usage before the final execution winner is sent

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
  - validate protective stop modifications against executable quote side with extra stop/freeze cushion instead of only the generic position price snapshot
  - perform one widened retry on `TRADE_RETCODE_INVALID_STOPS` before surfacing a protective-modification failure
  - emergency-aware protective modification flow
  - expose execution receipt status (`requestId`, retcode, requested/fill volume, request/fill price, slippage points, round-trip latency, retry count, avg fill price) for post-send handling
  - check market hours before position closure/modification (blocks only when `SYMBOL_TRADE_MODE_DISABLED`, allows `SYMBOL_TRADE_MODE_CLOSEONLY`)

### 2.7 Position lifecycle domain
- Owner: `MultiStrategyAutonomousEA.mq5` safety/timer lifecycle loop using `CTradeManager::ManageAllPositions(...)`
- The generic EA-level breakeven/trailing lifecycle is now operator-controlled through:
  - `InpEnablePositionLifecycleManager`
  - `InpLifecycleBreakevenBufferPoints`
  - `InpLifecycleTrailingDistancePoints`
  - `InpLifecycleTrailingStepPoints`
- Default posture is disabled to avoid hidden scalp-style exits overriding wider structural trade intent.
- Responsibilities:
  - trailing/BE/partial-close lifecycle handling
  - scale breakeven, trailing, and partial-close triggers against original stop distance so lifecycle behavior stays proportional across FX and wide-stop synthetic symbols
  - treat configured pip values as broker-floor-aware minimums instead of absolute fixed thresholds
  - run from the lightweight safety loop once per second instead of inside the heavy symbol-scan path
  - managed by EA magic scope

### 2.8 Shared indicator domain
- Class: `CIndicatorManager`
- Responsibilities:
  - indicator handle cache and shared access
  - periodic unused release
  - explicit singleton teardown on deinit
  - remain the first ATR source for validator/execution sizing, with raw-rate fallback in the EA entry path when a direct ATR handle read misses

### 2.9 Chart visualization domain (Batch 58)
- Class: `CChartDrawingManager`
- Responsibilities:
  - centralized chart drawing coordination across all strategies
  - color scheme management with consistent professional palette
  - drawing configuration per feature type (structure, SR, OB, FVG, etc.)
  - **Chart Visualization Hardening (Batch 58):**
    - Elliott Wave strategy draws comprehensive Fib target levels for all waves (W1-W5)
    - Trend lines use thin dashed style (STYLE_DOT, width 1) with muted colors
    - ICT drawing colors (OB, FVG, Liquidity, BOS, CHOCH) reduced in intensity using 0x909090 mask
    - SupportResistance trendlines aligned to thin dashed style for consistency
    - All chart elements use consistent thin dashed styling for improved clarity

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
- ONNX adapter (`COnnxAIStrategyAdapter`)
- Registration is registry-driven and active-only: disabled adapters are not instantiated into managers or orchestrator identity sets, and the legacy `InpUseOrchestrator` toggle has been removed.

**Memory Safety**: All AI adapters implement RAII patterns with proper cleanup of transformer models and comprehensive error handling. Constants are used throughout to eliminate magic numbers.
**Runtime Efficiency**:
- inference is cached per bar in the adapter or backing AI module so repeated same-bar `GetSignal(...)` calls do not rerun transformer/NN forward passes
- feature-build/inference failures are cached as `NONE` for the rest of the bar to avoid hot-loop retries on unchanged data
- `CNextGenStrategyBrain` now runs as a local-only transformer path and exposes dashboard-safe readiness/runtime-mode state instead of legacy cloud/hybrid labels
- `CEnsembleMetaLearner` now aggregates model class probabilities via `GetPredictions(...)` and uses container ownership correctly (`CArrayObj::FreeMode(true)`) to avoid double-delete behavior
- `CNextGenStrategyBrain` now builds its inference tensors directly from `CAIFeatureVectorBuilder`, and the redundant `CMarketDataProcessor` layer has been removed from runtime execution
- `CNeuralNetworkStrategy` and `CUncertaintyQuantifier` use ring-buffered histories instead of heap churn or `Delete(0)`/array-shift patterns
- All three AI adapters now expose explicit last-decision reason tags on abstain and signal paths, eliminating manager-side `UNTAGGED_NO_SIGNAL` blind spots during AI-enabled audits
- All AI strategy adapters implement a unified `SetConfidenceThreshold(double)` interface for dynamic authoritative thresholding from the EA orchestrator
- The feature contract is now unified at 55 engineered inputs shared by the MQL runtime and the offline `Python/` ONNX training/export pipeline
- `Resources/model.onnx` is embedded as an EA resource, and `COnnxBrain` supports shadow-handle hot-swap promotion from a Common-files update path
- `CPipelineScaler` keeps the ONNX feature normalization path aligned with Python `StandardScaler` exports and can hot-reload updated scaler parameters without restarting the EA

### 3.3 Curated runtime profile (Batch 41)
Curated mode restricts runtime active set to a smaller operational profile while preserving full retained implementation in code.
- **Default curated roster** (Batch 41): Elliott Wave + Unified ICT only
  - Removed: Momentum (consistently filtered on no-crossover, adds denominator weight without productive votes), Trend (100% filtered on no-entry), Support/Resistance (rarely productive)
  - Rationale: Eliminates impossible quorum math where 1-2 real votes were rejected because inactive strategies inflated the weight pool; reduces default weight pool from 10.865 to ~4.2
  - Fresh input defaults now match that curated baseline so new sessions stay lean without hidden runtime rewrites
  - Explicit per-strategy enable flags override the curated baseline and remain authoritative for registration and voting
  - Disabled strategies are not registered into managers/orchestrator by default, so dormant code stays available for testing without inflating runtime weight pools, scan time, or duplicate logs

### 3.4 Institutional governance roles
- Strategy registration now includes explicit governance metadata:
  - role: `PRIMARY_ALPHA`, `CONTEXT_FEATURE`, `SHADOW_RESEARCH`
  - cluster: `TREND_CLUSTER`, `MEAN_REVERSION_CLUSTER`, `STRUCTURE_CLUSTER`, `NONE`
- Default policy:
  - all enabled retained strategies are registered as `PRIMARY_ALPHA` and vote live
  - per-strategy inputs gate registration (disabled strategies are not registered into the pool)
  - disabled strategies and disabled AI adapters are not instantiated into live manager pools, orchestrator identity maps, or weight summaries
- Intrabar eligibility is explicit and authoritative: when an enabled strategy's intrabar flag is `true`, that strategy is promoted into the live intrabar voter pool instead of a hidden probe-only lane.
- `EA_MODE_HYBRID` is indicator-led by design: indicator-backed candidates remain admissible when AI abstains, AI corroboration is additive, and AI-only packets are rejected unless the effective runtime mode is AI-primary.
- `EA_MODE_AI_ONLY` is now a strict operating mode: when `InpEAMode=EA_MODE_AI_ONLY`, indicator strategies are filtered from the strategy registry at startup, ensuring the engine runs exclusively on AI votes.
- AI adapters can be the sole tradable family on both new-bar and timed intrabar paths when enabled.
- AI intrabar participation is strategy-scoped (`InpIntrabarEligibilityNeuralNetworkAI`, `InpIntrabarEligibilityTransformerAI`, `InpIntrabarEligibilityEnsembleAI`, `InpIntrabarEligibilityOnnxAI`) instead of being hard-forced `OFF` at governance time.
- Governance startup logs now mark disabled strategies as `INACTIVE` in the intrabar summary instead of implying they are live because a different profile leaves the raw input toggles set.
- Symbol-class governance now exists above raw enable flags:
  - FX symbols keep the full enabled roster unless manually disabled
  - synthetic symbols (`Volatility`, `Jump`, `Step`, `Boom/Crash`, `Range Break`, `PainX`) switch to a lean structure-first profile when structure-capable strategies are enabled, suppressing `Momentum` and `Trend` from that symbol's active manager roster
  - under that same synthetic lean profile, `Fibonacci`, `Elliott Wave`, `Support/Resistance`, and `Unified ICT` remain intrabar `LIVE`, while `Candlestick` stays registered for new-bar participation but is reduced to intrabar `PROBE`
  - if the operator enables only `Momentum` / `Trend` on a synthetic symbol, the profile does not zero the roster; manual fallback remains available
- Strategy trust is continuous, not purely binary:
  - `healthScore` is updated from realized closed-trade outcomes
  - live vote weight is scaled by reliability instead of only live/shadow membership
- Manager-level controls are exposed by strategy name for role, cluster, live-vote eligibility, and shadow mode.

### 3.5 Unified ICT Architecture
The `StrategyUnifiedICT` module operates as a dedicated institutional-flow container with strict rule adherence:
- **FVG & Order Block Models:** detection is strictly gap-based (no body color/size filters), and mitigation requires a full boundary close, not just midpoint touches. Source order blocks are dynamically anchored to 3-bar displacement impulses.
- **Session Context:** `CSessionGapDetector` tracks NDOG/NWOG opening gaps and fill percentages. `CICTKillZones` enforces Silver Bullet windows. `CAMDDetector` defines Accumulation/Manipulation/Distribution phase sweeps to time structural reversals.
- **Institutional References & Order Flow:** `CLiquidityDetector` now injects monthly/quarterly highs-lows plus NY midnight and quarterly opens, `CAnchoredVWAP` anchors to the latest institutional reference, and `CCumulativeDelta` contributes directional pressure confirmation into POI scoring.
- **Advanced Block Taxonomy:** `CAdvancedOrderBlockDetector` now includes propulsion, rejection, and vacuum blocks in the same order-block contract used by entry selection, mitigation checks, chart drawing, and TP targeting.
- **Confluence Scoring:** Replaces flat array counting with a weighted 0-130 point scale (`ScoreConfluences(...)`). Highest weights are given to Order Block presence (30pts) and FVG/Sweeps (20pts).
- **Dynamic Confidence:** `ComputeEntryConfidence(...)` generates probabilistic confidence scalars dynamically using Market Structure break types (CHoCH = high, BOS = mid) combined with AMD Distribution phase alignment.
- **Institutional TP Hierarchy:** `CalculateTakeProfits(...)` bypasses fixed Risk:Reward scaling. Targets are structurally anchored (TP1 = Opposing FVG CE, TP2 = Opposing OB CE, TP3 = Unswept Liquidity).
- **Position Scaling:** `CICTPositionSizer` governs trade volume using an equity-aware point distance formula, half-Kelly caps from recent symbol-specific closed-deal stats, and hard daily/weekly drawdown guards.

### 3.6 Support/Resistance & Trendline Architecture
The `StrategySupportResistance` and `TrendlineDetector` operate under a rigid, non-repainting framework optimized for look-ahead safety and chart performance:
- **ATR-Driven Clustering:** S/R levels and Trendline swings are normalized using dynamic ATR thresholds. The clustering algorithm merges nodes not by an arithmetic average, but by promoting the highest-strength focal line.
- **Look-Ahead Bias Elimination:** All logic within `CTrendEntryTypes`, `CSRBounceStrategy`, `CSRBreakoutStrategy`, and `CSupportResistanceDetector` strictly evaluates signal breaks and touches against `bar[1]` (completed-bar confirmation), blocking forward-sniffing.
- **Dynamic Chart Optimization:** Instead of emitting unlimited background markers, graphical line rendering passes through a bubble-sort array capping output strictly to the Top 8 highest-strength horizontal zones and Top 6 slope-validated trendlines.
- **ATR Position Scaling:** Fixed pips have been removed entirely. `CADXPositionSizing` dynamically calculates Lot Size exclusively using exact market Tick Sizes/Values relative to physical price distance.
- **Indicator Handle Hygiene:** clean detector paths now cache ATR handles at initialization and reuse them during repeated detection/touch passes instead of creating and releasing indicator handles inside hot methods.

## 3.7 AXIOM Refactor Notes
- The AXIOM refactor batch was a structural efficiency pass, not a strategy-logic rewrite.
- Main outcomes:
  - removed dead AI/control-flow branches and no-op lifecycle surface
  - stabilized AI hot paths around bar-cached inference
  - replaced repeated O(n) history shifts with fixed-size ring buffers in AI data structures
  - separated mandatory runtime bootstrap from optional AI/bootstrap subsystems
  - tightened detector-level indicator lifecycle in clean hot paths

## 4. Decision Pipeline (Signal to Execution)

### 4.1 Cadence selection
- Startup emits per-symbol `[ACCOUNT-CAPACITY]` diagnostics before the first live scan and reconstructs `[TRADE-STATE]` so inherited EA positions carry cooldown forward across restarts.
- Shared validator spread-shock state is symbol-scoped, not portfolio-global, so cross-symbol spread contamination cannot veto otherwise valid candidates.
- New-bar path: conservative scan cadence.
- Intrabar path: timer-driven scans when enabled.
- Heavy evaluation work is cycle-budgeted: pending new-bar symbols are selected first, deferred cleanly when the cycle budget is exhausted, and only the remaining budget may be spent on intrabar work.
- Startup/runtime symbol-state priming now seeds one pending new-bar evaluation per validated symbol, preventing cold-start idle loops where managers exist but no symbol is ever admitted into the first scan.
- Global cadence now defaults to hybrid live scanning: `InpSignalScanOnNewBarOnly=false` keeps timed intrabar scheduling active out of the box, while startup telemetry still emits `[CADENCE-WARNING]` whenever operators explicitly force a strict new-bar-only posture.
- Default intrabar breadth is slightly widened for live verification (`InpMaxIntrabarSymbolsPerCycle=4`) so restored timer cadence spends its budget on more than a minimal subset of the managed symbol universe.
- Symbol evaluation start index rotates each cycle to reduce deterministic first-symbol concentration.
- Intrabar symbol selection is yield-aware: recent near-miss symbols, recent generators, and readiness-healthy symbols are prioritized first.
- Per-symbol intrabar backoff tiers escalate from base cadence to `30s`, then `60s`, then suspension until a new bar resets the symbol.

### 4.2 Consensus
- Manager computes strategy votes and confidence.
- Mixed-timeframe conflicts are resolved with `CTimeframeConsistency` before final consensus acceptance.
- Quorum is evaluated via normalized weighted conviction pooling:
  - adjusted live weight = `base strategy weight x role multiplier x healthScore reliability multiplier`
  - ready live weight = `adjusted live weight x pipeline readinessScore`
  - **dynamic weight decay** (Batch 41): strategies filtering ≥ 3 consecutive cycles have weight decayed by `m_strategyActivityDecayRate` per additional filter, reducing denominator bloat; weight recovers when strategy votes
  - per-direction conviction = `sum(ready live weight x conviction_i)` for agreeing live voters
  - conviction is confidence shaped by pipeline `contextScore`, `readinessScore`, and `costScore`
  - directional quality = `direction conviction / direction weight`
  - support ratio = `direction weight / total ready live weight`
  - **adaptive quorum thresholds** (Batch 41): direction passes full quorum if:
    - 1 active voter: `directional_quality >= 0.40`, support ≥ 0.15
    - 2 active voters: `directional_quality >= 0.48`, support ≥ 0.30
    - 3+ active voters: `directional_quality >= InpQuorumThreshold (0.55)`, support ≥ scan-mode floor
    - AND agreeing voters clear the effective minimum AND `readyLiveWeight / totalLiveWeight >= InpConsensusMinReadyWeightRatio`
  - Adaptive thresholds prevent denominator dilution where inactive strategies inflate the weight pool; single/dual-voter consensus can now pass with proportional thresholds
- if both directions pass, higher score wins unless the spread is inside the configured conflict deadband, in which case consensus is vetoed to `TRADE_SIGNAL_NONE`
- intrabar may instead admit a `SPARSE_INTRABAR` decision when exactly one direction has one voter and readiness/context/cost/support/coverage thresholds all remain high
- Vote admission into quorum reuses the pipeline's effective confidence threshold for that cycle, preventing pipeline-approved relaxed-threshold signals from being dropped before consensus.
- Consensus may fail by:
  - raw no-vote
  - quorum miss (threshold and/or min voters)
  - intrabar ineligibility
  - filter rejection
- **Detailed veto diagnostics** (Batch 41): failures emit specific veto codes with numeric evidence:
  - `no_voters`: no strategies produced votes
  - `insufficient_quality`: shows actual quality vs required, voter count, support ratio
  - `insufficient_support`: shows actual support vs required floor, voter count, quality
  - `insufficient_readiness_weight`: shows ready vs minimum required weight
- `direction_quorum_not_met`: shows all four dimensions (buy/sell quality and support)
- Post-quorum nullification is emitted as `[CONSENSUS-VETO]` when timeframe consistency or the intrabar single-voter floor clears an otherwise qualified candidate.
- Untagged placeholder abstentions (`BASE_INITIALIZED`, empty override tags) are defensively downgraded before ready-live weighting so broken strategy telemetry cannot silently bloat the quorum denominator.

### 4.3 Validation
- `CAdvancedSignalValidator` now runs in manager-owned admission mode during normal runtime.
- In that mode, validator is exogenous-only: it enforces spread, time, session, volatility, and cost-viability sanity after manager quorum has already admitted the packet.
- Structural confidence / confluence / quality / support admission remains manager-owned and is not re-adjudicated by validator when `SetManagerOwnedAdmission(true)` is active.
- Validator profiles remain input-configurable by scan mode (new-bar vs intrabar): minimum confidence, minimum strategy confluence, and minimum quality score.
- Those profile inputs are now a telemetry/fallback surface in normal runtime rather than a second structural authority; they remain available for legacy/non-manager-owned validator mode if explicitly re-enabled.
- Validator quality still consumes upstream decision-path evidence (`conviction`, `readiness`, `context`, `cost`, `diversity`, `freshness`) plus manager quorum evidence (`effectiveMinVoters`, `directionalQuality`, `supportRatio`) so exogenous validation telemetry stays aligned with the already-authoritative manager decision.
- Near-threshold confidence and confluence can soft-pass within bounded margins when the broader evidence profile is strong.
- Near-threshold quality can now also soft-pass for strong new-bar single-voter packets when the quality gap is small and the broader evidence profile remains strong.
- Time and session filters are evaluated in GMT, and synthetic off-hours detection now recognizes both Deriv-style and Weltrade-style synthetic symbol families.
- Rejected signals emit reasoned logs.
- Entry-governance blocks (cooldown, total-position cap, unresolved unprotected positions, per-symbol capacity) apply after validation so approved signals remain visible in diagnostics even when sends are paused.
- Cost viability parameters are explicit (`spread/ATR`, spread-shock cooldown).

### 4.4 Risk gate
- Pre-size validation to accept/reject candidate conditions.
- Position sizing computes lot.
- Post-size validation with actual lot before execution.
- Unprotected-position remediation runs before new-entry scans; unresolved states pause new entries until resolved.
- Trade requests carry role/cluster/contributor context for cluster-aware risk governance.

### 4.5 Execution branch
- Cooldown and capacity logic are entry-only gates; they do not suppress consensus or validator execution.
- The runtime stages every risk-approved opportunity as a candidate and ranks them across the full symbol scan before sending.
- Shadow mode: logs virtual trade, no send.
- Live mode: send through `CTradeManager`.
- Startup emits `[EXECUTION-MODE]` so shadow/live posture is explicit before the first scan.
- Startup rejects unsupported non-hedging account models before runtime ownership becomes ambiguous.
- Live comment tagging carries compact cluster code (`K:T/R/S/N`) for deterministic open-position cluster attribution.
- Live execution telemetry now includes broker request/fill price, slippage points, and round-trip latency through `[EXECUTION-TELEMETRY]`, `[TRADE-SUCCESS]`, `[TRADE-ERROR]`, and `[TRADE-EXECUTION]`.
- Execution receipts and fill deltas are surfaced to the EA so post-send accounting uses actual fill state rather than requested size alone.

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
- Startup state: `[ACCOUNT-CAPACITY]`, `[TRADE-STATE]`
- Conversion funnel: `[HEARTBEAT-FUNNEL]`, `[CONVERSION-RATES]`
- Entry suppression telemetry: `[ENTERPRISE-BLOCKED]`
- Risk budget split: `[RISK-BUDGET]`
- Unprotected remediation: `[RISK-UNPROTECTED]`
- External capacity denial: `[CAPACITY-EXTERNAL]`
- Consensus diagnostics: `[CONSENSUS-QUORUM]`, `[CONSENSUS-DIAG]`, `[CONSENSUS-ROOT]`, `[CONSENSUS-SNAPSHOT]`, `[CONSENSUS-STRATEGY]`, `[CONSENSUS-ACTIVE]`
- Post-quorum veto diagnostics: `[CONSENSUS-VETO]`
- Governance diagnostics: `[CONSENSUS-ROLE]`, `[CONSENSUS-CLUSTER]`, `[ROLE-CLUSTER]`
- Strategy reject attribution: `[STRATEGY-REJECTS]`
- Signal rejection reasons: `[SIGNAL-REJECTED]`
- Candidate ranking telemetry: `[SCAN-CANDIDATE]`, `[SCAN-DECISION]`
- Threshold source tracing: `[PIPELINE-THRESHOLD]`
- Regime/cost viability tracing: `[REGIME-STATE]`, `[COST-GATE]`, `[ENTRY-VETO]`, `[TrendEngine][READINESS-FAULT]`
- No-vote telemetry now preserves aggregate readiness/context/cost from the ready live pool, and `[COST-GATE]` prints both spread/ATR ratio and raw spread/ATR values so tiny-but-real spread ratios do not look like dead zeros.
- No-signal deadlock alerting: `[NO-SIGNAL-ALERT]`
- Cluster risk governance tracing: `[RISK-CLUSTER]`, `[RISK-MUTEX-BLOCK]`
- Virtual reservation tracing: `[RISK-VIRTUAL]`
- AI liveness: `[AI-VOTE]`
- confirmed deals: `[TRADE-CONFIRMED]`
- Shadow actions: `[SHADOW-TRADE]`
- Execution outcomes: `[TRADE-SUCCESS]`, `[TRADE-ERROR]`, `[TRADE-EXECUTION]`, `[EXECUTION-RECEIPT]`, `[EXECUTION-TELEMETRY]`, `[FILL-DIFF]`

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
- `TrainingDataExporter.ini`
- `shadow_session_mt5_tester.ini`
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

## 11. 2026-03-25 Runtime Integrity Deltas
- `CUnifiedSignalPipeline` now owns two distinct layers of state:
  - current-cycle evidence (`m_lastEvidence`)
  - same-bar structural cache (`m_cachedStructuralEvidence`)
- Structural cache now preserves the original engine readiness contract for the bar; later strategy evaluations cannot silently upgrade a warmup/faulted engine into a ready contributor.
- Pipeline startup is now fail-closed for required diagnostics/protection/engine components; `CEnterpriseStrategyManager` aborts initialization if the pipeline cannot be constructed cleanly.
- `CLiquidityEngine` now tracks symbol-scoped point geometry internally instead of using chart-symbol geometry.
- `CRegimeEngine` now resets spread-shock cooldown state on symbol/timeframe context changes, keeping cost gating symbol-local under multi-symbol scans.
- `CPositionSizer` now prefers shared ATR handles from `CIndicatorManager`, reducing split ownership of sizing-critical indicator lifecycle.
- `CTradeManager` execution ownership remains unchanged, but its market-send contract is now three-stage:
  - preflight viability check
  - broker submit
  - bounded fill confirmation
- The EA scan loop now carries a cycle identifier across no-trade, validation, block, candidate, decision, and execution logs for one-cycle traceability.

## 12. 2026-04-01 Default Runtime Remediation
- `CTrendEngine` still owns trend-readiness state, but ATR mature-series failures are now treated as recoverable data faults:
  - attempt bounded ATR fallback from price series
  - if fallback succeeds, emit degraded readiness-state telemetry and continue with valid evidence
  - if fallback fails, degrade explicitly instead of silently pinning the symbol in false warmup
- `MultiStrategyAutonomousEA` still owns scan scheduling, but now distinguishes idle cycles from active work before entering the per-symbol loop. This reduces wasted throughput and makes quiet-cycle accounting more truthful.
- `CEnterpriseStrategyManager` still owns intrabar governance, and `Support/Resistance` now respects the configured probe toggle instead of being silently forced off.
- `CStrategyElliottWaveEnhanced` ownership is unchanged; this batch only repaired MT5 enum usage and removed local min-confidence shadowing so the inherited base threshold remains authoritative.

## 13. 2026-04-01 Strategy Registry + AI Runtime Extension
- `CStrategyRegistry` is now the activation authority for strategy families and EA mode (`InpEAMode`):
  - indicator strategies and AI adapters are registered from one roster
  - unsupported mixes degrade to a viable effective mode during startup
  - startup telemetry emits `[STRATEGY-REGISTRY]`
- `MultiStrategyAutonomousEA` still owns manager bootstrap, but registration is now registry-driven rather than split across independent boolean branches.
- EA mode affects the post-consensus admission contract:
  - `HYBRID` is indicator-led: indicator-backed candidates remain admissible when AI abstains, AI corroboration is additive, and AI-only packets are rejected unless the effective mode is AI-primary
  - `AI_ONLY` allows AI adapters to be the sole tradable family on both new-bar and intrabar paths when AI adapters are enabled
  - `AI_ASSISTED` keeps indicators primary and can add bounded confidence uplift from aligned AI contributors
  - `INDICATOR_FILTERED` requires AI-primary candidates to survive indicator confirmation
- Intrabar scheduling still remains EA-owned:
  - primary budget selection is unchanged
  - a bounded keepalive pick can now revive one symbol when hybrid cadence would otherwise fully starve intrabar work
- `CTrendEngine` now treats mature-series MA fragility similarly to ATR fragility:
  - partial readiness no longer forces immediate hard failure
  - manual EMA fallbacks can reconstruct fast/medium/slow series
  - snapshot reuse remains the final graceful-degradation path
- The AI feature stack is now split more cleanly:
  - transformer adapters use right-sized models and actual sequence lengths
  - `CNeuralNetworkStrategy` validates feature integrity before inference/training
  - NN tail features can be augmented with transformer-encoded context rather than relying on raw handcrafted tail features only

## 14. 2026-04-08 Synthetic Assets 24/7 Hardening
- `CAdvancedSignalValidator` explicitly filters `PainX`, `SFX Vol`, `GainX`, `FX Vol`, and `FlipX` as synthetic 24/7 symbols, allowing them to bypass MT5 weekend and off-hours session blocking.
- `CTradeManager` recognizes the same extended list of synthetics, ensuring live execution paths remain open globally.
- `CMarketAnalysis` safely classifies these assets for specialized indicator handling to prevent volatility/ADX calculation faults unique to their tick profiles.

