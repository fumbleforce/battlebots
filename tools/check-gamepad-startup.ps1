param([Parameter(Mandatory = $true)][string]$GodotPath)
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '../battlebots')).Path
$cachePath = Join-Path $projectRoot '.godot/global_script_class_cache.cfg'
# Simulate pulling #22 into an already imported checkout, then launching without
# an editor rescan. Run sequentially with imports; restore exact cache bytes.
$original = [IO.File]::ReadAllBytes($cachePath)
$cache = [Text.Encoding]::UTF8.GetString($original)
$entries = $cache.Trim() -replace '^list=\[\{', '' -replace '\}\]$', '' -split '\}, \{'
$kept = @($entries | Where-Object { $_ -notmatch '"class": &"GamepadInput"' })
if ($kept.Count -ne $entries.Count - 1) {
    throw 'Expected one imported GamepadInput entry; run the pinned editor import first.'
}
try {
    [IO.File]::WriteAllText($cachePath, ('list=[{' + ($kept -join '}, {') + "}]`n"), [Text.UTF8Encoding]::new($false))
    $lines = & $GodotPath --headless --path $projectRoot --max-fps 60 `
        --script res://tests/presentation/menu_flow_test.gd --quit-after 6000 2>&1
    $engineExitCode = $LASTEXITCODE
    $lines | ForEach-Object { Write-Host $_ }
    if ($engineExitCode -ne 0 -or
        ($lines -match 'SCRIPT ERROR:|Parse Error:|^ERROR:|CrashHandlerException:|Program crashed|END OF C\+\+ BACKTRACE') -or
        -not ($lines -match '^MENU FLOW PASS$')) {
        throw "Launch with stale controller class cache failed (exit $engineExitCode)"
    }
    Write-Host 'GAMEPAD STALE CACHE STARTUP PASS'
} finally {
    [IO.File]::WriteAllBytes($cachePath, $original)
}
