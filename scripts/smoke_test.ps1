param(
  [switch]$SkipPythonDesktop,
  [switch]$SkipWindowsExe,
  [switch]$SkipWindowsInstaller,
  [switch]$SkipAndroid,
  [switch]$SkipAndroidInstall,
  [string]$AndroidDeviceSerial = "",
  [switch]$KeepArtifacts
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Write-Step {
  param([string]$Message)

  Write-Host ""
  Write-Host "==> $Message"
}

function Resolve-PythonCommand {
  if (Get-Command py -ErrorAction SilentlyContinue) {
    return "py"
  }

  if (Get-Command python -ErrorAction SilentlyContinue) {
    return "python"
  }

  throw "Python launcher not found. Install Python 3.10+ first."
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

function Test-HealthEndpoint {
  param([string]$Url)

  try {
    $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 2
    if ($response.StatusCode -eq 200) {
      return $response.Content
    }
  } catch {
    return $null
  }

  return $null
}

function Assert-PortFree {
  param([string]$Url)

  $response = Test-HealthEndpoint -Url $Url
  if ($response) {
    throw "Smoke test port is already in use: $Url"
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

function Start-SmokeProcess {
  param(
    [string]$FilePath,
    [string[]]$Arguments = @(),
    [string]$WorkingDirectory,
    [hashtable]$Environment = @{},
    [string]$Name,
    [string]$HealthUrl
  )

  Assert-PortFree -Url $HealthUrl

  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $FilePath
  $psi.Arguments = (($Arguments | ForEach-Object { ConvertTo-ProcessArgument -Argument $_ }) -join " ")
  $psi.WorkingDirectory = $WorkingDirectory
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true

  foreach ($key in $Environment.Keys) {
    $psi.Environment[$key] = [string]$Environment[$key]
  }

  $process = [System.Diagnostics.Process]::Start($psi)
  if (-not $process) {
    throw "Could not start smoke test process: $Name"
  }

  for ($attempt = 0; $attempt -lt 20; $attempt++) {
    Start-Sleep -Milliseconds 500
    $response = Test-HealthEndpoint -Url $HealthUrl
    if ($response) {
      return @{
        Process = $process
        Response = $response
      }
    }

    if ($process.HasExited) {
      break
    }
  }

  $stdout = $process.StandardOutput.ReadToEnd()
  $stderr = $process.StandardError.ReadToEnd()
  if (-not $process.HasExited) {
    $process.Kill()
    $process.WaitForExit()
  }

  throw "$Name did not become healthy. ExitCode=$($process.ExitCode) STDOUT=$stdout STDERR=$stderr"
}

function Stop-SmokeProcess {
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
$healthUrl = "http://127.0.0.1:8765/api/health"
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$smokeRoot = Join-Path $projectRoot ".tmp\smoke-tests\$timestamp"
$desktopLocalAppData = Join-Path $smokeRoot "desktop-localappdata"
$windowsExeOutputRoot = Join-Path $smokeRoot "windows-exe-output"
$windowsExeTempRoot = Join-Path $smokeRoot "windows-exe-temp"
$exeLocalAppData = Join-Path $smokeRoot "exe-localappdata"
$windowsInstallerOutputDir = Join-Path $smokeRoot "windows-installer-output"
$windowsInstallerTempRoot = Join-Path $smokeRoot "windows-installer-temp"
$windowsInstallerBuildOutputRoot = Join-Path $smokeRoot "windows-installer-build-output"
$installerLocalAppData = Join-Path $smokeRoot "installer-localappdata"
$installerInstallRoot = Join-Path $smokeRoot "installer-app"
$installerLogPath = Join-Path $smokeRoot "installer.log"
$androidBuildDir = Join-Path $smokeRoot "android-build\app"
$androidOutputDir = Join-Path $smokeRoot "android-output"
$summary = [System.Collections.Generic.List[string]]::new()

New-Item -ItemType Directory -Force -Path $smokeRoot | Out-Null

try {
  if (-not $SkipPythonDesktop) {
    Write-Step "Smoke test desktop Python app"
    New-Item -ItemType Directory -Force -Path $desktopLocalAppData | Out-Null
    $pythonCommand = Resolve-PythonCommand
    $pythonSmoke = Start-SmokeProcess `
      -FilePath $pythonCommand `
      -Arguments @("app.py") `
      -WorkingDirectory $projectRoot `
      -Environment @{
        FHPLAYER_NO_BROWSER = "1"
        LOCALAPPDATA = $desktopLocalAppData
      } `
      -Name "Python desktop app" `
      -HealthUrl $healthUrl
    try {
      Write-Host $pythonSmoke.Response
      $summary.Add("Python desktop app: ok")
    } finally {
      Stop-SmokeProcess -Process $pythonSmoke.Process
    }
  }

  if (-not $SkipWindowsExe) {
    Write-Step "Build and smoke test Windows EXE"
    New-Item -ItemType Directory -Force -Path $windowsExeTempRoot, $windowsExeOutputRoot, $exeLocalAppData | Out-Null
    Invoke-CheckedCommand `
      -FilePath (Join-Path $projectRoot "build_windows.ps1") `
      -Arguments @("-OutputRoot", $windowsExeOutputRoot, "-TempRoot", $windowsExeTempRoot) `
      -WorkingDirectory $projectRoot `
      -Environment @{
        FHPLAYER_NO_PAUSE = "1"
      }

    $exePath = Join-Path $windowsExeOutputRoot "dist\FHPlayer\FHPlayer.exe"
    if (-not (Test-Path $exePath)) {
      throw "Missing built Windows EXE at $exePath"
    }

    $exeSmoke = Start-SmokeProcess `
      -FilePath $exePath `
      -WorkingDirectory (Split-Path $exePath -Parent) `
      -Environment @{
        FHPLAYER_NO_BROWSER = "1"
        LOCALAPPDATA = $exeLocalAppData
      } `
      -Name "Windows EXE" `
      -HealthUrl $healthUrl
    try {
      Write-Host $exeSmoke.Response
      $summary.Add("Windows EXE: ok")
    } finally {
      Stop-SmokeProcess -Process $exeSmoke.Process
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

    New-Item -ItemType Directory -Force -Path $installerInstallRoot, $installerLocalAppData | Out-Null
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

    $installerSmoke = Start-SmokeProcess `
      -FilePath $installedExe `
      -WorkingDirectory $installerInstallRoot `
      -Environment @{
        FHPLAYER_NO_BROWSER = "1"
        LOCALAPPDATA = $installerLocalAppData
      } `
      -Name "Installed Windows EXE" `
      -HealthUrl $healthUrl
    try {
      Write-Host $installerSmoke.Response
      $summary.Add("Windows installer: ok")
    } finally {
      Stop-SmokeProcess -Process $installerSmoke.Process
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
      -FilePath (Join-Path $projectRoot "FHPlayerMobile\android\build_debug_apk.ps1") `
      -Arguments @("-BuildDir", $androidBuildDir, "-OutputDir", $androidOutputDir) `
      -WorkingDirectory (Join-Path $projectRoot "FHPlayerMobile\android") `
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
        -FilePath (Join-Path $projectRoot "FHPlayerMobile\android\install_debug_apk.ps1") `
        -Arguments @("-ApkPath", $apkPath, "-DeviceSerial", $targetDeviceSerial, "-LaunchApp") `
        -WorkingDirectory (Join-Path $projectRoot "FHPlayerMobile\android")

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
