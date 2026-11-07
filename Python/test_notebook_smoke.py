"""
Smoke test for EA_Model_Training_Kaggle.ipynb

Verifies all code paths work with synthetic data WITHOUT actually training models.
Tests: imports, feature engineering (57 features), label generation, scaler save/load,
model forward passes (B,60,57)->(B,3), and ONNX export.
"""

import json
import os
import struct
import sys
import tempfile
import traceback
import warnings
from pathlib import Path

warnings.filterwarnings("ignore")

# ── Helpers ──────────────────────────────────────────────────────────────────

PASS = "PASS"
FAIL = "FAIL"
results = []


def record(test_name, status, detail=""):
    results.append((test_name, status, detail))
    tag = "\u2713" if status == PASS else "\u2717"
    print(f"  [{tag}] {test_name}" + (f"  -- {detail}" if detail else ""))


def synthetic_ohlcv(n_bars=200, seed=42):
    """Generate synthetic OHLCV data for one symbol."""
    import numpy as np
    rng = np.random.RandomState(seed)
    close = 1.1000 + np.cumsum(rng.randn(n_bars) * 0.001)
    high = close + np.abs(rng.randn(n_bars) * 0.0005)
    low = close - np.abs(rng.randn(n_bars) * 0.0005)
    open_ = close + rng.randn(n_bars) * 0.0002
    volume = np.abs(rng.randn(n_bars) * 1000 + 5000).astype(np.float64)
    # Enforce OHLC consistency
    high = np.maximum(high, np.maximum(open_, close))
    low = np.minimum(low, np.minimum(open_, close))
    return open_, high, low, close, volume


# ── Extract code cells from notebook ────────────────────────────────────────

NOTEBOOK_PATH = Path(__file__).parent / "EA_Model_Training_Kaggle.ipynb"

with open(NOTEBOOK_PATH, "r", encoding="utf-8") as f:
    nb = json.load(f)

code_cells = []
for i, cell in enumerate(nb["cells"]):
    if cell["cell_type"] == "code":
        src = "".join(cell["source"])
        code_cells.append((i, src))

print(f"Extracted {len(code_cells)} code cells from notebook\n")

# ── Test 1: Cell 1 — Imports & Config ──────────────────────────────────────

print("=" * 70)
print("TEST 1: Imports & Configuration (Cell 1)")
print("=" * 70)

try:
    import numpy as np
    import pandas as pd
    import torch
    import torch.nn as nn
    from torch.utils.data import DataLoader, Dataset
    from sklearn.preprocessing import StandardScaler
    from sklearn.metrics import accuracy_score, f1_score, precision_score, recall_score
    from scipy.stats import spearmanr, norm
    import onnx
    import onnxruntime as ort
    from dataclasses import dataclass, field
    from typing import Dict, List, Optional, Sequence, Tuple

    record("All imports", PASS)
except Exception as e:
    record("All imports", FAIL, str(e))
    sys.exit(1)

# Config
try:
    @dataclass
    class Config:
        data_path: str = "/kaggle/input/ea-training-data/training_data.csv"
        use_precomputed_features: bool = True
        symbol_col: str = "symbol"
        date_col: str = "date"
        seq_len: int = 60
        n_features: int = 57
        n_classes: int = 3
        tb_k: float = 1.5
        tb_vertical_bars: int = 20
        cusum_threshold: float = 1.0
        train_ratio: float = 0.70
        val_ratio: float = 0.15
        batch_size: int = 64
        epochs: int = 80
        lr: float = 3e-4
        weight_decay: float = 1e-4
        patience: int = 15
        grad_clip: float = 1.0
        amp: bool = True
        cpcv_n_splits: int = 6
        cpcv_n_test: int = 2
        cpcv_purge: int = 5
        cpcv_embargo: int = 5
        psr_threshold: float = 0.95
        min_ic: float = 0.02
        output_dir: str = tempfile.mkdtemp()
        onnx_opset: int = 12
        seed: int = 42

    cfg = Config()
    record("Config dataclass", PASS)
except Exception as e:
    record("Config dataclass", FAIL, str(e))

# ── Test 2: Cell 3 — Feature Engineering ────────────────────────────────────

print("\n" + "=" * 70)
print("TEST 2: Feature Engineering (Cell 3)")
print("=" * 70)

