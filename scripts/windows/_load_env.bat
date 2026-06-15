@echo off
rem Shared .env loader for ai-maxx-ide Windows scripts.
rem Call: call "%~dp0_load_env.bat"
rem Sets: REPO_ROOT, SERVER_PORT, SERVER_EXE, TUNNEL_NAME
rem (No setlocal — variables must propagate to the caller.)

if not defined SCRIPT_DIR set "SCRIPT_DIR=%~dp0"
if not defined REPO_ROOT (
    cd /d "%SCRIPT_DIR%..\.."
    set "REPO_ROOT=%CD%"
) else (
    cd /d "%REPO_ROOT%"
)

set "SERVER_PORT=9000"
set "TUNNEL_NAME=ai-maxx-ide"
set "SERVER_EXE="

if exist "%REPO_ROOT%\.env" (
    for /f "usebackq eol=# tokens=1,* delims==" %%A in ("%REPO_ROOT%\.env") do (
        if /I "%%~A"=="SERVER_PORT" set "SERVER_PORT=%%~B"
        if /I "%%~A"=="BIND_PORT" if "%SERVER_PORT%"=="9000" set "SERVER_PORT=%%~B"
        if /I "%%~A"=="TUNNEL_NAME" set "TUNNEL_NAME=%%~B"
    )
)

if exist "%REPO_ROOT%\aimaxx-ide.exe" (
    set "SERVER_EXE=%REPO_ROOT%\aimaxx-ide.exe"
) else if exist "%REPO_ROOT%\server\standalone\dist\aimaxx-ide\aimaxx-ide.exe" (
    set "SERVER_EXE=%REPO_ROOT%\server\standalone\dist\aimaxx-ide\aimaxx-ide.exe"
)
