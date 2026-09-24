param(
    [Parameter(Mandatory = $true)][string]$GodotPath,
    [ValidateRange(10, 86400)][int]$DurationSeconds = 60,
    [ValidateRange(0, 3600)][int]$WarmupSeconds = 30,
    [switch]$RequireSoak
)
$ErrorActionPreference = 'Stop'
if ($RequireSoak -and ($DurationSeconds -lt 3600 -or $WarmupSeconds -lt 60)) {
    throw 'Soak acceptance requires at least 3600 measured seconds after at least 60 seconds of warm-up.'
}
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '../battlebots')).Path
$enginePath = (Resolve-Path -LiteralPath $GodotPath).Path
$runDirectory = Join-Path ([IO.Path]::GetTempPath()) ('battlebots-performance-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $runDirectory | Out-Null
# Let the OS choose a free UDP port: a random pick can land on a busy or
# Windows-reserved port (#13).
$probe = [System.Net.Sockets.UdpClient]::new(0)
$port = ([System.Net.IPEndPoint]$probe.Client.LocalEndPoint).Port
$probe.Close()
$processes = [Collections.Generic.List[object]]::new()
$memorySamples = [Collections.Generic.List[object]]::new()
$startedAt = [DateTime]::UtcNow
$measurementStart = $null
$lastMemory = [DateTime]::MinValue
$lastProgress = [DateTime]::MinValue
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$sourceFiles = @(git -C $repositoryRoot ls-files --cached --others --exclude-standard | Sort-Object -Unique | Where-Object {
    $_ -match '\.(gd|tscn|tres|godot|json|ps1)$'
})
$sourceManifest = @($sourceFiles | ForEach-Object {
    $sourcePath = Join-Path $repositoryRoot $_
    if (Test-Path -LiteralPath $sourcePath -PathType Leaf) {
        [pscustomobject]@{ path = $_; sha256 = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash }
    }
})
$sourceManifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $runDirectory 'source-manifest.json') -Encoding utf8
$metadata = [ordered]@{
    schema = 1
    started_utc = $startedAt.ToString('o')
    duration_seconds = $DurationSeconds
    warmup_seconds = $WarmupSeconds
    cpu = @(Get-CimInstance Win32_Processor | Select-Object Name, NumberOfCores, NumberOfLogicalProcessors)
    os = [Environment]::OSVersion.VersionString
    engine = $enginePath
    commit = (git -C $projectRoot rev-parse HEAD)
    working_tree_dirty = [bool](git -C $projectRoot status --porcelain)
    source_manifest = 'source-manifest.json; SHA256 of tracked/unignored source, scenes, resources, JSON and check scripts at launch'
    processes = 11
    rendering = 'headless; no rendered frame-time or GPU acceptance'
    traffic_units = 'decimal KB/s (1000 bytes); includes ENet payload plus 28 IPv4/UDP bytes per datagram, excludes Ethernet framing'
    memory_definition = 'Per-process private bytes and working set, sampled every 5 wall seconds; compare first and final 60-second medians after warm-up'
}
$metadata | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $runDirectory 'machine.json') -Encoding utf8

function Read-RunJson([string]$Name) {
    $path = Join-Path $runDirectory $Name
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try { return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json } catch { return $null }
}

function Median($Values) {
    $ordered = @($Values | Sort-Object)
    if ($ordered.Count -eq 0) { return $null }
    $middle = [int][Math]::Floor($ordered.Count / 2)
    if ($ordered.Count % 2 -eq 0) {
        return ([double]$ordered[$middle - 1] + [double]$ordered[$middle]) / 2.0
    }
    return [double]$ordered[$middle]
}

