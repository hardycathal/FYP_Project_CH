@echo off
echo =============================================
echo  Hide-and-Seek RL -- First-time Setup
echo =============================================

:: Check Python is available
python --version >nul 2>&1
if errorlevel 1 (
    echo ERROR: Python not found. Install Python 3.10+ and try again.
    pause
    exit /b 1
)

:: Create virtual environment
echo Creating virtual environment...
python -m venv Python\venv
if errorlevel 1 (
    echo ERROR: Failed to create virtual environment.
    pause
    exit /b 1
)

:: Activate and install dependencies
echo Installing dependencies...
call Python\venv\Scripts\activate.bat
pip install -r requirements.txt

echo.
echo =============================================
echo  Setup complete. You can now run:
echo    run_demo.bat     -- watch trained agents
echo    run_training.bat -- start dual self-play
echo =============================================
pause
