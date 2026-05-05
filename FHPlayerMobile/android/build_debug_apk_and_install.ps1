param(
  [string]$BuildDir = "",
  [string]$OutputDir = "",
  [string]$DeviceSerial = "",
  [switch]$LaunchApp
)

$ErrorActionPreference = "Stop"

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

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent (Split-Path -Parent $scriptRoot)
$resolvedBuildDir = Resolve-AbsolutePath -Path $BuildDir -BasePath (Get-Location).Path
$resolvedOutputDir = Resolve-AbsolutePath -Path $OutputDir -BasePath (Get-Location).Path
$appVersion = Get-AppVersion -ProjectRoot $projectRoot

$buildArgs = @()
if ($resolvedBuildDir) { $buildArgs += "-BuildDir"; $buildArgs += $resolvedBuildDir }
if ($resolvedOutputDir) { $buildArgs += "-OutputDir"; $buildArgs += $resolvedOutputDir }

Write-Host "Building debug APK..."
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot "build_debug_apk.ps1") @buildArgs
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$apkPath = if ($resolvedOutputDir) {
  Join-Path $resolvedOutputDir "FHPlayer-$appVersion-debug.apk"
} else {
  Join-Path $projectRoot "installers\android\FHPlayer-$appVersion-debug.apk"
}

$installArgs = @()
if ($resolvedBuildDir) { $installArgs += "-BuildDir"; $installArgs += $resolvedBuildDir }
$installArgs += "-ApkPath"; $installArgs += $apkPath
if ($DeviceSerial) { $installArgs += "-DeviceSerial"; $installArgs += $DeviceSerial }
if ($LaunchApp) { $installArgs += "-LaunchApp" }

Write-Host "Installing debug APK to emulator/device..."
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptRoot "install_debug_apk.ps1") @installArgs
exit $LASTEXITCODE
