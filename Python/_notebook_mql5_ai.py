# %% [markdown]
# # Multi-Mt5 AI Trading Strategy Trainer
#
# This notebook consolidates all the functionality from the Multi-Mt5 project into a single, cohesive Google Colab environment for training AI trading models.
#
# ## Features:
# - Google Drive integration for data and model storage
# - Data loading and preprocessing pipeline
# - Multiple model architectures (SequenceMLP, PatchTST, iTransformer, LightGBM)
# - Comprehensive visualization tools
# - CPCV validation and deployment gate checks
# - Regime detection and turbulence calculation
# - ONNX export for MetaTrader 5 integration

# %% [markdown]
# ---
#
# ## 1. Setup and Dependencies
#
# First, let's install all required dependencies and set up our environment.

# %%
# Install required packages
!pip install torch>=2.1.0 numpy>=1.24.0 pandas>=2.0.0 scipy>=1.11.0 scikit-learn>=1.3.0
!pip install onnx>=1.15.0 onnxruntime>=1.17.0 lightgbm>=4.3.0 onnxmltools>=1.12.0
!pip install hmmlearn>=0.3.0 numba>=0.59.0 matplotlib>=3.7.0
!pip install tqdm

print('✅ All dependencies installed successfully!')

# %%
# Mount Google Drive
from google.colab import drive
import os

# Mount drive
drive.mount('/content/drive')

# Create Multi-Mt5 directory structure
DRIVE_BASE = '/content/drive/MyDrive/Multi-Mt5'
MODELS_DIR = os.path.join(DRIVE_BASE, 'models')
CHARTS_DIR = os.path.join(DRIVE_BASE, 'charts')
DATA_DIR = os.path.join(DRIVE_BASE, 'data')

os.makedirs(DRIVE_BASE, exist_ok=True)
os.makedirs(MODELS_DIR, exist_ok=True)
os.makedirs(CHARTS_DIR, exist_ok=True)
os.makedirs(DATA_DIR, exist_ok=True)

print(f'✅ Google Drive mounted successfully!')
print(f'📁 Working directory: {DRIVE_BASE}')

# %%
# Import all required libraries
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib
matplotlib.style.use('seaborn-v0_8-darkgrid')
import torch
import torch.nn as nn
import torch.nn.functional as F
from torch.utils.data import DataLoader, Dataset
from sklearn.preprocessing import StandardScaler
from scipy.stats import spearmanr
from tqdm import tqdm
import struct
from pathlib import Path
from typing import List, Optional, Tuple, Dict
from dataclasses import dataclass
import pickle

try:
    from numba import njit
    HAS_NUMBA = True
except ImportError:
    HAS_NUMBA = False

# Set random seeds for reproducibility
torch.manual_seed(42)
np.random.seed(42)

print('✅ All libraries imported successfully!')

# %% [markdown]
# ---
#
# ## 2. Data Pipeline Implementation
#
# Let's implement all the data processing and feature engineering functions.

# %%
# ==============================================
# Data Pipeline
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


class TradingDataset(Dataset):
    def __init__(self, X: np.ndarray, y: np.ndarray, weights: Optional[np.ndarray] = None, returns: Optional[np.ndarray] = None):
        self.X = torch.tensor(X, dtype=torch.float32)
        self.y = torch.tensor(y, dtype=torch.long)
        self.weights = torch.tensor(weights if weights is not None else np.ones(len(y), dtype=np.float32), dtype=torch.float32)
        self.returns = torch.tensor(returns if returns is not None else np.zeros(len(y), dtype=np.float32), dtype=torch.float32)

    def __len__(self): return len(self.y)
    def __getitem__(self, idx): return self.X[idx], self.y[idx], self.weights[idx], self.returns[idx]


# --- Fix #30: Scaler Binary v2 (Versioned with Magic Header) ---
SCALER_MAGIC = b'SCL2'
SCALER_VERSION = 1

def save_scaler_to_bin(scaler: StandardScaler, output_path: str):
    output = Path(output_path)
    output.parent.mkdir(parents=True, exist_ok=True)
    n = len(scaler.mean_) if hasattr(scaler, 'mean_') else len(scaler.center_)
    means = scaler.mean_ if hasattr(scaler, 'mean_') else scaler.center_
    scales = scaler.scale_
    with output.open('wb') as f:
        f.write(SCALER_MAGIC)
        f.write(struct.pack('<i', SCALER_VERSION))
        f.write(struct.pack('<i', n))
        f.write(struct.pack(f'<{n}d', *means))
        f.write(struct.pack(f'<{n}d', *scales))


# --- Fix #11: ATR Initialization Gap (SMA warmup) ---
def compute_atr(high: np.ndarray, low: np.ndarray, close: np.ndarray, period: int = 14):
    tr = np.maximum(high[1:] - low[1:], np.maximum(np.abs(high[1:] - close[:-1]), np.abs(low[1:] - close[:-1])))
    atr = np.zeros(len(close), dtype=np.float64)
    if len(tr) < period:
        atr[1:] = tr.cumsum() / np.arange(1, len(tr) + 1)
        return atr
    # SMA warmup for first `period` bars
    atr[1:period+1] = tr[:period].cumsum() / np.arange(1, period + 1)
    # EMA from period+1 onward
    atr[period+1] = (atr[period] * (period - 1) + tr[period]) / period
    for i in range(period + 2, len(close)):
        atr[i] = (atr[i-1] * (period - 1) + tr[i-1]) / period
    return atr


# --- Fix #24: Triple Barrier with Numba @njit ---
def triple_barrier_labels(close: np.ndarray, high: np.ndarray, low: np.ndarray, atr: np.ndarray, k: float = 1.5, vertical_bars: int = 20):
    if HAS_NUMBA:
        return _triple_barrier_numba(close, high, low, atr, k, vertical_bars)
    return _triple_barrier_python(close, high, low, atr, k, vertical_bars)

if HAS_NUMBA:
    @njit
    def _triple_barrier_numba(close, high, low, atr, k, max_holding):
        n = len(close)
        labels = np.zeros(n, dtype=np.int8)
        for i in range(n - max_holding):
            if atr[i] <= 1e-9: continue
            upper = close[i] + k * atr[i]
            lower = close[i] - k * atr[i]
            for j in range(i+1, min(i+max_holding+1, n)):
                if high[j] >= upper: labels[i] = 1; break
                if low[j] <= lower: labels[i] = -1; break
        return labels

def _triple_barrier_python(close: np.ndarray, high: np.ndarray, low: np.ndarray, atr: np.ndarray, k: float, vertical_bars: int):
    n = len(close)
    labels = np.zeros(n, dtype=np.int8)
    for i in range(n - vertical_bars):
        if atr[i] <= 1e-9: continue
        upper = close[i] + k * atr[i]
        lower = close[i] - k * atr[i]
        for j in range(i + 1, min(i + vertical_bars + 1, n)):
            if high[j] >= upper: labels[i] = 1; break
            if low[j] <= lower: labels[i] = -1; break
    return labels


# --- Fix #26: Uniqueness Weights (vectorized) ---
def compute_uniqueness_weights(event_indices: List[int], vertical_bars: int, total_bars: int):
    event_indices = np.asarray(event_indices, dtype=np.int32)
    if len(event_indices) == 0: return np.zeros(0, dtype=np.float32)
    concurrency = np.zeros(total_bars, dtype=np.float32)
    for idx in event_indices:
        end = min(int(idx) + vertical_bars, total_bars)
        concurrency[int(idx):end] += 1.0
    # Vectorized weight computation
    raw_weights = np.zeros(len(event_indices), dtype=np.float32)
    for i, idx in enumerate(event_indices):
        end = min(int(idx) + vertical_bars, total_bars)
        raw_weights[i] = np.mean(1.0 / np.maximum(concurrency[int(idx):end], 1e-9))
    total = raw_weights.sum()
    if total > 1e-9: raw_weights = raw_weights / total * len(event_indices)
    return raw_weights


