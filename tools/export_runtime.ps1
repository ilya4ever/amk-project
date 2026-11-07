param([string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot))

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath $ProjectRoot).Path
$compiled = Join-Path $root 'spawn-clean\all.spawn'
$assets = Join-Path $root 'build-deadcity\assets\gamedata'
$payload = Join-Path $root 'deploy\gamedata'
if (!(Test-Path -LiteralPath $compiled -PathType Leaf) -or !(Test-Path -LiteralPath (Join-Path $assets 'levels\dead_city\level.gct') -PathType Leaf)) {
    throw 'Run tools/build_all.ps1 -NoDeploy before exporting the runtime.'
}

New-Item -ItemType Directory -Path (Join-Path $payload 'spawns') -Force | Out-Null
Copy-Item -LiteralPath $compiled -Destination (Join-Path $payload 'spawns\all.spawn') -Force
$entries = foreach ($file in (Get-ChildItem -LiteralPath $assets -Recurse -File | Sort-Object FullName)) {
    $relative = $file.FullName.Substring($assets.Length + 1).Replace('\', '/')
    $legacy = Join-Path $root $relative
    $hash = (Get-FileHash -LiteralPath $file.FullName).Hash
    $source = $relative
    if ($file.Extension -eq '.ltx' -or !(Test-Path -LiteralPath $legacy -PathType Leaf) -or (Get-FileHash -LiteralPath $legacy).Hash -ne $hash) {
        $source = 'deploy/gamedata/' + $relative
        $target = Join-Path $root $source
        New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
        Copy-Item -LiteralPath $file.FullName -Destination $target -Force
    }
    [ordered]@{ path = $relative; source = $source; sha256 = $hash }
}
$entries += [ordered]@{
    path = 'spawns/all.spawn'; source = 'deploy/gamedata/spawns/all.spawn'; sha256 = (Get-FileHash -LiteralPath $compiled).Hash
}
$manifest = [ordered]@{
    base_dbb_sha256 = (Get-FileHash -LiteralPath (Join-Path $root 'game\gamedata.dbb')).Hash
    game_graph_sha256 = (Get-FileHash -LiteralPath (Join-Path $root 'story\gamedata\game.graph')).Hash
    files = @($entries)
}
$json = $manifest | ConvertTo-Json -Depth 4
[IO.File]::WriteAllText((Join-Path $root 'deploy\runtime.json'), $json + "`n", [Text.UTF8Encoding]::new($false))
Write-Host "Exported $($entries.Count) runtime files to deploy/runtime.json."
