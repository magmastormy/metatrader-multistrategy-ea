# SYSTEM_STRUCTURE.md

## Document Metadata

- Last Updated: 2026-10-26
- Last Architecture Sync: 2026-10-26
- Scope: Full structural description of runtime system
- Source of Truth: Current repository implementation
- Current Batch: 262

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
- Batch 93 implements systematic strategy refactoring for full AGENTS.md architectural compliance: UnifiedICT simplified from 4 to 2 entry types (2,194 → 2,012 lines), StrategyTrend cleaned up (300 → 259 lines), ElliottWave removed (~1,600 lines), Fibonacci merged into SupportResistance as CFibConfluence module, all 7 active strategies now validate through CUnifiedRiskManager with [CONSENSUS-DIAG] logging.
- Batch 96 restores profitable execution mechanics: scan cycles retain multiple `CUnifiedRiskManager`-reserved candidates instead of replacing them with one winner, `InpMaxTradeSendsPerCycle` controls ranked multi-send throughput, same-symbol capacity counts EA-owned positions, synthetic symbol detection covers SFX/FX Vol/SwitchX/PainX/GainX/FlipX, and `CTradeManager` stop lifecycle management is magic-filtered and volatility-aware.
min R:R enforcement (2.0 default, 1.5 for the mean-reversion cluster; the "1:5" in this sentence was the 1.5 literal misread, and no consensus trade ever reached that branch because `SConsensusDecisionContext.dominantCluster` had no writer until Batch 219)
- Batch 98 completes the EA Overhaul Blueprint monolith decomposition (R6/R7) and risk framework items: `CPositionSizer::CalculateSize()` is now truly stateless via `CalculateOptimalPositionSizeCore()` (no save/restore hack); position lifecycle management extracted into `CPositionLifecycleManager`; heartbeat/diagnostics extracted into `CDiagnosticsManager` with consensus diagnostics; unprotected position tracking extracted into `CUnprotectedPositionTracker` with 3-attempt SL escalation; synthetic spike monitoring extracted into `CSyntheticSpikeMonitor`; trade attribution and NN prediction mapping extracted into `CTradeAttributionManager`; symbol scan scheduling extracted into `CSymbolScanScheduler`; anti-Martingale dynamic lot scaling added; CICTPositionSizer risk denominator fixed to use `MathMin(balance, equity)`; risk percent scale consistency verified with conversion helpers; cluster rebalancing updated for Conservative tier; Statistical Arbitrage conditionally registered when Python Bridge is connected; heartbeat interval made configurable. Total ~1,180 lines extracted from the main EA monolith into 7 focused manager classes.
- Batch 99 implements log-evidence-driven fixes and research solutions: S/R lot validation ordering fix unblocks 79 SELL signals on PainX 400; ONNX CPU fallback enables signals when CUDA unavailable; AI degenerate model detection downweights 100% BUY/SELL models by 50%; trend bias consensus check raises quorum for counter-trend signals; scalp margin-aware lot cap prevents oversized orders; hybrid gate relaxation lowers AI standalone threshold after indicator drought; P\&L-adjusted risk budget enables re-entries on profitable positions; Bayesian Kelly modifier with Beta-Binomial priors; equity curve manager reduces size when equity < EMA; CVaR portfolio risk integration; commission-aware scalp validation; async trade executor with OrderSendAsync + OnTradeTransaction confirmation.
- Batch 100 adds CSpikeHunterEngine for synthetic CFD indices: 3-layer spike detection (tick velocity ≥ 2.5× average, direction accumulation ≥ 12 ticks, ATR compression ≤ 60%), symbol-aware direction mapping (PainX→SELL, GainX→BUY, etc.), independent spike trades with separate magic numbers (offset 9000), push notification alerts throttled at 120s, and long-term entry cooldown of 60s to prevent re-entry into fading spikes.
- Batch 101 adds four advanced mathematical engines for no-API-required quantitative analysis: CHurstEngine (fractal persistence via variance-time Hurst exponent, regime-based strategy weight multipliers integrated into CRegimeEngine), CVPINFilter (volume-synchronized probability of informed trading from tick data, toxicity-based position sizing and trade blocking), COrnsteinUhlenbeckEngine (mean-reversion speed estimation via OLS, OU-adjusted z-scores integrated into StatisticalArbitrageStrategy), COrderFlowImbalanceEngine (proxy order flow imbalance from tick classification at 3 time scales, Welford z-score normalization, directional confirmation filter in consensus pipeline). Python ML ensemble expanded with CatBoost and XGBoost training scripts, and train\_stacker.py updated to accept both as optional meta-feature sources (6→12 columns, backwards compatible).
- Batch 102 adds the Deriv Asset Profiler system for 18-family synthetic index auto-detection and per-family engine optimization: CDerivAssetProfiler (auto-detects family from symbol name, provides SDerivProfile with 20 fields per family), CGridRecoveryEngine (Hurst-activated grid recovery for mean-reverting families with Modified Martingale and Fibonacci progression), CATRScalpingEngine (ATR-based between-spike scalping with spike window avoidance for Jump/DEX/Hybrid families), SSpikeHunterFamilyOverrides (8 GetEffective*() methods for per-family spike parameter tuning), SSymbolRiskOverride (per-family risk/drawdown scaling in CUnifiedRiskManager). Magic number offsets 7000-9900 allocated per engine and family. New input parameters: InpDerivProfilerEnabled, InpGridRecoveryEnabled, InpATRScalpingEnabled.
- Batch 103 (Enterprise Vision) upgrades the multi-strategy EA to an enterprise consensus engine with 11 strategies: Candlestick v2.0 (7 new pattern detectors + CCandleConfluenceScorer with 0-100 scoring, threshold ≥70), Momentum v2.0 (MACD confirmation, ADX strong trend filter, pullback entry, freshness/volume confidence modifiers), Volatility Breakout v2.0 (TTM Squeeze detection, ADX rising filter, breakout retest, breakout failure reversal), Mean Reversion v2.0 (Stochastic extreme confirmation, Hurst regime lockout H<0.45, BB width filter, no-divergence check, dynamic TP), Statistical Arbitrage (new strategy: pair trading via Python Bridge, OU half-life filter, z-score detection). Consensus engine improvements: regime weight wiring via GetRegimeCategoryMultiplier(), VPIN toxicity integration (EXTREME→block, HIGH→50%, MEDIUM→25%), 0-100 consensus scoring (rawConsensusScore = directionalQuality × supportRatio × 100, threshold=60), OFI regime integration (1.2× boost aligned, 0.7× penalty contradicted). Engine wiring: VPIN/OFI at EnterpriseStrategyManager level, Hurst at MeanReversion level (pointer-based migration), OU at StatisticalArbitrage level.
- Batch 106 (Synthetic Strategy Research + Compounding Tiers + Legacy Cleanup) implements aggressive micro-account growth infrastructure for Deriv synthetics: CCompoundingTierManager (auto-tier switching at $25/$50/$100/$500 milestones, 5 tiers from MICRO_AGGRESSIVE to PROFESSIONAL with per-tier risk/drawdown/position limits), CFamilyStrategyWeightMatrix (per-Deriv-family cluster weight multipliers: Crash/Boom→STRUCTURE 1.5x, Volatility→MEAN_REVERSION 1.5x, HFV→SCALP 2.0x, etc.), CSessionWeightManager (Asian/London/NY/Weekend session-aware sizing and threshold adjustments, weekend 1.2x sizing boost), CSkewStepAnalyzer (200-step rolling buffer phase detection for Skew Step indices, calm/post-spike/counter-due sizing multipliers), per-family position limits in CUnifiedRiskManager (Crash/Boom max 2, Volatility max 3, HFV max 2), ADX lot modifier wired into position sizer chain, PythonBridge correlation methods fixed (JSON parsing for GetPairCorrelation/FindBestCorrelatedPair), Batch 103 strategy weights made user-configurable (InpWeightFVGScalper/TurtleSoup/BreakerBlock/NYOpenGap/AsianRangeBreak), legacy dead code cleanup (removed CMarketAnalysis global, CStrategyWrapper include, 34+ dead REMOVED comments, Fibonacci/Elliott Wave commented-out registration blocks).
- Batch 108 (Comprehensive Bug Audit + Strategy Fine-Tuning + Dashboard Improvements) fixes 8 critical bugs (memory leak in OnDeinit for VWAP/VP/CVD engines, null pointer dereference on Deriv Profiler, uninitialized pointers, undefined variable in CompoundingTierManager, double momentum scaling in PositionSizer, inverted MathMax in ApplyTierOverrides, double-free risk in UniversalTransformerService, VWAP double-counting), 12 high-severity bugs (29 dead globals removed, unchecked PositionGetTicket, uncapped oversized lots, unbounded static arrays, dead ternary in SupportResistance, signal overwrite in MeanReversion, dangerous SL/TP fallback in PowerOfThree, zero SL/TP in StatisticalArbitrage, wrong retest direction in VolatilityBreakout, dead code removal), 7 dashboard fixes (malformed JSON, AI/risk/performance data wired, debounced ChartRedraw), and 4 strategy fine-tunings (MACD confirmation in Trend, volume filter in MeanReversion, configurable thresholds in Momentum, configurable scoring in FVGScalper).
- Batch 121 (Academic Rigor & Production Hardening) implements comprehensive bug fixes, memory leak elimination, magic number overflow protection, and API error handling improvements to meet academic paper standards and production reliability requirements:
  - **PERIOD_CURRENT Misuse**: Fixed 4 locations where `PERIOD_CURRENT` (value 0) was passed directly to MQL5 `iATR()` and indicator APIs. Now resolved to actual chart timeframe with `PERIOD_M15` fallback.
  - **Magic Number Overflow Protection**: Changed magic number fields from `uint` to `long` (64-bit) in `CTradeManager`. Added `MAX_VALID_MAGIC_NUMBER = 2147483548` safety constant. Added input validation with clamping in `GenerateMagicNumber()` and `IsEAOwnedMagic()`.
  - **ATR Access Consolidation**: `CPositionLifecycleManager::GetATR()` now uses `CIndicatorManager` singleton for handle management. Removed redundant `IndicatorRelease()` calls. Added proper error logging with `GetLastError()`.
  - **Memory Leak Elimination**: All strategy registration paths (`RegisterManagerAIAdapterByName`, `RegisterIndicatorStrategyByName`, `InitializeNeuralNetForSymbol`) now properly delete allocated objects on registration failure. Covers 17 strategy types and 3 AI adapter types.
  - **MQL5 API Error Handling**: `GetMinimumStopPoints()` made public for EA access. `Initialize()` parameter changed from `uint` to `long`. Added error propagation for `CopyBuffer`, `OrderSend`, `SymbolInfoInteger`, `SymbolInfoDouble`.
  - **Resource Cleanup Verification**: All dynamic allocations in `OnDeinit()` verified with matching deletions. `CIndicatorManager::DestroyInstance()` called. ONNX handles released via `COnnxBrain::Deinit()`.
- **Batch 123 (Dead Code Removal — Shadow Mode & Dormancy/Blacklist Encapsulation)** — Complete removal of legacy shadow mode infrastructure and encapsulation of dormancy/blacklist tracking into registry classes. The system now operates in live-only mode with clean execution paths:
  - **Shadow Mode Removal** (~400+ lines across 8 files):
    - Removed `InpShadowMode` and `InpShadowModeEnabled` input parameters from main EA
    - Removed `m_shadowMode` member and `SetShadowMode()` from `CDiagnosticsManager`
    - Removed `shadowTrades` parameter from `CDiagnosticsManager::UpdateCounters()` and heartbeat logs
    - Removed `m_shadowMode` and `m_shadowModeEnabled` from `CTradeExecutor`
    - Removed `shadowOnly` field from `StrategyEntry` struct in `CEnterpriseStrategyManager`
    - Removed `SetStrategyShadowModeByName()` and `IsRegisteredStrategyShadowOnly()` methods
    - Removed `shadowOnly` parameter from `RegisterStrategy()` and `SetStrategyGovernanceByName()`
    - Removed shadow references from JSON serialization
    - Removed `SHADOW_RESEARCH` role references from consensus diagnostics
    - Removed `g_hbShadowTrades` global variable and all increments
    - Removed shadow trade execution path and `[SHADOW-TRADE]` logging from main EA
  - **Dormancy/Blacklist Encapsulation** (~60 lines from main EA):
    - Removed `g_dormantConsecutiveCount[]`, `g_dormantCooldownUntil[]`, `g_dormantCooldownSymbols[]` global arrays from main EA
    - Removed `DORMANT_COOLDOWN_THRESHOLD` and `DORMANT_COOLDOWN_MINUTES` constants from main EA
    - Removed `g_scalpBlacklistFailCount[]`, `g_scalpBlacklisted[]`, `g_scalpBlacklistDay[]`, `g_scalpBlacklistSymbols[]` global arrays from main EA
    - Removed `SCALP_BLACKLIST_THRESHOLD` constant from main EA
    - Dormancy tracking now fully encapsulated in `CSymbolScanScheduler` / `CScanSchedulerRegistry`
    - Scalp blacklist tracking now fully encapsulated in `CScanSchedulerRegistry` / `CSymbolStateTracker`
    - **(Both lines above are superseded by Batch 215.)** Neither class ever held state: `CSymbolScanScheduler`
      was never instantiated and `CSymbolStateTracker`'s seven record/test methods had no caller, so the globals
      this batch moved out of the main EA simply landed in fields nothing wrote to. `CSignalGenerator`'s own
      dormancy counters - made configurable in Batch 212 and printed as `[DORMANT-COOLDOWN]` - are the live
      implementation, and `CScanSchedulerRegistry` keeps only the per-symbol bar stamp.
    - `CSignalGenerator` implements dormancy warning logic for signal evaluation
  - **Batch 150 ownership corrections (2026-08-23)**: `CSignalGenerator` owns per-symbol new-bar gating (`m_lastEvalBar[]`) and stores results by manager index; `CScanSchedulerRegistry::CheckNewBar` is the single bar-rollover authority consumed by `EAOrchestrator::ProcessNewBars`; `CTradeRetcodeClassifier` no longer retries UNKNOWN-state retcodes (TIMEOUT/CONNECTION); `CPosLifecycleExit` owns the once-per-ticket partial-close marker.
  - **Documentation Updates**: Updated `README.md`, `changelogs.md`, `SYSTEM_STRUCTURE.md`, `RUNTIME_DECISION_GRAPH.md`, `SYSTEM_AUDIT_TRACE.md`
  - **Runtime Invariants Preserved**: All 5 AGENTS.md §3 invariants verified

- **Batch 126 (Layer 2 Initialization & Lifecycle Audit — Fixes & Improvements)** — Implemented fixes for medium/low severity issues from AUDIT_Layer2_Initialization.md:
  - **L2-023: Documented Two-Phase Initialization for Enterprise Manager** — Added comprehensive comment block to `CEnterpriseStrategyManager::Initialize()` documenting Phase 1 (required: Pipeline, TimeframeConsistency) and Phase 2 (optional: FourStateRegimeDetector, FamilyWeightMatrix, VPINFilter, OFIEngine) with graceful degradation
  - **L2-028: Gated Verbose PrintFormat Behind Log Level** — Added `LOG_IF` macro in `Core/Utils/Enums.mqh` using existing `g_logLevel`/`InpLogLevel` (0-4). Applied to verbose diagnostics in hot paths:
    - `DiagnosticsManager` — heartbeat, consensus, conversion rates, risk budget, asset class/family
    - `EnterpriseStrategyManager` — consensus diagnostics (CONSENSUS-DIAG, ROOT, STRATEGY, ROLE, CLUSTER, SCORE, RELAX, TREND-BIAS, TREND-FLIP, SOLO, QUORUM, SPARSE, NEARMISS, VETO, ACTIVE), VPIN, family weights, AI uncertainty, regime weights
    - `UnifiedSignalPipeline` — cache, threshold, cost gate, entry veto, health check
  - **L2-029: Documented Pipeline Dependencies** — Added input parameter comment for `InpUseSignalPipeline` documenting required engines (Trend, Structure, Liquidity, Volatility, Regime) and INIT_FAILED behavior
  - **Files Changed**: `Core/Utils/Enums.mqh`, `Core/Management/DiagnosticsManager.mqh`, `Core/Management/EnterpriseStrategyManager.mqh`, `Core/Pipeline/UnifiedSignalPipeline.mqh`, `MultiStrategyAutonomousEA.mq5`
  - **Runtime Invariants Preserved**: All 5 AGENTS.md §3 invariants verified

- **Batch 129 (Layer 4 Signal Pipeline & Filtering — Complete Audit Fixes)** — Resolved all 15 issues from `layer_4.md` audit across signal pipeline, engines, and timeframe consistency:
  - **L4-001 CRITICAL: Filter Chain Abstraction with Early Exit** — Added configurable filter order via `SignalFilterSettings.filterOrder[]`, implemented early-exit in `ProcessSignal()` after each filter failure, skips disabled filters entirely, added `BuildFilterOrderMap()` for runtime filter execution ordering
  - **L4-002 HIGH: Stale Intrabar Cache** — `RefreshStructuralContext()` now includes intrabar context in cache key with `m_intrabarContext` tracking for cache invalidation
  - **L4-003 HIGH: Quality Score Weight Normalization** — Renormalized `CalculateQualityScore()` weights to sum to 1.0, removed ad-hoc +0.05 filter bonus, integrated as proper weighted component
  - **L4-004 HIGH: Confidence Threshold Variable Naming** — Fixed `multiplierThreshold` → `effectiveMinConfidence` naming inconsistency, consolidated threshold calculation logic
  - **L4-005 MEDIUM: Engine Health Check Uses Readiness State** — `CheckEngineHealth()` now verifies `GetReadinessSnapshot().state == HEALTHY || REUSED_SNAPSHOT`, added `m_lastEngineDataTimestamp` per engine for staleness detection
  - **L4-006 MEDIUM: Consolidated ApplySpreadFilter Overloads** — Unified both overloads to use `ratio = spread / atr` comparison, extracted common logic to `CheckSpreadRatio()` helper, renamed parameters consistently to `maxSpreadToAtrRatio`
  - **L4-007 MEDIUM: Budget Exhaustion Auto-Clear** — Added `ResetBudgetExhausted()` called at session rollover (00:00 server time), tracks `m_budgetExhaustedSessionDate` for daily auto-reset, added `CheckBudgetExhaustedAutoClear()` in `ProcessSignal()`
  - **L4-008 MEDIUM: ADX Handle Race Condition** (TrendEngine) — Added `m_adxReinitPending` flag for handle reinitialization, `IndicatorsReadyForRead()` waits for `BarsCalculated() >= minBars*2` before clearing flag, resets `m_consecutiveAdxFailures` only after successful data read
  - **L4-009 MEDIUM: Swing Detection Real-Time Flaw** (StructureEngine) — Added `IsPotentialSwingHigh/Low()` checking only left side (historical) for real-time, `IsConfirmedSwingHigh/Low()` checking both sides for historical confirmation, `ConfirmPotentialSwings()` to validate pending potential swings on next bar, member variables: `m_potentialSwingHighPrice`, `m_potentialSwingHighIndex`, `m_potentialSwingHighValid`, `m_potentialSwingLowPrice`, `m_potentialSwingLowIndex`, `m_potentialSwingLowValid`, updated `DetectSwingPoints()` to track potential swings and confirm them when right-side data available
  - **L4-010 LOW: Weighted Resolution Ignores NONE Signals** (TimeframeConsistency) — `ResolveWeighted()` now tracks `totalActiveWeight` (non-NONE signals only), normalizes confidence by active weight, returns NONE with 0 confidence if all signals are NONE
  - **L4-011 LOW: Snapshot Reuse Ignores Regime Transitions** (RegimeEngine) — `TryReuseRecentSnapshot()` now validates regime state consistency by calling `BuildFallbackIndicators()` and `EstimateRegimeStateFromFallback()` to compare current vs snapshot regime, invalidates snapshot if regime differs
  - **L4-012 LOW: SignalFilterSettings Grouped** — **COMPLETED** Grouped 18 flat settings into nested structs: `TrendFilterSettings` (`enabled`, `minStrength`), `VolatilityFilterSettings` (`enabled`, `maxVolatility`), `LiquidityFilterSettings` (`enabled`), `StructureFilterSettings` (`enabled`), `SessionFilterSettings` (`enableTimeFilter`, `enableSessionFilter`, `allowSyntheticOffHours`, `tradeLondonSession`, `tradeNewYorkSession`, `tradeTokyoSession`), `RegimeCostGateSettings` (`enabled`, `maxSpreadToAtrRatio`, `spreadShockCooldownSeconds`, `maxEntryRangeZScore`), `ConfidenceSettings` (`minConfidence`, `intrabarConfidenceCap`), `FilterOrderSettings` (`filterOrder[7]`, `filterOrderCount`). Added `Validate()` method with range checks on all nested structs, added `ApplyPreset(ENUM_FILTER_PRESET)` for CONSERVATIVE/BALANCED/AGGRESSIVE configurations. Updated all call sites in `ProcessSignal()`, `ComputeReadinessScore()`, `ApplyRegimeAndCostGate()`, `ApplySpreadFilter()`, `ApplyFilterPreset()`, `ApplyTimeFilter()`, `ApplySessionFilter()`, `ApplyVolatilityFilter()`.
  - **L4-013 LOW: Regime Gate Log Throttling** — Added `m_regimeGateLogCounter` and `m_regimeGateLogInterval` (default 10), detailed regime snapshot logging now throttled to 1 in N signals
  - **L4-014 LOW: Duplicate ATR Calculation** (VolatilityEngine) — Extracted `CalculateAtrFromRates()` static helper used by both `BuildFallbackMetrics()` and `ValidateAtrCalculation()`, eliminated duplicate Wilder's ATR implementation
  - **L4-015 LOW: Magic Numbers in Readiness Score** — **COMPLETED** Added `SReadinessComponentWeights` struct with configurable weights: `trendWeight`, `structureWeight`, `liquidityWeight`, `volatilityWeight`, `regimeWeight`. Added `Validate()` method. Updated `ComputeReadinessScore()` to use weighted component scores from `m_filters.readinessWeights` instead of hardcoded values. Added `stalenessPenaltyMax` and `stalenessPenaltyDivisor` to `SReadinessScoreConfig` for configurable staleness penalty. Updated `RefreshEvidenceFromEngines()` and `ApplyRegimeAndCostGate()` to use config values.
  - **Files Modified**: `Core/Pipeline/UnifiedSignalPipeline.mqh`, `Core/Engines/TrendEngine.mqh`, `Core/Engines/StructureEngine.mqh`, `Core/Engines/VolatilityEngine.mqh`, `Core/Signals/TimeframeConsistency.mqh`, `Core/Engines/RegimeEngine.mqh`
  - **Runtime Invariants Preserved**: All 5 AGENTS.md §3 invariants verified

