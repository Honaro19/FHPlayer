# FHPlayer

FHPlayer is a local Flutter video player for Windows and Android that triggers Lovense actions at the timestamps defined in `funscript` files. Multiple video/funscript pairs can be loaded as a playlist and played sequentially or randomly.

FHPlayer is a private project and is not intended for production use.

Before using this software, it is recommended to back up important data.

## Features

- Load multiple videos with matching `funscript` files as a playlist
- Play the playlist sequentially or randomly
- Save and load `.fhplaylist` files with media paths, playlist order, playback mode, funscript data, and per-entry Lovense settings
- Read `funscript` files and display all contained actions
- Choose between `Lovense live` and `Lovense test` per playlist entry
- Connect to Lovense over configurable protocol, host/IP, and port
- Store multiple Lovense user profiles globally in the playlist and activate different users per video
- Keep separate Lovense rule scripts per user and playlist entry in `Lovense live` and `Lovense test`
- Detect one or more connected Lovense devices per user profile with their supported capabilities
- Validate Lovense rules so untargeted actions are shared-compatible and targeted actions match the addressed devices
- Run multiple Lovense actions at the same time on every selected device when their shared functions allow it
- Address individual selected devices by name or ID inside Lovense rules
- Show live rule validation, detected device types, and allowed parallel action count in the UI
- Test Lovense rules locally with simulated devices directly in Lovense test mode
- Read optional defaults directly from the `funscript`
- Pause Lovense live playback quickly with the player overlay stop/resume control
- No artificial 1-second limit between triggers: closely spaced actions are sent to the backend in parallel
- View a log of triggered Lovense requests and responses

## Start

Requirement: Flutter SDK

```powershell
Set-Location .\fhplayer_flutter
flutter run -d windows
```

The project version is defined centrally in `VERSION`.

On startup FHPlayer creates a managed library under:

- Windows desktop: `%LOCALAPPDATA%\FHPlayer\Library\Videos`, `%LOCALAPPDATA%\FHPlayer\Library\Funscripts`, `%LOCALAPPDATA%\FHPlayer\Library\Exports`
- Android app: app-managed `Library/Videos`, `Library/Funscripts`, and `Library/Exports` folders inside the app storage area

## Quick Start

### Desktop

1. Start FHPlayer with `flutter run -d windows` or the built Windows executable.
2. Wait for the Flutter window to open.
3. Select one or more video files.
4. Select the matching `.funscript` or `.json` files.
5. Configure `Lovense live` or `Lovense test`.
6. Click `Add to playlist`.
7. Optional: click `Save to Library` to copy selected media into the managed library and save the current playlist into `Exports`.
8. Load the playlist entry and start the video.

### Android

1. Install `installers\android\FHPlayer-<version>-debug.apk` for debug use or the release APK once you have one.
2. Start the app.
3. Select videos and then the matching `.funscript` or `.json` files through the Android document picker.
4. Configure `Lovense live` or `Lovense test`.
5. Add the entry to the playlist and start playback.
6. Optional: click `Save to Library` to copy selected media into the app-managed library and save the current playlist into `Exports`.

### First Lovense Connection

1. Use `Lovense test` first if you only want to validate the rule logic.
2. For desktop Lovense Remote defaults, start with `HTTPS`, `127.0.0.1`, and port `30010`.
3. For a phone running Lovense Remote, usually use `HTTP`, the phone IP, and the port shown by the Lovense app.
4. Click `Detect devices`.
5. Select one or more devices from the device list.
6. Confirm any first-time Lovense permission or pairing popup before testing live playback.

## Updates

FHPlayer now includes an optional update check in the UI:

- `Check automatically on startup` is off by default and can be enabled or disabled by the user at any time
- `Check now` always remains available for a manual check
- The desktop and Android app both compare the current version against the latest GitHub Release metadata for FHPlayer

By default the app checks:

```text
https://api.github.com/repos/Honaro19/FHPlayer/releases/latest
```

FHPlayer reads the GitHub release JSON, compares the release tag with the current app version, and uses the release asset URLs for platform-specific downloads.

The UI opens the public GitHub releases page, or the specific release page returned by the feed after a successful check:

- Windows: `https://github.com/Honaro19/FHPlayer/releases`
- Android: `https://github.com/Honaro19/FHPlayer/releases`

Custom manifest feeds are still supported. The manifest contract is versioned explicitly and the current app expects `schema_version: 1` for non-GitHub feeds.

On Windows you can still override that feed URL for testing or custom hosting:

