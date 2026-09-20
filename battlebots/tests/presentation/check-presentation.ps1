param([Parameter(Mandatory = $true)][string]$GodotPath)
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$engineVersion = & $GodotPath --version
if ($LASTEXITCODE -ne 0 -or $engineVersion -notmatch '^4\.7\.2\.stable') {
    throw "Expected Godot 4.7.2 stable; got $engineVersion"
}
function Invoke-PresentationCheck {
    param([string[]]$EngineArgs, [string]$Marker = '')
    $outputLines = & $GodotPath @EngineArgs 2>&1
    $runExitCode = $LASTEXITCODE
    $outputLines | ForEach-Object { Write-Host $_ }
    # Godot's native crash handler can print a backtrace and still return zero.
    if ($runExitCode -ne 0 -or ($outputLines -match 'SCRIPT ERROR:|Parse Error:|^ERROR:|CrashHandlerException:|Program crashed|END OF C\+\+ BACKTRACE') -or
        ($Marker -and -not ($outputLines -match "^$Marker$"))) {
        throw "Presentation check failed: $Marker (exit $runExitCode)"
    }
}
Invoke-PresentationCheck -EngineArgs @('--headless', '--path', $projectRoot, '--editor', '--import', '--quit')
foreach ($check in @(@('practice_hud_test.gd', 'PRACTICE HUD PASS'),
    @('practice_session_test.gd', 'PRACTICE SESSION PASS'),
    @('practice_menu_test.gd', 'PRACTICE MENU PASS'))) {
    Invoke-PresentationCheck -EngineArgs @('--headless', '--path', $projectRoot,
        '--max-fps', '60', '--script', "res://tests/practice/$($check[0])",
        '--quit-after', '6000') -Marker $check[1]
}
foreach ($check in @(@('gameplay_audio_test.gd', 'GAMEPLAY AUDIO PASS'),
    @('crowd_sound_bank_test.gd', 'CROWD_SOUND_BANK_PASS'),
    @('crowd_audio_test.gd', 'CROWD AUDIO PASS'),
    @('spatial_impact_audio_test.gd', 'SPATIAL_IMPACT_AUDIO_PASS'),
    @('combat_audio_status_test.gd', 'COMBAT_AUDIO_STATUS_PASS'),
    @('status_sound_bank_test.gd', 'STATUS_SOUND_BANK_PASS'),
    @('combat_status_playback_test.gd', 'COMBAT STATUS PLAYBACK PASS'),
    @('status_audio_game_test.gd', 'STATUS AUDIO GAME PASS'),
    @('status_caption_layout_test.gd', 'STATUS_CAPTION_LAYOUT_PASS'),
    @('gameplay_loop_bank_test.gd', 'GAMEPLAY_LOOP_BANK_PASS'),
    @('continuous_gameplay_audio_test.gd', 'CONTINUOUS_GAMEPLAY_AUDIO_TEST: PASS'),
    @('audio_session_test.gd', 'AUDIO SESSION PASS'),
    @('continuous_audio_game_test.gd', 'CONTINUOUS AUDIO GAME PASS'),
    @('audio_settings_test.gd', 'AUDIO SETTINGS PASS'),
    @('audio_menu_test.gd', 'AUDIO MENU PASS'))) {
    Invoke-PresentationCheck -EngineArgs @('--headless', '--path', $projectRoot,
        '--max-fps', '60', '--script', "res://tests/audio/$($check[0])",
        '--quit-after', '6000') -Marker $check[1]
}
$checks = @(
	@('main_menu_fit_test.gd', 'MAIN MENU FIT PASS'),
	@('menu_host_fit_test.gd', 'MENU HOST FIT PASS'),
	@('video_settings_test.gd', 'VIDEO SETTINGS PASS'),
	@('video_settings_layout_test.gd', 'VIDEO SETTINGS LAYOUT PASS'),
	@('settings_hub_test.gd', 'SETTINGS HUB PASS'),
	@('private_lobby_code_test.gd', 'PRIVATE LOBBY CODE PASS'),
	@('duel_scoreboard_test.gd', 'DUEL SCOREBOARD PASS'),
	@('world_markers_test.gd', 'WORLD MARKERS PASS'),
	@('world_markers_game_test.gd', 'WORLD MARKERS GAME PASS'),
    @('menu_text_settings_test.gd', 'MENU TEXT SETTINGS PASS'),
    @('menu_text_screens_test.gd', 'MENU TEXT SCREENS PASS'),
    @('match_menu_text_test.gd', 'MATCH MENU TEXT PASS'),
    @('combat_hud_test.gd', 'COMBAT HUD PASS'),
    @('game_hud_test.gd', 'GAME HUD PASS'),
    @('match_hud_layout_test.gd', 'MATCH HUD LAYOUT PASS'),
    @('game_menu_page_test.gd', 'GAME MENU PAGE PASS'),
    @('online_panel_test.gd', 'ONLINE PANEL PASS'),
    @('results_panels_test.gd', 'RESULTS PANELS PASS'),
    @('lobby_panel_layout_test.gd', 'LOBBY PANEL LAYOUT PASS'),
    @('reconnect_panel_test.gd', 'RECONNECT PANEL PASS'),
    @('hud_preferences_test.gd', 'HUD PREFERENCES PASS'),
    @('hud_settings_test.gd', 'HUD SETTINGS PASS'),
    @('hud_accessibility_test.gd', 'HUD ACCESSIBILITY PASS'),
    @('hud_accessibility_menu_test.gd', 'HUD ACCESSIBILITY MENU PASS'),
    @('match_results_test.gd', 'MATCH RESULTS PASS'),
    @('camera_arena_test.gd', 'PRESENTATION PASS'),
    @('foundry_arena_test.gd', 'FOUNDRY PASS'),
    @('camera_settings_test.gd', 'CAMERA SETTINGS PASS'),
    @('input_menu_test.gd', 'INPUT MENU PASS'),
    @('input_preferences_test.gd', 'INPUT PREFERENCES PASS'),
    @('weapon_toggle_test.gd', 'WEAPON TOGGLE PASS'),
    @('input_settings_test.gd', 'INPUT SETTINGS PASS'),
    @('network_diagnostics_test.gd', 'NETWORK DIAGNOSTICS PASS'),
    @('network_diagnostics_sandbox_test.gd', 'NETWORK DIAGNOSTICS SANDBOX PASS'),
    @('lobby_panel_test.gd', 'LOBBY PANEL PASS'),
    @('match_hud_test.gd', 'MATCH HUD PASS'),
    @('menu_profile_test.gd', 'MENU PROFILE PASS'),
    @('garage_history_test.gd', 'GARAGE HISTORY PASS'),
    @('menu_customization_screens_test.gd', 'MENU CUSTOMIZATION SCREENS PASS'),
    @('menu_kit_test.gd', 'MENU KIT PASS'),
    @('menu_flow_test.gd', 'MENU FLOW PASS'),
    @('menu_music_test.gd', 'MENU MUSIC PASS'),
    @('lobby_game_test.gd', 'LOBBY GAME PASS'),
    @('camera_contact_test.gd', 'CAMERA CONTACT PASS')
)
foreach ($check in $checks) {
    Invoke-PresentationCheck -EngineArgs @('--headless', '--path', $projectRoot,
        '--fixed-fps', '60', '--script', "res://tests/presentation/$($check[0])",
        '--quit-after', '10000') -Marker $check[1]
}
Invoke-PresentationCheck -EngineArgs @('--headless', '--path', $projectRoot,
    '--max-fps', '60', 'res://tests/presentation/camera_round_lifecycle_test.tscn', '--quit-after', '6000') -Marker 'CAMERA ROUND LIFECYCLE PASS'
