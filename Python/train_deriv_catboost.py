from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np

from data_pipeline import build_scaled_dataset_splits
from train_common import FAMILY_PREFIXES, adjust_seq_len_for_family, compute_test_ic, load_split, save_pickle


def main() -> None:
    parser = argparse.ArgumentParser(description="Train a family-specific CatBoost model for Deriv synthetic indices.")
    parser.add_argument("--csv", required=True)
    parser.add_argument("--family-id", type=int, required=True, choices=range(18),
                        help="Deriv family ID (0-17)")
    parser.add_argument("--output", default=None)
    parser.add_argument("--seq-len", type=int, default=60)
    parser.add_argument("--k", type=float, default=1.5)
    parser.add_argument("--vert", type=int, default=20)
    args = parser.parse_args()

    # Jump (3) and DEX (4) use longer sequences
    args.seq_len = adjust_seq_len_for_family(args.family_id, args.seq_len)

    try:
        from catboost import CatBoostClassifier, Pool
    except ImportError as exc:  # pragma: no cover
        raise SystemExit("catboost is required for train_deriv_catboost.py") from exc

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
    if args.family_id in (0, 4):  # CrashBoom, DEX
        model = CatBoostClassifier(
            iterations=1500,
            learning_rate=0.025,
            depth=8,
            loss_function="MultiClass",
            classes_count=3,
            l2_leaf_reg=5.0,
            random_seed=42,
            verbose=100,
            early_stopping_rounds=75,
            class_weights=[1.0, 0.5, 1.0],
        )
    elif args.family_id == 7:  # Hybrid
        model = CatBoostClassifier(
            iterations=1200,
            learning_rate=0.03,
            depth=7,
            loss_function="MultiClass",
            classes_count=3,
            l2_leaf_reg=4.0,
            random_seed=42,
            verbose=100,
            early_stopping_rounds=50,
        )
    else:  # Default
        model = CatBoostClassifier(
            iterations=1000,
            learning_rate=0.03,
            depth=6,
            loss_function="MultiClass",
            classes_count=3,
            l2_leaf_reg=3.0,
            random_seed=42,
            verbose=100,
            early_stopping_rounds=50,
        )

    train_pool = Pool(X_tr, label=y_tr, feature_names=None)
    val_pool = Pool(X_va, label=y_va, feature_names=None)
    model.fit(train_pool, eval_set=val_pool)

    pkl_output = args.output or f"{prefix}_catboost.pkl"
    save_pickle(model, pkl_output)

    preds = model.predict_proba(X_te)
    test_ic = compute_test_ic(preds, y_te)
    print(
        f"trained=deriv_catboost family={prefix}({args.family_id}) "
        f"samples={metadata.train_size}/{metadata.val_size}/{metadata.test_size} "
        f"test_ic={float(test_ic):.4f} pkl={pkl_output}"
    )


if __name__ == "__main__":
    main()
