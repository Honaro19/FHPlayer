@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build_release_artifacts.ps1" %*
exit /b %errorlevel%
