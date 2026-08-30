param(
    [string]$Repository = "ApriL2-7/COBBLEVERSE-1.8-Snapshot-Custom"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$GuardFileName = "cobbleverse-client-pack-guard-2026.08.29.1.jar"
$StateFileName = "cobbleverse-pack-state.json"
$PreferredProfileName = "COBBLEVERSE 1.8 Snapshot Custom"

function Write-ConsoleProgress([string]$Phase, [string]$Message, [int]$Percent, [switch]$Complete) {
    $Percent = [Math]::Max(0, [Math]::Min(100, $Percent))
    $width = 30
    $filled = [int][Math]::Floor($width * $Percent / 100.0)
    $bar = ('#' * $filled) + ('-' * ($width - $filled))
    $line = ("[{0}] [{1}] {2,3}%  {3}" -f $Phase.ToUpperInvariant(), $bar, $Percent, $Message)
    if ($line.Length -lt 112) { $line = $line.PadRight(112) }
    Write-Host ("`r" + $line) -NoNewline -ForegroundColor Cyan
    if ($Complete) { Write-Host "" }
}

function Show-LauncherError([string]$Message) {
    Write-Host ""
    Write-Host "[COBBLEVERSE] $Message" -ForegroundColor Red
    Write-Host ""
}

function Get-FullPath([string]$Path) {
    return [IO.Path]::GetFullPath($Path)
}

function Test-LooksLikeProfile([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $false
    }
    try {
        $full = Get-FullPath ($Path.Trim().Trim('"'))
        return (Test-Path -LiteralPath $full -PathType Container) -and
            (Test-Path -LiteralPath (Join-Path $full "mods") -PathType Container)
    } catch {
        return $false
    }
}

function Get-CandidateRoots {
    $roots = [Collections.Generic.List[string]]::new()
    $candidates = @(
        (Join-Path $env:APPDATA "ModrinthApp\profiles"),
        (Join-Path $env:USERPROFILE "curseforge\minecraft\Instances"),
        (Join-Path $env:USERPROFILE "Documents\Curse\Minecraft\Instances")
    )

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Container)) {
            $full = Get-FullPath $candidate
            if (-not ($roots | Where-Object { $_ -eq $full })) {
                $roots.Add($full)
            }
        }
    }
    return @($roots)
}

function Resolve-CobbleverseProfile {
    $roots = @(Get-CandidateRoots)
    $matches = [Collections.Generic.List[object]]::new()

    foreach ($root in $roots) {
        $named = Join-Path $root $PreferredProfileName
        if (Test-LooksLikeProfile $named) {
            $matches.Add((Get-Item -LiteralPath $named))
        }

        foreach ($dir in @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue)) {
            $guardPath = Join-Path $dir.FullName ("mods\" + $GuardFileName)
            $statePath = Join-Path $dir.FullName $StateFileName
            if ((Test-Path -LiteralPath $guardPath -PathType Leaf) -or
                (Test-Path -LiteralPath $statePath -PathType Leaf)) {
                $matches.Add($dir)
            }
        }
    }

    $unique = [Collections.Generic.List[object]]::new()
    $seen = @{}
    foreach ($match in $matches) {
        $full = Get-FullPath $match.FullName
        if (-not $seen.ContainsKey($full)) {
            $seen[$full] = $true
            $unique.Add($match)
        }
    }

    $preferred = @($unique | Where-Object { $_.Name -eq $PreferredProfileName })
    if ($preferred.Count -eq 1) {
        return Get-FullPath $preferred[0].FullName
    }
    if ($unique.Count -eq 1) {
        return Get-FullPath $unique[0].FullName
    }

    Write-Host ""
    if ($unique.Count -gt 1) {
        Write-Host "[COBBLEVERSE] Multiple candidate profiles were found:" -ForegroundColor Yellow
        foreach ($item in $unique) { Write-Host ("  - " + $item.FullName) }
    }
    $typed = (Read-Host "Enter the COBBLEVERSE profile folder path (blank to cancel)").Trim().Trim('"')
    if ([string]::IsNullOrWhiteSpace($typed)) {
        return $null
    }
    if (-not (Test-LooksLikeProfile $typed)) {
        throw "The selected path is not a Minecraft profile with a mods folder:`n$typed"
    }
    return Get-FullPath $typed
}

