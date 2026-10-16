# MetaTrader Multi-Strategy Autonomous EA

![Status](https://img.shields.io/badge/status-production-blue)
![Batch](https://img.shields.io/badge/batch-140-green)
![Platform](https://img.shields.io/badge/platform-MetaTrader%205-orange)
![Strategies](https://img.shields.io/badge/strategies-20-purple)
![Academic Rigor](https://img.shields.io/badge/academic_rigor-validated-brightgreen)

## Overview

**MultiStrategyAutonomousEA** is an autonomous multi-strategy trading system for MetaTrader 5 that combines 20 strategy modules across three tiers (Institutional, Structure, Indicator) through a weighted consensus voting mechanism. Built for serious traders who need enterprise-grade signal validation before any order touches the broker.

The system covers **Forex, Metals, Indices, Energies, and 18 Deriv synthetic index families** with per-asset-class optimization — automatically detecting instrument types and applying tailored risk parameters, lot scaling, and strategy weights. AI modes (Indicator Only, AI Only, Hybrid) let operators control the blend of human-designed strategies and machine-learned predictions.

Designed for production: every trade entry passes through a multi-layer pre-trade gate (risk, correlation, portfolio exposure, spread, session, regime) before reaching centralized execution. No single strategy can bypass the unified risk authority.

**Academic Rigor (Batch 122):** Complete modular architecture migration with 6 registries and 8 orchestration modules. All critical bugs fixed — magic number overflow protection, PERIOD_CURRENT misuse in ATR calculations (4 locations), memory leaks in strategy registration (20+ allocation paths), MQL5 API error handling, and resource cleanup verification. ~2,000 lines of dead code removed from main EA. System compiles with 0 errors, 11 warnings (style only).

**Phase 4 Observability (Batch 123):** Structured JSON logging with correlation IDs, PERIOD_CURRENT audit complete (all indicator calls validated), CIndicatorManager FindHandle paramCount fix, unit test scaffolding for core math modules.

**Layer 2 Initialization & Lifecycle Audit (Batch 126):** Two-phase enterprise manager initialization documented, verbose diagnostics gated behind log levels via LOG_IF macro, pipeline dependencies documented for InpUseSignalPipeline.

**Layer 4 Signal Pipeline & Filtering (Batch 129):** Complete audit of signal pipeline and filtering layer — all 15 issues from `layer_4.md` resolved. Key improvements: configurable filter chain with early-exit, intrabar-aware cache invalidation, quality score weight normalization, grouped SignalFilterSettings with Validate/ApplyPreset, readiness score component weights made configurable, ADX handle race condition fixed, swing detection real-time support, NONE signal handling in weighted MTF resolution, regime snapshot reuse with transition validation, log throttling, duplicate ATR calculation eliminated.

**Layer 6 Strategy Implementation Logic (Batch 130):** Complete resolution of all 4 remaining issues from `layer_6.md`:
- **L6-007 MEDIUM**: Intrabar policy PROBE mode wired through EA inputs → SOrchestratorConfig → AutoRegisterStrategies. Strategies 15-16 (NY Open Gap, Asian Range Break) now use configured intrabar policies.
- **L6-008 MEDIUM**: Participation score update logic implemented. ConsensusEngine now calls `UpdateParticipationScore(strategyIndex, signalType)` for all strategies (signal=1, filtered=0, none=-1), feeding into weight adaptation via health monitor.
- **L6-013 LOW**: `GetQuickProbeSignal()` removed from IStrategy interface and all 5 implementations (MeanReversion, SimpleMomentum, StatisticalArbitrage, Candlestick, VolatilityBreakout). Two-tier consensus path was unused; removal simplifies LSP contract.
- **L6-016 LOW**: AIPerformanceFeedback integrated with EnterpriseStrategyManager weight adaptation. AI metrics (accuracy, profitability, recent accuracy) now update strategy health scores and apply profitability multipliers for AI strategies (Neural Network, Transformer, Ensemble, ONNX).

**Layer 12 Main EA Entrypoint Flow Audit (Batch 139):** All 18 issues from `AUDIT_Layer12_MainEAEntryFlow.md` resolved. Key fixes: SymbolScanScheduler intrabar scoring temporal mismatch corrected (state now updated AFTER consensus); ManageAllPositions optimized with EA-owned position ticket cache (O(1) vs O(n)); ProcessTradingLogic decomposed into 7 focused methods; OnTimer processes async confirmations; crash recovery state atomic write without FILE_COMMON; heartbeat deltas via snapshots; CIndicatorManager::DestroyInstance() and OnChartEvent verified.

**Phase 4-5 Strategy Debloat (Batch 140):** Strategy duplication consolidated into `CStrategyBase` (reject logging, new-bar refresh, risk-validation helper, consensus-diag logging) — ~260 lines of duplicated boilerplate removed across strategy files. God object `EAOrchestrator.mqh` decomposed: `SOrchestratorConfig` extracted to `OrchestratorConfig.mqh` (710 lines) and `InitializeStrategyConfigs` extracted to `StrategyConfigBuilder.mqh` (249 lines), reducing EAOrchestrator from 5,529 → 4,571 lines (17.3% smaller). No runtime behavior change — pure structural refactoring. Compiles with 0 errors, 0 warnings.

**Hostile Audit Remediation (Batch 150):** Full-stack audit (risk / orchestration / indicators / execution) with live-correctness fixes: wrong-symbol signal-result indexing in `CSignalGenerator` (results now stored by manager slot); per-symbol bar-gated NEW_BAR evaluation ending the 30-minute dormancy blackout; `ProcessNewBars` rewired off the always-NULL `GetScanScheduler()` so `OnNewBar`, consensus-cache invalidation, and AI adaptation actually run; EA-owned position cache fixed to store position tickets (BE/trailing were dead); TIMEOUT/CONNECTION retcodes removed from the order-retry set (duplicate-order vector); partial-profit rule once-per-ticket (was liquidating 25%/tick); portfolio-risk double division removed (cap was disarmed ~100x); pipeline approval booked once + pip-convention unified after correlation lot reduction; async crash ledger appends instead of truncating; static-array `CopyBuffer` time-order fixed in Momentum/MeanRev/VolBreakout/Trend; per-tick JSON logging removed, scalp fast path throttled to 1s. Compiles 0 errors / 0 warnings.

**Deferred-Findings Remediation (Batch 151):** Implements the confirmed-but-deferred list from Batch 150. Virtual reservations now actually book (the zero-risk placeholder was silently rejected by the reservation book, leaving the post-approval budget window and opposing-direction guard dead); win/loss stats record again (`UpdatePerformanceMetrics` no longer dead-selects the closed position); IOC/FOK fill decision is honored instead of being overwritten by `SetTypeFillingBySymbol`; portfolio risk cache no longer rescans every call while an SL-less position exists; CVaR equity-buffer internals corrected and the veto wired live (minute-gated equity feed in `RefreshRuntimeState` + pre-approval pipeline gate, arming after 20 samples; `[RISK-GATE-REJECT] reason=cvar_tail_risk` on breach); day-rollover halt-reset can no longer steal the daily-reset event from `CheckAndResetDailyLimits`; per-symbol position caps armed via `CCandidateBuilder::Configure` (were 0 = bypassed) and hybrid-gate relaxation no longer double-counts cycles; Liquidity Sweep / Range Compression catalog rows de-cross-wired (17/18 -> 18/19); decorative SignalGenerator throttles removed; ~1,300-line dead `RiskValidationGate.mqh` + zero-caller `TimerProcessor`/`TickProcessor`/`BarProcessor` deleted; anti-martingale drawdown scaler un-noop'd (peak now the real equity high-water mark, not equity-vs-equity). Compiles 0 errors / 0 warnings.

**Full Audit Closure (Batch 152):** Closes the complete finding lists from all four audit domains — every ID fixed or explicitly dispositioned. **Two live-behavior changes:** (1) pip-geometry correction in `CPositionSizer::CalculateRiskPerLot` (the ×10 pip factor removed) means fixed-risk lots move ~10x TOWARD configured risk — expect visibly larger lots on first post-deploy trades, verified against configured risk%, not the old undersized baseline; (2) explicit magic overrides now ship as-is through `CTradeManager` (`m_pendingExplicitMagic`), so SpikeHunter's absolute magics land inside the EA-owned range again instead of double-offsetting out of it. Also: async path enforces the mandatory-SL gate (`[EXECUTION-BLOCKED] reason=MandatoryStopLoss | path=async`); manual-close restore gate uses `IsEAOwnedMagic()` (was arithmetic that never matched); scalp fast path refreshes its cache and runs full management per tick with deal-confirm handoff from `OnTradeTransaction`; ATR-scalp partial-profit is ticket-latched (one per lifetime); live-authority policy actually configures the resolver gates; ADX modifier no longer releases shared `CIndicatorManager` handles; volatility-target sizing anchors ATR to D1 (was chart-TF-dependent, ~5x lot error on H1); symbol win-rate/profit-factor memoized behind a 60s TTL (full-history scans were running per symbol per budget refresh); conservative-mode flag ownership moved to the circuit breaker; correlation candidate queries pin symbols against mid-query prune; tier preset no longer zeroes `maxRiskPerTradeOverride`; hedging margin recalculation fails closed; all 36 leftover `[DBG-RET0]` prints stripped. Dormant suites dispositioned in SYSTEM_AUDIT_TRACE.md (margin monitor unwired by authority design; FullMargin/SafeMode tier-conditional; D-01..D-08 documented-dormant). Compiles 0 errors / 0 warnings.

**Hygiene Closure (Batch 153):** Dead-code removal plus three small repairs found inside the hygiene list — no trading-logic changes, but two log surfaces become truthful. Deleted: `CErrorHandling` wrapper class, five dead `CPositionManager`/StateStore position-state methods (+ their StateStore counterparts), and two dead `CSignalGenerator` methods — all zero-caller chains verified by repo-wide sweeps. Fixed: `[HEARTBEAT]` funnel counters had **zero writers**, so `scans=`, `no_signal=` and `validator_reject=` printed 0 forever and the status report's `Scans=` field was permanently 0 — the scan loop now feeds them (prior all-zero baselines are NOT expected values); trade attribution stored the whole contributor CSV as one malformed name instead of splitting it (`SplitContributors` now used, so attribution rows carry individual contributors); init-failure cleanup covered only registry/AI/bridges — a late init failure (e.g. dependency-validation abort) leaked EA-owned sizing modifiers with live indicator handles, math engines, neural nets, drawing managers and engine state; `CleanupOnInitFailure` now mirrors `Shutdown()`'s release sequence. Investigated but deliberately NOT changed (product decision pending): the strategy performance feedback loop (`CEnterpriseStrategyManager::OnTradeTransaction`, `CPerformanceAnalytics::RecordClosedTrade`, loss-guard trade accounting) is unwired end-to-end — every consumer treats "no data" as neutral, so nothing learns from closed trades until wiring is approved; see SYSTEM_AUDIT_TRACE.md Batch 153 entry. Compiles 0 errors / 0 warnings (all 7 root EAs).

**Product Decisions Executed (Batch 154):** The closed-trade feedback loop is now **live** — the EA learns from every fully-closed EA-owned trade. Per-strategy attribution/health/auto-disable runs (`[EnterpriseManager] Trade Closed`, `[Enterprise-Adaptation] DISABLED/RE-ENABLED`; a strategy below its win-rate floor or over the consecutive-loss limit stops voting for a 1-hour cooldown); account analytics accrue again so the momentum lot-scale and URM risk snapshots move off permanent defaults as samples grow; loss-guard consecutive-loss accounting feeds `[LOSS-MIN]` cooldowns; and executed AI-contributed trades record outcomes into the live-authority resolver (`[AUTHORITY-LEARN]`) so AI candidates can promote from the bootstrap cap to PROVEN_AI ≥0.75× risk after 30 tracked trades with positive expectancy — evidence-based promotion, cap unchanged for unproven AI. Two prerequisite defects fixed in the same pass: the re-enable predicate demanded post-disable wins from strategies that cannot trade (permanent-death trap — cooldown-served recovery plus rolling-sample reset replaces it), and disable/re-enable sweeps ran only under AI mode with good prediction accuracy (now an orchestrator-owned 60s governance sweep). Parked by decision: SpikeHunter/GridRecovery/ATRScalping stay unwired but their init logs now state it explicitly (`PARKED: not wired into the tick loop`), and the VPIN/institutional layer stays documented-dormant. Compiles 0 errors / 0 warnings (all 7 root EAs).

**Strategies Signal-Suppression Audit (Batch 155):** Dedicated emission-path audit of every registered strategy; only defect-level suppressors were repaired — quorum, risk gates and quality floors untouched. Biggest finds: **VolatilityBreakout's ADX-rising filter was inverted** (it required ADX *falling*, rejecting nearly every breakout); **StrategyTrend's entire EMA engine ran on data from nine bars ago** (static arrays filled oldest-first, read as if newest — crosses/slope/alignment all stale); SimpleMomentum had five reversed buffer reads plus an FX-scale ATR floor that blocked M1 FX while permanently taxing synthetic confidence ~40% (now price-relative); MeanReversion's RSI-only and BB-touch entry classes could never clear their own confidence floor (rebased, hierarchy preserved) and its divergence filter rejected healthy fades at random; RangeCompression evaluated its own forming bar and its fade branch was always killed by the trend filter (closed-bar reads; filter now momentum-only); AsianRangeBreak compared a 6-hour M5 range against a per-bar chart-TF ATR (never passed on M1/M5 — sqrt-of-time scaling fixes it on all TFs) and demanded exact-midnight M5 bars (one missing bar killed the day); Statistical Arbitrage was registered-but-permanently-mute because no catalog-path injector ever handed it the Python bridge (now wired in the orchestrator dependency pass); LiquiditySweep daily-high/low sweeps maxed out under the confidence floor (level bonus added) and placed stops half-way inside the already-traded sweep wick (now beyond the extreme); NYOpenGap/AsianRangeBreak synthetic skips extended from 4 Deriv families to all of them. Structural scarcity by design (Turtle Soup / Breaker Block conjunctive entries, FVG strongest-zone selection) is documented, deliberately not loosened. Compiles 0 errors / 0 warnings (all 7 root EAs).

**Detector-Layer Deep Audit (Batch 156):** went below the strategies into the detector/analyzer helpers that feed their votes, hunting the same defect classes. Anchor-chronology bugs fixed: TrendlineDetector's pair loops skipped every candidate pair (its `p1` was always the NEWER swing while requiring it older — zero trendlines were ever built) and its pip-based slope angle saturated past the ±70° gate on synthetics; AdvancedOrderBlocks' Source-OB walk kept the OLDEST opposite candle in a 20-bar window instead of the one adjacent to the impulse start (zones mis-anchored every scan). Forming-bar evaluation removed from every path that latches permanent state: SR bounce/trendline rejection candles, breakout detection (an intrabar transient used to permanently consume a level; tolerance also gets a scale-free floor), OB mitigation, FVG rebalance, session-gap fill status and structure-break classification — tradeable sets and structure flags no longer flip tick-by-tick into strategy confluence bonuses. Starved paths restored: external swing liquidity emits sell-side pools again (a shared slot budget let highs consume all ten), Break-of-Market-Structure works on H2–H12 charts (enum-range gap left them BMS_NONE forever), session-gap detection fails closed without ATR instead of manufacturing phantom gaps from a 5-point fallback, pin bars with near-zero bodies qualify again, and Shooting Star vs Inverted Hammer is decided by prior-trend context with dominant-wick scoring. Scale/correctness: engulfing tolerance uses the analyzed symbol's point+ATR (was chart `_Point`), OB key-level checks ATR-floored (20 points ≈ 0.2 absolute on synthetics = permanently false), candle-pattern confidence now blends strength/confluence 50/50 instead of multiplying two sub-1 factors into floor-hugging values, SL padding scales with ATR. Shared-feed safety: ADXPositionSizing no longer releases the indicator manager's shared ADX handle (re-init permanently killed the whole Trend stack's ADX feed), and TrendTrailingStop ignores unwarmed EMA/ATR feeds so TRAIL_HYBRID can no longer emit a near-zero stop for sells. Compiles 0 errors / 0 warnings (all 7 root EAs).

**Scout-Findings Sweep Closure (Batch 157):** sorted every remaining sub-agent finding, not just the headline defects. Fixed: equal-highs/lows detection was effectively dead outside FX (`equalTolerancePips` multiplied by raw POINT — now floored at 0.2bp of price at all three sites); sweep-confidence penetration depth saturated instantly on synthetics (normalized by the sweep bar's range); the psychological-level strength bonus could never apply to non-FX digits (magnitude-based round grid added); breaker-block candidacy admitted the forming bar; vacuum order blocks demanded <30% average volume on a huge-range bar — a practically unreachable contradiction (now <65%, reachable but selective); three fast structure detectors judged the forming bar so FVGScalper/AsianRangeBreak confidence bonuses flip-flopped tick-by-tick (closed bars now); iATR create/release churn in AdvancedOrderBlocks and SessionGapDetector replaced with shared indicator-manager handles; and sell-side trailing extremes track ASK instead of BID (spread no longer understates adverse excursion). Re-adjudicated with evidence, unchanged: the reported min-lot clamp-up defect does not exist (all sites are standard broker-min baselines); the roleReversed-set-on-copy lines are harmless no-ops because HasRoleReversed latches internally — its real bug was a 10-point match tolerance that never fired on synthetics (now 1bp-of-price floored). Compiles 0 errors / 0 warnings (all 7 root EAs).

**Full per-file ledger of the entire audit campaign** (every repair, defect class, and adjudicated-not-changed item across Batches 155–157): [`docs/SIGNAL_SUPPRESSION_AUDIT_B155-B157.md`](docs/SIGNAL_SUPPRESSION_AUDIT_B155-B157.md).

## Key Features

- **Multi-Strategy Consensus** — 20 strategy modules vote through weighted quorum; no single strategy can unilaterally enter a trade
- **3-Tier Signal Architecture** — Institutional (ICT/SMC), Structure (S/R, Trend), and Indicator (Momentum, Candlestick, MA) tiers with configurable weights
- **AI Integration** — 4 AI adapters (Neural Network, Transformer, Ensemble, ONNX) with Indicator Only / AI Only / Hybrid modes
- **Multi-Asset Class Profiling** — Auto-detection and per-class parameterization for Forex, Metals, Indices, Energies, and 18 Deriv synthetics
- **Multi-Layer Risk Authority** — Pre-trade gating covering per-trade, daily, portfolio, correlation, drawdown, and position limits
- **Deriv Synthetic Support** — Family-specific engines: Spike Hunter, Grid Recovery, ATR Scalping for Crash/Boom, Volatility, Step, Jump, and 14 more families
- **Compounding Tiers** — Auto-tier switching at $25/$50/$100/$500 milestones with risk/drawdown scaling
- **Session-Aware Sizing** — Asian/London/NY/Weekend session multipliers
- **Mathematical Engines** — Hurst Exponent, VPIN Toxicity, Ornstein-Uhlenbeck, Order Flow Imbalance
- **Quantitative Position Sizing** — Kelly Criterion, equity compounding, correlation-adjusted sizing
- **Python ML Bridge** — ZMQ/HTTP bridge to Python-trained CatBoost/XGBoost/LightGBM ensemble with per-asset-class models
- **Visual Dashboard** — Real-time chart overlay showing regime, consensus, risk budget, and position status
- **Modular Architecture (Batch 122)** — 8 orchestration modules + 6 registries replacing monolithic EA with clear ownership boundaries

## Architecture Overview

```
┌─────────────┐    ┌──────────────┐    ┌─────────────┐    ┌──────────────┐    ┌─────────────┐
│  Strategies  │───▶│   Pipeline   │───▶│  Consensus  │───▶│  Risk Gate   │───▶│  Execution  │
│  (15 modules)│    │  (Regime,    │    │  (Weighted  │    │  (Multi-layer│    │  (TradeMgr) │
│  3 tiers     │    │   Cost,      │    │   quorum    │    │   pre-trade  │    │             │
│              │    │   Filter)    │    │   voting)   │    │   validation)│    │             │
└─────────────┘    └──────────────┘    └─────────────┘    └──────────────┘    └─────────────┘
       │                                                            │
       ▼                                                            ▼
┌─────────────┐                                            ┌──────────────┐
│  AI Adapters │                                            │  Position    │
│  (NN/Trans/  │                                            │  Lifecycle   │
│   Ens/ONNX)  │                                            │  (SL/BE/     │
│              │                                            │   Trailing)  │
└─────────────┘                                            └──────────────┘
```

**Signal Flow:** Strategy generates signal → Pipeline filters (regime, cost, spread) → Consensus manager votes with weighted quorum → Risk gate validates exposure/correlation/drawdown → TradeManager executes → PositionLifecycle manages SL/BE/trailing

## Supported Instruments

| Asset Class | Examples | Risk/Trade | ATR SL/TP | Key Engines |
|-------------|----------|:----------:|:---------:|-------------|
| **Forex** | EURUSD, GBPUSD, USDJPY | 1.0% | 1.5/2.0 ATR | Trend 1.3x, VolBreakout 1.2x |
| **Metals** | XAUUSD, XAGUSD | 0.75% | 2.0/2.5 ATR | VolBreakout 1.5x |
| **Indices** | US30, NAS100, SPX500 | 0.75% | 1.8/2.2 ATR | MeanRevert 1.5x |
| **Energies** | USOIL, NATGAS | 1.0% | 2.0/2.5 ATR | VolBreakout 1.4x |
| **Deriv Synthetics** | Volatility, Crash/Boom, Step, Jump, DEX, RangeBreak + 12 more | varies | varies | Family-specific (Spike Hunter, Grid Recovery, ATR Scalping) |

## Quick Start

1. **Install** — Copy `MultiStrategyAutonomousEA.mq5`, `Core/`, `Strategies/`, `Resources/`, and `IndicatorManager.mq5` to your MT5 `Experts/` folder
2. **Compile** — Build in MetaEditor (MQL5 compiler)
3. **Attach** — Drag EA onto any chart (e.g., EURUSD M15)
4. **Configure Symbols** — Set `InpSymbols` to your instrument list (auto-detects asset class)
5. **Set Risk** — Configure `InpBaseRiskPerTradePercent` (default 1.0%), `InpMaxDailyRiskPercent` (5%), `InpMaxPortfolioRiskPercent` (15%)
6. **Choose Mode** — Set `InpEAMode` to `INDICATOR_ONLY`, `AI_ONLY`, or `HYBRID`
7. **Go Live** — EA runs in live mode by default

## Standalone Testing EA

For isolated component testing and backtesting optimization, use `MultiStrategyTestingEA.mq5` instead of the main EA. This standalone testing EA includes the **Complete Test Profile System** with 45 predefined test profiles:

### Test Profile Categories

| Category | Profiles | Description |
|----------|----------|-------------|
| **Special / Utility** | 2 | `TEST_PROFILE_CUSTOM` (manual flags), `TEST_PROFILE_DISABLE_ALL` (baseline noise floor) |
| **Single Indicator Strategies** | 17 | Test each of the 19 registry strategies individually (Momentum, Trend, SR, ICT, Candle, Unicorn, POT, MR, VB, StatArb, FVG, Turtle, Breaker, NYGap, Asian, LiqSweep, RangeComp) |
| **Single AI Strategies** | 4 | Neural Network, Transformer, Ensemble, ONNX AI modes individually |
| **Single Independent Engines** | 4 | Fast Scalp, Spike Hunter, Grid Recovery, ATR Scalping engines individually |
| **Curated Strategy Families** | 5 | Trend Suite, MeanRev Suite, ICT/SMC Suite, Session Suite, Scalp Engines Suite |
| **Aggregate Modes** | 5 | All Indicators, All Indicators Live, AI Suite, All Engines, All Engines Safe |
| **Full System Modes** | 5 | Full Indicators, Full Hybrid, Full With Engines, Full With Engines Safe, Everything |

### Key Input Parameters (Testing EA only)

| Parameter | Default | Description |
|-----------|:-------:|-------------|
| `InpCompleteTestProfile` | `TEST_PROFILE_CUSTOM` | Select from 45 predefined test profiles |
| `InpTestProfileOverrideAll` | `true` | If true, profile overrides all individual input flags |
| `InpIncludeDeadCodeInProfiles` | `false` | Include dead-code strategies (Hurst, OU Process) in profiles |

### Usage

1. **Attach Testing EA** — Drag `MultiStrategyTestingEA.mq5` onto chart instead of main EA
2. **Select Profile** — Set `InpCompleteTestProfile` to desired test mode (e.g., `TEST_PROFILE_SINGLE_MOMENTUM`, `TEST_PROFILE_ALL_INDICATORS`, `TEST_PROFILE_FULL_HYBRID`)
3. **Run Backtest** — Use Strategy Tester with the selected profile for isolated component validation
4. **Review Logs** — Check `[ACTIVATION-MATRIX]` and `[PER-SYMBOL-REPORT]` logs for effective component configuration

### Benefits

- **Isolated Testing** — Test single strategies/engines without modifying main EA inputs
- **No Code Changes** — Main production EA remains untouched
- **45 Predefined Profiles** — Comprehensive coverage from single components to full system
- **Activation Matrix Logging** — Automatic logging of what's active per profile
- **Per-Symbol Reporting** — See exactly which components run on each symbol
- **Optimization Ready** — Works with MT5 optimizer for single-component parameter sweeps

## Configuration

### Risk Management
| Parameter | Default | Description |
|-----------|:-------:|-------------|
| `InpBaseRiskPerTradePercent` | 1.0 | Base risk per trade (% of equity) |
| `InpMaxDailyRiskPercent` | 5.0 | Daily risk budget cap |
| `InpMaxPortfolioRiskPercent` | 15.0 | Max total portfolio risk |
| `InpDrawdownWarningPercent` | 5.0 | Drawdown warning threshold |
| `InpDrawdownCriticalPercent` | 10.0 | Emergency drawdown stop |
| — correlation thresholds | 0.4 / 0.7 | Not an input. `InpCorrelationBlockThreshold` does not exist in any `.mq5`. Correlation is enforced once, in the pre-trade gate (`EAOrchestrator.mqh:853-854`); the `CPositionSizer` correlation path is explicitly disabled at `:886`. |

### AI Integration
| Parameter | Default | Description |
|-----------|:-------:|-------------|
| `InpEAMode` | INDICATOR_ONLY | Operating mode |
| `InpEnableNeuralNetwork` | false | NN adapter |
| `InpEnableTransformer` | false | Transformer adapter |
| `InpEnableEnsemble` | false | Ensemble adapter |
| `InpEnableOnnxAI` | true | Python-trained ONNX adapter |
| `InpPythonBridgeMode` | disabled | ZMQ/HTTP bridge mode |

### Strategies
| Parameter | Default | Description |
|-----------|:-------:|-------------|
| `InpEnableMomentum` | true | Simple Momentum strategy |
| `InpEnableTrend` | true | Trend following |
| `InpEnableMeanReversion` | true | Mean reversion |
| `InpEnableSupportResistance` | true | S/R with Fibonacci confluence |
| `InpEnableCandlestick` | true | Candlestick patterns |
| `InpEnableVolatilityBreakout` | true | Volatility breakout |
| `InpEnableFVGScalper` | true | FVG gap scalper |
| `InpEnableTurtleSoup` | true | Liquidity sweep (Turtle Soup) |
| `InpEnableBreakerBlock` | true | Breaker block entries |
| `InpEnableNYOpenGap` | true | NY open gap fade |
| `InpEnableAsianRangeBreak` | true | Asian range breakout |
| `InpEnableStatisticalArbitrage` | false | Statistical arbitrage (also needs the Python bridge) |
| `InpEnableLiquiditySweep` | true | Liquidity Sweep strategy |
| `InpEnableRangeCompression` | true | Range Compression Breakout |

`InpEnableExitOptimizer` is not one of these: the Exit Optimizer is a math engine registered by
`COrchestratorMathEngineHub`, never a consensus voter, and it has owned an enable-flag slot until Batch 209
deleted that slot as unread.

**Under `InpUseCuratedStrategySet = true` (the live default) a false input does not switch a curated strategy
off.** Which rows are curated is catalog data (`SStrategyDefinition::curatedEnable`), not a list in the flag
builder: today that is all twelve except Candlestick and Statistical Arbitrage, so those two inputs bind.

### Strategy Slot Scheme (semantic-only, Batch 147)

The per-strategy enable flags (`strategyFlags[]`) are written by a single producer,
`COrchestratorStrategyFlagBuilder::BuildStrategyFlags`, which since Batch 209 loops the catalog's indicator
rows: each row's `siIndex` is the slot, `ConfigEnableForSlot` is the one switch from slot to operator input,
and a row whose slot has no input prints `[CATALOG] <name> | enable slot N has no operator input`.
`CEnterpriseStrategyManager::AutoRegisterStrategies` reads the same slots back through `CatalogEnableSlot(i)`,
so writer and reader cannot disagree. The legacy literal slot scheme that Batch 146 shipped dormant was
**removed entirely in Batch 147**; there is no mode switch.

| Slot | Resolved by | Notes |
|---|---|---|
| Enable flag | `SI_*` (`ENUM_STRATEGY_INDEX`), via `CatalogEnableSlot(i)` | `-1` = always on |
| Intrabar policy | own `StrategyConfigBuilder` row, via `CatalogPolicySlot(i)` | `-1` = use `fixedPolicy` |

`ENUM_STRATEGY_INDEX` and `ENUM_STRATEGY_TYPE` share no numbering, so nothing may cast a flag slot to a
strategy type. Roster naming and roster counting go through the catalog rows for that reason.

| Slot | Resolved by | Notes |
|---|---|---|
| Enable flag | `SI_*` (`ENUM_STRATEGY_INDEX`), via `CatalogEnableSlot(i)` | `-1` = always on |
| Intrabar policy | own `StrategyConfigBuilder` row, via `CatalogPolicySlot(i)` | `-1` = use `fixedPolicy` |

The always-LIVE intrabar fallback for Mean Reversion / Volatility Breakout is hardcoded to semantic slots `7/8` in `CIntrabarPolicy::GetIntrabarPolicyHelper`.

Registration prints a `[CATALOG-AUDIT]` block on every boot confirming `slot_scheme=SEMANTIC` and listing each strategy's enable/policy slot.

## Strategy Roster

### Indicator-Based Strategies (14 catalog rows)

| Strategy | Tier | Cluster | Weight | Curated | Description |
|----------|:----:|---------|:------:|:-------:|-------------|
| Momentum | 3 | TREND | 1.0 | yes | Simplified 4-indicator momentum with scalp mode |
| Trend | 2 | TREND | 1.2 | yes | EMA crossover + ADX + multi-TF alignment |
| Support/Resistance | 2 | MEAN_REVERSION | 1.5 | yes | S/R with Fibonacci confluence + Hurst filter |
| Candlestick | 2 | STRUCTURE | 1.5 | **no** | Engulfing, pin bar, Doji patterns |
| Mean Reversion | 2 | MEAN_REVERSION | 1.8 | yes | Bollinger band reversion with z-score |
| Volatility Breakout | 1 | TREND | 2.0 | yes | ATR compression breakout |
| Statistical Arbitrage* | 2 | MEAN_REVERSION | 1.8 | **no** | Pair correlation / spread reversion (Python bridge required) |
| FVG Scalper | 2 | STRUCTURE | 1.8 | yes | Fair Value Gap scalper with structure alignment |
| Turtle Soup | 2 | STRUCTURE | 1.6 | yes | Liquidity sweep detection + confirmation |
| Breaker Block | 2 | STRUCTURE | 1.7 | yes | Failed OB → breaker retest entries |
| NY Open Gap | 3 | STRUCTURE | 1.3 | yes | NY session open gap fade |
| Asian Range Break | 3 | STRUCTURE | 1.3 | yes | Asian range breakout at London open |
| Liquidity Sweep | 2 | STRUCTURE | 1.5 | yes | Sweep-and-reclaim entries |
| Range Compression | 2 | TREND | 1.6 | yes | Compression break with trend cluster |

*Statistical Arbitrage is only registered when Python Bridge is connected. Unified ICT, Unicorn Model and Power
of Three left this table in Batch 207: they had no class, so nothing could ever register them.

### AI Adapters (5 Registered)

| Adapter | Tier | Cluster | Weight | Description |
|---------|:----:|---------|:------:|-------------|
| Neural Network AI | 2 | NONE | 1.0* | LSTM/MLP neural network via `CAIStrategyAdapter` |
| Transformer AI | 2 | NONE | 1.0* | Transformer attention model via `CTransformerAIStrategyAdapter` |
| Ensemble AI | 2 | NONE | 1.0* | Ensemble of multiple AI models via `CEnsembleAIStrategyAdapter` |
| ONNX AI | 2 | NONE | 2.0* | ONNX runtime inference via `COnnxAIStrategyAdapter` |
| Python Bridge AI | 2 | NONE | 1.5* | External Python inference via `CPythonBridgeAIStrategyAdapter` |

*AI adapter weights are scaled by `InpAIWeightMultiplier` input parameter.

## Risk Management

The EA enforces a **multi-layer pre-trade risk gate** before any order reaches the broker:

1. **Per-Trade Risk** — Scaled to equity with Kelly Criterion, equity compounding, and correlation adjustment
2. **Daily Budget** — Tracked via entry risk + mark-to-market drawdown + open stop exposure; halts at limit
3. **Portfolio Exposure** — Total open risk capped at `InpMaxPortfolioRiskPercent`
4. **Correlation Engine** — Reduces size at 0.4 correlation, blocks at 0.7
5. **Drawdown Protection** — Warning at 5%, critical emergency stop at 10%
6. **Equity Curve** — Reduces sizing to 50% when equity < 20-period EMA
7. **Position Limits** — Per-symbol and per-family max position caps
8. **Spread/Session/Regime** — Filters reject signals during adverse conditions
9. **Unprotected Position Tracker** — Blocks new entries when positions lack protective stops
10. **Daily Loss Limit** — Circuit breaker halts trading on excessive daily loss
11. **Stop Feasibility and Expectancy** — Rejects a trade whose stop must widen more than 1.25x past the distance lots were sized at, or whose take-profit is under 4x the round-trip spread cost (Batch 169)

### What the operator will notice after Batch 168-169

- **Protective code runs for the first time.** Trailing stops, breakeven, signal-reversal exit, max-hold, loss-minimization, no-stop remediation and drawdown/daily halts previously classified the EA's own positions as foreign and returned early *without logging*. Expect `[MAGIC-AUTHORITY]`, `[SL-GUARD]`, `[SCALP-EXIT]` and exit activity that never appeared before.
- **Halts survive a restart** and are re-armed at runtime, so an EA that used to resume trading after a same-day halt now stays halted until the recovery cooldown clears.
- **Fewer, smaller trades.** Consensus needs two independent voters; indicator/data gaps now veto instead of passing; targets that do not clear the spread are refused. Authorized risk per trade is clamped to the configured limit (compounding tiers can reduce it, never raise it), while the corrected cost model lowers *estimated* risk so more of what remains passes the gate.
- **Execution is verified, not assumed.** Fills are confirmed against live positions, retries dedup before resending, and unreconciled sends log `[EXECUTION-UNCONFIRMED]` / `[RISK-UNRECONCILED]` instead of disappearing.
- **Statistical arbitrage abstains** (`[STATARB-UNHEDGED]`) until both legs of a pair signal are executable; it is disabled in the live config today.
- **Small accounts may see trades refused on size.** A lot that would have to round up to the broker minimum by more than 3x the approved risk is now refused (`[PositionSizer] Min lot round-up refused`). Widen the stop; do not raise the ceiling.
- **Scalp positions are exited by the scalp engine again.** Batch 168 switched lifecycle breakeven/trailing on for every owned position, which was cutting fast-scalp trades short of their own targets; engine-tagged positions are now excluded from lifecycle exits (they still count in risk and daily-loss accounting).
- **Order-flow filters no longer fire on made-up volume.** OFI and VPIN are disabled for synthetic-index symbols, and any symbol whose broker publishes no traded volume logs `[VOLUME-PROXY]` at init.
- **Log verification is still owed.** These batches ship on compile + static review (AGENTS.md §5.2); confirm the signatures above on the first live or demo session before trusting the equity curve.

### What the operator will notice after Batch 172 (live-authority gate)

- **`PROVEN_AI` promotion becomes reachable in code.** The gate read a `profitFactor` that nothing ever wrote, so it stayed at 0 and the branch never executed. Profit factor is now accumulated from the closed-trade R stream (`grossWinR / grossLossR`), so the branch can fire. At Batch 172 the resolved multiplier still was not consumed — that gap is what Batch 173, below, closed.
- **`costScore` authority bonus was inverted and is now correct.** The old test awarded +0.05 authority when `costScore <= 0.3`, i.e. to the *most expensive* trades, because `costScore` is quality-shaped (`SignalPipelineWeighter:279` adds it as `costScore * 0.0543`). It is now `>= 0.50`, so cheap entries get the bonus and expensive ones don't — and since Batch 173 that difference is a difference in lot, not just in a log line.
- **Scope limit you must know.** In `CLiveAuthorityResolver::Resolve`, `result.allowed` is set `true` unconditionally at the end — the only *vetoes* are still the two mode checks and `LOW_CONFIDENCE`. Since Batch 173 the ladder (`1.0 / 0.85 / 0.70 / 0.50 / bootstrap / promoted`), the `PROVEN_AI` vs `BOOTSTRAP_AI` split, and the cost/readiness/context bonuses all set the shipped lot; they just express themselves through size rather than through permission.
- **Init logs a new `[AUTHORITY-CONFIG]` pair.** `effective:` lists the thresholds in force; `clamped:` names any `InpAuthority*` input that was looser than the documented floor. On stock defaults six names clamp — `authorityMinSamples` (12→30), `authorityMinExpectancyR` (0.03→0.3), `authorityMinProfitFactor` (1.10→1.2), `aiPromotedRiskMultiplier` (1.00→0.75), `authorityMinReadinessScore` (0.52→0.60) and `authorityMinContextScore` (0.48→0.55). The last two land on the literals the code already used, so only the first four represent a real policy choice.
- **Configured authority values can only tighten a gate, never loosen one.** The floors are `AUTHORITY_MIN_*` defines in `LiveAuthorityResolver.mqh`. Making promotion easier is a deliberate source edit, not a slider in the inputs dialog.
- **The `[LiveAuthorityResolver]` status block prints `pf=` and `eligible=Y|N` per tracked AI strategy**, so the gate's arming is observable rather than inferred from an absent `PROVEN_AI`.
- **Not fixed, and not silently:** per-family demotion to shadow, and the trial tracking implied by `InpAuthorityTrialHorizonSeconds` / `InpAuthorityMaxTrackedTrials` / `InpNonAIPromotedRiskMultiplier`, do not exist. The `[LIVE-AUTHORITY]`, `[AUTHORITY-TRIAL]` and `[AUTHORITY-RESULT]` tags named in SYSTEM_STRUCTURE.md appear in no source file and never have.

### What the operator will notice after Batch 173 (authority now sets the lot)

This is a live-sizing change. The ladder stopped being a log line.

- **Low-authority trades are materially smaller.** Candidates below the 0.35 score rung are sized at `bootstrapMult * 0.5` (0.25x of approved risk on stock defaults); unproven AI-only candidates are capped at 0.5x; a fully-scored hybrid candidate is still 1.0x. Total exposure and per-symbol lot counts should drop and the per-trade equity swing with them. That is the change working.
- **A symbol can be sized out of existence, and it says so.** Where the approved lot times the multiplier lands under `SYMBOL_VOLUME_MIN`, the trade is **refused rather than rounded up** — `CPositionSizer::NormalizeVolume` would have clamped it back to the minimum and handed the whole reduction straight back. Each refusal logs `[AUTHORITY-REJECT]` twice (the arithmetic, then which levers would bring the symbol back) and increments a per-symbol and session counter that appears in the `[CandidateBuilder]` status block as `authorityLotRefusals total=N`. Coarse-tick synthetic indices and small accounts will see this first.
- **Every shrink prints `[AUTHORITY-REDUCED]`** with the multiplier, the before/after lot, the before/after risk percentage and the reason. These two tags are the first real writes to `FMT_AUTHORITY_REJECT` / `FMT_AUTHORITY_REDUCED`, which have been defined since Batch 168 with no consumer while AGENTS.md §6 kept listing them as verification evidence.
- **The daily risk budget follows the actual lot.** `candidate.riskPercent` is rescaled by the same ratio before the send, because `RegisterExecutedTradeRisk` books it; otherwise the gate would reduce exposure while the budget kept charging full risk.
- **Do not read the first session as strategy regression.** Judge it against `[AUTHORITY-REDUCED]` counts and the refusal breakdown, not against last month's trade count.
- **Levers, in order of preference:** widen the stop at the same risk percentage (raises the approved lot above the minimum), revisit the `AUTHORITY_MIN_*` floors in `LiveAuthorityResolver.mqh`, or accept the smaller size. There is no input that turns the ladder back off — that would mean removing the call at `EAOrchestrator.mqh:3517`.
- **What authority still does not do:** `result.allowed` remains `true` unconditionally at the end of `Resolve()`, so authority influences size and vetoes only on mode conflict and `LOW_CONFIDENCE`. It is not a permission layer.

### What the operator will notice after Batch 174 (VPIN vetoes; the risk clamp stops claiming a size it never had)

- **Toxic order flow now blocks entries instead of merely shrinking them.** When a symbol's VPIN reaches its configured extreme threshold (`InpVPINExtremeThreshold`, default 0.70), the post-consensus validator vetoes the candidate and logs `[POST-CONSENSUS-FILTER] ... filter=vpin_extreme | VETO`. The veto method existed with no caller; VPIN only reduced the lot to 0.1x. Expect fewer new positions in exactly the conditions where the strategies signal most. The threshold is the lever if that is too strict. (This arm only became reachable in Batch 175, which gave the validator its missing configuration call.)
- **The validator's old 0.85 and 0.95 literals sat above the configured line,** so with the default 0.70 threshold EXTREME toxicity was reported as if no filter had run. It reads the filter's own regime now, which is also what `CVPINLotModifier` sizes from.
- **A trade that cannot be sized compliantly is refused, not rounded up.** Where the lot needed to meet the per-trade risk cap falls under the broker minimum, the candidate is dropped with `[RISK-GATE-REJECT] ... reason=compliant_lot_below_min`. It used to be rounded up to the minimum and then booked at the cap: the position could lose more than the cap while the daily budget recorded it as if it had not.
- **Four steps left the sizing chain** (`ApplySkewStepScaling`, `ApplyFullMarginStacking`, `ApplySafeModeRestrictions`, `EvaluateEAModeAdmission`). Each returned its input untouched, so nothing they claimed to do ever happened and no behavior changes — this is the code stopping the claim.
- **Conservative-tier safe mode is still only half-wired, now stated where it can be found.** Of `SSafeModeConfig`, only `minConfidence` reaches an entry decision; kill-zone-only trading, `noStacking`, `minVoters` and `minConfluence` are read by the diagnostics printer alone. Your live tier is `RISK_TIER_MODERATE`, so nothing changes today, but selecting conservative will not restrict entries the way the config names imply. (Batch 175 closed most of this — see below.)

### What the operator will notice after Batch 175 (two filters switch on that have never run)

- **`[VALIDATOR-CONFIG]` now prints once per symbol at init** with the quality floors, the hard spread cutoff and OFI/VPIN ON/OFF. If that line is missing from a session log, the validator is running on defaults and no symbol is being screened by order-flow or toxicity filters.
- **Order-flow (OFI) and VPIN screening are live for the first time.** `InpEnableOFIProxy` and `InpEnableVPINFilter` both default to `true`, but the validator's configuration method had no call site, so both arms were off. Expect `[SIGNAL-REJECTED] ... reason=ofi_contradiction` and `reason=vpin_toxicity` lines that have never appeared in this account's logs, and a lower entry count as a result.
- **The quality floor drops to what you configured:** 0.68 new-bar and 0.70 intrabar, replacing the accidental 0.75/0.72. This one admits slightly more signals than the broken version did.
- **The hard spread cutoff did not take its configured default.** `InpHardSpreadCutoffPoints=200` is below the 1,727-11,140-point spreads the synthetic book trades at and would have vetoed every synthetic at startup; the effective value is `max(hardSpreadCutoffPoints, InpMaxEntrySpreadPoints)`. Raise `InpMaxEntrySpreadPoints` if you want a wider backstop.
- **If you switch to the conservative tier, it now means what it says:** 3 voters minimum, quorum 0.65, spread within 0.15 ATR, one position per symbol, confidence floor 0.70. Startup prints exactly which gates are on and which are not.
- **Two safe-mode fields are deliberately not enforced** and are printed as such: `tradeOnlyKillZones` (London 07-10 / NY 12-15 UTC is FX-session semantics over a roster of 24/7 synthetics that the session filter exempts on purpose) and `avoidNewsEvents` (no economic-calendar feed exists; the check is a stub).
- **Still decoration, recorded:** the validator's spike-hunter branch is empty, and `InpValidator*MinConfidence` / `MinConfluence` are printed in `[ENTERPRISE-CONFIG]` but enforce nothing. Turning them into vetoes is next, after this wiring has been observed live.

### What the operator will notice after Batch 176-177 (logs stop describing controls that were never running; engine fills get confirmed)

- **`[VPIN] Constructed | ... mode=` now reports the classification the filter actually uses.** It used to print a second, decorative field that nothing ever wrote and nothing read, in the same sessions where VPIN became a live veto.
- **`[GRID-RECOVERY] Level opened: ... ticket=` now shows a position ticket.** It previously stored the *order* ticket, and the grid's own close path selects and closes by position ticket — on a hedging account those are different numbers, so a level could never be selected, never be closed by the engine, and had no other exit owner because engine-tagged positions are excluded from lifecycle management. If the position cannot be matched yet, `[GRID-RECOVERY] TICKET UNRESOLVED` says so instead of quietly storing an unusable ticket.
- **A partially filled scalp, spike or grid trade is no longer treated as "no trade".** `CTrade::Buy/Sell` report `DONE_PARTIAL` as a failure even though a position exists, and the engine would re-fire on the next scan — duplicate exposure. The paths now confirm from the position (`FILL CONFIRMED BY POSITION`), arm their cooldown, and skip the resend.
- **A scalp pending order whose response was lost is recovered, not forgotten.** On `TIMEOUT` / `CONNECTION`, or whenever the broker returned an order number, the tracker finds the order by symbol and magic and tracks it (`[SCALP-PENDING] PLACEMENT RECOVERED`) instead of placing a second order behind the one the server already accepted.
- **README no longer lists `InpCorrelationBlockThreshold`** — that input does not exist in any `.mq5`. Correlation is enforced once, in the pre-trade gate, and the sizer's correlation path is switched off in code.
- **Two known gaps are stated rather than implied:** the margin gate's 80% free-margin / 200% margin-level ceiling has no knob (a rejection prints the threshold in force), and grid level tickets are in-memory only, so a terminal restart leaves open grid positions untracked by the engine until their own SL/TP. Both are in the changelog's open list.

### Batch 178: three trading engines are enabled by their inputs and wired to nothing

`InpGridRecoveryEnabled`, `InpATRScalpingEnabled` and `InpSpikeHunterEnabled` all default to `true`. Each of those engines initializes, registers its symbols per Deriv profile, prints a line saying it is enabled, and is deinitialized on shutdown — and nothing ever calls its tick routine, so it opens zero trades. The init lines do say `PARKED`, and `[ENGINE-STATUS]` now prints the whole set once at startup, naming each parked engine and the input that claims it is on.

If your logs show no grid, spike or ATR-scalp entries, that is the reason: they were never connected to the loop, not a signal problem. **Wiring them in is deliberately not done here.** It would start real orders from three strategies that have never traded on this account, at lots from sizing paths that have never run — every other fix in this audit reduces risk, and this one would create exposure. Treat it as a strategy-activation decision: choose the engines and symbols you actually want trading, then wire the tick loop behind that choice, on a small book first.

Two items are therefore latent rather than live, and sit behind the same decision: grid level state is in-memory only (nothing to reconcile while the grid never trades), and the ATR-scalp magic band (`base + 7000 + symbolIndex`) overlaps the `ASSET_FOREX` asset offset — positions are separated today by send comments, not by magic.

### Batch 179: what the last live session's logs actually said

The terminal's own EA journals (`MQL5/Logs/`, UTF-16LE) for 17-23 September were read against the code. They are the first runtime evidence for Batches 168-178, and the newest is 23 September — this EA has not been attached to a chart since the October batches, so the new tags below cannot be evidenced from here yet.

- **The live-authority gate has always run, whatever its input says.** `InpEnableLiveAuthorityGate` defaults to `false` in both `.mq5` files and gated exactly one init print; `Resolve()` and Batch 173's lot scaling are called unconditionally. Startup now prints `[AUTHORITY-GATE] live authority resolver ACTIVE on every risk-approved candidate | InpEnableLiveAuthorityGate=false is not consulted by the sizing path`. The flag was **not** turned into a real switch: making "input off" mean "stop shrinking lots" would let a chart with the saved default quietly trade at full size.
- **Scalp positions were tracked under the wrong ticket, and that released their risk budget early.** The fast-scalp entry registered the *order* ticket while the tracker is keyed by *position* ticket, so the next management pass dropped the slot, freed a full per-trade risk unit, and re-added the position without consuming anything. `usedScalpRiskPct >= scalpRiskPct` could therefore only ever bind inside the entry tick. The entry now resolves the position ticket (or leaves registration to the sync pass, with the budget left consumed). `maxScalpPositions` was unaffected — it counts live positions, not the accumulator.
- **The ATR crisis gate logged a number it had already clamped.** 46 of the 71 vetoes in the last session printed `10.000`, covering both a 10.58× spike and a 431× reading that is a data fault, not volatility. The message now carries the raw ratio too. The veto itself still uses the capped value; treating a 431× read as bad data rather than a crisis is recorded, not guessed at.
- **The journals confirm Batches 175 and 178 from the log side**: no `quality_gate`, `hard_spread_cutoff`, `ofi_*` or `vpin_*` lines ever appear (those arms had no configuration call site), and the grid / ATR-scalp / spike-hunter engines appear only as `Initialized`, `PARKED`, `Deinitialized` with `gridsOpened=0`.
- **`RUNTIME_DECISION_GRAPH` no longer claims an `EXOGENOUS_ONLY` validator mode.** That string was a stale log label, not a mode: all five arms run. The quality gate is documented honestly as near-self-satisfying above its 0.40 absolute floor.

### Batch 190: the risk gate now prices the trade you are actually sending

The pre-trade gate used to be called before the position was sized, with `lotSize` set to the broker minimum, and the real lot was computed afterwards. Twenty-odd checks inside it — portfolio exposure, the correlation tiers, the daily risk budget, margin, cluster governance — were therefore voting on a 0.01-lot trade while the candidate shipped whatever the sizer, the daily-budget cap, the drawdown and momentum scalers and the min-lot round-up produced. The file's own comment said the shipped lot "can carry several times the proposed risk with no gate behind it"; only the per-trade cap clamp looked at the real size.

- **What changed:** `ValidateTradeRequest` now runs once, at the end, against `candidate.lotSize`. It moved rather than being added because each approval keeps a virtual reservation until its TTL, so two calls would count the same trade twice.
- **What to expect on the first session:** fewer and smaller consensus entries, never larger. Refusals are countable: `[RISK-GATE-REJECT] ... reason=final_lot_validation`, `reason=adjusted_lot_below_min`, `reason=correlation_reduce_below_min_lot`, and `[RISK-GATE-ADJUST] symbol | lot=A -> B | risk=x% -> y% | reason` when the gate asked for less and got it.
- **Three gates that could not refuse now can:** a correlation reduction that cannot be expressed above the broker minimum used to approve the full lot with the discount silently gone; a lot above `SYMBOL_VOLUME_MAX` printed "caller must cap" and returned approval; the validator's quality floor was derived from the very quality being compared, so `InpValidatorNewBarMinQuality=0.68` / `InpValidatorIntrabarMinQuality=0.70` did nothing for the two consensus classes that carry most entries. That last one tightens entries: the floors become 0.612 / 0.63 / 0.595 instead of 0.40 / 0.45.
- **Stop distance is volatility-aware and unit-consistent:** `atrValue` was hard-wired to 0, so the ATR branch in `CalculateStops` never ran; ATR(14) now comes from the shared indicator cache. The broker minimum stop was compared in price units against point counts, roughly 100,000x too small on 5-digit FX, so the spread-folded floor never bound.
- **One lifecycle bug:** `CMeanReversionStrategy::Cleanup()` released a Stochastic handle owned by `CIndicatorManager`, which releases it again in `DestroyInstance()` — the call AGENTS.md §3.5 requires. Shared handles now stay with their owner; handles a strategy creates itself are still released by that strategy.

### Batch 192: what changes in the logs and in sizing

- **Fast-scalp now reserves risk once, not twice.** The entry gate and the pre-send gate both called `ValidateTradeRequest` on the same lot, and every approval holds a virtual position until TTL pruning, so one scalp double-counted against portfolio and daily-risk limits and filed two approvals. The entry-stage gate survived because its request is the one that carries the cluster code.
- **A risk-manager lot cut is now visible:** `[SCALP-RISK-ADJUSTED] XAUUSD | lot 0.05 -> 0.03 | reason=...`. Adoption is shrink-only — the pipeline can round a reduction up to the broker minimum, and that is no longer taken.
- **Compounding tiers can no longer size above the envelope.** A tier wrote its raw risk percent straight into the position sizer, which does not clamp, while the envelope clamp applies only on the risk-manager path: the per-trade cap check then refused the entries, so a tier could look applied and trade nothing. `[COMPOUNDING-TIER] Applied to PositionSizer` names the clamped value when it binds.
- **`[RISK-ENVELOPE]` no longer skips a warning-only clamp,** and the line gained `ddWarn A->B`.
- Two things reported during the audit were disproved before being acted on: the daily-loss halt clears itself at the trading-day roll (`UnifiedRiskManager.mqh:1304`), and the CVaR gate is fed by the equity-curve buffer (`:655`). Neither was "fixed".

### Batch 193: five things that were stopping valid trades, and one strategy that could never start

No risk ceiling moved in this batch. Each item was a control that did not behave as designed.

- **Statistical Arbitrage can now be enabled.** It had an input, a flag slot, a catalog row and a working class, but no `RegisterDefinition` line — the only one of fourteen strategies missing from a hand-written block. The registry now builds indicator definitions by looping the catalog, so adding a strategy is one catalog row plus its input, and a row missing its `registryType` says so at init instead of silently never trading.
- **`InpWeight*` inputs decide voting weight.** They used to reach only the registry descriptor, which nothing reads for indicators; the catalog literal was the real authority. The resolved input is now written into the row before the managers register, and every row that moves prints `[CATALOG] <name> | registration weight A -> B from operator input`. Five defaults differ from the literal, so relative influence between voters shifts on the first session.
- **The dormancy cooldown stopped re-arming itself.** A symbol parked after three quiet evaluations stayed parked indefinitely, because the strike count that caused the park was never cleared on expiry — roughly one evaluated bar per half hour per quiet symbol. Expiry now resets the strikes and prints `[DORMANT-COOLDOWN] ... strikes reset`.
- **A 0% scalp tier no longer latches the engine off for the session.** The budget was read once at init and a 0% tier zeroed `maxScalpPositions`; when the tier raised the budget the engine still refused everything. It is re-read every cycle now, and refusals print `[SCALP-GATE]` with used risk, budget, cap and remaining cooldown (one line per minute per symbol since Batch 214 — the throttle used to be one EA-wide slot).
- **Momentum keeps the next bar's crossover.** Its cooldown was a full bar measured from when the signal fired, so a mid-bar signal ate the following bar's edge. It is half a bar; the same-bar guard still caps it at one signal per bar.
- **Stops follow volatility instead of a percentage cap, and the cost gate stopped being circular.** The 0.3%-of-price stop ceiling (1% on synthetics) could sit below the `3 x spread` floor, which made take-profit a function of the spread alone — the cost ratio became a constant, and every candidate on it was vetoed for a reason that had nothing to do with the market. The ceiling is now `max(price cap, 3 x ATR)`, TP is an R-multiple of the stop actually taken, and when the floor still binds, `[CANDIDATE-BUILDER] ... stop pinned to floor | designed= floor= spread= tp= costRatio= limit=` says so at the point it becomes known.

Expect more entries at the same risk per trade: a wider stop shrinks the lot, and the per-trade cap, the daily and portfolio budgets and the final lot gate are unchanged.

### Batch 194: strategy inputs that reached no strategy

The strategies are built by catalog creators that construct them bare. `CStrategyFactory` still holds a per-strategy configuration path, but its only live call site passes the AI rows' factory name, so anything whose value travelled through the factory config struct was inert - the class kept its constructor default instead of the operator's input. (That path is gone as of Batch 210; the three inputs below are applied through `ConfigureBeforeInit`, which is what this batch wired them into.)

- **Momentum's scalping mode never switched on.** `InpEnableMomentumScalping` defaults to true and had no reader, so the strategy has run trend-following everywhere its whole life. It is now applied before `Init`, and bounded: the strategy declares M1-M15 as its scalp band and used to ignore that check's result, so an out-of-band chart now prints `[MOMENTUM] Scalping input ON but H1 is outside the M1-M15 band - trend-following mode, one signal per bar` and keeps the one-signal-per-bar guard. `InpMomentumScalpCooldownSeconds` is live with it.
- **Candlestick was requiring a trend the operator had switched off.** `InpCandlestickRequireTrend = false` reached nothing while the class defaulted to requiring alignment; the flag is read in `Init` (it decides whether the EMA50/200 handles exist at all), so it is applied before `Init` now. Counter-trend candlestick patterns become eligible.
- **Mean Reversion never learned its symbol was synthetic.** `SetSyntheticMode` had one caller, in that dead factory path, and its source field exists in no config struct and no `.mq5` - so every synthetic index ran the Bollinger+RSI+tick-volume branch built for FX liquidity. `Init` now derives it from the symbol and prints which path it took: `[MEANREV] Initialized ... path=synthetic(1.5sigma+spike)` or `path=fx(bands+rsi+volume)`.
- **`InpTrendADXNoTrendThreshold` stays unwired, on purpose.** With a value it would replace `CStrategyTrend`'s per-asset-class ADX tuning with one constant on every symbol. The strategy already logs `Source=ASSET_CLASS` at init, so the inert input is visible rather than silently wrong.

None of this moves a risk limit: consensus still requires two independent voters, the validator arms are unchanged, and every entry still passes `CUnifiedRiskManager` on its final lot.

### Batch 195: a regime veto that had never fired, because two strategies never reported their type

`IStrategy::GetType()` is pure virtual, and `CStrategyBase::GetType()` answers `STRATEGY_TYPE_CUSTOM`. Liquidity Sweep and Range Compression Breakout each declared a method called `GetStrategyType()` - a lookalike name that overrides nothing and has no callers - so both reported CUSTOM to the consensus engine while everything else about them (catalog row, registry name, magic, status reports) looked correct.

- **Range Compression is classified as fading the trend**, and `RegimeStateHardGate` is written to zero its vote in a confirmed trend regime - the case the code itself calls "the fastest way to blow an account". With the type arriving as CUSTOM, that veto never fired. It fires now.
- **Both strategies now take their regime category weight** (`breakoutWeightMult` for compression, `ictWeightMult` for liquidity sweeps) instead of the neutral 1.0 default branch.
- **Nothing else moves.** No gate, lot, magic number, position comment or ownership range changed, so positions already open keep the identity that manages them. The type-based magic table in `CMagicNumberAllocator` would have relocated them, but no method of that class is called anywhere - it is on the open list as dead code, not as a live authority (deleted in Batch 197).
- **One comment corrected:** a zero regime multiplier removes a vote's score and dilutes the ready-weight ratio, but the vote still counts toward the minimum-voter floor. Turning that into a real vote-drop would tighten one test while loosening another, so it is recorded as an open item rather than shipped without runtime evidence.

Expect equal or fewer entries from these two strategies, and `[CONSENSUS-REJECT] ... Ready weight ratio` lines where a trend-regime candidate now carries a vetoed voter.

### Batch 196: fill confirmation could answer "yes" to the wrong owner

When a send comes back failed, the EA asks `FindFreshPositionForSend` whether a position from that send nevertheless exists. Until now it answered yes for **any** EA-owned position on the same symbol and side opened in the last 30 seconds - and it could not have been stricter by magic, because a fast-scalp market order and a consensus entry on the same symbol are given the *same* magic by `CTradeManager`.

That was not a logging nicety. Every caller turns the answer into state: a grid level bound to a borrowed ticket is a level that later calls `PositionClose` on a position it does not own; a scalp tracker slot registered under one releases and manages the wrong risk; a consensus receipt computed from a foreign volume books a trade that never happened, and the transient-retcode dedup guard could refuse a legitimate entry because some engine's fill happened to be in the window.

- **The fix is an owner parameter, not a new identity.** The matcher now takes the comment prefix the send used. A caller that names one matches only its own positions; a caller that names none - the consensus path - matches only positions no engine claims. The four engine prefixes are the same strings the exit paths already trade on, so this relies on a field the account was already depending on.
- **No send changed.** Magic numbers, comments, lots and ownership ranges are untouched, so positions already open keep the identity that manages them.

A false "yes" used to mis-bind tracking and close operations; a false "no" only re-fires an engine's own retry path, which each site already bounds with its cooldown and counters.

### Batch 197: every engine now ships its own magic, the grid survives a restart, and the lifecycle manager recognises its own positions

- **One number, one owner.** The four engines moved to bands under the lowest asset offset - fast scalp `+6000`, ATR scalp `+6100`, grid `+6200+level`, spike `+6300` - and consensus entries gained the symbol slot they never had: `SetMagicOffsetForSymbol` registered the asset offset alone, so every forex pair shipped `base + 7000` and every position in an asset class was one book to a magic-keyed reader. Before this a fast scalp sent through `CTradeManager` carried exactly that number, so a scalp fill reached that symbol's strategy attribution. No gate reads an exact magic, so the re-label moves no decision; `[MAGIC-LAYOUT]` now asserts the layout at init and refuses to start if a symbol slot composes into an engine band.
- **Positions already open are unaffected.** Comment tags stay the exit discriminator: a pre-renumber scalp still carries a consensus-band magic and only its comment tells it apart, and the grid's restart recovery decodes both the new band and the legacy one.
- **A restart used to forget the grid.** Level tickets lived only in memory, so after a recompile the orphaned levels ran to their own stops with no manager while the engine laid a fresh level 0 on top of them. `[GRID-RESTART]` rebuilds each slot from the open positions at init. The grid engine is parked today (no tick-loop caller since Batch 178), so this is what makes wiring it safe rather than something that fixes a live leak.
- **The quiet money bug:** `PositionLifecycleManager::IsEAOwnedMagic` still used a `base + symbolCount*100 + cluster` window. On the default 13-symbol universe that ceiling was `base + 1399` while positions shipped at `base + 7000..9400`, so twelve of thirteen symbols were "not ours" - Signal Reversal Exit never fired and no ranging position ever moved to breakeven, despite `InpEnableSignalReversalExit = true`. It reads `CMagicRange` like every other owner now does, so expect both exits to work on the next attach.
- **Dead authority removed:** `CMagicNumberAllocator` (395 lines) is deleted. Its family-offset table does not match the offsets orders actually ship with, so wiring it in would renumber live positions; its only live call fed the narrow window above.

### Batch 199: the EA can now learn which strategies make money

The consensus decision never published who voted. `CEntStrategySignalContext`'s contributor arrays had readers in four places and a writer in none, and the class documented that in its own header. Consequences, each verified at the call site:

- **Strategy performance never updated.** Per-strategy win rate, trade count and health score are written only by the closed-trade attribution path, which had nothing to pop. Every indicator strategy voted at the registration default forever; AI strategies, whose health has a separate live writer, were the only ones held to their results.
- **Per-cluster risk caps never applied.** `ValidateClusterGovernance` bailed out on an empty cluster code, so the 5-position / 5%-risk-per-cluster caps and the opposing-cluster mutex were skipped for every candidate. They run now and print `[RISK-CLUSTER]`.
- **PROVEN_AI never saw an outcome.** The provenance record was gated on a flag computed from that empty list, so the live-authority promotion gate had no input and `[AUTHORITY-LEARN]` could not print.
- **Performance auto-disable was unreachable**, so a strategy could lose indefinitely without being paused.

Attribution is now keyed to the fill's own `positionId` at execution rather than to whatever decision the cache holds when the deal event arrives, every executed trade records its voters, and each prints `[TRADE-ATTRIBUTION]`. Engine (scalp/grid/spike) deals are filtered out of the feedback path first, so a scalp's P/L can no longer be scored against the strategies cached on that symbol.

Expect **fewer** entries, not more: caps can now refuse what they never measured. Nothing in the risk ceilings, lot math, stops or sends changed.

### Batch 200: dead code removed, and the unwired-but-wireable list is now explicit

281 lines of code that no path could reach are gone. The deletions all name themselves in `changelogs.md`; the two worth knowing operationally are a never-called duplicate of the VPIN/OFI + Skew Step tick feed (`FeedMicrostructureEngines`, next to the live copy in `OnTick`) and an uncalled `CTradeExecutor::ExecuteBatch` that carried its own `[EXECUTION]` print. Both were places a future edit would have looked correct and done nothing.

No decision path changed: the risk gate, consensus scoring, lot math, stops, magics, comments and sends are untouched, so open positions keep their identity and log shapes are stable. What the audit found *unwired* stays in the code and is listed as a batch-sized gap each: consensus participation has never adapted (every vote scaled by a constant 0.985), the neural net has never been fed a realized P&L, the lifecycle's "pause trailing in a ranging market" branch has no regime source, and the heartbeat's `paused` field, which printed false until Batch 202 wired it to the spike monitor's real state.

### Batch 201: AI confidence now adapts to the market regime

`m_currentMarketRegime` had four readers and no writer, so `CAIEngine::AdaptToRegime` took its no-op branch every cycle and the per-regime confidence factors (0.9 in a trend, 1.1 in a range, 1.2 when volatile) had never been applied to any AI strategy. The manager now publishes the regime from the same `CRegimeEngine` snapshot that gates strategy votes - an unvalidated snapshot maps to `UNKNOWN`, meaning no adaptation, rather than a guess - and prints `[MARKET-REGIME] <symbol> | old -> new | valid=` on each change. AI entries become slightly more permissive in a confirmed trend and more selective in ranges and volatile expansions; indicator voting, the consensus gate, risk ceilings, lot math, stops and sends are unchanged.

Two nearby findings were **not** wired, each for a stated reason: participation (a 0.35 "no signal" target would permanently discount strategies meant to fire rarely, like the NY open gap) and the ranging-regime trailing pause (`CTradeManager::ManageAllPositions` has no symbol filter, so per-symbol routing means changing the exit authority - not attempted without a live attach). Both are recorded with their reasoning in `SYSTEM_STRUCTURE.md` §4.

### Batch 202: the heartbeat `paused` field reports a real pause

`m_tradingPaused` fed the heartbeat `pause_active=` field while its only writers had no callers, so it read `false` even when the synthetic-spike monitor had paused new positions (and the heartbeat block reached only the JSON log until Batch 218 put it in the journal). `CHeartbeatTelemetry::Emit` now takes the state and pushes it through `SetTradingPaused` before the counter snapshot, fed by `m_spikeMonitor.IsPaused()` at the existing emit site. No decision reads that field, so nothing but the log changed - but a pause is now visible, which is how the operator learns the monitor acted at all.

### Batch 203: the neural net now learns from its own trades

Six links were missing between a filled trade and the net's training buffer: nothing reserved a prediction for the send, nothing assigned `candidate.predictionId`, nothing wrote the position-to-prediction map, nothing queued the realized result at close, the drain never consumed its rows, and the id lookup read a **live position comment** - impossible once the position had closed, so even a filled queue would have returned empty ids. All six are connected now, and a label is only taken when the net actually contributed to the decision (`candidate.hasNeuralNetContributor`), with the reservation released if the send produces no position.

Two things were left alone deliberately: realized P/L is still not a *training target* (the meta-labeler keeps the barrier's directional sample, since switching mid-dataset would mix two label semantics in one training set), and an over-long comment now skips the `|N:<id>` marker instead of replacing the position comment with a truncated fragment. No entry, exit, lot or risk path changed.

### Batch 204: a regime veto now vetoes the vote

`RegimeStateHardGate` zeroes a category the regime forbids - reversion in a confirmed trend, trend/momentum in a range - but only its *score* was zeroed. The vote still counted toward the minimum-voter rule, the quorum ratio and the conflict deadband, still took a contributor slot, and still added its weight to the ready-ratio denominator that then judged it. So one veto made three gates looser and one stricter at the same time, and because Batch 199 charges contributors with the closed trade's outcome, a strategy the regime forbade was credited or blamed for a position it was not allowed to open - through `m_strategyHealthScore`, that error fed the reliability multiplier of its future permitted votes.

The consensus scan now drops a hard-gated strategy before any of those accumulations. Entry count moves both ways, and both moves are the point: two permitted voters agreeing are no longer diluted by three forbidden ones, while a single permitted voter can no longer reach the two-voter minimum on the strength of a colleague the regime killed. Deweights are untouched (Breakout reversion at 0.25, Chaos at 0.40 still vote with a smaller score). Watch the new `[CONSENSUS-REGIME-VETO] <symbol> | N vote(s) hard-gated by regime | excluded weight= | counted votes=` line; a fully vetoed field now prints `[CONSENSUS-ABSTAIN]` instead of `[CONSENSUS-TIE]`. Risk ceilings, lot math, stops, sends and the exit authority are unchanged.

### Batch 205: the position-size ladder finally reads its own inputs

`CLiveAuthorityResolver` converts an `authorityScore` into the lot multiplier, and four of the terms that build that score - conviction, readiness, context and cost - were handed `0.0` on every consensus trade, because the consensus decision context had no writer for them. So no trade in the repository's history ever earned the `+0.08 / +0.07 / +0.05 / +0.05` those four bonuses pay, every consensus position was sized one to two rungs below the ladder the operator configured, and `InpAuthorityMinReadinessScore`, `InpAuthorityMinContextScore` and `InpAuthorityMinCostScore` changed nothing. The pipeline does measure all three (per signal, in its own evidence snapshot); the values simply never crossed into the decision.

They do now: the consensus loop captures each voter's evidence and publishes the winning side's mean, plus the ready-ratio numerator and denominator the log used to print as zeros. **Consensus lots get larger where the pipeline genuinely measures a ready, in-context, cheap signal, and stay exactly as small as they are where it does not** - each bonus is still conditional on a threshold, and with no pipeline the values stay zero rather than being guessed. Nothing about vetoes, the low-confidence refusal, the AI bootstrap caps or the risk gates moved. Earned bonuses now name themselves in the authority reason string, so a grown lot is traceable to the measurement that earned it.

### Batch 206: the minimum R:R stopped capping the take-profit

`CalculateStops` clamped the stop and then set the target to `MathMin(proposedTP, stopLossPips * minRR)`. `minRR` is a *minimum* reward-to-risk requirement, so the line silently converted it into a maximum take-profit: a strategy designed for 5R was taken out at 1.5R or 2R on every entry, and because the execution-cost gate measures `spread / TP`, the shortened target also made those same entries more likely to be refused as too expensive. It is now a floor (`MathMax`), so a wider designed target survives and a stop widened by the spread floor drags its target up with it instead of letting the trade ship under the required R:R.

Stop distance, lot size, per-trade risk and every gate are untouched - this changes where a winner is closed, not how big the position is. The sweep that found it checked five other suspected over-restrictions to the line and rejected them: a triple-counted spread term that a policy term dominates, a safe-mode per-symbol cap that cannot go stale because MT5 inputs cannot change mid-run, two quality-threshold arms whose decision classes are never published, a min-lot refusal that is this project's deliberate anti-round-up rule, and a fail-closed portfolio poison that is recomputed every pass by design. One real finding is deferred rather than guessed at: every ATR the EA reads is measured on the timeframe of the chart it sits on, because each per-symbol manager is initialized with that value - choosing a per-symbol operating timeframe is an operator decision.

### Batch 207: three strategy slots that never had a class were deleted

`SI_UNICORN_MODEL`, `SI_POWER_OF_THREE` and `SI_UNIFIED_ICT` named strategies that do not exist - no catalog row, no class, and no `GetType()` that could ever answer them. Their only code presence was three unreachable `case` labels in the regime weighting switch; their only operator presence was three `InpIntrabarEligibility*` inputs whose values landed on config rows 3, 5 and 6, rows no catalog entry selects. So those inputs were written at init and read by nobody: three dead controls in the inputs dialog under names that imply live per-strategy policy. 51 lines removed, with both enums keeping their explicit numeric values so no surviving slot moved.

No entry, exit, lot or risk path changed. `SI_EXIT_OPTIMIZER` was kept on purpose: `CExitOptimizer` is a real component, parked because wiring it would create a second exit authority - a decision about code that exists rather than a phantom identity.

### Batch 208: who voted a trade is read from the strategy catalog, not from a copy of its names

Five predicates in the candidate builder decided whether a trade had an indicator, an AI adapter, an ONNX model or the neural net behind it by searching contributor names for hard-coded substrings. Contributor names *are* the catalog row names, and the token lists had drifted: `MeanReversion` never matched the row `Mean Reversion`, `StatArb` never matched `Statistical Arbitrage`, `NYOpen` never matched `NY Open Gap`, `AsianRange` never matched `Asian Range Break`, and `Liquidity Sweep`, `Range Compression` and `Python Bridge AI` were absent from the lists entirely. Six of fourteen indicator strategies and one of five AI adapters were invisible to the live-authority gate.

That was not a reporting problem. The authority score that picks the lot multiplier awards a `+0.20` `INDICATOR` term, so those strategies' trades sat a rung low; the lower 0.55 confidence bar applies only to indicator-backed decisions, so a purely indicator trade from those rows was judged against the 0.65 standard meant for an unproven neural net; and Python Bridge AI, unrecognized as AI, never entered the bootstrap cap that holds an adapter with no track record - it took full size while earning no AI credit. Classification now comes from the row's own `kind` / `aiKind`, so a correctly added strategy is correctly classified and there is no fifth list anyone can forget to update.

Expect more and larger consensus trades from the six indicator rows, correct bootstrap capping for Python Bridge, and mixed AI-plus-indicator decisions no longer treated as AI-standalone. The vetoes, the refusal shape, the promotion thresholds and the risk gates are unchanged.

### Batch 209: the enable roster is written from the catalog, and `[CURATION]` names the strategies it means

`BuildStrategyFlags` hand-wrote fifteen slot assignments and twelve curated force-enables, and the two places that reported the roster back to the operator were both wrong. `[CURATION] Effective strategy set for X:` cast a flag-array index to `ENUM_STRATEGY_TYPE` - the two enums share no numbering, so Mean Reversion printed as `STRATEGY_CANDLESTICK`, Volatility Breakout as `STRATEGY_MEAN_REVERSION`, Liquidity Sweep as the bare number `17`, and Momentum as `0`. `CountEffectiveIndicatorStrategiesForSymbol` then subtracted four literal "AI slots" (17-20) that are actually Liquidity Sweep, Range Compression and Exit Optimizer, so the enabled-indicator count ran two low on the default roster - the Exit Optimizer's spurious `+1` cancelled its own `-1`, leaving Liquidity Sweep and Range Compression charged against themselves.

The roster is now catalog data. The flag builder loops the indicator rows, one `ConfigEnableForSlot` switch maps a slot to its operator input, and a row whose slot has no input prints `[CATALOG] <name> | enable slot N has no operator input - it stays off unless curated` instead of being silently absent. Curated membership moved into the row (`curatedEnable`), which is where it belongs for the plug-and-play contract: a new strategy needs a row, a slot and a case in that switch, and nothing else. Both reporting paths now walk the rows, so they name and count what registration will actually do.

Slot `SI_EXIT_OPTIMIZER` is gone: `InpEnableExitOptimizer` gates the Exit Optimizer *math engine* at `OrchestratorMathEngineHub.mqh:272,440`, and its one effect on the strategy roster was being misread as an AI vote. Operator-visible output changes only in accuracy - `[CURATION]` now lists real row names and no longer lists Exit Optimizer, and the skip guard at `EAOrchestrator.mqh:1624` sees the true count. Registration, weights, policies and every risk gate are untouched.

### Batch 210: the strategy factory builds AI adapters and nothing else

`CStrategyFactory` carried twelve indicator creators - `CreateMomentum`, `CreateCandlestick`, `CreateMeanReversion` and friends - that still called `SetScalpingMode`, `SetRequireTrendAlignment`, `SetSyntheticMode`, `SetHurstEngine`, `SetPythonBridge` and `SetOUEngine`, together with a seventeen-field `SStrategyConfig` to carry those values. `Create` is reachable from one place, inside the loop that only walks `CAT_KIND_AI` rows, and no indicator row has a `factoryName`, so none of it could ever run. The five adapters that *are* built never read a single field of the struct either: their real configuration is `PrepareCatalogAIAdapter`, which initializes the neural network with the symbol and its timeframe, and the ONNX buffer and Python bridge arrive as globals.

So this is deletion, not rewiring: the twelve creators, the struct, the eight assignments the caller made into it, four public helpers with no call site (`IsRegistered`, `GetRegisteredNames`, `GetCount`, and a `BuildConfigFromEA` stub whose comments admitted it returned placeholder values), and fourteen includes. `Create` now takes a name alone, and `[StrategyFactory] Initialized with N strategy creators` reports 5 where it reported 17. A trade path is unchanged; the second, unreachable way to construct a strategy no longer exists to confuse the next reader or half-implement.

### Batch 211: `[WIRE-STATUS]` tells you which strategy actually received its engine

Four strategies get their statistical engines injected after registration - Hurst into Trend, Support/Resistance and Mean Reversion, OU into Statistical Arbitrage, VPIN/OFI onto the manager - and every print describing that injection sat behind `logLevel >= 3`, while `InpLogLevel` defaults to 1. No journal this repository has produced says whether a single engine landed. A failed cast was worse than silent: a registered strategy that is not the class its catalog row names simply kept its engine pointer at NULL, and Mean Reversion's regime lockout returns *true* with no Hurst engine, so band re-entries stay eligible in a confirmed trend with nothing in the log to distinguish that from a properly filtered strategy.

One `[WIRE-STATUS] <symbol> | Trend=wired S/R=wired MeanRev=NO-ENGINE StatArb=not-registered | hurst=OFF ou=on ...` line per symbol now prints at init, and a cast failure prints `[WIRE-CAST-FAIL]`. Nothing was switched on or off: the fix is visibility, and the decision about whether a NULL engine should fail closed is left where it belongs - with the operator who can see it.

### Batch 212: the scan cadence controls bind, and a parked symbol no longer costs another symbol its scan

Three numbers decide how often this EA looks for a trade, and none of them was yours. `InpMaxSignalEvaluationsPerCycle` wrote a config field that no code read while the generator capped each cycle with its own literal 8 - under a comment claiming the budget was "config-driven only". `InpSignalScanOnNewBarOnly` wrote a field with no reader either, and the documents around it described a `[CADENCE-WARNING]` startup line and a "hard global override" that have never existed in the repository: `EvaluateSymbol` gates every symbol to one evaluation per bar of the chart's timeframe, unconditionally, so both states of the input described the same EA. It is deleted. The dormancy park - three no-signal bars earning a 30-minute evaluation blackout - was two anonymous constants, mixing bars and minutes: three quiet minutes on an M1 chart bought 30 minutes of not being looked at, ten times the entry chances lost, and there was no way to change it.

Now `InpDormancyStrikeBars` (3) and `InpDormancyCooldownMinutes` (30) exist, the cycle budget comes from the input, and `[SCAN-POLICY]` prints the posture once so it is in the journal instead of in a source file. Selection skips parked symbols, so a park costs only its own symbol, and the rotation advances by symbols examined rather than by the budget, which used to step past symbols whenever fewer than the budget were selectable. `[ENTRY-GATE] entries held this cycle | refused by=trade_cooldown position_limit unprotected_positions spike_pause profit_guard_halt basket_equity_halt` names the six holds that used to be fused into one silent `continue`. Every default equals the number already in the code, and no threshold, veto or lot moved.

### Batch 213: ADX tiering was multiplied twice, and VPIN toxicity never reached a lot

`CPositionSizer` registered an ADX lot modifier itself and `CEAOrchestrator` added a second configured instance to the same chain. Each one holds its own iADX handle and multiplies the lot by its tier, so a "strong" 1.3x shipped 1.69x and a "very strong" 1.5x shipped 2.25x of the lot the risk math had computed, and `[ADX-MODIFIER]` printed twice per sizing. On the consensus path the per-trade cap clamp caught it, which is why the symptom there was `[RISK-GATE-ADJUST]` churn and a tier ladder pinned at the ceiling; the five callers that go straight to the sizer - ATR scalp, fast scalp, grid recovery, spike hunter and Momentum's own sizing - run no such clamp and shipped the doubled lot.

`CVPINLotModifier` was the mirror-image defect: it read a `CVPINFilter` it had created itself, and nothing feeds ticks to a filter outside the math hub, so its warm-up test never passed and the designed 0.10-1.00x toxicity shrink never applied. A book with informed flow sized every trade at full size, `[VPIN-MODIFIER]` has never printed in this repository's history, and three documents said the modifier was applying it. The modifier now holds references to the hub's per-symbol filters, registered in the same loop that hands that pointer to Trend, S/R and the manager, and `[SIZING-CHAIN] modifiers=VPIN,Kelly,EquityCurve,ADX | vpin_filters=N | kelly=inert(...)` names the chain at every start, so a sizing input that reaches no multiplier is visible instead of assumed.

Both fixes reduce lot sizes; neither widens risk. Bayesian Kelly is left inert on purpose and says so - wiring it as written would multiply an already risk-sized lot by a fraction of bankroll and cut trades to roughly 1/13-1/40 of intended size on one closed trade's evidence. The compounding ladder's 5.0% band for $1,000-5,000 (after 1.5% for $500-1,000, with a comment on that line saying "<$1K") is flagged for you rather than guessed at: Batch 192's clamp caps it at your approved per-trade risk today, but the number itself is your call.

### Batch 214: a fast-scalp gate could be answered by another instrument's numbers

One `CFastScalpEngine` serves the whole symbol universe, and its fallback indicator cache is a single slot:
one symbol tag, one bar time, one ATR, one RSI. `RefreshIndicators` wrote each value as its own read
succeeded and restamped the tag only at the end, so when a handle went invalid or `CopyBuffer` came back
short, the cache held **the new symbol's ATR under the previous symbol's name**. The next lookup for that
previous symbol matched on the tag and was served the foreign number for the rest of its bar. Four decisions
read it: the spread-vs-ATR cost gate, the momentum-burst body test, the confidence bonus for a tight spread,
and through confidence the lot itself. Gold's M1 ATR is several times an FX pair's, so an EURUSD scalp could
clear the gate whose whole job is refusing trades whose spread consumes the take-profit. The RSI confirmation
took no symbol argument at all.

The same "missing data read as a number" mistake sat in the per-symbol signal cache. A failed RSI copy is
marked non-critical and left at `0.0`, and `0 >= 70` is false while `0 <= 30` is true — so the overbought
check admitted every BUY on no data, and the oversold check refused every SELL on that same missing value.
Both paths now fail closed on a number they cannot read, the way the slow path already did.

Reads land in locals and commit only when all of them succeed, so a failure leaves the cache stale but
truthful instead of mixed. And the refusals speak: `[SCALP-SIGNAL-REJECT] EURUSD | gate=spread_vs_atr` (or
`rsi_overbought`, `rsi_oversold`, `rsi_unavailable`, `indicator_refresh_failed`, `ema_handles_failed`,
`no_atr_or_point`) and `[SCALP-SIZING] ... sizer returned lot 0.0000`. A bar with no EMA crossover is the
market's normal state, not a refusal, so it stays silent. `[SCALP-GATE]` was throttled by one EA-wide slot,
meaning the first symbol refused in a minute muted the other twelve; the throttle is per symbol now. Six
`GetCached*` accessors with no caller and the two EMA fields behind them are deleted — a crossover needs two
bars, which a one-slot cache can never supply, so nothing could have read them.

Nothing about the scalp gate *policy* changed: same thresholds, same cooldown, same single
`CUnifiedRiskManager` call on the lot actually sent. What changed is which numbers those gates are given, and
whether you can see them refuse.

### Batch 215: three inputs you could set that reached nothing, and 92 log tags this EA never prints

Two classes existed to hold symbol state and were never written to. `CSymbolStateTracker` was allocated,
initialised with your symbol list and printed into the shutdown report; none of its seven record-or-test methods
had a caller, so `[SCALP-BLACKLIST]` has never printed here and the report it contributed asserted
`scalpBlacklisted=false, dormant=none` from a class with no way to learn otherwise. `CSymbolScanScheduler` was
never created at all - its one access route returned `NULL` and nobody called it. Both are deleted, together with
the matching dead fields in `CScanSchedulerRegistry`, which now keeps the one thing the code uses: which bar each
symbol was last seen on. That registry's `pendingNewBarScan` flag was set true and cleared by nothing, so its
report said `pending=Y` for every symbol after the first bar.

Three inputs go with them: `InpIntrabarScanSeconds`, `InpMaxIntrabarSymbolsPerCycle` and
`InpIntrabarBackoffMaxSeconds`. Each wrote a config field read only by the never-built scheduler's own
`SetInputParams`, which had no caller. They are removed rather than wired, because instantiating that scheduler
would put a second cadence authority next to the bar gate that already decides when a symbol is evaluated. If you
had set them, nothing you chose was in effect; the cadence you can actually set is
`InpMaxSignalEvaluationsPerCycle`, `InpDormancyStrikeBars` and `InpDormancyCooldownMinutes`.

The larger finding is in the documentation. Diffing every bracketed log tag the five root documents name against
the tags the code can print left **92 with no printer**, about two thirds of them in sentences saying the runtime
emits them - `[SCHEDULER-STATE]`, `[CADENCE-WARNING]`, `[MODE-MASK]`, `[AI-TOPOLOGY]`, `[ACCOUNT-CAPACITY]`,
`[TRADE-STATE]`, `[LIVE-AUTHORITY]`, `[SCALP-BLACKLIST]`, `[CONSENSUS-ACTIVE]` among them, plus two misnames
(`[CONSENSUS-VETO]` for `[CONSENSUS-VETOED]`, `[TRADE-CONFIRMED]` for `[ASYNC-TRADE-CONFIRMED]`). A tag list is how
you search a journal, so a phantom name produces a wrong conclusion rather than a missing one: silence where no
line can ever appear reads as "that routine ran quietly". The Diagnostics and Observability sections are now
restricted to tags verified in the tree, and the phantom names are recorded so nobody re-adds them.

No decision path changed: nothing deleted was reachable by a trade.

### Batch 216: the fast-scalp cache was computing six indicator series nobody read

`CScalpSignalCache` keeps one entry per symbol and has a single consumer - the fast-scalp signal check, which
reads four EMA values, the ATR, the RSI and the spread. The struct held twenty-one fields, and every M1 bar it
filled six more: an ATR value from five bars ago, three Bollinger bands, ADX, and current plus 20-bar-average
volume. Across thirteen symbols that is 78 `CopyBuffer` calls and thirteen averaging loops a minute, inside the
tick path, whose results no gate, no sizing decision and no log line ever looked at. Three shared indicator
handles per symbol were acquired at init for the same purpose. All of it is gone, along with the
`bidPrice`/`askPrice` fields that only the next line of the same function read, and five methods with no caller
(`HasNewBar`, `EnsureInitialized`, `GetCacheCount`, `IsInitialized`, `SetScalpSetup`).

One thing was deliberately not wired: `SetPeriods` could change the cache's EMA, ATR and RSI periods, and nothing
called it. The scalp engine's own periods are separate hard-coded literals. They match today only because neither
can move - calling the setter would let the fast path and the fallback path evaluate different EMAs on the same
symbol and disagree about the crossover. So the configurability is deleted rather than introduced, and the note
says so: if these numbers ever become inputs, both paths must read one place.

The last correction in this batch is about what the documentation told you the scalp engine is. Two sections
described three scalp *strategies* - Momentum, Spread and VolatilityBreakout - with file paths. Two of those files
have never existed. The third is real, complete, and not in the program: nothing includes it, it has no catalog
row, no enable input, nothing registers it. What actually decides a fast scalp is an M1 EMA 5/13 crossover, an
RSI(7) limit and a spread-vs-ATR cost test. The unregistered strategy file stays where it is, listed as something
you can activate, because switching on a trading path that has never traded is your decision and not a cleanup.

### Batch 217: volatility targeting was measuring a scalar that no lot reads

Four inputs - `InpEnableVolTargeting` (on by default), `InpTargetVol`, `InpVolMinScale`, `InpVolMaxScale` - build a
genuine volatility model. Per symbol it computes an ATR-based vol and a realised vol, blends them with an EWMA,
tracks where current vol sits in its own history, and derives a position scalar clamped to your min and max. It
updates every cycle and prints its answer into the journal once a minute per symbol.

Nothing reads that answer. All five of the engine's getters have zero call sites, and the sizing path's own
volatility modifier has been switched off since the day it was written: its flag is set to `false` in a struct
constructor and no code ever assigns it. So a log line showing `scalar=1.480` described a lot size that was not
happening, and the only thing your target-vol input was controlling was a number in a log.

I did not wire it, and the reason is the direction. With a 15% annual target and FX daily ranges that annualise to
roughly 8-13%, the formula's output is *above* 1.0 most of the time - around 1.2 to 1.9 on majors, and up to 3.0
because that is the default maximum. Volatility targeting is meant to shrink positions when markets get rough; this
default would mostly have grown them, in calm conditions, by a multiple nobody picked. Switching that on under a
"find the money leaks" mandate would have been choosing your risk policy from a constant.

What shipped instead is the truth in two places: `[SIZING-CHAIN] ... vol_targeting=inert(...)` at every start, and
`[VOL-TARGET] ... | applied=no(no sizing consumer)` on the measurement line. If you want it live, the decision
needed from you is the target and whether a scaler may ever exceed 1.0 - then the wiring itself is mechanical, and
one of the two duplicate implementations gets deleted so there is only one answer to the question.

### Batch 222: three consensus gates could never pass, so most committees were being thrown away

`InpConsensusConflictDeadband = 0.05` compared against a vote-count ratio that cannot fall below one dissenter
out of the votes cast (`1/19 = 0.053` on this roster): any single dissenting strategy vetoed the decision, and
only a unanimous committee could trade. The default is now `0.35` - the value the quorum config class was
audited to and marked `[PROFIT-02]`, which the input default had been overwriting - and the accepted range is
`[0.05, 0.50]`, because the old `[0.01, 0.20]` check refused the audited value outright.

The ready-weight floor was also unreachable, not merely tight: an unconfirmed regime snapshot stands every
voter aside at `0.30`, which caps that ratio at `0.36` against a `0.40` floor, and the snapshot's only writer
ran from the *optional* pipeline regime-cost-gate filter. With that filter off, no symbol ever got a valid
snapshot and the EA opened zero consensus trades. Consensus now refreshes the regime itself when the snapshot
is missing, and the refusal says which of the two causes it hit.

Two honesty fixes: the ATR14/ATR50 crisis veto set its flag, printed its line and then `return true`, so it
has never refused a trade while section 6 of `AGENTS.md` cites that tag as proof it does (it returns `false`
now); and `[RISK-VOL-GATE] ... action=halve_risk` announced a lot halving written into a field with zero
readers. That one stays unwired with the arithmetic on record - the stop is already `2.0 x ATR14` and the lot
is fixed-fractional over it, so a 1.6 ratio has shrunk it about `0.62x` already, and halving again would
double-count. `supportFloor` is documented as inert for the same reason: the winning share of votes cast is
always above 0.50, so no floor at or below 0.50 can refuse anything, and making it live would cut trades.

### Batch 221: fourteen module headers cut from 9-18 lines down to 3-7

The longest comments in the tree were file headers that listed the members and includes declared underneath
them, glossaried parameters the signature already names, or repeated one four-line include caveat across seven
`EnterpriseStrategyManager` satellites. Sixteen files lost 120 comment lines; what remains in each is the
ownership fact and the exception a reader cannot recover from the code - by-value holders and back-pointer
direction, index lifetimes, the include-order constraint that keeps `SPositionState` visible, and why the
atomic quorum setters could not follow their siblings out of the manager. Executable lines proved
byte-identical against a pre-edit snapshot; compile 8 root programs, 0 errors / 0 warnings.

### Batch 220: the quality floor has been measuring strategy weight as well as conviction

`directionalQuality` accumulates `voter confidence x registration weight` and divides by the number of voters,
not by the summed weight. On the default roster (Momentum 1.0 up to Volatility Breakout 2.0) that puts the
metric about 1.5x the committee's mean confidence, so `InpValidatorNewBarMinQuality = 0.68` admits trades on
roughly 0.41 mean confidence, and the consensus `confidence` figure inherits the same inflation. Rescaling it
would raise the admission bar on every symbol at once, which is an operator decision rather than a cleanup, so
this batch changes no comparison: a `quality_gate` refusal now prints `conviction=` beside `quality=`, and the
difference between the two is how much of the pass came from the weights.

### Batch 219: a resolved value with six readers and no writer

Every consensus decision that reaches consensus resolves its winning cluster
(`ResolveDominantCluster(winningContributors)`) and publishes the string for attribution. The enum field on
the decision context had no writer, so its six readers saw the default forever. Two of them are behaviour:
mean-reversion-dominant entries never got their own 1.5 minimum R:R floor (they were stretched to the general
2.0 - lots and stops untouched, only the take-profit), and the structure-cluster `[STRUCTURAL-EXIT]` could
never fire even though `InpEnableStructuralInvalidation` defaults to true. Both are live now; the exit is
restricted so it cannot overrule the last-stand or too-young abstains in the same function, and a shorter
mean-reversion TP means the `spread / TP` cost ratio is measured against the target that will actually be
placed, which can refuse a tight-spread entry that used to pass. Three documents claimed the mean-reversion
floor was 1:5; the literal is 1.5.

### Batch 218: the heartbeat the checklist tells you to verify had no printer

AGENTS.md section 6 asks for `[HEARTBEAT]` after any strategy, risk or execution change. Eight of the
heartbeat tags - `[HEARTBEAT]`, `[HEARTBEAT-FUNNEL]`, `[CONVERSION-RATES]`, `[NO-SIGNAL-ALERT]`,
`[RISK-BUDGET]`, `[HEARTBEAT-POSITIONS]`, `[HEARTBEAT-ASSET-CLASS]`, `[HEARTBEAT-FAMILY]` - had no `Print`
call site at all: `CDiagMgrHeartbeat` computed every field and sent it to the JSON log file, and the format
strings sat unused in `Core/Utils/LogMacros.mqh` (42 macros, 37 with no caller). Operational effect: the
journal could not show a scan loop running and producing nothing, which is the one thing the heartbeat exists
to show. They print now, from the values the JSON record already uses, and `[RISK-FAMILY-POS]` prints at the
per-family position cap - the only risk gate that refused through JSON alone. The other 29 macros are gone:
ten were duplicate copies of tags the code prints literally, eleven were unused JSON wrappers, seven named a
tag with neither emitter nor payload. The documents were swept too - about 250 lines corrected, including two
sections that described classes and files not in this repository and two engine behaviours (OFI weight
adjustment, VPIN weight reduction) that were designed in 2026-08 and never built.

## AI Integration

The EA supports three AI operating modes:

- **INDICATOR_ONLY** — Only human-designed strategy modules generate tradable signals
- **AI_ONLY** — Only AI adapters (Neural, Transformer, Ensemble, ONNX) generate signals
- **HYBRID** — Both indicators and AI participate; AI confirmation adds a confidence bonus

**AI Adapters:**
- **Neural Network** — Online-learning feedforward network with feature vector validation
- **Transformer** — Multi-scale attention with 64-dim, 4-head architecture
- **Ensemble** — CatBoost + XGBoost + LightGBM stacking
- **ONNX** — Python-trained models exported to ONNX, executed natively in MT5

All adapters are symbol-scoped, bar-cached, and register through the enterprise strategy manager for consensus participation. Disabled adapters are not instantiated.

**AI Vote Heartbeat Monitoring (L11-004):**
Runtime verification of `[AI-VOTE]` heartbeats is now implemented. The diagnostics manager tracks vote activity per symbol per AI type (NeuralNet, Transformer, Ensemble, ONNX). If any enabled AI adapter fails to log a vote within 30 seconds during active trading, a `[AI-VOTE-MISSING]` warning is emitted with symbol, AI type, last vote timestamp, and staleness duration.

## Python Integration

The Python ML pipeline (`Python/`) provides:

- **Feature Engineering** — 57 universal features + 26 Deriv-specific + asset-class extensions
- **Training Scripts** — Per-asset-class model trainers (CatBoost, XGBoost, LightGBM, stacking)
- **ONNX Export** — Trained models exported to `Resources/model.onnx` for MT5-native inference
- **ZMQ/HTTP Bridge** — Real-time prediction server with health monitoring and reconnection
- **Feature Cross-Check** — Validates Python-vs-MQL feature parity

## Project Structure

```
MultiStrategyAutonomousEA.mq5       # Main EA entry point (production)
MultiStrategyTestingEA.mq5          # Standalone testing EA with Complete Test Profile System
IndicatorManager.mqh                # Singleton indicator cache
Core/
  Engines/                      # Market analysis engines (Trend, Regime, Volatility, Hurst, VPIN, OU, OFI, VWAP, VolumeProfile, CVD)
  Pipeline/                     # UnifiedSignalPipeline (regime, cost, spread filtering)
  Management/                   # EnterpriseStrategyManager, PositionLifecycleManager, SymbolUniverseBuilder
  Risk/                         # UnifiedRiskManager, PositionSizer, PortfolioRiskManager, CorrelationEngine, EquityCurveManager
  Trading/                      # TradeManager, PositionStateManager, TradeAttributionManager
  Scalp/                        # SpikeHunterEngine, GridRecoveryEngine, ATRScalpingEngine, FastScalpEngine
  Strategy/                     # AI adapters (ONNX, Transformer, Ensemble), StrategyBase, StrategyRegistry
  AI/                           # AIFeatureVectorBuilder, PipelineScaler, NNModelStorage
  Processing/                   # TickSafetyMonitor, DerivAssetProfiler, MultiAssetProfiler
  Signals/                      # SignalDiagnostics, TimeframeConsistency
  Monitoring/                   # PerformanceAnalytics
  Visualization/                # VisualDashboard, ChartDrawingManager
  Utils/                        # PythonBridge, Instruments, Enums, SessionManager, ErrorHandling
  Cache/                        # ATRCache, ConsensusCache
Strategies/                         # 15 strategy modules
Python/                             # ML training, ONNX export, ZMQ bridge
Resources/                          # Trained ONNX models
Dashboard/                          # Dashboard components
```

## Documentation

| Document | Description |
|----------|-------------|
| [SYSTEM_STRUCTURE.md](SYSTEM_STRUCTURE.md) | Full architecture and component ownership |
| [RUNTIME_DECISION_GRAPH.md](RUNTIME_DECISION_GRAPH.md) | Runtime decision path documentation |
| [SYSTEM_AUDIT_TRACE.md](SYSTEM_AUDIT_TRACE.md) | Lifecycle trace and audit history |
| [changelogs.md](changelogs.md) | Dated batch changelog |
| [AGENTS.md](AGENTS.md) | Agent workflow contract |
| [MAINTENANCE_PROTOCOL.md](MAINTENANCE_PROTOCOL.md) | Forward maintenance protocol |

## License

Proprietary. All rights reserved.
