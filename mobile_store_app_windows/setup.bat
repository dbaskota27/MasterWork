@echo off
:: ════════════════════════════════════════════════════════
::  Mobile Store App — Windows First-Time Setup
::  Run this ONCE before using start_app.bat
:: ════════════════════════════════════════════════════════

cd /d "%~dp0"

echo.
echo  =========================================
echo   Mobile Store App — Setup
echo  =========================================
echo.

:: ── Activate conda if available ──
if exist "%USERPROFILE%\miniconda3\Scripts\activate.bat" (
    call "%USERPROFILE%\miniconda3\Scripts\activate.bat" base
    goto :install
)
if exist "%USERPROFILE%\anaconda3\Scripts\activate.bat" (
    call "%USERPROFILE%\anaconda3\Scripts\activate.bat" base
    goto :install
)
if exist "C:\ProgramData\miniconda3\Scripts\activate.bat" (
    call "C:\ProgramData\miniconda3\Scripts\activate.bat" base
    goto :install
)
if exist "C:\ProgramData\anaconda3\Scripts\activate.bat" (
    call "C:\ProgramData\anaconda3\Scripts\activate.bat" base
    goto :install
)

echo  [INFO] Conda not found - using system Python.
echo.

:install
echo  Installing required packages...
echo  (This may take a few minutes on first run)
echo.

pip install -r requirements.txt

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo  [ERROR] Some packages failed to install.
    echo  Make sure Python and pip are installed and try again.
    echo.
    pause
    exit /b 1
)

echo.
echo  =========================================
echo   Setup complete!
echo   You can now run start_app.bat to launch.
echo  =========================================
echo.

:: ── Remind about .env setup ──
if not exist ".env" (
    echo  [IMPORTANT] No .env file found!
    echo  Copy .env.example to .env and fill in your Supabase credentials.
    echo.
)

pause
