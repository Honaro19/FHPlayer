param(
  [string]$BuildDir = "",
  [string]$OutputDir = ""
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

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$appVersion = Get-AppVersion -ProjectRoot $projectRoot
$gradle = Get-ChildItem "$env:USERPROFILE\.gradle\wrapper\dists\gradle-8.0.2-bin" -Recurse -Filter gradle.bat |
  Select-Object -First 1 -ExpandProperty FullName

if (-not $gradle) {
  throw "Gradle 8.0.2 was not found in the local wrapper cache. Open any Android project once in Android Studio or install Gradle 8.0.2."
}

$resolvedBuildDir = if ($BuildDir) {
  Resolve-AbsolutePath -Path $BuildDir -BasePath (Get-Location).Path
} else {
  Join-Path $env:LOCALAPPDATA "FHPlayer\AndroidBuild\app"
}
$resolvedOutputDir = if ($OutputDir) {
  Resolve-AbsolutePath -Path $OutputDir -BasePath (Get-Location).Path
} else {
  Join-Path $projectRoot "installers\android"
}
New-Item -ItemType Directory -Force -Path $resolvedBuildDir | Out-Null
New-Item -ItemType Directory -Force -Path $resolvedOutputDir | Out-Null

$generatedAssetDirs = @(
  (Join-Path $PSScriptRoot "app\build\generated\fhplayer-assets"),
  (Join-Path $PSScriptRoot "app\build\intermediates\assets\debug\www"),
  (Join-Path $resolvedBuildDir "generated\fhplayer-assets"),
  (Join-Path $resolvedBuildDir "intermediates\assets\debug\www")
)

foreach ($assetDir in $generatedAssetDirs) {
  if (Test-Path $assetDir) {
    Remove-Item -LiteralPath $assetDir -Recurse -Force
  }
}

& $gradle -p $PSScriptRoot "-PfhplayerBuildDir=$resolvedBuildDir" clean assembleDebug

if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

$apkPath = Join-Path $resolvedBuildDir "outputs\apk\debug\app-debug.apk"
$finalApkPath = Join-Path $resolvedOutputDir "FHPlayer-$appVersion-debug.apk"
if (Test-Path $apkPath) {
  Copy-Item -LiteralPath $apkPath -Destination $finalApkPath -Force
  Write-Host "APK created at $apkPath"
  Write-Host "Installer output: $finalApkPath"
} else {
  Write-Warning "Gradle finished, but no APK was found at $apkPath"
}