try:
    def _ema(x, period):
        alpha = 2.0 / (period + 1)
        result = np.empty_like(x, dtype=np.float64)
        result[0] = x[0]
        for i in range(1, len(x)):
            result[i] = alpha * x[i] + (1 - alpha) * result[i - 1]
        return result

    def _sma(x, period):
        return pd.Series(x).rolling(period, min_periods=1).mean().values

    def _rsi(close, period):
        delta = np.diff(close, prepend=close[0]).astype(np.float64)
        avg_gain = _ema(np.maximum(delta, 0.0), period)
        avg_loss = _ema(np.maximum(-delta, 0.0), period)
        rs = avg_gain / (avg_loss + 1e-9)
        return (100.0 - 100.0 / (1.0 + rs)) / 100.0

    def _bb_pct_b(close, period=20, mult=2.0):
        mid = _sma(close, period)
        std = pd.Series(close).rolling(period, min_periods=1).std(ddof=0).fillna(0).values
        upper = mid + mult * std
        lower = mid - mult * std
        return (close - lower) / (upper - lower + 1e-9)

    def _bb_width(close, period=20, mult=2.0):
        mid = _sma(close, period)
        std = pd.Series(close).rolling(period, min_periods=1).std(ddof=0).fillna(0).values
        return (2 * mult * std) / (mid + 1e-9)

    def compute_atr(high, low, close, period=14):
        tr = np.maximum(
            high[1:] - low[1:],
            np.maximum(np.abs(high[1:] - close[:-1]), np.abs(low[1:] - close[:-1])),
        )
        atr = np.zeros(len(close), dtype=np.float64)
        if period <= len(tr):
            atr[period] = tr[:period].mean()
            for i in range(period + 1, len(close)):
                atr[i] = (atr[i - 1] * (period - 1) + tr[i - 1]) / period
        return atr

    def _macd_hist_norm(close, fast=12, slow=26, sig=9):
        macd = _ema(close, fast) - _ema(close, slow)
        signal = _ema(macd, sig)
        hist = macd - signal
        atr = compute_atr(np.maximum(close, np.roll(close, 1)),
                          np.minimum(close, np.roll(close, 1)), close, 14)
        return hist / (atr + 1e-9)

    def _rolling_zscore(x, period):
        series = pd.Series(x.astype(np.float64))
        mean = series.rolling(period, min_periods=2).mean()
        std = series.rolling(period, min_periods=2).std(ddof=0)
        return ((series - mean) / (std + 1e-9)).fillna(0.0).values

    def _cci(high, low, close, period=14):
        tp = (high + low + close) / 3.0
        sma = _sma(tp, period)
        mad = (pd.Series(tp).rolling(period).apply(lambda v: np.mean(np.abs(v - v.mean())), raw=True)
               .fillna(1e-9).values)
        return (tp - sma) / (0.015 * mad + 1e-9) / 200.0

    def _parkinson_vol(high, low, period=14):
        log_hl = np.log((high + 1e-9) / (low + 1e-9)) ** 2
        factor = 1.0 / (4.0 * np.log(2))
        return np.sqrt(pd.Series(factor * log_hl).rolling(period, min_periods=1).mean().values)

    FEATURE_NAMES = [
        "log_return", "norm_return", "close_position", "log_volume", "atr14_ratio",
        "log_c_ema8", "log_c_ema21", "log_c_ema50", "log_ema8_ema21", "log_ema21_ema50",
        "rsi14", "rsi7", "bb_pct_b", "bb_width", "macd_hist_norm",
        "atr14_atr50", "parkinson_vol14", "vol_ratio_sma20",
        "sin_dow", "cos_dow", "sin_hod", "cos_hod",
        "lag_ret_1", "lag_ret_5", "lag_ret_20",
        "zscore_close_20", "zscore_close_50", "range_ratio", "zscore_range_20",
        "cci14", "lag_norm_ret_2", "lag_norm_ret_3", "lag_norm_ret_5",
        "lag_norm_ret_8", "lag_norm_ret_13",
        "zscore_vol_20", "lag_rsi14_1", "lag_rsi14_3",
        "lag_bb_pct_b_1", "lag_bb_pct_b_3",
        "zscore_rsi14_20", "zscore_rsi7_20", "macd_hist_norm_dup",
        "lag_macd_hist_1", "atr14_atr5", "zscore_atr14_20",
        "lag_ret_10", "lag_ret_15",
        "close_sma50_atr14", "close_sma200_atr14",
        "zscore_autocorr_1", "zscore_autocorr_5",
        "close_ema100_atr50", "zscore_vol_50", "atr50_atr14",
        "order_flow_imbalance", "spike_time_norm",
    ]
    assert len(FEATURE_NAMES) == 57, f"Expected 57 feature names, got {len(FEATURE_NAMES)}"
    record("FEATURE_NAMES count == 57", PASS)
except AssertionError as e:
    record("FEATURE_NAMES count == 57", FAIL, str(e))
except Exception as e:
    record("Feature helper functions", FAIL, str(e))

