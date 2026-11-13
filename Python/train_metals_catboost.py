from __future__ import annotations

import argparse

from train_common import ASSET_CLASS_IDS, ASSET_CLASS_NAMES, compute_test_ic, load_split, save_pickle


ASSET_CLASS_NAME = "metals"
ASSET_CLASS_ID = ASSET_CLASS_IDS[ASSET_CLASS_NAME]


def main() -> None:
    parser = argparse.ArgumentParser(description="Train CatBoost + XGBoost models for Metals (Gold/Silver).")
    parser.add_argument("--csv", required=True)
    parser.add_argument("--output-dir", default=".")
    parser.add_argument("--seq-len", type=int, default=60)
    parser.add_argument("--k", type=float, default=1.5)
    parser.add_argument("--vert", type=int, default=20)
    args = parser.parse_args()

    try:
        import catboost as cb
    except ImportError as exc:
        raise SystemExit("catboost is required for train_metals_catboost.py") from exc

    try:
        import xgboost as xgb
    except ImportError as exc:
        raise SystemExit("xgboost is required for train_metals_catboost.py") from exc

    X_tr, X_va, X_te, y_tr, y_va, y_te, metadata = load_split(
        args.csv,
        seq_len=args.seq_len,
        k=args.k,
        vert=args.vert,
        asset_class=ASSET_CLASS_ID,
    )

    output_dir = args.output_dir

    # CatBoost: deeper trees for breakout detection
    cb_model = cb.CatBoostClassifier(
        iterations=600,
        learning_rate=0.03,
        depth=6,
        l2_leaf_reg=3.0,
        loss_function="MultiClass",
        classes_count=3,
        verbose=0,
        early_stopping_rounds=50,
    )
    cb_model.fit(X_tr, y_tr, eval_set=(X_va, y_va))

    cb_path = f"{output_dir}/{ASSET_CLASS_NAME}_catboost.pkl"
    save_pickle(cb_model, cb_path)

    cb_preds = cb_model.predict_proba(X_te)
    cb_ic = compute_test_ic(cb_preds, y_te)
    print(
        f"trained=metals_catboost asset_class={ASSET_CLASS_NAME}({ASSET_CLASS_ID}) "
        f"samples={metadata.train_size}/{metadata.val_size}/{metadata.test_size} "
        f"test_ic={float(cb_ic):.4f} pkl={cb_path}"
    )

    # XGBoost: breakout probability with higher max depth
    xgb_model = xgb.XGBClassifier(
        n_estimators=500,
        learning_rate=0.03,
        max_depth=6,
        subsample=0.8,
        colsample_bytree=0.7,
        objective="multi:softprob",
        num_class=3,
        eval_metric="mlogloss",
        early_stopping_rounds=50,
        verbosity=0,
    )
    xgb_model.fit(X_tr, y_tr, eval_set=[(X_va, y_va)], verbose=False)

    xgb_path = f"{output_dir}/{ASSET_CLASS_NAME}_xgboost.pkl"
    save_pickle(xgb_model, xgb_path)

    xgb_preds = xgb_model.predict_proba(X_te)
    xgb_ic = compute_test_ic(xgb_preds, y_te)
    print(
        f"trained=metals_xgboost asset_class={ASSET_CLASS_NAME}({ASSET_CLASS_ID}) "
        f"samples={metadata.train_size}/{metadata.val_size}/{metadata.test_size} "
        f"test_ic={float(xgb_ic):.4f} pkl={xgb_path}"
    )


if __name__ == "__main__":
    main()
