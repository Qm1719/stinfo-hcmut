@echo off
REM HCMUT Grades Fetcher - No Python Required
REM Uses PowerShell (built into Windows)
REM Just double-click to run!

REM Set UTF-8 code page for proper Vietnamese character display
chcp 65001 >nul
REM Also set PowerShell to use UTF-8
set PYTHONIOENCODING=utf-8

REM Clear screen and show welcome
cls
echo ========================================
echo   HCMUT Grades Fetcher
echo ========================================
echo.

REM Check if user wants to use auto-login or manual credentials
echo Choose login method:
echo   1. Auto-login with username/password (Recommended)
echo   2. Use manual credentials (Token and Cookie)
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

set /p SEMESTER_YEAR="Enter semester year (default: 251): "
if "%SEMESTER_YEAR%"=="" set SEMESTER_YEAR=20251

REM Normalize semester code: if 3 digits (e.g., 251), convert to 5 digits (20251)
for /f "tokens=*" %%s in ('powershell -ExecutionPolicy Bypass -NoProfile -Command "if ('%SEMESTER_YEAR%' -match '^\d{3}$') { Write-Output ('20' + '%SEMESTER_YEAR%') } else { Write-Output '%SEMESTER_YEAR%' }"') do set SEMESTER_YEAR=%%s

echo.
echo Please wait, logging in...

REM Call PowerShell login script
REM Use full path to ensure script is found
set "SCRIPT_DIR=%~dp0"
powershell -ExecutionPolicy Bypass -File "%SCRIPT_DIR%login_hcmut.ps1" -Username "%USERNAME%" -Password "%PASSWORD%" > login_result.json 2>error.log

REM Wait a moment for file to be written
timeout /t 1 /nobreak >nul 2>&1

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
    )
    if exist login_result.json del login_result.json >nul 2>&1
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
for /f "tokens=*" %%i in ('powershell -ExecutionPolicy Bypass -NoProfile -Command "$ErrorActionPreference='Stop'; $json = Get-Content 'login_result.json' -Raw -Encoding UTF8; $data = $json | ConvertFrom-Json; Write-Host $data.auth_token"') do set AUTH_TOKEN=%%i
for /f "tokens=*" %%i in ('powershell -ExecutionPolicy Bypass -NoProfile -Command "$ErrorActionPreference='Stop'; $json = Get-Content 'login_result.json' -Raw -Encoding UTF8; $data = $json | ConvertFrom-Json; Write-Host $data.cookie"') do set COOKIE=%%i
for /f "tokens=*" %%i in ('powershell -ExecutionPolicy Bypass -NoProfile -Command "$ErrorActionPreference='Stop'; $json = Get-Content 'login_result.json' -Raw -Encoding UTF8; $data = $json | ConvertFrom-Json; Write-Host $data.student_id"') do set STUDENT_ID=%%i

if "%STUDENT_ID%"=="" (
    echo.
    set /p STUDENT_ID="Student ID not found. Please enter your Student ID: "
    if "%STUDENT_ID%"=="" (
        echo Error: Student ID is required!
        if exist login_result.json del login_result.json >nul 2>&1
        pause
        exit /b 1
    )
)

echo [OK] Login successful!
goto :fetch_grades

:manual_login
echo.
echo === Manual Credentials Mode ===
echo.
echo You need to provide:
echo   - Authorization Token (JWT)
echo   - JSESSIONID Cookie
echo   - Student ID
echo.
set /p AUTH_TOKEN="Enter Authorization Token: "
if "%AUTH_TOKEN%"=="" (
    echo Error: Authorization Token is required!
    pause
    exit /b 1
)

set /p COOKIE="Enter JSESSIONID Cookie: "
if "%COOKIE%"=="" (
    echo Error: Cookie is required!
    pause
    exit /b 1
)

set /p STUDENT_ID="Enter Student ID: "
if "%STUDENT_ID%"=="" (
    echo Error: Student ID is required!
    pause
    exit /b 1
)

set /p SEMESTER_YEAR="Enter semester year (default: 20251): "
if "%SEMESTER_YEAR%"=="" set SEMESTER_YEAR=20251

REM Normalize semester code: if 3 digits (e.g., 251), convert to 5 digits (20251)
for /f "tokens=*" %%s in ('powershell -ExecutionPolicy Bypass -NoProfile -Command "if ('%SEMESTER_YEAR%' -match '^\d{3}$') { Write-Output ('20' + '%SEMESTER_YEAR%') } else { Write-Output '%SEMESTER_YEAR%' }"') do set SEMESTER_YEAR=%%s

:fetch_grades
echo.
echo Fetching grades...
echo Student ID: %STUDENT_ID%
echo Semester: %SEMESTER_YEAR%
echo.

REM Optimized curl command - save to file first to avoid encoding issues
curl -s -f -L --compressed --max-time 30 ^
  --cookie-jar cookies.txt ^
  --cookie cookies.txt ^
  "https://mybk.hcmut.edu.vn/api/v1/student/subject-grade/detail?studentId=%STUDENT_ID%&semesterYear=%SEMESTER_YEAR%" ^
  -H "Accept: application/json" ^
  -H "Accept-Encoding: gzip, deflate, br" ^
  -H "Accept-Language: en-US,en;q=0.9,vi;q=0.8" ^
  -H "Authorization: %AUTH_TOKEN%" ^
  -H "Cookie: JSESSIONID=%COOKIE%" ^
  -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" ^
  -H "Referer: https://mybk.hcmut.edu.vn/" ^
  -H "Origin: https://mybk.hcmut.edu.vn" -o grades_temp.json

if errorlevel 1 (
    echo.
    echo [ERROR] Failed to fetch grades from API!
    echo Please check your internet connection and try again.
    if exist grades_temp.json del grades_temp.json >nul 2>&1
    pause
    exit /b 1
)

REM Parse the JSON file
powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0parse_grades.ps1" -InputFile "grades_temp.json"

REM Cleanup
if exist grades_temp.json del grades_temp.json >nul 2>&1

REM Cleanup
if exist login_result.json del login_result.json >nul 2>&1
if exist cookies.txt del cookies.txt >nul 2>&1
if exist error.log del error.log >nul 2>&1

echo.
echo ========================================
echo Done! Press any key to exit...
pause >nul

