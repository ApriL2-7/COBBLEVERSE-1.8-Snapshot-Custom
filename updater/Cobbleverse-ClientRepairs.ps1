param([Parameter(Mandatory=$true)][string]$ProfilePath,[string]$LocalHotfixPath='')
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
$utf8=New-Object Text.UTF8Encoding($false)
$stage=$null
$changedFiles=$false

function Get-RepairHash([string]$Path) {
    $stream=[IO.File]::OpenRead($Path)
    $sha=[Security.Cryptography.SHA256]::Create()
    try {return [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','').ToLowerInvariant()}
    finally {$stream.Dispose();$sha.Dispose()}
}

function Read-ZipJson($Zip,[string]$Name) {
    $entry=$Zip.GetEntry($Name)
    if (-not $entry) {return $null}
    $reader=New-Object IO.StreamReader($entry.Open(),[Text.Encoding]::UTF8)
    try {return ($reader.ReadToEnd() | ConvertFrom-Json)} finally {$reader.Dispose()}
}
function Write-ZipText($Zip,[string]$Name,[string]$Text) {
    $entry=$Zip.CreateEntry($Name,[IO.Compression.CompressionLevel]::Optimal)
    $entry.LastWriteTime=[DateTimeOffset]'2026-10-27T00:00:00Z'
    $writer=New-Object IO.StreamWriter($entry.Open(),$script:utf8)
    try {$writer.Write($Text)} finally {$writer.Dispose()}
}

try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $profile=(Resolve-Path -LiteralPath $ProfilePath).Path
    $mods=Join-Path $profile 'mods'
    $clients=@(Get-CimInstance Win32_Process -Filter "name='javaw.exe' OR name='java.exe'" |
        Where-Object {$_.CommandLine -match 'KnotClient|net\.minecraft\.client\.main\.Main'})
    if ($clients.Count) {throw 'Close Minecraft before applying client repairs.'}
    $core=@();$installed=@();$resourceMods=@()
    foreach ($jar in @(Get-ChildItem -LiteralPath $mods -Filter '*.jar' -File)) {
        $z=[IO.Compression.ZipFile]::OpenRead($jar.FullName)
        try {$meta=Read-ZipJson $z 'fabric.mod.json'} finally {$z.Dispose()}
        if ($meta.id) {$resourceMods+=@{Id=[string]$meta.id;Path=$jar.FullName}}
        if ($meta.id -eq 'cobblemon') {$core+=@{File=$jar;Metadata=$meta}}
        if ($meta.id -eq 'cobbleverse_client_callback_guard') {$installed+=@{File=$jar;Metadata=$meta}}
    }
    if ($core.Count -ne 1) {throw 'Exactly one active Cobblemon JAR is required.'}
    if ([string]$core[0].Metadata.version -notmatch '^1\.8\.3(?:\+|$)') {
        Write-Host '[COBBLEVERSE] These resource/callback repairs target Cobblemon 1.8.3 only; no additional files changed.'
        exit 0
    }
    if ($installed.Count -gt 1) {throw 'Duplicate client callback guard mods found.'}
    # Private callback names are version-specific: verify the reviewed target class.
    $z=[IO.Compression.ZipFile]::OpenRead($core[0].File.FullName)
    try {
        $entry=$z.GetEntry('com/cobblemon/mod/common/events/CallbackHandler.class')
        if (-not $entry) {throw 'Cobblemon callback class is missing.'}
        $stream=$entry.Open();$sha=[Security.Cryptography.SHA256]::Create()
        try {$targetHash=[BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','').ToLowerInvariant()}
        finally {$stream.Dispose();$sha.Dispose()}
        if ($targetHash -ne '9779816a41488499574e88d9d219e4be103aa5927c282ed4dbde1f24de630bf7') {
            throw 'This Cobblemon callback implementation differs from the reviewed 1.8.3 build. No files changed.'
        }
    } finally {$z.Dispose()}
    $addonName='cobbleverse-client-callback-guard-1.0.0.jar'
    $expected='9a51a11cb20fb48cd335499f535f0ba7d54801ecc622491cdcefddcfcfd10079'
    $needAddon=$installed.Count -eq 0
    if ($installed.Count -eq 1) {
        if ([version]$installed[0].Metadata.version -gt [version]'1.0.0') {$needAddon=$false}
        elseif ((Get-RepairHash $installed[0].File.FullName) -ne $expected) {
            throw 'Installed callback guard does not match the reviewed artifact; refusing overwrite.'
        }
    }
    $options=Join-Path $profile 'options.txt'
    $configPath=Join-Path $profile 'config\resourcepackoverrides.json'
    $optionsText=[IO.File]::ReadAllText($options,$utf8)
    $configText=[IO.File]::ReadAllText($configPath,$utf8)
    $config=ConvertFrom-Json -InputObject $configText
    if (-not $config) {throw 'resourcepackoverrides.json is empty; restore its original configuration first.'}
    $match=[regex]::Match($optionsText,'(?m)^resourcePacks:([^\r\n]*)')
    if (-not $match.Success) {throw 'resourcePacks setting not found.'}
    $packList=ConvertFrom-Json -InputObject $match.Groups[1].Value
    $repairName='Cobbleverse-Client-Repair-2026.10.27.zip'
    $token='file/'+$repairName
    $packRoot=[IO.Path]::GetFullPath((Join-Path $profile 'resourcepacks'))
    # Fabric's normal mod resource order is mod ID order, followed by enabled packs.
    $sources=@($resourceMods | Sort-Object { $_.Id } | ForEach-Object {$_.Path})
    foreach ($id in $packList) {
        if (-not $id.StartsWith('file/') -or $id -eq $token) {continue}
        $path=[IO.Path]::GetFullPath((Join-Path $packRoot $id.Substring(5)))
        if (-not $path.StartsWith($packRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) {throw 'Unsafe resource pack path.'}
        if (Test-Path -LiteralPath $path -PathType Container) {
            $folderAnimations=@(Get-ChildItem -LiteralPath $path -Recurse -File -Filter '*.animation.json')
            if ($folderAnimations.Count) {throw 'Folder-based animation packs are not supported. Convert that pack to ZIP before applying repairs.'}
        }
        if (Test-Path -LiteralPath $path -PathType Leaf) {$sources+=@($path)}
    }
    Write-Host '[COBBLEVERSE] Scanning installed animations (this can take a minute)...'
    $animationFiles=[ordered]@{};$animationGroups=[ordered]@{}
    foreach ($path in $sources) {
        $z=[IO.Compression.ZipFile]::OpenRead($path)
        try {
            foreach ($entry in $z.Entries) {
                if ($entry.FullName -notmatch '^assets/[^/]+/bedrock/pokemon/animations/.+\.animation\.json$') {continue}
                $data=Read-ZipJson $z $entry.FullName
                if (-not $data.animations) {continue}
                if (-not $animationFiles.Contains($entry.FullName)) {
                    $animationFiles[$entry.FullName]=@{Data=$null;Animations=[ordered]@{}}
                }
                $file=$animationFiles[$entry.FullName]
                $group=[IO.Path]::GetFileName($entry.FullName)
                if (-not $animationGroups.Contains($group)) {$animationGroups[$group]=[ordered]@{}}
                # Last pack wins for existing names; restore only names it dropped.
                foreach ($prop in $data.animations.PSObject.Properties) {
                    $file.Animations[$prop.Name]=$prop.Value
                    $animationGroups[$group][$prop.Name]=$prop.Value
                }
                $file.Data=$data
            }
        } finally {$z.Dispose()}
    }
    $repairs=[ordered]@{};$restoredCount=0
    foreach ($name in $animationFiles.Keys) {
        $file=$animationFiles[$name]
        # Cobblemon indexes groups by basename, even across different directories.
        # Fill every competing path so resource enumeration order cannot drop names.
        $group=[IO.Path]::GetFileName($name)
        foreach ($key in $animationGroups[$group].Keys) {
            if (-not $file.Animations.Contains($key)) {$file.Animations[$key]=$animationGroups[$group][$key]}
        }
        $lastNames=@($file.Data.animations.PSObject.Properties | ForEach-Object {$_.Name})
        $missing=@($file.Animations.Keys | Where-Object {$_ -cnotin $lastNames})
        if (-not $missing.Count) {continue}
        $restoredCount+=$missing.Count
        $file.Data.animations=$file.Animations
        $repairs[$name]=$file.Data
    }
    $fields=@($config.pack_overrides.PSObject.Properties | ForEach-Object {$_.Value})+@($config.default_overrides)
    foreach ($entry in $fields) {
        if (-not $entry) {continue}
        foreach ($field in @('title','description')) {
            $prop=$entry.PSObject.Properties[$field]
            if ($prop -and $prop.Value -is [string]) {
                try {$decoded=ConvertFrom-Json -InputObject $prop.Value -ErrorAction Stop} catch {$decoded=$prop.Value}
                $prop.Value=ConvertTo-Json -InputObject $decoded -Depth 50 -Compress
            }
        }
    }
    $config.default_packs=@($config.default_packs | Where-Object {$_ -ne $token})+@($token)
    $newConfig=ConvertTo-Json -InputObject $config -Depth 100
    $newPacks=@($packList | Where-Object {$_ -ne $token})+@($token)
    $line='resourcePacks:'+(ConvertTo-Json -InputObject $newPacks -Compress)
    $newOptions=$optionsText.Substring(0,$match.Index)+$line+$optionsText.Substring($match.Index+$match.Length)
    $stage=Join-Path $profile ('.cobbleverse-client-repair-'+[guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $stage | Out-Null
    $newPack=Join-Path $stage 'repair-pack.tmp'
    $z=[IO.Compression.ZipFile]::Open($newPack,[IO.Compression.ZipArchiveMode]::Create)
    try {
        $packMeta=[ordered]@{pack=[ordered]@{pack_format=34;description='Cobbleverse animation compatibility repairs'}}
        Write-ZipText $z 'pack.mcmeta' (ConvertTo-Json -InputObject $packMeta -Depth 10)
        foreach ($name in $repairs.Keys) {
            Write-ZipText $z $name (ConvertTo-Json -InputObject $repairs[$name] -Depth 100)
        }
    } finally {$z.Dispose()}
    $addon=Join-Path $stage $addonName
    if ($needAddon) {
        if ($LocalHotfixPath) {Copy-Item -LiteralPath $LocalHotfixPath -Destination $addon}
        else {
            Write-Host '[COBBLEVERSE] Downloading held-item client repair (3 KB)...'
            Invoke-WebRequest -UseBasicParsing -Uri ('https://github.com/ApriL2-7/COBBLEVERSE-1.8-Snapshot-Custom/releases/download/v2026.10.27-clientfix1/'+$addonName) -OutFile $addon
        }
        if ((Get-RepairHash $addon) -ne $expected) {throw 'Client callback repair hash mismatch. Installed files unchanged.'}
    }
    $packDest=Join-Path $packRoot $repairName
    $packChanged=(-not (Test-Path -LiteralPath $packDest))
    if (-not $packChanged) {$packChanged=(Get-RepairHash $newPack) -ne (Get-RepairHash $packDest)}
    if (-not $needAddon -and -not $packChanged -and $newConfig -ceq $configText -and $newOptions -ceq $optionsText) {
        Remove-Item -LiteralPath $newPack -Force
        [IO.Directory]::Delete($stage)
        Write-Host '[COBBLEVERSE] Client repairs are already installed.' -ForegroundColor Green
        exit 0
    }
    Copy-Item -LiteralPath $options -Destination (Join-Path $stage 'options.txt')
    Copy-Item -LiteralPath $configPath -Destination (Join-Path $stage 'resourcepackoverrides.json')
    $hadPack=Test-Path -LiteralPath $packDest
    if ($hadPack) {Copy-Item -LiteralPath $packDest -Destination (Join-Path $stage $repairName)}
    $addonDest=Join-Path $mods $addonName
    if ($needAddon -and (Test-Path -LiteralPath $addonDest)) {throw 'Unexpected callback repair destination; refusing overwrite.'}
    try {
        if ($needAddon) {Copy-Item -LiteralPath $addon -Destination $addonDest}
        Copy-Item -LiteralPath $newPack -Destination $packDest
        [IO.File]::WriteAllText($configPath,$newConfig,$utf8)
        [IO.File]::WriteAllText($options,$newOptions,$utf8)
    } catch {
        Copy-Item -LiteralPath (Join-Path $stage 'options.txt') -Destination $options
        Copy-Item -LiteralPath (Join-Path $stage 'resourcepackoverrides.json') -Destination $configPath
        if ($hadPack) {Copy-Item -LiteralPath (Join-Path $stage $repairName) -Destination $packDest}
        elseif (Test-Path -LiteralPath $packDest) {Remove-Item -LiteralPath $packDest -Force}
        if ($needAddon -and (Test-Path -LiteralPath $addonDest)) {Remove-Item -LiteralPath $addonDest -Force}
        throw
    }
    Remove-Item -LiteralPath $newPack -Force
    if (Test-Path -LiteralPath $addon) {Remove-Item -LiteralPath $addon -Force}
    Write-Host ('[COBBLEVERSE] Animation repairs: '+$repairs.Count+' files, '+$restoredCount+' restored names.') -ForegroundColor Green
    Write-Host '[COBBLEVERSE] Animation, resource configuration and held-item callback repairs installed.' -ForegroundColor Green
    Write-Host ('[COBBLEVERSE] Original settings backup: '+$stage)
    exit 0
} catch {
    Write-Host ('[COBBLEVERSE] Client repairs stopped: '+$_.Exception.Message) -ForegroundColor Red
    exit 1
}
