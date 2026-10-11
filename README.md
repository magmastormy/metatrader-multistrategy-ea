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
| `InpCorrelationBlockThreshold` | 0.7 | Correlation block threshold |

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
| `InpEnableUnifiedICT` | true | ICT/SMC structure |
| `InpEnableFVGScalper` | true | FVG gap scalper |
| `InpEnableTurtleSoup` | true | Liquidity sweep (Turtle Soup) |
| `InpEnableBreakerBlock` | true | Breaker block entries |
| `InpEnableNYOpenGap` | true | NY open gap fade |
| `InpEnableAsianRangeBreak` | true | Asian range breakout |
| `InpEnablePowerOfThree` | true | Power of Three |
| `InpEnableUnicornModel` | true | Unicorn model |
| `InpEnableStatArb` | true | Statistical arbitrage |

### Strategy Slot Scheme (semantic-only, Batch 147)

The per-strategy enable flags (`strategyFlags[]`) are written by a single producer (`COrchestratorStrategyFlagBuilder::BuildStrategyFlags`) at **semantic `SI_*`** slots, and `CEnterpriseStrategyManager::AutoRegisterStrategies` reads them back through `CatalogEnableSlot(i)` — so reader and writer always agree. The legacy literal slot scheme that Batch 146 shipped dormant was **removed entirely in Batch 147**; there is no mode switch.

| Slot | Resolved by | Notes |
|---|---|---|
| Enable flag | `SI_*` (`ENUM_STRATEGY_INDEX`), via `CatalogEnableSlot(i)` | `-1` = always on |
| Intrabar policy | own `StrategyConfigBuilder` row, via `CatalogPolicySlot(i)` | `-1` = use `fixedPolicy` |

The always-LIVE intrabar fallback for Mean Reversion / Volatility Breakout is hardcoded to semantic slots `7/8` in `CIntrabarPolicy::GetIntrabarPolicyHelper`.

Registration prints a `[CATALOG-AUDIT]` block on every boot confirming `slot_scheme=SEMANTIC` and listing each strategy's enable/policy slot.

## Strategy Roster

### Indicator-Based Strategies (15 Active)

| Strategy | Tier | Cluster | Weight | Description |
|----------|:----:|---------|:------:|-------------|
| Momentum | 3 | TREND | 1.0 | Simplified 4-indicator momentum with scalp mode |
| Trend | 2 | TREND | 1.2 | EMA crossover + ADX + multi-TF alignment |
| Support/Resistance | 2 | MEAN_REVERSION | 1.5 | S/R with Fibonacci confluence + Hurst filter |
| Candlestick | 2 | STRUCTURE | 1.5 | Engulfing, pin bar, Doji patterns |
| UnifiedICT | 2 | STRUCTURE | 1.5 | ICT/SMC structure with order blocks and FVG |
| Unicorn Model | 1 | STRUCTURE | 2.4 | Unicorn pattern (OB + FVG confluence) |
| Power of Three | 1 | STRUCTURE | 2.3 | Accumulation/Manipulation/Distribution |
| Mean Reversion | 2 | MEAN_REVERSION | 1.8 | Bollinger band reversion with z-score |
| Volatility Breakout | 1 | TREND | 2.0 | ATR compression breakout |
| Statistical Arbitrage* | 2 | MEAN_REVERSION | 1.8 | Pair correlation / spread reversion (Python bridge required) |
| FVG Scalper | 2 | STRUCTURE | 1.8 | Fair Value Gap scalper with structure alignment |
| Turtle Soup | 2 | STRUCTURE | 1.6 | Liquidity sweep detection + confirmation |
| Breaker Block | 2 | STRUCTURE | 1.7 | Failed OB → breaker retest entries |
| NY Open Gap | 3 | STRUCTURE | 1.3 | NY session open gap fade |
| Asian Range Break | 3 | STRUCTURE | 1.3 | Asian range breakout at London open |

*Statistical Arbitrage is only registered when Python Bridge is connected.

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
- **Levers, in order of preference:** widen the stop at the same risk percentage (raises the approved lot above the minimum), revisit the `AUTHORITY_MIN_*` floors in `LiveAuthorityResolver.mqh`, or accept the smaller size. There is no input that turns the ladder back off — that would mean removing the call at `EAOrchestrator.mqh:3425`.
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
