from __future__ import annotations

import struct
from dataclasses import dataclass
from pathlib import Path
from typing import List, Optional, Sequence, Tuple

import numpy as np
import pandas as pd
import torch
from sklearn.preprocessing import StandardScaler
from torch.utils.data import DataLoader, Dataset


FEATURE_COUNT = 57


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
    def __init__(
        self,
        X: np.ndarray,
        y: np.ndarray,
        weights: Optional[np.ndarray] = None,
        returns: Optional[np.ndarray] = None,
    ) -> None:
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

    def __len__(self) -> int:
        return len(self.y)

    def __getitem__(self, index: int):
        return self.X[index], self.y[index], self.weights[index], self.returns[index]


def save_scaler_to_bin(scaler: StandardScaler, output_path: str) -> None:
    output = Path(output_path)
    output.parent.mkdir(parents=True, exist_ok=True)
    n = len(scaler.mean_)
    with output.open("wb") as handle:
        handle.write(struct.pack("<i", n))
        handle.write(struct.pack(f"<{n}d", *scaler.mean_))
        handle.write(struct.pack(f"<{n}d", *scaler.scale_))


def compute_atr(
    high: np.ndarray,
    low: np.ndarray,
    close: np.ndarray,
    period: int = 14,
) -> np.ndarray:
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


def triple_barrier_labels(
    close: np.ndarray,
    high: np.ndarray,
    low: np.ndarray,
    atr: np.ndarray,
    k: float = 1.5,
    vertical_bars: int = 20,
) -> np.ndarray:
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


def compute_uniqueness_weights(
    event_indices: Sequence[int],
    vertical_bars: int,
    total_bars: int,
) -> np.ndarray:
    event_indices = np.asarray(event_indices, dtype=np.int32)
    if len(event_indices) == 0:
        return np.zeros(0, dtype=np.float32)

    concurrency = np.zeros(total_bars, dtype=np.float32)
    for idx in event_indices:
        end = min(int(idx) + vertical_bars, total_bars)
        concurrency[int(idx) : end] += 1.0

    raw_weights = np.zeros(len(event_indices), dtype=np.float32)
    for i, idx in enumerate(event_indices):
        end = min(int(idx) + vertical_bars, total_bars)
        raw_weights[i] = np.mean(1.0 / np.maximum(concurrency[int(idx) : end], 1e-9))

    total = raw_weights.sum()
    if total > 1e-9:
        raw_weights = raw_weights / total * len(event_indices)
    return raw_weights


def compute_forward_returns(
    prices: np.ndarray,
    event_indices: Sequence[int],
    holding_bars: int = 10,
) -> np.ndarray:
    event_indices = np.asarray(event_indices, dtype=np.int32)
    returns = np.zeros(len(event_indices), dtype=np.float32)
    for i, idx in enumerate(event_indices):
        end = min(int(idx) + holding_bars, len(prices) - 1)
        returns[i] = (prices[end] - prices[int(idx)]) / max(prices[int(idx)], 1e-10)
    return returns


def cusum_filter(
    close: np.ndarray,
    threshold_multiplier: float = 1.0,
    atr: Optional[np.ndarray] = None,
) -> List[int]:
    if atr is None:
        atr = np.ones(len(close), dtype=np.float64)
    events: List[int] = []
    s_pos, s_neg = 0.0, 0.0
    for i in range(1, len(close)):
        ret = float(np.log(close[i] / (close[i - 1] + 1e-12)))
        thresh = max(1e-8, threshold_multiplier * float(atr[i]))
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
    result = np.empty_like(x, dtype=np.float64)
    result[0] = x[0]
    for i in range(1, len(x)):
        result[i] = alpha * x[i] + (1 - alpha) * result[i - 1]
    return result


def _sma(x: np.ndarray, period: int) -> np.ndarray:
    return pd.Series(x).rolling(period, min_periods=1).mean().values


