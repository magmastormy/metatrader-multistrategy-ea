@echo off
REM 🛡️ BEAST MODE: Fixed path handling for MetaEditor

REM --- 1. Auto-detect MetaEditor location on D: drive ---
set "METAEDITOR="
if exist "c:\Program Files\MetaTrader 5\MetaEditor64.exe" set "METAEDITOR=c:\Program Files\MetaTrader 5\MetaEditor64.exe"

if "%METAEDITOR%"=="" (
    echo 🚨 ERROR: MetaEditor not found in standard D: locations
    pause
    exit /b 1
)

REM --- 2. Set Project Paths ---
set "PROJECT_DIR=%~dp0"
set "EA_FILE=%PROJECT_DIR%MultiStrategyAutonomousEA.mq5"
set "LOG_FILE=%PROJECT_DIR%compile.log"
set "FILTERED_LOG=%PROJECT_DIR%compile_filtered.log"

echo 🛡️ [BEAST-COMPILE] Using MetaEditor: %METAEDITOR%
echo 🛡️ [BEAST-COMPILE] Project Dir: %PROJECT_DIR%
echo 🛡️ [BEAST-COMPILE] Compiling: %EA_FILE%
echo.

REM --- 3. Compile the EA ---
"%METAEDITOR%" /compile:"%EA_FILE%" /log:"%LOG_FILE%"

REM --- 4. Check if compilation was successful ---
set "COMPILE_SUCCESSFUL=false"
if exist "%LOG_FILE%" (
    findstr /C:"0 error(s)" "%LOG_FILE%" >nul
    if not errorlevel 1 (
        set "COMPILE_SUCCESSFUL=true"
    )
)

REM --- 5. Display Results ---
if "%COMPILE_SUCCESSFUL%"=="true" (
    echo ✅ [COMPILE-SUCCESS] Compilation completed with 0 errors.
    type "%LOG_FILE%"
) else (
    echo.
    echo 📋 [COMPILE-LOG] Compilation failed or had warnings. Displaying log:
    echo ----------------------------------------------------
    
    if exist "%LOG_FILE%" (
        type "%LOG_FILE%"
    ) else (
        echo No compilation log file was created. Check if MetaEditor path is correct.
    )
    echo ----------------------------------------------------
)

REM --- 6. Cleanup ---
REM if exist "%LOG_FILE%" del "%LOG_FILE%"
REM if exist "%FILTERED_LOG%" del "%FILTERED_LOG%"

echo.
if "%COMPILE_SUCCESSFUL%"=="true" (
    echo 🎉 All done! Your EA is ready.
) else (
    echo 💥 Please fix the errors above and try again.
)

REM Auto-close after a short delay for readability
timeout /t 3 >nul
exit /b 0