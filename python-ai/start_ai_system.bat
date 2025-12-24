@echo off
setlocal enabledelayedexpansion

echo ========================================
echo   AI Trading System Startup Script
echo ========================================
echo.

REM Move into python-ai directory
pushd "%~dp0..\python-ai"

REM Activate hariaki conda environment
call conda activate hariaki

REM Validate activation
if errorlevel 1 (
    echo ERROR: Failed to activate hariaki environment.
    echo Ensure conda is installed and the environment exists.
    popd
    pause
    exit /b 1
)

echo Environment activated: hariaki
echo Python version:
python --version
echo.

REM Prompt optional bridge selection
set "BRIDGE_MODE=socket"
if not "%1"=="" (
    set "BRIDGE_MODE=%1"
) else (
    echo Available bridge modes: auto, zmq, socket, file
    set /p BRIDGE_MODE=Enter bridge mode [socket]: 
    if "%BRIDGE_MODE%"=="" set "BRIDGE_MODE=socket"
)

echo Selected bridge: %BRIDGE_MODE%
echo.

echo Starting AI Trading System...
echo Logs -> python-ai\logs\ai_runtime.log
echo Press Ctrl+C to stop the AI server.
echo ========================================

python main.py --bridge %BRIDGE_MODE%

echo.
set RUN_TEST=N
echo Run communication test harness now? [Y/N]
set /p RUN_TEST=Choice [N]: 
if "%RUN_TEST%"=="" set "RUN_TEST=N"

if /I "%RUN_TEST%"=="Y" (
    echo.
    echo Running test harness (socket)...
    python test_harness.py --type socket
)

popd
echo.
echo Shutdown complete. Review logs if needed.
pause
endlocal