```powershell
$env:FHPLAYER_UPDATE_FEED_URL = "https://example.com/update_manifest.json"
flutter run -d windows
```

The update preference and the last result are stored locally:

- Desktop: `%LOCALAPPDATA%\FHPlayer\settings.json`
- Android: `fhplayer-settings.json` inside the app files directory

The same settings file also stores which optional UI panels stay visible. You can hide or re-enable:

- `Diagnostics`
- `Funscript overview`
- `Execution log`

For a real end-to-end update test, publish a new GitHub Release with the Windows and Android assets, then let an older installed FHPlayer build use `Check now`. That verifies the real update path before you distribute the new installer or APK.

The release workflow and the local manifest template are documented in:

- `release/RELEASE_PROCESS.md`
- `release/update_manifest.template.json`

## Legal And Privacy

- FHPlayer is licensed under the MIT License with additional disclaimer text in `LICENSE`.
- The software is provided "as is" without warranty of any kind.
- Use of the software is at your own risk.
- The software may contain bugs or incomplete functionality.
- The author is not liable for damages, especially data loss, system failures, or consequential damages.
- This software is provided free of charge without any support or maintenance obligation.
- Liability for intent and gross negligence remains unaffected where required by applicable law.
- FHPlayer is a private project and is not intended for production use.

## Diagnostics

FHPlayer now keeps a rotating local application log and exposes the most important diagnostic paths in the UI.

Stored diagnostic files:

- Desktop: `%LOCALAPPDATA%\FHPlayer\Logs\fhplayer.log`
- Android: `logs/fhplayer.log` inside the app files directory

The Diagnostics panel in the UI shows:

- app data, library, settings, and log paths
- recent log output from the embedded backend
- on desktop only: a button to open the log folder directly

## Release Check

Run the consolidated release verification with:

```powershell
.\scripts\release_check.ps1
```

That combines:

- PowerShell syntax checks
- Flutter tests + `dart analyze`
- the full smoke test runner
- Windows release installer build verification
- Android release APK and AAB build verification

Useful options:

- `-SkipAndroidInstall` if no emulator or device is connected
- `-AndroidDeviceSerial <serial>` to target a specific Android device
- `-WindowsSigningMode Skip|Auto|Require`
- `-AndroidSigningMode Skip|Auto|Require`
- `-KeepArtifacts` to keep the full `.tmp\release-checks\...` output

## Windows EXE

You can package FHPlayer as a Windows `.exe` from the Flutter Windows target.

Create the executable bundle:

```powershell
.\build_windows.ps1
```

Or send the generated `dist\` folder somewhere else:

```powershell
.\build_windows.ps1 -OutputRoot .tmp\windows-build -TempRoot .tmp\windows-temp
```

Or with double-click / Command Prompt:

```cmd
build_windows.cmd
```

The result is written to `dist\FHPlayer\FHPlayer.exe`.

The Windows build now also uses `assets\branding\fhplayer.ico`. If that icon file does not exist yet, `build_windows.ps1` generates a branded placeholder icon automatically.

Current branding assets:

- Windows EXE / installer: `assets\branding\fhplayer.ico`
- Source image for branding work: `assets\branding\fhplayer-icon-256.png`

## Windows Installer

You can build a per-user Windows installer with Inno Setup 6:

```powershell
.\build_windows_installer.ps1
```

To keep both the EXE build and the final installer output outside the project tree:

```powershell
.\build_windows_installer.ps1 -OutputDir .tmp\installer-output -WindowsBuildOutputRoot .tmp\installer-build -TempRoot .tmp\installer-temp
```

Or with double-click / Command Prompt:

```cmd
build_windows_installer.cmd
```

The installer:

- installs FHPlayer into `%LOCALAPPDATA%\Programs\FHPlayer`
- creates Start menu and optional desktop shortcuts
- pre-creates `%LOCALAPPDATA%\FHPlayer\Library\Videos`, `Funscripts`, and `Exports`

The setup executable is written to:

```text
installers\windows\FHPlayer-Setup.exe
```

## Windows Release Build

Use the release wrapper when you want a versioned installer name and optional code signing:

```powershell
.\build_windows_release.ps1
```

That writes:

```text
installers\windows\FHPlayer-<version>-Setup.exe
```

Unsigned release builds are allowed with:

```powershell
.\build_windows_release.ps1 -SigningMode Skip
```

To require code signing, provide either a certificate file or a certificate thumbprint:

```powershell
.\build_windows_release.ps1 `
  -SigningMode Require `
  -CertificatePath C:\secure\fhplayer-signing.pfx `
  -CertificatePassword "<password>"
```

