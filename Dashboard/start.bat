@echo off
echo ============================================
echo   EA Command Center Dashboard
echo ============================================
echo.

:: Check Python
where python >nul 2>nul
if %ERRORLEVEL% neq 0 (
    echo ERROR: Python not found. Please install Python 3.10+
    pause
    exit /b 1
)

:: Check Node/pnpm
where pnpm >nul 2>nul
if %ERRORLEVEL% neq 0 (
    echo ERROR: pnpm not found. Install with: npm install -g pnpm
    pause
    exit /b 1
)

:: Install Python dependencies
echo [1/4] Installing Python dependencies...
cd /d "%~dp0server"
pip install -r requirements.txt -q

:: Install frontend dependencies
echo [2/4] Installing frontend dependencies...
cd /d "%~dp0client"
call pnpm install --frozen-lockfile 2>nul || call pnpm install

:: Start Python server in background
echo [3/4] Starting dashboard server on port 8765...
cd /d "%~dp0server"
start "EA Dashboard Server" python -m uvicorn Dashboard.server.dashboard_server:app --host 0.0.0.0 --port 8765

:: Wait for server to be ready
timeout /t 2 /nobreak >nul

:: Start frontend dev server
echo [4/4] Starting frontend dev server on port 5173...
cd /d "%~dp0client"
call pnpm dev

echo.
echo Dashboard stopped.
pause
