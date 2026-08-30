# COBBLEVERSE 1.8 Snapshot Custom Updater

This repository contains the small Windows updater and patch-building tools for the private Cobbleverse server community. Large mod and resource-pack files are not committed to Git. Patch ZIP files are published as GitHub Release assets.

## Player usage

1. Download `Cobbleverse-Update-Launcher.bat` once.
2. Close Minecraft completely.
3. Run the launcher. The BAT downloads the latest `updater/Cobbleverse-Launcher.ps1`, which then downloads the latest bootstrap verifier and updater scripts.
4. Keep the CMD window open while the numeric download, verification, and installation progress reaches 100%.

The BAT is intentionally a tiny permanent bootstrap. Profile discovery, Modrinth/CurseForge support, baseline registration, console progress, and updater orchestration live in remotely downloaded PowerShell scripts, so existing players do not need to re-download the BAT when those behaviors change.

The normal player path is console-only. It shows SFC-style progress bars and numeric percentages for setup, patch downloads (including downloaded MB), installation verification, SHA-256 verification, rollback backup creation, and file application. The window remains open at the end so the player can read the result.

Players who downloaded a launcher from before this permanent-bootstrap design need to download the BAT one final time. After that migration, the same local BAT can be kept and reused indefinitely as long as the repository location remains unchanged.

Players who still have the previous hidden/GUI launcher BAT must also download the current BAT once to switch to the visible CMD progress window. Future updater-script changes will then arrive automatically through that BAT.

The launcher resolves both Modrinth and CurseForge profiles. It checks the normal Modrinth profiles directory and common CurseForge Minecraft instance directories, recognizes the standard `COBBLEVERSE 1.8 Snapshot Custom` folder name, and can also identify already-registered profiles by their guard/state file. If automatic detection is not possible, it accepts a pasted profile path or falls back to a folder picker.

For older copies that do not yet contain the Cobbleverse guard file or updater state file, `updater/Cobbleverse-Bootstrap.ps1` performs a one-time baseline signature verification. It compares managed `mods/` and `resourcepacks/` files against `baselines/baseline-2026.08.29.1.json` using file size and SHA-256. To tolerate launcher/export differences and optional files, registration no longer requires a 100% identical file set: at least 80% of baseline files must match exactly and at least two Cobbleverse-specific signature files must match. This still rejects unrelated profiles while allowing small CurseForge/Modrinth packaging differences. After registration, the generated state file avoids repeating the full verification on future runs.

The selected profile's parent directory is passed to the updater as the allowed profiles root, so CurseForge and custom launcher locations still use the updater's existing path-boundary safety check.

The updater downloads only missing sequential patches, verifies SHA-256 hashes before changing files, backs up affected files, and restores the original files if installation fails. A client that is already current skips all historical patch ZIP downloads.

## Static patch index

Clients do not enumerate GitHub Releases through the GitHub Releases API. Instead, the launcher downloads the small repository file `updater/patch-index.json`, stages the listed Release assets into a temporary local release directory, and invokes the existing updater with `-LocalReleaseRoot`. This keeps patch discovery independent from client-side GitHub Releases API behavior while preserving the existing manifest, SHA-256, backup, and rollback logic.

`.github/workflows/update-patch-index.yml` runs when a normal Release is published. If that Release contains `cobbleverse-patch.json`, the workflow reads its `fromVersion`, `toVersion`, and `patchAsset` fields and commits the corresponding entry into `updater/patch-index.json` on `main`. Releases without a patch manifest, such as the initial bootstrap Release, leave the index unchanged.

## Bootstrap launcher release

The launcher asset in release `v2026.08.29.1` is the permanent bootstrap download for players. `.github/workflows/sync-launcher-release.yml` automatically replaces that Release asset whenever the launcher, updater, or sync workflow changes on `main`, so new downloads from the original player link always receive the current bootstrap. Existing players on the permanent-bootstrap BAT continue receiving current launcher/updater logic without replacing their local BAT.

## Release asset contract

Every non-draft, non-prerelease GitHub Release that changes the client must contain exactly these assets:

- `cobbleverse-patch.json`
- the ZIP named by `patchAsset` inside that JSON

Patch releases form a strict chain using `fromVersion` and `toVersion`. A client that misses several releases applies each patch in order. Publishing the Release automatically updates `updater/patch-index.json` through GitHub Actions.

## Creating a patch

Use `tools/New-CobbleversePatch.ps1` with the current full-client payload and the baseline manifest from the previous release.

```powershell
powershell -ExecutionPolicy Bypass -File tools/New-CobbleversePatch.ps1 `
  -PayloadRoot "C:\path\to\payload" `
  -BaselineManifest "baselines\baseline-2026.08.29.1.json" `
  -FromVersion "2026.08.29.1" `
  -ToVersion "2026.08.30.1" `
  -OutputDirectory "out\2026.08.30.1"
```

Upload `cobbleverse-patch.json` and the generated patch ZIP to a Release tagged `v<toVersion>`. After publishing, preserve the generated next baseline for the following patch.

## Safety properties

- Only files under `mods/` and `resourcepacks/` can be changed.
- Absolute paths and `..` traversal are rejected.
- Markerless legacy installations are registered only when a strong majority of baseline files and multiple Cobbleverse-specific signatures match by SHA-256.
- The ZIP file and every extracted file are checked against SHA-256 values.
- All downloads are verified before the current profile is modified.
- Affected originals are backed up and restored on failure.
- The updater refuses to run while the selected Minecraft profile is active.
