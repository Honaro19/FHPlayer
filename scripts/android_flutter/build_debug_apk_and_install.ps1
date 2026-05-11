param(
  [string]$BuildDir = "",
  [string]$OutputDir = "",
  [string]$DeviceSerial = "",
  [string]$FlutterRoot = "",
  [switch]$NoLaunch
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$buildArgs = @()
if ($BuildDir) {
  $buildArgs += @("-BuildDir", $BuildDir)
}
if ($OutputDir) {
  $buildArgs += @("-OutputDir", $OutputDir)
}
if ($FlutterRoot) {
  $buildArgs += @("-FlutterRoot", $FlutterRoot)
}

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "build_debug_apk.ps1") @buildArgs
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

$installArgs = @()
if ($BuildDir) {
  $installArgs += @("-BuildDir", $BuildDir)
}
if ($DeviceSerial) {
  $installArgs += @("-DeviceSerial", $DeviceSerial)
}
if ($FlutterRoot) {
  $installArgs += @("-FlutterRoot", $FlutterRoot)
}
if (-not $NoLaunch) {
  $installArgs += "-LaunchApp"
}

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "install_debug_apk.ps1") @installArgs
exit $LASTEXITCODE
