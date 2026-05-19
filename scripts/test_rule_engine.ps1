$ErrorActionPreference = "Stop"

Write-Warning "scripts\\test_rule_engine.ps1 is deprecated. Running Flutter tests instead."

$projectRoot = Split-Path -Parent $PSScriptRoot
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $projectRoot "scripts\\test_flutter.ps1") -Reporter compact
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}
