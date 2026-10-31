param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$AcdcRoot = 'C:\amk-tools\Universal-ACDC',
    [string]$PerlExe = 'C:\Program Files\Git\usr\bin\perl.exe',
    [switch]$NoDeploy
)

$ErrorActionPreference = 'Stop'

& (Join-Path $PSScriptRoot 'build_scripts.ps1') -ProjectRoot $ProjectRoot
& (Join-Path $PSScriptRoot 'build_overlay.ps1') -ProjectRoot $ProjectRoot
& (Join-Path $PSScriptRoot 'build_spawn.ps1') -ProjectRoot $ProjectRoot

$spawnSource = Join-Path $ProjectRoot 'spawn-clean'
$spawnOutput = Join-Path $spawnSource 'all.spawn'
Push-Location $AcdcRoot
try {
    & $PerlExe -I $AcdcRoot (Join-Path $AcdcRoot 'universal_acdc.pl') -compile $spawnSource -out $spawnOutput
    if ($LASTEXITCODE -ne 0) {
        throw "Universal ACDC exited with code $LASTEXITCODE"
    }
} finally {
    Pop-Location
}

if (-not $NoDeploy) {
    $runtimeData = Join-Path $ProjectRoot 'game\gamedata'
    Copy-Item -Path (Join-Path $ProjectRoot 'story\gamedata\*') -Destination $runtimeData -Recurse -Force
    $runtimeSpawns = Join-Path $runtimeData 'spawns'
    New-Item -ItemType Directory -Path $runtimeSpawns -Force | Out-Null
    Copy-Item -LiteralPath $spawnOutput -Destination (Join-Path $runtimeSpawns 'all.spawn') -Force
    Write-Host "Deployed clean story build to $runtimeData"
}

Write-Host "Build complete: $spawnOutput"
