@echo off
setlocal EnableExtensions
set "LAUNCHER_URL=https://raw.githubusercontent.com/ApriL2-7/COBBLEVERSE-1.8-Snapshot-Custom/main/updater/Cobbleverse-Launcher.ps1"
set "LAUNCHER_FILE=%TEMP%\Cobbleverse-Launcher-%RANDOM%-%RANDOM%.ps1"

del /q "%TEMP%\Cobbleverse-Launcher-*.ps1" >nul 2>&1
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -UseBasicParsing -Uri ('%LAUNCHER_URL%?cache=' + [Guid]::NewGuid().ToString('N')) -OutFile '%LAUNCHER_FILE%'"
if errorlevel 1 goto download_failed

start "" powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%LAUNCHER_FILE%"
exit /b 0

:download_failed
powershell.exe -NoLogo -NoProfile -WindowStyle Hidden -Command "Add-Type -AssemblyName System.Windows.Forms; [Windows.Forms.MessageBox]::Show('Could not download the latest Cobbleverse launcher. Check your Internet connection.','Cobbleverse Updater',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Error)" >nul
del /q "%LAUNCHER_FILE%" >nul 2>&1
exit /b 1