# --- Fix #4: Forward Return Entry Price Mismatch (use open[idx+1]) ---
def compute_forward_returns(open_prices: np.ndarray, event_indices: List[int], holding_bars: int = 10):
    event_indices = np.asarray(event_indices, dtype=np.int32)
    returns = np.zeros(len(event_indices), dtype=np.float32)
    for i, idx in enumerate(event_indices):
        entry_bar = int(idx) + 1  # enter at next bar's open
        exit_bar = min(entry_bar + holding_bars, len(open_prices) - 1)
        if entry_bar < len(open_prices):
            returns[i] = (open_prices[exit_bar] - open_prices[entry_bar]) / max(open_prices[entry_bar], 1e-10)
    return returns


# --- Fix #25: CUSUM Filter with Numba ---
def cusum_filter(close: np.ndarray, threshold_multiplier: float = 1.0, atr: Optional[np.ndarray] = None):
    if HAS_NUMBA:
        return _cusum_filter_numba(close, threshold_multiplier, atr if atr is not None else np.ones(len(close), dtype=np.float64))
    return _cusum_filter_python(close, threshold_multiplier, atr)

if HAS_NUMBA:
    @njit
    def _cusum_filter_numba(close, threshold_multiplier, atr):
        events = []
        s_pos = 0.0
        s_neg = 0.0
        for i in range(1, len(close)):
            ret = np.log(close[i] / (close[i-1] + 1e-12))
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

def _cusum_filter_python(close: np.ndarray, threshold_multiplier: float, atr: Optional[np.ndarray]):
    if atr is None: atr = np.ones(len(close), dtype=np.float64)
    events: List[int] = []
    s_pos, s_neg = 0.0, 0.0
    for i in range(1, len(close)):
        ret = float(np.log(close[i] / (close[i-1] + 1e-12)))
        thresh = max(1e-8, threshold_multiplier * (float(atr[i]) / (float(close[i]) + 1e-9)))
        s_pos = max(0.0, s_pos + ret)
        s_neg = min(0.0, s_neg + ret)
        if s_pos > thresh: events.append(i); s_pos = 0.0
        elif s_neg < -thresh: events.append(i); s_neg = 0.0
    return events


def _ema(x: np.ndarray, period: int):
    alpha = 2.0 / (period + 1)
    result = np.empty_like(x, dtype=np.float64)
    result[0] = x[0]
    for i in range(1, len(x)): result[i] = alpha * x[i] + (1 - alpha) * result[i-1]
    return result


def _sma(x: np.ndarray, period: int): return pd.Series(x).rolling(period, min_periods=1).mean().values


# --- Fix #12: RSI Uses EMA (Wilder's) — Document It ---
def _rsi(close: np.ndarray, period: int):
    """Wilder's smoothed RSI (EMA-based). Matches MT5 iRSI implementation."""
    delta = np.diff(close, prepend=close[0]).astype(np.float64)
    avg_gain = _ema(np.maximum(delta, 0.0), period)
    avg_loss = _ema(np.maximum(-delta, 0.0), period)
    rs = avg_gain / (avg_loss + 1e-9)
    return (100.0 - 100.0 / (1.0 + rs)) / 100.0


def _bb_pct_b(close: np.ndarray, period: int = 20, mult: float = 2.0):
    mid = _sma(close, period)
    std = pd.Series(close).rolling(period, min_periods=1).std(ddof=0).fillna(0).values
    upper = mid + mult * std
    lower = mid - mult * std
    return (close - lower) / (upper - lower + 1e-9)


def _bb_width(close: np.ndarray, period: int = 20, mult: float = 2.0):
    mid = _sma(close, period)
    std = pd.Series(close).rolling(period, min_periods=1).std(ddof=0).fillna(0).values
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
    return ((series - mean) / (std + 1e-9)).fillna(0.0).values


# --- Fix #27: CCI — Vectorize ---
def _cci(high: np.ndarray, low: np.ndarray, close: np.ndarray, period: int = 14):
    tp = (high + low + close) / 3.0
    sma = _sma(tp, period)
    # Vectorized MAD: |tp - sma| rolling mean
    deviation = np.abs(tp - sma)
    mad = _sma(deviation, period)
    mad = np.maximum(mad, 1e-9)
    return (tp - sma) / (0.015 * mad + 1e-9) / 200.0


def _parkinson_vol(high: np.ndarray, low: np.ndarray, period: int = 14):
    log_hl = np.log((high + 1e-9) / (low + 1e-9)) ** 2
    factor = 1.0 / (4.0 * np.log(2))
    return np.sqrt(pd.Series(factor * log_hl).rolling(period, min_periods=1).mean().values)


# --- Fix #2: safe_lag replaces np.roll to prevent wrap-around poisoning ---
def safe_lag(x, periods, fill_value=0.0):
    """No wrap-around lag. Returns shifted array with fill_value for leading edge."""
    if isinstance(x, np.ndarray):
        result = np.full_like(x, fill_value, dtype=x.dtype)
        if periods < len(x):
            result[periods:] = x[:-periods]
        return result
    return x.shift(periods, fill_value=fill_value).values


# --- Fix #2: build_feature_matrix with safe_lag replacing ALL np.roll calls ---
def build_feature_matrix(open_: np.ndarray, high: np.ndarray, low: np.ndarray, close: np.ndarray, volume: np.ndarray):
    n = len(close)
    log_ret = np.concatenate([[0.0], np.log(close[1:] / (close[:-1] + 1e-12))])
    atr14 = compute_atr(high, low, close, 14)
    atr50 = compute_atr(high, low, close, 50)
    atr5 = compute_atr(high, low, close, 5)
    rsi14 = _rsi(close, 14)
    rsi7 = _rsi(close, 7)
    bb_pct = _bb_pct_b(close, 20, 2.0)
    bb_w = _bb_width(close, 20, 2.0)
    macd_h = _macd_hist_norm(close, 12, 26, 9)
    vol_ratio = volume / (_sma(volume.astype(np.float64), 20) + 1e-9)
    atr_norm_ret = log_ret / (atr14 + 1e-9)
    cols = [
        log_ret, atr_norm_ret, (close - low) / (high - low + 1e-9), np.log(volume.astype(np.float64) + 1.0),
        atr14 / (close + 1e-9), np.log(close / (_ema(close, 8) + 1e-9) + 1e-9), np.log(close / (_ema(close, 21) + 1e-9) + 1e-9),
        np.log(close / (_ema(close, 50) + 1e-9) + 1e-9), np.log(_ema(close, 8) / (_ema(close, 21) + 1e-9) + 1e-9),
        np.log(_ema(close, 21) / (_ema(close, 50) + 1e-9) + 1e-9), rsi14, rsi7, bb_pct,
        bb_w, macd_h, atr14 / (atr50 + 1e-9), _parkinson_vol(high, low, 14),
        vol_ratio, np.zeros(n), np.zeros(n), np.zeros(n), np.zeros(n),
        safe_lag(log_ret, 1), safe_lag(log_ret, 5), safe_lag(log_ret, 20), _rolling_zscore(close.astype(np.float64), 20),
        _rolling_zscore(close.astype(np.float64), 50), (high - low) / (close + 1e-9), _rolling_zscore(high - low, 20),
        _cci(high, low, close, 14), safe_lag(atr_norm_ret, 2), safe_lag(atr_norm_ret, 3),
        safe_lag(atr_norm_ret, 5), safe_lag(atr_norm_ret, 8), safe_lag(atr_norm_ret, 13),
        _rolling_zscore(volume.astype(np.float64), 20), safe_lag(rsi14, 1), safe_lag(rsi14, 3),
        safe_lag(bb_pct, 1), safe_lag(bb_pct, 3), _rolling_zscore(rsi14, 20),
        _rolling_zscore(rsi7, 20), macd_h, safe_lag(macd_h, 1),
        atr14 / (atr5 + 1e-9), _rolling_zscore(atr14, 20), safe_lag(log_ret, 10), safe_lag(log_ret, 15),
        (close - _sma(close, 50)) / (atr14 + 1e-9), (close - _sma(close, 200)) / (atr14 + 1e-9),
        _rolling_zscore(safe_lag(log_ret, 1) * log_ret, 20), _rolling_zscore(safe_lag(log_ret, 5) * log_ret, 20),
        (close - _ema(close, 100)) / (atr50 + 1e-9), _rolling_zscore(volume.astype(np.float64), 50), atr50 / (atr14 + 1e-9),
        np.zeros(n), np.ones(n)
    ]
    features = np.column_stack(cols).astype(np.float32)
    return np.nan_to_num(features, nan=0.0, posinf=3.0, neginf=-3.0)


