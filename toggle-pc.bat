@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Toggle-SteamTV.ps1" -ForcePc %*
