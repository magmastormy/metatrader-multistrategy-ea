import numpy as np
import pandas as pd
from typing import List, Tuple


def compute_atr(high: np.ndarray, low: np.ndarray,
                close: np.ndarray, period: int = 14) -> np.ndarray:
    """Wilder's Average True Range."""
    tr = np.maximum(high[1:] - low[1:],
         np.maximum(np.abs(high[1:] - close[:-1]),
                    np.abs(low[1:] - close[:-1])))
    atr = np.zeros(len(close))
    if period <= len(tr):
        atr[period] = tr[:period].mean()
        for i in range(period + 1, len(close)):
            atr[i] = (atr[i - 1] * (period - 1) + tr[i - 1]) / period
    return atr


def triple_barrier_labels(close: np.ndarray, high: np.ndarray,
                           low: np.ndarray, atr: np.ndarray,
                           k: float = 1.5,
                           vertical_bars: int = 20) -> np.ndarray:
    """
    Returns array of shape (n,) with values in {-1, 0, +1}.
    -1 = lower barrier hit first (loss)
     0 = vertical barrier hit first (neutral/time-exit)
    +1 = upper barrier hit first (profit)
    """
    n = len(close)
    labels = np.zeros(n, dtype=np.int8)
    for i in range(n - vertical_bars):
        if atr[i] == 0:
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


def cusum_filter(close: np.ndarray, threshold_multiplier: float = 1.0,
                 atr: np.ndarray = None) -> List[int]:
    """
    Event-based CUSUM sampling.
    Returns sorted list of bar indices where a sampling event occurs.
    """
    if atr is None:
        atr = np.ones(len(close))
    events = []
    s_pos, s_neg = 0.0, 0.0
    for i in range(1, len(close)):
        ret = float(np.log(close[i] / (close[i - 1] + 1e-12)))
        thresh = threshold_multiplier * float(atr[i])
        s_pos = max(0.0, s_pos + ret)
        s_neg = min(0.0, s_neg + ret)
        if s_pos > thresh:
            events.append(i)
            s_pos = 0.0
        elif s_neg < -thresh:
            events.append(i)
            s_neg = 0.0
    return events


def _ema(x: np.ndarray, period: int) -> np.ndarray:
    alpha = 2.0 / (period + 1)
    result = np.empty_like(x, dtype=float)
    result[0] = x[0]
    for i in range(1, len(x)):
        result[i] = alpha * x[i] + (1 - alpha) * result[i - 1]
    return result


def _sma(x: np.ndarray, period: int) -> np.ndarray:
    return pd.Series(x).rolling(period, min_periods=1).mean().values


def _rsi(close: np.ndarray, period: int) -> np.ndarray:
    delta = np.diff(close, prepend=close[0]).astype(float)
    avg_gain = _ema(np.maximum(delta, 0), period)
    avg_loss = _ema(np.maximum(-delta, 0), period)
    rs = avg_gain / (avg_loss + 1e-9)
    return (100.0 - 100.0 / (1.0 + rs)) / 100.0


def _bb_pct_b(close: np.ndarray, period: int = 20, mult: float = 2.0) -> np.ndarray:
    mid = _sma(close, period)
    std = pd.Series(close).rolling(period, min_periods=1).std().fillna(0).values
    upper = mid + mult * std
    lower = mid - mult * std
    return (close - lower) / (upper - lower + 1e-9)


def _bb_width(close: np.ndarray, period: int = 20, mult: float = 2.0) -> np.ndarray:
    mid = _sma(close, period)
    std = pd.Series(close).rolling(period, min_periods=1).std().fillna(0).values
    return (2 * mult * std) / (mid + 1e-9)


def _macd_hist_norm(close: np.ndarray, fast=12, slow=26, sig=9) -> np.ndarray:
    macd = _ema(close, fast) - _ema(close, slow)
    signal = _ema(macd, sig)
    hist = macd - signal
    atr = compute_atr(np.maximum(close, np.roll(close, 1)),
                      np.minimum(close, np.roll(close, 1)), close, 14)
    return hist / (atr + 1e-9)


def _rolling_zscore(x: np.ndarray, period: int) -> np.ndarray:
    s = pd.Series(x.astype(float))
    mean = s.rolling(period, min_periods=2).mean()
    std = s.rolling(period, min_periods=2).std()
    return ((s - mean) / (std + 1e-9)).fillna(0.0).values


