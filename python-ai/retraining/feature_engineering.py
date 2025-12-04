"""
Advanced Feature Engineering for Retraining Pipeline
Extends core feature engineer with log-based and strategy-based features
"""

import numpy as np
import pandas as pd
from typing import Dict, List
import logging
import sys
sys.path.append('..')

from core.feature_engineer import FeatureEngineer

logger = logging.getLogger(__name__)


class RetrainingFeatureEngineer(FeatureEngineer):
    """Extended feature engineering for model retraining"""
    
    def __init__(self):
        super().__init__()
        self.feature_groups = {
            'price_based': [],
            'log_based': [],
            'strategy_based': [],
            'technical': [],
            'time_based': []
        }
    
    def build_training_features(self, df: pd.DataFrame, include_target: bool = True) -> pd.DataFrame:
        """Build complete feature set for model training"""
        logger.info(f"Building training features from {len(df)} rows...")
        
        features_df = pd.DataFrame()
        
        # 1. Price-based features
        if 'close' in df.columns:
            price_features = self._extract_price_features(df)
            features_df = pd.concat([features_df, price_features], axis=1)
            self.feature_groups['price_based'] = list(price_features.columns)
        
        # 2. Technical indicators
        if 'close' in df.columns:
            technical_features = self._extract_technical_features(df)
            features_df = pd.concat([features_df, technical_features], axis=1)
            self.feature_groups['technical'] = list(technical_features.columns)
        
        # 3. Time-based features
        if 'timestamp' in df.columns:
            time_features = self._extract_time_features(df)
            features_df = pd.concat([features_df, time_features], axis=1)
            self.feature_groups['time_based'] = list(time_features.columns)
        
        # 4. Log-based features (if available)
        if 'profit' in df.columns or 'action' in df.columns:
            log_features = self._extract_log_features(df)
            features_df = pd.concat([features_df, log_features], axis=1)
            self.feature_groups['log_based'] = list(log_features.columns)
        
        # 5. Strategy-based features (if available)
        if 'win_rate' in df.columns or 'drawdown' in df.columns:
            strategy_features = self._extract_strategy_features(df)
            features_df = pd.concat([features_df, strategy_features], axis=1)
            self.feature_groups['strategy_based'] = list(strategy_features.columns)
        
        # 6. Target variable (if requested)
        if include_target and 'close' in df.columns:
            target = self._create_target_variable(df)
            features_df['target'] = target
        
        # Clean features
        features_df = self._clean_features(features_df)
        
        logger.info(f"Features built: {len(features_df.columns)} features, {len(features_df)} samples")
        
        return features_df
    
    def _extract_price_features(self, df: pd.DataFrame) -> pd.DataFrame:
        """Extract price-based features"""
        features = pd.DataFrame(index=df.index)
        
        close = df['close'].values
        
        # Returns
        features['returns'] = df['close'].pct_change()
        features['log_returns'] = np.log(df['close'] / df['close'].shift(1))
        
        # Volatility
        features['volatility_10'] = features['returns'].rolling(10).std()
        features['volatility_20'] = features['returns'].rolling(20).std()
        features['volatility_50'] = features['returns'].rolling(50).std()
        
        # Price position
        features['price_pct_change_1'] = df['close'].pct_change(1)
        features['price_pct_change_5'] = df['close'].pct_change(5)
        features['price_pct_change_10'] = df['close'].pct_change(10)
        
        # High/Low range
        if 'high' in df.columns and 'low' in df.columns:
            features['hl_range'] = (df['high'] - df['low']) / df['close']
            features['hl_range_ma'] = features['hl_range'].rolling(20).mean()
        
        return features
    
    def _extract_technical_features(self, df: pd.DataFrame) -> pd.DataFrame:
        """Extract technical indicator features"""
        features = pd.DataFrame(index=df.index)
        
        close = df['close'].values
        
        # Moving averages
        features['sma_10'] = df['close'].rolling(10).mean()
        features['sma_20'] = df['close'].rolling(20).mean()
        features['sma_50'] = df['close'].rolling(50).mean()
        
        # Distance from MAs
        features['dist_sma_10'] = (df['close'] - features['sma_10']) / df['close']
        features['dist_sma_20'] = (df['close'] - features['sma_20']) / df['close']
        
        # MA crossovers
        features['sma_10_20_cross'] = (features['sma_10'] > features['sma_20']).astype(int)
        
        # RSI
        delta = df['close'].diff()
        gain = (delta.where(delta > 0, 0)).rolling(14).mean()
        loss = (-delta.where(delta < 0, 0)).rolling(14).mean()
        rs = gain / loss
        features['rsi'] = 100 - (100 / (1 + rs))
        
        # Momentum
        features['momentum_5'] = df['close'] / df['close'].shift(5) - 1
        features['momentum_10'] = df['close'] / df['close'].shift(10) - 1
        
        # Bollinger Bands
        bb_period = 20
        features['bb_middle'] = df['close'].rolling(bb_period).mean()
        bb_std = df['close'].rolling(bb_period).std()
        features['bb_upper'] = features['bb_middle'] + 2 * bb_std
        features['bb_lower'] = features['bb_middle'] - 2 * bb_std
        features['bb_position'] = (df['close'] - features['bb_lower']) / (features['bb_upper'] - features['bb_lower'])
        
        return features
    
    def _extract_time_features(self, df: pd.DataFrame) -> pd.DataFrame:
        """Extract time-based features"""
        features = pd.DataFrame(index=df.index)
        
        if 'timestamp' in df.columns:
            timestamps = pd.to_datetime(df['timestamp'])
            
            features['hour'] = timestamps.dt.hour
            features['day_of_week'] = timestamps.dt.dayofweek
            features['day_of_month'] = timestamps.dt.day
            
            # Cyclical encoding
            features['hour_sin'] = np.sin(2 * np.pi * features['hour'] / 24)
            features['hour_cos'] = np.cos(2 * np.pi * features['hour'] / 24)
            features['day_sin'] = np.sin(2 * np.pi * features['day_of_week'] / 7)
            features['day_cos'] = np.cos(2 * np.pi * features['day_of_week'] / 7)
            
            # Trading sessions
            features['is_asian_session'] = ((features['hour'] >= 0) & (features['hour'] < 8)).astype(int)
            features['is_london_session'] = ((features['hour'] >= 8) & (features['hour'] < 16)).astype(int)
            features['is_ny_session'] = ((features['hour'] >= 13) & (features['hour'] < 22)).astype(int)
        
        return features
    
    def _extract_log_features(self, df: pd.DataFrame) -> pd.DataFrame:
        """Extract log-based features from trading history"""
        features = pd.DataFrame(index=df.index)
        
        # Entry/Exit reasons
        if 'action' in df.columns:
            features['action_buy'] = (df['action'] == 'BUY').astype(int)
            features['action_sell'] = (df['action'] == 'SELL').astype(int)
        
        # Profit/Loss patterns
        if 'profit' in df.columns:
            features['profit'] = df['profit']
            features['is_profitable'] = (df['profit'] > 0).astype(int)
            features['profit_ma_5'] = df['profit'].rolling(5).mean()
            features['profit_std_5'] = df['profit'].rolling(5).std()
        
        # Confidence levels
        if 'confidence' in df.columns:
            features['confidence'] = df['confidence']
            features['confidence_ma'] = df['confidence'].rolling(10).mean()
        
        return features
    
    def _extract_strategy_features(self, df: pd.DataFrame) -> pd.DataFrame:
        """Extract strategy performance features"""
        features = pd.DataFrame(index=df.index)
        
        # Win rate
        if 'win_rate' in df.columns:
            features['win_rate'] = df['win_rate']
            features['win_rate_ma'] = df['win_rate'].rolling(20).mean()
        
        # Drawdown
        if 'drawdown' in df.columns:
            features['drawdown'] = df['drawdown']
            features['max_drawdown_20'] = df['drawdown'].rolling(20).min()
        
        # Expectancy
        if 'expectancy' in df.columns:
            features['expectancy'] = df['expectancy']
        
        return features
    
    def _create_target_variable(self, df: pd.DataFrame) -> pd.Series:
        """Create target variable for supervised learning"""
        # Target: future price direction
        future_periods = 5
        
        future_returns = df['close'].shift(-future_periods) / df['close'] - 1
        
        # Classify into BUY (1), SELL (-1), HOLD (0)
        target = pd.Series(0, index=df.index)
        target[future_returns > 0.002] = 1  # BUY if >0.2% gain
        target[future_returns < -0.002] = -1  # SELL if >0.2% loss
        
        return target
    
    def _clean_features(self, df: pd.DataFrame) -> pd.DataFrame:
        """Clean and normalize features"""
        # Forward fill NaN values
        df = df.fillna(method='ffill')
        
        # Backward fill remaining NaN
        df = df.fillna(method='bfill')
        
        # Replace inf values
        df = df.replace([np.inf, -np.inf], 0)
        
        # Final NaN fill
        df = df.fillna(0)
        
        return df
    
    def get_feature_importance_groups(self) -> Dict[str, List[str]]:
        """Get feature groups for importance analysis"""
        return self.feature_groups
