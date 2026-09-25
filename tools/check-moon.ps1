param([Parameter(Mandatory = $true)][string]$GodotPath, [switch]$Capture)
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'check-arena.ps1') -GodotPath $GodotPath
$projectRoot = Join-Path $PSScriptRoot '../battlebots'
$checks = @(
    @('tests/presentation/moon_arena_test.gd', 'MOON ARENA PASS'),
    @('tests/presentation/arena_selection_test.gd', 'ARENA SELECTION PASS'),
    @('tests/presentation/main_menu_fit_test.gd', 'MAIN MENU FIT PASS'),
    @('tests/presentation/menu_host_fit_test.gd', 'MENU HOST FIT PASS'),
    # A scene: as a --script main loop it hit a Godot exit crash (#10).
    @('tests/practice/practice_session_test.tscn', 'PRACTICE SESSION PASS'),
    @('tests/network/moon_session_test.gd', 'NETWORK PASS'),
    @('tests/network/session_smoke.gd', 'NETWORK PASS')
)
foreach ($check in $checks) {
    $target = if ($check[0].EndsWith('.tscn')) { @("res://$($check[0])") } else { @('--script', "res://$($check[0])") }
    $lines = & $GodotPath --headless --path $projectRoot --max-fps 60 @target --quit-after 6000 2>&1
    $checkExit = $LASTEXITCODE
    $lines | ForEach-Object { Write-Host $_ }
    if ($checkExit -ne 0 -or ($lines -match 'SCRIPT ERROR:|Parse Error:|^ERROR:|CrashHandlerException:|Program crashed|END OF C\+\+ BACKTRACE') -or -not ($lines -match "^$($check[1])$")) {
        throw "Moon validation failed ($($check[0]), exit $checkExit)"
    }
}
if ($Capture) {
    $lines = & $GodotPath --path $projectRoot --max-fps 60 --script res://tests/presentation/moon_arena_test.gd -- --capture 2>&1
    $checkExit = $LASTEXITCODE
    $lines | ForEach-Object { Write-Host $_ }
    if ($checkExit -ne 0 -or ($lines -match 'SCRIPT ERROR:|Parse Error:|^ERROR:|CrashHandlerException:|Program crashed|END OF C\+\+ BACKTRACE') -or -not ($lines -match '^MOON ARENA PASS$')) {
        throw "Moon rendered validation failed (exit $checkExit)"
    }
}