def _cci(high, low, close, period=14) -> np.ndarray:
    tp = (high + low + close) / 3.0
    sma = _sma(tp, period)
    mad = pd.Series(tp).rolling(period).apply(
              lambda x: np.mean(np.abs(x - x.mean())), raw=True).fillna(1e-9).values
    return (tp - sma) / (0.015 * mad + 1e-9) / 200.0


def _parkinson_vol(high, low, period=14) -> np.ndarray:
    log_hl = np.log((high + 1e-9) / (low + 1e-9)) ** 2
    factor = 1.0 / (4.0 * np.log(2))
    return np.sqrt(pd.Series(factor * log_hl).rolling(period, min_periods=1).mean().values)


def build_feature_matrix(open_: np.ndarray, high: np.ndarray,
                          low: np.ndarray, close: np.ndarray,
                          volume: np.ndarray) -> np.ndarray:
    """
    Returns (n, 55) float32 matrix matching AIFeatureVectorBuilder.mqh.
    All price-based features use log-returns, not raw prices.
    """
    n = len(close)
    log_ret = np.concatenate([[0.0], np.log(close[1:] / (close[:-1] + 1e-12))])
    atr14 = compute_atr(high, low, close, 14)
    atr50 = compute_atr(high, low, close, 50)
    atr5 = compute_atr(high, low, close, 5)

    cols = [
        log_ret,
        log_ret / (atr14 + 1e-9),
        (close - low) / (high - low + 1e-9),
        np.log(volume.astype(float) + 1.0),
        atr14 / (close + 1e-9),
        np.log(close / (_ema(close, 8) + 1e-9) + 1e-9),
        np.log(close / (_ema(close, 21) + 1e-9) + 1e-9),
        np.log(close / (_ema(close, 50) + 1e-9) + 1e-9),
        np.log(_ema(close, 8) / (_ema(close, 21) + 1e-9) + 1e-9),
        np.log(_ema(close, 21) / (_ema(close, 50) + 1e-9) + 1e-9),
        _rsi(close, 14),
        _rsi(close, 7),
        _bb_pct_b(close, 20, 2.0),
        _bb_width(close, 20, 2.0),
        _macd_hist_norm(close, 12, 26, 9),
        atr14 / (atr50 + 1e-9),
        _parkinson_vol(high, low, 14),
        volume / (_sma(volume.astype(float), 20) + 1e-9),
        np.zeros(n),
        np.zeros(n),
        np.zeros(n),
        np.zeros(n),
        np.roll(log_ret, 1),
        np.roll(log_ret, 5),
        np.roll(log_ret, 20),
        _rolling_zscore(close.astype(float), 20),
        _rolling_zscore(close.astype(float), 50),
        (high - low) / (close + 1e-9),
        _rolling_zscore(high - low, 20),
        _cci(high, low, close, 14),
        np.roll(log_ret / (atr14 + 1e-9), 2),
        np.roll(log_ret / (atr14 + 1e-9), 3),
        np.roll(log_ret / (atr14 + 1e-9), 5),
        np.roll(log_ret / (atr14 + 1e-9), 8),
        np.roll(log_ret / (atr14 + 1e-9), 13),
        _rolling_zscore(volume.astype(float), 20),
        np.roll(_rsi(close, 14), 1),
        np.roll(_rsi(close, 14), 3),
        np.roll(_bb_pct_b(close, 20, 2.0), 1),
        np.roll(_bb_pct_b(close, 20, 2.0), 3),
        _rolling_zscore(_rsi(close, 14), 20),
        _rolling_zscore(_rsi(close, 7), 20),
        _macd_hist_norm(close, 12, 26, 9),
        np.roll(_macd_hist_norm(close, 12, 26, 9), 1),
        atr14 / (atr5 + 1e-9),
        _rolling_zscore(atr14, 20),
        np.roll(log_ret, 10),
        np.roll(log_ret, 15),
        (close - _sma(close, 50)) / (atr14 + 1e-9),
        (close - _sma(close, 200)) / (atr14 + 1e-9),
        _rolling_zscore(np.roll(log_ret, 1) * log_ret, 20),
        _rolling_zscore(np.roll(log_ret, 5) * log_ret, 20),
        (close - _ema(close, 100)) / (atr50 + 1e-9),
        _rolling_zscore(volume.astype(float), 50),
        atr50 / (atr14 + 1e-9),
    ]

    features = np.column_stack(cols).astype(np.float32)
    return np.nan_to_num(features, nan=0.0, posinf=3.0, neginf=-3.0)


