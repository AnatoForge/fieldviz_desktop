@echo off
if /i "%~1"=="test" (
  powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0tests\test_publish.ps1"
  exit /b %errorlevel%
)
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\publish.ps1" %*
exit /b %errorlevel%
