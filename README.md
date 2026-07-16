# MetaTrader Multi-Strategy Autonomous EA

![Status](https://img.shields.io/badge/status-production-blue)
![Batch](https://img.shields.io/badge/batch-122-green)
![Platform](https://img.shields.io/badge/platform-MetaTrader%205-orange)
![Strategies](https://img.shields.io/badge/strategies-15-purple)
![Academic Rigor](https://img.shields.io/badge/academic_rigor-validated-brightgreen)

## Overview

**MultiStrategyAutonomousEA** is an autonomous multi-strategy trading system for MetaTrader 5 that combines 15+ strategy modules across three tiers (Institutional, Structure, Indicator) through a weighted consensus voting mechanism. Built for serious traders who need enterprise-grade signal validation before any order touches the broker.

The system covers **Forex, Metals, Indices, Energies, and 18 Deriv synthetic index families** with per-asset-class optimization — automatically detecting instrument types and applying tailored risk parameters, lot scaling, and strategy weights. AI modes (Indicator Only, AI Only, Hybrid) let operators control the blend of human-designed strategies and machine-learned predictions.

Designed for production: every trade entry passes through a multi-layer pre-trade gate (risk, correlation, portfolio exposure, spread, session, regime) before reaching centralized execution. No single strategy can bypass the unified risk authority.

**Academic Rigor (Batch 122):** Complete modular architecture migration with 6 registries and 8 orchestration modules. All critical bugs fixed — magic number overflow protection, PERIOD_CURRENT misuse in ATR calculations (4 locations), memory leaks in strategy registration (20+ allocation paths), MQL5 API error handling, and resource cleanup verification. ~2,000 lines of dead code removed from main EA. System compiles with 0 errors, 11 warnings (style only).

**Phase 4 Observability (Batch 123):** Structured JSON logging with correlation IDs, PERIOD_CURRENT audit complete (all indicator calls validated), CIndicatorManager FindHandle paramCount fix, unit test scaffolding for core math modules.

## Key Features

- **Multi-Strategy Consensus** — 15 strategy modules vote through weighted quorum; no single strategy can unilaterally enter a trade
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

## Strategy Roster

| Strategy | Tier | Cluster | Weight | Description |
|----------|:----:|---------|:------:|-------------|
| Unified ICT | 1 | STRUCTURE | 1.2 | ICT/SMC: FVG, OB, BOS/CHOCH, CISD, kill zones |
| FVG Scalper | 2 | STRUCTURE | 1.8 | Fair Value Gap scalper with structure alignment |
| Turtle Soup | 2 | STRUCTURE | 1.6 | Liquidity sweep detection + confirmation |
| Breaker Block | 2 | STRUCTURE | 1.7 | Failed OB → breaker retest entries |
| NY Open Gap | 3 | STRUCTURE | 1.3 | NY session open gap fade |
| Asian Range Break | 3 | STRUCTURE | 1.3 | Asian range breakout at London open |
| Power of Three | 1 | STRUCTURE | 1.2 | Accumulation/Manipulation/Distribution |
| Unicorn Model | 1 | STRUCTURE | 1.2 | Unicorn pattern (OB + FVG confluence) |
| Support/Resistance | 3 | MEAN_REVERSION | 1.0 | S/R with Fibonacci confluence + Hurst filter |
| Trend | 3 | TREND | 1.0 | EMA crossover + ADX + multi-TF alignment |
| Momentum | 3 | TREND | 1.0 | Simplified 4-indicator momentum with scalp mode |
| Candlestick | 3 | MEAN_REVERSION | 0.8 | Engulfing, pin bar, Doji patterns |
| Mean Reversion | 3 | MEAN_REVERSION | 1.0 | Bollinger band reversion with z-score |
| Volatility Breakout | 3 | TREND | 1.0 | ATR compression breakout |
| Statistical Arbitrage | 3 | MEAN_REVERSION | 0.8 | Pair correlation / spread reversion |

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

## Python Integration

The Python ML pipeline (`Python/`) provides:

- **Feature Engineering** — 57 universal features + 26 Deriv-specific + asset-class extensions
- **Training Scripts** — Per-asset-class model trainers (CatBoost, XGBoost, LightGBM, stacking)
- **ONNX Export** — Trained models exported to `Resources/model.onnx` for MT5-native inference
- **ZMQ/HTTP Bridge** — Real-time prediction server with health monitoring and reconnection
- **Feature Cross-Check** — Validates Python-vs-MQL feature parity

## Project Structure

```
MultiStrategyAutonomousEA.mq5    # EA entry point
IndicatorManager.mqh             # Singleton indicator cache
Core/
  ├── Engines/                   # Market analysis engines (Trend, Regime, Volatility, Hurst, VPIN, OU, OFI, VWAP, VolumeProfile, CVD)
  ├── Pipeline/                  # UnifiedSignalPipeline (regime, cost, spread filtering)
  ├── Management/                # EnterpriseStrategyManager, PositionLifecycleManager, SymbolUniverseBuilder
  ├── Risk/                      # UnifiedRiskManager, PositionSizer, PortfolioRiskManager, CorrelationEngine, EquityCurveManager
  ├── Trading/                   # TradeManager, PositionStateManager, TradeAttributionManager
  ├── Scalp/                     # SpikeHunterEngine, GridRecoveryEngine, ATRScalpingEngine, FastScalpEngine
  ├── Strategy/                  # AI adapters (ONNX, Transformer, Ensemble), StrategyBase, StrategyRegistry
  ├── AI/                        # AIFeatureVectorBuilder, PipelineScaler, NNModelStorage
  ├── Processing/                # TickSafetyMonitor, BarProcessor, DerivAssetProfiler, MultiAssetProfiler
  ├── Signals/                   # SignalDiagnostics, TimeframeConsistency
  ├── Monitoring/                # PerformanceAnalytics
  ├── Visualization/             # VisualDashboard, ChartDrawingManager
  ├── Utils/                     # PythonBridge, Instruments, Enums, SessionManager, ErrorHandling
  └── Cache/                     # ATRCache, ConsensusCache
Strategies/                      # 15 strategy modules
Python/                          # ML training, ONNX export, ZMQ bridge
Resources/                       # Trained ONNX models
Dashboard/                       # Dashboard components
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
