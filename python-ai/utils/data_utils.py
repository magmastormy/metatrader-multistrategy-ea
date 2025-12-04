"""Data processing utilities"""
import numpy as np
import pandas as pd
from typing import List, Dict, Any, Optional

def normalize_data(data: np.ndarray, method: str = 'minmax') -> np.ndarray:
    """Normalize data using specified method"""
    if method == 'minmax':
        min_val = np.min(data)
        max_val = np.max(data)
        if max_val - min_val == 0:
            return data
        return (data - min_val) / (max_val - min_val)
    elif method == 'zscore':
        mean = np.mean(data)
        std = np.std(data)
        if std == 0:
            return data - mean
        return (data - mean) / std
    return data

def safe_divide(a: float, b: float, default: float = 0.0) -> float:
    """Safely divide two numbers"""
    return a / b if b != 0 else default

def rolling_window(data: np.ndarray, window: int) -> np.ndarray:
    """Create rolling windows from data"""
    shape = (data.shape[0] - window + 1, window)
    strides = (data.strides[0], data.strides[0])
    return np.lib.stride_tricks.as_strided(data, shape=shape, strides=strides)

def handle_missing_values(df: pd.DataFrame, method: str = 'ffill') -> pd.DataFrame:
    """Handle missing values in DataFrame"""
    if method == 'ffill':
        return df.fillna(method='ffill').fillna(method='bfill')
    elif method == 'drop':
        return df.dropna()
    elif method == 'zero':
        return df.fillna(0)
    return df

def convert_timeframe(minutes: int) -> str:
    """Convert minutes to timeframe string"""
    if minutes == 1:
        return "M1"
    elif minutes == 5:
        return "M5"
    elif minutes == 15:
        return "M15"
    elif minutes == 30:
        return "M30"
    elif minutes == 60:
        return "H1"
    elif minutes == 240:
        return "H4"
    elif minutes == 1440:
        return "D1"
    return f"M{minutes}"
