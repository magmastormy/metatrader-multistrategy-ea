#!/usr/bin/env python
"""
Signal diagnostic for the AI training set.

Question this answers, before anyone ships a model:
do the 70 exported features contain ANY information about the future direction at a
5/10/20-bar horizon, or is the label essentially unpredictable given the inputs?

Method: strict chronological split, no shuffling, and two learners far stronger than the
EA's 70-32-16-8-3 MLP (logistic regression and gradient-boosted trees). If a boosted
tree cannot beat the majority-class baseline, no MLP will, and the correct action is to
fix the features/labels - not to train harder.

Reported per horizon:
  * test accuracy vs majority baseline
  * binary up/down accuracy on rows where the label is directional (drop HOLD)
  * top feature importances, so a leakage or a dead feature is visible
"""

from __future__ import annotations

import argparse
import csv
import sys
from collections import defaultdict

import numpy as np
from sklearn.ensemble import HistGradientBoostingClassifier
from sklearn.linear_model import LogisticRegression

FEATURE_VECTOR_SIZE = 70
HORIZONS = ("label_5bar", "label_10bar", "label_20bar")


def load(path, symbol):
    with open(path, newline="", encoding="utf-8-sig") as handle:
        reader = csv.reader(handle)
        header = next(reader)
        idx = {n: i for i, n in enumerate(header)}
        feats = [idx[f"feature_{i:02d}"] for i in range(FEATURE_VECTOR_SIZE)]
        labels = [idx[h] for h in HORIZONS]
        sym_i = idx["symbol"]
        xs, ys = [], []
        for row in reader:
            if row[sym_i] != symbol:
                continue
            try:
                x = [float(row[i]) for i in feats]
                y = [int(float(row[i])) for i in labels]
            except ValueError:
                continue
            xs.append(x)
            ys.append(y)
    return np.asarray(xs, np.float64), np.asarray(ys, np.int64), list(header)


def split(x, y, val_frac=0.15, purge=20):
    n = len(y)
    n_val = int(n * val_frac)
    return (x[:n - 2 * n_val - purge], y[:n - 2 * n_val - purge]), \
           (x[n - 2 * n_val:n - n_val], y[n - 2 * n_val:n - n_val]), \
           (x[n - n_val:], y[n - n_val:])


def run(path, symbol, horizon_idx, model_name):
    x, ys, header = load(path, symbol)
    y_raw = ys[:, horizon_idx]
    (x_tr, y_tr), (x_va, y_va), (x_te, y_te) = split(x, y_raw)

    mean, std = x_tr.mean(0), x_tr.std(0) + 1e-9
    x_tr_n, x_va_n, x_te_n = ((a - mean) / std for a in (x_tr, x_va, x_te))

    def fit_eval(xtr, ytr, xte, yte, tag):
        if model_name == "gbm":
            clf = HistGradientBoostingClassifier(max_depth=4, max_iter=120,
                                                 learning_rate=0.08, random_state=7)
        else:
            clf = LogisticRegression(max_iter=400, C=0.5, multi_class="auto")
        clf.fit(xtr, ytr)
        acc = float((clf.predict(xte) == yte).mean())
        base = float(np.bincount(yte - yte.min()).max()) / len(yte)
        print(f"  {tag:14s} {model_name:6s} testAcc {acc:.4f} | baseline {base:.4f} "
              f"| edge {acc - base:+.4f}")
        return acc, base, clf

    print(f"\n[{symbol}] {HORIZONS[horizon_idx]}  n={len(y_raw)}  "
          f"classes={dict(zip(*[a.tolist() for a in np.unique(y_raw, return_counts=True)]))}")
    fit_eval(x_tr_n, y_tr, x_te_n, y_te, "3-class")

    dir_tr = y_tr != 0
    dir_te = y_te != 0
    if dir_te.sum() > 200:
        fit_eval(x_tr_n[dir_tr], y_tr[dir_tr], x_te_n[dir_te], y_te[dir_te], "up/down only")

    if model_name == "gbm":
        clf = HistGradientBoostingClassifier(max_depth=4, max_iter=120,
                                             learning_rate=0.08, random_state=7)
        clf.fit(x_tr_n, y_tr)
        # HistGradientBoosting has no per-feature importance; use permutation on the test set
        rng = np.random.default_rng(0)
        base_acc = float((clf.predict(x_te_n) == y_te).mean())
        deltas = []
        for f in range(x_te_n.shape[1]):
            perm = x_te_n.copy()
            rng.shuffle(perm[:, f])
            deltas.append((base_acc - float((clf.predict(perm) == y_te).mean()), f))
        deltas.sort(reverse=True)
        print("  most useful features (permutation drop):")
        for drop, f in deltas[:8]:
            print(f"    feature_{f:02d}  delta {drop:+.4f}")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--csv", required=True)
    ap.add_argument("--symbol", default="Volatility 25 Index")
    ap.add_argument("--model", default="gbm", choices=("gbm", "logreg"))
    ap.add_argument("--horizons", default="0,1,2")
    args = ap.parse_args()
    for h in [int(v) for v in args.horizons.split(",")]:
        run(args.csv, args.symbol, h, args.model)
