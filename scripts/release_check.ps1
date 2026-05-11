param(
  [string]$OutputRoot = "",
  [ValidateSet("Auto", "Require", "Skip")]
  [string]$WindowsSigningMode = "Auto",
  [ValidateSet("Auto", "Require", "Skip")]
  [string]$AndroidSigningMode = "Auto",
  [switch]$SkipSyntaxChecks,
  [switch]$SkipRuleTests,
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

function Resolve-PythonCommand {
  if (Get-Command py -ErrorAction SilentlyContinue) {
    return "py"
  }

  if (Get-Command python -ErrorAction SilentlyContinue) {
    return "python"
  }

  throw "Python launcher not found. Install Python 3.10+ first."
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

New-Item -ItemType Directory -Force -Path $releaseCheckRoot | Out-Null

try {
  if (-not $SkipSyntaxChecks) {
    Write-Step "Run syntax and parser checks"

    $pythonCommand = Resolve-PythonCommand
    Invoke-CheckedCommand `
      -FilePath $pythonCommand `
      -Arguments @("-m", "py_compile", ".\app.py") `
      -WorkingDirectory $projectRoot `
      -Environment @{
        PYTHONPYCACHEPREFIX = (Join-Path $releaseCheckRoot "pythoncache")
      }

    Invoke-CheckedCommand `
      -FilePath "node" `
      -Arguments @("--check", ".\static\playlist-app.js") `
      -WorkingDirectory $projectRoot

    Test-PowerShellSyntax -Files @(
      ".\build_windows.ps1",
      ".\build_windows_installer.ps1",
      ".\build_windows_release.ps1",
      ".\scripts\android_flutter\build_debug_apk.ps1",
      ".\scripts\android_flutter\install_debug_apk.ps1",
      ".\scripts\android_flutter\build_release_artifacts.ps1",
      ".\scripts\smoke_test.ps1",
      ".\scripts\prepare_public_release.ps1",
      ".\scripts\test_rule_engine.ps1",
      ".\scripts\release_check.ps1"
    )

    $summary.Add("Syntax checks: ok")
  }

  if (-not $SkipRuleTests) {
    Write-Step "Run rule-engine tests"
    Invoke-CheckedCommand `
      -FilePath (Join-Path $projectRoot "scripts\test_rule_engine.ps1") `
      -WorkingDirectory $projectRoot
    $summary.Add("Rule-engine tests: ok")
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
