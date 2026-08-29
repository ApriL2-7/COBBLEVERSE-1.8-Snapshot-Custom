# Release procedure

1. Update the full-client payload to the desired new client state.
2. Choose a new version. The server pack-guard channel must use the same release version.
3. Run `tools/New-CobbleversePatch.ps1` using the previous baseline.
4. Review the changed and deleted file counts.
5. Publish the generated manifest and ZIP with `tools/Publish-CobbleversePatch.ps1`.
6. Copy the generated next baseline into `baselines/`, commit it, and push it.
7. Update and restart the server-side pack guard only after the Release is downloadable.
8. Test one updated client before announcing the release.

Never commit mod JARs, resource-pack ZIPs, patch ZIPs, GitHub tokens, or private signing credentials to this repository.
