@echo off
setlocal EnableExtensions
chcp 65001 >nul
title Cobbleverse Updater
set "LAUNCHER_URL=https://api.github.com/repos/ApriL2-7/COBBLEVERSE-1.8-Snapshot-Custom/contents/updater/Cobbleverse-Launcher.ps1?ref=main"
set "LAUNCHER_FILE=%TEMP%\Cobbleverse-Launcher-%RANDOM%-%RANDOM%.ps1"

del /q "%TEMP%\Cobbleverse-Launcher-*.ps1" >nul 2>&1
echo [COBBLEVERSE] Downloading the latest updater...
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $h=@{'Accept'='application/vnd.github.raw+json';'User-Agent'='Cobbleverse-Updater';'X-GitHub-Api-Version'='2022-11-28'}; Invoke-WebRequest -UseBasicParsing -Headers $h -Uri ('%LAUNCHER_URL%&cache=' + [Guid]::NewGuid().ToString('N')) -OutFile '%LAUNCHER_FILE%'"
if errorlevel 1 goto download_failed

rem Runs in this console so every step prints here instead of opening a window.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%LAUNCHER_FILE%"
set "RESULT=%ERRORLEVEL%"
del /q "%LAUNCHER_FILE%" >nul 2>&1
echo.
if not "%RESULT%"=="0" echo [COBBLEVERSE] Update failed with error code %RESULT%.
pause
exit /b %RESULT%

:download_failed
echo.
echo [COBBLEVERSE] Could not download the latest Cobbleverse launcher.
echo [COBBLEVERSE] Check your Internet connection and run this again.
del /q "%LAUNCHER_FILE%" >nul 2>&1
echo.
pause
exit /b 1
