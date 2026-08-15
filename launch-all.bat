@echo off
REM Launches Skyrim (via SKSE) and TwitchBridge together in separate windows.
REM Edit SKYRIM_DIR below to match your own Skyrim Special Edition install
REM location if it differs.

set SKYRIM_DIR=F:\SteamLibrary\steamapps\common\Skyrim Special Edition
set REPO_DIR=%~dp0

start "Skyrim (SKSE)" /D "%SKYRIM_DIR%" "%SKYRIM_DIR%\skse64_loader.exe"
start "TwitchBridge" "%REPO_DIR%TwitchBridge\run-twitchbridge.bat"

echo Launched Skyrim and TwitchBridge in separate windows.
