#!/usr/bin/env python
"""
Label-geometry test.

The exporter's label (`ComputeTripleBarrierLabel`, TrainingDataExporter.mq5:367-388) uses
a barrier of only 0.5 ATR over 5/10/20 bars. Measured on the shipped dataset, a boosted
tree beats the majority baseline by 0.09 percentage points at every horizon - i.e. the
target is noise. This script asks the next question: is the problem the features, or is
it the barrier width?

It recomputes triple-barrier labels from the dataset's own OHLC columns at several
(ATR multiple, horizon) combinations and measures learnability the same way. If wider
barriers become predictable while 0.5 ATR does not, then the AI arm was trained on an
unlearnable target and the fix is label geometry - not a bigger network.

Output is a table: geometry -> test accuracy, baseline, edge, and directional precision.
"""

from __future__ import annotations

import argparse
import csv
from collections import defaultdict

import numpy as np
from sklearn.ensemble import HistGradientBoostingClassifier

FEATURE_VECTOR_SIZE = 70
ATR_PERIOD = 14


def load_ohlc_features(path, symbol):
    with open(path, newline="", encoding="utf-8-sig") as handle:
        reader = csv.reader(handle)
        header = next(reader)
        idx = {n: i for i, n in enumerate(header)}
        feats = [idx[f"feature_{i:02d}"] for i in range(FEATURE_VECTOR_SIZE)]
        c_open, c_high, c_low, c_close = (idx["open"], idx["high"], idx["low"], idx["close"])
        sym_i = idx["symbol"]
        x, o, h, l, c = [], [], [], [], []
        for row in reader:
            if row[sym_i] != symbol:
                continue
            try:
                x.append([float(row[i]) for i in feats])
                o.append(float(row[c_open])); h.append(float(row[c_high]))
                l.append(float(row[c_low])); c.append(float(row[c_close]))
            except ValueError:
                continue
    return (np.asarray(x, np.float64), np.asarray(o), np.asarray(h),
            np.asarray(l), np.asarray(c))


def atr(high, low, close, period=ATR_PERIOD):
    prev_close = np.concatenate(([close[0]], close[:-1]))
    tr = np.maximum(high - low, np.maximum(np.abs(high - prev_close), np.abs(low - prev_close)))
    out = np.full(len(close), np.nan)
    if len(tr) >= period:
        cs = np.cumsum(np.insert(tr, 0, 0.0))
        out[period:] = (cs[period + 1:] - cs[1:len(tr) - period + 1]) / period
    return out


def barrier_labels(high, low, close, atr_vals, multiplier, horizon):
    n = len(close)
    labels = np.zeros(n, np.int64)
    for t in range(n - horizon):
        a = atr_vals[t]
        if not np.isfinite(a) or a <= 0:
            labels[t] = 0
            continue
        up = close[t] + a * multiplier
        dn = close[t] - a * multiplier
        label = 0
        for j in range(t + 1, t + horizon + 1):
            if high[j] >= up:
                label = 1
                break
            if low[j] <= dn:
                label = -1
                break
        labels[t] = label
    return labels


def evaluate(x, labels, drop_hold=True):
    mask = np.isfinite(labels) & (labels != 0) if drop_hold else np.ones(len(labels), bool)
    x, labels = x[mask], labels[mask]
    n = len(labels)
    if n < 500:
        return None
    cut = int(n * 0.7)
    xtr, xte = x[:cut], x[cut:]
    ytr, yte = labels[:cut], labels[cut:]
    mean, std = xtr.mean(0), xtr.std(0) + 1e-9
    xtr, xte = (xtr - mean) / std, (xte - mean) / std
    clf = HistGradientBoostingClassifier(max_depth=4, max_iter=120,
                                         learning_rate=0.08, random_state=7)
    clf.fit(xtr, ytr)
    pred = clf.predict(xte)
    acc = float((pred == yte).mean())
    base = float(np.bincount((yte - yte.min()).astype(int)).max()) / len(yte)
    probs = clf.predict_proba(xte)
    conf = probs.max(axis=1)
    hit = conf >= 0.60
    prec = float((pred[hit] == yte[hit]).mean()) if hit.sum() > 30 else float("nan")
    return dict(n=n, acc=acc, base=base, edge=acc - base, cov=float(hit.mean()), prec=prec)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--csv", required=True)
    ap.add_argument("--symbol", default="Volatility 25 Index")
    ap.add_argument("--multipliers", default="0.5,1.0,1.5,2.0,3.0")
    ap.add_argument("--horizons", default="5,10,20")
    args = ap.parse_args()

    x, o, h, l, c = load_ohlc_features(args.csv, args.symbol)
    a = atr(h, l, c)
    print(f"[{args.symbol}] rows={len(c)}  atr14 median={np.nanmedian(a):.4f}  "
          f"close median={np.median(c):.2f}")
    print(f"{'mult':>5} {'horizon':>8} {'n':>7} {'acc':>7} {'baseline':>9} "
          f"{'edge':>7} {'cov@0.6':>8} {'prec@0.6':>9}")
    for mult in [float(v) for v in args.multipliers.split(",")]:
        for hor in [int(v) for v in args.horizons.split(",")]:
            labels = barrier_labels(h, l, c, a, mult, hor)
            res = evaluate(x, labels)
            if res is None:
                print(f"{mult:5.1f} {hor:8d}   too few directional rows")
                continue
            print(f"{mult:5.1f} {hor:8d} {res['n']:7d} {res['acc']:7.3f} {res['base']:9.3f} "
                  f"{res['edge']:+7.3f} {res['cov']:8.3f} {res['prec']:9.3f}")


if __name__ == "__main__":
    main()
