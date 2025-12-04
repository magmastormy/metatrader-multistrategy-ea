"""Data loader for historical and live market data"""
import numpy as np
import pandas as pd
from typing import Dict, List, Optional, Any
from datetime import datetime, timedelta
import logging

logger = logging.getLogger(__name__)

class DataLoader:
    """Loads and manages market data from various sources"""
    
    def __init__(self):
        self.cache = {}
        self.cache_ttl = 300  # 5 minutes
        
    def load_from_dict(self, data: Dict[str, Any]) -> pd.DataFrame:
        """Load data from dictionary format"""
        try:
            if isinstance(data, dict):
                # Convert dict to DataFrame
                df = pd.DataFrame(data)
            elif isinstance(data, pd.DataFrame):
                df = data.copy()
            else:
                raise ValueError("Data must be dict or DataFrame")
            
            # Ensure required columns exist
            required_cols = ['open', 'high', 'low', 'close']
            for col in required_cols:
                if col not in df.columns:
                    logger.warning(f"Missing column: {col}, using close prices")
                    if 'close' in df.columns:
                        df[col] = df['close']
                    elif 'price' in df.columns:
                        df[col] = df['price']
            
            # Add timestamp if not present
            if 'timestamp' not in df.columns:
                df['timestamp'] = pd.date_range(
                    end=datetime.now(), 
                    periods=len(df), 
                    freq='1min'
                )
            
            return df
            
        except Exception as e:
            logger.error(f"Error loading data: {e}")
            raise
    
    def load_from_array(self, prices: np.ndarray, symbol: str = "UNKNOWN") -> pd.DataFrame:
        """Load data from price array"""
        df = pd.DataFrame({
            'timestamp': pd.date_range(end=datetime.now(), periods=len(prices), freq='1min'),
            'open': prices,
            'high': prices,
            'low': prices,
            'close': prices,
            'volume': np.zeros(len(prices))
        })
        df['symbol'] = symbol
        return df
    
    def load_live_data(self, symbol: str, bars: int = 100) -> Optional[pd.DataFrame]:
        """Load live data from MT5 or data feed"""
        # Placeholder for live data integration
        # In production, this would connect to MT5 or data provider
        logger.info(f"Loading live data for {symbol}, {bars} bars")
        
        # Simulate data for now
        return self._generate_sample_data(symbol, bars)
    
    def _generate_sample_data(self, symbol: str, bars: int) -> pd.DataFrame:
        """Generate sample data for testing"""
        base_price = 1900.0 if "XAU" in symbol else 1.1000
        
        timestamps = pd.date_range(end=datetime.now(), periods=bars, freq='1min')
        prices = base_price + np.cumsum(np.random.randn(bars) * 0.5)
        
        df = pd.DataFrame({
            'timestamp': timestamps,
            'open': prices,
            'high': prices * 1.001,
            'low': prices * 0.999,
            'close': prices + np.random.randn(bars) * 0.2,
            'volume': np.random.randint(100, 1000, bars)
        })
        df['symbol'] = symbol
        
        return df
    
    def resample_data(self, df: pd.DataFrame, timeframe: str = '5min') -> pd.DataFrame:
        """Resample data to different timeframe"""
        if 'timestamp' not in df.columns:
            return df
        
        df = df.set_index('timestamp')
        
        resampled = df.resample(timeframe).agg({
            'open': 'first',
            'high': 'max',
            'low': 'min',
            'close': 'last',
            'volume': 'sum'
        }).dropna()
        
        return resampled.reset_index()
    
    def validate_data(self, df: pd.DataFrame) -> bool:
        """Validate data quality"""
        if df is None or len(df) == 0:
            return False
        
        required_cols = ['open', 'high', 'low', 'close']
        if not all(col in df.columns for col in required_cols):
            return False
        
        # Check for invalid values
        for col in required_cols:
            if df[col].isnull().any():
                return False
            if (df[col] <= 0).any():
                return False
        
        # Check OHLC logic
        if not ((df['high'] >= df['open']) & (df['high'] >= df['close'])).all():
            return False
        if not ((df['low'] <= df['open']) & (df['low'] <= df['close'])).all():
            return False
        
        return True