- Batch 130 (2026-07-25): Layer 6 Strategy Implementation Logic — All 4 remaining issues resolved (L6-007, L6-008, L6-013, L6-016). Intrabar PROBE mode wired through config chain; participation score update logic implemented in ConsensusEngine; GetQuickProbeSignal() removed from IStrategy and 5 strategies; AIPerformanceFeedback integrated with EnterpriseStrategyManager weight adaptation for AI strategies.
- Batch 140 (2026-08-05): Phase 4-5 Strategy Duplication Consolidation + God Object Decomposition — `CStrategyBase` expanded with shared helpers (`LogRejectEvent`/`RejectSignal`, `RefreshForNewBar`/`OnRefreshComponents`, `ValidateWithRiskManager`, `LogConsensusDiag`) eliminating ~260 lines of duplicated boilerplate across strategy files. `EAOrchestrator.mqh` decomposed: `SOrchestratorConfig` extracted to `OrchestratorConfig.mqh` (710 lines) and `InitializeStrategyConfigs` extracted to `StrategyConfigBuilder.mqh` (249 lines), reducing EAOrchestrator 5,529 → 4,571 lines (17.3% smaller). Pure structural refactoring, no runtime behavior change.

- Batch 158 (2026-08-28): Signal-suppression audit sweep — unaudited strategy files + ATR handle caching — Final sweep of the signal-suppression audit campaign (Batches 155–157 covered the strategy emission paths and detector/analyzer layer). Fixed: TrendEntryTypes/TrendSignalEnhancers GetATR() forming-bar (shift 0) → closed-bar (shift 1); FourStateRegimeDetector KAMA/trend reads forming bar close → shift 1; StatisticalArbitrageStrategy static array oldest-first read → dynamic array with ArraySetAsSeries; BreakerBlock/FVGScalper/TurtleSoup FX-calibrated SYMBOL_POINT pip conversions → ATR-denominated scale-free (1 ATR = 1 unit); StrategySupportResistance ApplyFibConfluence per-call iATR create/release → cached shared handle via CIndicatorManager. All 7 EAs compile 0 errors / 0 warnings.

---

## 2. Top-Level Runtime Topology

### 2.1 Entrypoint and orchestration

- File: `Core/Orchestration/EAOrchestrator.mqh` (primary coordination class)
- **Config/data modules extracted from EAOrchestrator (Batch 140):**
  - `Core/Orchestration/OrchestratorConfig.mqh` — `SOrchestratorConfig` struct + helper structs (pure data definitions, zero invariant risk)
  - `Core/Orchestration/StrategyConfigBuilder.mqh` — `CStrategyConfigBuilder::Initialize()` static method (pure EA-input → config mapping, no runtime behavior)
