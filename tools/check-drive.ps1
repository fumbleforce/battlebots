param(
    [Parameter(Mandatory = $true)]
    [string]$GodotPath
)
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'check-baseline.ps1') -GodotPath $GodotPath
$projectRoot = Join-Path $PSScriptRoot '../battlebots'
$lines = & $GodotPath --headless --path $projectRoot --fixed-fps 60 --script res://tests/simulation/drive_smoke.gd 2>&1
$engineExitCode = $LASTEXITCODE
$lines | ForEach-Object { Write-Host $_ }
# Godot's native crash handler can print a backtrace and still return zero.
if ($engineExitCode -ne 0 -or ($lines -match 'SCRIPT ERROR:|Parse Error:|^ERROR:|CrashHandlerException:|Program crashed|END OF C\+\+ BACKTRACE') -or -not ($lines -match '^DRIVE PASS$')) {
    throw "Drive validation failed (exit $engineExitCode)"
}
$lines = & $GodotPath --headless --path $projectRoot --fixed-fps 60 res://tests/simulation/heavy_drive_test.tscn --quit-after 5000 2>&1
$engineExitCode = $LASTEXITCODE
$lines | ForEach-Object { Write-Host $_ }
if ($engineExitCode -ne 0 -or ($lines -match 'SCRIPT ERROR:|Parse Error:|^ERROR:|CrashHandlerException:|Program crashed|END OF C\+\+ BACKTRACE') -or -not ($lines -match '^HEAVY DRIVE PASS$')) {
    throw "Heavy drive validation failed (exit $engineExitCode)"
}
