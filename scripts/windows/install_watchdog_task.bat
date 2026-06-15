@echo off
setlocal EnableExtensions

rem Register watchdog: every minute, ensure tunnel + server (no visible windows).

call "%~dp0_load_env.bat"

set "TASK_NAME=ai-maxx-ide-watchdog"
set "VBS=%SCRIPT_DIR%_run_hidden.vbs"
set "RUN_BAT=%REPO_ROOT%\scripts\windows\ensure_services_running.bat"
set "TASK_CMD=wscript.exe \"%VBS%\" \"%RUN_BAT%\""

net session >nul 2>&1
if errorlevel 1 (
    echo Re-launching elevated to create scheduled task...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b 0
)

echo Creating watchdog task: %TASK_NAME% (every 1 minute, hidden)
schtasks /Create /TN "%TASK_NAME%" /TR "%TASK_CMD%" /SC MINUTE /MO 1 /RL LIMITED /F
if errorlevel 1 (
    echo ERROR: schtasks create failed.
    pause
    exit /b 1
)

echo.
echo Watchdog task installed (runs silently in background).
echo   Tunnel: cloudflared tunnel run %TUNNEL_NAME%
echo   Server: http://127.0.0.1:%SERVER_PORT%/api/health/
echo   Log:    %REPO_ROOT%\data\watchdog.log
echo.
pause
exit /b 0