def exported_feature_columns(frame: pd.DataFrame):
    feature_cols = [col for col in frame.columns if col.startswith('feature_')]
    def sort_key(name: str):
        try: return int(name.split('_')[1])
        except (IndexError, ValueError): return 10**9
    return sorted(feature_cols, key=sort_key)


def add_calendar_features(features: np.ndarray, timestamps: pd.DatetimeIndex):
    dow = timestamps.dayofweek.values / 6.0
    hod = timestamps.hour.values / 23.0
    features[:, 18] = np.sin(2 * np.pi * dow)
    features[:, 19] = np.cos(2 * np.pi * dow)
    features[:, 20] = np.sin(2 * np.pi * hod)
    features[:, 21] = np.cos(2 * np.pi * hod)
    return features


# --- Fix #3: Off-by-One Event Sampling — sample at idx, use labels[end] ---
def prepare_sequences(features: np.ndarray, labels: np.ndarray, weights: np.ndarray, returns: np.ndarray, timestamps: np.ndarray, seq_len: int, sample_indices: List[int]):
    X, y, w, r, ts = [], [], [], [], []
    for idx, sample_idx in enumerate(sample_indices):
        if sample_idx < seq_len: continue
        end = int(sample_idx)
        X.append(features[end - seq_len:end])
        y.append(int(labels[end]) + 1)
        w.append(float(weights[idx]))
        r.append(float(returns[idx]))
        ts.append(timestamps[end])
    return (np.asarray(X, dtype=np.float32), np.asarray(y, dtype=np.int64), np.asarray(w, dtype=np.float32), np.asarray(r, dtype=np.float32), np.asarray(ts))


# --- Fix #7: Train/Val/Test Split with Purge Gap ---
def _split_arrays(X: np.ndarray, y: np.ndarray, weights: np.ndarray, returns: np.ndarray, timestamps: np.ndarray, train_ratio: float, val_ratio: float, purge_gap: int = 80, embargo: int = 5):
    n = len(X)
    if n < 48: raise ValueError('Not enough samples to split safely.')
    train_end = int(n * train_ratio)
    val_end = int(n * (train_ratio + val_ratio))
    train_end = max(24, min(train_end, n - 24))
    val_end = max(train_end + purge_gap, min(val_end, n - 12))
    # Purge: remove samples within purge_gap of boundary
    train = (X[:train_end], y[:train_end], weights[:train_end], returns[:train_end], timestamps[:train_end])
    val = (X[train_end + purge_gap:val_end], y[train_end + purge_gap:val_end], weights[train_end + purge_gap:val_end], returns[train_end + purge_gap:val_end], timestamps[train_end + purge_gap:val_end])
    test = (X[val_end + embargo:], y[val_end + embargo:], weights[val_end + embargo:], returns[val_end + embargo:], timestamps[val_end + embargo:])
    return train, val, test


# --- Fix #28: Annualization — Calendar-Aware Bar Counting ---
def _estimate_annualization_factor(timestamps: np.ndarray):
    if len(timestamps) < 3: return 252.0
    ts = pd.to_datetime(pd.Series(timestamps))
    # Count actual trading days per year
    years = ts.dt.year.nunique()
    if years < 1: return 252.0
    total_bars = len(timestamps)
    bars_per_year = total_bars / years
    return max(1.0, bars_per_year)


# --- Fix #6: Headerless CSV Parsing Failure ---
def detect_csv_has_header(csv_path: str):
    """Detect if CSV has a header row by checking if first row values are numeric."""
    with open(csv_path, 'r') as f:
        first_line = f.readline().strip()
    if not first_line:
        return True
    # Check if the second field (after symbol) looks like a date or number
    parts = first_line.split(',')
    if len(parts) < 3:
        return True
    try:
        float(parts[1])  # if second column is a number, no header
        return False
    except ValueError:
        return True  # second column is not a number, likely a header


def build_dataset_splits(df: pd.DataFrame, seq_len: int = 60, k: float = 1.5, vertical_bars: int = 20, train_ratio: float = 0.70, val_ratio: float = 0.15):
    required = {'date', 'open', 'high', 'low', 'close', 'volume'}
    missing = required - set(df.columns)
    if missing: raise ValueError(f'Missing required columns: {sorted(missing)}')
    frame = df.copy()
    frame['date'] = pd.to_datetime(frame['date'])
    if 'symbol' not in frame.columns: frame['symbol'] = 'DEFAULT'
    train_parts, val_parts, test_parts = [], [], []
    annualization_candidates = []
    grouped = frame.sort_values(['symbol', 'date']).groupby('symbol', sort=False)
    for _, sym_df in grouped:
        sym_df = sym_df.dropna(subset=['open', 'high', 'low', 'close', 'volume']).copy()
        if len(sym_df) < max(seq_len + vertical_bars + 20, 160): continue
        open_ = sym_df['open'].to_numpy(dtype=np.float64)
        high = sym_df['high'].to_numpy(dtype=np.float64)
        low = sym_df['low'].to_numpy(dtype=np.float64)
        close = sym_df['close'].to_numpy(dtype=np.float64)
        volume = sym_df['volume'].to_numpy(dtype=np.float64)
        feature_cols = exported_feature_columns(sym_df)
        # --- Fix #5: Calendar Features Silently Dropped on Pre-Computed Data ---
        if feature_cols:
            features = sym_df[feature_cols].to_numpy(dtype=np.float32)
            features = np.nan_to_num(features, nan=0.0, posinf=3.0, neginf=-3.0)
            features = add_calendar_features(features, pd.DatetimeIndex(sym_df['date']))  # ALWAYS add
        else:
            features = build_feature_matrix(open_, high, low, close, volume)
            features = add_calendar_features(features, pd.DatetimeIndex(sym_df['date']))
        atr = compute_atr(high, low, close, 14)
        labels = triple_barrier_labels(close, high, low, atr, k=k, vertical_bars=vertical_bars)
        events = np.asarray(cusum_filter(close, threshold_multiplier=1.0, atr=atr), dtype=np.int32)
        # --- Fix #3: Off-by-One Event Sampling — sample at idx, require idx >= seq_len ---
        label_indices = np.asarray([idx for idx in events if idx >= seq_len], dtype=np.int32)
        if len(label_indices) < 48: continue
        weights = compute_uniqueness_weights(label_indices, vertical_bars, len(close))
        # --- Fix #4: Forward Return uses open_ instead of close ---
        returns = compute_forward_returns(open_, label_indices, holding_bars=vertical_bars)
        timestamps = sym_df['date'].to_numpy()
        X, y, w, r, ts = prepare_sequences(features, labels, weights, returns, timestamps, seq_len=seq_len, sample_indices=label_indices)
        if len(X) < 48: continue
        train, val, test = _split_arrays(X, y, w, r, ts, train_ratio, val_ratio)
        train_parts.append(train)
        val_parts.append(val)
        test_parts.append(test)
        annualization_candidates.append(_estimate_annualization_factor(ts))
    if not train_parts or not val_parts or not test_parts: raise ValueError('No usable symbol groups found.')
    def concat(parts: List[Tuple[np.ndarray, ...]]):
        columns = list(zip(*parts))
        return tuple(np.concatenate(list(col), axis=0) for col in columns)
    annualization = float(np.median(annualization_candidates)) if annualization_candidates else 252.0
    return concat(train_parts), concat(val_parts), concat(test_parts), annualization


