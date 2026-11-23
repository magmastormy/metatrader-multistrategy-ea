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

# Canonical implementations live in training_core.py (single source of truth,
# also vendored into the self-contained Colab script mql5_v2.py).
from training_core import (
    _bb_pct_b,
    _bb_width,
    _cci,
    _ema,
    _macd_hist_norm,
    _parkinson_vol,
    _rsi,
    _rolling_zscore,
    _sma,
    add_calendar_features,
    build_base_feature_matrix,
    compute_atr,
    compute_uniqueness_weights,
    cusum_filter,
    exported_feature_columns,
    triple_barrier_labels,
)


FEATURE_COUNT = 57
BASE_FEATURE_COUNT = 57
DERIV_SIGNAL_FEATURES = 8
DERIV_FAMILY_COUNT = 18
DERIV_FEATURE_COUNT = DERIV_SIGNAL_FEATURES + DERIV_FAMILY_COUNT  # 26


def get_feature_count(family_id: int = -1, asset_class: int = -1) -> int:
    """Return feature count based on family_id or asset_class.

    Priority: family_id (Deriv) > asset_class (non-Deriv) > base only.
    - family_id >= 0 → 57 + 26 = 83 (Deriv family features)
    - asset_class >= 0 → 57 + asset-class extras (3/4/4/3)
    - neither → 57 (universal base)
    """
    if family_id >= 0:
        return BASE_FEATURE_COUNT + DERIV_FEATURE_COUNT
    if asset_class >= 0:
        return get_asset_class_feature_count(asset_class)
    return BASE_FEATURE_COUNT


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


def build_deriv_family_features(
    close: np.ndarray,
    high: np.ndarray,
    low: np.ndarray,
    volume: np.ndarray,
    family_id: int,
) -> List[np.ndarray]:
    """Deriv synthetic index family-specific features (26 columns: 8 signal + 18 one-hot).

    Family IDs aligned with MQL5 ENUM_DERIV_FAMILY:
      0=CrashBoom, 1=Volatility, 2=Step, 3=Jump, 4=DEX,
      5=MultiStep, 6=Exponential, 7=Hybrid, 8=RangeBreak,
      9=SkewStep, 10=VolSwitch, 11=DriftSwitch, 12=Trek,
      13=Tactical, 14=Derived, 15=StableSpread, 16=PairsArbitrage,
      17=SpotVolatility
    """
    n = len(close)
    atr14 = compute_atr(high, low, close, 14)
    atr5 = compute_atr(high, low, close, 5)

    deriv_features: List[np.ndarray] = []

    # === SIGNAL FEATURE 1: Tick velocity z-score ===
    tick_velocity = np.concatenate([[0.0], np.diff(close)])
    deriv_features.append(_rolling_zscore(tick_velocity, 20))

    # === SIGNAL FEATURE 2: Direction accumulation (consecutive same-direction ticks) ===
    direction = np.sign(np.diff(close, prepend=close[0]))
    dir_accum = np.zeros(n, dtype=np.float64)
    for i in range(1, n):
        if direction[i] == direction[i - 1] and direction[i] != 0:
            dir_accum[i] = dir_accum[i - 1] + 1
        else:
            dir_accum[i] = 0
    deriv_features.append(dir_accum / 20.0)

    # === SIGNAL FEATURE 3: ATR compression ratio (pre-spike "coiling") ===
    atr_ratio = atr14 / (_sma(atr14, 50) + 1e-9)
    deriv_features.append(atr_ratio)

    # === SIGNAL FEATURE 4: Spike magnitude z-score ===
    spike_mag = np.abs(np.diff(close, prepend=close[0])) / (atr14 + 1e-9)
    deriv_features.append(_rolling_zscore(spike_mag, 50))

    # === SIGNAL FEATURE 5: OU process residual (mean-reversion strength) ===
    ou_residual = (close - _ema(close, 50)) / (atr14 + 1e-9)
    deriv_features.append(ou_residual)

    # === SIGNAL FEATURE 6: Step frequency (discrete movement detection) ===
    step_changes = np.abs(np.diff(close, prepend=close[0])) > 0
    step_freq = pd.Series(step_changes.astype(np.float64)).rolling(20).mean().fillna(0).values
    deriv_features.append(step_freq)

    # === SIGNAL FEATURE 7: Range bound score (distance from BB midpoint) ===
    bb_pct = _bb_pct_b(close, 20, 2.0)
    range_score = 2.0 * np.abs(bb_pct - 0.5)
    deriv_features.append(range_score)

    # === SIGNAL FEATURE 8: Bars since last extreme move ===
    extreme_move = np.abs(np.diff(close, prepend=close[0])) > (2.0 * atr14)
    bars_since_extreme = np.zeros(n, dtype=np.float64)
    for i in range(1, n):
        if extreme_move[i]:
            bars_since_extreme[i] = 0
        else:
            bars_since_extreme[i] = bars_since_extreme[i - 1] + 1
    deriv_features.append(np.clip(bars_since_extreme / 100.0, 0, 1))

    # === FAMILY ONE-HOT ENCODING (18 families) ===
    for fid in range(DERIV_FAMILY_COUNT):
        deriv_features.append(np.full(n, 1.0 if family_id == fid else 0.0, dtype=np.float64))

    return deriv_features


