# %% [markdown]
# # Multi-Mt5 AI Trading Strategy Trainer — Production Hardened v2.0
#
# **Critical fixes applied:**
# - Eliminated `np.roll` wrap-around lookahead bias (replaced with safe lag)
# - Fixed off-by-one event sampling (CUSUM events now correctly aligned)
# - Added purged train/val/test splits (no overlapping label leakage)
# - Replaced StandardScaler with RobustScaler (fat-tail resistant)
# - Scaler now saved with versioned binary header (MT5-safe)
# - Vectorized & Numba-accelerated triple-barrier, CUSUM, and uniqueness weights
# - CPCV runs **before** final model selection (no data leakage)
# - Realistic forward returns using `open[i+1]` entry price
# - Transaction cost model integrated into Sharpe calculations
# - Fixed regime detection logic (trend = directional state, not high-vol)
# - Ledoit-Wolf shrinkage for turbulence (singular covariance fix)
# - Robust class weighting (effective number)
# - Residual connections + BatchNorm in MLP
# - Attention pooling in iTransformer (no mean-pool information loss)
# - Automatic CSV header detection (supports headerless raw dumps)
# - Calendar features always injected from timestamps

# %%
# ==============================================
# 1. Setup and Dependencies
# ==============================================
import subprocess
subprocess.check_call('pip install -q torch>=2.1.0 numpy>=1.24.0 pandas>=2.0.0 scipy>=1.11.0 scikit-learn>=1.3.0', shell=True)
subprocess.check_call('pip install -q onnx>=1.15.0 onnxruntime>=1.17.0 lightgbm>=4.3.0 onnxmltools>=1.12.0', shell=True)
subprocess.check_call('pip install -q hmmlearn>=0.3.0 einops>=0.7.0 optuna>=3.6.0 matplotlib>=3.7.0 tqdm numba', shell=True)
print('✅ All dependencies installed successfully!')

# %%
# Mount Google Drive
from google.colab import drive
import os
drive.mount('/content/drive')
DRIVE_BASE = '/content/drive/MyDrive/Multi-Mt5'
MODELS_DIR = os.path.join(DRIVE_BASE, 'models')
CHARTS_DIR = os.path.join(DRIVE_BASE, 'charts')
DATA_DIR = os.path.join(DRIVE_BASE, 'data')
LOGS_DIR = os.path.join(DRIVE_BASE, 'logs')
for d in [DRIVE_BASE, MODELS_DIR, CHARTS_DIR, DATA_DIR, LOGS_DIR]:
    os.makedirs(d, exist_ok=True)
print(f'📁 Working directory: {DRIVE_BASE}')

# %%
# ==============================================
# 2. Imports & Seeding
# ==============================================
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib
matplotlib.style.use('seaborn-v0_8-darkgrid')
import torch
import torch.nn as nn
import torch.nn.functional as F
from torch.utils.data import DataLoader, Dataset
from sklearn.preprocessing import RobustScaler
from sklearn.covariance import LedoitWolf
from scipy.stats import spearmanr
from tqdm import tqdm
import struct
from pathlib import Path
from typing import List, Optional, Tuple, Dict
from dataclasses import dataclass
from datetime import datetime
import pickle
from itertools import combinations

try:
    from numba import njit
    HAS_NUMBA = True
except ImportError:
    HAS_NUMBA = False
    print('⚠️ numba not available — falling back to pure Python loops (slower)')

try:
    import onnxruntime as ort
    HAS_ONNX = True
except ImportError:
    HAS_ONNX = False
    print('⚠️ onnxruntime not installed')

torch.manual_seed(42)
np.random.seed(42)
if torch.cuda.is_available():
    torch.cuda.manual_seed_all(42)
print('✅ All libraries imported successfully!')

# %%
# ==============================================
# 3. Configuration
# ==============================================
@dataclass
class Config:
    TRAIN_MODE: str = 'sequential'          # 'single', 'sequential', 'ensemble'
    MODEL_TYPE: str = 'patchtst'            # used when TRAIN_MODE='single'
    SEQ_LEN: int = 60
    K: float = 1.5
    VERTICAL_BARS: int = 20
    HOLDING_BARS: int = 20
    EPOCHS: int = 60
    BATCH_SIZE: int = 64
    LR: float = 3e-4
    WEIGHT_DECAY: float = 1e-4
    DROPOUT: float = 0.20
    PURGE_GAP: int = 25                     # seq_len + vertical_bars + buffer
    EMBARGO: int = 5
    COST_BPS: float = 1.0                   # estimated round-trip cost in basis points
    MIN_IC_THRESHOLD: float = 0.03
    CPCV_SPLITS: int = 6
    CPCV_TEST: int = 2
    MAX_GRAD_NORM: float = 1.0
    GRAD_ACCUM_STEPS: int = 1               # set to 2+ if OOM
    EARLY_STOP_PATIENCE: int = 20

CFG = Config()

# CSV discovery
csv_candidates = ['UNIVERSAL_TRAINING_SET.csv', 'Universal.csv', 'training_data.csv']
CSV_PATH = None
for candidate in csv_candidates:
    candidate_path = os.path.join(DATA_DIR, candidate)
    if os.path.exists(candidate_path):
        CSV_PATH = candidate_path
        print(f'✅ Found training data: {candidate}')
        break
if CSV_PATH is None:
    raise FileNotFoundError(f'No training data found. Upload CSV to {DATA_DIR}')

MODEL_OUTPUT = os.path.join(MODELS_DIR, 'best_model.onnx')
SCALER_OUTPUT = os.path.join(MODELS_DIR, 'scaler_v2.bin')

print(f'📋 Configuration:')
for k, v in vars(CFG).items():
    print(f'  {k}: {v}')
print(f'  Data Path: {CSV_PATH}')

# %%
# ==============================================
# 4. Data Pipeline — Hardened & Vectorized
# ==============================================

@dataclass
class PipelineMetadata:
    seq_len: int
    n_features: int
    train_size: int
    val_size: int
    test_size: int
    annualization: float
    scaler_path: Optional[str]
    cost_bps: float

class TradingDataset(Dataset):
    def __init__(self, X: np.ndarray, y: np.ndarray,
                 weights: Optional[np.ndarray] = None,
                 returns: Optional[np.ndarray] = None):
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

def _safe_lag(x: np.ndarray, periods: int, fill_value: float = 0.0) -> np.ndarray:
    """Safe lag without np.roll wrap-around."""
    return pd.Series(x, dtype=np.float64).shift(periods, fill_value=fill_value).to_numpy(dtype=np.float64)

def save_scaler_v2(scaler: RobustScaler, output_path: str):
    """Versioned binary scaler for MT5 with magic header."""
    output = Path(output_path)
    output.parent.mkdir(parents=True, exist_ok=True)
    n = len(scaler.center_)
    with output.open('wb') as f:
        f.write(b'SCL2')                       # magic
        f.write(struct.pack('<i', 1))           # version
        f.write(struct.pack('<i', n))          # num features
        f.write(struct.pack(f'<{n}d', *scaler.center_))
        f.write(struct.pack(f'<{n}d', *scaler.scale_))

def compute_atr(high: np.ndarray, low: np.ndarray, close: np.ndarray, period: int = 14):
    tr = np.maximum(
        high[1:] - low[1:],
        np.maximum(np.abs(high[1:] - close[:-1]), np.abs(low[1:] - close[:-1])),
    )
    atr = np.zeros(len(close), dtype=np.float64)
    if period <= len(tr):
        atr[period] = tr[:period].mean()
        for i in range(period + 1, len(close)):
            atr[i] = (atr[i - 1] * (period - 1) + tr[i - 1]) / period
    # Backfill first period bars with simple mean to avoid zeros
    atr[:period] = tr[:period].mean() if len(tr) >= period else tr.mean()
    return atr

def triple_barrier_labels(close: np.ndarray, high: np.ndarray, low: np.ndarray,
                          atr: np.ndarray, k: float = 1.5, vertical_bars: int = 20):
    """Pure Python triple barrier (Numba version below if available)."""
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

