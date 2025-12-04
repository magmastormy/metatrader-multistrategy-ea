@echo off
REM Activate AI Nexus Environment

echo ========================================
echo  Activating AI Nexus Environment
echo ========================================
echo.

call %USERPROFILE%\anaconda3\Scripts\activate.bat ai_nexus

echo Environment: ai_nexus (Python 3.11.14)
echo.
echo Ready! You can now run:
echo   python test_system.py
echo   python main.py
echo   python -m retraining.retrain_loop
echo.

cmd /k
