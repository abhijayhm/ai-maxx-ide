@echo off
setlocal EnableExtensions

rem Start cloudflared tunnel (and optionally Django) for ai-maxx-ide.

set "SCRIPT_DIR=%~dp0"
set "REPO_ROOT=%SCRIPT_DIR%..\.."
cd /d "%REPO_ROOT%"

set "PY="
where py >nul 2>&1 && set "PY=py -3"
if not defined PY where python >nul 2>&1 && set "PY=python"

set "CF="
where cloudflared >nul 2>&1 && set "CF=cloudflared"
if not defined CF if exist "C:\cloudflared\cloudflared.exe" set "CF=C:\cloudflared\cloudflared.exe"

set "TUNNEL_NAME=ai-maxx-ide"
if exist "%REPO_ROOT%\.env" (
    for /f "usebackq tokens=1,* delims==" %%A in (`findstr /B /I "TUNNEL_NAME=" "%REPO_ROOT%\.env"`) do set "TUNNEL_NAME=%%B"
)

echo.
echo ai-maxx-ide — start tunnel + server
echo.

if not defined CF (
    echo [tunnel] cloudflared not found. Run setup_cloudflare_tunnel.bat first.
    goto :server
)

for /f "tokens=*" %%L in ('"%CF%" tunnel list 2^>nul ^| findstr /I "%TUNNEL_NAME%"') do set "TUNNEL_LINE=%%L"
echo %TUNNEL_LINE% | findstr /I "bom maa sin" >nul 2>&1
if not errorlevel 1 (
    echo [tunnel] %TUNNEL_NAME% already has edge connections.
) else (
    echo [tunnel] Starting cloudflared tunnel run %TUNNEL_NAME% ...
    start "ai-maxx-ide tunnel" /MIN "%CF%" tunnel run %TUNNEL_NAME%
)

:server
echo [api] Start Django ASGI manually in another terminal:
echo   cd server
echo   %PY% -m uvicorn config.asgi:application --host 127.0.0.1 --port 8000
echo.
echo Health check: https://YOUR_SERVER_DOMAIN/api/health/
echo.
pause