def add_calendar_features(features: np.ndarray,
                           timestamps: pd.DatetimeIndex) -> np.ndarray:
    """Fill in the calendar feature slots [18-21] from timestamps."""
    dow = timestamps.dayofweek.values / 6.0
    hod = timestamps.hour.values / 23.0
    features[:, 18] = np.sin(2 * np.pi * dow)
    features[:, 19] = np.cos(2 * np.pi * dow)
    features[:, 20] = np.sin(2 * np.pi * hod)
    features[:, 21] = np.cos(2 * np.pi * hod)
    return features


def prepare_sequences(features: np.ndarray, labels: np.ndarray,
                       seq_len: int = 60,
                       sample_indices: List[int] = None) -> Tuple[np.ndarray, np.ndarray]:
    """
    Build (N, seq_len, n_features) input tensor and (N,) label tensor.
    Labels are remapped: -1 -> 0, 0 -> 1, +1 -> 2.
    """
    X, y = [], []
    idx_iter = sample_indices if sample_indices else range(seq_len, len(features))
    for i in idx_iter:
        if i < seq_len:
            continue
        X.append(features[i - seq_len:i])
        y.append(int(labels[i - 1]) + 1)
    return np.array(X, dtype=np.float32), np.array(y, dtype=np.int64)


def build_symbol_sequences(df: pd.DataFrame,
                           seq_len: int = 60,
                           k: float = 1.5,
                           vertical_bars: int = 20,
                           train_ratio: float = 0.80) -> Tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    """
    Build train/validation tensors from a single-symbol or multi-symbol OHLCV dataframe.

    Required columns:
      date, open, high, low, close, volume
    Optional column:
      symbol
    """
    required = {"date", "open", "high", "low", "close", "volume"}
    missing = required.difference(df.columns)
    if missing:
        raise ValueError(f"Missing required columns: {sorted(missing)}")

    frame = df.copy()
    frame["date"] = pd.to_datetime(frame["date"])
    if "symbol" not in frame.columns:
        frame["symbol"] = "DEFAULT"

    X_train_parts, y_train_parts = [], []
    X_val_parts, y_val_parts = [], []

    grouped = frame.sort_values(["symbol", "date"]).groupby("symbol", sort=False)
    for symbol, symbol_df in grouped:
        symbol_df = symbol_df.dropna(subset=["open", "high", "low", "close", "volume"]).copy()
        if len(symbol_df) < max(seq_len + vertical_bars + 10, 120):
            continue

        open_ = symbol_df["open"].to_numpy(dtype=np.float64)
        high = symbol_df["high"].to_numpy(dtype=np.float64)
        low = symbol_df["low"].to_numpy(dtype=np.float64)
        close = symbol_df["close"].to_numpy(dtype=np.float64)
        volume = symbol_df["volume"].to_numpy(dtype=np.float64)

        feats = build_feature_matrix(open_, high, low, close, volume)
        feats = add_calendar_features(feats, pd.DatetimeIndex(symbol_df["date"]))
        atr = compute_atr(high, low, close, 14)
        labels = triple_barrier_labels(close, high, low, atr, k=k, vertical_bars=vertical_bars)
        events = cusum_filter(close, threshold_multiplier=1.0, atr=atr)
        X_sym, y_sym = prepare_sequences(feats, labels, seq_len, events)

        if len(X_sym) < 32:
            continue

        split = int(len(X_sym) * train_ratio)
        split = max(16, min(split, len(X_sym) - 16))

        X_train_parts.append(X_sym[:split])
        y_train_parts.append(y_sym[:split])
        X_val_parts.append(X_sym[split:])
        y_val_parts.append(y_sym[split:])

    if not X_train_parts or not X_val_parts:
        raise ValueError("No usable symbol groups were found in the supplied OHLCV dataset.")

    X_tr = np.concatenate(X_train_parts, axis=0).astype(np.float32)
    y_tr = np.concatenate(y_train_parts, axis=0).astype(np.int64)
    X_val = np.concatenate(X_val_parts, axis=0).astype(np.float32)
    y_val = np.concatenate(y_val_parts, axis=0).astype(np.int64)
    return X_tr, y_tr, X_val, y_val
