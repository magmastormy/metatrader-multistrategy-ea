@echo off
REM ==========================================
REM Solo Operator Deploy Script
REM Compiles, validates, deploys to live VPS
REM ==========================================

setlocal enabledelayedexpansion

set EA_NAME=MultiStrategyAutonomousEA
set METAEDITOR="C:\Program Files\MetaTrader 5\metaeditor64.exe"
set MQL5_ROOT=%APPDATA%\MetaQuotes\Terminal\Common
set VPS_HOST=your-vps-ip
set VPS_USER=trader
set VPS_PATH=C:\Users\%VPS_USER%\AppData\Roaming\MetaQuotes\Terminal\Common

REM Colors for output
set GREEN=\033[92m
set RED=\033[91m
set YELLOW=\033[93m
set CYAN=\033[96m
set RESET=\033[0m

echo.
echo ==========================================
echo [DEPLOY] MultiStrategyAutonomousEA Deploy Script
echo ==========================================
echo.

REM Check if MetaEditor exists
if not exist %METAEDITOR% (
    echo [ERROR] MetaEditor not found at %METAEDITOR%
    echo Please update METAEDITOR path in this script
    pause
    exit /b 1
)

REM Step 1: Compile
echo [STEP 1/5] Compiling %EA_NAME%.mq5...
%METAEDITOR% /compile:%EA_NAME%.mq5 /log:compile.log /inc:"Core" /inc:"Strategies" /inc:"AIModules" /inc:"Interfaces" /inc:"Utilities"

if errorlevel 1 (
    echo [ERROR] Compilation failed!
    echo.
    type compile.log
    echo.
    pause
    exit /b 1
)

echo [OK] Compilation successful

REM Step 2: Check for critical warnings in compile log
echo.
echo [STEP 2/5] Checking compile warnings...
findstr /I /C:"warning" compile.log > nul
if not errorlevel 1 (
    echo [WARNING] Compilation has warnings:
    findstr /I /C:"warning" compile.log
) else (
    echo [OK] No warnings
)

REM Step 3: Validate inputs using Python script
echo.
echo [STEP 3/5] Validating input parameters...
python validate_inputs.py %EA_NAME%.set
if errorlevel 1 (
    echo [ERROR] Input validation failed!
    pause
    exit /b 1
)
echo [OK] Input validation passed

REM Step 4: Copy to VPS
echo.
echo [STEP 4/5] Deploying to VPS (%VPS_HOST%)...
echo [INFO] Ensure SSH keys are configured for passwordless access

REM Copy EA
scp %EA_NAME%.ex5 %VPS_USER%@%VPS_HOST%:%VPS_PATH%\MQL5\Experts\%EA_NAME%.ex5
if errorlevel 1 (
    echo [ERROR] Failed to copy EA to VPS
    pause
    exit /b 1
)

REM Copy config files
scp Config\*.json %VPS_USER%@%VPS_HOST%:%VPS_PATH%\MQL5\Files\Config\ 2>nul
if errorlevel 1 (
    echo [WARNING] Config folder not found or empty, skipping config copy
)

echo [OK] Files copied to VPS

REM Step 5: Restart EA on VPS
echo.
echo [STEP 5/5] Restarting EA on VPS...
ssh %VPS_USER%@%VPS_HOST% "powershell -Command \"& { Stop-Process -Name 'terminal64' -Force -ErrorAction SilentlyContinue; Start-Sleep 2; Start-Process 'C:\Program Files\MetaTrader 5\terminal64.exe' -ArgumentList '/portable' }\""

if errorlevel 1 (
    echo [WARNING] VPS restart command failed - manual restart may be needed
) else (
    echo [OK] VPS restart initiated
)

echo.
echo ==========================================
echo [DEPLOY] Deployment complete!
echo ==========================================
echo.
echo Next steps:
echo 1. Check VPS logs: tail -f %VPS_PATH%\MQL5\Logs\MultiStrategyEA_structured_*.jsonl
echo 2. Verify EA attached to chart on VPS
echo 3. Monitor risk dashboard on chart
echo.
pause