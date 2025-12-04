"""Data validation utilities"""
import numpy as np
from typing import Dict, Any, List

def validate_market_data(data: Dict[str, Any]) -> bool:
    """Validate market data structure and content"""
    required_fields = ['open', 'high', 'low', 'close']
    
    # Check required fields exist
    for field in required_fields:
        if field not in data:
            return False
    
    # Check data types and values
    for field in required_fields:
        values = data[field]
        if not isinstance(values, (list, np.ndarray)):
            return False
        if len(values) == 0:
            return False
        # Check for valid prices (positive numbers)
        if np.any(np.array(values) <= 0):
            return False
    
    # Check OHLC logic
    opens = np.array(data['open'])
    highs = np.array(data['high'])
    lows = np.array(data['low'])
    closes = np.array(data['close'])
    
    # High should be >= Open, Close and Low should be <= High
    if not np.all(highs >= np.maximum(opens, closes)):
        return False
    if not np.all(lows <= np.minimum(opens, closes)):
        return False
    
    return True

def validate_signal(signal: Dict[str, Any]) -> bool:
    """Validate trading signal structure"""
    required_fields = ['symbol', 'action', 'confidence']
    
    for field in required_fields:
        if field not in signal:
            return False
    
    # Validate action
    if signal['action'] not in ['BUY', 'SELL', 'HOLD', 'NONE']:
        return False
    
    # Validate confidence (0.0 to 1.0)
    if not (0.0 <= signal['confidence'] <= 1.0):
        return False
    
    return True

def sanitize_features(features: np.ndarray) -> np.ndarray:
    """Sanitize feature array (handle NaN, Inf, etc.)"""
    features = np.nan_to_num(features, nan=0.0, posinf=1e6, neginf=-1e6)
    features = np.clip(features, -1e6, 1e6)
    return features
