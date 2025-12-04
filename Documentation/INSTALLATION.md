# 📦 Installation Guide - AI Trading System

## Prerequisites

- Python 3.10 or higher
- Windows 10/11 (for MT5 integration)
- 4GB RAM minimum
- MetaTrader 5 installed (optional for standalone testing)

## Step-by-Step Installation

### 1. Create Virtual Environment

```bash
# Navigate to python-ai directory
cd python-ai

# Create virtual environment
python -m venv ai_trading_env

# Activate (Windows)
ai_trading_env\Scripts\activate

# Activate (Linux/Mac)
source ai_trading_env/bin/activate
```

### 2. Install Dependencies

```bash
# Install core dependencies
pip install --upgrade pip
pip install -r requirements.txt
```

**Note**: If you encounter issues with PyTorch on Windows:
```bash
# Install CPU version only
pip install torch --index-url https://download.pytorch.org/whl/cpu
```

### 3. Train Initial Models

```bash
# Navigate to training scripts
cd models/training_scripts

# Train LightGBM model (fast, ~30 seconds)
python train_lgbm.py

# Train Transformer model (slower, ~5 minutes)
python train_transformer.py

# Return to main directory
cd ../..
```

### 4. Test System

```bash
# Run system tests
python test_system.py
```

You should see:
```
✅ ALL TESTS PASSED - SYSTEM READY
```

### 5. Start AI System

**Option A: Using batch script (Windows)**
```bash
start_ai_system.bat
```

**Option B: Manual start**
```bash
python main.py --bridge auto
```

**Option C: Specific bridge**
```bash
# ZeroMQ (fastest)
python main.py --bridge zmq

# Socket (fallback)
python main.py --bridge socket

# File-based (last resort)
python main.py --bridge file
```

## Verification

### Check System Status

The system should display:
```
🔥 AI TRADING SYSTEM ONLINE
Bridge Mode: ZMQ
Models Loaded: 2
```

### Test Signal Generation

Create a test request file:
```json
// requests/request_test.json
{
  "type": "signal_request",
  "data": {
    "symbol": "XAUUSD",
    "market_data": {
      "close": [1900, 1901, 1902, 1903, 1904]
    }
  }
}
```

Check for response in `signals/` directory.

## Troubleshooting

### Issue: "Module not found"
```bash
# Reinstall requirements
pip install -r requirements.txt --force-reinstall
```

### Issue: "Models not loaded"
```bash
# Train models
cd models/training_scripts
python train_lgbm.py
python train_transformer.py
```

### Issue: "ZeroMQ not available"
```bash
# Install ZeroMQ
pip install pyzmq
```

### Issue: "Port already in use"
Edit `config/bridge.yaml`:
```yaml
primary:
  port: 5556  # Change from 5555
```

### Issue: "Permission denied on logs/"
```bash
# Create logs directory manually
mkdir logs
```

## Minimal Installation (No ML Models)

If you want to run without models (fallback mode):

```bash
# Install only core dependencies
pip install numpy pandas pyyaml pyzmq

# Start system (will use rule-based logic)
python main.py
```

## Docker Installation (Advanced)

```bash
# Build Docker image
docker build -t ai-trading-system .

# Run container
docker run -p 5555:5555 ai-trading-system
```

## Integration with MT5

### Method 1: ZeroMQ (Recommended)

1. Install ZeroMQ MQL5 library in MT5
2. Copy bridge script to MT5 Scripts folder
3. Configure MT5 EA to connect to `tcp://127.0.0.1:5555`

### Method 2: File-Based

1. Set MT5 EA to write requests to `python-ai/requests/`
2. EA reads responses from `python-ai/signals/`
3. No additional setup needed

## Performance Tuning

### For Low-Latency Trading
```yaml
# config/bridge.yaml
primary:
  timeout_ms: 1000  # Reduce from 5000
```

### For High-Throughput
Edit `config/model_config.yaml`:
```yaml
inference:
  cache_enabled: true
  cache_ttl_seconds: 60
```

## Upgrade Path

To upgrade from old system:
1. Backup old `python-ai/` folder
2. Install new system in new directory
3. Copy trained models if compatible
4. Update MT5 EA connection settings

## Next Steps

- Read [README.md](README.md) for usage guide
- Check [ARCHITECTURE.md](ARCHITECTURE.md) for system design
- Review configuration files in `config/`
- Test with historical data before live trading

## Support

- Check logs in `logs/` directory
- Run `python test_system.py` for diagnostics
- Review error messages carefully

---

**Installation complete! Ready for production trading.**
