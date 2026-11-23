from __future__ import annotations

import argparse
from typing import Callable, Optional

import numpy as np

try:
    import onnxruntime as ort
except ImportError:  # pragma: no cover
    ort = None

# Canonical timestamp-purge / CPCV / PSR implementations live in
# training_core.py (also vendored into the self-contained Colab script
# mql5_v2.py via sync_mql5_v2.py).
from training_core import (  # noqa: F401  (re-exported for existing callers)
    cpcv_folds,
    label_horizon_ns,
    psr,
    purge_embargo,
)


def run_cpcv(
    X: np.ndarray,
    bar_returns: np.ndarray,
    timestamps: np.ndarray,
    vertical_bars: int,
    fold_model_path: Callable[[int, np.ndarray], str],
    n_splits: int = 6,
    annualization: float = 252.0,
    label_ends_ns: Optional[np.ndarray] = None,
) -> dict:
    if ort is None:
        raise ImportError("onnxruntime is required for CPCV validation but is not installed.")

    starts_ns = np.asarray(timestamps, dtype="datetime64[ns]").astype(np.int64)
    ends_ns = None
    if label_ends_ns is not None:
        ends_ns = np.asarray(label_ends_ns, dtype="datetime64[ns]").astype(np.int64)
    folds = cpcv_folds(
        starts_ns,
        label_horizon_ns(timestamps, vertical_bars),
        n_splits=n_splits,
        ends_ns=ends_ns,
    )
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
    label_ends = np.concatenate([train[5], val[5], test[5]], axis=0)

    result = run_cpcv(
        X=X,
        bar_returns=returns,
        timestamps=timestamps,
        vertical_bars=args.vert,
        fold_model_path=lambda fold, _train_idx: args.fold_model_template.format(fold=fold),
        n_splits=args.splits,
        annualization=metadata.annualization,
        label_ends_ns=label_ends,
    )
    if not result["deploy_gate"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
