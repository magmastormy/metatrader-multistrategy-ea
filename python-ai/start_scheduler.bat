@echo off
REM Start Automated Retraining Scheduler

echo ========================================
echo  AUTOMATED RETRAINING SCHEDULER
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
)

REM Create necessary directories
if not exist "logs" mkdir logs
if not exist "reports" mkdir reports

echo.
echo Starting automated scheduler...
echo This will run continuously and check for triggers.
echo Press Ctrl+C to stop.
echo.

REM Start scheduler
python -m retraining.auto_scheduler

pause