def _rsi(close: np.ndarray, period: int) -> np.ndarray:
    delta = np.diff(close, prepend=close[0]).astype(np.float64)
    avg_gain = _ema(np.maximum(delta, 0.0), period)
    avg_loss = _ema(np.maximum(-delta, 0.0), period)
    rs = avg_gain / (avg_loss + 1e-9)
    return (100.0 - 100.0 / (1.0 + rs)) / 100.0


def _bb_pct_b(close: np.ndarray, period: int = 20, mult: float = 2.0) -> np.ndarray:
    mid = _sma(close, period)
    std = pd.Series(close).rolling(period, min_periods=1).std(ddof=0).fillna(0).values
    upper = mid + mult * std
    lower = mid - mult * std
    return (close - lower) / (upper - lower + 1e-9)


def _bb_width(close: np.ndarray, period: int = 20, mult: float = 2.0) -> np.ndarray:
    mid = _sma(close, period)
    std = pd.Series(close).rolling(period, min_periods=1).std(ddof=0).fillna(0).values
    return (2 * mult * std) / (mid + 1e-9)


def _macd_hist_norm(close: np.ndarray, fast: int = 12, slow: int = 26, sig: int = 9) -> np.ndarray:
    macd = _ema(close, fast) - _ema(close, slow)
    signal = _ema(macd, sig)
    hist = macd - signal
    atr = compute_atr(np.maximum(close, np.roll(close, 1)), np.minimum(close, np.roll(close, 1)), close, 14)
    return hist / (atr + 1e-9)


def _rolling_zscore(x: np.ndarray, period: int) -> np.ndarray:
    series = pd.Series(x.astype(np.float64))
    mean = series.rolling(period, min_periods=2).mean()
    std = series.rolling(period, min_periods=2).std(ddof=0)
    return ((series - mean) / (std + 1e-9)).fillna(0.0).values


def _cci(high: np.ndarray, low: np.ndarray, close: np.ndarray, period: int = 14) -> np.ndarray:
    tp = (high + low + close) / 3.0
    sma = _sma(tp, period)
    mad = (
        pd.Series(tp)
        .rolling(period)
        .apply(lambda x: np.mean(np.abs(x - x.mean())), raw=True)
        .fillna(1e-9)
        .values
    )
    return (tp - sma) / (0.015 * mad + 1e-9) / 200.0


def _parkinson_vol(high: np.ndarray, low: np.ndarray, period: int = 14) -> np.ndarray:
    log_hl = np.log((high + 1e-9) / (low + 1e-9)) ** 2
    factor = 1.0 / (4.0 * np.log(2))
    return np.sqrt(pd.Series(factor * log_hl).rolling(period, min_periods=1).mean().values)


def build_feature_matrix(
    open_: np.ndarray,
    high: np.ndarray,
    low: np.ndarray,
    close: np.ndarray,
    volume: np.ndarray,
) -> np.ndarray:
    n = len(close)
    log_ret = np.concatenate([[0.0], np.log(close[1:] / (close[:-1] + 1e-12))])
    atr14 = compute_atr(high, low, close, 14)
    atr50 = compute_atr(high, low, close, 50)
    atr5 = compute_atr(high, low, close, 5)

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
        _rsi(close, 14),
        _rsi(close, 7),
        _bb_pct_b(close, 20, 2.0),
        _bb_width(close, 20, 2.0),
        _macd_hist_norm(close, 12, 26, 9),
        atr14 / (atr50 + 1e-9),
        _parkinson_vol(high, low, 14),
        volume / (_sma(volume.astype(np.float64), 20) + 1e-9),
        np.zeros(n, dtype=np.float64),
        np.zeros(n, dtype=np.float64),
        np.zeros(n, dtype=np.float64),
        np.zeros(n, dtype=np.float64),
        np.roll(log_ret, 1),
        np.roll(log_ret, 5),
        np.roll(log_ret, 20),
        _rolling_zscore(close.astype(np.float64), 20),
        _rolling_zscore(close.astype(np.float64), 50),
        (high - low) / (close + 1e-9),
        _rolling_zscore(high - low, 20),
        _cci(high, low, close, 14),
        np.roll(log_ret / (atr14 + 1e-9), 2),
        np.roll(log_ret / (atr14 + 1e-9), 3),
        np.roll(log_ret / (atr14 + 1e-9), 5),
        np.roll(log_ret / (atr14 + 1e-9), 8),
        np.roll(log_ret / (atr14 + 1e-9), 13),
        _rolling_zscore(volume.astype(np.float64), 20),
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
        _rolling_zscore(volume.astype(np.float64), 50),
        atr50 / (atr14 + 1e-9),
        np.zeros(n, dtype=np.float64),
        np.ones(n, dtype=np.float64),
    ]

    features = np.column_stack(cols).astype(np.float32)
    return np.nan_to_num(features, nan=0.0, posinf=3.0, neginf=-3.0)


