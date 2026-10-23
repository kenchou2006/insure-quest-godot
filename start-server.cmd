@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\start-server.ps1" %*
if errorlevel 1 (
  echo.
  echo Server startup failed. See the message above.
  pause
)
