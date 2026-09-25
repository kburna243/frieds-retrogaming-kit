@echo off
rem Starts the kit without changing the machine-wide execution policy.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0core\Start-KitDemo.ps1" %*
exit /b %ERRORLEVEL%
