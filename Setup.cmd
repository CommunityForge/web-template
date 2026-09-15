@echo off
rem Double-clickable launcher for the Windows setup wizard; see README.md.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Setup.ps1"
pause
