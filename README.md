# FHPlayer

FHPlayer is a local video player that plays videos in the browser and triggers Lovense actions at the timestamps defined in `funscript` files. Multiple video/funscript pairs can be loaded as a playlist and played sequentially or randomly.

## Features

- Load multiple videos with matching `funscript` files as a playlist
- Play the playlist sequentially or randomly
- Read `funscript` files and display all contained actions
- Choose between `Lovense live` and `Lovense test` per playlist entry
- Connect to Lovense over configurable protocol, host/IP, and port
- Store multiple Lovense connection profiles per playlist entry for different users or hosts
- Detect one or more connected Lovense devices per user profile with their supported capabilities
- Validate Lovense rules so untargeted actions are shared-compatible and targeted actions match the addressed devices
- Run multiple Lovense actions at the same time on every selected device when their shared functions allow it
- Address individual selected devices by name or ID inside Lovense rules
- Show live rule validation, detected device types, and allowed parallel action count in the UI
- Test Lovense rules locally with simulated devices directly in Lovense test mode
- Read optional defaults directly from the `funscript`
- Use dry-run mode to test without sending real Lovense requests
- No artificial 1-second limit between triggers: closely spaced actions are sent to the backend in parallel
- View a log of triggered Lovense requests and responses

## Start

Requirement: Python 3.10 or newer

```powershell
python app.py
```

After that, the app is available at `http://127.0.0.1:8765`. The browser opens automatically by default.

On startup FHPlayer creates a managed library under:

- Windows desktop: `%LOCALAPPDATA%\FHPlayer\Library\Videos`, `%LOCALAPPDATA%\FHPlayer\Library\Funscripts`, `%LOCALAPPDATA%\FHPlayer\Library\Exports`
- Android app: app-managed `Library/Videos`, `Library/Funscripts`, and `Library/Exports` folders inside the app storage area

## Windows EXE

You can package FHPlayer as a Windows `.exe` with PyInstaller.

Install the build dependency:

```powershell
pip install -r requirements-build.txt
```

Create the executable:

```powershell
.\build_windows.ps1
```

Or with double-click / Command Prompt:

```cmd
build_windows.cmd
```

The result is written to `dist\FHPlayer\FHPlayer.exe`.
If copying the finished build back into the project folder fails, the script keeps the working output in `%TEMP%\FHPlayer-PyInstaller-<timestamp>\dist\FHPlayer\FHPlayer.exe`.

The Windows build now also uses `assets\branding\fhplayer.ico`. If that icon file does not exist yet, `build_windows.ps1` generates a branded placeholder icon automatically.

Current branding assets:

- Windows EXE / installer: `assets\branding\fhplayer.ico`
- Source image for branding work: `assets\branding\fhplayer-icon-256.png`

## Windows Installer

You can build a per-user Windows installer with Inno Setup 6:

```powershell
.\build_windows_installer.ps1
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
dist-installer\FHPlayer-Setup.exe
```

## Mobile Version

FHPlayer now includes an Android app target in `FHPlayerMobile/android`.

The Android build wraps the existing browser UI inside a native `WebView` app and starts a small embedded local HTTP server for the static files plus the Lovense API bridge. File selection uses the native Android document picker.

Build the debug APK with:

```powershell
FHPlayerMobile\android\build_debug_apk.ps1
```

Or with double-click / Command Prompt:

```cmd
FHPlayerMobile\android\build_debug_apk.cmd
```

The APK is written to:

```text
%LOCALAPPDATA%\FHPlayer\AndroidBuild\app\outputs\apk\debug\app-debug.apk
```

Install the APK onto a connected emulator or Android device with:

```powershell
FHPlayerMobile\android\install_debug_apk.ps1 -LaunchApp
```

Or with double-click / Command Prompt:

```cmd
FHPlayerMobile\android\install_debug_apk.cmd
```

Current Android limitations:

- `Lovense live` and `Lovense test` remain available through the embedded backend.
- Video and `.funscript` pairing still works once both files are selected, but Android does not automatically scan sibling files from the filesystem by filename.
- The Android installer artifact is the APK itself. For a distributable release build, add a release keystore and build a signed release APK.
- On first app start FHPlayer creates the managed `Library\Videos`, `Library\Funscripts`, and `Library\Exports` folders inside the app storage area.

