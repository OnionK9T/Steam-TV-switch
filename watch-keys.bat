@echo off
title steam-tv key watcher
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Watch-Keys.ps1" %*
echo.
echo watcher exited.
pause