# Batch 103: Asset-class-specific feature builders

def build_forex_features(close, high, low, volume, spread):
    """Forex-specific features: spread z-score, correlation proxy, carry return."""
    n = len(close)
    spread_z = _rolling_zscore(spread, 20) if len(spread) >= 20 else np.zeros(n)
    corr_proxy = _rolling_zscore(close, 50) if n >= 50 else np.zeros(n)
    carry = np.zeros(n)  # Populated from broker swap data
    return np.column_stack([spread_z, corr_proxy, carry])


def build_metals_features(close, high, low, volume):
    """Metals-specific features: vol-of-vol, session timing, trend strength, vol regime."""
    n = len(close)
    atr14 = compute_atr(high, low, close, 14) if n >= 14 else np.ones(n)
    vol_of_vol = _rolling_zscore(atr14, 50) if n >= 50 else np.zeros(n)
    # Session proxy (simplified - real implementation uses timestamps)
    session_ny = np.zeros(n)  # Placeholder: populated from timestamps
    trend_strength = (close - _ema(close, 50)) / (atr14 + 1e-9) if n >= 50 else np.zeros(n)
    vol_regime = atr14 / (_sma(atr14, 50) + 1e-9) if n >= 50 else np.ones(n)
    return np.column_stack([vol_of_vol, session_ny, trend_strength, vol_regime])


def build_indices_features(close, high, low, volume, timestamps=None):
    """Indices-specific features: overnight gap, circadian, BB width, vol spike."""
    n = len(close)
    overnight_gap = np.zeros(n)
    if n > 1:
        overnight_gap[1:] = close[1:] / close[:-1] - 1.0
    circadian = np.zeros(n)  # Placeholder: populated from timestamps
    bb_width = _bb_width(close, 20, 2.0) if n >= 20 else np.ones(n)
    vol_spike = volume / (_sma(volume, 20) + 1e-9) if n >= 20 else np.ones(n)
    return np.column_stack([overnight_gap, circadian, bb_width, vol_spike])


def build_energies_features(close, high, low, volume):
    """Energies-specific features: inventory proxy, seasonality, contango."""
    n = len(close)
    inventory_proxy = _rolling_zscore(close, 50) if n >= 50 else np.zeros(n)
    seasonality = np.zeros(n)  # Placeholder: populated from timestamps
    contango = np.zeros(n)  # Placeholder: populated from futures curve
    return np.column_stack([inventory_proxy, seasonality, contango])


def get_asset_class_feature_count(asset_class: int) -> int:
    """Get total feature count for a non-Deriv asset class."""
    base = BASE_FEATURE_COUNT
    extras = {0: 3, 1: 4, 2: 4, 3: 3}  # forex, metals, indices, energies
    return base + extras.get(asset_class, 0)


