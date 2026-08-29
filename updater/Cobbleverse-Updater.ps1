param(
    [string]$ProfilePath = "",
    [string]$Repository = "ApriL2-7/COBBLEVERSE-1.8-Snapshot-Custom",
    [string]$ProfilesRoot = "",
    [string]$LocalReleaseRoot = "",
    [switch]$Yes,
    [switch]$CheckOnly
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$BaselineVersion = "2026.08.29.1"
$StateFileName = "cobbleverse-pack-state.json"
$GuardFileName = "cobbleverse-client-pack-guard-2026.08.29.1.jar"
$AllowedPrefixes = @("mods/", "resourcepacks/")

function Write-Step([string]$Message) {
    Write-Host "[COBBLEVERSE] $Message" -ForegroundColor Cyan
}

function Write-Ok([string]$Message) {
    Write-Host "[COBBLEVERSE] $Message" -ForegroundColor Green
}

function Get-FullPath([string]$Path) {
    return [IO.Path]::GetFullPath($Path)
}

function Test-IsUnder([string]$Path, [string]$Root) {
    $full = Get-FullPath $Path
    $rootFull = (Get-FullPath $Root).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    return $full.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)
}

function Resolve-Profile([string]$Requested, [string]$Root) {
    if (-not $Root) {
        $Root = Join-Path $env:APPDATA "ModrinthApp\profiles"
    }
    $Root = Get-FullPath $Root

    if ($Requested) {
        $candidate = $Requested.Trim().Trim('"')
    } else {
        $preferred = Join-Path $Root "COBBLEVERSE 1.8 Snapshot Custom"
        if (Test-Path -LiteralPath $preferred -PathType Container) {
            $candidate = $preferred
        } else {
            $candidate = (Read-Host "Modrinth profile folder path").Trim().Trim('"')
        }
    }

    $resolved = Get-FullPath $candidate
    if (-not (Test-IsUnder $resolved $Root)) {
        throw "The target profile must be inside: $Root"
    }
    if (-not (Test-Path -LiteralPath $resolved -PathType Container)) {
        throw "Profile folder does not exist: $resolved"
    }
    if (-not (Test-Path -LiteralPath (Join-Path $resolved "mods") -PathType Container)) {
        throw "The selected folder does not look like a Minecraft profile: $resolved"
    }
    return $resolved
}