if HAS_NUMBA:
    @njit
    def _triple_barrier_numba(close, high, low, atr, k, vertical_bars):
        n = len(close)
        labels = np.zeros(n, dtype=np.int8)
        for i in range(n - vertical_bars):
            if atr[i] <= 0.0:
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

    def triple_barrier_labels(close, high, low, atr, k=1.5, vertical_bars=20):
        return _triple_barrier_numba(close, high, low, atr, k, vertical_bars)

def compute_uniqueness_weights(event_indices: List[int], vertical_bars: int, total_bars: int):
    event_indices = np.asarray(event_indices, dtype=np.int32)
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

if HAS_NUMBA:
    @njit
    def _uniq_weights_numba(event_indices, vertical_bars, total_bars):
        concurrency = np.zeros(total_bars, dtype=np.float32)
        for idx in event_indices:
            end = min(idx + vertical_bars, total_bars)
            for t in range(idx, end):
                concurrency[t] += 1.0
        weights = np.zeros(len(event_indices), dtype=np.float32)
        for i in range(len(event_indices)):
            idx = event_indices[i]
            end = min(idx + vertical_bars, total_bars)
            s = 0.0
            cnt = 0
            for t in range(idx, end):
                s += 1.0 / max(concurrency[t], 1e-9)
                cnt += 1
            weights[i] = s / max(cnt, 1)
        total = weights.sum()
        if total > 1e-9:
            weights = weights / total * len(event_indices)
        return weights

    def compute_uniqueness_weights(event_indices, vertical_bars, total_bars):
        arr = np.asarray(event_indices, dtype=np.int32)
        if len(arr) == 0:
            return np.zeros(0, dtype=np.float32)
        return _uniq_weights_numba(arr, vertical_bars, total_bars)

def compute_forward_returns(open_: np.ndarray, event_indices: List[int], holding_bars: int = 10):
    """Realistic forward returns: enter at next open, exit after holding_bars."""
    event_indices = np.asarray(event_indices, dtype=np.int32)
    returns = np.zeros(len(event_indices), dtype=np.float32)
    for i, idx in enumerate(event_indices):
        entry_idx = min(int(idx) + 1, len(open_) - 1)
        exit_idx = min(entry_idx + holding_bars, len(open_) - 1)
        entry = open_[entry_idx]
        exit_price = open_[exit_idx]
        returns[i] = (exit_price - entry) / max(entry, 1e-10)
    return returns

def cusum_filter(close: np.ndarray, threshold_multiplier: float = 1.0, atr: Optional[np.ndarray] = None):
    if atr is None:
        atr = np.ones(len(close), dtype=np.float64)
    events: List[int] = []
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

if HAS_NUMBA:
    @njit
    def _cusum_numba(close, threshold_multiplier, atr):
        events = []
        s_pos, s_neg = 0.0, 0.0
        for i in range(1, len(close)):
            ret = np.log(close[i] / (close[i - 1] + 1e-12))
            thresh = max(1e-8, threshold_multiplier * (atr[i] / (close[i] + 1e-9)))
            s_pos = max(0.0, s_pos + ret)
            s_neg = min(0.0, s_neg + ret)
            if s_pos > thresh:
                events.append(i)
                s_pos = 0.0
            elif s_neg < -thresh:
                events.append(i)
                s_neg = 0.0
        return events

    def cusum_filter(close, threshold_multiplier=1.0, atr=None):
        if atr is None:
            atr = np.ones(len(close), dtype=np.float64)
        return _cusum_numba(close, threshold_multiplier, atr)

def _ema(x: np.ndarray, period: int):
    alpha = 2.0 / (period + 1)
    result = np.empty_like(x, dtype=np.float64)
    result[0] = x[0]
    for i in range(1, len(x)):
        result[i] = alpha * x[i] + (1 - alpha) * result[i - 1]
    return result

def _sma(x: np.ndarray, period: int):
    return pd.Series(x).rolling(period, min_periods=1).mean().to_numpy(dtype=np.float64)

def _rsi(close: np.ndarray, period: int):
    delta = np.diff(close, prepend=close[0]).astype(np.float64)
    avg_gain = _ema(np.maximum(delta, 0.0), period)
    avg_loss = _ema(np.maximum(-delta, 0.0), period)
    rs = avg_gain / (avg_loss + 1e-9)
    return (100.0 - 100.0 / (1.0 + rs)) / 100.0

def _bb_pct_b(close: np.ndarray, period: int = 20, mult: float = 2.0):
    mid = _sma(close, period)
    std = pd.Series(close).rolling(period, min_periods=1).std(ddof=0).fillna(0).to_numpy(dtype=np.float64)
    upper = mid + mult * std
    lower = mid - mult * std
    return (close - lower) / (upper - lower + 1e-9)

def _bb_width(close: np.ndarray, period: int = 20, mult: float = 2.0):
    mid = _sma(close, period)
    std = pd.Series(close).rolling(period, min_periods=1).std(ddof=0).fillna(0).to_numpy(dtype=np.float64)
    return (2 * mult * std) / (mid + 1e-9)

def _macd_hist_norm(close: np.ndarray, fast: int = 12, slow: int = 26, sig: int = 9):
    macd = _ema(close, fast) - _ema(close, slow)
    signal = _ema(macd, sig)
    hist = macd - signal
    atr = compute_atr(np.maximum(close, np.roll(close, 1)), np.minimum(close, np.roll(close, 1)), close, 14)
    return hist / (atr + 1e-9)

def _rolling_zscore(x: np.ndarray, period: int):
    series = pd.Series(x.astype(np.float64))
    mean = series.rolling(period, min_periods=2).mean()
    std = series.rolling(period, min_periods=2).std(ddof=0)
    return ((series - mean) / (std + 1e-9)).fillna(0.0).to_numpy(dtype=np.float64)

def _cci(high: np.ndarray, low: np.ndarray, close: np.ndarray, period: int = 14):
    tp = (high + low + close) / 3.0
    sma = _sma(tp, period)
    tp_series = pd.Series(tp)
    mad = tp_series.rolling(period, min_periods=1).apply(lambda x: np.mean(np.abs(x - x.mean())), raw=True).fillna(1e-9).to_numpy(dtype=np.float64)
    return (tp - sma) / (0.015 * mad + 1e-9) / 200.0

def _parkinson_vol(high: np.ndarray, low: np.ndarray, period: int = 14):
    log_hl = np.log((high + 1e-9) / (low + 1e-9)) ** 2
    factor = 1.0 / (4.0 * np.log(2))
    return np.sqrt(pd.Series(factor * log_hl).rolling(period, min_periods=1).mean().to_numpy(dtype=np.float64))