def build_feature_matrix(
    open_: np.ndarray,
    high: np.ndarray,
    low: np.ndarray,
    close: np.ndarray,
    volume: np.ndarray,
    family_id: int = -1,
    asset_class: int = -1,
) -> np.ndarray:
    """57-col canonical base matrix plus optional family/asset-class extras.

    The base block is ``training_core.build_base_feature_matrix`` (safe lags,
    no ``np.roll`` wrap-around - the wrap only touched the first lag-period bars
    but is gone entirely now). ``compute_atr`` backfills its warm-up window, so
    ratio features at bars < period are finite instead of clipped at +/-3.
    """
    n = len(close)
    base = build_base_feature_matrix(open_, high, low, close, volume)

    extra_cols = []
    if family_id >= 0:
        extra_cols = build_deriv_family_features(close, high, low, volume, family_id)
    elif asset_class >= 0:
        if asset_class == 0:      # FOREX
            ext = build_forex_features(close, high, low, volume, volume)
        elif asset_class == 1:    # METALS
            ext = build_metals_features(close, high, low, volume)
        elif asset_class == 2:    # INDICES
            ext = build_indices_features(close, high, low, volume)
        elif asset_class == 3:    # ENERGIES
            ext = build_energies_features(close, high, low, volume)
        else:
            ext = np.zeros((n, 0))
        extra_cols = [ext[:, i] for i in range(ext.shape[1])]

    if not extra_cols:
        return base
    features = np.column_stack([base] + [np.asarray(c, dtype=np.float32) for c in extra_cols])
    return np.nan_to_num(features.astype(np.float32), nan=0.0, posinf=3.0, neginf=-3.0)



def prepare_sequences(
    features: np.ndarray,
    labels: np.ndarray,
    weights: np.ndarray,
    returns: np.ndarray,
    timestamps: np.ndarray,
    seq_len: int,
    sample_indices: Sequence[int],
    vertical_bars: int = 0,
) -> Tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    X, y, w, r, ts, le = [], [], [], [], [], []
    skipped = 0
    n_bars = len(timestamps)
    for idx, sample_index in enumerate(sample_indices):
        if sample_index < seq_len:
            skipped += 1
            continue
        end = int(sample_index)
        X.append(features[end - seq_len : end])
        y.append(int(labels[end - 1]) + 1)
        w.append(float(weights[idx]))
        r.append(float(returns[idx]))
        ts.append(timestamps[end - 1])
        # Label for bar (end - 1) resolves over the next vertical_bars bars; the last
        # bar it can touch is end - 1 + vertical_bars. Clamped - purged samples near
        # the data end never reach a split.
        le.append(timestamps[min(end - 1 + vertical_bars, n_bars - 1)])

    X_arr = np.asarray(X, dtype=np.float32)
    y_arr = np.asarray(y, dtype=np.int64)
    w_arr = np.asarray(w, dtype=np.float32)
    r_arr = np.asarray(r, dtype=np.float32)
    ts_arr = np.asarray(ts)
    le_arr = np.asarray(le)
    assert len(X_arr) == len(y_arr) == len(w_arr) == len(r_arr) == len(ts_arr) == len(le_arr)
    assert len(X_arr) == len(sample_indices) - skipped

    return X_arr, y_arr, w_arr, r_arr, ts_arr, le_arr


