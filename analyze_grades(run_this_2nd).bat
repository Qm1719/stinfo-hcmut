@echo off
setlocal enabledelayedexpansion
REM Analyze Grades - Batch Wrapper
REM Analyzes the grades JSON file and shows statistics

REM Set UTF-8 code page for proper Vietnamese character display
chcp 65001 >nul

REM Clear screen and show welcome
cls
echo ========================================
echo   Grade Analysis Tool
echo ========================================
echo.

REM Check if input file is provided as argument
if not "%1"=="" (
    REM Argument provided, use it
    set "INPUT_FILE=%1"
    goto :file_selected
)

REM No argument, try default files in script directory
pushd "%~dp0" >nul 2>&1

REM First try all_grades.json
if exist "all_grades.json" (
    set "INPUT_FILE=all_grades.json"
    popd
    goto :file_selected
)

REM Then try all_grades_deduped.json
if exist "all_grades_deduped.json" (
    set "INPUT_FILE=all_grades_deduped.json"
    popd
    goto :file_selected
)

REM Return to original directory
popd

REM Neither default exists, ask user
echo Default files not found.
echo.
set "INPUT_FILE="
set /p "INPUT_FILE=Enter path to grades JSON file: "

REM Check if user entered anything
if "!INPUT_FILE!"=="" (
    echo.
    echo [ERROR] No file specified!
    pause
    exit /b 1
)

REM Remove quotes if user added them and trim whitespace
set "INPUT_FILE=!INPUT_FILE:"=!"
set "INPUT_FILE=!INPUT_FILE: =!"

REM Check if the entered file exists (try current directory first, then script directory)
if not exist "!INPUT_FILE!" (
    REM Try in script directory
    if exist "%~dp0!INPUT_FILE!" (
        set "INPUT_FILE=%~dp0!INPUT_FILE!"
    )
)

:file_selected

REM Check if file exists
if not exist "!INPUT_FILE!" (
    if not exist "%INPUT_FILE%" (
        echo.
        echo [ERROR] File not found: '!INPUT_FILE!%INPUT_FILE%'
        echo.
        echo Please check:
        echo   1. The file name is correct
        echo   2. The file is in the same directory as this script
        echo   3. Or provide the full path to the file
        echo.
        pause
        exit /b 1
    )
)

REM Use the correct variable
if not "!INPUT_FILE!"=="" (
    set "FINAL_FILE=!INPUT_FILE!"
) else (
    set "FINAL_FILE=%INPUT_FILE%"
)

echo Analyzing grades from: !FINAL_FILE!
echo.

REM Run the PowerShell analysis script
set "SCRIPT_DIR=%~dp0"
powershell -ExecutionPolicy Bypass -File "%SCRIPT_DIR%analyze_grades.ps1" -InputFile "!FINAL_FILE!"

if errorlevel 1 (
    echo.
    echo [ERROR] Analysis failed!
    pause
    exit /b 1
)

echo.
echo ========================================
echo Analysis complete! Press any key to exit...
pause >nul

endlocal