Invoke-PresentationCheck -EngineArgs @('--headless', '--path', $projectRoot,
    '--max-fps', '60', 'res://tests/presentation/camera_duel_lifecycle_test.tscn', '--quit-after', '6000') -Marker 'CAMERA DUEL LIFECYCLE PASS'
Invoke-PresentationCheck -EngineArgs @('--headless', '--path', $projectRoot,
    'res://tests/presentation/camera_mouse_scale_test.tscn', '--quit-after', '10000') -Marker 'CAMERA MOUSE SCALE PASS'
Invoke-PresentationCheck -EngineArgs @('--headless', '--path', $projectRoot,
    'res://tests/presentation/camera_terrain_test.tscn', '--quit-after', '10000') -Marker 'CAMERA TERRAIN PASS'
Invoke-PresentationCheck -EngineArgs @('--headless', '--path', $projectRoot,
    'res://tests/presentation/garage_preview_test.tscn', '--quit-after', '10000') -Marker 'GARAGE PREVIEW PASS'
Invoke-PresentationCheck -EngineArgs @('--headless', '--path', $projectRoot,
    'res://tests/presentation/garage_showcase_test.tscn', '--quit-after', '10000') -Marker 'GARAGE SHOWCASE PASS'
Invoke-PresentationCheck -EngineArgs @('--headless', '--path', $projectRoot,
    'res://tests/presentation/featured_vehicle_test.tscn', '--quit-after', '10000') -Marker 'FEATURED VEHICLE PASS'
Invoke-PresentationCheck -EngineArgs @('--headless', '--path', $projectRoot,
    '--max-fps', '60', 'res://tests/presentation/featured_vehicle_menu_test.tscn', '--quit-after', '6000') -Marker 'FEATURED VEHICLE MENU PASS'
Invoke-PresentationCheck -EngineArgs @('--headless', '--path', $projectRoot,
    'res://tests/presentation/garage_test_drive_entry_test.tscn', '--quit-after', '10000') -Marker 'GARAGE TEST DRIVE ENTRY PASS'
