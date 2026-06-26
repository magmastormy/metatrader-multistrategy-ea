# SYSTEM\_STRUCTURE.md

## Document Metadata

- Last Updated: 2026-06-25
- Scope: Full structural description of runtime system
- Source of Truth: Current repository implementation
- Current Batch: 106

## 1. System Goal

Provide autonomous, multi-strategy trade decisions with clear ownership boundaries:

- signal generation and consensus
- robust session-aware execution
- adaptive AI thresholding
- pre-trade risk veto
- execution
- post-trade feedback and adaptation

The system prioritizes deterministic control flow, explicit diagnostics, live-capable AI/ONNX execution, and candidate-level shadow fallback when a signal family loses authority.

- Batch 78 replaces global proof-only posture with an adaptive live-authority gate. AI/ONNX can warm-start live at scaled risk, all candidate families collect forward R evidence, and mature families are promoted or demoted from live execution based on expectancy/profit-factor thresholds.
- Batch 80 resolves the AI-only inactivity issue by ensuring experimental AI families (Transformer, Ensemble) receive non-zero weights from the AI multiplier during registry bootstrap, rather than being hard-coded to 0.0.
- Batch 81 makes indicator/hybrid no-signal diagnosis falsifiable and changes the math that was suppressing real producers: runtime fingerprints include requested vs effective EA mode, pipeline-filtered abstentions expose the actual filter chain in manager summaries, infrastructure/raw-none/filtered abstentions no longer inflate the live denominator at full weight, and `Momentum` / `Candlestick` have lower-timeframe scalp/intrabar registration controls.
- Batch 82 removes the "AI-Only" bias by relaxing strategy and consensus filters: softened weight decay (15 bars threshold, 5% rate), lowered tier confidence floors (Tier 3 to 0.62), and enabled high-quality solo strategy signals for live trading. It also introduces "Smart SRE" with Profit Guard and Structural Invalidation, and upgrades the lifecycle manager with dynamic ATR-based trailing stops.
- Batch 90 fixes visualization system vulnerabilities: hardcoded chart ID 0 in StrategyUnifiedICT caused cross-chart contamination; StrategyUnifiedICT/StrategyFibonacci bypassed CChartDrawingManager; no global object counter for MT5 1000-object limit; excessive object retention with maxObjectAge=500; debug logging ran in production; bitwise OR colors caused inconsistent rendering; no coordinate validation for invalid time/price values. All strategies now use CChartDrawingManager with per-strategy object limits, global count alerts at 800/900/950, coordinate validation, explicit RGB colors, and periodic cleanup with maxObjectAge=150. Drawing statistics added to VisualDashboard.
- Batch 91 implements comprehensive enterprise 12-layer audit fixes: addresses circular initialization dependencies, memory leaks, pipeline fail-closed logic, and scalability across all components; adds SharedEngineManager for multi-symbol efficiency, enhanced error aggregation, and configurable verbosity levels.
- Batch 92 implements comprehensive AI modules audit: all 25 findings addressed including memory management, numerical stability, training integrity, checkpoint integrity, and GOD TIER architectural refactoring; adds IAIStrategy interface for unified AI adapter contract.
- Batch 93 implements systematic strategy refactoring for full AGENTS.md architectural compliance: UnifiedICT simplified from 4 to 2 entry types (2,194 → 2,012 lines), StrategyTrend cleaned up (300 → 259 lines), ElliottWave removed (\~1,600 lines), Fibonacci merged into SupportResistance as CFibConfluence module, all 7 active strategies now validate through CUnifiedRiskManager with \[CONSENSUS-DIAG] logging.
- Batch 96 restores profitable execution mechanics: scan cycles retain multiple `CUnifiedRiskManager`-reserved candidates instead of replacing them with one winner, `InpMaxTradeSendsPerCycle` controls ranked multi-send throughput, same-symbol capacity counts EA-owned positions, synthetic symbol detection covers SFX/FX Vol/SwitchX/PainX/GainX/FlipX, and `CTradeManager` stop lifecycle management is magic-filtered and volatility-aware.
- Batch 97 implements the full EA\_SYSTEM\_REDESIGN.md Phase 1-5: centralized indicator access across 8 strategy files, conditional diagnostic logging with `InpLogLevel`, rationalized risk defaults (1% base risk, 5% max per trade, 5% daily, 15% portfolio), unified PositionSizer correlation via `CCorrelationEngine`, broker trading day reset with configurable start hour, TickSafetyMonitor CAccountInfo caching, Kelly Criterion position sizing (`POSITION_SIZE_KELLY`), equity compounding with sqrt upside/linear downside, tiered correlation response (reduce at 0.4, block at 0.7), daily P\&L loss limit circuit breaker, regime-aware strategy weighting (`GetRegimeConfidenceMultiplier`), volatility direction awareness (`GetVolatilityDirection`), multi-timeframe confluence (`IsAlignedWithHigherTF`), cross-cluster conflict resolution in consensus, mandatory SL gate in `CTradeManager`, min R:R enforcement (1:2 default, 1:5 mean-reversion), portfolio profit target with trailing floor, auto mode switching (conservative/aggressive/emergency), and a dedicated scalping engine with `CScalpSignalCache`, three scalp strategies (Momentum, Spread, VolatilityBreakout), async order execution via `OrderSendAsync()`, and dual-path OnTick/OnTimer processing.
- Batch 98 completes the EA Overhaul Blueprint monolith decomposition (R6/R7) and risk framework items: `CPositionSizer::CalculateSize()` is now truly stateless via `CalculateOptimalPositionSizeCore()` (no save/restore hack); position lifecycle management extracted into `CPositionLifecycleManager`; heartbeat/diagnostics extracted into `CDiagnosticsManager` with consensus diagnostics; unprotected position tracking extracted into `CUnprotectedPositionTracker` with 3-attempt SL escalation; synthetic spike monitoring extracted into `CSyntheticSpikeMonitor`; trade attribution and NN prediction mapping extracted into `CTradeAttributionManager`; symbol scan scheduling extracted into `CSymbolScanScheduler`; anti-Martingale dynamic lot scaling added; CICTPositionSizer risk denominator fixed to use `MathMin(balance, equity)`; risk percent scale consistency verified with conversion helpers; cluster rebalancing updated for Conservative tier; Statistical Arbitrage conditionally registered when Python Bridge is connected; heartbeat interval made configurable. Total \~1,180 lines extracted from the main EA monolith into 7 focused manager classes.
- Batch 99 implements log-evidence-driven fixes and research solutions: S/R lot validation ordering fix unblocks 79 SELL signals on PainX 400; ONNX CPU fallback enables signals when CUDA unavailable; AI degenerate model detection downweights 100% BUY/SELL models by 50%; trend bias consensus check raises quorum for counter-trend signals; scalp margin-aware lot cap prevents oversized orders; hybrid gate relaxation lowers AI standalone threshold after indicator drought; P\&L-adjusted risk budget enables re-entries on profitable positions; Bayesian Kelly modifier with Beta-Binomial priors; equity curve manager reduces size when equity < EMA; CVaR portfolio risk integration; commission-aware scalp validation; async trade executor with OrderSendAsync + OnTradeTransaction confirmation.
- Batch 100 adds CSpikeHunterEngine for synthetic CFD indices: 3-layer spike detection (tick velocity ≥ 2.5× average, direction accumulation ≥ 12 ticks, ATR compression ≤ 60%), symbol-aware direction mapping (PainX→SELL, GainX→BUY, etc.), independent spike trades with separate magic numbers (offset 9000), push notification alerts throttled at 120s, and long-term entry cooldown of 60s to prevent re-entry into fading spikes.
- Batch 101 adds four advanced mathematical engines for no-API-required quantitative analysis: CHurstEngine (fractal persistence via variance-time Hurst exponent, regime-based strategy weight multipliers integrated into CRegimeEngine), CVPINFilter (volume-synchronized probability of informed trading from tick data, toxicity-based position sizing and trade blocking), COrnsteinUhlenbeckEngine (mean-reversion speed estimation via OLS, OU-adjusted z-scores integrated into StatisticalArbitrageStrategy), COrderFlowImbalanceEngine (proxy order flow imbalance from tick classification at 3 time scales, Welford z-score normalization, directional confirmation filter in consensus pipeline). Python ML ensemble expanded with CatBoost and XGBoost training scripts, and train\_stacker.py updated to accept both as optional meta-feature sources (6→12 columns, backwards compatible).
- Batch 102 adds the Deriv Asset Profiler system for 18-family synthetic index auto-detection and per-family engine optimization: CDerivAssetProfiler (auto-detects family from symbol name, provides SDerivProfile with 20 fields per family), CGridRecoveryEngine (Hurst-activated grid recovery for mean-reverting families with Modified Martingale and Fibonacci progression), CATRScalpingEngine (ATR-based between-spike scalping with spike window avoidance for Jump/DEX/Hybrid families), SSpikeHunterFamilyOverrides (8 GetEffective*() methods for per-family spike parameter tuning), SSymbolRiskOverride (per-family risk/drawdown scaling in CUnifiedRiskManager). Magic number offsets 7000-9900 allocated per engine and family. New input parameters: InpDerivProfilerEnabled, InpGridRecoveryEnabled, InpATRScalpingEnabled.
- Batch 103 (Enterprise Vision) upgrades the multi-strategy EA to an enterprise consensus engine with 11 strategies: Candlestick v2.0 (7 new pattern detectors + CCandleConfluenceScorer with 0-100 scoring, threshold ≥70), Momentum v2.0 (MACD confirmation, ADX strong trend filter, pullback entry, freshness/volume confidence modifiers), Volatility Breakout v2.0 (TTM Squeeze detection, ADX rising filter, breakout retest, breakout failure reversal), Mean Reversion v2.0 (Stochastic extreme confirmation, Hurst regime lockout H<0.45, BB width filter, no-divergence check, dynamic TP), Statistical Arbitrage (new strategy: pair trading via Python Bridge, OU half-life filter, z-score detection). Consensus engine improvements: regime weight wiring via GetRegimeCategoryMultiplier(), VPIN toxicity integration (EXTREME→block, HIGH→50%, MEDIUM→25%), 0-100 consensus scoring (rawConsensusScore = directionalQuality × supportRatio × 100, threshold=60), OFI regime integration (1.2× boost aligned, 0.7× penalty contradicted). Engine wiring: VPIN/OFI at EnterpriseStrategyManager level, Hurst at MeanReversion level (pointer-based migration), OU at StatisticalArbitrage level.
- Batch 106 (Synthetic Strategy Research + Compounding Tiers + Legacy Cleanup) implements aggressive micro-account growth infrastructure for Deriv synthetics: CCompoundingTierManager (auto-tier switching at $25/$50/$100/$500 milestones, 5 tiers from MICRO_AGGRESSIVE to PROFESSIONAL with per-tier risk/drawdown/position limits), CFamilyStrategyWeightMatrix (per-Deriv-family cluster weight multipliers: Crash/Boom→STRUCTURE 1.5x, Volatility→MEAN_REVERSION 1.5x, HFV→SCALP 2.0x, etc.), CSessionWeightManager (Asian/London/NY/Weekend session-aware sizing and threshold adjustments, weekend 1.2x sizing boost), CSkewStepAnalyzer (200-step rolling buffer phase detection for Skew Step indices, calm/post-spike/counter-due sizing multipliers), per-family position limits in CUnifiedRiskManager (Crash/Boom max 2, Volatility max 3, HFV max 2), ADX lot modifier wired into position sizer chain, PythonBridge correlation methods fixed (JSON parsing for GetPairCorrelation/FindBestCorrelatedPair), Batch 103 strategy weights made user-configurable (InpWeightFVGScalper/TurtleSoup/BreakerBlock/NYOpenGap/AsianRangeBreak), legacy dead code cleanup (removed CMarketAnalysis global, CStrategyWrapper include, 34+ dead REMOVED comments, Fibonacci/Elliott Wave commented-out registration blocks).

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
  - delegate position lifecycle management to `CPositionLifecycleManager` (SRE, structural invalidation, breakeven/trailing, safe mode)
  - delegate heartbeat and diagnostics to `CDiagnosticsManager` (core heartbeat, consensus diagnostics, conversion rates, risk budget snapshot)
  - delegate unprotected position tracking and SL remediation to `CUnprotectedPositionTracker` (3-attempt escalation)
  - delegate synthetic tick spike monitoring and trading pause to `CSyntheticSpikeMonitor`
  - delegate trade attribution and NN prediction mapping to `CTradeAttributionManager`
  - delegate symbol scan scheduling and intrabar scoring to `CSymbolScanScheduler`
  - budget heavy signal evaluations across both new-bar and intrabar paths via `InpMaxSignalEvaluationsPerCycle`, carrying deferred new-bar symbols forward to later cycles
  - budget intrabar scans by symbol yield instead of blindly scanning the whole intrabar universe every cycle
  - apply per-symbol intrabar backoff after repeated low-yield or readiness-faulted scans
  - self-heal cadence scheduler state at runtime if any scheduler array drifts away from the active symbol set
  - dispatch per-symbol evaluations
  - rank approved candidates across symbols before execution
  - reserve every staged candidate as a virtual position inside unified risk before it can enter the ranked execution list
  - execute up to `InpMaxTradeSendsPerCycle` ranked candidates per scan cycle through `CTradeManager`, preserving runtime execution ownership
  - detect synthetic-index tick-velocity spikes and trigger flatten-plus-pause protection
  - register the `Unicorn Model` and `Power of Three` ICT expansion strategies as manager-owned Tier-1 participants
  - own the non-AI confidence policy inputs for pipeline and manager admission stages
  - resolve strategy registration timeframes per strategy so scalp/intrabar modules can use lower timeframes than the attached chart when explicitly configured
  - adapt per-symbol runtime profiles (strategy roster, intrabar policy, and context posture) by instrument class when symbol-class profiles are enabled
  - emit explicit mode-mask diagnostics when indicator profile entries remain configured but the effective runtime mode filters them out of the active registry
  - emit runtime fingerprints with both requested and effective EA mode so `AI_ONLY` logs cannot be mistaken for failed indicator/hybrid participation
  - emit explicit AI topology diagnostics so MT5-native voters, Python-trained ONNX runtime voting, Python sidecar expectations, and external LLM reasoning are not conflated
  - coordinate validator/risk/execution path
  - enforce live-authority source defaults: AI/ONNX enabled, global live execution allowed, candidate-level shadow fallback for unproven packets, EA-owned same-symbol stacking, and no one-voter sparse intrabar admission
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
- compute live denominator weight from the strategy's actual contribution class so raw-none cycles, pipeline-filtered packets, and warmup/unavailable infrastructure abstentions do not pretend to be full support evidence
- downgrade warmup/unavailable/infrastructure abstentions before ready-live-weight math so a dead or warming adapter does not pretend to be useful consensus evidence
- require both directional quality and support-ratio floors before full quorum can pass
- keep one-voter sparse intrabar admission disabled by default; the tagged `SPARSE_INTRABAR` lane is an explicit opt-in proof surface only
- allow high-confidence AI-only HYBRID packets through the explicit live-authority path instead of the sparse one-voter path
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
  - apply trend-direction bias check: raise effectiveQualityThreshold to 0.70 when strong trend opposes consensus direction
  - apply AI calibration: degenerate models (direction ratio > 0.80 in last 20 predictions) have effective weight reduced by 50% via `GetCalibratedWeight()`