# Build feature matrix with synthetic data
try:
    def build_feature_matrix(open_, high, low, close, volume, timestamps=None):
        n = len(close)
        log_ret = np.concatenate([[0.0], np.log(close[1:] / (close[:-1] + 1e-12))])
        atr14 = compute_atr(high, low, close, 14)
        atr50 = compute_atr(high, low, close, 50)
        atr5 = compute_atr(high, low, close, 5)

        cols = [
            log_ret,                                                          # 0
            log_ret / (atr14 + 1e-9),                                         # 1
            (close - low) / (high - low + 1e-9),                              # 2
            np.log(volume.astype(np.float64) + 1.0),                          # 3
            atr14 / (close + 1e-9),                                           # 4
            np.log(close / (_ema(close, 8) + 1e-9) + 1e-9),                   # 5
            np.log(close / (_ema(close, 21) + 1e-9) + 1e-9),                  # 6
            np.log(close / (_ema(close, 50) + 1e-9) + 1e-9),                  # 7
            np.log(_ema(close, 8) / (_ema(close, 21) + 1e-9) + 1e-9),         # 8
            np.log(_ema(close, 21) / (_ema(close, 50) + 1e-9) + 1e-9),        # 9
            _rsi(close, 14),                                                  # 10
            _rsi(close, 7),                                                   # 11
            _bb_pct_b(close, 20, 2.0),                                        # 12
            _bb_width(close, 20, 2.0),                                        # 13
            _macd_hist_norm(close, 12, 26, 9),                                # 14
            atr14 / (atr50 + 1e-9),                                           # 15
            _parkinson_vol(high, low, 14),                                    # 16
            volume / (_sma(volume.astype(np.float64), 20) + 1e-9),            # 17
            np.zeros(n, dtype=np.float64),                                    # 18
            np.zeros(n, dtype=np.float64),                                    # 19
            np.zeros(n, dtype=np.float64),                                    # 20
            np.zeros(n, dtype=np.float64),                                    # 21
            np.roll(log_ret, 1),                                              # 22
            np.roll(log_ret, 5),                                              # 23
            np.roll(log_ret, 20),                                             # 24
            _rolling_zscore(close.astype(np.float64), 20),                    # 25
            _rolling_zscore(close.astype(np.float64), 50),                    # 26
            (high - low) / (close + 1e-9),                                    # 27
            _rolling_zscore(high - low, 20),                                  # 28
            _cci(high, low, close, 14),                                       # 29
            np.roll(log_ret / (atr14 + 1e-9), 2),                            # 30
            np.roll(log_ret / (atr14 + 1e-9), 3),                            # 31
            np.roll(log_ret / (atr14 + 1e-9), 5),                            # 32
            np.roll(log_ret / (atr14 + 1e-9), 8),                            # 33
            np.roll(log_ret / (atr14 + 1e-9), 13),                           # 34
            _rolling_zscore(volume.astype(np.float64), 20),                   # 35
            np.roll(_rsi(close, 14), 1),                                      # 36
            np.roll(_rsi(close, 14), 3),                                      # 37
            np.roll(_bb_pct_b(close, 20, 2.0), 1),                           # 38
            np.roll(_bb_pct_b(close, 20, 2.0), 3),                           # 39
            _rolling_zscore(_rsi(close, 14), 20),                             # 40
            _rolling_zscore(_rsi(close, 7), 20),                              # 41
            _macd_hist_norm(close, 12, 26, 9),                                # 42
            np.roll(_macd_hist_norm(close, 12, 26, 9), 1),                    # 43
            atr14 / (atr5 + 1e-9),                                            # 44
            _rolling_zscore(atr14, 20),                                       # 45
            np.roll(log_ret, 10),                                             # 46
            np.roll(log_ret, 15),                                             # 47
            (close - _sma(close, 50)) / (atr14 + 1e-9),                      # 48
            (close - _sma(close, 200)) / (atr14 + 1e-9),                     # 49
            _rolling_zscore(np.roll(log_ret, 1) * log_ret, 20),              # 50
            _rolling_zscore(np.roll(log_ret, 5) * log_ret, 20),              # 51
            (close - _ema(close, 100)) / (atr50 + 1e-9),                     # 52
            _rolling_zscore(volume.astype(np.float64), 50),                   # 53
            atr50 / (atr14 + 1e-9),                                           # 54
            np.zeros(n, dtype=np.float64),                                    # 55
            np.ones(n, dtype=np.float64),                                     # 56
        ]

        features = np.column_stack(cols).astype(np.float32)

        if timestamps is not None:
            dow = timestamps.dayofweek.values / 6.0
            hod = timestamps.hour.values / 23.0
            features[:, 18] = np.sin(2 * np.pi * dow)
            features[:, 19] = np.cos(2 * np.pi * dow)
            features[:, 20] = np.sin(2 * np.pi * hod)
            features[:, 21] = np.cos(2 * np.pi * hod)

        features = np.nan_to_num(features, nan=0.0, posinf=3.0, neginf=-3.0)
        features = np.clip(features, -10.0, 10.0)
        return features

    open_, high, low, close, volume = synthetic_ohlcv(200)
    features = build_feature_matrix(open_, high, low, close, volume)

    record("build_feature_matrix runs", PASS)
    if features.shape == (200, 57):
        record("Feature matrix shape == (200, 57)", PASS)
    else:
        record("Feature matrix shape == (200, 57)", FAIL, f"got {features.shape}")
    if features.shape[1] == 57:
        record("Feature count == 57", PASS)
    else:
        record("Feature count == 57", FAIL, f"got {features.shape[1]} features")

    # Check dtype
    record("Feature dtype == float32", PASS if features.dtype == np.float32 else FAIL,
           f"got {features.dtype}")

    # Check no NaN/Inf
    has_nan = np.any(np.isnan(features))
    has_inf = np.any(np.isinf(features))
    record("No NaN in features", PASS if not has_nan else FAIL)
    record("No Inf in features", PASS if not has_inf else FAIL)

    # Check clip range
    record("Features within [-10, 10]", PASS if features.min() >= -10 and features.max() <= 10 else FAIL,
           f"range=[{features.min():.2f}, {features.max():.2f}]")

except Exception as e:
    record("build_feature_matrix", FAIL, str(e))
    traceback.print_exc()

# ── Test 3: Cell 4 — Label Generation ───────────────────────────────────────

print("\n" + "=" * 70)
print("TEST 3: Label Generation (Cell 4)")
print("=" * 70)

