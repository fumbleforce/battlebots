param(
    [Parameter(Mandatory = $true)]
    [string]$GodotPath
)
$ErrorActionPreference = 'Stop'
$projectRoot = Join-Path $PSScriptRoot '../battlebots'
$engineVersion = & $GodotPath --version
if ($LASTEXITCODE -ne 0 -or $engineVersion -notmatch '^4\.7\.2\.stable') {
    throw "Expected Godot 4.7.2 stable; got $engineVersion"
}
function Invoke-GodotCheck {
    param([string[]]$EngineArgs)
    $lines = & $GodotPath @EngineArgs 2>&1
    $engineExitCode = $LASTEXITCODE
    $lines | ForEach-Object { Write-Host $_ }
    if ($engineExitCode -ne 0 -or ($lines -match 'SCRIPT ERROR:|Parse Error:|^ERROR:')) {
        throw "Godot validation failed (exit $engineExitCode)"
    }
}
Invoke-GodotCheck -EngineArgs @('--headless', '--path', $projectRoot, '--editor', '--import', '--quit')
Invoke-GodotCheck -EngineArgs @('--headless', '--path', $projectRoot, '--script', 'res://tests/baseline_smoke.gd')
