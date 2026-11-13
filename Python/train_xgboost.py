from __future__ import annotations

import argparse
from pathlib import Path

from train_common import compute_test_ic, export_onnx, load_split, save_pickle


def main() -> None:
    parser = argparse.ArgumentParser(description="Train an XGBoost ensemble member for MT5.")
    parser.add_argument("--csv", required=True)
    parser.add_argument("--output", default="xgboost_model.onnx")
    parser.add_argument("--pkl-output", default=None)
    parser.add_argument("--seq-len", type=int, default=60)
    parser.add_argument("--k", type=float, default=1.5)
    parser.add_argument("--vert", type=int, default=20)
    args = parser.parse_args()

    try:
        import xgboost as xgb
    except ImportError as exc:  # pragma: no cover
        raise SystemExit("xgboost is required for train_xgboost.py") from exc

    X_tr, X_va, X_te, y_tr, y_va, y_te, metadata = load_split(
        args.csv, seq_len=args.seq_len, k=args.k, vert=args.vert
    )

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

    pkl_output = args.pkl_output or str(Path(args.output).with_suffix(".pkl"))
    save_pickle(model, pkl_output)

    preds = model.predict_proba(X_te)
    test_ic = compute_test_ic(preds, y_te)
    print(
        f"trained=xgboost samples={metadata.train_size}/{metadata.val_size}/{metadata.test_size} "
        f"test_ic={float(test_ic):.4f} pkl={pkl_output}"
    )

    export_onnx(
        "xgboost",
        model,
        args.output,
        X_tr.shape[1],
        "xgboost_trading",
    )


if __name__ == "__main__":
    main()
