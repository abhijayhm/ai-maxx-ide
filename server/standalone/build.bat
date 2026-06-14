@echo off
setlocal EnableExtensions
cd /d "%~dp0.."

set "PY="
if exist "..\env\Scripts\python.exe" set "PY=..\env\Scripts\python.exe"
if not defined PY where py >nul 2>&1 && set "PY=py -3"
if not defined PY where python >nul 2>&1 && set "PY=python"
if not defined PY (
  echo ERROR: Python not found.
  exit /b 1
)

echo Installing packaging deps...
"%PY%" -m pip install -r requirements.txt -r requirements-packaging.txt
if errorlevel 1 exit /b 1

echo Building aimaxx-ide.exe ...
taskkill /IM aimaxx-ide.exe /F >nul 2>&1
timeout /t 2 /nobreak >nul
"%PY%" -m PyInstaller standalone\aimaxx-ide.spec --noconfirm --distpath standalone\dist --workpath standalone\build
if errorlevel 1 exit /b 1

echo.
echo Build complete:
echo   standalone\dist\aimaxx-ide\aimaxx-ide.exe
echo Copy .env beside the exe before running.
exit /b 0
