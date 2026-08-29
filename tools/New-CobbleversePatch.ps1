param(
    [Parameter(Mandatory = $true)]
    [string]$PayloadRoot,
    [Parameter(Mandatory = $true)]
    [string]$BaselineManifest,
    [Parameter(Mandatory = $true)]
    [string]$FromVersion,
    [Parameter(Mandatory = $true)]
    [string]$ToVersion,
    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory,
    [switch]$IncludeAllFiles
)

$ErrorActionPreference = "Stop"

function Assert-Version([string]$Value) {
    if ($Value -notmatch '^[0-9A-Za-z._-]+$') {
        throw "Invalid version: $Value"
    }
}

function Get-Sha([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Get-PayloadFiles([string]$Root) {
    $rootFull = [IO.Path]::GetFullPath($Root)
    $result = [Collections.Generic.List[object]]::new()
    foreach ($folder in @('mods', 'resourcepacks')) {
        $folderPath = Join-Path $rootFull $folder
        if (-not (Test-Path -LiteralPath $folderPath -PathType Container)) {
            throw "Payload folder is missing: $folderPath"
        }
        foreach ($file in Get-ChildItem -LiteralPath $folderPath -File -Recurse | Sort-Object FullName) {
            $relative = $file.FullName.Substring($rootFull.Length + 1).Replace('\', '/')
            $result.Add([pscustomobject]@{
                path = $relative
                size = [long]$file.Length
                sha256 = Get-Sha $file.FullName
                source = $file.FullName
            })
        }
    }
    return @($result)
}

Assert-Version $FromVersion
Assert-Version $ToVersion
if ($FromVersion -eq $ToVersion) {
    throw "FromVersion and ToVersion must differ."
}

$payload = [IO.Path]::GetFullPath($PayloadRoot)
$baselinePath = [IO.Path]::GetFullPath($BaselineManifest)
$output = [IO.Path]::GetFullPath($OutputDirectory)
$baseline = Get-Content -LiteralPath $baselinePath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($baseline.version -and [string]$baseline.version -ne $FromVersion) {
    throw "Baseline version '$($baseline.version)' does not match FromVersion '$FromVersion'."
}

$old = @{}
foreach ($file in @($baseline.files)) {
    $old[[string]$file.path] = $file
}
$currentFiles = Get-PayloadFiles $payload
$current = @{}
foreach ($file in $currentFiles) {
    $current[[string]$file.path] = $file
}

$changed = [Collections.Generic.List[object]]::new()
foreach ($file in $currentFiles) {
    if ($IncludeAllFiles) {
        $changed.Add($file)
        continue
    }

    $previous = $old[[string]$file.path]
    if (-not $previous -or [long]$previous.size -ne [long]$file.size -or
        ([string]$previous.sha256).ToUpperInvariant() -ne ([string]$file.sha256).ToUpperInvariant()) {
        $changed.Add($file)
    }
}
$deleted = [Collections.Generic.List[string]]::new()
foreach ($path in $old.Keys) {
    if (-not $current.ContainsKey($path)) {
        $deleted.Add([string]$path)
    }
}

New-Item -ItemType Directory -Path $output -Force | Out-Null
$work = Join-Path ([IO.Path]::GetTempPath()) ("cobbleverse-patch-builder-" + [Guid]::NewGuid().ToString('N'))
$packageRoot = Join-Path $work 'package'
New-Item -ItemType Directory -Path (Join-Path $packageRoot 'payload') -Force | Out-Null
try {
    foreach ($file in $changed) {
        $destination = Join-Path (Join-Path $packageRoot 'payload') ($file.path.Replace('/', [IO.Path]::DirectorySeparatorChar))
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
        Copy-Item -LiteralPath $file.source -Destination $destination -Force
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $safeVersion = $ToVersion.Replace('.', '-')
    $zipName = "cobbleverse-patch-$safeVersion.zip"
    $zipPath = Join-Path $output $zipName
    if (Test-Path -LiteralPath $zipPath -PathType Leaf) {
        Remove-Item -LiteralPath $zipPath -Force
    }
    [IO.Compression.ZipFile]::CreateFromDirectory(
        $packageRoot,
        $zipPath,
        [IO.Compression.CompressionLevel]::Optimal,
        $false
    )

    $manifestFiles = @($changed | ForEach-Object {
        [ordered]@{ path = $_.path; size = [long]$_.size; sha256 = $_.sha256 }
    })
    $patchManifest = [ordered]@{
        schemaVersion = 1
        fromVersion = $FromVersion
        toVersion = $ToVersion
        createdAt = (Get-Date).ToString('o')
        patchAsset = $zipName
        patchSize = (Get-Item -LiteralPath $zipPath).Length
        patchSha256 = Get-Sha $zipPath
        files = $manifestFiles
        delete = @($deleted | Sort-Object)
    }
    $patchManifestPath = Join-Path $output 'cobbleverse-patch.json'
    [IO.File]::WriteAllText($patchManifestPath, ($patchManifest | ConvertTo-Json -Depth 7), [Text.UTF8Encoding]::new($false))

    $nextBaseline = [ordered]@{
        schemaVersion = 1
        version = $ToVersion
        createdAt = (Get-Date).ToString('o')
        files = @($currentFiles | ForEach-Object {
            [ordered]@{ path = $_.path; size = [long]$_.size; sha256 = $_.sha256 }
        })
    }
    $nextBaselinePath = Join-Path $output ("baseline-" + $ToVersion + ".json")
    [IO.File]::WriteAllText($nextBaselinePath, ($nextBaseline | ConvertTo-Json -Depth 7), [Text.UTF8Encoding]::new($false))

    Write-Host "PATCH_READY"
    Write-Host "From: $FromVersion"
    Write-Host "To: $ToVersion"
    Write-Host "Mode: $(if ($IncludeAllFiles) { 'FULL_REPAIR' } else { 'INCREMENTAL' })"
    Write-Host "Included: $($changed.Count)"
    Write-Host "Deleted: $($deleted.Count)"
    Write-Host "ZIP: $zipPath"
    Write-Host "Manifest: $patchManifestPath"
    Write-Host "Next baseline: $nextBaselinePath"
}
finally {
    if (Test-Path -LiteralPath $work -PathType Container) {
        Remove-Item -LiteralPath $work -Recurse -Force
    }
}
