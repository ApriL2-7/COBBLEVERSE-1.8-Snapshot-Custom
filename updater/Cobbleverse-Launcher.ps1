param(
    [string]$Repository = "ApriL2-7/COBBLEVERSE-1.8-Snapshot-Custom"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$GuardFileName = "cobbleverse-client-pack-guard-2026.08.29.1.jar"
$StateFileName = "cobbleverse-pack-state.json"
$PreferredProfileName = "COBBLEVERSE 1.8 Snapshot Custom"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName Microsoft.VisualBasic

function Show-LauncherError([string]$Message) {
    [Windows.Forms.MessageBox]::Show(
        $Message,
        "Cobbleverse Updater",
        [Windows.Forms.MessageBoxButtons]::OK,
        [Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
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

    $typed = [Microsoft.VisualBasic.Interaction]::InputBox(
        "Paste the COBBLEVERSE profile path (Modrinth or CurseForge). Leave blank to browse.",
        "Cobbleverse Updater",
        ""
    )
    if (-not [string]::IsNullOrWhiteSpace($typed)) {
        $typed = $typed.Trim().Trim('"')
        if (-not (Test-LooksLikeProfile $typed)) {
            throw "The selected path is not a Minecraft profile with a mods folder:`n$typed"
        }
        return Get-FullPath $typed
    }

    $dialog = [Windows.Forms.FolderBrowserDialog]::new()
    $dialog.Description = "Select the COBBLEVERSE profile folder (Modrinth or CurseForge)"
    $dialog.ShowNewFolderButton = $false
    if ($roots.Count -gt 0) {
        $dialog.SelectedPath = $roots[0]
    }
    if ($dialog.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) {
        return $null
    }
    if (-not (Test-LooksLikeProfile $dialog.SelectedPath)) {
        throw "The selected folder is not a Minecraft profile with a mods folder:`n$($dialog.SelectedPath)"
    }
    return Get-FullPath $dialog.SelectedPath
}

function Download-RepoFile([string]$RelativePath, [string]$Destination) {
    $rawUrl = "https://raw.githubusercontent.com/{0}/main/{1}" -f $Repository, $RelativePath
    $commonHeaders = @{
        "User-Agent" = "Cobbleverse-Updater"
        "Cache-Control" = "no-cache"
        "Pragma" = "no-cache"
    }

    try {
        Invoke-WebRequest -UseBasicParsing -Headers $commonHeaders -Uri $rawUrl -OutFile $Destination
        return
    }
    catch {
        $rawError = $_.Exception.Message
    }

    $apiUrl = "https://api.github.com/repos/{0}/contents/{1}?ref=main" -f $Repository, $RelativePath
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
        throw "Could not download repository file: $RelativePath`r`n`r`nraw.githubusercontent.com: $rawError`r`nGitHub API: $($_.Exception.Message)"
    }
}

function Download-ReleaseAsset([string]$Url, [string]$Destination) {
    $headers = @{
        "User-Agent" = "Cobbleverse-Updater"
        "Cache-Control" = "no-cache"
        "Pragma" = "no-cache"
    }
    try {
        Invoke-WebRequest -UseBasicParsing -Headers $headers -Uri $Url -OutFile $Destination
    }
    catch {
        throw "Could not download patch asset:`r`n$Url`r`n`r`n$($_.Exception.Message)"
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

function Prepare-IndexedReleases([string]$Root) {
    $indexPath = Join-Path $Root "patch-index.json"
    $releaseRoot = Join-Path $Root "releases"
    New-Item -ItemType Directory -Path $releaseRoot -Force | Out-Null

    Download-RepoFile "updater/patch-index.json" $indexPath
    $index = Get-Content -LiteralPath $indexPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([int]$index.schemaVersion -ne 1) {
        throw "Unsupported patch index schema: $($index.schemaVersion)"
    }
    if ([string]$index.baselineVersion -ne "2026.08.29.1") {
        throw "Patch index baseline does not match this updater."
    }

    $patches = @($index.patches)
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

        Download-ReleaseAsset ("$baseUrl/$manifestAsset") $manifestPath
        $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ([string]$manifest.fromVersion -ne $fromVersion -or [string]$manifest.toVersion -ne $toVersion) {
            throw "Patch index version metadata does not match $manifestAsset for $tag."
        }
        if ([string]$manifest.patchAsset -ne $patchAsset) {
            throw "Patch index asset metadata does not match $manifestAsset for $tag."
        }

        Download-ReleaseAsset ("$baseUrl/$patchAsset") $patchPath
    }

    return $releaseRoot
}

$workRoot = Join-Path $env:TEMP ("Cobbleverse-Launcher-" + [Guid]::NewGuid().ToString('N'))
$bootstrapFile = Join-Path $workRoot "Cobbleverse-Bootstrap.ps1"
$updaterFile = Join-Path $workRoot "Cobbleverse-Updater.ps1"

try {
    $profile = Resolve-CobbleverseProfile
    if (-not $profile) {
        return
    }
    $profilesRoot = Split-Path -Parent $profile
    if (-not $profilesRoot) {
        throw "Could not determine the parent folder for the selected profile."
    }

    New-Item -ItemType Directory -Path $workRoot -Force | Out-Null
    Download-RepoFile "updater/Cobbleverse-Bootstrap.ps1" $bootstrapFile
    Download-RepoFile "updater/Cobbleverse-Updater.ps1" $updaterFile
    $releaseRoot = Prepare-IndexedReleases $workRoot

    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File $bootstrapFile -Gui -ProfilePath $profile -Repository $Repository
    if ($LASTEXITCODE -ne 0) {
        return
    }

    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File $updaterFile -Gui -ProfilePath $profile -ProfilesRoot $profilesRoot -Repository $Repository -LocalReleaseRoot $releaseRoot
} catch {
    $message = $_.Exception.Message
    if ([string]::IsNullOrWhiteSpace($message)) {
        $message = [string]$_
    }
    Show-LauncherError $message
} finally {
    Remove-Item -LiteralPath $workRoot -Recurse -Force -ErrorAction SilentlyContinue
}