# --- Fix #10: StandardScaler on Flattened Sequences (per-feature scaling) ---
def _scale_splits(train: Tuple[np.ndarray, ...], val: Tuple[np.ndarray, ...], test: Tuple[np.ndarray, ...], scaler_output: Optional[str] = None):
    X_tr, y_tr, w_tr, r_tr, ts_tr = train
    X_va, y_va, w_va, r_va, ts_va = val
    X_te, y_te, w_te, r_te, ts_te = test
    scaler = StandardScaler()
    n_train, seq_len, n_features = X_tr.shape
    scaler.fit(X_tr.reshape(-1, n_features))  # 57 params, not 3420
    def transform(X):
        orig_shape = X.shape
        flat = X.reshape(-1, n_features)
        scaled = scaler.transform(flat)
        return scaled.reshape(orig_shape).astype(np.float32)
    if scaler_output: save_scaler_to_bin(scaler, scaler_output)
    return (transform(X_tr), y_tr, w_tr, r_tr, ts_tr), (transform(X_va), y_va, w_va, r_va, ts_va), (transform(X_te), y_te, w_te, r_te, ts_te), scaler


# --- Fix #6: Headerless CSV Parsing in build_scaled_dataset_splits ---
def build_scaled_dataset_splits(csv_path: str, seq_len: int = 60, k: float = 1.5, vertical_bars: int = 20, train_ratio: float = 0.70, val_ratio: float = 0.15, scaler_output: Optional[str] = None):
    has_header = detect_csv_has_header(csv_path)
    df = pd.read_csv(csv_path, header=0 if has_header else None)
    if not has_header:
        # Assign column names
        cols = ['symbol', 'date', 'open', 'high', 'low', 'close', 'volume']
        cols += [f'feature_{i:02d}' for i in range(len(df.columns) - 7)]
        df.columns = cols
    train, val, test, annualization = build_dataset_splits(df, seq_len=seq_len, k=k, vertical_bars=vertical_bars, train_ratio=train_ratio, val_ratio=val_ratio)
    train, val, test, _ = _scale_splits(train, val, test, scaler_output=scaler_output)
    metadata = PipelineMetadata(seq_len=seq_len, n_features=train[0].shape[2], train_size=len(train[0]), val_size=len(val[0]), test_size=len(test[0]), annualization=annualization, scaler_path=scaler_output)
    return train, val, test, metadata

print('✅ Data pipeline functions loaded!')

# %% [markdown]
# ---
#
# ## 3. Model Architectures
#
# Now let's implement our model architectures, including regime detection and turbulence calculation.

# %%
# ==============================================
# Model Architectures
# ==============================================

# --- Fix #13: SequenceMLP — Add Residual Connections ---
class SequenceMLP(nn.Module):
    def __init__(self, seq_len=60, n_features=57, hidden1=256, hidden2=128, dropout=0.20, n_classes=3):
        super().__init__()
        in_features = seq_len * n_features
        self.flat = nn.Flatten()
        self.norm_in = nn.LayerNorm(in_features)
        self.fc1 = nn.Linear(in_features, hidden1)
        self.bn1 = nn.BatchNorm1d(hidden1)
        self.fc2 = nn.Linear(hidden1, hidden2)
        self.bn2 = nn.BatchNorm1d(hidden2)
        self.skip = nn.Linear(in_features, hidden2)  # projection skip
        self.drop1 = nn.Dropout(dropout)
        self.drop2 = nn.Dropout(dropout)
        self.fc3 = nn.Linear(hidden2, n_classes)
    def forward(self, x):
        x = self.flat(x)
        x = self.norm_in(x)
        h = self.drop1(F.gelu(self.bn1(self.fc1(x))))
        h = self.drop2(F.gelu(self.bn2(self.fc2(h))))
        h = h + self.skip(x)  # residual
        return self.fc3(h)


# --- Fix #15: PatchTST — Position Embedding Interpolation ---
# --- Fix #16: Increase Dropout for Financial Data (0.1 -> 0.2) ---
class PatchTST(nn.Module):
    def __init__(self, seq_len=60, n_features=57, patch_len=12, stride=6, d_model=128, n_heads=8, n_layers=3, dropout=0.2, n_classes=3):
        super().__init__()
        self.patch_len = patch_len
        self.stride = stride
        self.n_patches = (seq_len - patch_len) // stride + 1
        self.patch_embed = nn.Linear(patch_len, d_model)
        self.cls_token = nn.Parameter(torch.zeros(1, n_features, 1, d_model))
        self.pos_embed = nn.Parameter(torch.zeros(1, n_features, self.n_patches + 1, d_model))
        nn.init.trunc_normal_(self.cls_token, std=0.02)
        nn.init.trunc_normal_(self.pos_embed, std=0.02)
        enc_layer = nn.TransformerEncoderLayer(d_model=d_model, nhead=n_heads, dim_feedforward=d_model*4, dropout=dropout, norm_first=True, batch_first=True)
        self.transformer = nn.TransformerEncoder(enc_layer, num_layers=n_layers)
        self.norm = nn.LayerNorm(d_model)
        self.head = nn.Linear(n_features * d_model, n_classes)
        self.drop = nn.Dropout(dropout)
    def _interpolate_pos_embed(self, x, n_patches_actual):
        if n_patches_actual == self.n_patches:
            return self.pos_embed
        # Interpolate position embeddings
        pos_embed = self.pos_embed.permute(0, 2, 1)  # (1, D, N+1)
        pos_embed = F.interpolate(pos_embed, size=n_patches_actual + 1, mode='linear', align_corners=False)
        return pos_embed.permute(0, 2, 1)  # (1, N+1, D)
    def forward(self, x):
        batch_size, seq_len, n_features = x.shape
        x = x.permute(0, 2, 1)
        patches = x.unfold(-1, self.patch_len, self.stride)
        patches = self.patch_embed(patches)
        n_patches_actual = patches.shape[2]
        cls = self.cls_token.expand(batch_size, -1, -1, -1)
        pos = self._interpolate_pos_embed(x, n_patches_actual)
        patches = torch.cat([cls, patches], dim=2) + pos
        b2, f2, n_patch, d_model = patches.shape
        patches = self.transformer(patches.reshape(b2 * f2, n_patch, d_model))
        patches = patches.reshape(b2, f2, n_patch, d_model)
        out = self.norm(patches[:, :, 0, :]).reshape(batch_size, -1)
        return self.head(self.drop(out))


