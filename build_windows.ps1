$ErrorActionPreference = "Stop"

function Wait-BeforeExit {
  if (-not $env:FHPLAYER_NO_PAUSE) {
    Write-Host ""
    Read-Host "Press Enter to close"
  }
}

function Resolve-PythonLauncher {
  if (Get-Command py -ErrorAction SilentlyContinue) {
    return @("py", "-m", "PyInstaller")
  }
  if (Get-Command python -ErrorAction SilentlyContinue) {
    return @("python", "-m", "PyInstaller")
  }
  throw "Python launcher not found. Install Python 3.10+ first."
}

try {
  $projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
  $staticDir = Join-Path $projectRoot "static"
  $staticBundleFiles = @("index.html", "styles.css", "playlist-app.js")
  $brandingScript = Join-Path $projectRoot "assets\\branding\\generate_brand_assets.ps1"
  $iconPath = Join-Path $projectRoot "assets\\branding\\fhplayer.ico"
  $distDir = Join-Path $projectRoot "dist"
  $buildDir = Join-Path $projectRoot "build"
  $buildToken = Get-Date -Format "yyyyMMdd-HHmmss"
  $tempRoot = Join-Path $env:TEMP "FHPlayer-PyInstaller-$buildToken"
  $tempDistDir = Join-Path $tempRoot "dist"
  $tempBuildDir = Join-Path $tempRoot "build"
  $tempStaticDir = Join-Path $tempRoot "static"
  $launcher = Resolve-PythonLauncher

  Write-Host "Building FHPlayer Windows executable..."

  New-Item -ItemType Directory -Path $tempDistDir -Force | Out-Null
  New-Item -ItemType Directory -Path $tempBuildDir -Force | Out-Null
  New-Item -ItemType Directory -Path $tempStaticDir -Force | Out-Null
  if (-not (Test-Path $staticDir)) {
    throw "Missing static assets in $staticDir"
  }
  foreach ($staticFile in $staticBundleFiles) {
    $sourcePath = Join-Path $staticDir $staticFile
    if (-not (Test-Path $sourcePath)) {
      throw "Missing required static asset at $sourcePath"
    }
    Copy-Item -LiteralPath $sourcePath -Destination (Join-Path $tempStaticDir $staticFile) -Force
  }
  if ((-not (Test-Path $iconPath)) -and (Test-Path $brandingScript)) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $brandingScript
    if ($LASTEXITCODE -ne 0) {
      throw "Brand asset generation failed."
    }
  }
  if (-not (Test-Path $iconPath)) {
    Write-Warning "Missing Windows icon asset at $iconPath. The executable will use the default icon."
  }

  $versionOutput = & $launcher[0] $launcher[1] $launcher[2] --version 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw "PyInstaller is not installed for the selected Python. Run: pip install -r requirements-build.txt"
  }

  & $launcher[0] $launcher[1] $launcher[2] `
    --noconfirm `
    --clean `
    --name FHPlayer `
    --onedir `
    --console `
    --specpath $tempRoot `
    --distpath $tempDistDir `
    --workpath $tempBuildDir `
    --add-data "${tempStaticDir};static" `
    $(if (Test-Path $iconPath) { "--icon"; $iconPath }) `
    app.py

  if ($LASTEXITCODE -ne 0) {
    throw "PyInstaller build failed."
  }

  $tempExePath = Join-Path $tempDistDir "FHPlayer\FHPlayer.exe"
  if (-not (Test-Path $tempExePath)) {
    throw "Build finished without creating $tempExePath"
  }

  $outputRoot = $projectRoot
  try {
    if (Test-Path $distDir) {
      Remove-Item -LiteralPath $distDir -Recurse -Force
    }
    if (Test-Path $buildDir) {
      Remove-Item -LiteralPath $buildDir -Recurse -Force
    }
    Copy-Item -LiteralPath $tempDistDir -Destination $distDir -Recurse -Force
    Copy-Item -LiteralPath $tempBuildDir -Destination $buildDir -Recurse -Force
  } catch {
    Write-Warning "Could not copy build output into the project folder. Using temp build output at $tempRoot"
    $outputRoot = $tempRoot
  }

  $exePath = Join-Path $outputRoot "dist\FHPlayer\FHPlayer.exe"

  Write-Host ""
  Write-Host "Build finished."
  Write-Host "Executable: $exePath"
  Write-Host "To start without auto-opening the browser, set FHPLAYER_NO_BROWSER=1 before launch."
} catch {
  Write-Error $_
  exit 1
} finally {
  Wait-BeforeExit
}
