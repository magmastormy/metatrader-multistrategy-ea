from __future__ import annotations

import argparse
from pathlib import Path

from train_common import compute_test_ic, export_onnx, load_split, save_pickle


def main() -> None:
    parser = argparse.ArgumentParser(description="Train a CatBoost ensemble member for MT5.")
    parser.add_argument("--csv", required=True)
    parser.add_argument("--output", default="catboost_model.onnx")
    parser.add_argument("--pkl-output", default=None)
    parser.add_argument("--seq-len", type=int, default=60)
    parser.add_argument("--k", type=float, default=1.5)
    parser.add_argument("--vert", type=int, default=20)
    args = parser.parse_args()

    try:
        from catboost import CatBoostClassifier, Pool
    except ImportError as exc:  # pragma: no cover
        raise SystemExit("catboost is required for train_catboost.py") from exc

    X_tr, X_va, X_te, y_tr, y_va, y_te, metadata = load_split(
        args.csv, seq_len=args.seq_len, k=args.k, vert=args.vert
    )

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

    pkl_output = args.pkl_output or str(Path(args.output).with_suffix(".pkl"))
    save_pickle(model, pkl_output)

    preds = model.predict_proba(X_te)
    test_ic = compute_test_ic(preds, y_te)
    print(
        f"trained=catboost samples={metadata.train_size}/{metadata.val_size}/{metadata.test_size} "
        f"test_ic={float(test_ic):.4f} pkl={pkl_output}"
    )

    export_onnx(
        "catboost",
        model,
        args.output,
        X_tr.shape[1],
        "catboost_trading",
    )


if __name__ == "__main__":
    main()