try {
    foreach ($index in -1..9) {
        $label = if ($index -lt 0) { 'server' } else { "client-$index" }
        $script = if ($index -lt 0) { 'server_peer.gd' } else { 'client_peer.gd' }
        $arguments = "--headless --path `"$projectRoot`" --max-fps 60 --script res://tests/performance/$script -- --port=$port `"--output=$runDirectory`" --index=$index --seconds=$DurationSeconds --warmup=$WarmupSeconds"
        $process = Start-Process -FilePath $enginePath -ArgumentList $arguments -WindowStyle Hidden -PassThru `
            -RedirectStandardOutput (Join-Path $runDirectory "$label.out.log") `
            -RedirectStandardError (Join-Path $runDirectory "$label.err.log")
        $processes.Add([pscustomobject]@{ label = $label; process = $process })
        if ($index -lt 0) {
            $readyDeadline = [DateTime]::UtcNow.AddSeconds(20)
            do {
                $status = Read-RunJson 'server-status.json'
                if ($process.HasExited) { throw "Server exited during startup. Logs: $runDirectory" }
                if ($null -ne $status) { break }
                Start-Sleep -Milliseconds 100
            } while ([DateTime]::UtcNow -lt $readyDeadline)
            if ($null -eq $status) { throw "Server did not publish readiness. Logs: $runDirectory" }
        }
    }
    Write-Host "PERFORMANCE RUN: 11 independent headless processes. Reports: $runDirectory"
    $deadline = $startedAt.AddSeconds($DurationSeconds + $WarmupSeconds + 150)
    while ([DateTime]::UtcNow -lt $deadline) {
        $now = [DateTime]::UtcNow
        $stopping = Test-Path -LiteralPath (Join-Path $runDirectory 'stop')
        if ($null -eq $measurementStart -and (Test-Path -LiteralPath (Join-Path $runDirectory 'measure'))) {
            $measurementStart = $now
        }
        foreach ($entry in $processes) {
            $entry.process.Refresh()
            if ($entry.process.HasExited) { $entry.process.WaitForExit() }
            if ($entry.process.HasExited -and ($entry.process.ExitCode -ne 0 -or -not $stopping)) {
                throw "$($entry.label) exited unexpectedly ($($entry.process.ExitCode)). Logs: $runDirectory"
            }
        }
        if ($null -ne $measurementStart -and ($now - $lastMemory).TotalSeconds -ge 5) {
            foreach ($entry in $processes) {
                if (-not $entry.process.HasExited) {
                    $memorySamples.Add([pscustomobject]@{
                        peer = $entry.label
                        seconds = ($now - $measurementStart).TotalSeconds
                        private_bytes = $entry.process.PrivateMemorySize64
                        working_set_bytes = $entry.process.WorkingSet64
                    })
                }
            }
            $memorySamples | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $runDirectory 'memory.json') -Encoding utf8
            $lastMemory = $now
        }
        if (($now - $lastProgress).TotalSeconds -ge 30) {
            $status = Read-RunJson 'server-status.json'
            Write-Host ("PERFORMANCE PROGRESS: wall={0:F0}s phase={1} round={2} weapon_events={3}" -f ($now - $startedAt).TotalSeconds, $status.phase, $status.round, ($status.measured_authored_weapon_events | ConvertTo-Json -Compress))
            $lastProgress = $now
        }
        if ($stopping -and @($processes | Where-Object { -not $_.process.HasExited }).Count -eq 0) { break }
        Start-Sleep -Milliseconds 500
    }
    if (@($processes | Where-Object { -not $_.process.HasExited }).Count -gt 0) { throw "Performance run exceeded its bounded deadline. Logs: $runDirectory" }
    $server = Read-RunJson 'server.json'
    $clients = @(0..9 | ForEach-Object { Read-RunJson "client-$_.json" })
    if ($null -eq $server -or $clients.Count -ne 10) { throw "Missing peer reports. Logs: $runDirectory" }
    foreach ($entry in $processes) {
        $errors = Get-Content -LiteralPath (Join-Path $runDirectory "$($entry.label).err.log") -Raw
        if ($errors -match 'SCRIPT ERROR:|Parse Error:|(?m)^ERROR:') { throw "$($entry.label) reported runtime errors. Logs: $runDirectory" }
    }
    $memory = @()
    foreach ($entry in $processes) {
        $peerSamples = @($memorySamples | Where-Object peer -eq $entry.label)
        $first = @($peerSamples | Where-Object seconds -lt 60)
        $last = @($peerSamples | Where-Object seconds -ge ($DurationSeconds - 60))
        $basePrivate = Median ($first.private_bytes)
        $finalPrivate = Median ($last.private_bytes)
        $memory += [pscustomobject]@{
            peer = $entry.label
            samples = $peerSamples.Count
            baseline_private_bytes = $basePrivate
            final_private_bytes = $finalPrivate
            private_growth_percent = if ($basePrivate -gt 0) { 100 * ($finalPrivate / $basePrivate - 1) } else { $null }
            baseline_working_set_bytes = Median ($first.working_set_bytes)
            final_working_set_bytes = Median ($last.working_set_bytes)
            soak_eligible = $DurationSeconds -ge 3600 -and $WarmupSeconds -ge 60 -and $first.Count -ge 10 -and $last.Count -ge 10
        }
    }
    $traffic = @($clients | ForEach-Object {
        [pscustomobject]@{
            client = $_.index
            upstream_KB_s = $_.traffic_measured.uplink_wire_bytes_per_s / 1000.0
            downstream_KB_s = $_.traffic_measured.downlink_wire_bytes_per_s / 1000.0
            peak_10s_upstream_KB_s = $_.traffic_window_10s.peak_uplink_wire_bytes_per_s / 1000.0
            peak_10s_downstream_KB_s = $_.traffic_window_10s.peak_downlink_wire_bytes_per_s / 1000.0
            completed_10s_windows = $_.traffic_window_10s.completed_windows
            within_budget = $_.traffic_measured.uplink_wire_bytes_per_s -lt 30000 -and $_.traffic_measured.downlink_wire_bytes_per_s -lt 100000
        }
    })
    $report = [ordered]@{ machine = $metadata; server = $server; clients = $clients; memory = $memory; traffic = $traffic; soak_required = [bool]$RequireSoak }
    $report | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $runDirectory 'report.json') -Encoding utf8
    # Headless success never certifies rendered client performance or exact
    # full-engine per-tick timing; these limitations remain explicit in reports.
    if ($server.valid -ne $true -or @($clients | Where-Object { $_.valid -ne $true }).Count -gt 0) {
        throw "A peer report failed its activity/lifecycle checks. Report: $runDirectory/report.json"
    }
    if ($RequireSoak) {
        if (@($memory | Where-Object { -not $_.soak_eligible -or $_.private_growth_percent -gt 5 }).Count -gt 0) {
            throw "Memory soak gate failed or lacked sufficient samples. Report: $runDirectory/report.json"
        }
        if ($server.measured_results -lt 2 -or $server.measured_rematches -lt 1) {
            throw "Soak did not complete repeated normal matches and a rematch. Report: $runDirectory/report.json"
        }
        if (@($traffic | Where-Object { -not $_.within_budget }).Count -gt 0) {
            throw "Measured per-player bandwidth exceeds the budget. Report: $runDirectory/report.json"
        }
        foreach ($weapon in @('vertical_spinner', 'horizontal_spinner', 'lifter', 'hammer', 'saw')) {
            if ($server.measured_authored_weapon_events.$weapon -lt 1) { throw "No authored $weapon contact during measured soak. Report: $runDirectory/report.json" }
        }
        Write-Host "SOAK PASS: repeated-match memory, weapon coverage and average bandwidth gates. Full timing/rendering acceptance remains separate. Report: $runDirectory/report.json"
    } else {
        Write-Host "PERFORMANCE HARNESS PASS (smoke evidence only): $runDirectory/report.json"
    }
} finally {
    Set-Content -LiteralPath (Join-Path $runDirectory 'stop') -Value 'runner cleanup' -Encoding utf8
    foreach ($entry in $processes) {
        $entry.process.Refresh()
        if (-not $entry.process.HasExited) { Stop-Process -Id $entry.process.Id }
    }
}