- Thin EA entry point: `MultiStrategyAutonomousEA.mq5` delegates to `CEAOrchestrator` via builder pattern
- **Testing EA entry point:** `MultiStrategyTestingEA.mq5` — standalone testing EA with Complete Test Profile System (45 predefined profiles). See [README.md#standalone-testing-ea](README.md#standalone-testing-ea) for details.
- Responsibilities (EAOrchestrator):
  - initialize all owned subsystems (risk, trade, position, signal, AI, registry aggregator) in deterministic order
  - initialize `CRegistryAggregator` as unified registry access point for mathematical, neural net, drawing, scan and strategy registries (the institutional registry it also owned was deleted in Batch 262 - nothing constructed the engines it held) (the symbol-state registry it also used to own was deleted in Batch 215 - nothing wrote to it). It now exposes only getters with callers: Batch 215 also removed the nine per-symbol `Get*(symbol)` conveniences, `GetScanScheduler`, `GetTotalRegisteredCount` and six `Is*Ready()` probes, all of which had zero call sites on this class - the same-named getters callers use belong to `CUnifiedSignalPipeline`, `COrchestratorMathEngineHub` and the manager's infra struct.
  - initialize per-symbol `CEnterpriseStrategyManager` instances with injected strategy registry
  - wire mathematical engines (Hurst, OU, OFI, VPIN, Kalman, CPD, Four-State, VolTarget, LiqSweep, RangeComp) to registries through `CreateEnginesForSymbol`, the hub's one creation path - `InitializeMathematicalEngines`/`InitializeInstitutionalEngines` were a second, uncalled copy of it, and the ExitOpt/VWAP/VP/CVD fleets they also built are gone (Batch 262)
  - initialize AI subsystems (NextGenStrategyBrain, AIEngine, NeuralNetwork adapters via StrategyFactory) with clear ownership (adapters own NNs)
  - maintain cadence loops (new-bar/intrabar) via `OnTimer()`/`OnTick()` delegation
  - delegate position lifecycle management to `CPositionLifecycleManager` (SRE, structural invalidation, breakeven/trailing, safe mode)
  - delegate heartbeat and diagnostics to `CDiagnosticsManager` (core heartbeat, consensus diagnostics, conversion rates, risk budget snapshot)
  - delegate unprotected position tracking and SL remediation to `CUnprotectedPositionTracker` (3-attempt escalation)
  - delegate synthetic tick spike monitoring and trading pause to `CSyntheticSpikeMonitor`
  - delegate trade attribution and NN prediction mapping to `CTradeAttributionManager`
  - hold per-symbol bar-rollover state in `CScanSchedulerRegistry`; it does no intrabar scoring - the scheduler that would have is deleted in Batch 215
  - budget heavy signal evaluations across both new-bar and intrabar paths via config
  - budget intrabar scans by symbol yield instead of blindly scanning the whole intrabar universe every cycle
  - apply per-symbol intrabar backoff after repeated low-yield or readiness-faulted scans
  - self-heal cadence scheduler state at runtime if any scheduler array drifts away from the active symbol set
  - dispatch per-symbol evaluations
  - rank approved candidates across symbols before execution
  - reserve every staged candidate as a virtual position inside unified risk before it can enter the ranked execution list
  - execute up to configured max trade sends per scan cycle through `CTradeManager`, preserving runtime execution ownership
  - detect synthetic-index tick-velocity spikes and trigger flatten-plus-pause protection
  - own the non-AI confidence policy inputs for pipeline and manager admission stages
  - resolve strategy registration timeframes per strategy so scalp/intrabar modules can use lower timeframes than the attached chart when explicitly configured
  - adapt per-symbol runtime profiles (strategy roster, intrabar policy, and context posture) by instrument class when symbol-class profiles are enabled
  - emit explicit mode-mask diagnostics when indicator profile entries remain configured but the effective runtime mode filters them out of the active registry
  - emit runtime fingerprints with both requested and effective EA mode so `AI_ONLY` logs cannot be mistaken for failed indicator/hybrid participation
  - emit explicit AI topology diagnostics so MT5-native voters, Python-trained ONNX runtime voting, Python sidecar expectations, and external LLM reasoning are not conflated
  - coordinate validator/risk/execution path
  - enforce live-authority source defaults: AI/ONNX enabled, global live execution allowed, EA-owned same-symbol stacking, and no one-voter sparse intrabar admission
  - handle runtime telemetry and deinitialization

- Thin EA (`MultiStrategyAutonomousEA.mq5`) responsibilities:
  - parse input parameters into `SOrchestratorConfig`
  - construct `CEAOrchestrator` via `CEAOrchestratorBuilder`
  - call `orchestrator.Initialize(config)`
  - forward `OnTick()`, `OnTimer()`, `OnDeinit()` to orchestrator
  - no business logic in EA file

- Testing EA (`MultiStrategyTestingEA.mq5`) responsibilities:
  - Same orchestration flow as main EA but with Complete Test Profile System integration
  - Applies test profile flags to `SOrchestratorConfig` via `ApplyCompleteTestProfile()` before initialization
  - Provides 45 predefined test profiles (single components, suites, aggregate modes, full system)
  - Logs activation matrix (`[ACTIVATION-MATRIX]`) and per-symbol effective component report (`[PER-SYMBOL-REPORT]`) on init
  - Use for isolated component testing, backtesting optimization, and regression validation
  - No business logic changes — only input flag override via test profiles

### 2.2 Per-symbol strategy domain

- Class: `CEnterpriseStrategyManager`
- One manager per managed symbol.
- Responsibilities:
  - hold registered strategies (core + AI adapters)
  - consume only registry-enabled descriptors so disabled strategies and disabled AI adapters do not enter live manager pools or denominator math
  - execute strategy voting and confidence aggregation
  - own the single authoritative `GetSignal(...)` call for each strategy evaluation so strategies do not pre-consume per-bar state ahead of consensus
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

#### 2.2.1 Strategy slot-scheme ownership (Batch 147 — semantic-only)

`strategyFlags[]` has exactly **one** producer and **one** reader, and they agree by construction:

| Role | Owner | Slot space |
|---|---|---|
| Written | `COrchestratorStrategyFlagBuilder::BuildStrategyFlags`, looping the catalog's indicator rows (Batch 209) | semantic `SI_*` (`ENUM_STRATEGY_INDEX`) |
| Read | `CEnterpriseStrategyManager::AutoRegisterStrategies` via `CatalogEnableSlot(i)` | semantic `SI_*` |
| Read (registry) | `CEAOrchestrator::BuildStrategyRegistry` via `CatalogEnableSlot(i)` | semantic `SI_*` (Batch 193) |
| Read (roster report) | `COrchestratorSymbolClassifier::BuildEnabledStrategyList` / `CountEffectiveIndicatorStrategiesForSymbol`, both row loops (Batch 209) | semantic `SI_*`, named by row |
| Intrabar policy | `StrategyConfigBuilder` slot table → `CIntrabarPolicy` | each strategy's own `siPolicyIndex` |
| Strategy timeframe | `StrategyConfigBuilder` slot table → `CIntrabarPolicy` (bound in Batch 249) | same `siPolicyIndex`; `PERIOD_CURRENT` = inherit the chart |
| Voting weight | catalog row, overridden once at init by `InpWeight*` | `StrategyConfigWeight(siIndex, rowDefault)` (Batch 193) |

Ownership after Batch 147 (legacy scheme deleted):

- **`CEnterpriseStrategyManager` owns registration.** `AutoRegisterStrategies` calls `CatalogLogIndexAudit()` (no arg), `CatalogEnableSlot(i)`, `CatalogPolicySlot(i)` — all unconditional semantic. There is no scheme flag to set; `SetUseSemanticStrategyIndices` was removed.
- **`StrategyCatalog` resolves slots, never decides.** `CatalogEnableSlot(i)`, `CatalogPolicySlot(i)` and `CatalogCuratedEnable(i)` are the only slot/roster resolvers; `CatalogFlagEnabled` was removed. `CatalogLogIndexAudit()` prints `slot_scheme=SEMANTIC (legacy literals removed in Batch 147)` and is report-only.
- **No flag slot may be cast to a strategy type (Batch 209).** `ENUM_STRATEGY_INDEX` and `ENUM_STRATEGY_TYPE` number the same strategies differently (`SI_MEAN_REVERSION = 7`, `STRATEGY_MEAN_REVERSION = 8`) and the type enum has gaps at 3, 4, 6, 16 and 17. `[CURATION]` used to print `EnumToString((ENUM_STRATEGY_TYPE)i)` over flag indices, which named the wrong row for everything after Momentum. Roster text and roster counts now come from row loops, and the `STRATEGY_*_AI 17..20` literals those loops relied on are deleted.
- **`SStrategyDefinition` is the whole registration contract (Batch 193).** The row gained `registryType`, the `ENUM_STRATEGY_TYPE` the registry filter matches on, and `BuildStrategyRegistry` now loops the catalog's indicator rows instead of repeating fourteen hand-written `enabled = flags[SI_X]; RegisterDefinition("X", ...)` pairs — which is how Statistical Arbitrage stayed unregistered while its input, flag slot, class and row all existed. A row with `registryType < 0` prints `[STRATEGY-REGISTRY] <name> has no registryType in its catalog row - it cannot pass the registry filter`. AI rows keep their own definitions: their enabled flag comes from adapter availability, not a strategy input.
- **One weight per strategy (Batch 193).** `ApplyCatalogWeightOverrides()` runs after the registry aggregator initializes and before `InitializeEnterpriseManagers()`, writing each row's resolved `InpWeight*` into `SStrategyDefinition.weight`. That row value is what `RegisterStrategy` -> `SetWeight` -> the roster -> `GetStrategyWeight()` gives consensus, and what the registry descriptor reports; before it, the operator's fourteen weight inputs reached only the descriptor, which no indicator path reads. `CatalogApplyConfigWeight` logs every row it moves.
- **`CIntrabarPolicy` holds the hard-coded LIVE fallback pair** (Mean Reversion / Volatility Breakout) at semantic slots `7/8`. The always-LIVE pair no longer depends on a scheme — it is fixed at the semantic slots, which is exactly what the producer writes.
- **`MAX_STRATEGY_CONFIGS` = 23.** Slots 21 (FVG Scalper) and 22 (Statistical Arbitrage) own their own rows. `CIntrabarPolicy::m_policyConfig` is sized 32, so the count is safely absorbed.

There is no legacy default — the semantic scheme is the only scheme.

#### 2.2.2 Adding or removing a strategy (Batch 193: the catalog is the whole contract)

A strategy now needs five facts and no other call site:

1. `Strategies/<Name>.mqh` defining a class derived from `IStrategy`.
2. `#include "../../Strategies/<Name>.mqh"` in `StrategyCatalog.mqh`, tagged `// [CAT:<Name>]`.
3. `CATALOG_SIMPLE_CREATOR(CatCreate_<Name>, C<Name>)` on the next anchored line.
4. One `CatalogAdd("<Name>", CAT_KIND_INDICATOR, ..., siIndex, siPolicyIndex, ..., weight, ..., registryType)` row, carrying the row's own `SI_*` flag slot, its own `StrategyConfigBuilder` policy slot, the `STRATEGY_*` enum the registry matches on, and its default weight.
5. `InpEnable<Name>` / `InpWeight<Name>` in each root `.mq5`, written into `config.enable<Name>` / `config.weight<Name>`, the new slot appended to `ENUM_STRATEGY_INDEX`, and one `case` for it in `COrchestratorStrategyFlagBuilder::ConfigEnableForSlot`. `BuildStrategyFlags` itself needs no new line: it walks the rows.

Registration, the registry definition, the enable gate, the intrabar policy, the curated roster, the contributor class and the consensus weight are all read from that row. Remove a strategy by deleting the lines carrying its `[CAT:]` anchor and its input. One enumeration is still not catalog-driven and is worth naming: `BuildStrategyFlagsForSymbol` suppresses named strategies per symbol class. A row whose `registryType` is missing prints `[STRATEGY-REGISTRY] <name> has no registryType in its catalog row` rather than trading nothing in silence, a row whose `siIndex` is `-1` is registered for every symbol (what the AI adapter rows rely on), and a row whose slot has no `ConfigEnableForSlot` case prints `[CATALOG] <name> | enable slot N has no operator input - it stays off unless curated` instead of being quietly unreachable.

Curated membership is row data since Batch 209 (`SStrategyDefinition::curatedEnable`): the twelve indicator rows the operator cannot switch off under `InpUseCuratedStrategySet` are every indicator row except Candlestick and Statistical Arbitrage, which is the set the deleted `if(!config.enableX)` ladder named by hand.

Contributor classification is derived from the same row since Batch 208: `CatalogContributorIsIndicator`, `CatalogContributorIsAI` and `CatalogContributorIsAIKind` answer from `kind` / `aiKind`, and `CandidateBuilder`'s `hasIndicatorContributor`, `indicatorContributorCount`, `hasAIContributor`, `hasONNXContributor` and `hasNeuralNetContributor` - which the live-authority ladder and the neural-net label gate read - are built from them. Before that, those five were substring tests against a hand-copied list of the row names, and the copy had drifted (six indicator rows and Python Bridge AI matched nothing). The precondition is the one this section already states: the registered name is `g_strategyCatalog[i].name`, at both `RegisterStrategy` and `RegisterCatalogAIAdapter`.

#### 2.2.3 Strategy construction has one authority per kind (Batch 194, closed by Batch 210)

| Path | Builds | Applies operator inputs | Live? |
|---|---|---|---|
| `CStrategyFactory::Create(name)` | the five AI adapters, keyed by `SStrategyDefinition.factoryName` | no — the adapter is configured by `PrepareCatalogAIAdapter`, and the ONNX buffer / Python bridge are globals | yes, AI rows only |
| `g_strategyCatalogCreators[i]()` | every indicator strategy | bare `new ClassName()`, then `CEnterpriseStrategyManager::ConfigureBeforeInit(strategy, name)` | yes |

Until Batch 210 the factory also registered **twelve** indicator creators (the section said fourteen; the
registry held 12 indicator + 5 AI = 17 entries) whose bodies called `SetScalpingMode` /
`SetRequireTrendAlignment` / `SetSyntheticMode` / `SetHurstEngine` / `SetPythonBridge` / `SetOUEngine`. No
indicator row carries a `factoryName`, `Create` is reached only from the `CAT_KIND_AI` loop, and none of the five
surviving creators ever read a field of `SStrategyConfig` — so those calls could not run, and the struct's
seventeen fields, the eight assignments the call site made into them, and four uncalled public helpers
(`IsRegistered`, `GetRegisteredNames`, `GetCount`, `BuildConfigFromEA`) are deleted. `Create` now takes only a
name.

`ConfigureBeforeInit(strategy, name)` remains the live authority for the values a strategy's `Init` reads for
itself, fed by `SetStrategyConstructionInputs` from the orchestrator's own pass that already sets intrabar
policies. Engines are injected after registration, in `InitializeEnterpriseManagers`: Hurst (+VPIN) into Trend,
Hurst (+VPIN) into Support/Resistance, Hurst into Mean Reversion, OU (+Python bridge) into Statistical
Arbitrage, and VPIN/OFI onto the manager - reported per symbol by `[WIRE-STATUS]` since Batch 211.
(`WireAndValidateDependencies` wires the orchestrator's own sub-objects - candidate builder, trade executor,
risk/position managers - not strategies; §2.2.3 said otherwise until this batch corrected it.)
A name the factory does not know prints
`[StrategyFactory] ERROR: Unknown strategy '<name>'`, so an indicator pointed at the factory fails loudly instead
of producing a second, unconfigured instance.

Mean Reversion's synthetic branch is not an input: `Init` derives `m_isSynthetic` from `IsSyntheticIndexSymbolName(symbol)`, because the branch is a property of the symbol and its config field exists in no `SOrchestratorConfig` and no root `.mq5`.

**A strategy's type is a fourth identity, and it must be a `GetType()` override.** `IStrategy::GetType()` is pure virtual, `CStrategyBase::GetType()` answers `STRATEGY_TYPE_CUSTOM`, and the consensus engine reads it for the regime hard gate and the category weight. Two classes declared `GetStrategyType()` instead — a lookalike with no callers — and quietly lost both (Batch 195). The catalog row's `registryType` and the class's `GetType()` must carry the same `STRATEGY_*` value; anything else gives the registry and the consensus two different strategies under one name.

### 2.3 Extracted Lifecycle Managers

#### CPositionLifecycleManager

- File: `Core/Management/PositionLifecycleManager.mqh`
- Responsibilities:
  - Signal Reversal Exit (SRE) with breathing room, last-stand zone, profit guard
  - Structural Invalidation exit (ICT/Structure trend flip)
  - Breakeven and trailing stop delegation to `CTradeManager`
  - Safe mode partial profit taking for conservative tier. Position-side only: of `SSafeModeConfig`, just `minConfidence` reaches an entry decision (`EAOrchestrator.mqh:1795`); `IsSignalEvaluationAllowed` (kill-zone + spread), `noStacking`, `minVoters` and `minConfluence` are read by the diagnostics printer alone. Live tier is `RISK_TIER_MODERATE`, so this bites only when an operator selects conservative.
  - Configurable via `ConfigureSRE()` and `ConfigureLifecycle()` from EA inputs

#### CDiagnosticsManager

- File: `Core/Management/DiagnosticsManager.mqh`
- Responsibilities:
- Core heartbeat emission (`[HEARTBEAT]`, `[HEARTBEAT-FUNNEL]`, `[CONVERSION-RATES]`, `[NO-SIGNAL-ALERT]`, `[RISK-BUDGET]`) - journal and JSON log together since Batch 218; before that the payload reached only the JSON file
  - Consensus reason counters: deleted in Batch 256 (`EmitConsensusDiagnostics` had no caller and the 25 `CDiagMgrCounters` counters it read had no writer), so `[CONSENSUS-SNAPSHOT]`, `[STRATEGY-REJECTS]`, `[ROLE-CLUSTER]`, `[QUIET-REASONS]` and `[NO-SIGNAL-ALERT-CONSENSUS]` have no emitter
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
  - Per-symbol tick-rate spike detection over the registered Deriv synthetics, measured as the M1 tick-volume delta
    across 1-second windows (`EvaluateSpikes`, driven from `OnTick` and the 1 s `OnTimer`)
  - Trading pause activation and release, which is the only effect an alarm has: no position is closed here
- Owned by: `CEAOrchestrator` (by value). It holds no pointers to the trade, risk or tick-safety objects - Batch 237
  deleted the two flatten loops that needed them, leaving `CRiskCircuitBreaker` as the single halt-and-flatten authority

#### CTradeAttributionManager

- File: `Core/Trading/TradeAttributionManager.mqh`
- Responsibilities:
  - Prediction position mapping (prediction ID ↔ position ID)
  - AI prediction position mapping with signal/time tracking
  - AI pending request mapping
  - Pending close profit accumulation
  - NN diagnostics logging and self-test
  - Cluster code utilities and trade comment building

#### CScanSchedulerRegistry

- File: `Core/Registry/ScanSchedulerRegistry.mqh`
- Responsibilities:
  - Per-symbol bar-rollover memory (`symbol` + `lastBarTime`), consumed by `EAOrchestrator::ProcessNewBars`
    through `CheckNewBar` - the single new-bar authority for the tick path
  - Nothing else: its `GetStatusReport` was deleted in Batch 247 (the report chain has no entry point), so `lastBarTime` is read only by `CheckNewBar`
- Deleted in Batch 215: `CSymbolScanScheduler` (`Core/Processing/SymbolScanScheduler.mqh`) was never
  instantiated - `new CSymbolScanScheduler` appears nowhere and its only access route,
  `CRegistryAggregator::GetScanScheduler`, returned `NULL` and had no caller - and with it went the dormancy,
  scalp-blacklist, intrabar-timer and pending-new-bar fields of `CScanSchedulerRegistry`, whose accessors had no
  caller either. `CSymbolStateTracker` was deleted on the same evidence: allocated, initialised, printed in the
  shutdown report, and written by nobody.

### 2.4 Pipeline domain

- Class: `CUnifiedSignalPipeline`
- Responsibilities:
- Engine access: `CUnifiedSignalPipeline::SetMathRegistry` is the single seam; Batch 258 wires it from `EAOrchestrator.mqh:1815` under `InpPipelineEngineRegistry` (default false, which is the behaviour every previous build had)
  - cache structural/indicator context once per symbol/timeframe/bar for reuse across strategy votes
  - apply symbol-class-aware context posture so synthetic indices can bypass FX-style ADX trend assumptions while FX keeps full trend filtering
  - apply trend/volatility/liquidity/structure/confidence filters - **inert while `registry=unbound`** (Batch 258): each filter reads `m_mathRegistry`, which `SetMathRegistry` never populated in any build, so signals passed straight through; `InpPipelineEngineRegistry=true` binds the orchestrator's registry and turns them on
  - apply deterministic regime + cost viability pre-gate via `CRegimeEngine` - same dependency, and `SignalPipelineFilter.mqh:41` returns 'pass' when the engine pointer is NULL
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
  - emit threshold-source telemetry (`[PIPELINE-THRESHOLD]`) - unreachable while unbound (0 lines in the 2026-10-23 journal)
  - emit regime/cost veto telemetry (`[REGIME-STATE]`, `[COST-GATE]`, `[ENTRY-VETO]`) - also unreachable while unbound; `[PIPELINE-ENGINES]` at init states which mode a symbol is in

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
- **External LLM Integration:** Optional external LLM support via `CAIEngine`, armed from `InpEnableExternalLLM` at init:
  - HTTP client for Ollama API communication (`http://localhost:11434/api/generate`)
  - Configuration flag: `useExternalLLM` in `SAIAdaptiveConfig` (default `false`), read only by `ProcessAdaptation`
  - Methods (Batch 251 trimmed the surface to what an entry point reaches): `QueryExternalLLM()`,
    `ReasonStrategyWeights()`, `ConfigureExternalLLM()`, `SetExternalAIEndpoint()`
  - Runtime observability: `[EXT-LLM]` covers init, endpoint config, query start/success/failure, reasoning capture,
    weight application and shutdown, so "enabled but unused" states are visible from logs

### 2.6.1 Offline training tools (Batch 235) - one model, two metric holders

- **Not in the EA binary.** `MQHModelTrainer.mq5`, `MQHModelVisualizer.mq5`, `MQHHyperparameterTuner.mq5` and
  `MQHModelEvaluator.mq5` are standalone scripts; nothing under `Core/` includes `MQHModelTrainer/`. The EA loads the
  checkpoint files these produce, so their authority is over *which model gets loaded*, not over a live decision.
- **Model authority:** `CTrainingSession` has exactly one network - `m_model_ptr`, the caller's - set by
  `Train(model, ...)`. The by-value `m_model` member and the family that used it (`Initialize()`, the no-arg `Train()`,
  `TrainEpoch()`, `Evaluate()`, `GetModel()`, `SetLearningRate/SetTemperature/SetL2Regularization`) are deleted; they
  had no callers except that `Finalize()` did call `Evaluate()`, which scored the never-trained network and wrote it
  into `m_metrics` - the object both `GetTrainMetrics()` and `GetValMetrics()` returned.
- **Metrics:** `m_metrics` is validation, `m_trainMetrics` is one real pass over the training set, both filled by
  `EvaluateWithModel(features, labels, count, CTrainingMetrics &target)`. `HyperparameterOptimizer::RankResults` sorts
  by `f1Score` from `GetValMetrics()`, so that ranking reads the trained model from this batch on.
- **Early stopping:** improvement means `valLoss < m_bestValLoss - m_earlyStopMinDelta`, where the delta comes from
  `STrainingConfig::earlyStoppingMinDelta` - constructor default `1e-6`, which is the value the test has always used
  (the three callers wrote `0.0001` into a field nothing read). Patience is `earlyStoppingPatience` (10 at all three
  call sites).
- **Observability:** `Train()` opens `MQHTrainingLog_<date time>.txt` and prints `[MQH-TRAIN] Training log: <file>`.
  The name is set once per program run; a later `Train()` reopens the same file with `FILE_READ | FILE_WRITE` and seeks
  to the end, so a tuner run appends one section per candidate. `Finalize()` prints `stop=early-stopping|epoch-budget`
  plus one `Train:` and one `Validation:` line. Before this batch the log's only `FileOpen` sat in the uncalled
  `Initialize()`, so neither the file nor those metric lines existed and the file branch of `LogMessage` was
  unreachable - and `m_logHandle` was absent from the initialiser list, which matters because a zero handle is `0`,
  not `INVALID_HANDLE`, and that is the value the write branch tests against.
- **Run scoping:** one `CTrainingSession` is reused across the tuner's candidates, so `Train()` resets
  `m_bestValLoss`/`m_bestEpoch`/`m_earlyStopCounter`/`m_earlyStopTriggered` before the epoch loop. Without it, every
  candidate after the first was measured against an earlier candidate's best validation loss and inherited its stop
  flag.

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
  - enforce cluster-aware governance (same-symbol opposing-cluster mutex + per-cluster caps) through `CRiskValidationPipeline` (Batch 151: the never-instantiated `RiskValidationGate.mqh` duplicate was deleted)
  - split budget telemetry (`entry`, `mtm`, `open_exposure`, `effective`) for operator clarity
  - expose unprotected-position state for runtime remediation workflows
  - executed-risk registration after successful synchronous sends, scaled by actual fill ratio
  - portfolio correlation fallback uses bounded value (0.65, capped to `m_maxCorrelation`) when correlation data is unavailable, avoiding hard blocks while preserving safety
  - progressively throttle recommended per-trade risk as daily and portfolio utilization rise, instead of waiting for the final hard-cap stage
  - enforce tiered correlation response: reduce position size at `correlationReduceThreshold` (0.4) and block at `correlationBlockThreshold` (0.7)
  - enforce daily P\&L loss limit circuit breaker via `dailyLossLimitPercent`, `CheckDailyLossLimit()`, and `m_dailyLossHaltActive` state
  - reset daily risk counters at configurable `m_tradingDayStartHour` instead of relying on MT5 server day boundary
  - apply rationalized safe defaults: 1% base risk, 5% max per trade, 5% daily, 15% portfolio
  - maintain a scan-time `CVirtualPositionBook` so approved-candidate reservations count against projected daily and portfolio usage and guard against opposing cross-cluster entries (Batch 151: reservations book the provisional request risk, sync to the final adjusted risk via `UpdateVirtualPositionRisk`, and expire after their 60s TTL; previously a zero-risk placeholder made every reservation silently fail. Batch 239: a reservation ends on TTL **or** on coverage - `PruneCoveredByPositions()` discharges it once an open position with the same symbol, direction, magic != 0, an open time at or after the reservation and a lot at least as large exists, one position per reservation - because `GetPortfolioRisk()` already counts that position and the caps were charging it twice. `UpdateVirtualPositionRisk` now also re-syncs the lot from `result.adjustedLotSize`, without which a shrunk fill could never discharge its own reservation)
  - day-rollover uses pure `TradingDayKey()` comparisons (Batch 151): `CheckDailyLossLimit` no longer mutates `m_lastTradingDayKey` ahead of `CheckAndResetDailyLimits`
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
- **Batch 152 magic-send authority:** `CTradeManager::OpenPosition(magicNumber>0)` records the caller's ABSOLUTE magic in `m_pendingExplicitMagic`, and the actual send (`ExecuteMarketOrder` via `GetSymbolTrade`) ships it verbatim; callers passing 0 derive base+symbol-offset as before. SpikeHunter's precomputed absolute magics therefore land inside `IsEAOwnedMagic` instead of being double-offset out of range. The async path enforces the same mandatory-SL invariant as the sync path (`[EXECUTION-BLOCKED] reason=MandatoryStopLoss | path=async`).
- **Batch 152 ownership checks:** manual-close restore gates in both EAs use `IsEAOwnedMagic()` (the previous `(int)(magic/100)` arithmetic matched no EA-owned ticket); scalp deal confirms flow from `OnTradeTransaction` -> `ProcessScalpDealConfirmed`.
- **Batch 153 telemetry + lifecycle hygiene:** the orchestrator scan loop now writes the heartbeat funnel counters (`IncScansAttempted` per symbol slot, `IncNoSignalCount` on generator-empty slots, `IncValidatorRejects` on failed post-consensus validation) — `[HEARTBEAT] scans/no_signal/validator_reject` and the status report's `Scans=` field were previously hard-zero because no writer existed. Trade attribution splits the contributor CSV via `CTradeAttributionManager::SplitContributors()` (previously stored as one malformed name). `CleanupOnInitFailure()` mirrors `Shutdown()`'s release sequence (math hub, EA-owned sizing modifiers, neural nets, drawing managers, Deriv-engine deinits, TradeManager deinit, scalp cache, uncertainty, error-handler singleton) so a late init failure no longer leaks objects with live indicator handles. Dead zero-caller code removed: `CErrorHandling` wrapper class, five dead `CPositionManager`/StateStore position-state methods, two dead `CSignalGenerator` methods. The strategy performance feedback loop (`CEnterpriseStrategyManager::OnTradeTransaction` chain, `CPerformanceAnalytics::RecordClosedTrade`, loss-guard trade accounting) remains unwired by explicit product decision — see SYSTEM_AUDIT_TRACE.md.
- **Batch 154 closed-trade feedback loop (live):** both EAs route `OnTradeTransaction` into `EAOrchestrator::ProcessManagerTradeTransactions`: (1) fan-out to every symbol manager so attribution pop / per-strategy `UpdatePerformance` / health monitor / governance disable write-through run; (2) on full closes of EA-owned positions (`POSITION_IDENTIFIER` re-check excludes partial closes) feed `CPerformanceAnalytics::RecordClosedTrade`, `CPositionManager::RecordClosedTrade` and `CLiveAuthorityResolver::RecordOutcome` via an execution-time provenance map (position id → contributor summary + owning manager). AI-contributed candidates can now promote to PROVEN_AI (≥0.75× risk after 30 tracked trades with expectancyR ≥0.3 / PF ≥1.2); the bootstrap cap is unchanged for unproven AI. Prerequisite repairs: health-monitor re-enable predicate accepts cooldown-served recovery with a rolling-sample reset (post-disable wins were unreachable), and an orchestrator-owned 60s governance sweep in `ProcessTradingLogic` runs disable/re-enable independent of AI mode. Legacy Deriv engines remain parked with explicit `PARKED:` init logging; VPIN/institutional layer stays documented-dormant.
- **Batch 155 strategy emission-path repairs (signal-suppression bugs, 9 files):** series-ordering corruption fixed where static (non-series) buffers filled OLDEST-first but were read as newest-first — `VolatilityBreakout.ADXRising()` was inverted (required ADX falling), `SimpleMomentum` MACD/volume/ROC/divergence/hysteresis reads reversed, `MeanReversion` divergence window + synthetic-mode bands stale by two bars, `MultiEMASystem` EMA/ADX buffers reverse-mapped to `[k]=shift k+1` (the entire StrategyTrend trend state ran nine bars stale), and `StrategyTrend.MACDConfirmed` now/prev un-swapped. Scale fixes: Momentum's FX-scale absolute ATR floor capped at 1bp of price and its volatility confidence tax re-anchored to the symbol's own 10-bar ATR average; TrendEntryTypes pullback tolerance widens to 0.25×ATR (was 15 POINTS ≈ 1.5 pips). Confidence-economics: MeanReversion RSI-only/BB-touch tiers rebased so they clear the 0.60 floor (hierarchy preserved); LiquiditySweep daily high/low sweeps get a level bonus (+0.10) and stops sit beyond the swept wick extreme instead of inside it. Wiring: the orchestrator dependency pass injects the Python bridge into Statistical Arbitrage (catalog path never did — registered-but-permanently-mute). Robustness: AsianRangeBreak uses exact=false bar lookup and sqrt-of-time-scaled expected range (6h M5 window vs per-bar chart-TF ATR was unsatisfiable on M1/M5, vacuous on H4/D1); NYOpenGap/AsianRangeBreak synthetic skips use the full `IsSyntheticIndexSymbolName` umbrella; RangeCompression reads closed bars only and exempts counter-trend FADE entries from the momentum-only trend filter. Consensus quorum, risk gates and per-strategy quality floors untouched; Turtle Soup/Breaker Block/FVG conjunctive scarcity documented as design, not defect.
- **Batch 156 detector-layer repairs (helpers feeding the strategies):** same defect classes audited one layer below the strategies. Chronology: `TrendlineDetector` pair-anchor inversion fixed (p1/p2 were assigned newest/oldest then required p1 older — zero trendlines ever built) and `NormalizeSlope` is ATR-relative (pip-based angles saturated past the ±70° gate on synthetics); `AdvancedOrderBlocks` Source-OB walk breaks on the first match closest to the impulse start (was keeping the oldest candle in a 20-bar window — mis-anchored zones every scan). Closed-bar state: SR bounce/trendline-bounce rejection reads, `DetectBreakout` (+1bp-of-price tolerance floor), OB `CheckMitigation`, FVG `CheckRebalance` (fillPercent keeps deepest penetration), session-gap `UpdateFillStatus`, and `HasStructureBreak` all ignore the forming bar — no more intrabar latching of permanent state or per-tick structure-flag flips feeding FVG/TurtleSoup/BreakerBlock confluence bonuses. Starved paths: `DetectExternalSwingLiquidity` per-side budgets (sell-side pools were structurally never emitted), `DetectBMS` PeriodSeconds classification (H2–H12 fell through every enum branch → permanent BMS_NONE), NDOG/NWOG fail closed without ATR (5/10-point fallback manufactured phantom gaps). Scale/candle chain: engulfing tolerance uses the analyzed symbol's point+ATR (was chart `_Point`), AOB key-level tolerance ATR-floored (20×point ≈ 0.2 absolute on synthetics), pin-bar zero-body squeeze fix + fail-closed ATR gates (pin/doji/hammer), hammer/star merged with prior-trend context split and dominant-wick scoring, CandleAnalyzer shift-1 ATR + symbol accessors, StrategyCandlestick 8-site 50/50 strength/confluence blend with ATR-floored SL padding. Shared feeds: `ADXPositionSizing` no longer `IndicatorRelease()`s the manager-owned shared ADX handle (re-init permanently killed the Trend stack's ADX feed); `TrendTrailingStop` unwarmed-feed guards return "no trail" and TRAIL_HYBRID's sell side combines only live stops (a ~0 stop previously won MathMin selection).
- **Batch 157 scout-findings sweep closure:** every remaining audit finding sorted. `LiquidityDetector`: equal-highs/lows tolerance floored at 0.2bp of price at all three sites (`equalTolerancePips` was multiplied by raw POINT — detection effectively dead outside FX), sweep-confidence penetration normalized by the sweep bar's range, `IsAtPsychologicalLevel` gains a magnitude-based round grid for non-FX digits. `AdvancedOrderBlocks`: breaker windows exclude the forming bar, vacuum-block volume gate relaxed to <65% of average (was <30% on a ≥1.5×ATR range bar — practically unreachable), and all iATR create/release churn (GetATRValue + two inline Source-OB copies) replaced with shared CIndicatorManager handles; SessionGapDetector::GetATR likewise. `MarketStructureAnalyzer`: DetectFastCHOCH/DetectWickBOS/DetectCISDDisplacement judge closed bars (FVGScalper/AsianRangeBreak confidence bonuses were flip-flopping tick-by-tick). `TrendTrailingStop`: sell extremes tracked off ASK. Re-adjudicated with evidence, no change: the reported min-lot clamp-up does not exist; the roleReversed copy-set is an inert no-op (the real defect — HasRoleReversed's own 10-point match tolerance, dead on synthetics — is now 1bp-of-price floored).
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
- Implementation: `Core/Orchestration/LiveAuthorityResolver.mqh`
- Responsibilities that are implemented:
  - score each risk-approved candidate (ONNX / AI / indicator / confluence / decision-path quality) and return a live risk multiplier
  - shadow-only rejection on mode conflict (`INDICATOR_ONLY_MODE`, `AI_ONLY_MODE_NO_AI`) and on `LOW_CONFIDENCE`
  - track forward-R outcomes for AI and ONNX contributors only — `RecordOutcome` is fed from `ExtractAIName`, which returns nothing for indicator or Elliott families, so those families carry no authority record
  - promote a mature AI-only contributor from the bootstrap cap to the promoted floor once samples, expectancy, profit factor and loss-streak gates all pass (Batch 172: this became reachable for the first time — see below)
  - size the trade with that multiplier (Batch 173): `EAOrchestrator` calls `CCandidateBuilder::ScaleLotByLiveAuthority(...)` after the `allowed` test and before the send, so the ladder, the bootstrap cap and `PROVEN_AI` promotion now set the shipped lot instead of only the log line. Shrink-only by construction — the top rung is 1.0, the only raising branch (`PROVEN_AI`) is clamped to 0.75 — so this can never size above what `CUnifiedRiskManager` approved
  - emit `[AUTHORITY-LEARN]` per recorded close and `AuthorityDecision` / `AuthorityReject` JSON events; the thresholds are stated at init by `[AUTHORITY-CONFIG]` and each decision prints with its own reason (`[AUTHORITY-REJECT]` / `[AUTHORITY-REDUCED]`) - the class's `[LiveAuthorityResolver]` status block was deleted in Batch 247 because nothing could print it
- Visibility contract for the sizing step (Batch 173). Nothing about this gate is allowed to look like a quiet market:
  - every shrink prints `[AUTHORITY-REDUCED]` with the multiplier, the before/after lot, the before/after risk percentage and the reason
  - a lot that lands under `SYMBOL_VOLUME_MIN` is **refused, not rounded up** — `CPositionSizer::NormalizeVolume` clamps up to the minimum (`PositionSizer.mqh:572`) and would return the whole reduction while the log claimed a shrink happened, so the floor is applied by hand with `SYMBOL_VOLUME_STEP`. Each refusal prints `[AUTHORITY-REJECT]` twice (the arithmetic, then which levers would bring the symbol back) plus an `AuthorityReject` JSON event
  - refusals accumulate per symbol and per session, and `[CandidateBuilder]` status prints `authorityLotRefusals total=N` with the breakdown, so a symbol the ladder has sized out of existence is distinguishable from a symbol with no signals
  - `candidate.riskPercent` is scaled by the same ratio as the lot, because `RegisterExecutedTradeRisk` books it into the daily entry budget
- Not implemented (documented here so the gap is visible rather than implied):
  - `result.allowed` is still set `true` unconditionally at the end of `Resolve()`, so the only *vetoes* remain the two mode checks and `LOW_CONFIDENCE`; the score ladder acts through size, not through permission
  - per-family demotion back to shadow when forward evidence degrades — an unproven contributor is capped each cycle, but a promoted one is never demoted except through the `consecutiveLosses < 4` test at evaluation time
  - trial-window tracking: never implemented, and Batch 238 deleted the three inputs that implied it
  - `[LIVE-AUTHORITY]`, `[AUTHORITY-TRIAL]` and `[AUTHORITY-RESULT]` telemetry — these tags appear in no source file and will never appear in a log