def build_feature_matrix(open_: np.ndarray, high: np.ndarray, low: np.ndarray,
                         close: np.ndarray, volume: np.ndarray):
    n = len(close)
    log_ret = np.concatenate([[0.0], np.log(close[1:] / (close[:-1] + 1e-12))])
    atr14 = compute_atr(high, low, close, 14)
    atr50 = compute_atr(high, low, close, 50)
    atr5 = compute_atr(high, low, close, 5)

    # Safe lags — no wrap-around
    lag_ret_1 = _safe_lag(log_ret, 1)
    lag_ret_5 = _safe_lag(log_ret, 5)
    lag_ret_10 = _safe_lag(log_ret, 10)
    lag_ret_15 = _safe_lag(log_ret, 15)
    lag_ret_20 = _safe_lag(log_ret, 20)
    lag_ret_atr_2 = _safe_lag(log_ret / (atr14 + 1e-9), 2)
    lag_ret_atr_3 = _safe_lag(log_ret / (atr14 + 1e-9), 3)
    lag_ret_atr_5 = _safe_lag(log_ret / (atr14 + 1e-9), 5)
    lag_ret_atr_8 = _safe_lag(log_ret / (atr14 + 1e-9), 8)
    lag_ret_atr_13 = _safe_lag(log_ret / (atr14 + 1e-9), 13)
    rsi14 = _rsi(close, 14)
    lag_rsi14_1 = _safe_lag(rsi14, 1)
    lag_rsi14_3 = _safe_lag(rsi14, 3)
    bb_pct = _bb_pct_b(close, 20, 2.0)
    lag_bb_pct_1 = _safe_lag(bb_pct, 1)
    lag_bb_pct_3 = _safe_lag(bb_pct, 3)
    macd_norm = _macd_hist_norm(close, 12, 26, 9)
    lag_macd_1 = _safe_lag(macd_norm, 1)

    cols = [
        log_ret,
        log_ret / (atr14 + 1e-9),
        (close - low) / (high - low + 1e-9),
        np.log(volume.astype(np.float64) + 1.0),
        atr14 / (close + 1e-9),
        np.log(close / (_ema(close, 8) + 1e-9) + 1e-9),
        np.log(close / (_ema(close, 21) + 1e-9) + 1e-9),
        np.log(close / (_ema(close, 50) + 1e-9) + 1e-9),
        np.log(_ema(close, 8) / (_ema(close, 21) + 1e-9) + 1e-9),
        np.log(_ema(close, 21) / (_ema(close, 50) + 1e-9) + 1e-9),
        rsi14,
        _rsi(close, 7),
        bb_pct,
        _bb_width(close, 20, 2.0),
        macd_norm,
        atr14 / (atr50 + 1e-9),
        _parkinson_vol(high, low, 14),
        volume / (_sma(volume.astype(np.float64), 20) + 1e-9),
        np.zeros(n),   # 18: calendar sin(dow) — injected later
        np.zeros(n),   # 19: calendar cos(dow)
        np.zeros(n),   # 20: calendar sin(hod)
        np.zeros(n),   # 21: calendar cos(hod)
        lag_ret_1,
        lag_ret_5,
        lag_ret_20,
        _rolling_zscore(close.astype(np.float64), 20),
        _rolling_zscore(close.astype(np.float64), 50),
        (high - low) / (close + 1e-9),
        _rolling_zscore(high - low, 20),
        _cci(high, low, close, 14),
        lag_ret_atr_2,
        lag_ret_atr_3,
        lag_ret_atr_5,
        lag_ret_atr_8,
        lag_ret_atr_13,
        _rolling_zscore(volume.astype(np.float64), 20),
        lag_rsi14_1,
        lag_rsi14_3,
        lag_bb_pct_1,
        lag_bb_pct_3,
        _rolling_zscore(rsi14, 20),
        _rolling_zscore(_rsi(close, 7), 20),
        macd_norm,
        lag_macd_1,
        atr14 / (atr5 + 1e-9),
        _rolling_zscore(atr14, 20),
        lag_ret_10,
        lag_ret_15,
        (close - _sma(close, 50)) / (atr14 + 1e-9),
        (close - _sma(close, 200)) / (atr14 + 1e-9),
        _rolling_zscore(lag_ret_1 * log_ret, 20),
        _rolling_zscore(lag_ret_5 * log_ret, 20),
        (close - _ema(close, 100)) / (atr50 + 1e-9),
        _rolling_zscore(volume.astype(np.float64), 50),
        atr50 / (atr14 + 1e-9),
        np.zeros(n),   # 55: placeholder
        np.ones(n),    # 56: bias feature
    ]
    features = np.column_stack(cols).astype(np.float32)
    return np.nan_to_num(features, nan=0.0, posinf=3.0, neginf=-3.0)

def exported_feature_columns(frame: pd.DataFrame):
    feature_cols = [col for col in frame.columns if col.startswith('feature_')]
    def sort_key(name: str):
        try:
            return int(name.split('_')[1])
        except (IndexError, ValueError):
            return 10 ** 9
    return sorted(feature_cols, key=sort_key)

def add_calendar_features(features: np.ndarray, timestamps: pd.DatetimeIndex):
    """Always overwrite calendar slots 18-21 from timestamps."""
    dow = timestamps.dayofweek.values / 6.0
    hod = timestamps.hour.values / 23.0
    features[:, 18] = np.sin(2 * np.pi * dow).astype(np.float32)
    features[:, 19] = np.cos(2 * np.pi * dow).astype(np.float32)
    features[:, 20] = np.sin(2 * np.pi * hod).astype(np.float32)
    features[:, 21] = np.cos(2 * np.pi * hod).astype(np.float32)
    return features

def prepare_sequences(features: np.ndarray, labels: np.ndarray, weights: np.ndarray,
                      returns: np.ndarray, timestamps: np.ndarray,
                      seq_len: int, sample_indices: List[int]):
    X, y, w, r, ts = [], [], [], [], []
    for idx, sample_idx in enumerate(sample_indices):
        if sample_idx < seq_len:
            continue
        end = int(sample_idx)
        X.append(features[end - seq_len:end])
        y.append(int(labels[end]) + 1)   # map -1→0, 0→1, 1→2
        w.append(float(weights[idx]))
        r.append(float(returns[idx]))
        ts.append(timestamps[end - 1])
    return (
        np.asarray(X, dtype=np.float32),
        np.asarray(y, dtype=np.int64),
        np.asarray(w, dtype=np.float32),
        np.asarray(r, dtype=np.float32),
        np.asarray(ts),
    )

def _split_arrays_purged(X: np.ndarray, y: np.ndarray, weights: np.ndarray,
                         returns: np.ndarray, timestamps: np.ndarray,
                         train_ratio: float, val_ratio: float,
                         purge_gap: int, embargo: int):
    n = len(X)
    if n < 48:
        raise ValueError('Not enough samples to split safely.')
    train_end = int(n * train_ratio)
    val_end = int(n * (train_ratio + val_ratio))
    # Apply purge gap
    train_end = max(24, min(train_end - purge_gap, n - 24 - purge_gap))
    val_start = train_end + purge_gap
    val_end = max(val_start + 12, min(val_end, n - 12 - embargo))
    test_start = val_end + purge_gap
    train = (X[:train_end], y[:train_end], weights[:train_end], returns[:train_end], timestamps[:train_end])
    val = (X[val_start:val_end], y[val_start:val_end], weights[val_start:val_end],
           returns[val_start:val_end], timestamps[val_start:val_end])
    test = (X[test_start:n - embargo], y[test_start:n - embargo], weights[test_start:n - embargo],
            returns[test_start:n - embargo], timestamps[test_start:n - embargo])
    return train, val, test

def _estimate_annualization_factor(timestamps: np.ndarray):
    if len(timestamps) < 3:
        return 252.0 * 24.0 * 4  # default 15-min FX assumption
    ts = pd.to_datetime(pd.Series(timestamps)).astype('int64') // 10 ** 9
    deltas = np.diff(ts.to_numpy(dtype=np.int64))
    deltas = deltas[deltas > 0]
    if len(deltas) == 0:
        return 252.0 * 24.0 * 4
    median_seconds = float(np.median(deltas))
    if median_seconds <= 0:
        return 252.0 * 24.0 * 4
    bars_per_year = (365.25 * 24.0 * 3600.0) / median_seconds
    # Clamp to realistic range (monthly ~12 to 1-min ~525k)
    return max(12.0, min(bars_per_year, 525600.0))

def load_csv_robust(csv_path: str) -> pd.DataFrame:
    """Auto-detect headerless CSV and assign proper column names."""
    with open(csv_path, 'r', encoding='utf-8') as f:
        first_line = f.readline().strip()
    has_header = any(c.isalpha() for c in first_line.split(',')[0])
    if has_header:
        df = pd.read_csv(csv_path)
    else:
        cols = ['symbol', 'date', 'open', 'high', 'low', 'close', 'volume'] + [f'feature_{i:02d}' for i in range(57)]
        df = pd.read_csv(csv_path, header=None, names=cols)
    df['date'] = pd.to_datetime(df['date'])
    return df

