# Verify that a later clean exit cannot erase a failed diagnostic trial.
$ErrorActionPreference = 'Stop'
$runnerPath = Join-Path $PSScriptRoot '../diagnose-shutdown.ps1'
$tempParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$fixtureRoot = Join-Path $tempParent ('battlebots-shutdown-test-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $fixtureRoot
$cleanupPaths = [Collections.Generic.List[string]]::new()
$cleanupPaths.Add($fixtureRoot)
$fakeEnginePath = Join-Path $fixtureRoot 'fake-engine.ps1'
$scenarioPath = Join-Path $fixtureRoot 'scenario.json'
$counterPath = Join-Path $fixtureRoot 'counter.txt'
$casesPassed = 0

function Assert-Condition([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

try {
    @'
$global:LASTEXITCODE = 0
if ($args -contains '--version') { '4.7.2.stable.official.test'; return }
$scenario = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'scenario.json') -Raw | ConvertFrom-Json
$expectedScript = switch ($scenario.fixture) {
    'drive' { 'res://tests/simulation/drive_smoke.gd' }
    'baseline' { 'res://tests/baseline_smoke.gd' }
    'views' { 'res://tests/networking/shutdown_view_diagnostic.gd' }
}
if ($args -notcontains $expectedScript -or $args -notcontains '--headless' -or $args -notcontains '--fixed-fps') {
    throw "Unexpected diagnostic engine arguments: $args"
}
$counterPath = Join-Path $PSScriptRoot 'counter.txt'
$trial = [int](Get-Content -LiteralPath $counterPath)
Set-Content -LiteralPath $counterPath -Value ($trial + 1)
$outcome = $scenario.outcomes[$trial]
$global:LASTEXITCODE = [int]$outcome.exitCode
$outcome.lines | ForEach-Object { Write-Output $_ }
'@ | Set-Content -LiteralPath $fakeEnginePath -Encoding UTF8

    $cases = @(
        @{ name = 'native crash then clean'; fixture = 'drive'; exitCode = 0; lines = @('DRIVE PASS', 'Program crashed with signal 11'); native = $true; scriptError = $false; marker = $true; failed = $true },
        @{ name = 'nonzero without backtrace then clean'; fixture = 'drive'; exitCode = -1073741819; lines = @('DRIVE PASS'); native = $false; scriptError = $false; marker = $true; failed = $true },
        @{ name = 'missing marker then clean'; fixture = 'drive'; exitCode = 0; lines = @('Drive stopped'); native = $false; scriptError = $false; marker = $false; failed = $true },
        @{ name = 'baseline script error then clean'; fixture = 'baseline'; exitCode = 0; lines = @('BASELINE PASS', 'SCRIPT ERROR: Invalid call'); native = $false; scriptError = $true; marker = $true; failed = $true },
        @{ name = 'both clean'; fixture = 'baseline'; exitCode = 0; lines = @('BASELINE PASS'); native = $false; scriptError = $false; marker = $true; failed = $false },
        @{ name = 'views backtrace then clean'; fixture = 'views'; exitCode = 0; lines = @('SHUTDOWN VIEW DONE', 'END OF C++ BACKTRACE'); native = $true; scriptError = $false; marker = $true; failed = $true }
    )
    foreach ($case in $cases) {
        $cleanMarker = switch ($case.fixture) {
            'drive' { 'DRIVE PASS' }
            'baseline' { 'BASELINE PASS' }
            'views' { 'SHUTDOWN VIEW DONE' }
        }
        @{
            fixture = $case.fixture
            outcomes = @(
                @{ exitCode = $case.exitCode; lines = $case.lines },
                @{ exitCode = 0; lines = @($cleanMarker) }
            )
        } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $scenarioPath -Encoding UTF8
        Set-Content -LiteralPath $counterPath -Value 0
        $output = [Collections.Generic.List[string]]::new()
        $failureMessage = $null
        try {
            & $runnerPath -GodotPath $fakeEnginePath -Fixture $case.fixture -Trials 2 *>&1 |
                ForEach-Object { $output.Add([string]$_) }
        } catch {
            $failureMessage = $_.Exception.Message
        }
        $directoryLine = @($output | Where-Object { $_ -match '^Shutdown diagnosis: .* Logs: (.+)$' })
        Assert-Condition ($directoryLine.Count -eq 1) "Case '$($case.name)' did not expose its report directory: $failureMessage"
        $null = $directoryLine[0] -match ' Logs: (.+)$'
        $runDirectory = $Matches[1]
        $cleanupPaths.Add($runDirectory)
        $report = Get-Content -LiteralPath (Join-Path $runDirectory 'report.json') -Raw | ConvertFrom-Json
        Assert-Condition ($report.requested_trials -eq 2 -and $report.results.Count -eq 2) "Case '$($case.name)' did not retain both outcomes"
        Assert-Condition ([int](Get-Content -LiteralPath $counterPath) -eq 2) "Case '$($case.name)' did not execute exactly two trials"
        $first = $report.results[0]
        $second = $report.results[1]
        Assert-Condition ($first.trial -eq 1 -and $second.trial -eq 2) "Case '$($case.name)' reordered trial evidence"
        Assert-Condition ($first.exit_code -eq $case.exitCode -and $first.native_crash -eq $case.native -and
            $first.script_error -eq $case.scriptError -and $first.completion_marker -eq $case.marker -and
            $first.passed -eq (-not $case.failed)) "Case '$($case.name)' misclassified the first outcome"
        Assert-Condition ($second.passed -and $second.exit_code -eq 0 -and $second.completion_marker -and
            -not $second.native_crash -and -not $second.script_error) "Case '$($case.name)' misclassified the clean second outcome"
        $firstLog = @(Get-Content -LiteralPath (Join-Path $runDirectory $first.log))
        $secondLog = @(Get-Content -LiteralPath (Join-Path $runDirectory $second.log))
        Assert-Condition (($firstLog -join "`n") -eq ($case.lines -join "`n") -and
            ($secondLog -join "`n") -eq $cleanMarker) "Case '$($case.name)' lost or replaced raw logs"
        if ($case.failed) {
            Assert-Condition ($failureMessage -match '^1/2 shutdown trials failed\. All outcomes retained: ') "Case '$($case.name)' masked the failure: $failureMessage"
        } else {
            Assert-Condition (-not $failureMessage) "Clean case unexpectedly failed: $failureMessage"
            Assert-Condition (@($output | Where-Object { $_ -match '^All 2 diagnostic exits were clean; this does not establish a crash fix\.' }).Count -eq 1) 'Clean case omitted the limitation on its result'
        }
        $casesPassed++
    }
    Write-Host "SHUTDOWN DIAGNOSTIC TEST PASS ($casesPassed cases)"
} finally {
    foreach ($cleanupPath in $cleanupPaths) {
        $resolvedPath = [IO.Path]::GetFullPath($cleanupPath)
        if ([IO.Path]::GetDirectoryName($resolvedPath).TrimEnd('\', '/') -ne $tempParent.TrimEnd('\', '/') -or
            [IO.Path]::GetFileName($resolvedPath) -notmatch '^battlebots-shutdown-(test-)?[0-9a-f]{32}$') {
            throw "Refusing to remove unexpected diagnostic directory: $resolvedPath"
        }
        Remove-Item -LiteralPath $resolvedPath -Recurse -Force
    }
}
