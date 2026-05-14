param(
  [switch]$SkipPythonDesktop,
  [switch]$SkipWindowsExe,
  [switch]$SkipWindowsInstaller,
  [switch]$SkipAndroid,
  [switch]$SkipAndroidInstall,
  [string]$AndroidDeviceSerial = "",
  [string]$SmokeRoot = "",
  [switch]$KeepArtifacts
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Write-Step {
  param([string]$Message)

  Write-Host ""
  Write-Host "==> $Message"
}

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

function Invoke-CheckedCommand {
  param(
    [string]$FilePath,
    [string[]]$Arguments = @(),
    [string]$WorkingDirectory,
    [hashtable]$Environment = @{}
  )

  $resolvedWorkingDirectory = if ($WorkingDirectory) { $WorkingDirectory } else { (Get-Location).Path }
  $savedEnvironment = @{}
  $didPushLocation = $false
  $isPowerShellScript = [string]::Equals([System.IO.Path]::GetExtension($FilePath), ".ps1", [System.StringComparison]::OrdinalIgnoreCase)
  foreach ($key in $Environment.Keys) {
    $savedEnvironment[$key] = [Environment]::GetEnvironmentVariable($key, "Process")
    [Environment]::SetEnvironmentVariable($key, [string]$Environment[$key], "Process")
  }

  try {
    Push-Location $resolvedWorkingDirectory
    $didPushLocation = $true
    Write-Host "> $FilePath $($Arguments -join ' ')"
    if ($isPowerShellScript) {
      & powershell -NoProfile -ExecutionPolicy Bypass -File $FilePath @Arguments
      if ($LASTEXITCODE -ne 0) {
        throw "Command failed with exit code ${LASTEXITCODE}: $FilePath"
      }
    } else {
      & $FilePath @Arguments
      if ($LASTEXITCODE -ne 0) {
        throw "Command failed with exit code ${LASTEXITCODE}: $FilePath"
      }
    }
  } finally {
    if ($didPushLocation) {
      Pop-Location
    }
    foreach ($key in $savedEnvironment.Keys) {
      [Environment]::SetEnvironmentVariable($key, $savedEnvironment[$key], "Process")
    }
  }
}

function Save-FileSnapshot {
  param(
    [string]$Path,
    [string]$SnapshotRoot
  )

  $snapshotPath = Join-Path $SnapshotRoot ([System.IO.Path]::GetFileName($Path) + ".bak")
  $snapshot = @{
    OriginalPath = $Path
    SnapshotPath = $snapshotPath
    Existed = $false
  }

  if (Test-Path $Path) {
    New-Item -ItemType Directory -Force -Path $SnapshotRoot | Out-Null
    Copy-Item -LiteralPath $Path -Destination $snapshotPath -Force
    $snapshot.Existed = $true
  }

  return $snapshot
}

function Restore-FileSnapshot {
  param([hashtable]$Snapshot)

  if ($Snapshot.Existed) {
    Copy-Item -LiteralPath $Snapshot.SnapshotPath -Destination $Snapshot.OriginalPath -Force
    return
  }

  if (Test-Path $Snapshot.OriginalPath) {
    Remove-Item -LiteralPath $Snapshot.OriginalPath -Force
  }
}

function Wait-ForPath {
  param(
    [string]$Path,
    [int]$TimeoutSeconds = 10
  )

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    if (Test-Path $Path) {
      return $true
    }
    Start-Sleep -Milliseconds 250
  }

  return (Test-Path $Path)
}

function Wait-ForAndroidProcessId {
  param(
    [string]$AdbPath,
    [string]$DeviceSerial,
    [string]$PackageName,
    [int]$TimeoutSeconds = 15
  )

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    $result = & $AdbPath -s $DeviceSerial shell pidof $PackageName
    $processIdText = if ($null -eq $result) { "" } else { (("$result") -join "").Trim() }
    if ($processIdText) {
      return $processIdText
    }
    Start-Sleep -Milliseconds 500
  }

  return $null
}

function ConvertTo-ProcessArgument {
  param([string]$Argument)

  if ($null -eq $Argument) {
    return '""'
  }

  if ($Argument -notmatch '[\s"]') {
    return $Argument
  }

  $escaped = $Argument -replace '(\\*)"', '$1$1\"'
  $escaped = $escaped -replace '(\\+)$', '$1$1'
  return '"' + $escaped + '"'
}

