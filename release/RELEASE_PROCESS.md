# FHPlayer Release Process

This project uses GitHub Releases distribution with:

- the GitHub latest release API as the default update feed for Windows and Android
- one public GitHub release page opened by the update UI
- versioned release assets for the Windows installer, Windows portable ZIP, Android APK, and Android AAB

## Current Public Links

Default update feed:

```text
https://api.github.com/repos/Honaro19/FHPlayer/releases/latest
```

Releases page:

```text
https://github.com/Honaro19/FHPlayer/releases
```

All releases:

```text
https://github.com/Honaro19/FHPlayer/releases
```

## Update Feed Strategy

FHPlayer reads the GitHub latest release JSON by default.

The app uses:

- `tag_name` to compare the newest release with the installed app version
- `html_url` as the release destination opened by the UI
- `assets[].browser_download_url` as optional direct file metadata

The release tag should use `v<version>`, for example `v0.1.2`. The parser also accepts plain semantic versions such as `0.1.2`.

Custom manifest feeds are still supported for testing or alternate hosting. Recommended custom manifest schema:

```json
{
  "schema_version": 1,
  "app": "FHPlayer",
  "latest_version": "0.0.0",
  "release_notes": [
    "Short change 1",
    "Short change 2"
  ],
  "platforms": {
    "windows": {
      "folder_url": "<release page link>",
      "installer_url": "<optional direct file link>",
      "portable_url": "<optional direct file link>"
    },
    "android": {
      "folder_url": "<release page link>",
      "apk_url": "<optional direct file link>",
      "aab_url": "<optional direct file link>"
    }
  }
}
```

For custom manifests, the app uses:

- `schema_version` to validate that the manifest matches the expected contract
- `latest_version` to compare versions
- `platforms.windows.folder_url` or `platforms.android.folder_url` as the release destination opened by the UI
- optional direct file URLs only as additional metadata

## Stable Links

The following links should stay unchanged between releases:

- the GitHub latest release API URL
- the GitHub releases page URL

Each release tag and its uploaded asset files are version-specific.

## Local Release Layout

Recommended local structure:

```text
release/
  Public Releases/
    FHPlayer/
      Windows/
        <version>/
      Android/
        <version>/
```

## Release Checklist

1. Update `VERSION`.
2. Build the Windows release installer with `.\build_windows_release.ps1`.
3. Build the Android release artifacts with `.\FHPlayerMobile\android\build_release_artifacts.ps1`.
4. Run `.\scripts\prepare_public_release.ps1 -DryRun` and verify the resolved input paths and release notes.
5. Run `.\scripts\prepare_public_release.ps1` to create the public release folders, portable ZIP, checksums, and manifest.
6. Optionally run `.\scripts\prepare_public_release.ps1 -VerifyOnly` as a final local consistency check.
7. Create or update the GitHub Release for tag `v<VERSION>`.
8. Upload the Windows installer, Windows portable ZIP, Android APK, Android AAB, checksums, and release notes to that GitHub Release.
9. Test `Check now` from an older Windows build and an older Android build.
10. Confirm the update dialog opens the correct GitHub release page.

## Notes

- The default update path reads GitHub's latest release JSON directly; no separate hosted manifest is required.
- If you use a custom manifest feed, keep its public URL stable between releases.
- The update UI should open the release page link, not scrape HTML for version detection.
- `prepare_public_release.ps1` validates the generated manifest, checksums, and required public files automatically after a normal run.