### 2.3 Extracted Lifecycle Managers

#### CPositionLifecycleManager

- File: `Core/Management/PositionLifecycleManager.mqh`
- Responsibilities:
  - Signal Reversal Exit (SRE) with breathing room, last-stand zone, profit guard
  - Structural Invalidation exit (ICT/Structure trend flip)
  - Breakeven and trailing stop delegation to `CTradeManager`
  - Safe mode partial profit taking for conservative tier
  - Configurable via `ConfigureSRE()` and `ConfigureLifecycle()` from EA inputs

#### CDiagnosticsManager

- File: `Core/Management/DiagnosticsManager.mqh`
- Responsibilities:
  - Core heartbeat emission (`[HEARTBEAT]`, `[HEARTBEAT-FUNNEL]`, `[CONVERSION-RATES]`, `[NO-SIGNAL-ALERT]`, `[RISK-BUDGET]`)
  - Consensus diagnostics (`[CONSENSUS-SNAPSHOT]`, `[STRATEGY-REJECTS]`, `[ROLE-CLUSTER]`, `[QUIET-REASONS]`, `[NO-SIGNAL-ALERT-CONSENSUS]`)
  - Windowed conversion-rate calculations
  - Indicator manager cleanup
  - NN health checks
  - Counter values passed via `UpdateCounters()` (MQL5-safe)

#### CUnprotectedPositionTracker

- File: `Core/Risk/UnprotectedPositionTracker.mqh`
- Responsibilities:
  - Track positions without stop-loss protection
  - 3-attempt SL escalation: Escalation-1 (3x ATR), Escalation-2 (broker min distance), Escalation-3 (unconditional close)
  - Fallback stop calculation for synthetic instruments

#### CSyntheticSpikeMonitor

- File: `Core/Processing/SyntheticSpikeMonitor.mqh`
- Responsibilities:
  - Synthetic tick velocity spike detection
  - Trading pause activation and release
  - Emergency drawdown stop
  - Tick safety loop processing

#### CTradeAttributionManager

- File: `Core/Trading/TradeAttributionManager.mqh`
- Responsibilities:
  - Prediction position mapping (prediction ID ↔ position ID)
  - AI prediction position mapping with signal/time tracking
  - AI pending request mapping
  - Pending close profit accumulation
  - NN diagnostics logging and self-test
  - Cluster code utilities and trade comment building

#### CSymbolScanScheduler

- File: `Core/Processing/SymbolScanScheduler.mqh`
- Responsibilities:
  - Symbol scan state management (new-bar, intrabar, pending)
  - Intrabar scoring and backoff logic
  - Symbol scheduler state alignment and rebuild
  - Evaluation budget tracking and symbol rotation

### 2.4 Pipeline domain