- Related but separate: VPIN order-flow toxicity affects size through `CVPINLotModifier` in the `CPositionSizer` modifier chain, not through this resolver (**true only from Batch 213**: the modifier had been reading a `CVPINFilter` it created itself, which nothing feeds ticks to, so `IsWarmedUp()` was false forever and every lot passed through unchanged; it now reads the math hub's per-symbol filters, registered from the engine-injection loop, and `[SIZING-CHAIN] vpin_filters=N` says whether any are present). Since Batch 174 it also vetoes: `CPostConsensusValidator::CheckVPINFilter` calls `CVPINFilter::ShouldBlockNewPositions()` and returns false at the filter's configured EXTREME level, reading the regime from the filter instead of the 0.85/0.95 literals that sat above it. `m_lastVPINMultiplier` is a diagnostic mirror of the modifier's value, not a sizing input.
- Sizing chain ownership (Batch 174): `BuildCandidate`'s modifier chain is `ApplyDrawdownScaling` → `ApplyMomentumScaling` → broker-minimum floor → post-size re-gate → `ScaleLotByLiveAuthority`. The four steps that used to sit in that chain and return their input untouched (`ApplySkewStepScaling`, `ApplyFullMarginStacking`, `ApplySafeModeRestrictions`, `EvaluateEAModeAdmission`) are deleted; skew-step, full-margin and safe-mode each have a real owner elsewhere or need a hook that does not exist yet, and are tracked as open rather than faked in the sizing path.
- Threshold policy (Batch 172): every `InpAuthority*` input now reaches the resolver, but each is clamped so it can only tighten its gate or shrink its multiplier, never the reverse. The floors are the values this project has always documented (30 samples, expectancyR >= 0.3, PF >= 1.2, promoted 0.75x, bootstrap 0.5x); a clamp is announced once at init as `[AUTHORITY-CONFIG] clamped ...` and the effective set is printed as `[AUTHORITY-CONFIG] effective: ...`.

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
- Implemented drawing diagnostics (`[DRAW-LEVELS]`, `[LEVEL-DETAILS]`, `[DRAW-RESULT]`) reach the SupportResistance subsystem log file through `CSubsystemLogger::Log`, not the terminal journal
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
- Signal Cache: `CScalpSignalCache` in `Core/Scalp/ScalpSignalCache.mqh` — the per-symbol store, and the only
  cache its entry path trusts
- Slow-path cache: `CFastScalpIndicators` in `Core/Scalp/FastScalpIndicators.mqh` holds **one** slot
  (symbol tag + bar time + ATR + RSI) shared by the whole universe, because the orchestrator holds one engine
  by value and walks every symbol through it each tick. Since Batch 214 a refresh commits only after both
  `CopyBuffer` reads succeed; before that a mid-sequence failure left one symbol's numbers under another
  symbol's tag and the new-bar test served them back. The EMAs are deliberately not cached — a crossover needs
  two bars, so `GetEMACrossover` reads its own pair statelessly.
- Missing data fails closed: `EvaluateFromCache` refuses a signal whose cached RSI is `<= 0.0` rather than
  reading "no data" as "not overbought" (Batch 214), and every gate that refuses names itself under
  `[SCALP-SIGNAL-REJECT] ... gate=`, throttled per symbol.
- Responsibilities:
  - provide tick-level signal evaluation via cached indicator values, bypassing the full consensus pipeline for low-latency scalping entries
  - manage `SScalpIndicatorCache` struct per symbol (fixed-size array for 20): since Batch 216 it carries the six values one consumer reads - `emaFast/emaSlow` with their previous-bar values, `atrValue`, `rsiValue` - plus `spreadPoints`, `lastBarTime`, `isValid` and four handles. The Bollinger, ADX, volume and ATR-history fields this struct also used to fill every new bar were computed for no reader and are gone.
  - separate `UpdateOnNewBar()` (CopyBuffer path) from `UpdateTickValues()` (SymbolInfoDouble-only path) to minimize per-tick computation
  - all indicator handles sourced from `CIndicatorManager::Instance()` singleton
  - support async order execution via `OrderSendAsync()` with `SScalpPendingAsync` tracking and `OnDealConfirmed()` callback
  - track execution latency via `InpScalpMaxLatencyMs` and timeout pending async orders
  - integrate with `OnTradeTransaction()` for async order confirmation routing
- **Scalp Strategies - corrected in Batch 216.** This block used to list three classes as if the engine ran them.
  It runs none of them: the fast-scalp path's entry logic is `CFastScalpSignal` (EMA 5/13 crossover on M1 + RSI(7)
  confirmation + spread-vs-ATR cost gate), not a strategy object.
  - `CScalpMomentumStrategy` (`Core/Scalp/ScalpMomentumStrategy.mqh`) and `CScalpSpreadStrategy`
    (`Core/Scalp/ScalpSpreadStrategy.mqh`): **no such file has ever existed in the repository.**
  - `CScalpVolatilityBreakout` (`Core/Scalp/ScalpVolatilityBreakout.mqh`): the file exists and is a complete
    233-line `CStrategyBase` subclass, but nothing `#include`s it, it has no catalog row, no `SI_*` slot, no
    `InpEnable*` input and no `factoryName` - so it is not in the binary at all. Kept rather than deleted,
    because unlike the unreachable factory paths of Batch 210 this is a whole strategy that could be activated;
    activation is the operator's call (it would create exposure on a path that has never traded), so it is on the
    `unwired but wireable` list in §4.
