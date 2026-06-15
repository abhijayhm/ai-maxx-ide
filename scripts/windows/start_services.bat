@echo off
setlocal EnableExtensions

rem Start cloudflared tunnel and ai-maxx-ide server on SERVER_PORT (default 9000).

call "%~dp0_load_env.bat"

set "CF="
where cloudflared >nul 2>&1 && set "CF=cloudflared"
if not defined CF if exist "C:\cloudflared\cloudflared.exe" set "CF=C:\cloudflared\cloudflared.exe"

echo.
echo ai-maxx-ide — start tunnel + server (port %SERVER_PORT%)
echo Repo: %REPO_ROOT%
echo.

if not defined CF (
    echo [tunnel] cloudflared not found. Run setup_cloudflare_tunnel.bat first.
    goto :server
)

call "%~dp0ensure_tunnel_running.bat"

:server
call "%~dp0ensure_server_running.bat"
echo.
echo Health: http://127.0.0.1:%SERVER_PORT%/api/health/
echo Dashboard: http://127.0.0.1:%SERVER_PORT%/dashboard/
echo.
exit /b 0
