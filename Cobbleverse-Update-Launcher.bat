@echo off
setlocal EnableExtensions
set "UPDATER_URL=https://raw.githubusercontent.com/ApriL2-7/COBBLEVERSE-1.8-Snapshot-Custom/main/updater/Cobbleverse-Updater.ps1"
set "UPDATER_FILE=%TEMP%\Cobbleverse-Updater-%RANDOM%-%RANDOM%.ps1"
set "PROFILE_PATH="

del /q "%TEMP%\Cobbleverse-Updater-*.ps1" >nul 2>&1
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -UseBasicParsing -Uri ('%UPDATER_URL%?cache=' + [Guid]::NewGuid().ToString('N')) -OutFile '%UPDATER_FILE%'"
if errorlevel 1 goto download_failed

for /f "usebackq delims=" %%P in (`powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "Add-Type -AssemblyName System.Windows.Forms; $root=Join-Path $env:APPDATA 'ModrinthApp\profiles'; $preferred=Join-Path $root 'COBBLEVERSE 1.8 Snapshot Custom'; if (Test-Path -LiteralPath $preferred -PathType Container) { $preferred } else { $guard='cobbleverse-client-pack-guard-2026.08.29.1.jar'; $matches=@(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue ^| Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName ('mods\' + $guard)) -PathType Leaf }); if ($matches.Count -eq 1) { $matches[0].FullName } else { $dlg=[Windows.Forms.FolderBrowserDialog]::new(); $dlg.Description='COBBLEVERSE Modrinth profile folder'; if (Test-Path -LiteralPath $root -PathType Container) { $dlg.SelectedPath=$root }; if ($dlg.ShowDialog() -eq [Windows.Forms.DialogResult]::OK) { $dlg.SelectedPath } } }"`) do set "PROFILE_PATH=%%P"

if not defined PROFILE_PATH goto profile_not_selected

start "" powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%UPDATER_FILE%" -Gui -ProfilePath "%PROFILE_PATH%"
exit /b 0

:profile_not_selected
powershell.exe -NoLogo -NoProfile -WindowStyle Hidden -Command "Add-Type -AssemblyName System.Windows.Forms; [Windows.Forms.MessageBox]::Show('Could not find the COBBLEVERSE Modrinth profile. Select the profile folder and try again.','Cobbleverse Updater',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Warning)" >nul
del /q "%UPDATER_FILE%" >nul 2>&1
exit /b 1

:download_failed
powershell.exe -NoLogo -NoProfile -WindowStyle Hidden -Command "Add-Type -AssemblyName System.Windows.Forms; [Windows.Forms.MessageBox]::Show('Could not download the updater. Check your Internet connection.','Cobbleverse Updater',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Error)" >nul
del /q "%UPDATER_FILE%" >nul 2>&1
exit /b 1
