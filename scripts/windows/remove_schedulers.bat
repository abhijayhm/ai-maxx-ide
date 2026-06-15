@echo off
setlocal EnableExtensions

rem Remove scheduled tasks and stop the packaged server.

call "%~dp0_load_env.bat"

echo Removing scheduled tasks...
schtasks /Delete /TN "ai-maxx-ide-startup" /F >nul 2>&1
schtasks /Delete /TN "ai-maxx-ide-watchdog" /F >nul 2>&1

echo Waiting before stopping server (dashboard can close)...
timeout /t 3 /nobreak >nul

echo Stopping ai-maxx-ide server...
taskkill /IM aimaxx-ide.exe /F >nul 2>&1

echo.
echo Schedulers removed and server stopped.
echo You can close this window.
exit /b 0
