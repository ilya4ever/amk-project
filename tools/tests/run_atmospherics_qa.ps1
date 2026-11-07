param([string]$ProjectRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))
$ErrorActionPreference = 'Stop'
$game = Join-Path $ProjectRoot 'game'
$qa = Join-Path $ProjectRoot 'build-deadcity\qa\atmospherics'
if (Get-Process -Name xrEngine -ErrorAction SilentlyContinue) { throw 'A game instance is running; leave it untouched.' }
New-Item -ItemType Directory -Path $qa -Force | Out-Null
$runtime = Join-Path $game 'gamedata\scripts\pravo_story.script'
$probe = Join-Path $game 'gamedata\scripts\atmospherics.script'
$fs = Join-Path $game 'fsgame_atmos_qa.ltx'
$original = [IO.File]::ReadAllBytes($runtime)
$fsOriginal = if (Test-Path -LiteralPath $fs) { [IO.File]::ReadAllBytes($fs) } else { $null }
$user = [IO.File]::ReadAllText((Join-Path $game '_appdata_\user_ogsr.ltx'))
$user = $user -replace '(?m)^keypress_on_start .*$', 'keypress_on_start off'
[IO.File]::WriteAllText((Join-Path $qa 'user_ogsr.ltx'), $user)
$fsgame = [IO.File]::ReadAllText((Join-Path $game 'fsgame.ltx'))
$fsgame = [regex]::Replace($fsgame, '(?m)^\$app_data_root\$.*$', { '$app_data_root$ = true| false| ' + $qa + '\' })
foreach ($name in @('reload.requested')) {
    $path = Join-Path $qa $name
    if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
}
try {
    [IO.File]::WriteAllText($fs, $fsgame)
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'atmospherics.script') -Destination $probe -Force
    $source = [Text.Encoding]::UTF8.GetString($original).Replace('    pravo_mil_gift.update()', "    pravo_mil_gift.update()`n    atmospherics.run()")
    [IO.File]::WriteAllText($runtime,$source,[Text.UTF8Encoding]::new($false))
    New-Item -ItemType Directory -Path (Join-Path $qa 'savedgames') -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $game '_appdata_\savedgames\mario_quicksave.sav') -Destination (Join-Path $qa 'savedgames\mario_quicksave.sav') -Force
    $process = Start-Process -FilePath (Join-Path $game 'bin_x64\xrEngine.exe') -ArgumentList @('-nointro','-fsltx','fsgame_atmos_qa.ltx','-start','server(mario_quicksave/single/alife/load)','client(localhost)') -WorkingDirectory (Join-Path $game 'bin_x64') -PassThru
    if (-not $process.WaitForExit(180000)) { Stop-Process -Id $process.Id -Force; throw 'Native Atmospherics QA timed out.' }
} finally {
    [IO.File]::WriteAllBytes($runtime,$original)
    if (Test-Path -LiteralPath $probe) { Remove-Item -LiteralPath $probe -Force }
    if ($null -ne $fsOriginal) { [IO.File]::WriteAllBytes($fs,$fsOriginal) }
    elseif (Test-Path -LiteralPath $fs) { Remove-Item -LiteralPath $fs -Force }
}
$log = Get-ChildItem (Join-Path $qa 'logs') -Filter '*.log' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
Select-String -LiteralPath $log.FullName -Pattern 'ATMOS_QA|FATAL ERROR|\[error\]' | ForEach-Object Line
if (-not (Select-String -LiteralPath $log.FullName -SimpleMatch 'ATMOS_QA: PASS' -Quiet)) { throw "Native Atmospherics QA failed; see $($log.FullName)" }
