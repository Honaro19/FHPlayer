@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0test_rule_engine.ps1" %*
exit /b %errorlevel%
