@echo off
setlocal enabledelayedexpansion

title Wayfinder Game File Encryptor / Decryptor

:: Check Python
python --version >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] Python is not installed or not in PATH.
    pause
    exit /b 1
)

:: If arguments were passed, handle drag-and-drop or CLI invocation
if not "%~1"=="" (
    set "INPUT_FILE=%~1"
    goto PROMPT_KEY
)

:MENU
cls
echo =======================================================
echo        Wayfinder Game File Encryption Utility
echo =======================================================
echo.
echo Drag and drop a file onto this window/bat or enter path:
set /p "INPUT_FILE=Input File: "
:: Strip quotes
set INPUT_FILE=%INPUT_FILE:"=%

if "%INPUT_FILE%"=="" (
    echo No file specified. Exiting...
    pause
    exit /b 0
)

:PROMPT_KEY
if not exist "%INPUT_FILE%" (
    echo [ERROR] File not found: "%INPUT_FILE%"
    pause
    exit /b 1
)

echo.
echo Target File: %INPUT_FILE%
echo.

:: Detect default action based on extension
set "IS_ENC=0"
if /i "%~x1"==".enc" set "IS_ENC=1"
if /i "%INPUT_FILE:~-4%"==".enc" set "IS_ENC=1"

if "%IS_ENC%"=="1" (
    echo File ends with .enc - Decryption mode suggested.
    set /p "MODE=Mode ([D]ecrypt / [E]ncrypt) [default: D]: "
    if /i "!MODE!"=="E" (set "ACTION=encrypt") else (set "ACTION=decrypt")
) else (
    echo File does not end with .enc - Encryption mode suggested.
    set /p "MODE=Mode ([E]ncrypt / [D]ecrypt) [default: E]: "
    if /i "!MODE!"=="D" (set "ACTION=decrypt") else (set "ACTION=encrypt")
)

echo.
set /p "KEY=Enter Passphrase / Key: "
if "%KEY%"=="" (
    echo [ERROR] Key cannot be empty!
    pause
    exit /b 1
)

:: Compute default output filename
if "%ACTION%"=="encrypt" (
    set "OUTPUT_FILE=%INPUT_FILE%.enc"
) else (
    if /i "%INPUT_FILE:~-4%"==".enc" (
        set "OUTPUT_FILE=%INPUT_FILE:~0,-4%"
    ) else (
        set "OUTPUT_FILE=%INPUT_FILE%.dec"
    )
)

echo.
echo Output File: %OUTPUT_FILE%
set /p "CUSTOM_OUT=Press Enter to use this output or enter custom path: "
if not "%CUSTOM_OUT%"=="" (
    set "OUTPUT_FILE=%CUSTOM_OUT:"=%"
)

echo.
echo Running %ACTION%...
set "SCRIPT_PATH=%~dp0encrypt_game_file.py"

if "%ACTION%"=="decrypt" (
    python "%SCRIPT_PATH%" --decrypt -i "%INPUT_FILE%" -o "%OUTPUT_FILE%" -k "%KEY%"
) else (
    python "%SCRIPT_PATH%" -i "%INPUT_FILE%" -o "%OUTPUT_FILE%" -k "%KEY%"
)

echo.
if %errorlevel% equ 0 (
    echo [SUCCESS] Operation completed successfully!
) else (
    echo [FAILED] An error occurred during %ACTION%.
)

echo.
pause
