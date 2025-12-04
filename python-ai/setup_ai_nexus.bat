@echo off
REM Setup AI Nexus Environment and Install Dependencies

echo ========================================
echo  AI NEXUS - Environment Setup
echo ========================================
echo.

REM Activate conda environment
echo Activating ai_nexus environment...
call %USERPROFILE%\anaconda3\Scripts\activate.bat ai_nexus

echo.
echo Installing Python packages...
echo.

REM Install core packages
pip install numpy pandas scipy pyyaml

REM Install ML packages
pip install lightgbm scikit-learn

REM Install PyTorch (CPU version for Python 3.11)
pip install torch --index-url https://download.pytorch.org/whl/cpu

REM Install ONNX Runtime
pip install onnxruntime

REM Install communication packages
pip install pyzmq

REM Install retraining system packages
pip install optuna schedule pyarrow

REM Install utilities
pip install joblib tqdm coloredlogs

echo.
echo ========================================
echo  Installation Complete!
echo ========================================
echo.
echo Environment: ai_nexus (Python 3.11.14)
echo.
echo To activate this environment:
echo   conda activate ai_nexus
echo.
echo To test the system:
echo   python test_system.py
echo.
echo To start the AI system:
echo   python main.py
echo.

pause
