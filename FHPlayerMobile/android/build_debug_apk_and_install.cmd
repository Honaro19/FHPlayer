@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build_debug_apk_and_install.ps1" %*
exit /b %errorlevel%
