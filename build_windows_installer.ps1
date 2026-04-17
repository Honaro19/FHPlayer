param(
  [string]$OutputDir = "",
  [string]$TempRoot = "",
  [string]$WindowsBuildOutputRoot = "",
  [string]$WindowsExePath = "",
  [string]$SetupFileName = "",
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

function Get-FirstNonBlank {
  param([string[]]$Values)

  foreach ($value in $Values) {
    if (-not [string]::IsNullOrWhiteSpace($value)) {
      return $value.Trim()
    }
  }

  return ""
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

function Resolve-SignToolExecutable {
  param([string]$PreferredPath)

  $candidatePaths = @()
  if (-not [string]::IsNullOrWhiteSpace($PreferredPath)) {
    $candidatePaths += $PreferredPath
  }

  $discoveredCommand = Get-Command signtool -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue
  if ($discoveredCommand) {
    $candidatePaths += $discoveredCommand
  }

  $candidatePaths += @(
    "C:\Program Files (x86)\Windows Kits\10\App Certification Kit\signtool.exe"
  )

  $windowsKitRoots = @(
    "C:\Program Files (x86)\Windows Kits\10\bin",
    "C:\Program Files\Windows Kits\10\bin"
  )
  foreach ($kitRoot in $windowsKitRoots) {
    if (-not (Test-Path $kitRoot)) {
      continue
    }

    $kitSignTools =
      Get-ChildItem -Path $kitRoot -Recurse -Filter signtool.exe -ErrorAction SilentlyContinue |
      Sort-Object FullName -Descending |
      Select-Object -ExpandProperty FullName
    $candidatePaths += $kitSignTools
  }

  foreach ($candidatePath in $candidatePaths | Where-Object { $_ }) {
    if (Test-Path $candidatePath) {
      return $candidatePath
    }
  }

  return ""
}

function Sign-File {
  param(
    [string]$SignToolExecutable,
    [string]$TargetPath,
    [string]$CertificateFile,
    [string]$CertificateSecret,
    [string]$Thumbprint,
    [string]$TimestampServer
  )

  if (-not (Test-Path $TargetPath)) {
    throw "Cannot sign missing file $TargetPath"
  }

  $arguments = @(
    "sign",
    "/fd", "sha256"
  )

  if (-not [string]::IsNullOrWhiteSpace($TimestampServer)) {
    $arguments += @("/tr", $TimestampServer, "/td", "sha256")
  }

  if (-not [string]::IsNullOrWhiteSpace($CertificateFile)) {
    $arguments += @("/f", $CertificateFile)
    if (-not [string]::IsNullOrWhiteSpace($CertificateSecret)) {
      $arguments += @("/p", $CertificateSecret)
    }
  } elseif (-not [string]::IsNullOrWhiteSpace($Thumbprint)) {
    $arguments += @("/sha1", $Thumbprint)
  } else {
    throw "Signing requires either a certificate file or a certificate thumbprint."
  }

  $arguments += $TargetPath
  & $SignToolExecutable @arguments
  if ($LASTEXITCODE -ne 0) {
    throw "Code signing failed for $TargetPath"
  }
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
  $finalSetupFileName = if ($SetupFileName) { $SetupFileName } else { "FHPlayer-Setup.exe" }
  $resolvedCertificatePath = Resolve-AbsolutePath -Path (Get-FirstNonBlank @($CertificatePath, $env:FHPLAYER_WINDOWS_SIGN_CERT_PATH)) -BasePath $projectRoot
  $resolvedCertificateThumbprint = Get-FirstNonBlank @($CertificateThumbprint, $env:FHPLAYER_WINDOWS_SIGN_CERT_THUMBPRINT)
  $resolvedCertificatePassword = Get-FirstNonBlank @($CertificatePassword, $env:FHPLAYER_WINDOWS_SIGN_CERT_PASSWORD)
  $resolvedTimestampUrl = Get-FirstNonBlank @($TimestampUrl, $env:FHPLAYER_WINDOWS_SIGN_TIMESTAMP_URL)
  $hasSigningIdentity = (-not [string]::IsNullOrWhiteSpace($resolvedCertificatePath)) -or (-not [string]::IsNullOrWhiteSpace($resolvedCertificateThumbprint))
  $resolvedSignToolPath = ""
  $shouldSignArtifacts = $false
  $compiler = Resolve-InnoSetupCompiler

  if ($SigningMode -eq "Require" -and -not $hasSigningIdentity) {
    throw "Windows code signing was required, but no certificate path or thumbprint was configured."
  }
  if ($SigningMode -ne "Skip" -and $hasSigningIdentity) {
    $resolvedSignToolPath = Resolve-SignToolExecutable -PreferredPath (Get-FirstNonBlank @($SignToolPath, $env:FHPLAYER_WINDOWS_SIGNTOOL_PATH))
    if (-not $resolvedSignToolPath) {
      if ($SigningMode -eq "Require") {
        throw "Windows code signing was required, but signtool.exe was not found."
      }
      Write-Warning "Windows signing configuration was detected, but signtool.exe was not found. Continuing without signing."
    } else {
      $shouldSignArtifacts = $true
    }
  } elseif ($SigningMode -eq "Auto" -and -not $hasSigningIdentity) {
    Write-Warning "No Windows code-signing configuration was found. Building an unsigned installer."
  }

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
  $stagedExePath = Join-Path $stagedDistRoot "FHPlayer\FHPlayer.exe"

  if ($shouldSignArtifacts) {
    Sign-File `
      -SignToolExecutable $resolvedSignToolPath `
      -TargetPath $stagedExePath `
      -CertificateFile $resolvedCertificatePath `
      -CertificateSecret $resolvedCertificatePassword `
      -Thumbprint $resolvedCertificateThumbprint `
      -TimestampServer $resolvedTimestampUrl
  }

  & $compiler "/DMyAppVersion=$appVersion" $stagedIssPath
  if ($LASTEXITCODE -ne 0) {
    throw "Inno Setup compilation failed."
  }

  if (-not (Test-Path $builtSetupPath)) {
    throw "Missing built Windows installer at $builtSetupPath"
  }

  $finalSetupPath = Join-Path $resolvedOutputDir $finalSetupFileName
  Copy-Item -LiteralPath $builtSetupPath -Destination $finalSetupPath -Force

  if ($shouldSignArtifacts) {
    Sign-File `
      -SignToolExecutable $resolvedSignToolPath `
      -TargetPath $finalSetupPath `
      -CertificateFile $resolvedCertificatePath `
      -CertificateSecret $resolvedCertificatePassword `
      -Thumbprint $resolvedCertificateThumbprint `
      -TimestampServer $resolvedTimestampUrl
  }

  Write-Host ""
  Write-Host "Windows installer build finished."
  Write-Host "Version: $appVersion"
  Write-Host "Output: $finalSetupPath"
  Write-Host "Signing mode: $SigningMode"
  Write-Host "Signed: $shouldSignArtifacts"
} catch {
  Write-Error $_
  exit 1
} finally {
  Wait-BeforeExit
}