Or through environment variables:

- `FHPLAYER_WINDOWS_SIGN_CERT_PATH`
- `FHPLAYER_WINDOWS_SIGN_CERT_PASSWORD`
- `FHPLAYER_WINDOWS_SIGN_CERT_THUMBPRINT`
- `FHPLAYER_WINDOWS_SIGNTOOL_PATH`
- `FHPLAYER_WINDOWS_SIGN_TIMESTAMP_URL`

To prepare the local public release package from the built artifacts, run:

```powershell
.\scripts\prepare_public_release.ps1
```

That populates:

```text
release\Public Releases\FHPlayer\
```

It creates the versioned Windows and Android folders, builds the portable Windows ZIP, writes `README.txt`, `CHANGELOG.txt`, `SHA256SUMS.txt`, and refreshes `update_manifest.json`.

Useful options:

- `-DryRun` to validate all inputs and show the planned output paths without writing files
- `-VerifyOnly` to validate an already prepared public release folder, manifest, and checksums
- `-ReleaseNote "..."` to override the release notes directly from the command line
- `-ReleaseNotesPath .\path\to\notes.txt` to load release notes from a text file
- `-CleanVersionDirectories` to rebuild the versioned Windows and Android output folders from scratch

## Flutter App (Android + Windows)

FHPlayer includes a shared Flutter app in `fhplayer_flutter`.
Android and Windows are built from the same Flutter project. A split into
separate `FHPlayerAndroid`/`FHPlayerWindows` app roots is intentionally not
used.

The current Flutter structure is:

- `fhplayer_flutter/`: Flutter app root (shared code + platform targets)
- `fhplayer_flutter/android/`: Android Flutter target and Gradle files
- `fhplayer_flutter/windows/`: Windows Flutter runner target
- `scripts/android_flutter/`: Windows PowerShell helpers for Android APK/AAB build and install

Build the debug APK with:

```powershell
scripts\android_flutter\build_debug_apk.ps1
```

To write the output APK somewhere else:

```powershell
scripts\android_flutter\build_debug_apk.ps1 -OutputDir .tmp\android-output
```

The APK is written to:

```text
installers\android\FHPlayer-<version>-debug.apk
```

Install the APK onto a connected emulator or Android device with:

```powershell
scripts\android_flutter\install_debug_apk.ps1 -LaunchApp
```

If you built the APK into a custom output directory, pass that APK path during install:

```powershell
scripts\android_flutter\install_debug_apk.ps1 -ApkPath .tmp\android-output\FHPlayer-<version>-debug.apk -LaunchApp
```

Current Android limitations:

- `Lovense live` and `Lovense test` are available in the Flutter app.
- Video and `.funscript` pairing still works once both files are selected, but Android does not automatically scan sibling files from the filesystem by filename.
- The Android installer artifact is the APK itself. For a distributable release build, add a release keystore and build a signed release APK.
- On first app start FHPlayer creates the managed `Library\Videos`, `Library\Funscripts`, and `Library\Exports` folders inside the app storage area.

## Android Release Build

Build release artifacts with:

```powershell
scripts\android_flutter\build_release_artifacts.ps1
```

That produces:

```text
installers\android\FHPlayer-<version>.apk
installers\android\FHPlayer-<version>.aab
```

If no signing configuration is present, the script builds unsigned release artifacts by default and tells you so.

To require signing, copy `fhplayer_flutter\android\release-signing.example.properties` to `fhplayer_flutter\android\release-signing.properties` and fill in the real values, or provide the same values through environment variables:

- `FHPLAYER_ANDROID_KEYSTORE_PATH`
- `FHPLAYER_ANDROID_KEYSTORE_PASSWORD`
- `FHPLAYER_ANDROID_KEY_ALIAS`
- `FHPLAYER_ANDROID_KEY_PASSWORD`

Then build with:

```powershell
scripts\android_flutter\build_release_artifacts.ps1 -SigningMode Require
```

Useful options:

- `-SkipApk`
- `-SkipBundle`
- `-OutputDir .tmp\android-release-output`
- `-SigningPropertiesPath .\fhplayer_flutter\android\release-signing.properties`

## Internal Testing Guide

For the full internal Windows testing flow (fast checks, Flutter hang troubleshooting, and Android emulator validation), see:

- `INTERNAL_TESTING_GUIDE.md`

## Smoke Tests

Run the reusable smoke-test runner with:

```powershell
.\scripts\smoke_test.ps1
```

By default it tests the built Windows EXE, the Windows installer, and the Android APK build. When exactly one adb device or emulator is connected, it also installs and launches the Android app.

