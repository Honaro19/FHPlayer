param(
  [string]$BuildDir = "",
  [string]$OutputDir = "",
  [string]$FlutterRoot = ""
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
  if ($appVersion -notmatch '^(\d+)\.(\d+)\.(\d+)$') {
    throw "VERSION must use major.minor.patch. Found: $appVersion"
  }

  return $appVersion
}

function Get-AppVersionCode {
  param([string]$AppVersion)

  if ($AppVersion -notmatch '^(\d+)\.(\d+)\.(\d+)$') {
    throw "VERSION must use major.minor.patch. Found: $AppVersion"
  }

  return ([int]$matches[1] * 10000) + ([int]$matches[2] * 100) + ([int]$matches[3])
}

function Resolve-FlutterRoot {
  param([string]$ExplicitRoot)

  $candidates = @(
    $ExplicitRoot,
    $env:FHPLAYER_FLUTTER_ROOT,
    $env:FLUTTER_ROOT,
    "C:\\Dev\\flutter"
  ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

  foreach ($candidate in $candidates) {
    $resolved = Resolve-AbsolutePath -Path $candidate -BasePath (Get-Location).Path
    $snapshotPath = Join-Path $resolved "bin\\cache\\flutter_tools.snapshot"
    $dartPath = Join-Path $resolved "bin\\cache\\dart-sdk\\bin\\dart.exe"
    if ((Test-Path $snapshotPath) -and (Test-Path $dartPath)) {
      return $resolved
    }
  }

  throw "Flutter SDK not found. Set -FlutterRoot, FHPLAYER_FLUTTER_ROOT, or FLUTTER_ROOT."
}

function Resolve-BuiltApkPath {
  param(
    [string]$BuildDirPath,
    [string]$FlutterProjectPath
  )

  $candidates = @(
    (Join-Path $BuildDirPath "app\\outputs\\flutter-apk\\app-debug.apk"),
    (Join-Path $FlutterProjectPath "build\\app\\outputs\\flutter-apk\\app-debug.apk")
  )

  foreach ($candidate in $candidates) {
    if (Test-Path $candidate) {
      return $candidate
    }
  }

  $fallback = Get-ChildItem -Path $BuildDirPath -Recurse -Filter app-debug.apk -ErrorAction SilentlyContinue |
    Select-Object -First 1 -ExpandProperty FullName
  if ($fallback) {
    return $fallback
  }

  throw "Gradle finished, but no debug APK was found."
}

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$flutterProjectPath = Join-Path $projectRoot "fhplayer_flutter"
if (-not (Test-Path $flutterProjectPath)) {
  throw "Flutter project not found: $flutterProjectPath"
}

$appVersion = Get-AppVersion -ProjectRoot $projectRoot
$appVersionCode = Get-AppVersionCode -AppVersion $appVersion
$resolvedBuildDir = Join-Path $flutterProjectPath "build"
$resolvedOutputDir = if ($OutputDir) {
  Resolve-AbsolutePath -Path $OutputDir -BasePath (Get-Location).Path
} else {
  Join-Path $projectRoot "installers\\android"
}
$resolvedFlutterRoot = Resolve-FlutterRoot -ExplicitRoot $FlutterRoot

New-Item -ItemType Directory -Force -Path $resolvedOutputDir | Out-Null

$dartPath = Join-Path $resolvedFlutterRoot "bin\\cache\\dart-sdk\\bin\\dart.exe"
$snapshotPath = Join-Path $resolvedFlutterRoot "bin\\cache\\flutter_tools.snapshot"
$arguments = @(
  $snapshotPath,
  "build",
  "apk",
  "--debug",
  "--no-pub",
  "--build-name",
  $appVersion,
  "--build-number",
  "$appVersionCode"
)

if ($BuildDir) {
  Write-Warning "The current Flutter toolchain does not support --build-dir for apk builds; using the default build directory."
}

$env:FLUTTER_SUPPRESS_ANALYTICS = "true"
$env:DART_SUPPRESS_ANALYTICS = "true"

Push-Location $flutterProjectPath
try {
  & $dartPath @arguments
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }
} finally {
  Pop-Location
}

$apkPath = Resolve-BuiltApkPath -BuildDirPath $resolvedBuildDir -FlutterProjectPath $flutterProjectPath
$finalApkPath = Join-Path $resolvedOutputDir "FHPlayer-$appVersion-debug.apk"
Copy-Item -LiteralPath $apkPath -Destination $finalApkPath -Force

Write-Host "Flutter debug APK: $apkPath"
Write-Host "Installer output: $finalApkPath"
