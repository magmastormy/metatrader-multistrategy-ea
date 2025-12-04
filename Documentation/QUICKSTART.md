# ⚡ QUICKSTART - AI Trading System

**Get up and running in 5 minutes!**

## Prerequisites ✓

- Python 3.10+
- Windows 10/11

## Step 1: Setup (2 minutes)

```bash
# Create virtual environment
python -m venv ai_trading_env

# Activate it
ai_trading_env\Scripts\activate

# Install dependencies
pip install -r requirements.txt
```

## Step 2: Train Models (3 minutes)

```bash
# Navigate to training
cd models\training_scripts

# Train LightGBM (30 seconds)
python train_lgbm.py

# Train Transformer (2 minutes)
python train_transformer.py

# Go back
cd ..\..
```

## Step 3: Test (30 seconds)

```bash
python test_system.py
```

Expected output:
```
✅ ALL TESTS PASSED - SYSTEM READY
```

## Step 4: Start System (Done!)

```bash
# Option A: Batch file (easiest)
start_ai_system.bat

# Option B: Command line
python main.py
```

System should show:
```
🔥 AI TRADING SYSTEM ONLINE
Bridge Mode: ZMQ
Models Loaded: 2
```

## Verify It's Working

### Send Test Request

Create file `requests/test_request.json`:
```json
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

Check for response in `signals/` directory within 1 second.

## Common Issues

### "Module not found"
```bash
pip install -r requirements.txt
```

### "Models not loaded"
```bash
cd models\training_scripts
python train_lgbm.py
python train_transformer.py
```

### "Port in use"
```bash
# Use file-based bridge instead
python main.py --bridge file
```

## What's Next?

1. **Read Full Docs**: Check `README.md` for detailed usage
2. **Configure**: Edit files in `config/` folder
3. **Integrate MT5**: Update your EA to connect
4. **Monitor**: Check `logs/ai_runtime.log`

## Key Commands

```bash
# Test system
python test_system.py

# Start (auto bridge)
python main.py

# Start (specific bridge)
python main.py --bridge zmq
python main.py --bridge socket
python main.py --bridge file

# Train models
cd models\training_scripts && python train_lgbm.py
```

## File Structure (What You Need to Know)

```
python-ai/
├── config/          # ← Edit these to configure
├── core/            # ← AI logic (don't edit unless you know)
├── bridge/          # ← Communication (usually don't touch)
├── models/          # ← Trained models stored here
├── logs/            # ← Check these for issues
├── main.py          # ← This starts the system
└── test_system.py   # ← Run this to test
```

## Success Checklist

- [x] Dependencies installed
- [x] Models trained
- [x] Tests passed
- [x] System started
- [ ] MT5 EA connected (your next step)

## Need Help?

- **Installation Issues**: See `INSTALLATION.md`
- **System Design**: See `ARCHITECTURE.md`
- **Migration**: See `MIGRATION_GUIDE.md`
- **Cleanup**: Run `cleanup_old_files.bat`

---

**That's it! System ready in 5 minutes. Now connect your MT5 EA and start trading! 🚀**