Useful options:

- `-SkipWindowsInstaller`
- `-SkipAndroid`
- `-SkipAndroidInstall`
- `-AndroidDeviceSerial emulator-5554`
- `-KeepArtifacts`

## Flutter Tests

Run Flutter tests through the logged wrapper:

```powershell
.\scripts\test_flutter.ps1
```

Run only one Flutter test file:

```powershell
.\scripts\test_flutter.ps1 -TestPath test\lovense_mock_test.dart
```

Useful options:

- `-TimeoutSeconds 900` for slower machines
- `-AllowPub` to allow `pub get` during the test run
- `-Reporter compact|expanded|json`
- `-ExtraFlutterArgs '--plain-name','My test name'`

The script writes logs to:

- `.tmp\flutter-logs\*.out.log`
- `.tmp\flutter-logs\*.err.log`
- `.tmp\flutter-logs\*.meta.log`

Common failure signatures and meaning:

- `PathAccessException: Cannot copy ... build\unit_test_assets\NativeAssetsManifest.json ... Access denied`
  - The execution context cannot overwrite/delete files under `build\unit_test_assets`.
  - Re-run outside restrictive sandbox environments.
- `Flutter failed to run "git ...". The flutter tool cannot access the file or directory.`
  - The execution context cannot run required subprocesses (for example `git`) with sufficient access.
  - Re-run outside restrictive sandbox environments.

## Daily Use

1. Select one or more videos.
2. Select the matching `.funscript` or `.json` files.
   FHPlayer applies saved FHPlayer metadata from the first selected script immediately when available.
3. Optional: click `Import selected files` if you want copies inside the managed FHPlayer library.
4. Choose `Lovense live` or `Lovense test`.
5. For `Lovense live`, select or create a connection profile, enter host settings, click `Detect devices`, and select the devices you want to use.
6. For `Lovense test`, select one or more simulated devices from the same device list.
7. Review or edit the rule script for the selected Lovense user. Each user profile has its own script for the selected playlist entry.
8. Click `Add to playlist`.
9. Use `Save selected entry` after later changes to the selected playlist item.
10. Click `Save to Library` to copy selected videos and funscripts into the managed library and store the full playlist as a `.fhplaylist` file in `Exports`.
11. Use `Load playlist` to restore a saved playlist. Saved media paths are used first; managed-library filenames and embedded funscript data are used as fallbacks.
12. Use `Save to funscript` only for the funscript content itself. Playlist-only Lovense rules are not written into `.funscript` files.
13. Choose `Sequential` or `Random` playlist mode.
14. Load and play the video. Rule scripts execute automatically during playback.

Saved playlists keep the video and funscript source paths, global Lovense users/device profiles, active users per entry, and each user's per-entry rule script. The same `.funscript` can therefore appear in multiple saved playlists while each playlist uses different Lovense programs.

## Common Problems

### No Lovense devices are detected

- On desktop, try the default local setup first: `HTTPS`, `127.0.0.1`, port `30010`.
- On phone-based setups, switch to `HTTP` and use the phone IP and port shown by the Lovense app.
- Confirm any first-time Lovense permission popup before retrying detection.
- Check the Diagnostics panel in the UI and the local log file if detection still fails.

### The wrong files were selected

- Video selection accepts video files only.
- Funscript selection should contain `.funscript` or `.json` only.
- On Android, FHPlayer rejects unsupported files after the picker returns them.

### Save to funscript does not overwrite the original file

- Direct overwrite depends on browser or Android document access support.
- If overwrite is unavailable, use the exported file from the managed `Exports` folder.

### Playback triggers nothing

- Verify that at least one real or simulated device is selected.
- Review the live rule validation status before starting playback.
- If the player overlay shows `RESUME`, click it to continue Lovense live execution after an emergency stop.

### The app starts but the UI does not load correctly

- Check the Diagnostics panel or `%LOCALAPPDATA%\FHPlayer\Logs\fhplayer.log` on desktop.
- Run `.\scripts\smoke_test.ps1` or `.\scripts\release_check.ps1 -SkipAndroidInstall` if you want a full local verification pass.

## File Matching

- FHPlayer first tries to match videos and `funscript` files by the same base filename.
- `scene-01.mp4` and `scene_01.funscript` also match correctly.
- Remaining unmatched files are paired in their selection order.

## Lovense Rules

FHPlayer uses a small Lovense rule language per playlist entry.

Example:

