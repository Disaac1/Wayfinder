@echo off
setlocal enabledelayedexpansion

echo =======================================================
echo Godot UI-Only Export Template Local Builder
echo =======================================================

where scons >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo [ERROR] SCons is not installed or not in PATH.
    echo Run: pip install scons
    pause
    exit /b 1
)

where cl >nul 2>&1
if %ERRORLEVEL% neq 0 (
    where gcc >nul 2>&1
    if !ERRORLEVEL! neq 0 (
        echo [ERROR] No C++ compiler detected (MSVC 'cl' or MinGW 'gcc').
        echo Please run this from the Visual Studio Developer Command Prompt or install MinGW.
        pause
        exit /b 1
    )
)

if not exist godot-src (
    echo [*] Cloning Godot 4.7 source...
    git clone --depth 1 --branch 4.7-stable https://github.com/godotengine/godot.git godot-src
)

echo [*] Copying build profile...
copy /Y client\profiles\ui_only.build godot-src\ui_only.build

cd godot-src
echo [*] Compiling stripped UI-only release template...
scons platform=windows target=template_release arch=x86_64 build_profile=ui_only.build disable_3d=yes optimize=size use_lto=yes deprecated=no vrs=no openxr=no -j%NUMBER_OF_PROCESSORS%

if %ERRORLEVEL% neq 0 (
    echo [ERROR] Compilation failed.
    cd ..
    pause
    exit /b 1
)

cd ..
if not exist client\custom_templates mkdir client\custom_templates
copy /Y godot-src\bin\godot.windows.template_release.x86_64.exe client\custom_templates\windows_release_x86_64.exe

echo.
echo [SUCCESS] Custom export template saved to:
echo   client\custom_templates\windows_release_x86_64.exe
echo.
echo Now in Godot, set 'Custom Template -> Release' to:
echo   res://custom_templates/windows_release_x86_64.exe
echo =======================================================
pause
