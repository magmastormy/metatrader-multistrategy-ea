"""
run_wfo.py - Command-line walk-forward validator for the real EA strategies.

Usage:
  python run_wfo.py --input sample_wfo.csv
  python run_wfo.py --input AITraining_Enterprise_H1.csv --exporter
  python run_wfo.py --input AITraining_Enterprise_H1.csv --exporter --symbols EURUSD,XAUUSD
  python run_wfo.py --input sample_wfo.csv --train 252 --test 63 --cost 1.5

Flags:
  --exporter    Treat input as a TrainingDataExporter.mq5 CSV. It auto-detects
                the *_signal / *_confidence columns (the REAL strategies your EA
                runs) and derives ATR from OHLC. When the CSV carries a `symbol`
                column it is split PER SYMBOL and each symbol is walk-forwarded
                INDEPENDENTLY with its own spread-based round-turn cost. This is
                mandatory: a single continuous WFO over the concatenation would
                simulate trades ACROSS symbol boundaries (buy EURUSD close ->
                sell GBPUSD open), which is nonsense.
  --symbols LST Comma-separated symbol filter (exporter multi-symbol only).
                Use it to smoke-test a couple of symbols before the full run.
  --cost BPS    PER-SIDE cost in bps (round-turn = 2x). In --exporter mode with a
                `spread` column the cost is ESTIMATED per symbol and --cost is
                ignored unless explicitly passed (then applied flat to all).
  --train/--test/--step  window sizing in bars (H1 by default).
  --json OUT    write a machine-readable verdict report (nested by symbol).

VERDICT GATES (metrics.verdict): a strategy is only safe to ship live if it is
APPROVED. REJECTED/CONDITIONAL mean no validated edge.
"""

import argparse
import csv as _csv
import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))

from dataio import (load_ohlc_signals, load_exporter_csv,
                    load_exporter_csv_by_symbol, estimate_cost_bps)
from walkforward import run_walkforward


def fmt(x, d=4):
    if isinstance(x, float):
        if x == float("inf"):
            return "inf"
        if x == float("-inf"):
            return "-inf"
        return f"{x:.{d}f}"
    return str(x)


def _detect_symbol_column(path):
    with open(path, "r", newline="") as f:
        hdr = next(_csv.reader(f), [])
    return "symbol" in [h.strip().lower() for h in hdr]


def run_single_symbol(sym, data, cost_bps, train_bars, test_bars, step,
                      sl_atr, tp_atr, max_bars):
    """Walk-forward every real strategy in `data` for ONE symbol.

    Returns {strategy_name: result_dict}. `cost_bps` is PER-SIDE (the simulator
    internally doubles it to round-turn).
    """
    opens = data["opens"]; highs = data["highs"]; lows = data["lows"]
    closes = data["closes"]; atr = data["atr"]
    strats = data["strategies"]

    print("\n" + "-" * 92)
    print(f"SYMBOL {sym}  | bars={len(closes)} cost(per-side)={fmt(cost_bps, 3)}bps "
          f"(round-turn {fmt(2.0 * cost_bps, 3)}bps)")
    print("-" * 92)

    results = {}
    for name, (signals, confs) in strats.items():
        if len(signals) != len(closes):
            # align length (defensive; exporter rows are uniform per symbol)
            signals = (signals + [0] * len(closes))[:len(closes)]
            confs = (confs + [0.0] * len(closes))[:len(closes)]
        res = run_walkforward(opens, highs, lows, closes, signals, confs, atr,
                             train_bars=train_bars, test_bars=test_bars,
                             step=step, sl_atr=sl_atr, tp_atr=tp_atr,
                             cost_bps=cost_bps, max_bars=max_bars)
        if "error" in res:
            print(f"  [{name}] SKIPPED: {res['error']}")
            continue
        ism = res["is_metrics"]; osm = res["oos_metrics"]
        print(f"  {name:<12} -> {res['verdict']:<14} WFE={fmt(res['wfe'])} "
              f"rob={fmt(res['robustness'], 3)} | IS n={ism['n_trades']:>5} "
              f"net={fmt(ism['net_return'])} | OOS n={osm['n_trades']:>5} "
              f"net={fmt(osm['net_return'])} PF={fmt(osm['profit_factor'])} "
              f"WR={fmt(osm['win_rate'], 3)} maxDD={fmt(osm['max_dd_pct'], 3)}")
        results[name] = {
            "verdict": res["verdict"],
            "n_windows": res["n_windows"],
            "wfe": res["wfe"],
            "robustness": res["robustness"],
            "is": ism,
            "oos": osm,
            "oos_window_nets": [round(x, 6) for x in res["oos_window_nets"]],
        }
    return results


