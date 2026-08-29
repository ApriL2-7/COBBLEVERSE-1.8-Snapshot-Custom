param(
    [Parameter(Mandatory = $true)]
    [string]$ReleaseDirectory,
    [string]$Repository = "ApriL2-7/COBBLEVERSE-1.8-Snapshot-Custom",
    [string]$Notes = "Cobbleverse client patch"
)

$ErrorActionPreference = "Stop"
$releaseRoot = [IO.Path]::GetFullPath($ReleaseDirectory)
$manifestPath = Join-Path $releaseRoot 'cobbleverse-patch.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Missing patch manifest: $manifestPath"
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$version = [string]$manifest.toVersion
if ($version -notmatch '^[0-9A-Za-z._-]+$') {
    throw "Invalid toVersion in patch manifest: $version"
}
$zipPath = Join-Path $releaseRoot ([string]$manifest.patchAsset)
if (-not (Test-Path -LiteralPath $zipPath -PathType Leaf)) {
    throw "Missing patch ZIP: $zipPath"
}
if ((Get-Item -LiteralPath $zipPath).Length -ne [long]$manifest.patchSize) {
    throw "Patch ZIP size no longer matches the manifest."
}
if ((Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash -ne ([string]$manifest.patchSha256).ToUpperInvariant()) {
    throw "Patch ZIP hash no longer matches the manifest."
}

$gh = 'C:\Program Files\GitHub CLI\gh.exe'
if (-not (Test-Path -LiteralPath $gh -PathType Leaf)) {
    throw "GitHub CLI is not installed: $gh"
}
& $gh auth status | Out-Host
if ($LASTEXITCODE -ne 0) {
    throw "GitHub CLI is not authenticated. Run: gh auth login"
}

$tag = "v$version"
& $gh release create $tag $manifestPath $zipPath --repo $Repository --title "Cobbleverse $version" --notes $Notes --latest
if ($LASTEXITCODE -ne 0) {
    throw "GitHub Release creation failed."
}

Write-Host "Published Release $tag" -ForegroundColor Green
Write-Host "Remember to copy baseline-$version.json into baselines/ and push it before building the next patch."

