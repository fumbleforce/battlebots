param([Parameter(Mandatory = $true)][string]$GodotPath)
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '../battlebots')).Path
$engineVersion = & $GodotPath --version
if ($LASTEXITCODE -ne 0 -or $engineVersion -notmatch '^4\.7\.2\.stable') {
    throw "Expected Godot 4.7.2 stable; got $engineVersion"
}
# Real ENet timers and canonical rounds require wall-clock physics, not fixed-fps
# acceleration. The fixture has its own 500-second deadline; this frame bound is
# a secondary guard and cannot turn a timeout into a pass without the marker.
$lines = & $GodotPath --headless --path $projectRoot --max-fps 60 `
    res://tests/integration/natural_duel.tscn --quit-after 36000 2>&1
$engineExitCode = $LASTEXITCODE
$lines | ForEach-Object { Write-Host $_ }
if ($engineExitCode -ne 0 -or ($lines -match 'SCRIPT ERROR:|Parse Error:|^ERROR:|CrashHandlerException:|Program crashed|END OF C\+\+ BACKTRACE') -or
    -not ($lines -match '^NATURAL DUEL PASS$')) {
    throw "Natural duel gameplay validation failed (exit $engineExitCode)"
}
