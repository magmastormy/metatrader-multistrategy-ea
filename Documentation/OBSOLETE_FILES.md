# 🗑️ Obsolete Files - To Be Removed

## Old System Files (Replace with New System)

### Core Old Files - OBSOLETE
These files have been completely replaced by the new modular system:

1. **`python_ai.py`** (64KB) → REPLACED
   - Old monolithic AI system
   - Replaced by modular `core/` package
   - Contains redundant code and poor structure

2. **`python_ai_server.py`** (13KB) → PARTIALLY OBSOLETE
   - Old FastAPI server
   - Bridge functionality moved to `bridge/` package
   - Can keep for reference but not needed

3. **`IntelligentSignalSelector.py`** (24KB) → OBSOLETE
   - Old signal selection logic
   - Replaced by `core/signal_generator.py`
   - Less sophisticated than new system

### Test/Validation Files - REVIEW
4. **`test_ai_bridge.py`** → Replace with `test_system.py`
5. **`validate_setup.py`** → Redundant (new system has built-in validation)
6. **`verify_server.py`** → Redundant

### Training Scripts - OBSOLETE
7. **`train_models.py`** → REPLACED
   - Old training script
   - Replaced by `models/training_scripts/train_lgbm.py` and `train_transformer.py`

8. **`simple_onnx_exporter.py`** → KEEP (may be useful for model export)

### Documentation - REVIEW
9. **`AI_INTEGRATION_COMPLETE_GUIDE.md`** → OBSOLETE
   - Old documentation
   - Replaced by `README.md`, `INSTALLATION.md`, `ARCHITECTURE.md`

10. **`QUICK_REFERENCE.txt`** → OBSOLETE
11. **`QUICK_START_GUIDE.txt`** → OBSOLETE
12. **`userWritten_ProjectUpgrade.md`** → ARCHIVE (keep for reference)

### MQL5 Files - REVIEW
13. **`NextGenBrainTrainer.mq5`** → Should be in main MT5 directory, not python-ai
14. **`NextGenBrainTrainer.ex5`** → Should be in main MT5 directory

### Batch/Startup Scripts - REPLACE
15. **`START_AI_SERVER.bat`** → REPLACED by `start_ai_system.bat`
16. **`DEPLOY_DOCKER.bat`** → Can keep if Docker needed

### Docker Files - REVIEW
17. **`Dockerfile`** → Update for new system
18. **`docker-compose.yml`** → Update for new system
19. **`docker-compose.production.yml`** → Update for new system

### Include Directory - EMPTY
20. **`Include/`** → Empty directory, remove

### Virtual Environment - DON'T DELETE
21. **`ai_trading_env/`** → KEEP (virtual environment)

### Logs - DON'T DELETE
22. **`logs/`** → KEEP (runtime logs)
23. **`ai_server.log`** → Old log file, can delete

### Models - REVIEW
24. **`models/trading_model.onnx`** → Keep if trained
25. **`models/transformer_model.onnx`** → Keep if trained

## Cleanup Commands

### Safe Cleanup (Remove obsolete files)
```bash
# Create backup first
mkdir ../python-ai-backup
xcopy /E /I .\ ..\python-ai-backup\

# Remove obsolete Python files
del python_ai.py
del python_ai_server.py
del IntelligentSignalSelector.py
del test_ai_bridge.py
del validate_setup.py
del verify_server.py
del train_models.py

# Remove old documentation
del AI_INTEGRATION_COMPLETE_GUIDE.md
del QUICK_REFERENCE.txt
del QUICK_START_GUIDE.txt

# Remove old startup
del START_AI_SERVER.bat

# Remove empty directories
rmdir /S /Q Include

# Remove old log
del ai_server.log
```

### Archive (Move to backup folder)
```bash
mkdir archive
move userWritten_ProjectUpgrade.md archive\
move simple_onnx_exporter.py archive\
move NextGenBrainTrainer.mq5 archive\
move NextGenBrainTrainer.ex5 archive\
```

## What to Keep

### Essential Files
- `main.py` - New orchestrator ✅
- `test_system.py` - New test script ✅
- `start_ai_system.bat` - New startup script ✅
- `requirements.txt` - Updated dependencies ✅
- `README.md` - New documentation ✅
- `INSTALLATION.md` - Install guide ✅
- `ARCHITECTURE.md` - System design ✅

### Directories to Keep
- `config/` - New configuration ✅
- `core/` - New core modules ✅
- `bridge/` - New communication layer ✅
- `models/` - ML models ✅
- `utils/` - Utility functions ✅
- `logs/` - Runtime logs ✅
- `ai_trading_env/` - Virtual environment ✅

## Migration Notes

### For Users of Old System

1. **Backup everything first**
2. **Train new models**: Run `train_lgbm.py` and `train_transformer.py`
3. **Update MT5 EA**: Point to new bridge endpoints
4. **Test thoroughly**: Run `test_system.py` before live trading
5. **Monitor logs**: Check `logs/ai_runtime.log` for issues

### API Changes

Old system used FastAPI REST endpoints:
- `POST /predict` → Now handled by bridge messages

New system uses multiple bridges:
- ZeroMQ (primary)
- Socket (fallback)
- File-based (last resort)

### Configuration Changes

Old: Hardcoded parameters
New: YAML configuration files in `config/`

## Automated Cleanup Script

See `cleanup_old_files.bat` for safe automated cleanup.

---

**⚠️ WARNING: Always backup before deleting files!**
