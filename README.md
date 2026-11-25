# MetaTrader Multi-Strategy Autonomous EA

A MetaTrader 5 Expert Advisor that forms weighted strategy votes per symbol, then applies configured admission checks and centralized pre-trade risk validation. The default `InpMinLiveVoters=1` permits a single live voter when other entry checks pass; multi-strategy agreement is not guaranteed.

> **Risk warning:** This software trades real money when attached to a live account. Backtest and forward-test on a demo account before running it live. Past results do not guarantee future performance, and you are responsible for the settings you choose.

## Which symbols to use — read this first

**Measured best: Deriv synthetic indices.** The shipped universe is `Crash 1000 Index,Boom 1000 Index`. Every
gain number in [RUNS_AND_GAINS.md](RUNS_AND_GAINS.md) comes from that book.

| Preference | Symbol | Evidence |
|---|---|---|
| 1 — primary payer | `Crash 1000 Index` | The only row that paid in every measured window; it decides the book. |
| 2 — second payer | `Boom 1000 Index` | Adds +0.8 to +20.7 pp paired out-of-slice; needs the per-symbol spread override that ships as the default (`Boom 1000 Index=25000`). |
| Avoid | `Jump 75`, `Step Index`, `Volatility *` | Measured negative as a second row, or trimmed out of the book on measured grounds. Do not mix them back in without a paired cold-window test. |

**Do not use this EA on FX currency pairs.** This is measured, not a preference. Seven majors
(`EURUSD, GBPUSD, USDJPY, USDCHF, AUDUSD, USDCAD, NZDUSD`) were run cold on the shipped defaults, same windows as
the synthetic book:

| Window | 7 FX majors | `Crash+Boom` |
|---|---|---|
| 08.01 to 08.08 | **-4.632%** (203 fills) | +21.100% |
| 09.22 to 09.29 | **-5.615%** (209 fills) | +39.266% |

Six of seven rows were negative in both windows, and the two sizing levers were also tested: doubling per-trade
risk moved the result by -1.20 pp and +0.13 pp (inside noise, still deeply negative), and disabling the lot floor
(`InpMinLotRiskMultiplier=1.0`) produced **identical** results to the cent. The loss is signal quality on majors
plus modelled spread, not position size, so there is no setting here that rescues it.

**Metals, indices, and energies are untested.** They are classified and supported in code, but no cold paired
window exists for them in this repository. Treat them as unknown, not as recommended.

**The one thing FX teaches about the edge:** it is a synthetic-spike mechanism. A minimum lot on `Crash 1000`
captures a large point move; the same minimum lot on `EURUSD` captures a couple of dollars against spread. Do not
carry the configuration across asset classes without re-measuring.

## What it does

The EA runs a multi-strategy consensus engine on MetaTrader 5. Each enabled strategy casts a weighted vote per symbol; votes are aggregated, quorum and confidence gates are applied, and a centralized risk authority validates exposure, drawdown, margin, and correlation before any order is sent. Approved orders flow through a shared execution path with position-lifecycle management (stops, trailing, breakeven, max hold time).

## How a signal becomes an order

```
Strategies --> Signal Pipeline --> Weighted Consensus --> Risk Gate --> Execution --> Position Lifecycle
(indicator / AI)   (configured checks; engine-backed filters are opt-in)
```

Strategies produce votes; configured pipeline checks run, while registry-backed trend, volatility, liquidity,
structure, and regime/cost filters pass through by default when `InpPipelineEngineRegistry=false`. Consensus applies
its configured quorum, the risk gate validates exposure and drawdown, execution places approved orders, and the
lifecycle manager handles stops and exits.

## Quick Start

1. **Install.** Copy the repository into a folder under your MT5 `MQL5/Experts/` directory, keeping the folder structure intact. The EA uses relative includes, so partial copies will fail to compile.
2. **Compile.** Open the EA in MetaEditor and compile it. Confirm there are no errors.
3. **Attach.** Drag the EA onto a chart of a Deriv synthetic index (for example `Crash 1000 Index` M15). The chart symbol is only a host; the universe comes from `InpSymbolsToTrade`.
4. **Set symbols.** `InpSymbolsToTrade` is the exact trading universe. The chart symbol is never injected; include it explicitly if it should trade.
5. **Set risk.** Review the risk inputs (per-trade, daily, and portfolio risk percentages, and the drawdown thresholds) before enabling trading.
6. **Choose a mode.** Set `InpEAMode` to `EA_MODE_INDICATOR_ONLY`, an AI-only mode, or `EA_MODE_HYBRID` (the default).

Enable a feature only after you understand what it does. Defaults are set in the input dialog and in the source files.

## Key Features

- **Weighted voting.** Strategy tiers contribute configured weights. Quorum and confidence settings apply only where their runtime gates are wired; the default minimum is one live voter.
- **Centralized risk authority.** Per-trade, daily, portfolio, correlation, drawdown, and margin checks run before any order is sent.
- **Per-asset-class profiles.** Symbols are classified automatically (Forex, Metals, Indices, Energies, Deriv synthetics), and risk parameters and strategy weights are adjusted per class.
- **AI operating modes.** `INDICATOR_ONLY`, `AI_ONLY`, and `HYBRID` control how human-designed strategies and machine-learned predictions are blended.
- **Python ML bridge.** A ZMQ/HTTP bridge connects to Python-trained CatBoost, XGBoost, and LightGBM models. Trained models can also be exported to ONNX and run natively in MT5.
- **Deriv synthetic support.** Family-specific engines cover spike trading, grid recovery, and ATR-based scalping.
- **Observable decisions.** Structured logs with correlation IDs record why each signal was accepted, filtered, or vetoed.

