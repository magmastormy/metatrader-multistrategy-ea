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
  Processing/                   # TickSafetyMonitor, BarProcessor, DerivAssetProfiler, MultiAssetProfiler
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
