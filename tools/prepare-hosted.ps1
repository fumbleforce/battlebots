param([Parameter(Mandatory = $true)][string]$GodotPath, [switch]$WindowsSmokeServer)
$ErrorActionPreference = 'Stop'
$engineVersion = & $GodotPath --version
if ($LASTEXITCODE -ne 0 -or $engineVersion -notmatch '^4\.7\.2\.stable') {
    throw "Expected Godot 4.7.2 stable; got $engineVersion"
}
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '../battlebots')).Path
$outputDirectory = Join-Path $projectRoot 'exports/hosted-server'
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
function Invoke-PreparedCheck([string[]]$EngineArguments) {
    $outputLines = & $GodotPath @EngineArguments 2>&1
    $code = $LASTEXITCODE
    $outputLines | ForEach-Object { Write-Host $_ }
    if ($code -ne 0 -or ($outputLines -match 'SCRIPT ERROR:|Parse Error:|^ERROR:|CrashHandlerException:|Program crashed|END OF C\+\+ BACKTRACE')) {
        throw "Hosted preparation failed (exit $code)"
    }
}
Invoke-PreparedCheck @('--headless', '--path', $projectRoot, '--editor', '--import', '--quit')
Invoke-PreparedCheck @('--headless', '--path', $projectRoot, '--script', 'res://tools/write_service_manifest.gd',
    '--', "--output=$(Join-Path $outputDirectory 'manifest.json')")
Invoke-PreparedCheck @('--headless', '--path', $projectRoot, '--export-release', 'Linux Server',
    (Join-Path $outputDirectory 'battlebots-server.x86_64'))
$required = @('battlebots-server.x86_64', 'battlebots-server.pck', 'manifest.json')
foreach ($file in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $outputDirectory $file))) {
        throw "Required deployment artifact missing: $file"
    }
}
$record = [ordered]@{
    commit = (git -C $projectRoot rev-parse HEAD)
    dirty = [bool](git -C $projectRoot status --porcelain)
    prepared_utc = [DateTime]::UtcNow.ToString('o')
    files = @($required | ForEach-Object {
        [pscustomobject]@{ name = $_; sha256 = (Get-FileHash -LiteralPath (Join-Path $outputDirectory $_) -Algorithm SHA256).Hash }
    })
}
$record | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $outputDirectory 'build-record.json') -Encoding utf8
if ($WindowsSmokeServer) {
    $windowsDirectory = Join-Path $projectRoot 'exports/hosted-windows'
    New-Item -ItemType Directory -Force -Path $windowsDirectory | Out-Null
    Invoke-PreparedCheck @('--headless', '--path', $projectRoot, '--export-release', 'Windows Client',
        (Join-Path $windowsDirectory 'battlebots.exe'))
}
Write-Host "HOSTED DEPLOYMENT PREPARED: $outputDirectory"
