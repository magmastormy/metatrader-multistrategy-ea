# Walk-Forward Validator (Phase 1)

A **cost-aware, look-ahead-safe walk-forward validation engine** that proves whether a
strategy edge is *real* (OOS beats IS, stable across windows) **before** it ever ships
live to the EA. This is the single highest-leverage gap the research flagged: the repo
had no walk-forward discipline, so every "strategy" was unproven.

The harness exists in two forms that implement the **same methodology**:

- `run_wfo.py` (Python) — the workhorse. Runs on any machine, reuses the
  `TrainingDataExporter.mq5` CSV feed, verifiable offline. **This is what you run
  to gate a new edge.**
- `WalkForwardTesterEA.mq5` + `Core/Validation/WalkForwardValidator.mqh` (MQL5) —
  validates directly inside MT5 against the live broker's real history (true spread,
  true session gaps) without exporting data.

## Why this matters (the research thesis)

Retail EAs bleed because they are tuned on in-sample data and fall apart out-of-sample.
A genuine edge must satisfy **all** of:

1. **OOS net profit > 0** with **profit factor ≥ 1.10** — it makes money on data it
   never saw during optimization.
2. **Walk-Forward Efficiency (WFE) ≥ 0.50** — `expectancy_OOS / expectancy_IS`. If the
   live edge is a fraction of the backtest edge, the backtest was lying.
3. **Robustness ≥ 0.60** — fraction of OOS windows that were individually profitable.
   One lucky window is not a strategy.
4. **OOS max drawdown ≤ 35%** — survivable.

Anything else is `REJECTED` (noise / overfit) or `CONDITIONAL` (borderline — trade only
with reduced risk).

## Python usage

```bash
# Generate a synthetic but realistic multi-regime dataset (4 signals: one real
# edge, one mean-revert edge, one pure noise, one overfit/anti-edge):
python sample_data.py            # -> sample_wfo.csv

# Validate every signal column in the CSV:
python run_wfo.py --input sample_wfo.csv --cost 1.5 --json wfo_report.json
```

`--cost` is the round-trip cost in **basis points** (spread + commission + slippage).
Use realistic numbers:
- DERIV Vol 75/100: ~1.5–3.0 bps round-trip
- DERIV Crash/Boom: ~5–10 bps (wide fixed spread)
- Forex majors London/NY: ~1.0–2.0 bps
- Forex exotics / Weltrade SyntX: ~3–8 bps

### Feeding REAL data

Export from MT5 with `TrainingDataExporter.mq5` (writes `symbol,time,open,high,low,
close,spread,atr,<Strategy>_signal,<Strategy>_confidence,...`). `dataio.load_ohlc_signals`
parses the `<Strategy>_signal` / `<Strategy>_confidence` columns automatically. A plain
OHLCV CSV (no signal columns) works too — pair it with your own strategy signal generator.

## Methodology notes (so the gate is honest)

- **Continuous simulation across window boundaries.** The WFO re-optimizes the entry
  threshold on each in-sample (IS) window, but the trade simulation runs **continuously**
  across IS→OOS boundaries — positions are NOT reset at each boundary. Resetting positions
  at boundaries was found to *invent* bad trades (a known WFO artifact) and was removed.
- **Entry at `open[i+1]`** (next-bar open), never at the signal bar close, so no
  look-ahead.
- **ATR-based stops**: SL = `sl_atr × ATR`, TP = `tp_atr × ATR` (default 1.5 / 2.0 →
  1.33 R:R). One open position per signal direction; flat between trades (cooldown).
- **Cost applied per round-turn trade.**
- **Look-ahead-safe label generation** in `sample_data.py` builds prices first, then
  derives TP/SL labels from the complete series.

## Files

| File | Purpose |
|------|---------|
| `metrics.py` | expectancy, profit factor, drawdown, WFE, robustness, `verdict()` |
| `simulator.py` | cost-aware, look-ahead-safe trade simulator (ATR SL/TP) |
| `walkforward.py` | rolling IS/OOS windowing + per-window threshold optimization |
| `dataio.py` | load `TrainingDataExporter` CSV + plain OHLCV |
| `sample_data.py` | realistic multi-regime synthetic generator (4 reference signals) |
| `run_wfo.py` | CLI entry point |
| `WalkForwardValidator.mqh` | MQL5 port of the same math (in-terminal) |
| `WalkForwardTesterEA.mq5` | MQL5 self-contained tester against broker history |

Pure standard library — runs on any Python 3.8+. No pip install required.
