param([string]$ProfilePath)
$ErrorActionPreference = 'Stop'

try {
    if (-not $ProfilePath) {
        Add-Type -AssemblyName System.Windows.Forms
        $picker = New-Object System.Windows.Forms.FolderBrowserDialog
        $picker.Description = 'Select your COBBLEVERSE profile folder (contains options.txt). Close Minecraft first.'
        $picker.SelectedPath = Join-Path $env:APPDATA 'ModrinthApp\profiles'
        if ($picker.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { exit 0 }
        $ProfilePath = $picker.SelectedPath
    }
    $folder = (Resolve-Path -LiteralPath $ProfilePath).Path
    $options = Join-Path $folder 'options.txt'
    if (-not (Test-Path -LiteralPath $options -PathType Leaf)) {
        throw 'options.txt not found. Select the game profile folder, not mods or config.'
    }
    $clients = @(Get-CimInstance Win32_Process -Filter "name='javaw.exe' OR name='java.exe'" |
        Where-Object { $_.CommandLine -match 'KnotClient|net\.minecraft\.client\.main\.Main' })
    if ($clients.Count -gt 0) { throw 'Close Minecraft before applying this patch. The dedicated server can stay running.' }

    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $text = [System.IO.File]::ReadAllText($options, $utf8)
    if ($text -notmatch '(?m)^key_key\.cobblemon\.summary:') {
        throw 'This does not look like a Cobblemon profile. Start the correct profile once and close it first.'
    }
    $preset = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'keybinds.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $keys = @{}
    foreach ($prop in $preset.PSObject.Properties) {
        if (-not $prop.Name.StartsWith('key_') -or $prop.Value -notmatch '^key\.(keyboard|mouse)\.') {
            throw 'Invalid key preset.'
        }
        $keys[$prop.Name] = [string]$prop.Value
    }
    $newline = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $lines = [regex]::Split($text, '\r?\n')
    if ($lines.Length -gt 1 -and $lines[-1] -eq '') { $lines = $lines[0..($lines.Length - 2)] }
    $result = New-Object 'System.Collections.Generic.List[string]'
    $seen = @{}
    foreach ($line in $lines) {
        $name = ($line -split ':', 2)[0]
        if ($keys.ContainsKey($name)) {
            if (-not $seen.ContainsKey($name)) {
                $result.Add($name + ':' + $keys[$name])
                $seen[$name] = $true
            }
        } else { $result.Add($line) }
    }
    foreach ($name in ($keys.Keys | Sort-Object)) {
        if (-not $seen.ContainsKey($name)) { $result.Add($name + ':' + $keys[$name]) }
    }
    $updated = [string]::Join($newline, $result)
    if ($text.EndsWith("`n")) { $updated += $newline }
    $backup = $options + '.keybind-backup-' + [guid]::NewGuid().ToString('N') + '.bak'
    Copy-Item -LiteralPath $options -Destination $backup
    $temp = $options + '.keybind-' + [guid]::NewGuid().ToString('N') + '.tmp'
    [System.IO.File]::WriteAllText($temp, $updated, $utf8)
    Move-Item -LiteralPath $temp -Destination $options -Force
    Write-Host 'Done! Keybind defaults applied. Other settings were preserved.' -ForegroundColor Green
    Write-Host ('Backup: ' + $backup)
    Write-Host 'C: Starter/Summary | R: Send Pokemon | B: Backpack | P: PC | M: Map'
    Write-Host 'Grave accent (left of 1): Quests | F6/F7: Raid accept/decline'
} catch {
    Write-Host ('Failed: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
