@echo off
REM Manual Retraining Script

echo ========================================
echo  MODEL RETRAINING PIPELINE
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
if not exist "data_lake" mkdir data_lake
if not exist "data_lake\raw" mkdir data_lake\raw
if not exist "data_lake\processed" mkdir data_lake\processed
if not exist "data_lake\training_sets" mkdir data_lake\training_sets

echo.
echo Running retraining pipeline...
echo.

REM Run retraining
python -m retraining.retrain_loop

echo.
echo ========================================
echo  RETRAINING COMPLETE
echo ========================================
echo.
echo Check reports\ directory for results
echo.

pause