function Download-RepoFile([string]$RelativePath, [string]$Destination) {
    $cacheKey = [Guid]::NewGuid().ToString('N')
    $apiUrl = "https://api.github.com/repos/{0}/contents/{1}?ref=main&cache={2}" -f $Repository, $RelativePath, $cacheKey
    $apiHeaders = @{
        "Accept" = "application/vnd.github.raw+json"
        "User-Agent" = "Cobbleverse-Updater"
        "X-GitHub-Api-Version" = "2022-11-28"
        "Cache-Control" = "no-cache"
    }

    try {
        Invoke-WebRequest -UseBasicParsing -Headers $apiHeaders -Uri $apiUrl -OutFile $Destination
        return
    }
    catch {
        $apiError = $_.Exception.Message
    }

    $rawUrl = "https://raw.githubusercontent.com/{0}/main/{1}?cache={2}" -f $Repository, $RelativePath, $cacheKey
    $rawHeaders = @{
        "User-Agent" = "Cobbleverse-Updater"
        "Cache-Control" = "no-cache"
        "Pragma" = "no-cache"
    }

    try {
        Invoke-WebRequest -UseBasicParsing -Headers $rawHeaders -Uri $rawUrl -OutFile $Destination
        return
    }
    catch {
        throw "Could not download repository file: $RelativePath`r`n`r`nGitHub API: $apiError`r`nraw.githubusercontent.com: $($_.Exception.Message)"
    }
}

function Normalize-WindowsPowerShellScript([string]$Path) {
    $utf8NoBom = [Text.UTF8Encoding]::new($false)
    $utf8Bom = [Text.UTF8Encoding]::new($true)
    $text = [IO.File]::ReadAllText($Path, $utf8NoBom)
    [IO.File]::WriteAllText($Path, $text, $utf8Bom)
}

function Get-InstalledVersionHint([string]$Profile) {
    $statePath = Join-Path $Profile $StateFileName
    if (Test-Path -LiteralPath $statePath -PathType Leaf) {
        $state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not [string]::IsNullOrWhiteSpace([string]$state.version)) {
            return [string]$state.version
        }
    }
    return "2026.08.29.1"
}

