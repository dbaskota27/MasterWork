@echo off
:: ════════════════════════════════════════════════════════
::  Mobile Store App — Windows Launcher
::  Double-click this file to start the app.
::  Your browser will open automatically.
:: ════════════════════════════════════════════════════════

cd /d "%~dp0"

echo.
echo  =========================================
echo   📱 Starting Mobile Store App...
echo  =========================================
echo.

:: ── Try to activate conda (checks common install paths) ──
if exist "%USERPROFILE%\miniconda3\Scripts\activate.bat" (
    call "%USERPROFILE%\miniconda3\Scripts\activate.bat" base
    goto :run
)
if exist "%USERPROFILE%\anaconda3\Scripts\activate.bat" (
    call "%USERPROFILE%\anaconda3\Scripts\activate.bat" base
    goto :run
)
if exist "C:\ProgramData\miniconda3\Scripts\activate.bat" (
    call "C:\ProgramData\miniconda3\Scripts\activate.bat" base
    goto :run
)
if exist "C:\ProgramData\anaconda3\Scripts\activate.bat" (
    call "C:\ProgramData\anaconda3\Scripts\activate.bat" base
    goto :run
)

echo  [INFO] Conda not found - using system Python.
echo.

:run
:: ── Check streamlit is available ──
where streamlit >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo  [ERROR] Streamlit is not installed.
    echo  Please run setup.bat first, then try again.
    echo.
    pause
    exit /b 1
)

echo  Browser opening at http://localhost:8501
echo  Press Ctrl+C or close this window to stop.
echo.

streamlit run app.py --server.headless false

pause
