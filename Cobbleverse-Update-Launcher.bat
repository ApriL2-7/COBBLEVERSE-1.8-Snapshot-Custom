@echo off
if not defined COBBLEVERSE_LAUNCHER_HIDDEN (
    set "COBBLEVERSE_LAUNCHER_HIDDEN=1"
    set "COBBLEVERSE_LAUNCHER_PATH=%~f0"
    powershell.exe -NoLogo -NoProfile -WindowStyle Hidden -Command "Start-Process -FilePath $env:ComSpec -ArgumentList '/d','/c',('""{0}""' -f $env:COBBLEVERSE_LAUNCHER_PATH) -WindowStyle Hidden"
    exit /b 0
)
setlocal
set "UPDATER_URL=https://raw.githubusercontent.com/ApriL2-7/COBBLEVERSE-1.8-Snapshot-Custom/main/updater/Cobbleverse-Updater.ps1"
set "UPDATER_FILE=%TEMP%\Cobbleverse-Updater-%RANDOM%-%RANDOM%.ps1"

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -UseBasicParsing -Uri '%UPDATER_URL%' -OutFile '%UPDATER_FILE%'"
if errorlevel 1 goto download_failed

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%UPDATER_FILE%" -Gui %*
set "RESULT=%ERRORLEVEL%"
del /q "%UPDATER_FILE%" >nul 2>&1
if "%RESULT%"=="0" exit /b 0

exit /b %RESULT%

:download_failed
del /q "%UPDATER_FILE%" >nul 2>&1
powershell.exe -NoLogo -NoProfile -WindowStyle Hidden -Command "Add-Type -AssemblyName System.Windows.Forms; [Windows.Forms.MessageBox]::Show('최신 업데이터를 다운로드하지 못했습니다. 인터넷 연결을 확인해 주세요.','Cobbleverse 업데이트',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Error)" >nul
exit /b 1