## Configuration

Settings are exposed as EA inputs in these groups:

| Group | What it controls |
|-------|------------------|
| Risk | Per-trade and daily risk budgets, portfolio exposure, drawdown warning and stop thresholds, minimum lot risk |
| Strategies | Enable flags for each strategy module and strategy weights |
| AI | Operating mode, which AI adapters are active, and the Python bridge mode |
| Live overrides | `Config/live_overrides.json` applies supported risk keys only; unsupported strategy weights, thresholds, symbols, AI, and engine changes are logged but not applied |

Startup risk inputs define the hard operator envelope; risk tiers and compounding can only reduce it. The live override file is a second, risk-only control channel that can tighten this envelope, not raise it above startup inputs. Risk-tier policy is startup-only and requires reinitialization; a `risk.riskTier` override is logged and ignored. Compounding can be toggled live, and unrelated or unchanged file edits preserve the current adaptive/compounding state. Verify effective values in `[RISK-TIER]`, `[COMPOUNDING-TIER]`, `[RISK-OVERRIDE]`, and `[LIVE-CONFIG-RISK]` logs.

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

## Supported Instruments

| Asset class | Examples | Measured status | Notes |
|-------------|----------|-----------------|-------|
| Forex | EURUSD, GBPUSD, USDJPY | **Measured loss, do not use** (-4.6% / -5.6% on two cold windows; sizing levers neutral) | Standard ATR-based stops and targets |
| Metals | XAUUSD, XAGUSD | Untested | Separate volatility parameters |
| Indices | US30, NAS100, SPX500 | Untested | Separate volatility parameters |
| Energies | USOIL, NATGAS | Untested | Separate volatility parameters |
| Deriv synthetics | `Crash 1000 Index`, `Boom 1000 Index` | **Measured best, use these** (+21.1% / +39.3% two cold windows, +66.5% over a month) | Family-specific engines and profiles |

## Python Pipeline

The `Python/` directory contains the ML pipeline: feature engineering, training (CatBoost, XGBoost, LightGBM, stacking), ONNX export to `Resources/`, ZMQ/HTTP prediction bridge, and feature-parity validation between Python and MQL5. Google Colab notebooks are included in `Python/`.

## Standalone Testing EA

`MultiStrategyTestingEA.mq5` isolates individual strategies, AI adapters, and engines for backtesting and optimization without changing the production EA. Select a predefined test profile with `InpCompleteTestProfile`. The EA logs the effective component configuration per symbol.

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

## Documentation Index

| Document | Purpose |
|----------|---------|
| [SYSTEM_STRUCTURE.md](SYSTEM_STRUCTURE.md) | Architecture and component ownership (current runtime structure) |
| [RUNTIME_DECISION_GRAPH.md](RUNTIME_DECISION_GRAPH.md) | How a signal becomes a trade decision (runtime signal-to-execution flow) |
| [SYSTEM_AUDIT_TRACE.md](SYSTEM_AUDIT_TRACE.md) | End-to-end lifecycle and logic traces (OnInit, tick/timer cycle, signal path) |
| [changelogs.md](changelogs.md) | Dated record of changes by batch (Batch 282–300f) |
| [docs/changelogs_batch170-281.md](docs/changelogs_batch170-281.md) | Dated record of changes by batch (Batch 170–281, archived) |
| [docs/changelogs_batch102-169.md](docs/changelogs_batch102-169.md) | Dated record of changes by batch (Batch 102–169, archived) |
| [docs/changelogs_old.md](docs/changelogs_old.md) | Dated record of changes by batch (Batch 101 and earlier, archived) |
| [AGENTS.md](AGENTS.md) | Development workflow rules and runtime invariants |
| [MAINTENANCE_PROTOCOL.md](MAINTENANCE_PROTOCOL.md) | Mandatory update checklist and release gate template |
| [REMAINING_WORK.md](REMAINING_WORK.md) | Open-item backlog and status updates |
| [RUNS_AND_GAINS.md](RUNS_AND_GAINS.md) | Measured backtest record — what was tested, what it moved, conclusions |
| [MQHModelTrainer/README.md](MQHModelTrainer/README.md) | MQL5 model training workflow |
| [Tools/walkforward/README.md](Tools/walkforward/README.md) | Walk-forward validation |
| [Tools/OFFLINE_NN_FINDINGS.md](Tools/OFFLINE_NN_FINDINGS.md) | Offline neural-network training findings |
| [Dashboard/client/README.md](Dashboard/client/README.md) | React/TypeScript dashboard client |

## Requirements

- MetaTrader 5 with MetaEditor (MQL5 compiler)
- Python 3 for the training pipeline and the optional ML bridge (only needed if you use those features)

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for the full text.

Copyright (c) 2026 magmastormy / Axiom Engineering Studio.