def exported_feature_columns(frame: pd.DataFrame) -> List[str]:
    feature_cols = [col for col in frame.columns if col.startswith("feature_")]
    def sort_key(name: str) -> int:
        try:
            return int(name.split("_")[1])
        except (IndexError, ValueError):
            return 10**9
    return sorted(feature_cols, key=sort_key)


def add_calendar_features(features: np.ndarray, timestamps: pd.DatetimeIndex) -> np.ndarray:
    dow = timestamps.dayofweek.values / 6.0
    hod = timestamps.hour.values / 23.0
    features[:, 18] = np.sin(2 * np.pi * dow)
    features[:, 19] = np.cos(2 * np.pi * dow)
    features[:, 20] = np.sin(2 * np.pi * hod)
    features[:, 21] = np.cos(2 * np.pi * hod)
    return features


def prepare_sequences(
    features: np.ndarray,
    labels: np.ndarray,
    weights: np.ndarray,
    returns: np.ndarray,
    timestamps: np.ndarray,
    seq_len: int,
    sample_indices: Sequence[int],
) -> Tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    X, y, w, r, ts = [], [], [], [], []
    for idx, sample_index in enumerate(sample_indices):
        if sample_index < seq_len:
            continue
        end = int(sample_index)
        X.append(features[end - seq_len : end])
        y.append(int(labels[end - 1]) + 1)
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


def _split_arrays(
    X: np.ndarray,
    y: np.ndarray,
    weights: np.ndarray,
    returns: np.ndarray,
    timestamps: np.ndarray,
    train_ratio: float,
    val_ratio: float,
) -> Tuple[Tuple[np.ndarray, ...], Tuple[np.ndarray, ...], Tuple[np.ndarray, ...]]:
    n = len(X)
    if n < 48:
        raise ValueError("Not enough prepared samples to split safely.")

    train_end = int(n * train_ratio)
    val_end = int(n * (train_ratio + val_ratio))
    train_end = max(24, min(train_end, n - 24))
    val_end = max(train_end + 12, min(val_end, n - 12))

    train = (X[:train_end], y[:train_end], weights[:train_end], returns[:train_end], timestamps[:train_end])
    val = (X[train_end:val_end], y[train_end:val_end], weights[train_end:val_end], returns[train_end:val_end], timestamps[train_end:val_end])
    test = (X[val_end:], y[val_end:], weights[val_end:], returns[val_end:], timestamps[val_end:])
    return train, val, test


def _estimate_annualization_factor(timestamps: np.ndarray) -> float:
    if len(timestamps) < 3:
        return 252.0
    ts = pd.to_datetime(pd.Series(timestamps)).astype("int64") // 10**9
    deltas = np.diff(ts.to_numpy(dtype=np.int64))
    deltas = deltas[deltas > 0]
    if len(deltas) == 0:
        return 252.0
    median_seconds = float(np.median(deltas))
    if median_seconds <= 0:
        return 252.0
    return max(1.0, (365.25 * 24.0 * 3600.0) / median_seconds)


