@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install_debug_apk.ps1" -LaunchApp %*
exit /b %errorlevel%
