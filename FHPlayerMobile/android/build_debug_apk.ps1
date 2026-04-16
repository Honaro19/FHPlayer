$ErrorActionPreference = "Stop"

$gradle = Get-ChildItem "$env:USERPROFILE\.gradle\wrapper\dists\gradle-8.0.2-bin" -Recurse -Filter gradle.bat |
  Select-Object -First 1 -ExpandProperty FullName

if (-not $gradle) {
  throw "Gradle 8.0.2 was not found in the local wrapper cache. Open any Android project once in Android Studio or install Gradle 8.0.2."
}

$buildDir = Join-Path $env:LOCALAPPDATA "FHPlayer\AndroidBuild\app"
New-Item -ItemType Directory -Force -Path $buildDir | Out-Null

$generatedAssetDirs = @(
  (Join-Path $PSScriptRoot "app\build\generated\fhplayer-assets"),
  (Join-Path $PSScriptRoot "app\build\intermediates\assets\debug\www"),
  (Join-Path $buildDir "generated\fhplayer-assets"),
  (Join-Path $buildDir "intermediates\assets\debug\www")
)

foreach ($assetDir in $generatedAssetDirs) {
  if (Test-Path $assetDir) {
    Remove-Item -LiteralPath $assetDir -Recurse -Force
  }
}

& $gradle -p $PSScriptRoot "-PfhplayerBuildDir=$buildDir" clean assembleDebug

if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

$apkPath = Join-Path $buildDir "outputs\apk\debug\app-debug.apk"
if (Test-Path $apkPath) {
  Write-Host "APK created at $apkPath"
} else {
  Write-Warning "Gradle finished, but no APK was found at $apkPath"
}
