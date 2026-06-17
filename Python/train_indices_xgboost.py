from __future__ import annotations

import argparse
import pickle
from pathlib import Path

import numpy as np
from scipy.stats import spearmanr

from data_pipeline import build_scaled_dataset_splits, build_indices_features, get_asset_class_feature_count

ASSET_CLASS_NAME = "indices"
ASSET_CLASS_ID = 2


def main() -> None:
    parser = argparse.ArgumentParser(description="Train XGBoost model for Equity Indices (US30, US100, etc.).")
    parser.add_argument("--csv", required=True)
    parser.add_argument("--output", default=None)
    parser.add_argument("--seq-len", type=int, default=60)
    parser.add_argument("--k", type=float, default=1.5)
    parser.add_argument("--vert", type=int, default=20)
    args = parser.parse_args()

    try:
        import xgboost as xgb
    except ImportError as exc:
        raise SystemExit("xgboost is required for train_indices_xgboost.py") from exc

    train, val, test, metadata = build_scaled_dataset_splits(
        args.csv,
        seq_len=args.seq_len,
        k=args.k,
        vertical_bars=args.vert,
        asset_class=ASSET_CLASS_ID,
    )
    X_tr = train[0].reshape(len(train[0]), -1)
    X_va = val[0].reshape(len(val[0]), -1)
    X_te = test[0].reshape(len(test[0]), -1)
    y_tr, y_va, y_te = train[1], val[1], test[1]

    # Indices: mean-reversion detection with moderate depth
    model = xgb.XGBClassifier(
        n_estimators=600,
        learning_rate=0.025,
        max_depth=5,
        subsample=0.8,
        colsample_bytree=0.7,
        objective="multi:softprob",
        num_class=3,
        eval_metric="mlogloss",
        early_stopping_rounds=50,
        verbosity=0,
    )
    model.fit(X_tr, y_tr, eval_set=[(X_va, y_va)], verbose=False)

    pkl_output = args.output or f"{ASSET_CLASS_NAME}_xgboost.pkl"
    with open(pkl_output, "wb") as handle:
        pickle.dump(model, handle)

    preds = model.predict_proba(X_te)
    test_ic, _ = spearmanr(preds[:, 2] - preds[:, 0], test[3])
    print(
        f"trained=indices_xgboost asset_class={ASSET_CLASS_NAME}({ASSET_CLASS_ID}) "
        f"samples={metadata.train_size}/{metadata.val_size}/{metadata.test_size} "
        f"test_ic={float(test_ic):.4f} pkl={pkl_output}"
    )


if __name__ == "__main__":
    main()
