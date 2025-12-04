@echo off
REM Cleanup script for obsolete files
REM Creates backup before deletion

echo ========================================
echo  CLEANUP OLD FILES - AI TRADING SYSTEM
echo ========================================
echo.
echo This script will:
echo  1. Create backup of current system
echo  2. Remove obsolete files
echo  3. Archive potentially useful files
echo.
echo Press Ctrl+C to cancel, or
pause

REM Create backup
echo.
echo Creating backup...
set BACKUP_DIR=..\python-ai-backup-%date:~-4,4%%date:~-10,2%%date:~-7,2%
if not exist "%BACKUP_DIR%" mkdir "%BACKUP_DIR%"
xcopy /E /I /Q .\ "%BACKUP_DIR%\"
echo Backup created at: %BACKUP_DIR%
echo.

REM Create archive directory
if not exist "archive" mkdir archive

REM Archive potentially useful files
echo Archiving useful files...
if exist "userWritten_ProjectUpgrade.md" move userWritten_ProjectUpgrade.md archive\
if exist "simple_onnx_exporter.py" move simple_onnx_exporter.py archive\
if exist "NextGenBrainTrainer.mq5" move NextGenBrainTrainer.mq5 archive\
if exist "NextGenBrainTrainer.ex5" move NextGenBrainTrainer.ex5 archive\
if exist "Dockerfile" move Dockerfile archive\
if exist "docker-compose.yml" move docker-compose.yml archive\
if exist "docker-compose.production.yml" move docker-compose.production.yml archive\
if exist "DEPLOY_DOCKER.bat" move DEPLOY_DOCKER.bat archive\

REM Remove obsolete Python files
echo.
echo Removing obsolete Python files...
if exist "python_ai.py" (
    del /F /Q python_ai.py
    echo - Removed python_ai.py
)
if exist "python_ai_server.py" (
    del /F /Q python_ai_server.py
    echo - Removed python_ai_server.py
)
if exist "IntelligentSignalSelector.py" (
    del /F /Q IntelligentSignalSelector.py
    echo - Removed IntelligentSignalSelector.py
)
if exist "test_ai_bridge.py" (
    del /F /Q test_ai_bridge.py
    echo - Removed test_ai_bridge.py
)
if exist "validate_setup.py" (
    del /F /Q validate_setup.py
    echo - Removed validate_setup.py
)
if exist "verify_server.py" (
    del /F /Q verify_server.py
    echo - Removed verify_server.py
)
if exist "train_models.py" (
    del /F /Q train_models.py
    echo - Removed train_models.py
)

REM Remove old documentation
echo.
echo Removing obsolete documentation...
if exist "AI_INTEGRATION_COMPLETE_GUIDE.md" (
    del /F /Q AI_INTEGRATION_COMPLETE_GUIDE.md
    echo - Removed AI_INTEGRATION_COMPLETE_GUIDE.md
)
if exist "QUICK_REFERENCE.txt" (
    del /F /Q QUICK_REFERENCE.txt
    echo - Removed QUICK_REFERENCE.txt
)
if exist "QUICK_START_GUIDE.txt" (
    del /F /Q QUICK_START_GUIDE.txt
    echo - Removed QUICK_START_GUIDE.txt
)

REM Remove old startup
if exist "START_AI_SERVER.bat" (
    del /F /Q START_AI_SERVER.bat
    echo - Removed START_AI_SERVER.bat
)

REM Remove empty directories
if exist "Include" (
    rmdir /S /Q Include
    echo - Removed Include directory
)

REM Remove old log
if exist "ai_server.log" (
    del /F /Q ai_server.log
    echo - Removed ai_server.log
)

REM Clean pycache
if exist "__pycache__" (
    rmdir /S /Q __pycache__
    echo - Cleaned __pycache__
)

echo.
echo ========================================
echo  CLEANUP COMPLETE
echo ========================================
echo.
echo Backup location: %BACKUP_DIR%
echo Archived files: archive\
echo.
echo Old system files removed.
echo New system is ready to use.
echo.
echo Next steps:
echo  1. Test system: python test_system.py
echo  2. Start system: start_ai_system.bat
echo.
pause
