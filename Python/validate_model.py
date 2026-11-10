from __future__ import annotations

import argparse
from itertools import combinations
from typing import Callable, List, Optional, Tuple

import numpy as np

try:
    import onnxruntime as ort
except ImportError:  # pragma: no cover
    ort = None


def purge_embargo(
    train_idx: np.ndarray,
    test_idx: np.ndarray,
    starts_ns: np.ndarray,
    horizon_ns: int,
    embargo_ns: int = 0,
) -> np.ndarray:
    """Drop training samples whose label span [start, start + horizon] overlaps any test span."""
    radius = horizon_ns + embargo_ns
    test_starts = np.sort(starts_ns[test_idx])
    s = starts_ns[train_idx]
    lo = np.searchsorted(test_starts, s - radius, side="left")
    hi = np.searchsorted(test_starts, s + radius, side="right")
    return train_idx[hi == lo]


def cpcv_folds(
    starts_ns: np.ndarray,
    horizon_ns: int,
    n_splits: int = 6,
    n_test: int = 2,
    embargo_ns: int = 0,
) -> List[Tuple[np.ndarray, np.ndarray]]:
    n = len(starts_ns)
    groups = np.array_split(np.arange(n), n_splits)
    folds: List[Tuple[np.ndarray, np.ndarray]] = []
    for test_groups in combinations(range(n_splits), n_test):
        test_idx = np.concatenate([groups[i] for i in test_groups])
        train_idx = np.concatenate([groups[i] for i in range(n_splits) if i not in test_groups])
        train_idx = purge_embargo(train_idx, test_idx, starts_ns, horizon_ns, embargo_ns)
        folds.append((train_idx, test_idx))
    return folds


def psr(sharpe_ratios: np.ndarray, sr_ref: float = 0.0) -> float:
    from scipy.stats import norm

    mu = sharpe_ratios.mean()
    sig = sharpe_ratios.std(ddof=1) + 1e-9
    z = (mu - sr_ref) / sig * np.sqrt(len(sharpe_ratios))
    return float(norm.cdf(z))


def label_horizon_ns(timestamps: np.ndarray, vertical_bars: int) -> int:
    ts = np.unique(np.asarray(timestamps, dtype="datetime64[ns]").astype(np.int64))
    diffs = np.diff(ts)
    diffs = diffs[diffs > 0]
    if len(diffs) == 0:
        raise ValueError("Cannot infer bar spacing from timestamps for CPCV purging.")
    return int(np.median(diffs)) * int(vertical_bars)


def run_cpcv(
    X: np.ndarray,
    bar_returns: np.ndarray,
    timestamps: np.ndarray,
    vertical_bars: int,
    fold_model_path: Callable[[int, np.ndarray], str],
    n_splits: int = 6,
    annualization: float = 252.0,
) -> dict:
    if ort is None:
        raise ImportError("onnxruntime is required for CPCV validation but is not installed.")

    starts_ns = np.asarray(timestamps, dtype="datetime64[ns]").astype(np.int64)
    folds = cpcv_folds(starts_ns, label_horizon_ns(timestamps, vertical_bars), n_splits=n_splits)
    sharpe = []

    for fold_no, (train_idx, test_idx) in enumerate(folds):
        session = ort.InferenceSession(fold_model_path(fold_no, train_idx))
        input_name = session.get_inputs()[0].name
        X_test = X[test_idx].astype(np.float32)
        logits = session.run(None, {input_name: X_test})[0]
        preds = logits.argmax(axis=1) - 1
        returns = preds * bar_returns[test_idx]
        sr = returns.mean() / (returns.std() + 1e-9) * np.sqrt(annualization)
        sharpe.append(float(sr))

    sharpe = np.asarray(sharpe, dtype=np.float64)
    p10 = float(np.percentile(sharpe, 10))
    result = {
        "sharpe_ratios": sharpe,
        "mean_sr": float(sharpe.mean()),
        "p10_sr": p10,
        "psr": psr(sharpe),
        "deploy_gate": p10 > 0.0,
    }

    print(f"CPCV Results ({len(folds)} folds):")
    print(f"  Sharpe per fold: {np.round(sharpe, 3)}")
    print(
        "  Mean SR: "
        f"{result['mean_sr']:.3f}  |  10th pct SR: {p10:.3f}  |  PSR: {result['psr']:.3f}"
    )
    print(f"  DEPLOYMENT GATE: {'PASS' if result['deploy_gate'] else 'FAIL'}")
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description="Run CPCV validation against an exported ONNX model.")
    parser.add_argument("--csv", required=True, help="OHLCV CSV used to rebuild aligned validation features.")
    parser.add_argument("--seq-len", type=int, default=60)
    parser.add_argument("--k", type=float, default=1.5)
    parser.add_argument("--vert", type=int, default=20)
    parser.add_argument("--splits", type=int, default=6)
    parser.add_argument(
        "--fold-model-template",
        required=True,
        help="ONNX path per CPCV fold, fit on that fold's training indices, e.g. models/cpcv_fold_{fold}.onnx",
    )
    args = parser.parse_args()

    from data_pipeline import build_scaled_dataset_splits

    train, val, test, metadata = build_scaled_dataset_splits(
        args.csv,
        seq_len=args.seq_len,
        k=args.k,
        vertical_bars=args.vert,
    )
    X = np.concatenate([train[0], val[0], test[0]], axis=0)
    returns = np.concatenate([train[3], val[3], test[3]], axis=0)
    timestamps = np.concatenate([train[4], val[4], test[4]], axis=0)

    result = run_cpcv(
        X=X,
        bar_returns=returns,
        timestamps=timestamps,
        vertical_bars=args.vert,
        fold_model_path=lambda fold, _train_idx: args.fold_model_template.format(fold=fold),
        n_splits=args.splits,
        annualization=metadata.annualization,
    )
    if not result["deploy_gate"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
