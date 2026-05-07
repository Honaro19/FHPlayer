param(
    [string]$FlutterExe = ".\.tools\flutter\bin\flutter.bat",
    [string]$ProjectDir = ".\FHPlayerMobile\fhplayer_flutter",
    [string[]]$FlutterArgs = @("--no-version-check", "--version"),
    [int]$TimeoutSeconds = 180,
    [string]$LogDir = ".\.tmp\flutter-logs",
    [string]$WorkspaceDataDir = ".\.tmp\flutter-userdata"
)

$ErrorActionPreference = "Stop"

function Resolve-RequiredPath {
    param(
        [string]$PathValue,
        [string]$Label
    )

    $resolved = Resolve-Path -LiteralPath $PathValue -ErrorAction SilentlyContinue
    if (-not $resolved) {
        throw "$Label not found: $PathValue"
    }
    return $resolved.Path
}

function Quote-CmdArgument {
    param([string]$Value)

    if ($null -eq $Value) {
        return '""'
    }
    return '"' + ($Value -replace '"', '""') + '"'
}

$flutterPath = Resolve-RequiredPath -PathValue $FlutterExe -Label "Flutter executable"
$projectPath = Resolve-RequiredPath -PathValue $ProjectDir -Label "Project directory"

New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
$resolvedLogDir = (Resolve-Path -LiteralPath $LogDir).Path
New-Item -ItemType Directory -Path $WorkspaceDataDir -Force | Out-Null
$resolvedWorkspaceDataDir = (Resolve-Path -LiteralPath $WorkspaceDataDir).Path
$workspaceRoamingPath = Join-Path $resolvedWorkspaceDataDir "AppData\Roaming"
$workspaceLocalPath = Join-Path $resolvedWorkspaceDataDir "AppData\Local"
$workspacePubCachePath = Join-Path $resolvedWorkspaceDataDir "Pub\Cache"
New-Item -ItemType Directory -Path $workspaceRoamingPath, $workspaceLocalPath, $workspacePubCachePath -Force | Out-Null

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$safeCommand = ($FlutterArgs -join "_") -replace '[^A-Za-z0-9_.-]', '_'
if ($safeCommand.Length -gt 80) {
    $safeCommand = $safeCommand.Substring(0, 80)
}

$stdoutPath = Join-Path $resolvedLogDir "$stamp-$safeCommand.out.log"
$stderrPath = Join-Path $resolvedLogDir "$stamp-$safeCommand.err.log"
$metaPath = Join-Path $resolvedLogDir "$stamp-$safeCommand.meta.log"

$quotedFlutter = Quote-CmdArgument $flutterPath
$quotedArgs = @($FlutterArgs | ForEach-Object { Quote-CmdArgument $_ })
$cmdLine = "call $quotedFlutter $($quotedArgs -join ' ')"

$meta = @(
    "Started: $(Get-Date -Format o)"
    "FlutterExe: $flutterPath"
    "ProjectDir: $projectPath"
    "TimeoutSeconds: $TimeoutSeconds"
    "Command: $cmdLine"
    "WorkspaceDataDir: $resolvedWorkspaceDataDir"
    "ChildAPPDATA: $workspaceRoamingPath"
    "ChildLOCALAPPDATA: $workspaceLocalPath"
    "ChildPUB_CACHE: $workspacePubCachePath"
    "PowerShell: $($PSVersionTable.PSVersion)"
    "User: $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"
    "PATH: $env:Path"
    ""
)
$meta | Set-Content -LiteralPath $metaPath -Encoding UTF8

