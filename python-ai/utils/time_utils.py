"""Time utility functions for trading system"""
import numpy as np
from datetime import datetime, timezone

def get_session_type() -> str:
    """Determine current trading session"""
    hour = datetime.now(timezone.utc).hour
    
    if 0 <= hour < 8:
        return "ASIA"
    elif 8 <= hour < 16:
        return "EUROPE"
    elif 16 <= hour < 24:
        return "US"
    return "ASIA"

def get_time_features() -> dict:
    """Extract time-based features for ML models"""
    now = datetime.now()
    
    return {
        'hour_sin': np.sin(2 * np.pi * now.hour / 24),
        'hour_cos': np.cos(2 * np.pi * now.hour / 24),
        'day_sin': np.sin(2 * np.pi * now.weekday() / 7),
        'day_cos': np.cos(2 * np.pi * now.weekday() / 7),
        'session': get_session_type(),
        'is_weekend': now.weekday() >= 5
    }

def is_market_open(symbol: str = "XAUUSD") -> bool:
    """Check if market is open for trading"""
    now = datetime.now(timezone.utc)
    
    # Forex and metals trade 24/5
    if now.weekday() >= 5:  # Saturday or Sunday
        return False
    
    # Friday close at 22:00 UTC
    if now.weekday() == 4 and now.hour >= 22:
        return False
    
    # Sunday open at 22:00 UTC
    if now.weekday() == 6 and now.hour < 22:
        return False
    
    return True