- Class: `CUnifiedSignalPipeline`
- Responsibilities:
  - cache structural/indicator context once per symbol/timeframe/bar for reuse across strategy votes
  - apply symbol-class-aware context posture so synthetic indices can bypass FX-style ADX trend assumptions while FX keeps full trend filtering
  - apply trend/volatility/liquidity/structure/confidence filters
  - apply deterministic regime + cost viability pre-gate via `CRegimeEngine`
  - recover ATR/Bollinger inputs from raw `CopyRates(...)` data when volatility/regime indicator buffers fault or warm slowly despite mature price history
  - produce reusable evidence snapshot data (`readinessScore`, `contextScore`, `costScore`, effective confidence floor, soft-threshold pass\`, readiness class, reuse/staleness flags)
  - retain the last rejecting filter name and reason for manager-level no-signal summaries
  - allow bounded soft-threshold promotion when near-threshold confidence is supported by strong readiness/context evidence
  - attenuate surviving signal confidence by context/readiness/staleness after threshold admission so weak evidence cannot carry fake certainty into quorum/validator stages
  - tolerate transient regime data faults by reusing a recent same-context valid snapshot when safe
  - allow trend partial-readiness to proceed when the underlying series is mature, enabling MA/ATR fallback logic to attempt recovery instead of hard-failing, which reduces persistent readiness vetoes on synthetic indices where `BarsCalculated` may lag behind `Bars()`
  - tolerate transient trend MA/ATR copy faults by reusing a bounded last-good trend snapshot instead of forcing full indicator-set churn
  - trigger bounded `CRegimeEngine` handle self-heal after repeated data faults
  - apply bounded weak-regime intrabar confidence threshold uplift (`min(base+cap, base*multiplier)`) using `CRegimeEngine` snapshot state as the authority
  - emit threshold-source telemetry (`[PIPELINE-THRESHOLD]`)
  - emit regime/cost veto telemetry (`[REGIME-STATE]`, `[COST-GATE]`, `[ENTRY-VETO]`)

### 2.5 Shared AI feature contract

- Class: `CAIFeatureVectorBuilder`
- The canonical runtime/training feature width is now `57`.
- Features `0..54` remain the original OHLCV/indicator-derived contract.
- Feature `55` adds tick-level Order Flow Imbalance (OFI) context.
- Feature `56` adds synthetic spike-recovery context (`time since last spike`, normalized) for synthetic-style symbols and defaults to `1.0` elsewhere.
- `TrainingDataExporter.mq5` can export the full 57-feature contract directly.
- `Python/data_pipeline.py` now prefers exported `feature_*` columns when present, preserving parity for tick-derived features that cannot be reconstructed faithfully from OHLCV alone.
  - normalize decision hygiene before final consensus acceptance without hot-path hedging neutralization
  - keep runtime diagnostics authoritative in the manager/runtime layer rather than spinning local `SignalDiagnostics` sinks per pipeline instance

### 2.6 AI adaptation domain

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

### 2.7 AI Modular Architecture (Batch 92 - GOD TIER Refactoring)

- **Modular Component Decomposition:**
  - `CNeuralCore.mqh`: Core neural operations (ReLU, Softmax with temperature, CrossEntropy loss, gradient computation, gradient clipping)
  - `CNeuralTrainingDataManager.mqh`: Training examples and barrier buffer management (SMTrainingExample, SMBarrierEntry)
  - `CNeuralCheckpointManager.mqh`: Atomic checkpoint save/load with validation
  - `IAIStrategy.mqh`: Unified interface for AI adapters extending `IStrategy`
- **Symbol Embedding System (UniversalTransformerService.mqh):**
  - `CSymbolEmbedding`: Learnable 32-dimensional symbol embeddings
  - Automatic symbol classification: Forex, Crypto, Synthetic based on name patterns
  - Hebbian-style embedding updates based on prediction performance
  - Integrated into `CSymbolAdaptationHead` for feature blending
- **Transformer FFN Residual Compensation:**
  - `m_residualScale = 1/sqrt(2*layers)` prevents activation explosion in deep networks
  - `numLayers` parameter propagated through `CFeedForwardNetwork` → `CTransformerBlock` → `CTransformerBrain`
- **Checkpoint Integrity Validation:**
  - 128-bit hash using two xorshift generators (hash1, hash2)
  - Computed over all weight matrices (W1-W4) before save
  - Validated on load - rejects corrupted checkpoints with `REJECTED_CHECKSUM_MISMATCH`
- **IAIStrategy Interface Implementation:**
  - `GetUncertainty()`: Model uncertainty (0 = certain, 1 = uncertain)
  - `IsModelHealthy()`: Model health status check
  - `IsTraining()`: Online training status
  - `GetTrainingSteps()`: Training step counter
  - `GetTemperature()`/`SetTemperature()`: Confidence calibration control
  - `GetRegimeState()`: Current market regime (-1 to 3)
  - `SaveCheckpoint()`: Force checkpoint save
  - `GetLastLoadStatus()`: Diagnostics string

### 2.8 Risk domain

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
  - enforce tiered correlation response: reduce position size at `correlationReduceThreshold` (0.4) and block at `correlationBlockThreshold` (0.7)
  - enforce daily P\&L loss limit circuit breaker via `dailyLossLimitPercent`, `CheckDailyLossLimit()`, and `m_dailyLossHaltActive` state
  - reset daily risk counters at configurable `m_tradingDayStartHour` instead of relying on MT5 server day boundary
  - apply rationalized safe defaults: 1% base risk, 5% max per trade, 5% daily, 15% portfolio
  - maintain a scan-time `CVirtualPositionBook` so cycle-best reservations count against projected daily and portfolio usage before the final execution winner is sent
  - **Batch 102 family-specific risk overrides:** `SSymbolRiskOverride` struct provides per-family risk and drawdown scaling. CrashBoom: 1.5% risk, 15% drawdown; Volatility: 1.0% risk, 10% drawdown; Step: 0.8% risk, 8% drawdown; Jump: 2.0% risk, 20% drawdown; DEX: 1.5% risk, 15% drawdown. Applied during pre-trade risk validation via `m_riskOverrides[]` array populated from `CDerivAssetProfiler` profiles.
- **Module 4 Hardening (Batch 85):**
  - Safe default risk limits (2% per trade, 6% daily, 10% portfolio) when config values are invalid
  - Currency-aware position sizing via `CPositionSizer::CalculateRiskPerLot()` conversion
  - 20% margin buffer (uses max 80% of free margin) for volatile period safety
  - Volatility adjustment uses minimum price threshold to prevent exaggerated ratios on low-priced symbols

### 2.9 Execution domain

- Class: `CTradeManager`
- Responsibilities:
  - convert approved intent into actual order send
  - run synchronous market execution by default
  - enforce execution-level safety checks
  - block stale or expensive market sends with hard pre-send spread and signal-price drift gates
  - configurable broker fill policy (IOC/FOK/RETURN)
  - bounded retries for transient broker retcodes
  - single bounded retry behavior for `LOCKED` / `FROZEN` retcodes
  - reprice market orders at submit time and rebuild protective SL/TP from the current market price
  - validate protective stop modifications against executable quote side with extra stop/freeze cushion instead of only the generic position price snapshot
  - perform one widened retry on `TRADE_RETCODE_INVALID_STOPS` before surfacing a protective-modification failure
  - emergency-aware protective modification flow
  - expose execution receipt status (`requestId`, retcode, requested/fill volume, request/fill price, slippage points, round-trip latency, retry count, avg fill price) for post-send handling
  - check market hours before position closure/modification (blocks only when `SYMBOL_TRADE_MODE_DISABLED`, allows `SYMBOL_TRADE_MODE_CLOSEONLY`)
- **Batch 87 Module 5 Execution Hardening:**
  - Dynamic slippage adjustment based on ATR volatility (configurable percentage, min/max bounds)
  - Order fill mode selection based on spread and volatility conditions (IOC vs FOK)
  - Execution quality metrics tracking (total/filled/partial/rejected orders, slippage, latency, spread costs)
  - Smart order routing that analyzes historical performance and adjusts parameters
  - Unified position state management via `CPositionStateManager`
  - Configurable synthetic spike detection confirmation window (default: 2 consecutive windows)
  - `GenerateExecutionQualityReport()` for detailed execution analytics

### 2.9.1 Live authority domain

- Owner: `MultiStrategyAutonomousEA.mq5`
- Responsibilities:
  - decide whether each risk-approved candidate is live-send eligible or candidate-level shadow-only
  - warm-start high-confidence AI/ONNX candidates at scaled risk while evidence is still building
  - track forward R outcomes for AI, ONNX, indicator, and Elliott contributor families
  - promote mature families when samples, expectancy, profit factor, and loss-streak gates pass
  - demote mature families to shadow when forward evidence degrades
  - emit `[LIVE-AUTHORITY]`, `[AUTHORITY-TRIAL]`, and `[AUTHORITY-RESULT]` telemetry for every authority decision lifecycle

### 2.10 Position lifecycle domain

- Owner: `MultiStrategyAutonomousEA.mq5` safety/timer lifecycle loop using `CTradeManager::ManageAllPositions(...)`
- The generic EA-level breakeven/trailing lifecycle is now operator-controlled through:
  - `InpEnablePositionLifecycleManager` (Enabled by default in Batch 82)
  - `InpLifecycleBreakevenBufferPoints`
  - `InpLifecycleTrailingDistancePoints`
  - `InpLifecycleTrailingStepPoints`
  - `InpLifecycleUseATRTrailing` (Dynamic ATR-based trailing)
  - `InpLifecycleATRMultiplier` (ATR breathing room)
- **Signal Reversal Exit (SRE)**: (Batch 82) High-speed exit monitoring:
  - `InpEnableSignalReversalExit`: Close on trend flip
  - `InpSignalReversalMinConfidence`: Noise filter for exit signals (0.58)
  - `InpSignalReversalProfitGuard`: Never close winners via SRE
  - `InpEnableStructuralInvalidation`: Bail if ICT/Structure trend flips
  - `InpSignalReversalMinLossR` / `InpSignalReversalMaxLossR`: Define the "Professional Exit Zone" (25% to 82% of SL)
  - `InpSignalReversalMinTimeSec`: Initial immunity window (45s)
- Default posture is enabled for scalping support.
- Responsibilities:
  - trailing/BE/partial-close lifecycle handling
  - scale breakeven, trailing, and partial-close triggers against original stop distance so lifecycle behavior stays proportional across FX and wide-stop synthetic symbols
  - treat configured pip values as broker-floor-aware minimums instead of absolute fixed thresholds
  - run from the lightweight safety loop once per second instead of inside the heavy symbol-scan path
  - managed by EA magic scope

### 2.11 Shared indicator domain

- Class: `CIndicatorManager`
- Responsibilities:
  - indicator handle cache and shared access
  - periodic unused release
  - explicit singleton teardown on deinit
  - remain the first ATR source for validator/execution sizing, with raw-rate fallback in the EA entry path when a direct ATR handle read misses

### 2.12 Chart visualization domain (Batch 58, Batch 86, Batch 90)

- Class: `CChartDrawingManager`
- Responsibilities:
  - centralized chart drawing coordination across all strategies
  - color scheme management with consistent professional palette
  - drawing configuration per feature type (structure, SR, OB, FVG, etc.)
  - **Chart Visualization Hardening (Batch 58):**
    - Elliott Wave strategy draws comprehensive Fib target levels for all waves (W1-W5)
    - Trend lines use thin dashed style (STYLE\_DOT, width 1) with muted colors
    - ICT drawing colors (OB, FVG, Liquidity, BOS, CHOCH) reduced in intensity using 0x909090 mask
    - SupportResistance trendlines aligned to thin dashed style for consistency
    - All chart elements use consistent thin dashed styling for improved clarity
  - **Module 7 - Chart Object Limit Enforcement (Batch 86):**
    - Added `m_maxObjects` member (default: 900) to prevent MT5's 1000 object limit violation
    - Implemented `CheckObjectLimitAndCleanup()` with LRU (oldest-first) deletion strategy
    - Integrated cleanup check before drawing operations in `PrepareSnapshotDraw()`
    - Added `SetMaxObjects()` method for configuration via `InpMaxVisualObjects` parameter
    - Class: `CDrawingCoordinator` now manages global object tracking with `CheckGlobalObjectLimitAndCleanup()`
    - StrategyUnifiedICT updated to check object limits before drawing order blocks and imbalances
  - **Visualization System Audit Fixes (Batch 90):**
    - Fixed hardcoded chart ID 0 in StrategyUnifiedICT that caused cross-chart contamination
    - Converted StrategyUnifiedICT to use CChartDrawingManager (DrawOrderBlock, DrawFVG)
    - Converted StrategyFibonacci to use CChartDrawingManager (DrawHorizontalLevel)
    - Added m\_chartID member to strategies initialized with ChartID()
    - Added global object counter with tiered alerts (800=warning, 900=critical, 950=emergency)
    - Implemented periodic logging of object counts with `[DRAWING-STATS]` telemetry
    - Reduced maxObjectAge from 500 to 150 bars for faster cleanup of stale objects
    - Added coordinate validation (ValidateTime, ValidatePrice, ValidateCoordinates)
    - Validates time > 0, time <= current + 1 day, price > 0, reasonable price range
    - Replaced bitwise OR color operations with explicit RGB values
    - Colors: ORDERBLOCK\_BULL (0x8787CC), ORDERBLOCK\_BEAR (0xCC6B6B), FVG\_BULL (0x6BAB8A), FVG\_BEAR (0xCC786B), LIQUIDITY (0xCCBC6B), STRUCTURE\_BOS (0xCC6BCC), STRUCTURE\_CHOCH (0xCC986B)
    - Wrapped debug logging in `if(m_config.enableDebugMode)`
    - Added SafeObjectsDeleteAll with verification of deletion counts and discrepancy logging
    - Added per-strategy object limit enforcement (maxObjectsPerStrategy)
    - Added dirty-flag optimization (m\_isDirty, SetDirty, IsDirty, ShouldRedraw)
    - Added LogStatistics() method for periodic drawing metrics logging
    - Integrated drawing statistics into VisualDashboard showing global/per-strategy counts
    - Added UpdateDrawingStats() and DrawLabelAt() to VisualDashboard

### 2.13 Regime Detection Robustness (Batch 86)

- Class: `CRegimeEngine`
- Enhancements:
  - Added `regimeConfidence` (0.0-1.0) to track detection confidence level
  - Added `regimeStabilityBars` to track consecutive bars in same regime state
  - Added `confirmedState` requiring 3+ bars stability before confirming regime change
  - Enhanced `[REGIME-STATE]` logging to include confidence and stability metrics
  - Prevents rapid regime flipping and reduces overfitting to noisy market data

### 2.14 Volatility Engine Validation (Batch 86)

- Class: `CVolatilityEngine`
- Enhancements:
  - Added `ValidateAtrCalculation()` test function for runtime ATR verification
  - Validates boundary conditions and array access safety
  - Emits `[ATR-VALIDATE]` telemetry with validation results

### 2.15 Python Bridge Integration (Batch 85, updated Batch 102)

- Class: `CPythonBridge` in `Core/Utils/PythonBridge.mqh`
- Files: `Python/zmq_server.py`, `Core/Utils/Enums.mqh`
- Responsibilities:
  - HTTP-based communication with Python server (FastAPI on `http://127.0.0.1:8000`)
  - Connection management (state tracking: `DISCONNECTED`, `CONNECTING`, `CONNECTED`, `ERROR`)
  - Request timeout handling (configurable via `InpPythonBridgeRequestTimeoutMs`)
  - Heartbeat monitoring with configurable interval (`InpPythonBridgeHeartbeatTimeoutSec`)
  - Reconnection logic with exponential backoff (configurable max attempts and backoff)
  - Message serialization validation (JSON structure validation)
  - Version compatibility check (requires server version `1.0.0+`)
  - Health monitoring dashboard with real-time telemetry
  - Local AI fallback mode when bridge is unavailable
  - **Family-aware prediction routing (Batch 102)**: `Predict()` accepts `family_id` and `symbol` params; `PredictFamily()` convenience method routes to family-specific ML models; `SPythonBridgeResponse` includes 8 new fields (family_id, family_name, catboost_buy/sell, xgboost_buy/sell, onnx_buy/sell)
- HTTP Endpoints in Python server (`Python/zmq_server.py`):
  - `POST /predict`: Get predictions from ensemble/dual-adapt/maml-ppo models; accepts `family_id` and `symbol` for family-specific routing (Batch 102)
  - `GET /health`: Check server health status
  - `GET /heartbeat`: Periodic health check (updates last heartbeat timestamp)
  - `GET /version`: Get server version information
  - `GET /families`: List loaded family-specific models and status (Batch 102)
  - `GET /family/{family_id}`: Status of specific family's models (Batch 102)
- Observability: Emits `[PYTHON-BRIDGE-DASHBOARD]` telemetry with connection state, version, and request stats

### 2.16 Shared Engine & Scalability (Batch 91)

- Class: `CSharedEngineManager` in `Core/Management/SharedEngineManager.mqh`
- Responsibilities:
  - Shared read-only TrendEngine, VolatilityEngine, and RegimeEngine across symbols to reduce memory and computation footprint
  - Symbol prioritization based on spread, volume 24h, and custom priority score
  - Dynamic priority recalculation with configurable window
  - Active symbol management with enable/disable controls
  - Symbol priority tracking with SSymbolPriority struct
  - Provides GetNextPrioritySymbol() for load balancing
- **Engine Sharing Modes**:
  - `SHARING_DISABLED`: Each symbol gets its own engines (legacy mode)
  - `SHARING_READONLY`: Engines are shared read-only (default)
  - `SHARING_FULL`: Full engine sharing (future use)
- **Symbol Priority Calculation**:
  - Spread-based score (lower spread = higher score)
  - Volume-based score (higher volume = higher score)
  - Configurable weight mix (spread: 40%, volume:40%, manual:20%)
  - Sorts symbols by priority each recalculation interval
- **Observability**: GetSharingStatus() returns sharing mode, active symbol count, and engine health

### 2.17 Scalping Engine domain

- Class: `CFastScalpEngine` in `Core/Scalp/FastScalpEngine.mqh`
- Signal Cache: `CScalpSignalCache` in `Core/Scalp/ScalpSignalCache.mqh`
- Responsibilities:
  - provide tick-level signal evaluation via cached indicator values, bypassing the full consensus pipeline for low-latency scalping entries
  - manage `SScalpIndicatorCache` struct (13 indicator values + tick-level bid/ask/spread + 7 handle references) per symbol, fixed-size array for 20 symbols
  - separate `UpdateOnNewBar()` (CopyBuffer path) from `UpdateTickValues()` (SymbolInfoDouble-only path) to minimize per-tick computation
  - all indicator handles sourced from `CIndicatorManager::Instance()` singleton
  - support async order execution via `OrderSendAsync()` with `SScalpPendingAsync` tracking and `OnDealConfirmed()` callback
  - track execution latency via `InpScalpMaxLatencyMs` and timeout pending async orders
  - integrate with `OnTradeTransaction()` for async order confirmation routing
- **Scalp Strategies:**
  - `CScalpMomentumStrategy` (`Core/Scalp/ScalpMomentumStrategy.mqh`): EMA trend + pullback + ATR expanding + spread filter + RSI 40-60; SL=0.75×ATR, TP=1.5×ATR (1:2 R:R); SCALP\_CLUSTER; confidence 0.60-0.90
  - `CScalpSpreadStrategy` (`Core/Scalp/ScalpSpreadStrategy.mqh`): Spread normalization + price near EMA + RSI filter; SL=0.06×ATR, TP=0.3×ATR; MEAN\_REVERSION\_CLUSTER; confidence 0.50-0.90
  - `CScalpVolatilityBreakout` (`Core/Scalp/ScalpVolatilityBreakout.mqh`): ATR squeeze + BB breakout + strong bar + RSI confirmation; SL=BB middle, TP=2×ATR; SCALP\_CLUSTER; confidence 0.55-0.90
- **Dual-Path Processing:**
  - `OnTick()` runs `ProcessScalpFastPath()` for tick-level cached-indicator signal evaluation alongside the existing safety loop
  - `OnTimer()` retains full consensus logic (pipeline → manager → validator → risk → execution)
  - Scalp fast path reads from `CScalpSignalCache` for zero-computation indicator access
  - Scalp entries still pass through `CUnifiedRiskManager` pre-trade gating (AGENTS.md invariant #1 preserved)

### 2.18 Risk Enhancement domain (Batch 97)

- Enhancements to `CUnifiedRiskManager`:
  - Tiered correlation response: `correlationReduceThreshold` (0.4) reduces position size, `correlationBlockThreshold` (0.7) blocks trade entirely
  - Daily P\&L loss limit: `dailyLossLimitPercent` circuit breaker halts trading when daily loss exceeds threshold, tracked via `CheckDailyLossLimit()` and `m_dailyLossHaltActive`
  - Broker trading day reset: `m_tradingDayStartHour` (configurable, default 0) ensures daily risk counters reset at the correct broker trading day boundary
  - Rationalized defaults: baseRiskPerTradePercent=1%, maxRiskPerTradePercent=5%, maxDailyRiskPercent=5%, maxPortfolioRiskPercent=15%
- Enhancements to `CPositionSizer`:
  - `POSITION_SIZE_KELLY` mode: half-Kelly fraction with 25% cap, `CalculateKellyFraction()` computes from recent trade history
  - Equity compounding: `CalculateCompoundingMultiplier()` with sqrt upside / linear downside scaling
  - Unified correlation: `SetCorrelationEngine()` delegates to `CCorrelationEngine` instead of internal Pearson
  - Conditional logging: `m_logLevel` + `SetLogLevel()` gates `LogSizingDecision()` output
  - **Batch 98 stateless refactor**: `CalculateSize()` is now truly stateless via `CalculateOptimalPositionSizeCore()` — the save/restore hack on `m_lots` has been removed; callers receive the computed size without side effects on internal state

### 2.19 Strategy Intelligence domain (Batch 97)

- Enhancements to `CStrategyBase`:
  - Regime-aware weighting: `GetRegimeConfidenceMultiplier()` scales confidence by regime alignment (TREND\_CLUSTER: 1.5x strong/0.3x range; MEAN\_REVERSION\_CLUSTER: 1.5x range/0.2x strong; STRUCTURE\_CLUSTER: 1.0x)
  - Volatility direction: `GetVolatilityDirection()` classifies ATR as EXPANDING/CONTRACTING/STABLE; `GetVolatilityDirectionMultiplier()` applies 1.2x/0.8x/1.0x
  - Multi-timeframe confluence: `IsAlignedWithHigherTF()` checks EMA50 on next higher timeframe
  - All intelligence factors applied in `GetSignal()` before returning to manager consensus
- Enhancements to `CEnterpriseStrategyManager`:
  - Per-cluster conviction tracking (trendClusterBuyConviction/SellConviction, meanRevClusterBuyConviction/SellConviction)
  - Cross-cluster conflict resolution: opposing cluster conviction subtracted, regime-weighted
  - `MathMax(0.0, ...)` guards on conviction subtraction to prevent negative values from floating-point precision
- Enhancements to `CTradeManager`:
  - Mandatory SL gate: `ExecuteMarketOrder()` rejects trades with `stopLossPips <= 0.0`
  - Conditional logging: `m_logLevel` + `SetLogLevel()` gates execution quality reports
- EA-level risk controls in `MultiStrategyAutonomousEA.mq5`:
  - Min R:R enforcement: 1:2 default, 1:5 for MEAN\_REVERSION\_CLUSTER
  - Portfolio profit target: `InpDailyProfitTargetPercent` with `InpProfitTrailFactor` trailing floor
  - Auto mode switching: `InpEnableAutoModeSwitch` with CONSERVATIVE/AGGRESSIVE/EMERGENCY modes based on drawdown and win streak

### 2.20 Equity Curve Manager domain (Batch 99)

- Class: `CEquityCurveManager` in `Core/Risk/EquityCurveManager.mqh`
- Responsibilities:
  - Track equity EMA (period=20) to establish adaptive equity baseline
  - Provide position size multiplier: 0.50 when equity < EMA (drawdown protection), 1.0 when equity >= EMA
  - Reduce position sizing during equity drawdowns without halting trading entirely
  - Integrate with `CPositionSizer` as a pre-sizing modifier

### 2.21 Bayesian Kelly Modifier domain (Batch 99)

- Class: `CBayesianKellyModifier` in `Core/Risk/PositionSizerModifiers.mqh`
- Responsibilities:
  - Beta-Binomial conjugate priors for win-rate estimation with uncertainty quantification
  - Quarter Kelly fraction (25% of full Kelly) for conservative position sizing
  - Prior: Beta(α=2, β=2) as weakly informative starting distribution
  - Posterior updates from realized trade outcomes (wins/losses)
  - Shrink toward prior when sample size is small to prevent overfitting to early results

### 2.22 CVaR Portfolio Risk domain (Batch 99)

- Extension to `CPortfolioRiskManager`
- Responsibilities:
  - CVaR (Conditional Value at Risk) calculation at 95% confidence level
  - 10% max CVaR risk limit across portfolio
  - 100-trade lookback window for historical tail-risk estimation
  - `IsCVaRLimitExceeded()` gate blocks new entries when portfolio tail risk exceeds threshold
  - Integrates with `CUnifiedRiskManager` as an additional pre-trade veto check

### 2.23 Async Trade Executor domain (Batch 99)

- Extension to `CTradeManager`
- Responsibilities:
  - `SendTradeAsync()`: non-blocking order execution via `OrderSendAsync()` for low-latency scalping entries
  - `ProcessTradeTransaction()`: `OnTradeTransaction()` callback handler for async order confirmation
  - `CheckAsyncTimeouts()`: timeout monitoring for pending async orders with configurable deadline
  - Async order state tracking with `SAsyncPendingOrder` struct (request ID, submit time, expected volume)
  - Fallback to synchronous execution when async path fails or times out

### 2.24 Commission-Aware Scalp Validation domain (Batch 99)

- Extension to `CFastScalpEngine`
- Method: `IsScalpCostViable()`
- Responsibilities:
  - Reject scalp entries when breakeven win-rate requirement > 70% (after commissions)
  - Reject scalp entries when commission cost > 25% of take-profit target
  - Calculate commission-adjusted breakeven win-rate: `WR_be = cost / (cost + TP_net)`
  - Integrate spread, swap, and per-lot commission into total cost estimation
  - Emit `[SCALP-COST-VETO]` when cost viability fails

### 2.25 Spike Hunter Engine domain (Batch 100)

- Class: `CSpikeHunterEngine` in `Core/Scalp/SpikeHunterEngine.mqh`
- Responsibilities:
  - 3-layer spike detection for synthetic CFD indices:
    - Layer 1: tick velocity ≥ 2.5× rolling average
    - Layer 2: direction accumulation ≥ 12 consecutive ticks in same direction
    - Layer 3: ATR compression ≤ 60% (price squeeze before spike)
  - Symbol-aware direction mapping: PainX→SELL, GainX→BUY, Volatility Index→directional, Jump Index→momentum continuation
  - Independent spike trades with separate magic numbers (magic offset 9000)
  - Push notification alerts throttled at 120s to prevent alert spam
  - Long-term entry cooldown of 60s to prevent re-entry into fading spikes
  - Emit `[SPIKE-HUNT-DETECTED]`, `[SPIKE-HUNT-TRADE]`, `[SPIKE-HUNT-SKIP]`, `[SPIKE-HUNT-ALERT]`, `[SPIKE-HUNT-ALERT-THROTTLED]`, `[SPIKE-COOLDOWN]`, `[SPIKE-HUNTER-STATS]`, `[SPIKE-HUNT-ENGINE]` log signatures
  - **Batch 102 family override integration:** `SSpikeHunterFamilyOverrides` struct provides per-family spike parameter overrides with 8 `GetEffective*()` methods. Profiler-driven configuration via `SetFamilyOverrides()` applies family-specific velocity multipliers (CrashBoom 2.8×, Jump 3.0×, Volatility 3.5×), ATR compression ratios, SL/TP multipliers, magic offsets, cooldowns, and minimum confluence thresholds.

### 2.26 Hurst Engine domain (Batch 101)

- Class: `CHurstEngine` in `Core/Engines/HurstEngine.mqh`
- Responsibilities:
  - Fractal persistence estimation via variance-time Hurst exponent
  - Regime-based strategy weight multipliers integrated into `CRegimeEngine`
  - Classify market persistence: H > 0.5 (trending), H ≈ 0.5 (random walk), H < 0.5 (mean-reverting)
  - Provide `GetHurstExponent()` and `GetPersistenceMultiplier()` for strategy weight scaling
  - Emit `[HURST-ENGINE]` telemetry with exponent value and regime classification

### 2.27 OU Process Engine domain (Batch 101)

- Class: `COrnsteinUhlenbeckEngine` in `Core/Engines/OrnsteinUhlenbeckEngine.mqh`
- Responsibilities:
  - Mean-reversion speed estimation via OLS regression on price series
  - OU-adjusted z-scores integrated into `StatisticalArbitrageStrategy`
  - Estimate mean-reversion half-life from OU parameters (θ, μ, σ)
  - Provide `GetOUZScore()`, `GetHalfLife()`, `GetMeanReversionSpeed()` for signal conditioning
  - Emit `[OU-ENGINE]` telemetry with parameter estimates and z-score values

### 2.28 OFI Proxy Engine domain (Batch 101)

- Class: `COrderFlowImbalanceEngine` in `Core/Engines/OrderFlowImbalanceEngine.mqh`
- Responsibilities:
  - Proxy order flow imbalance from tick classification (buyer/seller initiated) at 3 time scales
  - Welford online z-score normalization for streaming OFI values
  - Directional confirmation filter integrated into consensus pipeline
  - Provide `GetOFIZScore()`, `GetImbalanceDirection()`, `GetMultiScaleOFI()` for consensus augmentation
  - Emit `[OFI-ENGINE]` telemetry with imbalance values and z-scores per time scale

### 2.29 VPIN Filter domain (Batch 101)

- Class: `CVPINFilter` in `Core/Risk/VPINFilter.mqh`
- Responsibilities:
  - Volume-synchronized probability of informed trading (VPIN) from tick data
  - Toxicity-based position sizing: reduce size when VPIN exceeds threshold
  - Trade blocking when informed trading probability is critically high
  - Provide `GetVPIN()`, `GetToxicityLevel()`, `GetSizeMultiplier()` for risk integration
  - Emit `[VPIN-FILTER]` telemetry with VPIN value, toxicity classification, and sizing multiplier

### 2.30 Deriv Asset Profiler domain (Batch 102)

- Class: `CDerivAssetProfiler` in `Core/Processing/DerivAssetProfiler.mqh`
- Enum: `ENUM_DERIV_FAMILY` (19 values: DERIV_CRASH_BOOM through DERIV_UNKNOWN)
- Struct: `SDerivProfile` (20 fields per family)
- Responsibilities:
  - Auto-detect which of 18 Deriv synthetic index families a symbol belongs to via `DetectFamily(symbol)` using 13 family-specific symbol-name matchers from `Instruments.mqh`
  - Provide per-family trading parameters via `GetProfile(symbol)` returning `SDerivProfile`
  - Map families to magic number offsets via `GetMagicOffset(symbol)` (offsets 9000-9900)
  - Provide human-readable family names via `GetFamilyName(symbol)`
  - Print full profile diagnostics via `PrintProfile(symbol)`
  - Integrate with `CEnterpriseStrategyManager` via `SetDerivProfiler()` and `ApplyFamilyEngineWeights()`
  - Integrate with `CDiagnosticsManager` via `SetDerivProfiler()` for `[HEARTBEAT-FAMILY]` logging
- Data flow: symbol name → DetectFamily() → SDerivProfile → engine config / risk override / magic offset
- Per-family parameters include: `spikeThreshold`, `atrCompressionRatio`, `atrMultiplierSL`, `atrMultiplierTP`, `hurstThreshold`, `riskPerTrade`, `magicOffset`, `maxDrawdownPercent`, `enableSpikeHunter`, `enableGridRecovery`, `enableHurstRegime`, `enableOUFilter`, `gridFactorATR`, `maxGridLevels`, `gridProgressionFactor`, `spikeCooldownSec`, `spikeWindowBars`
- Emit `[PROFILER-DETECT]` telemetry with detected family and profile summary

### 2.31 Grid Recovery Engine domain (Batch 102)

- Class: `CGridRecoveryEngine` in `Core/Scalp/GridRecoveryEngine.mqh`
- Enum: `ENUM_GRID_PROGRESSION` (GRID_PROGRESSION_MARTINGALE, GRID_PROGRESSION_FIBONACCI)
- Struct: `SGridRecoveryConfig` (12 fields)
- Responsibilities:
  - Provide grid recovery for mean-reverting synthetic families (Volatility, Step, StableSpread, MultiStep, Exponential, SkewStep, VolSwitch, DriftSwitch, Trek, Tactical, Derived)
  - Activate only when Hurst exponent < `activationHurstThreshold` (0.45), confirming mean-reversion regime
  - Support two progression modes: Modified Martingale (lot × factor^level, factor=1.5) and Fibonacci (lot × fib(level))
  - Per-level SL = ATR × `slAtrMultiplier` (1.5), TP = `tpAtrMultiplier` × grid spacing (0.5)
  - Magic offset 8000 from base EA magic
  - Max 8 grid levels with configurable `maxDrawdownPercent` (15%) cap
  - Cooldown between grid entries via `cooldownMs` (30000ms default)
  - Configure per-family grid parameters via `SetFamilyConfig(symbol, gridFactorATR, maxGridLevels, progressionFactor)`
  - Update Hurst regime state via `SetHurstRegime(symbol, hurstValue)` — grid entries only placed when Hurst confirms mean-reversion
  - Emit `[GRID-RECOVERY-ENTRY]`, `[GRID-RECOVERY-LEVEL]`, `[GRID-RECOVERY-CLOSE]`, `[GRID-RECOVERY-DRAWDOWN]` telemetry

### 2.32 ATR Scalping Engine domain (Batch 102)

- Class: `CATRScalpingEngine` in `Core/Scalp/ATRScalpingEngine.mqh`
- Struct: `SATRScalpingConfig` (14 fields), `SATRScalpSymbolState`
- Responsibilities:
  - Provide ATR-based scalping for between-spike/between-jump trading on Jump, DEX, and Hybrid families
  - Implement spike window avoidance: learn spike intervals from `CSpikeHunterEngine` via `NotifySpikeDetected(symbol)` and `SetSpikeInterval(symbol, intervalSec)`; avoid trading `spikeWindowAvoidMinutes` (default 5) before expected spikes
  - Entry conditions: EMA fast/slow trend alignment + RSI filter (30-70) + spread < `spreadMaxATRRatio` × ATR (0.30)
  - SL = ATR × `slAtrMultiplier` (1.5), TP = ATR × `tpAtrMultiplier` (2.0)
  - Magic offset 7000 from base EA magic
  - Max `maxPositions` (3) concurrent scalp positions per symbol
  - Cooldown between scalp entries via `cooldownMs` (30000ms default)
  - Emit `[ATR-SCALP-ENTRY]`, `[ATR-SCALP-EXIT]`, `[ATR-SCALP-SPIKE-WINDOW]`, `[ATR-SCALP-COOLDOWN]` telemetry

### 2.33 Deriv Python ML Stack (Batch 102)

- **Feature Pipeline** (`Python/data_pipeline.py`):
  - `build_deriv_family_features(close, high, low, volume, family_id)` returns 26 feature columns: 8 signal features (tick velocity z-score, direction accumulation, ATR compression ratio, spike magnitude z-score, OU residual, step frequency, range bound score, bars-since-extreme) + 18 family one-hot encoding columns
  - `get_feature_count(family_id)`: returns 57 for universal (family_id=-1), 83 for Deriv families
  - `build_feature_matrix()` accepts `family_id` param; extends base 57 features to 83 when family_id >= 0
  - All downstream functions (`build_dataset_splits`, `build_pipeline`, `build_scaled_dataset_splits`, `build_symbol_sequences`) pass `family_id` through

- **Family-Specific Training Scripts**:
  - `Python/train_deriv_catboost.py` — `--family-id` arg; CrashBoom/DEX (iterations=1500, depth=8, l2_leaf_reg=5.0, class_weights=[1.0,0.5,1.0]), Hybrid (iterations=1200, depth=7)
  - `Python/train_deriv_xgboost.py` — `--family-id` arg; Step/MultiStep/SkewStep (gamma=1.0, reg_alpha=0.5, reg_lambda=2.0)
  - `Python/train_deriv_lgbm.py` — `--family-id` arg; Volatility (num_leaves=31, learning_rate=0.02)
  - `Python/train_deriv_stacker.py` — `--family-id` arg; optional `--catboost-pkl`/`--xgboost-pkl` for expanded meta features (6→12→15 columns); bundle includes `family_id` and `n_base_models`
  - All scripts auto-override seq_len=120 for Jump (3) and DEX (4) families

- **Server Routing** (`Python/zmq_server.py` v1.1.0):
  - `FAMILY_IDS` dict: 18 families mapped from symbol keyword → family_id
  - `_load_family_models(family_id)`: loads `{prefix}_patchtst.onnx`, `{prefix}_catboost.pkl`, `{prefix}_xgboost.pkl`, `{prefix}_lgbm.pkl`, `{prefix}_stacker.pkl`
  - `_detect_family_from_symbol(symbol)`: uppercase match against FAMILY_IDS keys (longest key first)
  - `_predict_family()`: dynamic seq_len (60/120) and feat_count (83) per family; ONNX + GBDT + stacking inference
  - `GET /families` and `GET /family/{family_id}` endpoints for model status
  - Backward compatible: requests without `family_id` fall through to universal model path

- **MQL5 Bridge Protocol**:
  - `DetectFamilyId(symbol)` in `Instruments.mqh`: priority-ordered cascade returning integer 0-17 or -1, matching `CDerivAssetProfiler::DetectFamily()` exactly
  - `CPythonBridge::Predict()` extended with `family_id` and `symbol` params (default -1/"")
  - `CPythonBridge::PredictFamily()` convenience method: `Predict(features, size, "ensemble", family_id, symbol)`
  - `SPythonBridgeResponse` extended with: `family_id` (int), `family_name` (string), `catboost_buy/sell`, `xgboost_buy/sell`, `onnx_buy/sell` (6 doubles)
  - `ParsePredictionResponse()` parses all new fields; backward compatible with old server responses
  - `GetFamilyPrediction(symbol, features, size)` global helper in `MultiStrategyAutonomousEA.mq5`

### 2.34 Multi-Asset Class Profiler domain (Batch 103)

- Class: `CMultiAssetProfiler` in `Core/Processing/MultiAssetProfiler.mqh`
- Enum: `ENUM_ASSET_CLASS` (10 values: ASSET_FOREX(0) through ASSET_UNIVERSAL(9))
- Struct: `SAssetProfile` (14 fields per asset class)
- Responsibilities:
  - Auto-detect which of 10 asset classes a symbol belongs to via `DetectAssetClass(symbol)` using priority-ordered detection (Deriv first, then Metals, Indices, Energies, Forex, Universal)
  - Provide per-asset-class trading parameters via `GetProfile(symbol)` returning `SAssetProfile`
  - Map asset classes to magic number offsets via `GetMagicNumber(symbol)` (Forex=+7000, Metals=+7100, Indices=+7200, Energies=+7300, Deriv=+9000-9400)
  - Provide human-readable class names via `GetAssetClassName(symbol)`
  - Provide feature set sizes via `GetFeatureSetSize(symbol)` (Forex=60, Metals=61, Indices=61, Energies=60, Deriv=70, Universal=57)
  - Provide Python model family identifiers via `GetPythonModelFamily(symbol)`
  - Print full profile diagnostics via `PrintProfile(symbol)`
  - Wrap `CDerivAssetProfiler` internally for fine-grained Deriv family detection; expose via `GetDerivProfiler()`
  - Map 18 Deriv families to 5 coarse asset classes via `DerivFamilyToAssetClass()`
  - Integrate with `CEnterpriseStrategyManager` via `SetMultiAssetProfiler()` and `ApplyAssetClassEngineWeights()`
  - Integrate with `CDiagnosticsManager` via `SetMultiAssetProfiler()` for `[HEARTBEAT-ASSET-CLASS]` logging
- Data flow: symbol name → DetectAssetClass() → SAssetProfile → engine config / risk / magic offset / feature count
- Per-asset-class parameters include: `atrMultiplierSL`, `atrMultiplierTP`, `hurstThreshold`, `riskPerTrade`, `magicOffset`, `maxDrawdownPercent`, `enableScalp`, `enableGrid`, `enableBreakout`, `featureSetSize`, `pythonModelFamily`
- Emit `[MULTI-ASSET-PROFILER]` telemetry with detected class and profile summary

### 2.35 Multi-Asset Python ML Stack (Batch 103)

- **Asset-Class Feature Pipeline** (`Python/data_pipeline.py`):
  - `build_forex_features(close, high, low, volume, spread)` returns 3 features: spread_z, corr_proxy, carry
  - `build_metals_features(close, high, low, volume)` returns 4 features: vol_of_vol, session_ny, trend_strength, vol_regime
  - `build_indices_features(close, high, low, volume, timestamps=None)` returns 4 features: overnight_gap, circadian, bb_width, vol_spike
  - `build_energies_features(close, high, low, volume)` returns 3 features: inventory_proxy, seasonality, contango
  - `get_asset_class_feature_count(asset_class)`: returns 60 (Forex), 61 (Metals/Indices), 60 (Energies)
  - `build_feature_matrix()` accepts `asset_class` param; extends base 57 features with asset-class-specific features when asset_class >= 0
  - All downstream functions (`build_dataset_splits`, `build_scaled_dataset_splits`) pass `asset_class` through

- **Asset-Class Training Scripts**:
  - `Python/train_forex_lgbm.py` — asset_class=0; LightGBM, lr=0.025, num_leaves=31, n_estimators=800
  - `Python/train_metals_catboost.py` — asset_class=1; CatBoost (depth=6, iterations=1000) + XGBoost (depth=5, estimators=800)
  - `Python/train_indices_xgboost.py` — asset_class=2; XGBoost, lr=0.025, depth=5, n_estimators=800
  - `Python/train_energies_xgboost.py` — asset_class=3; XGBoost, lr=0.03, depth=6, n_estimators=600

- **Server Routing** (`Python/zmq_server.py`):
  - `ASSET_CLASS_NAMES` dict: 10 entries mapping IDs 0-9 to string names
  - `ASSET_CLASS_FEATURE_COUNTS` dict: Forex=60, Metals=61, Indices=61, Energies=60
  - `_load_asset_class_models()`: loads ONNX + GBDT models from `models/{asset_class_name}/`
  - `_predict_asset_class()`: ONNX sequence + GBDT flat + stacking inference
  - `_process_request()` routes asset_class 0-3 to `_predict_asset_class()`, 4-8 to Deriv family routing, -1 to universal
  - Backward compatible: requests without `asset_class` fall through to existing family/universal paths

- **MQL5 Bridge Protocol**:
  - `DetectAssetClassId(symbol)` in `Instruments.mqh`: priority-ordered detection returning 0-9
  - `CPythonBridge::PredictMultiAsset()` convenience method: `Predict(features, size, "ensemble", -1, "", asset_class, asset_class_name)`
  - `SPythonBridgeResponse` extended with: `asset_class` (int, default -1), `asset_class_name` (string, default "")
  - `ParsePredictionResponse()` parses both new fields; backward compatible
  - `GetFamilyPrediction()` in `MultiStrategyAutonomousEA.mq5` now calls `PredictMultiAsset()` with `DetectAssetClassId()` + `GetAssetClassName()`

### 2.36 Asset-Class Engine Weight Adjustment (Batch 103)

- Method: `CEnterpriseStrategyManager::ApplyAssetClassEngineWeights(symbol)`
- Applies per-asset-class strategy weight multipliers after consensus:
  - **Forex**: Trend 1.3x, VolBreakout 1.2x, MeanRevert 0.7x
  - **Metals**: VolBreakout 1.5x, MeanRevert 0.5x
  - **Indices**: MeanRevert 1.5x, VolBreakout 0.5x, Trend 0.8x
  - **Energies**: VolBreakout 1.4x, Trend 1.2x
- Deriv symbols (asset_class 4-8) delegate to existing `ApplyFamilyEngineWeights()`
- Emit `[ASSET-CLASS-WEIGHT]` telemetry with class name and applied multipliers

### 2.37 Trend & S/R Strategy Enhancement (Batch 103 cont.)

- **CTrendSignalEnhancer** (`Strategies/TrendFiles/TrendSignalEnhancers.mqh`): EMA slope momentum detection (3-bar slope > 0.1 ATR-normalized) and trend freshness scoring (consistency<10 → +15%, >50 → -10%). Uses CMultiEMASystem reference and CIndicatorManager ATR handle.
- **CSRSignalScorer** (`Strategies/SupportResistanceFiles/SRSignalScorer.mqh`): Weighted soft confluence scoring (0-100) replacing hard AND logic for S/R bounce. Weights: PriceAtLevel=30, CandleRejection=25, EMAAligned=20, TrendlineConfluence=15, MultipleTouches=10. Signal threshold ≥60/100.
- **CStrategyTrend v2.1** (`Strategies/StrategyTrend.mqh`): Hurst regime filter (H<0.50 → reject), VPIN toxicity filter (VPIN>0.5 → reject), EMA momentum bonus (+10%), freshness multiplier, trailing stop integration (breakeven at 1R + CTrendTrailingStop hybrid trail), asset-class ADX thresholds via `CADXPositionSizing::InitForAssetClass()`. Engine injection via `SetHurstEngine()`/`SetVPINFilter()` setters (not owned).
- **CStrategySupportResistance** (`Strategies/StrategySupportResistance.mqh`): Hurst filter (H>0.55 in bounce → reject), VPIN filter (VPIN>0.5 → reject), drawing throttle (every 5 bars). Engine injection via `SetHurstEngine()`/`SetVPINFilter()` setters (not owned).
- **CSRBreakoutStrategy::FalseBreakoutDetected()**: 3-bar lookback for price breaking above resistance or below support then returning; ATR-based tolerance; counter-signal at 0.70 confidence.
- **CSupportResistanceDetector::CalculateStrength()**: Exponential decay `0.99^barsOld` (capped at 500 bars) replacing step-function age penalty.
- **CEnterpriseStrategyManager::GetStrategyByName()**: Returns `IStrategy*` by name (wraps `FindStrategyIndexByName()`). Used by EA wiring code for `dynamic_cast` to concrete strategy types.
- **EA Wiring** (`MultiStrategyAutonomousEA.mq5`): Batch 103 block after `ApplyAssetClassEngineWeights()` — iterates `g_mathEngineSymbols[]`, finds matching symbol index, calls `GetStrategyByName("Trend")`/`GetStrategyByName("Support/Resistance")`, `dynamic_cast` to concrete types, injects Hurst/VPIN engine pointers. Emits `[BATCH103]` log.

### 2.38 ICT/SMC Strategy Overhaul (Batch 103 cont.)

- **CFVGScalperStrategy** (`Strategies/FVGScalperStrategy.mqh`): FVG gap detection + OB freshness filter + rejection candle confirmation. Finds strongest FVG imbalance zone, checks price inside FVG, confirms with bullish/bearish wick rejection. Confidence: base 0.55 + structure alignment (+0.08) + fast CHOCH (+0.07) + CISD displacement (+0.05), capped 0.95. SL 0.5×ATR beyond FVG boundary, TP 1.5R. Tier 2, STRUCTURE_CLUSTER, weight 1.8. Owned components: `CImbalanceDetector`, `CMarketStructureAnalyzer(swings=3)`. Log: `[FVG-SCALPER]`.

- **CTurtleSoupStrategy** (`Strategies/TurtleSoupStrategy.mqh`): Liquidity sweep (Turtle Soup) detection via `CLiquidityDetector::DetectTurtleSoup()` + CHOCH/CISD confirmation + FVG confluence bonus. Confidence: base 0.50 + turtleSoup.confidence×0.15 + structure alignment (+0.10) + FVG confluence (+0.08) + fast CHOCH (+0.07), capped 0.95. SL beyond sweep extreme + 0.3×ATR, TP 2R. Tier 2, STRUCTURE_CLUSTER, weight 1.6. Owned components: `CLiquidityDetector(atrMultiplier=5.0)`, `CImbalanceDetector`, `CMarketStructureAnalyzer(swings=3)`. Log: `[TURTLE-SOUP]`.

- **CBreakerBlockStrategy** (`Strategies/BreakerBlockStrategy.mqh`): Failed OB → breaker conversion + price retest + opposing FVG + CISD displacement + structure alignment. Scans for unmitigated breaker OBs (OB_BREAKER_BULL/OB_BREAKER_BEAR), waits for price retest. Confidence: base 0.55 + freshness > 0.7 (+0.08) + FVG confluence (+0.10) + CISD displacement (+0.05) + structure alignment (+0.07), capped 0.95. SL 0.5×ATR beyond breaker boundary, TP 2R. Tier 2, STRUCTURE_CLUSTER, weight 1.7. Owned components: `CMarketStructureAnalyzer(swings=3)`, `CAdvancedOrderBlockDetector`, `CImbalanceDetector`. Log: `[BREAKER-BLOCK]`.

- **CNYOpenGapStrategy** (`Strategies/NYOpenGapStrategy.mqh`): NY session open gap (NDOG) fade during 13:30-14:00 UTC. Gap size > 0.5×ATR(14,D1). Fades gap direction (gap up = SELL, gap down = BUY). Confidence: base 0.50 + FVG confluence (+0.10) + large gap >1.0×ATR (+0.08) + near gap level (+0.07), capped 0.95. SL beyond gap extreme + 0.5×ATR, TP at previous close. Tier 3, STRUCTURE_CLUSTER, weight 1.3, session-limited. Synthetic symbol filter: skips Volatility/Boom/Crash/Jump/Step. Owned components: `CSessionGapDetector(PERIOD_D1)`, `CImbalanceDetector`. Log: `[NYGAP]`.

- **CAsianRangeBreakStrategy** (`Strategies/AsianRangeBreakStrategy.mqh`): Asian session range (00:00-06:00 UTC) breakout during London open (07:00-07:30 UTC). Requires tight range < 0.8×ATR. Trades breakout above/below Asian range. Confidence: base 0.50 + range compression < 0.5×ATR (+0.10) + structure alignment (+0.08) + fast CHOCH (+0.07), capped 0.95. SL at opposite range boundary, TP 2× range size. Tier 3, STRUCTURE_CLUSTER, weight 1.3, session-limited. Synthetic symbol filter: same as NY Open Gap. Owned components: `CICTKillZones(sessionCount=2, autoDetect=true)`, `CMarketStructureAnalyzer(swings=3)`. Log: `[ASIANRB]`.

- **CPartialCloseManager** (`Strategies/UnifiedICTFiles/PartialCloseManager.mqh`): 3-step exit management for ICT strategy positions. Step 1: 50% close at 1R profit (respects SYMBOL_VOLUME_MIN/STEP). Step 2: Breakeven move after 1R (SL → entry + 0.1% buffer, validates against SYMBOL_TRADE_STOPS_LEVEL). Step 3: ATR trailing after 2R (1.5×ATR(M5,14) from price, only moves favorably). Max 50 tracked positions with periodic compaction every 5 minutes. Internal state: `SPartialCloseState` per position. Log: `[PARTIAL-CLOSE]`.

- **CTimeframeConfluence** (`Strategies/UnifiedICTFiles/TimeframeConfluence.mqh`): Multi-TF alignment scorer. Creates 3 `CMarketStructureAnalyzer` instances for H1, M15, M5 (each swing lookback=3). Scoring: H1 alignment = 40pts, M15 = 30pts, M5 = 30pts (max 100). `IsMajorityAligned()` requires ≥2/3 timeframes aligned. Per-bar caching via `STFAlignmentCache` (invalidated on new bar via `iTime` comparison). Log: `[TF-CONF]`.

- **Component Upgrades**:
  - `AdvancedOrderBlocks.mqh`: `GetFreshness(int obIndex)` returns 0.0-1.0 freshness decay for order blocks. Used by BreakerBlockStrategy for freshness > 0.7 confidence bonus.
  - `MarketStructureAnalyzer.mqh`: 5 fast structure detection methods — `DetectFastCHOCH()` (3-swing CHOCH), `DetectWickBOS()` (wick-based BOS), `DetectCISDDisplacement()` (CISD displacement), `GetSwingHighLevel()`, `GetSwingLowLevel()`. Used by FVGScalper, TurtleSoup, BreakerBlock, AsianRangeBreak for rapid structure confirmation without full re-analysis.
  - `LiquidityDetector.mqh`: `SExternalLiquidityPool` struct + `DetectExternalSwingLiquidity()` for swing-based external liquidity detection. Used by TurtleSoupStrategy for liquidity sweep identification.

- **EnterpriseStrategyManager Extensions**: `m_maxStrategies` increased 20→25 to accommodate 5 new strategies. `GetStrategyByName(const string name)` returns `IStrategy*` by name (wraps `FindStrategyIndexByName()`). 5 new `RegisterStrategy()` calls with tier/cluster/weight assignments.

- **Synthetic Symbol Filtering**: Session-based strategies (NY Open Gap, Asian Range Break) skip synthetic symbols (Volatility, Boom/Crash, Jump, Step) since these CFDs have no real session gaps. Filtered via `IsVolatilitySyntheticSymbolName()`, `IsBoomCrashSyntheticSymbolName()`, `IsJumpSyntheticSymbolName()`, `IsStepSyntheticSymbolName()`.

- **Enum Additions** (`Core/Utils/Enums.mqh`): `STRATEGY_FVG_SCALPER=11`, `STRATEGY_TURTLE_SOUP=12`, `STRATEGY_BREAKER_BLOCK=13`, `STRATEGY_NY_OPEN_GAP=14`, `STRATEGY_ASIAN_RANGE_BREAK=15`.

- **EA Input Parameters** (`MultiStrategyAutonomousEA.mq5`): `InpEnableFVGScalper`, `InpEnableTurtleSoup`, `InpEnableBreakerBlock`, `InpEnableNYOpenGap`, `InpEnableAsianRangeBreak` (all bool, default true). Mapped in `BuildStrategyFlags()` at indices 12-16.

### 2.39 EA Enterprise Vision — Strategy v2.0 Enhancements (Batch 103 cont.)

- **CCandleConfluenceScorer** (`Strategies/CandlestickFiles/CandleConfluenceScorer.mqh`): 0-100 confluence scoring across all pattern detectors. Each detector contributes weighted points; total score ≥70 required for signal generation. Confidence = score/100.0. Detectors: CDojiDetector, CHammerDetector, CStarDetector, CHaramiDetector, CThreeSoldiersDetector, CPiercingDetector.
- **Candlestick v2.0** (`Strategies/StrategyCandlestick.mqh`): Integrated 7 new pattern detectors + CCandleConfluenceScorer. Confluence score ≥70 required for signal; confidence scaled by score/100.0.
- **Momentum v2.0** (`Strategies/SimpleMomentumStrategy.mqh`): MACD histogram confirmation (MACD line above signal = BUY confirmation), ADX strong trend filter (ADX > 25 required for trend entries), pullback entry mode (EMA pullback within 0.5×ATR), freshness confidence modifier (recent signal boost +10%), volume confidence modifier (above-average volume boost +8%).
- **Volatility Breakout v2.0** (`Strategies/VolatilityBreakoutStrategy.mqh`): TTM Squeeze detection (BB inside KC = squeeze active, breakout on BB exit), ADX rising filter (ADX slope > 0 required for breakout confirmation), breakout retest entry (price retests breakout level before entry), breakout failure reversal (failed breakout → counter-direction signal at 0.65 confidence).
- **Mean Reversion v2.0** (`Strategies/MeanReversionStrategy.mqh`): Stochastic extreme confirmation (Stoch < 20 for BUY, > 80 for SELL), Hurst regime lockout (H < 0.45 → reject "MR_HURST_NOT_MEAN_REVERTING"), BB width filter (BB width < 20th percentile required), no-divergence check (price vs indicator divergence blocks entry), dynamic TP (TP adjusts by BB width percentile). Hurst engine injection via `SetHurstEngine()` (pointer-based, not owned).
- **Statistical Arbitrage** (`Strategies/StatisticalArbitrageStrategy.mqh`): New strategy for pair trading via Python Bridge. OU half-life filter (half-life < 50 bars required), z-score detection (entry at |z| > 2.0, exit at |z| < 0.5). OU engine injection via `SetOUEngine()` (pointer-based, not owned). MEAN_REVERSION_CLUSTER, weight 1.5. Conditionally registered when Python Bridge is connected.

### 2.40 EA Enterprise Vision — Consensus Engine Improvements (Batch 103 cont.)

- **Regime Weight Wiring (B1)**: `CEnterpriseStrategyManager` now reads `CRegimeEngine` weight multipliers via `GetRegimeCategoryMultiplier()`. Regime category weights applied to strategy weights before consensus quorum evaluation.
- **VPIN Toxicity Integration (B2)**: VPIN toxicity gating in consensus flow:
  - `VPIN_EXTREME`: blocks all entries (consensus veto), logged as `[VPIN-BLOCK]`
  - `VPIN_HIGH`: reduces strategy weights by 50%
  - `VPIN_MEDIUM`: reduces strategy weights by 25%
- **0-100 Consensus Scoring (B3)**: New graduated consensus scoring replacing binary quorum:
  - `rawConsensusScore = directionalQuality × supportRatio × 100`
  - Threshold = 60/100 for consensus pass
  - Scores 60-70: marginal consensus (reduced position sizing)
  - Scores 70-85: standard consensus
  - Scores 85+: strong consensus (full position sizing)
- **OFI Regime Integration (B4)**: OFI confirms/contradicts regime category weights:
  - OFI aligned with regime → 1.2× boost on regime category multiplier
  - OFI contradicts regime → 0.7× penalty on regime category multiplier
  - Applied after regime weight wiring, before consensus scoring

### 2.41 EA Enterprise Vision — Engine Wiring (Batch 103 cont.)

- **EnterpriseStrategyManager VPIN/OFI Wiring**: VPIN filter and OFI engine wired from EA per-symbol loop in `MultiStrategyAutonomousEA.mq5`. Each symbol's `CEnterpriseStrategyManager` receives VPIN and OFI engine pointers via `SetVPINFilter()` and `SetOFIEngine()` setters (not owned).
- **MeanReversion Hurst Engine Wiring**: Hurst engine pointer wired from EA per-symbol loop via `GetStrategyByName("Mean Reversion")` + `dynamic_cast<CStrategyMeanReversion*>`, then `SetHurstEngine()`. Migrated from index-based to pointer-based injection.
- **StatisticalArbitrage OU Engine Wiring**: OU engine pointer wired from EA per-symbol loop via `GetStrategyByName("Statistical Arbitrage")` + `dynamic_cast<CStatisticalArbitrageStrategy*>`, then `SetOUEngine()`. Registration gated by Python Bridge connection check.
- **A5 Strategy Registration**: StatisticalArbitrage registered in `BuildStrategyFlags()` with Python Bridge availability check; shadow mode when bridge disconnected, live mode when connected.

## 3. Managed Strategies

### 3.1 Core retained set

- **Momentum** (SimpleMomentumStrategy.mqh)
  - v2.0: MACD histogram confirmation, ADX strong trend filter (ADX > 25), pullback entry mode (EMA pullback within 0.5×ATR), freshness confidence modifier (+10%), volume confidence modifier (+8%)
  - Optional scalp-continuation mode is configured by `InpEnableMomentumScalping` and `InpMomentumScalpCooldownSeconds`; it shortens cooldown only for momentum itself and still sends every entry through manager consensus, unified risk, and trade-manager execution.
  - Optional scalp timeframe registration is configured by `InpMomentumScalpTimeframe`; when this is lower than the attached chart timeframe, Momentum evaluates on that lower timeframe instead of waiting on the chart bar cadence.
  - Risk management integrated with \[CONSENSUS-DIAG] logging (Batch 93)
- **Trend** (StrategyTrend.mqh)
  - Simplified from 300 → 259 lines (-13.7%), removed timeframe auto-stepping and dead trailing stop code
  - Risk management integrated with \[CONSENSUS-DIAG] logging (Batch 93)
- **Support/Resistance** (StrategySupportResistance.mqh)
  - Integrated CFibConfluence module (Fibonacci merge), replaced bubble sort with ArraySort()
  - Risk management integrated with \[CONSENSUS-DIAG] logging (Batch 93)
- **Unified ICT** (StrategyUnifiedICT.mqh)
  - Simplified from 4 to 2 entry types (2,194 → 2,012 lines, -8.3%)
  - Risk management integrated with \[CONSENSUS-DIAG] logging (Batch 93)
- **Candlestick** (StrategyCandlestick.mqh)
  - v2.0: 7 new pattern detectors (Doji, Hammer, Star, Harami, ThreeSoldiers, Piercing) + CCandleConfluenceScorer (0-100 scoring, threshold ≥70); confidence scaled by confluence score
  - Optional intrabar timeframe registration is configured by `InpCandlestickIntrabarTimeframe`; when this is lower than the attached chart timeframe and candlestick intrabar eligibility is enabled, Candlestick evaluates its own lower-timeframe bar stream.
  - Risk management integrated with \[CONSENSUS-DIAG] logging (Batch 93)
- **Power of Three** (CPowerOfThreeStrategy.mqh)
  - ICT AMD (Accumulation-Manipulation-Distribution) phase detection
  - Risk management integrated with \[CONSENSUS-DIAG] logging (Batch 93)
- **Unicorn Model** (CUnicornModelStrategy.mqh)
  - ICT breaker/OB + FVG overlap pattern detection
  - Risk management integrated with \[CONSENSUS-DIAG] logging (Batch 93)
- **Volatility Breakout** (VolatilityBreakoutStrategy.mqh)
  - v2.0: TTM Squeeze detection (BB inside KC = squeeze active, breakout on BB exit), ADX rising filter (ADX slope > 0 required), breakout retest entry (price retests breakout level before entry), breakout failure reversal (failed breakout → counter-direction signal at 0.65 confidence)
  - Risk management integrated with \[CONSENSUS-DIAG] logging (Batch 93)
- **Mean Reversion** (MeanReversionStrategy.mqh)
  - v2.0: Stochastic extreme confirmation (Stoch < 20 for BUY, > 80 for SELL), Hurst regime lockout (H < 0.45 → reject "MR_HURST_NOT_MEAN_REVERTING"), BB width filter (BB width < 20th percentile required), no-divergence check (price vs indicator divergence blocks entry), dynamic TP (TP adjusts by BB width percentile)
  - Hurst engine injection via SetHurstEngine() (pointer-based, not owned)
  - Risk management integrated with \[CONSENSUS-DIAG] logging (Batch 93)
- **Statistical Arbitrage** (StatisticalArbitrageStrategy.mqh)
  - Pair trading via Python Bridge, OU half-life filter (half-life < 50 bars required), z-score detection (entry at |z| > 2.0, exit at |z| < 0.5)
  - OU engine injection via SetOUEngine() (pointer-based, not owned)
  - Conditionally registered when Python Bridge is connected
  - MEAN_REVERSION_CLUSTER, weight 1.5

**Removed Strategies:**

- ~~Elliott Wave~~ - Deleted (\~1,600 lines removed, unreliable)
- ~~Fibonacci~~ - Merged into SupportResistance as CFibConfluence module
- ~~RSI, Mean Reversion, Swing, Volatility, MACD, Bollinger, Ichimoku, Harmonic, legacy SMC wrapper~~ - Previously retired

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

### 3.3 Curated runtime profile

Curated mode is now a baseline recommendation while live-authority defaults decide whether a candidate can actually send.

- **Default authority roster** (Batch 78): AI/ONNX and retained indicator strategies can contribute; ordinary live trades require quorum, while high-confidence AI/ONNX packets can use the explicit authority gate.
- Earlier Batch 41 work reduced denominator bloat by recommending a lean roster; Batch 78 keeps that lesson but avoids globally muting profitable AI/ONNX paths.
- Explicit per-strategy enable flags still control registration, but Elliott-only execution is candidate-level shadow unless evidence/confluence earns authority.
- Disabled strategies are not registered into managers/orchestrator by default, so dormant code stays available for testing without inflating runtime weight pools, scan time, or duplicate logs.

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
  - denominator weight = adjusted live weight reduced by contribution class (`raw-none`, `pipeline-filtered`, `infrastructure/warmup`, or other neutral)
  - ready live weight = `denominator weight x pipeline readinessScore`
  - **dynamic weight decay** (Batch 82): strategies filtering ≥ 15 consecutive cycles have weight decayed by 5% rate per additional filter, reducing denominator bloat; weight recovers when strategy votes
  - per-direction conviction = `sum(ready live weight x conviction_i)` for agreeing live voters
  - conviction is confidence shaped by pipeline `contextScore`, `readinessScore`, and `costScore`
  - directional quality = `direction conviction / direction weight`
  - support ratio = `direction weight / total ready live weight`
  - **adaptive quorum thresholds** (Batch 82): direction passes full quorum if:
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
- **Detailed veto diagnostics** (Batch 82): failures emit specific veto codes with numeric evidence:
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

### 5.4 Domain authority registry (Batch 99)

- AI calibration authority: `IAIStrategy::GetCalibratedWeight()` — runtime degenerate model detection; models with direction ratio > 0.80 in last 20 predictions have effective weight reduced by 50%
- Equity curve authority: `CEquityCurveManager` — position size modulation based on equity vs EMA; multiplier 0.50 when equity < EMA, 1.0 when above
- CVaR authority: `CPortfolioRiskManager::IsCVaRLimitExceeded()` — portfolio risk capped by historical tail risk; 95% confidence, 10% max risk, 100-trade lookback
- Spike hunting authority: `CSpikeHunterEngine` — 3-layer spike detection and independent spike trade execution for synthetic CFD indices; symbol-aware direction mapping, magic offset 9000, push alerts throttled 120s, entry cooldown 60s

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
- Python bridge health: `[PYTHON-BRIDGE-DASHBOARD]`
- Scalp cost viability: `[SCALP-COST-VETO]`
- Spike hunting: `[SPIKE-HUNT-DETECTED]`, `[SPIKE-HUNT-TRADE]`, `[SPIKE-HUNT-SKIP]`, `[SPIKE-HUNT-ALERT]`, `[SPIKE-HUNT-ALERT-THROTTLED]`, `[SPIKE-COOLDOWN]`, `[SPIKE-HUNTER-STATS]`, `[SPIKE-HUNT-ENGINE]`

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

