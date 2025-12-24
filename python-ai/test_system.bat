@echo off
echo ========================================
echo   AI Trading System Test Script
echo ========================================
echo.

REM Activate conda environment
call conda activate hariaki

REM Check if activation was successful
if errorlevel 1 (
    echo ERROR: Failed to activate hariaki environment
    pause
    exit /b 1
)

echo Testing AI Trading System...
echo.

REM Test socket bridge
echo Testing Socket Bridge (127.0.0.1:8888)...
python test_harness.py --type socket
echo.

echo ========================================
echo Test completed! Check results above.
echo ========================================
pause