- **Dual-Path Processing:**
  - `OnTick()` runs `ProcessScalpFastPath()` for tick-level cached-indicator signal evaluation alongside the existing safety loop
  - `OnTimer()` retains full consensus logic (pipeline → manager → validator → risk → execution)
  - Scalp fast path reads from `CScalpSignalCache` for zero-computation indicator access
  - Scalp entries still pass through `CUnifiedRiskManager` pre-trade gating (AGENTS.md invariant #1 preserved)
  - **Batch 152 fast-path completion:** the fast path refreshes its own cache (`UpdateOnNewBar` + `UpdateTickValues`, self-throttled to new bars) at head and runs the full management set per tick (`SyncScalpPositionTracking / ManageScalpPositions / CheckPendingAsyncOrders / CheckPendingScalpOrders`); async fills confirm via `OnTradeTransaction` -> `ProcessScalpDealConfirmed`. ATR-scalp partial-profit is ticket-latched (one partial per position lifetime, latch pruned on close); same-bar EMA-cross re-entries are locked out per symbol; grid-recovery activation floor baselines on ACCOUNT_BALANCE (was equity-vs-equity, never failed).

### 2.18 Risk Enhancement domain (Batch 97)

- Enhancements to `CUnifiedRiskManager`:
  - Tiered correlation response: `correlationReduceThreshold` (0.4) reduces position size, `correlationBlockThreshold` (0.7) blocks trade entirely
  - Daily P\&L loss limit: `dailyLossLimitPercent` circuit breaker halts trading when daily loss exceeds threshold, tracked via `CheckDailyLossLimit()` and `m_dailyLossHaltActive`
  - Broker trading day reset: `m_tradingDayStartHour` (configurable, default 0) ensures daily risk counters reset at the correct broker trading day boundary
  - Rationalized defaults: baseRiskPerTradePercent=1%, maxRiskPerTradePercent=5%, maxDailyRiskPercent=5%, maxPortfolioRiskPercent=15%
- Enhancements to `CPositionSizer`:
  - `POSITION_SIZE_KELLY` mode: **consolidated to Bayesian Kelly modifier** (L5-012), falls back to fixed risk sizing; `CBayesianKellyModifier` applies quarter Kelly (25%) with Beta-Binomial priors
  - `CBayesianKellyModifier` is **inert** and says so at every start (`[SIZING-CHAIN] kelly=inert`): its only input, `UpdateTradeResult`, has no caller, so `m_totalTrades` stays 0 and it returns the lot unchanged. Wiring it as written would be a trap rather than a fix - it multiplies a lot that is already fixed-risk sized by a fraction of bankroll (`K * 0.25` is ~0.02-0.075), which would cut every subsequent trade to roughly 1/13-1/40 of intended size on the strength of a single closed trade. The correct form is Kelly choosing `riskPercent` before sizing, which is a redesign, not a wiring (Batch 213)
  - Equity compounding: `CalculateCompoundingMultiplier()` with sqrt upside / linear downside scaling
  - Unified correlation: `SetCorrelationEngine()` delegates to `CCorrelationEngine` instead of internal Pearson
  - Conditional logging: `m_logLevel` + `SetLogLevel()` gates `LogSizingDecision()` output
  - **Batch 98 stateless refactor**: `CalculateSize()` is now truly stateless via `CalculateOptimalPositionSizeCore()` — the save/restore hack on `m_lots` has been removed; callers receive the computed size without side effects on internal state
- **Batch 152 sizing/risk-math corrections:**
  - `CPositionSizer::CalculateRiskPerLot` uses the execution pip convention (`stopLossPips * point`, no ×10): fixed-risk lots now match actual stop geometry — LIVE-BEHAVIOR CHANGE, sizes move ~10x toward configured risk
  - `NormalizeLot` floors to whole `SYMBOL_VOLUME_STEP`s with 8-digit cleanup (no trailing 2dp re-rounding)
  - `CADXLotModifier` tracks handle provenance (`m_handleOwned`): shared `CIndicatorManager` handles are never released; only fallback-created ones are
  - `CVolatilityTargetingModifier` anchors volatility ATR to `PERIOD_D1` (chart-TF-independent; annualization assumes daily vol)
  - `CRiskSymbolStats` computes win-rate + profit-factor in one pass, memoized per symbol behind a 60s TTL (full-history `HistorySelect(0,...)` scans eliminated from the per-symbol budget refresh)
  - `CUnifiedRiskManager::CalculatePositionRiskPercent` converts tickValue per-tick via `point/tickSize` (symbols where tickSize≠point)
  - `CCorrelationEngine::GetCorrelation` pins both query symbols across the internal refresh so `PruneStaleSymbols` cannot drop/shift a fresh candidate mid-query
  - `CRiskAdaptiveTuner` may only RAISE conservative mode; escalation/clear ownership belongs to the circuit breaker's bool& write-backs

### 2.19 Strategy Intelligence domain (Batch 97)

- Enhancements to `CStrategyBase`:
  - Regime-aware weighting: `GetRegimeConfidenceMultiplier()` scales confidence by regime alignment (TREND\_CLUSTER: 1.5x strong/0.3x range; MEAN\_REVERSION\_CLUSTER: 1.5x range/0.2x strong; STRUCTURE\_CLUSTER: 1.0x)
  - Volatility direction: `GetVolatilityDirection()` classifies ATR as EXPANDING/CONTRACTING/STABLE; `GetVolatilityDirectionMultiplier()` applies 1.2x/0.8x/1.0x
  - Multi-timeframe confluence: `IsAlignedWithHigherTF()` checks EMA50 on next higher timeframe
  - All intelligence factors applied in `GetSignal()` before returning to manager consensus
  - **Batch 140 shared helpers (Phase 4 debloat):** Consolidated duplicated strategy boilerplate into protected virtual methods so all strategies share one implementation:
    - `LogRejectEvent()` / `RejectSignal()` — throttled reject logging via `m_strategyPrefix`, `m_lastRejectReasonTag`, `m_lastRejectLogTime` (removed from 8 strategy files)
    - `RefreshForNewBar()` + `OnRefreshComponents()` virtual hook — new-bar guard via `m_lastBarCount`; 5 strategies override `HandleNewBar()`/`OnRefreshComponents()` instead of duplicating boilerplate
    - `ValidateWithRiskManager()` — pre-trade risk-validation helper (consolidated into 11 of 12 strategies; StatisticalArbitrage skipped — different pattern)
    - `LogConsensusDiag()` — `[CONSENSUS-DIAG]` logging helper (consolidated into 9 of 12 strategies; 3 outliers skipped — structural variations)
- Enhancements to `CEnterpriseStrategyManager`:
  - Per-cluster conviction tracking (trendClusterBuyConviction/SellConviction, meanRevClusterBuyConviction/SellConviction)
  - Cross-cluster conflict resolution: opposing cluster conviction subtracted, regime-weighted
  - `MathMax(0.0, ...)` guards on conviction subtraction to prevent negative values from floating-point precision
- Enhancements to `CTradeManager`:
  - Mandatory SL gate: `ExecuteMarketOrder()` rejects trades with `stopLossPips <= 0.0`
  - Conditional logging: `m_logLevel` + `SetLogLevel()` gates execution quality reports
- EA-level risk controls in `MultiStrategyAutonomousEA.mq5`:
- Min R:R enforcement: 2.0 default, 1.5 for MEAN\_REVERSION\_CLUSTER (`CandidateBuilder.Configure(2.0, 1.5, ...)`, reachable only from Batch 219)
  - Portfolio profit target: `InpDailyProfitTargetPercent` with `InpProfitTrailFactor` trailing floor
  - Auto mode switching: does not exist. The stub that its input gated is deleted in Batch 238; the live mode authority is `CRiskAdaptiveTuner` (scales the base per-trade risk down) plus the two-of-five conservative trigger vote in `PerfAnalyticsRiskTriggers.mqh:124-138`

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
  - Batch 151 wiring (flagged-item closure): `CUnifiedRiskManager::RefreshRuntimeState()` feeds the minute-gated `UpdateEquityCurve()` sampler; `CRiskValidationPipeline` vets proposed risk (as a fraction) against the gate before final approval and releases the virtual reservation on reject. Arms only after 20 equity samples (~20 minutes uptime).

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
- Emit `[SCALP-COST-REJECTED]` when cost viability fails (`[SCALP-SIGNAL-REJECT]` names the gate that refused the signal itself)

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
  - Emit `[SPIKE-HUNT-DETECT]`, `[SPIKE-HUNT-TRADE]`, `[SPIKE-HUNT-SKIP]`, `[SPIKE-HUNT-ALERT]`, `[SPIKE-HUNT-ALERT-THROTTLED]`, `[SPIKE-PAUSE]`, `[SPIKE-HUNT-ENGINE]` log signatures; `[SPIKE-HUNT-DETECTED]`, `[SPIKE-COOLDOWN]` and `[SPIKE-HUNTER-STATS]` were never tags
  - **Batch 102 family override integration:** `SSpikeHunterFamilyOverrides` struct provides per-family spike parameter overrides with 8 `GetEffective*()` methods. Profiler-driven configuration via `SetFamilyOverrides()` applies family-specific velocity multipliers (CrashBoom 2.8×, Jump 3.0×, Volatility 3.5×), ATR compression ratios, SL/TP multipliers, magic offsets, cooldowns, and minimum confluence thresholds.

### 2.26 Hurst Engine domain (Batch 101)

- Class: `CHurstEngine` in `Core/Engines/HurstEngine.mqh`
- Responsibilities:
  - Fractal persistence estimation via variance-time Hurst exponent
  - Regime-based strategy weight multipliers integrated into `CRegimeEngine`
  - Classify market persistence: H > 0.5 (trending), H ≈ 0.5 (random walk), H < 0.5 (mean-reverting)
  - Provide `GetHurstExponent()` and `GetPersistenceMultiplier()` for strategy weight scaling
- Emit `[HURST]` telemetry with exponent value and regime classification

### 2.27 OU Process Engine domain (Batch 101)

- Class: `COrnsteinUhlenbeckEngine` in `Core/Engines/OrnsteinUhlenbeckEngine.mqh`
- Responsibilities:
  - Mean-reversion speed estimation via OLS regression on price series
  - OU-adjusted z-scores integrated into `StatisticalArbitrageStrategy`
  - Estimate mean-reversion half-life from OU parameters (θ, μ, σ)
  - Provide `GetOUZScore()`, `GetHalfLife()`, `GetMeanReversionSpeed()` for signal conditioning
- Emit `[STATARB-OU]` / `[KALMAN-MR]` telemetry with parameter estimates and z-score values

### 2.28 OFI Proxy Engine domain (Batch 101)

- Class: `COrderFlowImbalanceEngine` in `Core/Engines/OrderFlowImbalanceEngine.mqh`
- Responsibilities:
  - Proxy order flow imbalance from tick classification (buyer/seller initiated) at 3 time scales
  - Welford online z-score normalization for streaming OFI values
  - Directional confirmation filter integrated into consensus pipeline
  - Provide `GetOFIZScore()`, `GetImbalanceDirection()`, `GetMultiScaleOFI()` for consensus augmentation
- Emit `[OFI]` telemetry with imbalance values and z-scores per time scale

### 2.29 VPIN Filter domain (Batch 101)

- Class: `CVPINFilter` in `Core/Risk/VPINFilter.mqh`
- Responsibilities:
  - Volume-synchronized probability of informed trading (VPIN) from tick data
  - Toxicity-based position sizing: reduce size when VPIN exceeds threshold
  - Trade blocking when informed trading probability is critically high
  - Provide `GetVPIN()`, `GetToxicityLevel()`, `GetSizeMultiplier()` for risk integration
- Emit `[VPIN]` telemetry with the VPIN value and toxicity state, and `[VPIN-MODIFIER]` with the sizing multiplier

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
- Emit `[DERIV-PROFILER] <symbol> family=<name> -> ...` and `[MULTI-ASSET-PROFILER] <symbol> class=<name> -> risk= maxDD= magic=`; `[PROFILER-DETECT]` was never a tag

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
  - Emit `[GRID-RECOVERY]` with `-DIAG` / `-DEBUG` / `-MARGIN` / `-FAILED` plus `[GRID-RESTART]` at init (engine parked, Batch 178); `[GRID-RECOVERY-ENTRY]`, `-LEVEL`, `-CLOSE` and `-DRAWDOWN` were never tags

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
  - Emit `[ATR-SCALP]` with `[ATR-SCALP-DIAG]` / `-FAILED` / `-PARTIAL` / `-BREAKEVEN` (engine parked, Batch 178); `[ATR-SCALP-ENTRY]`, `-EXIT`, `-SPIKE-WINDOW` and `-COOLDOWN` were never tags

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

- **NOT IN THIS REPOSITORY** - `CPartialCloseManager`, `SPartialCloseState` and `Strategies/UnifiedICTFiles/PartialCloseManager.mqh` do not exist (Batch 218 check). Partial closes are owned per engine: `[PARTIAL-PROFIT]` (`PosLifecycleExit.mqh:134`), `[SAFE-MODE-PARTIAL]`, `[SCALP-PARTIAL]`, `[ATR-SCALP-PARTIAL]`.

- **NOT IN THIS REPOSITORY** - `CTimeframeConfluence`, `STFAlignmentCache` and `Strategies/UnifiedICTFiles/TimeframeConfluence.mqh` do not exist (Batch 218 check). Neither does `CTimeframeConsistency`: `Core/Signals/TimeframeConsistency.mqh` was deleted in Batch 261 with 608 lines, nothing having ever called its two feeding methods. Its 40/30/30 scoring was a 2026-08 design note, and `[TimeframeConsistency] Initialized with mode:` has no printer now.

- **Component Upgrades**:
  - `AdvancedOrderBlocks.mqh`: `GetFreshness(int obIndex)` returns 0.0-1.0 freshness decay for order blocks. Used by BreakerBlockStrategy for freshness > 0.7 confidence bonus.
  - `MarketStructureAnalyzer.mqh`: 5 fast structure detection methods — `DetectFastCHOCH()` (3-swing CHOCH), `DetectWickBOS()` (wick-based BOS), `DetectCISDDisplacement()` (CISD displacement), `GetSwingHighLevel()`, `GetSwingLowLevel()`. Used by FVGScalper, TurtleSoup, BreakerBlock, AsianRangeBreak for rapid structure confirmation without full re-analysis.
  - `LiquidityDetector.mqh`: `SExternalLiquidityPool` struct + `DetectExternalSwingLiquidity()` for swing-based external liquidity detection. Used by TurtleSoupStrategy for liquidity sweep identification.

- **EnterpriseStrategyManager Extensions**: `m_maxStrategies` increased 20→25 to accommodate 5 new strategies. `GetStrategyByName(const string name)` returns `IStrategy*` by name (wraps `FindStrategyIndexByName()`). 5 new `RegisterStrategy()` calls with tier/cluster/weight assignments.

- **Synthetic Symbol Filtering**: Session-based strategies (NY Open Gap, Asian Range Break) skip synthetic symbols (Volatility, Boom/Crash, Jump, Step) since these CFDs have no real session gaps. Filtered via `IsVolatilitySyntheticSymbolName()`, `IsBoomCrashSyntheticSymbolName()`, `IsJumpSyntheticSymbolName()`, `IsStepSyntheticSymbolName()`.

- **Enum Additions** (`Core/Utils/Enums.mqh`): `STRATEGY_FVG_SCALPER=11`, `STRATEGY_TURTLE_SOUP=12`, `STRATEGY_BREAKER_BLOCK=13`, `STRATEGY_NY_OPEN_GAP=14`, `STRATEGY_ASIAN_RANGE_BREAK=15`.

- **EA Input Parameters** (`MultiStrategyAutonomousEA.mq5`): `InpEnableFVGScalper`, `InpEnableTurtleSoup`, `InpEnableBreakerBlock`, `InpEnableNYOpenGap`, `InpEnableAsianRangeBreak` (all bool, default true). Mapped in `BuildStrategyFlags()` at indices 12-16 (as written; the current `SI_*` slots are 10-14, and since Batch 209 the flag builder holds no per-strategy lines).

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
  - `VPIN_EXTREME`: refused after consensus by `[POST-CONSENSUS-FILTER] ... filter=vpin_extreme` (Batch 174); `VPIN_HIGH`/`VPIN_MEDIUM` shrink the lot through `[VPIN-MODIFIER]` (Batch 213), not the weights
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
- **A5 Strategy Registration**: StatisticalArbitrage registered via its catalog row's enable slot, gated on Python Bridge availability (`BuildStrategyFlags()` no longer names strategies); shadow mode when bridge disconnected, live mode when connected.

## 3. Managed Strategies

### 3.1 Core retained set

- **Momentum** (SimpleMomentumStrategy.mqh)
  - v2.0: MACD histogram confirmation, ADX strong trend filter (ADX > 25), pullback entry mode (EMA pullback within 0.5×ATR), freshness confidence modifier (+10%), volume confidence modifier (+8%)
  - Optional scalp-continuation mode is configured by `InpEnableMomentumScalping` and `InpMomentumScalpCooldownSeconds`; it shortens cooldown only for momentum itself and still sends every entry through manager consensus, unified risk, and trade-manager execution.
  - `InpMomentumScalpTimeframe` is the timeframe Momentum registers on (bound from Batch 249; before it the value reached no `Init`). With the shipped `PERIOD_M5` it also keeps `InpEnableMomentumScalping` honoured: the strategy's own M1-M15 band test (`SimpleMomentumStrategy.mqh:513`) used to force trend-following whenever the chart sat above M15.
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
  - `InpCandlestickIntrabarTimeframe` is the timeframe Candlestick registers on (bound from Batch 249). It changes its pattern reads only - intrabar *participation* is still report-only, and entries never request intrabar mode (`RUNTIME_DECISION_GRAPH.md` Batch 233).
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
- AI adapters can be the sole tradable family when enabled. The *entry* vote is new-bar only (`EVAL_MODE_NEW_BAR` at
  `EAOrchestrator.mqh:3507`/`:3573`); no entry path runs an intrabar scan (Batch 233).
- AI intrabar participation is *configured* per strategy (`InpIntrabarEligibilityNeuralNetworkAI`, `InpIntrabarEligibilityTransformerAI`, `InpIntrabarEligibilityEnsembleAI`, `InpIntrabarEligibilityOnnxAI`) rather than hard-forced `OFF` at governance time — and since Batch 233 that field is stated as report-only: the stored policy gates no vote, and the AI adapters register with `fixedPolicy = LIVE` regardless of the input, because their catalog slot is `-1`.
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

- Startup emits per-symbol symbol-selection evidence as `[SYMBOL-UNIVERSE]` (tradeability and market mode) and the affordability ceiling shows up where it bites: `[RISK-GATE-REJECT] ... reason=compliant_lot_below_min`. Restart reconciliation of inherited EA positions is `[GRID-RESTART]` and `[RISK-MUTEX-COOLDOWN]`, not a `[TRADE-STATE]` line - that tag never existed.
- Shared validator spread-shock state is symbol-scoped, not portfolio-global, so cross-symbol spread contamination cannot veto otherwise valid candidates.
- New-bar path: conservative scan cadence.
- Intrabar path: timer-driven scans when enabled.
- Heavy evaluation work is cycle-budgeted: pending new-bar symbols are selected first, deferred cleanly when the cycle budget is exhausted, and only the remaining budget may be spent on intrabar work.
- Startup/runtime symbol-state priming now seeds one pending new-bar evaluation per validated symbol, preventing cold-start idle loops where managers exist but no symbol is ever admitted into the first scan.
- Cadence, stated as it actually is (Batch 212): the consensus entry scan runs once per tick and `CSignalGenerator::EvaluateSymbol` gates **each symbol to one evaluation per bar of the chart's timeframe**. There is no new-bar-only switch - `InpSignalScanOnNewBarOnly` wrote a config field that no code read, and the `[CADENCE-WARNING]` line three documents cited has never existed in the repository. Both are deleted; `EVAL_MODE_INTRABAR` is not passed on the entry path at all, so between-bar consensus *entries* do not happen (see `RUNTIME_DECISION_GRAPH.md`, Batch 212). What is settable now: `InpMaxSignalEvaluationsPerCycle` (the cycle budget the generator used to hardcode at 8), `InpDormancyStrikeBars`, `InpDormancyCooldownMinutes`, reported once by `[SCAN-POLICY]`.
- **Superseded by Batch 215:** this line described `InpMaxIntrabarSymbolsPerCycle` and quoted a default of 4 where the code said 6. The input wrote a config field that no code read, and the scheduler it fed was never instantiated; the input, the field and the scheduler are deleted. Per-cycle evaluation breadth is `InpMaxSignalEvaluationsPerCycle`, live since Batch 212.
- Symbol evaluation start index rotates each cycle to reduce deterministic first-symbol concentration.
- Intrabar symbol selection is yield-aware: recent near-miss symbols, recent generators, and readiness-healthy symbols are prioritized first.
- Per-symbol intrabar backoff tiers escalate from base cadence to `30s`, then `60s`, then suspension until a new bar resets the symbol.

### 4.2 Consensus

Live path is `CConsensusEngine::EvaluateConsensusInternal` (the Two-Tier, probe-only and fallback-solo siblings have no caller).

- `m_src.RefreshMarketRegime()` publishes the per-symbol regime into the signal context first, so AI adaptation and this scan read the same snapshot.
- Per live voter: `GetSignal` once, then `CUnifiedSignalPipeline::ProcessSignal(symbol, tf, rawSignal, confidence)` filters that
  same signal (`[CONSENSUS-FILTERED]`). Before Batch 260 the pipeline re-polled the strategy, so a voter that records its signal on
  emission failed its own cooldown or same-bar guard on the second call and its vote was dropped with a blank `filtered by `. A NONE
  or filtered signal contributes nothing.
- **Vote score** = `stratConf × weight × participation × reliability × regimeCategoryMult`.
  - `weight` is the catalog row's weight, operator-overridden at init (`[CATALOG]`).
  - `participation` = `clamp(0.55, 1.05, 0.40 + 0.65 × participationScore)`; `participationScore` is registered at 0.90 and never updated, so this is a constant 0.985 (recorded in §4.8).
  - `reliability` = `clamp(0.55, 1.15, 0.65 + 0.50 × healthScore)` — live since Batch 199 wrote the contributor list that feeds the health counters.
  - `regimeCategoryMult` comes from the same `CRegimeSnapshot` as the hard gate; invalid snapshots return 0.30 (stand-aside, not a veto).
- **A regime hard veto is not a vote** (Batch 204). `RegimeStateHardGate` returns 0.0 for reversion in `REGIME_TREND` and for trend/momentum in `REGIME_RANGE`; the multiplier is therefore 0 and the strategy is skipped before any accumulation, so it cannot enter the vote count, the contributor array, the ready-ratio denominator, the conflict deadband or the outcome-learning charge. A *deweight* (Breakout reversion 0.25, Chaos 0.40, low confidence 0.55) still votes with a smaller score. `[CONSENSUS-REGIME-VETO]` reports the excluded count and weight once per scan.
- Directional quality per side is the mean of `stratConf × weight` over that side's voters (vetoed strategies excluded by the rule above).
- Gates, in order, each printing `[CONSENSUS-REJECT]` with its own numbers:
  - `readyWeightRatio = (buyScore + sellScore) / votedWeight`, where `votedWeight` sums the weights of the strategies that actually contributed score; compared against `InpConsensusMinReadyWeightRatio` (clamped 0.10–1.00 at `EAOrchestrator.mqh:1791`).
  - Higher score wins; exact tie → `[CONSENSUS-TIE]`.
  - `winningVotes ≥ effectiveMinVoters` where `effectiveMinVoters = max(baseMinQuorum, MIN_CONSENSUS_VOTERS=1)`, deliberately never capped by the eligible count (capping made one lone voter 100% consensus). Batch 283: the constant is 1, so the stored floor is what binds and `InpMinLiveVoters` is the input that moves it.
  - `supportRatio = winningScore / (winningScore + losingScore) ≥ supportFloor` (mode-specific).
  - `quorumRatio = winningVotes / (buyVotes + sellVotes) ≥ buyQuorum/sellQuorum`, each `clamp(0.30, 0.80, baseQuorum ± quality adjustment)`.
  - `conflictRatio = losingVotes / (winningVotes + losingVotes) ≤ InpConsensusConflictDeadband` → `[CONSENSUS-VETOED]`.
  - `winningQuality ≥ effectiveQualityThreshold` = `max(pipeline min confidence, last pipeline effective floor)`.
- `confidence = min(0.95, winningQuality × 0.8 + supportRatio × 0.2)`; `confluence = winningVotes`; class is `SPARSE_INTRABAR` when intrabar and fewer than three eligible live voters, else `FULL_QUORUM`.
- Winning contributor indices are published through `SetLastSignalContributors` with the dominant role, cluster tag and normalized cluster code — the input Batch 199's attribution, `[TRADE-ATTRIBUTION]`, `[RISK-CLUSTER]` governance and `[AUTHORITY-LEARN]` all read.
- The decision context also publishes the winning side's mean pipeline evidence — `convictionScore` (raw `stratConf`), `readinessScore`, `contextScore`, `costScore` — plus `readyLiveWeight` / `totalLiveWeight`, the numerator and denominator of the ready-ratio gate (Batch 205). `CLiveAuthorityResolver` sizes the lot from the first four.
- Mixed-timeframe conflicts are **not** resolved anywhere and never were: the only code that fed that logic,
  `CUnifiedSignalPipeline::ProcessMTFSignals`, had zero callers and went in Batch 260; `CTimeframeConsistency` itself went
  in Batch 261. Post-quorum nullification prints `[CONSENSUS-VETO]` and is a consensus-vote test, not a timeframe
  resolution.
- **Legacy vocabulary still in this file's older notes:** "role multiplier", "dynamic weight decay", "contribution class denominator", and the veto codes `insufficient_quality` / `insufficient_support` / `insufficient_readiness_weight` / `direction_quorum_not_met` describe the Batch 82 implementation and match no code in the repository. The live strings are the `[CONSENSUS-REJECT]` reasons above. `convictionScore`, `readinessScore`, `contextScore`, `costScore`, `readyLiveWeight` and `totalLiveWeight` now have writers (Batch 205: the winning side's mean pipeline evidence, which `CLiveAuthorityResolver`'s lot ladder and the candidate log read); `diversityScore`, `directionalWeight`, `readyCoverage` and `stalenessPenalty` had no reader outside the struct's own copy operations and were deleted in Batch 205.

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
- Startup emits `[TRADE-MGR] Account margin mode: ...` so the account semantics the executor will run under are explicit before the first scan.
- Startup rejects unsupported non-hedging account models before runtime ownership becomes ambiguous.
- Live comment tagging carries compact cluster code (`K:T/R/S/N`) for deterministic open-position cluster attribution.
- Live execution telemetry now includes broker request/fill price, slippage points, and round-trip latency through `[EXECUTION-TELEMETRY]`, `[EXECUTION-RECEIPT]` and `[EXECUTION-SLIPPAGE-EXCESS]`; a refused send is `[EXECUTION-BLOCKED]` and a failed one `[TRADE-ERROR]`.
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

### 4.8 Risk, Cost and Execution Authorities (Batch 168-169)

Ownership and single sources of truth introduced or moved by the live-money audit:

| Domain | Authority | Notes |
|---|---|---|
| Magic-number ownership | `Core/Utils/MagicRange.mqh` (`ConfigureMagicOwnership`/`IsMagicOwned`/`IsMagicOwnershipConfigured`/`ValidateMagicOwnershipCoverage`) | Replaced five disagreeing windows. Configured in `CEAOrchestrator::Initialize` after the symbol universe is known; the asset-class offset span (10000, covering `DERIV_UNKNOWN` = 9999) is asserted at startup. Every close/modify predicate routes through it; fail closed when unconfigured, except loss aggregation which falls back to counting everything. |
| Exit management | `CPositionLifecycleManager::ManagePositions()` via `ManageOpenPositions()` | `CPositionManager`'s exit surface (`ManagePositions`, five `Manage*`, six `Configure*`, `CheckSignalReversalExit`, `SetDailyRiskBudget`, `Initialize`) was deleted in Batch 245: no call on that owner ever reached it. Batch 246 deleted the four satellites only that surface used (`CPositionMgrSRE/Pyramid/DynamicSL/LossGuard`), the class's status report, and its closed-trade tally. What it holds now is the position-state registry and the prediction maps. |
| Position inventory | `PositionsTotal()` filtered by ownership | `CTradeManager::ManageAllPositions` no longer trusts the in-memory ticket cache, which was written only by the synchronous open path. |
| Breaker evaluation | `CUnifiedRiskManager::RefreshRuntimeState()` | Drawdown and daily-loss breakers run continuously, not only when a candidate reaches the pipeline. From Batch 240 the margin ladder runs there too, on its own `MARGIN_HEALTH_POLL_MS` (30 s wall-clock) throttle. |
| Margin-level protection | `CRiskMarginHealth` measures, `CRiskCircuitBreaker` closes | Below 150% the monitor raises the breaker's emergency-close flag and the orchestrator's existing flatten path executes it; below 200% `CUnifiedRiskManager` holds new entries on a flag the same poll releases. The monitor no longer calls `PositionClose()` itself (a second flatten authority) and no longer writes `conservativeMode`, which the tuner cannot clear once set. Before Batch 240 nothing called `MonitorMarginHealth()`, so no tier of it could run. |
| Risk-state persistence | `PersistRiskRuntimeState`/`RestoreRiskRuntimeState` (version:2 state file) | Restore is applied *after* `CUnifiedRiskManager::Initialize`, written on a `GetTickCount()`-based 30 s cadence, and carries halt flags plus the broker trading-day key. |
| Authorised risk ceiling | `CUnifiedRiskManager` envelope (`m_envelope*`) | Captured from config before any compounding tier writes; `ApplyTierOverrides` can only clamp downward. |
| Min-lot round-up ceiling | `MAX_MIN_LOT_RISK_MULTIPLIER` (`Core/Utils/Enums.mqh`), applied by `SOrchestratorConfig::EffectiveMinLotRiskMultiplier()` and again in `CUnifiedRiskManager::Initialize` (Batch 241) | The uplift to `SYMBOL_VOLUME_MIN` multiplies the risk the gate approved, so 3.0 binds in all three lot consumers - sizer, pipeline, candidate builder. Before this batch only the sizer clamped, while the gate and the builder read `InpMinLotRiskMultiplier`, whose shipped default was 15.0. `allowMinLotRoundUp` is likewise enforced by the gate now, not just the sizer. |
| Live risk re-configuration | `CEAOrchestrator::UpdateRiskParametersFromInputs` → tier manager → risk manager → sizer (Batch 241) | Re-runs the initialization order so an operator change reaches every consumer: `SetBaseRiskPerTrade`, `SetTier`, `ApplyToRiskManager`, `ApplyToPositionSizer`, `SetMinLotRoundupPolicy`. `maxRiskPerTrade` previously reached only the `[RISK-INPUT-UPDATE]` print, and `m_config` kept the previous values, so a later reader of the config saw a stale ceiling. |
| Live configuration channel | `CLiveConfigReloader` detects, `CEAOrchestrator::ApplyLiveConfigOverrides` applies (Batch 242) | The reloader owns mtime, throttle and JSON parsing and exposes `ConsumeReloaded()` plus `GetCurrentConfig()`; the owner applies the `risk` section through `UpdateRiskParametersFromInputs`, every key defaulting to the running value so an omitted key cannot zero a ceiling. The `IConfigCallback` seam is deleted: a class declared inside a method cannot reach its owner, so no callback at that seam could have applied a value, and the four registered ones only printed. `weights`, `thresholds`, `symbols`, `ai` and `engines` are report-only until their owners gain live setters. |
| Manual circuit-breaker release | `risk.resetCircuitBreaker` in `Config/live_overrides.json` -> `CUnifiedRiskManager::ResetCircuitBreaker()` (Batch 242) | The only path that answers `[RISK-CIRCUIT-BREAKER] Max recovery attempts reached ... Manual reset required`, whose method had zero callers. Edge-triggered on a false-to-true transition so an unrelated file edit cannot re-arm trading. The two automatic releases stay the normal route: the trading-day counter reset in `UnifiedRiskManager.mqh:709` and 60 stable minutes under half the warning drawdown. |
| Pending-risk lifetime | `CVirtualPositionBook::PruneStale()` - TTL **or** a covering open position (Batch 239) | A reservation is released on every rejection branch and kept on approval; before this batch only the 60 s TTL could end it, while `GetPortfolioRisk()` had begun counting the same trade at the fill, so the daily and portfolio caps priced one position twice. The matcher takes the terminal's own position list as its authority, one position per reservation, `POSITION_MAGIC != 0`. What still ends only on TTL: a candidate approved and never sent. |
| Scalp risk gate count | One `ValidateTradeRequest` per scalp, at the entry stage (Batch 192) | `Execute` used to run the same check again on the already-adjusted lot. Both calls reserved a virtual position that only TTL pruning released (Batch 239 added coverage by the filled position as the second ending), so one trade counted its risk twice against the portfolio and daily-budget gates and filed two approvals. The surviving gate is the one whose request sets `clusterCode`/`strategyRole`/`strategyCluster`, which cluster governance groups on; `FinalizeLotSize` after it can only shrink or refuse. Adoption of `adjustedLotSize` is shrink-only and prints `[SCALP-RISK-ADJUSTED]`. |
| Tier-to-sizer risk | Clamped to the risk manager's approved per-trade risk (Batch 192) | `CPositionSizer::SetParameters` clamps nothing, so a tier writing its raw `riskPerTradeOverride` could exceed the operator envelope that `ApplyTierOverrides` enforces on the risk-manager side; the per-trade cap check then refused entries instead of sizing them, so a tier could look applied while trading nothing. `ApplyTierToPositionSizer` now takes the manager and uses `GetActiveRiskPerTradePercent()`, set from the clamped base risk at `UnifiedRiskManager.mqh:382`. |
| Consensus stop ceiling | `max(0.3% of price, 3 x ATR)` in `CCandidateBuilder::CalculateStops` (Batch 193) | The percentage cap alone pinned every synthetic stop at 1% of price whenever the `max(broker, 3 x spread)` floor rose above it, and `takeProfitPips` was capped by `ceiling x minRR` rather than by the stop actually taken, so `CheckExecutionCost`'s `spread / tp` became `1 / (3 x minRR)` — a constant veto that read like a market measurement. The lot shrinks for a wider stop, so per-trade currency risk is unchanged; when the floor still binds the designed stop, `[CANDIDATE-BUILDER] ... stop pinned to floor` names designed/floor/spread/tp/costRatio. |
| Scalp budget read | Per cycle in `ShouldEnterScalp`, not latched at init (Batch 193) | `m_config.scalpRiskPct` came from the risk tier once in `Initialize`, and a 0% tier also set `maxScalpPositions = 0`, which nothing ever restored (default 3, `FastScalpTypes.mqh:34`). After the tier raised the budget `PassesEntryGates` still refused on `scalpCount >= 0` for the whole session. Refusals now print `[SCALP-GATE]` with used risk, budget, cap and remaining cooldown, throttled to one line per minute **per symbol** (Batch 214: the throttle was one EA-wide `static` slot, so the first symbol refused in a window muted the other twelve). |
| Round-trip cost | `CTradeMgrPricing::GetRoundTripCostPrice` | One definition of cost, used by both the risk money model and the take-profit expectancy gate. |
| Fill-confirmation owner | `CTradeMgrPreflight::FindFreshPositionForSend`'s `expectedCommentPrefix` (Batch 196) | The scan answering "did my failed send nevertheless fill" matched only symbol + side + `IsMagicOwned` + a 30 s window, and magic cannot separate a fast-scalp market order from a consensus entry on the same symbol because `TradeManager.mqh:1267` gives both the same `base + per-symbol offset`. A caller naming a prefix matches only its own positions; naming none (the two consensus sites) matches only positions no engine claims, via `HasEngineComment` over the four prefixes the exit paths already own. `requestedVolume` stays unread: a volume test would break the partial-fill case the helper exists for. |
| Stop feasibility | `CTradeMgrPricing::GetMinimumStopDistance` / `GetBrokerStopLevelDistance` | The former is the sizing floor (broker level, 1.5 spreads, 10 points); the latter is the broker-only term used by the preflight spread-anomaly gate, kept separate because a spread-derived floor is circular there. |
| Consensus voter floor | `MIN_CONSENSUS_VOTERS` in `CConsensusEngine::CalculateEffectiveQuorumParamsInternal` | Policy floor applied at the decision point; the old formula capped the requirement at the number of voters actually eligible. |
| Min-lot risk ceiling | `MAX_MIN_LOT_RISK_MULTIPLIER` in `Core/Risk/PositionSizer.mqh` | Bounds the post-approval round-up; config is clamped to it because the round-up multiplies the risk the gate signed off. |
| Exit authority per book | `IsEngineManagedPosition()` (`Core/Utils/MagicRange.mqh`) + `CPosLifecycleMagicFilter::IsLifecycleManaged` | Engine-stamped send comments (ATR-SCALP / GRID-RECOVERY / SPIKE-HUNT / SCALP\|) are EA-owned but engine-exited; lifecycle stops touching them. Since Batch 197 each engine also ships its own magic band (6000/6100/6200+level/6300), but the comment stays the discriminator because positions opened before the renumber carry a consensus-band magic. |
| Magic layout | `Core/Utils/MagicRange.mqh` band constants, asserted by `[MAGIC-LAYOUT]` at init (Batch 197) | Consensus = `base + assetClassOffset + symbolIndex*100`; engines live in 6000..6399, under the lowest asset offset (7000). A fast scalp used to ship `base + per-symbol offset` through `CTradeManager` - the same number as every symbol in that asset class, whose registration carried the asset offset alone - and the ATR scalp shipped `base + 7000 + symbolIndex`, so no magic-scoped consumer (`UnprotectedPositionTracker`, `BasketEquityStop`, the dedup guard, Batch 196's fill matcher) could tell a scalp from a strategy entry. A composed consensus offset that lands in a band refuses the start rather than merging two books. |
| Contributor context | `CEntStrategySignalContext::SetContributors`, written by `CConsensusEngine::EvaluateConsensusInternal` (Batch 199) | The decision names its voters; attribution is then recorded at execution against the fill's `positionId` (`AttributeExecutedPosition`), and closed-deal feedback filters engine books out by comment tag or magic band before scoring. Before this batch the arrays had readers and no writer, so per-strategy performance, health-derived reliability, performance auto-disable, per-cluster risk governance and `[AUTHORITY-LEARN]` all ran on an empty list. |
| Lifecycle ownership window | `CPositionLifecycleManager::IsEAOwnedMagic` -> `CMagicRange::IsOwned` (Batch 197) | The last class still computing `base + symbolCount*100 + maxClusterCode` (Batch 168 fixed the four siblings). On the default 13-symbol universe the ceiling was `base + 1399` against magics shipped at `base + 7000..9400`, so twelve symbols read as "not ours" and Signal Reversal Exit plus the ranging breakeven path - both gated on `IsPositionLifecycleManaged()` - never ran with their inputs ON. |
| Post-consensus validator arms | `CPostConsensusValidator::SetValidatorConfig`, called per symbol from `InitializeEnterpriseManagerForSymbol` | Before Batch 175 the method existed with no caller anywhere, so OFI confirmation and the VPIN arm ran OFF regardless of `InpEnableOFIProxy` / `InpEnableVPINFilter`, and the quality floors were the constructor's 0.72/0.75 instead of the configured 0.70/0.68. Hard spread cutoff is passed as `max(hardSpreadCutoffPoints, maxEntrySpreadPoints)`: the configured 200-point default is below synthetic-index spreads and would veto the whole synthetic book, the failure the constructor already documented fixing. |
| Conservative-tier safe mode | Tightens existing owners, never a parallel gate | `minVoters` → `SetMinQuorum`/`SetIntrabarMinQuorum`, `minQuorumThreshold` → `SetQuorumThreshold`, `maxSpreadATRRatio` → pipeline `regimeCostGate`, `noStacking` → the builder's per-symbol position cap. All applied after `ApplyQuorumProfile`, all `MathMax`/`MathMin` clamps. `tradeOnlyKillZones` and `avoidNewsEvents` are not enforced and `[INIT] Conservative safe mode ENABLED` says so at startup. |
| Quorum profile precedence | `ApplyQuorumProfile` is the last writer of the four quantities it owns | The profile overwrites `InpMinLiveVoters` / `InpQuorumThreshold` / `InpConsensusSupportFloor*` / `InpIntrabarDynamicQuorumEnabled` with the selected preset (CONSERVATIVE 2 / 0.60 / 0.35+0.30 / ON, BALANCED 1 / 0.50 / 0.25+0.20 / ON, AGGRESSIVE 1 / 0.45 / 0.15+0.10 / OFF), and keeping it last is deliberate: the preset is the policy, and letting one input win would silently overrule AGGRESSIVE's relaxation. `intrabarMinQuorum` is the field it does **not** own, and neither voter count reaches the decision raw: `CConsensusEngine::EnforcedMinVoters` applies `MIN_CONSENSUS_VOTERS` on top — **1 since Batch 273's floor change, not 2** (Batch 283 corrected this line's older claim), so the stored `InpMinLiveVoters` is the binding number and a preset's `minQuorum = 1` does reach the decision when the input says 1. `[ENTERPRISE-CONFIG]` used to print the four inputs as if they were in force; since Batch 227 it reads them back from the manager and `[QUORUM-PRECEDENCE]` prints `input / stored / enforced` once per symbol at init. |
| Build verification | `sync_and_compile.ps1`, one `Result:` line per program | The only acceptable evidence a compile finished. Since Batch 228 a log that never writes its `Result:` line is a failure rather than a zero count, the wait is `-MaxCompileWaitSec` (420 s; `MultiStrategyAutonomousEA.mq5` measures ~252 s), and the script exits 1 on any failure. Before that the harness counted error lines in a partial log, reported `0 errors, 0 warnings` for compiles it had given up on, and its next-iteration worker cleanup deleted the binary being written - two batches shipped against binaries from a previous day. Corollary for the operator: compare the `.ex5` timestamp with your last edit before calling a build deployed. |
| Engine send confirmation | `CTradeMgrPreflight::FindFreshPositionForSend`, called at the four engine send sites (Batch 177) | The engines still send on their own `CTrade`/`MqlTradeRequest` (§3.2 remains unmet by choice: moving the send would recompute the magic and comment identity that positions on a live book are matched by), but a `DONE_PARTIAL` or a dropped response is no longer read as "nothing happened". Grid levels now store the **position** ticket their own close path requires, resolved by magic; `ResultOrder()` is kept only as a logged fallback. |
| Scalp tracker key | Position ticket resolved at entry (Batch 179) | `CFastScalpPositionTracker` is keyed by position ticket, but the synchronous entry registered `CTradeManager::GetLastTicket()` (the order ticket). `SyncScalpPositionTracking` therefore dropped the slot on the next pass, `FreeForTicket` could not select it, fell through to `ReleaseFallback`, and subtracted a full per-trade risk unit while the position stayed open — then re-added the position without consuming anything. Entry resolves the position ticket now, and registers nothing if the position is not visible yet (the sync pass adopts it; the consumed budget stands). |
| Live-authority gate ownership | `CLiveAuthorityResolver` is called from the sizing path, not from its input | `InpEnableLiveAuthorityGate` (default `false` in both `.mq5`) had one consumer: an init print. `Resolve()` and `ScaleLotByLiveAuthority` run for every risk-approved candidate regardless, so `[AUTHORITY-GATE]` prints unconditionally at startup and names the input as unconsulted. The flag is deliberately not a kill switch — a chart holding the saved default would otherwise stop shrinking lots. |
| Risk gate lot | `CCandidateBuilder::BuildCandidate` calls `ValidateTradeRequest` once, at the final lot (Batch 190) | The call used to sit before `CalculatePositionSizeWithRisk` with `tradeReq.lotSize = SYMBOL_VOLUME_MIN`, so portfolio, correlation, daily-budget and margin decisions were made about a 0.01-lot trade and the returned `adjustedLotSize` had no consumer on the consensus path. It is one call, not two: each approval keeps a virtual reservation until its TTL and the tag is microsecond-unique, so a second call would double-count this candidate in the portfolio and daily-budget gates. Refusal prints `[RISK-GATE-REJECT] ... reason=final_lot_validation`, an adopted reduction prints `[RISK-GATE-ADJUST]`, adoption is shrink-only, and a lot that cannot be expressed above the broker minimum is refused rather than rounded up. |
| Validator quality floor | `GetAdaptiveQualityThreshold` scales the configured floor, not the value under test (Batch 190) | It returned `max(0.40, ctx.directionalQuality * 0.9)` (FULL_QUORUM) and `max(0.45, ... * 0.85)` (SPARSE_INTRABAR) and the caller compared that to the same `ctx.directionalQuality`; `0.9*q < q` always, so those classes could only fail below the hard-coded constants and `InpValidatorNewBarMinQuality=0.68` / `InpValidatorIntrabarMinQuality=0.70` were inert for them. Effective floors are now 0.612 / 0.63 / 0.595 and the veto prints `[POST-CONSENSUS-FILTER] filter=quality_gate` with class, quality and threshold. |
| Shared indicator handles | `CIndicatorManager` owns cached handles; strategies clear their field only (Batch 190) | `CMeanReversionStrategy::Cleanup` released the Stochastic handle it took from `GetStochasticHandle`, double-releasing against `DestroyInstance` (AGENTS.md §3.5) and killing it for other holders. Handles created locally with `iATR`/`iBands`/`iMA` (`LiquiditySweepStrategy`, `RangeCompressionBreakout`, `TrendEntryTypes`) are still released by their owner — the distinction is who created the handle. |
| Volume-data capability | `COrchestratorMathEngineHub::HasOnlyTickVolume` | `MqlRates.real_volume` probe; synthetic-index symbols get no OFI/VPIN engines and tick-volume-only symbols are labelled with `[VOLUME-PROXY]`. |

- **The last live journals (17-23 September, UTF-16LE in `MQL5/Logs/`) are the runtime evidence for Batches 168-178** (Batch 179). They confirm the dormant-engine finding (grid/ATR-scalp/spike-hunter appear only as `Initialized` / `PARKED` / `Deinitialized`, `gridsOpened=0`), confirm that no OFI/VPIN/quality/hard-spread veto line ever existed before Batch 175's wiring, and show `[SCALP-ENTRY]` as the only engine traffic. Nothing newer than 23 September exists, so the tags introduced by Batches 173-179 cannot be evidenced from this machine.

- **Three scalp-class engines are enabled by inputs and wired to no tick routine** (Batch 178, verified by call-site diffing): `m_spikeHunter`, `m_gridRecovery` and `m_atrScalping` receive only `Init`/`AddSymbol`/`Deinit` in `EAOrchestrator` (`:1177`, `:1287`, `:1336` each print `PARKED`), while `InpSpikeHunterEnabled` / `InpGridRecoveryEnabled` / `InpATRScalpingEnabled` all default true. They open zero trades. The only engine with a per-cycle driver is `CFastScalpEngine` (`:2640-2646` entry, `:3375-3378` management). Wiring the other three is a strategy-activation decision, not a refactor: it creates exposure on paths that have never traded, so it is left to the operator and `[ENGINE-STATUS]` reports the state at every startup.
- `config.allowSparseIntrabarSingleVoter` / `SetAllowSparseIntrabarSingleVoter` / `IsSparseIntrabarSingleVoterAllowed` — **gone** (Batch 231). It never bypassed the voter floor: one-voter entries were refused by the stored floor (2 at the time), and `SPARSE_INTRABAR` is only the label `ConsensusEngine.mqh:766` puts on a decision that already passed quorum.
- Configuration entry points with no caller anywhere, found by diffing every `Set*/Configure*` in `Core/` against its call sites (Batch 176). None has an operator input behind it, so these are unsettable features rather than misreported inputs — the distinction matters, and each is listed with what actually runs:
  - `CRiskMarginHealth`'s two margin gates (`Core/Risk/RiskMarginHealth.mqh:16/17` fields, read at `:41`/`:49`): the setter pair was deleted in Batch 240 (zero callers, no input feeding it) — **this one gates live money**: the pre-trade margin check runs on the construction defaults 80% free-margin usage and 200% margin level, and its rejection message prints those numbers, so an operator reading a rejection can see the ceiling in force.
  - `CUnifiedRiskManager::SetTradingDayStartHour` (`UnifiedRiskManager.mqh:225`) — the daily risk window rolls at server midnight.
  - `CPositionSizer::SetCorrelationThresholds` — **gone** (Batch 226): it had zero call sites and the three params it wrote were only read by the sizer's unreachable correlation branch, which the same batch deleted.
  - `CRiskTieredCorrelation`'s `m_correlationReduceThreshold` / `m_correlationBlockThreshold` — **gone** (Batch 225): written from config, read by nothing, while `CRiskValidationPipeline::ValidateCorrelationLimits` enforces both tiers from its own copy.
  - `CPositionLifecycleManager::ConfigurePyramiding` / `ConfigureDynamicSL` / `ConfigureLossMinimization` / `ConfigurePartialProfitTaking` (`PositionLifecycleManager.mqh:151/156/161/170`) — the `CPositionManager` twins of these four no longer exist: Batch 245 deleted that class's whole `Configure*` surface, and Batch 246 deleted the satellites those setters used to fill. Loss minimization is settable: Batch 244 wired all six of its numbers to inputs (`InpLossGuard*` in both root EAs) whose defaults are the constructor values, calls `ConfigureLossMinimization` at init behind `[LOSS-GUARD] ... armed=yes|no`, and replaced the startup-only right term of the gate (`m_consecutiveLossLimit(3)`, `PosLifecycleLossGuard.mqh:40`) with an answerable one - so the close at 75% of a position's own SL distance, the 1800 s cooldown after three such closes, and the daily breaker fed by `EAOrchestrator.mqh:1014` are all stated and reachable. `m_adverseMomentumExitEnabled` still defaults off, so `[LOSS-MIN] Adverse momentum exit` prints only if an operator switches it on. Pyramiding, dynamic SL/TP and partial profit taking deliberately keep their `false` and their uncalled setters - inputs for them would launch position layers, moved stops and partial closes nobody asked for.
  - `CPositionLifecycleManager::SetRegimeEngine` (`:184`) — stays NULL, so the ranging-regime branch that pauses trailing (`:372`) never runs and positions are trailed in range like any other regime. The per-symbol regime source is live as of Batch 201 (`GetCurrentMarketRegime()`), but routing needs a symbol-scoped trailing call that `CTradeManager::ManageAllPositions` does not offer. Recorded, not shipped.
  - `CVPINFilter::SetClassificationMode` and its `m_classificationMode` shadow field — **deleted in Batch 176**: `ClassifyTick` reads `m_classifyMode` (set by the constructor), while the init log printed the decorative twin, so the line reported a mode that never affected classification.
- `CStatisticalArbitrageStrategy` abstains (`[STATARB-UNHEDGED]`) because only one leg of a pair signal is executable; `ExecutePairTrade` has no callers.
- **Consensus participation has never adapted** (recorded Batch 200, left alone in 201). `StrategyMgrRoster.mqh:228` registers `participationScore = 0.90` and `RecordSignalGenerated` / `RecordSignalFiltered` have no caller (the health monitor's own `UpdateParticipationScore` ladder was deleted in Batch 251: no caller, and nothing downstream read what it wrote), so `GetStrategyParticipationMultiplier` returns the same `0.40 + 0.65*0.90 = 0.985` for every strategy in every vote: the score formula's adaptive term is a constant haircut. Not wired in 201 on purpose - its targets (1.0 signal / 0.65 filtered / **0.35 none**) with decay 0.85 per call would pin intrinsically low-frequency strategies (`NYOpenGapStrategy`, statistical arbitrage) at the floor and scale their votes to 0.6275, which is a bias the wiring would invent rather than a control it restores.
- **The regime value the AI reads is now written** (Batch 201). `m_currentMarketRegime` had four readers and no writer, so `CAIEngine::AdaptToRegime` took its `default:` branch every cycle and the per-regime confidence factors (0.9 trend / 1.1 range / 1.2 volatile) were never applied. `CEnterpriseStrategyManager::RefreshMarketRegime` maps the live `CRegimeEngine` snapshot - the same source as `GetRegimeCategoryMultiplier` - into `ENUM_MARKET_REGIME` at the top of `EvaluateConsensusInternal` and prints `[MARKET-REGIME]` on each change; an invalid snapshot stays `MARKET_REGIME_UNKNOWN`, which is the honest no-adaptation case. Batch 251 deleted `AdaptToRegime`: it computed its scaled threshold into a local and never wrote it anywhere, so the 0.9 / 1.1 / 1.2 factors applied to no strategy in any build. The publication stays - the consensus regime gate and the `[EXT-LLM]` reasoning prompt read it.
- **`CRiskAdaptiveTuner::m_riskReductionFactor` has readers and no writer, and is left that way on purpose** (found Batch 213). `UnifiedRiskManager::ApplyPnlRiskAdjustment` (:1544, :1570) uses it as the fraction of unrealized profit that frees risk budget, so the credit is the constructor's constant 0.5 forever - including while `[RISK-BUDGET-PNL-ADJUSTED] ... factor=0.5` prints as if it were adaptive. `UpdateAdaptiveRiskLevel` does compute a `reductionFactor` (<=0.35 at critical drawdown, <=0.65 at warning, <=0.60 conservative) and applies it to `targetRisk` only. The two numbers are different quantities that happen to move the same way, so storing one into the other would give a single field two meanings - the shape Batch 203 refused for the neural-net labels. Fixing this needs the operator to say what the profit credit should do in drawdown.
- **The compounding tier ladder is not monotone, and the number is an operator decision** (flagged Batch 213, not changed). Tier 4 ($500-1,000) risks 1.5% per trade and tier 5 ($1,000-5,000) risks **5.0%** - a 3.3x jump at $1,000 - with an inline comment on the tier-5 line reading "5% risk per trade for <$1K equity", which is tier 1's number in the wrong band. Batch 192's clamp caps the applied value at the approved per-trade risk, so the live effect is "full ceiling from $1,000 up" rather than 5%. What that band *should* risk is a decision about how a growing account behaves; guessing it would silently change the sizing character of every trade above $1,000.
- **Two sizing modifier duplications, told apart in Batch 213.** `CPositionSizer::Initialize` registered a `CADXLotModifier` unconditionally while the orchestrator added its own configured instance to the same chain, so ADX tiers multiplied twice (1.69x / 2.25x) - the sizer's copy is deleted. Its `m_equityCurveModifier` looks similar but is registered only `if(m_params.useEquityCurveScaling)` and has its own reader at `PositionSizer.mqh:483`, so it stayed: a conditional feature with a consumer, not a duplicate.
- **Volatility targeting is measured every bar and applied to nothing** (Batch 217, reported not wired). Two
  independent implementations exist and neither reaches a lot. `InpEnableVolTargeting` / `InpTargetVol` /
  `InpVolMinScale` / `InpVolMaxScale` build one `CVolatilityTargeting` per symbol in the math hub, `Update()`-d
  every cycle (`OrchestratorMathEngineHub.mqh:297`), producing an EWMA vol, a percentile and a clamped scalar -
  and all five getters (`GetVolScalar`, `GetScaledSize`, `GetRealizedVol`, `GetEwmaVol`, `GetVolPercentile`) have
  zero call sites. Inside the sizer, `CVolatilityTargetingModifier` is registered only
  `if(m_params.useVolatilityTargeting)`, a field set `false` in `SPositionSizingParams`' constructor and assigned
  from nothing in the tree, so `CalculateVolatilityTargetSize` has always fallen through to
  `CalculateFixedRiskSize`. The two also disagree on the ceiling: modifier 0.25-2.0 with a hard-coded 0.15 target,
  engine the operator's 0.2-3.0. Wiring either as configured would **widen** risk: 0.15 annual against typical FX
  daily ATR (~8-13% annualised) is a scalar near 1.5, and `InpVolMaxScale` defaults to 3.0. What is wanted is a
  target vol and a decision about whether a scaler may exceed 1.0 - the operator's call, not a default's. Now
  stated at runtime: `[SIZING-CHAIN] ... vol_targeting=inert(...)` and `[VOL-TARGET] ... applied=no(no sizing
  consumer)`.
- **`CScalpSignalCache::SetPeriods` deleted instead of wired** (Batch 216). It was the only way to change the
  cache's EMA/ATR/RSI periods, and `SScalpConfig`'s are separate literals assigned at
  `EAOrchestrator.mqh:1266` (5/13/14/7). The cache and the config agree today only because neither can move;
  calling the setter would let the fast path and the slow path evaluate different EMAs on the same symbol. If
  those periods ever become operator inputs, one source must feed both paths.
- **`CScalpVolatilityBreakout` is a complete strategy that is not in the build** (recorded Batch 216, not
  activated). `Core/Scalp/ScalpVolatilityBreakout.mqh` is 233 lines of `CStrategyBase` subclass - squeeze
  detection, BB breakout, bar-body filter, RSI confirmation - and nothing `#include`s it: no catalog row, no
  `SI_*` slot, no `InpEnable*` input, no `factoryName`, so it compiles into no program. Its two documented
  siblings (`CScalpMomentumStrategy`, `CScalpSpreadStrategy`) have no file at all. Kept because activation is a
  strategy decision that opens exposure on a path that has never traded; enabling it takes a catalog row, an
  enable slot and a registration, and that is the operator's call, exactly as with the three parked engines above.
- **The ranging-regime trailing pause is still unwired, and why.** `CPositionLifecycleManager::m_regimeEngine` is NULL (`SetRegimeEngine` has no caller), so the branch at `PositionLifecycleManager.mqh:370` never runs. The per-symbol regime source now exists (`GetManagerForSymbol(symbol).GetCurrentMarketRegime()`), but `CTradeManager::ManageAllPositions` walks the whole book with no symbol filter, so ranging symbols cannot be routed to the breakeven-only branch without changing the exit authority's API. Not attempted without an attach to verify it against live positions.
- **Three phantom strategy slots deleted** (Batch 207). `SI_UNIFIED_ICT` / `SI_UNICORN_MODEL` / `SI_POWER_OF_THREE` and their `STRATEGY_*` type values had no catalog row and no class: the type values appeared only as unreachable `case` labels in `GetRegimeCategoryMultiplier`, and the three `InpIntrabarEligibility*` inputs wrote `strategyTimeframeConfigs[3]/[5]/[6]`, slots no row's `siPolicyIndex` selects - so `CatalogPolicySlot` never returned them and the inputs bound nothing. Enum values were not renumbered. `SI_EXIT_OPTIMIZER` was listed here as surviving; Batch 209 deleted the *slot* after grepping it down to its own declaration and one unread flag-array write - `CExitOptimizer` itself is untouched and still gated by `InpEnableExitOptimizer` through `config.enableExitOptimizer` at the hub's per-symbol engine creation, because it is a math engine and never a consensus voter. Batch 262 deleted the input, the field and both construction sites; the class file stays, unreferenced.
- **`COrchestratorIntrabarPolicy::GetIntrabarPolicy` has no caller** (recorded while Batch 209 removed its only cross-space flag read). It takes a *policy* slot and looks that number up in the *enable-flag* array, which would mix the two index spaces the way the `[CURATION]` cast did; the live path is `CIntrabarPolicy::GetIntrabarPolicyHelper(pIdx)`, which reads configured policy and nothing else. Its `EAOrchestrator` wrapper is equally uncalled. Left in place rather than deleted because it is a plausible future per-symbol policy resolver, and its sibling `GetStrategyTimeframeConfig` wrapper is in the same state.
- **Every ATR this EA measures is taken on the chart's timeframe** (recorded by Batch 206, not fixed). `CPostConsensusValidator::GetATRDirect` calls `Period()`, `CalculateStops` passes `PERIOD_CURRENT`, and both resolve identically because `EAOrchestrator.mqh:1768` initializes each per-symbol manager with `manager.Initialize(symbol, (ENUM_TIMEFRAMES)Period(), ...)`. So the ATR-ratio crisis veto, the `atr_ratio > 1.5` lot halving, the spread/ATR veto and the volatility-sized stop apply to all thirteen symbols on the timeframe of whichever chart the EA sits on, while the strategies that voted carry their own catalog timeframes (`GetStrategyTimeframe(i)`). The correction is a per-symbol operating timeframe - which of a symbol's timeframes counts as its trading timeframe is a policy decision the operator owns, and guessing it on a live book is how a sizing path silently changes character.
- **The min-R:R floor no longer caps the target** (Batch 206). `CalculateStops` clamps the stop and then sets `takeProfitPips = MathMax(proposedTP, stopLossPips * minRR)`. As `MathMin` it turned the minimum R:R requirement into a maximum take-profit, cutting every wider strategy target down to the floor and simultaneously raising the `spread / TP` ratio `CheckExecutionCost` refuses on. Stop distance, lot size and per-trade risk are untouched.
- **The authority lot ladder reads measured values** (Batch 205). `CLiveAuthorityResolver::Resolve` awards `+0.08 / +0.07 / +0.05 / +0.05` for `convictionScore`, `readinessScore`, `contextScore` and `costScore` and turns `authorityScore` into the risk multiplier rung. All four arrived as `0.0` from `SConsensusDecisionContext`, which never wrote them, so no consensus trade in the repository's history earned that `0.25` and `InpAuthorityMinReadinessScore` / `InpAuthorityMinContextScore` / `InpAuthorityMinCostScore` bound nothing. The consensus loop now captures each voter's `SPipelineEvidenceSnapshot` after its `ProcessSignal` and publishes the winning side's mean; `pipeline == NULL` leaves them at zero (no measurement, no bonus) rather than inventing a neutral value. Earned measurement bonuses now appear in `reasons` as `QUALITY CONVICTION READINESS CONTEXT COST`. **Corrected by Batch 258:** with a pipeline present but its engine registry unbound (the shipped default until `InpPipelineEngineRegistry` is switched on), the snapshot is *not* zero - it holds its own defaults, and the 2026-10-23 journal shows `READINESS CONTEXT COST` credited on them, so that row's "earned" reading only holds for a bound registry. Crediting requires a measurement is task #114, a tightening that shrinks live lots.
- **A regime hard veto now removes the vote** (Batch 204). `RegimeStateHardGate`'s `0.0` used to zero only the score: the strategy still counted in `buyVotes`/`sellVotes`, entered `winningContributors`, kept its weight in the ready-ratio denominator and could oppose through the conflict deadband. One veto loosened the min-voter, quorum and conflict gates while tightening the weight gate, and charged the outcome to a strategy the regime forbade. The skip is provably restricted to the hard gate: `RegimeComposite.mqh:246-250` clamps every category weight to `>= 0.01` and the chaos/low-confidence factors are `0.30`/`0.55`, so no deweight can reach zero.
- **Trade-linked neural-net labels are connected** (Batch 203). Reserve immediately before the send, bind at execution through `UpsertPredictionPositionMap(positionId, predictionId)`, accumulate realized profit+swap+commission at close, drain in `ProcessClosedPositionsForNNTraining` which now *consumes* each row it reads. The id is resolved from the position map, not the position comment: a closed position is not selectable, and the previous comment read returned an empty id for every row, which is why the whole loop was inert even after its writers arrived. Only a candidate whose contributor list names the neural net may take a label (`ContributorsIncludeNeuralNet`), and `ReleaseNeuralNetPrediction` un-tags a reservation whose send produced no position.
- **Realized P&L is still not a training target, on purpose** (Batch 203). `UpdateTradeResultByPredictionId` tags the barrier entry and counts a win; the meta-labeler keeps the barrier's directional outcome as its sample. Switching the meta target to profitability is the textbook meta-labeling move, but the existing dataset would then mix semantics mid-stream - old samples "direction was right", new ones "trade paid" - and that transition window is invisible on a live account. Operator decision, with journals.
- **`m_tradeLinkedLabels` can double-count one winning trade**: once when the result lands on an unresolved barrier entry, once in `AddTrainingExample` when that entry resolves. Counter's only consumers are a `>= 5` readiness guard and the checkpoint summary, so it is recorded rather than patched.
- **Deleted in Batch 200 as unreachable rather than unwired**: the closed-trade attribution API (`PopClosedTradeAttribution` and its three backing fields plus both forwarders), `UpdateRegimePerformance` in `CEnterpriseStrategyManager`/`CStrategyPerformanceHealth` (the `CStrategyHealthMonitor` overload of that name is live), `CPortfolioRiskManager`'s event cache hooks and the private mutators only they called (portfolio risk is and was a full scan on the 60s interval), `CTradeExecutor::ExecuteBatch`, `FeedMicrostructureEngines` (a never-called copy of the live `OnTick` VPIN/OFI + Skew Step feed), `ReenableONNXAI`/`CONNXInitManager::Reset`, `GetTotalGridRisk`, `m_preRetrainTimestamp`, `ApplyStrategyWeights`, and `CDiagnosticsManager`'s NN-health check, no-signal-rate getters, duplicate `UpdateTradingPaused` and `m_lastNNHealthLogTime`.

- **The validator quality floor is not a confidence bar, and making it one would tighten admission** (found
  Batch 220, not changed). `buyDirectionalQuality = sum(voter confidence x registration weight) / buyVotes`
  (`ConsensusEngine.mqh:588-591` accumulate and `:615-619` divide) divides by the *vote count*, not the summed weight, so on the default roster
  (weights 1.0 Momentum to 2.0 Volatility Breakout, mean about 1.5) the metric runs ~1.5x the committee's mean
  confidence: `InpValidatorNewBarMinQuality = 0.68`, discounted to 0.612 for a full quorum, is in practice a
  ~0.41 mean-confidence bar. `confidence = min(0.95, quality x 0.8 + support x 0.2)` inherits the same inflation,
  which is why it sits at its 0.95 ceiling for high-weight committees. Dividing by the summed weight makes both
  numbers dimensionally honest and raises the bar everywhere - an operator policy decision, not a cleanup. What
  shipped is visibility: a `filter=quality_gate` refusal now prints `conviction=` (the unweighted mean
  confidence) beside `quality=`, and the gap between them is the weight inflation.

- **A collaborator list is only honest if every entry is read** (Batch 229). `CRiskValidationPipeline` was
  handed eleven pointers and stored one - `CRiskAdaptiveTuner*` - that no line in the class reads, and its own
  comment said so while `IsWired()` gated the ten that were read and skipped the eleventh: the class's only
  liveness probe agreed with the dead member. Field, initialiser, parameter, assignment, the argument at the
  single call site and the include are gone. The tuner stays exactly as alive as it was - `CUnifiedRiskManager`
  reads it at fourteen sites (six each for active risk and conservative mode) including the factor behind
  `ApplyPnlRiskAdjustment` - this removed a second reader, not a control.

- **A dead path is proved by its inputs, not its caller** (Batch 230). The solo-voter fallback had no call site,
  and on top of that the four `SStrategyEntry` fields its ranking formula read - `participation`,
  `readinessScore`, `contextScore`, `costScore`, under a comment saying the pipeline populated them - had no
  writer anywhere. So it was not a control waiting to be connected; connected as written, it would have scored
  every candidate 0.0 and refused everything, quietly. 242 lines and six reader-only accessors deleted. The live
  readers of those three quantities are `SPipelineEvidence` -> `SConsensusDecisionContext` (Batch 205), which is
  what sizes a trade.

- **A citation is part of the argument, not decoration** (Batch 236). Thirty pointers in the five current-state docs
  could not reach what they named - blank lines, lone braces, a line past a 196-line file, and `EAOrchestrator.mq5`, a
  file that has never existed - because Batches 215-231 deleted thousands of lines and re-pointed only what their own
  edits broke. Two of the sentences they anchored turned out to be claims rather than pointers: both said the
  live-authority multiplier reaches nothing, which Batch 205 ended. Re-reading a claim to fix its pointer is how that
  class of staleness surfaces, and it is why section 8 makes re-pointing part of the moving batch. Same batch deleted the
  last field that the re-read exposed: `STradeCandidate::liveAuthorityRiskMult`, two writers and no reader, while the
  lot is sized by the parameter `ScaleLotByLiveAuthority` receives and the log line by `liveAuthorityReason`.

- **A count measured before the loop is not a bound on the loop** (Batch 237). `GenerateAndProcessSignals` reads
  `GetEAPositionCount()` once, folds it into one `canOpenNewTrades` bool, and re-tests that bool at every send - so the
  total-position ceiling bounded the *start* of a cycle, not its output, and one cycle could order all 13 slots against
  a book measured at 14/15. `InpMaxTradeSendsPerCycle` named the missing bound and had no reader anywhere. The fix is
  an in-cycle tally tested per slot, with the send budget decremented only by a fill. Where the test goes matters: an
  approved candidate keeps a virtual portfolio reservation whose owner tag embeds `GetMicrosecondCount()`, so a slot
  validated and then held reserves risk that no release call can reach for the reservation's whole 60 s TTL.

- **A protective class can be complete, compilable and unreachable** (Batch 237). `CSyntheticSpikeMonitor` had the
  pause primitives its consumers read (`IsPaused` feeds the `[ENTRY-GATE]` term and `[HEARTBEAT] pause_active=`) and
  the detection code that raises them, but the only entry point to the detection - `ProcessTickSafety` - had no caller,
  so the three spike inputs bound nothing, `spike_events=` was a constant zero, and both of its alarm paths would have
  closed positions from a second place, beside `CRiskCircuitBreaker`'s halt. Rebuilt as per-symbol M1 tick-volume
  windows driven from `OnTick` and the 1 s timer, alarm holds entries only; the flatten loops and their
  `Alert()`/`Comment()` affordances are gone. Its counting method was also wrong before it was unreachable: it counted
  its own calls, which is the chart symbol's tick callback, not the market - and for a chart attached to EURUSD, nothing.

- **A validator can police values that gate nothing and still own the gate on startup** (Batch 238). The dual-mode
  `[VALIDATION]` block compared four inputs whose config fields had no reader and set `valid = false`, which aborts
  `OnInit`, while the feature it was checking was a two-line stub whose body said "not implemented". Deleting dead
  inputs therefore has a live effect even where no trade path reads them: it removes a way for the EA to refuse to start
  over a comparison that describes nothing. Delete-vs-wire still turned on one authority per domain - the base per-trade
  risk is `InpMaxRiskPerTrade` through `CRiskAdaptiveTuner`, which only scales it down, and the conservative flag is a
  two-of-five trigger vote - so a conservative/aggressive *pair* of base risks was a second authority, not a missing
  feature.

- **An input's default can be recording what the build does rather than prescribing it** (Batch 238).
  `InpEnableNNAttributionDiagnostics = false` read like an off switch, but its setter had no caller, so the struct
  default (`true`) is what every build printed and the `[NN-DIAG]` shutdown summary was live. Wiring the setter at that
  `false` would have deleted the line - the same "made invisible by a wiring fix" trap Batch 233 records. The default
  moved to `true`, so the wiring is behaviour-preserving and the switch is real in both directions. Corollary: a dead
  setter's field default is the running value, and the input is the lie; and a dead control's *implementation* may be
  sound (the NN self-test round-trips the prediction id through the trade comment and the map Batch 203 made
  load-bearing) which is the argument for wiring it rather than deleting it.

- **A write-only table keeps only what a future decision needs** (Batch 234). The per-strategy timeframe table
  (`SStrategyTimeframeConfig`, 23 slots) is read by nothing - `GetStrategyTimeframeConfig` has no caller on either
  owner - so `InpMomentumScalpTimeframe` and `InpCandlestickIntrabarTimeframe` are stored and never consulted, and
  every strategy runs the chart timeframe its catalog row carries (`PERIOD_CURRENT`). What stayed is the carrier for
  the per-strategy timeframe decision; what went is what could never be part of it: `intrabarEnabled` (a bool
  restating the policy enum's fact, 20 writes and no reader), `GetStrategyIntrabarPolicyConfig` on both owners (no
  caller; `GetIntrabarPolicyHelper` is the live per-slot reader), and config slot 20 still named "Exit Optimizer" for
  a strategy Batch 207 deleted. `GetIntrabarPolicyHelper` is called with `CatalogPolicySlot(i)`, which names 14 of the
  19 written rows; rows 9-13 (the five AI adapters) carry `siPolicyIndex = -1` and register a `fixedPolicy`, so their
  stored policy has no consumer - kept because those strategies exist and the table is the timeframe carrier.
  `[ENTERPRISE]` now prints `strategyTF=chart(...) | momentumScalpTF=...(stored,
  unconsulted) candlestickTF=...(stored,unconsulted)` so the mismatch is visible at init rather than inferred from a
  dialog.

- **A forwarder is not a caller, and a report with no entry point starves its own readers** (Batch 250). With the
  orchestrator status chain gone (Batch 247), nine manager/reporter chains had no occurrence outside their own two files,
  and the state only they read - total and successful signal counters, `m_avgConfidence`, and `StrategyEntry::avgConfidence` -
  had no remaining consumer or no writer at all. Deleted with them: five by-name governance chains, the four
  participation-formula setters (read live by consensus, never written, so constructor constants), `EnableStrategy` /
  `DisableStrategy` (the only printers of `[EnterpriseStrategyManager] Strategy ENABLED:` / `DISABLED:`), `IsStrategyLiveVoter`
  on both owners, and six forwarders each shadowing a live method its own satellite calls by name. Recorded rather than
  fixed: `GetEnsembleConfidence()` averages a field nobody writes, so it is structurally 0.0 - and its readers sit behind
  `CAIEngine::OnAIQuery`, which has no caller either. Batch 251 deleted the island, the reporter method, both forwarders
  and `StrategyEntry::avgConfidence` with it, so the question is closed by removal rather than by a writer.
- **A gate that was always true makes the code below it dead** (Batch 252). `CConsensusWeightingConfig::UpdateStrategyWeights`
  begins `if(healthMonitor != NULL) { ...; return; }`, and `CEnterpriseStrategyManager`'s constructor allocates the monitor
  unconditionally, so the win-rate weight-scaling loop underneath it had never run in any build. It is deleted, not wired:
  `recentWinRate` registers at `0.0` and is rewritten only on a closed trade, so `scale = 0.75 + (0 - 0.50)` would clamp to
  the 0.50 floor and halve the vote of every strategy that had not traded yet, and the AI rows would be scaled by the model
  accuracy that `UpdateAIPerformanceMetrics` stores in that same field. Weight adaptation that actually runs is one thing:
  the AI profitability multiplier, 0.8x..1.2x, printing `[AI-WEIGHT-ADJUST]`. `SStrategyHealthEntry::currentWeight` /
  `originalWeight`, `UpdateAllStrategyWeights`, the monitor's three weight accessors and `StrategyEntry::originalWeight`
  went with it, leaving `StrategyEntry::weight` as the single weight consensus reads.
- **A silent early return is indistinguishable from an empty market** (Batch 253). The scan entry point's algo-trading guard
  printed nothing, so a blocked account produced the same journal as a quiet one, and `[ENTRY-GATE]` - the tag that exists to
  explain a held book - sits below it. The rule generalises: any `return` that ends a whole decision cycle needs a name, a
  reason and a throttle, because the alternative reading is a conclusion about the market. `[HEARTBEAT] scans=` not growing
  is the secondary tell, since the counter sits below the same return.
- **A threshold compared against an integer ratio has a floor of 1/N** (Batch 253). `conflictRatio` is losingVotes/votesCast,
  so no scan can express a conflict finer than one dissenter; an asked deadband below `1/N` is not a tight tolerance, it is a
  unanimity requirement, and it fails silently because the veto looks like a market statement. Floored at runtime
  (`ConsensusEngine.mqh:737-750`) with `[CONSENSUS-DEADBAND-FLOORED]` naming both numbers, `[CONSENSUS-QUORUM] finestDissent=`
  warning at scan time, and `[VALIDATION] WARNING` at init.
- **Telemetry ownership: one counter, one event, one writer** (Batch 253). `CHeartbeatTelemetry` went 18 fields -> 7, each with
  exactly one call site, because a stage that no line increments is not a low reading and every `[CONVERSION-RATES]` percentage
  divides by a stage; and two stages incremented in the same statement, so a `100.0%` conversion between them was arithmetic
  dressed as a rate. `signals_sent` is the fill count (`if(execResult.executed)`), which is why there is no separate
  trades-opened field. `CDiagnosticsManager::UpdateCounters` mirrors the same seven arguments - the mirror is the reason eleven
  dead fields survived: the print path read the mirror, not the writer.
- **A subsystem's reported path is a claim** (Batch 253). `CStructuredLogger::Init` printed a `MQL5\Logs\...` path while
  `FileOpen` wrote the basename into `MQL5\Files\`; the sink had 635 events and every reader who followed the log line concluded
  it had never run. Same batch deleted 18 methods on that class whose only two occurrences were a declaration and a definition -
  including `IsEnabled()`, whose six apparent external callers were `CJsonLogger::IsEnabled()` on a different class.
- **Two call sites for one event is a doubled sample, not a redundancy** (Batch 255). `CStrategyMgrTradeFeedback` called
  `CEnterpriseStrategyManager::UpdatePerformance` (which forwards to `CStrategyHealthMonitor::RecordTradeResult`) and then
  called `RecordTradeResult` again on the next statement. Rates survived it - `winRate` doubled numerator and denominator -
  but every *count* behind a threshold doubled: the `consecutiveLosses >= 5` park fired after three real losses and the
  20-trade rolling window held ten real trades. Same rule as Batch 239's reservation double-count, applied to the governance
  sample: ask what the completing event is, then count the call sites that deliver it.
- **A fallback under an always-true guard is a second holder that never receives writes** (Batch 255). Six methods in
  `CStrategyPerformanceHealth` and one in `CStrategyLifecycle` begin `if(m_src.GetHealthMonitor() != NULL) { ...; return; }`,
  and the manager's constructor allocates the monitor, so the fallbacks had never run - and the roster fields they alone
  wrote (`winRate`, `profitFactor`, `sharpeRatio`, `recentWinRate`, the `recentTrades[20]` ring) were therefore never written
  at all, while the monitor held the live copy of the same numbers. Deleting a caller makes its callees write-only (Batch 250);
  an always-taken branch makes the *other* holder dark in exactly the same way. Prove the guard's truth once (constructor, or
  `new` + NULL check) and the whole subtree below it falls out as one unit.
- **A getter with no writer behind it is a constant wearing a measurement's name** (Batch 255). `SStrategyHealthEntry::sharpeRatio`
  had no writer anywhere in the tree, so `GetSharpeRatio` returned `0.0` and the caller that used it as the strategy's risk-adjusted
  return was reading a constructor value. `StrategyEntry::participationScore` is the recorded sibling: registered at `0.90`, read
  live by consensus (`ConsensusEngine.mqh:290`), and the fallback at `:292` is also `0.90` - so the per-strategy participation term
  has been one constant for every strategy. Recorded, not fixed: making it real is vote arithmetic.

- **The AI query surface was an entry point nobody had** (Batch 251). `CAIEngine::OnAIQuery` has no call in any `.mq5`
  or `.mqh`, and neither did the free `InitializeAIEngine`/`CleanupAIEngine` pair or the `g_AIEngine` global that were the
  only other way in - so 24 unreachable methods (five `Process*Query`, `AI_ModifyWeights`, `AI_ExplainDecision`,
  `AI_AdaptiveMode`, `SynthesizeSignals`, `GenerateTradeExplanation`, `AssessRisk`, `ProvideFeedback`, five getters,
  seven `Set/Is` and name helpers, and the single-manager `Initialize` overload)
  and the ten members they alone wrote or read (`m_queryCount`, `m_successfulQueries`, `m_pendingMods`,
  `m_recentDecisions`, `m_predictionAccuracy` and friends) were a second, unreachable copy of the Batch 246/247 shape.
  Deleting them retired two claims the docs had carried as live: the `[AIEngine] shutdown - Queries: n, Accuracy: x%`
  line, whose numbers could only ever be 0 and 50.00%, and `[AI-ENGINE] Clearing accumulated modifications`, whose counter
  had no writer. `AdaptToPerformance`'s disable/re-enable pair went for the same reason (accuracy is a constant 0.5 with
  nothing able to change it); the live governance sweep at `EAOrchestrator.mqh:3101-3114` is what actually parks and
  restores strategies. What is left of `CAIEngine` is 404 lines: `Initialize`, `ProcessAdaptation`, `SetExternalAIEndpoint`
  and the external-LLM reasoning path that applies weights by name. `StrategyEntry::avgConfidence` had no writer and its
  only readers were in the island, so the field, the roster getter, both forwarders and `GetEnsembleConfidence` went with
  it; `GetStrategyWeightsJSON` stayed because `MaybeCaptureExternalReasoning` feeds it to the LLM on a live path.
  File sizes: `AIEngine.mqh` 1095 -> 404, `StrategyHealthMonitor.mqh` 454 -> 383, `StrategyStateReporter.mqh`
  254 -> 230, `EnterpriseStrategyManager.mqh` 1173 -> 1165, `StrategyMgrRoster.mqh` 302 -> 299,
  `EntStrategyTypes.mqh` 142 -> 141. 9 added / 810 deleted across seven files.
- **A bound table is only bound where a reader exists** (Batch 249). Batch 234 kept the per-strategy timeframe table as
  the carrier for a future decision; the decision landed, and what made it small was not the binding but the read set:
  `StrategyEntry::timeframe` already had three live consumers (`ConsensusEngine.mqh:542`, `StrategyLifecycle.mqh:154`,
  `EnterpriseStrategyManager.mqh:975`) and `CStrategyRegistryState::RegisterStrategy` already resolved
  `PERIOD_CURRENT -> m_baseTimeframe` at `:90`, so feeding the row value into `RegisterStrategy` was one argument, not a
  new mechanism. `SStrategyTimeframeConfig` is now `ENUM_TIMEFRAMES strategyTimeframes[23]` - `name`, `intrabarTF` and
  `forceHigherOnM1Synthetic` (21 writes, 0 readers each) are gone, and the third was a second holder of the band rule
  `SimpleMomentumStrategy.mqh:513` enforces. Two rows can name a timeframe, so two strategies move; the other 19 slots
  keep `PERIOD_CURRENT` and resolve to the chart exactly as before.
- **A field no branch reads must announce itself** (Batch 233). The eleven `InpIntrabarEligibility*` inputs still
  write a per-strategy intrabar policy, and after Batch 231 the only reader left is the registration print: the entry
  path passes `EVAL_MODE_NEW_BAR` (`EAOrchestrator.mqh:3507`/`:3573`, `SignalGenerator.mqh:109` says so outright), and
  the one live `EVAL_MODE_INTRABAR` caller is the reversal-exit check (`PositionLifecycleManager.mqh:261`), whose voter
  set is enabled + `liveVotingEnabled` + the regime veto - never the policy. Making it binding is one line and the
  *restrictive* direction, because eight indicator rows carry `defaultPolicy = INTRABAR_POLICY_OFF` with no input at
  all (`StrategyConfigBuilder.mqh` slots 14-22), so enforcement would drop them from the reversal vote. Held as an
  operator decision; shipped instead is `[INTRABAR-POLICY] <symbol> | stored LIVE= | other= | applied=no(...) |
  rows_not_LIVE=` from the roster, and the per-row field relabelled `Intrabar(report-only):`. The point is the
  journal's grammar: a line that reads `OFF` where no gate exists is evidence for a conclusion the runtime never draws.

- **A derived mirror needs a reader or it goes** (Batch 232). `StrategyEntry::intrabarEligible` was
  `intrabarPolicy == INTRABAR_POLICY_LIVE` stored as a second boolean: written at registration and by the by-name
  policy setter, read by nothing once the unreachable policy-resolution copies died in Batch 231. Deleted with its
  getter, setter, forwarder and both writes, and with `SetStrategyIntrabarPolicyByName` /
  `...EligibilityByName` on both owners - a declared, defined, forwarded chain with no caller, since the live write
  path is positional (`SetStrategyIntrabarPolicyConfig` from the `StrategyConfigBuilder` rows). What the sweep
  exposed and deliberately left alone: the stored `intrabarPolicy` is now read only by the strategy report's
  `Intrabar:` field, `GetStrategyIntrabarPolicyConfig` has no caller, and
  `SStrategyTimeframeConfig::intrabarEnabled` is written 20 times and read nowhere - so the eleven
  `InpIntrabarEligibility*` inputs gate no entry, and enforcing the stored policy would strip eight catalog rows
  whose `defaultPolicy` is hardcoded `INTRABAR_POLICY_OFF` from sub-bar voting. Restriction is operator policy
  (Batch 233); the one authority that remains is `intrabarPolicy`, the integer.

- **A reader is not reachability** (Batch 231, and the correction of Batch 230's own note). The probe path was
  recorded as live because its getters had readers; the readers were inside
  `EvaluateConsensusProbeOnlyInternal`, which no code can enter, and whose eligibility test read
  `SStrategyEntry.isProbeEligible` - a field with no writer in the tree. So `probeEligibleCount` was always zero
  and the gate could have admitted nothing. Same finding for `EvaluateConsensusTwoTier` (a wrapper around the live
  evaluator, unreachable), four sibling `GetConsensusSignal*` forwarders, ten engine/policy helpers whose only two
  occurrences are a declaration and a definition, `m_adxHandleCached` (written only by a dead ADX test, so never
  valid, "released" twice at deinit anyway), and a seven-input chain - `InpAllowSparseIntrabarSingleVoter`,
  `InpSparseIntrabarMin*`, `InpIntrabarSingleVoterMinConfidence`, `InpSyntheticLean*` - through config fields,
  resolvers, setters and quorum storage. 706 lines deleted. The single live consensus entry point is
  `GetConsensusSignalForSymbolWithConfluenceMode`; `INTRABAR_POLICY_PROBE` survives as an operator-selectable
  value that `COrchestratorIntrabarPolicy::GetIntrabarPolicy` upgrades to `LIVE` on synthetic-lean rosters. The
  method this batch changes: an "is it wired" claim needs a caller chain to an entry point, not a reader.

- **A comment that miscounts a machine-read layout is a defect** (Batch 229). `MetaLabeler::BuildInput` fills
  `[0]`..`[25]` into an array `AI_MLP_INPUT` sizes at 26, and its header said "24 features"; a
  `WalkForwardValidator.mqh` header named a consumer that does not include it. Both corrected during the sweep
  that removed 90 comment lines and cut runs of 8+ from 17 to 1 (the survivor is that 26-slot layout, which is
  the net's input contract). Length reduction is where these were found; the finding is the point.

- **One authority per risk means one *reachable* authority** (Batch 226). `CPositionSizer` held a complete
  second correlation reduction behind a flag no writer ever set true. It was deleted rather than enabled:
  the pipeline's REDUCE tier already scales the lot and, since Batch 224, every book adopts that result -
  switching the sizer's copy on would have multiplied two shrink factors against one lot, which is the
  Batch 213 double-ADX defect in a different class. The general test applied here: a dormant duplicate of a
  live control is not a spare, it is a future double-application, so it goes.
- **A limit that can act must name its own measurement** (Batch 226). The asset-class drawdown ceiling
  compares an account-wide peak drawdown with a per-class limit and can halt a symbol because of losses on
  another. That is the design in `SAssetProfile`, so the numbers stay; what changed is that the refusal now
  prints both quantities and says which is account-wide, so the policy is readable in the journal instead of
  inferable from silence.

- **An input either reaches the gate or it goes** (Batch 225). `InpAIStandaloneRelaxedConfidence` fed a log
  line while the resolver tested its own configured floor; `InpPortfolioMaxPositionsPerSymbol` and
  `CRiskTieredCorrelation`'s reduce/block copies were state that existed so a control could look configured.
  The relaxed floor is now handed to the resolver per symbol per scan, and the three unread holders are
  deleted rather than documented as dead. `AGENTS.md` section 4.4's warning - a factory path can still contain
  configuration that no longer runs - is the reason each input gets checked to its consuming comparison, not
  just to its assignment.

- **A governance bucket must contain what its name says** (Batch 224). `DERIV_UNKNOWN` is the fallback for
  "this symbol is not a Deriv synthetic", and the per-family position cap counted it as a family, so the
  entire non-Deriv half of the universe shared one limit that no input names. Same test applied to the risk
  answers: three engine books consumed `.approved` and discarded `.adjustedLotSize`/`.riskPercent`, and
  printed a refusal reason from a field no writer in `Core/Risk/` ever assigns. Ownership of the position
  comment (Batch 196/197) and of magic bands (`CPositionLifecycleManager::IsEAOwnedMagic`) stays where it is:
  reading the cluster out of the comment would put a second owner authority in the risk pipeline, and the
  limitation is documented instead.

- **A limit must be able to refuse** (Batch 223). Three risk ceilings were written so their own arithmetic
  made the refusing branch unreachable: a round-up ceiling compared against a ratio bounded below 1.0, a
  daily-risk projection compared against the value the getter clamps to that same limit, and per-cluster caps
  stored as absolute percents that replaced the operator's configured ceiling instead of scaling it. Where a
  designed behaviour was unreachable but *reaching* it would change risk in a direction the operator has not
  chosen (margin-health floors, the CVaR tail cap), the constant stays and the code says so; where the
  operator already configured the number and the code silently overrode it, the code now obeys it and prints
  what it applied.

- **Consensus gates must be reachable to count as policy** (Batch 222). Three admission gates on the
  consensus path were arithmetic dead ends rather than market tests: the conflict deadband (`0.05`) sat below
  the smallest dissent an integer committee can produce (`1/19`), so unanimity was required; the ready-weight
  floor (`0.40`) sat above the ceiling the `0.30` regime stand-aside allows (`0.362`), and the snapshot that
  stand-aside reads had as its only writer an optional pipeline filter; the ATR crisis branch returned the
  caller's "pass" value after setting its own veto flag. Deadband default and accepted range now match the
  value the quorum config class was audited to (`0.35`, range `[0.05, 0.50]`), the manager refreshes the
  regime snapshot when nobody else has, and the crisis veto returns `false`. `supportFloor` is left inert and
  labelled so in `[CONSENSUS-QUORUM]`: the winner's share of votes cast is always above 0.50, so binding it
  would mean a different denominator and fewer trades - operator policy, recorded with the arithmetic like
  the Batch 220 quality scale and the Batch 217 vol target.

- **Module headers state ownership, not inventory** (Batch 221). The satellites of
  `EnterpriseStrategyManager.mqh` and the engine coordinators now carry a header of 3-7 lines: which object
  holds which (by value or by non-const back-pointer), the index lifetimes, the include-order constraint that
  keeps `SPositionState` visible, and the specific reason a piece of logic could not move with its neighbours
  (the consensus core reads the mirrored quorum fields directly). Member lists, module maps that duplicate the
  `#include` block, parameter glossaries and the repeated include caveat are gone.

- **`Core/Utils/LogMacros.mqh` is now only the heartbeat block** (Batch 218). It declared 42 macros and 37
  had no call site: ten duplicated tags the code prints literally, eleven `LOG_JSON_*`/`LOG_PERFORMANCE`/
  `GENERATE_CORR_ID` wrappers, seven named a tag with no emitter and no payload (`[CONSENSUS-ROOT]`,
  `[CONSENSUS-STRATEGY]`, `[CONSENSUS-ROLE]`, `[CONSENSUS-CLUSTER]`, `[FAMILY-WEIGHT-VOL]`, `[NN-HEALTH]`,
  `[AI-VOTE-MISSING]`). The eight heartbeat macros that remained were the unused half of a split-brain
  emission: `CDiagMgrHeartbeat` computed the values and passed them to `CJsonLogger` only, so from Batch 218
  they print to the journal as well. `[AI-VOTE-MISSING]` was left unprinted on purpose - staleness is per
  symbol per adapter type, so a journal line would emit up to 52 per minute on a fully-stale AI setup.
  A tag list is a search index: `changelogs.md` Batch 218 records the ~250 document lines corrected against
  the tree, including two sections that named classes this repository does not contain.

## 5. Data and Control Boundaries

### 5.1 What can veto a trade

- Validator failure.
- Unified risk rejection.
- Consensus admitting fewer than `MIN_CONSENSUS_VOTERS` agreeing voters.
- Strategy confirmer with unavailable indicator data (fail closed since Batch 169 — a missing handle or short copy is a veto, not a pass).
- Execution preflight (market closed, stale tick, quote anomaly, spread anomaly, entry drift).
- Stop feasibility: a broker-forced SL widening beyond `MAX_ACCEPTABLE_STOP_WIDENING_RATIO` of the sized distance, or a take-profit under `MIN_TP_COST_MULTIPLE` times the round-trip spread cost.
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
- Magic ownership authority (Batch 168): `CMagicRange` / `IsMagicOwned()` — the only predicate that decides whether a position belongs to the EA; superseded per-module windows that disagreed by up to 9400 points. Batch 197 added the owner bands inside that window (fast scalp 6000 / ATR scalp 6100 / grid 6200+level / spike 6300, all under the lowest asset offset), the `[MAGIC-LAYOUT]` init assertion, and removed the last stale window (`CPositionLifecycleManager`). `CMagicNumberAllocator` was deleted in Batch 197: a parallel family-offset table with no call site whose adoption would renumber every open position.
- Grid level state authority (Batch 197): `CGridRecoveryLevels::RebuildLevelsFromPositions` via `CGridRecoveryEngine::RecoverOpenGridLevels()` at init — level slots are recovered from open positions (magic decodes the level, comment `GRID-RECOVERY` claims the book, legacy 8000-band magics decode by `%100`), so a restart no longer leaves the grid's own positions unmanaged while it lays a fresh level 0.
- Authorised-risk authority (Batch 169): `CUnifiedRiskManager` configured envelope — compounding tiers may reduce, never raise, per-trade/daily/portfolio/drawdown limits
- Transaction-cost authority (Batch 169): `CTradeMgrPricing::GetRoundTripCostPrice()` — one spread-cost definition for both risk math and the entry expectancy gate

## 6. Runtime Modes

### 6.1 Shadow mode

- Full stack decisioning, no live order send.
- Used for burn-in and diagnostics.

### 6.2 Live mode

- Full stack decisioning with real execution.
- Requires extra monitoring window post-activation.

## 7. Observability Model

### 7.1 Key log families

- Decision heartbeat: `[HEARTBEAT]`, `[HEARTBEAT-POSITIONS]`, `[HEARTBEAT-ASSET-CLASS]`, `[HEARTBEAT-FAMILY]`
- Startup state: `[SYMBOL-UNIVERSE]`, `[ENTERPRISE-CONFIG]`, `[RISK-UNIFIED] Initialized`, `[TRADE-MGR] Account margin mode`
- Conversion funnel: `[HEARTBEAT-FUNNEL]`, `[CONVERSION-RATES]`
- Entry suppression: `[CONSENSUS-VETOED]`, `[CONSENSUS-REGIME-VETO]`, `[CONSENSUS-ABSTAIN]`
- Risk budget split: `[RISK-BUDGET]`
- Positions the EA did not open: `[RISK-UNPROTECTED]`
- Consensus diagnostics: `[CONSENSUS-QUORUM]`, `[CONSENSUS-DIAG]` (strategy-side only since Batch 256), `[CONSENSUS-DECISION]`; `[CONSENSUS-SNAPSHOT]` had no emitter and is deleted
- Governance diagnostics: `[ROLE-CLUSTER]` had no emitter and is deleted (Batch 256); `[CONSENSUS-ROLE]` and `[CONSENSUS-CLUSTER]` were format-macro names with no call site and are deleted (Batch 218)
- Strategy reject attribution: `[STRATEGY-REJECTS]` had no emitter and is deleted (Batch 256)
- Signal rejection reasons: `[SIGNAL-REJECTED]`
- Scan cadence budget: `[SCAN-POLICY]` at init, `[SCAN-BUDGET]` per cycle
- Threshold source tracing: `[PIPELINE-THRESHOLD]` (DEBUG) - cannot print while the pipeline registry is unbound (Batch 258)
- Regime/cost viability tracing: `[REGIME-STATE]`, `[COST-GATE]`, `[ENTRY-VETO]`, `[TrendEngine][READINESS-FAULT]` - the first three need the engine registry, so they print only with `InpPipelineEngineRegistry=true`
- No-vote telemetry now preserves aggregate readiness/context/cost from the ready live pool, and `[COST-GATE]` prints both spread/ATR ratio and raw spread - while the registry is unbound those three evidence values stay at their defaults (`contextScore` 0.5, `costScore` 0.72 written before the NULL return, readiness from `warmupScore` 0.58), and Batch 258 proved each default already clears its floor (0.48 / 0.50 / 0.52), so the three bonuses are *paid* on unmeasured constants rather than unearnable
- No-signal deadlock alerting: `[NO-SIGNAL-ALERT]`
- Cluster risk governance tracing: `[RISK-CLUSTER]`, `[RISK-CLUSTER-CAP]`, `[RISK-MUTEX-BLOCK]`, `[RISK-FAMILY-POS]`
- Virtual reservation tracing: `[RISK-VIRTUAL]`
- AI liveness: `[AI-VOTE]` (a stale adapter is a `AIVoteMissing` record in the JSON log, not a journal line)
- Confirmed deals: `[EXECUTION-CONFIRMED]`, `[EXECUTION-CONFIRMED-BY-POSITION]`, `[ASYNC-TRADE-CONFIRMED]`
- Authority gate actions: `[AUTHORITY-REJECT]` / `[AUTHORITY-REDUCED]`
- Execution outcomes: `[EXECUTION-RECEIPT]`, `[EXECUTION-TELEMETRY]`, `[EXECUTION-BLOCKED]`, `[PARTIAL-FILL]`, `[TRADE-ERROR]`, `[TRADE-FAILED]`
- Python bridge health: `[PYTHON-BRIDGE-DASHBOARD]`
- Scalp cost viability: `[SCALP-COST-REJECTED]` / `[SCALP-COST-OK]`, signal refusals `[SCALP-SIGNAL-REJECT]`
- Spike hunting (engine parked, Batch 178): `[SPIKE-HUNT-DETECT]`, `[SPIKE-HUNT-TRADE]`, `[SPIKE-HUNT-SKIP]`, `[SPIKE-HUNT-ALERT]`, `[SPIKE-HUNT-ALERT-THROTTLED]`, `[SPIKE-PAUSE]`, `[SPIKE-HUNT-ENGINE]`

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

## 15. 2026-08-06 Phase 6-7 Execution Flow Optimization + File Hygiene

- `CPythonBridge` gained three private JSON parsing helpers (`ParseJsonDouble`, `ParseJsonString`, `ParseJsonInteger`) that eliminate 18+ duplicated field-extraction patterns across `ParsePredictionResponse`, `GetPairCorrelation`, `FindBestCorrelatedPair`, and `ParseVersionResponse`. The helpers take a key name and handle the find/extract/parse cycle generically.
- `CEnsembleAIStrategyAdapter` TODO comments resolved — `TrainStep()` and `OnRegimeChange()` documented as intentional no-ops due to parameter mismatch between the adapter interface and `CEnsembleMetaLearner`'s method signatures.
- `SignalValidator.mqh` confirmed already merged into `EnterpriseStrategyManager.mqh` — post-consensus validation (spread/ATR/OFI/VPIN checks) runs within `GetConsensusSignalForSymbolWithConfluenceMode()`.
- `IRegistry.mqh` provides template-based `CRegistryBase<T>` with full Get/Register/Unregister/Has/Count/Clear implementation. None of the 6 concrete registries currently inherit from it — all are too specialized (multi-pointer slots, scalar state, create-on-demand logic).
- `Core/Position/PositionManager.mqh` is the sole position manager (not a duplicate of a non-existent `Core/Trading/PositionManager.mqh`). Actively included by 4 files via `../Position/PositionManager.mqh`.
- Dashboard `App.tsx` now imports real page components from `./pages/` instead of rendering inline "Coming Soon" stubs for all 8 routes.

## 16. 2026-08-06 Phase 6.2 + 7.4 — Position Sizing Consolidation + Error Logging

- `UnifiedRiskManager.mqh` no longer carries a redundant `<minLot` validation branch (formerly ~22 lines) that hard-coded `if(riskRatio <= 15.0)` with no config binding. The lot-size gate is now `if(request.lotSize > maxLot)` using `SYMBOL_VOLUME_MAX`. `CPositionSizer` remains the single authority for min-lot round-up.
- Min-lot round-up tolerance is restored to 15x (reverted the L5-002 1x clamp) in three places: URM config default `minLotRiskMultiplier = 15.0`, `CPositionSizer` hard cap `if(riskRatio > 15.0)`, and the `SetMinLotRiskMultiplier` setter clamp `MathMin(MathMax(1.0, multiplier), 15.0)`.
- EA inputs `InpAllowMinLotRoundUp = true` and `InpMinLotRiskMultiplier = 15.0` expose the round-up policy to the user.
- 38 `PrintFormat("[DBG-RET0] ...")` debug statements were added to ambiguous `return 0.0` paths across `UnifiedRiskManager.mqh` (16), `TradeManager.mqh` (14), `PositionSizer.mqh` (5), and `PythonBridge.mqh` (3). Logging only — no runtime behavior change. Documented valid returns (hedging-mode path, already-braced inline early-exits) were skipped.

