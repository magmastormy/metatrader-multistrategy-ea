# 🐍 Conda Environment Setup - AI Nexus

## ✅ Environment Created!

**Name**: `ai_nexus`  
**Python Version**: 3.11.14  
**Status**: Ready for package installation

---

## 🚀 Quick Installation

### Option 1: Automated Setup (Recommended)

Run the installation batch file:

```bash
INSTALL_WITH_CONDA.bat
```

This will:
1. Activate the `ai_nexus` environment
2. Install all required packages
3. Test the installation

### Option 2: Manual Installation

```bash
# Activate environment
conda activate ai_nexus

# Install packages (copy-paste all at once)
pip install numpy pandas scipy pyyaml lightgbm scikit-learn pyzmq optuna schedule pyarrow joblib tqdm coloredlogs

# Install PyTorch (CPU)
pip install torch --index-url https://download.pytorch.org/whl/cpu

# Install ONNX Runtime
pip install onnxruntime
```

---

## 🎯 Usage

### Activate Environment

Every time you want to use the AI system:

```bash
conda activate ai_nexus
```

### Run System

```bash
# Test the system
python test_system.py

# Start AI trading system
python main.py

# Run retraining pipeline
python -m retraining.retrain_loop
```

### Deactivate Environment

```bash
conda deactivate
```

---

## 📋 Your Existing Conda Environments

Based on what I found:

1. **base** - Default Anaconda environment
2. **kejian** - Your existing environment
3. **teriaki** - Your existing environment  
4. **ai_nexus** ⭐ - Newly created for AI trading system

---

## ✨ Why ai_nexus?

- **Python 3.11.14** - Perfect compatibility with all packages
- **ONNX Runtime** - Works (not available on Python 3.14)
- **PyTorch** - Full support
- **All packages** - No version conflicts

---

## 🔧 Troubleshooting

### "conda: command not found"

```bash
# Use full path
%USERPROFILE%\anaconda3\Scripts\conda.exe activate ai_nexus
```

### Check Python Version

```bash
conda activate ai_nexus
python --version
# Should show: Python 3.11.14
```

### List Installed Packages

```bash
conda activate ai_nexus
pip list
```

---

## 🎓 Quick Reference

### Conda Commands

```bash
# List environments
conda env list

# Activate environment
conda activate ai_nexus

# Deactivate
conda deactivate

# Delete environment (if needed)
conda env remove -n ai_nexus

# Export environment
conda env export > environment.yml

# Create from file
conda env create -f environment.yml
```

---

## ⚡ Integration with Batch Scripts

All existing batch scripts will work after activating the environment:

```bash
# Activate first
conda activate ai_nexus

# Then run any script
start_ai_system.bat
run_retraining.bat
test_system.py
```

Or modify scripts to auto-activate by adding at the top:

```batch
call %USERPROFILE%\anaconda3\Scripts\activate.bat ai_nexus
```

---

## 🎉 Next Steps

1. ✅ Run `INSTALL_WITH_CONDA.bat`
2. ✅ Test with `python test_system.py`
3. ✅ Start trading with `python main.py`

---

**Environment ready! Your AI trading system now has a compatible Python setup. 🚀**
