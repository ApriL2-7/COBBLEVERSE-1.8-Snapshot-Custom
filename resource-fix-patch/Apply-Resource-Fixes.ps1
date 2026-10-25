param([string]$ProfilePath)
$ErrorActionPreference='Stop'
try {
    if (-not $ProfilePath) {
        Add-Type -AssemblyName System.Windows.Forms
        $dialog=New-Object System.Windows.Forms.FolderBrowserDialog
        $dialog.Description='Select COBBLEVERSE profile folder. Close Minecraft first.'
        $dialog.SelectedPath=Join-Path $env:APPDATA 'ModrinthApp\profiles'
        if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { exit 0 }
        $ProfilePath=$dialog.SelectedPath
    }
    $root=(Resolve-Path -LiteralPath $ProfilePath).Path
    $jar=Join-Path $root 'mods\mega_showdown-fabric-1.3.2+1.8.2+1.21.1-release.jar'
    $options=Join-Path $root 'options.txt'
    $config=Join-Path $root 'config\resourcepackoverrides.json'
    if (-not (Test-Path -LiteralPath $jar) -or -not (Test-Path -LiteralPath $options) -or -not (Test-Path -LiteralPath $config)) {
        throw 'Select the integrated COBBLEVERSE client profile with Mega Showdown 1.3.2.'
    }
    $clients=@(Get-CimInstance Win32_Process -Filter "name='javaw.exe' OR name='java.exe'" | Where-Object {$_.CommandLine -match 'KnotClient|net\.minecraft\.client\.main\.Main'})
    if ($clients.Count) { throw 'Close Minecraft first. The server can stay running.' }
    $utf8=New-Object System.Text.UTF8Encoding($false)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $read=[System.IO.Compression.ZipFile]::OpenRead($jar)
    try {
        $entry=$read.GetEntry('assets/cobblemon/lang/ko_kr.json')
        if (-not $entry) { throw 'Korean language entry missing.' }
        $reader=New-Object System.IO.StreamReader($entry.Open(),$utf8)
        try { $lang=$reader.ReadToEnd() } finally { $reader.Dispose() }
    } finally { $read.Dispose() }
    $pattern='("cobblemon\.move\.dragoncheer\.desc"\s*:\s*"[^"\n]*")\s*("cobblemon\.ui\.pokedex\.info\.form\.pikachu-cosplay")'
    $fixed=[regex]::Replace($lang,$pattern,('$1,' + "`n  " + '$2'))
    $cfg=([System.IO.File]::ReadAllText($config,$utf8) | ConvertFrom-Json)
    foreach ($fields in @($cfg.pack_overrides.PSObject.Properties.Value)+@($cfg.default_overrides)) {
        foreach ($field in @('title','description')) {
            $prop=$fields.PSObject.Properties[$field]
            if ($prop -and $prop.Value -is [string]) {
                try { $decoded=ConvertFrom-Json -InputObject $prop.Value -ErrorAction Stop } catch { $decoded=$prop.Value }
                $prop.Value=ConvertTo-Json -InputObject $decoded -Depth 30 -Compress
            }
        }
    }
    $packName='Cobbleverse-Resource-Fixes-2026.10.25.zip'
    $token='file/'+$packName
    $cfg.default_packs=@($cfg.default_packs | Where-Object {$_ -ne $token})+@($token)
    $text=[System.IO.File]::ReadAllText($options,$utf8)
    $match=[regex]::Match($text,'(?m)^resourcePacks:([^\r\n]*)')
    if (-not $match.Success) { throw 'resourcePacks option not found.' }
    $packs=@((ConvertFrom-Json -InputObject $match.Groups[1].Value) | Where-Object {$_ -ne $token})+@($token)
    $packLine='resourcePacks:'+(ConvertTo-Json -InputObject $packs -Compress)
    $updated=$text.Substring(0,$match.Index)+$packLine+$text.Substring($match.Index+$match.Length)
    $backup=Join-Path $root ('resource-fix-backup-'+[guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $backup | Out-Null
    Copy-Item -LiteralPath $jar -Destination (Join-Path $backup ([System.IO.Path]::GetFileName($jar)))
    Copy-Item -LiteralPath $config -Destination (Join-Path $backup 'resourcepackoverrides.json')
    Copy-Item -LiteralPath $options -Destination (Join-Path $backup 'options.txt')
    if ($fixed -ne $lang) {
        $temp=$jar+'.resourcefix.tmp'
        Copy-Item -LiteralPath $jar -Destination $temp
        $zip=[System.IO.Compression.ZipFile]::Open($temp,[System.IO.Compression.ZipArchiveMode]::Update)
        try {
            $zip.GetEntry('assets/cobblemon/lang/ko_kr.json').Delete()
            $entry=$zip.CreateEntry('assets/cobblemon/lang/ko_kr.json')
            $writer=New-Object System.IO.StreamWriter($entry.Open(),$utf8)
            try {$writer.Write($fixed)} finally {$writer.Dispose()}
        } finally {$zip.Dispose()}
        Move-Item -LiteralPath $temp -Destination $jar -Force
    }
    $packDest=Join-Path $root ('resourcepacks\'+$packName)
    if (Test-Path -LiteralPath $packDest) {Copy-Item -LiteralPath $packDest -Destination (Join-Path $backup $packName)}
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $packName) -Destination $packDest
    [System.IO.File]::WriteAllText($config,(ConvertTo-Json -InputObject $cfg -Depth 50),$utf8)
    [System.IO.File]::WriteAllText($options,$updated,$utf8)
    Write-Host 'Done! Korean JSON and resource fixes applied. Restart Minecraft.' -ForegroundColor Green
    Write-Host ('Backup: '+$backup)
} catch { Write-Host ('Failed: '+$_.Exception.Message) -ForegroundColor Red; exit 1 }
