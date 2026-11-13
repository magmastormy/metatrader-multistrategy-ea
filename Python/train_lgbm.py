from __future__ import annotations

import argparse
from pathlib import Path

from train_common import compute_test_ic, export_onnx, load_split, save_pickle


def main() -> None:
    parser = argparse.ArgumentParser(description="Train a LightGBM ensemble member for MT5.")
    parser.add_argument("--csv", required=True)
    parser.add_argument("--output", default="lgbm_model.onnx")
    parser.add_argument("--pkl-output", default=None)
    parser.add_argument("--seq-len", type=int, default=60)
    parser.add_argument("--k", type=float, default=1.5)
    parser.add_argument("--vert", type=int, default=20)
    args = parser.parse_args()

    try:
        import lightgbm as lgb
    except ImportError as exc:  # pragma: no cover
        raise SystemExit("lightgbm is required for train_lgbm.py") from exc

    X_tr, X_va, X_te, y_tr, y_va, y_te, metadata = load_split(
        args.csv, seq_len=args.seq_len, k=args.k, vert=args.vert
    )

    model = lgb.train(
        {
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
        },
        lgb.Dataset(X_tr, label=y_tr),
        valid_sets=[lgb.Dataset(X_va, label=y_va)],
        num_boost_round=1000,
        callbacks=[lgb.early_stopping(50)],
    )

    pkl_output = args.pkl_output or str(Path(args.output).with_suffix(".pkl"))
    save_pickle(model, pkl_output)

    preds = model.predict(X_te)
    test_ic = compute_test_ic(preds, y_te)
    print(
        f"trained=lgbm samples={metadata.train_size}/{metadata.val_size}/{metadata.test_size} "
        f"test_ic={float(test_ic):.4f} pkl={pkl_output}"
    )

    export_onnx(
        "lightgbm",
        model,
        args.output,
        X_tr.shape[1],
        "lgbm_trading",
    )


if __name__ == "__main__":
    main()
