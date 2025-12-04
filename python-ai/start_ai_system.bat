@echo off
REM Start AI Trading System with automatic bridge selection

echo ========================================
echo  AI TRADING SYSTEM LAUNCHER
echo ========================================
echo.

REM Activate conda environment (ai_nexus)
if exist "%USERPROFILE%\anaconda3\Scripts\activate.bat" (
    echo Activating conda environment: ai_nexus...
    call %USERPROFILE%\anaconda3\Scripts\activate.bat ai_nexus
) else if exist "ai_trading_env\Scripts\activate.bat" (
    echo Activating virtual environment...
    call ai_trading_env\Scripts\activate.bat
) else (
    echo Warning: No environment found
    echo Using system Python...
)

REM Create logs directory
if not exist "logs" mkdir logs

REM Start the system
echo Starting AI system...
python main.py --bridge auto

pause
