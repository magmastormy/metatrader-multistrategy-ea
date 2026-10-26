# MetaTrader Multi-Strategy Autonomous EA

![Status](https://img.shields.io/badge/status-production-blue)
![Batch](https://img.shields.io/badge/batch-261-green)
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

1. **Install** — Copy `MultiStrategyAutonomousEA.mq5`, `Core/`, `Strategies/`, `Resources/`, and `IndicatorManager.mqh` to your MT5 `Experts/` folder
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
| — correlation thresholds | 0.4 / 0.7 | Not an input. `InpCorrelationBlockThreshold` does not exist in any `.mq5`. Correlation is enforced once, in the pre-trade gate (`RiskValidationPipeline.mqh:476` calls `ValidateCorrelationLimits`; the REDUCE shrink is `:713`). The `CPositionSizer` correlation path was deleted in Batch 226, and `EAOrchestrator.mqh:850-851` says so where the switch used to be set. |

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
- **The `[LiveAuthorityResolver]` status block that was to print `pf=` and `eligible=Y|N` per tracked AI strategy could never print** - its only reader chain dead-ends at `CEAOrchestrator::GetStatusReport()`, which has no caller, and Batch 247 deleted it. What is observable is `[AUTHORITY-CONFIG]` at init and the per-decision `[AUTHORITY-REJECT]` / `[AUTHORITY-REDUCED]` lines. `PROVEN_AI`.
- **Not fixed, and not silently:** per-family demotion to shadow, and the trial tracking those three inputs used to imply, do not exist (Batch 238 deleted the inputs; there was never a trial store). The `[LIVE-AUTHORITY]`, `[AUTHORITY-TRIAL]` and `[AUTHORITY-RESULT]` tags named in SYSTEM_STRUCTURE.md appear in no source file and never have.

### What the operator will notice after Batch 173 (authority now sets the lot)

This is a live-sizing change. The ladder stopped being a log line.

- **Low-authority trades are materially smaller.** Candidates below the 0.35 score rung are sized at `bootstrapMult * 0.5` (0.25x of approved risk on stock defaults); unproven AI-only candidates are capped at 0.5x; a fully-scored hybrid candidate is still 1.0x. Total exposure and per-symbol lot counts should drop and the per-trade equity swing with them. That is the change working.
- **A symbol can be sized out of existence, and it says so.** Where the approved lot times the multiplier lands under `SYMBOL_VOLUME_MIN`, the trade is **refused rather than rounded up** — `CPositionSizer::NormalizeVolume` would have clamped it back to the minimum and handed the whole reduction straight back. Each refusal logs `[AUTHORITY-REJECT]` twice (the arithmetic, then which levers would bring the symbol back) and increments a per-symbol and session counter that appears in the `[CandidateBuilder]` status block as `authorityLotRefusals total=N`. Coarse-tick synthetic indices and small accounts will see this first.
- **Every shrink prints `[AUTHORITY-REDUCED]`** with the multiplier, the before/after lot, the before/after risk percentage and the reason. These two tags are the first real writes to `FMT_AUTHORITY_REJECT` / `FMT_AUTHORITY_REDUCED`, which have been defined since Batch 168 with no consumer while AGENTS.md §6 kept listing them as verification evidence.
- **The daily risk budget follows the actual lot.** `candidate.riskPercent` is rescaled by the same ratio before the send, because `RegisterExecutedTradeRisk` books it; otherwise the gate would reduce exposure while the budget kept charging full risk.
- **Do not read the first session as strategy regression.** Judge it against `[AUTHORITY-REDUCED]` counts and the refusal breakdown, not against last month's trade count.
- **Levers, in order of preference:** widen the stop at the same risk percentage (raises the approved lot above the minimum), revisit the `AUTHORITY_MIN_*` floors in `LiveAuthorityResolver.mqh`, or accept the smaller size. There is no input that turns the ladder back off — that would mean removing the call at `EAOrchestrator.mqh:3608`.
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

- **What changed:** `ValidateTradeRequest` now runs once, at the end, against `candidate.lotSize`. It moved rather than being added because each approval keeps a virtual reservation until its TTL, so two calls would count the same trade twice. (Batch 239 added the other ending, and found the one this line could not see: a *filled* trade was still counted twice, because no code discharged its reservation when the position appeared.)
- **What to expect on the first session:** fewer and smaller consensus entries, never larger. Refusals are countable: `[RISK-GATE-REJECT] ... reason=final_lot_validation`, `reason=adjusted_lot_below_min`, `reason=correlation_reduce_below_min_lot`, and `[RISK-GATE-ADJUST] symbol | lot=A -> B | risk=x% -> y% | reason` when the gate asked for less and got it.
- **Three gates that could not refuse now can:** a correlation reduction that cannot be expressed above the broker minimum used to approve the full lot with the discount silently gone; a lot above `SYMBOL_VOLUME_MAX` printed "caller must cap" and returned approval; the validator's quality floor was derived from the very quality being compared, so `InpValidatorNewBarMinQuality=0.68` / `InpValidatorIntrabarMinQuality=0.70` did nothing for the two consensus classes that carry most entries. That last one tightens entries: the floors become 0.612 / 0.63 / 0.595 instead of 0.40 / 0.45.
- **Stop distance is volatility-aware and unit-consistent:** `atrValue` was hard-wired to 0, so the ATR branch in `CalculateStops` never ran; ATR(14) now comes from the shared indicator cache. The broker minimum stop was compared in price units against point counts, roughly 100,000x too small on 5-digit FX, so the spread-folded floor never bound.
- **One lifecycle bug:** `CMeanReversionStrategy::Cleanup()` released a Stochastic handle owned by `CIndicatorManager`, which releases it again in `DestroyInstance()` — the call AGENTS.md §3.5 requires. Shared handles now stay with their owner; handles a strategy creates itself are still released by that strategy.

### Batch 192: what changes in the logs and in sizing

- **Fast-scalp now reserves risk once, not twice.** The entry gate and the pre-send gate both called `ValidateTradeRequest` on the same lot, and every approval holds a virtual position until TTL pruning, so one scalp double-counted against portfolio and daily-risk limits and filed two approvals. The entry-stage gate survived because its request is the one that carries the cluster code.
- **A risk-manager lot cut is now visible:** `[SCALP-RISK-ADJUSTED] XAUUSD | lot 0.05 -> 0.03 | reason=...`. Adoption is shrink-only — the pipeline can round a reduction up to the broker minimum, and that is no longer taken.
- **Compounding tiers can no longer size above the envelope.** A tier wrote its raw risk percent straight into the position sizer, which does not clamp, while the envelope clamp applies only on the risk-manager path: the per-trade cap check then refused the entries, so a tier could look applied and trade nothing. `[COMPOUNDING-TIER] Applied to PositionSizer` names the clamped value when it binds.
- **`[RISK-ENVELOPE]` no longer skips a warning-only clamp,** and the line gained `ddWarn A->B`.
- Two things reported during the audit were disproved before being acted on: the daily-loss halt clears itself at the trading-day roll (`UnifiedRiskManager.mqh:1338`), and the CVaR gate is fed by the equity-curve buffer (`:680`). Neither was "fixed".

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
**Corrected by Batch 251:** that last clause was never true. `AdaptToRegime` scaled the threshold into a local, iterated the managers with an empty body and returned, so the factor reached no strategy on any cycle - publishing the regime made `[MARKET-REGIME]` truthful, not the adaptation. The method is deleted; the entry, lot and risk arithmetic this entry says is unchanged is unchanged for the same reason it always was.

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

Slot `SI_EXIT_OPTIMIZER` is gone: `InpEnableExitOptimizer` gates the Exit Optimizer *math engine* at `OrchestratorMathEngineHub.mqh:272,440`, and its one effect on the strategy roster was being misread as an AI vote. Operator-visible output changes only in accuracy - `[CURATION]` now lists real row names and no longer lists Exit Optimizer, and the skip guard at `EAOrchestrator.mqh:1584` sees the true count. Registration, weights, policies and every risk gate are untouched.

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

### Batch 261: the timeframe-consistency island is gone - and the gate that only pretended to consult it was switching consensus off

Two things, found in the same line of code.

- **A class nobody fed.** `CTimeframeConsistency` (608 lines) aggregates per-timeframe votes and resolves conflicts
  between them. Nothing has ever handed it a vote: its two feeding methods lost their only caller when Batch 260 deleted
  `ProcessMTFSignals`, and the 2026-10-23 journal says the same thing from the other side - 22
  `[TimeframeConsistency] Initialized with mode:` lines (one per symbol for the manager's copy, one per symbol for the
  pipeline's, which is now gone) and **zero** lines from any other printer in the file. Its conflict warning cannot fire
  because its signal list is structurally empty. So the documents claiming consensus resolves mixed-timeframe conflicts
  described a subsystem that only ever introduced itself.
- **Its failure branch could not fail either.** The manager treated it as mandatory and printed
  `ERROR: TimeframeConsistency initialization failed` if its `Initialize` returned false - but that `Initialize` assigns
  three fields and returns `true`, with no other exit. Only an out-of-memory allocation could have stopped startup.
- **The real bug was in the gate, not the island.** `ConsensusEngine.mqh:109` tested
  `pipeline != NULL && tfConsistency != NULL` before running consensus. The second term was decorative. The first was not:
  the pipeline is an operator input, `InpUseSignalPipeline` (default `true`). Switch it off and `m_pipeline` is NULL, the
  gate answers `NONE` on every symbol on every scan, and the EA opens zero consensus trades - quietly, with no reject or
  gate line to explain it. That is the "blocked book looks like a quiet market" failure, reached from one checkbox.
- **Now:** the gate tests `m_src.IsManagerInitialized()` - the flag the manager sets only after a real initialization, and
  an accessor that already has two live readers. This is the honest condition, because the filter chain is optional by
  design: every pipeline use inside the evaluator is NULL-guarded (`:208`, `:419`, `:515`, `:539`, `:582`) and a vote
  passes unfiltered when there is no filter to run. With the shipped `true` nothing moves - 11 `Pipeline: ENABLED` lines,
  0 `DISABLED` in that session - so the fix is proved by reading rather than observed.
- **Deleted:** `Core/Signals/TimeframeConsistency.mqh` with `STimeframeSignal`, `ENUM_CONFLICT_RESOLUTION` and both of
  its prints; the manager's member, getter, 30-line allocate/rollback block and two teardown copies; the forwarder in
  `EnterpriseStrategyManager.mqh`; the forward declaration in `OrchestratorFwd.mqh`. 7 added / 661 deleted across five
  files. No quorum, deadband, threshold, lot, stop, take-profit or exit moved.

### Batch 260: a strategy's vote reserved the daily risk budget, and every voter was polled twice per scan

Two money defects in the same seam, both counted out of the attached 2026-10-23 journal.

- **Votes were holding money.** That session carries 1,092 `[RISK-VIRTUAL] reserve` lines booking 67.08% of risk against
  **five** fills. 1,024 of them print an empty `cluster=`, which is the strategy-poll shape (only `CandidateBuilder.mqh:470`
  and `FastScalpEntry.mqh:70` ever assign a cluster), and 953 are at lot 0.01 - the placeholder a strategy builds for a
  signal it is only deciding whether to emit. One Support/Resistance vote in one scan booked two reservations and printed
  its DIAG line twice (`16:27:59.229` / `16:27:59.230` / `16:27:59.231`, owners `..._1443626511` and `..._1443628039`),
  so ~500 votes cast held ~1,000 reservations. 52 releases and 253 prunes means roughly 787 of those holds ended only when
  their 60 s TTL expired, and peak concurrent reserved risk measured 35.21% against `InpMaxDailyRisk = 4.0`.
- **And the votes were then refused by it.** All five `[RISK-DAILY-LIMIT] ... daily_risk_would_exceed` refusals carry
  `phase=TURTLE-SOUP` or `phase=MOMENTUM` - a gate refusing a strategy its own teammates' phantom holds - and seven strategy
  rejects read `Virtual reservation conflict on <symbol> (opposing candidate already reserved)` with
  `[RISK-DAILY-CAP] ... entry_used=0.00% | mtm=0.00% | open_exp=0.00%` beside them. Now `reserveBudget=false` reaches the gate
  from the three poll sites (`StrategyBase.mqh:460` for eleven strategies, `MeanReversionStrategy.mqh:405`,
  `StatisticalArbitrageStrategy.mqh:263`), so a vote answers the gates and claims nothing. `final-lot` and the four engine
  pre-send tags still reserve - nothing was loosened for a trade.
- **Every voter was polled twice, and the second answer destroyed the first.** `CConsensusEngine` polled the voter
  (`ConsensusEngine.mqh:531`) and then handed the same strategy to `CUnifiedSignalPipeline::ProcessSignal`, which polled it
  again. A strategy that records its emission - Momentum writes `m_lastSignalTimestamp` at
  `SimpleMomentumStrategy.mqh:769` - fails its own cooldown (`:566`) on the repeat call and returns NONE, so consensus dropped
  the vote and printed `[CONSENSUS-FILTERED] ... | filtered by ` with a blank name (`LogResult` names a filter only on a veto;
  nothing vetoed - the strategy refused to answer twice in a row). Three Momentum signals, three
  `[MOMENTUM] Filtered: MOMENTUM_COOLDOWN` receipts, three of the five blank-filter lines. The repeat also double-counted
  `m_signalsGenerated`/`RecordSignal()` and printed 611 `[S/R-LOT-DEFERRED]` lines for a path that runs once per scan.
- **Now:** `ProcessSignal(symbol, tf, rawSignal, confidence)` filters the signal the voter already produced, confidence keeps
  its in/out contract, and the budget-exhausted return names itself (`m_lastFilterName = "BudgetExhausted"`), so that tag can
  no longer print blank while the pipeline returns NONE.
- **Deleted with the second poll:** `ProcessMTFSignals` (zero call sites), `Core/Pipeline/SignalPipelineAggregator.mqh`
  (54 lines, its only reader), the pipeline's own `CTimeframeConsistency` holder with two `[UnifiedSignalPipeline] ERROR:`
  lines that no build needed, the `component initialization incomplete; fail-closed startup` line it justified, and
  `m_lastRawSignalNone` with its uncalled getter. What remains of that subsystem is the manager's instance - allocated,
  initialised, NULL-tested at `ConsensusEngine.mqh:109`, and consulted by nobody, which is why the four docs that said
  consensus resolves mixed-timeframe conflicts now say it does not, and the island is queued (#116).
- **Read `[RISK-VIRTUAL] owner=` differently from this batch:** it is `<symbol>_<phase>_<ORDER_TYPE>_<micros>`, so a
  reservation says which gate booked it. Counting `reserve` lines in an older journal measures votes, not trades.
- **Recorded, not fixed:** the fast-scalp gate at `FastScalpEntry.mqh:74` approves and its caller can still walk away at
  `:102`/`:126`/`:138`/`:144`, leaving the hold to its TTL (64 of the 1,092). Closing it needs the owner tag returned to the
  caller - Batch 239's gap, now attributable.

46 added / 178 deleted across eight files, one of them deleted. No lot, stop, take-profit, quorum or threshold moved: a poll's own verdict is
unchanged, because every read of the reservation book inside a call happens before the reserve or subtracts it.

### Batch 259: the init line said `0 active strategies` in every build, and it was measuring the wrong moment

`AutoRegisterStrategies` registers against a `CStrategyRegistry` the orchestrator has not filled yet, so
`StrategyRegistryState.mqh:67` locks all 16 rows disabled - the 2026-10-23 journal carries 176
`[ENTERPRISE] Strategy <name> disabled by registry` lines - and `SyncEnabledWithRegistry` releases them about 7
seconds later (176 `Synced strategy ... -> enabled=true`, eleven `reconciled 16 strategy enable-flags`). Both init
prints read the *enabled* count before that reconciliation, so they reported an empty roster no matter what the
book ended up as, and AGENTS.md section 6 documents one of them as the per-symbol roster count.

- **Now:** `[ENTERPRISE] Manager initialized for <symbol> | registered=N | profile=... | baseTF=... | tfOverride ...`
  and `Auto-registration complete. Registered strategies: N`, while the reconciliation line carries the state that
  gates trading: `reconciled N strategy enable-flags with registry | enabled=n/m | liveVoting=k`. It prints even when
  `N=0`, because a line that only appears when a flag flips cannot tell "already correct" from "nothing is voting".
- **Deleted with their last caller:** `CStrategyStateReporter::GetActiveStrategyCount` and the manager forwarder
  behind it. `IsStrategyEnabled` keeps six live readers, so the vote path is untouched.
- **Unreachable classes gone:** `Strategies/SMCFiles/PremiumDiscount.mqh` (325 lines) and
  `Core/Strategy/StrategyWrapper.mqh` (45) were included by nothing, and `Core/Trading/IntelligentSLGuard.mqh` (83)
  was held by value in `CPositionLifecycleManager` with no method call on it - `m_slGuard.` appears nowhere. Its
  include, member and forward declaration go too; wiring it would have created a second stop authority beside the
  lifecycle guard and the circuit breaker.
- **One deletion reversed inside the batch:** `Core/Scalp/ScalpVolatilityBreakout.mqh` came back byte identical.
  Batch 216 recorded it as a deliberate keep - a complete strategy class that nothing includes is neither
  unreachable construction nor an undriven feature, and deleting it closes an option that only you should open.
- **Left for its own batch:** `CExitOptimizer`, `CVolumeProfileEngine`, `CVWAPEngine` and `CCVDEngine` are built,
  initialized and registered, and then never consulted (their registry getters have zero callers). Four inputs, two
  registries and the `[VOLUME-PROXY]` line move with them, and an exit optimizer is a trading decision, not hygiene.
  `CTrendTrailingStop` looked dead by its setter list and is not - `StrategyTrend.mqh:459` calls
  `CalculateTrailingStop`.

22 added / 485 deleted across nine files. No entry, exit, lot, quorum or threshold moved.

### Batch 258: the pipeline's five filters were announced as ON and had never run, because one setter was never called

`CUnifiedSignalPipeline::SetMathRegistry` has no call site in any build. Every filter, every engine getter
and the manager's regime refresh read `m_mathRegistry`, so all of them answered NULL and the EA traded as if
the pipeline had no engines at all.

- **What that means for a journal.** `[UnifiedSignalPipeline] Initialized with filters: Trend=true Volatility=true
  Liquidity=true Structure=true RegimeCostGate=true` prints at init, while `SignalPipelineFilter.mqh:41` returns
  "pass" for a NULL engine. So `[COST-GATE]`, `[ENTRY-VETO]`, `[PIPELINE-THRESHOLD]`, `[PIPELINE-HEALTH]`,
  `[REGIME-STATE]` and `[MARKET-REGIME]` each have **0** lines in the attached 2026-10-23 session, and so does
  `[CONSENSUS-REGIME-VETO]`: `ConsensusEngine.mqh:211` fetches the regime engine, gets NULL, and `:213` returns
  weight `1.0`. Batch 204's regime veto, Batch 222's 0.30 stand-aside and the per-category regime multipliers have
  never touched a vote.
- **And for sizing: the bonuses were paid from constants.** The live-authority ladder reads the pipeline's evidence
  (`ConsensusEngine.mqh:581-604` -> `LiveAuthorityResolver.mqh:213-223`), and unbound that evidence is never
  measured - it is its own default: `contextScore = 0.5` (`SignalPipelineTypes.mqh:357`) against
  `InpAuthorityMinContextScore = 0.48`, `costScore = 0.72` written before the NULL return
  (`SignalPipelineFilter.mqh:38`) against `InpAuthorityMinCostScore = 0.50`, and readiness computed from
  `warmupScore = 0.58` (`SignalPipelineTypes.mqh:33`) against `InpAuthorityMinReadinessScore = 0.52`. So all three
  bonuses - `+0.07 +0.05 +0.05` - are earned with no engine consulted, and the journal shows exactly that:
  `[AUTHORITY-REDUCED] Jump 25 Index | mult=0.85 | ... | reason=AUTHORIZED | score=0.70 | AI INDICATOR QUALITY
  CONVICTION READINESS CONTEXT COST`. About a quarter of that `0.70` measures nothing, and `score` is what picks the
  lot multiplier. Recorded, not fixed: making those three tests require a measurement is a **tightening** that
  shrinks live lots, so it is your call, not a cleanup.
- **What shipped instead of a silent switch-on.** `InpPipelineEngineRegistry` (default `false`) binds the
  orchestrator's registry to each symbol's pipeline at `EAOrchestrator.mqh:1836`, and
  `[PIPELINE-ENGINES] <symbol> | registry= | trend/vol/liq/struct/regimeCost= | readinessTTL=` states per symbol
  which mode is running. Binding is a **tightening** - five veto layers, the regime stand-aside and confidence
  attenuation start applying to a book that already refuses 97 scans at the two-voter floor against 5 fills - so it
  is your call, not a default. `InpReadinessReuseTtlSeconds` only reaches the engines once bound.

Behaviour with the input off is byte-for-byte what every previous build did.


### Batch 256: the consensus diagnostics printed nothing because nothing wrote them - and the manager's teardown deleted an object it did not own

Followed Batch 255's queued note down one more floor and found the same shape twice, plus a real teardown bug.

- **Five tags the docs told you to verify have no emitter.** `[CONSENSUS-SNAPSHOT]`, `[STRATEGY-REJECTS]`,
  `[ROLE-CLUSTER]`, `[QUIET-REASONS]` and `[NO-SIGNAL-ALERT-CONSENSUS]` all lived behind
  `CDiagnosticsManager::EmitConsensusDiagnostics`, which has zero call sites. Its 25 counters were no better: not one
  of the 73 `Increment*` methods on `CDiagMgrCounters` (or the forwarders on the diagnostics manager) had a caller,
  and `MaybeLogDiagnostics` - the only printer - had none either. They printed nothing, about nothing, forever.
- **`[CONSENSUS-DIAG]` is strategy-side only.** The attached 2026-10-23 session carries 995 of those lines
  (`[CONSENSUS-DIAG] Volatility 75 Index | BUY | Mode: Mixed | Conf: 100.0% | Weight: 1.80 | Reason: SR_UNSET`) and
  none of them is the counters pair (`... | Generated= | AfterPipeline=`, `Role: Primary= | Cluster: Trend=`), which
  matches 0 times. Read `[CONSENSUS-REJECT]`, `[CONSENSUS-QUORUM]`, `[CONSENSUS-VETOED]` and `[ENTRY-GATE]` for why a
  scan traded nothing; the deleted counters were never the answer.
- **`ReleaseOnDeinit()` deleted the orchestrator's own objects.** Each symbol manager held injected pointers to
  `&m_diagnosticsManager` and `&m_attributionManager` - by-value members of `CEAOrchestrator`, never `new`ed - and the
  deinit path ran `delete` on both. Detaching with the shipped 13-symbol roster did that thirteen times to two
  addresses the orchestrator still owns and later destroys itself; an init-failure rollback runs the same pair. The
  deletes are gone, so a detach now leaves both objects intact for whoever reads them next in teardown
  (`NNDiagPrintSummary("deinit")` runs before the release for exactly that reason).
- **What went with it:** `DiagMgrCounters.mqh`, `DiagMgrAggregator.mqh` and `DiagMgrConsensusReport.mqh` deleted
  outright (1,026 lines), `DiagnosticsManager.mqh` 697 -> 320, the manager and reporter reads that fed the report, the
  now-unread `GetDiagnostics`/`GetDiagnosticsConst` pair and the injected-diagnostics pointer chain including its init
  call (its last reader was the deleted report). `SetConsensusDiagnosticsIntervalSeconds` went too - it configured a
  field only the unreachable printer read. 12 added / 1635 deleted across eight code files.

Nothing here touched an entry, exit, lot, threshold, quorum or veto: every deleted line was unreachable. The one
reachable change is at teardown, and it can only remove undefined behaviour.


### Batch 255: a closed trade was counted twice in the strategy park, and the metrics nobody wrote are gone

This is the follow-up to Batch 252's "prove the health monitor's accessors against a caller chain". It found one real
bug, one log lie, and 486 lines of code no build could enter.

- **Every closed trade entered the health sample twice.** The closed-trade loop called
  `UpdatePerformance(name, netProfit)` - which already forwards to the health monitor - and then called
  `RecordTradeResult(stratIdx, netProfit)` again on the next statement. `consecutiveLosses` grew by two per real loss, so
  the park rule `consecutiveLosses >= 5` fired after **three** losing trades instead of five, and the "20-trade rolling
  window" held ten real trades with each outcome duplicated. The second call is deleted; the park now enforces the rule
  its own text describes. Win rate was unaffected (numerator and denominator both doubled).
- **Six methods had an unreachable half.** `CEnterpriseStrategyManager`'s constructor allocates the health monitor, so every
  `if(GetHealthMonitor() != NULL) { ...; return; }` in `CStrategyPerformanceHealth` is always taken. The code underneath -
  a real rolling Sharpe computation, a `>= 10 closed trades` disable rule, a cooldown expiry test, and the only writer of
  the roster's `winRate`/`profitFactor`/`sharpeRatio`/`recentWinRate` - had never run in any build, and
  `CStrategyLifecycle::CheckStrategyDisabling`'s 32-line loop (a second park authority, printing
  "disabled by AI model degeneration check") was unreachable for the same reason. All of it is deleted, together with the
  state only it touched: the roster's second rolling window (`recentTrades[20]`, never written), `avgLoss`,
  `maxConsecutiveLosses`, `lastUpdate`, `regimePerformance[]`/`regimeTrades[]`, and on the monitor `healthScore` (a second
  copy read only by its own dead getter), `sharpeRatio` (**no writer anywhere in the tree**), `profitFactor`,
  `disabledUntil` (armed by nothing) and seventeen dead accessors.
- **`[Enterprise-Adaptation] ... (WinRate: ...)` printed 0.00 beside every park.** Its argument was a roster field with no
  live writer. It now prints the monitor's lifetime and recent win rates - the sample the decision actually came from:
  `(WinRate: 0.62, recent: 0.40, Losses: 6)`.
- **Also worth knowing before you read a journal:** `CDiagnosticsManager::EmitConsensusDiagnostics` had no caller, so
  `[CONSENSUS-SNAPSHOT]`, `[STRATEGY-REJECTS]`, `[ROLE-CLUSTER]`, `[QUIET-REASONS]` and `[NO-SIGNAL-ALERT-CONSENSUS]`
  could not appear in any journal - and the 25 counters they would have printed had no writer either. Batch 256 deletes
  the whole chain; the 2026-10-23 journal already shows it (995 strategy-side `[CONSENSUS-DIAG]` lines, none carrying `Generated=`).

Operator-visible behaviour: a strategy that loses three in a row is no longer parked early; the park still releases on the
next governance pass because no code arms its cooldown (arming a one-hour hold is a tightening, and it is on the ask list).
No lot, stop, take-profit, quorum, threshold or exit moved.

### Batch 253: the first runtime journal - what it showed, and what it corrected

This is the first batch judged against a running journal instead of against the tree. Three of its findings were
invisible to 250 static sweeps, and two of them corrected conclusions this batch had already written down.

- **A blocked account and a quiet market used to write identical journals.** The scan entry point opened with a bare
  `return` when terminal or program algo-trading is off. The attached chart printed
  `[TRADE-BLOCKED] scanning stopped | terminal=NOT-allowed | program=allowed`, which is the terminal's AutoTrading
  button - not the per-expert flag, and not something `terminal.ini` `[Experts] Enabled=1` speaks for. `[HEARTBEAT] scans=`
  stops growing while the block holds, because the scan counter sits below the return.
- **A saved chart can still be demanding unanimity, and now says so.** The conflict deadband is compared against a vote-count
  ratio, so the finest conflict a scan can express is one dissenter out of the votes cast. This chart carried `0.05`; five
  symbols each printed `[CONSENSUS-DEADBAND-FLOORED] asked=0.050 enforced=0.333 | votes 2-1`. Those decisions had been
  vetoed by the old arithmetic. The veto is now floored at `1/votes_cast` - one dissenter can never block, two or more still
  answer to your own number. `finestDissent=` in `[CONSENSUS-QUORUM]` is the *eligible*-voter figure and is only the init
  warning; the votes actually cast are what decide.
- **The funnel printed zeros beside the fills it had counted.** One journal block contained
  `[HEARTBEAT] ... trades_opened=0` and `[HEARTBEAT-FUNNEL] ... signals_sent=3`, and `[CONVERSION-RATES]` said
  `generated=0 ... sent=0.0% | no_signal=100.0%` in a session that had five `accepted=true | filled=0.01 | retcode=10009`
  receipts in its first half hour. Eleven of eighteen telemetry counters had no writer, every rate divides by a stage, and
  three stages incremented in one statement. The telemetry class is now seven counters with one writer each; `signals_sent`
  is the fill count, so there is no separate trades-opened number, and `intrabar=` is gone because that entry path is gone.
- **`InpEnableOnnxAI` ships ON and has never been able to load a model.** No `#resource` writes `g_onnxModel`, so the adapter
  gets an empty buffer; the init check printed OK anyway and claimed the test would need file system access. It now reads the
  buffer, and `[ONNX]` distinguishes "no model bytes" (needs a `#resource`) from "bytes present, no session" (needs a
  re-export: `Resources/model.onnx` is `[0, 60, 57]` while `FEATURE_VECTOR_SIZE` is 70 - the shipped note said 65, which is
  wrong in both numbers).
- **The structured JSONL sink did work; its own log line pointed at the wrong folder.** `FileOpen` accepted the absolute path
  and wrote the basename into `MQL5\Files`, while `m_logPath` printed `MQL5\Logs`. 635 events were sitting in the real file.
  The path is now truthful, the session name uses `TimeLocal` (`TimeCurrent()` at `OnInit` is the last server tick), and 18
  uncalled methods are gone.

Operational effect: no lot, stop, take-profit, quorum or exit threshold moved. Two entry-path behaviours changed - a
single-dissent scan that the deadband arithmetic vetoed now proceeds, and `[HEARTBEAT]`/`[CONVERSION-RATES]` now report
stages that are actually measured. Expect the funnel numbers to be non-zero for the first time.

### Batch 252: the win-rate weight scaler sat behind a gate that was always open, on a mirror nobody read

`CConsensusWeightingConfig::UpdateStrategyWeights()` starts with `if(healthMonitor != NULL) { ...; return; }`, and
`CEnterpriseStrategyManager`'s constructor calls `m_infra.AllocateHealthMonitor()` unconditionally. The monitor therefore
exists for every manager before any strategy is registered, the branch is always taken, and the loop written underneath it
- "Performance-adaptive weight scaling using recent win rate", `scale = 0.75 + (winRate - 0.50)`, clamped to
[0.50, 1.50] - has never run for any strategy in any build.

It is deleted rather than wired, because as written it would have hurt: `recentWinRate` is registered as `0.0`
(`StrategyMgrRoster.mqh:239`) and only rewritten when a trade closes, so every registered row on every symbol would have
started life at the 0.50 floor - half voting weight, on a fresh install, for strategies that simply had not traded yet -
and the five AI rows would have been scaled by a number `UpdateAIPerformanceMetrics` puts in that field as model accuracy,
not a win rate. A safe version needs a `recentTradeCount` guard, AI rows kept out, and an input that defaults off. Say the
word and it is a small batch; inventing that arithmetic silently, with no journal newer than 2026-09-23 to check it
against, is not.

What went with the unreachable loop is the second weight mirror in the tree: `SStrategyHealthEntry::currentWeight` and
`::originalWeight`, `UpdateAllStrategyWeights()`, the monitor's `GetStrategyWeight` / `SetStrategyWeight` /
`GetStrategyOriginalWeight`, the `weight` parameter of its `RegisterStrategy()`, the roster's push into it, and
`StrategyEntry::originalWeight` with its getter and manager forwarder - the only reader of that last one was the dead
loop. Consensus reads one weight from one place: `StrategyEntry::weight`, written by `ApplyRawStrategyWeight` and
`UpdateStrategyWeightByName`. Those are untouched, as is `[AI-WEIGHT-ADJUST]`, which still prints with the same
arithmetic.

The honest sentence for what AI adaptation does now: it re-weights the five AI rows by their model profitability.
Indicator rows are parked and restored by the health monitor; they are never re-weighted. 19 added / 87 deleted across
five files.

### Batch 251: the AI engine's query island had no entry point, and the weight mirrors below it had no reader

`CAIEngine::OnAIQuery` is not called anywhere, and neither are the free `InitializeAIEngine`/`CleanupAIEngine` pair or
the `g_AIEngine` global that were the only other way in. Everything reachable only from there was a second copy of the
Batch 246/247 shape, and this time it was the AI domain: 26 methods, 10 members, 4 structs, and the whole
`SAIAdaptiveConfig` set of knobs the orchestrator was still assigning (`learningRate`, `minConfidenceThreshold`,
`useMarketRegimeAdaptation`, `useSentimentAdaptation`) into fields that only dead code read.

What the docs had been repeating as live behaviour, and what the code could not actually do:

- `AIEngine shutdown - Queries: %d, Accuracy: %.2f%%` could only ever print `Queries: 0, Accuracy: 50.00%`. Both numbers
  had writers only inside the island, so the shutdown summary was a constant dressed as telemetry. It is gone; the
  `[EXT-LLM] SHUTDOWN` line stays because its counters (`queries/ok/fail`) are real.
- `[AI-ENGINE] Clearing accumulated modifications` had a printer behind a counter (`m_pendingModCount`) whose only writer
  was `AI_ModifyWeights`, which had no caller. The tag no longer exists in the tree.
- `AdaptToPerformance` gated strategy parking and re-enabling on `m_predictionAccuracy < 0.4` / `> 0.6`. The only writer,
  `UpdatePredictionAccuracy`, sat behind `ProvideFeedback`. So the two branches were unreachable arithmetic on a 0.5
  constant, and what actually parks a strategy has always been the orchestrator's 60 s governance sweep
  (`EAOrchestrator.mqh:3122-3135`), which is untouched.
- `AdaptToRegime` multiplied a threshold by the regime factor (0.9 / 1.1 / 1.2), stored it in a local, walked the
  managers with an empty body, and returned. Batch 201's records - here and in `SYSTEM_STRUCTURE.md` /
  `RUNTIME_DECISION_GRAPH.md` / `SYSTEM_AUDIT_TRACE.md` - said AI entries became more permissive in a confirmed trend.
  They never could: nothing wrote the value. The regime publication itself and `[MARKET-REGIME]` are real; the claimed
  behavioural effect was not, and the method is now deleted.
- `GetEnsembleConfidence()` averaged `StrategyEntry::avgConfidence`, which no line in the tree wrote, and its only three
  readers were in the island. Field, roster getter, manager forwarder and reporter method are gone - Batch 250's
  "recorded, not fixed" note is closed by removal rather than by a writer.
- The health monitor's participation ladder (`UpdateParticipationScore`, seven `m_participation*` thresholds, seven
  `SetParticipation*` setters, `GetStrategyParticipationScore`) had no driver and no reader. The live
  `UpdateAllStrategyWeights` product became `originalWeight * healthScore`, which is the same number as before because
  the deleted term was registered at 1.0 and never moved. Batch 252 deleted that product too, with the weight mirror it wrote.

`CAIEngine` is 404 lines and does three things: it initializes against the symbol managers, it calls
`UpdateStrategyWeights()` on the adaptation interval, and - when `InpEnableExternalLLM` is on - it asks the configured
Ollama endpoint for weight commentary and applies the numbers that commentary names through
`CEnterpriseStrategyManager::UpdateStrategyWeight`. `GetStrategyWeightsJSON` stays for exactly that reason.

No entry, lot, quorum, veto, stop or exit moved. 9 added / 810 deleted across seven files.

### Batch 250: the manager stopped reporting to nobody

Batch 247 deleted the status chain that had no entry point. This deletes what fed it, and then keeps going down until
nothing is left that answers to nobody:

- nine read-only reporting chains (`GetStrategyReport`, `GetStrategyListJSON`, `GetConsensusContextJSON`,
  `GetActiveBrainStrategyCount`, `GetRegisteredStrategyWeight` / `Role` / `Cluster`,
  `IsRegisteredStrategyLiveVotingEnabled`, and the manager's `ConsensusDecisionClassToString` forwarder) - the reporter's
  own static stays, because `CPostConsensusValidator` calls it directly;
- five by-name governance setters (`SetStrategyRoleByName`, `...ClusterByName`, `...LiveVotingEligibilityByName`,
  `...GovernanceByName`, `...ConfidenceThresholdByName`) declared, forwarded and implemented with no caller;
- `EnableStrategy(name)` / `DisableStrategy(name)`, which carried the only printers of
  `[EnterpriseStrategyManager] Strategy ENABLED:` and `... DISABLED:` - no build could ever have written either line.
  The health monitor's automatic disable stays live: that path prints `[Enterprise-Adaptation]` and runs;
- four participation-formula setters, on both owners. The formula values are read live by consensus, and nothing has
  ever written them, so they are constructor constants (base 0.40, coeff 0.65, min 0.55, max 1.05) like the margin
  ladder's thresholds. A knob that exists only as a setter is not a knob; if you want to tune participation, ask and it
  becomes an input;
- the funnel counters the deleted report was the only reader of: total signals, successful signals (written on every
  profitable close), and an average-confidence field with no writer at all.

**One finding, recorded and not fixed:** `StrategyEntry::avgConfidence` has no writer either, so
`GetEnsembleConfidence()` averages zeros and has returned `0.0` for its whole life. It is not a money path today - its
readers live behind `CAIEngine::OnAIQuery`, which has no caller either, and that whole query island is the next batch.
Giving the field a real running mean is a behaviour change, so it gets its own batch and its own verification.
*Closed by Batch 251: the island went, and the ensemble-confidence chain went with it - the field's only readers were in
there, so removal, not a writer, was the answer.*

Nothing here moved a lot, a stop, a threshold or an exit. Every deleted method's only occurrences were its own
declaration, its definition, and a forwarder no caller could reach - which is the test this repository has now needed
often enough to write down: a reader is not a caller, and a caller is not an entry point.

**Verification:** eight programs, each with its own `Result:` line, 0 errors / 0 warnings, harness exit 0, all binaries
newer than the sources; the EA program went 143.0 s (Batch 249) -> 90.0 s. Not runtime-observed: newest journal 2026-09-23.

### Batch 249: your two timeframe inputs now choose the timeframe a strategy reads

Batch 234 recorded that `InpMomentumScalpTimeframe` and `InpCandlestickIntrabarTimeframe` land in a table nothing reads.
That is ended: the table is one `ENUM_TIMEFRAMES` per strategy slot, pushed into the symbol's manager at init and read
during registration, so Momentum and Candlestick `Init` — indicator handles, bar-time guards and all — on the timeframe you
named, whatever chart the EA sits on. Everything else in the table still says `PERIOD_CURRENT` and keeps the chart
timeframe, so the change is exactly those two strategies.

The one consequence worth reading before you change the inputs: Momentum declares M1-M15 as its scalp band and switches
itself off outside it. With the chart on H1 the shipped `InpEnableMomentumScalping = true` was therefore never honoured,
and the strategy ran trend-following on every symbol. Registering it on `PERIOD_M5` keeps scalping live, which means
Momentum may re-signal every `InpMomentumScalpCooldownSeconds` (20 s) instead of once per chart bar. That is signal
cadence, not exposure: consensus still needs two voters, the quality and support floors still apply, every entry still
passes `CUnifiedRiskManager`, the per-cycle send cap and the position ceiling still bind, and each position is still sized
against `InpMaxRiskPerTrade`. The signal-reversal exit reads the same manager, so exits get the faster view too.

If you want the old behaviour back, set `InpMomentumScalpTimeframe` to your chart timeframe — the row then matches what
`baseTF=` prints and nothing moves.

Three fields that no code read went with it: `name`, `intrabarTF` and `forceHigherOnM1Synthetic` (21 writes each). The
last one restated the band rule Momentum already enforces, and a second holder of one rule is how Batch 38 started. The
init line now tells the truth instead of annotating its own uselessness:

```
[ENTERPRISE] Manager initialized for EURUSD | registered=16 | profile=STANDARD |
  baseTF=chart(PERIOD_H1) | tfOverride Momentum=PERIOD_M5 Candlestick=PERIOD_M5
```

Per-strategy confirmation is already in the journal: `Registered strategy: Momentum | ... | TF: PERIOD_M5` and
`[MOMENTUM] Effective mode=scalping | TF=PERIOD_M5 | sameBarGuard=bypassed`.

### Batch 247: the rest of the status-report chain is gone, and the EA now compiles five times faster

Batch 246 proved the entry point was unreachable (`CEAOrchestrator::GetStatusReport()` had no caller). This batch deletes
the whole chain rather than leaving eight more methods that answer to nobody:

- `Core/Orchestration/OrchestratorStatusReporter.mqh` (114 lines), its member in the orchestrator, the `SetManagers` call,
  and the `ClearEnterpriseManager()` call whose only purpose was keeping the reporter's borrowed pointer from outliving a
  deleted manager.
- `CLiveAuthorityResolver::GetStatusReport()` - the per-strategy `pf=` / `eligible=` block three documents described as
  observability. It has never printed, in any build. `README.md` and `SYSTEM_STRUCTURE.md` now point at what does print:
  `[AUTHORITY-CONFIG]` at init and `[AUTHORITY-REJECT]` / `[AUTHORITY-REDUCED]` per decision.
- `CTradeExecutor::GetStatusReport()` and the four counters it alone read (`m_totalSubmitted` / `Confirmed` / `Rejected` /
  `Timeout`), with their `++` sites. The events themselves still print - `[EXECUTION-TIMEOUT]`,
  `[EXECUTION-CONFIRMED-BY-POSITION]` - so nothing about execution became less visible, only the aggregate that no path
  could reach.
- `CCandidateBuilder::GetStatusReport()` and `GetAuthorityBlockedTotal()`. The authority lot-refusal ledger stays, because
  the refusal line at `CandidateBuilder.mqh:255-276` reads it on a live path; the report's copy of the same numbers went.
- `CPostConsensusValidator::GetValidationStatusReport()` and the manager forwarder that only delegated to it.
- The five engine-registry reports (`Mathematical` / `Institutional` / `NeuralNet` / `DrawingManager` / `ScanScheduler`)
  plus the two helpers only they read (`GetActiveCount`, `GetTotalObjectCount`). Engine presence per symbol is already
  printed by `[WIRE-STATUS]`, which is on a live init path.
- `CHeartbeatTelemetry`'s eighteen getters. All eighteen had zero callers - `Emit()` passes the counters to
  `CDiagnosticsManager::UpdateCounters` directly, and that is what builds `[HEARTBEAT]`. The three the reporter used were
  dead too, because the reporter was dead.
- `CPostConsensusValidator::m_lastVPINMultiplier`, a field whose own comment called it "diagnostic mirror", written in
  three branches and read only by the deleted validator report.

What you get back: 6 added / 378 deleted across fifteen files, and a build that stops recompiling eight heavy headers
through a translation unit that never needed them. `MultiStrategyAutonomousEA.mq5` measured **48.0 s** against 129.3 s in
Batch 246 and 247.7 s in Batch 245; `MultiStrategyTestingEA.mq5` 60.3 s. Fewer headers also means `PositionManager.mqh`
no longer drags `RegimeEngine` / `RiskTierManager` / `SafeModeConfig` into five files that never asked for them.

If you want a status line, say which numbers and where - init or deinit, journal or chart comment - and one small printer
goes in. What was removed could not be asked for, because there was no way to call it.

### Batch 246: the position registry dropped three dead satellites - and a status report no build ever printed

Batch 245 left four small classes alive for one reason: `CPositionManager::GetStatusReport()` read them. That report is
gone now, and with it the fields that were constants (`Enabled=Y`, `Pyramid=N`, `DynamicSL=N`, `SRE=N`, `PyramidStates=0`,
`VolRegimes=0`), the `LossMin=N` flag whose setter lost its caller in 245, and the consecutive-loss / daily-loss tally
next to them.

The finding worth knowing is bigger than the position class: **no build of this EA has ever printed that status text.**
The chain is `CPositionManager::GetStatusReport()` <- `COrchestratorStatusReporter::GetStatusReport()` <-
`CEAOrchestrator::GetStatusReport()` , and that last method has no call anywhere in the
`.mq5` or `.mqh` tree. The seven other sections the reporter assembles - live authority, the enterprise manager's
validator block, the five engine registries - are in the same position: a parallel diagnostics API with no entry point.
That is AGENTS.md §8's "a reader is not a caller" one level up, and the rest of that chain is the next batch.

What else went:
- `PositionMgrSRE.mqh`, `PositionMgrPyramid.mqh`, `PositionMgrDynamicSL.mqh` (488 lines). Their behaviour was the exit
  surface Batch 245 deleted; after that batch they existed only to answer `IsEnabled()` / `GetStateCount()` /
  `GetRegimeCount()` for a string nobody printed.
- `PositionMgrLossGuard.mqh` (170 lines). Batch 245 orphaned its `ManageLossMinimization()`, which contained a second
  `ClosePosition(ticket, "Position Loss Limit")` beside the lifecycle guard's live one - a latent third exit authority,
  unreachable rather than harmless. Its surviving counters fed only the dead report, so the duplicate consecutive-loss
  tally goes too. `CPerformanceAnalytics::RecordClosedTrade` stays as the one closed-trade
  feed with real consumers: momentum lot scaling, win rate and profit factor, the `[AUTHORITY-LEARN]` outcome path.
- `CPositionManager::RecordClosedTrade`, its call site next to the analytics feed, the class's `m_enabled`, the three
  includes its deleted collaborators needed, and the reporter's never-called `Init`/`IsWired` pair.
- The refactor this area asked for: `PositionMgrStateStore.mqh` had three copies of "evict the oldest slot when full,
  then append" and two copies of "shift down and shrink". Those are now `AcquireSlot()` and `EraseAt()` - same
  arithmetic, one place to change.

Kept on purpose: `PositionMgrMagicFilter.mqh` (28 lines), because `BasketEquityStop.mqh:103` calls
`CPositionMgrMagicFilter::IsEAOwnedMagic` on a live path. It is that file's only caller now.

No entry, exit, stop, lot or risk number moved: 54 added / 870 deleted across eight files, and the position registry is
119 lines that do one job.

### Batch 245: `CPositionManager` is a registry now, not a second exit authority

This class had a full set of exit methods - `ManagePositions`, five `Manage*`, six `Configure*`,
`CheckSignalReversalExit`, `SetDailyRiskBudget` - and no caller could reach any of them. The only calls on this owner are
`RegisterPositionState`, `RecordClosedTrade`, `GetStatusReport`, `GetPositionStateCount` and the nine prediction-map
accessors, so 229 lines of exit surface and its now-unreadable collaborators went, and the file says what it is:
the position-state and prediction-map registry. `Initialize` went with them rather than becoming a stub that stores pointers
nobody reads; its four parameters and fourteen config fields had no reader left after the exit methods did.

Two things this means for you, and one it does not:
- The init line changed: `[INIT] PositionManager initialized` is now `[INIT] PositionManager registry ready | position-state +
  prediction maps, no exit authority`. `[CRITICAL] PositionManager initialization FAILED` no longer exists - nothing cited it,
  and it could not have fired, because the call passed two addresses that are never `NULL`.
- The status report kept printing the same nine fields, five of them constants (`Enabled=Y | Pyramid=N | DynamicSL=N |
  LossMin=N | SRE=N | ... | PyramidStates=0 | VolRegimes=0`), and Batch 246 deleted the report and the satellites together - see the section above.
- No exit, stop, lot or entry moved. The live exit path remains `CPositionLifecycleManager::ManagePositions()`, which is what
  has always run.

Kept on purpose: `PositionMgrMagicFilter.mqh`. It looked like residue of the deleted magic-number forwarder, but
`BasketEquityStop.mqh:103` calls `CPositionMgrMagicFilter::IsEAOwnedMagic` on a live path. That is the difference between a
name having readers and an owner having callers.

### Batch 244: the loss-guard exit that had no settings now has six - and its numbers did not move

A live exit path in this EA has been running on a class constructor since the first build. `ManageLossMinimization()` closes
any position this EA owns once price has moved **75% of that position's own stop distance** against it and it is in loss, and
three such closes pause the whole guard for 1800 seconds. You could not set either number, because the setter
(`ConfigureLossMinimization`) had no caller and no input existed - the gate that decides whether the path runs is an OR, and
its right-hand term, `GetConsecutiveLossLimit() > 0`, has been true from startup the whole time.

What changed: six inputs in both EAs, and one line at init.

```
Loss Guard (exit path that ran unconfigurable until Batch 244)
  InpLossGuardAdverseMomentumExit          = false   // off is what every build has done
  InpLossGuardAdverseMomentumATR           = 0.5     // close after this x ATR(14) adverse move
  InpLossGuardConsecutiveLossLimit         = 3       // >0 also ARMS the whole guard
  InpLossGuardConsecutiveLossCooldownSec   = 1800
  InpLossGuardDailyLossCircuitBreakerPct   = 50.0    // of InpMaxDailyRisk, guard closes only
  InpLossGuardPositionLossLimitPct         = 75.0    // fraction of the position's own SL distance
```

`[LOSS-GUARD] adverseMomentum=off atrMult=0.50 | consecutiveLossLimit=3 cooldown=1800s | dailyBreaker=50% of the 4.00% budget
| positionLossLimit=75% of own SL | armed=yes` prints once at start, so the journal now states what this path is doing instead
of leaving it in a constructor. **A normal start behaves exactly as before** - the defaults are the values that were already
running, and nothing was retuned. What you gain is the ability to set them, and to switch the path off deliberately
(`InpLossGuardConsecutiveLossLimit = 0` with the adverse-momentum flag off prints `armed=no`).

Two log lines were also corrected because they promised more than the code does: `[LOSS-MIN] Daily loss circuit breaker
triggered` no longer ends in `| stopping trading` - it returns from this path only, and entries are gated by
`CRiskCircuitBreaker` and the risk pipeline - and its `loss=` field became `guardLoss=`, which is what it actually measures,
since that counter only grows from these two exit branches.

Not switched on, on purpose: pyramiding, volatility-scaled SL/TP and partial profit taking are still off, their setters still
uncalled, because wiring them would add position layers, moved stops and partial closes nobody asked for. That is a feature
decision for you, not a cleanup I should make while you are asleep.

### Batch 243: two collaborators the position manager was handed and never used - and an exit that runs on numbers nobody set

No trading decision moved in this batch. `CPositionManager` kept a `CFullMarginMode*` and a `CIntelligentSLGuard*`, was passed
`&m_fullMarginMode` and a literal `NULL` for them at init, and asked neither anything, ever; the margin object actually
consulted is the orchestrator's own (`EAOrchestrator.mqh:966`, read by `CDiagnosticsManager`). Gone: the two members, the two
`Initialize` parameters, the include that only they needed, and three circuit-breaker getters (`GetTriggeredAt`,
`GetRecoveryAttempts`, `GetRecoveryLevel`) with no caller anywhere. The recovery ladder still reads that state internally and
prints it, so the journal is unchanged.

**What the same sweep found, stated plainly because it touches money.** One of the four exit arms this repository's own doc
row described as "unsettable" is not off - it is running, on constructor defaults:

- `ManageLossMinimization()` executes on every lifecycle pass. Its gate is `IsAdverseMomentumExitEnabled() ||
  GetConsecutiveLossLimit() > 0`, and `CPosLifecycleLossGuard()` initializes `m_consecutiveLossLimit(3)`, so the second term
  has been true since the first build.
- The live effect: any EA-managed position whose price has moved **75% of its own stop distance** against it, while in loss,
  is closed early and prints `[LOSS-MIN] Position loss limit exit | ticket= | lossRatio= | limit=`. Three such closes arm a
  1800-second cooldown that pauses the whole guard.
- You cannot set any of it. `ConfigureLossMinimization` has no caller and no input exists for it, so 75%, 3 and 1800 are the
  class's constructor, not your choices. Pyramiding, dynamic SL/TP and partial profit taking *are* genuinely off - their
  flags are `false` and nothing writes them - so `[LOSS-MIN] Adverse momentum exit` cannot print.
- One message overstates itself: `[LOSS-MIN] Daily loss circuit breaker triggered ... | stopping trading` follows a plain
  `return` from this path. Entries are stopped by `CRiskCircuitBreaker` and the risk pipeline, not here.

Left in place deliberately, with the reason: changing that threshold or switching the early close off moves realised exits on
live positions, which is a trading decision rather than a cleanup, and this batch is the one that deletes pointers. The next
batch owns the decision, and `AGENTS.md` §6 now lists the five `[LOSS-MIN]` lines with which ones can actually fire, so
absence of a line is evidence again.

### Batch 242: `Config/live_overrides.json` now actually changes the running EA

**What you thought you had.** `MQL5\Files\Config\live_overrides.json` is described in this repository as the runtime risk
source - the file you edit when you want to cut risk during a drawdown without touching the chart. Editing it changed
nothing. Three separate defects made the channel dead: the reader asked MetaEditor for a file by absolute path, which the
file sandbox does not allow; the change test compared two file timestamps that were both zero, so it concluded "not
modified" forever and never even printed an error; and the four reload callbacks it did register printed
"`<section>` section reloaded" and threw the parsed values away.

**What you have now.** The file is opened by its sandbox-relative path, the poll runs on wall-clock time (a quiet market
no longer suspends the check), and a missing or unreadable file says so once:
`[LIVE-CONFIG] file not readable | path=... | live overrides inactive`. When you save a change you get
`[LIVE-CONFIG-RISK] perTrade=1.00->0.50 | daily=4.0->2.0 | portfolio=12.0->12.0 | maxDD=... | dailyLoss=... |
roundUp=yes->yes | cap=3.0->3.0 | compounding=yes->yes | tier=1->1` followed by the ordinary
`[RISK-TIER]`/`[RISK-INPUT-UPDATE]` receipts, because the values go through the same path the dialog inputs use.

Two rules worth knowing:
- **A key you leave out keeps the running value.** The file does not have to be complete; deleting a line is not the same
  as setting it to zero.
- **Only the `risk` section is applied.** `weights`, `thresholds`, `symbols`, `ai` and `engines` are read and announced as
  `applied=no(report-only sections, no consumer reads them)`. They are per-strategy or per-symbol configuration whose
  owners are built once at initialization, so making them live means rebuilding rosters mid-session - a real design
  decision, not a line to delete.

**The circuit-breaker reset you can now reach.** After three automatic re-arms the EA prints
`[RISK-CIRCUIT-BREAKER] Max recovery attempts reached (3/3) | Manual reset required` and waits for a manual reset that
did not exist anywhere in the program. Put `"resetCircuitBreaker": true` in the `risk` block and save: trading re-arms,
the peak equity re-baselines to the current equity, and the journal prints
`[RISK-CIRCUIT-BREAKER] manual reset via live config | ... | set risk.resetCircuitBreaker false before the next edit`.
It fires on the transition from false to true, so leaving it `true` will not silently re-arm on your next unrelated edit
- and it should stay a deliberate act, because the same reset clears the conservative-mode sizing step.

### Batch 241: rounding a lot up to the broker minimum could cost fifteen times the risk you configured

**The problem.** When the sized lot falls under `SYMBOL_VOLUME_MIN`, the EA can round it up - and that round-up
multiplies the risk the gate just approved, because sizing happens after the gate. To keep that bounded there is a hard
ceiling, `MAX_MIN_LOT_RISK_MULTIPLIER = 3.0`: a lot that needs more than a 3x uplift is refused instead of traded. The
clamp only ever guarded one of the three places that touch a lot - the position sizer. The **risk gate** and the
**candidate builder** each read the operator's own number, and the shipped default of `InpMinLotRiskMultiplier` was
**15.0**. So on the path that decides the money, one position could be widened to fifteen times its approved risk: at
`InpMaxRiskPerTrade = 1.0`, a single trade could risk 15% of the account. The sizer refused the same lot at 5x.

**What changed.** One ceiling, read by all three consumers, defined next to the other hard risk limits in
`Core/Utils/Enums.mqh`. The effective value is clamped to `[1.0, 3.0]` before it reaches the risk gate, the sizer or the
builder, and if your input asks for more, startup says so:
`[RISK-ROUNDUP-CEILING] asked=15.0x | enforced=3.0x | ceiling=MAX_MIN_LOT_RISK_MULTIPLIER`. `InpMinLotRiskMultiplier`
now defaults to `3.0` (a larger ask can no longer be honoured, so the dialog should not suggest one), and
`Config/live_overrides.json` is corrected to match.

**Two more controls that did not do what they said.**
- `InpAllowMinLotRoundUp = false` was obeyed by the sizer and ignored by the gate, which widened the lot anyway. The gate
  now refuses with `[RISK-GATE-REJECT] <symbol> | reason=lot_below_min_roundup_disabled`.
- `UpdateRiskParametersFromInputs` took nine risk parameters and applied eight. Your per-trade risk appeared only in its
  `[RISK-INPUT-UPDATE]` line: neither the gate's base risk nor the sizer's risk percent was updated. It now re-runs the
  same sequence initialization uses (operator base risk, then the tier, then the sizer), and the line reports
  `roundupCap=X enforced`.
- `CCandidateBuilder` was configured with a literal `5.0` for max risk per trade while the dialog shipped `1.0`, and that
  field is the fallback whenever a signal asks for no risk - so a quiet request was sized at five times your ceiling.

If you run a small account where the broker minimum binds, expect a new refusal where the EA used to trade an oversized
position: `[RISK-LOT-FLOOR] ... REJECTED: ... risk 8.0x > 3.0x cap`. Widen the stop so the sized lot needs less uplift.
Raising the ceiling is a deliberate source edit, not a forgotten one - `MAX_MIN_LOT_RISK_MULTIPLIER` in
`Core/Utils/Enums.mqh` is the one number all three consumers now read, and `[RISK-ROUNDUP-CEILING]` says what is in force.
Note that this reverses a 2026-08-06 decision ("keep risk up to 15x, not 1x", Batch 142), which a later audit batch
overturned for the sizer and never reconciled with the gate: fifteen times the approved risk on one position is the
exposure this repository was audited to remove.

### Batch 240: margin was checked on a lot the trade never shipped, and the margin ladder had no driver at all

Two findings on the same subject - whether the account can actually afford what it sends.

**The margin gate priced a lot that was not the lot it approved.** `ValidateTradeRequest` runs its free-margin and
margin-level checks on `request.lotSize`, and *after* that the lot floor can raise the size to the broker minimum
(`[RISK-LOT-FLOOR] ... Adjusted 0.004 -> 0.010`). The trade then ships the raised lot, which had never been priced for
margin. The gate now re-checks on the lot the candidate actually ships and refuses with
`[RISK-GATE-REJECT] <symbol> | reason=lot_floor_margin | lot=A -> B`, so a round-up cannot pass on margin it never used.
This matters most on a small account, where the broker minimum is the lot most often raised.

**The margin-level ladder had no driver.** `CRiskMarginHealth` measures account margin level and is written to react:
under 150% flatten everything, under 200% cut the worst position and hold entries, under 300% de-risk. Its only entry
point, `CUnifiedRiskManager::MonitorMarginHealth()`, had no caller anywhere - so no `[RISK-MARGIN]` line has ever been
in a journal, and none of that protection has ever run while the EA held positions. It is now polled every 30 seconds
from the runtime-state refresh the timer already drives, and it says so at startup:
`[RISK-MARGIN] monitor armed | poll_ms=30000 | hold_entries_below=200% | request_flatten_below=150% | free_margin_use_limit=80% | min_post_trade_level=200%`.

Wiring it meant fixing what it does, not just calling it. The old code closed positions itself, from inside a risk
class - a second flatten authority beside `CRiskCircuitBreaker`, which is exactly the shape Batch 237 removed from the
spike monitor. It now *requests*: below 150% it raises the breaker's emergency-close flag and the existing
orchestrator path does the closing, which keeps the single owner of execution. It also used to set the shared
conservative-mode flag, and that one is a trap: `CRiskAdaptiveTuner` only clears the flag when it was not already set,
so a margin write would have latched the account into conservative sizing permanently - one temporary 250% reading and
every trade is half size until a drawdown recovery happens to clear it. The margin ladder no longer touches sizing;
below 200% it holds new entries through a flag the same poll releases.

What you will see if the account gets leveraged: `[RISK-MARGIN] CRITICAL | Margin Level=178.4% < 200% | entries held(open positions untouched)`,
then `[RISK-MARGIN] entries released | ...`, and if it goes under 150%, `[RISK-MARGIN] EMERGENCY | ... flatten requested(circuit breaker owns closing)`
followed by the ordinary close-out receipts. Entries refused by the hold print `[RISK-MARGIN] <symbol> | entry refused | marginLevel=...`.

Also removed by the sweep in the same files: seven `Validate...` forwarders on `CUnifiedRiskManager`
(`ValidateBasicParameters`, `ValidateRiskLimits`, `ValidatePortfolioRisk`, `ValidateCorrelationLimits`,
`ValidateMarginRequirements`, `ValidateAccountHealth`, `ValidateClusterGovernance`) that the pipeline never used -
every pre-trade gate calls its own method inside `CRiskValidationPipeline`, so those entry points had no caller - and the
four accessors around `CRiskMarginHealth`'s two pinned thresholds went with them. Recorded, not wired: `CFullMarginMode` is
initialized at `EAOrchestrator.mqh:966`, keeps its own config and de-risks nothing, because none of its methods is
called from anywhere - full-margin stacking and its stricter gates are a trading mode choice, not a cleanup.

### Batch 239: an open trade was counted twice against your risk caps for a minute after every fill

When a candidate passes the risk gate it books its risk as a *pending* reservation, so the next candidate in the same
scan cannot spend budget the first one already took. On rejection the reservation is released. On approval it is kept -
correctly, because there is a gap between "approved" and "the terminal shows me a position" - and then nothing ever
ended it except its 60-second timeout. Meanwhile your open exposure had started counting that same trade the moment it
filled. So for up to a minute after every fill, that trade's risk appeared twice in the number the caps are compared
against: `InpMaxDailyRisk = 4.0` and `InpMaxPortfolioRisk = 12.0`, plus the remaining-budget figures in the risk
snapshot. At your default sizing of roughly 1% per trade, four fills inside a minute read as 8% of a 4% daily budget,
and the EA refused live entries on money it was already carrying. The Batch 237 send cap of three per cycle makes that
minute easy to reach.

What changed: a reservation now also ends when the position it stands for appears. The matcher is conservative - one
open position discharges one reservation, matched on symbol, direction, a lot at least as large, an open time at or
after the reservation, and a non-zero magic so a manual trade cannot clear pending EA risk. The gate's final lot is now
written back into the reservation too, because a correlation shrink or a broker-minimum floor changes the size *after*
the reservation was taken, and a reservation still carrying the old lot could never be recognised by the fill that
replaced it.

You will see `[RISK-VIRTUAL] pruned | expired=0 | covered_by_position=3 | remaining=1` where the journal used to show
only `expired=`. Expect more entries inside the minute after a burst of fills - that is the point: the caps are now
measuring the risk you actually have on. The two-line cleanup in the same file (`GetReservation`, `ClearVirtualPositions`)
had no callers, and the `[RISK-VIRTUAL] clear` line they would have printed has never appeared in a journal.

Not fixed, on purpose: a trade the gate approves and the EA then never sends still holds its reservation for the full
60 seconds, because no position exists to discharge it. That direction over-counts risk rather than under-counting it,
and closing it properly means the send path reporting its outcome back into the risk layer.

### Batch 238: twelve inputs removed from your dialog because they changed nothing

The audit that found the dead spike monitor also checked every field the two EAs write into the orchestrator config.
Fourteen had a writer and no reader. Twelve are deleted; two are wired. What this means for you is that the inputs
gone from the dialog are inputs that never did anything, and the two that remain now do.

Deleted, with the reason each one could not be wired honestly:

| Input | Why it is gone |
|---|---|
| `InpAllowAIWarmStartLive` | the live-authority resolver has no warm-start concept to receive it |
| `InpAuthorityTrialHorizonSeconds`, `InpAuthorityMaxTrackedTrials` | there is no trial store: the resolver's config takes eleven values and none is a window or a cap |
| `InpNonAIPromotedRiskMultiplier` | one promotion branch exists and it is AI-only; a second promoted multiplier would be a second authority over one lot |
| `InpEnableHybridCadence`, `InpIntrabarChartSymbolOnly` | scan cadence is the bar gate plus `evalBudget`, which `[SCAN-POLICY]` prints |
| `InpCloseUnprotectedOnRemediationFailure` | escalation 3 closes because "no position should exist without a stop" is an invariant, not a setting; the off direction had no code |
| `InpEnableAutoModeSwitch`, `InpConservativeBaseRiskPct`, `InpAggressiveBaseRiskPct`, `InpModeSwitchDrawdownPct`, `InpModeSwitchWinStreak` | the whole auto-mode-switch feature is a stub whose body said "not implemented", and its `[VALIDATION]` block was failing OnInit over relationships between four values that reached nothing |

The risk-mode story the deleted inputs implied is not how this EA behaves, and the real authorities are worth knowing:
your per-trade risk base is `InpMaxRiskPerTrade`, and `CRiskAdaptiveTuner` only ever scales it *down*; the conservative
flag comes from a two-of-five trigger vote (rolling win rate under 40, Sharpe under 0.5, drawdown past warning, three
consecutive losses, profit factor under 1.2). Replacing that with a single drawdown threshold and a bigger "aggressive"
base would have loosened a risk gate on settings nobody had ever applied - your decision to make deliberately, not a
cleanup to slip in.

Wired instead of deleted: `InpEnableNNAttributionDiagnostics` and `InpRunNNAttributionSelfTest`. Their setters had no
caller, so the code's own defaults ran - diagnostics on, self-test never executed. Both are now fed at startup, and the
self-test (which round-trips the prediction id through the trade comment and the position map the neural net learns
from) is callable. The diagnostics input's default moves `false -> true` because that is what every build has printed;
wiring it at `false` would have quietly deleted the `[NN-DIAG]` shutdown summary, and losing evidence to a "cleanup" is
the mistake this repo has now made and corrected three times.

One dead class went with them: `Core/Processing/TickSafetyMonitor.mqh` (164 lines). After Batch 237 nothing called any
of its checks - it was a member that got three configuration calls at startup and was never consulted again. Margin and
drawdown protection is `CRiskMarginHealth`, `CRiskCircuitBreaker` and `CUnifiedRiskManager`, and those are called.

### Batch 237: one cycle could order every symbol, and the spike monitor could not see a spike

Two controls in the path that spends money were declared and did nothing. Both are now real, and both announce
themselves.

**The per-cycle burst.** `InpMaxPositionsTotal = 15` and `InpMaxTradeSendsPerCycle = 3` are both in your inputs dialog.
The EA read the position count once, at the top of the scan cycle, and every symbol slot in that cycle sent against
that one measurement - so a book at 14 open positions could take thirteen more in a single pass, and the send cap had
no code anywhere. Now each slot is tested against the count plus the sends this cycle already made, before the
candidate is validated (a validated candidate holds a 60-second virtual reservation of the portfolio budget, and the
orchestrator cannot release it, so testing after validation would spend next minute's risk headroom on trades that
were never going out). Only a fill consumes budget; a refused or deduped send does not. You will see
`[ENTRY-GATE] entry held mid-cycle | reason=cycle_send_cap | eaPositions=2 +1/15 | sends=3/3` when it binds, and
`[ENTRY-BOUNDS]` at startup prints the three numbers the loop actually enforces, including that
`InpMinSecondsBetweenTrades` is still measured once per cycle, not per send.

**The spike monitor.** `CSyntheticSpikeMonitor` is the protective half of the Deriv-synthetic story: a tick flood on a
volatility index should stop new entries, because that is when a fill lands at a price that does not exist. Its
entry point had no caller, so nothing could ever be detected - `[SPIKE-PAUSE]`, `[SYNTHETIC-SPIKE]` and
`[SPIKE-ALARM]` had printers on unreachable paths, `pause_active=` in `[HEARTBEAT]` and the `spike_pause` term in
`[ENTRY-GATE]` were constant false, `spike_events=` constant zero, and three of your inputs bound nothing. Two more
things were wrong with the code that could not run: it counted *its own calls*, which measures how often the chart
symbol ticks rather than what the market does, and both of its trigger paths closed positions, which would have made
it a second flatten authority next to `CRiskCircuitBreaker`. It now watches every synthetic on your roster from the
M1 tick-volume series (a real per-symbol tick count, sampled once a second), keeps the same confirmation arithmetic
and pause length, and raises the entry pause only. The flatten loops are deleted. `[SPIKE-MONITOR] 7 synthetic
symbol(s) watched | velMult=3.0 | confirmWindows=2 | pauseSeconds=30 | action=pause_entries(open positions untouched)`
at startup is the evidence that it is armed; FX and crypto slots are not watched, because their tick volume tracks
the session and would alarm on any busy hour.

This is not runtime-observed. The newest journal in the terminal is still 2026-09-23, so no `[SPIKE-PAUSE]` or
held-mid-cycle line has ever been seen firing - the first live session will be the test.

### Batch 236: thirty doc pointers that could not point anywhere, and one more field written into nothing

This documentation is the instrument you read decisions from, and it is full of `file.mqh:NNNN` pointers. Batches
215-231 deleted thousands of lines and re-pointed only what their own edits broke, so the rest drifted: a mechanical
pass over the five current-state docs found 20 citations landing on a blank line, a lone brace, past the end of the
file, or on a filename that has never existed (`EAOrchestrator.mq5`). Resolving each claim against the tree turned up
ten more that sat on a plausible neighbouring line. All thirty are re-anchored now, 26 lines in total.

Two of them were not stale pointers but stale *claims*, which is the part worth your attention. Two sentences said the
live-authority multiplier "reaches nothing" and that only the mode vetoes and `LOW_CONFIDENCE` have any effect. That
was true when written; Batch 205 ended it, and `ScaleLotByLiveAuthority` (`EAOrchestrator.mqh:3608`) is what applies it
to the lot today. And the README's own correlation row told you the position sizer had a path "explicitly disabled at
`:886`" — Batch 226 deleted that path, so the row now points at the pipeline's REDUCE shrink and at the comment that
records the deletion.

Reading those sentences to find what actually applies the multiplier surfaced one last dead copy:
`STradeCandidate::liveAuthorityRiskMult` had two writers and no reader — the lot uses the value passed as a parameter,
and the log line uses `liveAuthorityReason`, which is read in three places. The field, its initialiser and both writes
are gone, the same way `liveAuthorityAllowed` went in Batch 225. No lot, gate or threshold moved.

What this sweep does *not* claim: a pointer landing on the wrong-but-plausible line is invisible to it. The guarantee
you get is narrower and real — no citation in the current-state docs now points at something that cannot be there.

### Batch 235: the trainer measured the model it never trained, and reported that as your validation score



`CTrainingSession` had two neural networks inside it. One was a pointer to the model your script passes in — the one
that actually trains. The other was a member network, created when the session was constructed, that no code ever
trained. That second network is not a curiosity: `Finalize()` runs at the end of every training session, and it
finished by evaluating the validation set **through the untrained network**, writing the result into the same metrics
object your summary reads.

What that did to the evidence you act on:

- `--- Validation Metrics ---` in `MQHModelTrainer` and the visualizer's metrics table were the accuracy, F1 and
  confusion counts of a randomly initialised network.
- `GetTrainMetrics()` and `GetValMetrics()` returned the *same object*, so `--- Training Metrics ---` printed the same
  untrained numbers again. The train-vs-validation gap you use to spot overfitting could not have appeared.
- The hyperparameter tuner ranks candidates by `f1Score`, taken from that same object. Because the untrained network
  is the same for every candidate, `[MQH-TUNER]` scored every architecture identically and the `rank` column described
  one untrained network, not your candidates.
- The training log file the code formats (`MQHTrainingLog_*.txt`) could never be created: its only open call sat inside
  `Initialize()`, which nothing calls, so the file branch of every `LogMessage` and the closing `FileClose` were
  unreachable.
- `GetModel()`, `SetLearningRate()`, `SetTemperature()` and `SetL2Regularization()` were the session's own wrappers
  around the untrained network. Nothing calls them — a lookalike API that would have silently configured the wrong
  model for whoever reached for it first.

The session now has one network: the one you gave it. `Finalize()` scores that model on validation into
`m_metrics` and does one real pass over the training set into a new `m_trainMetrics`, so the two blocks in your
summary are two measurements, and the tuner's F1 ranking is an F1 of the model that was trained. The log file is
opened by the live training call and named on the journal: `[MQH-TRAIN] Training log: <file>`. The closing line says
which condition ended the run — `stop=early-stopping` or `stop=epoch-budget` — which is the difference between "the
model stopped improving" and "you ran out of epochs".

Two dead config fields went with it. `earlyStoppingMinDelta` was set to `0.0001` by all three callers and read by
nothing, while the improvement test used a hard-coded `1e-6`; it is now a real field that the test uses, defaulted in
the struct to `1e-6`, so today's behaviour is unchanged and the knob is honest. `enableVisualization` — an input in
the dialog, a config field, and a `SetVisualizer()` whose body was a comment that threw its argument away — is
deleted; the visualizer program drives its charts itself and always did. `MQHModelTrainer/README.md` documented
`earlyStoppingMinDelta: 0.0001` as a working setting; it now says what actually binds and lists the training log as an
output, which is true only from this batch.

Fixing that surfaced a second leak in the same object: the tuner reuses one session for every architecture candidate,
and the early-stopping state was only initialised when the session was constructed. From the second candidate onward the
"improved enough?" test was measured against the *previous* candidate's best validation loss, the patience counter
carried over, and once any candidate stopped early the flag stayed set for the rest of the run. A training session now
resets that state at the start of each run, and the log file is named once per program run with each candidate
appending to it — a tuning session leaves one readable file instead of one per candidate.

No EA binary includes this code, so no live decision, lot or exit moved. What changed is the evidence behind the
decision of *which trained model to load into the EA*.

### Batch 234: two timeframe inputs the EA never consults, now stated at startup

`InpMomentumScalpTimeframe` and `InpCandlestickIntrabarTimeframe` both default to M5, and both land in a per-strategy
timeframe table that nothing reads — its only getter chain (`GetStrategyTimeframeConfig`) has no caller. So Momentum
and Candlestick run on the chart timeframe, which is exactly what their own startup lines print, and moving those
inputs moves nothing.

They were not quietly switched on, because that is strategy behaviour, not housekeeping: binding the table would move
Momentum's scalp reads and Candlestick's intrabar reads to M5 on every symbol at once. That belongs with the
per-symbol operating-timeframe decision, where you choose a timeframe per strategy on purpose.

What shipped is the truth on the line you already read at init:

```
[ENTERPRISE] Manager initialized for EURUSD | registered=16 | profile=... |
  strategyTF=chart(PERIOD_M1) | momentumScalpTF=PERIOD_M5(stored,unconsulted) candlestickTF=PERIOD_M5(stored,unconsulted)
```

Three pieces of residue went with it: `intrabarEnabled`, a boolean restating the intrabar-policy fact the policy enum
already carries (20 writes, no reader); `GetStrategyIntrabarPolicyConfig` on both owners, declared, defined,
forwarded, never called; and config slot 20, a row still named "Exit Optimizer" — a strategy whose catalog slot
Batch 207 deleted and which nothing indexes any more. Behaviour is unchanged by construction: every deleted line wrote
to storage no code read, or was a getter nothing called.

### Batch 233: your eleven intrabar eligibility inputs are a report field, and the journal now says so

If you set `InpIntrabarEligibilityMeanReversion = OFF` you would expect Mean Reversion to stop voting inside a bar.
It does not, and this batch proves why rather than guessing: after the unreachable evaluators were deleted in
Batch 231, the only code that ever *read* a strategy's stored intrabar policy is the line that prints it. The entry
path never asks for sub-bar evaluation at all (it passes `EVAL_MODE_NEW_BAR`, and the declined change is recorded in
Batch 212), so the only live intrabar evaluation is the signal-reversal exit check — and there the voter set is
"enabled and live-voting", whatever the policy field says.

**Why the control was not simply switched on.** Fourteen indicator rows are configured through
`StrategyConfigBuilder`, and eight of them have no input at all: Statistical Arbitrage, FVG Scalper, Turtle Soup,
Breaker Block, NY Open Gap, Asian Range Break, Liquidity Sweep and Range Compression carry
`defaultPolicy = INTRABAR_POLICY_OFF` in code. Making the stored policy binding would therefore remove those eight
from the reversal-exit vote — the EA would be slower to flip a position against a new signal — on a setting nobody
chose. Enforcement is your risk policy, so it needs your decision: say the word and the gate is one line, and the
eight rows would first need inputs so you can pick them individually.

**What you get now:** one line per symbol at startup,
`[INTRABAR-POLICY] <symbol> | stored LIVE=n other=m | applied=no(...) | rows_not_LIVE=<names>`, generated from the
roster rather than from the dialog, so it tells you what is stored *and* that nothing branches on it; and the
per-strategy registration line now reads `Intrabar(report-only): OFF`, because a journal field that says `OFF` where
no gate exists is the kind of evidence that sends you hunting the wrong thing.

### Batch 232: a second copy of the intrabar policy that nothing consulted

Removing the dead evaluators left `SStrategyEntry.intrabarEligible` in the shape this project keeps finding: two
places write it, nothing reads it. It is a boolean mirror of `intrabarPolicy == INTRABAR_POLICY_LIVE`, and the policy
integer is what every live path actually uses. Field, getter, manager forwarder, setter and both writes are gone —
one quantity, one authority.

The by-name policy API went with it: `SetStrategyIntrabarPolicyByName` and its `...EligibilityByName` shim exist on
both the manager and the policy class and no code calls them. Strategies are configured positionally, from the
catalog rows through `SetStrategyIntrabarPolicyConfig`. One consequence worth knowing as an operator: the
`[EnterpriseStrategyManager] Intrabar policy updated: <name> => <policy>` line those methods print has **never
appeared in any journal** and never could, because nothing could reach the code that prints it. If you want to flip
one strategy's intrabar policy at runtime, that is now a real feature request rather than a switch you expected to
work — and the eleven `InpIntrabarEligibility*` inputs that exist reach a stored field, not a decision (Batch 233).

52 lines deleted across five files; no policy value, threshold or eligibility decision moved, so what a symbol may do
inside a bar is unchanged. Verified by the eight-program compile at 0 errors / 0 warnings with each program's own
`Result:` line.

What this batch's sweep exposed is bigger than what it deleted, and is filed as Batch 233 rather than fixed here:
the eleven `InpIntrabarEligibility*` inputs reach a stored per-strategy policy that **no decision consults**. They
do bind to the value printed as `Intrabar:` in the strategy report, and they do select the policy recorded at
registration — but the only code that ever tested it (the probe and two-tier voters, and the policy-resolution
helpers) was unreachable and is now gone. So every enabled live-voting strategy votes intrabar today, including the
eight rows whose policy is `OFF` by hardcoded default (Statistical Arbitrage, FVG Scalper, Turtle Soup, Breaker
Block, NY Open Gap, Asian Range Break, Liquidity Sweep, Range Compression). Turning the control on is a *restriction*
of eight strategies' sub-bar participation, which is your risk policy, not a cleanup — so it gets visibility first and
your decision second.

### Batch 231: two more consensus evaluators nothing could call, and the seven inputs that configured them

Batch 230 said the intrabar *probe* path was live and that seven-ish quorum inputs were a decision waiting for you.
It was wrong, and the check that would have caught it was *who can reach this function*, not *who reads its
values*. `EvaluateConsensusProbeOnlyInternal` has no caller in the repository, and its own first line of comment
already said so.

The dead set is gone — 706 lines across thirteen files:

- **Two unreachable evaluators.** The two-tier consensus path (a quick probe counting Tier 1, then the normal
  evaluation as Tier 2) and the probe-only path. Neither had an entry point: the manager's forwarder for the
  first is called by nothing, and the second is not even exposed.
- **Four sibling entry points.** `GetConsensusSignal`, `GetConsensusSignalWithConfluence`,
  `GetConsensusSignalForSymbol` and `GetConsensusSignalForSymbolWithConfluence` each forward to the next, and the
  last forwards to the one method the signal generator, the position lifecycle manager and the training exporter
  actually call. Your consensus decisions come from that one entry point and always did.
- **Ten uncalled helpers** across the consensus engine and the intrabar-policy class — a direction-diversity
  score, an average-metric helper, a role-vote multiplier, a join-contributors string, a diagnostics printer
  (`[CONSENSUS-DIAG]` prints from the strategy classes; the diagnostics-manager counters under the same tag had no writer and no caller and are gone (Batch 256), so nothing you read in a
  journal is lost), and an ADX "is it trending" test.
- **Seven inputs in each EA** — `InpAllowSparseIntrabarSingleVoter`, `InpSparseIntrabarMinQuality`,
  `InpSparseIntrabarMinSupportRatio`, `InpSparseIntrabarMinReadyCoverage`, `InpIntrabarSingleVoterMinConfidence`,
  `InpSyntheticLeanSparseIntrabarMinQuality`, `InpSyntheticLeanIntrabarSingleVoterMinConfidence` — with their
  config fields, per-symbol resolvers, manager setters and quorum-storage fields. They were the reason those two
  evaluators looked configured rather than abandoned.

Two findings worth reading as an operator:

**Probe eligibility was never assignable.** `SStrategyEntry.isProbeEligible` has no writer anywhere — registration
sets the intrabar policy, never this field — so even if the probe path had been wired it would have counted zero
eligible voters and abstained every scan. That is why deleting seven inputs changes no trade count: the gate they
configured could not run, and could not have admitted anything.

**The ADX handle cache never held a handle.** Only the deleted trending-regime test called `SetAdxHandleCached`,
so the cached handle stayed invalid for the life of every symbol, and two deinit blocks "released" it. Removed
with the test.

`[ENTERPRISE-CONFIG]` no longer prints `sparse_single_voter=`, `sparse_quality=`, `sparse_support=`,
`sparse_ready=` or `single_voter_min_conf=`, and `[SYMBOL-PROFILE]` loses the same two trailing numbers. Those
fields made unreachable controls look configured — the reason we now treat an init line naming a setting as
evidence only if the value is read on a path that can be entered. `INTRABAR_POLICY_PROBE` stays selectable in the
dialog and keeps its one live meaning: on a synthetic-lean roster it behaves as `LIVE`.

### Batch 230: a 242-line fallback that could never be called, and the fields that only it read

The consensus engine carried a "solo fallback" for the case where every strategy abstains. Nothing in the
repository called it — the manager's forwarder had no caller, the engine's public method was reachable only
through that, and the implementation only through that. Its comment already said *Dead path*. Gone: 242 lines
across four files, plus three roster getters, three manager forwarders, and four `SStrategyEntry` fields
(`participation`, `readinessScore`, `contextScore`, `costScore`) whose comment claimed the pipeline filled them.
No line ever wrote those fields, which is the proof this was never a live control: had it been wired, every
solo candidate would have scored 0.0 on its own quality formula and been refused. Your live authority
measurements are unaffected — those come from pipeline evidence averaged into the consensus decision context
(Batch 205), which is what sizes your lots.

**Corrected by Batch 231:** the last paragraph here is wrong. The probe path was not live, and those inputs did
not gate any trades — so deleting them changed nothing about how many trades you get. See the Batch 231 entry.

Still live and honoured: the intrabar **probe** path, gated by `InpSparseIntrabarMinQuality` and
`InpSparseIntrabarMinSupportRatio`. What we found and did not touch: four more quorum inputs that reach no decision at all —
`InpSparseIntrabarMinReadyCoverage`, `InpAllowSparseIntrabarSingleVoter`, and the pair
`InpIntrabarSingleVoterMinConfidence` / `InpSyntheticLeanIntrabarSingleVoterMinConfidence` (both 0.95, both
feeding one unread field). Two of them are printed at init as if they were settings, and the single-voter
switch reads as "off" while a lone probe winner passes whenever three or fewer strategies are probe-eligible.
Deleting or wiring those changes how many trades you get, so it is flagged for your call rather than decided in a
cleanup.

### Batch 229: a risk collaborator nobody read, and 90 comment lines that restated the code

`CRiskValidationPipeline` was handed eleven pointers and stored one — the adaptive risk tuner — that no line in
the class ever read. Its comment admitted this ("stored but never used, so it is not gated") and the class's
health probe `IsWired()` checked the ten live ones and skipped it, so the check agreed with the dead weight
instead of flagging it. The pointer, its parameter and its include are gone. Nothing about risk behaviour moved:
`CUnifiedRiskManager` still reads the tuner at fourteen sites, including the factor that gives you budget back
when a position is in profit. This is the case for why the pointer went — one decision, one reader.

The rest is comment surface: fifteen files carried 8-13 line blocks listing the members and includes declared a
few lines below, and cutting them (runs of 8+ consecutive comment lines: 17 → 1) turned up two wrong claims
worth more than the lines saved. The neural net's meta-input header said "24 features" for a 26-slot vector —
`BuildInput` fills `[0]`..`[25]` into an array `AI_MLP_INPUT` sizes at 26, so anyone matching a training matrix
to that comment was sizing the input wrong — and the walk-forward validator named a consumer file that does not
include it. Both corrected. If you train or export model data, trust `AI_MLP_INPUT`, not prose.

### Batch 228: the build script reported success for compiles it had abandoned

`sync_and_compile.ps1` waited 180 s for each compile to write its `Result:` line, and when it didn't arrive it
counted error lines in the log so far — a compile still running has none — printed `0 errors, 0 warnings` and
called the build a success. `MultiStrategyAutonomousEA.mq5` needs **257 s**, so that file never passed on
merit: the script gave up, reported green, and the next iteration's process cleanup killed the compiler before
it wrote its binary. Both EA `.ex5` files were still from **2026-10-17 17:22 / 17:24** — the compile right
before the Batch 225 commit — while Batches 226 and 227 each claimed a clean eight-program compile. Attaching
the EA this week loaded the Batch 225 build: no `[RISK-ASSET-DD]` halt line, no `[QUORUM-PRECEDENCE]`, with a
changelog saying both existed. How far back this hid cannot be recovered, because an interrupted compile leaves
no trace in a partial log.

What changed: the wait is `-MaxCompileWaitSec` (default 420), a log that never finalizes is a **failure**
rather than a silent zero, a missing log is too, and the script exits 1 on any of those so `EXIT=0` means the
compiler finished. Verified by the run that proved it: all eight programs wrote their own `Result:` line, all
at 0 errors / 0 warnings (18.0 / 7.2 / 12.8 / 12.1 / 257.6 / 112.0 / 40.4 / 5.6 s), and all eight binaries were
rewritten. Before you deploy, check the `.ex5` timestamp against your last edit — that comparison is now part of
the definition of a verified build (AGENTS.md §7).

### Batch 227: the quorum profile, not your four inputs, sets the voting bar

`InpMinLiveVoters`, `InpQuorumThreshold` and the two `InpConsensusSupportFloor*` inputs are applied per symbol
and then **overwritten** by `InpQuorumProfile`, because a preset moves that set together — BALANCED (the
default) 1 voter / 0.50 / 0.25 / 0.20, CONSERVATIVE 2 / 0.60 / 0.35 / 0.30, AGGRESSIVE 1 / 0.45 / 0.15 / 0.10.
The startup line printed the numbers you typed as though they were what ran, so on defaults it claimed a
stricter voter floor and a looser support floor than the committee held — in opposite directions — and editing
any of those four showed you the edit rather than the effect. The precedence is kept: letting one input win
would silently override the relaxation AGGRESSIVE exists to provide. What shipped is that you can read it:
`[ENTERPRISE-CONFIG]` shows what the manager holds, and a new
`[QUORUM-PRECEDENCE] EURUSD | profile=BALANCED | minQuorum input=2 stored=1 enforced=2 | …` prints once per
symbol at start with all three stages of every quorum field. Two facts come out of that line:
`MIN_CONSENSUS_VOTERS = 2` sits on top of whatever voter floor is stored, so no preset and no input has ever
been able to trade on a single voter, and `intrabarMinQuorum` is the one field the profile does not write — the
only quorum number your input still controls. No threshold, comparison or admission decision moved.

### Batch 226: a correlation shrink that could never run, and a halt that now says what it measures

The position sizer carried its own correlation-based lot reduction - measure the average positive
correlation to your other open positions, scale the lot by `1 - that`, floored at 0.25. It was switched off by
the only thing that ever set the flag (`false` in the constructor, `false` from the orchestrator, no other
writer), so it never touched a lot while still printing lines that implied it did. Deleted: both methods, the
engine pointer and its setter, and a threshold setter with no callers. It was not switched on, because
correlation already shrinks the lot exactly once - in the risk pipeline's REDUCE tier, which every book now
honours - and two reductions multiplied against one lot is the ADX-doubling bug from Batch 213 in a different
class. `useVolatilityAdjustment` went with it: written `true` once, read nowhere, not even initialised.

The per-asset drawdown ceiling compared the **account's** peak drawdown against a symbol's class limit
(Forex 10%, Metals 12%, Step 8%) and called the result "Family drawdown limit reached for EURUSD" with no
journal line at all. It now prints `[RISK-ASSET-DD] ... accountDD= ceiling= criticalLimit=` and says which two
numbers were compared. The thresholds themselves are untouched: with `InpMaxDrawdown = 15` you can be stopped
at 10% on a class ceiling, which is what the profiles say, and changing a halt is your decision - but it will
not be invisible.

### Batch 225: an input that only moved a log line, plus four pieces of state nothing read

`InpAIStandaloneRelaxedConfidence = 0.60` is the bar the EA is supposed to fall back to when a symbol's
committee has produced no indicator signal for `InpHybridGateRelaxAfterCycles` scans. `[HYBRID-GATE-RELAXED]`
printed "AI threshold 0.650 -> 0.600" and the gate tested 0.650 anyway: the number that binds lives in
`CLiveAuthorityResolver`, and the relaxed value reached only a print statement. The builder's per-symbol state
now feeds the resolver before each decision, so the relaxed bar is real - which means AI-standalone entries on
indicator-quiet symbols at 0.60-0.65 confidence, previously refused, are now admitted. `[AUTHORITY-CONFIG]`
reports `standaloneConf=` at init so you can see the input landed.

Deleted as unread: `InpPortfolioMaxPositionsPerSymbol` (a second per-symbol cap, tighter than
`InpMaxPositionsPerSymbol = 5` and never consulted - 5 was always the real limit), `CRiskTieredCorrelation`'s
reduce/block threshold copies (the pipeline enforces those tiers), `SValidationResult.confidenceMultiplier`
(only ever written 1.0 while a caller multiplied confidence by it), `SPositionSizingParams.correlationAdjustment`
and `STradeCandidate.liveAuthorityAllowed`. Each removal is state the code kept alive so a reader could believe
a control existed.

### Batch 224: a cap that applied to the wrong symbols, and refusals that did not say why

The per-family position limit counted `DERIV_UNKNOWN` - the answer `DetectFamily` gives to every symbol that
is *not* a Deriv synthetic - as a family. Six of your thirteen default symbols (EURUSD, GBPUSD, USDJPY,
AUDUSD, XAUUSD, BTCUSD) therefore shared a single 3-position bucket between them, a limit tighter
than `InpMaxPositionsPerSymbol = 5` and `InpMaxPositionsTotal = 15` and one you could not see in the inputs
dialog. The cap now applies only to a real synthetic family, and those symbols are bounded by the caps that
name them.

Three books - ATR scalp, grid recovery, spike hunter - asked the unified risk manager for permission and used
only the yes/no. The correlation shrink, the lot-floor adjustment and the recomputed risk percentage were
discarded, while the fast scalp has honoured the shrink since Batch 192. They now adopt it shrink-only and
log it (`[ATR-SCALP-RISK-ADJUSTED]`, `[GRID-RISK-ADJUSTED]`, `[SPIKE-RISK-ADJUSTED]`), and their refusals
print a reason: they were printing `reason=` with nothing after it, because the field they read is cleared by
`ZeroMemory` and nothing in `Core/Risk/` ever writes it. The populated field is `.message`.

Not changed, with the reason: the cluster letter is still not decoded from position comments, so
`[RISK-CLUSTER]` counts same-symbol positions only and `[RISK-CLUSTER-SYNC]` reconciles nothing. Wiring it
would rewrite the field that identifies a position's owner and would loosen the opposing-position mutex at the
same time. `AGENTS.md` said it counted clusters that can be entered; that sentence was wrong and is fixed.

### Batch 223: three risk ceilings that could not bind

Each of these was written as a limit and reads as a limit in the logs, but its own arithmetic made refusal
unreachable - and the unreachable direction was always "let more risk through".

- `ApplyDrawdownScaling` decided whether a sub-minimum lot may be rounded up by comparing
  `brokerMinLot / lotSize` against `InpMinLotRiskMultiplier`. Under the branch that computes it, that ratio is
  always below 1.0 while the ceiling is 15.0, so the check never failed and every drawdown shrink that fell
  under the broker minimum became a full minimum-size lot. It now measures the round-up the way the risk
  pipeline does (the factor the shipped lot exceeds the intended one) and refuses above the ceiling with
  `[RISK-GATE-REJECT] ... reason=drawdown_lot_below_min`.
- The daily-risk projection gate tested `projectedDailyRisk > maxDailyRiskPercent` on a value that
  `GetEffectiveDailyRiskUsedPercent` has already clamped to `maxDailyRiskPercent`. Impossible by construction;
  now `>=`, like the pre-approval gate above it, and it prints `[RISK-DAILY-LIMIT]` instead of only writing a
  JSON record nobody reads at the moment of refusal.
- Per-cluster risk caps were stored as absolute percentages (`T` 10.0, `R` 5.0), so
  `InpRiskMaxClusterExposurePct` reached only the clusters with no row and trend ran at double the configured
  cluster exposure whatever you set. They are factors of your number now (2.0x, 1.0x) - same values at the
  default, and bounded by your ceiling at any other.

Untouched on purpose: the margin-health constants (200% floor, 0.8 free-margin usage) and the CVaR cap (0.10)
have no setter call and no input; their comments admit it, and inventing thresholds is your call, not a
cleanup.

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
  Processing/                   # DerivAssetProfiler, MultiAssetProfiler
  Signals/                      # SignalDiagnostics
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
