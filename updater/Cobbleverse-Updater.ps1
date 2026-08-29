param(
    [string]$ProfilePath = "",
    [string]$Repository = "ApriL2-7/COBBLEVERSE-1.8-Snapshot-Custom",
    [string]$ProfilesRoot = "",
    [string]$LocalReleaseRoot = "",
    [switch]$Yes,
    [switch]$CheckOnly,
    [switch]$Gui
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$BaselineVersion = "2026.08.29.1"
$StateFileName = "cobbleverse-pack-state.json"
$GuardFileName = "cobbleverse-client-pack-guard-2026.08.29.1.jar"
$AllowedPrefixes = @("mods/", "resourcepacks/")
$script:StatusLabel = $null
$script:DetailLabel = $null
$script:ProgressBar = $null
$script:MainForm = $null
$script:CloseButton = $null

function Write-Step([string]$Message) {
    Write-Host "[COBBLEVERSE] $Message" -ForegroundColor Cyan
    if ($script:StatusLabel) {
        $script:StatusLabel.Text = $Message
        [Windows.Forms.Application]::DoEvents()
    }
}

function Write-Ok([string]$Message) {
    Write-Host "[COBBLEVERSE] $Message" -ForegroundColor Green
    if ($script:StatusLabel) {
        $script:StatusLabel.ForeColor = [Drawing.Color]::FromArgb(90, 230, 170)
        $script:StatusLabel.Text = $Message
        [Windows.Forms.Application]::DoEvents()
    }
}

function New-UiFont([float]$Size, [Drawing.FontStyle]$Style = [Drawing.FontStyle]::Regular) {
    return [Drawing.Font]::new("Malgun Gothic", $Size, $Style, [Drawing.GraphicsUnit]::Point)
}

function Show-StyledConfirm([string]$From, [string]$To, [int]$PatchCount, [long]$Bytes) {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $dialog = [Windows.Forms.Form]::new()
    $dialog.Text = "Cobbleverse 업데이트"
    $dialog.Size = [Drawing.Size]::new(510, 350)
    $dialog.StartPosition = [Windows.Forms.FormStartPosition]::CenterScreen
    $dialog.FormBorderStyle = [Windows.Forms.FormBorderStyle]::FixedDialog
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    $dialog.BackColor = [Drawing.Color]::FromArgb(17, 22, 31)
    $dialog.ForeColor = [Drawing.Color]::White

    $accent = [Windows.Forms.Panel]::new()
    $accent.Dock = [Windows.Forms.DockStyle]::Top
    $accent.Height = 6
    $accent.BackColor = [Drawing.Color]::FromArgb(24, 210, 190)
    $dialog.Controls.Add($accent)

    $title = [Windows.Forms.Label]::new()
    $title.Text = "새로운 패치가 준비됐어요"
    $title.Location = [Drawing.Point]::new(34, 34)
    $title.AutoSize = $true
    $title.Font = New-UiFont 18 ([Drawing.FontStyle]::Bold)
    $dialog.Controls.Add($title)

    $subtitle = [Windows.Forms.Label]::new()
    $subtitle.Text = "Minecraft를 닫은 상태에서 안전하게 업데이트합니다."
    $subtitle.Location = [Drawing.Point]::new(37, 78)
    $subtitle.AutoSize = $true
    $subtitle.ForeColor = [Drawing.Color]::FromArgb(170, 180, 195)
    $subtitle.Font = New-UiFont 9.5
    $dialog.Controls.Add($subtitle)

    $card = [Windows.Forms.Panel]::new()
    $card.Location = [Drawing.Point]::new(36, 116)
    $card.Size = [Drawing.Size]::new(422, 100)
    $card.BackColor = [Drawing.Color]::FromArgb(28, 35, 47)
    $dialog.Controls.Add($card)

    $mb = [Math]::Round($Bytes / 1MB, 1)
    $info = [Windows.Forms.Label]::new()
    $info.Text = "현재 버전   $From`r`n업데이트   $To`r`n다운로드   패치 $PatchCount개 · 약 $mb MB"
    $info.Location = [Drawing.Point]::new(18, 14)
    $info.Size = [Drawing.Size]::new(390, 76)
    $info.Font = New-UiFont 10
    $info.ForeColor = [Drawing.Color]::FromArgb(220, 225, 232)
    $card.Controls.Add($info)

    $cancel = [Windows.Forms.Button]::new()
    $cancel.Text = "나중에"
    $cancel.Location = [Drawing.Point]::new(245, 242)
    $cancel.Size = [Drawing.Size]::new(100, 42)
    $cancel.FlatStyle = [Windows.Forms.FlatStyle]::Flat
    $cancel.FlatAppearance.BorderColor = [Drawing.Color]::FromArgb(70, 80, 95)
    $cancel.BackColor = [Drawing.Color]::FromArgb(35, 42, 54)
    $cancel.ForeColor = [Drawing.Color]::White
    $cancel.Font = New-UiFont 9 ([Drawing.FontStyle]::Bold)
    $cancel.DialogResult = [Windows.Forms.DialogResult]::Cancel
    $dialog.Controls.Add($cancel)

    $install = [Windows.Forms.Button]::new()
    $install.Text = "지금 업데이트"
    $install.Location = [Drawing.Point]::new(355, 242)
    $install.Size = [Drawing.Size]::new(103, 42)
    $install.FlatStyle = [Windows.Forms.FlatStyle]::Flat
    $install.FlatAppearance.BorderSize = 0
    $install.BackColor = [Drawing.Color]::FromArgb(24, 210, 190)
    $install.ForeColor = [Drawing.Color]::FromArgb(10, 25, 28)
    $install.Font = New-UiFont 9 ([Drawing.FontStyle]::Bold)
    $install.DialogResult = [Windows.Forms.DialogResult]::OK
    $dialog.Controls.Add($install)

    $dialog.AcceptButton = $install
    $dialog.CancelButton = $cancel
    return $dialog.ShowDialog() -eq [Windows.Forms.DialogResult]::OK
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
    if ($Gui) {
        return Show-StyledConfirm $From $To $PatchCount $Bytes
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

function Invoke-CobbleverseUpdate {
    $profile = Resolve-Profile $ProfilePath $ProfilesRoot
    Test-GameNotRunning $profile
    $state = Read-State $profile
    Write-Step "프로필을 확인했습니다"
    if ($script:DetailLabel) {
        $script:DetailLabel.Text = "설치 버전  $($state.Version)"
    }
    Write-Host "[COBBLEVERSE] Profile: $profile"
    Write-Host "[COBBLEVERSE] Installed version: $($state.Version)"

    $workRoot = Join-Path ([IO.Path]::GetTempPath()) ("cobbleverse-updater-" + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $workRoot -Force | Out-Null
    try {
        Write-Step "새 패치를 확인하는 중..."
        $descriptors = @(Get-PatchDescriptors $Repository $LocalReleaseRoot $workRoot)
        $chain = @(Get-UpdateChain $descriptors $state.Version)
        if ($chain.Count -eq 0) {
            Write-Ok "이미 최신 버전입니다"
            return [pscustomobject]@{ Code = 0; Message = "업데이트할 파일이 없습니다.`r`n현재 클라이언트가 최신 상태예요." }
        }

        $latest = [string]$chain[-1].Manifest.toVersion
        $downloadBytes = [long]0
        foreach ($item in $chain) {
            $downloadBytes += [long]$item.Manifest.patchSize
        }
        if ($CheckOnly) {
            Write-Host "UPDATE_AVAILABLE=$latest"
            return [pscustomobject]@{ Code = 2; Message = "업데이트 가능: $latest" }
        }
        if (-not (Confirm-Update $state.Version $latest $chain.Count $downloadBytes -AssumeYes:$Yes)) {
            Write-Step "업데이트를 취소했습니다"
            return [pscustomobject]@{ Code = 0; Message = "파일은 변경되지 않았습니다." }
        }

        Write-Step "패치를 다운로드하고 안전성을 확인하는 중..."
        $prepared = @(Prepare-Patches $chain $workRoot)
        Write-Step "검증 완료 · 패치를 적용하는 중..."
        Apply-PreparedPatches $prepared $profile $state
        Write-Ok "업데이트 완료 · $latest"
        return [pscustomobject]@{ Code = 0; Message = "모든 패치를 정상적으로 적용했습니다.`r`n이제 Modrinth에서 게임을 실행해도 됩니다." }
    }
    finally {
        if (Test-Path -LiteralPath $workRoot -PathType Container) {
            Remove-Item -LiteralPath $workRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Show-UpdaterWindow {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [Windows.Forms.Application]::EnableVisualStyles()

    $form = [Windows.Forms.Form]::new()
    $script:MainForm = $form
    $form.Text = "Cobbleverse Client Updater"
    $form.Size = [Drawing.Size]::new(610, 430)
    $form.StartPosition = [Windows.Forms.FormStartPosition]::CenterScreen
    $form.FormBorderStyle = [Windows.Forms.FormBorderStyle]::FixedSingle
    $form.MaximizeBox = $false
    $form.BackColor = [Drawing.Color]::FromArgb(14, 19, 27)
    $form.ForeColor = [Drawing.Color]::White

    $accent = [Windows.Forms.Panel]::new()
    $accent.Dock = [Windows.Forms.DockStyle]::Top
    $accent.Height = 7
    $accent.BackColor = [Drawing.Color]::FromArgb(24, 210, 190)
    $form.Controls.Add($accent)

    $badge = [Windows.Forms.Label]::new()
    $badge.Text = "CV"
    $badge.TextAlign = [Drawing.ContentAlignment]::MiddleCenter
    $badge.Location = [Drawing.Point]::new(38, 40)
    $badge.Size = [Drawing.Size]::new(58, 58)
    $badge.BackColor = [Drawing.Color]::FromArgb(24, 210, 190)
    $badge.ForeColor = [Drawing.Color]::FromArgb(8, 28, 30)
    $badge.Font = New-UiFont 16 ([Drawing.FontStyle]::Bold)
    $form.Controls.Add($badge)

    $title = [Windows.Forms.Label]::new()
    $title.Text = "COBBLEVERSE"
    $title.Location = [Drawing.Point]::new(113, 38)
    $title.AutoSize = $true
    $title.Font = New-UiFont 21 ([Drawing.FontStyle]::Bold)
    $form.Controls.Add($title)

    $sub = [Windows.Forms.Label]::new()
    $sub.Text = "1.8 Snapshot Custom · Client Updater"
    $sub.Location = [Drawing.Point]::new(116, 77)
    $sub.AutoSize = $true
    $sub.Font = New-UiFont 9.5
    $sub.ForeColor = [Drawing.Color]::FromArgb(145, 158, 177)
    $form.Controls.Add($sub)

    $card = [Windows.Forms.Panel]::new()
    $card.Location = [Drawing.Point]::new(38, 132)
    $card.Size = [Drawing.Size]::new(518, 182)
    $card.BackColor = [Drawing.Color]::FromArgb(24, 31, 43)
    $form.Controls.Add($card)

    $script:StatusLabel = [Windows.Forms.Label]::new()
    $script:StatusLabel.Text = "업데이터를 준비하는 중..."
    $script:StatusLabel.Location = [Drawing.Point]::new(24, 25)
    $script:StatusLabel.Size = [Drawing.Size]::new(470, 34)
    $script:StatusLabel.Font = New-UiFont 13 ([Drawing.FontStyle]::Bold)
    $card.Controls.Add($script:StatusLabel)

    $script:DetailLabel = [Windows.Forms.Label]::new()
    $script:DetailLabel.Text = "잠시만 기다려 주세요"
    $script:DetailLabel.Location = [Drawing.Point]::new(26, 65)
    $script:DetailLabel.Size = [Drawing.Size]::new(465, 44)
    $script:DetailLabel.Font = New-UiFont 9.5
    $script:DetailLabel.ForeColor = [Drawing.Color]::FromArgb(160, 172, 190)
    $card.Controls.Add($script:DetailLabel)

    $script:ProgressBar = [Windows.Forms.ProgressBar]::new()
    $script:ProgressBar.Location = [Drawing.Point]::new(27, 128)
    $script:ProgressBar.Size = [Drawing.Size]::new(464, 12)
    $script:ProgressBar.Style = [Windows.Forms.ProgressBarStyle]::Marquee
    $script:ProgressBar.MarqueeAnimationSpeed = 24
    $card.Controls.Add($script:ProgressBar)

    $safety = [Windows.Forms.Label]::new()
    $safety.Text = "SHA-256 검증  ·  자동 백업  ·  실패 시 원상 복구"
    $safety.Location = [Drawing.Point]::new(41, 329)
    $safety.AutoSize = $true
    $safety.Font = New-UiFont 8.5
    $safety.ForeColor = [Drawing.Color]::FromArgb(110, 125, 145)
    $form.Controls.Add($safety)

    $script:CloseButton = [Windows.Forms.Button]::new()
    $script:CloseButton.Text = "닫기"
    $script:CloseButton.Location = [Drawing.Point]::new(446, 322)
    $script:CloseButton.Size = [Drawing.Size]::new(110, 42)
    $script:CloseButton.FlatStyle = [Windows.Forms.FlatStyle]::Flat
    $script:CloseButton.FlatAppearance.BorderSize = 0
    $script:CloseButton.BackColor = [Drawing.Color]::FromArgb(24, 210, 190)
    $script:CloseButton.ForeColor = [Drawing.Color]::FromArgb(8, 28, 30)
    $script:CloseButton.Font = New-UiFont 9 ([Drawing.FontStyle]::Bold)
    $script:CloseButton.Visible = $false
    $script:CloseButton.Add_Click({ $script:MainForm.Close() })
    $form.Controls.Add($script:CloseButton)

    $form.Add_Shown({
        $form.Activate()
        try {
            $result = Invoke-CobbleverseUpdate
            $script:ProgressBar.Style = [Windows.Forms.ProgressBarStyle]::Continuous
            $script:ProgressBar.Value = 100
            $script:DetailLabel.Text = $result.Message
        }
        catch {
            $script:ProgressBar.Style = [Windows.Forms.ProgressBarStyle]::Continuous
            $script:ProgressBar.Value = 0
            $script:StatusLabel.ForeColor = [Drawing.Color]::FromArgb(255, 105, 120)
            $script:StatusLabel.Text = "업데이트하지 못했습니다"
            $script:DetailLabel.Text = $_.Exception.Message
            $form.Tag = 1
        }
        finally {
            $script:CloseButton.Visible = $true
            [Windows.Forms.Application]::DoEvents()
        }
    })

    $form.Show()
    while (-not $form.IsDisposed -and $form.Visible) {
        [Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 50
    }
    if ($form.Tag -eq 1) { return 1 }
    return 0
}

if ($Gui) {
    try {
        exit (Show-UpdaterWindow)
    }
    catch {
        $fatalMessage = $_.Exception.ToString()
        try {
            [IO.File]::WriteAllText((Join-Path ([IO.Path]::GetTempPath()) 'Cobbleverse-Updater-Error.log'), $fatalMessage)
            Add-Type -AssemblyName System.Windows.Forms
            [Windows.Forms.MessageBox]::Show(
                $_.Exception.Message,
                'Cobbleverse Updater',
                [Windows.Forms.MessageBoxButtons]::OK,
                [Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
        }
        catch {}
        exit 1
    }
}

try {
    $result = Invoke-CobbleverseUpdate
    exit ([int]$result.Code)
}
catch {
    Write-Host "[COBBLEVERSE] $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
