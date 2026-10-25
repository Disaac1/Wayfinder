@echo off
echo =======================================================
echo Compressing client/.export/Build.exe with UPX...
echo =======================================================

if not exist client\.export\Build.exe (
    echo [ERROR] client/.export/Build.exe not found!
    echo Please export your project in Godot first.
    pause
    exit /b 1
)

tools\w64devkit\bin\upx.exe --best client\.export\Build.exe
echo.
echo [DONE] Final compressed size:
dir client\.export\Build.exe | findstr /i "Build.exe"
echo =======================================================
pause
