"""
walkforward.py - Rolling in-sample / out-of-sample walk-forward engine.

CORE METHODOLOGY (this is what separates a real WFO from a toy):
  The strategy runs CONTINUOUSLY over the whole history. At each window
  boundary we RE-OPTIMIZE the confidence threshold on the trailing in-sample
  window, but we do NOT reset open positions. Positions carry across the
  IS/OOS boundary exactly as they would live. We then attribute each closed
  trade to IS or OOS by its ENTRY bar and measure OOS performance with the
  threshold that was actually in effect. (Resetting positions at every
  boundary - the naive approach - invents spurious trades and destroys the
  measured edge, which is why it must not be done.)

Headline metrics:
  WFE (Walk-Forward Efficiency) = OOS per-trade expectancy / IS per-trade
        expectancy. ~1.0 = robust; <0.3 = overfit / no edge.
  robustness = fraction of OOS windows (with enough trades) whose own
        per-trade expectancy is positive.
"""

from metrics import summarize, verdict
from simulator import simulate, compute_atr


def make_windows(n, train_bars, test_bars, step=None):
    """Return list of (is_start, is_end, oos_start, oos_end) index tuples."""
    step = step or test_bars
    windows = []
    i = 0
    while i + train_bars + test_bars <= n:
        is_s, is_e = i, i + train_bars
        oos_s, oos_e = i + train_bars, i + train_bars + test_bars
        windows.append((is_s, is_e, oos_s, oos_e))
        i += step
    return windows


def _optimize_threshold(opens, highs, lows, closes, signals, confs, atr,
                        is_s, is_e, sl_atr, tp_atr, cost_bps, max_bars):
    """Grid-search the confidence threshold that maximizes IS net return."""
    best_t = 0.0
    best_net = float("-inf")
    for t in [x / 20.0 for x in range(0, 21)]:
        r, _, _ = simulate(opens, highs, lows, closes,
                           signals[is_s:is_e], confs[is_s:is_e], atr[is_s:is_e],
                           threshold=t, sl_atr=sl_atr, tp_atr=tp_atr,
                           cost_bps=cost_bps, max_bars=max_bars)
        net = sum(r)
        if net > best_net:
            best_net = net
            best_t = t
    return best_t


def simulate_continuous(opens, highs, lows, closes, signals, confs, atr,
                        thresholds, *, sl_atr=1.5, tp_atr=2.0, cost_bps=0.0,
                        max_bars=60, size_base=1.0):
    """
    Single continuous pass. `thresholds[bar]` is the confidence threshold used
    when ENTERING a trade at that bar. Positions are never force-closed at
    window boundaries - the strategy runs live, as it would on a terminal.
    """
    n = len(closes)
    if n == 0:
        return [], [1.0], []
    pos = 0
    entry = 0.0
    entry_bar = -1
    entry_atr = 0.0
    entry_conf = 0.0
    trades = []
    returns = []
    equity = [1.0]
    cost_frac = 2.0 * cost_bps / 10000.0

    for i in range(1, n):
        sig = signals[i - 1] if i - 1 < len(signals) else 0
        conf = confs[i - 1] if i - 1 < len(confs) else 0.0
        a = atr[i] if i < len(atr) else 0.0
        o, h, l, c = opens[i], highs[i], lows[i], closes[i]

        if pos != 0:
            bars_held = i - entry_bar
            stop_hit = tgt_hit = False
            exit_price = None
            if pos > 0:
                sl = entry - sl_atr * entry_atr
                tp = entry + tp_atr * entry_atr
                if l <= sl:
                    stop_hit = True; exit_price = sl
                elif h >= tp:
                    tgt_hit = True; exit_price = tp
            else:
                sl = entry + sl_atr * entry_atr
                tp = entry - tp_atr * entry_atr
                if h >= sl:
                    stop_hit = True; exit_price = sl
                elif l <= tp:
                    tgt_hit = True; exit_price = tp
            thr = thresholds[i] if i < len(thresholds) else 0.0
            if stop_hit or tgt_hit:
                ret = pos * (exit_price - entry) / entry - cost_frac
                returns.append(ret); equity.append(equity[-1] * (1.0 + ret * size_base))
                trades.append({"entry_bar": entry_bar, "exit_bar": i, "dir": pos,
                               "entry": entry, "exit": exit_price, "ret": ret,
                               "reason": "sl" if stop_hit else "tp", "conf": entry_conf})
                pos = 0
            elif sig != 0 and sig != pos and abs(conf) >= thr:
                ret = pos * (o - entry) / entry - cost_frac
                returns.append(ret); equity.append(equity[-1] * (1.0 + ret * size_base))
                trades.append({"entry_bar": entry_bar, "exit_bar": i, "dir": pos,
                               "entry": entry, "exit": o, "ret": ret,
                               "reason": "flip", "conf": entry_conf})
                pos = 0
            elif bars_held >= max_bars:
                ret = pos * (c - entry) / entry - cost_frac
                returns.append(ret); equity.append(equity[-1] * (1.0 + ret * size_base))
                trades.append({"entry_bar": entry_bar, "exit_bar": i, "dir": pos,
                               "entry": entry, "exit": c, "ret": ret,
                               "reason": "maxhold", "conf": entry_conf})
                pos = 0

        if pos == 0 and sig != 0 and abs(conf) >= thresholds[i] if i < len(thresholds) else abs(conf) >= 0.0:
            thr = thresholds[i] if i < len(thresholds) else 0.0
            if abs(conf) >= thr:
                pos = 1 if sig > 0 else -1
                entry = o
                entry_bar = i
                entry_atr = a if a > 0 else (abs(o) * 0.01)
                entry_conf = abs(conf)

    if pos != 0:
        c = closes[-1]
        ret = pos * (c - entry) / entry - cost_frac
        returns.append(ret); equity.append(equity[-1] * (1.0 + ret * size_base))
        trades.append({"entry_bar": entry_bar, "exit_bar": n - 1, "dir": pos,
                       "entry": entry, "exit": c, "ret": ret, "reason": "eod",
                       "conf": entry_conf})
    return returns, equity, trades


