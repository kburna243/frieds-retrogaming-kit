@echo off
rem Starts the pinball wizard without changing the machine-wide execution policy (Bypass also runs files that
rem still carry a download mark; the wizard then unblocks the kit files). It opens without administrator rights
rem and can restart itself elevated through the core elevation.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0pinball\ui\Wizard.ps1" %*
exit /b %ERRORLEVEL%
