param(
  [string]$ReleaseRoot = "",
  [string]$ManifestPath = "",
  [string]$WindowsSetupPath = "",
  [string]$PortableSourceDir = "",
  [string]$AndroidApkPath = "",
  [string]$AndroidBundlePath = "",
  [string[]]$ReleaseNote = @(),
  [string]$ReleaseNotesPath = "",
  [string]$WindowsInstallerUrl = "",
  [string]$WindowsPortableUrl = "",
  [string]$AndroidApkUrl = "",
  [string]$AndroidBundleUrl = "",
  [switch]$CleanVersionDirectories,
  [switch]$DryRun,
  [switch]$VerifyOnly
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

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

function Read-JsonFile {
  param([string]$Path)

  if (-not (Test-Path $Path)) {
    return $null
  }

  $rawJson = Get-Content -LiteralPath $Path -Raw
  $convertFromJson = Get-Command ConvertFrom-Json
  if ($convertFromJson.Parameters.ContainsKey("Depth")) {
    return $rawJson | ConvertFrom-Json -Depth 16
  }

  return $rawJson | ConvertFrom-Json
}

function Get-PortableSourceDirectory {
  param(
    [string]$ProjectRoot,
    [string]$OverridePath
  )

  if ($OverridePath) {
    return Resolve-AbsolutePath -Path $OverridePath -BasePath $ProjectRoot
  }

  $candidates = @(
    (Join-Path $ProjectRoot "dist\FHPlayer"),
    (Join-Path $ProjectRoot "installers\windows-portable\FHPlayer")
  )

  foreach ($candidate in $candidates) {
    if (Test-Path $candidate) {
      return $candidate
    }
  }

  throw "No portable Windows app directory was found. Checked: $($candidates -join ', ')"
}

function Get-ReleaseNotes {
  param(
    [string[]]$ExplicitNotes,
    [string]$ReleaseNotesPath,
    [string]$ExistingManifestPath,
    [string]$ExistingChangelogPath,
    [string]$AppVersion,
    [string]$ProjectRoot
  )

  if ($ExplicitNotes.Count -gt 0) {
    return @($ExplicitNotes | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
  }

  if ($ReleaseNotesPath) {
    $resolvedReleaseNotesPath = Resolve-AbsolutePath -Path $ReleaseNotesPath -BasePath $ProjectRoot
    if (-not (Test-Path $resolvedReleaseNotesPath)) {
      throw "Release notes file was not found at $resolvedReleaseNotesPath"
    }

    return @(
      Get-Content -LiteralPath $resolvedReleaseNotesPath |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ }
    )
  }

  $existingManifest = Read-JsonFile -Path $ExistingManifestPath
  if ($existingManifest -and $existingManifest.latest_version -eq $AppVersion -and $existingManifest.release_notes) {
    return @($existingManifest.release_notes | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
  }

  if (Test-Path $ExistingChangelogPath) {
    $notes = @(
      Get-Content -LiteralPath $ExistingChangelogPath |
        Select-Object -Skip 2 |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -and $_ -like '- *' } |
        ForEach-Object { $_.Substring(2).Trim() } |
        Where-Object { $_ }
    )
    if ($notes.Count -gt 0) {
      return $notes
    }
  }

  return @(
    "Manual release package prepared automatically.",
    "See the bundled CHANGELOG.txt for the release summary.",
    "Automatic update checks use the shared FHPlayer manifest."
  )
}

function Ensure-ParentDirectory {
  param([string]$Path)

  $parent = Split-Path -Parent $Path
  if ($parent) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
  }
}

