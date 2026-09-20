param([Parameter(Mandatory=$true)][string]$GodotPath)
$ErrorActionPreference='Stop'
& (Join-Path $PSScriptRoot 'check-moon.ps1') -GodotPath $GodotPath
$projectRoot=Join-Path $PSScriptRoot '../battlebots'
foreach($check in @(@('lunar_asset_test.gd','LUNAR ASSET PASS',$true),@('lunar_cinematic_test.gd','LUNAR CINEMATIC PASS',$false))) {
    $engineArgs=@('--path',$projectRoot,'--script',"res://tests/presentation/$($check[0])",'--quit-after','10000')
    if($check[2]) {$engineArgs=@('--headless')+$engineArgs}
    $lines=& $GodotPath @engineArgs 2>&1
    $engineExit=$LASTEXITCODE
    $lines | ForEach-Object {Write-Host $_}
    if($engineExit -ne 0 -or ($lines -match 'SCRIPT ERROR:|Parse Error:|^ERROR:|CrashHandlerException:|Program crashed|END OF C\+\+ BACKTRACE|couldn.t find previously baked nodes') -or -not ($lines -match "^$($check[1])$")) {
        throw "Cinematic lunar validation failed: $($check[0])"
    }
}
