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

function Save-State([string]$Path) {
    $state = [ordered]@{
        schemaVersion = 1
        version = $BaselineVersion
        repository = $Repository
        updatedAt = (Get-Date).ToString('o')
        detectedBy = 'baseline-sha256'
    }
    [IO.File]::WriteAllText($Path, ($state | ConvertTo-Json -Depth 4), [Text.UTF8Encoding]::new($false))
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

    Update-Ui "기존 CurseForge 설치를 확인하는 중..." 2

    $baselineUrl = "https://raw.githubusercontent.com/$Repository/main/baselines/baseline-$BaselineVersion.json?cache=$([Guid]::NewGuid().ToString('N'))"
    $headers = @{ "User-Agent" = "Cobbleverse-Updater" }
    $baseline = Invoke-RestMethod -UseBasicParsing -Headers $headers -Uri $baselineUrl
    if ([int]$baseline.schemaVersion -ne 1 -or [string]$baseline.version -ne $BaselineVersion) {
        throw "The baseline manifest is invalid or has an unexpected version."
    }

    $files = @($baseline.files | Where-Object { [string]$_.path -ine ("mods/" + $GuardFileName) })
    if ($files.Count -eq 0) {
        throw "The baseline manifest contains no files."
    }

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
            throw "기준 버전과 파일 구성이 다릅니다. 없는 파일: $relative"
        }
        if ((Get-Item -LiteralPath $target).Length -ne [long]$file.size) {
            throw "기준 버전과 파일 크기가 다릅니다: $relative"
        }
        if ((Get-FileSha256 $target) -ne ([string]$file.sha256).ToUpperInvariant()) {
            throw "기준 버전과 파일 내용이 다릅니다: $relative"
        }
    }

    Save-State $statePath
    Update-Ui "기존 설치 확인 완료" 100
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
                "기존 설치를 Cobbleverse $BaselineVersion 기준 버전으로 확인하지 못했습니다.`r`n`r`n$($_.Exception.Message)`r`n`r`n선택한 CurseForge 프로필이 맞는지, 또는 클라이언트 파일이 변경되지 않았는지 확인해 주세요.",
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
