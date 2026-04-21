@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0prepare_public_release.ps1" %*
exit /b %ERRORLEVEL%