def run(input_path, exporter, cost_bps, train_bars, test_bars, step, sl_atr,
        tp_atr, max_bars, out_json, symbols_filter):

    all_results = {}   # sym -> {"cost_per_side": float, "strategies": {name: res}}
    symbol_cost = {}

    if exporter:
        multi = _detect_symbol_column(input_path)
        if multi:
            by_symbol = load_exporter_csv_by_symbol(input_path)
            if symbols_filter:
                keep = set(s.strip().upper() for s in symbols_filter.split(","))
                by_symbol = {s: d for s, d in by_symbol.items() if s.upper() in keep}
            print(f"EXPORTER MULTI-SYMBOL: {len(by_symbol)} symbol(s) loaded "
                  f"from {os.path.basename(input_path)}")
            for sym, sdata in by_symbol.items():
                rt = estimate_cost_bps(sdata["spread"], sdata["closes"])
                c = cost_bps if cost_bps is not None else (rt / 2.0)
                symbol_cost[sym] = c
                all_results[sym] = {
                    "cost_per_side": c,
                    "strategies": run_single_symbol(
                        sym, sdata, c, train_bars, test_bars, step,
                        sl_atr, tp_atr, max_bars),
                }
        else:
            data = load_exporter_csv(input_path)
            c = cost_bps if cost_bps is not None else (
                estimate_cost_bps(data["spread"], data["closes"]) / 2.0)
            sym = os.path.splitext(os.path.basename(input_path))[0]
            symbol_cost[sym] = c
            all_results[sym] = {
                "cost_per_side": c,
                "strategies": run_single_symbol(
                    sym, data, c, train_bars, test_bars, step,
                    sl_atr, tp_atr, max_bars),
            }
    else:
        data = load_ohlc_signals(input_path)
        c = cost_bps if cost_bps is not None else 1.5
        sym = os.path.splitext(os.path.basename(input_path))[0]
        symbol_cost[sym] = c
        all_results[sym] = {
            "cost_per_side": c,
            "strategies": run_single_symbol(
                sym, data, c, train_bars, test_bars, step,
                sl_atr, tp_atr, max_bars),
        }

    # ---- Combined ranking across all symbols/strategies ----
    flat = []
    for sym, blob in all_results.items():
        for name, r in blob["strategies"].items():
            flat.append((sym, name, r))
    ranked = sorted(flat, key=lambda t: t[2]["oos"]["net_return"], reverse=True)

    print("\n" + "=" * 92)
    print("COMBINED RANKING (by OOS net return):")
    for sym, name, r in ranked:
        print(f"  {sym:<16} {name:<12} {r['verdict']:<14} "
              f"OOSnet={fmt(r['oos']['net_return'])} WFE={fmt(r['wfe'])} "
              f"rob={fmt(r['robustness'], 3)}")
    print("=" * 92)

    # ---- JSON (nested by symbol) ----
    if out_json:
        with open(out_json, "w") as f:
            json.dump(all_results, f, indent=2, default=str)
        print(f"wrote {out_json}")
        out_csv = os.path.splitext(out_json)[0] + ".csv"
        with open(out_csv, "w", newline="") as cf:
            w = _csv.writer(cf)
            w.writerow(["Symbol", "Strategy", "Verdict", "Windows", "WFE",
                        "Robustness", "IS_net", "OOS_net", "OOS_PF", "OOS_WR",
                        "OOS_maxDD", "Cost_bps_roundturn"])
            for sym, blob in all_results.items():
                c = blob["cost_per_side"]
                rt_cost = 2.0 * c
                for name, r in blob["strategies"].items():
                    o = r["oos"]; i = r["is"]
                    w.writerow([sym, name, r["verdict"], r["n_windows"],
                                f'{r["wfe"]:.3f}', f'{r["robustness"]:.3f}',
                                f'{i["net_return"]:.4f}', f'{o["net_return"]:.4f}',
                                f'{o["profit_factor"]:.3f}', f'{o["win_rate"]:.3f}',
                                f'{o["max_dd_pct"]:.3f}', f'{rt_cost:.3f}'])
        print(f"wrote {out_csv}")
    return all_results


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", default="sample_wfo.csv")
    ap.add_argument("--exporter", action="store_true")
    ap.add_argument("--symbols", default=None,
                    help="comma-separated symbol filter (exporter multi-symbol)")
    ap.add_argument("--cost", type=float, default=None,
                    help="per-side cost bps; default auto-estimate in exporter mode")
    ap.add_argument("--train", type=int, default=252)
    ap.add_argument("--test", type=int, default=126)
    ap.add_argument("--step", type=int, default=None)
    ap.add_argument("--sl", type=float, default=1.5)
    ap.add_argument("--tp", type=float, default=2.0)
    ap.add_argument("--maxbars", type=int, default=60)
    ap.add_argument("--json", default="wfo_report.json")
    args = ap.parse_args()

    here = os.path.dirname(os.path.abspath(__file__))
    inp = args.input if os.path.isabs(args.input) else os.path.join(here, args.input)
    out = args.json if os.path.isabs(args.json) else os.path.join(here, args.json)
    run(inp, args.exporter, args.cost, args.train, args.test, args.step,
        args.sl, args.tp, args.maxbars, out, args.symbols)
