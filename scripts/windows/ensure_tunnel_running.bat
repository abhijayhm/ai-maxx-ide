@echo off
setlocal EnableExtensions

rem Start cloudflared tunnel if %TUNNEL_NAME% has no active edge connections.

call "%~dp0_load_env.bat"

if not defined TUNNEL_NAME set "TUNNEL_NAME=ai-maxx-ide"

set "CF="
where cloudflared >nul 2>&1 && set "CF=cloudflared"
if not defined CF if exist "C:\cloudflared\cloudflared.exe" set "CF=C:\cloudflared\cloudflared.exe"

if not defined CF (
    if not defined SILENT echo [watchdog] cloudflared not found — skip tunnel.
    exit /b 0
)

"%CF%" tunnel list 2>nul | findstr /I "%TUNNEL_NAME%" | findstr /I "bom maa sin" >nul 2>&1
if not errorlevel 1 (
    if not defined SILENT echo [watchdog] Tunnel %TUNNEL_NAME% OK.
    exit /b 0
)

if defined SILENT (
    if not exist "%REPO_ROOT%\data" mkdir "%REPO_ROOT%\data" >nul 2>&1
    >>"%REPO_ROOT%\data\watchdog.log" echo [%date% %time%] Tunnel down — starting %TUNNEL_NAME%
    wscript.exe "%~dp0_run_hidden.vbs" "%CF%" tunnel run %TUNNEL_NAME%
) else (
    echo [watchdog] Tunnel %TUNNEL_NAME% down — starting...
    start "ai-maxx-ide tunnel" /MIN "%CF%" tunnel run %TUNNEL_NAME%
)
exit /b 0
