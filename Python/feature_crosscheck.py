from __future__ import annotations

import argparse
from typing import List

import numpy as np
import pandas as pd

from data_pipeline import add_calendar_features, build_feature_matrix


def feature_columns(frame: pd.DataFrame) -> List[str]:
    def sort_key(name: str) -> int:
        try:
            return int(name.split("_")[1])
        except (IndexError, ValueError):
            return 10**9
    return sorted([col for col in frame.columns if col.startswith("feature_")], key=sort_key)


def main() -> None:
    parser = argparse.ArgumentParser(description="Cross-check MQL5-exported features against Python recomputation.")
    parser.add_argument("--mql5-csv", required=True, help="CSV exported by TrainingDataExporter with feature columns enabled.")
    parser.add_argument("--threshold", type=float, default=1e-5)
    args = parser.parse_args()

    frame = pd.read_csv(args.mql5_csv)
    feat_cols = feature_columns(frame)
    if not feat_cols:
        raise SystemExit("No feature_* columns found. Re-export with InpExportFeatureVectors=true.")

    frame["date"] = pd.to_datetime(frame["date"])
    mae = []

    for symbol, group in frame.sort_values(["symbol", "date"]).groupby("symbol", sort=False):
        open_ = group["open"].to_numpy(dtype=np.float64)
        high = group["high"].to_numpy(dtype=np.float64)
        low = group["low"].to_numpy(dtype=np.float64)
        close = group["close"].to_numpy(dtype=np.float64)
        volume = group["volume"].to_numpy(dtype=np.float64)

        py_features = build_feature_matrix(open_, high, low, close, volume)
        py_features = add_calendar_features(py_features, pd.DatetimeIndex(group["date"]))
        mql_features = group[feat_cols].to_numpy(dtype=np.float64)
        shared_features = min(py_features.shape[1], mql_features.shape[1])
        if shared_features <= 0:
            raise SystemExit(
                f"Feature shape mismatch for {symbol}: python={py_features.shape} mql={mql_features.shape}"
            )
        mae.append(np.mean(np.abs(py_features[:, :shared_features] - mql_features[:, :shared_features]), axis=0))

    mean_mae = np.mean(np.stack(mae), axis=0)
    max_mae = float(np.max(mean_mae))
    print(f"feature_count={len(feat_cols)}")
    if len(feat_cols) > len(mean_mae):
        print(
            f"note=compared first {len(mean_mae)} shared OHLCV-derived features; "
            f"{len(feat_cols) - len(mean_mae)} exported MT5-only tick features were skipped"
        )
    print(f"max_mae={max_mae:.8f} threshold={args.threshold:.8f}")
    for idx, value in enumerate(mean_mae):
        print(f"feature_{idx:02d} mae={value:.8f}")

    if max_mae > args.threshold:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
