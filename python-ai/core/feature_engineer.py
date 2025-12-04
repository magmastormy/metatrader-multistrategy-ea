"""Feature engineering for ML models"""
import numpy as np
import pandas as pd
from typing import Dict, List, Optional
import logging
import sys
sys.path.append('..')

from utils.math_utils import calculate_rsi, calculate_ema, calculate_atr
from utils.time_utils import get_time_features

logger = logging.getLogger(__name__)

class FeatureEngineer:
    """Transforms raw market data into ML-ready features"""
    
    def __init__(self):
        self.feature_names = []
        self.scaler = None
        
    def build_features(self, df: pd.DataFrame) -> np.ndarray:
        """Build comprehensive feature set from market data"""
        try:
            features = []
            
            # 1. Price-based features
            close = df['close'].values
            if len(close) > 1:
                returns = np.diff(close) / close[:-1]
                returns = np.append(0, returns)  # Prepend 0 for alignment
                
                features.extend([
                    returns[-1] if len(returns) > 0 else 0.0,  # Last return
                    np.mean(returns[-10:]) if len(returns) >= 10 else 0.0,  # Recent momentum
                    np.std(returns[-20:]) if len(returns) >= 20 else 0.01,  # Volatility
                ])
            else:
                features.extend([0.0, 0.0, 0.01])
            
            # 2. Technical indicators
            if len(close) >= 20:
                rsi = calculate_rsi(close, period=14)
                features.append((rsi - 50) / 50)  # Normalize RSI
                
                # Moving averages
                sma_20 = np.mean(close[-20:])
                sma_50 = np.mean(close[-50:]) if len(close) >= 50 else sma_20
                
                features.extend([
                    (close[-1] - sma_20) / close[-1],  # Distance from SMA20
                    (sma_20 - sma_50) / sma_20 if sma_20 > 0 else 0.0,  # Trend strength
                ])
            else:
                features.extend([0.0, 0.0, 0.0])
            
            # 3. Volatility features
            if len(close) >= 20:
                volatility_20 = np.std(close[-20:]) / np.mean(close[-20:])
                features.append(volatility_20)
            else:
                features.append(0.01)
            
            # 4. Market structure
            if len(close) >= 10:
                # Higher highs / lower lows
                recent_high = np.max(close[-10:])
                recent_low = np.min(close[-10:])
                price_position = (close[-1] - recent_low) / (recent_high - recent_low) if recent_high > recent_low else 0.5
                features.append(price_position)
            else:
                features.append(0.5)
            
            # 5. Volume features (if available)
            if 'volume' in df.columns and len(df['volume']) >= 20:
                volume = df['volume'].values
                volume_ma = np.mean(volume[-20:])
                volume_ratio = volume[-1] / volume_ma if volume_ma > 0 else 1.0
                features.append(min(5.0, volume_ratio))  # Cap at 5x
            else:
                features.append(1.0)
            
            # 6. Time-based features
            time_feats = get_time_features()
            features.extend([
                time_feats['hour_sin'],
                time_feats['hour_cos'],
                time_feats['day_sin'],
                time_feats['day_cos'],
            ])
            
            # 7. Trend features
            if len(close) >= 20:
                # Linear regression slope
                x = np.arange(20)
                y = close[-20:]
                slope = np.polyfit(x, y, 1)[0]
                features.append(slope / np.mean(y) if np.mean(y) > 0 else 0.0)
            else:
                features.append(0.0)
            
            # 8. ATR-based features
            if len(df) >= 20 and all(col in df.columns for col in ['high', 'low', 'close']):
                atr = calculate_atr(
                    df['high'].values,
                    df['low'].values,
                    df['close'].values,
                    period=14
                )
                features.append(atr / close[-1] if close[-1] > 0 else 0.0)
            else:
                features.append(0.01)
            
            # 9. Momentum oscillators
            if len(close) >= 10:
                momentum = close[-1] / close[-10] - 1.0 if close[-10] > 0 else 0.0
                features.append(momentum)
            else:
                features.append(0.0)
            
            # Pad or truncate to exactly 20 features
            while len(features) < 20:
                features.append(0.0)
            features = features[:20]
            
            # Convert to numpy array and sanitize
            features = np.array(features, dtype=np.float32)
            features = np.nan_to_num(features, nan=0.0, posinf=1e6, neginf=-1e6)
            features = np.clip(features, -10, 10)
            
            return features
            
        except Exception as e:
            logger.error(f"Feature engineering error: {e}")
            return np.zeros(20, dtype=np.float32)
    
    def get_feature_names(self) -> List[str]:
        """Get names of all features"""
        return [
            'return_last', 'momentum_10', 'volatility_20',
            'rsi_norm', 'distance_sma20', 'trend_strength',
            'volatility_ratio', 'price_position', 'volume_ratio',
            'hour_sin', 'hour_cos', 'day_sin', 'day_cos',
            'trend_slope', 'atr_ratio', 'momentum_10_period',
            'feature_16', 'feature_17', 'feature_18', 'feature_19'
        ]
    
    def classify_market_regime(self, df: pd.DataFrame) -> str:
        """Classify current market regime"""
        if len(df) < 50:
            return "UNKNOWN"
        
        close = df['close'].values
        sma_20 = np.mean(close[-20:])
        sma_50 = np.mean(close[-50:])
        
        volatility = np.std(close[-20:]) / np.mean(close[-20:])
        
        # Trend detection
        if sma_20 > sma_50 * 1.01:
            trend = "UPTREND"
        elif sma_20 < sma_50 * 0.99:
            trend = "DOWNTREND"
        else:
            trend = "RANGING"
        
        # Volatility regime
        if volatility > 0.02:
            vol_regime = "HIGH_VOL"
        elif volatility < 0.01:
            vol_regime = "LOW_VOL"
        else:
            vol_regime = "NORMAL_VOL"
        
        return f"{trend}_{vol_regime}"
