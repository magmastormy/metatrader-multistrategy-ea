#!/usr/bin/env python3
"""Export a volatility-regime classifier as plain JSON trees the EA can evaluate.

Why this exists
---------------
Batch 276 measured the 70-feature vector to be a volatility descriptor with no
directional content: switching the target to "does volatility expand" scored
+4.16 points over the majority baseline, 70.8% precision at confidence >= 0.60.
Batch 277 then tried to put that edge inside the architecture the EA can run
(70-32-16-8-3 MLP, 2963 params) and could not: at band 0 the MLP reached
0.6137 vs 0.6102 baseline (+0.35 pp), i.e. it held almost none of the edge a
gradient-boosted tree extracts from the same rows.

A 2,963-parameter net is not the constraint that matters here - the *shape* of
the decision boundary is. Boosted trees model the threshold interactions in
ATR / BB-width / range-compression features that this target depends on; a
single hidden layer of 32 units smooths them away. So the model is trained
where it wins and exported in a form MQL5 can evaluate exactly, with no
inference library, no ONNX buffer and no Python bridge.

Artifact
--------
JSON: {"classes": 2, "feature_count": 70, "learning_rate": L, "base": b,
       "trees": [{"nodes": [[feat, thr, left, right, value], ...]}, ...]}
Node encoding: feats -1 = leaf (value is the raw score), otherwise
  x[feat] <= thr -> left, else -> right.
Score = base + learning_rate * sum(leaf values).  class 1 (expansion) when
score > 0.

Verification done here, not assumed
-----------------------------------
After serialising, the trees are re-evaluated from the JSON in pure python and
compared against sklearn's own predict_proba on the held-out test split: any
disagreement is reported and the export is refused. The printed edge is
measured on the chronological test split with a purge gap, never shuffled.

Usage
-----
  python Tools/nn_vol_model_export.py --csv <AITraining_Enterprise_H1.csv> \
      --out-dir <dir> --symbols all --band 0 --horizon 5 --lookback 20
"""
from __future__ import annotations

import argparse
import csv
import json
import sys
from collections import defaultdict
from pathlib import Path

import numpy as np

FEATURE_VECTOR_SIZE = 70


def load_rows(path: str, wanted: str):
    """Only what this model needs: 70 features, timestamps, OHLC, per symbol."""
    per_symbol = defaultdict(lambda: {"x": [], "t": [], "h": [], "l": [], "c": []})
    with open(path, newline="", encoding="utf-8-sig") as handle:
        reader = csv.reader(handle)
        header = next(reader)
        idx = {name: i for i, name in enumerate(header)}
        feat_idx = [idx[f"feature_{i:02d}"] for i in range(FEATURE_VECTOR_SIZE)]
        sym_idx, ts_idx = idx["symbol"], idx["timestamp"]
        hi_idx, lo_idx, cl_idx = idx["high"], idx["low"], idx["close"]
        skipped = 0
        for row in reader:
            symbol = row[sym_idx]
            if wanted != "all" and symbol not in wanted:
                continue
            try:
                feats = [float(row[i]) for i in feat_idx]
                hi, lo, cl = float(row[hi_idx]), float(row[lo_idx]), float(row[cl_idx])
            except ValueError:
                skipped += 1
                continue
            bucket = per_symbol[symbol]
            bucket["x"].append(feats)
            bucket["t"].append(row[ts_idx])
            bucket["h"].append(hi)
            bucket["l"].append(lo)
            bucket["c"].append(cl)
    if skipped:
        print(f"[data] skipped {skipped} malformed rows")
    return per_symbol


def volatility_label(high, low, close, horizon, lookback, band):
    """1 = next `horizon` bars' mean true range is `band` above the trailing median."""
    n = len(close)
    prev = np.concatenate(([close[0]], close[:-1]))
    tr = np.maximum(high - low, np.maximum(np.abs(high - prev), np.abs(low - prev)))
    labels = np.full(n, -1, np.int64)
    for t in range(n):
        if t + horizon >= n or t < lookback:
            continue
        future = tr[t + 1:t + 1 + horizon].mean()
        trailing = np.median(tr[t - lookback:t + 1])
        if trailing <= 0:
            continue
        labels[t] = 1 if future > trailing * (1.0 + band) else 0
    return labels


