param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$AcdcRoot = (Join-Path (Split-Path -Parent $ProjectRoot) 'mod-tools\Universal-ACDC'),
    [string]$PerlExe = 'C:\Program Files\Git\usr\bin\perl.exe',
    [string]$PythonExe = (Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'),
    [switch]$NoDeploy
)

$ErrorActionPreference = 'Stop'

& (Join-Path $PSScriptRoot 'build_scripts.ps1') -ProjectRoot $ProjectRoot
& (Join-Path $PSScriptRoot 'build_overlay.ps1') -ProjectRoot $ProjectRoot
& (Join-Path $PSScriptRoot 'disable_vanilla_story.ps1') -ProjectRoot $ProjectRoot
& (Join-Path $PSScriptRoot 'build_spawn.ps1') -ProjectRoot $ProjectRoot
& (Join-Path $PSScriptRoot 'build_military.ps1') -ProjectRoot $ProjectRoot
& $PythonExe -B (Join-Path $PSScriptRoot 'build_newgame_spawn.py') --project $ProjectRoot
if ($LASTEXITCODE -ne 0) { throw 'New-game story spawn preparation failed' }
& $PythonExe -B (Join-Path $PSScriptRoot 'build_mil_gift.py') --project $ProjectRoot
if ($LASTEXITCODE -ne 0) { throw 'Military gift preparation failed' }
& (Join-Path $PSScriptRoot 'build_deadcity.ps1') -ProjectRoot $ProjectRoot -AcdcRoot $AcdcRoot -PerlExe $PerlExe -PythonExe $PythonExe
& $PythonExe -B (Join-Path $PSScriptRoot 'build_deadcity_population.py') --project $ProjectRoot
if ($LASTEXITCODE -ne 0) { throw 'Dead City population preparation failed' }
& $PythonExe -B (Join-Path $PSScriptRoot 'build_atmospherics.py') --project $ProjectRoot
if ($LASTEXITCODE -ne 0) { throw 'Atmospherics configuration failed' }
& (Join-Path $PSScriptRoot 'remove_retired_files.ps1') -ProjectRoot $ProjectRoot -SourceOnly:$NoDeploy

$spawnSource = Join-Path $ProjectRoot 'spawn-clean'
$spawnOutput = Join-Path $spawnSource 'all.spawn'
$acdcWorkspace = Join-Path $ProjectRoot 'build-deadcity\acdc'
New-Item -ItemType Directory -Path $acdcWorkspace -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $AcdcRoot 'sections.ini') -Destination (Join-Path $acdcWorkspace 'sections.ini') -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'acdc_sections.ini') -Destination (Join-Path $acdcWorkspace 'user_sections.ini') -Force
# ACDC's Perl parser retains CR in class names. Git on Windows can check out
# user_sections.ini with CRLF, so normalize both temporary tables before use.
$acdcEncoding = [Text.Encoding]::GetEncoding(1251)
foreach ($table in @('sections.ini', 'user_sections.ini')) {
    $tablePath = Join-Path $acdcWorkspace $table
    $tableText = [IO.File]::ReadAllText($tablePath, $acdcEncoding).Replace("`r`n", "`n")
    [IO.File]::WriteAllText($tablePath, $tableText, $acdcEncoding)
}
Push-Location $acdcWorkspace
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
    Copy-Item -Path (Join-Path $ProjectRoot 'build-deadcity\assets\gamedata\*') -Destination $runtimeData -Recurse -Force
    Write-Host "Deployed clean story build to $runtimeData"
}

Write-Host "Build complete: $spawnOutput"
