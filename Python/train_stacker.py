from __future__ import annotations

import argparse
import pickle
from pathlib import Path

import numpy as np
from scipy.special import softmax
from scipy.stats import spearmanr
from sklearn.linear_model import Ridge
from sklearn.model_selection import TimeSeriesSplit
from sklearn.preprocessing import StandardScaler

from data_pipeline import build_scaled_dataset_splits


def get_onnx_probs(path: str, X: np.ndarray) -> np.ndarray:
    import onnxruntime as ort

    sess = ort.InferenceSession(path)
    name = sess.get_inputs()[0].name
    logits = sess.run(None, {name: X.astype(np.float32)})[0]
    return softmax(logits, axis=1)


def main() -> None:
    parser = argparse.ArgumentParser(description="Train an OOF ridge stacker for ONNX + LightGBM + CatBoost + XGBoost outputs.")
    parser.add_argument("--csv", required=True)
    parser.add_argument("--patchtst-onnx", required=True)
    parser.add_argument("--lgbm-pkl", required=True)
    parser.add_argument("--catboost-pkl", default=None)
    parser.add_argument("--xgboost-pkl", default=None)
    parser.add_argument("--output", default="stacker.pkl")
    parser.add_argument("--seq-len", type=int, default=60)
    parser.add_argument("--k", type=float, default=1.5)
    parser.add_argument("--vert", type=int, default=20)
    args = parser.parse_args()

    train, val, test, _metadata = build_scaled_dataset_splits(
        args.csv,
        seq_len=args.seq_len,
        k=args.k,
        vertical_bars=args.vert,
    )

    X_all = np.concatenate([train[0], val[0]], axis=0)
    y_all = np.concatenate([train[1], val[1]], axis=0)
    r_all = np.concatenate([train[3], val[3]], axis=0)
    X_test = test[0]
    r_test = test[3]

    with open(args.lgbm_pkl, "rb") as handle:
        lgbm = pickle.load(handle)

    catboost = None
    if args.catboost_pkl is not None:
        with open(args.catboost_pkl, "rb") as handle:
            catboost = pickle.load(handle)

    xgboost = None
    if args.xgboost_pkl is not None:
        with open(args.xgboost_pkl, "rb") as handle:
            xgboost = pickle.load(handle)

    n_base = 3  # onnx + lgbm
    if catboost is not None:
        n_base += 1
    if xgboost is not None:
        n_base += 1
    n_cols = n_base * 3

    X_all_flat = X_all.reshape(len(X_all), -1)
    X_test_flat = X_test.reshape(len(X_test), -1)
    onnx_probs = get_onnx_probs(args.patchtst_onnx, X_all)
    lgbm_probs = lgbm.predict(X_all_flat)

    tscv = TimeSeriesSplit(n_splits=5, gap=20)
    meta_X = np.zeros((len(X_all), n_cols), dtype=np.float32)
    for _, val_idx in tscv.split(X_all):
        col = 0
        meta_X[val_idx, col:col + 3] = onnx_probs[val_idx]
        col += 3
        meta_X[val_idx, col:col + 3] = lgbm_probs[val_idx]
        col += 3
        if catboost is not None:
            catboost_probs = catboost.predict_proba(X_all_flat[val_idx])
            meta_X[val_idx, col:col + 3] = catboost_probs
            col += 3
        if xgboost is not None:
            xgboost_probs = xgboost.predict_proba(X_all_flat[val_idx])
            meta_X[val_idx, col:col + 3] = xgboost_probs
            col += 3

    scaler = StandardScaler().fit(meta_X)
    ridge = Ridge(alpha=1.0).fit(scaler.transform(meta_X), (y_all == 2).astype(float))

    bundle = {"ridge": ridge, "scaler": scaler}
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("wb") as handle:
        pickle.dump(bundle, handle)

    test_onnx = get_onnx_probs(args.patchtst_onnx, X_test)
    test_lgbm = lgbm.predict(X_test_flat)
    test_parts = [test_onnx, test_lgbm]
    if catboost is not None:
        test_parts.append(catboost.predict_proba(X_test_flat))
    if xgboost is not None:
        test_parts.append(xgboost.predict_proba(X_test_flat))
    stack_signal = ridge.predict(scaler.transform(np.hstack(test_parts)))

    print("Test IC comparison:")
    print(f"  ONNX:     {float(spearmanr(test_onnx[:, 2] - test_onnx[:, 0], r_test)[0]):.4f}")
    print(f"  LGBM:     {float(spearmanr(test_lgbm[:, 2] - test_lgbm[:, 0], r_test)[0]):.4f}")
    if catboost is not None:
        test_catboost = test_parts[2]
        print(f"  CatBoost: {float(spearmanr(test_catboost[:, 2] - test_catboost[:, 0], r_test)[0]):.4f}")
    if xgboost is not None:
        test_xgboost = test_parts[-1]
        print(f"  XGBoost:  {float(spearmanr(test_xgboost[:, 2] - test_xgboost[:, 0], r_test)[0]):.4f}")
    print(f"  Stacker:  {float(spearmanr(stack_signal, r_test)[0]):.4f}")
    print(f"bundle={output}")


if __name__ == "__main__":
    main()
