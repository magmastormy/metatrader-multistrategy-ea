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
        """Lightweight transformer for trading"""
        
        def __init__(self, input_dim=20, d_model=64, nhead=4, num_layers=3):
            super().__init__()
            self.input_dim = input_dim
            self.d_model = d_model
            
            self.input_projection = nn.Linear(input_dim, d_model)
            self.positional_encoding = nn.Parameter(torch.randn(500, d_model) * 0.02)
            
            encoder_layer = nn.TransformerEncoderLayer(
                d_model=d_model,
                nhead=nhead,
                dim_feedforward=d_model * 2,
                dropout=0.1,
                batch_first=True
            )
            self.transformer = nn.TransformerEncoder(encoder_layer, num_layers=num_layers)
            
            # Output heads
            self.signal_head = nn.Linear(d_model, 1)
            self.confidence_head = nn.Linear(d_model, 1)
            
        def forward(self, x):
            # x shape: (batch, seq_len, input_dim) or (batch, input_dim)
            if len(x.shape) == 2:
                x = x.unsqueeze(1)  # Add sequence dimension
            
            batch_size, seq_len, _ = x.shape
            
            x = self.input_projection(x)
            x = x + self.positional_encoding[:seq_len, :].unsqueeze(0)
            
            x = self.transformer(x)
            x = x[:, -1, :]  # Take last token
            
            signal = torch.tanh(self.signal_head(x))
            confidence = torch.sigmoid(self.confidence_head(x))
            
            return signal, confidence
else:
    class LightweightTransformer:
        pass


class ModelManager:
    """Manages ML models for trading predictions"""
    
    def __init__(self, model_dir: str = "models"):
        self.model_dir = Path(model_dir)
        self.model_dir.mkdir(exist_ok=True)
        
        self.models = {}
        self.model_weights = {}
        self.registry = self._load_registry()
        
        # Simple cache
        self.cache = {}
        self.cache_size = 1000
        
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
        
        # 2. Load Transformer model
        if TORCH_AVAILABLE:
            transformer_path = self.model_dir / "transformer_small.pt"
            if transformer_path.exists():
                try:
                    self.models['transformer'] = LightweightTransformer()
                    self.models['transformer'].load_state_dict(
                        torch.load(transformer_path, map_location='cpu')
                    )
                    self.models['transformer'].eval()
                    self.model_weights['transformer'] = 0.4
                    logger.info("Transformer model loaded")
                except Exception as e:
                    logger.error(f"Failed to load Transformer: {e}")
        
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
        """Generate ensemble prediction"""
        try:
            # Check cache
            features_hash = hash(features.tobytes())
            if features_hash in self.cache:
                return self.cache[features_hash]
            
            if len(self.models) == 0:
                result = self._fallback_prediction(features)
                self._update_cache(features_hash, result)
                return result
            
            predictions = []
            weights = []
            
            # LightGBM prediction
            if 'lgbm' in self.models:
                try:
                    pred = self.models['lgbm'].predict(features.reshape(1, -1))[0]
                    predictions.append(np.tanh(pred))  # Normalize to [-1, 1]
                    weights.append(self.model_weights['lgbm'])
                except Exception as e:
                    logger.error(f"LightGBM prediction failed: {e}")
            
            # Transformer prediction
            if 'transformer' in self.models and TORCH_AVAILABLE:
                try:
                    with torch.no_grad():
                        x = torch.FloatTensor(features).unsqueeze(0)
                        signal, conf = self.models['transformer'](x)
                        predictions.append(float(signal.item()))
                        weights.append(self.model_weights['transformer'])
                except Exception as e:
                    logger.error(f"Transformer prediction failed: {e}")
            
            # ONNX prediction
            if 'onnx' in self.models:
                try:
                    input_name = self.models['onnx'].get_inputs()[0].name
                    input_data = features.reshape(1, -1).astype(np.float32)
                    outputs = self.models['onnx'].run(None, {input_name: input_data})
                    predictions.append(float(np.tanh(outputs[0][0][0])))
                    weights.append(self.model_weights['onnx'])
                except Exception as e:
                    logger.error(f"ONNX prediction failed: {e}")
            
            # Ensemble prediction
            if predictions:
                weights = np.array(weights)
                weights_sum = weights.sum()
                if weights_sum > 0:
                    weights = weights / weights_sum  # Normalize weights
                
                signal = np.sum(np.array(predictions) * weights)
                confidence = 1.0 - np.std(predictions) if len(predictions) > 1 else 0.7
                
                result = {
                    'signal': float(signal),
                    'confidence': float(np.clip(confidence, 0.0, 1.0)),
                    'uncertainty': float(1.0 - confidence),
                    'model_count': len(predictions)
                }
            else:
                result = self._fallback_prediction(features)
            
            self._update_cache(features_hash, result)
            return result
                
        except Exception as e:
            logger.error(f"Prediction error: {e}")
            return self._fallback_prediction(features)
    
    def _update_cache(self, key, value):
        """Update cache with LRU-like behavior"""
        if len(self.cache) >= self.cache_size:
            # Remove a random item (simplified LRU)
            self.cache.pop(next(iter(self.cache)))
        self.cache[key] = value

    def _fallback_prediction(self, features: np.ndarray) -> Dict[str, float]:
        """Fallback prediction using simple logic"""
        # Use momentum and trend features
        momentum = features[1] if len(features) > 1 else 0.0
        trend = features[4] if len(features) > 4 else 0.0
        
        signal = np.tanh(momentum * 5 + trend * 3)
        confidence = 0.5
        
        return {
            'signal': float(signal),
            'confidence': confidence,
            'uncertainty': 0.5,
            'model_count': 0
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
