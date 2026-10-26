param([Parameter(Mandatory=$true)][string]$ProfilePath, [switch]$Inspect)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12

try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $profile=(Resolve-Path -LiteralPath $ProfilePath).Path
    $mods=Join-Path $profile 'mods'
    if (-not (Test-Path -LiteralPath $mods -PathType Container)) { throw 'Select a Minecraft profile with a mods folder.' }
    $core=@();$tweaks=@()
    foreach ($file in @(Get-ChildItem -LiteralPath $mods -Filter '*.jar' -File)) {
        $zip=$null
        try {
            $zip=[IO.Compression.ZipFile]::OpenRead($file.FullName)
            $entry=$zip.GetEntry('fabric.mod.json')
            if (-not $entry) { continue }
            $reader=New-Object IO.StreamReader($entry.Open(),[Text.Encoding]::UTF8)
            try { $meta=$reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose() }
            if ($meta.id -eq 'cobblemon') { $core+=@{File=$file;Metadata=$meta} }
            if ($meta.id -eq 'more_cobblemon_tweaks') { $tweaks+=@{File=$file;Metadata=$meta} }
        } finally { if ($zip) { $zip.Dispose() } }
    }
    if ($core.Count -ne 1) { throw 'Exactly one active Cobblemon JAR is required.' }
    $coreVersion=[string]$core[0].Metadata.version
    if ($coreVersion -notmatch '^(\d+\.\d+\.\d+)') { throw 'Cannot read the Cobblemon version.' }
    $version=[version]$Matches[1]
    if ($version -lt [version]'1.8.2') {
        Write-Host '[COBBLEVERSE] Legacy profile: using the existing patch updater.'
        exit 20
    }
    if ($version -ge [version]'1.9.0') { throw 'This integration update has not been validated for Cobblemon 1.9 or later.' }
    if ($Inspect) { Write-Host ('[COBBLEVERSE] Integrated profile detected: Cobblemon '+$coreVersion); exit 0 }
    $clients=@(Get-CimInstance Win32_Process -Filter "name='javaw.exe' OR name='java.exe'" |
        Where-Object {$_.CommandLine -match 'KnotClient|net\.minecraft\.client\.main\.Main'})
    if ($clients.Count) { throw 'Close Minecraft before updating. The dedicated server may stay running.' }
    if ($tweaks.Count -eq 0) {
        Write-Host '[COBBLEVERSE] More Cobblemon Tweaks is not installed. No PC fix is required.'
        exit 0
    }
    if ($tweaks.Count -ne 1) { throw 'Multiple More Cobblemon Tweaks JARs are active. Remove duplicate versions first.' }
    $installed=[version]([string]$tweaks[0].Metadata.version)
    if ($installed -ge [version]'1.3.6') {
        Write-Host '[COBBLEVERSE] PC fix is already installed.' -ForegroundColor Green
        exit 0
    }
    $url='https://cdn.modrinth.com/data/5KWlJ2HC/versions/g4m18yE2/MoreCobblemonTweaks-fabric-1.3.6.jar'
    $expected='d99fe98b741ed209d2537c44c69fefd888490859e71f2ea57e3b170803d3d8e5716f904f3f7024f1f6e8fd95f82fcac42f6c97a63fb6047f500ae1447c1f692b'
    $old=$tweaks[0].File.FullName
    $destination=Join-Path $mods 'MoreCobblemonTweaks-fabric-1.3.6.jar'
    if (Test-Path -LiteralPath $destination) { throw 'Unexpected existing destination JAR. Refusing overwrite.' }
    $stage=Join-Path $profile ('.cobbleverse-pcfix-'+[guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $stage | Out-Null
    $download=Join-Path $stage 'download.jar'
    Write-Host '[COBBLEVERSE] Downloading PC crash fix (135 KB)...'
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $download
    if ((Get-FileHash -LiteralPath $download -Algorithm SHA512).Hash -ne $expected) { throw 'Official mod download hash mismatch. No installed files changed.' }
    $check=[IO.Compression.ZipFile]::OpenRead($download)
    try {
        $reader=New-Object IO.StreamReader($check.GetEntry('fabric.mod.json').Open(),[Text.Encoding]::UTF8)
        try { $meta=$reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose() }
        if ($meta.id -ne 'more_cobblemon_tweaks' -or $meta.version -ne '1.3.6') { throw 'Unexpected downloaded mod metadata.' }
    } finally { $check.Dispose() }
    $backup=Join-Path $stage ([IO.Path]::GetFileName($old))
    Copy-Item -LiteralPath $old -Destination $backup
    try {
        Copy-Item -LiteralPath $download -Destination $destination
        Remove-Item -LiteralPath $old -Force
    } catch {
        if (Test-Path -LiteralPath $destination) { Remove-Item -LiteralPath $destination -Force }
        if (-not (Test-Path -LiteralPath $old)) { Copy-Item -LiteralPath $backup -Destination $old }
        throw
    }
    Remove-Item -LiteralPath $download -Force
    Write-Host '[COBBLEVERSE] PC crash fix installed. Start Minecraft from Modrinth.' -ForegroundColor Green
    Write-Host ('[COBBLEVERSE] Previous mod backup: '+$backup)
    exit 0
} catch {
    Write-Host ('[COBBLEVERSE] '+$_.Exception.Message) -ForegroundColor Red
    exit 1
}
