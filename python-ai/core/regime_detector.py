"""Advanced Market Regime Detection using Hidden Markov Models and Clustering"""
import numpy as np
import pandas as pd
from typing import Dict, List, Tuple, Optional
import logging
from collections import deque

logger = logging.getLogger(__name__)

try:
    from sklearn.cluster import KMeans
    from sklearn.preprocessing import StandardScaler
    SKLEARN_AVAILABLE = True
except ImportError:
    SKLEARN_AVAILABLE = False
    logger.warning("scikit-learn not available for regime detection")

try:
    from hmmlearn import hmm
    HMM_AVAILABLE = True
except ImportError:
    try:
        import hmmlearn.hmm as hmm
        HMM_AVAILABLE = True
    except ImportError:
        HMM_AVAILABLE = False
        logger.warning("hmmlearn not available - install with: pip install hmmlearn")


class MarketRegimeDetector:
    """Advanced market regime detection using HMM and clustering"""
    
    def __init__(self, n_regimes: int = 4, lookback: int = 100):
        self.n_regimes = n_regimes
        self.lookback = lookback
        self.hmm_model = None
        self.kmeans_model = None
        self.scaler = StandardScaler() if SKLEARN_AVAILABLE else None
        self.regime_history = deque(maxlen=lookback)
        self.feature_history = deque(maxlen=lookback)
        self.is_fitted = False
        
    def extract_regime_features(self, df: pd.DataFrame) -> np.ndarray:
        """Extract features for regime detection"""
        try:
            close = df['close'].values
            high = df['high'].values if 'high' in df.columns else close
            low = df['low'].values if 'low' in df.columns else close
            volume = df['volume'].values if 'volume' in df.columns else np.ones(len(close))
            
            features = []
            
            # Returns
            returns = np.diff(close) / close[:-1]
            returns = np.append(0, returns)
            
            # Volatility
            volatility = np.std(returns[-20:]) if len(returns) >= 20 else 0.01
            
            # Trend strength
            sma_20 = np.mean(close[-20:]) if len(close) >= 20 else close[-1]
            sma_50 = np.mean(close[-50:]) if len(close) >= 50 else sma_20
            trend_strength = (sma_20 - sma_50) / sma_50 if sma_50 > 0 else 0.0
            
            # Momentum
            momentum = (close[-1] - close[-10]) / close[-10] if len(close) >= 10 and close[-10] > 0 else 0.0
            
            # Volume trend
            volume_ma = np.mean(volume[-20:]) if len(volume) >= 20 else 1.0
            volume_ratio = volume[-1] / volume_ma if volume_ma > 0 else 1.0
            
            # ATR
            atr = np.mean(high[-14:] - low[-14:]) if len(high) >= 14 else close[-1] * 0.01
            atr_ratio = atr / close[-1] if close[-1] > 0 else 0.01
            
            # Price position
            recent_high = np.max(high[-20:]) if len(high) >= 20 else high[-1]
            recent_low = np.min(low[-20:]) if len(low) >= 20 else low[-1]
            price_position = (close[-1] - recent_low) / (recent_high - recent_low) if recent_high > recent_low else 0.5
            
            features = np.array([
                returns[-1],
                volatility,
                trend_strength,
                momentum,
                volume_ratio,
                atr_ratio,
                price_position
            ])
            
            return features
            
        except Exception as e:
            logger.error(f"Error extracting regime features: {e}")
            return np.zeros(7)
    
    def detect_regime_hmm(self, features: np.ndarray) -> Tuple[int, float]:
        """Detect regime using Hidden Markov Model"""
        if not HMM_AVAILABLE or self.hmm_model is None:
            return 0, 0.5
        
        try:
            # Reshape for HMM (needs sequence)
            if len(features.shape) == 1:
                features = features.reshape(1, -1)
            
            # Predict regime
            regime = self.hmm_model.predict(features)[0]
            log_prob = self.hmm_model.score(features)
            confidence = min(1.0, max(0.0, 1.0 - abs(log_prob) / 10.0))
            
            return int(regime), float(confidence)
            
        except Exception as e:
            logger.error(f"HMM regime detection error: {e}")
            return 0, 0.5
    
    def detect_regime_clustering(self, features: np.ndarray) -> Tuple[int, float]:
        """Detect regime using K-Means clustering"""
        if not SKLEARN_AVAILABLE or self.kmeans_model is None:
            return 0, 0.5
        
        try:
            # Scale features
            features_scaled = self.scaler.transform(features.reshape(1, -1))
            
            # Predict cluster
            regime = self.kmeans_model.predict(features_scaled)[0]
            
            # Calculate distance to cluster center (confidence)
            center = self.kmeans_model.cluster_centers_[regime]
            distance = np.linalg.norm(features_scaled[0] - center)
            max_distance = np.max([np.linalg.norm(center - c) for c in self.kmeans_model.cluster_centers_])
            confidence = 1.0 - min(1.0, distance / (max_distance + 1e-8))
            
            return int(regime), float(confidence)
            
        except Exception as e:
            logger.error(f"Clustering regime detection error: {e}")
            return 0, 0.5
    
    def detect_regime(self, df: pd.DataFrame) -> Dict:
        """Detect current market regime"""
        try:
            features = self.extract_regime_features(df)
            
            # Try HMM first, fallback to clustering
            if self.hmm_model is not None:
                regime_id, confidence = self.detect_regime_hmm(features)
                method = 'hmm'
            elif self.kmeans_model is not None:
                regime_id, confidence = self.detect_regime_clustering(features)
                method = 'clustering'
            else:
                # Fallback to simple classification
                regime_id, confidence = self._simple_regime_classification(df)
                method = 'simple'
            
            # Map regime ID to name
            regime_names = ['TRENDING_UP', 'TRENDING_DOWN', 'RANGING', 'HIGH_VOLATILITY']
            regime_name = regime_names[regime_id % len(regime_names)]
            
            result = {
                'regime_id': regime_id,
                'regime_name': regime_name,
                'confidence': confidence,
                'method': method,
                'features': features.tolist()
            }
            
            # Update history
            self.regime_history.append(result)
            self.feature_history.append(features)
            
            return result
            
        except Exception as e:
            logger.error(f"Regime detection error: {e}")
            return {
                'regime_id': 0,
                'regime_name': 'UNKNOWN',
                'confidence': 0.0,
                'method': 'error'
            }
    
    def _simple_regime_classification(self, df: pd.DataFrame) -> Tuple[int, float]:
        """Simple regime classification fallback"""
        try:
            close = df['close'].values
            if len(close) < 20:
                return 0, 0.5
            
            sma_20 = np.mean(close[-20:])
            sma_50 = np.mean(close[-50:]) if len(close) >= 50 else sma_20
            
            returns = np.diff(close) / close[:-1]
            volatility = np.std(returns[-20:]) if len(returns) >= 20 else 0.01
            
            # Determine regime
            if sma_20 > sma_50 * 1.01:
                regime = 0  # Trending up
            elif sma_20 < sma_50 * 0.99:
                regime = 1  # Trending down
            elif volatility > 0.02:
                regime = 3  # High volatility
            else:
                regime = 2  # Ranging
            
            confidence = 0.7
            
            return regime, confidence
            
        except Exception as e:
            logger.error(f"Simple regime classification error: {e}")
            return 0, 0.5
    
    def fit(self, df_list: List[pd.DataFrame]):
        """Fit regime detection models on historical data"""
        try:
            if not SKLEARN_AVAILABLE:
                logger.warning("Cannot fit models - scikit-learn not available")
                return
            
            # Extract features from all dataframes
            all_features = []
            for df in df_list:
                features = self.extract_regime_features(df)
                all_features.append(features)
            
            if len(all_features) < 50:
                logger.warning(f"Insufficient data for fitting ({len(all_features)} samples)")
                return
            
            X = np.array(all_features)
            
            # Fit scaler
            self.scaler.fit(X)
            X_scaled = self.scaler.transform(X)
            
            # Fit K-Means
            self.kmeans_model = KMeans(n_clusters=self.n_regimes, random_state=42, n_init=10)
            self.kmeans_model.fit(X_scaled)
            
            logger.info(f"Fitted K-Means regime detector with {self.n_regimes} regimes")
            
            # Fit HMM if available
            if HMM_AVAILABLE:
                try:
                    self.hmm_model = hmm.GaussianHMM(n_components=self.n_regimes, covariance_type="full", n_iter=100)
                    self.hmm_model.fit(X_scaled)
                    logger.info(f"Fitted HMM regime detector with {self.n_regimes} states")
                except Exception as e:
                    logger.warning(f"Failed to fit HMM: {e}")
            
            self.is_fitted = True
            
        except Exception as e:
            logger.error(f"Error fitting regime detector: {e}")
    
    def get_regime_statistics(self) -> Dict:
        """Get statistics about detected regimes"""
        if not self.regime_history:
            return {'total_detections': 0}
        
        regime_counts = {}
        for r in self.regime_history:
            name = r['regime_name']
            regime_counts[name] = regime_counts.get(name, 0) + 1
        
        confidences = [r['confidence'] for r in self.regime_history]
        
        return {
            'total_detections': len(self.regime_history),
            'regime_counts': regime_counts,
            'avg_confidence': float(np.mean(confidences)),
            'is_fitted': self.is_fitted
        }

