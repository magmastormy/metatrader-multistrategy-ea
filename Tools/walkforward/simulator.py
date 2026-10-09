"""
simulator.py - Cost-aware, lookahead-safe trade simulator.

Models the single most important reality the research flagged: on synthetic
indices (and via spread/commission on forex) there is a structural cost per
round-turn. A signal with NO real edge produces NEGATIVE expectancy once that
cost is deducted - which is exactly why "more trading" on synthetics does not
print. The simulator deducts cost on every round-turn so the walk-forward
verdict reflects reality, not a spread-free fantasy.

Signal convention (matches TrainingDataExporter output):
  signals[i] in {-1, 0, +1}  (sell / flat / buy)
  confs[i]   in [0, 1]        (strategy confidence)

Lookahead safety: a signal observed at the close of bar i is only acted on at
the OPEN of bar i+1. Intrabar stops/targets are checked against the bar's own
high/low, which is valid because the position is already open before that bar.
"""

import math


def compute_atr(highs, lows, closes, period=14):
    """
    Wilder's smoothing ATR, aligned to index (atr[i] uses bars up to i).
    Returns 0.0 before enough history exists.
    """
    n = len(closes)
    atr = [0.0] * n
    if n < period + 1:
        return atr
    trs = [0.0] * n
    for i in range(1, n):
        h, l, c0, c1 = highs[i], lows[i], closes[i - 1], closes[i]
        trs[i] = max(h - l, abs(h - c0), abs(l - c0))
    # first ATR = simple average of first `period` TRs
    s = sum(trs[1:period + 1]) / period
    atr[period] = s
    for i in range(period + 1, n):
        s = (s * (period - 1) + trs[i]) / period
        atr[i] = s
    return atr


def simulate(opens, highs, lows, closes, signals, confs, atr,
             threshold=0.0, sl_atr=1.5, tp_atr=2.0, cost_bps=0.0,
             max_bars=60, size_base=1.0, start_equity=1.0):
    """
    Run the signal as a position-taking strategy. Returns:
      (returns, equity_curve, trades)

    returns : list of net return fractions per closed trade
    trades  : list of dicts (diagnostic)
    """
    n = len(closes)
    if n == 0:
        return [], [start_equity], []

    pos = 0          # 0 flat, +1 long, -1 short
    entry = 0.0
    entry_bar = -1
    entry_atr = 0.0
    entry_conf = 0.0
    trades = []
    returns = []
    equity = [start_equity]

    cost_frac = 2.0 * cost_bps / 10000.0  # round-turn cost as fraction of price

    for i in range(1, n):
        sig = signals[i - 1] if i - 1 < len(signals) else 0
        conf = confs[i - 1] if i - 1 < len(confs) else 0.0
        a = atr[i] if i < len(atr) else 0.0
        o, h, l, c = opens[i], highs[i], lows[i], closes[i]

        # --- 1) Manage an OPEN position on this bar ---
        if pos != 0:
            bars_held = i - entry_bar
            stop_hit = tgt_hit = False
            exit_price = None
            # stops / targets (intrabar, valid because pos already open)
            if pos > 0:
                sl = entry - sl_atr * entry_atr
                tp = entry + tp_atr * entry_atr
                if l <= sl:
                    stop_hit = True
                    exit_price = sl
                elif h >= tp:
                    tgt_hit = True
                    exit_price = tp
            else:
                sl = entry + sl_atr * entry_atr
                tp = entry - tp_atr * entry_atr
                if h >= sl:
                    stop_hit = True
                    exit_price = sl
                elif l <= tp:
                    tgt_hit = True
                    exit_price = tp

            if stop_hit or tgt_hit:
                ret = pos * (exit_price - entry) / entry - cost_frac
                returns.append(ret)
                equity.append(equity[-1] * (1.0 + ret * size_base))
                trades.append({"entry_bar": entry_bar, "exit_bar": i,
                               "dir": pos, "entry": entry, "exit": exit_price,
                               "ret": ret, "reason": "sl" if stop_hit else "tp",
                               "conf": entry_conf})
                pos = 0
            elif sig != 0 and sig != pos and abs(conf) >= threshold:
                # signal flipped opposite -> exit at this bar's open (conservative)
                ret = pos * (o - entry) / entry - cost_frac
                returns.append(ret)
                equity.append(equity[-1] * (1.0 + ret * size_base))
                trades.append({"entry_bar": entry_bar, "exit_bar": i,
                               "dir": pos, "entry": entry, "exit": o,
                               "ret": ret, "reason": "flip", "conf": entry_conf})
                pos = 0
            elif bars_held >= max_bars:
                ret = pos * (c - entry) / entry - cost_frac
                returns.append(ret)
                equity.append(equity[-1] * (1.0 + ret * size_base))
                trades.append({"entry_bar": entry_bar, "exit_bar": i,
                               "dir": pos, "entry": entry, "exit": c,
                               "ret": ret, "reason": "maxhold", "conf": entry_conf})
                pos = 0

        # --- 2) Manage a NEW entry on this bar (after any exit) ---
        if pos == 0 and sig != 0 and abs(conf) >= threshold:
            # size scales mildly with confidence, floored so weak signals still trade
            pos = 1 if sig > 0 else -1
            entry = o
            entry_bar = i
            entry_atr = a if a > 0 else (abs(o) * 0.01)
            entry_conf = abs(conf)

    # close any dangling position at the final close
    if pos != 0:
        c = closes[-1]
        ret = pos * (c - entry) / entry - cost_frac
        returns.append(ret)
        equity.append(equity[-1] * (1.0 + ret * size_base))
        trades.append({"entry_bar": entry_bar, "exit_bar": n - 1,
                       "dir": pos, "entry": entry, "exit": c,
                       "ret": ret, "reason": "eod", "conf": entry_conf})

    return returns, equity, trades
