param(
    [Parameter(Mandatory = $true)][string]$GodotPath,
    [ValidateSet(2, 4, 10)][int]$PlayerCount = 4,
    [ValidateSet('teams', 'ffa')][string]$Mode = 'teams'
)
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '../battlebots')).Path
$runDirectory = Join-Path ([IO.Path]::GetTempPath()) ('battlebots-process-check-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $runDirectory | Out-Null
$port = Get-Random -Minimum 30000 -Maximum 45000
$processes = @()
try {
    foreach ($index in 0..$PlayerCount) {
        $launchArgs = if ($index -eq 0) { "--server --players=$PlayerCount --mode=$Mode --port=$port" } else { "--join=127.0.0.1 --port=$port --ready" }
        $arguments = "--headless --path `"$projectRoot`" --max-fps 60 --quit-after 2400 -- $launchArgs"
        $processes += Start-Process -FilePath $GodotPath -ArgumentList $arguments -WindowStyle Hidden -PassThru `
            -RedirectStandardOutput (Join-Path $runDirectory "$index.out.log") `
            -RedirectStandardError (Join-Path $runDirectory "$index.err.log")
        if ($index -eq 0) { Start-Sleep -Milliseconds 750 }
    }
    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    $passed = $false
    while ([DateTime]::UtcNow -lt $deadline) {
        $ready = 0
        foreach ($index in 0..$PlayerCount) {
            if ((Get-Content (Join-Path $runDirectory "$index.out.log") -Raw) -match 'SESSION PHASE: active') { $ready++ }
        }
        if ($ready -eq $PlayerCount + 1) { $passed = $true; break }
        Start-Sleep -Milliseconds 200
    }
    foreach ($index in 0..$PlayerCount) {
        $errors = Get-Content (Join-Path $runDirectory "$index.err.log") -Raw
        if ($errors -match 'SCRIPT ERROR:|Parse Error:|ERROR:') { throw "Process $index failed: $errors" }
    }
    if (-not $passed) { throw "Server/$PlayerCount-client readiness/active check timed out. Logs: $runDirectory" }
    Write-Host "PROCESS PASS: dedicated server and $PlayerCount independent clients reached active. Logs: $runDirectory"
} finally {
    foreach ($process in $processes) {
        if (-not $process.HasExited) { Stop-Process -Id $process.Id }
    }
}
