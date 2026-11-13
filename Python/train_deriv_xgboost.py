from __future__ import annotations

import argparse

from data_pipeline import build_scaled_dataset_splits
from train_common import FAMILY_PREFIXES, adjust_seq_len_for_family, compute_test_ic, load_split, save_pickle


def main() -> None:
    parser = argparse.ArgumentParser(description="Train a family-specific XGBoost model for Deriv synthetic indices.")
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
        import xgboost as xgb
    except ImportError as exc:  # pragma: no cover
        raise SystemExit("xgboost is required for train_deriv_xgboost.py") from exc

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
    if args.family_id in (2, 5, 9):  # Step, MultiStep, SkewStep
        model = xgb.XGBClassifier(
            objective="multi:softprob",
            num_class=3,
            learning_rate=0.03,
            max_depth=6,
            n_estimators=1000,
            subsample=0.8,
            colsample_bytree=0.8,
            gamma=1.0,
            reg_alpha=0.5,
            reg_lambda=2.0,
            min_child_weight=50,
            early_stopping_rounds=50,
        )
    else:  # Default
        model = xgb.XGBClassifier(
            objective="multi:softprob",
            num_class=3,
            learning_rate=0.03,
            max_depth=6,
            n_estimators=1000,
            subsample=0.8,
            colsample_bytree=0.7,
            reg_alpha=0.1,
            reg_lambda=0.1,
            min_child_weight=50,
            early_stopping_rounds=50,
        )

    model.fit(
        X_tr,
        y_tr,
        eval_set=[(X_va, y_va)],
        verbose=100,
    )

    pkl_output = args.output or f"{prefix}_xgboost.pkl"
    save_pickle(model, pkl_output)

    preds = model.predict_proba(X_te)
    test_ic = compute_test_ic(preds, y_te)
    print(
        f"trained=deriv_xgboost family={prefix}({args.family_id}) "
        f"samples={metadata.train_size}/{metadata.val_size}/{metadata.test_size} "
        f"test_ic={float(test_ic):.4f} pkl={pkl_output}"
    )


if __name__ == "__main__":
    main()
