@echo off
setlocal
cd /d "%~dp0"
echo Run the PowerShell script with the required version arguments.
echo Example:
echo powershell -ExecutionPolicy Bypass -File New-CobbleversePatch.ps1 -PayloadRoot "PATH\payload" -BaselineManifest "PATH\baseline.json" -FromVersion "2026.08.29.1" -ToVersion "2026.08.30.1" -OutputDirectory "PATH\out"
pause

