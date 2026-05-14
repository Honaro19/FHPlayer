param(
    [string]$FlutterExe = "flutter",
    [string]$ProjectDir = ".\fhplayer_flutter",
    [string]$TestPath = "",
    [string]$Reporter = "compact",
    [switch]$AllowPub,
    [int]$TimeoutSeconds = 600,
    [string]$LogDir = ".\.tmp\flutter-logs",
    [string]$WorkspaceDataDir = ".\.tmp\flutter-userdata",
    [string[]]$ExtraFlutterArgs = @()
)

$ErrorActionPreference = "Stop"

$runnerPath = Join-Path $PSScriptRoot "run_flutter_logged.ps1"
if (-not (Test-Path -LiteralPath $runnerPath)) {
    throw "Runner script not found: $runnerPath"
}

$flutterArgs = @("--no-version-check", "test")
if (-not $AllowPub) {
    $flutterArgs += "--no-pub"
}
if (-not [string]::IsNullOrWhiteSpace($Reporter)) {
    $flutterArgs += "-r"
    $flutterArgs += $Reporter
}
if (-not [string]::IsNullOrWhiteSpace($TestPath)) {
    $flutterArgs += $TestPath
}
if ($ExtraFlutterArgs.Count -gt 0) {
    $flutterArgs += $ExtraFlutterArgs
}

Write-Host "Running Flutter tests via logged runner..."
Write-Host "Project: $ProjectDir"
Write-Host "Args: $($flutterArgs -join ' ')"

$result = & $runnerPath `
    -FlutterExe $FlutterExe `
    -ProjectDir $ProjectDir `
    -FlutterArgs $flutterArgs `
    -TimeoutSeconds $TimeoutSeconds `
    -LogDir $LogDir `
    -WorkspaceDataDir $WorkspaceDataDir

Write-Host ""
Write-Host "ExitCode: $($result.ExitCode)"
Write-Host "TimedOut: $($result.TimedOut)"
Write-Host "Stdout:   $($result.Stdout)"
Write-Host "Stderr:   $($result.Stderr)"
Write-Host "Meta:     $($result.Meta)"

exit $result.ExitCode
