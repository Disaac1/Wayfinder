@echo off
setlocal enabledelayedexpansion
title Wayfinder Release & Deployment Pipeline

echo =======================================================
echo          Wayfinder Release & Deployment Tool
echo =======================================================
echo.

cd /d "%~dp0"

REM 1. Check Python
where python >nul 2>nul
if %errorlevel% neq 0 (
    echo [ERROR] Python is not installed or not in PATH!
    pause
    exit /b 1
)

REM 2. Check and auto-install Inno Setup if missing
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
    echo [INFO] Inno Setup 6 not found on your system.
    echo Installing Inno Setup automatically via winget...
    echo.
    winget install --id JRSoftware.InnoSetup -e --accept-source-agreements --accept-package-agreements
    if exist "%LocalAppData%\Programs\Inno Setup 6\ISCC.exe" (
        set "ISCC_PATH=%LocalAppData%\Programs\Inno Setup 6\ISCC.exe"
        echo [OK] Inno Setup installed successfully!
    ) else if exist "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" (
        set "ISCC_PATH=C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
        echo [OK] Inno Setup installed successfully!
    )
    echo.
)

REM 3. Determine current version and compute default next version
set "CURR_VER=1.0.0"
set "NEXT_VER=1.0.1"

for /f "tokens=1,2" %%A in ('python tools\package_release.py --get-next-version 2^>nul') do (
    set "CURR_VER=%%A"
    set "NEXT_VER=%%B"
)

echo Current Published Version:  v%CURR_VER%
echo Suggested Next Version:     v%NEXT_VER%
echo.

REM 4. Interactive user prompts
set "REL_VER="
set /p "REL_VER=Enter release version [Default: %NEXT_VER%]: "
if "!REL_VER!"=="" set "REL_VER=%NEXT_VER%"

set "REL_NOTES="
set /p "REL_NOTES=Enter changelog summary [Default: Maintenance and stability update]: "
if "!REL_NOTES!"=="" set "REL_NOTES=Maintenance and stability update"

set "DO_EXPORT="
set /p "DO_EXPORT=Export fresh Godot binaries? (Y/n) [Default: Y]: "
if "!DO_EXPORT!"=="" set "DO_EXPORT=Y"

echo.
echo =======================================================
echo Deploying Wayfinder v!REL_VER!
echo Notes: "!REL_NOTES!"
echo =======================================================
echo.

REM 5. Execute deployment pipeline
set "SKIP_FLAG="
if /i "!DO_EXPORT!"=="n" set "SKIP_FLAG=--skip-export"

python tools\package_release.py --version "!REL_VER!" --notes "!REL_NOTES!" !SKIP_FLAG!
if %errorlevel% neq 0 (
    echo.
    echo [ERROR] Deployment failed! Check the output above.
    pause
    exit /b 1
)

echo.
echo =======================================================
echo            WAYFINDER DEPLOYMENT SUCCESSFUL!
echo =======================================================
echo  • Version:        v!REL_VER!
echo  • Notes:          !REL_NOTES!
echo  • Auto-Update:    Live for all connected clients
echo  • Website:        https://wayfinder.disaac1.com
echo  • Installer:      backend\public\downloads\Wayfinder_Setup.exe
echo  • Portable ZIP:   backend\public\downloads\Wayfinder_Windows.zip
echo =======================================================
echo.

pause
