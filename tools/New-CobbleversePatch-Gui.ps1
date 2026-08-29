$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName Microsoft.VisualBasic
[Windows.Forms.Application]::EnableVisualStyles()

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

function Select-Folder([string]$Description, [string]$InitialPath = '') {
    $dialog = [Windows.Forms.FolderBrowserDialog]::new()
    $dialog.Description = $Description
    $dialog.ShowNewFolderButton = $true
    if ($InitialPath -and (Test-Path -LiteralPath $InitialPath -PathType Container)) {
        $dialog.SelectedPath = $InitialPath
    }
    if ($dialog.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) {
        return $null
    }
    return [IO.Path]::GetFullPath($dialog.SelectedPath)
}

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$builder = Join-Path $PSScriptRoot 'New-CobbleversePatch.ps1'
$baselinesRoot = Join-Path $repoRoot 'baselines'

try {
    if (-not (Test-Path -LiteralPath $builder -PathType Leaf)) {
        throw "Patch builder script was not found:`r`n$builder"
    }

    $payloadRoot = Select-Folder 'Select the CURRENT, CORRECT Cobbleverse client profile folder. It must contain mods and resourcepacks.'
    if (-not $payloadRoot) { return }

    foreach ($required in @('mods', 'resourcepacks')) {
        if (-not (Test-Path -LiteralPath (Join-Path $payloadRoot $required) -PathType Container)) {
            throw "The selected profile does not contain a $required folder:`r`n$payloadRoot"
        }
    }

    $defaultBaseline = Get-ChildItem -LiteralPath $baselinesRoot -Filter 'baseline-*.json' -File -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending |
        Select-Object -First 1

    $fileDialog = [Windows.Forms.OpenFileDialog]::new()
    $fileDialog.Title = 'Select the baseline manifest for the version your friends currently have'
    $fileDialog.Filter = 'Cobbleverse baseline (baseline-*.json)|baseline-*.json|JSON files (*.json)|*.json'
    $fileDialog.InitialDirectory = $baselinesRoot
    if ($defaultBaseline) {
        $fileDialog.FileName = $defaultBaseline.Name
    }
    if ($fileDialog.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) {
        return
    }
    $baselineManifest = [IO.Path]::GetFullPath($fileDialog.FileName)
    $baseline = Get-Content -LiteralPath $baselineManifest -Raw -Encoding UTF8 | ConvertFrom-Json
    $fromVersion = [string]$baseline.version
    if ([string]::IsNullOrWhiteSpace($fromVersion)) {
        throw 'The selected baseline does not contain a version.'
    }

    $toVersion = [Microsoft.VisualBasic.Interaction]::InputBox(
        "Current baseline: $fromVersion`r`n`r`nEnter the NEW version number.",
        'Cobbleverse Patch Builder',
        (Get-Date -Format 'yyyy.MM.dd') + '.1'
    ).Trim()
    if ([string]::IsNullOrWhiteSpace($toVersion)) { return }
    if ($toVersion -eq $fromVersion) {
        throw 'The new version must differ from the baseline version.'
    }
    if ($toVersion -notmatch '^[0-9A-Za-z._-]+$') {
        throw "Invalid version: $toVersion"
    }

    $suggestedOutput = Join-Path $repoRoot 'patch-output'
    if (-not (Test-Path -LiteralPath $suggestedOutput -PathType Container)) {
        New-Item -ItemType Directory -Path $suggestedOutput -Force | Out-Null
    }
    $outputDirectory = Select-Folder 'Select where the generated patch files should be saved.' $suggestedOutput
    if (-not $outputDirectory) { return }

    $result = & $builder `
        -PayloadRoot $payloadRoot `
        -BaselineManifest $baselineManifest `
        -FromVersion $fromVersion `
        -ToVersion $toVersion `
        -OutputDirectory $outputDirectory 2>&1 | Out-String

    $zipName = 'cobbleverse-patch-' + $toVersion.Replace('.', '-') + '.zip'
    $zipPath = Join-Path $outputDirectory $zipName
    $manifestPath = Join-Path $outputDirectory 'cobbleverse-patch.json'
    $nextBaselinePath = Join-Path $outputDirectory ("baseline-$toVersion.json")

    if (-not (Test-Path -LiteralPath $zipPath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $manifestPath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $nextBaselinePath -PathType Leaf)) {
        throw "The builder finished without all expected output files.`r`n`r`n$result"
    }

    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $changedCount = @($manifest.files).Count
    $deletedCount = @($manifest.delete).Count

    Show-Info ("Patch created successfully.`r`n`r`n" +
        "From: $fromVersion`r`n" +
        "To: $toVersion`r`n" +
        "Changed/New: $changedCount`r`n" +
        "Deleted: $deletedCount`r`n`r`n" +
        "ZIP: $zipName`r`n" +
        "Manifest: cobbleverse-patch.json`r`n" +
        "Next baseline: baseline-$toVersion.json")

    Start-Process explorer.exe -ArgumentList ('"' + $outputDirectory + '"')
}
catch {
    $message = $_.Exception.Message
    if ([string]::IsNullOrWhiteSpace($message)) { $message = [string]$_ }
    Show-Error $message
    exit 1
}
