param(
    [Parameter(Mandatory)][ValidatePattern('^[a-zA-Z0-9_]+$')][string]$Level,
    [string]$ProjectRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'ogsr-project'),
    [switch]$Apply,
    [switch]$AllowUnlit,
    [switch]$Package
)
$ErrorActionPreference = 'Stop'
$sdk = $PSScriptRoot
$source = Join-Path $sdk ('gamedata\levels\' + $Level)
$game = Join-Path $ProjectRoot 'game\gamedata'
$target = Join-Path $game ('levels\' + $Level)
$manifestFile = Join-Path $source 'sdk-build.json'
if (-not (Test-Path $manifestFile)) { throw 'Compile with Compile-Level.ps1 first; sdk-build.json is missing.' }
$build = Get-Content $manifestFile -Raw | ConvertFrom-Json
if ($build.Level -ne $Level -or $build.Stage -ne 'Geometry' -or -not (Test-Path $build.Log) -or -not (Select-String -LiteralPath $build.Log -SimpleMatch 'Build succesful!' -Quiet)) { throw 'Successful geometry build not confirmed.' }
if ($build.Draft -and -not $AllowUnlit) { throw 'This is an unlit draft. Compile without -Draft for normal gameplay, or use -AllowUnlit for an intentional preview.' }
foreach ($file in @('level','level.geom','level.cform')) {
    if ($build.Hashes -and (Get-FileHash (Join-Path $source $file)).Hash -ne $build.Hashes.$file) { throw "Build output changed after compilation: $file. Compile again." }
}
if (-not $Package -and -not (Test-Path $target)) { throw 'For a NEW location use -Package first, then register its map and integrate its graph/spawn into the story. Geometry replacement expects an existing game level.' }
if (Get-Process xrCompiler -ErrorAction SilentlyContinue) { throw 'Wait for the compiler to finish.' }
if ($Apply -and -not $Package -and (Get-Process xrEngine -ErrorAction SilentlyContinue)) { throw 'Close the game before deployment.' }
$python = Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
$helper = Join-Path $ProjectRoot 'tools\deploy_sdk_textures.py'
$dependencyArgs = @('-B',$helper,'--project',$ProjectRoot,'--sdk',$sdk,'--level',$Level)
if ($Package) { $dependencyArgs += @('--output-root',(Join-Path $ProjectRoot ('level-builds\' + $Level + '\gamedata'))) }
# Resolve texture dependencies before changing any game files.
& $python @dependencyArgs
if ($LASTEXITCODE -ne 0) { throw 'Missing texture dependencies; deployment cancelled.' }
$files = @('level','level.geom','level.cform')
foreach ($name in @('level.geomx','level_lods.dds','level_lods_nm.dds','level.details','level.hom')) {
    if (Test-Path (Join-Path $source $name)) { $files += $name }
}
$files += @(Get-ChildItem $source -Filter 'lmap#*.dds' -File | ForEach-Object Name)
if (Test-Path (Join-Path $source 'terrain')) { $files += @(Get-ChildItem (Join-Path $source 'terrain') -Filter '*.dds' -File | ForEach-Object { 'terrain\' + $_.Name }) }
if ($Package) {
    foreach ($name in @('level.ai','level.gct','level.graph','level.game','level.spawn','level.ltx','level.snd_env','level.snd_static','level.wallmarks','level.env_mod','level.fog_vol')) { if (Test-Path (Join-Path $source $name)) { $files += $name } }
    $target = Join-Path $ProjectRoot ('level-builds\' + $Level + '\gamedata\levels\' + $Level)
}
if (-not $Apply) { Write-Host "Preview: $($files.Count) files -> $target"; $files; Write-Host 'Add -Apply to install these files.'; return }
$backup = Join-Path $sdk ('backup\deploy-' + $Level + '-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Path $backup -Force | Out-Null
$manifest = foreach ($name in $files) {
    $destination = Join-Path $target $name
    $exists = Test-Path $destination
    if ($exists) {
        $saved = Join-Path $backup $name
        New-Item -ItemType Directory -Path (Split-Path -Parent $saved) -Force | Out-Null
        Copy-Item -LiteralPath $destination -Destination $saved
    }
    [pscustomobject]@{ Name=$name; PreviouslyExisted=$exists; SHA256=(Get-FileHash (Join-Path $source $name)).Hash }
}
$manifest | ConvertTo-Json | Set-Content (Join-Path $backup 'manifest.json') -Encoding UTF8
foreach ($entry in $manifest) {
    $destination = Join-Path $target $entry.Name
    New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $source $entry.Name) -Destination $destination -Force
    if ((Get-FileHash $destination).Hash -ne $entry.SHA256) { throw "Copy verification failed: $($entry.Name)" }
}
& $python @dependencyArgs --apply
if ($LASTEXITCODE -ne 0) { throw 'Texture deployment failed.' }
Write-Host "Installed $($files.Count) files: $target"
Write-Host "Backup: $backup"
if ($Package) { Write-Host 'Package is staged. A new story location still needs map registration, graph/spawn integration and transitions.' }
