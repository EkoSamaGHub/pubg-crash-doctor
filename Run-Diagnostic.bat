@echo off
REM PUBG Crash Doctor - convenience launcher
REM Runs the read-only scanner even if PowerShell script execution is normally blocked.
title PUBG Crash Doctor
echo Running PUBG Crash Doctor (read-only scan)...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0diagnose.ps1"
echo.
echo Done. If your browser did not open, open index.html in this folder.
pause
