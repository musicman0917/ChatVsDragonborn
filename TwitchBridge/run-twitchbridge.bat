@echo off
REM Double-click this to launch TwitchBridge without typing commands.
REM Keeps the window open after exit/crash so you can read any error output.
cd /d "%~dp0"
dotnet run --project TwitchBridge.App
pause