## Usage

1. Load one or more video files.
2. Load the matching `funscript` files.
   Saved FHPlayer metadata from the first selected `funscript` is applied to the form immediately.
3. Optional: click `Import selected files` to copy the currently selected videos and funscripts into the managed FHPlayer library folders shown in the UI.
4. Choose the execution mode for new playlist entries.
5. For `Lovense live`, choose or create a user profile, configure protocol, host/IP, port, platform name, detect devices, select one or more devices for that profile, and enter the rule script.
   On desktop the default profile uses `HTTPS` with `127.0.0.1:30010`.
6. For phone-based Lovense setups, switch to `HTTP` when needed and enter the phone IP and port shown by the Lovense app.
   With `Lovense Remote` on PC, the pairing/permission popup may appear only the first time you connect FHPlayer to that Lovense host. After you confirm it once, later detections may connect without showing the popup again.
7. For `Lovense test`, pick one or more simulated devices from the normal device dropdown and reuse the same rule editor. On desktop, multi-select uses `Ctrl` + click on Windows/Linux or `Cmd` + click on macOS.
8. Click `Add to playlist`.
9. If needed, adjust the selected entry and click `Save selected entry`.
10. Click `Save to funscript` if you want to write the current Lovense settings back into the matching script file.
   If direct file saving is unavailable, FHPlayer stores the updated file in the managed `Exports` folder instead.
11. Choose playlist mode `Sequential` or `Random`.
12. Test with `Dry Run` enabled first.
13. Click `Enable execution` and start the video.

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

FHPlayer validates the selected rule script against the active live device selection or simulated test selection before saving or playback. The UI shows:

- detected device types
- shared capabilities plus the capabilities of each selected device
- shared parallel-action limit plus the per-device parallel-action limits
- unique action ranges for the current selection without duplicate entries
- the available device selectors as `Name [ID]`

Lovense connection settings are stored per playlist entry, including:

- one or more live connection profiles
- the selected live connection profile
- one or more selected devices per live connection
- one or more selected simulated devices for test mode
- shared detected capabilities per live connection

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

FHPlayer can also write the current entry settings back into the funscript under `metadata.fhplayer`:

```json
{
  "metadata": {
    "fhplayer": {
      "schemaVersion": 2,
      "executionMode": "lovense-live",
      "rulesText": "if pos >= 15 then vibrate(10)\nelse stop()",
      "lovense": {
        "selectedConnectionId": "user-1",
        "connections": [
          {
            "id": "user-1",
            "label": "User 1",
            "scheme": "https",
            "host": "127.0.0.1",
            "port": "30010",
            "platformName": "FHPlayer",
            "selectedToys": [
              {
                "id": "xxxx",
                "name": "Nora",
                "nickName": "Nora",
                "type": "Nora",
                "fullFunctionNames": ["Vibrate", "Rotate"]
              },
              {
                "id": "yyyy",
                "name": "Max 2",
                "nickName": "Max 2",
                "type": "Max 2",
                "fullFunctionNames": ["Vibrate", "Pump"]
              }
            ],
            "toyId": "xxxx",
            "toyName": "Nora",
            "toyType": "Nora",
            "capabilities": ["Vibrate"]
          }
        ],
        "testSelectedToys": [
          {
            "id": "sim-nora",
            "name": "Nora Simulator",
            "nickName": "Nora Simulator",
            "type": "Nora",
            "fullFunctionNames": ["Vibrate", "Rotate"]
          }
        ],
        "testToyId": "sim-nora",
        "testToyName": "Nora Simulator",
        "testToyType": "Nora",
        "testCapabilities": ["Vibrate", "Rotate"]
      }
    }
  }
}
```

When the browser supports the File System Access API, `Save to funscript` lets you overwrite the target file directly. Otherwise FHPlayer falls back to downloading the updated `.funscript` file.

## Safety

FHPlayer sends exactly the Lovense actions defined by your rules. Therefore:

- test with `Dry Run` first
- only use trusted `funscript` files
- verify live Lovense rules before using them with real devices
