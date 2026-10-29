@echo off
setlocal enabledelayedexpansion

echo =======================================================
echo          Lodestone Windows Installer Builder
echo =======================================================

cd /d "%~dp0\.."

REM Verify export files exist
if not exist "client\.export\Build.exe" (
    echo [ERROR] client\.export\Build.exe not found!
    echo Please export your project using Godot Preset 'Windows Desktop' first.
    pause
    exit /b 1
)

if not exist "client\.export\Build.pck" (
    echo [ERROR] client\.export\Build.pck not found!
    echo Ensure preset option 'embed_pck' is set to false so Build.pck is generated.
    pause
    exit /b 1
)

REM Find Inno Setup Compiler (ISCC.exe)
set "ISCC_PATH="
where iscc.exe >nul 2>nul
if %errorlevel% equ 0 (
    set "ISCC_PATH=iscc.exe"
) else if exist "%LocalAppData%\Programs\Inno Setup 6\ISCC.exe" (
    set "ISCC_PATH=%LocalAppData%\Programs\Inno Setup 6\ISCC.exe"
) else if exist "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" (
    set "ISCC_PATH=C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
) else if exist "C:\Program Files\Inno Setup 6\ISCC.exe" (
    set "ISCC_PATH=C:\Program Files\Inno Setup 6\ISCC.exe"
)

if "%ISCC_PATH%"=="" (
    echo [ERROR] Inno Setup 6 compiler (ISCC.exe) was not found!
    echo.
    echo To install Inno Setup, run in PowerShell:
    echo    winget install JRSoftware.InnoSetup
    echo.
    echo Or download from: https://jrsoftware.org/isinfo.php
    pause
    exit /b 1
)

REM Note: UPX packing is intentionally skipped to avoid heuristic false positives in Windows Smart App Control and SmartScreen.
echo Compiling Inno Setup installer...
if not exist "dist" mkdir dist

"%ISCC_PATH%" "installer\lodestone.iss"
if %errorlevel% neq 0 (
    echo [ERROR] Inno Setup compilation failed!
    pause
    exit /b 1
)

echo.
echo =======================================================
echo [SUCCESS] Installer generated in dist\ directory!
echo =======================================================
dir dist\*.exe
pause
