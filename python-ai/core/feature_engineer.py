"""Advanced feature engineering for ML models with market microstructure, multi-timeframe, and regime-aware features"""
import numpy as np
import pandas as pd
from typing import Dict, List, Optional, Tuple
import logging
import sys
sys.path.append('..')

from utils.math_utils import calculate_rsi, calculate_ema, calculate_atr
from utils.time_utils import get_time_features

logger = logging.getLogger(__name__)

class FeatureEngineer:
    """Advanced feature engineering with market microstructure, multi-timeframe analysis, and regime detection"""
    
    def __init__(self):
        self.feature_names = []
        self.scaler = None
        self.market_regime_cache = {}
        self.feature_cache = {}
        self.cache_size = 1000
        
    def build_features(self, df: pd.DataFrame) -> np.ndarray:
        """Build advanced comprehensive feature set with market microstructure, multi-timeframe, and regime-aware features"""
        try:
            # Check cache
            cache_key = hash(str(df.values.tobytes() if hasattr(df.values, 'tobytes') else str(df)))
            if cache_key in self.feature_cache:
                return self.feature_cache[cache_key]
            
            features = []
            close = df['close'].values
            high = df['high'].values if 'high' in df.columns else close
            low = df['low'].values if 'low' in df.columns else close
            open_prices = df['open'].values if 'open' in df.columns else close
            volume = df['volume'].values if 'volume' in df.columns else np.ones(len(close))
            
            min_len = len(close)
            
            # ========== 1. PRICE-BASED FEATURES (Enhanced) ==========
            if min_len > 1:
                returns = np.diff(close) / close[:-1]
                returns = np.append(0, returns)
                log_returns = np.diff(np.log(close))
                log_returns = np.append(0, log_returns)
                
                features.extend([
                    returns[-1],  # Last return
                    np.mean(returns[-5:]) if min_len >= 5 else 0.0,  # Short momentum
                    np.mean(returns[-10:]) if min_len >= 10 else 0.0,  # Medium momentum
                    np.mean(returns[-20:]) if min_len >= 20 else 0.0,  # Long momentum
                    np.std(returns[-10:]) if min_len >= 10 else 0.01,  # Short volatility
                    np.std(returns[-20:]) if min_len >= 20 else 0.01,  # Long volatility
                    log_returns[-1],  # Log return
                    np.sum(returns[-5:] > 0) / 5.0 if min_len >= 5 else 0.5,  # Upward momentum ratio
                ])
            else:
                features.extend([0.0] * 8)
            
            # ========== 2. ADVANCED TECHNICAL INDICATORS ==========
            if min_len >= 20:
                # RSI (multiple periods)
                rsi_14 = calculate_rsi(close, 14)
                rsi_7 = calculate_rsi(close[-7:], 7) if min_len >= 7 else 50.0
                features.extend([
                    (rsi_14 - 50) / 50,  # Normalized RSI
                    (rsi_7 - 50) / 50,  # Fast RSI
                ])
                
                # Moving Averages (multiple periods)
                sma_9 = np.mean(close[-9:]) if min_len >= 9 else close[-1]
                sma_20 = np.mean(close[-20:])
                sma_50 = np.mean(close[-50:]) if min_len >= 50 else sma_20
                sma_200 = np.mean(close[-200:]) if min_len >= 200 else sma_50
                
                ema_12 = calculate_ema(close, 12)[-1] if min_len >= 12 else close[-1]
                ema_26 = calculate_ema(close, 26)[-1] if min_len >= 26 else close[-1]
                
                features.extend([
                    (close[-1] - sma_9) / close[-1],  # Distance from SMA9
                    (close[-1] - sma_20) / close[-1],  # Distance from SMA20
                    (close[-1] - sma_50) / close[-1],  # Distance from SMA50
                    (sma_20 - sma_50) / sma_20 if sma_20 > 0 else 0.0,  # Trend strength
                    (sma_50 - sma_200) / sma_50 if sma_50 > 0 else 0.0,  # Long-term trend
                    (ema_12 - ema_26) / close[-1] if close[-1] > 0 else 0.0,  # MACD-like
                ])
            else:
                features.extend([0.0] * 8)
            
            # ========== 3. MARKET MICROSTRUCTURE FEATURES ==========
            if min_len >= 5:
                # Order flow imbalance
                buy_pressure = np.sum((close[-5:] - open_prices[-5:]) > 0) / 5.0
                sell_pressure = np.sum((close[-5:] - open_prices[-5:]) < 0) / 5.0
                imbalance = buy_pressure - sell_pressure
                
                # Price efficiency (how much price moved vs range)
                ranges = high[-5:] - low[-5:]
                price_moves = np.abs(close[-5:] - open_prices[-5:])
                efficiency = np.mean(price_moves / (ranges + 1e-8)) if len(ranges) > 0 else 0.5
                
                # Body to range ratio
                body_sizes = np.abs(close[-5:] - open_prices[-5:])
                body_to_range = np.mean(body_sizes / (ranges + 1e-8)) if len(ranges) > 0 else 0.5
                
                features.extend([
                    imbalance,  # Order flow imbalance
                    efficiency,  # Price efficiency
                    body_to_range,  # Body to range ratio
                ])
            else:
                features.extend([0.0] * 3)
            
            # ========== 4. VOLATILITY FEATURES (Advanced) ==========
            if min_len >= 20:
                # ATR-based features
                atr_14 = calculate_atr(high, low, close, 14) if all(len(arr) >= 15 for arr in [high, low, close]) else close[-1] * 0.01
                atr_ratio = atr_14 / close[-1] if close[-1] > 0 else 0.01
                
                # Volatility clustering
                volatility_20 = np.std(close[-20:]) / np.mean(close[-20:])
                volatility_5 = np.std(close[-5:]) / np.mean(close[-5:]) if min_len >= 5 else volatility_20
                vol_ratio = volatility_5 / (volatility_20 + 1e-8)
                
                # Parkinson volatility (using high-low)
                parkinson_vol = np.sqrt(np.mean((np.log(high[-20:] / low[-20:])) ** 2) / (4 * np.log(2))) if min_len >= 20 else 0.01
                
                features.extend([
                    atr_ratio,  # ATR ratio
                    vol_ratio,  # Volatility ratio
                    parkinson_vol,  # Parkinson volatility
                ])
            else:
                features.extend([0.01] * 3)
            
            # ========== 5. MARKET STRUCTURE FEATURES ==========
            if min_len >= 20:
                # Support/Resistance levels
                recent_high = np.max(high[-20:])
                recent_low = np.min(low[-20:])
                price_position = (close[-1] - recent_low) / (recent_high - recent_low) if recent_high > recent_low else 0.5
                
                # Higher highs / Lower lows detection
                highs_10 = high[-10:] if min_len >= 10 else high
                lows_10 = low[-10:] if min_len >= 10 else low
                higher_highs = np.sum(np.diff(highs_10) > 0) / max(len(highs_10) - 1, 1)
                lower_lows = np.sum(np.diff(lows_10) < 0) / max(len(lows_10) - 1, 1)
                
                # Swing points
                swing_high = np.max(high[-10:]) if min_len >= 10 else high[-1]
                swing_low = np.min(low[-10:]) if min_len >= 10 else low[-1]
                swing_range = (swing_high - swing_low) / close[-1] if close[-1] > 0 else 0.0
                
                features.extend([
                    price_position,  # Price position in range
                    higher_highs,  # Higher highs ratio
                    lower_lows,  # Lower lows ratio
                    swing_range,  # Swing range
                ])
            else:
                features.extend([0.5, 0.5, 0.5, 0.0])
            
            # ========== 6. VOLUME FEATURES (Advanced) ==========
            if min_len >= 20:
                volume_ma_20 = np.mean(volume[-20:])
                volume_ma_5 = np.mean(volume[-5:]) if min_len >= 5 else volume_ma_20
                volume_ratio = volume_ma_5 / (volume_ma_20 + 1e-8)
                
                # Price-Volume Trend (PVT)
                pvt = np.sum((close[-20:] - close[-21:-1]) / close[-21:-1] * volume[-20:]) if min_len >= 21 else 0.0
                pvt_normalized = pvt / (np.sum(volume[-20:]) + 1e-8)
                
                # Volume-weighted average price distance
                vwap = np.sum(close[-20:] * volume[-20:]) / np.sum(volume[-20:]) if np.sum(volume[-20:]) > 0 else close[-1]
                vwap_distance = (close[-1] - vwap) / close[-1] if close[-1] > 0 else 0.0
                
                features.extend([
                    min(5.0, volume_ratio),  # Volume ratio (capped)
                    pvt_normalized,  # PVT normalized
                    vwap_distance,  # VWAP distance
                ])
            else:
                features.extend([1.0, 0.0, 0.0])
            
            # ========== 7. TIME-BASED FEATURES (Enhanced) ==========
            time_feats = get_time_features()
            features.extend([
                time_feats['hour_sin'],
                time_feats['hour_cos'],
                time_feats['day_sin'],
                time_feats['day_cos'],
            ])
            
            # ========== 8. TREND FEATURES (Advanced) ==========
            if min_len >= 20:
                # Linear regression slope (multiple periods)
                x_20 = np.arange(20)
                y_20 = close[-20:]
                slope_20 = np.polyfit(x_20, y_20, 1)[0] / np.mean(y_20) if np.mean(y_20) > 0 else 0.0
                
                # ADX-like trend strength (simplified)
                up_moves = np.sum(np.maximum(high[-20:] - high[-21:-1], 0)) if min_len >= 21 else 0.0
                down_moves = np.sum(np.maximum(low[-21:-1] - low[-20:], 0)) if min_len >= 21 else 0.0
                trend_strength = (up_moves - down_moves) / (up_moves + down_moves + 1e-8)
                
                # Momentum acceleration
                momentum_5 = close[-1] / close[-5] - 1.0 if min_len >= 5 and close[-5] > 0 else 0.0
                momentum_10 = close[-1] / close[-10] - 1.0 if min_len >= 10 and close[-10] > 0 else 0.0
                momentum_accel = momentum_5 - momentum_10
                
                features.extend([
                    slope_20,  # Trend slope
                    trend_strength,  # Trend strength
                    momentum_accel,  # Momentum acceleration
                ])
            else:
                features.extend([0.0] * 3)
            
            # ========== 9. MOMENTUM OSCILLATORS ==========
            if min_len >= 14:
                # Stochastic-like
                highest_14 = np.max(high[-14:])
                lowest_14 = np.min(low[-14:])
                stoch = (close[-1] - lowest_14) / (highest_14 - lowest_14) if highest_14 > lowest_14 else 0.5
                
                # Rate of Change
                roc_10 = (close[-1] / close[-10] - 1.0) if min_len >= 10 and close[-10] > 0 else 0.0
                
                features.extend([
                    (stoch - 0.5) * 2,  # Normalized stochastic
                    roc_10,  # Rate of change
                ])
            else:
                features.extend([0.0, 0.0])
            
            # ========== 10. MARKET REGIME FEATURES ==========
            regime = self.classify_market_regime(df)
            regime_features = self._encode_regime(regime)
            features.extend(regime_features)
            
            # ========== 11. MULTI-TIMEFRAME FEATURES (Simplified) ==========
            if min_len >= 50:
                # Higher timeframe trend (using longer periods)
                ht_trend = (sma_20 - sma_50) / sma_20 if sma_20 > 0 else 0.0
                features.append(ht_trend)
            else:
                features.append(0.0)
            
            # Pad or truncate to exactly 50 features (expanded from 20)
            while len(features) < 50:
                features.append(0.0)
            features = features[:50]
            
            # Convert to numpy array and sanitize
            features = np.array(features, dtype=np.float32)
            features = np.nan_to_num(features, nan=0.0, posinf=1e6, neginf=-1e6)
            features = np.clip(features, -10, 10)
            
            # Update cache
            if len(self.feature_cache) >= self.cache_size:
                self.feature_cache.pop(next(iter(self.feature_cache)))
            self.feature_cache[cache_key] = features
            
            return features
            
        except Exception as e:
            logger.error(f"Feature engineering error: {e}")
            return np.zeros(50, dtype=np.float32)
    
    def get_feature_names(self) -> List[str]:
        """Get names of all features"""
        return [
            # Price features (8)
            'return_last', 'momentum_5', 'momentum_10', 'momentum_20',
            'volatility_10', 'volatility_20', 'log_return', 'upward_ratio',
            # Technical indicators (8)
            'rsi_14', 'rsi_7', 'dist_sma9', 'dist_sma20', 'dist_sma50',
            'trend_strength', 'long_trend', 'macd_like',
            # Microstructure (3)
            'order_imbalance', 'price_efficiency', 'body_to_range',
            # Volatility (3)
            'atr_ratio', 'vol_ratio', 'parkinson_vol',
            # Market structure (4)
            'price_position', 'higher_highs', 'lower_lows', 'swing_range',
            # Volume (3)
            'volume_ratio', 'pvt_normalized', 'vwap_distance',
            # Time (4)
            'hour_sin', 'hour_cos', 'day_sin', 'day_cos',
            # Trend (3)
            'trend_slope', 'trend_strength_adv', 'momentum_accel',
            # Momentum (2)
            'stoch_norm', 'roc_10',
            # Regime (4)
            'regime_trend', 'regime_vol', 'regime_combined_1', 'regime_combined_2',
            # Multi-timeframe (1)
            'ht_trend',
            # Padding (7)
            'feature_44', 'feature_45', 'feature_46', 'feature_47', 'feature_48', 'feature_49'
        ]
    
    def _encode_regime(self, regime: str) -> List[float]:
        """Encode market regime as features"""
        # One-hot encoding for regime
        regimes = ['UPTREND_HIGH_VOL', 'UPTREND_LOW_VOL', 'UPTREND_NORMAL_VOL',
                   'DOWNTREND_HIGH_VOL', 'DOWNTREND_LOW_VOL', 'DOWNTREND_NORMAL_VOL',
                   'RANGING_HIGH_VOL', 'RANGING_LOW_VOL', 'RANGING_NORMAL_VOL', 'UNKNOWN']
        
        # Extract trend and vol components
        trend_component = 0.0
        vol_component = 0.0
        
        if 'UPTREND' in regime:
            trend_component = 1.0
        elif 'DOWNTREND' in regime:
            trend_component = -1.0
        else:
            trend_component = 0.0
        
        if 'HIGH_VOL' in regime:
            vol_component = 1.0
        elif 'LOW_VOL' in regime:
            vol_component = -1.0
        else:
            vol_component = 0.0
        
        # Return 4 features: trend, vol, and 2 combined
        return [trend_component, vol_component, trend_component * vol_component, abs(trend_component)]
    
    def classify_market_regime(self, df: pd.DataFrame) -> str:
        """Advanced market regime classification with multiple indicators"""
        if len(df) < 20:
            return "UNKNOWN"
        
        close = df['close'].values
        high = df['high'].values if 'high' in df.columns else close
        low = df['low'].values if 'low' in df.columns else close
        
        # Multiple timeframe analysis
        sma_9 = np.mean(close[-9:]) if len(close) >= 9 else close[-1]
        sma_20 = np.mean(close[-20:])
        sma_50 = np.mean(close[-50:]) if len(close) >= 50 else sma_20
        sma_200 = np.mean(close[-200:]) if len(close) >= 200 else sma_50
        
        # Volatility calculation (multiple methods)
        returns = np.diff(close) / close[:-1]
        volatility = np.std(returns[-20:]) if len(returns) >= 20 else 0.01
        atr = calculate_atr(high, low, close, 14) if len(close) >= 15 else close[-1] * 0.01
        atr_ratio = atr / close[-1] if close[-1] > 0 else 0.01
        
        # Trend detection (multiple confirmations)
        trend_score = 0.0
        
        # SMA alignment
        if sma_9 > sma_20 > sma_50:
            trend_score += 1.0
        elif sma_9 < sma_20 < sma_50:
            trend_score -= 1.0
        
        # Price vs SMAs
        if close[-1] > sma_20 > sma_50:
            trend_score += 0.5
        elif close[-1] < sma_20 < sma_50:
            trend_score -= 0.5
        
        # Momentum
        momentum_20 = (close[-1] - close[-20]) / close[-20] if len(close) >= 20 else 0.0
        if momentum_20 > 0.01:
            trend_score += 0.5
        elif momentum_20 < -0.01:
            trend_score -= 0.5
        
        # Determine trend
        if trend_score > 0.5:
            trend = "UPTREND"
        elif trend_score < -0.5:
            trend = "DOWNTREND"
        else:
            trend = "RANGING"
        
        # Volatility regime (using ATR ratio)
        if atr_ratio > 0.02:
            vol_regime = "HIGH_VOL"
        elif atr_ratio < 0.005:
            vol_regime = "LOW_VOL"
        else:
            vol_regime = "NORMAL_VOL"
        
        return f"{trend}_{vol_regime}"
