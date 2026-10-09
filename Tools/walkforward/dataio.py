"""
dataio.py - Load price + signal data for the walk-forward engine.

Two input shapes are supported:

1) Plain OHLCV + signal columns (what sample_data.py produces):
       time,open,high,low,close,spread,atr,
       <Name>_signal,<Name>_confidence, ...

   `load_ohlc_signals` returns: a dict with 'opens/highs/lows/closes/spread/atr'
   (parallel lists) and 'strategies' -> {name: (signal_list, conf_list)}. The
   time column is optional.

2) The full TrainingDataExporter.mq5 CSV (many feature/regime columns + one
   *_signal / *_confidence pair per exported strategy). `load_exporter_csv`
   auto-detects the signal/confidence columns by suffix and derives OHLCV from
   the canonical columns, computing ATR from OHLC if not present. This lets you
   run the EXACT signals your live EA produced against history - the real gate.

All prices are parsed as float; signal as int; confidence as float.
"""

import csv


def _to_float(x):
    try:
        return float(x)
    except (ValueError, TypeError):
        return 0.0


def _to_int(x):
    try:
        return int(float(x))
    except (ValueError, TypeError):
        return 0


def load_ohlc_signals(path):
    """Load a plain OHLCV + *_signal/*_confidence CSV."""
    opens, highs, lows, closes, spread, atr = [], [], [], [], [], []
    strat = {}  # name -> [signal_list, conf_list]
    with open(path, "r", newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            opens.append(_to_float(row.get("open")))
            highs.append(_to_float(row.get("high")))
            lows.append(_to_float(row.get("low")))
            closes.append(_to_float(row.get("close")))
            spread.append(_to_float(row.get("spread", 0.0)))
            atr.append(_to_float(row.get("atr", 0.0)))
            for k, v in row.items():
                if k.endswith("_signal"):
                    name = k[: -len("_signal")]
                    if name not in strat:
                        strat[name] = [[], []]
                    strat[name][0].append(_to_int(v))
                elif k.endswith("_confidence"):
                    name = k[: -len("_confidence")]
                    if name not in strat:
                        strat[name] = [[], []]
                    strat[name][1].append(_to_float(v))
    return {
        "opens": opens, "highs": highs, "lows": lows,
        "closes": closes, "spread": spread, "atr": atr,
        "strategies": strat,
    }


def load_exporter_csv(path):
    """
    Load a TrainingDataExporter.mq5 CSV. Derives OHLCV from canonical columns and
    extracts every *_signal / *_confidence column pair as a strategy. ATR is
    computed from OHLC when absent.
    """
    opens, highs, lows, closes, spread = [], [], [], [], []
    strat = {}
    ohlc_present = True
    with open(path, "r", newline="") as f:
        reader = csv.DictReader(f)
        fields = reader.fieldnames or []
        # detect ATR column if present
        atr_col = next((c for c in fields if c.lower().startswith("atr")), None)
        for row in reader:
            if not all(k in row for k in ("open", "high", "low", "close")):
                ohlc_present = False
                break
            opens.append(_to_float(row["open"]))
            highs.append(_to_float(row["high"]))
            lows.append(_to_float(row["low"]))
            closes.append(_to_float(row["close"]))
            spread.append(_to_float(row.get("spread", 0.0)))
            for k, v in row.items():
                if k.endswith("_signal"):
                    name = k[: -len("_signal")]
                    strat.setdefault(name, [[], []])
                    strat[name][0].append(_to_int(v))
                elif k.endswith("_confidence"):
                    name = k[: -len("_confidence")]
                    strat.setdefault(name, [[], []])
                    strat[name][1].append(_to_float(v))
    if not ohlc_present:
        raise ValueError("Exporter CSV missing OHLC columns; expected open/high/low/close")
    atr = []
    if atr_col:
        with open(path, "r", newline="") as f:
            reader = csv.DictReader(f)
            for row in reader:
                atr.append(_to_float(row.get(atr_col, 0.0)))
    else:
        from simulator import compute_atr
        atr = compute_atr(highs, lows, closes, 14)
    return {
        "opens": opens, "highs": highs, "lows": lows,
        "closes": closes, "spread": spread, "atr": atr,
        "strategies": strat,
    }


def load_exporter_csv_by_symbol(path):
    """
    Load a multi-symbol TrainingDataExporter.mq5 CSV and split it into one
    data dict PER SYMBOL (grouped by the `symbol` column). This is required
    because the exporter concatenates all symbols into one file; running a
    single continuous walk-forward over the concatenation would simulate
    trades ACROSS symbol boundaries (buy EURUSD close -> sell GBPUSD open),
    which is nonsense. Returns {symbol: <same dict as load_exporter_csv>}.
    """
    from simulator import compute_atr

    groups = {}  # sym -> raw accumulators
    atr_col = None
    with open(path, "r", newline="") as f:
        reader = csv.DictReader(f)
        fields = reader.fieldnames or []
        atr_col = next((c for c in fields if c.lower().startswith("atr")), None)
        for row in reader:
            sym = (row.get("symbol") or "").strip()
            if sym == "":
                continue
            g = groups.setdefault(sym, {
                "opens": [], "highs": [], "lows": [], "closes": [],
                "spread": [], "atr": [], "strat": {},
            })
            g["opens"].append(_to_float(row.get("open")))
            g["highs"].append(_to_float(row.get("high")))
            g["lows"].append(_to_float(row.get("low")))
            g["closes"].append(_to_float(row.get("close")))
            g["spread"].append(_to_float(row.get("spread", 0.0)))
            if atr_col:
                g["atr"].append(_to_float(row.get(atr_col, 0.0)))
            for k, v in row.items():
                if k.endswith("_signal"):
                    name = k[: -len("_signal")]
                    g["strat"].setdefault(name, [[], []])
                    g["strat"][name][0].append(_to_int(v))
                elif k.endswith("_confidence"):
                    name = k[: -len("_confidence")]
                    g["strat"].setdefault(name, [[], []])
                    g["strat"][name][1].append(_to_float(v))

    out = {}
    for sym, g in groups.items():
        atr = g["atr"] if atr_col else compute_atr(g["highs"], g["lows"], g["closes"], 14)
        out[sym] = {
            "opens": g["opens"], "highs": g["highs"], "lows": g["lows"],
            "closes": g["closes"], "spread": g["spread"], "atr": atr,
            "strategies": g["strat"],
        }
    return out


def estimate_cost_bps(spread_list, close_list):
    """
    Estimate round-turn cost in basis points from a symbol's per-bar spread
    (in points) and close prices, mirroring the MQL5 tester's
    `SYMBOL_SPREAD * SYMBOL_POINT * 2 / bid` formula. Point size is inferred
    from the decimal precision of the close price (no external symbol table
    needed). Returns a round-turn bps value.
    """
    if not close_list:
        return 1.5
    s = repr(close_list[0])
    dec = len(s.split(".")[1]) if "." in s else 0
    point = 10.0 ** (-dec)
    m_spread = sum(spread_list) / len(spread_list)
    m_close = sum(close_list) / len(close_list)
    if m_close <= 0:
        return 1.5
    return m_spread * point * 2.0 / m_close * 1e4