function Start-AppProcessSmoke {
  param(
    [string]$FilePath,
    [string[]]$Arguments = @(),
    [string]$WorkingDirectory,
    [string]$Name,
    [int]$StartupDelaySeconds = 4
  )

  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $FilePath
  $psi.Arguments = (($Arguments | ForEach-Object { ConvertTo-ProcessArgument -Argument $_ }) -join " ")
  $psi.WorkingDirectory = $WorkingDirectory
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true

  $process = [System.Diagnostics.Process]::Start($psi)
  if (-not $process) {
    throw "Could not start process: $Name"
  }

  Start-Sleep -Seconds $StartupDelaySeconds
  $process.Refresh()
  if ($process.HasExited) {
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    throw "$Name exited too early. ExitCode=$($process.ExitCode) STDOUT=$stdout STDERR=$stderr"
  }

  return $process
}

function Stop-AppProcessSmoke {
  param([System.Diagnostics.Process]$Process)

  if ($Process -and -not $Process.HasExited) {
    $Process.Kill()
    $Process.WaitForExit()
  }
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

$projectRoot = Split-Path -Parent $PSScriptRoot
$appVersion = Get-AppVersion -ProjectRoot $projectRoot
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$smokeRoot = if ($SmokeRoot) {
  if ([System.IO.Path]::IsPathRooted($SmokeRoot)) {
    [System.IO.Path]::GetFullPath($SmokeRoot)
  } else {
    [System.IO.Path]::GetFullPath((Join-Path $projectRoot $SmokeRoot))
  }
} else {
  Join-Path $projectRoot ".tmp\smoke-tests\$timestamp"
}
$windowsExeOutputRoot = Join-Path $smokeRoot "windows-exe-output"
$windowsInstallerOutputDir = Join-Path $smokeRoot "windows-installer-output"
$windowsInstallerTempRoot = Join-Path $smokeRoot "windows-installer-temp"
$windowsInstallerBuildOutputRoot = Join-Path $smokeRoot "windows-installer-build-output"
$installerInstallRoot = Join-Path $smokeRoot "installer-app"
$installerLogPath = Join-Path $smokeRoot "installer.log"
$androidOutputDir = Join-Path $smokeRoot "android-output"
$summary = [System.Collections.Generic.List[string]]::new()

if ($SkipPythonDesktop) {
  Write-Warning "-SkipPythonDesktop is deprecated and ignored. The desktop app smoke test now targets Flutter Windows only."
}

New-Item -ItemType Directory -Force -Path $smokeRoot | Out-Null

try {
  if (-not $SkipWindowsExe) {
    Write-Step "Build and smoke test Windows Flutter EXE"
    New-Item -ItemType Directory -Force -Path $windowsExeOutputRoot | Out-Null
    Invoke-CheckedCommand `
      -FilePath (Join-Path $projectRoot "build_windows.ps1") `
      -Arguments @("-OutputRoot", $windowsExeOutputRoot) `
      -WorkingDirectory $projectRoot `
      -Environment @{
        FHPLAYER_NO_PAUSE = "1"
      }

    $exePath = Join-Path $windowsExeOutputRoot "dist\FHPlayer\FHPlayer.exe"
    if (-not (Test-Path $exePath)) {
      throw "Missing built Windows EXE at $exePath"
    }

    $exeSmoke = Start-AppProcessSmoke `
      -FilePath $exePath `
      -WorkingDirectory (Split-Path $exePath -Parent) `
      -Name "Windows EXE"
    try {
      $summary.Add("Windows EXE: ok")
    } finally {
      Stop-AppProcessSmoke -Process $exeSmoke
    }
  }

  if (-not $SkipWindowsInstaller) {
    Write-Step "Build and smoke test Windows installer"
    $brandingSnapshotRoot = Join-Path $smokeRoot "branding-snapshots"
    $brandingSnapshots = @(
      (Save-FileSnapshot -Path (Join-Path $projectRoot "assets\branding\fhplayer-icon-256.png") -SnapshotRoot $brandingSnapshotRoot),
      (Save-FileSnapshot -Path (Join-Path $projectRoot "assets\branding\fhplayer.ico") -SnapshotRoot $brandingSnapshotRoot)
    )

    try {
      Invoke-CheckedCommand `
        -FilePath (Join-Path $projectRoot "build_windows_installer.ps1") `
        -Arguments @(
          "-OutputDir", $windowsInstallerOutputDir,
          "-TempRoot", $windowsInstallerTempRoot,
          "-WindowsBuildOutputRoot", $(if ($SkipWindowsExe) { $windowsInstallerBuildOutputRoot } else { $windowsExeOutputRoot })
        ) `
        -WorkingDirectory $projectRoot `
        -Environment @{
          FHPLAYER_NO_PAUSE = "1"
        }
    } finally {
      foreach ($snapshot in $brandingSnapshots) {
        Restore-FileSnapshot -Snapshot $snapshot
      }
    }

    $setupPath = Join-Path $windowsInstallerOutputDir "FHPlayer-Setup.exe"
    if (-not (Test-Path $setupPath)) {
      throw "Missing built Windows installer at $setupPath"
    }

    New-Item -ItemType Directory -Force -Path $installerInstallRoot | Out-Null
    Invoke-CheckedCommand `
      -FilePath $setupPath `
      -Arguments @(
        "/VERYSILENT",
        "/SUPPRESSMSGBOXES",
        "/NORESTART",
        "/SP-",
        "/NOICONS",
        "/DIR=$installerInstallRoot",
        "/LOG=$installerLogPath"
      ) `
      -WorkingDirectory $projectRoot

    $installedExe = Join-Path $installerInstallRoot "FHPlayer.exe"
    if (-not (Wait-ForPath -Path $installedExe -TimeoutSeconds 15)) {
      throw "Installed EXE not found at $installedExe"
    }

    $installerSmoke = Start-AppProcessSmoke `
      -FilePath $installedExe `
      -WorkingDirectory $installerInstallRoot `
      -Name "Installed Windows EXE"
    try {
      $summary.Add("Windows installer: ok")
    } finally {
      Stop-AppProcessSmoke -Process $installerSmoke
    }

    $uninstallerPath = Join-Path $installerInstallRoot "unins000.exe"
    if (Test-Path $uninstallerPath) {
      Invoke-CheckedCommand `
        -FilePath $uninstallerPath `
        -Arguments @("/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART") `
        -WorkingDirectory $installerInstallRoot
    }
  }

  if (-not $SkipAndroid) {
    Write-Step "Build Android debug APK"
    Invoke-CheckedCommand `
      -FilePath (Join-Path $projectRoot "scripts\android_flutter\build_debug_apk.ps1") `
      -Arguments @("-OutputDir", $androidOutputDir) `
      -WorkingDirectory $projectRoot `
      -Environment @{
        FHPLAYER_NO_PAUSE = "1"
      }

    $apkPath = Join-Path $androidOutputDir "FHPlayer-$appVersion-debug.apk"
    if (-not (Test-Path $apkPath)) {
      throw "Missing built Android APK at $apkPath"
    }
    $summary.Add("Android APK build: ok")

    if (-not $SkipAndroidInstall) {
      Write-Step "Install and launch Android debug APK"
      $adbPath = Resolve-AdbPath
      $onlineDevices = @(Get-AdbOnlineDevices -AdbPath $adbPath)
      $targetDeviceSerial = $AndroidDeviceSerial
      if (-not $targetDeviceSerial) {
        if ($onlineDevices.Count -eq 1) {
          $targetDeviceSerial = $onlineDevices[0]
        } elseif ($onlineDevices.Count -eq 0) {
          throw "No adb device or emulator is connected. Use -SkipAndroidInstall to skip this step."
        } else {
          throw "Multiple adb devices are connected ($($onlineDevices -join ', ')). Use -AndroidDeviceSerial to choose one."
        }
      }

      Invoke-CheckedCommand `
        -FilePath (Join-Path $projectRoot "scripts\android_flutter\install_debug_apk.ps1") `
        -Arguments @("-ApkPath", $apkPath, "-DeviceSerial", $targetDeviceSerial, "-LaunchApp") `
        -WorkingDirectory $projectRoot

      $androidProcessId = Wait-ForAndroidProcessId -AdbPath $adbPath -DeviceSerial $targetDeviceSerial -PackageName "com.fhplayer.mobile" -TimeoutSeconds 20
      if (-not $androidProcessId) {
        throw "Android app process was not found after launch on $targetDeviceSerial."
      }

      Write-Host "Android app PID: $androidProcessId"
      $summary.Add("Android install and launch: ok")
    }
  }

  Write-Step "Smoke test summary"
  foreach ($line in $summary) {
    Write-Host "- $line"
  }
} finally {
  if ($KeepArtifacts) {
    Write-Host ""
    Write-Host "Smoke test artifacts kept at $smokeRoot"
  } elseif (Test-Path $smokeRoot) {
    Remove-Item -LiteralPath $smokeRoot -Recurse -Force -ErrorAction SilentlyContinue
  }
}
