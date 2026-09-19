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
$checks = @(
    @('camera_arena_test.gd', 'PRESENTATION PASS'),
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
# Real transport checks run at wall-clock speed; accelerated ENet can throttle.
foreach ($check in @(@('network_diagnostics_session_test.gd', 'NETWORK DIAGNOSTICS SESSION PASS'),
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
    '--max-fps', '60', '--script', 'res://tests/services/public_service_client_test.gd',
    '--quit-after', '6000') -Marker 'PUBLIC SERVICE CLIENT PASS'
Write-Host 'B PRESENTATION CHECKS PASS'
