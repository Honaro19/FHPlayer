param(
  [string]$Repo = "Honaro19/FHPlayer",
  [string]$Version = "0.1.2"
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
- Added Library playlist saving with editable names and automatic replacement of renamed Library playlists.
- Moved playlist actions into the Playlist area and added Library delete flows for videos, funscripts, and playlists.
- Improved loading saved playlists when referenced video or funscript paths are missing.
- Fixed Android Library playlist loading crashes caused by interrupted local file streams.
"@

$Assets = @(
  "Windows\0.1.2\FHPlayer-0.1.2-Setup.exe",
  "Windows\0.1.2\FHPlayer-Portable-0.1.2.zip",
  "Windows\0.1.2\SHA256SUMS-Windows.txt",
  "Android\0.1.2\FHPlayer-0.1.2.apk",
  "Android\0.1.2\FHPlayer-0.1.2.aab",
  "Android\0.1.2\SHA256SUMS-Android.txt",
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