function Write-Utf8File {
  param(
    [string]$Path,
    [string]$Content
  )

  Ensure-ParentDirectory -Path $Path
  [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

function Get-HashText {
  param([string]$Path)

  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Format-HashLine {
  param(
    [string]$Hash,
    [string]$FileName
  )

  return "$Hash *$FileName"
}

function Build-WindowsReadme {
  param(
    [string]$AppVersion,
    [string]$SetupFileName,
    [string]$PortableFileName
  )

  return @"
FHPlayer $AppVersion for Windows

Contents:
- ${SetupFileName}: per-user Windows installer
- ${PortableFileName}: portable bundle without installer
- CHANGELOG.txt: release summary
- SHA256SUMS.txt: checksums for the public files

Installation:
1. Run ${SetupFileName} for the standard Windows installation.
2. Or extract ${PortableFileName} and start FHPlayer.exe from the extracted FHPlayer folder.

Notes:
- The installer and the portable bundle contain FHPlayer ${AppVersion}.
- Automatic update checks use the shared FHPlayer manifest and open the public Windows release folder.
"@
}

function Build-AndroidReadme {
  param(
    [string]$AppVersion,
    [string]$ApkFileName,
    [string]$BundleFileName
  )

  return @"
FHPlayer $AppVersion for Android

Contents:
- ${ApkFileName}: installable Android release package
- ${BundleFileName}: Android App Bundle archive
- CHANGELOG.txt: release summary
- SHA256SUMS.txt: checksums for the public files

Installation:
1. Install ${ApkFileName} on the target Android device.
2. Use the `.aab` only if you specifically need the Android App Bundle artifact.

Notes:
- On first start FHPlayer creates its managed Library folders inside the app storage area.
- Automatic update checks use the shared FHPlayer manifest and open the public Android release folder.
"@
}

function Build-Changelog {
  param(
    [string]$AppVersion,
    [string[]]$ReleaseNotes
  )

  $lines = @("FHPlayer $AppVersion", "")
  $lines += $ReleaseNotes | ForEach-Object { "- $_" }
  return ($lines -join [Environment]::NewLine) + [Environment]::NewLine
}

function Get-RequiredReleasePaths {
  param(
    [string]$ProjectRoot,
    [string]$AppVersion,
    [string]$WindowsSetupPath,
    [string]$PortableSourceDir,
    [string]$AndroidApkPath,
    [string]$AndroidBundlePath
  )

  $resolvedWindowsSetupPath = if ($WindowsSetupPath) {
    Resolve-AbsolutePath -Path $WindowsSetupPath -BasePath $ProjectRoot
  } else {
    Join-Path $ProjectRoot "installers\windows\FHPlayer-$AppVersion-Setup.exe"
  }

  $resolvedPortableSourceDirectory = Get-PortableSourceDirectory -ProjectRoot $ProjectRoot -OverridePath $PortableSourceDir

  $resolvedAndroidApkPath = if ($AndroidApkPath) {
    Resolve-AbsolutePath -Path $AndroidApkPath -BasePath $ProjectRoot
  } else {
    Join-Path $ProjectRoot "installers\android\FHPlayer-$AppVersion.apk"
  }

  $resolvedAndroidBundlePath = if ($AndroidBundlePath) {
    Resolve-AbsolutePath -Path $AndroidBundlePath -BasePath $ProjectRoot
  } else {
    Join-Path $ProjectRoot "installers\android\FHPlayer-$AppVersion.aab"
  }

  return [ordered]@{
    WindowsSetupPath = $resolvedWindowsSetupPath
    PortableSourceDirectory = $resolvedPortableSourceDirectory
    AndroidApkPath = $resolvedAndroidApkPath
    AndroidBundlePath = $resolvedAndroidBundlePath
  }
}

function Test-RequiredReleaseInputs {
  param([hashtable]$Paths)

  foreach ($requiredPath in $Paths.Values) {
    if (-not (Test-Path $requiredPath)) {
      throw "Required release input was not found at $requiredPath"
    }
  }
}

function Read-Sha256SumsFile {
  param([string]$Path)

  if (-not (Test-Path $Path)) {
    throw "Missing SHA256SUMS file at $Path"
  }

  $hashes = [ordered]@{}
  foreach ($rawLine in Get-Content -LiteralPath $Path) {
    $line = $rawLine.Trim()
    if (-not $line) {
      continue
    }

    if ($line -notmatch '^([0-9a-f]{64}) \*(.+)$') {
      throw "Invalid SHA256SUMS entry in ${Path}: $line"
    }

    $hashes[$matches[2]] = $matches[1]
  }

  return $hashes
}

function Test-ManifestPlatformBlock {
  param(
    [object]$PlatformObject,
    [string]$FolderUrlPropertyName,
    [string[]]$ExpectedShaKeys,
    [string]$ManifestPath,
    [string]$PlatformName
  )

  if (-not $PlatformObject) {
    throw "Manifest $ManifestPath is missing platforms.$PlatformName"
  }

  $folderUrl = $PlatformObject.$FolderUrlPropertyName
  if ([string]::IsNullOrWhiteSpace("$folderUrl")) {
    throw "Manifest $ManifestPath is missing platforms.$PlatformName.$FolderUrlPropertyName"
  }

  if (-not $PlatformObject.sha256) {
    throw "Manifest $ManifestPath is missing platforms.$PlatformName.sha256"
  }

  foreach ($shaKey in $ExpectedShaKeys) {
    $shaValue = "$($PlatformObject.sha256.$shaKey)".Trim().ToLowerInvariant()
    if ($shaValue -notmatch '^[0-9a-f]{64}$') {
      throw "Manifest $ManifestPath contains an invalid SHA256 for platforms.$PlatformName.sha256.$shaKey"
    }
  }
}

function Assert-PublicReleaseOutputs {
  param(
    [string]$ManifestPath,
    [string]$AppVersion,
    [string]$WindowsVersionDirectory,
    [string]$AndroidVersionDirectory,
    [string]$WindowsSetupFileName,
    [string]$WindowsPortableFileName,
    [string]$AndroidApkFileName,
    [string]$AndroidBundleFileName,
    [string[]]$ReleaseNotes
  )

  $manifest = Read-JsonFile -Path $ManifestPath
  if (-not $manifest) {
    throw "Manifest was not found at $ManifestPath"
  }

  if ("$($manifest.app)".Trim() -ne "FHPlayer") {
    throw "Manifest $ManifestPath must contain app = FHPlayer"
  }

  if ("$($manifest.latest_version)".Trim() -ne $AppVersion) {
    throw "Manifest $ManifestPath must contain latest_version = $AppVersion"
  }

  if (-not $manifest.platforms) {
    throw "Manifest $ManifestPath is missing platforms"
  }

  Test-ManifestPlatformBlock -PlatformObject $manifest.platforms.windows -FolderUrlPropertyName "folder_url" -ExpectedShaKeys @("installer", "portable") -ManifestPath $ManifestPath -PlatformName "windows"
  Test-ManifestPlatformBlock -PlatformObject $manifest.platforms.android -FolderUrlPropertyName "folder_url" -ExpectedShaKeys @("apk", "aab") -ManifestPath $ManifestPath -PlatformName "android"

  $windowsReadmePath = Join-Path $WindowsVersionDirectory "README.txt"
  $windowsChangelogPath = Join-Path $WindowsVersionDirectory "CHANGELOG.txt"
  $windowsShaPath = Join-Path $WindowsVersionDirectory "SHA256SUMS.txt"
  $androidReadmePath = Join-Path $AndroidVersionDirectory "README.txt"
  $androidChangelogPath = Join-Path $AndroidVersionDirectory "CHANGELOG.txt"
  $androidShaPath = Join-Path $AndroidVersionDirectory "SHA256SUMS.txt"
  $publicWindowsSetupPath = Join-Path $WindowsVersionDirectory $WindowsSetupFileName
  $publicWindowsPortablePath = Join-Path $WindowsVersionDirectory $WindowsPortableFileName
  $publicAndroidApkPath = Join-Path $AndroidVersionDirectory $AndroidApkFileName
  $publicAndroidBundlePath = Join-Path $AndroidVersionDirectory $AndroidBundleFileName

  foreach ($requiredOutput in @(
    $windowsReadmePath,
    $windowsChangelogPath,
    $windowsShaPath,
    $androidReadmePath,
    $androidChangelogPath,
    $androidShaPath,
    $publicWindowsSetupPath,
    $publicWindowsPortablePath,
    $publicAndroidApkPath,
    $publicAndroidBundlePath
  )) {
    if (-not (Test-Path $requiredOutput)) {
      throw "Expected public release output was not found at $requiredOutput"
    }
  }

  $windowsHashes = Read-Sha256SumsFile -Path $windowsShaPath
  $androidHashes = Read-Sha256SumsFile -Path $androidShaPath

  $expectedWindowsInstallerHash = Get-HashText -Path $publicWindowsSetupPath
  $expectedWindowsPortableHash = Get-HashText -Path $publicWindowsPortablePath
  $expectedAndroidApkHash = Get-HashText -Path $publicAndroidApkPath
  $expectedAndroidBundleHash = Get-HashText -Path $publicAndroidBundlePath

  if ($windowsHashes[$WindowsSetupFileName] -ne $expectedWindowsInstallerHash) {
    throw "SHA256SUMS mismatch for $WindowsSetupFileName"
  }
  if ($windowsHashes[$WindowsPortableFileName] -ne $expectedWindowsPortableHash) {
    throw "SHA256SUMS mismatch for $WindowsPortableFileName"
  }
  if ($androidHashes[$AndroidApkFileName] -ne $expectedAndroidApkHash) {
    throw "SHA256SUMS mismatch for $AndroidApkFileName"
  }
  if ($androidHashes[$AndroidBundleFileName] -ne $expectedAndroidBundleHash) {
    throw "SHA256SUMS mismatch for $AndroidBundleFileName"
  }

  if ("$($manifest.platforms.windows.sha256.installer)".Trim().ToLowerInvariant() -ne $expectedWindowsInstallerHash) {
    throw "Manifest SHA256 mismatch for platforms.windows.sha256.installer"
  }
  if ("$($manifest.platforms.windows.sha256.portable)".Trim().ToLowerInvariant() -ne $expectedWindowsPortableHash) {
    throw "Manifest SHA256 mismatch for platforms.windows.sha256.portable"
  }
  if ("$($manifest.platforms.android.sha256.apk)".Trim().ToLowerInvariant() -ne $expectedAndroidApkHash) {
    throw "Manifest SHA256 mismatch for platforms.android.sha256.apk"
  }
  if ("$($manifest.platforms.android.sha256.aab)".Trim().ToLowerInvariant() -ne $expectedAndroidBundleHash) {
    throw "Manifest SHA256 mismatch for platforms.android.sha256.aab"
  }

  $windowsReadme = Get-Content -LiteralPath $windowsReadmePath -Raw
  $windowsChangelog = Get-Content -LiteralPath $windowsChangelogPath -Raw
  $androidReadme = Get-Content -LiteralPath $androidReadmePath -Raw
  $androidChangelog = Get-Content -LiteralPath $androidChangelogPath -Raw

  foreach ($requiredSnippet in @("FHPlayer $AppVersion", $WindowsSetupFileName, $WindowsPortableFileName)) {
    if ($windowsReadme -notlike "*$requiredSnippet*") {
      throw "Windows README is missing '$requiredSnippet'"
    }
  }
  foreach ($requiredSnippet in @("FHPlayer $AppVersion", $AndroidApkFileName, $AndroidBundleFileName)) {
    if ($androidReadme -notlike "*$requiredSnippet*") {
      throw "Android README is missing '$requiredSnippet'"
    }
  }
  if ($windowsChangelog -notlike "*FHPlayer $AppVersion*") {
    throw "Windows CHANGELOG does not mention FHPlayer $AppVersion"
  }
  if ($androidChangelog -notlike "*FHPlayer $AppVersion*") {
    throw "Android CHANGELOG does not mention FHPlayer $AppVersion"
  }

  foreach ($releaseNote in $ReleaseNotes) {
    if ($windowsChangelog -notlike "*$releaseNote*") {
      throw "Windows CHANGELOG is missing release note '$releaseNote'"
    }
    if ($androidChangelog -notlike "*$releaseNote*") {
      throw "Android CHANGELOG is missing release note '$releaseNote'"
    }
  }

  $manifestReleaseNotes = @($manifest.release_notes | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
  if (@($manifestReleaseNotes).Count -ne @($ReleaseNotes).Count) {
    throw "Manifest release_notes count does not match the resolved release notes"
  }

  for ($index = 0; $index -lt $ReleaseNotes.Count; $index++) {
    if ($manifestReleaseNotes[$index] -ne $ReleaseNotes[$index]) {
      throw "Manifest release_notes entry $index does not match the resolved release notes"
    }
  }
}

function Write-DryRunSummary {
  param(
    [string]$AppVersion,
    [string]$ReleaseRoot,
    [string]$ManifestPath,
    [hashtable]$RequiredPaths,
    [string[]]$ReleaseNotes,
    [string]$WindowsVersionDirectory,
    [string]$AndroidVersionDirectory
  )

  Write-Host "Dry run for FHPlayer $AppVersion"
  Write-Host "Release root: $ReleaseRoot"
  Write-Host "Manifest target: $ManifestPath"
  Write-Host "Windows setup input: $($RequiredPaths.WindowsSetupPath)"
  Write-Host "Windows portable source: $($RequiredPaths.PortableSourceDirectory)"
  Write-Host "Android APK input: $($RequiredPaths.AndroidApkPath)"
  Write-Host "Android AAB input: $($RequiredPaths.AndroidBundlePath)"
  Write-Host "Windows version directory: $WindowsVersionDirectory"
  Write-Host "Android version directory: $AndroidVersionDirectory"
  Write-Host "Release notes:"
  foreach ($releaseNote in $ReleaseNotes) {
    Write-Host "- $releaseNote"
  }
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$appVersion = Get-AppVersion -ProjectRoot $projectRoot

if ($DryRun -and $VerifyOnly) {
  throw "Use either -DryRun or -VerifyOnly, not both at the same time."
}

if ($VerifyOnly -and $CleanVersionDirectories) {
  throw "-VerifyOnly cannot be combined with -CleanVersionDirectories."
}

$resolvedReleaseRoot = if ($ReleaseRoot) {
  Resolve-AbsolutePath -Path $ReleaseRoot -BasePath $projectRoot
} else {
  Join-Path $projectRoot "release\Public Releases\FHPlayer"
}
$resolvedManifestPath = if ($ManifestPath) {
  Resolve-AbsolutePath -Path $ManifestPath -BasePath $projectRoot
} else {
  Join-Path $resolvedReleaseRoot "update_manifest.json"
}

$templatePath = Join-Path $projectRoot "release\update_manifest.template.json"
if (-not (Test-Path $templatePath)) {
  throw "Missing manifest template at $templatePath"
}

$manifestTemplate = Read-JsonFile -Path $templatePath
$existingManifest = Read-JsonFile -Path $resolvedManifestPath
$windowsVersionDirectory = Join-Path $resolvedReleaseRoot "Windows\$appVersion"
$androidVersionDirectory = Join-Path $resolvedReleaseRoot "Android\$appVersion"

$requiredReleasePaths = Get-RequiredReleasePaths `
  -ProjectRoot $projectRoot `
  -AppVersion $appVersion `
  -WindowsSetupPath $WindowsSetupPath `
  -PortableSourceDir $PortableSourceDir `
  -AndroidApkPath $AndroidApkPath `
  -AndroidBundlePath $AndroidBundlePath
Test-RequiredReleaseInputs -Paths $requiredReleasePaths

$releaseNotes = Get-ReleaseNotes `
  -ExplicitNotes $ReleaseNote `
  -ReleaseNotesPath $ReleaseNotesPath `
  -ExistingManifestPath $resolvedManifestPath `
  -ExistingChangelogPath (Join-Path $windowsVersionDirectory "CHANGELOG.txt") `
  -AppVersion $appVersion `
  -ProjectRoot $projectRoot

$windowsSetupFileName = "FHPlayer-$appVersion-Setup.exe"
$windowsPortableFileName = "FHPlayer-Portable-$appVersion.zip"
$androidApkFileName = "FHPlayer-$appVersion.apk"
$androidBundleFileName = "FHPlayer-$appVersion.aab"

$resolvedWindowsSetupPath = $requiredReleasePaths.WindowsSetupPath
$resolvedPortableSourceDirectory = $requiredReleasePaths.PortableSourceDirectory
$resolvedAndroidApkPath = $requiredReleasePaths.AndroidApkPath
$resolvedAndroidBundlePath = $requiredReleasePaths.AndroidBundlePath
$publicWindowsSetupPath = Join-Path $windowsVersionDirectory $windowsSetupFileName
$publicWindowsPortablePath = Join-Path $windowsVersionDirectory $windowsPortableFileName
$publicAndroidApkPath = Join-Path $androidVersionDirectory $androidApkFileName
$publicAndroidBundlePath = Join-Path $androidVersionDirectory $androidBundleFileName

if ($DryRun) {
  Write-DryRunSummary `
    -AppVersion $appVersion `
    -ReleaseRoot $resolvedReleaseRoot `
    -ManifestPath $resolvedManifestPath `
    -RequiredPaths $requiredReleasePaths `
    -ReleaseNotes $releaseNotes `
    -WindowsVersionDirectory $windowsVersionDirectory `
    -AndroidVersionDirectory $androidVersionDirectory
  return
}

if ($VerifyOnly) {
  Assert-PublicReleaseOutputs `
    -ManifestPath $resolvedManifestPath `
    -AppVersion $appVersion `
    -WindowsVersionDirectory $windowsVersionDirectory `
    -AndroidVersionDirectory $androidVersionDirectory `
    -WindowsSetupFileName $windowsSetupFileName `
    -WindowsPortableFileName $windowsPortableFileName `
    -AndroidApkFileName $androidApkFileName `
    -AndroidBundleFileName $androidBundleFileName `
    -ReleaseNotes $releaseNotes

  Write-Host "Verified public release for FHPlayer $appVersion"
  Write-Host "Release root: $resolvedReleaseRoot"
  Write-Host "Manifest: $resolvedManifestPath"
  return
}

if ($CleanVersionDirectories) {
  foreach ($directory in @($windowsVersionDirectory, $androidVersionDirectory)) {
    if (Test-Path $directory) {
      Remove-Item -LiteralPath $directory -Recurse -Force
    }
  }
}

New-Item -ItemType Directory -Force -Path $windowsVersionDirectory, $androidVersionDirectory | Out-Null

Copy-Item -LiteralPath $resolvedWindowsSetupPath -Destination $publicWindowsSetupPath -Force
Copy-Item -LiteralPath $resolvedAndroidApkPath -Destination $publicAndroidApkPath -Force
Copy-Item -LiteralPath $resolvedAndroidBundlePath -Destination $publicAndroidBundlePath -Force

$tempPortableArchivePath = Join-Path `
  ([System.IO.Path]::GetTempPath()) `
  ("FHPlayer-Portable-$appVersion-" + [System.Guid]::NewGuid().ToString("N") + ".zip")

try {
  Compress-Archive -Path $resolvedPortableSourceDirectory -DestinationPath $tempPortableArchivePath -CompressionLevel Optimal

  try {
    Copy-Item -LiteralPath $tempPortableArchivePath -Destination $publicWindowsPortablePath -Force
  } catch {
    if (Test-Path $publicWindowsPortablePath) {
      Write-Warning "Could not replace $publicWindowsPortablePath. Keeping the existing portable archive. $($_.Exception.Message)"
    } else {
      throw
    }
  }
} finally {
  if (Test-Path $tempPortableArchivePath) {
    Remove-Item -LiteralPath $tempPortableArchivePath -Force -ErrorAction SilentlyContinue
  }
}

$windowsInstallerHash = Get-HashText -Path $publicWindowsSetupPath
$windowsPortableHash = Get-HashText -Path $publicWindowsPortablePath
$androidApkHash = Get-HashText -Path $publicAndroidApkPath
$androidBundleHash = Get-HashText -Path $publicAndroidBundlePath

Write-Utf8File -Path (Join-Path $windowsVersionDirectory "README.txt") -Content (Build-WindowsReadme -AppVersion $appVersion -SetupFileName $windowsSetupFileName -PortableFileName $windowsPortableFileName)
Write-Utf8File -Path (Join-Path $androidVersionDirectory "README.txt") -Content (Build-AndroidReadme -AppVersion $appVersion -ApkFileName $androidApkFileName -BundleFileName $androidBundleFileName)

$changelogText = Build-Changelog -AppVersion $appVersion -ReleaseNotes $releaseNotes
Write-Utf8File -Path (Join-Path $windowsVersionDirectory "CHANGELOG.txt") -Content $changelogText
Write-Utf8File -Path (Join-Path $androidVersionDirectory "CHANGELOG.txt") -Content $changelogText

$windowsShaContent = @(
  (Format-HashLine -Hash $windowsInstallerHash -FileName $windowsSetupFileName),
  (Format-HashLine -Hash $windowsPortableHash -FileName $windowsPortableFileName)
) -join [Environment]::NewLine
$androidShaContent = @(
  (Format-HashLine -Hash $androidApkHash -FileName $androidApkFileName),
  (Format-HashLine -Hash $androidBundleHash -FileName $androidBundleFileName)
) -join [Environment]::NewLine
Write-Utf8File -Path (Join-Path $windowsVersionDirectory "SHA256SUMS.txt") -Content ($windowsShaContent + [Environment]::NewLine)
Write-Utf8File -Path (Join-Path $androidVersionDirectory "SHA256SUMS.txt") -Content ($androidShaContent + [Environment]::NewLine)

$windowsTemplate = if ($existingManifest -and $existingManifest.platforms -and $existingManifest.platforms.windows) {
  $existingManifest.platforms.windows
} else {
  $manifestTemplate.platforms.windows
}
$androidTemplate = if ($existingManifest -and $existingManifest.platforms -and $existingManifest.platforms.android) {
  $existingManifest.platforms.android
} else {
  $manifestTemplate.platforms.android
}

$manifestObject = [ordered]@{
  app = "FHPlayer"
  latest_version = $appVersion
  release_notes = @($releaseNotes)
  platforms = [ordered]@{
    windows = [ordered]@{
      folder_url = [string]$windowsTemplate.folder_url
      installer_url = if ($WindowsInstallerUrl) { $WindowsInstallerUrl } elseif ($existingManifest -and $existingManifest.latest_version -eq $appVersion) { $windowsTemplate.installer_url } else { $null }
      portable_url = if ($WindowsPortableUrl) { $WindowsPortableUrl } elseif ($existingManifest -and $existingManifest.latest_version -eq $appVersion) { $windowsTemplate.portable_url } else { $null }
      sha256 = [ordered]@{
        installer = $windowsInstallerHash
        portable = $windowsPortableHash
      }
    }
    android = [ordered]@{
      folder_url = [string]$androidTemplate.folder_url
      apk_url = if ($AndroidApkUrl) { $AndroidApkUrl } elseif ($existingManifest -and $existingManifest.latest_version -eq $appVersion) { $androidTemplate.apk_url } else { $null }
      aab_url = if ($AndroidBundleUrl) { $AndroidBundleUrl } elseif ($existingManifest -and $existingManifest.latest_version -eq $appVersion) { $androidTemplate.aab_url } else { $null }
      sha256 = [ordered]@{
        apk = $androidApkHash
        aab = $androidBundleHash
      }
    }
  }
}

$manifestJson = $manifestObject | ConvertTo-Json -Depth 10
Write-Utf8File -Path $resolvedManifestPath -Content ($manifestJson + [Environment]::NewLine)

Assert-PublicReleaseOutputs `
  -ManifestPath $resolvedManifestPath `
  -AppVersion $appVersion `
  -WindowsVersionDirectory $windowsVersionDirectory `
  -AndroidVersionDirectory $androidVersionDirectory `
  -WindowsSetupFileName $windowsSetupFileName `
  -WindowsPortableFileName $windowsPortableFileName `
  -AndroidApkFileName $androidApkFileName `
  -AndroidBundleFileName $androidBundleFileName `
  -ReleaseNotes $releaseNotes

Write-Host "Prepared public release for FHPlayer $appVersion"
Write-Host "Release root: $resolvedReleaseRoot"
Write-Host "Manifest: $resolvedManifestPath"
Write-Host "Windows: $windowsVersionDirectory"
Write-Host "Android: $androidVersionDirectory"
