param([Parameter(Mandatory = $true)][string]$GodotPath)
$ErrorActionPreference = 'Stop'
$projectRoot = Join-Path $PSScriptRoot '../battlebots'
& (Join-Path $PSScriptRoot 'check-baseline.ps1') -GodotPath $GodotPath
function Invoke-SawbladeCheck([string]$Target, [switch]$Script, [switch]$Network) {
    [string[]]$targetArgs = if ($Script) { @('--script', $Target) } else { @($Target) }
    [string[]]$timing = if ($Network) { @('--max-fps', '60') } else { @('--fixed-fps', '120') }
    Write-Host "Checking $Target"
    $lines = & $GodotPath --headless --path $projectRoot @timing @targetArgs --quit-after 10000 2>&1
    $exitCode = $LASTEXITCODE
    $lines | ForEach-Object { Write-Host $_ }
    if ($exitCode -ne 0 -or $lines -match 'SCRIPT ERROR:|Parse Error:|^ERROR:|CrashHandlerException:' -or -not ($lines -match 'PASS')) {
        throw "Sawblade check failed: $Target"
    }
}
Invoke-SawbladeCheck 'res://tests/presentation/sawblade_test.tscn'
Invoke-SawbladeCheck 'res://tests/presentation/walker_test.tscn'
Invoke-SawbladeCheck 'res://tests/presentation/sawblade_contact_test.tscn'
Invoke-SawbladeCheck 'res://tests/simulation/hammer_physics.tscn'
Invoke-SawbladeCheck 'res://tests/simulation/saw_physics.tscn'
Invoke-SawbladeCheck 'res://tests/simulation/content_smoke.gd' -Script
Invoke-SawbladeCheck 'res://tests/presentation/menu_profile_test.gd' -Script
Invoke-SawbladeCheck 'res://tests/presentation/garage_history_test.gd' -Script
Invoke-SawbladeCheck 'res://tests/presentation/garage_preview_test.tscn'
Invoke-SawbladeCheck 'res://tests/presentation/garage_repair_test.tscn'
Invoke-SawbladeCheck 'res://tests/presentation/garage_recovery_test.tscn'
Invoke-SawbladeCheck 'res://tests/presentation/customize_text_test.tscn'
Invoke-SawbladeCheck 'res://tests/presentation/weapon_toggle_test.gd' -Script
$previousProfile = $env:BATTLEBOTS_NET_PROFILE
try {
    foreach ($profile in @('0', '80')) {
        $env:BATTLEBOTS_NET_PROFILE = $profile
        Invoke-SawbladeCheck 'res://tests/network/sawblade_session.gd' -Script -Network
    }
} finally { $env:BATTLEBOTS_NET_PROFILE = $previousProfile }
Write-Host 'SAWBLADE SUITE PASS'
