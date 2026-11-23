from __future__ import annotations

import argparse
import pickle
from pathlib import Path

from train_common import FAMILY_PREFIXES, adjust_seq_len_for_family, train_oof_stacker


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Train a family-specific OOF ridge stacker for Deriv synthetic indices."
    )
    parser.add_argument("--csv", required=True)
    parser.add_argument("--family-id", type=int, required=True, choices=range(18),
                        help="Deriv family ID (0-17)")
    parser.add_argument("--patchtst-onnx", required=True)
    parser.add_argument("--lgbm-pkl", required=True)
    parser.add_argument("--catboost-pkl", default=None)
    parser.add_argument("--xgboost-pkl", default=None)
    parser.add_argument("--output", default=None)
    parser.add_argument("--seq-len", type=int, default=60)
    parser.add_argument("--k", type=float, default=1.5)
    parser.add_argument("--vert", type=int, default=20)
    args = parser.parse_args()

    # Jump (3) and DEX (4) use longer sequences
    args.seq_len = adjust_seq_len_for_family(args.family_id, args.seq_len)

    prefix = FAMILY_PREFIXES[args.family_id]

    result = train_oof_stacker(
        args.csv,
        seq_len=args.seq_len,
        k=args.k,
        vert=args.vert,
        patchtst_onnx=args.patchtst_onnx,
        lgbm_pkl=args.lgbm_pkl,
        catboost_pkl=args.catboost_pkl,
        xgboost_pkl=args.xgboost_pkl,
        family_id=args.family_id,
    )

    bundle = {
        "ridge": result["ridge"],
        "scaler": result["scaler"],
        "family_id": args.family_id,
        "n_base_models": 2 + (args.catboost_pkl is not None) + (args.xgboost_pkl is not None),
    }
    output = Path(args.output or f"{prefix}_stacker.pkl")
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
    print(f"Family: {prefix} ({args.family_id})")
    print(f"bundle={output}")


if __name__ == "__main__":
    main()