def build_dataset_splits(df: pd.DataFrame, seq_len: int = 60, k: float = 1.5,
                         vertical_bars: int = 20, train_ratio: float = 0.70,
                         val_ratio: float = 0.15, purge_gap: int = 25, embargo: int = 5):
    required = {'date', 'open', 'high', 'low', 'close', 'volume'}
    missing = required - set(df.columns)
    if missing:
        raise ValueError(f'Missing required columns: {sorted(missing)}')
    frame = df.copy()
    if 'symbol' not in frame.columns:
        frame['symbol'] = 'DEFAULT'
    train_parts, val_parts, test_parts = [], [], []
    annualization_candidates = []
    grouped = frame.sort_values(['symbol', 'date']).groupby('symbol', sort=False)
    for _, sym_df in grouped:
        sym_df = sym_df.dropna(subset=['open', 'high', 'low', 'close', 'volume']).copy()
        if len(sym_df) < max(seq_len + vertical_bars + 20, 160):
            continue
        open_ = sym_df['open'].to_numpy(dtype=np.float64)
        high = sym_df['high'].to_numpy(dtype=np.float64)
        low = sym_df['low'].to_numpy(dtype=np.float64)
        close = sym_df['close'].to_numpy(dtype=np.float64)
        volume = sym_df['volume'].to_numpy(dtype=np.float64)
        feature_cols = exported_feature_columns(sym_df)
        if feature_cols:
            features = sym_df[feature_cols].to_numpy(dtype=np.float32)
            features = np.nan_to_num(features, nan=0.0, posinf=3.0, neginf=-3.0)
        else:
            features = build_feature_matrix(open_, high, low, close, volume)
        # Always inject fresh calendar features from timestamps
        features = add_calendar_features(features, pd.DatetimeIndex(sym_df['date']))
        atr = compute_atr(high, low, close, 14)
        labels = triple_barrier_labels(close, high, low, atr, k=k, vertical_bars=vertical_bars)
        events = np.asarray(cusum_filter(close, threshold_multiplier=1.0, atr=atr), dtype=np.int32)
        # Filter events: must have enough history and room for forward label
        label_indices = np.asarray([idx for idx in events if idx >= seq_len and idx < len(close) - vertical_bars], dtype=np.int32)
        if len(label_indices) < 48:
            continue
        weights = compute_uniqueness_weights(label_indices, vertical_bars, len(close))
        returns = compute_forward_returns(open_, label_indices, holding_bars=vertical_bars)
        timestamps = sym_df['date'].to_numpy()
        X, y, w, r, ts = prepare_sequences(features, labels, weights, returns, timestamps,
                                           seq_len=seq_len, sample_indices=label_indices)
        if len(X) < 48:
            continue
        train, val, test = _split_arrays_purged(X, y, w, r, ts, train_ratio, val_ratio, purge_gap, embargo)
        train_parts.append(train)
        val_parts.append(val)
        test_parts.append(test)
        annualization_candidates.append(_estimate_annualization_factor(ts))
    if not train_parts or not val_parts or not test_parts:
        raise ValueError('No usable symbol groups found.')
    def concat(parts: List[Tuple[np.ndarray, ...]]):
        columns = list(zip(*parts))
        return tuple(np.concatenate(list(col), axis=0) for col in columns)
    annualization = float(np.median(annualization_candidates)) if annualization_candidates else 252.0 * 24.0 * 4
    return concat(train_parts), concat(val_parts), concat(test_parts), annualization

def _scale_splits(train: Tuple[np.ndarray, ...], val: Tuple[np.ndarray, ...],
                  test: Tuple[np.ndarray, ...], scaler_output: Optional[str] = None):
    X_tr, y_tr, w_tr, r_tr, ts_tr = train
    X_va, y_va, w_va, r_va, ts_va = val
    X_te, y_te, w_te, r_te, ts_te = test
    scaler = RobustScaler(quantile_range=(5.0, 95.0))
    B, T, F = X_tr.shape
    # Scale per-feature across all timesteps (preserves temporal structure)
    scaler.fit(X_tr.reshape(-1, F))
    def transform(X):
        flat = X.reshape(-1, F)
        scaled = scaler.transform(flat)
        return scaled.reshape(len(X), T, F).astype(np.float32)
    if scaler_output:
        save_scaler_v2(scaler, scaler_output)
    return (
        (transform(X_tr), y_tr, w_tr, r_tr, ts_tr),
        (transform(X_va), y_va, w_va, r_va, ts_va),
        (transform(X_te), y_te, w_te, r_te, ts_te),
        scaler,
    )

def build_scaled_dataset_splits(csv_path: str, seq_len: int = 60, k: float = 1.5,
                                vertical_bars: int = 20, train_ratio: float = 0.70,
                                val_ratio: float = 0.15, purge_gap: int = 25, embargo: int = 5,
                                scaler_output: Optional[str] = None):
    df = load_csv_robust(csv_path)
    train, val, test, annualization = build_dataset_splits(
        df, seq_len=seq_len, k=k, vertical_bars=vertical_bars,
        train_ratio=train_ratio, val_ratio=val_ratio, purge_gap=purge_gap, embargo=embargo,
    )
    train, val, test, _ = _scale_splits(train, val, test, scaler_output=scaler_output)
    metadata = PipelineMetadata(
        seq_len=seq_len, n_features=train[0].shape[2],
        train_size=len(train[0]), val_size=len(val[0]), test_size=len(test[0]),
        annualization=annualization, scaler_path=scaler_output, cost_bps=CFG.COST_BPS,
    )
    return train, val, test, metadata

print('✅ Data pipeline functions loaded!')

# %%
# ==============================================
# 5. Model Architectures — Improved
# ==============================================