def _split_arrays(
    X: np.ndarray,
    y: np.ndarray,
    weights: np.ndarray,
    returns: np.ndarray,
    timestamps: np.ndarray,
    label_ends: np.ndarray,
    label_bars: np.ndarray,
    train_ratio: float,
    val_ratio: float,
    vertical_bars: int,
    n_bars: int,
) -> Tuple[Tuple[np.ndarray, ...], Tuple[np.ndarray, ...], Tuple[np.ndarray, ...]]:
    n = len(X)
    if n < 48:
        raise ValueError("Not enough prepared samples to split safely.")

    train_end = int(n * train_ratio)
    val_end = int(n * (train_ratio + val_ratio))
    train_end = max(24, min(train_end, n - 24))
    val_end = max(train_end + 12, min(val_end, n - 12))

    # A sample's label is resolved at label_bar + vertical_bars, so it is kept only if that
    # horizon ends strictly before the first bar of the next segment.
    idx = np.arange(n)
    horizon_end = label_bars + vertical_bars
    train_sel = idx[(idx < train_end) & (horizon_end < label_bars[train_end])]
    val_sel = idx[(idx >= train_end) & (idx < val_end) & (horizon_end < label_bars[val_end])]
    # The test segment has no following segment, so its boundary is the end of the data:
    # a label needs vertical_bars of future bars or triple_barrier_labels leaves it 0.
    test_sel = idx[(idx >= val_end) & (horizon_end < n_bars)]

    def take(sel: np.ndarray) -> Tuple[np.ndarray, ...]:
        return (X[sel], y[sel], weights[sel], returns[sel], timestamps[sel], label_ends[sel])

    return take(train_sel), take(val_sel), take(test_sel)


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
    family_id: int = -1,
    asset_class: int = -1,
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
            features = build_feature_matrix(open_, high, low, close, volume, family_id=family_id, asset_class=asset_class)
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
        X, y, w, r, ts, le = prepare_sequences(
            features,
            labels,
            weights,
            returns,
            timestamps,
            seq_len=seq_len,
            sample_indices=label_indices,
            vertical_bars=vertical_bars,
        )
        if len(X) < 48:
            continue

        kept_label_bars = np.asarray([s - 1 for s in label_indices if s >= seq_len], dtype=np.int64)
        train, val, test = _split_arrays(
            X, y, w, r, ts, le, kept_label_bars, train_ratio, val_ratio,
            vertical_bars=vertical_bars, n_bars=len(close),
        )
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
    X_tr, y_tr, w_tr, r_tr, ts_tr, le_tr = train
    X_va, y_va, w_va, r_va, ts_va, le_va = val
    X_te, y_te, w_te, r_te, ts_te, le_te = test

    # The scaler is applied per bar at inference (CPipelineScaler::Apply scales a
    # FEATURE_VECTOR_SIZE vector), so it must be fit per feature across all bars,
    # not on the flattened (seq_len * n_features) sequence layout.
    scaler = StandardScaler()
    n_train, seq_len, n_features = X_tr.shape
    scaler.fit(X_tr.reshape(-1, n_features))

    def transform(X: np.ndarray) -> np.ndarray:
        flat = X.reshape(-1, n_features)
        scaled = scaler.transform(flat)
        return scaled.reshape(len(X), seq_len, n_features).astype(np.float32)

    if scaler_output:
        save_scaler_to_bin(scaler, scaler_output)

    return (
        (transform(X_tr), y_tr, w_tr, r_tr, ts_tr, le_tr),
        (transform(X_va), y_va, w_va, r_va, ts_va, le_va),
        (transform(X_te), y_te, w_te, r_te, ts_te, le_te),
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
    family_id: int = -1,
) -> Tuple[DataLoader, DataLoader, DataLoader, PipelineMetadata]:
    df = pd.read_csv(csv_path)
    train, val, test, annualization = build_dataset_splits(
        df,
        seq_len=seq_len,
        k=k,
        vertical_bars=vertical_bars,
        train_ratio=train_ratio,
        val_ratio=val_ratio,
        family_id=family_id,
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
    family_id: int = -1,
    asset_class: int = -1,
) -> Tuple[Tuple[np.ndarray, ...], Tuple[np.ndarray, ...], Tuple[np.ndarray, ...], PipelineMetadata]:
    df = pd.read_csv(csv_path)
    train, val, test, annualization = build_dataset_splits(
        df,
        seq_len=seq_len,
        k=k,
        vertical_bars=vertical_bars,
        train_ratio=train_ratio,
        val_ratio=val_ratio,
        family_id=family_id,
        asset_class=asset_class,
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
    family_id: int = -1,
) -> Tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    train, val, _test, _annualization = build_dataset_splits(
        df,
        seq_len=seq_len,
        k=k,
        vertical_bars=vertical_bars,
        train_ratio=train_ratio,
        val_ratio=max(0.05, (1.0 - train_ratio) * 0.5),
        family_id=family_id,
    )
    return train[0], train[1], val[0], val[1]