def write_csv(path, artifact: dict) -> None:
    """Flat CSV, tree-major and node-major, so MQL5 needs no JSON parser.

    META,classes,feature_count,learning_rate,base,tree_count
    tree,node,feature,threshold,left,right,value      (feature = -1 marks a leaf)
    """
    with path.open("w", newline="", encoding="utf-8") as handle:
        handle.write("META,2,%d,%.9f,%.9f,%d\n" % (
            artifact["feature_count"], artifact["learning_rate"],
            artifact["base"], len(artifact["trees"])))
        for t, tree in enumerate(artifact["trees"]):
            for n, entry in enumerate(tree["nodes"]):
                handle.write("%d,%d,%d,%.9f,%d,%d,%.9f\n" % (
                    t, n, entry[0], entry[1], entry[2], entry[3], entry[4]))


def read_csv(path):
    """Read the artifact back exactly as MQL5 will, so the check covers the file too."""
    artifact = {"trees": [], "base": 0.0, "learning_rate": 0.0, "feature_count": 0}
    with path.open(newline="", encoding="utf-8") as handle:
        for row in csv.reader(handle):
            if not row:
                continue
            if row[0] == "META":
                artifact["feature_count"] = int(row[2])
                artifact["learning_rate"] = float(row[3])
                artifact["base"] = float(row[4])
                artifact["trees"] = [{"nodes": []} for _ in range(int(row[5]))]
                continue
            tree = artifact["trees"][int(row[0])]
            tree["nodes"].append([int(row[2]), float(row[3]), int(row[4]), int(row[5]), float(row[6])])
    return artifact


def export_trees(model, feature_count: int, learning_rate: float) -> dict:
    # sklearn's GradientBoostingClassifier applies a sigmoid to `base + lr * sum(leaves)`,
    # where `base` is the log-odds of the initial prior. Recovering it here keeps the
    # exported artifact reproducible without carrying a second model object.
    prior = float(model.init_.predict_proba(np.zeros((1, feature_count)))[0, 1])
    prior = min(max(prior, 1e-9), 1.0 - 1e-9)
    base = float(np.log(prior / (1.0 - prior)))
    trees = []
    for estimator in model.estimators_[:, 0]:
        tree = estimator.tree_
        nodes = []
        for node in range(tree.node_count):
            left, right = int(tree.children_left[node]), int(tree.children_right[node])
            feat = int(tree.feature[node])
            if left == right:  # leaf
                nodes.append([-1, 0.0, -1, -1, round(float(tree.value[node][0][0]), 9)])
            else:
                nodes.append([feat, round(float(tree.threshold[node]), 9), left, right, 0.0])
        trees.append({"nodes": nodes})
    return {
        "classes": 2,
        "feature_count": feature_count,
        "learning_rate": learning_rate,
        "base": round(base, 9),
        "trees": trees,
    }


