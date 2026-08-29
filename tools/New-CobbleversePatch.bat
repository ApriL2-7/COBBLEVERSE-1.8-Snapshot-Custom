@echo off
setlocal EnableExtensions

set "GUI_URL=https://raw.githubusercontent.com/ApriL2-7/COBBLEVERSE-1.8-Snapshot-Custom/main/tools/New-CobbleversePatch-Gui.ps1"
set "GUI_FILE=%TEMP%\Cobbleverse-PatchBuilder-%RANDOM%-%RANDOM%.ps1"

del /q "%TEMP%\Cobbleverse-PatchBuilder-*.ps1" >nul 2>&1
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -UseBasicParsing -Uri ('%GUI_URL%?cache=' + [Guid]::NewGuid().ToString('N')) -OutFile '%GUI_FILE%'"
if errorlevel 1 goto download_failed

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%GUI_FILE%"
set "RC=%ERRORLEVEL%"
del /q "%GUI_FILE%" >nul 2>&1
exit /b %RC%

:download_failed
powershell.exe -NoLogo -NoProfile -WindowStyle Hidden -Command "Add-Type -AssemblyName System.Windows.Forms; [Windows.Forms.MessageBox]::Show('Could not download the latest Cobbleverse patch builder. Check your Internet connection.','Cobbleverse Patch Builder',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Error)" >nul
del /q "%GUI_FILE%" >nul 2>&1
exit /b 1
