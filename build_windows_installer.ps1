param(
  [string]$OutputDir = "",
  [string]$TempRoot = "",
  [string]$WindowsBuildOutputRoot = "",
  [string]$WindowsExePath = ""
)

$ErrorActionPreference = "Stop"

function Wait-BeforeExit {
  if (-not $env:FHPLAYER_NO_PAUSE) {
    Write-Host ""
    Read-Host "Press Enter to close"
  }
}

function Resolve-InnoSetupCompiler {
  $candidates = @(
    (Get-Command iscc -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue),
    (Join-Path $env:LOCALAPPDATA "Programs\Inno Setup 6\ISCC.exe"),
    (Join-Path $env:LOCALAPPDATA "Programs\Inno Setup 7\ISCC.exe"),
    "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
    "C:\Program Files\Inno Setup 6\ISCC.exe",
    "C:\Program Files (x86)\Inno Setup 7\ISCC.exe",
    "C:\Program Files\Inno Setup 7\ISCC.exe"
  ) | Where-Object { $_ }

  foreach ($candidate in $candidates) {
    if (Test-Path $candidate) {
      return $candidate
    }
  }

  throw "Inno Setup 6 was not found. Install it or add ISCC.exe to PATH."
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

try {
  $projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
  $brandingScript = Join-Path $projectRoot "assets\branding\generate_brand_assets.ps1"
  $iconPath = Join-Path $projectRoot "assets\branding\fhplayer.ico"
  $issPath = Join-Path $projectRoot "installers\windows\FHPlayer.iss"
  $appVersion = Get-AppVersion -ProjectRoot $projectRoot
  $buildToken = Get-Date -Format "yyyyMMdd-HHmmss"
  $resolvedOutputDir = if ($OutputDir) { Resolve-AbsolutePath -Path $OutputDir -BasePath $projectRoot } else { Join-Path $projectRoot "installers\windows" }
  $resolvedTempRoot = if ($TempRoot) {
    Resolve-AbsolutePath -Path $TempRoot -BasePath $projectRoot
  } else {
    Join-Path $env:TEMP "FHPlayer-Installer-$buildToken"
  }
  $resolvedWindowsBuildOutputRoot = if ($WindowsBuildOutputRoot) {
    Resolve-AbsolutePath -Path $WindowsBuildOutputRoot -BasePath $projectRoot
  } else {
    $projectRoot
  }
  $resolvedWindowsExePath = if ($WindowsExePath) {
    Resolve-AbsolutePath -Path $WindowsExePath -BasePath $projectRoot
  } else {
    Join-Path $resolvedWindowsBuildOutputRoot "dist\FHPlayer\FHPlayer.exe"
  }
  $compiler = Resolve-InnoSetupCompiler

  if (Test-Path $brandingScript) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $brandingScript
    if ($LASTEXITCODE -ne 0) {
      throw "Brand asset generation failed."
    }
  }

  if (-not (Test-Path $iconPath)) {
    throw "Missing installer icon at $iconPath"
  }

  if (-not (Test-Path $resolvedWindowsExePath)) {
    $env:FHPLAYER_NO_PAUSE = "1"
    $buildWindowsArguments = @(
      "-NoProfile",
      "-ExecutionPolicy", "Bypass",
      "-File", (Join-Path $projectRoot "build_windows.ps1"),
      "-OutputRoot", $resolvedWindowsBuildOutputRoot
    )
    if ($TempRoot) {
      $buildWindowsArguments += @("-TempRoot", (Join-Path $resolvedTempRoot "windows-build"))
    }
    & powershell @buildWindowsArguments
    if ($LASTEXITCODE -ne 0) {
      throw "Windows executable build failed."
    }
  }

  if (-not (Test-Path $resolvedWindowsExePath)) {
    throw "Missing Windows executable at $resolvedWindowsExePath"
  }

  if (-not (Test-Path $issPath)) {
    throw "Missing Inno Setup script at $issPath"
  }

  $stagingRoot = Join-Path $resolvedTempRoot "installer-stage"
  $stagedDistRoot = Join-Path $stagingRoot "dist"
  $stagedBrandingDir = Join-Path $stagingRoot "assets\branding"
  $stagedInstallerDir = Join-Path $stagingRoot "installers\windows"
  $stagedOutputDir = Join-Path $stagingRoot "dist-installer"
  $stagedIssPath = Join-Path $stagedInstallerDir "FHPlayer.iss"
  $builtSetupPath = Join-Path $stagedOutputDir "FHPlayer-Setup.exe"
  $appDir = Split-Path -Parent $resolvedWindowsExePath

  if (Test-Path $stagingRoot) {
    Remove-Item -LiteralPath $stagingRoot -Recurse -Force
  }

  New-Item -ItemType Directory -Force -Path $stagedDistRoot, $stagedBrandingDir, $stagedInstallerDir, $stagedOutputDir, $resolvedOutputDir | Out-Null
  Copy-Item -LiteralPath $issPath -Destination $stagedIssPath -Force
  Copy-Item -LiteralPath $iconPath -Destination (Join-Path $stagedBrandingDir "fhplayer.ico") -Force
  Copy-Item -LiteralPath $appDir -Destination $stagedDistRoot -Recurse -Force

  & $compiler "/DMyAppVersion=$appVersion" $stagedIssPath
  if ($LASTEXITCODE -ne 0) {
    throw "Inno Setup compilation failed."
  }

  if (-not (Test-Path $builtSetupPath)) {
    throw "Missing built Windows installer at $builtSetupPath"
  }

  $finalSetupPath = Join-Path $resolvedOutputDir "FHPlayer-Setup.exe"
  Copy-Item -LiteralPath $builtSetupPath -Destination $finalSetupPath -Force

  Write-Host ""
  Write-Host "Windows installer build finished."
  Write-Host "Version: $appVersion"
  Write-Host "Output: $finalSetupPath"
} catch {
  Write-Error $_
  exit 1
} finally {
  Wait-BeforeExit
}
