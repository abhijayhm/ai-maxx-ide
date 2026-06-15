@echo off
setlocal EnableExtensions

rem Start packaged server (or dev runserver) if health check fails.

call "%~dp0_load_env.bat"

where curl >nul 2>&1
if errorlevel 1 (
    echo ERROR: curl not found. Install curl or add it to PATH.
    exit /b 1
)

curl -sf "http://127.0.0.1:%SERVER_PORT%/api/health/" >nul 2>&1
if not errorlevel 1 (
    if not defined SILENT echo [watchdog] Server OK on port %SERVER_PORT%.
    exit /b 0
)

if defined SILENT (
    if not exist "%REPO_ROOT%\data" mkdir "%REPO_ROOT%\data" >nul 2>&1
    >>"%REPO_ROOT%\data\watchdog.log" echo [%date% %time%] Server down on port %SERVER_PORT% — starting
) else (
    echo [watchdog] Server down on port %SERVER_PORT% — starting...
)

if defined SERVER_EXE (
    if not defined SILENT echo [watchdog] Launching %SERVER_EXE%
    if defined SILENT (
        wscript.exe "%SCRIPTS_WIN%\_run_hidden.vbs" "%SERVER_EXE%"
    ) else (
        start "ai-maxx-ide server" /MIN "%SERVER_EXE%"
    )
    exit /b 0
)

set "PY="
where py >nul 2>&1 && set "PY=py -3"
if not defined PY where python >nul 2>&1 && set "PY=python"
if not defined PY (
    if defined SILENT (
        >>"%REPO_ROOT%\data\watchdog.log" echo [%date% %time%] ERROR: No aimaxx-ide.exe and Python not found.
    ) else (
        echo ERROR: No aimaxx-ide.exe and Python not found.
    )
    exit /b 1
)

if not defined SILENT echo [watchdog] Dev fallback: manage.py runserver
if defined SILENT (
    set "DEV_BAT=%TEMP%\ai-maxx-ide-watchdog-server.bat"
    > "%DEV_BAT%" echo @echo off
    >>"%DEV_BAT%" echo cd /d "%REPO_ROOT%\server"
    >>"%DEV_BAT%" echo %PY% manage.py runserver 127.0.0.1:%SERVER_PORT%
    wscript.exe "%SCRIPTS_WIN%\_run_hidden.vbs" "%DEV_BAT%"
) else (
    start "ai-maxx-ide server" /MIN cmd /c "cd /d \"%REPO_ROOT%\server\" && %PY% manage.py runserver 127.0.0.1:%SERVER_PORT%"
)
exit /b 0
