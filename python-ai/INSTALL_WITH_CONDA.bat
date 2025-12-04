@echo off
REM Complete Installation for AI Nexus Environment

echo ========================================
echo  AI NEXUS - Complete Setup
echo ========================================
echo.
echo Environment: ai_nexus (Python 3.11.14)
echo.

REM Initialize conda for this shell
call %USERPROFILE%\anaconda3\Scripts\activate.bat

REM Activate ai_nexus environment
call conda activate ai_nexus

echo.
echo Current Python version:
python --version
echo.

echo Installing core packages...
pip install numpy pandas scipy pyyaml

echo.
echo Installing ML packages...
pip install lightgbm scikit-learn

echo.
echo Installing PyTorch (CPU version)...
pip install torch --index-url https://download.pytorch.org/whl/cpu

echo.
echo Installing ONNX Runtime...
pip install onnxruntime

echo.
echo Installing communication packages...
pip install pyzmq

echo.
echo Installing retraining system packages...
pip install optuna schedule pyarrow

echo.
echo Installing utilities...
pip install joblib tqdm coloredlogs

echo.
echo ========================================
echo  Installation Complete!
echo ========================================
echo.
echo To use this environment, run:
echo   conda activate ai_nexus
echo.
echo Then you can run:
echo   python test_system.py
echo   python main.py
echo   python -m retraining.retrain_loop
echo.

pause
