# MetaTrader Multi-Strategy Autonomous EA

A MetaTrader 5 Expert Advisor that forms weighted strategy votes per symbol, then applies configured admission checks and centralized pre-trade risk validation. The default `InpMinLiveVoters=1` permits a single live voter when other entry checks pass; multi-strategy agreement is not guaranteed.

> **Risk warning:** This software trades real money when attached to a live account. Backtest and forward-test on a demo account before running it live. Past results do not guarantee future performance, and you are responsible for the settings you choose.

## Features

- **Weighted voting.** Strategy tiers contribute configured weights. Quorum and confidence settings apply only where their runtime gates are wired; the default minimum is one live voter.
- **Centralized risk authority.** Per-trade, daily, portfolio, correlation, drawdown, and margin checks run before any order is sent. Exposure checks exclude a candidate's own reservation by owner tag while including other pending risk in portfolio and symbol budgets.
- **Per-asset-class profiles.** Symbols are classified automatically (Forex, Metals, Indices, Energies, Deriv synthetics), and risk parameters and strategy weights are adjusted per class.
- **AI operating modes.** `INDICATOR_ONLY`, `AI_ONLY`, and `HYBRID` control how human-designed strategies and machine-learned predictions are blended.
- **Python ML bridge.** A ZMQ/HTTP bridge connects to Python-trained CatBoost, XGBoost, and LightGBM models. Trained models can also be exported to ONNX and run natively in MT5.
- **Deriv synthetic support.** Family-specific engines cover spike trading, grid recovery, and ATR-based scalping.
- **Observable decisions.** Structured logs with correlation IDs record why each signal was accepted, filtered, or vetoed.

## Architecture

```
Strategies --> Signal Pipeline --> Weighted Consensus --> Risk Gate --> Execution --> Position Lifecycle
(indicator / AI)   (configured checks; engine-backed filters are opt-in)


```

Signal flow: strategies produce votes; configured pipeline checks run, while registry-backed trend, volatility, liquidity, structure, and regime/cost filters pass through by default when `InpPipelineEngineRegistry=false`. Consensus applies its configured quorum, the risk gate validates exposure and drawdown, execution places approved orders, and the lifecycle manager handles stops and exits.

For the full component ownership map, see [SYSTEM_STRUCTURE.md](SYSTEM_STRUCTURE.md).

## Requirements

- MetaTrader 5 with MetaEditor (MQL5 compiler)
- Python 3 for the training pipeline and the optional ML bridge (only needed if you use those features)

## Getting Started

1. **Install.** Copy the repository into a folder under your MT5 `MQL5/Experts/` directory, keeping the folder structure intact. The EA uses relative includes, so partial copies will fail to compile.
2. **Compile.** Open the EA in MetaEditor and compile it. Confirm there are no errors.
3. **Attach.** Drag the EA onto a chart (for example EURUSD M15).
4. **Set symbols.** `InpSymbolsToTrade` is the exact trading universe. The chart symbol is never injected; include it explicitly if it should trade.
5. **Set risk.** Review the risk inputs (per-trade, daily, and portfolio risk percentages, and the drawdown thresholds) before enabling trading.
6. **Choose a mode.** Set `InpEAMode` to `EA_MODE_INDICATOR_ONLY`, an AI-only mode, or `EA_MODE_HYBRID` (the default).

Enable a feature only after you understand what it does. Defaults are set in the input dialog and in the source files.

## Configuration

Settings are exposed as EA inputs in these groups:

| Group | What it controls |
|-------|------------------|
| Risk | Per-trade and daily risk budgets, portfolio exposure, drawdown warning and stop thresholds, minimum lot risk |
| Strategies | Enable flags for each strategy module and strategy weights |
| AI | Operating mode, which AI adapters are active, and the Python bridge mode |
| Live overrides | `Config/live_overrides.json` applies supported risk keys only; unsupported strategy weights, thresholds, symbols, AI, and engine changes are logged but not applied |

Startup risk inputs define the hard operator envelope; risk tiers and compounding can only reduce it. The live override file is a second, risk-only control channel that can tighten this envelope, not raise it above startup inputs. Risk-tier policy is startup-only and requires reinitialization; a `risk.riskTier` override is logged and ignored. Compounding can be toggled live, and unrelated or unchanged file edits preserve the current adaptive/compounding state. Verify effective values in `[RISK-TIER]`, `[COMPOUNDING-TIER]`, `[RISK-OVERRIDE]`, and `[LIVE-CONFIG-RISK]` logs.

## Current state (2026-11-19)

The latest measured comparison is Batch 298: the six-symbol trim was rejected, leaving the eight-symbol roster unchanged. The current cleanup compiles with zero errors and zero warnings across all eight MetaTrader targets; the dashboard build passes with an advisory large-chunk warning. It has no paired cold-window backtest, so historical performance results do not validate this source state.

