param(
    [Parameter(Mandatory = $true)]
    [string]$GodotPath
)
$ErrorActionPreference = 'Stop'
$projectRoot = Join-Path $PSScriptRoot '../battlebots'
$engineVersion = & $GodotPath --version
if ($LASTEXITCODE -ne 0 -or $engineVersion -notmatch '^4\.7\.2\.stable') {
    throw "Expected Godot 4.7.2 stable; got $engineVersion"
}
function Invoke-GodotCheck {
    param([string[]]$EngineArgs)
    $lines = & $GodotPath @EngineArgs 2>&1
    $engineExitCode = $LASTEXITCODE
    $lines | ForEach-Object { Write-Host $_ }
    # Godot's native crash handler can print a backtrace and still return zero.
    if ($engineExitCode -ne 0 -or ($lines -match 'SCRIPT ERROR:|Parse Error:|^ERROR:|CrashHandlerException:|Program crashed|END OF C\+\+ BACKTRACE')) {
        throw "Godot validation failed (exit $engineExitCode)"
    }
}
Invoke-GodotCheck -EngineArgs @('--headless', '--path', $projectRoot, '--editor', '--import', '--quit')
Invoke-GodotCheck -EngineArgs @('--headless', '--path', $projectRoot, '--script', 'res://tests/baseline_smoke.gd')
& (Join-Path $PSScriptRoot 'check-gamepad-startup.ps1') -GodotPath $GodotPath
# Every class added since the last stable cache must survive a stale cache (#74).
& python (Join-Path $PSScriptRoot 'check-stale-class-cache.py') --godot $GodotPath
if ($LASTEXITCODE -ne 0) { throw 'Launch with a stale class cache failed' }
