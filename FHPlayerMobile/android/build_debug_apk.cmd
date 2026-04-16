@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build_debug_apk.ps1" %*
exit /b %errorlevel%