Invoke-PresentationCheck -EngineArgs @('--headless', '--path', $projectRoot,
    '--max-fps', '60', 'res://tests/presentation/garage_test_drive_game_test.tscn', '--quit-after', '6000') -Marker 'GARAGE TEST DRIVE GAME PASS'
Invoke-PresentationCheck -EngineArgs @('--headless', '--path', $projectRoot,
    'res://tests/presentation/garage_comparison_test.tscn', '--quit-after', '10000') -Marker 'GARAGE COMPARISON PASS'
Invoke-PresentationCheck -EngineArgs @('--headless', '--path', $projectRoot,
    'res://tests/presentation/garage_comparison_panel_test.tscn', '--quit-after', '10000') -Marker 'GARAGE COMPARISON PANEL PASS'
Invoke-PresentationCheck -EngineArgs @('--headless', '--path', $projectRoot,
    'res://tests/presentation/loadout_repair_test.tscn', '--quit-after', '10000') -Marker 'LOADOUT REPAIR PASS'
Invoke-PresentationCheck -EngineArgs @('--headless', '--path', $projectRoot,
    'res://tests/presentation/garage_repair_test.tscn', '--quit-after', '10000') -Marker 'GARAGE REPAIR PASS'
Invoke-PresentationCheck -EngineArgs @('--headless', '--path', $projectRoot,
    'res://tests/presentation/loadout_recovery_test.tscn', '--quit-after', '10000') -Marker 'LOADOUT RECOVERY PASS'
Invoke-PresentationCheck -EngineArgs @('--headless', '--path', $projectRoot,
    'res://tests/presentation/garage_recovery_test.tscn', '--quit-after', '10000') -Marker 'GARAGE RECOVERY PASS'
Invoke-PresentationCheck -EngineArgs @('--headless', '--path', $projectRoot,
    'res://tests/presentation/customize_text_test.tscn', '--quit-after', '10000') -Marker 'CUSTOMIZE TEXT PASS'
Invoke-PresentationCheck -EngineArgs @('--headless', '--path', $projectRoot,
    'res://tests/presentation/garage_catalogue_text_test.tscn', '--quit-after', '10000') -Marker 'GARAGE CATALOGUE TEXT PASS'
Invoke-PresentationCheck -EngineArgs @('--headless', '--path', $projectRoot,
    'res://tests/presentation/control_settings_text_test.tscn', '--quit-after', '10000') -Marker 'CONTROL SETTINGS TEXT PASS'
Invoke-PresentationCheck -EngineArgs @('--headless', '--path', $projectRoot,
    'res://tests/presentation/b_menu_text_game_test.tscn', '--quit-after', '10000') -Marker 'B MENU TEXT GAME PASS'
# Real transport checks run at wall-clock speed; accelerated ENet can throttle.
foreach ($check in @(@('network_diagnostics_session_test.gd', 'NETWORK DIAGNOSTICS SESSION PASS'),
    @('combat_hud_session_test.gd', 'COMBAT HUD SESSION PASS'),
    @('game_reconnect_test.gd', 'GAME RECONNECT PASS'),
    @('menu_mode_guard_test.gd', 'MENU MODE GUARD PASS'),
    @('lobby_session_test.gd', 'LOBBY SESSION PASS'),
    @('lobby_game_network_test.gd', 'LOBBY GAME NETWORK PASS'),
    @('menu_kit_lobby_test.gd', 'MENU KIT LOBBY PASS'),
    @('online_menu_test.gd', 'ONLINE MENU PASS'),
    @('menu_game_network_test.gd', 'MENU GAME NETWORK PASS'))) {
    Invoke-PresentationCheck -EngineArgs @('--headless', '--path', $projectRoot,
        '--max-fps', '60', '--script', "res://tests/presentation/$($check[0])",
        '--quit-after', '6000') -Marker $check[1]
}
Invoke-PresentationCheck -EngineArgs @('--headless', '--path', $projectRoot,
    '--max-fps', '60', '--script', 'res://tests/services/fake_public_api_port_test.gd',
    '--quit-after', '6000') -Marker 'HTTP FIXTURE PORT PASS'
Invoke-PresentationCheck -EngineArgs @('--headless', '--path', $projectRoot,
    '--max-fps', '60', '--script', 'res://tests/services/public_service_client_test.gd',
    '--quit-after', '6000') -Marker 'PUBLIC SERVICE CLIENT PASS'
Invoke-PresentationCheck -EngineArgs @('--headless', '--path', $projectRoot,
    '--max-fps', '60', '--script', 'res://tests/services/duel_quick_play_client_test.gd',
    '--quit-after', '6000') -Marker 'DUEL QUICK PLAY CLIENT PASS'
Write-Host 'B PRESENTATION CHECKS PASS'
