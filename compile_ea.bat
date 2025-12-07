@echo off
REM Enhanced Compilation Script - Syncs and Compiles All Files
setlocal enabledelayedexpansion

REM ============================
REM 1. SYNC FILES TO MT5 FIRST
REM ============================
echo.
echo =====================================================
echo    SYNCING PROJECT TO METATRADER 5
echo =====================================================
echo.

powershell -ExecutionPolicy Bypass -File "%~dp0sync_to_mt5.ps1"
if errorlevel 1 (
    echo.
    echo ERROR: Failed to sync files to MetaTrader 5
    pause
    exit /b 1
)

echo.
echo =====================================================
echo    COMPILATION STARTED
echo =====================================================
echo.

REM --- 2. Detect MetaEditor ---
set "METAEDITOR="
if exist "c:\Program Files\MetaTrader 5\MetaEditor64.exe" set "METAEDITOR=c:\Program Files\MetaTrader 5\MetaEditor64.exe"

if "%METAEDITOR%"=="" (
    echo ERROR: MetaEditor not found
    pause
    exit /b 1
)

REM --- 3. Set Paths ---
set "MT5_DIR=C:\Program Files\MetaTrader 5\MQL5\Experts\metatrader-multistrategy-ea"
set "EA_FILE=%MT5_DIR%\MultiStrategyAutonomousEA.mq5"
set "TRAINER_FILE=%MT5_DIR%\AIModules\NextGenBrainTrainer.mq5"
set "LOG_FILE=%~dp0compile_full.log"

REM --- 4. Compile Main EA ---
echo.
echo [1/2] Compiling Main EA: MultiStrategyAutonomousEA.mq5
echo ----------------------------------------------------
"%METAEDITOR%" /compile:"%EA_FILE%" /log:"%LOG_FILE%"

if exist "%LOG_FILE%" (
    type "%LOG_FILE%"
    echo.
) else (
    echo WARNING: No log file created for main EA
)

REM --- 5. Compile Trainer ---
echo.
echo [2/2] Compiling AI Trainer: NextGenBrainTrainer.mq5
echo ----------------------------------------------------
set "TRAINER_LOG=%~dp0compile_trainer.log"
"%METAEDITOR%" /compile:"%TRAINER_FILE%" /log:"%TRAINER_LOG%"

if exist "%TRAINER_LOG%" (
    type "%TRAINER_LOG%"
    echo.
) else (
    echo WARNING: No log file created for trainer
)

REM --- 6. Check Results ---
set "TOTAL_ERRORS=0"
set "TOTAL_WARNINGS=0"

if exist "%LOG_FILE%" (
    for /f "tokens=1" %%a in ('findstr /C:"error(s)" "%LOG_FILE%"') do (
        if not "%%a"=="0" set /a TOTAL_ERRORS+=%%a
    )
)

if exist "%TRAINER_LOG%" (
    for /f "tokens=1" %%a in ('findstr /C:"error(s)" "%TRAINER_LOG%"') do (
        if not "%%a"=="0" set /a TOTAL_ERRORS+=%%a
    )
)

echo.
echo =====================================================
echo    COMPILATION SUMMARY
echo =====================================================
echo Total Errors: %TOTAL_ERRORS%
echo.

if %TOTAL_ERRORS% EQU 0 (
    echo ✅ SUCCESS: All files compiled with 0 errors!
    echo.
    echo Your EA is ready to use in MetaTrader 5.
) else (
    echo ❌ FAILED: Please fix the errors above and try again.
    echo.
    echo TIP: Check the file paths and make sure all dependencies exist.
)

echo =====================================================
echo.

REM Keep window open to read results
pause
exit /b %TOTAL_ERRORS%