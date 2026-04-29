@echo off
echo Starting Hide and Seek demo...

if not exist "Python\venv\Scripts\activate.bat" (
    echo ERROR: Virtual environment not found. Run setup.bat first.
    pause
    exit /b 1
)

start "" "hide-and-seek\HideAndSeek.exe"

echo Waiting for game to load...
timeout /t 3 /nobreak >nul

call Python\venv\Scripts\activate.bat
cd Python
python watch_dual.py

pause
