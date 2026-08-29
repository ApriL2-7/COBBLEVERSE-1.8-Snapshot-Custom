@echo off
setlocal
set "UPDATER_URL=https://raw.githubusercontent.com/ApriL2-7/COBBLEVERSE-1.8-Snapshot-Custom/main/updater/Cobbleverse-Updater.ps1"
set "UPDATER_FILE=%TEMP%\Cobbleverse-Updater-%RANDOM%-%RANDOM%.ps1"

echo [COBBLEVERSE] Downloading the latest updater...
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -UseBasicParsing -Uri '%UPDATER_URL%' -OutFile '%UPDATER_FILE%'"
if errorlevel 1 goto download_failed

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%UPDATER_FILE%" %*
set "RESULT=%ERRORLEVEL%"
del /q "%UPDATER_FILE%" >nul 2>&1
if "%RESULT%"=="0" exit /b 0

echo.
echo [COBBLEVERSE] Update failed. Error code: %RESULT%
pause
exit /b %RESULT%

:download_failed
del /q "%UPDATER_FILE%" >nul 2>&1
echo.
echo [COBBLEVERSE] Could not download the updater. Check your Internet connection.
pause
exit /b 1

