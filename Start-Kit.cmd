@echo off
rem Starts the kit without changing the machine-wide execution policy. Full path: a powershell.exe in the
rem current folder or earlier in PATH must never win.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0core\Start-KitDemo.ps1" %*
exit /b %ERRORLEVEL%