def score_python(artifact: dict, x: np.ndarray):
    """Evaluate the exported trees exactly the way the MQL5 reader does."""
    score = np.full(x.shape[0], artifact["base"], dtype=np.float64)
    for tree in artifact["trees"]:
        nodes = tree["nodes"]
        for row in range(x.shape[0]):
            node = 0
            while True:
                entry = nodes[node]
                if entry[0] < 0:
                    score[row] += artifact["learning_rate"] * entry[4]
                    break
                node = entry[2] if x[row, entry[0]] <= entry[1] else entry[3]
    return score


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--csv", required=True)
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--symbols", default="all")
    ap.add_argument("--band", type=float, default=0.0)
    ap.add_argument("--horizon", type=int, default=5)
    ap.add_argument("--lookback", type=int, default=20)
    ap.add_argument("--trees", type=int, default=60)
    ap.add_argument("--depth", type=int, default=4)
    ap.add_argument("--learning-rate", type=float, default=0.1)
    ap.add_argument("--min-gain", type=float, default=0.01,
                    help="required margin over the majority baseline on the test split")
    args = ap.parse_args()

    try:
        from sklearn.ensemble import GradientBoostingClassifier
    except ImportError:
        print("[fatal] scikit-learn is required: pip install scikit-learn")
        return 2

    wanted = "all" if args.symbols == "all" else set(s.strip() for s in args.symbols.split(","))
    per_symbol = load_rows(args.csv, wanted)
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    summary = []
    for symbol, bucket in sorted(per_symbol.items()):
        x = np.asarray(bucket["x"], dtype=np.float64)
        y = volatility_label(np.asarray(bucket["h"]), np.asarray(bucket["l"]),
                             np.asarray(bucket["c"]), args.horizon, args.lookback, args.band)
        keep = y >= 0
        x, y = x[keep], y[keep]
        if len(y) < 2000:
            print(f"[skip] {symbol}: {len(y)} usable rows")
            continue

        n = len(y)
        train_end, val_end = int(n * 0.70), int(n * 0.85)
        gap = 12
        x_tr, y_tr = x[:train_end - gap], y[:train_end - gap]
        x_va, y_va = x[train_end:val_end - gap], y[train_end:val_end - gap]
        x_te, y_te = x[val_end:], y[val_end:]

        model = GradientBoostingClassifier(
            n_estimators=args.trees, max_depth=args.depth,
            learning_rate=args.learning_rate, subsample=1.0, random_state=7)
        model.fit(x_tr, y_tr)

        # pick the tree count that maximises validation accuracy, then freeze it
        # sklearn 1.9 dropped `ntree_limit`; staged_predict_proba is the supported way
        # to ask "what would the first k trees say".
        staged = list(model.staged_predict_proba(x_va))
        best_k, best_acc = args.trees, -1.0
        for k in range(10, min(len(staged), args.trees) + 1, 10):
            acc = float(((staged[k - 1][:, 1] > 0.5).astype(int) == y_va).mean())
            if acc > best_acc:
                best_k, best_acc = k, acc
        model.estimators_ = model.estimators_[:best_k]

        artifact = export_trees(model, FEATURE_VECTOR_SIZE, args.learning_rate)
        artifact["symbol"] = symbol
        artifact["target"] = f"vol band={args.band} horizon={args.horizon} lookback={args.lookback}"

        # round-trip: the JSON must reproduce sklearn's probabilities exactly
        proba = model.predict_proba(x_te)[:, 1]
        scale = 1.0
        raw = score_python(artifact, x_te)
        # sklearn applies a sigmoid on the raw score; recover it so parity is checkable
        got = 1.0 / (1.0 + np.exp(-raw * scale))
        max_err = float(np.max(np.abs(got - proba)))
        if max_err > 2e-6:
            print(f"[refuse] {symbol}: exported trees disagree with sklearn (max {max_err:.3e})")
            continue

        pred = (raw > 0.0).astype(int)
        baseline = max(float(y_te.mean()), 1.0 - float(y_te.mean()))
        acc = float((pred == y_te).mean())
        conf_mask = np.abs(raw) >= np.log(3.0)  # >=75% confidence
        conf_acc = float((pred[conf_mask] == y_te[conf_mask]).mean()) if conf_mask.any() else 0.0
        coverage = float(conf_mask.mean())

        path = out_dir / f"{symbol.replace(' ', '_')}_15_vol.csv"
        write_csv(path, artifact)
        artifact = read_csv(path)  # verify the file, not the in-memory dict
        raw = score_python(artifact, x_te)
        got = 1.0 / (1.0 + np.exp(-raw))
        max_err = float(np.max(np.abs(got - proba)))
        if max_err > 2e-6:
            print(f"[refuse] {symbol}: CSV artifact disagrees with sklearn (max {max_err:.3e})")
            path.unlink(missing_ok=True)
            continue
        wrote = (acc - baseline) >= args.min_gain
        summary.append((symbol, len(y), acc, baseline, conf_acc, coverage, wrote,
                        path.name, path.stat().st_size))

        print(f"[{symbol}] rows={len(y)} trees={best_k} testAcc={acc:.4f} baseline={baseline:.4f} "
              f"edge={acc - baseline:+.4f} confAcc={conf_acc:.4f} coverage={coverage:.3f} "
              f"roundtrip=ok({max_err:.1e}) wrote={wrote}")
        if wrote:
            print(f"    -> {path}")
        else:
            path.unlink(missing_ok=True)

    report = out_dir / "vol_model_report.csv"
    with report.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(["symbol", "rows", "test_acc", "baseline", "edge", "conf_acc",
                         "coverage", "wrote", "file", "bytes"])
        for row in summary:
            writer.writerow([row[0], row[1], f"{row[2]:.4f}", f"{row[3]:.4f}",
                             f"{row[2] - row[3]:+.4f}", f"{row[4]:.4f}", f"{row[5]:.3f}",
                             row[6], row[7] if row[6] else "", row[8] if row[6] else 0])
    print(f"[report] {report}")
    return 0 if any(row[6] for row in summary) else 1


if __name__ == "__main__":
    sys.exit(main())
