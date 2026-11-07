param([string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot), [switch]$SourceOnly)
$ErrorActionPreference = 'Stop'
$retired = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'retired_files.txt')
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