def run_walkforward(opens, highs, lows, closes, signals, confs, atr=None,
                   train_bars=252, test_bars=63, step=None,
                   sl_atr=1.5, tp_atr=2.0, cost_bps=0.0, max_bars=60,
                   threshold=None, calibrate=True):
    """
    Run a full walk-forward analysis for ONE strategy signal series.

    Returns a result dict with IS/OOS aggregates, per-window detail, WFE,
    robustness, and a verdict string.
    """
    n = len(closes)
    if atr is None:
        atr = compute_atr(highs, lows, closes, 14)
    windows = make_windows(n, train_bars, test_bars, step)
    if not windows:
        return {"error": "not_enough_data", "n_windows": 0}

    # Build the per-bar threshold schedule (continuous, never resets positions).
    thresholds = [0.0] * n
    window_thresholds = []
    for (is_s, is_e, oos_s, oos_e) in windows:
        if calibrate and threshold is None:
            t = _optimize_threshold(opens, highs, lows, closes, signals, confs,
                                    atr, is_s, is_e, sl_atr, tp_atr, cost_bps,
                                    max_bars)
        else:
            t = 0.0 if threshold is None else threshold
        for b in range(oos_s, min(oos_e, n)):
            thresholds[b] = t
        window_thresholds.append(t)

    returns, _, trades = simulate_continuous(
        opens, highs, lows, closes, signals, confs, atr, thresholds,
        sl_atr=sl_atr, tp_atr=tp_atr, cost_bps=cost_bps, max_bars=max_bars)

    # Attribute trades to IS / OOS by entry bar.
    is_ret, oos_ret = [], []
    oos_trades_by_window = {}
    for (is_s, is_e, oos_s, oos_e) in windows:
        oos_trades_by_window[(is_s, is_e, oos_s, oos_e)] = []
    for t in trades:
        eb = t["entry_bar"]
        placed = False
        for (is_s, is_e, oos_s, oos_e) in windows:
            if is_s <= eb < is_e:
                is_ret.append(t["ret"]); placed = True; break
            if oos_s <= eb < oos_e:
                oos_ret.append(t["ret"])
                oos_trades_by_window[(is_s, is_e, oos_s, oos_e)].append(t["ret"])
                placed = True; break
        if not placed:
            is_ret.append(t["ret"])

    is_m = summarize(is_ret)
    oos_m = summarize(oos_ret)

    is_exp = is_m["expectancy"]
    oos_exp = oos_m["expectancy"]
    wfe = (oos_exp / is_exp) if is_exp != 0 else (1.0 if oos_exp > 0 else 0.0)

    MIN_TRADES_PER_WINDOW = 3
    n_windows = len(windows)
    counted = 0
    n_prof = 0
    per_window = []
    for (is_s, is_e, oos_s, oos_e) in windows:
        wt = oos_trades_by_window[(is_s, is_e, oos_s, oos_e)]
        w_exp = (sum(wt) / len(wt)) if wt else 0.0
        per_window.append({
            "is_start": is_s, "is_end": is_e, "oos_start": oos_s, "oos_end": oos_e,
            "threshold": round(window_thresholds[len(per_window)], 3),
            "oos_n": len(wt), "oos_net": sum(wt), "oos_exp": w_exp,
        })
        if len(wt) >= MIN_TRADES_PER_WINDOW:
            counted += 1
            if w_exp > 0:
                n_prof += 1
    robustness = (n_prof / counted) if counted else 0.0

    v = verdict(is_m, oos_m, wfe, robustness, n_windows)

    return {
        "n_windows": n_windows,
        "is_metrics": is_m,
        "oos_metrics": oos_m,
        "wfe": wfe,
        "robustness": robustness,
        "robustness_windows_counted": counted,
        "oos_window_nets": [sum(v) for v in oos_trades_by_window.values()],
        "per_window": per_window,
        "verdict": v,
    }
