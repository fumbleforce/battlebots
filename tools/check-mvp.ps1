param([Parameter(Mandatory = $true)][string]$GodotPath)
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'check-drive.ps1') -GodotPath $GodotPath
$projectRoot = Join-Path $PSScriptRoot '../battlebots'
function Invoke-MvpTest {
    param([string]$Script, [string]$Marker)
    $lines = & $GodotPath --headless --path $projectRoot --fixed-fps 60 --script $Script --quit-after 10000 2>&1
    $exitCode = $LASTEXITCODE
    $lines | ForEach-Object { Write-Host $_ }
    if ($exitCode -ne 0 -or ($lines -match 'SCRIPT ERROR:|Parse Error:|^ERROR:') -or -not ($lines -match "^$Marker`$")) {
        throw "MVP test failed: $Script ($exitCode)"
    }
}
Invoke-MvpTest 'res://tests/simulation/content_smoke.gd' 'CONTENT PASS'
Invoke-MvpTest 'res://tests/simulation/rules_smoke.gd' 'RULES PASS'
Invoke-MvpTest 'res://tests/simulation/combat_physics_smoke.gd' 'COMBAT PHYSICS PASS'
Invoke-MvpTest 'res://tests/simulation/stress_smoke.gd' 'STRESS PASS'
$previousProfile = $env:BATTLEBOTS_NET_PROFILE
try {
    foreach ($profile in @('0', '80', '150')) {
        $env:BATTLEBOTS_NET_PROFILE = $profile
        Invoke-MvpTest 'res://tests/network/session_smoke.gd' 'NETWORK PASS'
    }
} finally {
    $env:BATTLEBOTS_NET_PROFILE = $previousProfile
}
Write-Host 'MVP PASS'
