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
    if ($exitCode -ne 0 -or ($lines -match 'SCRIPT ERROR:|Parse Error:|^ERROR:|CrashHandlerException:|Program crashed|END OF C\+\+ BACKTRACE') -or -not ($lines -match "^$Marker`$")) {
        throw "MVP test failed: $Script ($exitCode)"
    }
}
Invoke-MvpTest 'res://tests/simulation/content_smoke.gd' 'CONTENT PASS'
Invoke-MvpTest 'res://tests/simulation/heat_only_state.gd' 'HEAT ONLY STATE PASS'
Invoke-MvpTest 'res://tests/simulation/reverse_steering.gd' 'REVERSE STEERING PASS'
Invoke-MvpTest 'res://tests/simulation/heavy_spawn_test.gd' 'HEAVY SPAWN PASS'
Invoke-MvpTest 'res://tests/simulation/match_pickups_test.gd' 'MATCH PICKUPS PASS'
Invoke-MvpTest 'res://tests/network/pickup_session.tscn' 'PICKUP SESSION PASS' -Scene -RealTime
Invoke-MvpTest 'res://tests/simulation/scaled_combat.tscn' 'SCALED COMBAT PASS' -Scene
Invoke-MvpTest 'res://tests/services/hosted_admission_test.gd' 'HOSTED ADMISSION PASS'
Invoke-MvpTest 'res://tests/network/hosted_admission_session.tscn' 'HOSTED ADMISSION SESSION PASS' -Scene -RealTime
Invoke-MvpTest 'res://tests/network/reconnect_session.gd' 'RECONNECT SESSION PASS' -RealTime
Invoke-MvpTest 'res://tests/simulation/horizontal_spinner_state.gd' 'HORIZONTAL SPINNER STATE PASS'
Invoke-MvpTest 'res://tests/simulation/horizontal_spinner_visual.gd' 'HORIZONTAL VISUAL PASS'
Invoke-MvpTest 'res://tests/simulation/horizontal_spinner_physics.tscn' 'HORIZONTAL SPINNER PHYSICS PASS' -Scene
Invoke-MvpTest 'res://tests/simulation/hammer_state.gd' 'HAMMER STATE PASS'
Invoke-MvpTest 'res://tests/simulation/minigun_state.gd' 'MINIGUN STATE PASS'
Invoke-MvpTest 'res://tests/simulation/minigun_physics.tscn' 'MINIGUN PHYSICS PASS' -Scene
Invoke-MvpTest 'res://tests/simulation/scorpion_grounded_modules.tscn' 'SCORPION GROUNDED MODULES PASS' -Scene
Invoke-MvpTest 'res://tests/presentation/scorpion_input_test.gd' 'SCORPION INPUT PASS'
Invoke-MvpTest 'res://tests/presentation/scorpion_assembly_test.tscn' 'SCORPION ASSEMBLY PASS' -Scene
Invoke-MvpTest 'res://tests/presentation/scorpion_tail_test.tscn' 'SCORPION TAIL PASS' -Scene
Invoke-MvpTest 'res://tests/presentation/scorpion_diesel_test.tscn' 'SCORPION DIESEL PASS' -Scene
Invoke-MvpTest 'res://tests/presentation/scorpion_garage_test.tscn' 'SCORPION GARAGE PASS' -Scene
Invoke-MvpTest 'res://tests/practice/practice_npcs_test.gd' 'PRACTICE NPC PASS'
Invoke-MvpTest 'res://tests/simulation/hammer_visual.gd' 'HAMMER VISUAL PASS'
Invoke-MvpTest 'res://tests/simulation/hammer_physics.tscn' 'HAMMER PHYSICS PASS' -Scene
Invoke-MvpTest 'res://tests/simulation/armour_layout_test.gd' 'ARMOUR LAYOUT PASS'
Invoke-MvpTest 'res://tests/simulation/saw_state.gd' 'SAW STATE PASS'
Invoke-MvpTest 'res://tests/simulation/saw_visual.gd' 'SAW VISUAL PASS'
Invoke-MvpTest 'res://tests/simulation/saw_physics.tscn' 'SAW PHYSICS PASS' -Scene
Invoke-MvpTest 'res://tests/simulation/rules_smoke.gd' 'RULES PASS'
Invoke-MvpTest 'res://tests/simulation/five_v_five_rules.tscn' 'FIVE V FIVE RULES PASS' -Scene
Invoke-MvpTest 'res://tests/simulation/ffa_rules.tscn' 'FFA RULES PASS' -Scene
Invoke-MvpTest 'res://tests/simulation/combat_physics_smoke.gd' 'COMBAT PHYSICS PASS'
Invoke-MvpTest 'res://tests/simulation/stress_smoke.gd' 'STRESS PASS'
Invoke-MvpTest 'res://tests/presentation/camera_arena_test.gd' 'PRESENTATION PASS'
Invoke-MvpTest 'res://tests/presentation/camera_settings_test.gd' 'CAMERA SETTINGS PASS'
Invoke-MvpTest 'res://tests/integration/app_smoke.gd' 'APP INTEGRATION PASS'
Invoke-MvpTest 'res://tests/integration/network_presentation_smoke.gd' 'PRESENTATION NETWORK PASS' -RealTime
Invoke-MvpTest 'res://tests/integration/duel_menu_smoke.gd' 'DUEL MENU PASS' -RealTime
Invoke-MvpTest 'res://tests/integration/ffa_menu_smoke.gd' 'FFA MENU PASS' -RealTime
Invoke-MvpTest 'res://tests/integration/advanced_menu_smoke.gd' 'ADVANCED MENU PASS' -RealTime
Invoke-MvpTest 'res://tests/integration/navigation_smoke.gd' 'NAVIGATION PASS' -RealTime
Invoke-MvpTest 'res://tests/network/airborne_replay.tscn' 'AIRBORNE REPLAY PASS' -Scene
Invoke-MvpTest 'res://tests/network/clock_sync.tscn' 'CLOCK SYNC PASS' -Scene -RealTime
Invoke-MvpTest 'res://tests/network/clock_delivery.tscn' 'CLOCK DELIVERY PASS' -Scene -RealTime
Invoke-MvpTest 'res://tests/network/results_delivery.tscn' 'RESULTS DELIVERY PASS' -Scene -RealTime
Invoke-MvpTest 'res://tests/network/ffa_disconnect.tscn' 'FFA DISCONNECT PASS' -Scene -RealTime
Invoke-MvpTest 'res://tests/network/snapshot_reordering.tscn' 'SNAPSHOT REORDERING PASS' -Scene -RealTime
Invoke-MvpTest 'res://tests/network/snapshot_recovery.tscn' 'SNAPSHOT RECOVERY PASS' -Scene -RealTime
Invoke-MvpTest 'res://tests/network/raw_datagram_relay.tscn' 'RAW DATAGRAM RELAY PASS' -Scene -RealTime
Invoke-MvpTest 'res://tests/network/remote_extrapolation.tscn' 'REMOTE EXTRAPOLATION PASS' -Scene -RealTime
Invoke-MvpTest 'res://tests/network/wall_contact.tscn' 'WALL CONTACT PASS' -Scene -RealTime
$previousProfile = $env:BATTLEBOTS_NET_PROFILE
$previousMtu = $env:BATTLEBOTS_NET_MTU
try {
    # Reproduce the public Fly path: oversized UDP datagrams are dropped.
    $env:BATTLEBOTS_NET_MTU = '1350'
    foreach ($profile in @('0', '80', '150')) {
        $env:BATTLEBOTS_NET_PROFILE = $profile
        Invoke-MvpTest 'res://tests/network/session_smoke.gd' 'NETWORK PASS' -RealTime
        Invoke-MvpTest 'res://tests/network/contact_reconciliation.tscn' 'CONTACT NETWORK PASS' -Scene -RealTime
        Invoke-MvpTest 'res://tests/network/horizontal_spinner_session.tscn' 'HORIZONTAL SPINNER SESSION PASS' -Scene -RealTime
        Invoke-MvpTest 'res://tests/network/hammer_session.tscn' 'HAMMER SESSION PASS' -Scene -RealTime
        if ($profile -in @('0', '80')) {
            Invoke-MvpTest 'res://tests/network/scorpion_session.tscn' 'SCORPION SESSION PASS' -Scene -RealTime
        }
        Invoke-MvpTest 'res://tests/network/saw_session.tscn' 'SAW SESSION PASS' -Scene -RealTime
        Invoke-MvpTest 'res://tests/network/transport_session.tscn' 'TRANSPORT SESSION PASS' -Scene -RealTime
        Invoke-MvpTest 'res://tests/network/five_v_five_session.tscn' 'FIVE V FIVE SESSION PASS' -Scene -RealTime
        Invoke-MvpTest 'res://tests/network/ffa_session.tscn' 'FFA SESSION PASS' -Scene -RealTime
    }
} finally {
    $env:BATTLEBOTS_NET_PROFILE = $previousProfile
    $env:BATTLEBOTS_NET_MTU = $previousMtu
}
Write-Host 'MVP PASS'