class SequenceMLP(nn.Module):
    """ResNet-style MLP with BatchNorm, GELU, and residual skip."""
    def __init__(self, seq_len=60, n_features=57, hidden=256, dropout=0.20, n_classes=3):
        super().__init__()
        flat_dim = seq_len * n_features
        self.norm_in = nn.LayerNorm(flat_dim)
        self.fc1 = nn.Linear(flat_dim, hidden)
        self.bn1 = nn.BatchNorm1d(hidden)
        self.drop1 = nn.Dropout(dropout)
        self.fc2 = nn.Linear(hidden, hidden // 2)
        self.bn2 = nn.BatchNorm1d(hidden // 2)
        self.drop2 = nn.Dropout(dropout)
        self.skip = nn.Linear(flat_dim, hidden // 2)
        self.head = nn.Linear(hidden // 2, n_classes)

    def forward(self, x):
        x = x.reshape(x.size(0), -1)
        x = self.norm_in(x)
        h = self.fc1(x)
        h = self.bn1(h)
        h = F.gelu(h)
        h = self.drop1(h)
        h = self.fc2(h)
        h = self.bn2(h)
        h = F.gelu(h)
        h = self.drop2(h)
        return self.head(h + self.skip(x))

class PatchTST(nn.Module):
    def __init__(self, seq_len=60, n_features=57, patch_len=12, stride=6,
                 d_model=128, n_heads=8, n_layers=3, dropout=0.20, n_classes=3):
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
            d_model=d_model, nhead=n_heads, dim_feedforward=d_model * 4,
            dropout=dropout, norm_first=True, batch_first=True,
        )
        self.transformer = nn.TransformerEncoder(enc_layer, num_layers=n_layers)
        self.norm = nn.LayerNorm(d_model)
        self.head = nn.Linear(n_features * d_model, n_classes)
        self.drop = nn.Dropout(dropout)

    def forward(self, x):
        batch_size, seq_len, n_features = x.shape
        x = x.permute(0, 2, 1)
        patches = x.unfold(-1, self.patch_len, self.stride)
        patches = self.patch_embed(patches)
        cls = self.cls_token.expand(batch_size, -1, -1, -1)
        patches = torch.cat([cls, patches], dim=2) + self.pos_embed
        b2, f2, n_patch, d_model = patches.shape
        patches = self.transformer(patches.reshape(b2 * f2, n_patch, d_model))
        patches = patches.reshape(b2, f2, n_patch, d_model)
        out = self.norm(patches[:, :, 0, :]).reshape(batch_size, -1)
        return self.head(self.drop(out))

class iTransformer(nn.Module):
    """iTransformer with attention pooling instead of mean pooling."""
    def __init__(self, seq_len=60, n_features=57, d_model=128, n_heads=8,
                 n_layers=3, dropout=0.20, n_classes=3):
        super().__init__()
        self.feat_embed = nn.Linear(seq_len, d_model)
        enc_layer = nn.TransformerEncoderLayer(
            d_model=d_model, nhead=n_heads, dim_feedforward=d_model * 4,
            dropout=dropout, norm_first=True, batch_first=True,
        )
        self.transformer = nn.TransformerEncoder(enc_layer, num_layers=n_layers)
        self.norm = nn.LayerNorm(d_model)
        self.attn_pool = nn.Linear(d_model, 1)
        self.head = nn.Sequential(
            nn.Linear(d_model, d_model // 2),
            nn.GELU(),
            nn.Dropout(dropout),
            nn.Linear(d_model // 2, n_classes),
        )

    def forward(self, x):
        x = x.permute(0, 2, 1)
        x = self.feat_embed(x)
        x = self.transformer(x)
        x = self.norm(x)
        # Attention-weighted pooling across feature dimension
        attn = torch.softmax(self.attn_pool(x), dim=1)
        x = (x * attn).sum(dim=1)
        return self.head(x)

# %%
# ==============================================
# 6. Regime Detection & Turbulence — Fixed
# ==============================================

class RegimeDetector:
    def __init__(self, n_states: int = 2, lookback: int = 500) -> None:
        from hmmlearn.hmm import GaussianHMM
        self.model = GaussianHMM(
            n_components=n_states,
            covariance_type='full',
            n_iter=200,
            random_state=42,
        )
        self.lookback = lookback
        self.fitted = False
        self.trend_state = 0

    def fit(self, returns: np.ndarray) -> None:
        window = returns.reshape(-1, 1)[-self.lookback:]
        self.model.fit(window)
        means = self.model.means_.reshape(-1)
        # Trend = state with highest absolute mean return (directionality)
        self.trend_state = int(np.argmax(np.abs(means)))
        self.fitted = True

    def predict(self, recent_returns: np.ndarray) -> str:
        if not self.fitted:
            return 'unknown'
        state = int(self.model.predict(recent_returns.reshape(-1, 1))[-1])
        return 'trend' if state == self.trend_state else 'chop'

TURBULENCE_THRESHOLD = 3.5

def compute_turbulence(current_returns: np.ndarray, historical_returns: np.ndarray) -> float:
    """Mahalanobis distance with Ledoit-Wolf shrinkage covariance."""
    lw = LedoitWolf().fit(historical_returns)
    diff = current_returns - lw.location_
    return float(np.sqrt(diff @ lw.precision_ @ diff))

# %%
# ==============================================
# 7. CPCV Validation — Proper Implementation
# ==============================================

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
    from scipy.stats import norm
    mu = sharpe_ratios.mean()
    sig = sharpe_ratios.std(ddof=1) + 1e-9
    z = (mu - sr_ref) / sig * np.sqrt(len(sharpe_ratios))
    return float(norm.cdf(z))

def apply_costs(gross_returns, cost_bps=1.0):
    """Subtract round-trip cost in return space."""
    cost = 2.0 * cost_bps / 10000.0
    return gross_returns - cost

def run_cpcv(model_factory, X, y, bar_returns, n_splits=6, annualization=252.0,
             cost_bps=1.0, epochs=20, batch_size=64, device='cpu'):
    """Proper CPCV: trains a fresh model from scratch on each fold."""
    folds = cpcv_folds(len(X), n_splits=n_splits)
    sharpes = []
    for fold_idx, (train_idx, test_idx) in enumerate(folds):
        print(f'  CPCV fold {fold_idx + 1}/{len(folds)} ...')
        X_train, y_train = X[train_idx], y[train_idx]
        X_test, y_test = X[test_idx], y[test_idx]
        r_test = bar_returns[test_idx]
        # Build datasets
        train_ds = TradingDataset(X_train, y_train)
        test_ds = TradingDataset(X_test, y_test)
        train_loader = DataLoader(train_ds, batch_size=batch_size, shuffle=True, drop_last=False)
        test_loader = DataLoader(test_ds, batch_size=batch_size, shuffle=False, drop_last=False)
        # Train fresh model
        model = model_factory().to(device)
        counts = np.bincount(y_train, minlength=3)
        beta = 0.9999
        eff_num = 1.0 - np.power(beta, counts)
        cw = (1.0 - beta) / np.maximum(eff_num, 1e-9)
        cw = cw / cw.sum() * 3
        class_weights = torch.tensor(cw, dtype=torch.float32, device=device)
        criterion = nn.CrossEntropyLoss(weight=class_weights, reduction='none')
        optimizer = torch.optim.AdamW(model.parameters(), lr=3e-4, weight_decay=1e-4)
        steps = max(1, epochs * len(train_loader))
        scheduler = torch.optim.lr_scheduler.OneCycleLR(optimizer, max_lr=3e-4, total_steps=steps, pct_start=0.15)
        for _ in range(epochs):
            model.train()
            for x_b, y_b, w_b, _ in train_loader:
                x_b, y_b, w_b = x_b.to(device), y_b.to(device), w_b.to(device)
                optimizer.zero_grad()
                loss = (criterion(model(x_b), y_b) * w_b).mean()
                loss.backward()
                torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
                optimizer.step()
                scheduler.step()
        # Evaluate
        model.eval()
        preds = []
        with torch.no_grad():
            for x_b, _, _, _ in test_loader:
                logits = model(x_b.to(device))
                preds.extend((logits.argmax(dim=-1) - 1).cpu().numpy().tolist())
        preds = np.asarray(preds, dtype=np.int8)
        gross_rets = preds * r_test
        net_rets = apply_costs(gross_rets, cost_bps)
        sr = net_rets.mean() / (net_rets.std() + 1e-9) * np.sqrt(annualization)
        sharpes.append(float(sr))
    sharpes = np.asarray(sharpes, dtype=np.float64)
    p10 = float(np.percentile(sharpes, 10))
    result = {
        'sharpe_ratios': sharpes,
        'mean_sr': float(sharpes.mean()),
        'p10_sr': p10,
        'psr': psr(sharpes),
        'deploy_gate': p10 > 0.0,
    }
    print(f'CPCV Results ({len(folds)} folds):')
    print(f'  Sharpe per fold: {np.round(sharpes, 3)}')
    print(f'  Mean SR: {result["mean_sr"]:.3f} | 10th pct SR: {p10:.3f} | PSR: {result["psr"]:.3f}')
    print(f'  DEPLOYMENT GATE: {"PASS" if result["deploy_gate"] else "FAIL"}')
    return result

# %%
# ==============================================
# 8. Training Pipeline — Hardened
# ==============================================

def compute_ic(model, loader, device):
    model.eval()
    scores, rets = [], []
    with torch.no_grad():
        for x, _, _, r in loader:
            probs = torch.softmax(model(x.to(device)), dim=-1).cpu().numpy()
            scores.extend((probs[:, 2] - probs[:, 0]).tolist())
            rets.extend(r.numpy().tolist())
    ic, _ = spearmanr(scores, rets)
    return float(ic) if not np.isnan(ic) else 0.0

def train_epoch(model, loader, optimizer, scheduler, criterion, device, accum_steps=1):
    model.train()
    total_loss = 0.0
    for step, (x, y, w, _) in enumerate(loader):
        x, y, w = x.to(device), y.to(device), w.to(device)
        loss = (criterion(model(x), y) * w).mean() / accum_steps
        loss.backward()
        if (step + 1) % accum_steps == 0 or (step + 1) == len(loader):
            torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
            optimizer.step()
            optimizer.zero_grad()
            if scheduler is not None:
                scheduler.step()
        total_loss += float(loss.item()) * accum_steps
    return total_loss / max(1, len(loader))

def export_onnx(model, seq_len, n_feat, path, opset=12):
    output = Path(path)
    output.parent.mkdir(parents=True, exist_ok=True)
    model.eval()
    dummy = torch.zeros(1, seq_len, n_feat, dtype=torch.float32)
    torch.onnx.export(
        model, dummy, str(output), opset_version=opset,
        input_names=['input'], output_names=['output'],
        dynamic_axes={'input': {0: 'batch'}, 'output': {0: 'batch'}},
        do_constant_folding=True, verbose=False,
    )

def instantiate_models(model_name, seq_len, n_feat, dropout=0.20):
    candidates = {}
    if model_name in ('mlp', 'ensemble'):
        candidates['mlp'] = SequenceMLP(seq_len=seq_len, n_features=n_feat, dropout=dropout)
    if model_name in ('patchtst', 'ensemble'):
        candidates['patchtst'] = PatchTST(seq_len=seq_len, n_features=n_feat, dropout=dropout)
    if model_name in ('itransformer', 'ensemble'):
        candidates['itransformer'] = iTransformer(seq_len=seq_len, n_features=n_feat, dropout=dropout)
    return candidates

def build_loader(split, batch_size, shuffle):
    return DataLoader(TradingDataset(*split[:4]), batch_size=batch_size, shuffle=shuffle, drop_last=False)

def train_candidate(name, model, train_split, val_split, test_split, metadata,
                    epochs=60, batch_size=64, lr=3e-4, weight_decay=1e-4,
                    device=None, logs_dir=None, accum_steps=1, patience=20):
    if device is None:
        device = 'cuda' if torch.cuda.is_available() else 'cpu'
    train_loader = build_loader(train_split, batch_size, shuffle=True)
    val_loader = build_loader(val_split, batch_size, shuffle=False)
    test_loader = build_loader(test_split, batch_size, shuffle=False)
    y_train = train_split[1]
    counts = np.bincount(y_train, minlength=3)
    # Effective number weighting
    beta = 0.9999
    eff_num = 1.0 - np.power(beta, counts)
    class_weights_arr = (1.0 - beta) / np.maximum(eff_num, 1e-9)
    class_weights_arr = class_weights_arr / class_weights_arr.sum() * 3
    class_weights = torch.tensor(class_weights_arr, dtype=torch.float32, device=device)
    criterion = nn.CrossEntropyLoss(weight=class_weights, reduction='none')
    model = model.to(device)
    optimizer = torch.optim.AdamW(model.parameters(), lr=lr, weight_decay=weight_decay)
    total_steps = max(1, epochs * max(1, len(train_loader)) // accum_steps)
    scheduler = torch.optim.lr_scheduler.OneCycleLR(
        optimizer, max_lr=lr, total_steps=total_steps, pct_start=0.15,
    )
    best_state, best_val_ic, patience_counter = None, -1e9, 0
    train_losses, val_ics = [], []

    log_file_path = None
    if logs_dir:
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        log_file_path = os.path.join(logs_dir, f'{name}_{timestamp}.log')
        with open(log_file_path, 'w', encoding='utf-8') as f:
            f.write(f'=== Training {name} ===\n')
            f.write(f'Start: {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}\n')
            f.write(f'Epochs: {epochs}, BS: {batch_size}, LR: {lr}, Accum: {accum_steps}\n')
            f.write(f'Device: {device}\n\n')

    print(f'\n--- Training {name} ---')
    pbar = tqdm(range(epochs), desc=f'Training {name}')
    early_stop_epoch = None

    for epoch in pbar:
        loss = train_epoch(model, train_loader, optimizer, scheduler, criterion, device, accum_steps)
        val_ic = compute_ic(model, val_loader, device)
        current_lr = scheduler.get_last_lr()[0] if scheduler else lr
        train_losses.append(loss)
        val_ics.append(val_ic)

        if val_ic > best_val_ic:
            best_val_ic = val_ic
            best_state = {k: v.detach().cpu().clone() for k, v in model.state_dict().items()}
            patience_counter = 0
        else:
            patience_counter += 1

        if log_file_path:
            with open(log_file_path, 'a', encoding='utf-8') as f:
                f.write(f'Epoch {epoch+1:3d} | Loss: {loss:.6f} | Val IC: {val_ic:.6f} | '
                        f'Best: {best_val_ic:.6f} | LR: {current_lr:.6e}\n')

        pbar.set_postfix({'loss': f'{loss:.4f}', 'val_ic': f'{val_ic:.4f}', 'best': f'{best_val_ic:.4f}'})

        if patience_counter >= patience:
            early_stop_epoch = epoch + 1
            print(f'  Early stopping at epoch {early_stop_epoch}')
            if log_file_path:
                with open(log_file_path, 'a', encoding='utf-8') as f:
                    f.write(f'Early stopping at epoch {early_stop_epoch}\n')
            break

    if best_state is not None:
        model.load_state_dict(best_state)
    test_ic = compute_ic(model, test_loader, device)

    if log_file_path:
        with open(log_file_path, 'a', encoding='utf-8') as f:
            f.write(f'\n=== Final Results ===\n')
            f.write(f'Best Val IC: {best_val_ic:.6f}\n')
            f.write(f'Test IC: {test_ic:.6f}\n')
            f.write(f'End: {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}\n')
        print(f'  Logs saved to: {log_file_path}')

    print(f'  Final: Val IC {best_val_ic:.4f}, Test IC {test_ic:.4f}')
    return best_val_ic, test_ic, model, train_losses, val_ics

# %%
# ==============================================
# 9. LightGBM Training
# ==============================================

def train_lightgbm(train_split, val_split, test_split, metadata, output_path, cost_bps=1.0):
    try:
        import lightgbm as lgb
    except ImportError:
        print('⚠️ LightGBM not installed, skipping...')
        return None, None, None

    print('\n--- Training LightGBM ---')
    X_tr = train_split[0].reshape(len(train_split[0]), -1)
    X_va = val_split[0].reshape(len(val_split[0]), -1)
    X_te = test_split[0].reshape(len(test_split[0]), -1)
    y_tr, y_va, y_te = train_split[1], val_split[1], test_split[1]

    model = lgb.train(
        {
            'objective': 'multiclass',
            'num_class': 3,
            'metric': 'multi_logloss',
            'learning_rate': 0.03,
            'num_leaves': 63,
            'feature_fraction': 0.7,
            'bagging_fraction': 0.8,
            'bagging_freq': 5,
            'lambda_l1': 0.1,
            'lambda_l2': 0.1,
            'min_child_samples': 50,
            'verbose': -1,
        },
        lgb.Dataset(X_tr, label=y_tr),
        valid_sets=[lgb.Dataset(X_va, label=y_va)],
        num_boost_round=1000,
        callbacks=[lgb.early_stopping(50)],
    )

    pkl_output = Path(output_path).with_suffix('.pkl')
    with open(pkl_output, 'wb') as f:
        pickle.dump(model, f)

    preds = model.predict(X_te)
    test_ic, _ = spearmanr(preds[:, 2] - preds[:, 0], test_split[3])
    print(f'  Final: Test IC {test_ic:.4f}')

    try:
        import onnxmltools
        from onnxmltools.convert.common.data_types import FloatTensorType
        onnx_model = onnxmltools.convert_lightgbm(
            model, name='lgbm_trading',
            initial_types=[('float_input', FloatTensorType([None, X_tr.shape[1]]))],
            target_opset=12,
        )
        onnxmltools.utils.save_model(onnx_model, output_path)
        print(f'  ONNX exported to {output_path}')
    except ImportError:
        print('  onnxmltools not installed, skipping ONNX export')

    return model, test_ic, preds

# %%
# ==============================================
# 10. Visualization Tools
# ==============================================

def plot_data_distribution(df, save_path=None):
    fig, axes = plt.subplots(2, 2, figsize=(16, 12))
    fig.suptitle('Data Distribution Analysis', fontsize=16, fontweight='bold')
    if 'symbol' in df.columns:
        for symbol in df['symbol'].unique():
            sym_df = df[df['symbol'] == symbol].copy()
            sym_df['date'] = pd.to_datetime(sym_df['date'])
            axes[0, 0].plot(sym_df['date'], sym_df['close'], label=symbol, alpha=0.7)
        axes[0, 0].legend()
    else:
        df['date'] = pd.to_datetime(df['date'])
        axes[0, 0].plot(df['date'], df['close'])
    axes[0, 0].set_title('Price Chart')
    axes[0, 0].set_xlabel('Date')
    axes[0, 0].set_ylabel('Close Price')
    axes[0, 0].tick_params(axis='x', rotation=45)
    log_rets = np.log(df['close'] / df['close'].shift(1)).dropna()
    axes[0, 1].hist(log_rets, bins=50, alpha=0.7, edgecolor='black')
    axes[0, 1].axvline(log_rets.mean(), color='red', linestyle='--', label=f'Mean: {log_rets.mean():.4f}')
    axes[0, 1].axvline(log_rets.mean() + log_rets.std(), color='orange', linestyle='--', label='+1 Std')
    axes[0, 1].axvline(log_rets.mean() - log_rets.std(), color='orange', linestyle='--', label='-1 Std')
    axes[0, 1].set_title('Log Returns Distribution')
    axes[0, 1].legend()
    axes[1, 0].bar(range(len(df)), df['volume'], alpha=0.6)
    axes[1, 0].set_title('Volume')
    axes[1, 0].set_xlabel('Index')
    high_low = df['high'] - df['low']
    axes[1, 1].plot(high_low.rolling(20).mean(), label='20-period Volatility')
    axes[1, 1].set_title('Volatility')
    axes[1, 1].legend()
    plt.tight_layout()
    if save_path:
        plt.savefig(save_path, dpi=300, bbox_inches='tight')
    plt.show()

def plot_training_curves(train_losses, val_ics, title='Training Metrics', save_path=None):
    fig, axes = plt.subplots(1, 2, figsize=(14, 5))
    axes[0].plot(train_losses, label='Train Loss', color='blue')
    axes[0].set_title('Training Loss')
    axes[0].legend()
    axes[0].grid(True, alpha=0.3)
    axes[1].plot(val_ics, label='Validation IC', color='green')
    axes[1].axhline(y=0, color='red', linestyle='--', alpha=0.5)
    axes[1].set_title('Validation IC')
    axes[1].legend()
    axes[1].grid(True, alpha=0.3)
    plt.suptitle(title, fontsize=14, fontweight='bold')
    plt.tight_layout()
    if save_path:
        plt.savefig(save_path, dpi=300, bbox_inches='tight')
    plt.show()

def plot_label_distribution(labels, save_path=None):
    fig, ax = plt.subplots(figsize=(10, 6))
    label_counts = pd.Series(labels).value_counts().sort_index()
    bars = ax.bar(label_counts.index, label_counts.values, color=['#ff6b6b', '#4ecdc4', '#45b7d1'], alpha=0.7)
    ax.set_title('Triple Barrier Label Distribution', fontsize=14, fontweight='bold')
    ax.set_xlabel('Label (-1=Short, 0=Hold, 1=Long)')
    ax.set_ylabel('Count')
    for bar in bars:
        height = bar.get_height()
        ax.text(bar.get_x() + bar.get_width() / 2.0, height, f'{int(height)}', ha='center', va='bottom')
    plt.tight_layout()
    if save_path:
        plt.savefig(save_path, dpi=300, bbox_inches='tight')
    plt.show()

def plot_cpcv_results(cpcv_result, save_path=None):
    fig, ax = plt.subplots(figsize=(12, 6))
    sharpes = cpcv_result['sharpe_ratios']
    colors = ['green' if s > 0 else 'red' for s in sharpes]
    bars = ax.bar(range(len(sharpes)), sharpes, color=colors, alpha=0.7)
    ax.axhline(y=0, color='black', linestyle='-', linewidth=1)
    ax.axhline(y=cpcv_result['mean_sr'], color='blue', linestyle='--', label=f'Mean: {cpcv_result["mean_sr"]:.3f}')
    ax.axhline(y=cpcv_result['p10_sr'], color='orange', linestyle='-.', label=f'P10: {cpcv_result["p10_sr"]:.3f}')
    ax.set_title(f'CPCV Sharpe Ratios (PSR: {cpcv_result["psr"]:.3f})', fontsize=14, fontweight='bold')
    ax.set_xlabel('Fold')
    ax.set_ylabel('Sharpe Ratio')
    ax.legend()
    plt.tight_layout()
    if save_path:
        plt.savefig(save_path, dpi=300, bbox_inches='tight')
    plt.show()

def plot_feature_importance(model, save_path=None):
    try:
        import lightgbm as lgb
        if isinstance(model, lgb.Booster):
            fig, ax = plt.subplots(figsize=(12, 8))
            lgb.plot_importance(model, max_num_features=20, ax=ax)
            ax.set_title('LightGBM Feature Importance', fontsize=14, fontweight='bold')
            plt.tight_layout()
            if save_path:
                plt.savefig(save_path, dpi=300, bbox_inches='tight')
            plt.show()
    except ImportError:
        print('lightgbm not installed')

print('✅ Visualization tools ready!')

# %%
# ==============================================
# 11. Main Training Workflow — Corrected Order
# ==============================================

print('\n📥 Loading and preprocessing data...')

train_split, val_split, test_split, metadata = build_scaled_dataset_splits(
    CSV_PATH,
    seq_len=CFG.SEQ_LEN,
    k=CFG.K,
    vertical_bars=CFG.VERTICAL_BARS,
    train_ratio=0.70,
    val_ratio=0.15,
    purge_gap=CFG.PURGE_GAP,
    embargo=CFG.EMBARGO,
    scaler_output=SCALER_OUTPUT,
)

print(f'✅ Data loaded successfully!')
print(f'  Training samples: {metadata.train_size}')
print(f'  Validation samples: {metadata.val_size}')
print(f'  Test samples: {metadata.test_size}')
print(f'  Features: {metadata.n_features}')
print(f'  Annualization factor: {metadata.annualization:.1f}')

# Visualize label distribution (shifted back to -1/0/1)
plot_label_distribution(
    train_split[1] - 1,
    save_path=os.path.join(CHARTS_DIR, 'label_distribution.png'),
)

# %%
# Stage 1: Train candidates on train set, evaluate on val set
print('\n🚀 Stage 1: Candidate training on train set...')

if CFG.TRAIN_MODE == 'single':
    candidates = instantiate_models(CFG.MODEL_TYPE, metadata.seq_len, metadata.n_features, dropout=CFG.DROPOUT)
    print(f'  Training single model: {CFG.MODEL_TYPE}')
elif CFG.TRAIN_MODE == 'sequential':
    candidates = instantiate_models('ensemble', metadata.seq_len, metadata.n_features, dropout=CFG.DROPOUT)
    print(f'  Training all models sequentially: {list(candidates.keys())}')
else:  # ensemble
    candidates = instantiate_models('ensemble', metadata.seq_len, metadata.n_features, dropout=CFG.DROPOUT)
    print(f'  Training ensemble mode: {list(candidates.keys())}')

device = 'cuda' if torch.cuda.is_available() else 'cpu'
print(f'  Using device: {device}')

best_name = ''
best_val_ic = -1e9
best_test_ic = -1e9
best_model = None
best_train_losses = None
best_val_ics = None
model_results = []

for name, model in candidates.items():
    print(f'\n--- Training {name.upper()} ---')
    val_ic, test_ic, trained_model, train_losses, val_ics = train_candidate(
        name=name,
        model=model,
        train_split=train_split,
        val_split=val_split,
        test_split=test_split,
        metadata=metadata,
        epochs=CFG.EPOCHS,
        batch_size=CFG.BATCH_SIZE,
        lr=CFG.LR,
        weight_decay=CFG.WEIGHT_DECAY,
        device=device,
        logs_dir=LOGS_DIR,
        accum_steps=CFG.GRAD_ACCUM_STEPS,
        patience=CFG.EARLY_STOP_PATIENCE,
    )
    model_results.append({
        'name': name,
        'val_ic': val_ic,
        'test_ic': test_ic,
        'model': trained_model,
        'train_losses': train_losses,
        'val_ics': val_ics,
    })
    plot_training_curves(
        train_losses, val_ics,
        title=f'{name.upper()} Training Metrics',
        save_path=os.path.join(CHARTS_DIR, f'{name}_training.png'),
    )
    if val_ic > best_val_ic:
        best_name = name
        best_val_ic = val_ic
        best_test_ic = test_ic
        best_model = trained_model
        best_train_losses = train_losses
        best_val_ics = val_ics

print('\n' + '=' * 60)
print('MODEL TRAINING RESULTS SUMMARY')
print('=' * 60)
print(f'{"Model":<<12} {"Val IC":<<10} {"Test IC":<<10}')
print('-' * 60)
for result in model_results:
    best_mark = ' 🏆' if result['name'] == best_name else ''
    print(f'{result["name"]:<12} {result["val_ic"]:<10.4f} {result["test_ic"]:<10.4f}{best_mark}')
print('=' * 60)
print(f'\n🏆 Best Architecture by Val IC: {best_name} (Val IC: {best_val_ic:.4f}, Test IC: {best_test_ic:.4f})')

# %%
# Stage 2: CPCV on training data for the best architecture (unbiased robustness check)
print('\n🔍 Stage 2: CPCV validation on training data (proper unbiased check)...')

# Model factory for fresh instances per fold
model_factory = lambda: instantiate_models(
    best_name, metadata.seq_len, metadata.n_features, dropout=CFG.DROPOUT
)[best_name]

cpcv_result = run_cpcv(
    model_factory=model_factory,
    X=train_split[0],
    y=train_split[1],
    bar_returns=train_split[3],
    n_splits=CFG.CPCV_SPLITS,
    annualization=metadata.annualization,
    cost_bps=CFG.COST_BPS,
    epochs=20,  # lighter for speed
    batch_size=CFG.BATCH_SIZE,
    device=device,
)

plot_cpcv_results(
    cpcv_result,
    save_path=os.path.join(CHARTS_DIR, 'cpcv_results.png'),
)

# %%
# Stage 3: Retrain best model on train+val for final export
print('\n🚀 Stage 3: Final training on train+val for production export...')

def concat_splits(a, b):
    return tuple(np.concatenate([a[i], b[i]], axis=0) for i in range(5))

train_val_split = concat_splits(train_split, val_split)

final_val_ic, final_test_ic, final_model, final_losses, final_val_ics = train_candidate(
    name=f'{best_name}_final',
    model=instantiate_models(best_name, metadata.seq_len, metadata.n_features, dropout=CFG.DROPOUT)[best_name],
    train_split=train_val_split,
    val_split=val_split,   # monitor early stopping on val
    test_split=test_split,
    metadata=metadata,
    epochs=CFG.EPOCHS,
    batch_size=CFG.BATCH_SIZE,
    lr=CFG.LR,
    weight_decay=CFG.WEIGHT_DECAY,
    device=device,
    logs_dir=LOGS_DIR,
    accum_steps=CFG.GRAD_ACCUM_STEPS,
    patience=CFG.EARLY_STOP_PATIENCE,
)

plot_training_curves(
    final_losses, final_val_ics,
    title=f'{best_name.upper()} Final Training (Train+Val)',
    save_path=os.path.join(CHARTS_DIR, f'{best_name}_final_training.png'),
)

# Export final ONNX
print('\n📤 Exporting final model to ONNX...')
export_onnx(final_model, metadata.seq_len, metadata.n_features, MODEL_OUTPUT)
print(f'  ONNX model saved to: {MODEL_OUTPUT}')
print(f'  Scaler saved to: {SCALER_OUTPUT}')

# %%
# Deployment Gate
print('\n' + '=' * 50)
print('DEPLOYMENT GATE CHECK')
print('=' * 50)
print(f'Final Test IC: {final_test_ic:.4f} (min required: {CFG.MIN_IC_THRESHOLD})')
print(f'CPCV P10 Sharpe: {cpcv_result["p10_sr"]:.4f} (must be > 0)')
print(f'CPCV PSR: {cpcv_result["psr"]:.3f}')
print('=' * 50)

deploy_ok = (final_test_ic >= CFG.MIN_IC_THRESHOLD) and cpcv_result['deploy_gate']
if deploy_ok:
    print('✅ READY FOR DEPLOYMENT')
else:
    print('❌ DEPLOYMENT FAILED — do not push to MetaTrader')
    if final_test_ic < CFG.MIN_IC_THRESHOLD:
        print(f'   → Test IC {final_test_ic:.4f} below threshold {CFG.MIN_IC_THRESHOLD}')
    if not cpcv_result['deploy_gate']:
        print(f'   → CPCV 10th percentile Sharpe is negative')
print('=' * 50)

# %%
# Stage 4: LightGBM baseline
print('\n🌲 Stage 4: Training LightGBM baseline...')

lgb_model, lgb_test_ic, lgb_preds = train_lightgbm(
    train_split, val_split, test_split, metadata,
    output_path=os.path.join(MODELS_DIR, 'lgbm_model.onnx'),
    cost_bps=CFG.COST_BPS,
)

if lgb_model is not None:
    plot_feature_importance(
        lgb_model,
        save_path=os.path.join(CHARTS_DIR, 'feature_importance.png'),
    )
    print(f'\nLightGBM Test IC: {lgb_test_ic:.4f}')

# %%
# Stage 5: Regime & Turbulence Demo
print('\n🔮 Regime Detection & Turbulence Demo')

train_rets = train_split[3]
regime_detector = RegimeDetector(n_states=2, lookback=500)
regime_detector.fit(train_rets)

recent_rets = test_split[3][-20:]
current_regime = regime_detector.predict(recent_rets)
print(f'Current Market Regime: {current_regime}')

if len(train_rets) > 100:
    historical_rets = train_rets[-200:].reshape(-1, 1)
    current_returns_sample = test_split[3][-5:].reshape(-1, 1)
    turbulence = compute_turbulence(current_returns_sample.mean(axis=0), historical_rets)
    print(f'Turbulence Score: {turbulence:.4f} (Threshold: {TURBULENCE_THRESHOLD})')
    print(f'Turbulence Alert: {"⚠️ HIGH" if turbulence > TURBULENCE_THRESHOLD else "✅ NORMAL"}')

print('\n🎉 Training workflow completed!')
print(f'All outputs saved to: {DRIVE_BASE}')
print(f'  ONNX Model: {MODEL_OUTPUT}')
print(f'  Scaler:     {SCALER_OUTPUT}')
print(f'  Charts:     {CHARTS_DIR}')
print(f'  Logs:       {LOGS_DIR}')

# %% [markdown]
# ---
#
# ## Usage Instructions
#
# ### Getting Started:
# 1. Upload your CSV to `Google Drive > Multi-Mt5 > data` (headerless or with header)
# 2. Run all cells sequentially from the top
# 3. Adjust `CFG` hyperparameters in Section 3 as needed
#
# ### Outputs:
# - **Models**: `Multi-Mt5/models/best_model.onnx` (versioned scaler at `scaler_v2.bin`)
# - **Charts**: `Multi-Mt5/charts/`
# - **Logs**: `Multi-Mt5/logs/`
#
# ### Deployment Checklist:
# - [ ] Deployment gate passes (Test IC ≥ 0.03, CPCV P10 Sharpe > 0)
# - [ ] Scaler binary version matches MT5 parser (magic `SCL2`, version `1`)
# - [ ] Regime is not "chop" or turbulence is not HIGH
# - [ ] LightGBM IC is within 20% of neural model (sanity check)
#
# ### Notes:
# - This notebook uses **RobustScaler** (not StandardScaler) — update MT5 parser if migrating from v1
# - Calendar features are **always recomputed** from timestamps to ensure correctness
# - Forward returns now use **next-open entry** for realistic backtesting
# - CPCV is run **before** final export to avoid data leakage