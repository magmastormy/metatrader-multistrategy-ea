from __future__ import annotations

import argparse
import pickle
from pathlib import Path

import numpy as np
from scipy.stats import spearmanr

from data_pipeline import build_scaled_dataset_splits


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

    train, val, test, metadata = build_scaled_dataset_splits(
        args.csv,
        seq_len=args.seq_len,
        k=args.k,
        vertical_bars=args.vert,
    )
    X_tr = train[0].reshape(len(train[0]), -1)
    X_va = val[0].reshape(len(val[0]), -1)
    X_te = test[0].reshape(len(test[0]), -1)
    y_tr, y_va, y_te = train[1], val[1], test[1]

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
    with open(pkl_output, "wb") as handle:
        pickle.dump(model, handle)

    preds = model.predict_proba(X_te)
    test_ic, _ = spearmanr(preds[:, 2] - preds[:, 0], test[3])
    print(
        f"trained=xgboost samples={metadata.train_size}/{metadata.val_size}/{metadata.test_size} "
        f"test_ic={float(test_ic):.4f} pkl={pkl_output}"
    )

    try:
        import onnxmltools
        from onnxmltools.convert.common.data_types import FloatTensorType

        onnx_model = onnxmltools.convert_xgboost(
            model,
            name="xgboost_trading",
            initial_types=[("float_input", FloatTensorType([None, X_tr.shape[1]]))],
            target_opset=12,
        )
        Path(args.output).parent.mkdir(parents=True, exist_ok=True)
        onnxmltools.utils.save_model(onnx_model, args.output)
        print(f"onnx={args.output}")
    except ImportError:
        print("onnxmltools not installed; skipped ONNX export")


if __name__ == "__main__":
    main()