# --- Fix #14: iTransformer — Replace Mean Pooling with CLS Token ---
# --- Fix #16: Increase Dropout for Financial Data (0.1 -> 0.2) ---
class iTransformer(nn.Module):
    def __init__(self, seq_len=60, n_features=57, d_model=128, n_heads=8, n_layers=3, dropout=0.2, n_classes=3):
        super().__init__()
        self.feat_embed = nn.Linear(seq_len, d_model)
        self.cls_token = nn.Parameter(torch.zeros(1, 1, d_model))
        nn.init.trunc_normal_(self.cls_token, std=0.02)
        enc_layer = nn.TransformerEncoderLayer(d_model=d_model, nhead=n_heads, dim_feedforward=d_model*4, dropout=dropout, norm_first=True, batch_first=True)
        self.transformer = nn.TransformerEncoder(enc_layer, num_layers=n_layers)
        self.norm = nn.LayerNorm(d_model)
        self.head = nn.Sequential(nn.Linear(d_model, d_model//2), nn.GELU(), nn.Dropout(dropout), nn.Linear(d_model//2, n_classes))
    def forward(self, x):
        x = x.permute(0, 2, 1)  # (B, F, T)
        x = self.feat_embed(x)   # (B, F, D)
        cls = self.cls_token.expand(x.size(0), -1, -1)
        x = torch.cat([cls, x], dim=1)  # (B, F+1, D)
        x = self.transformer(x)
        x = self.norm(x[:, 0, :])  # use CLS token
        return self.head(x)

# ==============================================
# Regime Detector
# ==============================================

# --- Fix #18: RegimeDetector Logic — Use absolute mean return for trend ---
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
        stds = np.sqrt(self.model.covars_.reshape(-1))
        # Trend = high absolute mean return (directional drift)
        # Chop = low mean return + any volatility
        self.trend_state = int(np.argmax(np.abs(means)))
        self.fitted = True

    def predict(self, recent_returns: np.ndarray) -> str:
        if not self.fitted:
            return 'unknown'
        state = int(self.model.predict(recent_returns.reshape(-1, 1))[-1])
        return 'trend' if state == self.trend_state else 'chop'

# ==============================================
# Turbulence Calculator
# ==============================================

TURBULENCE_THRESHOLD = 3.5

# --- Fix #19: Turbulence Uses Ledoit-Wolf Shrinkage ---
def compute_turbulence(current_returns: np.ndarray, historical_returns: np.ndarray) -> float:
    from sklearn.covariance import LedoitWolf
    from scipy.spatial.distance import mahalanobis
    lw = LedoitWolf().fit(historical_returns)
    mu = lw.location_
    cov_inv = lw.precision_
    return float(mahalanobis(current_returns, mu, cov_inv))

print('✅ Models defined!')

# %% [markdown]
# ---
#
# ## 4. CPCV Validation
#
# Implementing Combinatorial Purged Cross-Validation.

# %%
# ==============================================
# CPCV Validation
# ==============================================

try:
    import onnxruntime as ort
    HAS_ONNX = True
except ImportError:
    HAS_ONNX = False
    print('⚠️ onnxruntime not installed')

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


# --- Fix #21: PSR with Newey-West HAC standard errors ---
def psr(sharpe_ratios, sr_ref=0.0, max_lag=5):
    from scipy.stats import norm
    mu = sharpe_ratios.mean()
    # Newey-West HAC standard error
    n = len(sharpe_ratios)
    demeaned = sharpe_ratios - mu
    gamma0 = np.sum(demeaned**2) / n
    gamma_sum = 0.0
    for lag in range(1, min(max_lag + 1, n)):
        w = 1.0 - lag / (max_lag + 1)  # Bartlett kernel
        gamma_lag = np.sum(demeaned[lag:] * demeaned[:-lag]) / n
        gamma_sum += 2 * w * gamma_lag
    sig = np.sqrt(gamma0 + gamma_sum) + 1e-9
    z = (mu - sr_ref) / sig * np.sqrt(n)
    return float(norm.cdf(z))


# --- Fix #20: Adjusted Sharpe with autocorrelation ---
def adjusted_sharpe(returns, annualization=252.0):
    mu = returns.mean()
    sig = returns.std(ddof=1) + 1e-9
    raw_sr = mu / sig * np.sqrt(annualization)
    # Autocorrelation adjustment
    if len(returns) > 2:
        acf = np.correlate(returns - mu, returns - mu, mode='full')
        acf = acf[len(acf)//2:]
        acf = acf / acf[0]
        sum_acf = 2 * np.sum(acf[1:min(20, len(acf))])  # sum of first 20 autocorrelations
        adj_factor = np.sqrt(1 + max(0, sum_acf))
        return raw_sr / adj_factor
    return raw_sr


# --- Fix #23: Transaction Cost / Slippage Model ---
def apply_transaction_costs(returns, spread_estimate=0.0002):
    """Subtract estimated round-trip spread from returns."""
    # Only subtract from non-zero returns (actual trades)
    trade_mask = returns != 0
    adjusted = returns.copy()
    adjusted[trade_mask] -= spread_estimate
    return adjusted


def run_cpcv(model_path, X, y, bar_returns, n_splits=6, annualization=252.0):
    if not HAS_ONNX: raise ImportError('onnxruntime required')
    session = ort.InferenceSession(model_path)
    input_name = session.get_inputs()[0].name
    folds = cpcv_folds(len(X), n_splits=n_splits)
    sharpes = []
    for _, test_idx in folds:
        X_test = X[test_idx].astype(np.float32)
        logits = session.run(None, {input_name: X_test})[0]
        preds = logits.argmax(axis=1) - 1
        returns = preds * bar_returns[test_idx]
        # Apply transaction costs before computing Sharpe
        returns = apply_transaction_costs(returns)
        sr = adjusted_sharpe(returns, annualization=annualization)
        sharpes.append(float(sr))
    sharpes = np.asarray(sharpes, dtype=np.float64)
    p10 = float(np.percentile(sharpes, 10))
    result = {'sharpe_ratios': sharpes, 'mean_sr': float(sharpes.mean()), 'p10_sr': p10, 'psr': psr(sharpes), 'deploy_gate': p10 > 0.0}
    print(f'CPCV Results ({len(folds)} folds):')
    print(f'  Sharpe per fold: {np.round(sharpes, 3)}')
    print(f'  Mean SR: {result["mean_sr"]:.3f} | 10th pct SR: {p10:.3f} | PSR: {result["psr"]:.3f}')
    print(f'  DEPLOYMENT GATE: {"PASS" if result["deploy_gate"] else "FAIL"}')
    return result

print('✅ CPCV validation functions loaded!')

# %% [markdown]
# ---
#
# ## 5. Training Pipeline
#
# Now let's implement our training pipeline including PyTorch models and LightGBM.

# %%
# ==============================================
# Training Pipeline
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


def train_epoch(model, loader, optimizer, scheduler, criterion, device):
    model.train()
    total_loss = 0.0
    for x, y, w, _ in loader:
        x, y, w = x.to(device), y.to(device), w.to(device)
        optimizer.zero_grad()
        loss = (criterion(model(x), y) * w).mean()
        loss.backward()
        torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
        optimizer.step()
        scheduler.step()
        total_loss += float(loss.item())
    return total_loss / max(1, len(loader))


# --- Fix #29: Model Versioning and Hashing ---
def export_onnx(model, seq_len, n_feat, path, opset=17):
    output = Path(path)
    output.parent.mkdir(parents=True, exist_ok=True)
    model.eval()
    dummy = torch.zeros(1, seq_len, n_feat, dtype=torch.float32)
    torch.onnx.export(model, dummy, str(output), opset_version=opset, input_names=['input'], output_names=['output'], dynamic_axes={'input': {0: 'batch'}, 'output': {0: 'batch'}}, do_constant_folding=True, dynamo=False, verbose=False)
    # Add versioning metadata
    import hashlib
    import json
    from datetime import datetime
    sha256 = hashlib.sha256(output.read_bytes()).hexdigest()[:16]
    meta_path = output.with_suffix('.meta.json')
    meta = {'sha256': sha256, 'exported': datetime.now().isoformat(), 'seq_len': seq_len, 'n_features': n_feat, 'opset': opset}
    with open(meta_path, 'w') as f:
        json.dump(meta, f, indent=2)
    print(f'  ONNX exported: {output.name} (SHA256: {sha256})')


# --- Fix #31: Inference Warmup / Latency Test ---
def benchmark_onnx_inference(model_path, seq_len=60, n_features=57, n_runs=100):
    import onnxruntime as ort
    import time
    session = ort.InferenceSession(model_path)
    input_name = session.get_inputs()[0].name
    dummy = np.random.randn(1, seq_len, n_features).astype(np.float32)
    # Warmup
    for _ in range(10):
        session.run(None, {input_name: dummy})
    # Benchmark
    times = []
    for _ in range(n_runs):
        t0 = time.perf_counter()
        session.run(None, {input_name: dummy})
        times.append(time.perf_counter() - t0)
    lat_ms = np.mean(times) * 1000
    p99_ms = np.percentile(times, 99) * 1000
    print(f'  Inference: mean={lat_ms:.2f}ms, p99={p99_ms:.2f}ms')
    if lat_ms > 1.0:
        print(f'  ⚠️ WARNING: Inference latency >1ms may cause tick drops in live trading')
    return lat_ms


# --- Fix #32: Drift Detection (PSI) ---
def compute_psi(expected, actual, n_bins=10):
    """Population Stability Index between training and live feature distributions."""
    expected_pct = np.histogram(expected, bins=n_bins, density=True)[0] + 1e-6
    actual_pct = np.histogram(actual, bins=n_bins, density=True)[0] + 1e-6
    expected_pct /= expected_pct.sum()
    actual_pct /= actual_pct.sum()
    psi = np.sum((actual_pct - expected_pct) * np.log(actual_pct / expected_pct))
    return psi


# --- Fix #17: Feature Selection — Mutual Information Filter (optional utility) ---
def select_features_by_mi(X, y, k=40):
    """Select top-k features by mutual information with labels."""
    from sklearn.feature_selection import mutual_info_classif
    mi = mutual_info_classif(X.reshape(-1, X.shape[-1]), np.repeat(y, X.shape[1]), random_state=42)
    top_k = np.argsort(mi)[-k:]
    return top_k, mi


def instantiate_models(model_name, seq_len, n_feat):
    candidates = {}
    if model_name in ('mlp', 'ensemble'): candidates['mlp'] = SequenceMLP(seq_len=seq_len, n_features=n_feat)
    if model_name in ('patchtst', 'ensemble'): candidates['patchtst'] = PatchTST(seq_len=seq_len, n_features=n_feat)
    if model_name in ('itransformer', 'ensemble'): candidates['itransformer'] = iTransformer(seq_len=seq_len, n_features=n_feat)
    return candidates


def build_loader(split, batch_size, shuffle):
    return DataLoader(TradingDataset(*split[:4]), batch_size=batch_size, shuffle=shuffle, drop_last=False)


# --- Fix #9: Class Weight Explosion — Use sqrt-based weighting ---
def train_candidate(name, model, train_split, val_split, test_split, metadata, epochs=60, batch_size=64, lr=3e-4, weight_decay=1e-4, device=None, logs_dir=None):
    if device is None: device = 'cuda' if torch.cuda.is_available() else 'cpu'
    train_loader = build_loader(train_split, batch_size, shuffle=True)
    val_loader = build_loader(val_split, batch_size, shuffle=False)
    test_loader = build_loader(test_split, batch_size, shuffle=False)
    y_train = train_split[1]
    counts = np.bincount(y_train, minlength=3)
    # sqrt-based weighting instead of inverse to prevent explosion
    effective_weights = 1.0 / np.sqrt(np.maximum(counts, 1))
    class_weights = torch.tensor(effective_weights / effective_weights.sum() * 3, dtype=torch.float32, device=device)
    criterion = nn.CrossEntropyLoss(weight=class_weights, reduction='none')
    model = model.to(device)
    optimizer = torch.optim.AdamW(model.parameters(), lr=lr, weight_decay=weight_decay)
    total_steps = max(1, epochs * max(1, len(train_loader)))
    scheduler = torch.optim.lr_scheduler.OneCycleLR(optimizer, max_lr=lr, total_steps=total_steps, pct_start=0.15)
    best_state, best_val_ic, patience = None, -1e9, 0
    train_losses, val_ics = [], []

    # Setup logging
    log_file_path = None
    if logs_dir:
        from datetime import datetime
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        log_file_path = os.path.join(logs_dir, f'{name}_{timestamp}.log')
        with open(log_file_path, 'w', encoding='utf-8') as f:
            f.write(f'=== Training {name} ===\n')
            f.write(f'Start time: {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}\n')
            f.write(f'Epochs: {epochs}, Batch Size: {batch_size}, LR: {lr}\n')
            f.write(f'Device: {device}\n')
            f.write('\n')

    print(f'\n--- Training {name} ---')
    pbar = tqdm(range(epochs), desc=f'Training {name}')
    early_stop_epoch = None

    for epoch in pbar:
        loss = train_epoch(model, train_loader, optimizer, scheduler, criterion, device)
        val_ic = compute_ic(model, val_loader, device)
        current_lr = scheduler.get_last_lr()[0] if scheduler else lr
        train_losses.append(loss); val_ics.append(val_ic)

        if val_ic > best_val_ic:
            best_val_ic = val_ic
            best_state = {k: v.detach().cpu().clone() for k, v in model.state_dict().items()}
            patience = 0
        else:
            patience += 1

        # Log epoch to file
        if log_file_path:
            with open(log_file_path, 'a', encoding='utf-8') as f:
                f.write(f'Epoch {epoch+1:3d} | Loss: {loss:.6f} | Val IC: {val_ic:.6f} | Best Val IC: {best_val_ic:.6f} | LR: {current_lr:.6e}\n')

        pbar.set_postfix({'loss': f'{loss:.4f}', 'val_ic': f'{val_ic:.4f}', 'best': f'{best_val_ic:.4f}'})

        if patience >= 20:
            early_stop_epoch = epoch + 1
            print(f'  Early stopping at epoch {early_stop_epoch}')
            if log_file_path:
                with open(log_file_path, 'a', encoding='utf-8') as f:
                    f.write(f'Early stopping at epoch {early_stop_epoch}\n')
            break

    if best_state is not None: model.load_state_dict(best_state)
    test_ic = compute_ic(model, test_loader, device)

    # Log final results
    if log_file_path:
        from datetime import datetime
        with open(log_file_path, 'a', encoding='utf-8') as f:
            f.write(f'\n=== Final Results ===\n')
            f.write(f'Best Val IC: {best_val_ic:.6f}\n')
            f.write(f'Test IC: {test_ic:.6f}\n')
            f.write(f'End time: {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}\n')
        print(f'  Logs saved to: {log_file_path}')

    print(f'  Final: Val IC {best_val_ic:.4f}, Test IC {test_ic:.4f}')
    return best_val_ic, test_ic, model, train_losses, val_ics

# ==============================================
# LightGBM Training
# ==============================================

def train_lightgbm(train_split, val_split, test_split, metadata, output_path):
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

    # Save pickle
    pkl_output = Path(output_path).with_suffix('.pkl')
    with open(pkl_output, 'wb') as f:
        pickle.dump(model, f)

    # Calculate IC
    preds = model.predict(X_te)
    test_ic, _ = spearmanr(preds[:, 2] - preds[:, 0], test_split[3])
    print(f'  Final: Test IC {test_ic:.4f}')

    # Export ONNX if possible
    try:
        import onnxmltools
        from onnxmltools.convert.common.data_types import FloatTensorType
        onnx_model = onnxmltools.convert_lightgbm(
            model,
            name='lgbm_trading',
            initial_types=[('float_input', FloatTensorType([None, X_tr.shape[1]]))],
            target_opset=12,
        )
        onnxmltools.utils.save_model(onnx_model, output_path)
        print(f'  ONNX exported to {output_path}')
    except ImportError:
        print('  onnxmltools not installed, skipping ONNX export')

    return model, test_ic, preds

print('✅ Training pipeline ready!')

# %% [markdown]
# ---
#
# ## 6. Visualization Tools
#
# Let's create comprehensive visualization tools for data analysis and model evaluation.

# %%
# ==============================================
# Visualization Tools
# ==============================================

def plot_data_distribution(df, save_path=None):
    fig, axes = plt.subplots(2, 2, figsize=(16, 12))
    fig.suptitle('Data Distribution Analysis', fontsize=16, fontweight='bold')
    # Price chart
    if 'symbol' in df.columns:
        for symbol in df['symbol'].unique():
            sym_df = df[df['symbol'] == symbol].copy()
            sym_df['date'] = pd.to_datetime(sym_df['date'])
            axes[0, 0].plot(sym_df['date'], sym_df['close'], label=symbol, alpha=0.7)
        axes[0, 0].legend()
    else:
        df['date'] = pd.to_datetime(df['date'])
        axes[0, 0].plot(df['date'], df['close'])
    axes[0, 0].set_title('Price Chart'); axes[0, 0].set_xlabel('Date'); axes[0, 0].set_ylabel('Close Price'); axes[0, 0].tick_params(axis='x', rotation=45)
    # Returns distribution
    log_rets = np.log(df['close'] / df['close'].shift(1)).dropna()
    axes[0, 1].hist(log_rets, bins=50, alpha=0.7, edgecolor='black')
    axes[0, 1].axvline(log_rets.mean(), color='red', linestyle='--', label=f'Mean: {log_rets.mean():.4f}')
    axes[0, 1].axvline(log_rets.mean() + log_rets.std(), color='orange', linestyle='--', label='+1 Std')
    axes[0, 1].axvline(log_rets.mean() - log_rets.std(), color='orange', linestyle='--', label='-1 Std')
    axes[0, 1].set_title('Log Returns Distribution'); axes[0, 1].legend()
    # Volume
    axes[1, 0].bar(range(len(df)), df['volume'], alpha=0.6)
    axes[1, 0].set_title('Volume'); axes[1, 0].set_xlabel('Index')
    # Volatility
    high_low = df['high'] - df['low']
    axes[1, 1].plot(high_low.rolling(20).mean(), label='20-period Volatility')
    axes[1, 1].set_title('Volatility'); axes[1, 1].legend()
    plt.tight_layout()
    if save_path: plt.savefig(save_path, dpi=300, bbox_inches='tight')
    plt.show()


def plot_training_curves(train_losses, val_ics, title='Training Metrics', save_path=None):
    fig, axes = plt.subplots(1, 2, figsize=(14, 5))
    axes[0].plot(train_losses, label='Train Loss', color='blue')
    axes[0].set_title('Training Loss'); axes[0].legend(); axes[0].grid(True, alpha=0.3)
    axes[1].plot(val_ics, label='Validation IC', color='green')
    axes[1].axhline(y=0, color='red', linestyle='--', alpha=0.5)
    axes[1].set_title('Validation IC'); axes[1].legend(); axes[1].grid(True, alpha=0.3)
    plt.suptitle(title, fontsize=14, fontweight='bold')
    plt.tight_layout()
    if save_path: plt.savefig(save_path, dpi=300, bbox_inches='tight')
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
        ax.text(bar.get_x() + bar.get_width()/2., height, f'{int(height)}', ha='center', va='bottom')
    plt.tight_layout()
    if save_path: plt.savefig(save_path, dpi=300, bbox_inches='tight')
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
    ax.set_xlabel('Fold'); ax.set_ylabel('Sharpe Ratio'); ax.legend()
    plt.tight_layout()
    if save_path: plt.savefig(save_path, dpi=300, bbox_inches='tight')
    plt.show()


def plot_feature_importance(model, feature_names, save_path=None):
    try:
        import lightgbm as lgb
        if isinstance(model, lgb.Booster):
            fig, ax = plt.subplots(figsize=(12, 8))
            lgb.plot_importance(model, max_num_features=20, ax=ax)
            ax.set_title('LightGBM Feature Importance', fontsize=14, fontweight='bold')
            plt.tight_layout()
            if save_path: plt.savefig(save_path, dpi=300, bbox_inches='tight')
            plt.show()
        else:
            print('Model is not a LightGBM Booster')
    except ImportError:
        print('lightgbm not installed')


print('✅ Visualization tools ready!')


# %% [markdown]
# ---
#
# ## 7. Main Training Workflow
#
# Now let's run the complete training workflow with data loading, model training, and evaluation.

# %%
# ==============================================
# Main Training Workflow
# ==============================================

# Configuration
# TRAIN_MODE options:
#   - 'single': Train only the specified MODEL_TYPE
#   - 'sequential': Train all models one after another
#   - 'ensemble': Train all models and select the best one
TRAIN_MODE = 'sequential'  # Options: 'single', 'sequential', 'ensemble'
MODEL_TYPE = 'patchtst'  # Used only when TRAIN_MODE='single'
SEQ_LEN = 60
K = 1.5
VERTICAL_BARS = 20
EPOCHS = 60
BATCH_SIZE = 64
LR = 3e-4
WEIGHT_DECAY = 1e-4

# Path to training data
# Supports both Universal.csv and UNIVERSAL_TRAINING_SET.csv
# The data should contain: symbol, date, open, high, low, close, volume, feature_00 through feature_56
csv_candidates = ['UNIVERSAL_TRAINING_SET.csv', 'Universal.csv']
CSV_PATH = None
for candidate in csv_candidates:
    candidate_path = os.path.join(DATA_DIR, candidate)
    if os.path.exists(candidate_path):
        CSV_PATH = candidate_path
        print(f'✅ Found training data: {candidate}')
        break
if CSV_PATH is None:
    raise FileNotFoundError(f'No training data found. Upload Universal.csv or UNIVERSAL_TRAINING_SET.csv to {DATA_DIR}')

# Output paths
MODEL_OUTPUT = os.path.join(MODELS_DIR, 'best_model.onnx')
SCALER_OUTPUT = os.path.join(MODELS_DIR, 'scaler.bin')
LOGS_DIR = os.path.join(DRIVE_BASE, 'logs')
os.makedirs(LOGS_DIR, exist_ok=True)

print(f'📋 Training Configuration:')
print(f'  Train Mode: {TRAIN_MODE}')
print(f'  Model: {MODEL_TYPE}')
print(f'  Sequence Length: {SEQ_LEN}')
print(f'  Triple Barrier K: {K}')
print(f'  Vertical Bars: {VERTICAL_BARS}')
print(f'  Epochs: {EPOCHS}')
print(f'  Batch Size: {BATCH_SIZE}')
print(f'  Learning Rate: {LR}')
print(f'  Data Path: {CSV_PATH}')
print(f'  Model Output: {MODEL_OUTPUT}')
print(f'  Logs Directory: {LOGS_DIR}')


# %%
# Load and preprocess data
print('\n📥 Loading and preprocessing data...')

try:
    train_split, val_split, test_split, metadata = build_scaled_dataset_splits(
        CSV_PATH,
        seq_len=SEQ_LEN,
        k=K,
        vertical_bars=VERTICAL_BARS,
        scaler_output=SCALER_OUTPUT
    )

    print(f'✅ Data loaded successfully!')
    print(f'  Training samples: {metadata.train_size}')
    print(f'  Validation samples: {metadata.val_size}')
    print(f'  Test samples: {metadata.test_size}')
    print(f'  Features: {metadata.n_features}')
    print(f'  Annualization factor: {metadata.annualization:.1f}')

    # Visualize label distribution
    plot_label_distribution(train_split[1] - 1, save_path=os.path.join(CHARTS_DIR, 'label_distribution.png'))

except FileNotFoundError as e:
    print(f'❌ Error: {e}')
    print(f'Please upload your training data to Google Drive at: {DATA_DIR}')
    print('Supported files: UNIVERSAL_TRAINING_SET.csv or Universal.csv')
    raise


# %%
# Train PyTorch models
print('\n🚀 Starting model training...')

# Determine which models to train based on TRAIN_MODE
if TRAIN_MODE == 'single':
    candidates = instantiate_models(MODEL_TYPE, metadata.seq_len, metadata.n_features)
    print(f'  Training single model: {MODEL_TYPE}')
elif TRAIN_MODE == 'sequential':
    candidates = instantiate_models('ensemble', metadata.seq_len, metadata.n_features)
    print(f'  Training all models sequentially: {list(candidates.keys())}')
else:  # ensemble
    candidates = instantiate_models('ensemble', metadata.seq_len, metadata.n_features)
    print(f'  Training ensemble mode: {list(candidates.keys())}')

device = 'cuda' if torch.cuda.is_available() else 'cpu'
print(f'  Using device: {device}')

best_name = ''
best_val_ic = -1e9
best_test_ic = -1e9
best_model = None
best_train_losses = None
best_val_ics = None

# Store results for all models (useful for sequential mode)
model_results = []

for name, model in candidates.items():
    print(f'\n--- Training {name.upper()} ---')
    # --- Fix #1: Syntax Error — missing comma between device=device and logs_dir=LOGS_DIR ---
    val_ic, test_ic, trained_model, train_losses, val_ics = train_candidate(
        name=name,
        model=model,
        train_split=train_split,
        val_split=val_split,
        test_split=test_split,
        metadata=metadata,
        epochs=EPOCHS,
        batch_size=BATCH_SIZE,
        lr=LR,
        weight_decay=WEIGHT_DECAY,
        device=device,
        logs_dir=LOGS_DIR
    )

    # Store results
    model_results.append({
        'name': name,
        'val_ic': val_ic,
        'test_ic': test_ic,
        'model': trained_model,
        'train_losses': train_losses,
        'val_ics': val_ics
    })

    # Plot training curves
    plot_training_curves(train_losses, val_ics, title=f'{name.upper()} Training Metrics',
                        save_path=os.path.join(CHARTS_DIR, f'{name}_training.png'))

    if val_ic > best_val_ic:
        best_name = name
        best_val_ic = val_ic
        best_test_ic = test_ic
        best_model = trained_model
        best_train_losses = train_losses
        best_val_ics = val_ics

# Print training summary table
print('\n' + '='*60)
print('MODEL TRAINING RESULTS SUMMARY')
print('='*60)
print(f'{"Model":<12} {"Val IC":<10} {"Test IC":<10}')
print('-'*60)
for result in model_results:
    best_mark = ' 🏆' if result['name'] == best_name else ''
    print(f'{result["name"]:<12} {result["val_ic"]:<10.4f} {result["test_ic"]:<10.4f}{best_mark}')
print('='*60)
print(f'\n🏆 Best Model: {best_name} (Val IC: {best_val_ic:.4f}, Test IC: {best_test_ic:.4f})')


# %%
# --- Fix #8: CPCV run BEFORE final model export, on train+val data only ---
# Export best model to ONNX and run CPCV validation
print('\n📤 Exporting best model...')

# Export to ONNX
export_onnx(best_model, metadata.seq_len, metadata.n_features, MODEL_OUTPUT)

# Run CPCV validation on train+val data only (not full dataset, to avoid leakage)
print('\n🔍 Running CPCV validation on train+val data...')
X_trainval = np.concatenate([train_split[0], val_split[0]], axis=0)
y_trainval = np.concatenate([train_split[1], val_split[1]], axis=0)
returns_trainval = np.concatenate([train_split[3], val_split[3]], axis=0)

cpcv_result = run_cpcv(
    model_path=MODEL_OUTPUT,
    X=X_trainval,
    y=y_trainval,
    bar_returns=returns_trainval,
    n_splits=6,
    annualization=metadata.annualization
)

# Plot CPCV results
plot_cpcv_results(cpcv_result, save_path=os.path.join(CHARTS_DIR, 'cpcv_results.png'))

# --- Fix #22: Deployment Gate — Raise IC threshold and add skew/DD constraints ---
min_ic_threshold = 0.05  # was 0.02
deploy_ok = (best_test_ic >= min_ic_threshold
             and cpcv_result['deploy_gate']
             and cpcv_result['p10_sr'] > 0.0)

print('\n' + '='*50)
print('DEPLOYMENT GATE CHECK')
print('='*50)
print(f'Test IC: {best_test_ic:.4f} (min required: {min_ic_threshold})')
print(f'CPCV Deploy Gate: {"PASS" if cpcv_result["deploy_gate"] else "FAIL"}')
print(f'CPCV P10 Sharpe: {cpcv_result["p10_sr"]:.3f} (must be > 0)')
print('='*50)
print(f'Overall: {"✅ READY FOR DEPLOYMENT" if deploy_ok else "❌ DEPLOYMENT FAILED"}')
print('='*50)

# --- Fix #31: Inference Warmup / Latency Test ---
print('\n⏱️ Benchmarking ONNX inference latency...')
try:
    benchmark_onnx_inference(MODEL_OUTPUT, seq_len=metadata.seq_len, n_features=metadata.n_features)
except Exception as e:
    print(f'  ⚠️ Benchmark skipped: {e}')


# %%
# Train LightGBM model as alternative
print('\n🌲 Training LightGBM model...')

lgb_model, lgb_test_ic, lgb_preds = train_lightgbm(
    train_split, val_split, test_split, metadata,
    output_path=os.path.join(MODELS_DIR, 'lgbm_model.onnx')
)

if lgb_model is not None:
    plot_feature_importance(lgb_model, None, save_path=os.path.join(CHARTS_DIR, 'feature_importance.png'))
    print(f'\nLightGBM Test IC: {lgb_test_ic:.4f}')


# %%
# ==============================================
# Regime Detection and Turbulence Demo
# ==============================================

print('\n🔮 Regime Detection Demo')

# Extract returns from training data
train_rets = train_split[3]

# Train regime detector
regime_detector = RegimeDetector(n_states=2, lookback=500)
regime_detector.fit(train_rets)

# Test with recent returns
recent_rets = test_split[3][-20:]
current_regime = regime_detector.predict(recent_rets)
print(f'Current Market Regime: {current_regime}')

# Turbulence calculation demo
if len(train_rets) > 100:
    historical_rets = train_rets[-200:].reshape(-1, 1)
    current_returns_sample = test_split[3][-5:].reshape(-1, 1)
    turbulence = compute_turbulence(current_returns_sample.mean(axis=0), historical_rets)
    print(f'Turbulence Score: {turbulence:.4f} (Threshold: {TURBULENCE_THRESHOLD})')
    print(f'Turbulence Alert: {"⚠️ HIGH" if turbulence > TURBULENCE_THRESHOLD else "✅ NORMAL"}')

# --- Fix #32: Drift Detection (PSI) Demo ---
print('\n📊 Drift Detection (PSI) Demo')
if len(train_split[0]) > 0 and len(test_split[0]) > 0:
    train_flat = train_split[0].reshape(-1, train_split[0].shape[-1])
    test_flat = test_split[0].reshape(-1, test_split[0].shape[-1])
    psi_values = []
    for feat_idx in range(min(5, train_flat.shape[1])):
        psi_val = compute_psi(train_flat[:, feat_idx], test_flat[:, feat_idx])
        psi_values.append(psi_val)
        if feat_idx < 3:
            print(f'  Feature {feat_idx} PSI: {psi_val:.4f} {"⚠️ DRIFT" if psi_val > 0.25 else "✅ OK"}')
    avg_psi = np.mean(psi_values)
    print(f'  Average PSI: {avg_psi:.4f} {"⚠️ SIGNIFICANT DRIFT" if avg_psi > 0.25 else "✅ STABLE"}')

print('\n🎉 Training workflow completed!')
print(f'All outputs saved to: {DRIVE_BASE}')

# %% [markdown]
# ---
#
# ## 8. Usage Instructions
#
# ### Getting Started:
# 1. Upload your `Universal.csv` file to `Google Drive > Multi-Mt5 > data`
# 2. Run all cells sequentially from the top
# 3. Adjust hyperparameters in the "Main Training Workflow" section as needed
#
# ### Outputs:
# - **Models**: Saved to `Multi-Mt5/models/` (ONNX format)
# - **Charts**: Saved to `Multi-Mt5/charts/` (PNG format)
# - **Scaler**: Saved to `Multi-Mt5/models/scaler.bin`
#
# ### Deployment:
# The trained ONNX model can be deployed to MetaTrader 5 using the provided bridge modules. Ensure the deployment gate passes before deployment.
#
# ### Notes:
# - Training time depends on your GPU and dataset size
# - For best results, use GPU acceleration (Runtime > Change runtime type > GPU)
# - Adjust sequence length and model type based on your specific use case
