@echo off
setlocal EnableExtensions

rem Cloudflare Tunnel bootstrap for ai-maxx-ide (Windows) — server URL only.
rem Double-click or run from cmd: setup_cloudflare_tunnel.bat

set "SCRIPT_DIR=%~dp0"
cd /d "%SCRIPT_DIR%"

rem cloudflared download + machine PATH may require elevation.
net session >nul 2>&1
if errorlevel 1 (
    echo.
    echo Administrator rights may be required ^(cloudflared install + service^).
    echo Re-launching elevated...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b 0
)

set "PY="
where py >nul 2>&1 && set "PY=py -3"
if not defined PY where python >nul 2>&1 && set "PY=python"
if not defined PY (
    echo.
    echo ERROR: Python 3 not found.
    echo Install from https://www.python.org/downloads/ and enable "Add python.exe to PATH".
    pause
    exit /b 1
)

echo.
echo ai-maxx-ide — Cloudflare Tunnel setup ^(server only^)
echo Script dir: %SCRIPT_DIR%
echo Repo root:  %SCRIPT_DIR%..\..
echo Python:     %PY%
echo.

if not exist "%SCRIPT_DIR%..\..\sample.env" (
    echo ERROR: sample.env not found at repo root.
    pause
    exit /b 1
)
if not exist "%SCRIPT_DIR%..\..\.env" (
    echo.
    echo No .env found. Copy sample.env to .env and set your domain:
    echo   copy "%SCRIPT_DIR%..\..\sample.env" "%SCRIPT_DIR%..\..\.env"
    echo.
    echo Required: SERVER_DOMAIN, TUNNEL_NAME, SERVER_PORT
    pause
    exit /b 1
)

echo Using: %SCRIPT_DIR%..\..\.env
echo.
%PY% "%SCRIPT_DIR%setup_cloudflare_tunnel.py"
set "ERR=%ERRORLEVEL%"

echo.
if not "%ERR%"=="0" (
    echo Setup failed with exit code %ERR%.
    pause
    exit /b %ERR%
)

echo Setup finished.
pause
exit /b 0
