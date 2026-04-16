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

try {
  $projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
  $brandingScript = Join-Path $projectRoot "assets\branding\generate_brand_assets.ps1"
  $iconPath = Join-Path $projectRoot "assets\branding\fhplayer.ico"
  $exePath = Join-Path $projectRoot "dist\FHPlayer\FHPlayer.exe"
  $issPath = Join-Path $projectRoot "installers\windows\FHPlayer.iss"
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

  if (-not (Test-Path $exePath)) {
    $env:FHPLAYER_NO_PAUSE = "1"
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $projectRoot "build_windows.ps1")
    if ($LASTEXITCODE -ne 0) {
      throw "Windows executable build failed."
    }
  }

  if (-not (Test-Path $issPath)) {
    throw "Missing Inno Setup script at $issPath"
  }

  & $compiler $issPath
  if ($LASTEXITCODE -ne 0) {
    throw "Inno Setup compilation failed."
  }

  Write-Host ""
  Write-Host "Windows installer build finished."
  Write-Host "Output: $(Join-Path $projectRoot 'dist-installer\FHPlayer-Setup.exe')"
} catch {
  Write-Error $_
  exit 1
} finally {
  Wait-BeforeExit
}
