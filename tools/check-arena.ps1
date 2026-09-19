param([Parameter(Mandatory = $true)][string]$GodotPath, [switch]$Capture)
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'check-baseline.ps1') -GodotPath $GodotPath
$projectRoot = Join-Path $PSScriptRoot '../battlebots'
foreach ($check in @('res://tests/presentation/foundry_arena_test.gd', 'res://tests/presentation/camera_arena_test.gd')) {
    $lines = & $GodotPath --headless --path $projectRoot --script $check 2>&1
    $checkExit = $LASTEXITCODE
    $lines | ForEach-Object { Write-Host $_ }
    if ($checkExit -ne 0 -or ($lines -match 'SCRIPT ERROR:|Parse Error:|^ERROR:|CrashHandlerException:|Program crashed|END OF C\+\+ BACKTRACE')) {
        throw "Arena validation failed ($check, exit $checkExit)"
    }
}
if ($Capture) {
    $lines = & $GodotPath --path $projectRoot --script res://tests/presentation/foundry_arena_test.gd -- --capture --benchmark 2>&1
    $checkExit = $LASTEXITCODE
    $lines | ForEach-Object { Write-Host $_ }
    if ($checkExit -ne 0 -or ($lines -match 'SCRIPT ERROR:|Parse Error:|^ERROR:|CrashHandlerException:|Program crashed|END OF C\+\+ BACKTRACE')) {
        throw "Arena rendered validation failed (exit $checkExit)"
    }
}
