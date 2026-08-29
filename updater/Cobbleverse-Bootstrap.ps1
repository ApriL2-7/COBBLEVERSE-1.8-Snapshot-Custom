param(
    [Parameter(Mandatory = $true)]
    [string]$ProfilePath,
    [string]$Repository = "ApriL2-7/COBBLEVERSE-1.8-Snapshot-Custom",
    [string]$BaselineVersion = "2026.08.29.1",
    [switch]$Gui
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$StateFileName = "cobbleverse-pack-state.json"
$GuardFileName = "cobbleverse-client-pack-guard-2026.08.29.1.jar"
$MinimumMatchRatio = 0.80
$MinimumSignatureMatches = 2
$SignaturePaths = @(
    "mods/cobblebase-fabric-2.0.0+1.7.0-cobblemon1.8-gatherer-configurable-quiet.jar",
    "mods/CobbleverseBadges-1.3.jar",
    "mods/cobbleverse-battle-extras-hotfix-1.0.0.jar",
    "mods/cobbleverse-compat-api119-hotfix-1.0.0.jar",
    "mods/cobbleverse-mount-sync-hotfix-1.0.0.jar",
    "mods/Cobbreeding-fabric-2.2.2-cobbleverse-pcfix.jar"
)
$script:Form = $null
$script:Status = $null
$script:Progress = $null

function Get-FullPath([string]$Path) {
    return [IO.Path]::GetFullPath($Path)
}

function Get-FileSha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Update-Ui([string]$Message, [int]$Value) {
    if ($script:Status) {
        $script:Status.Text = $Message
        $script:Progress.Value = [Math]::Max(0, [Math]::Min(100, $Value))
        [Windows.Forms.Application]::DoEvents()
    }
}

function Save-State([string]$Path, [int]$Matched, [int]$Total, [int]$SignatureMatches) {
    $state = [ordered]@{
        schemaVersion = 1
        version = $BaselineVersion
        repository = $Repository
        updatedAt = (Get-Date).ToString('o')
        detectedBy = 'baseline-signature-v2'
        verification = [ordered]@{
            matchedFiles = $Matched
            totalBaselineFiles = $Total
            signatureMatches = $SignatureMatches
        }
    }
    [IO.File]::WriteAllText($Path, ($state | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
}

function Get-BaselineManifest {
    $relativePath = "baselines/baseline-$BaselineVersion.json"
    $rawUrl = "https://raw.githubusercontent.com/{0}/main/{1}" -f $Repository, $relativePath
    $commonHeaders = @{
        "User-Agent" = "Cobbleverse-Updater"
        "Cache-Control" = "no-cache"
        "Pragma" = "no-cache"
    }

    try {
        $response = Invoke-WebRequest -UseBasicParsing -Headers $commonHeaders -Uri $rawUrl
        return ($response.Content | ConvertFrom-Json)
    }
    catch {
        $rawError = $_.Exception.Message
    }

    $apiUrl = "https://api.github.com/repos/{0}/contents/{1}?ref=main" -f $Repository, $relativePath
    $apiHeaders = @{
        "Accept" = "application/vnd.github.raw+json"
        "User-Agent" = "Cobbleverse-Updater"
        "X-GitHub-Api-Version" = "2022-11-28"
        "Cache-Control" = "no-cache"
    }

    try {
        $response = Invoke-WebRequest -UseBasicParsing -Headers $apiHeaders -Uri $apiUrl
        return ($response.Content | ConvertFrom-Json)
    }
    catch {
        throw "기준 파일을 GitHub에서 받지 못했습니다.`r`n`r`nraw.githubusercontent.com: $rawError`r`nGitHub API: $($_.Exception.Message)"
    }
}

function Test-AndRegisterBaseline {
    $profile = Get-FullPath ($ProfilePath.Trim().Trim('"'))
    if (-not (Test-Path -LiteralPath $profile -PathType Container)) {
        throw "Profile folder does not exist: $profile"
    }
    if (-not (Test-Path -LiteralPath (Join-Path $profile 'mods') -PathType Container)) {
        throw "The selected folder does not contain a mods folder."
    }

    $statePath = Join-Path $profile $StateFileName
    if (Test-Path -LiteralPath $statePath -PathType Leaf) {
        return
    }

    $guardPath = Join-Path $profile ("mods\" + $GuardFileName)
    if (Test-Path -LiteralPath $guardPath -PathType Leaf) {
        return
    }

    Update-Ui "기존 설치를 확인하는 중..." 2

    $baseline = Get-BaselineManifest
    if ([int]$baseline.schemaVersion -ne 1 -or [string]$baseline.version -ne $BaselineVersion) {
        throw "The baseline manifest is invalid or has an unexpected version."
    }

    $files = @($baseline.files | Where-Object { [string]$_.path -ine ("mods/" + $GuardFileName) })
    if ($files.Count -eq 0) {
        throw "The baseline manifest contains no files."
    }

    $signatureSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($signature in $SignaturePaths) {
        $null = $signatureSet.Add($signature)
    }

    $matched = 0
    $missing = 0
    $different = 0
    $signatureMatches = 0
    $examples = [Collections.Generic.List[string]]::new()
    $index = 0

    foreach ($file in $files) {
        $index++
        $relative = ([string]$file.path).Replace('\', '/')
        if (-not ($relative.StartsWith('mods/', [StringComparison]::OrdinalIgnoreCase) -or $relative.StartsWith('resourcepacks/', [StringComparison]::OrdinalIgnoreCase))) {
            throw "Unsafe baseline path rejected: $relative"
        }
        if ($relative.Split('/') -contains '..') {
            throw "Unsafe baseline path rejected: $relative"
        }

        $target = Join-Path $profile ($relative.Replace('/', [IO.Path]::DirectorySeparatorChar))
        $percent = 3 + [int](94.0 * $index / $files.Count)
        Update-Ui ("기존 설치 확인 중  {0}/{1}" -f $index, $files.Count) $percent

        if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
            $missing++
            if ($examples.Count -lt 5) { $examples.Add("없음: $relative") }
            continue
        }

        $isMatch = $false
        if ((Get-Item -LiteralPath $target).Length -eq [long]$file.size) {
            if ((Get-FileSha256 $target) -eq ([string]$file.sha256).ToUpperInvariant()) {
                $isMatch = $true
            }
        }

        if ($isMatch) {
            $matched++
            if ($signatureSet.Contains($relative)) {
                $signatureMatches++
            }
        }
        else {
            $different++
            if ($examples.Count -lt 5) { $examples.Add("다름: $relative") }
        }
    }

    $ratio = if ($files.Count -gt 0) { [double]$matched / [double]$files.Count } else { 0.0 }
    $ratioPercent = [Math]::Round($ratio * 100, 1)

    if ($ratio -lt $MinimumMatchRatio -or $signatureMatches -lt $MinimumSignatureMatches) {
        $exampleText = if ($examples.Count -gt 0) { "`r`n`r`n예시:`r`n- " + (($examples.ToArray()) -join "`r`n- ") } else { "" }
        throw ("선택한 설치가 Cobbleverse {0} 기준과 충분히 일치하지 않습니다.`r`n`r`n일치: {1}/{2} ({3}%)`r`n없음: {4}`r`n다름: {5}`r`nCobbleverse 핵심 서명: {6}/{7}`r`n필요 조건: 파일 80% 이상 + 핵심 서명 {8}개 이상{9}" -f $BaselineVersion, $matched, $files.Count, $ratioPercent, $missing, $different, $signatureMatches, $SignaturePaths.Count, $MinimumSignatureMatches, $exampleText)
    }

    Save-State $statePath $matched $files.Count $signatureMatches
    Update-Ui ("기존 설치 확인 완료  {0}% 일치" -f $ratioPercent) 100
}

function Show-VerificationWindow {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [Windows.Forms.Application]::EnableVisualStyles()

    $form = [Windows.Forms.Form]::new()
    $script:Form = $form
    $form.Text = "Cobbleverse Updater"
    $form.Size = [Drawing.Size]::new(500, 190)
    $form.StartPosition = [Windows.Forms.FormStartPosition]::CenterScreen
    $form.FormBorderStyle = [Windows.Forms.FormBorderStyle]::FixedDialog
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.BackColor = [Drawing.Color]::FromArgb(14, 19, 27)
    $form.ForeColor = [Drawing.Color]::White

    $script:Status = [Windows.Forms.Label]::new()
    $script:Status.Text = "기존 설치 정보를 확인하는 중..."
    $script:Status.Location = [Drawing.Point]::new(28, 30)
    $script:Status.Size = [Drawing.Size]::new(430, 45)
    $script:Status.Font = [Drawing.Font]::new("Malgun Gothic", 11, [Drawing.FontStyle]::Bold)
    $form.Controls.Add($script:Status)

    $script:Progress = [Windows.Forms.ProgressBar]::new()
    $script:Progress.Location = [Drawing.Point]::new(30, 92)
    $script:Progress.Size = [Drawing.Size]::new(420, 18)
    $script:Progress.Minimum = 0
    $script:Progress.Maximum = 100
    $script:Progress.Value = 0
    $form.Controls.Add($script:Progress)

    $form.Add_Shown({
        try {
            Test-AndRegisterBaseline
            $form.Tag = 0
        }
        catch {
            $form.Tag = 1
            [Windows.Forms.MessageBox]::Show(
                "기존 설치를 Cobbleverse $BaselineVersion 기준 버전으로 확인하지 못했습니다.`r`n`r`n$($_.Exception.Message)`r`n`r`n선택한 프로필이 맞는지 확인해 주세요.",
                "Cobbleverse Updater",
                [Windows.Forms.MessageBoxButtons]::OK,
                [Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
        }
        finally {
            $form.Close()
        }
    })

    $form.ShowDialog() | Out-Null
    if ($form.Tag -eq 1) { return 1 }
    return 0
}

try {
    if ($Gui) {
        exit (Show-VerificationWindow)
    }
    Test-AndRegisterBaseline
    exit 0
}
catch {
    Write-Host "[COBBLEVERSE] $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
