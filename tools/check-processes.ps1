param([Parameter(Mandatory = $true)][string]$GodotPath)
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '../battlebots')).Path
$runDirectory = Join-Path ([IO.Path]::GetTempPath()) ('battlebots-process-check-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $runDirectory | Out-Null
$port = Get-Random -Minimum 30000 -Maximum 45000
$processes = @()
try {
    foreach ($index in 0..4) {
        $mode = if ($index -eq 0) { "--server --players=4 --port=$port" } else { "--join=127.0.0.1 --port=$port --ready" }
        $arguments = "--headless --path `"$projectRoot`" --max-fps 60 --quit-after 1200 -- $mode"
        $processes += Start-Process -FilePath $GodotPath -ArgumentList $arguments -WindowStyle Hidden -PassThru `
            -RedirectStandardOutput (Join-Path $runDirectory "$index.out.log") `
            -RedirectStandardError (Join-Path $runDirectory "$index.err.log")
        if ($index -eq 0) { Start-Sleep -Milliseconds 750 }
    }
    $deadline = [DateTime]::UtcNow.AddSeconds(18)
    $passed = $false
    while ([DateTime]::UtcNow -lt $deadline) {
        $ready = 0
        foreach ($index in 0..4) {
            if ((Get-Content (Join-Path $runDirectory "$index.out.log") -Raw) -match 'SESSION PHASE: active') { $ready++ }
        }
        if ($ready -eq 5) { $passed = $true; break }
        Start-Sleep -Milliseconds 200
    }
    foreach ($index in 0..4) {
        $errors = Get-Content (Join-Path $runDirectory "$index.err.log") -Raw
        if ($errors -match 'SCRIPT ERROR:|Parse Error:|ERROR:') { throw "Process $index failed: $errors" }
    }
    if (-not $passed) { throw "Five-process readiness/active check timed out. Logs: $runDirectory" }
    Write-Host "PROCESS PASS: dedicated server and four independent clients reached active. Logs: $runDirectory"
} finally {
    foreach ($process in $processes) {
        if (-not $process.HasExited) { Stop-Process -Id $process.Id }
    }
}
