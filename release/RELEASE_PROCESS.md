# FHPlayer Release Process

This project uses manual Google Drive distribution with:

- one shared public manifest for Windows and Android
- one stable public folder link for `Windows`
- one stable public folder link for `Android`

## Current Public Links

Manifest share link:

```text
https://drive.google.com/file/d/1yB-YWh4vKyxgVeYKXK8raaCTsKBT70JV/view?usp=sharing
```

Manifest raw download URL for the app:

```text
https://drive.google.com/uc?export=download&id=1yB-YWh4vKyxgVeYKXK8raaCTsKBT70JV
```

Windows folder link:

```text
https://drive.google.com/drive/folders/1jm1sMNGEvUAdXWNPiGaqRJ5pKo6IDZQW?usp=sharing
```

Android folder link:

```text
https://drive.google.com/drive/folders/1iMRmAQ2dd2zzCSV8IXSWNE-bn_L7oNte?usp=sharing
```

## Manifest Strategy

FHPlayer uses one manifest file for both platforms.

Recommended schema:

```json
{
  "app": "FHPlayer",
  "latest_version": "0.0.0",
  "release_notes": [
    "Short change 1",
    "Short change 2"
  ],
  "platforms": {
    "windows": {
      "folder_url": "<stable Windows folder link>",
      "installer_url": "<optional direct file link>",
      "portable_url": "<optional direct file link>"
    },
    "android": {
      "folder_url": "<stable Android folder link>",
      "apk_url": "<optional direct file link>",
      "aab_url": "<optional direct file link>"
    }
  }
}
```

The app uses:

- `latest_version` to compare versions
- `platforms.windows.folder_url` or `platforms.android.folder_url` as the release destination opened by the UI
- optional direct file URLs only as additional metadata

## Stable Links

The following links should stay unchanged between releases:

- the manifest file share link
- the Windows folder link
- the Android folder link

Only the contents of the versioned release folders and the JSON content of the manifest should change.

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
7. Upload the new Windows files into the stable Windows Drive folder structure.
8. Upload the new Android files into the stable Android Drive folder structure.
9. Replace the existing manifest file contents in Google Drive so the file ID stays the same.
10. Test `Check now` from an older Windows build and an older Android build.
11. Confirm the update dialog opens the correct platform folder link.

## Notes

- Do not delete and recreate the manifest file if the public link must stay stable.
- The app can read the Google Drive share link directly because it converts the file URL to the raw download endpoint internally.
- The update UI should open the platform folder link, not scrape Google Drive HTML for version detection.
- `prepare_public_release.ps1` validates the generated manifest, checksums, and required public files automatically after a normal run.
