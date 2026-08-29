# COBBLEVERSE 1.8 Snapshot Custom Updater

This repository contains the small Windows updater and patch-building tools for the private Cobbleverse server community. Large mod and resource-pack files are not committed to Git. Patch ZIP files are published as GitHub Release assets.

## Player usage

1. Download `Cobbleverse-Update-Launcher.bat` once.
2. Close Minecraft completely.
3. Run the launcher. It downloads the latest updater script from this repository each time.
4. Use the graphical update window to accept the patch.

The launcher resolves both Modrinth and CurseForge profiles. It checks the normal Modrinth profiles directory and common CurseForge Minecraft instance directories, identifies the Cobbleverse profile by its guard/state file, and prefers `COBBLEVERSE 1.8 Snapshot Custom` when there is one clear match. If automatic detection is not possible, it accepts a pasted profile path or falls back to a folder picker.

The selected profile's parent directory is passed to the updater as the allowed profiles root, so CurseForge and custom launcher locations still use the updater's existing path-boundary safety check.

The updater downloads only missing sequential patches, verifies SHA-256 hashes before changing files, backs up affected files, and restores the original files if installation fails.

## Bootstrap launcher release

The launcher asset in release `v2026.08.29.1` is the permanent bootstrap download for players. `.github/workflows/sync-launcher-release.yml` automatically replaces that Release asset whenever the launcher, updater, or sync workflow changes on `main`, so the original player download link remains current.

## Release asset contract

Every non-draft, non-prerelease GitHub Release that changes the client must contain exactly these assets:

- `cobbleverse-patch.json`
- the ZIP named by `patchAsset` inside that JSON

Patch releases form a strict chain using `fromVersion` and `toVersion`. A client that misses several releases applies each patch in order.

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
- The ZIP file and every extracted file are checked against SHA-256 values.
- All downloads are verified before the current profile is modified.
- Affected originals are backed up and restored on failure.
- The updater refuses to run while the selected Minecraft profile is active.
