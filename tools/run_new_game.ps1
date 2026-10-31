param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$game = Join-Path $ProjectRoot 'game'
$engine = Join-Path $game 'bin_x64\xrEngine.exe'
$fsgame = Join-Path $game 'fsgame.ltx'
$arguments = "-nointro -fsltx `"$fsgame`" -start server(all/single/alife/new) client(localhost)"
Start-Process -FilePath $engine -ArgumentList $arguments -WorkingDirectory $game
