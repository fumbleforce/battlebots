# Exercise the production gate and its nested baseline checks without Godot.
$ErrorActionPreference = 'Stop'
$gatePath = Join-Path $PSScriptRoot '../check-drive.ps1'
$tempParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$fixtureRoot = Join-Path $tempParent ('battlebots-drive-gate-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $fixtureRoot
$fakeEnginePath = Join-Path $fixtureRoot 'fake-engine.ps1'
$scenarioPath = Join-Path $fixtureRoot 'scenario.json'
$callsPath = Join-Path $fixtureRoot 'calls.txt'
$casesPassed = 0

try {
    # A script shim explicitly sets LASTEXITCODE, matching the engine interface
    # used by both gates, while keeping this test independent of installed tools.
    @'
$scenario = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'scenario.json') -Raw | ConvertFrom-Json
$phase = if ($args -contains '--version') { 'version' }
    elseif ($args -contains '--editor') { 'import' }
    elseif ($args -contains 'res://tests/baseline_smoke.gd') { 'baseline' }
    elseif ($args -contains 'res://tests/simulation/drive_smoke.gd') { 'drive' }
    else { throw "Unexpected fake engine arguments: $args" }
Add-Content -LiteralPath (Join-Path $PSScriptRoot 'calls.txt') -Value $phase
$global:LASTEXITCODE = 0
if ($phase -eq $scenario.phase) {
    $global:LASTEXITCODE = [int]$scenario.exitCode
    $scenario.lines | ForEach-Object { Write-Output $_ }
} elseif ($phase -eq 'version') { '4.7.2.stable.official.test' }
elseif ($phase -eq 'baseline') { 'BASELINE PASS' }
elseif ($phase -eq 'drive') { 'DRIVE PASS' }
'@ | Set-Content -LiteralPath $fakeEnginePath -Encoding UTF8

    $cases = @(
        @{ name = 'clean run'; phase = 'none'; lines = @(); exitCode = 0; failure = $false },
        @{ name = 'missing drive marker'; phase = 'drive'; lines = @('Drive finished'); exitCode = 0; failure = $true }
    )
    $failureOutputs = @(
        @{ name = 'nonzero exit despite PASS'; lines = @(); exitCode = 17 },
        @{ name = 'native exception despite PASS'; lines = @('CrashHandlerException: signal 11'); exitCode = 0 },
        @{ name = 'native crash despite PASS'; lines = @('Program crashed with signal 11'); exitCode = 0 },
        @{ name = 'native backtrace despite PASS'; lines = @('END OF C++ BACKTRACE'); exitCode = 0 },
        @{ name = 'script error despite PASS'; lines = @('SCRIPT ERROR: Invalid call'); exitCode = 0 },
        @{ name = 'parse error despite PASS'; lines = @('Parse Error: Invalid declaration'); exitCode = 0 },
        @{ name = 'engine error despite PASS'; lines = @('ERROR: Invalid resource'); exitCode = 0 }
    )
    foreach ($phase in @('drive', 'baseline', 'import')) {
        foreach ($failureOutput in $failureOutputs) {
            $cases += @{
                name = "$phase $($failureOutput.name)"
                phase = $phase
                lines = @('BASELINE PASS', 'DRIVE PASS') + $failureOutput.lines
                exitCode = $failureOutput.exitCode
                failure = $true
            }
        }
    }
    foreach ($case in $cases) {
        $case | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $scenarioPath -Encoding UTF8
        Set-Content -LiteralPath $callsPath -Value ''
        $failureMessage = $null
        try {
            & $gatePath -GodotPath $fakeEnginePath *> $null
        } catch {
            $failureMessage = $_.Exception.Message
        }
        if ($case.failure) {
            $expected = if ($case.phase -eq 'drive') { '^Drive validation failed \(exit ' } else { '^Godot validation failed \(exit ' }
            if (-not $failureMessage -or $failureMessage -notmatch $expected) {
                throw "Case '$($case.name)' did not fail through the intended gate: $failureMessage"
            }
        } elseif ($failureMessage) {
            throw "Case '$($case.name)' unexpectedly failed: $failureMessage"
        }
        $expectedCalls = switch ($case.phase) {
            'import' { 'version,import' }
            'baseline' { 'version,import,baseline' }
            default { 'version,import,baseline,drive' }
        }
        $actualCalls = ((Get-Content -LiteralPath $callsPath) | Where-Object { $_ }) -join ','
        if ($actualCalls -ne $expectedCalls) {
            throw "Case '$($case.name)' called '$actualCalls'; expected '$expectedCalls'"
        }
        $casesPassed++
    }
    Write-Host "DRIVE GATE PASS ($casesPassed cases)"
} finally {
    $resolvedFixture = [IO.Path]::GetFullPath($fixtureRoot)
    if ([IO.Path]::GetDirectoryName($resolvedFixture).TrimEnd('\', '/') -ne $tempParent.TrimEnd('\', '/') -or
        [IO.Path]::GetFileName($resolvedFixture) -notmatch '^battlebots-drive-gate-[0-9a-f]{32}$') {
        throw "Refusing to remove unexpected fixture directory: $resolvedFixture"
    }
    Remove-Item -LiteralPath $resolvedFixture -Recurse -Force
}
