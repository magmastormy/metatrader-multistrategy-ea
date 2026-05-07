from __future__ import annotations

import argparse
import pickle
from pathlib import Path

import numpy as np
from scipy.stats import spearmanr

from data_pipeline import build_scaled_dataset_splits


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
    with open(pkl_output, "wb") as handle:
        pickle.dump(model, handle)

    preds = model.predict(X_te)
    test_ic, _ = spearmanr(preds[:, 2] - preds[:, 0], test[3])
    print(
        f"trained=lgbm samples={metadata.train_size}/{metadata.val_size}/{metadata.test_size} "
        f"test_ic={float(test_ic):.4f} pkl={pkl_output}"
    )

    try:
        import onnxmltools
        from onnxmltools.convert.common.data_types import FloatTensorType

        onnx_model = onnxmltools.convert_lightgbm(
            model,
            name="lgbm_trading",
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
