from __future__ import annotations

import argparse
from itertools import combinations
from typing import Callable, List, Optional, Tuple

import numpy as np
import pandas as pd
from sklearn.preprocessing import StandardScaler

try:
    import onnxruntime as ort
except ImportError:  # pragma: no cover
    ort = None


def purge_embargo(
    train_idx: np.ndarray,
    test_idx: np.ndarray,
    starts_ns: np.ndarray,
    label_ends_ns: np.ndarray,
    embargo_ns: int = 0,
) -> np.ndarray:
    """Drop training events whose actual label intervals overlap test intervals."""
    if starts_ns.ndim != 1 or label_ends_ns.ndim != 1:
        raise ValueError("CPCV timestamps must be one-dimensional")
    if starts_ns.shape != label_ends_ns.shape:
        raise ValueError("starts_ns and label_ends_ns must have identical shapes")
    if embargo_ns < 0:
        raise ValueError("embargo_ns cannot be negative")
    if np.any(train_idx < 0) or np.any(train_idx >= len(starts_ns)):
        raise ValueError("train_idx contains an out-of-range index")
    if np.any(test_idx < 0) or np.any(test_idx >= len(starts_ns)):
        raise ValueError("test_idx contains an out-of-range index")
    if np.any(label_ends_ns < starts_ns):
        raise ValueError("label end timestamps cannot precede sample timestamps")
    if len(test_idx) == 0 or len(train_idx) == 0:
        return train_idx.copy()

    test_starts = starts_ns[test_idx]
    test_ends = label_ends_ns[test_idx]
    order = np.argsort(test_starts, kind="stable")
    sorted_starts = test_starts[order]
    prefix_max_ends = np.maximum.accumulate(test_ends[order])

    train_starts = starts_ns[train_idx]
    train_ends = label_ends_ns[train_idx]
    candidates = np.searchsorted(sorted_starts, train_ends + embargo_ns, side="right")
    previous_test_end = prefix_max_ends[np.maximum(candidates - 1, 0)]
    overlaps = (candidates > 0) & (previous_test_end >= train_starts - embargo_ns)
    return train_idx[~overlaps]


def cpcv_folds(
    starts_ns: np.ndarray,
    label_ends_ns: np.ndarray,
    n_splits: int = 6,
    n_test: int = 2,
    embargo_ns: int = 0,
) -> List[Tuple[np.ndarray, np.ndarray]]:
    if starts_ns.ndim != 1 or label_ends_ns.ndim != 1:
        raise ValueError("CPCV timestamps must be one-dimensional")
    if starts_ns.shape != label_ends_ns.shape:
        raise ValueError("starts_ns and label_ends_ns must have identical shapes")
    if n_splits < 2 or n_test < 1 or n_test >= n_splits:
        raise ValueError("CPCV requires 2 <= n_splits and 1 <= n_test < n_splits")
    unique_starts = np.unique(starts_ns)
    if len(unique_starts) < n_splits:
        raise ValueError("CPCV needs at least one unique timestamp per split")

    row_time_groups = np.searchsorted(unique_starts, starts_ns)
    time_groups = np.array_split(np.arange(len(unique_starts)), n_splits)
    groups = [
        np.flatnonzero((row_time_groups >= group[0]) & (row_time_groups <= group[-1]))
        for group in time_groups
    ]
    folds: List[Tuple[np.ndarray, np.ndarray]] = []
    for test_groups in combinations(range(n_splits), n_test):
        test_idx = np.sort(np.concatenate([groups[i] for i in test_groups]))
        train_idx = np.sort(np.concatenate([groups[i] for i in range(n_splits) if i not in test_groups]))
        train_idx = purge_embargo(train_idx, test_idx, starts_ns, label_ends_ns, embargo_ns)
        if len(train_idx) == 0 or len(test_idx) == 0:
            raise ValueError("CPCV purging produced an empty train or test fold")
        folds.append((train_idx, test_idx))
    return folds


def purged_time_split_indices(
    indices: np.ndarray,
    timestamps: np.ndarray,
    label_end_timestamps: np.ndarray,
    validation_ratio: float = 0.15,
) -> Tuple[np.ndarray, np.ndarray]:
    """Create chronological fit/validation indices with label-overlap purging."""
    if not 0.0 < validation_ratio < 1.0:
        raise ValueError("validation_ratio must be between zero and one")
    times = np.asarray(timestamps, dtype="datetime64[ns]")
    ends = np.asarray(label_end_timestamps, dtype="datetime64[ns]")
    if times.ndim != 1 or ends.ndim != 1 or times.shape != ends.shape:
        raise ValueError("timestamps and label ends must be aligned one-dimensional arrays")
    if np.isnat(times).any() or np.isnat(ends).any():
        raise ValueError("timestamps cannot contain NaT")
    if np.any(ends < times):
        raise ValueError("label end timestamps cannot precede sample timestamps")
    if np.any(indices < 0) or np.any(indices >= len(times)):
        raise ValueError("indices contain an out-of-range value")

    unique_times = np.unique(times[indices])
    if len(unique_times) < 2:
        raise ValueError("a chronological fit/validation split needs at least two timestamps")
    cutoff = min(len(unique_times) - 1, max(1, int(len(unique_times) * (1.0 - validation_ratio))))
    validation_start = unique_times[cutoff]
    validation_indices = indices[times[indices] >= validation_start]
    fit_candidates = indices[times[indices] < validation_start]
    fit_indices = fit_candidates[ends[fit_candidates] < validation_start]
    if len(fit_indices) == 0 or len(validation_indices) == 0:
        raise ValueError("purging produced an empty fit or validation subset")
    return fit_indices, validation_indices


