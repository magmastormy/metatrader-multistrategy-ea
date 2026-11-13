from __future__ import annotations

import argparse

from train_common import ASSET_CLASS_IDS, ASSET_CLASS_NAMES, compute_test_ic, load_split, save_pickle


ASSET_CLASS_NAME = "indices"
ASSET_CLASS_ID = ASSET_CLASS_IDS[ASSET_CLASS_NAME]


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

    X_tr, X_va, X_te, y_tr, y_va, y_te, metadata = load_split(
        args.csv,
        seq_len=args.seq_len,
        k=args.k,
        vert=args.vert,
        asset_class=ASSET_CLASS_ID,
    )

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
    save_pickle(model, pkl_output)

    preds = model.predict_proba(X_te)
    test_ic = compute_test_ic(preds, y_te)
    print(
        f"trained=indices_xgboost asset_class={ASSET_CLASS_NAME}({ASSET_CLASS_ID}) "
        f"samples={metadata.train_size}/{metadata.val_size}/{metadata.test_size} "
        f"test_ic={float(test_ic):.4f} pkl={pkl_output}"
    )


if __name__ == "__main__":
    main()
