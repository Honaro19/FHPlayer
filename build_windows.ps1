param(
  [string]$OutputRoot = "",
  [string]$TempRoot = "",
  [string]$FlutterRoot = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Wait-BeforeExit {
  if (-not $env:FHPLAYER_NO_PAUSE) {
    Write-Host ""
    Read-Host "Press Enter to close"
  }
}

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

  $flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
  if ($flutterCommand) {
    $flutterExecutable = [System.IO.Path]::GetFullPath($flutterCommand.Source)
    $flutterRoot = Split-Path -Parent (Split-Path -Parent $flutterExecutable)
    $snapshotPath = Join-Path $flutterRoot "bin\\cache\\flutter_tools.snapshot"
    $dartPath = Join-Path $flutterRoot "bin\\cache\\dart-sdk\\bin\\dart.exe"
    if ((Test-Path $snapshotPath) -and (Test-Path $dartPath)) {
      return $flutterRoot
    }
  }

  throw "Flutter SDK not found. Set -FlutterRoot, FHPLAYER_FLUTTER_ROOT, or FLUTTER_ROOT."
}

function Resolve-WindowsBundlePath {
  param([string]$FlutterProjectPath)

  $candidates = @(
    (Join-Path $FlutterProjectPath "build\\windows\\x64\\runner\\Release"),
    (Join-Path $FlutterProjectPath "build\\windows\\runner\\Release")
  )

  foreach ($candidate in $candidates) {
    if ((Test-Path $candidate) -and (Test-Path (Join-Path $candidate "FHPlayer.exe"))) {
      return $candidate
    }
  }

  foreach ($candidate in $candidates) {
    if (Test-Path $candidate) {
      $fallbackExe = Get-ChildItem -Path $candidate -Filter "*.exe" -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notlike "*unins*.exe" } |
        Select-Object -First 1
      if ($fallbackExe) {
        return $candidate
      }
    }
  }

  throw "Flutter build finished, but no Windows release bundle was found."
}

function Reset-StaleWindowsBuildCache {
  param([string]$FlutterProjectPath)

  $windowsBuildDir = Join-Path $FlutterProjectPath "build\\windows"
  if (-not (Test-Path $windowsBuildDir)) {
    return
  }

  # The project location changed and stale CMake cache entries may still reference old absolute paths.
  # Old CMake cache entries can keep absolute source paths and break subsequent builds.
  Remove-Item -LiteralPath $windowsBuildDir -Recurse -Force
}

try {
  $projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
  $flutterProjectPath = Join-Path $projectRoot "fhplayer_flutter"
  if (-not (Test-Path $flutterProjectPath)) {
    throw "Flutter project not found: $flutterProjectPath"
  }

  $appVersion = Get-AppVersion -ProjectRoot $projectRoot
  $appVersionCode = Get-AppVersionCode -AppVersion $appVersion
  $resolvedOutputRoot = if ($OutputRoot) {
    Resolve-AbsolutePath -Path $OutputRoot -BasePath $projectRoot
  } else {
    $projectRoot
  }
  $resolvedFlutterRoot = Resolve-FlutterRoot -ExplicitRoot $FlutterRoot

  $distDir = Join-Path $resolvedOutputRoot "dist"
  $distAppDir = Join-Path $distDir "FHPlayer"

  New-Item -ItemType Directory -Force -Path $resolvedOutputRoot, $distDir | Out-Null

  $dartPath = Join-Path $resolvedFlutterRoot "bin\\cache\\dart-sdk\\bin\\dart.exe"
  $snapshotPath = Join-Path $resolvedFlutterRoot "bin\\cache\\flutter_tools.snapshot"
  $arguments = @(
    $snapshotPath,
    "build",
    "windows",
    "--release",
    "--no-pub",
    "--build-name",
    $appVersion,
    "--build-number",
    "$appVersionCode"
  )

  $env:FLUTTER_SUPPRESS_ANALYTICS = "true"
  $env:DART_SUPPRESS_ANALYTICS = "true"

  Reset-StaleWindowsBuildCache -FlutterProjectPath $flutterProjectPath

  Push-Location $flutterProjectPath
  try {
    & $dartPath @arguments
    if ($LASTEXITCODE -ne 0) {
      exit $LASTEXITCODE
    }
  } finally {
    Pop-Location
  }

  $bundlePath = Resolve-WindowsBundlePath -FlutterProjectPath $flutterProjectPath
  if (Test-Path $distAppDir) {
    Remove-Item -LiteralPath $distAppDir -Recurse -Force
  }
  Copy-Item -LiteralPath $bundlePath -Destination $distAppDir -Recurse -Force

  $exePath = Join-Path $distAppDir "FHPlayer.exe"
  if (-not (Test-Path $exePath)) {
    $fallbackExe = Get-ChildItem -Path $distAppDir -Filter "*.exe" -File -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -notlike "*unins*.exe" } |
      Select-Object -First 1
    if (-not $fallbackExe) {
      throw "Missing Windows executable in $distAppDir"
    }
    if (-not [string]::Equals($fallbackExe.Name, "FHPlayer.exe", [System.StringComparison]::OrdinalIgnoreCase)) {
      Move-Item -LiteralPath $fallbackExe.FullName -Destination $exePath -Force
    }
  }

  Write-Host ""
  Write-Host "Flutter Windows build finished."
  Write-Host "Version: $appVersion"
  Write-Host "Bundle source: $bundlePath"
  Write-Host "Output: $distAppDir"
  Write-Host "Executable: $exePath"
} catch {
  Write-Error $_
  exit 1
} finally {
  Wait-BeforeExit
}