def build_dataset_splits(
    df: pd.DataFrame,
    seq_len: int = 60,
    k: float = 1.5,
    vertical_bars: int = 20,
    train_ratio: float = 0.70,
    val_ratio: float = 0.15,
) -> Tuple[Tuple[np.ndarray, ...], Tuple[np.ndarray, ...], Tuple[np.ndarray, ...], float]:
    required = {"date", "open", "high", "low", "close", "volume"}
    missing = required.difference(df.columns)
    if missing:
        raise ValueError(f"Missing required columns: {sorted(missing)}")

    frame = df.copy()
    frame["date"] = pd.to_datetime(frame["date"])
    if "symbol" not in frame.columns:
        frame["symbol"] = "DEFAULT"

    train_parts: List[Tuple[np.ndarray, ...]] = []
    val_parts: List[Tuple[np.ndarray, ...]] = []
    test_parts: List[Tuple[np.ndarray, ...]] = []
    annualization_candidates: List[float] = []

    grouped = frame.sort_values(["symbol", "date"]).groupby("symbol", sort=False)
    for _, symbol_df in grouped:
        symbol_df = symbol_df.dropna(subset=["open", "high", "low", "close", "volume"]).copy()
        if len(symbol_df) < max(seq_len + vertical_bars + 20, 160):
            continue

        open_ = symbol_df["open"].to_numpy(dtype=np.float64)
        high = symbol_df["high"].to_numpy(dtype=np.float64)
        low = symbol_df["low"].to_numpy(dtype=np.float64)
        close = symbol_df["close"].to_numpy(dtype=np.float64)
        volume = symbol_df["volume"].to_numpy(dtype=np.float64)

        feature_cols = exported_feature_columns(symbol_df)
        if feature_cols:
            features = symbol_df[feature_cols].to_numpy(dtype=np.float32)
            features = np.nan_to_num(features, nan=0.0, posinf=3.0, neginf=-3.0)
        else:
            features = build_feature_matrix(open_, high, low, close, volume)
            features = add_calendar_features(features, pd.DatetimeIndex(symbol_df["date"]))

        atr = compute_atr(high, low, close, 14)
        labels = triple_barrier_labels(close, high, low, atr, k=k, vertical_bars=vertical_bars)
        events = np.asarray(cusum_filter(close, threshold_multiplier=1.0, atr=atr), dtype=np.int32)
        label_indices = np.asarray([idx - 1 for idx in events if idx >= 1], dtype=np.int32)
        if len(label_indices) < 48:
            continue

        weights = compute_uniqueness_weights(label_indices, vertical_bars, len(close))
        returns = compute_forward_returns(close, label_indices, holding_bars=vertical_bars)
        timestamps = symbol_df["date"].to_numpy()
        X, y, w, r, ts = prepare_sequences(
            features,
            labels,
            weights,
            returns,
            timestamps,
            seq_len=seq_len,
            sample_indices=label_indices,
        )
        if len(X) < 48:
            continue

        train, val, test = _split_arrays(X, y, w, r, ts, train_ratio, val_ratio)
        train_parts.append(train)
        val_parts.append(val)
        test_parts.append(test)
        annualization_candidates.append(_estimate_annualization_factor(ts))

    if not train_parts or not val_parts or not test_parts:
        raise ValueError("No usable symbol groups were found in the supplied OHLCV dataset.")

    def concat(parts: List[Tuple[np.ndarray, ...]]) -> Tuple[np.ndarray, ...]:
        columns = list(zip(*parts))
        return tuple(np.concatenate(list(col), axis=0) for col in columns)

    annualization = float(np.median(annualization_candidates)) if annualization_candidates else 252.0
    return concat(train_parts), concat(val_parts), concat(test_parts), annualization