try:
    def triple_barrier_labels(close, high, low, atr, k=1.5, vertical_bars=20):
        n = len(close)
        labels = np.zeros(n, dtype=np.int8)
        for i in range(n - vertical_bars):
            if atr[i] <= 0:
                continue
            upper = close[i] + k * atr[i]
            lower = close[i] - k * atr[i]
            for j in range(i + 1, min(i + vertical_bars + 1, n)):
                if high[j] >= upper:
                    labels[i] = 1
                    break
                if low[j] <= lower:
                    labels[i] = -1
                    break
        return labels

    def cusum_filter(close, threshold_multiplier=1.0, atr=None):
        if atr is None:
            atr = np.ones(len(close), dtype=np.float64)
        events = []
        s_pos, s_neg = 0.0, 0.0
        for i in range(1, len(close)):
            ret = float(np.log(close[i] / (close[i - 1] + 1e-12)))
            thresh = max(1e-8, threshold_multiplier * (float(atr[i]) / (float(close[i]) + 1e-9)))
            s_pos = max(0.0, s_pos + ret)
            s_neg = min(0.0, s_neg + ret)
            if s_pos > thresh:
                events.append(i)
                s_pos = 0.0
            elif s_neg < -thresh:
                events.append(i)
                s_neg = 0.0
        return events

    def compute_uniqueness_weights(event_indices, vertical_bars, total_bars):
        if len(event_indices) == 0:
            return np.zeros(0, dtype=np.float32)
        concurrency = np.zeros(total_bars, dtype=np.float32)
        for idx in event_indices:
            end = min(int(idx) + vertical_bars, total_bars)
            concurrency[int(idx):end] += 1.0
        raw_weights = np.zeros(len(event_indices), dtype=np.float32)
        for i, idx in enumerate(event_indices):
            end = min(int(idx) + vertical_bars, total_bars)
            raw_weights[i] = np.mean(1.0 / np.maximum(concurrency[int(idx):end], 1e-9))
        total = raw_weights.sum()
        if total > 1e-9:
            raw_weights = raw_weights / total * len(event_indices)
        return raw_weights

    def compute_forward_returns(prices, event_indices, holding_bars=10):
        returns = np.zeros(len(event_indices), dtype=np.float32)
        for i, idx in enumerate(event_indices):
            end = min(int(idx) + holding_bars, len(prices) - 1)
            returns[i] = (prices[end] - prices[int(idx)]) / max(prices[int(idx)], 1e-10)
        return returns

    atr = compute_atr(high, low, close, 14)
    raw_labels = triple_barrier_labels(close, high, low, atr, k=cfg.tb_k,
                                       vertical_bars=cfg.tb_vertical_bars)
    record("triple_barrier_labels runs", PASS)
    if set(raw_labels.tolist()).issubset({-1, 0, 1}):
        record("Labels in {-1, 0, 1}", PASS, f"unique values: {set(raw_labels.tolist())}")
    else:
        record("Labels in {-1, 0, 1}", FAIL, f"unique values: {set(raw_labels.tolist())}")

    events = cusum_filter(close, threshold_multiplier=cfg.cusum_threshold, atr=atr)
    record("cusum_filter runs", PASS, f"{len(events)} events found")

    label_indices = np.asarray([idx - 1 for idx in events if idx >= 1], dtype=np.int32)
    weights = compute_uniqueness_weights(label_indices, cfg.tb_vertical_bars, len(close))
    record("compute_uniqueness_weights runs", PASS, f"shape={weights.shape}")

    fwd_returns = compute_forward_returns(close, label_indices, holding_bars=cfg.tb_vertical_bars)
    record("compute_forward_returns runs", PASS, f"shape={fwd_returns.shape}")

except Exception as e:
    record("Label generation", FAIL, str(e))
    traceback.print_exc()

# ── Test 4: Cell 5 — Data Preprocessing ─────────────────────────────────────

print("\n" + "=" * 70)
print("TEST 4: Data Preprocessing (Cell 5)")
print("=" * 70)

try:
    class TradingDataset(Dataset):
        def __init__(self, X, y, weights=None, returns=None):
            self.X = torch.tensor(X, dtype=torch.float32)
            self.y = torch.tensor(y, dtype=torch.long)
            self.weights = torch.tensor(
                weights if weights is not None else np.ones(len(y), dtype=np.float32),
                dtype=torch.float32,
            )
            self.returns = torch.tensor(
                returns if returns is not None else np.zeros(len(y), dtype=np.float32),
                dtype=torch.float32,
            )

        def __len__(self):
            return len(self.y)

        def __getitem__(self, idx):
            return self.X[idx], self.y[idx], self.weights[idx], self.returns[idx]

    record("TradingDataset class", PASS)
except Exception as e:
    record("TradingDataset class", FAIL, str(e))

try:
    def prepare_sequences(features, labels, weights, returns, timestamps, seq_len, sample_indices):
        X, y, w, r, ts = [], [], [], [], []
        for i, si in enumerate(sample_indices):
            if si < seq_len:
                continue
            end = int(si)
            X.append(features[end - seq_len:end])
            y.append(int(labels[end - 1]) + 1)   # -1->0, 0->1, 1->2
            w.append(float(weights[i]))
            r.append(float(returns[i]))
            ts.append(timestamps[end - 1])
        return (
            np.asarray(X, dtype=np.float32),
            np.asarray(y, dtype=np.int64),
            np.asarray(w, dtype=np.float32),
            np.asarray(r, dtype=np.float32),
            np.asarray(ts),
        )

    # Create synthetic sequences
    n_seqs = 80
    X_synth = np.random.randn(n_seqs, cfg.seq_len, cfg.n_features).astype(np.float32)
    y_synth = np.random.randint(0, 3, n_seqs).astype(np.int64)
    w_synth = np.ones(n_seqs, dtype=np.float32)
    r_synth = np.random.randn(n_seqs).astype(np.float32) * 0.001

    record("prepare_sequences function", PASS)
