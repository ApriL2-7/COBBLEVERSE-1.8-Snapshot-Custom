$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName Microsoft.VisualBasic
[Windows.Forms.Application]::EnableVisualStyles()

$Repository = 'ApriL2-7/COBBLEVERSE-1.8-Snapshot-Custom'
$TempRoot = Join-Path ([IO.Path]::GetTempPath()) ('cobbleverse-patch-gui-' + [Guid]::NewGuid().ToString('N'))

function Show-Error([string]$Message) {
    [Windows.Forms.MessageBox]::Show(
        $Message,
        'Cobbleverse Patch Builder',
        [Windows.Forms.MessageBoxButtons]::OK,
        [Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
}

function Show-Info([string]$Message) {
    [Windows.Forms.MessageBox]::Show(
        $Message,
        'Cobbleverse Patch Builder',
        [Windows.Forms.MessageBoxButtons]::OK,
        [Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null
}

function Select-Folder([string]$Description) {
    $dialog = [Windows.Forms.FolderBrowserDialog]::new()
    $dialog.Description = $Description
    $dialog.ShowNewFolderButton = $false
    if ($dialog.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) {
        return $null
    }
    return [IO.Path]::GetFullPath($dialog.SelectedPath)
}

function Download-RepoFile([string]$RelativePath, [string]$Destination) {
    $escapedPath = ($RelativePath -split '/' | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/'
    $headers = @{
        'User-Agent' = 'Cobbleverse-Patch-Builder'
        'Cache-Control' = 'no-cache'
        'Pragma' = 'no-cache'
    }
    $rawUrl = 'https://raw.githubusercontent.com/{0}/main/{1}?cache={2}' -f $Repository, $escapedPath, [Guid]::NewGuid().ToString('N')
    try {
        Invoke-WebRequest -UseBasicParsing -Headers $headers -Uri $rawUrl -OutFile $Destination
        return
    }
    catch {
        $rawError = $_.Exception.Message
    }

    $apiUrl = 'https://api.github.com/repos/{0}/contents/{1}?ref=main' -f $Repository, $escapedPath
    $apiHeaders = @{
        'Accept' = 'application/vnd.github.raw+json'
        'User-Agent' = 'Cobbleverse-Patch-Builder'
        'X-GitHub-Api-Version' = '2022-11-28'
        'Cache-Control' = 'no-cache'
    }
    try {
        Invoke-WebRequest -UseBasicParsing -Headers $apiHeaders -Uri $apiUrl -OutFile $Destination
    }
    catch {
        throw "Could not download $RelativePath from GitHub.`r`n`r`nraw: $rawError`r`napi: $($_.Exception.Message)"
    }
}

function Get-LatestBaselineVersion($Index) {
    $current = [string]$Index.baselineVersion
    if ([string]::IsNullOrWhiteSpace($current)) {
        throw 'patch-index.json does not contain baselineVersion.'
    }

    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    while ($true) {
        if (-not $seen.Add($current)) {
            throw "Patch index contains a version loop at $current."
        }
        $next = @($Index.patches | Where-Object { [string]$_.fromVersion -eq $current })
        if ($next.Count -eq 0) { return $current }
        if ($next.Count -gt 1) { throw "Patch index has multiple patches starting from $current." }
        $current = [string]$next[0].toVersion
    }
}

function Get-SuggestedVersion([string]$FromVersion) {
    $today = Get-Date -Format 'yyyy.MM.dd'
    if ($FromVersion -match '^(\d{4}\.\d{2}\.\d{2})\.(\d+)$' -and $Matches[1] -eq $today) {
        return $today + '.' + ([int]$Matches[2] + 1)
    }
    return $today + '.1'
}

try {
    New-Item -ItemType Directory -Path $TempRoot -Force | Out-Null

    $payloadRoot = Select-Folder 'Select your CURRENT CORRECT Cobbleverse client profile folder (the folder containing mods and resourcepacks).'
    if (-not $payloadRoot) { return }

    foreach ($required in @('mods', 'resourcepacks')) {
        if (-not (Test-Path -LiteralPath (Join-Path $payloadRoot $required) -PathType Container)) {
            throw "The selected folder does not contain a $required folder:`r`n$payloadRoot"
        }
    }

    $indexPath = Join-Path $TempRoot 'patch-index.json'
    Download-RepoFile 'updater/patch-index.json' $indexPath
    $index = Get-Content -LiteralPath $indexPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([int]$index.schemaVersion -ne 1) { throw 'Unsupported patch-index schema.' }

    $fromVersion = Get-LatestBaselineVersion $index
    $baselinePath = Join-Path $TempRoot ("baseline-$fromVersion.json")
    Download-RepoFile ("baselines/baseline-$fromVersion.json") $baselinePath

    $baseline = Get-Content -LiteralPath $baselinePath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$baseline.version -ne $fromVersion) {
        throw "Downloaded baseline version does not match expected version $fromVersion."
    }

    $toVersion = [Microsoft.VisualBasic.Interaction]::InputBox(
        "Current published version: $fromVersion`r`n`r`nEnter the NEW version number.",
        'Cobbleverse Patch Builder',
        (Get-SuggestedVersion $fromVersion)
    ).Trim()
    if ([string]::IsNullOrWhiteSpace($toVersion)) { return }
    if ($toVersion -eq $fromVersion) { throw 'The new version must differ from the current version.' }
    if ($toVersion -notmatch '^[0-9A-Za-z._-]+$') { throw "Invalid version: $toVersion" }

    $repairChoice = [Windows.Forms.MessageBox]::Show(
        "Create a FULL REPAIR patch?`r`n`r`nYES: include every mod/resourcepack file. Use this for the first patch so incomplete legacy installs are repaired.`r`n`r`nNO: include only changed/new files for a normal incremental update.",
        'Cobbleverse Patch Builder',
        [Windows.Forms.MessageBoxButtons]::YesNo,
        [Windows.Forms.MessageBoxIcon]::Question
    )
    $includeAllFiles = ($repairChoice -eq [Windows.Forms.DialogResult]::Yes)

    $builder = Join-Path $TempRoot 'New-CobbleversePatch.ps1'
    Download-RepoFile 'tools/New-CobbleversePatch.ps1' $builder

    $desktop = [Environment]::GetFolderPath('Desktop')
    if ([string]::IsNullOrWhiteSpace($desktop)) { $desktop = $env:USERPROFILE }
    $outputDirectory = Join-Path $desktop ("Cobbleverse-Patch-$toVersion")
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null

    $builderArgs = @{
        PayloadRoot = $payloadRoot
        BaselineManifest = $baselinePath
        FromVersion = $fromVersion
        ToVersion = $toVersion
        OutputDirectory = $outputDirectory
    }
    if ($includeAllFiles) { $builderArgs.IncludeAllFiles = $true }

    $result = & $builder @builderArgs 2>&1 | Out-String

    $zipName = 'cobbleverse-patch-' + $toVersion.Replace('.', '-') + '.zip'
    $zipPath = Join-Path $outputDirectory $zipName
    $manifestPath = Join-Path $outputDirectory 'cobbleverse-patch.json'
    $nextBaselinePath = Join-Path $outputDirectory ("baseline-$toVersion.json")

    if (-not (Test-Path -LiteralPath $zipPath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $manifestPath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $nextBaselinePath -PathType Leaf)) {
        throw "The builder did not create all expected files.`r`n`r`n$result"
    }

    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $includedCount = @($manifest.files).Count
    $deletedCount = @($manifest.delete).Count
    $modeName = if ($includeAllFiles) { 'FULL REPAIR' } else { 'INCREMENTAL' }

    Show-Info ("Patch created successfully.`r`n`r`n" +
        "Mode: $modeName`r`n" +
        "From: $fromVersion`r`n" +
        "To: $toVersion`r`n" +
        "Included files: $includedCount`r`n" +
        "Deleted: $deletedCount`r`n`r`n" +
        "Saved to:`r`n$outputDirectory`r`n`r`n" +
        "Files:`r`n$zipName`r`ncobbleverse-patch.json`r`nbaseline-$toVersion.json")

    Start-Process explorer.exe -ArgumentList ('"' + $outputDirectory + '"')
}
catch {
    $message = $_.Exception.Message
    if ([string]::IsNullOrWhiteSpace($message)) { $message = [string]$_ }
    Show-Error $message
    exit 1
}
finally {
    if (Test-Path -LiteralPath $TempRoot -PathType Container) {
        Remove-Item -LiteralPath $TempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
