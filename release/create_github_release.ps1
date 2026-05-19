param(
  [string]$Repo = "Honaro19/FHPlayer",
  [string]$Version = "0.1.3"
)

$GhPath = Get-Command gh -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
if (-not $GhPath) {
  # Try common installation paths
  $PossiblePaths = @(
    "$env:ProgramFiles\GitHub CLI\gh.exe",
    "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GitHub.cli*\gh.exe",
    "$env:USERPROFILE\AppData\Local\Microsoft\WinGet\Packages\GitHub.cli*\gh.exe"
  )
  foreach ($Path in $PossiblePaths) {
    if (Test-Path $Path) {
      $GhPath = $Path
      break
    }
  }
}
if (-not $GhPath) {
  Write-Error "GitHub CLI (gh) not found. Run: winget install GitHub.cli"
  exit 1
}

# Check authentication
Write-Host "Checking GitHub authentication..."
& $GhPath auth status 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
  Write-Host ""
  Write-Host "Not authenticated with GitHub. Please run:" -ForegroundColor Yellow
  Write-Host "  gh auth login" -ForegroundColor Cyan
  Write-Host ""
  exit 1
}

$ReleaseNotes = @"
- Added fast-trigger and burst helper functions in the Lovense rule syntax:
  burstcount, burststart, burstduration, burstmember, and burstindex.
- Improved the rule editor with fullscreen mode, visible line numbers, and resizable input area.
- Fixed fullscreen player edge artifacts on Windows after switching from a maximized window.
- Unified Flutter behavior across Windows and Android for the Lovense rule editor improvements.
"@

$Assets = @(
  "Windows\$Version\FHPlayer-$Version-Setup.exe",
  "Windows\$Version\FHPlayer-Portable-$Version.zip",
  "Windows\$Version\SHA256SUMS.txt",
  "Android\$Version\FHPlayer-$Version.apk",
  "Android\$Version\FHPlayer-$Version.aab",
  "Android\$Version\SHA256SUMS.txt",
  "update_manifest.json"
)

$AssetPaths = @()
foreach ($Asset in $Assets) {
  $FullPath = Join-Path $PSScriptRoot "Public Releases\FHPlayer\$Asset"
  if (-not (Test-Path $FullPath)) {
    Write-Error "Asset not found: $FullPath"
    exit 1
  }
  $AssetPaths += $FullPath
}

Write-Host "Creating release v$Version for $Repo..." -ForegroundColor Green

& $GhPath release create "v$Version" `
  --title "FHPlayer $Version" `
  --notes $ReleaseNotes `
  --repo $Repo `
  @AssetPaths

if ($LASTEXITCODE -eq 0) {
  Write-Host ""
  Write-Host "Release v$Version created successfully!" -ForegroundColor Green
  Write-Host "Release page: https://github.com/$Repo/releases/tag/v$Version" -ForegroundColor Cyan
} else {
  Write-Error "Failed to create release. Exit code: $LASTEXITCODE"
  exit $LASTEXITCODE
}
