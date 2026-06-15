@echo off
setlocal EnableExtensions

rem Register logon task: start tunnel + server (may prompt for admin).

call "%~dp0_load_env.bat"

set "TASK_NAME=ai-maxx-ide-startup"
set "RUN_CMD=%REPO_ROOT%\scripts\windows\start_services.bat"

net session >nul 2>&1
if errorlevel 1 (
    echo Re-launching elevated to create scheduled task...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b 0
)

echo Creating startup task: %TASK_NAME%
schtasks /Create /TN "%TASK_NAME%" /TR "\"%RUN_CMD%\"" /SC ONLOGON /RL LIMITED /F
if errorlevel 1 (
    echo ERROR: schtasks create failed.
    pause
    exit /b 1
)

echo.
echo Startup task installed. Runs at user logon:
echo   %RUN_CMD%
echo.
pause
exit /b 0
