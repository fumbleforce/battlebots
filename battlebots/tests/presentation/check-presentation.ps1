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
    if ($runExitCode -ne 0 -or ($outputLines -match 'SCRIPT ERROR:|Parse Error:|^ERROR:') -or
        ($Marker -and -not ($outputLines -match "^$Marker$"))) {
        throw "Presentation check failed: $Marker (exit $runExitCode)"
    }
}
Invoke-PresentationCheck -EngineArgs @('--headless', '--path', $projectRoot, '--editor', '--import', '--quit')
$checks = @(
    @('camera_arena_test.gd', 'PRESENTATION PASS'),
    @('camera_settings_test.gd', 'CAMERA SETTINGS PASS'),
    @('input_menu_test.gd', 'INPUT MENU PASS')
)
foreach ($check in $checks) {
    Invoke-PresentationCheck -EngineArgs @('--headless', '--path', $projectRoot,
        '--fixed-fps', '60', '--script', "res://tests/presentation/$($check[0])",
        '--quit-after', '10000') -Marker $check[1]
}
Write-Host 'B PRESENTATION CHECKS PASS'