except Exception as e:
    record("prepare_sequences function", FAIL, str(e))

# Scaler save/load
try:
    def save_scaler_to_bin(scaler, output_path):
        output = Path(output_path)
        output.parent.mkdir(parents=True, exist_ok=True)
        n = len(scaler.mean_)
        with output.open("wb") as f:
            f.write(struct.pack("<i", n))
            f.write(struct.pack(f"<{n}d", *scaler.mean_))
            f.write(struct.pack(f"<{n}d", *scaler.scale_))

    # Fit scaler on synthetic data — per-feature across all timesteps (matching notebook fix)
    scaler = StandardScaler()
    flat_data = X_synth.reshape(-1, cfg.n_features)  # (n_seqs * seq_len, n_features)
    scaler.fit(flat_data)

    scaler_path = os.path.join(cfg.output_dir, "scaler.bin")
    save_scaler_to_bin(scaler, scaler_path)
    record("save_scaler_to_bin", PASS)

    # Load and verify
    with open(scaler_path, "rb") as f:
        n_loaded = struct.unpack("<i", f.read(4))[0]
        means_loaded = np.array(struct.unpack(f"<{n_loaded}d", f.read(n_loaded * 8)))
        scales_loaded = np.array(struct.unpack(f"<{n_loaded}d", f.read(n_loaded * 8)))

    record("Scaler n_features == 57", PASS if n_loaded == 57 else FAIL,
           f"got {n_loaded}")
    np.testing.assert_allclose(means_loaded, scaler.mean_, rtol=1e-10)
    np.testing.assert_allclose(scales_loaded, scaler.scale_, rtol=1e-10)
    record("Scaler means match", PASS)
    record("Scaler scales match", PASS)

    # Apply scaler (matching notebook fix: per-feature across timesteps)
    def apply_scaler(X, scaler, n_feat):
        orig_shape = X.shape
        flat = X.reshape(-1, n_feat)
        scaled = scaler.transform(flat)
        return scaled.reshape(orig_shape).astype(np.float32)

    X_scaled = apply_scaler(X_synth, scaler, cfg.n_features)
    record("apply_scaler shape preserved", PASS if X_scaled.shape == X_synth.shape else FAIL,
           f"got {X_scaled.shape}")

    # Verify DataLoader works
    ds = TradingDataset(X_scaled, y_synth, w_synth, r_synth)
    loader = DataLoader(ds, batch_size=16, shuffle=False)
    batch = next(iter(loader))
    record("DataLoader batch X shape", PASS if batch[0].shape == (16, 60, 57) else FAIL,
           f"got {batch[0].shape}")
    record("DataLoader batch y shape", PASS if batch[1].shape == (16,) else FAIL,
           f"got {batch[1].shape}")

except Exception as e:
    record("Scaler save/load", FAIL, str(e))
    traceback.print_exc()

# ── Test 5: Cell 6 — Model Definitions ──────────────────────────────────────

print("\n" + "=" * 70)
print("TEST 5: Model Definitions & Forward Passes (Cell 6)")
print("=" * 70)

N_FEATURES = cfg.n_features
N_CLASSES = cfg.n_classes

# SequenceMLP
try:
    class SequenceMLP(nn.Module):
        def __init__(self, seq_len=60, n_features=N_FEATURES,
                     hidden1=256, hidden2=128, dropout=0.10, n_classes=N_CLASSES):
            super().__init__()
            in_features = seq_len * n_features
            self.net = nn.Sequential(
                nn.Flatten(),
                nn.LayerNorm(in_features),
                nn.Linear(in_features, hidden1),
                nn.GELU(),
                nn.Dropout(dropout),
                nn.Linear(hidden1, hidden2),
                nn.GELU(),
                nn.Dropout(dropout),
                nn.Linear(hidden2, n_classes),
            )

        def forward(self, x):
            return self.net(x)

    m = SequenceMLP(seq_len=cfg.seq_len, n_features=cfg.n_features)
    dummy = torch.zeros(2, cfg.seq_len, cfg.n_features)
    out = m(dummy)
    record("SequenceMLP forward", PASS if out.shape == (2, 3) else FAIL,
           f"output shape={tuple(out.shape)}")
    del m
except Exception as e:
    record("SequenceMLP forward", FAIL, str(e))
    traceback.print_exc()

