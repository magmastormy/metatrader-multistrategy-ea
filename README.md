# MetaTrader Multi-Strategy Autonomous EA

A MetaTrader 5 Expert Advisor that makes trade decisions by weighted consensus. Fourteen indicator-based strategy modules and five AI adapters each vote on a symbol, and no single strategy can enter a trade alone. Every entry must then pass a centralized pre-trade risk gate before execution.

> **Risk warning:** This software trades real money when attached to a live account. Backtest and forward-test on a demo account before running it live. Past results do not guarantee future performance, and you are responsible for the settings you choose.

## Features

- **Weighted consensus voting.** Strategies are grouped into Institutional (ICT/SMC), Structure (support/resistance, trend), and Indicator (momentum, candlestick, moving averages) tiers. A quorum and minimum confidence are required before an entry is considered.
- **Centralized risk authority.** Per-trade, daily, portfolio, correlation, drawdown, and margin checks run before any order is sent. Virtual reservations stop concurrent signals from double-counting the same risk budget.
- **Per-asset-class profiles.** Symbols are classified automatically (Forex, Metals, Indices, Energies, Deriv synthetics), and risk parameters and strategy weights are adjusted per class.
- **AI operating modes.** `INDICATOR_ONLY`, `AI_ONLY`, and `HYBRID` control how human-designed strategies and machine-learned predictions are blended.
- **Python ML bridge.** A ZMQ/HTTP bridge connects to Python-trained CatBoost, XGBoost, and LightGBM models. Trained models can also be exported to ONNX and run natively in MT5.
- **Deriv synthetic support.** Family-specific engines cover spike trading, grid recovery, and ATR-based scalping.
- **Observable decisions.** Structured logs with correlation IDs record why each signal was accepted, filtered, or vetoed.

## Architecture

```
Strategies ──▶ Pipeline ──▶ Consensus ──▶ Risk Gate ──▶ Execution ──▶ Position Lifecycle
(indicator,    (regime,     (weighted     (pre-trade    (TradeManager)  (SL / breakeven /
 AI adapters)   cost,        quorum)       validation)                   trailing)
               spread)
```

Signal flow: a strategy produces a signal, the pipeline filters it by regime, cost, and spread, the consensus manager tallies weighted votes, the risk gate validates exposure and drawdown, `TradeManager` executes, and the position lifecycle manages stops and exits.

For the full component ownership map, see [SYSTEM_STRUCTURE.md](SYSTEM_STRUCTURE.md).

## Requirements

- MetaTrader 5 with MetaEditor (MQL5 compiler)
- Python 3 for the training pipeline and the optional ML bridge (only needed if you use those features)

## Getting Started

1. **Install.** Copy the repository into a folder under your MT5 `MQL5/Experts/` directory, keeping the folder structure intact. The EA uses relative includes, so partial copies will fail to compile.
2. **Compile.** Open the EA in MetaEditor and compile it. Confirm there are no errors.
3. **Attach.** Drag the EA onto a chart (for example EURUSD M15).
4. **Set symbols.** Set `InpSymbols` to the instruments you want to trade. Asset class is detected automatically.
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
| Live overrides | `Config/live_overrides.json` can change selected risk values while the EA is running |

The input dialog is the authoritative list of parameters and their current defaults.

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

Proprietary. All rights reserved.
