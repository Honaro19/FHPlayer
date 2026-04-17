param(
  [string]$OutputDir = "",
  [string]$TempRoot = "",
  [string]$WindowsBuildOutputRoot = "",
  [string]$WindowsExePath = "",
  [ValidateSet("Auto", "Require", "Skip")]
  [string]$SigningMode = "Auto",
  [string]$SignToolPath = "",
  [string]$CertificatePath = "",
  [string]$CertificatePassword = "",
  [string]$CertificateThumbprint = "",
  [string]$TimestampUrl = "http://timestamp.digicert.com"
)

$ErrorActionPreference = "Stop"

function Wait-BeforeExit {
  if (-not $env:FHPLAYER_NO_PAUSE) {
    Write-Host ""
    Read-Host "Press Enter to close"
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

try {
  $projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
  $appVersion = Get-AppVersion -ProjectRoot $projectRoot
  $resolvedOutputDir = if ($OutputDir) { Resolve-AbsolutePath -Path $OutputDir -BasePath $projectRoot } else { Join-Path $projectRoot "installers\windows" }
  $resolvedTempRoot = if ($TempRoot) { Resolve-AbsolutePath -Path $TempRoot -BasePath $projectRoot } else { "" }
  $resolvedWindowsBuildOutputRoot = if ($WindowsBuildOutputRoot) {
    Resolve-AbsolutePath -Path $WindowsBuildOutputRoot -BasePath $projectRoot
  } else {
    ""
  }
  $resolvedWindowsExePath = if ($WindowsExePath) {
    Resolve-AbsolutePath -Path $WindowsExePath -BasePath $projectRoot
  } else {
    ""
  }

  $installerArguments = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", (Join-Path $projectRoot "build_windows_installer.ps1"),
    "-OutputDir", $resolvedOutputDir,
    "-SetupFileName", "FHPlayer-$appVersion-Setup.exe",
    "-SigningMode", $SigningMode
  )

  if ($resolvedTempRoot) {
    $installerArguments += @("-TempRoot", $resolvedTempRoot)
  }
  if ($resolvedWindowsBuildOutputRoot) {
    $installerArguments += @("-WindowsBuildOutputRoot", $resolvedWindowsBuildOutputRoot)
  }
  if ($resolvedWindowsExePath) {
    $installerArguments += @("-WindowsExePath", $resolvedWindowsExePath)
  }
  if (-not [string]::IsNullOrWhiteSpace($SignToolPath)) {
    $installerArguments += @("-SignToolPath", $SignToolPath)
  }
  if (-not [string]::IsNullOrWhiteSpace($CertificatePath)) {
    $installerArguments += @("-CertificatePath", $CertificatePath)
  }
  if (-not [string]::IsNullOrWhiteSpace($CertificatePassword)) {
    $installerArguments += @("-CertificatePassword", $CertificatePassword)
  }
  if (-not [string]::IsNullOrWhiteSpace($CertificateThumbprint)) {
    $installerArguments += @("-CertificateThumbprint", $CertificateThumbprint)
  }
  if (-not [string]::IsNullOrWhiteSpace($TimestampUrl)) {
    $installerArguments += @("-TimestampUrl", $TimestampUrl)
  }

  & powershell @installerArguments
  if ($LASTEXITCODE -ne 0) {
    throw "Windows release installer build failed."
  }

  Write-Host ""
  Write-Host "Windows release build finished."
  Write-Host "Version: $appVersion"
  Write-Host "Output: $(Join-Path $resolvedOutputDir "FHPlayer-$appVersion-Setup.exe")"
} catch {
  Write-Error $_
  exit 1
} finally {
  Wait-BeforeExit
}