$childPath = $env:Path
$launcherName = [System.IO.Path]::GetFileName($flutterPath).ToLowerInvariant()
if ($launcherName -in @("flutter.bat", "dart.bat")) {
    $flutterRoot = Split-Path -Parent (Split-Path -Parent $flutterPath)
    $mingitPath = Join-Path $flutterRoot "bin\mingit\cmd"
    if ([System.IO.File]::Exists((Join-Path $mingitPath "git.exe"))) {
        $childPath = "$mingitPath;$childPath"
        Add-Content -LiteralPath $metaPath -Encoding UTF8 -Value "ChildPathPrepend: $mingitPath"
    }

    $cacheDir = Join-Path $flutterRoot "bin\cache"
    $lockPath = Join-Path $cacheDir "flutter.bat.lock"
    Add-Content -LiteralPath $metaPath -Encoding UTF8 -Value "PreflightLockPath: $lockPath"

    try {
        if (-not [System.IO.Directory]::Exists($cacheDir)) {
            [System.IO.Directory]::CreateDirectory($cacheDir) | Out-Null
        }
        $lockStream = [System.IO.File]::Open(
            $lockPath,
            [System.IO.FileMode]::OpenOrCreate,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::None
        )
        $lockStream.Dispose()
        Add-Content -LiteralPath $metaPath -Encoding UTF8 -Value "PreflightLockWritable: True"
    } catch {
        $exitCode = 126
        $message = "Unable to open Flutter SDK lock '$lockPath'. Flutter batch launchers retry forever in this state. Run this script outside the sandbox or place Flutter under a writable root. Error: $($_.Exception.Message)"
        [System.IO.File]::WriteAllText($stderrPath, "$message`r`n", [System.Text.UTF8Encoding]::new($false))
        Add-Content -LiteralPath $metaPath -Encoding UTF8 -Value @(
            "PreflightLockWritable: False"
            "PreflightError: $($_.Exception.Message)"
            "Finished: $(Get-Date -Format o)"
            "TimedOut: False"
            "ExitCode: $exitCode"
            "Stdout: $stdoutPath"
            "Stderr: $stderrPath"
        )

        [pscustomobject]@{
            ExitCode = $exitCode
            TimedOut = $false
            Stdout = $stdoutPath
            Stderr = $stderrPath
            Meta = $metaPath
        }
        exit $exitCode
    }
}

$process = [System.Diagnostics.Process]::new()
$startInfo = [System.Diagnostics.ProcessStartInfo]::new()
$startInfo.FileName = if ($env:ComSpec) { $env:ComSpec } else { "cmd.exe" }
$startInfo.WorkingDirectory = $projectPath
$startInfo.UseShellExecute = $false
$startInfo.CreateNoWindow = $true
$setEnvironment = @(
    "set `"APPDATA=$workspaceRoamingPath`"",
    "set `"LOCALAPPDATA=$workspaceLocalPath`"",
    "set `"PUB_CACHE=$workspacePubCachePath`"",
    "set `"FLUTTER_SUPPRESS_ANALYTICS=true`"",
    "set `"DART_SUPPRESS_ANALYTICS=true`"",
    "set `"PATH=$childPath`""
)
$redirectedCmdLine = "$cmdLine 1> $(Quote-CmdArgument $stdoutPath) 2> $(Quote-CmdArgument $stderrPath)"
$startInfo.Arguments = "/d /c $($setEnvironment -join ' && ') && $redirectedCmdLine"
$process.StartInfo = $startInfo

[System.IO.File]::WriteAllText($stdoutPath, "", [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::WriteAllText($stderrPath, "", [System.Text.UTF8Encoding]::new($false))

[void]$process.Start()
Add-Content -LiteralPath $metaPath -Encoding UTF8 -Value "ProcessPid: $($process.Id)"

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$timedOut = $false
while (-not $process.WaitForExit(500)) {
    if ((Get-Date) -ge $deadline) {
        $timedOut = $true
        Add-Content -LiteralPath $metaPath -Encoding UTF8 -Value "Timed out: $(Get-Date -Format o)"
        try {
            $process.Kill($true)
            Add-Content -LiteralPath $metaPath -Encoding UTF8 -Value "ManagedKill: requested process tree kill"
        } catch {
            Add-Content -LiteralPath $metaPath -Encoding UTF8 -Value "ManagedKillFailed: $($_.Exception.Message)"
            try {
                $taskkillOutput = & taskkill.exe /PID $process.Id /T /F 2>&1
                Add-Content -LiteralPath $metaPath -Encoding UTF8 -Value "TaskkillExitCode: $LASTEXITCODE"
                $taskkillOutput | Add-Content -LiteralPath $metaPath -Encoding UTF8
            } catch {
                Add-Content -LiteralPath $metaPath -Encoding UTF8 -Value "TaskkillFailed: $($_.Exception.Message)"
            }
        }
        if (-not $process.WaitForExit(10000)) {
            Add-Content -LiteralPath $metaPath -Encoding UTF8 -Value "ProcessStillRunningAfterKill: $($process.Id)"
        }
        break
    }
}

$exitCode = if ($timedOut) { 124 } else { $process.ExitCode }

if (-not $process.HasExited) {
    Add-Content -LiteralPath $metaPath -Encoding UTF8 -Value "OutputCaptureIncomplete: process did not exit"
}

Add-Content -LiteralPath $metaPath -Encoding UTF8 -Value @(
    "Finished: $(Get-Date -Format o)"
    "TimedOut: $timedOut"
    "ExitCode: $exitCode"
    "Stdout: $stdoutPath"
    "Stderr: $stderrPath"
)

[pscustomobject]@{
    ExitCode = $exitCode
    TimedOut = $timedOut
    Stdout = $stdoutPath
    Stderr = $stderrPath
    Meta = $metaPath
}

exit $exitCode
