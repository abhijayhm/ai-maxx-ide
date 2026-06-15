@echo off
setlocal EnableExtensions

rem Watchdog entry: ensure tunnel + server (silent, no console when run via _run_hidden.vbs).

call "%~dp0_load_env.bat"
set "SILENT=1"
call "%~dp0ensure_tunnel_running.bat"
call "%~dp0ensure_server_running.bat"
exit /b 0
