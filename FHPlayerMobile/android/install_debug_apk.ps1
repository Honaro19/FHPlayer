param(
  [string]$DeviceSerial = "",
  [switch]$LaunchApp
)

$ErrorActionPreference = "Stop"

function Resolve-AdbPath {
  $sdkAdb = Join-Path $env:LOCALAPPDATA "Android\Sdk\platform-tools\adb.exe"
  if (Test-Path $sdkAdb) {
    return $sdkAdb
  }

  $adbCommand = Get-Command adb -ErrorAction SilentlyContinue
  if ($adbCommand) {
    return $adbCommand.Source
  }

  throw "adb was not found. Install Android platform-tools or Android Studio first."
}

function Invoke-Adb {
  param(
    [string]$AdbPath,
    [string[]]$Arguments
  )

  if ($DeviceSerial) {
    & $AdbPath -s $DeviceSerial @Arguments
  } else {
    & $AdbPath @Arguments
  }
}

function Get-AdbOnlineDevices {
  param([string]$AdbPath)

  $lines = & $AdbPath devices
  if ($LASTEXITCODE -ne 0) {
    throw "adb devices failed."
  }

  return $lines |
    Select-Object -Skip 1 |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ } |
    ForEach-Object {
      $parts = $_ -split "\s+"
      if ($parts.Length -ge 2 -and $parts[1] -eq "device") {
        $parts[0]
      }
    }
}

try {
  $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
  $buildDir = Join-Path $env:LOCALAPPDATA "FHPlayer\AndroidBuild\app"
  $apkPath = Join-Path $buildDir "outputs\apk\debug\app-debug.apk"
  $adbPath = Resolve-AdbPath
  $onlineDevices = @(Get-AdbOnlineDevices -AdbPath $adbPath)
  $onlineDeviceSummary = if ($onlineDevices.Count) { $onlineDevices -join ", " } else { "none" }

  if ($DeviceSerial) {
    if ($onlineDevices -notcontains $DeviceSerial) {
      throw "The requested adb device '$DeviceSerial' is not connected. Online devices: $onlineDeviceSummary"
    }
  } elseif (-not $onlineDevices.Count) {
    throw "No adb device or emulator is connected."
  } elseif ($onlineDevices.Count -gt 1) {
    throw "Multiple adb devices are connected ($onlineDeviceSummary). Use -DeviceSerial to choose one."
  }

  if (-not (Test-Path $apkPath)) {
    $env:FHPLAYER_NO_PAUSE = "1"
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot "build_debug_apk.ps1")
    if ($LASTEXITCODE -ne 0) {
      throw "APK build failed."
    }
  }

  if (-not (Test-Path $apkPath)) {
    throw "No debug APK was found at $apkPath"
  }

  Invoke-Adb -AdbPath $adbPath -Arguments @("install", "-r", $apkPath)
  if ($LASTEXITCODE -ne 0) {
    throw "adb install failed."
  }

  if ($LaunchApp) {
    Invoke-Adb -AdbPath $adbPath -Arguments @("shell", "am", "start", "-n", "com.fhplayer.mobile/.MainActivity")
    if ($LASTEXITCODE -ne 0) {
      throw "The APK was installed, but launching the app failed."
    }
  }

  Write-Host ""
  Write-Host "FHPlayer debug APK installed successfully."
  Write-Host "APK: $apkPath"
  if ($DeviceSerial) {
    Write-Host "Device: $DeviceSerial"
  }
} catch {
  Write-Error $_
  exit 1
}