Runtime limitations: pipeline confidence applies only when that pipeline runs, while engine-derived filters pass through by default because the math-engine registry is unbound. Safe-mode FX kill-zone and news filters are unavailable. Per-strategy intrabar-eligibility settings and policy metadata were removed because no decision path enforced them; Momentum and Candlestick timeframe overrides remain active. Position contributors are unioned across fills; only exact single-contributor closes update a bounded health score that can modify vote weight; there is no hard strategy auto-parking, and the score is not dollar-expectancy evidence. Mixed and unattributed P&L is excluded, not apportioned. The live reloader applies risk fields only; unsupported strategy changes are explicitly logged as ignored. Candidate sizing enforces the minimum-lot permission and uplift ceiling after drawdown and momentum scaling; the current MQL source compiles cleanly and the dashboard build passes with a large-chunk advisory; paired cold-window tests remain pending.

## Strategy Roster

### Indicator-based strategies

| Strategy | Tier | Description |
|----------|:----:|-------------|
| Momentum | 3 | Four-indicator momentum with an optional scalp mode |
| Trend | 2 | EMA crossover, ADX, and multi-timeframe alignment |
| Support/Resistance | 2 | Support and resistance levels with Fibonacci confluence |
| Candlestick | 2 | Engulfing, pin bar, and Doji patterns |
| Mean Reversion | 2 | Bollinger band reversion with z-score filtering |
| Volatility Breakout | 1 | ATR compression breakouts |
| Statistical Arbitrage | 2 | Pair spread reversion (requires the Python bridge) |
| FVG Scalper | 2 | Fair value gap entries with structure alignment |
| Turtle Soup | 2 | Liquidity sweep detection with confirmation |
| Breaker Block | 2 | Failed order block retests |
| NY Open Gap | 3 | New York open gap fades |
| Asian Range Break | 3 | Asian session range breakouts at the London open |
| Liquidity Sweep | 2 | Sweep-and-reclaim entries |
| Range Compression | 2 | Compression breakouts with a trend cluster |

### AI adapters

| Adapter | Description |
|---------|-------------|
| Neural Network | Feedforward network with online learning |
| Transformer | Multi-scale attention model |
| Ensemble | Stacked CatBoost, XGBoost, and LightGBM models |
| ONNX | Python-trained models executed natively in MT5 |
| Python Bridge | External inference through the ZMQ/HTTP bridge |

All AI adapters are symbol-scoped and cache results per bar. Disabled adapters are not instantiated.

## Standalone Testing EA

`MultiStrategyTestingEA.mq5` isolates individual strategies, AI adapters, and engines for backtesting and optimization without changing the production EA. Select a predefined test profile with `InpCompleteTestProfile`. The EA logs the effective component configuration per symbol, so you can confirm what actually ran.

## Supported Instruments

| Asset class | Examples | Notes |
|-------------|----------|-------|
| Forex | EURUSD, GBPUSD, USDJPY | Standard ATR-based stops and targets |
| Metals | XAUUSD, XAGUSD | Separate volatility parameters |
| Indices | US30, NAS100, SPX500 | Separate volatility parameters |
| Energies | USOIL, NATGAS | Separate volatility parameters |
| Deriv synthetics | Volatility, Crash/Boom, Step, Jump, and more | Family-specific engines and profiles |

## Python Pipeline

The `Python/` directory contains the ML pipeline:

- **Feature engineering.** Universal features plus Deriv-specific and asset-class extensions
- **Training.** Per-asset-class trainers for CatBoost, XGBoost, LightGBM, and stacking models
- **ONNX export.** Trained models are exported to `Resources/` for native MT5 inference
- **Bridge.** A ZMQ/HTTP prediction server with health monitoring and reconnection
- **Validation.** Feature parity checks between Python and MQL5

Google Colab notebooks for training are included in `Python/`.

## Project Structure

```
MultiStrategyAutonomousEA.mq5   Main EA (production)
MultiStrategyTestingEA.mq5      Strategy and engine test harness
IndicatorManager.mqh            Shared indicator handle cache
Core/                           Engines, management, risk, trading, AI, scalp, utilities
Strategies/                     Indicator-based strategy modules
AIModules/                      AI models and adapters
Interfaces/                     Strategy and AI interfaces
Python/                         Training scripts, ONNX export, ZMQ bridge
MQHModelTrainer/                MQL5 model trainer and evaluator (see its README)
Tools/walkforward/              Walk-forward validation tools (see its README)
Dashboard/                      Web dashboard
Config/                         Runtime configuration overrides
Resources/                      Trained model artifacts
docs/                           Supplementary documentation
```

## Documentation

| Document | Purpose |
|----------|---------|
| [SYSTEM_STRUCTURE.md](SYSTEM_STRUCTURE.md) | Architecture and component ownership |
| [RUNTIME_DECISION_GRAPH.md](RUNTIME_DECISION_GRAPH.md) | How a signal becomes a trade decision |
| [changelogs.md](changelogs.md) | Dated record of changes by batch |
| [AGENTS.md](AGENTS.md) | Development workflow and runtime invariants |
| [MAINTENANCE_PROTOCOL.md](MAINTENANCE_PROTOCOL.md) | Maintenance process |
| [MQHModelTrainer/README.md](MQHModelTrainer/README.md) | Model training workflow |
| [Tools/walkforward/README.md](Tools/walkforward/README.md) | Walk-forward validation |

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for the full text.

Copyright (c) 2026 magmastormy / Axiom Engineering Studio.
