param(
  [string]$BuildDir = "",
  [string]$OutputDir = "",
  [ValidateSet("Auto", "Require", "Skip")]
  [string]$SigningMode = "Auto",
  [string]$SigningPropertiesPath = "",
  [switch]$SkipApk,
  [switch]$SkipBundle,
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

function Read-PropertiesFile {
  param([string]$Path)

  $properties = @{}
  if (-not (Test-Path $Path)) {
    return $properties
  }

  foreach ($line in Get-Content -LiteralPath $Path) {
    $trimmedLine = $line.Trim()
    if (-not $trimmedLine -or $trimmedLine.StartsWith("#")) {
      continue
    }

    $separatorIndex = $trimmedLine.IndexOf("=")
    if ($separatorIndex -lt 1) {
      continue
    }

    $key = $trimmedLine.Substring(0, $separatorIndex).Trim()
    $value = $trimmedLine.Substring($separatorIndex + 1).Trim()
    if ($key) {
      $properties[$key] = $value
    }
  }

  return $properties
}

function Get-SigningValue {
  param(
    [string]$GradleKey,
    [string]$EnvironmentKey,
    [hashtable]$Properties
  )

  $environmentValue = [Environment]::GetEnvironmentVariable($EnvironmentKey)
  if (-not [string]::IsNullOrWhiteSpace($environmentValue)) {
    return $environmentValue.Trim()
  }
  if ($Properties.ContainsKey($GradleKey) -and $Properties[$GradleKey]) {
    return [string]$Properties[$GradleKey]
  }
  return ""
}

function Resolve-BuiltArtifact {
  param(
    [string[]]$Candidates,
    [string]$BuildDirPath,
    [string]$Filter
  )

  foreach ($candidate in $Candidates) {
    if (Test-Path $candidate) {
      return $candidate
    }
  }

  $fallback = Get-ChildItem -Path $BuildDirPath -Recurse -Filter $Filter -ErrorAction SilentlyContinue |
    Select-Object -First 1 -ExpandProperty FullName
  if ($fallback) {
    return $fallback
  }

  throw "Built artifact not found ($Filter)."
}

if ($SkipApk -and $SkipBundle) {
  throw "At least one release artifact must be enabled. Remove -SkipApk or -SkipBundle."
}

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$flutterProjectPath = Join-Path $projectRoot "FHPlayerMobile\\fhplayer_flutter"
$flutterAndroidPath = Join-Path $flutterProjectPath "android"
$appVersion = Get-AppVersion -ProjectRoot $projectRoot
$appVersionCode = Get-AppVersionCode -AppVersion $appVersion
$resolvedBuildDir = Join-Path $flutterProjectPath "build"
$resolvedOutputDir = if ($OutputDir) {
  Resolve-AbsolutePath -Path $OutputDir -BasePath (Get-Location).Path
} else {
  Join-Path $projectRoot "installers\\android"
}
$resolvedSigningPropertiesPath = if ($SigningPropertiesPath) {
  Resolve-AbsolutePath -Path $SigningPropertiesPath -BasePath (Get-Location).Path
} else {
  Join-Path $flutterAndroidPath "release-signing.properties"
}
$normalizedSigningMode = $SigningMode.ToLowerInvariant()
$signingProperties = Read-PropertiesFile -Path $resolvedSigningPropertiesPath
$hasReleaseSigning =
  -not [string]::IsNullOrWhiteSpace((Get-SigningValue -GradleKey "fhplayerReleaseStoreFile" -EnvironmentKey "FHPLAYER_ANDROID_KEYSTORE_PATH" -Properties $signingProperties)) -and
  -not [string]::IsNullOrWhiteSpace((Get-SigningValue -GradleKey "fhplayerReleaseStorePassword" -EnvironmentKey "FHPLAYER_ANDROID_KEYSTORE_PASSWORD" -Properties $signingProperties)) -and
  -not [string]::IsNullOrWhiteSpace((Get-SigningValue -GradleKey "fhplayerReleaseKeyAlias" -EnvironmentKey "FHPLAYER_ANDROID_KEY_ALIAS" -Properties $signingProperties)) -and
  -not [string]::IsNullOrWhiteSpace((Get-SigningValue -GradleKey "fhplayerReleaseKeyPassword" -EnvironmentKey "FHPLAYER_ANDROID_KEY_PASSWORD" -Properties $signingProperties))

if ($normalizedSigningMode -eq "require" -and -not $hasReleaseSigning) {
  throw "Android release signing was required, but no complete signing configuration was found."
}
if ($normalizedSigningMode -eq "auto" -and -not $hasReleaseSigning) {
  Write-Warning "No Android release signing configuration was found. Building release artifacts with debug signing."
}

$resolvedFlutterRoot = Resolve-FlutterRoot -ExplicitRoot $FlutterRoot
New-Item -ItemType Directory -Force -Path $resolvedOutputDir | Out-Null

$dartPath = Join-Path $resolvedFlutterRoot "bin\\cache\\dart-sdk\\bin\\dart.exe"
$snapshotPath = Join-Path $resolvedFlutterRoot "bin\\cache\\flutter_tools.snapshot"
$env:FLUTTER_SUPPRESS_ANALYTICS = "true"
$env:DART_SUPPRESS_ANALYTICS = "true"
$env:FHPLAYER_ANDROID_SIGNING_MODE = $normalizedSigningMode
if (Test-Path $resolvedSigningPropertiesPath) {
  $env:FHPLAYER_ANDROID_SIGNING_PROPERTIES_PATH = $resolvedSigningPropertiesPath
}
if ($BuildDir) {
  Write-Warning "The current Flutter toolchain does not support --build-dir for release artifacts; using the default build directory."
}

if (-not $SkipApk) {
  Push-Location $flutterProjectPath
  try {
    & $dartPath $snapshotPath build apk --release --no-pub --build-name $appVersion --build-number "$appVersionCode"
    if ($LASTEXITCODE -ne 0) {
      exit $LASTEXITCODE
    }
  } finally {
    Pop-Location
  }

  $apkPath = Resolve-BuiltArtifact -BuildDirPath $resolvedBuildDir -Filter "app-release*.apk" -Candidates @(
    (Join-Path $resolvedBuildDir "app\\outputs\\flutter-apk\\app-release.apk"),
    (Join-Path $resolvedBuildDir "app\\outputs\\flutter-apk\\app-release-unsigned.apk"),
    (Join-Path $flutterProjectPath "build\\app\\outputs\\flutter-apk\\app-release.apk"),
    (Join-Path $flutterProjectPath "build\\app\\outputs\\flutter-apk\\app-release-unsigned.apk")
  )
  $finalApkPath = Join-Path $resolvedOutputDir "FHPlayer-$appVersion.apk"
  Copy-Item -LiteralPath $apkPath -Destination $finalApkPath -Force
  Write-Host "Release APK: $finalApkPath"
}

if (-not $SkipBundle) {
  Push-Location $flutterProjectPath
  try {
    & $dartPath $snapshotPath build appbundle --release --no-pub --build-name $appVersion --build-number "$appVersionCode"
    if ($LASTEXITCODE -ne 0) {
      exit $LASTEXITCODE
    }
  } finally {
    Pop-Location
  }

  $aabPath = Resolve-BuiltArtifact -BuildDirPath $resolvedBuildDir -Filter "app-release.aab" -Candidates @(
    (Join-Path $resolvedBuildDir "app\\outputs\\bundle\\release\\app-release.aab"),
    (Join-Path $flutterProjectPath "build\\app\\outputs\\bundle\\release\\app-release.aab")
  )
  $finalAabPath = Join-Path $resolvedOutputDir "FHPlayer-$appVersion.aab"
  Copy-Item -LiteralPath $aabPath -Destination $finalAabPath -Force
  Write-Host "Release AAB: $finalAabPath"
}

Write-Host "Signing mode: $SigningMode"
Write-Host "Signing configured: $hasReleaseSigning"
