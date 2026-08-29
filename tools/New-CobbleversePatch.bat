@echo off
setlocal EnableExtensions
cd /d "%~dp0"

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0New-CobbleversePatch-Gui.ps1"
if errorlevel 1 (
    echo.
    echo Cobbleverse patch builder failed. Check the popup message for details.
    pause
)

exit /b %errorlevel%
