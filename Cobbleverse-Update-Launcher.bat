@echo off
setlocal EnableExtensions
set "UPDATER_URL=https://raw.githubusercontent.com/ApriL2-7/COBBLEVERSE-1.8-Snapshot-Custom/main/updater/Cobbleverse-Updater.ps1"
set "BOOTSTRAP_URL=https://raw.githubusercontent.com/ApriL2-7/COBBLEVERSE-1.8-Snapshot-Custom/main/updater/Cobbleverse-Bootstrap.ps1"
set "UPDATER_FILE=%TEMP%\Cobbleverse-Updater-%RANDOM%-%RANDOM%.ps1"
set "BOOTSTRAP_FILE=%TEMP%\Cobbleverse-Bootstrap-%RANDOM%-%RANDOM%.ps1"
set "PROFILE_PATH="
set "PROFILES_ROOT="

del /q "%TEMP%\Cobbleverse-Updater-*.ps1" >nul 2>&1
del /q "%TEMP%\Cobbleverse-Bootstrap-*.ps1" >nul 2>&1
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -UseBasicParsing -Uri ('%UPDATER_URL%?cache=' + [Guid]::NewGuid().ToString('N')) -OutFile '%UPDATER_FILE%'; Invoke-WebRequest -UseBasicParsing -Uri ('%BOOTSTRAP_URL%?cache=' + [Guid]::NewGuid().ToString('N')) -OutFile '%BOOTSTRAP_FILE%'"
if errorlevel 1 goto download_failed

for /f "usebackq delims=" %%P in (`powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "Add-Type -AssemblyName System.Windows.Forms; Add-Type -AssemblyName Microsoft.VisualBasic; $guard='cobbleverse-client-pack-guard-2026.08.29.1.jar'; $state='cobbleverse-pack-state.json'; $roots=@(); $roots+=(Join-Path $env:APPDATA 'ModrinthApp\profiles'); $roots+=(Join-Path $env:USERPROFILE 'curseforge\minecraft\Instances'); $roots+=(Join-Path $env:USERPROFILE 'Documents\Curse\Minecraft\Instances'); $matches=@(); foreach($root in $roots){ if(-not (Test-Path -LiteralPath $root -PathType Container)){ continue }; $named=Join-Path $root 'COBBLEVERSE 1.8 Snapshot Custom'; if(Test-Path -LiteralPath $named -PathType Container){ $matches+=(Get-Item -LiteralPath $named) }; foreach($dir in @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue)){ $guardPath=Join-Path $dir.FullName ('mods\'+$guard); $statePath=Join-Path $dir.FullName $state; if((Test-Path -LiteralPath $guardPath -PathType Leaf) -or (Test-Path -LiteralPath $statePath -PathType Leaf)){ $matches+=$dir } } }; $unique=@(); $seen=@{}; foreach($m in $matches){ if(-not $seen.ContainsKey($m.FullName)){ $seen[$m.FullName]=$true; $unique+=$m } }; $preferred=@(); foreach($m in $unique){ if($m.Name -eq 'COBBLEVERSE 1.8 Snapshot Custom'){ $preferred+=$m } }; if($preferred.Count -eq 1){ $preferred[0].FullName } elseif($unique.Count -eq 1){ $unique[0].FullName } else { $typed=[Microsoft.VisualBasic.Interaction]::InputBox('Paste the COBBLEVERSE profile path (Modrinth or CurseForge). Leave blank to browse.','Cobbleverse Updater',''); if(-not [string]::IsNullOrWhiteSpace($typed)){ $typed.Trim().Trim([char]34) } else { $dlg=[Windows.Forms.FolderBrowserDialog]::new(); $dlg.Description='Select the COBBLEVERSE profile folder (Modrinth or CurseForge)'; $dlg.ShowNewFolderButton=$false; foreach($root in $roots){ if(Test-Path -LiteralPath $root -PathType Container){ $dlg.SelectedPath=$root; break } }; if($dlg.ShowDialog() -eq [Windows.Forms.DialogResult]::OK){ $dlg.SelectedPath } } }"`) do set "PROFILE_PATH=%%P"

if not defined PROFILE_PATH goto profile_not_selected
for %%R in ("%PROFILE_PATH%\..") do set "PROFILES_ROOT=%%~fR"
if not defined PROFILES_ROOT goto profile_not_selected

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%BOOTSTRAP_FILE%" -Gui -ProfilePath "%PROFILE_PATH%" -Repository "ApriL2-7/COBBLEVERSE-1.8-Snapshot-Custom"
if errorlevel 1 goto bootstrap_failed

del /q "%BOOTSTRAP_FILE%" >nul 2>&1
start "" powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%UPDATER_FILE%" -Gui -ProfilePath "%PROFILE_PATH%" -ProfilesRoot "%PROFILES_ROOT%"
exit /b 0

:bootstrap_failed
del /q "%BOOTSTRAP_FILE%" >nul 2>&1
del /q "%UPDATER_FILE%" >nul 2>&1
exit /b 1

:profile_not_selected
powershell.exe -NoLogo -NoProfile -WindowStyle Hidden -Command "Add-Type -AssemblyName System.Windows.Forms; [Windows.Forms.MessageBox]::Show('Could not find the COBBLEVERSE profile. Select the actual profile folder used by Modrinth or CurseForge and try again.','Cobbleverse Updater',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Warning)" >nul
del /q "%BOOTSTRAP_FILE%" >nul 2>&1
del /q "%UPDATER_FILE%" >nul 2>&1
exit /b 1

:download_failed
powershell.exe -NoLogo -NoProfile -WindowStyle Hidden -Command "Add-Type -AssemblyName System.Windows.Forms; [Windows.Forms.MessageBox]::Show('Could not download the updater. Check your Internet connection.','Cobbleverse Updater',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Error)" >nul
del /q "%BOOTSTRAP_FILE%" >nul 2>&1
del /q "%UPDATER_FILE%" >nul 2>&1
exit /b 1
