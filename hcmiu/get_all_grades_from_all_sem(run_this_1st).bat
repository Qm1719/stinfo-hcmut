@echo off
REM HCMIU Grades Fetcher - Fetches all grades from xemdiemthi page
REM Uses PowerShell (built into Windows)
REM Just double-click to run!

REM Set UTF-8 code page for proper Vietnamese character display
chcp 65001 >nul
REM Also set PowerShell to use UTF-8
set PYTHONIOENCODING=utf-8

REM Clear screen and show welcome
cls
echo ========================================
echo   HCMIU All Grades Fetcher
echo ========================================
echo.

REM Check if user wants to use auto-login or manual credentials
echo Choose login method:
echo   1. Auto-login with username/password (Recommended)
echo   2. Use manual credentials (Cookie)
echo.
set /p CHOICE="Enter choice (1 or 2, default: 1): "

REM Default to auto-login if empty or invalid
if "%CHOICE%"=="" set CHOICE=1
if /i not "%CHOICE%"=="2" set CHOICE=1

if "%CHOICE%"=="1" goto :auto_login
if "%CHOICE%"=="2" goto :manual_login

REM Should never reach here, but default to auto-login
goto :auto_login

:auto_login
echo.
echo === Auto-Login Mode ===
echo.
set /p USERNAME="Enter your username: "
if "%USERNAME%"=="" (
    echo Error: Username cannot be empty!
    pause
    exit /b 1
)

REM Get password securely (hidden input - shows asterisks)
echo Enter your password:
for /f "delims=" %%p in ('powershell -ExecutionPolicy Bypass -NoProfile -Command "$pwd = Read-Host -AsSecureString; $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($pwd); $plain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR); Write-Output $plain"') do set PASSWORD=%%p

if "%PASSWORD%"=="" (
    echo Error: Password cannot be empty!
    pause
    exit /b 1
)

echo.
echo Please wait, logging in...

REM Call PowerShell login script
REM Use full path to ensure script is found
set "SCRIPT_DIR=%~dp0"
powershell -ExecutionPolicy Bypass -NoProfile -File "%SCRIPT_DIR%login_hcmiu.ps1" -Username "%USERNAME%" -Password "%PASSWORD%" > login_result.json 2>error.log

REM Wait a moment for file to be written
timeout /t 2 /nobreak >nul 2>&1

REM Check if login was successful
if not exist login_result.json (
    echo.
    echo [ERROR] Login script failed to create output file!
    if exist error.log (
        echo Error details:
        type error.log
        del error.log >nul 2>&1
    )
    pause
    exit /b 1
)

REM Check if file is empty
for %%F in (login_result.json) do set size=%%~zF
if %size%==0 (
    echo.
    echo [ERROR] Login script returned empty result!
    if exist error.log (
        echo Error details:
        type error.log
        del error.log >nul 2>&1
    ) else (
        echo No error log found. The script may have failed silently.
    )
    if exist login_result.json (
        echo.
        echo login_result.json contents:
        type login_result.json
        del login_result.json >nul 2>&1
    )
    pause
    exit /b 1
)

REM Check if login was successful
powershell -ExecutionPolicy Bypass -NoProfile -Command "$ErrorActionPreference='Stop'; try { $json = Get-Content 'login_result.json' -Raw -Encoding UTF8; if ([string]::IsNullOrWhiteSpace($json)) { exit 1 }; $data = $json | ConvertFrom-Json; if ($data.success -eq $true) { exit 0 } else { exit 1 } } catch { Write-Host ('JSON Parse Error: ' + $_.Exception.Message); exit 1 }" 2>nul
if errorlevel 1 (
    echo.
    echo [ERROR] Login failed!
    echo Please check your username and password.
    echo.
    powershell -ExecutionPolicy Bypass -NoProfile -Command "$ErrorActionPreference='Stop'; try { $json = Get-Content 'login_result.json' -Raw -Encoding UTF8; $data = $json | ConvertFrom-Json; if ($data.error) { Write-Host ('Details: ' + $data.error) } else { Write-Host 'Details: Login was unsuccessful' } } catch { Write-Host ('Error reading result: ' + $_.Exception.Message) }" 2>nul
    echo.
    if exist login_result.json del login_result.json >nul 2>&1
    if exist error.log del error.log >nul 2>&1
    pause
    exit /b 1
)

REM Extract credentials
for /f "tokens=*" %%i in ('powershell -ExecutionPolicy Bypass -NoProfile -Command "$ErrorActionPreference='Stop'; $json = Get-Content 'login_result.json' -Raw -Encoding UTF8; $data = $json | ConvertFrom-Json; Write-Host $data.cookie"') do set COOKIE=%%i

echo [OK] Login successful!
goto :fetch_grades

:manual_login
echo.
echo === Manual Credentials Mode ===
echo.
echo You need to provide:
echo   - ASP.NET_SessionId Cookie
echo.
set /p COOKIE="Enter ASP.NET_SessionId Cookie: "
if "%COOKIE%"=="" (
    echo Error: Cookie is required!
    pause
    exit /b 1
)

:fetch_grades
echo.
echo Fetching all grades from API...
echo.

REM Set output filename
set /p OUTPUT_FILE="Enter output filename (default: all_grades.json): "
if "%OUTPUT_FILE%"=="" set OUTPUT_FILE=all_grades.json

REM Call PowerShell script to fetch grades
REM Capture stdout (JSON) to file, stderr (status messages) to error.log
powershell -ExecutionPolicy Bypass -File "%SCRIPT_DIR%get_all_grades.ps1" -Cookie "%COOKIE%" -OutputFile "%OUTPUT_FILE%" > fetch_result.json 2>error.log

REM Show status messages from stderr
if exist error.log (
    type error.log
)

REM Wait a moment for file to be written
timeout /t 1 /nobreak >nul 2>&1

REM Check if fetch was successful
powershell -ExecutionPolicy Bypass -NoProfile -Command "$ErrorActionPreference='Stop'; try { if (-not (Test-Path 'fetch_result.json')) { exit 1 }; $json = Get-Content 'fetch_result.json' -Raw -Encoding UTF8; if ([string]::IsNullOrWhiteSpace($json)) { exit 1 }; $data = $json | ConvertFrom-Json; if ($data.success -eq $true) { Write-Host ('[OK] Successfully fetched ' + $data.record_count + ' records'); exit 0 } else { Write-Host ('[ERROR] ' + $data.error); exit 1 } } catch { Write-Host ('JSON Parse Error: ' + $_.Exception.Message); if (Test-Path 'fetch_result.json') { Write-Host 'File contents:'; Get-Content 'fetch_result.json' -Raw | Write-Host }; exit 1 }"
if errorlevel 1 (
    echo.
    echo [ERROR] Failed to fetch grades!
    if exist error.log (
        echo Error details:
        type error.log
    )
    if exist fetch_result.json (
        echo.
        echo fetch_result.json contents:
        type fetch_result.json
    )
    if exist fetch_result.json del fetch_result.json >nul 2>&1
    if exist login_result.json del login_result.json >nul 2>&1
    if exist error.log del error.log >nul 2>&1
    pause
    exit /b 1
)

REM Cleanup
if exist login_result.json del login_result.json >nul 2>&1
if exist fetch_result.json del fetch_result.json >nul 2>&1
if exist error.log del error.log >nul 2>&1

echo.
echo ========================================
echo Done! Grades saved to: %OUTPUT_FILE%
echo Press any key to exit...
pause >nul