```text
let level = pos * 0.5 + 2
if level >= 15 then [Nora Simulator] vibrate(level) + [Max 2] pump(2)
else if pos >= 5 then delay(250) + [sim-nora] rotate(3, 800) + vibrate(5, 800)
else stop()
```

Supported condition variables:

- `pos`
- `index`
- `atMs`
- `currentMs`
- `deltaMs`

Supported comparison operators:

- `==`
- `!=`
- `>=`
- `<=`
- `>`
- `<`

You can join comparisons with `and` and `or`.

You can declare simple numeric variables before the rule branches:

```text
let level = pos * 0.5 + 2
let delayedLevel = level - 3
```

Supported arithmetic operators inside variables, conditions, action values, and delays:

- `+`
- `-`
- `*`
- `:` (division)

Examples:

```text
let level = pos * 0.4 + 1
if level >= 15 and index > 20 then vibrate(level)
else if pos == 5 then delay(500) + stop()
```

You can target specific selected devices by putting a selector in front of the action:

- `[Nora Simulator] vibrate(10, 800)`
- `[sim-nora] rotate(3, 400)`
- `[Max 2] pump(2)`

Without a selector, an action still applies to all selected devices. Selectors can use the visible device name or the device ID from the dropdown and live rule status.

Supported Lovense actions depend on the addressed device capabilities. Actions without a selector must be supported by all selected devices. Examples:

- `vibrate(10)`
- `rotate(4)`
- `pump(3)`
- `thrusting(12)`
- `fingering(8)`
- `suction(6)`
- `depth(2)`
- `stroke(50)`
- `oscillate(8)`
- `all(10)`
- `stop()`

Current value ranges in the UI and validator are:

- `all(0-20)`
- `vibrate(0-20)`
- `rotate(0-20)`
- `pump(0-3)`
- `thrusting(0-20)`
- `fingering(0-20)`
- `suction(0-20)`
- `depth(0-3)`
- `stroke(0-100)`
- `oscillate(0-20)`
- `stop()`

You can add an optional duration in milliseconds as the second action argument:

- `vibrate(10, 250)`
- `rotate(level, 500)`

Use a separate `delay(ms)` command when the whole branch should start later:

- `delay(200) + vibrate(10, 600)`
- `delay(500) + stop()`

If a device supports multiple functions at once, combine them with `+`:

```text
let level = pos * 0.5
if pos >= 15 then delay(250) + [Nora] vibrate(level, 900) + [Max 2] pump(2)
else stop()
```

FHPlayer validates the selected user's rule script against that user's active live device selection, or against that user's simulated test selection in `Lovense test`. Before saving a playlist entry, all active users are validated. Durations on action commands must be `0` or at least `200` ms; values between `1` and `199` ms are rejected after variables are resolved. The UI shows:

- detected device types
- shared capabilities plus the capabilities of each selected device
- shared parallel-action limit plus the per-device parallel-action limits
- unique action ranges for the current selection without duplicate entries
- the available device selectors as `Name [ID]`

Lovense user settings are stored globally in the playlist, including:

- one or more user profiles
- the selected profile
- one or more selected live devices per user
- one or more selected simulated devices per user for `Lovense test`
- shared detected capabilities per live connection

Each playlist entry stores which global users are active and the rule script for each active user. The playlist list shows the available Lovense users for live and test entries; use those checkboxes to decide which users are active for each video.

## Funscript Defaults

FHPlayer can optionally read its own settings directly from the `funscript`. Supported fields include:

```json
{
  "executionMode": "lovense-live",
  "rulesText": "if pos >= 15 then vibrate(10)\nelse stop()"
}
```

The same values also work under:

```json
{
  "fhplayer": {
    "executionMode": "lovense-live",
    "rulesText": "if pos >= 15 then vibrate(10)\nelse stop()"
  }
}
```

If the form still contains the default values, FHPlayer automatically uses these settings for the new playlist entry.

When you select one or more `funscript` files in the form, FHPlayer also applies the saved metadata from the first selected script to the current UI immediately. This avoids overwriting saved values accidentally before adding the entry to the playlist.

New Lovense rule scripts and device/profile assignments are saved in `.fhplaylist` files, not in `.funscript` files. When the browser supports the File System Access API, `Save to funscript` lets you overwrite the target funscript directly, but FHPlayer strips playlist-only rule metadata from that output. Otherwise FHPlayer falls back to downloading the cleaned `.funscript` file.

## Safety

FHPlayer sends exactly the Lovense actions defined by your rules. Therefore:

- test rule behavior in `Lovense test` mode first
- only use trusted `funscript` files
- verify live Lovense rules before using them with real devices
