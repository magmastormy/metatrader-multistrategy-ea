from __future__ import annotations

import argparse
from itertools import combinations
from typing import List, Tuple

import numpy as np

try:
    import onnxruntime as ort
except ImportError:  # pragma: no cover
    ort = None


def purge_embargo(
    train_idx: np.ndarray,
    test_idx: np.ndarray,
    purge: int = 5,
    embargo: int = 5,
) -> np.ndarray:
    t0, t1 = test_idx.min(), test_idx.max()
    mask = (train_idx < t0 - purge) | (train_idx > t1 + embargo)
    return train_idx[mask]


def cpcv_folds(
    n: int,
    n_splits: int = 6,
    n_test: int = 2,
    purge: int = 5,
    embargo: int = 5,
) -> List[Tuple[np.ndarray, np.ndarray]]:
    groups = np.array_split(np.arange(n), n_splits)
    folds: List[Tuple[np.ndarray, np.ndarray]] = []
    for test_groups in combinations(range(n_splits), n_test):
        test_idx = np.concatenate([groups[i] for i in test_groups])
        train_idx = np.concatenate([groups[i] for i in range(n_splits) if i not in test_groups])
        train_idx = purge_embargo(train_idx, test_idx, purge, embargo)
        folds.append((train_idx, test_idx))
    return folds


def psr(sharpe_ratios: np.ndarray, sr_ref: float = 0.0) -> float:
    from scipy.stats import norm

    mu = sharpe_ratios.mean()
    sig = sharpe_ratios.std(ddof=1) + 1e-9
    z = (mu - sr_ref) / sig * np.sqrt(len(sharpe_ratios))
    return float(norm.cdf(z))


def run_cpcv(
    model_path: str,
    X: np.ndarray,
    y: np.ndarray,
    bar_returns: np.ndarray,
    n_splits: int = 6,
    annualization: float = 252.0,
) -> dict:
    if ort is None:
        raise ImportError("onnxruntime is required for CPCV validation but is not installed.")

    session = ort.InferenceSession(model_path)
    input_name = session.get_inputs()[0].name
    folds = cpcv_folds(len(X), n_splits=n_splits)
    sharpe = []

    for _train_idx, test_idx in folds:
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
    parser.add_argument("--model-path", required=True, help="Path to exported ONNX model.")
    parser.add_argument("--seq-len", type=int, default=60)
    parser.add_argument("--k", type=float, default=1.5)
    parser.add_argument("--vert", type=int, default=20)
    parser.add_argument("--splits", type=int, default=6)
    args = parser.parse_args()

    from data_pipeline import build_scaled_dataset_splits

    train, val, test, metadata = build_scaled_dataset_splits(
        args.csv,
        seq_len=args.seq_len,
        k=args.k,
        vertical_bars=args.vert,
    )
    X = np.concatenate([train[0], val[0], test[0]], axis=0)
    y = np.concatenate([train[1], val[1], test[1]], axis=0)
    returns = np.concatenate([train[3], val[3], test[3]], axis=0)

    result = run_cpcv(
        model_path=args.model_path,
        X=X,
        y=y,
        bar_returns=returns,
        n_splits=args.splits,
        annualization=metadata.annualization,
    )
    if not result["deploy_gate"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