def _scale_splits(
    train: Tuple[np.ndarray, ...],
    val: Tuple[np.ndarray, ...],
    test: Tuple[np.ndarray, ...],
    scaler_output: Optional[str] = None,
) -> Tuple[Tuple[np.ndarray, ...], Tuple[np.ndarray, ...], Tuple[np.ndarray, ...], Optional[StandardScaler]]:
    X_tr, y_tr, w_tr, r_tr, ts_tr = train
    X_va, y_va, w_va, r_va, ts_va = val
    X_te, y_te, w_te, r_te, ts_te = test

    scaler = StandardScaler()
    n_train, seq_len, n_features = X_tr.shape
    scaler.fit(X_tr.reshape(n_train, seq_len * n_features))

    def transform(X: np.ndarray) -> np.ndarray:
        flat = X.reshape(len(X), seq_len * n_features)
        scaled = scaler.transform(flat)
        return scaled.reshape(len(X), seq_len, n_features).astype(np.float32)

    if scaler_output:
        save_scaler_to_bin(scaler, scaler_output)

    return (
        (transform(X_tr), y_tr, w_tr, r_tr, ts_tr),
        (transform(X_va), y_va, w_va, r_va, ts_va),
        (transform(X_te), y_te, w_te, r_te, ts_te),
        scaler,
    )


def build_pipeline(
    csv_path: str,
    seq_len: int = 60,
    k: float = 1.5,
    vertical_bars: int = 20,
    train_ratio: float = 0.70,
    val_ratio: float = 0.15,
    batch_size: int = 64,
    scaler_output: Optional[str] = None,
) -> Tuple[DataLoader, DataLoader, DataLoader, PipelineMetadata]:
    df = pd.read_csv(csv_path)
    train, val, test, annualization = build_dataset_splits(
        df,
        seq_len=seq_len,
        k=k,
        vertical_bars=vertical_bars,
        train_ratio=train_ratio,
        val_ratio=val_ratio,
    )
    train, val, test, _ = _scale_splits(train, val, test, scaler_output=scaler_output)

    train_loader = DataLoader(TradingDataset(*train[:4]), batch_size=batch_size, shuffle=True, drop_last=False)
    val_loader = DataLoader(TradingDataset(*val[:4]), batch_size=batch_size, shuffle=False, drop_last=False)
    test_loader = DataLoader(TradingDataset(*test[:4]), batch_size=batch_size, shuffle=False, drop_last=False)

    metadata = PipelineMetadata(
        seq_len=seq_len,
        n_features=train[0].shape[2],
        train_size=len(train[0]),
        val_size=len(val[0]),
        test_size=len(test[0]),
        annualization=annualization,
        scaler_path=scaler_output,
    )
    return train_loader, val_loader, test_loader, metadata


def build_scaled_dataset_splits(
    csv_path: str,
    seq_len: int = 60,
    k: float = 1.5,
    vertical_bars: int = 20,
    train_ratio: float = 0.70,
    val_ratio: float = 0.15,
    scaler_output: Optional[str] = None,
) -> Tuple[Tuple[np.ndarray, ...], Tuple[np.ndarray, ...], Tuple[np.ndarray, ...], PipelineMetadata]:
    df = pd.read_csv(csv_path)
    train, val, test, annualization = build_dataset_splits(
        df,
        seq_len=seq_len,
        k=k,
        vertical_bars=vertical_bars,
        train_ratio=train_ratio,
        val_ratio=val_ratio,
    )
    train, val, test, _ = _scale_splits(train, val, test, scaler_output=scaler_output)
    metadata = PipelineMetadata(
        seq_len=seq_len,
        n_features=train[0].shape[2],
        train_size=len(train[0]),
        val_size=len(val[0]),
        test_size=len(test[0]),
        annualization=annualization,
        scaler_path=scaler_output,
    )
    return train, val, test, metadata


def build_symbol_sequences(
    df: pd.DataFrame,
    seq_len: int = 60,
    k: float = 1.5,
    vertical_bars: int = 20,
    train_ratio: float = 0.80,
) -> Tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    train, val, _test, _annualization = build_dataset_splits(
        df,
        seq_len=seq_len,
        k=k,
        vertical_bars=vertical_bars,
        train_ratio=train_ratio,
        val_ratio=max(0.05, (1.0 - train_ratio) * 0.5),
    )
    return train[0], train[1], val[0], val[1]
