from __future__ import annotations

import argparse
import pickle
from pathlib import Path

import numpy as np
from scipy.stats import spearmanr

from data_pipeline import build_scaled_dataset_splits

FAMILY_PREFIXES = [
    "crashboom", "volatility", "step", "jump", "dex",
    "multistep", "exponential", "hybrid", "rangebreak",
    "skewstep", "volswitch", "driftswitch", "trek",
    "tactical", "derived", "stablespread", "pairsarbitrage", "spotvolatility",
]


def main() -> None:
    parser = argparse.ArgumentParser(description="Train a family-specific LightGBM model for Deriv synthetic indices.")
    parser.add_argument("--csv", required=True)
    parser.add_argument("--family-id", type=int, required=True, choices=range(18),
                        help="Deriv family ID (0-17)")
    parser.add_argument("--output", default=None)
    parser.add_argument("--seq-len", type=int, default=60)
    parser.add_argument("--k", type=float, default=1.5)
    parser.add_argument("--vert", type=int, default=20)
    args = parser.parse_args()

    # Jump (3) and DEX (4) use longer sequences
    if args.family_id in (3, 4) and args.seq_len == 60:
        args.seq_len = 120

    try:
        import lightgbm as lgb
    except ImportError as exc:  # pragma: no cover
        raise SystemExit("lightgbm is required for train_deriv_lgbm.py") from exc

    train, val, test, metadata = build_scaled_dataset_splits(
        args.csv,
        seq_len=args.seq_len,
        k=args.k,
        vertical_bars=args.vert,
        family_id=args.family_id,
    )
    X_tr = train[0].reshape(len(train[0]), -1)
    X_va = val[0].reshape(len(val[0]), -1)
    X_te = test[0].reshape(len(test[0]), -1)
    y_tr, y_va, y_te = train[1], val[1], test[1]

    prefix = FAMILY_PREFIXES[args.family_id]

    # Family-specific hyperparameters
    if args.family_id == 1:  # Volatility
        params = {
            "objective": "multiclass",
            "num_class": 3,
            "metric": "multi_logloss",
            "learning_rate": 0.02,
            "num_leaves": 31,
            "feature_fraction": 0.7,
            "bagging_fraction": 0.8,
            "bagging_freq": 5,
            "lambda_l1": 0.1,
            "lambda_l2": 0.1,
            "min_child_samples": 50,
            "verbose": -1,
        }
    else:  # Default
        params = {
            "objective": "multiclass",
            "num_class": 3,
            "metric": "multi_logloss",
            "learning_rate": 0.03,
            "num_leaves": 63,
            "feature_fraction": 0.7,
            "bagging_fraction": 0.8,
            "bagging_freq": 5,
            "lambda_l1": 0.1,
            "lambda_l2": 0.1,
            "min_child_samples": 50,
            "verbose": -1,
        }

    model = lgb.train(
        params,
        lgb.Dataset(X_tr, label=y_tr),
        valid_sets=[lgb.Dataset(X_va, label=y_va)],
        num_boost_round=1000,
        callbacks=[lgb.early_stopping(50)],
    )

    pkl_output = args.output or f"{prefix}_lgbm.pkl"
    with open(pkl_output, "wb") as handle:
        pickle.dump(model, handle)

    preds = model.predict(X_te)
    test_ic, _ = spearmanr(preds[:, 2] - preds[:, 0], test[3])
    print(
        f"trained=deriv_lgbm family={prefix}({args.family_id}) "
        f"samples={metadata.train_size}/{metadata.val_size}/{metadata.test_size} "
        f"test_ic={float(test_ic):.4f} pkl={pkl_output}"
    )


if __name__ == "__main__":
    main()