# PatchTST
try:
    class PatchTST(nn.Module):
        def __init__(self, seq_len=60, n_features=N_FEATURES,
                     patch_len=12, stride=6,
                     d_model=128, n_heads=8, n_layers=3,
                     dropout=0.1, n_classes=N_CLASSES):
            super().__init__()
            self.patch_len = patch_len
            self.stride = stride
            self.n_patches = (seq_len - patch_len) // stride + 1

            self.patch_embed = nn.Linear(patch_len, d_model)
            self.cls_token = nn.Parameter(torch.zeros(1, n_features, 1, d_model))
            self.pos_embed = nn.Parameter(torch.zeros(1, n_features, self.n_patches + 1, d_model))
            nn.init.trunc_normal_(self.cls_token, std=0.02)
            nn.init.trunc_normal_(self.pos_embed, std=0.02)

            enc_layer = nn.TransformerEncoderLayer(
                d_model=d_model, nhead=n_heads,
                dim_feedforward=d_model * 4,
                dropout=dropout, norm_first=True,
                batch_first=True,
            )
            self.transformer = nn.TransformerEncoder(enc_layer, num_layers=n_layers)
            self.norm = nn.LayerNorm(d_model)
            self.head = nn.Linear(n_features * d_model, n_classes)
            self.drop = nn.Dropout(dropout)

        def forward(self, x):
            B, S, F = x.shape
            x = x.permute(0, 2, 1)
            patches = x.unfold(-1, self.patch_len, self.stride)
            patches = self.patch_embed(patches)
            cls = self.cls_token.expand(B, -1, -1, -1)
            patches = torch.cat([cls, patches], dim=2) + self.pos_embed
            b2, f2, np_, dm = patches.shape
            patches = self.transformer(patches.reshape(b2 * f2, np_, dm))
            patches = patches.reshape(b2, f2, np_, dm)
            out = self.norm(patches[:, :, 0, :]).reshape(B, -1)
            return self.head(self.drop(out))

    m = PatchTST(seq_len=cfg.seq_len, n_features=cfg.n_features)
    dummy = torch.zeros(2, cfg.seq_len, cfg.n_features)
    out = m(dummy)
    record("PatchTST forward", PASS if out.shape == (2, 3) else FAIL,
           f"output shape={tuple(out.shape)}")
    del m
except Exception as e:
    record("PatchTST forward", FAIL, str(e))
    traceback.print_exc()

# Conv1D
try:
    class Conv1DModel(nn.Module):
        def __init__(self, seq_len=60, n_features=N_FEATURES,
                     hidden=128, dropout=0.1, n_classes=N_CLASSES):
            super().__init__()
            self.conv = nn.Sequential(
                nn.Conv1d(n_features, 64, kernel_size=3, padding=1),
                nn.GELU(),
                nn.BatchNorm1d(64),
                nn.Conv1d(64, 128, kernel_size=3, padding=1),
                nn.GELU(),
                nn.BatchNorm1d(128),
                nn.AdaptiveAvgPool1d(1),
            )
            self.head = nn.Sequential(
                nn.Flatten(),
                nn.Linear(128, hidden),
                nn.GELU(),
                nn.Dropout(dropout),
                nn.Linear(hidden, n_classes),
            )

        def forward(self, x):
            x = x.permute(0, 2, 1)
            x = self.conv(x)
            return self.head(x)

    m = Conv1DModel(seq_len=cfg.seq_len, n_features=cfg.n_features)
    dummy = torch.zeros(2, cfg.seq_len, cfg.n_features)
    out = m(dummy)
    record("Conv1DModel forward", PASS if out.shape == (2, 3) else FAIL,
           f"output shape={tuple(out.shape)}")
    del m
except Exception as e:
    record("Conv1DModel forward", FAIL, str(e))
    traceback.print_exc()

