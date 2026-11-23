"""Canonical shared training primitives.

Single source of truth for the pure NumPy/pandas functions that were
previously duplicated between ``data_pipeline.py`` / ``validate_model.py``
(repo trainers) and ``mql5_v2.py`` (self-contained Colab script).

Blocks between ``# @@VENDOR-BEGIN <name>`` / ``# @@VENDOR-END <name>``
markers are vendored verbatim into ``mql5_v2.py`` by
``sync_mql5_v2.py`` — edit them here only, then re-run the sync script.
"""

from __future__ import annotations

from typing import List, Optional, Sequence, Tuple

import numpy as np
import pandas as pd

try:
    from numba import njit

    HAS_NUMBA = True
except ImportError:  # pragma: no cover
    HAS_NUMBA = False


# @@VENDOR-BEGIN core_atr_labels
def compute_atr(
    high: np.ndarray,
    low: np.ndarray,
    close: np.ndarray,
    period: int = 14,
    backfill_first_period: bool = True,
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
    if backfill_first_period:
        # Fill the warm-up bars so downstream ratios never divide by a literal 0.
        atr[:period] = tr[:period].mean() if len(tr) >= period else tr.mean()
    return atr


def _triple_barrier_labels_py(
    close: np.ndarray,
    high: np.ndarray,
    low: np.ndarray,
    atr: np.ndarray,
    k: float,
    vertical_bars: int,
) -> np.ndarray:
    n = len(close)
    labels = np.zeros(n, dtype=np.int8)
    for i in range(n - vertical_bars):
        if atr[i] <= 0:
            continue
        upper = close[i] + k * atr[i]
        lower = close[i] - k * atr[i]
        for j in range(i + 1, min(i + vertical_bars + 1, n)):
            # Stop is checked first: when one bar touches both barriers, the
            # conservative outcome is the loss.
            if low[j] <= lower:
                labels[i] = -1
                break
            if high[j] >= upper:
                labels[i] = 1
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
                if low[j] <= lower:
                    labels[i] = -1
                    break
                if high[j] >= upper:
                    labels[i] = 1
                    break
        return labels

    def triple_barrier_labels(
        close: np.ndarray,
        high: np.ndarray,
        low: np.ndarray,
        atr: np.ndarray,
        k: float = 1.5,
        vertical_bars: int = 20,
    ) -> np.ndarray:
        return _triple_barrier_numba(close, high, low, atr, k, vertical_bars)

else:

    def triple_barrier_labels(
        close: np.ndarray,
        high: np.ndarray,
        low: np.ndarray,
        atr: np.ndarray,
        k: float = 1.5,
        vertical_bars: int = 20,
    ) -> np.ndarray:
        return _triple_barrier_labels_py(close, high, low, atr, k, vertical_bars)
# @@VENDOR-END core_atr_labels


# @@VENDOR-BEGIN core_weights
def _compute_uniqueness_weights_py(
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

    def compute_uniqueness_weights(
        event_indices: Sequence[int],
        vertical_bars: int,
        total_bars: int,
    ) -> np.ndarray:
        arr = np.asarray(event_indices, dtype=np.int32)
        if len(arr) == 0:
            return np.zeros(0, dtype=np.float32)
        return _uniq_weights_numba(arr, vertical_bars, total_bars)

else:

    def compute_uniqueness_weights(
        event_indices: Sequence[int],
        vertical_bars: int,
        total_bars: int,
    ) -> np.ndarray:
        return _compute_uniqueness_weights_py(event_indices, vertical_bars, total_bars)
# @@VENDOR-END core_weights


# @@VENDOR-BEGIN core_cusum
def _cusum_filter_py(
    close: np.ndarray,
    threshold_multiplier: float,
    atr: np.ndarray,
) -> List[int]:
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

    def cusum_filter(
        close: np.ndarray,
        threshold_multiplier: float = 1.0,
        atr: Optional[np.ndarray] = None,
    ) -> List[int]:
        if atr is None:
            atr = np.ones(len(close), dtype=np.float64)
        return _cusum_numba(close, threshold_multiplier, atr)

else:

    def cusum_filter(
        close: np.ndarray,
        threshold_multiplier: float = 1.0,
        atr: Optional[np.ndarray] = None,
    ) -> List[int]:
        if atr is None:
            atr = np.ones(len(close), dtype=np.float64)
        return _cusum_filter_py(close, threshold_multiplier, atr)
# @@VENDOR-END core_cusum


# @@VENDOR-BEGIN core_features
def _safe_lag(x: np.ndarray, periods: int, fill_value: float = 0.0) -> np.ndarray:
    """Safe lag without np.roll wrap-around."""
    return pd.Series(x, dtype=np.float64).shift(periods, fill_value=fill_value).to_numpy(dtype=np.float64)


def _ema(x: np.ndarray, period: int) -> np.ndarray:
    alpha = 2.0 / (period + 1)
    result = np.empty_like(x, dtype=np.float64)
    result[0] = x[0]
    for i in range(1, len(x)):
        result[i] = alpha * x[i] + (1 - alpha) * result[i - 1]
    return result


def _sma(x: np.ndarray, period: int) -> np.ndarray:
    return pd.Series(x).rolling(period, min_periods=1).mean().to_numpy(dtype=np.float64)


def _rsi(close: np.ndarray, period: int) -> np.ndarray:
    delta = np.diff(close, prepend=close[0]).astype(np.float64)
    avg_gain = _ema(np.maximum(delta, 0.0), period)
    avg_loss = _ema(np.maximum(-delta, 0.0), period)
    rs = avg_gain / (avg_loss + 1e-9)
    return (100.0 - 100.0 / (1.0 + rs)) / 100.0


def _bb_pct_b(close: np.ndarray, period: int = 20, mult: float = 2.0) -> np.ndarray:
    mid = _sma(close, period)
    std = pd.Series(close).rolling(period, min_periods=1).std(ddof=0).fillna(0).to_numpy(dtype=np.float64)
    upper = mid + mult * std
    lower = mid - mult * std
    return (close - lower) / (upper - lower + 1e-9)


def _bb_width(close: np.ndarray, period: int = 20, mult: float = 2.0) -> np.ndarray:
    mid = _sma(close, period)
    std = pd.Series(close).rolling(period, min_periods=1).std(ddof=0).fillna(0).to_numpy(dtype=np.float64)
    return (2 * mult * std) / (mid + 1e-9)


def _macd_hist_norm(close: np.ndarray, fast: int = 12, slow: int = 26, sig: int = 9) -> np.ndarray:
    macd = _ema(close, fast) - _ema(close, slow)
    signal = _ema(macd, sig)
    hist = macd - signal
    atr = compute_atr(
        np.maximum(close, np.roll(close, 1)),
        np.minimum(close, np.roll(close, 1)),
        close,
        14,
    )
    return hist / (atr + 1e-9)


def _rolling_zscore(x: np.ndarray, period: int) -> np.ndarray:
    series = pd.Series(x.astype(np.float64))
    mean = series.rolling(period, min_periods=2).mean()
    std = series.rolling(period, min_periods=2).std(ddof=0)
    return ((series - mean) / (std + 1e-9)).fillna(0.0).to_numpy(dtype=np.float64)


def _cci(high: np.ndarray, low: np.ndarray, close: np.ndarray, period: int = 14) -> np.ndarray:
    tp = (high + low + close) / 3.0
    sma = _sma(tp, period)
    tp_series = pd.Series(tp)
    mad = (
        tp_series.rolling(period, min_periods=1)
        .apply(lambda x: np.mean(np.abs(x - x.mean())), raw=True)
        .fillna(1e-9)
        .to_numpy(dtype=np.float64)
    )
    return (tp - sma) / (0.015 * mad + 1e-9) / 200.0


def _parkinson_vol(high: np.ndarray, low: np.ndarray, period: int = 14) -> np.ndarray:
    log_hl = np.log((high + 1e-9) / (low + 1e-9)) ** 2
    factor = 1.0 / (4.0 * np.log(2))
    return np.sqrt(
        pd.Series(factor * log_hl).rolling(period, min_periods=1).mean().to_numpy(dtype=np.float64)
    )


def build_base_feature_matrix(
    open_: np.ndarray,
    high: np.ndarray,
    low: np.ndarray,
    close: np.ndarray,
    volume: np.ndarray,
) -> np.ndarray:
    """The 57-column base feature matrix shared by every pipeline.

    Uses ``_safe_lag`` (no ``np.roll`` wrap-around) for all lagged features;
    calendar slots 18-21 are zero placeholders filled by
    ``add_calendar_features``.
    """
    n = len(close)
    log_ret = np.concatenate([[0.0], np.log(close[1:] / (close[:-1] + 1e-12))])
    atr14 = compute_atr(high, low, close, 14)
    atr50 = compute_atr(high, low, close, 50)
    atr5 = compute_atr(high, low, close, 5)

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
        np.zeros(n, dtype=np.float64),  # 18: calendar sin(dow) - injected later
        np.zeros(n, dtype=np.float64),  # 19: calendar cos(dow)
        np.zeros(n, dtype=np.float64),  # 20: calendar sin(hod)
        np.zeros(n, dtype=np.float64),  # 21: calendar cos(hod)
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
        np.zeros(n, dtype=np.float64),  # 55: placeholder
        np.ones(n, dtype=np.float64),   # 56: bias feature
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
    """Overwrite calendar slots 18-21 from timestamps."""
    dow = timestamps.dayofweek.values / 6.0
    hod = timestamps.hour.values / 23.0
    features[:, 18] = np.sin(2 * np.pi * dow)
    features[:, 19] = np.cos(2 * np.pi * dow)
    features[:, 20] = np.sin(2 * np.pi * hod)
    features[:, 21] = np.cos(2 * np.pi * hod)
    return features
# @@VENDOR-END core_features


# @@VENDOR-BEGIN core_cpcv
def purge_embargo(
    train_idx: np.ndarray,
    test_idx: np.ndarray,
    starts_ns: np.ndarray,
    horizon_ns: int,
    embargo_ns: int = 0,
    ends_ns: Optional[np.ndarray] = None,
) -> np.ndarray:
    """Drop training samples whose label span overlaps any test span.

    When ``ends_ns`` (actual per-sample label-end timestamps) is provided, overlap is
    tested on the true spans [start, end]; otherwise each span is approximated as
    [start, start + horizon_ns].
    """
    if ends_ns is None:
        ends_ns = starts_ns + horizon_ns
    order = np.argsort(starts_ns[test_idx])
    test_starts = starts_ns[test_idx][order]
    test_ends = ends_ns[test_idx][order]
    # prefix maximum of test ends: a train span can only overlap a test whose start
    # precedes the train end, and among those the largest test end decides overlap.
    prefix_max_end = np.maximum.accumulate(test_ends)

    s = starts_ns[train_idx]
    e = ends_ns[train_idx]
    hi = np.searchsorted(test_starts, e + embargo_ns, side="right") - 1
    overlaps = np.zeros(len(train_idx), dtype=bool)
    valid = hi >= 0
    overlaps[valid] = prefix_max_end[np.clip(hi[valid], 0, len(prefix_max_end) - 1)] >= s[valid] - embargo_ns
    return train_idx[~overlaps]


def cpcv_folds(
    starts_ns: np.ndarray,
    horizon_ns: int,
    n_splits: int = 6,
    n_test: int = 2,
    embargo_ns: int = 0,
    ends_ns: Optional[np.ndarray] = None,
) -> List[Tuple[np.ndarray, np.ndarray]]:
    from itertools import combinations

    n = len(starts_ns)
    groups = np.array_split(np.arange(n), n_splits)
    folds: List[Tuple[np.ndarray, np.ndarray]] = []
    for test_groups in combinations(range(n_splits), n_test):
        test_idx = np.concatenate([groups[i] for i in test_groups])
        train_idx = np.concatenate([groups[i] for i in range(n_splits) if i not in test_groups])
        train_idx = purge_embargo(train_idx, test_idx, starts_ns, horizon_ns, embargo_ns, ends_ns)
        folds.append((train_idx, test_idx))
    return folds


def psr(sharpe_ratios: np.ndarray, sr_ref: float = 0.0) -> float:
    from scipy.stats import norm

    mu = sharpe_ratios.mean()
    sig = sharpe_ratios.std(ddof=1) + 1e-9
    z = (mu - sr_ref) / sig * np.sqrt(len(sharpe_ratios))
    return float(norm.cdf(z))


def label_horizon_ns(timestamps: np.ndarray, vertical_bars: int) -> int:
    ts = np.unique(np.asarray(timestamps, dtype="datetime64[ns]").astype(np.int64))
    diffs = np.diff(ts)
    diffs = diffs[diffs > 0]
    if len(diffs) == 0:
        raise ValueError("Cannot infer bar spacing from timestamps for CPCV purging.")
    return int(np.median(diffs)) * int(vertical_bars)
# @@VENDOR-END core_cpcv
