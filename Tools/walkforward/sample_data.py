"""
sample_data.py - Generate a realistic synthetic OHLCV + signals dataset.

Purpose: prove the walk-forward gate works WITHOUT needing a live MT5 terminal.

The price path switches between TREND / RANGE / VOL regimes (so different
strategy archetypes would behave differently in real markets). Three signal
series are embedded with deliberately different edge quality:

  Momentum  : a REAL edge - emits the trade direction that would actually hit
              its ATR take-profit before its stop (forward-checked) during
              trending/volatile regimes. Should be APPROVED.
  MeanRev   : a REAL edge - same forward-checked signal during range/trend
              regimes. Should be APPROVED.
  Random    : NO edge at all (pure noise +/-1). Should be REJECTED.
  Overfit   : REAL edge in the first 60% of history, pure noise after. Its
              in-sample looks great but out-of-sample collapses -> low WFE ->
              should be REJECTED.

Swap this file for a real TrainingDataExporter.mq5 CSV and re-run run_wfo.py to
validate your ACTUAL EA signals.
"""

import csv
import math
import random

N_BARS = 13000
START_PRICE = 1.0000
SL_ATR = 1.5
TP_ATR = 2.0
MAX_BARS = 30
ATR_PERIOD = 14


def fwd_signal(opens, closes, atrs, i):
    """Return +1 if +TP is hit before -SL within MAX_BARS, -1 if -SL first, 0 if neither.

    Uses the SIMULATOR's actual entry (open of the next bar) and that bar's ATR,
    so the embedded edge survives the cost-aware simulator exactly.
    """
    if i + 1 >= len(closes):
        return 0
    entry = opens[i + 1]
    a = atrs[i + 1]
    if a <= 0:
        return 0
    tp = TP_ATR * a
    sl = SL_ATR * a
    end = min(i + 1 + MAX_BARS, len(closes))
    for j in range(i + 1, end):
        if closes[j] >= entry + tp:
            return 1
        if closes[j] <= entry - sl:
            return -1
    return 0


def generate(path, seed=42):
    rng = random.Random(seed)
    opens, highs, lows, closes, spreads, atrs = [], [], [], [], [], []
    mom_s, mom_c = [], []
    mr_s, mr_c = [], []
    rnd_s, rnd_c = [], []
    ovr_s, ovr_c = [], []

    price = START_PRICE
    center = price
    regimes = ["TREND", "RANGE", "VOL", "TREND", "RANGE", "VOL"]
    regime = "TREND"
    regime_bars_left = 0
    tr_hist = []
    regime_of = []  # store regime per bar for the signal pass

    for i in range(N_BARS):
        if regime_bars_left <= 0:
            regime = regimes[rng.randrange(len(regimes))]
            regime_bars_left = rng.randint(900, 1700)
        regime_bars_left -= 1
        regime_of.append(regime)

        if regime == "TREND":
            drift = rng.uniform(-0.0006, 0.0010)
            vol = 0.0010
        elif regime == "RANGE":
            # genuinely mean-reverting: price is pulled back toward a slowly
            # drifting center, so buying below / selling above the mean has edge.
            center += rng.gauss(0, 0.0003)
            drift = (center - price) * 0.08
            vol = 0.0006
        else:  # VOL
            drift = rng.uniform(-0.0004, 0.0004)
            vol = 0.0024

        o = price
        c = o * (1.0 + drift + rng.gauss(0, vol))
        hi = max(o, c) * (1.0 + abs(rng.gauss(0, vol * 0.6)))
        lo = min(o, c) * (1.0 - abs(rng.gauss(0, vol * 0.6)))
        spread = 0.00015

        opens.append(o); highs.append(hi); lows.append(lo); closes.append(c)
        spreads.append(spread)
        tr = max(hi - lo, abs(hi - o), abs(lo - o))
        tr_hist.append(tr)
        if len(tr_hist) > ATR_PERIOD:
            tr_hist.pop(0)
        atrs.append(sum(tr_hist) / len(tr_hist) if tr_hist else vol)
        price = c

    # ---- Signal pass: needs the FULL price series to forward-check TP/SL ----
    # Build raw signal candidates, then enforce a trade cooldown so a real
    # systematic strategy does not reverse on every opposite tick (which would
    # whipsaw the embedded edge). Cooldown = trade horizon.
    def apply_cooldown(raw, cooldown=MAX_BARS):
        out = [0] * len(raw)
        last = -10 ** 9
        for i, s in enumerate(raw):
            if s != 0 and (i - last) > cooldown:
                out[i] = s
                last = i
        return out

    raw_mom, raw_mr, raw_ovr = [], [], []
    for i in range(N_BARS):
        fsig = fwd_signal(opens, closes, atrs, i)
        early = i < int(N_BARS * 0.6)
        regime = regime_of[i]

        # Momentum: real edge in trending / volatile regimes
        if regime in ("TREND", "VOL") and fsig != 0:
            raw_mom.append(fsig)
        else:
            raw_mom.append(0)

        # MeanRev: real edge in range / trend regimes
        if regime in ("RANGE", "TREND") and fsig != 0:
            raw_mr.append(fsig)
        else:
            raw_mr.append(0)

        # Overfit: real edge early, ANTI-edge late (the learned pattern breaks
        # and the strategy now trades the wrong direction) - should collapse OOS.
        if early and fsig != 0:
            raw_ovr.append(fsig)
        elif (not early) and fsig != 0:
            raw_ovr.append(-fsig)
        else:
            raw_ovr.append(0)

    mom_s = apply_cooldown(raw_mom)
    mr_s = apply_cooldown(raw_mr)
    ovr_s = apply_cooldown(raw_ovr)

    for i in range(N_BARS):
        mom_c.append(round(rng.uniform(0.65, 0.9), 3) if mom_s[i] != 0 else 0.0)
        mr_c.append(round(rng.uniform(0.6, 0.85), 3) if mr_s[i] != 0 else 0.0)
        ovr_c.append(round(rng.uniform(0.7, 0.95), 3) if ovr_s[i] != 0 else 0.0)

        # Random: no edge
        if rng.random() < 0.5:
            rnd_s.append(1 if rng.random() < 0.5 else -1)
            rnd_c.append(round(rng.uniform(0.3, 0.7), 3))
        else:
            rnd_s.append(0); rnd_c.append(0.0)

    with open(path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["time", "open", "high", "low", "close", "spread", "atr",
                    "Momentum_signal", "Momentum_confidence",
                    "MeanRev_signal", "MeanRev_confidence",
                    "Random_signal", "Random_confidence",
                    "Overfit_signal", "Overfit_confidence"])
        t0 = 1700000000
        for i in range(N_BARS):
            w.writerow([
                t0 + i * 3600,
                f"{opens[i]:.5f}", f"{highs[i]:.5f}", f"{lows[i]:.5f}",
                f"{closes[i]:.5f}", f"{spreads[i]:.5f}", f"{atrs[i]:.5f}",
                mom_s[i], mom_c[i], mr_s[i], mr_c[i],
                rnd_s[i], rnd_c[i], ovr_s[i], ovr_c[i],
            ])
    return path


if __name__ == "__main__":
    import os
    out = os.path.join(os.path.dirname(__file__), "sample_wfo.csv")
    generate(out)
    print("wrote", out)
