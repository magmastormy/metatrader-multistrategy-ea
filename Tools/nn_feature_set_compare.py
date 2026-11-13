#!/usr/bin/env python
"""
Feature-set comparison on the exported training data.

Motivation: nn_label_geometry_test.py showed that, across every barrier width and
horizon, a gradient-boosted tree on the 70-feature vector used by the live
CNeuralNetworkStrategy stays within +-2 points of the majority-class baseline on
Volatility 25 Index. Two explanations remain:

  (a) the market at these horizons on this instrument is genuinely unpredictable from
      this information set, or
  (b) the 70-feature vector that the NN sees is a lossy subset of what the exporter
      actually computed (regime state, hurst, ou, vpin, ofi, per-strategy signals and
      consensus fields are all present as separate columns).

This script trains the same model on progressively larger column sets and on labels
rebuilt at the EA's live geometry (1.5 ATR / 12 bars, AIConfig.mqh:90-94), so the answer
is "the information is missing from the vector" or "the information does not exist",
rather than a guess.
"""

from __future__ import annotations

import argparse
import csv

import numpy as np
from sklearn.ensemble import HistGradientBoostingClassifier

N_FEATURES = 70
ATR_PERIOD = 14


def load(path, symbol):
    with open(path, newline="", encoding="utf-8-sig") as handle:
        reader = csv.reader(handle)
        header = next(reader)
        idx = {n: i for i, n in enumerate(header)}
        feat_cols = [idx[f"feature_{i:02d}"] for i in range(N_FEATURES)]
        extra_cols, extra_names = [], []
        for i, name in enumerate(header):
            if name in ("symbol", "timestamp", "open", "high", "low", "close",
                        "tick_volume", "spread") or name.startswith("label_"):
                continue
            if name.startswith("feature_"):
                continue
            extra_cols.append(i)
            extra_names.append(name)
        ohlc = [idx["open"], idx["high"], idx["low"], idx["close"]]
        sym_i = idx["symbol"]
        rows_f, rows_all, o, h, l, c = [], [], [], [], [], []
        for row in reader:
            if row[sym_i] != symbol:
                continue
            try:
                rows_f.append([float(row[i]) for i in feat_cols])
                rows_all.append([float(row[i]) if row[i] not in ("", "nan") else 0.0
                                 for i in feat_cols + extra_cols])
                o.append(float(row[ohlc[0]])); h.append(float(row[ohlc[1]]))
                l.append(float(row[ohlc[2]])); c.append(float(row[ohlc[3]]))
            except ValueError:
                continue
    return (np.asarray(rows_f, np.float64), np.asarray(rows_all, np.float64),
            np.asarray(o), np.asarray(h), np.asarray(l), np.asarray(c), extra_names)


def atr(high, low, close, period=ATR_PERIOD):
    prev = np.concatenate(([close[0]], close[:-1]))
    tr = np.maximum(high - low, np.maximum(np.abs(high - prev), np.abs(low - prev)))
    out = np.full(len(close), np.nan)
    if len(tr) > period:
        cs = np.cumsum(np.insert(tr, 0, 0.0))
        out[period:] = (cs[period + 1:] - cs[1:len(tr) - period + 1]) / period
    return out


def barrier(high, low, close, a, mult, horizon):
    labels = np.zeros(len(close), np.int64)
    for t in range(len(close) - horizon):
        if not np.isfinite(a[t]) or a[t] <= 0:
            continue
        up, dn = close[t] + a[t] * mult, close[t] - a[t] * mult
        for j in range(t + 1, t + horizon + 1):
            if high[j] >= up:
                labels[t] = 1
                break
            if low[j] <= dn:
                labels[t] = -1
                break
    return labels


def test(x, y, tag, drop_hold=True):
    m = (y != 0) if drop_hold else np.ones(len(y), bool)
    x, y = x[m], y[m]
    cut = int(len(y) * 0.7)
    xtr, xte, ytr, yte = x[:cut], x[cut:], y[:cut], y[cut:]
    mean, std = xtr.mean(0), xtr.std(0) + 1e-9
    xtr, xte = (xtr - mean) / std, (xte - mean) / std
    clf = HistGradientBoostingClassifier(max_depth=4, max_iter=150,
                                         learning_rate=0.08, random_state=7)
    clf.fit(xtr, ytr)
    acc = float((clf.predict(xte) == yte).mean())
    base = float(np.bincount((yte - yte.min()).astype(int)).max()) / len(yte)
    print(f"  {tag:34s} n={len(y):6d} acc={acc:.4f} baseline={base:.4f} edge={acc - base:+.4f}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--csv", required=True)
    ap.add_argument("--symbol", default="Volatility 25 Index")
    args = ap.parse_args()
    xf, xall, o, h, l, c, extra = load(args.csv, args.symbol)
    a = atr(h, l, c)
    print(f"[{args.symbol}] rows={len(c)} extra columns={len(extra)}")
    for mult, hor in ((1.5, 12), (1.0, 10), (0.5, 5)):
        y = barrier(h, l, c, a, mult, hor)
        print(f"\ngeometry {mult} ATR / {hor} bars  "
              f"(hold rows {int((y == 0).sum())}, up {int((y == 1).sum())}, down {int((y == -1).sum())})")
        test(xf, y, "70-feature vector (what the NN sees)")
        test(xall, y, "all exported columns")


if __name__ == "__main__":
    main()
