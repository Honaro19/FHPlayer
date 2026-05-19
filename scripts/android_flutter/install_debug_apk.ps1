param(
  [string]$BuildDir = "",
  [string]$ApkPath = "",
  [string]$DeviceSerial = "",
  [string]$FlutterRoot = "",
  [switch]$LaunchApp
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Resolve-AbsolutePath {
  param(
    [string]$Path,
    [string]$BasePath
  )

  if ([string]::IsNullOrWhiteSpace($Path)) {
    return $null
  }

  if ([System.IO.Path]::IsPathRooted($Path)) {
    return [System.IO.Path]::GetFullPath($Path)
  }

  return [System.IO.Path]::GetFullPath((Join-Path $BasePath $Path))
}

function Get-AppVersion {
  param([string]$ProjectRoot)

  $versionPath = Join-Path $ProjectRoot "VERSION"
  if (-not (Test-Path $versionPath)) {
    throw "Missing VERSION file at $versionPath"
  }

  $appVersion = (Get-Content -LiteralPath $versionPath -Raw).Trim()
  if ($appVersion -notmatch '^\d+\.\d+\.\d+$') {
    throw "VERSION must use major.minor.patch. Found: $appVersion"
  }

  return $appVersion
}

function Resolve-AdbPath {
  $sdkAdb = Join-Path $env:LOCALAPPDATA "Android\\Sdk\\platform-tools\\adb.exe"
  if (Test-Path $sdkAdb) {
    return $sdkAdb
  }

  $adbCommand = Get-Command adb -ErrorAction SilentlyContinue
  if ($adbCommand) {
    return $adbCommand.Source
  }

  throw "adb was not found. Install Android platform-tools or Android Studio first."
}

function Get-AdbOnlineDevices {
  param([string]$AdbPath)

  $lines = & $AdbPath devices
  if ($LASTEXITCODE -ne 0) {
    throw "adb devices failed."
  }

  return @(
    $lines |
      Select-Object -Skip 1 |
      ForEach-Object { $_.Trim() } |
      Where-Object { $_ } |
      ForEach-Object {
        $parts = $_ -split "\s+"
        if ($parts.Length -ge 2 -and $parts[1] -eq "device") {
          $parts[0]
        }
      }
  )
}

function Get-AdbDeviceStatus {
  param(
    [string]$AdbPath,
    [string]$Serial
  )

  $lines = & $AdbPath devices
  if ($LASTEXITCODE -ne 0) {
    throw "adb devices failed."
  }

  foreach ($line in ($lines | Select-Object -Skip 1)) {
    $trimmed = $line.Trim()
    if (-not $trimmed) {
      continue
    }

    $parts = $trimmed -split "\s+"
    if ($parts.Length -ge 2 -and $parts[0] -eq $Serial) {
      return $parts[1]
    }
  }

  return $null
}

function Invoke-Adb {
  param(
    [string]$AdbPath,
    [string[]]$Arguments,
    [string]$Serial
  )

  if ($Serial) {
    & $AdbPath -s $Serial @Arguments
  } else {
    & $AdbPath @Arguments
  }
}

function Wait-ForAdbDeviceReady {
  param(
    [string]$AdbPath,
    [string]$Serial,
    [int]$TimeoutSeconds = 30
  )

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    $status = Get-AdbDeviceStatus -AdbPath $AdbPath -Serial $Serial
    if ($status -eq "device") {
      return $true
    }
    Start-Sleep -Seconds 1
  }

  return $false
}

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$appVersion = Get-AppVersion -ProjectRoot $projectRoot
$resolvedBuildDir = if ($BuildDir) {
  Resolve-AbsolutePath -Path $BuildDir -BasePath (Get-Location).Path
} else {
  Join-Path $projectRoot ".tmp\\flutter-android-build\\debug"
}
$resolvedApkPath = if ($ApkPath) {
  Resolve-AbsolutePath -Path $ApkPath -BasePath (Get-Location).Path
} else {
  Join-Path $projectRoot "installers\\android\\FHPlayer-$appVersion-debug.apk"
}

if (-not (Test-Path $resolvedApkPath)) {
  if ($ApkPath) {
    throw "No debug APK was found at $resolvedApkPath"
  }

  $buildArguments = @("-BuildDir", $resolvedBuildDir)
  if ($FlutterRoot) {
    $buildArguments += @("-FlutterRoot", $FlutterRoot)
  }

  & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "build_debug_apk.ps1") @buildArguments
  if ($LASTEXITCODE -ne 0) {
    throw "Flutter debug APK build failed."
  }
}

if (-not (Test-Path $resolvedApkPath)) {
  throw "No debug APK was found at $resolvedApkPath"
}

$adbPath = Resolve-AdbPath
$onlineDevices = @(Get-AdbOnlineDevices -AdbPath $adbPath)
$targetDeviceSerial = $DeviceSerial
if (-not $targetDeviceSerial) {
  if ($onlineDevices.Count -eq 1) {
    $targetDeviceSerial = $onlineDevices[0]
  } elseif ($onlineDevices.Count -eq 0) {
    throw "No adb device or emulator is connected."
  } else {
    throw "Multiple adb devices are connected ($($onlineDevices -join ', ')). Use -DeviceSerial to choose one."
  }
}

if ($onlineDevices -notcontains $targetDeviceSerial) {
  $deviceStatus = Get-AdbDeviceStatus -AdbPath $adbPath -Serial $targetDeviceSerial
  if (-not $deviceStatus) {
    throw "The requested adb device '$targetDeviceSerial' is not connected. Online devices: $($onlineDevices -join ', ')"
  }
}

for ($attempt = 1; $attempt -le 3; $attempt++) {
  if (-not (Wait-ForAdbDeviceReady -AdbPath $adbPath -Serial $targetDeviceSerial -TimeoutSeconds 30)) {
    Write-Warning "adb device '$targetDeviceSerial' is not ready (attempt $attempt/3). Trying to reconnect."
    & $adbPath reconnect offline | Out-Null
    & $adbPath start-server | Out-Null
    Start-Sleep -Seconds 2
    continue
  }

  Invoke-Adb -AdbPath $adbPath -Serial $targetDeviceSerial -Arguments @("install", "-r", $resolvedApkPath)
  if ($LASTEXITCODE -eq 0) {
    break
  }

  if ($attempt -lt 3) {
    Write-Warning "adb install failed on attempt $attempt/3. Retrying after reconnect."
    & $adbPath reconnect offline | Out-Null
    & $adbPath start-server | Out-Null
    Start-Sleep -Seconds 2
    continue
  }

  throw "adb install failed."
}

if ($LaunchApp) {
  Invoke-Adb -AdbPath $adbPath -Serial $targetDeviceSerial -Arguments @("shell", "am", "start", "-n", "com.fhplayer.mobile/.MainActivity")
  if ($LASTEXITCODE -ne 0) {
    throw "The APK was installed, but launching the app failed."
  }
}

Write-Host ""
Write-Host "Flutter debug APK installed successfully."
Write-Host "APK: $resolvedApkPath"
Write-Host "Device: $targetDeviceSerial"
