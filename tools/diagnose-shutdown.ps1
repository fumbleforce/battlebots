param(
    [Parameter(Mandatory = $true)][string]$GodotPath,
    [ValidateSet('drive', 'baseline', 'views', 'practice', 'load', 'typed_array', 'typed_var')][string]$Fixture = 'drive',
    [ValidateRange(1, 50)][int]$Trials = 8
)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '../battlebots')).Path
$engine = (Resolve-Path -LiteralPath $GodotPath).Path
$version = & $engine --version
if ($LASTEXITCODE -ne 0 -or $version -notmatch '^4\.7\.2\.stable') {
    throw "Expected Godot 4.7.2 stable; got $version"
}
$runDirectory = Join-Path ([IO.Path]::GetTempPath()) ('battlebots-shutdown-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $runDirectory | Out-Null
$scriptPath = switch ($Fixture) {
    'drive' { 'res://tests/simulation/drive_smoke.gd' }
    'baseline' { 'res://tests/baseline_smoke.gd' }
    'views' { 'res://tests/networking/shutdown_view_diagnostic.gd' }
    # Every Windows CI exit crash on record (5/5, #10) was this test's exit.
    'practice' { 'res://tests/practice/practice_session_test.gd' }
    # Loads only BATTLEBOTS_DIAG_LOAD (or nothing), then quits.
    'load' { 'res://tests/networking/shutdown_load_diagnostic.gd' }
    'typed_array' { 'res://tests/networking/shutdown_typed_array_diagnostic.gd' }
    'typed_var' { 'res://tests/networking/shutdown_typed_var_diagnostic.gd' }
}
# ENet timers need wall-clock frames, as in check-presentation.
$timing = if ($Fixture -in @('practice', 'load', 'typed_array', 'typed_var')) { @('--max-fps', '60') } else { @('--fixed-fps', '60') }
$marker = switch ($Fixture) {
    'drive' { '^DRIVE PASS$' }
    'baseline' { '^BASELINE PASS$' }
    'views' { '^SHUTDOWN VIEW DONE$' }
    'practice' { '^PRACTICE SESSION PASS$' }
    'load' { '^SHUTDOWN LOAD DONE' }
    'typed_array' { '^SHUTDOWN LOAD DONE' }
    'typed_var' { '^SHUTDOWN LOAD DONE' }
}
$revision = & git -C $projectRoot rev-parse HEAD
$dirty = @(& git -C $projectRoot status --porcelain).Count -gt 0
$results = @()
Write-Host "Shutdown diagnosis: $Trials $Fixture trials. Logs: $runDirectory"
for ($trial = 1; $trial -le $Trials; $trial++) {
    $started = [DateTime]::UtcNow
    $lines = @(& $engine --headless --path $projectRoot @timing --script $scriptPath 2>&1)
    $engineExit = $LASTEXITCODE
    $logName = "$Fixture-$trial.log"
    $lines | Set-Content -LiteralPath (Join-Path $runDirectory $logName) -Encoding utf8
    $nativeCrash = @($lines -match 'CrashHandlerException:|Program crashed|END OF C\+\+ BACKTRACE').Count -gt 0
    $scriptError = @($lines -match 'SCRIPT ERROR:|Parse Error:|^ERROR:').Count -gt 0
    $completed = @($lines -match $marker).Count -gt 0
    $results += [ordered]@{
        trial = $trial; exit_code = $engineExit; native_crash = $nativeCrash
        script_error = $scriptError; completion_marker = $completed
        passed = ($engineExit -eq 0 -and -not $nativeCrash -and -not $scriptError -and $completed)
        started_utc = $started.ToString('o'); elapsed_seconds = ([DateTime]::UtcNow - $started).TotalSeconds
        log = $logName
    }
    # Persist after every exit so an interrupted diagnosis retains prior failures.
    [ordered]@{
        engine = $engine; version = "$version"; revision = "$revision"; dirty = $dirty
        fixture = $scriptPath; requested_trials = $Trials; results = @($results)
        scope = 'Bounded shutdown diagnosis; no retry can erase a failed exit. Clean trials do not prove the intermittent crash fixed.'
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $runDirectory 'report.json') -Encoding utf8
    Write-Host "Trial $trial/$Trials : exit $engineExit; marker $completed; native crash $nativeCrash; script error $scriptError"
}
$failed = @($results | Where-Object { -not $_.passed }).Count
if ($failed -gt 0) {
    throw "$failed/$Trials shutdown trials failed. All outcomes retained: $runDirectory/report.json"
}
Write-Host "All $Trials diagnostic exits were clean; this does not establish a crash fix. Report: $runDirectory/report.json"
