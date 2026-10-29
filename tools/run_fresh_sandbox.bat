@echo off
setlocal
echo ==============================================================
echo   Wayfinder Interactive Fresh Install Sandbox Launcher
echo ==============================================================
set "SCRIPT_DIR=%~dp0"
set "SANDBOX_DIR=%SCRIPT_DIR%sandbox_userdata"

if not exist "%SANDBOX_DIR%" mkdir "%SANDBOX_DIR%"
set "APPDATA=%SANDBOX_DIR%"

echo [Sandbox] User data isolated to: %SANDBOX_DIR%
echo [Sandbox] Launching Wayfinder GUI client in clean sandbox mode...

start "" "%SCRIPT_DIR%client\godot.exe" --path "%SCRIPT_DIR%client"

echo [Sandbox] Client started in fresh sandbox!
endlocal
