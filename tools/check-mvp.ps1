param([Parameter(Mandatory = $true)][string]$GodotPath)
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'check-drive.ps1') -GodotPath $GodotPath
$projectRoot = Join-Path $PSScriptRoot '../battlebots'
function Invoke-MvpTest {
    param([string]$Script, [string]$Marker, [switch]$Scene, [switch]$RealTime)
    [string[]]$targetArgs = if ($Scene) { @($Script) } else { @('--script', $Script) }
    # ENet uses wall-clock transport timers. Accelerated physics can starve/drop
    # packets artificially; network acceptance runs at its intended real rate.
    [string[]]$timingArgs = if ($RealTime) { @('--max-fps', '60') } else { @('--fixed-fps', '60') }
    $lines = & $GodotPath --headless --path $projectRoot @timingArgs @targetArgs --quit-after 10000 2>&1
    $exitCode = $LASTEXITCODE
    $lines | ForEach-Object { Write-Host $_ }
    if ($exitCode -ne 0 -or ($lines -match 'SCRIPT ERROR:|Parse Error:|^ERROR:') -or -not ($lines -match "^$Marker`$")) {
        throw "MVP test failed: $Script ($exitCode)"
    }
}
Invoke-MvpTest 'res://tests/simulation/content_smoke.gd' 'CONTENT PASS'
Invoke-MvpTest 'res://tests/simulation/rules_smoke.gd' 'RULES PASS'
Invoke-MvpTest 'res://tests/simulation/five_v_five_rules.tscn' 'FIVE V FIVE RULES PASS' -Scene
Invoke-MvpTest 'res://tests/simulation/combat_physics_smoke.gd' 'COMBAT PHYSICS PASS'
Invoke-MvpTest 'res://tests/simulation/stress_smoke.gd' 'STRESS PASS'
Invoke-MvpTest 'res://tests/presentation/camera_arena_test.gd' 'PRESENTATION PASS'
Invoke-MvpTest 'res://tests/presentation/camera_settings_test.gd' 'CAMERA SETTINGS PASS'
Invoke-MvpTest 'res://tests/integration/app_smoke.gd' 'APP INTEGRATION PASS'
Invoke-MvpTest 'res://tests/integration/network_presentation_smoke.gd' 'PRESENTATION NETWORK PASS'
Invoke-MvpTest 'res://tests/integration/duel_menu_smoke.gd' 'DUEL MENU PASS'
Invoke-MvpTest 'res://tests/integration/navigation_smoke.gd' 'NAVIGATION PASS'
Invoke-MvpTest 'res://tests/network/airborne_replay.tscn' 'AIRBORNE REPLAY PASS' -Scene
Invoke-MvpTest 'res://tests/network/clock_sync.tscn' 'CLOCK SYNC PASS' -Scene -RealTime
Invoke-MvpTest 'res://tests/network/results_delivery.tscn' 'RESULTS DELIVERY PASS' -Scene -RealTime
Invoke-MvpTest 'res://tests/network/snapshot_reordering.tscn' 'SNAPSHOT REORDERING PASS' -Scene -RealTime
Invoke-MvpTest 'res://tests/network/raw_datagram_relay.tscn' 'RAW DATAGRAM RELAY PASS' -Scene -RealTime
Invoke-MvpTest 'res://tests/network/remote_extrapolation.tscn' 'REMOTE EXTRAPOLATION PASS' -Scene -RealTime
Invoke-MvpTest 'res://tests/network/wall_contact.tscn' 'WALL CONTACT PASS' -Scene -RealTime
$previousProfile = $env:BATTLEBOTS_NET_PROFILE
try {
    foreach ($profile in @('0', '80', '150')) {
        $env:BATTLEBOTS_NET_PROFILE = $profile
        Invoke-MvpTest 'res://tests/network/session_smoke.gd' 'NETWORK PASS' -RealTime
        Invoke-MvpTest 'res://tests/network/contact_reconciliation.tscn' 'CONTACT NETWORK PASS' -Scene -RealTime
        Invoke-MvpTest 'res://tests/network/transport_session.tscn' 'TRANSPORT SESSION PASS' -Scene -RealTime
        Invoke-MvpTest 'res://tests/network/five_v_five_session.tscn' 'FIVE V FIVE SESSION PASS' -Scene -RealTime
    }
} finally {
    $env:BATTLEBOTS_NET_PROFILE = $previousProfile
}
Write-Host 'MVP PASS'
