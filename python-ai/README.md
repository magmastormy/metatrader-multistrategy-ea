# 🔥 Modern AI Trading System - Python Subsystem

**Production-ready, modular, scalable AI engine for MetaTrader 5 trading**

## 🎯 Overview

This is a complete rebuild of the Python AI subsystem with:
- ✅ Clean modular architecture
- ✅ Lightweight ML models (LightGBM + Transformer)
- ✅ Multiple communication bridges (ZeroMQ, Socket, File)
- ✅ Production-ready error handling
- ✅ Comprehensive analytics and logging
- ✅ Risk management engine
- ✅ Model registry and versioning

## 📁 Project Structure

```
python-ai/
├── config/                 # Configuration files
│   ├── model_config.yaml   # Model parameters
│   ├── features.yaml       # Feature engineering config
│   └── bridge.yaml         # Bridge settings
│
├── core/                   # Core AI modules
│   ├── data_loader.py      # Market data loading
│   ├── feature_engineer.py # Feature extraction
│   ├── model_manager.py    # Model loading/inference
│   ├── signal_generator.py # Trading signal generation
│   ├── risk_engine.py      # Risk management
│   └── analytics.py        # Performance tracking
│
├── bridge/                 # MT5 ↔ Python communication
│   ├── zmq_server.py       # ZeroMQ bridge (primary)
│   ├── socket_server.py    # TCP socket bridge (fallback)
│   ├── file_pipe.py        # File-based bridge (last resort)
│   └── message_protocol.py # Message format
│
├── models/                 # ML models
│   ├── lgbm_model.pkl      # LightGBM model
│   ├── transformer_small.pt# Transformer model
│   ├── model_registry.json # Model metadata
│   └── training_scripts/   # Training code
│       ├── train_lgbm.py
│       └── train_transformer.py
│
├── utils/                  # Utility functions
│   ├── time_utils.py       # Time-based features
│   ├── data_utils.py       # Data processing
│   ├── validation.py       # Input validation
│   └── math_utils.py       # Math utilities
│
├── logs/                   # System logs
├── main.py                 # Main orchestrator
└── requirements.txt        # Dependencies
```

## 🚀 Quick Start

### 1. Install Dependencies

```bash
# Create virtual environment
python -m venv ai_trading_env
ai_trading_env\Scripts\activate

# Install requirements
pip install -r requirements.txt
```

### 2. Train Models (Optional)

```bash
# Train LightGBM model
cd models/training_scripts
python train_lgbm.py

# Train Transformer model
python train_transformer.py
```

### 3. Start AI System

```bash
# Auto-select best bridge
python main.py

# Force specific bridge
python main.py --bridge zmq
python main.py --bridge socket
python main.py --bridge file
```

## 🔌 Bridge Modes

### Primary: ZeroMQ (Recommended)
- **Speed**: Ultra-fast (<1ms latency)
- **Reliability**: Production-proven
- **Setup**: Requires `pyzmq` package
- **Port**: 5555 (default)

### Secondary: TCP Socket
- **Speed**: Fast (~2-5ms latency)
- **Reliability**: Good
- **Setup**: No extra dependencies
- **Port**: 8888 (default)

### Fallback: File-Based
- **Speed**: Slower (~100ms latency)
- **Reliability**: Always works
- **Setup**: No extra dependencies
- **Directories**: `./signals`, `./requests`

## 📊 Features

### Feature Engineering (20 features)
1. **Price Features**: Returns, momentum, volatility
2. **Technical Indicators**: RSI, SMA, trend strength
3. **Market Structure**: Price position, support/resistance
4. **Time Features**: Hour/day encoding, session type
5. **Volume Features**: Volume ratio, liquidity

### ML Models

#### LightGBM (Primary - 60% weight)
- Fast gradient boosting
- Excellent for tabular data
- Low latency inference (<1ms)

#### Transformer (Secondary - 40% weight)
- Sequence modeling
- Pattern recognition
- Slightly slower but more accurate

### Signal Generation
- **BUY**: Signal > 0.7, Confidence > 0.6
- **SELL**: Signal < -0.7, Confidence > 0.6
- **NONE**: Otherwise or risk too high

### Risk Management
- Dynamic position sizing
- Volatility-based SL/TP
- Market regime detection
- Time-based risk adjustments

## 📈 Analytics

System tracks:
- Prediction accuracy
- Signal statistics
- Trade performance
- Risk metrics
- Model performance

Access analytics:
```python
from core.analytics import Analytics
analytics = Analytics()
report = analytics.generate_report()
print(report)
```

## 🔧 Configuration

Edit `config/*.yaml` files to customize:

**model_config.yaml**: Model parameters, thresholds
**features.yaml**: Feature engineering settings
**bridge.yaml**: Communication settings

## 📝 API Reference

### Message Protocol

#### Signal Request
```json
{
  "type": "signal_request",
  "data": {
    "symbol": "XAUUSD",
    "market_data": {
      "open": [1900.0, 1901.0, ...],
      "high": [1902.0, 1903.0, ...],
      "low": [1899.0, 1900.0, ...],
      "close": [1901.0, 1902.0, ...],
      "volume": [100, 150, ...]
    }
  }
}
```

#### Signal Response
```json
{
  "type": "signal_response",
  "success": true,
  "data": {
    "symbol": "XAUUSD",
    "action": "BUY",
    "signal_value": 0.85,
    "confidence": 0.78,
    "stop_loss": 1895.50,
    "take_profit": 1910.00,
    "risk_score": 0.35,
    "risk_level": "MODERATE",
    "reason": "Strong buy signal: 0.85, confidence: 0.78",
    "timestamp": "2024-12-03T01:30:00"
  }
}
```

## 🛠️ Development

### Adding New Features
1. Edit `core/feature_engineer.py`
2. Update `config/features.yaml`
3. Retrain models

### Adding New Models
1. Create training script in `models/training_scripts/`
2. Update `core/model_manager.py`
3. Add model weights in config

### Custom Bridge
1. Implement in `bridge/`
2. Follow `MessageProtocol` standard
3. Register in `main.py`

## 🐛 Troubleshooting

### ZeroMQ Not Working
```bash
pip install pyzmq
```

### Models Not Loading
```bash
# Train models first
cd models/training_scripts
python train_lgbm.py
python train_transformer.py
```

### Port Already in Use
Edit `config/bridge.yaml` to change ports

## 📊 Performance Benchmarks

- **Inference time**: <5ms (full pipeline)
- **Model prediction**: <1ms (LGBM), ~3ms (Transformer)
- **Feature extraction**: <1ms
- **Communication overhead**: <1ms (ZMQ), ~2ms (Socket)

## 🔐 Production Checklist

- [x] Error handling
- [x] Logging system
- [x] Input validation
- [x] Risk management
- [x] Analytics tracking
- [x] Multiple bridge fallbacks
- [x] Model versioning
- [x] Configuration management
- [x] Clean architecture
- [x] Documentation

## 📄 License

Part of the MT5 AI Trading System

## 🤝 Contributing

This is a production system. Test thoroughly before modifications.

---

**Built with ❤️ for high-frequency trading**
