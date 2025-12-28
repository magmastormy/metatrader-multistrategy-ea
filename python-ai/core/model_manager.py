"""Model management and inference"""
import numpy as np
import pickle
import json
import logging
from pathlib import Path
from typing import Dict, Optional, Any
from datetime import datetime

logger = logging.getLogger(__name__)

try:
    import lightgbm as lgb
    LGBM_AVAILABLE = True
except ImportError:
    LGBM_AVAILABLE = False
    logger.warning("LightGBM not available")

try:
    import torch
    import torch.nn as nn
    TORCH_AVAILABLE = True
except ImportError:
    TORCH_AVAILABLE = False
    logger.warning("PyTorch not available")

try:
    import onnxruntime as ort
    ONNX_AVAILABLE = True
except ImportError:
    ONNX_AVAILABLE = False
    logger.warning("ONNX Runtime not available")



if TORCH_AVAILABLE:
    class LightweightTransformer(nn.Module):
        """Advanced lightweight transformer with attention mechanisms for trading"""
        
        def __init__(self, input_dim=50, d_model=128, nhead=8, num_layers=4, dropout=0.1):
            super().__init__()
            self.input_dim = input_dim
            self.d_model = d_model
            
            # Input projection with layer norm
            self.input_projection = nn.Sequential(
                nn.Linear(input_dim, d_model),
                nn.LayerNorm(d_model),
                nn.Dropout(dropout)
            )
            
            # Learnable positional encoding
            self.positional_encoding = nn.Parameter(torch.randn(500, d_model) * 0.02)
            
            # Multi-head attention transformer
            encoder_layer = nn.TransformerEncoderLayer(
                d_model=d_model,
                nhead=nhead,
                dim_feedforward=d_model * 4,  # Increased feedforward
                dropout=dropout,
                batch_first=True,
                activation='gelu'  # GELU activation
            )
            self.transformer = nn.TransformerEncoder(encoder_layer, num_layers=num_layers)
            
            # Multi-task output heads
            self.signal_head = nn.Sequential(
                nn.Linear(d_model, d_model // 2),
                nn.GELU(),
                nn.Dropout(dropout),
                nn.Linear(d_model // 2, 1)
            )
            
            self.confidence_head = nn.Sequential(
                nn.Linear(d_model, d_model // 2),
                nn.GELU(),
                nn.Dropout(dropout),
                nn.Linear(d_model // 2, 1)
            )
            
            # Uncertainty quantification head
            self.uncertainty_head = nn.Sequential(
                nn.Linear(d_model, d_model // 2),
                nn.GELU(),
                nn.Linear(d_model // 2, 1)
            )
            
        def forward(self, x):
            # x shape: (batch, seq_len, input_dim) or (batch, input_dim)
            if len(x.shape) == 2:
                x = x.unsqueeze(1)  # Add sequence dimension
            
            batch_size, seq_len, _ = x.shape
            
            # Project and add positional encoding
            x = self.input_projection(x)
            x = x + self.positional_encoding[:seq_len, :].unsqueeze(0)
            
            # Transformer encoding
            x = self.transformer(x)
            x = x[:, -1, :]  # Take last token
            
            # Multi-task predictions
            signal = torch.tanh(self.signal_head(x))
            confidence = torch.sigmoid(self.confidence_head(x))
            uncertainty = torch.sigmoid(self.uncertainty_head(x))
            
            return signal, confidence, uncertainty
    
    class TemporalConvolutionalNetwork(nn.Module):
        """Temporal Convolutional Network for sequence modeling"""
        
        def __init__(self, input_dim=50, num_filters=64, kernel_size=3, num_layers=3):
            super().__init__()
            self.input_dim = input_dim
            
            layers = []
            in_channels = input_dim
            for i in range(num_layers):
                layers.append(nn.Conv1d(in_channels, num_filters, kernel_size, padding=(kernel_size-1)//2))
                layers.append(nn.BatchNorm1d(num_filters))
                layers.append(nn.ReLU())
                layers.append(nn.Dropout(0.1))
                in_channels = num_filters
            
            self.conv_layers = nn.Sequential(*layers)
            
            # Global pooling
            self.global_pool = nn.AdaptiveAvgPool1d(1)
            
            # Output heads
            self.signal_head = nn.Linear(num_filters, 1)
            self.confidence_head = nn.Linear(num_filters, 1)
            
        def forward(self, x):
            # x: (batch, seq_len, features)
            if len(x.shape) == 2:
                x = x.unsqueeze(1)
            
            x = x.transpose(1, 2)  # (batch, features, seq_len)
            x = self.conv_layers(x)
            x = self.global_pool(x).squeeze(-1)  # (batch, features)
            
            signal = torch.tanh(self.signal_head(x))
            confidence = torch.sigmoid(self.confidence_head(x))
            
            return signal, confidence, torch.zeros_like(confidence)  # No uncertainty for TCN
else:
    class LightweightTransformer:
        pass
    
    class TemporalConvolutionalNetwork:
        pass


class ModelManager:
    """Manages ML models for trading predictions"""
    
    def __init__(self, model_dir: str = "models"):
        self.model_dir = Path(model_dir)
        self.model_dir.mkdir(exist_ok=True)
        
        self.models = {}
        self.model_weights = {}
        self.registry = self._load_registry()
        
        # Advanced cache with TTL
        self.cache = {}
        self.cache_timestamps = {}
        self.cache_size = 1000
        self.cache_ttl = 30  # seconds
        
        # Ensemble configuration
        self.use_dynamic_weights = True
        self.model_performance = {}  # Track model performance for dynamic weighting
        
        self._load_models()
    
    def _load_registry(self) -> Dict:
        """Load model registry"""
        registry_path = self.model_dir / "model_registry.json"
        if registry_path.exists():
            with open(registry_path, 'r') as f:
                return json.load(f)
        return {}
    
    def _save_registry(self):
        """Save model registry"""
        registry_path = self.model_dir / "model_registry.json"
        with open(registry_path, 'w') as f:
            json.dump(self.registry, f, indent=2)
    
    def _load_models(self):
        """Load all available models"""
        logger.info("Loading models...")
        
        # 1. Load LightGBM model
        if LGBM_AVAILABLE:
            lgbm_path = self.model_dir / "lgbm_model.pkl"
            if lgbm_path.exists():
                try:
                    with open(lgbm_path, 'rb') as f:
                        self.models['lgbm'] = pickle.load(f)
                    self.model_weights['lgbm'] = 0.6
                    logger.info("LightGBM model loaded")
                except Exception as e:
                    logger.error(f"Failed to load LightGBM: {e}")
        
        # 2. Load Transformer model (updated architecture)
        if TORCH_AVAILABLE:
            transformer_path = self.model_dir / "transformer_small.pt"
            if transformer_path.exists():
                try:
                    # Try loading with new architecture (50 features)
                    self.models['transformer'] = LightweightTransformer(input_dim=50, d_model=128, nhead=8, num_layers=4)
                    try:
                        self.models['transformer'].load_state_dict(
                            torch.load(transformer_path, map_location='cpu'),
                            strict=False  # Allow partial loading for architecture changes
                        )
                    except:
                        # If loading fails, initialize new model
                        logger.info("Initializing new transformer architecture")
                    self.models['transformer'].eval()
                    self.model_weights['transformer'] = 0.4
                    self.model_performance['transformer'] = {'accuracy': 0.0, 'count': 0}
                    logger.info("Transformer model loaded")
                except Exception as e:
                    logger.error(f"Failed to load Transformer: {e}")
            
            # 2b. Load TCN model if available
            tcn_path = self.model_dir / "tcn_model.pt"
            if tcn_path.exists():
                try:
                    self.models['tcn'] = TemporalConvolutionalNetwork(input_dim=50, num_filters=64, num_layers=3)
                    try:
                        self.models['tcn'].load_state_dict(
                            torch.load(tcn_path, map_location='cpu'),
                            strict=False
                        )
                    except:
                        logger.info("Initializing new TCN architecture")
                    self.models['tcn'].eval()
                    self.model_weights['tcn'] = 0.3
                    self.model_performance['tcn'] = {'accuracy': 0.0, 'count': 0}
                    logger.info("TCN model loaded")
                except Exception as e:
                    logger.error(f"Failed to load TCN: {e}")
        
        # 3. Load ONNX model
        if ONNX_AVAILABLE:
            onnx_path = self.model_dir / "trading_model.onnx"
            if onnx_path.exists():
                try:
                    self.models['onnx'] = ort.InferenceSession(
                        str(onnx_path),
                        providers=['CPUExecutionProvider']
                    )
                    self.model_weights['onnx'] = 0.5
                    logger.info("ONNX model loaded")
                except Exception as e:
                    logger.error(f"Failed to load ONNX: {e}")
        
        if not self.models:
            logger.warning("NO MODELS LOADED, using fallback logic")
    
    def predict(self, features: np.ndarray) -> Dict[str, float]:
        """Generate advanced ensemble prediction with dynamic weighting"""
        try:
            # Check cache with TTL
            features_hash = hash(features.tobytes())
            import time
            current_time = time.time()
            
            if features_hash in self.cache:
                cache_time = self.cache_timestamps.get(features_hash, 0)
                if current_time - cache_time < self.cache_ttl:
                    return self.cache[features_hash]
            
            if len(self.models) == 0:
                result = self._fallback_prediction(features)
                self._update_cache(features_hash, result, current_time)
                return result
            
            predictions = []
            confidences = []
            uncertainties = []
            weights = []
            model_names = []
            
            # LightGBM prediction
            if 'lgbm' in self.models:
                try:
                    # Handle feature dimension mismatch
                    if len(features) > 20:
                        # Use first 20 features for old models
                        pred_features = features[:20]
                    else:
                        pred_features = features
                    
                    pred = self.models['lgbm'].predict(pred_features.reshape(1, -1))[0]
                    signal = np.tanh(pred)  # Normalize to [-1, 1]
                    predictions.append(signal)
                    confidences.append(0.7)  # Default confidence for LGBM
                    uncertainties.append(0.3)
                    weights.append(self._get_model_weight('lgbm'))
                    model_names.append('lgbm')
                except Exception as e:
                    logger.error(f"LightGBM prediction failed: {e}")
            
            # Transformer prediction
            if 'transformer' in self.models and TORCH_AVAILABLE:
                try:
                    with torch.no_grad():
                        # Pad or truncate to expected dimension
                        if len(features) < 50:
                            x = np.pad(features, (0, 50 - len(features)), 'constant')
                        else:
                            x = features[:50]
                        
                        x = torch.FloatTensor(x).unsqueeze(0)
                        signal, conf, unc = self.models['transformer'](x)
                        predictions.append(float(signal.item()))
                        confidences.append(float(conf.item()))
                        uncertainties.append(float(unc.item()))
                        weights.append(self._get_model_weight('transformer'))
                        model_names.append('transformer')
                except Exception as e:
                    logger.error(f"Transformer prediction failed: {e}")
            
            # TCN prediction
            if 'tcn' in self.models and TORCH_AVAILABLE:
                try:
                    with torch.no_grad():
                        if len(features) < 50:
                            x = np.pad(features, (0, 50 - len(features)), 'constant')
                        else:
                            x = features[:50]
                        
                        x = torch.FloatTensor(x).unsqueeze(0)
                        signal, conf, _ = self.models['tcn'](x)
                        predictions.append(float(signal.item()))
                        confidences.append(float(conf.item()))
                        uncertainties.append(0.2)  # Default uncertainty for TCN
                        weights.append(self._get_model_weight('tcn'))
                        model_names.append('tcn')
                except Exception as e:
                    logger.error(f"TCN prediction failed: {e}")
            
            # ONNX prediction
            if 'onnx' in self.models:
                try:
                    input_name = self.models['onnx'].get_inputs()[0].name
                    # Handle dimension mismatch
                    if len(features) > 20:
                        input_data = features[:20].reshape(1, -1).astype(np.float32)
                    else:
                        input_data = np.pad(features, (0, 20 - len(features)), 'constant').reshape(1, -1).astype(np.float32)
                    
                    outputs = self.models['onnx'].run(None, {input_name: input_data})
                    predictions.append(float(np.tanh(outputs[0][0][0])))
                    confidences.append(0.7)
                    uncertainties.append(0.3)
                    weights.append(self._get_model_weight('onnx'))
                    model_names.append('onnx')
                except Exception as e:
                    logger.error(f"ONNX prediction failed: {e}")
            
            # Advanced ensemble prediction
            if predictions:
                weights = np.array(weights)
                weights_sum = weights.sum()
                if weights_sum > 0:
                    weights = weights / weights_sum  # Normalize weights
                
                # Weighted ensemble
                signal = np.sum(np.array(predictions) * weights)
                
                # Confidence from weighted average and agreement
                weighted_confidence = np.sum(np.array(confidences) * weights)
                agreement = 1.0 - np.std(predictions) if len(predictions) > 1 else 0.7
                confidence = (weighted_confidence * 0.7 + agreement * 0.3)
                
                # Uncertainty from weighted average
                weighted_uncertainty = np.sum(np.array(uncertainties) * weights)
                
                result = {
                    'signal': float(signal),
                    'confidence': float(np.clip(confidence, 0.0, 1.0)),
                    'uncertainty': float(np.clip(weighted_uncertainty, 0.0, 1.0)),
                    'model_count': len(predictions),
                    'model_predictions': {name: float(pred) for name, pred in zip(model_names, predictions)},
                    'model_weights': {name: float(w) for name, w in zip(model_names, weights)}
                }
            else:
                result = self._fallback_prediction(features)
            
            self._update_cache(features_hash, result, current_time)
            return result
                
        except Exception as e:
            logger.error(f"Prediction error: {e}")
            return self._fallback_prediction(features)
    
    def _get_model_weight(self, model_name: str) -> float:
        """Get model weight (dynamic if enabled)"""
        base_weight = self.model_weights.get(model_name, 0.3)
        
        if self.use_dynamic_weights and model_name in self.model_performance:
            perf = self.model_performance[model_name]
            if perf['count'] > 10:
                # Adjust weight based on performance
                accuracy = perf['accuracy']
                performance_multiplier = 0.5 + accuracy  # 0.5 to 1.5 range
                return base_weight * performance_multiplier
        
        return base_weight
    
    def _update_cache(self, key, value, timestamp=None):
        """Update cache with TTL and LRU-like behavior"""
        import time
        if timestamp is None:
            timestamp = time.time()
        
        if len(self.cache) >= self.cache_size:
            # Remove oldest item
            oldest_key = min(self.cache_timestamps.keys(), key=lambda k: self.cache_timestamps[k])
            self.cache.pop(oldest_key, None)
            self.cache_timestamps.pop(oldest_key, None)
        
        self.cache[key] = value
        self.cache_timestamps[key] = timestamp

    def _fallback_prediction(self, features: np.ndarray) -> Dict[str, float]:
        """Advanced fallback prediction using multiple features"""
        try:
            # Use multiple features for better fallback
            momentum = features[1] if len(features) > 1 else 0.0
            trend = features[4] if len(features) > 4 else 0.0
            rsi = features[8] if len(features) > 8 else 0.0  # RSI feature
            
            # Combine signals
            signal = np.tanh(momentum * 3 + trend * 2 + rsi * 1.5)
            confidence = 0.4  # Lower confidence for fallback
            uncertainty = 0.6
            
            return {
                'signal': float(signal),
                'confidence': confidence,
                'uncertainty': uncertainty,
                'model_count': 0,
                'method': 'fallback'
            }
        except Exception as e:
            logger.error(f"Fallback prediction error: {e}")
            return {
                'signal': 0.0,
                'confidence': 0.0,
                'uncertainty': 1.0,
                'model_count': 0,
                'method': 'error'
            }
    
    def save_model(self, model, model_name: str, metadata: Dict = None):
        """Save a trained model"""
        try:
            if model_name == 'lgbm' and LGBM_AVAILABLE:
                path = self.model_dir / "lgbm_model.pkl"
                with open(path, 'wb') as f:
                    pickle.dump(model, f)
                logger.info(f"Model saved: {path}")
            
            elif model_name == 'transformer' and TORCH_AVAILABLE:
                path = self.model_dir / "transformer_small.pt"
                torch.save(model.state_dict(), path)
                logger.info(f"Model saved: {path}")
            
            # Update registry
            self.registry[model_name] = {
                'timestamp': datetime.now().isoformat(),
                'metadata': metadata or {}
            }
            self._save_registry()
            
        except Exception as e:
            logger.error(f"Failed to save model: {e}")
