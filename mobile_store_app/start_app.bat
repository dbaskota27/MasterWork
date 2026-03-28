@echo off
:: ── Mobile Store App Launcher (Windows) ──────────────────────────────────────
:: Double-click this file to start the app. It will open in your browser.

cd /d "%~dp0"

echo.
echo   Starting Mobile Store App...
echo   Opening http://localhost:8501 in your browser.
echo   Close this window to stop the app.
echo.

:: Try conda activation (adjust path if your conda is elsewhere)
call "%USERPROFILE%\miniconda3\Scripts\activate.bat" 2>nul || ^
call "%USERPROFILE%\anaconda3\Scripts\activate.bat" 2>nul

streamlit run app.py --server.headless false

pause
