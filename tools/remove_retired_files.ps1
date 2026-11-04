param([string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot), [switch]$SourceOnly)
$ErrorActionPreference = 'Stop'
$retired = @(
    'scripts\pravo_debug.script', 'scripts\pravo_military_bar.script',
    'scripts\pravo_camp_safety.script', 'scripts\xr_motivator.script',
    'config\pravo_debug.ltx', 'config\ui\ui_pravo_debug.xml',
    'config\pravo_deadcity.ltx', 'config\pravo_waypoints.ltx',
    'config\pravo_military_cleanup.ltx', 'config\creatures\pravo_military_bar.ltx'
)
$roots = @((Join-Path $ProjectRoot 'story\gamedata'))
if (-not $SourceOnly) { $roots += Join-Path $ProjectRoot 'game\gamedata' }
foreach ($root in $roots) {
    $rootFull = [IO.Path]::GetFullPath($root).TrimEnd('\') + '\'
    foreach ($name in $retired) {
        $path = [IO.Path]::GetFullPath((Join-Path $root $name))
        if (-not $path.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid retired file path' }
        if (Test-Path -LiteralPath $path -PathType Leaf) { Remove-Item -LiteralPath $path -Force }
    }
}
