@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0release_check.ps1" %*
exit /b %errorlevel%