function Assert-RelativeFilePath([string]$RelativePath) {
    if ([string]::IsNullOrWhiteSpace($RelativePath)) {
        throw "Patch contains an empty path."
    }
    $normalized = $RelativePath.Replace('\', '/')
    if ($normalized.StartsWith('/') -or [IO.Path]::IsPathRooted($normalized)) {
        throw "Absolute patch path rejected: $RelativePath"
    }
    if ($normalized.Split('/') -contains '..') {
        throw "Parent traversal rejected: $RelativePath"
    }
    $allowed = $false
    foreach ($prefix in $AllowedPrefixes) {
        if ($normalized.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
            $allowed = $true
            break
        }
    }
    if (-not $allowed) {
        throw "Patch path outside mods/resourcepacks rejected: $RelativePath"
    }
    return $normalized
}

function Get-FileSha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Read-State([string]$Profile) {
    $statePath = Join-Path $Profile $StateFileName
    if (Test-Path -LiteralPath $statePath -PathType Leaf) {
        $state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $state.version) {
            throw "Invalid state file: $statePath"
        }
        return [pscustomobject]@{ Version = [string]$state.version; Path = $statePath; Existed = $true }
    }

    $guard = Join-Path $Profile ("mods\" + $GuardFileName)
    if (Test-Path -LiteralPath $guard -PathType Leaf) {
        return [pscustomobject]@{ Version = $BaselineVersion; Path = $statePath; Existed = $false }
    }

    throw "Cannot identify the installed pack version. Install the current full client package once, then run this updater."
}

function Save-State([string]$Path, [string]$Version, [string]$Repo) {
    $state = [ordered]@{
        schemaVersion = 1
        version = $Version
        repository = $Repo
        updatedAt = (Get-Date).ToString('o')
    }
    [IO.File]::WriteAllText($Path, ($state | ConvertTo-Json -Depth 4), [Text.UTF8Encoding]::new($false))
}

function Download-File([string]$Url, [string]$Destination) {
    $headers = @{
        "Accept" = "application/vnd.github+json"
        "User-Agent" = "Cobbleverse-Updater"
        "X-GitHub-Api-Version" = "2022-11-28"
    }
    Invoke-WebRequest -UseBasicParsing -Headers $headers -Uri $Url -OutFile $Destination
}

function Get-PatchDescriptors([string]$Repo, [string]$LocalRoot, [string]$CacheRoot) {
    $result = [Collections.Generic.List[object]]::new()

    if ($LocalRoot) {
        $root = Get-FullPath $LocalRoot
        foreach ($manifestFile in Get-ChildItem -LiteralPath $root -Filter "cobbleverse-patch.json" -File -Recurse) {
            $manifest = Get-Content -LiteralPath $manifestFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            $patchPath = Join-Path $manifestFile.DirectoryName ([string]$manifest.patchAsset)
            $result.Add([pscustomobject]@{
                Manifest = $manifest
                ManifestPath = $manifestFile.FullName
                PatchSource = $patchPath
                IsLocal = $true
            })
        }
        return @($result)
    }

    $apiUrl = "https://api.github.com/repos/$Repo/releases?per_page=100"
    $headers = @{
        "Accept" = "application/vnd.github+json"
        "User-Agent" = "Cobbleverse-Updater"
        "X-GitHub-Api-Version" = "2022-11-28"
    }
    $releases = @(Invoke-RestMethod -Headers $headers -Uri $apiUrl)
    foreach ($release in ($releases | Where-Object { -not $_.draft -and -not $_.prerelease } | Sort-Object published_at)) {
        $manifestAsset = @($release.assets | Where-Object { $_.name -eq "cobbleverse-patch.json" }) | Select-Object -First 1
        if (-not $manifestAsset) {
            continue
        }
        $manifestPath = Join-Path $CacheRoot ("manifest-" + $release.id + ".json")
        Download-File ([string]$manifestAsset.browser_download_url) $manifestPath
        $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $patchAsset = @($release.assets | Where-Object { $_.name -eq [string]$manifest.patchAsset }) | Select-Object -First 1
        if (-not $patchAsset) {
            throw "Release $($release.tag_name) is missing asset: $($manifest.patchAsset)"
        }
        $result.Add([pscustomobject]@{
            Manifest = $manifest
            ManifestPath = $manifestPath
            PatchSource = [string]$patchAsset.browser_download_url
            IsLocal = $false
        })
    }
    return @($result)
}

function Get-UpdateChain([object[]]$Descriptors, [string]$InstalledVersion) {
    $chain = [Collections.Generic.List[object]]::new()
    $cursor = $InstalledVersion
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

    while ($true) {
        if (-not $seen.Add($cursor)) {
            throw "Patch version cycle detected at $cursor"
        }
        $next = @($Descriptors | Where-Object { [string]$_.Manifest.fromVersion -eq $cursor })
        if ($next.Count -eq 0) {
            break
        }
        if ($next.Count -gt 1) {
            throw "Multiple patches start from version $cursor. Release chain is ambiguous."
        }
        $descriptor = $next[0]
        if (-not $descriptor.Manifest.toVersion) {
            throw "Patch manifest has no toVersion: $($descriptor.ManifestPath)"
        }
        $chain.Add($descriptor)
        $cursor = [string]$descriptor.Manifest.toVersion
    }
    return @($chain)
}

function Confirm-Update([string]$From, [string]$To, [int]$PatchCount, [long]$Bytes, [switch]$AssumeYes) {
    if ($AssumeYes) {
        return $true
    }
    Add-Type -AssemblyName System.Windows.Forms
    $mb = [Math]::Round($Bytes / 1MB, 1)
    $message = "새 Cobbleverse 패치가 있습니다.`n`n현재: $From`n최신: $To`n패치: $PatchCount개 / 약 $mb MB`n`n지금 업데이트하시겠습니까?"
    $answer = [Windows.Forms.MessageBox]::Show(
        $message,
        "Cobbleverse 업데이트",
        [Windows.Forms.MessageBoxButtons]::YesNo,
        [Windows.Forms.MessageBoxIcon]::Information
    )
    return $answer -eq [Windows.Forms.DialogResult]::Yes
}

function Test-GameNotRunning([string]$Profile) {
    $running = @(Get-CimInstance Win32_Process -Filter "Name='javaw.exe' OR Name='java.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -and $_.CommandLine.IndexOf($Profile, [StringComparison]::OrdinalIgnoreCase) -ge 0 })
    if ($running.Count -gt 0) {
        throw "Minecraft is currently using this profile. Close the game completely and try again."
    }
}

function Prepare-Patches([object[]]$Chain, [string]$WorkRoot) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $prepared = [Collections.Generic.List[object]]::new()
    $index = 0

    foreach ($descriptor in $Chain) {
        $manifest = $descriptor.Manifest
        if ([int]$manifest.schemaVersion -ne 1) {
            throw "Unsupported patch schema: $($manifest.schemaVersion)"
        }
        $index++
        $zipPath = Join-Path $WorkRoot ("patch-$index.zip")
        if ($descriptor.IsLocal) {
            Copy-Item -LiteralPath $descriptor.PatchSource -Destination $zipPath -Force
        } else {
            Download-File $descriptor.PatchSource $zipPath
        }
        if ((Get-Item -LiteralPath $zipPath).Length -ne [long]$manifest.patchSize) {
            throw "Patch size mismatch for $($manifest.toVersion)"
        }
        if ((Get-FileSha256 $zipPath) -ne ([string]$manifest.patchSha256).ToUpperInvariant()) {
            throw "Patch SHA-256 mismatch for $($manifest.toVersion)"
        }

        $expected = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($file in @($manifest.files)) {
            $relative = Assert-RelativeFilePath ([string]$file.path)
            if (-not $expected.Add(("payload/" + $relative))) {
                throw "Duplicate patch file: $relative"
            }
        }
        foreach ($deleted in @($manifest.delete)) {
            $null = Assert-RelativeFilePath ([string]$deleted)
        }

        $archive = [IO.Compression.ZipFile]::OpenRead($zipPath)
        try {
            $actual = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
            foreach ($entry in $archive.Entries) {
                $name = $entry.FullName.Replace('\', '/')
                if ($name.EndsWith('/')) {
                    continue
                }
                if (-not $name.StartsWith('payload/', [StringComparison]::OrdinalIgnoreCase) -or $name.Split('/') -contains '..') {
                    throw "Unsafe ZIP entry rejected: $name"
                }
                if (-not $actual.Add($name)) {
                    throw "Duplicate ZIP entry rejected: $name"
                }
            }
            if (-not $actual.SetEquals($expected)) {
                throw "ZIP contents do not match the patch manifest for $($manifest.toVersion)"
            }
        }
        finally {
            $archive.Dispose()
        }

        $extractRoot = Join-Path $WorkRoot ("extract-$index")
        [IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $extractRoot)
        foreach ($file in @($manifest.files)) {
            $relative = Assert-RelativeFilePath ([string]$file.path)
            $staged = Join-Path (Join-Path $extractRoot 'payload') ($relative.Replace('/', [IO.Path]::DirectorySeparatorChar))
            if (-not (Test-Path -LiteralPath $staged -PathType Leaf)) {
                throw "Extracted patch file is missing: $relative"
            }
            if ((Get-Item -LiteralPath $staged).Length -ne [long]$file.size) {
                throw "Patched file size mismatch: $relative"
            }
            if ((Get-FileSha256 $staged) -ne ([string]$file.sha256).ToUpperInvariant()) {
                throw "Patched file SHA-256 mismatch: $relative"
            }
        }
        $prepared.Add([pscustomobject]@{ Manifest = $manifest; ExtractRoot = $extractRoot })
    }
    return @($prepared)
}

function Apply-PreparedPatches([object[]]$Prepared, [string]$Profile, [object]$OriginalState) {
    $operationId = [Guid]::NewGuid().ToString('N')
    $backupRoot = Join-Path $Profile (".cobbleverse-update-backup-" + $operationId)
    $touched = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($item in $Prepared) {
        foreach ($file in @($item.Manifest.files)) {
            $null = $touched.Add((Assert-RelativeFilePath ([string]$file.path)))
        }
        foreach ($deleted in @($item.Manifest.delete)) {
            $null = $touched.Add((Assert-RelativeFilePath ([string]$deleted)))
        }
    }

    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
    $originalFiles = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($relative in $touched) {
        $target = Join-Path $Profile ($relative.Replace('/', [IO.Path]::DirectorySeparatorChar))
        if (-not (Test-IsUnder $target $Profile)) {
            throw "Resolved target escaped profile: $relative"
        }
        if (Test-Path -LiteralPath $target -PathType Leaf) {
            $backup = Join-Path $backupRoot ($relative.Replace('/', [IO.Path]::DirectorySeparatorChar))
            New-Item -ItemType Directory -Path (Split-Path -Parent $backup) -Force | Out-Null
            Copy-Item -LiteralPath $target -Destination $backup -Force
            $null = $originalFiles.Add($relative)
        }
    }

    try {
        foreach ($item in $Prepared) {
            foreach ($relativeRaw in @($item.Manifest.delete)) {
                $relative = Assert-RelativeFilePath ([string]$relativeRaw)
                $target = Join-Path $Profile ($relative.Replace('/', [IO.Path]::DirectorySeparatorChar))
                if (Test-Path -LiteralPath $target -PathType Leaf) {
                    Remove-Item -LiteralPath $target -Force
                }
            }
            foreach ($file in @($item.Manifest.files)) {
                $relative = Assert-RelativeFilePath ([string]$file.path)
                $source = Join-Path (Join-Path $item.ExtractRoot 'payload') ($relative.Replace('/', [IO.Path]::DirectorySeparatorChar))
                $target = Join-Path $Profile ($relative.Replace('/', [IO.Path]::DirectorySeparatorChar))
                New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
                $tempTarget = $target + '.cobbleverse-new-' + $operationId
                Copy-Item -LiteralPath $source -Destination $tempTarget -Force
                Move-Item -LiteralPath $tempTarget -Destination $target -Force
            }
            Save-State $OriginalState.Path ([string]$item.Manifest.toVersion) $Repository
        }
    }
    catch {
        Write-Host "Update failed; restoring original files..." -ForegroundColor Yellow
        foreach ($relative in $touched) {
            $target = Join-Path $Profile ($relative.Replace('/', [IO.Path]::DirectorySeparatorChar))
            if (Test-Path -LiteralPath $target -PathType Leaf) {
                Remove-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
            }
            if ($originalFiles.Contains($relative)) {
                $backup = Join-Path $backupRoot ($relative.Replace('/', [IO.Path]::DirectorySeparatorChar))
                New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
                Copy-Item -LiteralPath $backup -Destination $target -Force
            }
        }
        if ($OriginalState.Existed) {
            Save-State $OriginalState.Path $OriginalState.Version $Repository
        } elseif (Test-Path -LiteralPath $OriginalState.Path -PathType Leaf) {
            Remove-Item -LiteralPath $OriginalState.Path -Force
        }
        throw
    }
    finally {
        if (Test-Path -LiteralPath $backupRoot -PathType Container) {
            Remove-Item -LiteralPath $backupRoot -Recurse -Force
        }
    }
}

$profile = Resolve-Profile $ProfilePath $ProfilesRoot
Test-GameNotRunning $profile
$state = Read-State $profile
Write-Step "Profile: $profile"
Write-Step "Installed version: $($state.Version)"

$workRoot = Join-Path ([IO.Path]::GetTempPath()) ("cobbleverse-updater-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $workRoot -Force | Out-Null
try {
    Write-Step "Checking published patches..."
    $descriptors = @(Get-PatchDescriptors $Repository $LocalReleaseRoot $workRoot)
    $chain = @(Get-UpdateChain $descriptors $state.Version)
    if ($chain.Count -eq 0) {
        Write-Ok "Already up to date."
        exit 0
    }

    $latest = [string]$chain[-1].Manifest.toVersion
    $downloadBytes = [long]0
    foreach ($item in $chain) {
        $downloadBytes += [long]$item.Manifest.patchSize
    }
    if ($CheckOnly) {
        Write-Host "UPDATE_AVAILABLE=$latest"
        exit 2
    }
    if (-not (Confirm-Update $state.Version $latest $chain.Count $downloadBytes -AssumeYes:$Yes)) {
        Write-Step "Update cancelled."
        exit 0
    }

    Write-Step "Downloading and verifying patches before changing any files..."
    $prepared = @(Prepare-Patches $chain $workRoot)
    Write-Step "Applying $($prepared.Count) patch(es)..."
    Apply-PreparedPatches $prepared $profile $state
    Write-Ok "Update complete: $latest"
}
finally {
    if (Test-Path -LiteralPath $workRoot -PathType Container) {
        Remove-Item -LiteralPath $workRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
