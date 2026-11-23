from __future__ import annotations

import argparse
import pickle
from pathlib import Path

from train_common import train_oof_stacker


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

    result = train_oof_stacker(
        args.csv,
        seq_len=args.seq_len,
        k=args.k,
        vert=args.vert,
        patchtst_onnx=args.patchtst_onnx,
        lgbm_pkl=args.lgbm_pkl,
        catboost_pkl=args.catboost_pkl,
        xgboost_pkl=args.xgboost_pkl,
    )

    bundle = {"ridge": result["ridge"], "scaler": result["scaler"]}
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("wb") as handle:
        pickle.dump(bundle, handle)

    ic = result["test_ic"]
    print("Test IC comparison:")
    print(f"  ONNX:     {ic['onnx']:.4f}")
    print(f"  LGBM:     {ic['lgbm']:.4f}")
    if ic["catboost"] is not None:
        print(f"  CatBoost: {ic['catboost']:.4f}")
    if ic["xgboost"] is not None:
        print(f"  XGBoost:  {ic['xgboost']:.4f}")
    print(f"  Stacker:  {ic['stacker']:.4f}")
    print(f"bundle={output}")


if __name__ == "__main__":
    main()