function Download-ReleaseAsset([string]$Url, [string]$Destination, [int]$StartPercent, [int]$EndPercent, [string]$Label) {
    $response = $null
    $inputStream = $null
    $outputStream = $null
    try {
        $request = [Net.HttpWebRequest]::Create($Url)
        $request.UserAgent = "Cobbleverse-Updater"
        $request.AllowAutoRedirect = $true
        $request.Headers["Cache-Control"] = "no-cache"
        $response = $request.GetResponse()
        $total = [long]$response.ContentLength
        $inputStream = $response.GetResponseStream()
        $outputStream = [IO.File]::Open($Destination, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $buffer = New-Object byte[] (256KB)
        $received = [long]0
        $lastShown = -1
        while (($read = $inputStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $outputStream.Write($buffer, 0, $read)
            $received += $read
            $part = if ($total -gt 0) { [int][Math]::Floor(100.0 * $received / $total) } else { 0 }
            $overall = $StartPercent + [int][Math]::Floor(($EndPercent - $StartPercent) * $part / 100.0)
            if ($overall -ne $lastShown) {
                $sizeText = if ($total -gt 0) { "{0:N1}/{1:N1} MB" -f ($received / 1MB), ($total / 1MB) } else { "{0:N1} MB" -f ($received / 1MB) }
                Write-ConsoleProgress "DOWNLOAD" "$Label  $sizeText" $overall
                $lastShown = $overall
            }
        }
        Write-ConsoleProgress "DOWNLOAD" "$Label  complete" $EndPercent
    }
    catch {
        Remove-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue
        throw "Could not download patch asset:`r`n$Url`r`n`r`n$($_.Exception.Message)"
    }
    finally {
        if ($outputStream) { $outputStream.Dispose() }
        if ($inputStream) { $inputStream.Dispose() }
        if ($response) { $response.Dispose() }
    }
}

function Assert-SafeAssetName([string]$Name) {
    if ([string]::IsNullOrWhiteSpace($Name)) {
        throw "Patch index contains an empty asset name."
    }
    if ($Name.Contains('/') -or $Name.Contains('\') -or $Name -eq '.' -or $Name -eq '..') {
        throw "Unsafe patch asset name rejected: $Name"
    }
}

function Prepare-IndexedReleases([string]$Root, [string]$InstalledVersion) {
    $indexPath = Join-Path $Root "patch-index.json"
    $releaseRoot = Join-Path $Root "releases"
    New-Item -ItemType Directory -Path $releaseRoot -Force | Out-Null

    Write-ConsoleProgress "DOWNLOAD" "Reading patch index" 0
    Download-RepoFile "updater/patch-index.json" $indexPath
    $index = Get-Content -LiteralPath $indexPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([int]$index.schemaVersion -ne 1) {
        throw "Unsupported patch index schema: $($index.schemaVersion)"
    }
    if ([string]$index.baselineVersion -ne "2026.08.29.1") {
        throw "Patch index baseline does not match this updater."
    }

    $allPatches = @($index.patches)
    $selected = [Collections.Generic.List[object]]::new()
    $cursor = $InstalledVersion
    $chainSeen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    while ($true) {
        if (-not $chainSeen.Add($cursor)) {
            throw "Patch index contains a version cycle at $cursor."
        }
        $next = @($allPatches | Where-Object { [string]$_.fromVersion -eq $cursor })
        if ($next.Count -eq 0) { break }
        if ($next.Count -gt 1) {
            throw "Patch index contains multiple patches starting from $cursor."
        }
        $selected.Add($next[0])
        $cursor = [string]$next[0].toVersion
    }

    $knownVersions = @([string]$index.baselineVersion) + @($allPatches | ForEach-Object { [string]$_.toVersion })
    if ($knownVersions -notcontains $InstalledVersion) {
        throw "Installed version is not present in the patch index: $InstalledVersion"
    }

    $patches = @($selected)
    if ($patches.Count -eq 0) {
        Write-ConsoleProgress "DOWNLOAD" "No patch downloads required" 100 -Complete
        return $releaseRoot
    }
    $seenFrom = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $i = 0
    foreach ($entry in $patches) {
        $i++
        $tag = [string]$entry.tag
        $fromVersion = [string]$entry.fromVersion
        $toVersion = [string]$entry.toVersion
        $manifestAsset = [string]$entry.manifestAsset
        $patchAsset = [string]$entry.patchAsset

        if ([string]::IsNullOrWhiteSpace($tag) -or $tag -notmatch '^v[0-9A-Za-z._-]+$') {
            throw "Invalid patch tag in index: $tag"
        }
        if ([string]::IsNullOrWhiteSpace($fromVersion) -or [string]::IsNullOrWhiteSpace($toVersion)) {
            throw "Patch index entry $i is missing version information."
        }
        if (-not $seenFrom.Add($fromVersion)) {
            throw "Patch index contains multiple patches starting from $fromVersion."
        }
        Assert-SafeAssetName $manifestAsset
        Assert-SafeAssetName $patchAsset

        $entryRoot = Join-Path $releaseRoot ("release-{0:D3}" -f $i)
        New-Item -ItemType Directory -Path $entryRoot -Force | Out-Null
        $manifestPath = Join-Path $entryRoot $manifestAsset
        $patchPath = Join-Path $entryRoot $patchAsset
        $baseUrl = "https://github.com/{0}/releases/download/{1}" -f $Repository, $tag

        $segmentStart = if ($patches.Count -gt 0) { [int][Math]::Floor(100.0 * ($i - 1) / $patches.Count) } else { 0 }
        $segmentEnd = if ($patches.Count -gt 0) { [int][Math]::Floor(100.0 * $i / $patches.Count) } else { 100 }
        Write-ConsoleProgress "DOWNLOAD" "Patch $i/$($patches.Count) manifest" $segmentStart
        Download-ReleaseAsset ("$baseUrl/$manifestAsset") $manifestPath $segmentStart $segmentStart ("Patch {0}/{1} manifest" -f $i, $patches.Count)
        $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ([string]$manifest.fromVersion -ne $fromVersion -or [string]$manifest.toVersion -ne $toVersion) {
            throw "Patch index version metadata does not match $manifestAsset for $tag."
        }
        if ([string]$manifest.patchAsset -ne $patchAsset) {
            throw "Patch index asset metadata does not match $manifestAsset for $tag."
        }

        Download-ReleaseAsset ("$baseUrl/$patchAsset") $patchPath $segmentStart $segmentEnd ("Patch {0}/{1}  {2}" -f $i, $patches.Count, $toVersion)
    }

    Write-ConsoleProgress "DOWNLOAD" "All patch files downloaded" 100 -Complete

    return $releaseRoot
}

$workRoot = Join-Path $env:TEMP ("Cobbleverse-Launcher-" + [Guid]::NewGuid().ToString('N'))
$bootstrapFile = Join-Path $workRoot "Cobbleverse-Bootstrap.ps1"
$updaterFile = Join-Path $workRoot "Cobbleverse-Updater.ps1"
$exitCode = 0

try {
    Write-Host ""
    Write-Host "==============================================================" -ForegroundColor DarkCyan
    Write-Host "              COBBLEVERSE CLIENT UPDATER" -ForegroundColor Cyan
    Write-Host "==============================================================" -ForegroundColor DarkCyan
    Write-Host ""
    Write-ConsoleProgress "START" "Finding the Minecraft profile" 0
    $profile = Resolve-CobbleverseProfile
    if (-not $profile) {
        return
    }
    $profilesRoot = Split-Path -Parent $profile
    if (-not $profilesRoot) {
        throw "Could not determine the parent folder for the selected profile."
    }
    Write-ConsoleProgress "START" "Profile found: $(Split-Path $profile -Leaf)" 100 -Complete

    New-Item -ItemType Directory -Path $workRoot -Force | Out-Null
    Write-ConsoleProgress "SETUP" "Downloading updater components" 10
    Download-RepoFile "updater/Cobbleverse-Bootstrap.ps1" $bootstrapFile
    Write-ConsoleProgress "SETUP" "Bootstrap ready" 45
    Download-RepoFile "updater/Cobbleverse-Updater.ps1" $updaterFile
    Normalize-WindowsPowerShellScript $bootstrapFile
    Normalize-WindowsPowerShellScript $updaterFile
    Write-ConsoleProgress "SETUP" "Updater components ready" 100 -Complete
    $installedVersion = Get-InstalledVersionHint $profile
    Write-Host ("[COBBLEVERSE] Installed version hint: {0}" -f $installedVersion) -ForegroundColor DarkGray
    $releaseRoot = Prepare-IndexedReleases $workRoot $installedVersion

    Write-Host ""
    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $bootstrapFile -ProfilePath $profile -Repository $Repository
    if ($LASTEXITCODE -ne 0) {
        throw "Existing installation verification failed with exit code $LASTEXITCODE."
    }

    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $updaterFile -Yes -ProfilePath $profile -ProfilesRoot $profilesRoot -Repository $Repository -LocalReleaseRoot $releaseRoot
    if ($LASTEXITCODE -ne 0) {
        throw "The updater stopped with exit code $LASTEXITCODE."
    }
    Write-Host ""
    Write-Host "[COBBLEVERSE] Finished successfully." -ForegroundColor Green
} catch {
    $exitCode = 1
    $message = $_.Exception.Message
    if ([string]::IsNullOrWhiteSpace($message)) {
        $message = [string]$_
    }
    Show-LauncherError $message
} finally {
    Remove-Item -LiteralPath $workRoot -Recurse -Force -ErrorAction SilentlyContinue
}

exit $exitCode
