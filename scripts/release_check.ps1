param(
  [string]$OutputRoot = "",
  [ValidateSet("Auto", "Require", "Skip")]
  [string]$WindowsSigningMode = "Auto",
  [ValidateSet("Auto", "Require", "Skip")]
  [string]$AndroidSigningMode = "Auto",
  [switch]$SkipSyntaxChecks,
  [switch]$SkipRuleTests,
  [switch]$SkipFlutterTests,
  [switch]$SkipSmokeTests,
  [switch]$SkipWindowsRelease,
  [switch]$SkipAndroidRelease,
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
    } else {
      & $FilePath @Arguments
    }
    if ($LASTEXITCODE -ne 0) {
      throw "Command failed with exit code ${LASTEXITCODE}: $FilePath"
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

function Assert-FileExists {
  param([string]$Path)

  if (-not (Test-Path $Path)) {
    throw "Missing expected file: $Path"
  }

  $item = Get-Item -LiteralPath $Path
  if ($item.Length -le 0) {
    throw "Expected file is empty: $Path"
  }
}

function Test-PowerShellSyntax {
  param([string[]]$Files)

  foreach ($file in $Files) {
    $resolvedPath = Resolve-Path $file
    $errors = $null
    $tokens = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($resolvedPath, [ref]$tokens, [ref]$errors)
    if ($errors -and $errors.Count -gt 0) {
      $errors | ForEach-Object { Write-Error $_.ToString() }
      throw "PowerShell parse failed for $file"
    }
  }
}

function Resolve-FlutterRoot {
  param([string]$ProjectRoot)

  $candidates = @(
    $env:FHPLAYER_FLUTTER_ROOT,
    $env:FLUTTER_ROOT,
    "C:\\Dev\\flutter"
  ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

  foreach ($candidate in $candidates) {
    $resolved = Resolve-AbsolutePath -Path $candidate -BasePath $ProjectRoot
    $snapshotPath = Join-Path $resolved "bin\\cache\\flutter_tools.snapshot"
    $dartPath = Join-Path $resolved "bin\\cache\\dart-sdk\\bin\\dart.exe"
    if ((Test-Path $snapshotPath) -and (Test-Path $dartPath)) {
      return @{
        Root = $resolved
        SnapshotPath = $snapshotPath
        DartPath = $dartPath
      }
    }
  }

  $flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
  if ($flutterCommand) {
    $flutterExecutable = [System.IO.Path]::GetFullPath($flutterCommand.Source)
    $flutterRoot = Split-Path -Parent (Split-Path -Parent $flutterExecutable)
    $snapshotPath = Join-Path $flutterRoot "bin\\cache\\flutter_tools.snapshot"
    $dartPath = Join-Path $flutterRoot "bin\\cache\\dart-sdk\\bin\\dart.exe"
    if ((Test-Path $snapshotPath) -and (Test-Path $dartPath)) {
      return @{
        Root = $flutterRoot
        SnapshotPath = $snapshotPath
        DartPath = $dartPath
      }
    }
  }

  throw "Flutter SDK not found. Set FHPLAYER_FLUTTER_ROOT or FLUTTER_ROOT."
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$appVersion = Get-AppVersion -ProjectRoot $projectRoot
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$releaseCheckRoot = if ($OutputRoot) {
  Resolve-AbsolutePath -Path $OutputRoot -BasePath $projectRoot
} else {
  Join-Path $projectRoot ".tmp\release-checks\$timestamp"
}

$windowsReleaseOutputDir = Join-Path $releaseCheckRoot "windows-release-output"
$windowsReleaseBuildRoot = Join-Path $releaseCheckRoot "windows-release-build"
$windowsReleaseTempRoot = Join-Path $releaseCheckRoot "windows-release-temp"
$androidReleaseOutputDir = Join-Path $releaseCheckRoot "android-release-output"
$publicReleaseRoot = Join-Path $releaseCheckRoot "public-release\FHPlayer"
$smokeRoot = Join-Path $releaseCheckRoot "smoke-tests"
$summary = [System.Collections.Generic.List[string]]::new()
$skipFlutterValidation = $SkipRuleTests -or $SkipFlutterTests

if ($SkipRuleTests) {
  Write-Warning "-SkipRuleTests is deprecated and now behaves like -SkipFlutterTests."
}

New-Item -ItemType Directory -Force -Path $releaseCheckRoot | Out-Null

try {
  if (-not $SkipSyntaxChecks) {
    Write-Step "Run script syntax checks"

    Test-PowerShellSyntax -Files @(
      ".\build_windows.ps1",
      ".\build_windows_installer.ps1",
      ".\build_windows_release.ps1",
      ".\scripts\android_flutter\build_debug_apk.ps1",
      ".\scripts\android_flutter\install_debug_apk.ps1",
      ".\scripts\android_flutter\build_release_artifacts.ps1",
      ".\scripts\test_flutter.ps1",
      ".\scripts\run_flutter_logged.ps1",
      ".\scripts\smoke_test.ps1",
      ".\scripts\prepare_public_release.ps1",
      ".\scripts\release_check.ps1"
    )

    $summary.Add("Script syntax checks: ok")
  }

  if (-not $skipFlutterValidation) {
    Write-Step "Run Flutter tests and analyze"
    Invoke-CheckedCommand `
      -FilePath (Join-Path $projectRoot "scripts\test_flutter.ps1") `
      -Arguments @("-Reporter", "compact") `
      -WorkingDirectory $projectRoot

    $flutterTooling = Resolve-FlutterRoot -ProjectRoot $projectRoot
    Invoke-CheckedCommand `
      -FilePath $flutterTooling.DartPath `
      -Arguments @($flutterTooling.SnapshotPath, "analyze") `
      -WorkingDirectory (Join-Path $projectRoot "fhplayer_flutter")

    $summary.Add("Flutter tests + analyze: ok")
  }

  if (-not $SkipSmokeTests) {
    Write-Step "Run full smoke tests"
    $smokeArguments = @("-SmokeRoot", $smokeRoot)
    if ($SkipAndroidInstall) {
      $smokeArguments += "-SkipAndroidInstall"
    }
    if ($AndroidDeviceSerial) {
      $smokeArguments += @("-AndroidDeviceSerial", $AndroidDeviceSerial)
    }
    if ($KeepArtifacts) {
      $smokeArguments += "-KeepArtifacts"
    }

    Invoke-CheckedCommand `
      -FilePath (Join-Path $projectRoot "scripts\smoke_test.ps1") `
      -Arguments $smokeArguments `
      -WorkingDirectory $projectRoot `
      -Environment @{
        FHPLAYER_NO_PAUSE = "1"
      }
    $summary.Add("Full smoke tests: ok")
  }

  if (-not $SkipWindowsRelease) {
    Write-Step "Build Windows release installer"
    Invoke-CheckedCommand `
      -FilePath (Join-Path $projectRoot "build_windows_release.ps1") `
      -Arguments @(
        "-OutputDir", $windowsReleaseOutputDir,
        "-WindowsBuildOutputRoot", $windowsReleaseBuildRoot,
        "-TempRoot", $windowsReleaseTempRoot,
        "-SigningMode", $WindowsSigningMode
      ) `
      -WorkingDirectory $projectRoot `
      -Environment @{
        FHPLAYER_NO_PAUSE = "1"
      }

    $windowsInstallerPath = Join-Path $windowsReleaseOutputDir "FHPlayer-$appVersion-Setup.exe"
    Assert-FileExists -Path $windowsInstallerPath
    $summary.Add("Windows release artifact: ok ($windowsInstallerPath)")
  }

  if (-not $SkipAndroidRelease) {
    Write-Step "Build Android release artifacts"
    Invoke-CheckedCommand `
      -FilePath (Join-Path $projectRoot "scripts\android_flutter\build_release_artifacts.ps1") `
      -Arguments @(
        "-OutputDir", $androidReleaseOutputDir,
        "-SigningMode", $AndroidSigningMode
      ) `
      -WorkingDirectory $projectRoot `
      -Environment @{
        FHPLAYER_NO_PAUSE = "1"
      }

    $androidApkPath = Join-Path $androidReleaseOutputDir "FHPlayer-$appVersion.apk"
    $androidBundlePath = Join-Path $androidReleaseOutputDir "FHPlayer-$appVersion.aab"
    Assert-FileExists -Path $androidApkPath
    Assert-FileExists -Path $androidBundlePath
    $summary.Add("Android release artifacts: ok ($androidApkPath, $androidBundlePath)")
  }

  if (-not $SkipWindowsRelease -and -not $SkipAndroidRelease) {
    Write-Step "Prepare and verify public release package"
    $publicReleaseArguments = @(
      "-ReleaseRoot", $publicReleaseRoot,
      "-WindowsSetupPath", (Join-Path $windowsReleaseOutputDir "FHPlayer-$appVersion-Setup.exe"),
      "-PortableSourceDir", (Join-Path $windowsReleaseBuildRoot "dist\FHPlayer"),
      "-AndroidApkPath", (Join-Path $androidReleaseOutputDir "FHPlayer-$appVersion.apk"),
      "-AndroidBundlePath", (Join-Path $androidReleaseOutputDir "FHPlayer-$appVersion.aab")
    )

    Invoke-CheckedCommand `
      -FilePath (Join-Path $projectRoot "scripts\prepare_public_release.ps1") `
      -Arguments $publicReleaseArguments `
      -WorkingDirectory $projectRoot `
      -Environment @{
        FHPLAYER_NO_PAUSE = "1"
      }

    Invoke-CheckedCommand `
      -FilePath (Join-Path $projectRoot "scripts\prepare_public_release.ps1") `
      -Arguments ($publicReleaseArguments + "-VerifyOnly") `
      -WorkingDirectory $projectRoot `
      -Environment @{
        FHPLAYER_NO_PAUSE = "1"
      }

    $summary.Add("Public release package: ok ($publicReleaseRoot)")
  }

  Write-Step "Release check summary"
  foreach ($line in $summary) {
    Write-Host "- $line"
  }
} finally {
  if ($KeepArtifacts) {
    Write-Host ""
    Write-Host "Release check artifacts kept at $releaseCheckRoot"
  } elseif (Test-Path $releaseCheckRoot) {
    Remove-Item -LiteralPath $releaseCheckRoot -Recurse -Force -ErrorAction SilentlyContinue
  }
}
