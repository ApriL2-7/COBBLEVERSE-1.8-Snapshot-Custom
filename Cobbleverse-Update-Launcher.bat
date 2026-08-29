@echo off
setlocal
set "UPDATER_URL=https://raw.githubusercontent.com/ApriL2-7/COBBLEVERSE-1.8-Snapshot-Custom/main/updater/Cobbleverse-Updater.ps1"
set "UPDATER_FILE=%TEMP%\Cobbleverse-Updater-%RANDOM%-%RANDOM%.ps1"

del /q "%TEMP%\Cobbleverse-Updater-*.ps1" >nul 2>&1
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -UseBasicParsing -Uri ('%UPDATER_URL%?cache=' + [Guid]::NewGuid().ToString('N')) -OutFile '%UPDATER_FILE%'"
if errorlevel 1 goto download_failed

start "" powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%UPDATER_FILE%" -Gui
exit /b 0

:download_failed
powershell.exe -NoLogo -NoProfile -WindowStyle Hidden -Command "Add-Type -AssemblyName System.Windows.Forms; [Windows.Forms.MessageBox]::Show('Could not download the updater. Check your Internet connection.','Cobbleverse Updater',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Error)" >nul
exit /b 1
