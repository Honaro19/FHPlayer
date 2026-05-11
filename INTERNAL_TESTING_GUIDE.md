# Internal Testing Guide

This guide documents the repeatable local test flow for FHPlayer development on Windows, including Flutter and Android emulator checks.

## Scope

Use this guide before merging larger changes and before creating release artifacts.

## Prerequisites

- Windows PowerShell
- Python 3.10+
- Node.js + npm
- Flutter SDK available at `C:\Dev\flutter` (or adjust commands)
- Android SDK platform-tools (`adb`) and at least one running emulator for install/launch checks

## Fast Pre-Check (recommended for every change)

Run from repository root:

```powershell
.\scripts\test_rule_engine.ps1
```

```powershell
.\scripts\test_flutter.ps1 -Reporter compact
```

```powershell
C:\Dev\flutter\bin\cache\dart-sdk\bin\dart.exe C:\Dev\flutter\bin\cache\flutter_tools.snapshot analyze
```

Expected result:

- Rule tests pass
- Flutter tests pass
- `dart analyze` returns no errors

## Full Smoke Check

Run the full smoke suite:

```powershell
.\scripts\smoke_test.ps1
```

Useful variants:

```powershell
.\scripts\smoke_test.ps1 -SkipWindowsInstaller
```

```powershell
.\scripts\smoke_test.ps1 -SkipAndroidInstall
```

```powershell
.\scripts\smoke_test.ps1 -AndroidDeviceSerial emulator-5554
```

## Android Emulator Verification (Flutter app)

1. Verify emulator connectivity:

```powershell
adb devices
```

2. Build debug APK:

```powershell
.\scripts\android_flutter\build_debug_apk.ps1
```

3. Install and launch on emulator:

```powershell
.\scripts\android_flutter\install_debug_apk.ps1 -LaunchApp -DeviceSerial emulator-5554
```

4. Confirm process is running:

```powershell
adb -s emulator-5554 shell pidof com.fhplayer.mobile
```

Expected result:

- APK build succeeds
- install script reports success
- `pidof` returns a numeric PID

## Known Flutter Hang / Lock Issue

Symptom:

- `flutter.bat` appears to hang without useful output.

Cause:

- Batch launcher lock handling can stall when lockfiles or sandbox permissions block write/delete operations.

Workarounds:

1. Use logged wrapper first:

```powershell
.\scripts\test_flutter.ps1 -Reporter expanded
```

Logs are written to:

- `.tmp\flutter-logs\*.out.log`
- `.tmp\flutter-logs\*.err.log`
- `.tmp\flutter-logs\*.meta.log`

2. If launcher hangs, run tools directly through Dart snapshot:

```powershell
C:\Dev\flutter\bin\cache\dart-sdk\bin\dart.exe C:\Dev\flutter\bin\cache\flutter_tools.snapshot test --reporter expanded
```

```powershell
C:\Dev\flutter\bin\cache\dart-sdk\bin\dart.exe C:\Dev\flutter\bin\cache\flutter_tools.snapshot analyze
```

3. If errors mention `PathAccessException` under `build\unit_test_assets`, rerun in a less restricted context.

## CI-Relevant Minimum

Before pushing changes that touch Flutter or Android:

1. `scripts\test_rule_engine.ps1`
2. `scripts\test_flutter.ps1 -Reporter compact`
3. `dart.exe ... flutter_tools.snapshot analyze`
4. `scripts\smoke_test.ps1 -SkipWindowsInstaller` (or full smoke if release-adjacent)

## Result Recording (internal)

For each verification run, store:

- Commit/branch
- Commands executed
- Pass/fail per command
- For failures: first relevant error line and log path

This keeps regressions reproducible and shortens handover/debug time.
