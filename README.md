# FHPlayer

FHPlayer is a local video player that plays videos in the browser and executes system commands at the timestamps defined in `funscript` files. Multiple video/funscript pairs can be loaded as a playlist and played sequentially or randomly.

## Features

- Load multiple videos with matching `funscript` files as a playlist
- Play the playlist sequentially or randomly
- Read `funscript` files and display all contained actions
- Store an individual command for each playlist entry
- Choose between shell commands and Lovense rule execution per playlist entry
- Connect to Lovense over configurable protocol, host/IP, and port
- Detect the connected Lovense device type and its supported capabilities
- Validate Lovense rules so only actions supported by the selected device can be used
- Run multiple Lovense actions at the same time on devices that support multiple functions
- Show live rule validation, detected device type, and allowed parallel action count in the UI
- Use placeholders such as `{{atMs}}`, `{{pos}}`, or `{{index}}` inside commands
- Read optional defaults directly from the `funscript`
- Use dry-run mode to test without executing real commands
- No artificial 1-second limit between triggers: closely spaced actions are sent to the backend in parallel
- View a log with return code, runtime, `stdout`, and `stderr`

## Start

Requirement: Python 3.10 or newer

```powershell
python app.py
```

After that, the app is available at `http://127.0.0.1:8765`. The browser opens automatically by default.

## Usage

1. Load one or more video files.
2. Load the matching `funscript` files.
3. Choose the execution mode for new playlist entries.
4. For shell mode, configure shell, timeout, and command template.
5. For Lovense mode, configure protocol, host/IP, port, platform name, detect the device, and enter the rule script.
6. For phone-based Lovense setups, switch to `HTTP` when needed and enter the phone IP and port shown by the Lovense app.
7. Click `Add to playlist`.
8. If needed, adjust the selected entry and click `Save selected entry`.
9. Click `Save to funscript` if you want to write the current command settings back into the matching script file.
10. Choose playlist mode `Sequential` or `Random`.
11. Test with `Dry Run` enabled first.
12. Click `Enable execution` and start the video.

## File Matching

- FHPlayer first tries to match videos and `funscript` files by the same base filename.
- `scene-01.mp4` and `scene_01.funscript` also match correctly.
- Remaining unmatched files are paired in their selection order.

## Available Placeholders

- `{{index}}`: action index
- `{{atMs}}`: target timestamp of the action in milliseconds
- `{{pos}}`: `pos` value from the funscript
- `{{currentMs}}`: current video position when triggered
- `{{deltaMs}}`: difference between video time and action timestamp
- `{{previousAtMs}}`: timestamp of the previous action
- `{{nextAtMs}}`: timestamp of the next action
- `{{entryTitle}}`: title of the current playlist entry

## Example Commands

PowerShell:

```powershell
Write-Output "Action {{index}} at {{atMs}}ms pos={{pos}}"
```

CMD:

```cmd
echo Action {{index}} at {{atMs}}ms pos={{pos}}
```

Direct without shell:

```text
notepad.exe
```

Note: In `Direct without shell` mode, the text is started using argument splitting. For complex commands with pipes, variables, or redirections, use `PowerShell` or `CMD`.

## Lovense Rules

Lovense mode uses a small rule language instead of raw shell commands.

Example:

```text
let level = pos * 0.5 + 2
if level >= 15 then vibrate(level)
else if pos >= 5 then vibrate(5) + rotate(3, 250)
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
else if pos == 5 then stop(500)
```

Supported Lovense actions depend on the detected device capabilities, for example:

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

You can add an optional delay in milliseconds as the second action argument:

- `vibrate(10, 250)`
- `rotate(level, 500)`
- `stop(300)`

If a device supports multiple functions at once, combine them with `+`:

```text
let level = pos * 0.5
if pos >= 15 then vibrate(level) + rotate(3, 250)
else stop()
```

FHPlayer validates the selected rule script against the detected device before saving or playback. The UI shows:

- detected device type
- supported capabilities
- whether only a single action or multiple parallel actions are allowed

Lovense connection settings are stored per playlist entry, including:

- protocol
- host / IP
- port
- platform name
- selected toy ID and type
- detected capabilities

## Funscript Defaults

FHPlayer can optionally read its own settings directly from the `funscript`. Supported fields include:

```json
{
  "commandTemplate": "Write-Output \"{{entryTitle}} {{pos}}\"",
  "shell": "powershell",
  "timeoutSeconds": 2.5
}
```

The same values also work under:

```json
{
  "fhplayer": {
    "commandTemplate": "Write-Output \"{{entryTitle}} {{pos}}\"",
    "shell": "powershell",
    "timeoutSeconds": 2.5
  }
}
```

If the form still contains the default values, FHPlayer automatically uses these settings for the new playlist entry.

FHPlayer can also write the current entry settings back into the funscript under `metadata.fhplayer`:

```json
{
  "metadata": {
    "fhplayer": {
      "schemaVersion": 2,
      "executionMode": "lovense-rules",
      "commandTemplate": "Write-Output \"{{entryTitle}} {{pos}}\"",
      "shell": "powershell",
      "timeoutSeconds": 2.5,
      "rulesText": "if pos >= 15 then vibrate(10)\nelse stop()",
      "lovense": {
        "scheme": "https",
        "host": "127-0-0-1.lovense.club",
        "port": "30010",
        "platformName": "FHPlayer",
        "toyId": "xxxx",
        "toyName": "Nora",
        "toyType": "nora",
        "capabilities": ["Vibrate", "Rotate"]
      }
    }
  }
}
```

When the browser supports the File System Access API, `Save to funscript` lets you overwrite the target file directly. Otherwise FHPlayer falls back to downloading the updated `.funscript` file.

## Safety

FHPlayer executes exactly the commands you enter into the template. Therefore:

- test with `Dry Run` first
- only use trusted `funscript` files
- do not enter commands that change your system in unwanted ways
