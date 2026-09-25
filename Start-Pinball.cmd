@echo off
rem Starts the pinball wizard without changing the machine-wide execution policy (Bypass also runs files that
rem still carry a download mark; the wizard then unblocks the kit files). It opens without administrator rights
rem and can restart itself elevated through the core elevation. Full path: a powershell.exe in the current
rem folder or earlier in PATH must never win.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0pinball\ui\Wizard.ps1" %*
exit /b %ERRORLEVEL%