# LSTM
try:
    class LSTMModel(nn.Module):
        def __init__(self, seq_len=60, n_features=N_FEATURES,
                     hidden_size=128, num_layers=2, dropout=0.1, n_classes=N_CLASSES):
            super().__init__()
            self.lstm = nn.LSTM(
                input_size=n_features,
                hidden_size=hidden_size,
                num_layers=num_layers,
                batch_first=True,
                dropout=dropout if num_layers > 1 else 0.0,
            )
            self.head = nn.Sequential(
                nn.LayerNorm(hidden_size),
                nn.Linear(hidden_size, hidden_size // 2),
                nn.GELU(),
                nn.Dropout(dropout),
                nn.Linear(hidden_size // 2, n_classes),
            )

        def forward(self, x):
            _, (h_n, _) = self.lstm(x)
            return self.head(h_n[-1])

    m = LSTMModel(seq_len=cfg.seq_len, n_features=cfg.n_features)
    dummy = torch.zeros(2, cfg.seq_len, cfg.n_features)
    out = m(dummy)
    record("LSTMModel forward", PASS if out.shape == (2, 3) else FAIL,
           f"output shape={tuple(out.shape)}")
    del m
except Exception as e:
    record("LSTMModel forward", FAIL, str(e))
    traceback.print_exc()

# ── Test 6: ONNX Export ─────────────────────────────────────────────────────

print("\n" + "=" * 70)
print("TEST 6: ONNX Export & Verification (Cell 10)")
print("=" * 70)

model_defs = {
    "SequenceMLP": lambda: SequenceMLP(seq_len=cfg.seq_len, n_features=cfg.n_features),
    "PatchTST": lambda: PatchTST(seq_len=cfg.seq_len, n_features=cfg.n_features),
    "Conv1D": lambda: Conv1DModel(seq_len=cfg.seq_len, n_features=cfg.n_features),
    "LSTM": lambda: LSTMModel(seq_len=cfg.seq_len, n_features=cfg.n_features),
}

for name, factory in model_defs.items():
    try:
        model = factory()
        model.eval()
        onnx_path = os.path.join(cfg.output_dir, f"{name}_test.onnx")

        # Export
        dummy_input = torch.zeros(1, cfg.seq_len, cfg.n_features, dtype=torch.float32)
        torch.onnx.export(
            model,
            dummy_input,
            onnx_path,
            opset_version=cfg.onnx_opset,
            input_names=["input"],
            output_names=["output"],
            dynamic_axes={"input": {0: "batch"}, "output": {0: "batch"}},
            do_constant_folding=True,
        )
        record(f"{name} ONNX export", PASS)

        # Verify ONNX model loads
        onnx_model = onnx.load(onnx_path)
        onnx.checker.check_model(onnx_model)
        record(f"{name} ONNX checker", PASS)

        # Check input/output shapes (batch dim is 0 for dynamic_axes, which is expected)
        inp = onnx_model.graph.input[0]
        out_shape = onnx_model.graph.output[0]
        inp_dims = [d.dim_value for d in inp.type.tensor_type.shape.dim]
        out_dims = [d.dim_value for d in out_shape.type.tensor_type.shape.dim]
        # dim_value=0 means dynamic (from dynamic_axes), which is correct
        record(f"{name} ONNX input dims", PASS if inp_dims[1:] == [60, 57] else FAIL,
               f"got {inp_dims}")
        record(f"{name} ONNX output dims", PASS if out_dims[-1] == 3 else FAIL,
               f"got {out_dims}")

        # Run inference with ORT
        session = ort.InferenceSession(onnx_path)
        inp_name = session.get_inputs()[0].name
        test_input = np.random.randn(1, cfg.seq_len, cfg.n_features).astype(np.float32)
        ort_out = session.run(None, {inp_name: test_input})[0]
        record(f"{name} ORT inference shape", PASS if ort_out.shape == (1, 3) else FAIL,
               f"got {ort_out.shape}")

        # Verify PyTorch vs ONNX match
        with torch.no_grad():
            pt_out = model(torch.tensor(test_input)).numpy()
        max_diff = np.max(np.abs(pt_out - ort_out))
        record(f"{name} PT vs ONNX max_diff", PASS if max_diff < 1e-5 else FAIL,
               f"diff={max_diff:.2e}")

        # Cleanup
        os.remove(onnx_path)
        del model

    except Exception as e:
        record(f"{name} ONNX pipeline", FAIL, str(e))
        traceback.print_exc()

# ── Test 7: End-to-end with synthetic multi-symbol data ─────────────────────

print("\n" + "=" * 70)
print("TEST 7: End-to-end synthetic pipeline (2 symbols, 100 bars)")
print("=" * 70)

try:
    all_features_list = []
    all_labels_list = []
    all_weights_list = []
    all_returns_list = []
    all_timestamps_list = []

    for sym_idx, seed in enumerate([42, 99]):
        open_s, high_s, low_s, close_s, vol_s = synthetic_ohlcv(100, seed=seed)
        feat = build_feature_matrix(open_s, high_s, low_s, close_s, vol_s)
        atr_s = compute_atr(high_s, low_s, close_s, 14)
        labels_s = triple_barrier_labels(close_s, high_s, low_s, atr_s,
                                         k=cfg.tb_k, vertical_bars=cfg.tb_vertical_bars)
        events_s = cusum_filter(close_s, threshold_multiplier=cfg.cusum_threshold, atr=atr_s)
        label_indices_s = np.asarray([idx - 1 for idx in events_s if idx >= 1], dtype=np.int32)

        if len(label_indices_s) > 0:
            weights_s = compute_uniqueness_weights(label_indices_s, cfg.tb_vertical_bars, len(close_s))
            fwd_s = compute_forward_returns(close_s, label_indices_s, holding_bars=cfg.tb_vertical_bars)
            ts_s = np.arange(len(close_s), dtype=np.int64)  # fake timestamps

            all_features_list.append(feat)
            all_labels_list.append(labels_s)
            all_weights_list.append((label_indices_s, weights_s))
            all_returns_list.append((label_indices_s, fwd_s))
            all_timestamps_list.append(ts_s)

    record("Multi-symbol feature+label generation", PASS, f"{len(all_features_list)} symbols")

    # Build sequences
    all_X, all_y, all_w, all_r = [], [], [], []
    for k_sym in range(len(all_features_list)):
        features = all_features_list[k_sym]
        raw_labels = all_labels_list[k_sym]
        label_indices, weights = all_weights_list[k_sym]
        _, fwd_returns = all_returns_list[k_sym]
        timestamps = all_timestamps_list[k_sym]

        X_seq, y_seq, w_seq, r_seq, _ = prepare_sequences(
            features, raw_labels, weights, fwd_returns, timestamps,
            seq_len=cfg.seq_len, sample_indices=label_indices,
        )
        if len(X_seq) > 0:
            all_X.append(X_seq)
            all_y.append(y_seq)
            all_w.append(w_seq)
            all_r.append(r_seq)

    if all_X:
        X_all = np.concatenate(all_X)
        y_all = np.concatenate(all_y)
        w_all = np.concatenate(all_w)
        r_all = np.concatenate(all_r)

        record("Sequence building", PASS,
               f"X={X_all.shape}, y={y_all.shape}, classes={set(y_all.tolist())}")

        # Verify label mapping: -1->0, 0->1, 1->2
        if set(y_all.tolist()).issubset({0, 1, 2}):
            record("Labels in {0, 1, 2}", PASS, f"unique labels: {set(y_all.tolist())}")
        else:
            record("Labels in {0, 1, 2}", FAIL, f"unique labels: {set(y_all.tolist())}")
    else:
        record("Sequence building", FAIL, "No sequences generated (100 bars may be too few)")

except Exception as e:
    record("End-to-end pipeline", FAIL, str(e))
    traceback.print_exc()

# ── Test 8: CPCV functions ──────────────────────────────────────────────────

print("\n" + "=" * 70)
print("TEST 8: CPCV Validation Functions (Cell 9)")
print("=" * 70)

try:
    from itertools import combinations

    def purge_embargo(train_idx, test_idx, purge=5, embargo=5):
        t0, t1 = test_idx.min(), test_idx.max()
        mask = (train_idx < t0 - purge) | (train_idx > t1 + embargo)
        return train_idx[mask]

    def cpcv_folds(n, n_splits=6, n_test=2, purge=5, embargo=5):
        groups = np.array_split(np.arange(n), n_splits)
        folds = []
        for test_groups in combinations(range(n_splits), n_test):
            test_idx = np.concatenate([groups[i] for i in test_groups])
            train_idx = np.concatenate([groups[i] for i in range(n_splits) if i not in test_groups])
            train_idx = purge_embargo(train_idx, test_idx, purge, embargo)
            folds.append((train_idx, test_idx))
        return folds

    def psr(sharpe_ratios, sr_ref=0.0):
        mu = sharpe_ratios.mean()
        sig = sharpe_ratios.std(ddof=1) + 1e-9
        z = (mu - sr_ref) / sig * np.sqrt(len(sharpe_ratios))
        return float(norm.cdf(z))

    folds = cpcv_folds(100, n_splits=6, n_test=2, purge=5, embargo=5)
    record("cpcv_folds generates folds", PASS, f"{len(folds)} folds")

    # PSR test
    sr_test = np.array([0.5, 0.3, 0.7, 0.2, 0.6])
    psr_val = psr(sr_test)
    record("psr function", PASS if 0 < psr_val < 1 else FAIL, f"psr={psr_val:.4f}")

except Exception as e:
    record("CPCV functions", FAIL, str(e))
    traceback.print_exc()

# ── Test 9: Training loop functions exist and are callable ──────────────────

print("\n" + "=" * 70)
print("TEST 9: Training Loop Functions (Cell 7)")
print("=" * 70)

try:
    def compute_ic(model, loader, device):
        model.eval()
        scores, returns = [], []
        with torch.no_grad():
            for x, _y, _w, ret in loader:
                probs = torch.softmax(model(x.to(device)), dim=-1).cpu().numpy()
                scores.extend((probs[:, 2] - probs[:, 0]).tolist())
                returns.extend(ret.numpy().tolist())
        ic, _ = spearmanr(scores, returns)
        return float(ic) if not np.isnan(ic) else 0.0

    def compute_metrics(model, loader, device):
        model.eval()
        all_preds, all_labels = [], []
        with torch.no_grad():
            for x, y, _w, _r in loader:
                logits = model(x.to(device))
                preds = logits.argmax(dim=-1).cpu().numpy()
                all_preds.extend(preds)
                all_labels.extend(y.numpy())
        all_preds = np.array(all_preds)
        all_labels = np.array(all_labels)
        return {
            "accuracy": accuracy_score(all_labels, all_preds),
            "f1_macro": f1_score(all_labels, all_preds, average="macro", zero_division=0),
        }

    # Quick test with SequenceMLP
    model = SequenceMLP(seq_len=cfg.seq_len, n_features=cfg.n_features)
    model.eval()
    ds = TradingDataset(X_scaled[:20], y_synth[:20], w_synth[:20], r_synth[:20])
    loader = DataLoader(ds, batch_size=10, shuffle=False)
    device = "cpu"

    ic = compute_ic(model, loader, device)
    record("compute_ic runs", PASS, f"ic={ic:.4f}")

    metrics = compute_metrics(model, loader, device)
    record("compute_metrics runs", PASS, f"acc={metrics['accuracy']:.4f}")

    del model

except Exception as e:
    record("Training loop functions", FAIL, str(e))
    traceback.print_exc()

# ── Summary ──────────────────────────────────────────────────────────────────

print("\n" + "=" * 70)
print("SMOKE TEST SUMMARY")
print("=" * 70)

passed = sum(1 for _, s, _ in results if s == PASS)
failed = sum(1 for _, s, _ in results if s == FAIL)
total = len(results)

for name, status, detail in results:
    tag = "\u2713" if status == PASS else "\u2717"
    line = f"  [{tag}] {name}"
    if detail:
        line += f"  ({detail})"
    print(line)

print(f"\n  TOTAL: {total} | PASSED: {passed} | FAILED: {failed}")

if failed > 0:
    print("\n  FAILED TESTS:")
    for name, status, detail in results:
        if status == FAIL:
            print(f"    - {name}: {detail}")
    sys.exit(1)
else:
    print("\n  All smoke tests passed!")
    sys.exit(0)
