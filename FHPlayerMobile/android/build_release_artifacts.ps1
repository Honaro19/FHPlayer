param(
  [string]$BuildDir = "",
  [string]$OutputDir = "",
  [ValidateSet("Auto", "Require", "Skip")]
  [string]$SigningMode = "Auto",
  [string]$SigningPropertiesPath = "",
  [switch]$SkipApk,
  [switch]$SkipBundle
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

function Resolve-GradleLauncher {
  $gradle = Get-ChildItem "$env:USERPROFILE\.gradle\wrapper\dists\gradle-8.0.2-bin" -Recurse -Filter gradle.bat |
    Select-Object -First 1 -ExpandProperty FullName

  if (-not $gradle) {
    throw "Gradle 8.0.2 was not found in the local wrapper cache. Open any Android project once in Android Studio or install Gradle 8.0.2."
  }

  return $gradle
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

if ($SkipApk -and $SkipBundle) {
  throw "At least one release artifact must be enabled. Remove -SkipApk or -SkipBundle."
}

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$appVersion = Get-AppVersion -ProjectRoot $projectRoot
$gradle = Resolve-GradleLauncher
$resolvedBuildDir = if ($BuildDir) {
  Resolve-AbsolutePath -Path $BuildDir -BasePath (Get-Location).Path
} else {
  Join-Path $env:LOCALAPPDATA "FHPlayer\AndroidReleaseBuild\app"
}
$resolvedOutputDir = if ($OutputDir) {
  Resolve-AbsolutePath -Path $OutputDir -BasePath (Get-Location).Path
} else {
  Join-Path $projectRoot "installers\android"
}
$resolvedSigningPropertiesPath = if ($SigningPropertiesPath) {
  Resolve-AbsolutePath -Path $SigningPropertiesPath -BasePath (Get-Location).Path
} else {
  Join-Path $PSScriptRoot "release-signing.properties"
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
  Write-Warning "No Android release signing configuration was found. Building unsigned release artifacts."
}

New-Item -ItemType Directory -Force -Path $resolvedBuildDir | Out-Null
New-Item -ItemType Directory -Force -Path $resolvedOutputDir | Out-Null

$generatedAssetDirs = @(
  (Join-Path $PSScriptRoot "app\build\generated\fhplayer-assets"),
  (Join-Path $PSScriptRoot "app\build\intermediates\assets\debug\www"),
  (Join-Path $PSScriptRoot "app\build\intermediates\assets\release\www"),
  (Join-Path $resolvedBuildDir "generated\fhplayer-assets"),
  (Join-Path $resolvedBuildDir "intermediates\assets\debug\www"),
  (Join-Path $resolvedBuildDir "intermediates\assets\release\www")
)

foreach ($assetDir in $generatedAssetDirs) {
  if (Test-Path $assetDir) {
    Remove-Item -LiteralPath $assetDir -Recurse -Force
  }
}

$gradleArguments = @(
  "-p", $PSScriptRoot,
  "-PfhplayerBuildDir=$resolvedBuildDir",
  "-PfhplayerReleaseSigningMode=$normalizedSigningMode"
)
if (Test-Path $resolvedSigningPropertiesPath) {
  $gradleArguments += "-PfhplayerReleaseSigningProperties=$resolvedSigningPropertiesPath"
}

$gradleTasks = @("clean")
if (-not $SkipApk) {
  $gradleTasks += "assembleRelease"
}
if (-not $SkipBundle) {
  $gradleTasks += "bundleRelease"
}

& $gradle @gradleArguments @gradleTasks

if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

if (-not $SkipApk) {
  $apkCandidates = @(
    (Join-Path $resolvedBuildDir "outputs\apk\release\app-release.apk"),
    (Join-Path $resolvedBuildDir "outputs\apk\release\app-release-unsigned.apk")
  )
  $apkPath = $apkCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
  if (-not $apkPath) {
    throw "Gradle finished, but no release APK was found under $resolvedBuildDir\outputs\apk\release"
  }

  $finalApkPath = Join-Path $resolvedOutputDir "FHPlayer-$appVersion.apk"
  Copy-Item -LiteralPath $apkPath -Destination $finalApkPath -Force
  Write-Host "Release APK: $finalApkPath"
}

if (-not $SkipBundle) {
  $aabPath = Join-Path $resolvedBuildDir "outputs\bundle\release\app-release.aab"
  if (-not (Test-Path $aabPath)) {
    throw "Gradle finished, but no release App Bundle was found at $aabPath"
  }

  $finalAabPath = Join-Path $resolvedOutputDir "FHPlayer-$appVersion.aab"
  Copy-Item -LiteralPath $aabPath -Destination $finalAabPath -Force
  Write-Host "Release AAB: $finalAabPath"
}

Write-Host "Signing mode: $SigningMode"
Write-Host "Signing configured: $hasReleaseSigning"