def fit_fold_feature_scaler(X: np.ndarray, fit_idx: np.ndarray) -> StandardScaler:
    if X.ndim < 2 or len(fit_idx) == 0:
        raise ValueError("fold scaler requires non-empty training features")
    scaler = StandardScaler()
    scaler.fit(X[fit_idx].reshape(len(fit_idx), -1))
    return scaler


def transform_fold_features(X: np.ndarray, scaler: StandardScaler) -> np.ndarray:
    if X.ndim < 2:
        raise ValueError("fold features must include sample and feature dimensions")
    transformed = scaler.transform(X.reshape(len(X), -1))
    return transformed.reshape(X.shape).astype(np.float32)


def psr(sharpe_ratios: np.ndarray, sr_ref: float = 0.0) -> float:
    from scipy.stats import norm

    mu = sharpe_ratios.mean()
    sig = sharpe_ratios.std(ddof=1) + 1e-9
    z = (mu - sr_ref) / sig * np.sqrt(len(sharpe_ratios))
    return float(norm.cdf(z))


def run_cpcv(
    X: np.ndarray,
    bar_returns: np.ndarray,
    timestamps: np.ndarray,
    label_end_timestamps: np.ndarray,
    fold_model_path: Callable[[int, np.ndarray], object],
    n_splits: int = 6,
    annualization: float = 252.0,
) -> dict:
    if ort is None:
        raise ImportError("onnxruntime is required for CPCV validation but is not installed.")

    timestamp_values = np.asarray(timestamps, dtype="datetime64[ns]")
    label_end_values = np.asarray(label_end_timestamps, dtype="datetime64[ns]")
    if np.isnat(timestamp_values).any() or np.isnat(label_end_values).any():
        raise ValueError("CPCV timestamps cannot contain NaT")
    starts_ns = timestamp_values.astype(np.int64)
    label_ends_ns = label_end_values.astype(np.int64)
    if len(X) != len(bar_returns) or len(X) != len(starts_ns) or len(X) != len(label_ends_ns):
        raise ValueError("CPCV features, returns, starts, and label ends must align")
    folds = cpcv_folds(starts_ns, label_ends_ns, n_splits=n_splits)
    sharpe = []

    for fold_no, (train_idx, test_idx) in enumerate(folds):
        fold_artifact = fold_model_path(fold_no, train_idx)
        if isinstance(fold_artifact, tuple):
            if len(fold_artifact) != 2:
                raise ValueError("fold callback tuple must be (model_path, scaler)")
            model_path, fold_scaler = fold_artifact
        else:
            model_path, fold_scaler = fold_artifact, None
        session = ort.InferenceSession(model_path)
        input_name = session.get_inputs()[0].name
        X_test = X[test_idx].astype(np.float32)
        if fold_scaler is not None:
            X_test = transform_fold_features(X_test, fold_scaler)
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
        help="ONNX path per CPCV fold, e.g. models/cpcv_fold_{fold}.onnx; expects raw features unless paired with a scaler template",
    )
    parser.add_argument(
        "--fold-scaler-template",
        help="Optional joblib/pickle scaler per fold, fit only on that fold's training data, e.g. models/cpcv_scaler_{fold}.pkl",
    )
    args = parser.parse_args()

    from data_pipeline import build_dataset_splits

    train, val, test, annualization = build_dataset_splits(
        pd.read_csv(args.csv),
        seq_len=args.seq_len,
        k=args.k,
        vertical_bars=args.vert,
    )
    X = np.concatenate([train[0], val[0], test[0]], axis=0)
    returns = np.concatenate([train[3], val[3], test[3]], axis=0)
    timestamps = np.concatenate([train[4], val[4], test[4]], axis=0)
    label_end_timestamps = np.concatenate([train[5], val[5], test[5]], axis=0)

    def fold_model_artifact(fold: int, _train_idx: np.ndarray):
        model_path = args.fold_model_template.format(fold=fold)
        if not args.fold_scaler_template:
            return model_path
        import joblib

        scaler_path = args.fold_scaler_template.format(fold=fold)
        return model_path, joblib.load(scaler_path)

    result = run_cpcv(
        X=X,
        bar_returns=returns,
        timestamps=timestamps,
        label_end_timestamps=label_end_timestamps,
        fold_model_path=fold_model_artifact,
        n_splits=args.splits,
        annualization=annualization,
    )
    if not result["deploy_gate"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
