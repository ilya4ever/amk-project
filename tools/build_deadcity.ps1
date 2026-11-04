param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$DonorRoot = (Join-Path (Split-Path -Parent $ProjectRoot) 'unpackedtt2'),
    [string]$AcdcRoot = (Join-Path (Split-Path -Parent $ProjectRoot) 'mod-tools\Universal-ACDC'),
    [string]$PerlExe = 'C:\Program Files\Git\usr\bin\perl.exe',
    [string]$PythonExe = (Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'),
    [string]$SevenZip = (Join-Path (Split-Path -Parent $ProjectRoot) 'mod-tools\7zip-xdb\7z.exe')
)
$ErrorActionPreference = 'Stop'
$stage = Join-Path $ProjectRoot 'build-deadcity'
$story = Join-Path $ProjectRoot 'story\gamedata'
$spawn = Join-Path $ProjectRoot 'spawn-clean'
$cp = [Text.Encoding]::GetEncoding(1251)
function Read-DC([string]$p) { [IO.File]::ReadAllText($p, $cp).Replace("`r`n", "`n").Replace("`r", '') }
function Write-DC([string]$p, [string]$s) {
    New-Item -ItemType Directory -Path (Split-Path -Parent $p) -Force | Out-Null
    [IO.File]::WriteAllText($p, $s.Replace("`r`n", "`n"), $cp)
}
function Blocks-DC([string]$s) { @([regex]::Matches($s, '(?ms)^\[\d+\].*?(?=^\[\d+\]|\z)') | ForEach-Object { $_.Value.TrimEnd() }) }
function Renumber-DC([string]$s, [int]$id) {
    $s = [regex]::Replace($s, '(?m)^\[\d+\]', "[$id]", 1)
    [regex]::Replace($s, '(?m)^spawn_id\s*=.*$', "spawn_id = $id")
}
New-Item -ItemType Directory -Path (Join-Path $stage 'base') -Force | Out-Null
& $SevenZip e (Join-Path $ProjectRoot 'game\gamedata.dbb') 'game.graph' ("-o" + (Join-Path $stage 'base')) -y | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Cannot extract clean OGSR graph' }
& $PerlExe -I $AcdcRoot (Join-Path $PSScriptRoot 'merge_dead_city_graph.pl') `
    (Join-Path $stage 'base\game.graph') (Join-Path $DonorRoot 'game.graph') `
    (Join-Path $DonorRoot 'levels\dead_city\level.gct') (Join-Path $stage 'game.graph') `
    (Join-Path $stage 'level.gct') (Join-Path $stage 'graph.json')
if ($LASTEXITCODE -ne 0) { throw 'Dead City graph merge failed' }
$graph = Get-Content -LiteralPath (Join-Path $stage 'graph.json') -Raw | ConvertFrom-Json
& $PythonExe (Join-Path $PSScriptRoot 'stage_dead_city_assets.py') --project $ProjectRoot --donor $DonorRoot --sevenzip $SevenZip
if ($LASTEXITCODE -ne 0) { throw 'Dead City dependency staging failed' }
Copy-Item -LiteralPath (Join-Path $stage 'game.graph') -Destination (Join-Path $story 'game.graph') -Force
Copy-Item -LiteralPath (Join-Path $stage 'level.gct') -Destination (Join-Path $stage 'assets\gamedata\levels\dead_city\level.gct') -Force

# Vanilla levels remain untouched; only register the appended level.
$levels = Read-DC (Join-Path $ProjectRoot 'vanilla-reference\config\game_levels.ltx')
$levels = $levels.Replace('[levels]', "[levels]`n    level26")
$levels += "`n[level26]`nname = dead_city`ncaption = dead_city`noffset = 1000,1000,3000`nid = 26`n"
Write-DC (Join-Path $story 'config\game_levels.ltx') $levels
$maps = Read-DC (Join-Path $ProjectRoot 'vanilla-reference\config\game_maps_single.ltx')
$maps = $maps.Replace('[level_maps_single]', "[level_maps_single]`ndead_city")
$maps += "`n[dead_city]`ntexture = map\map_dead_city`nbound_rect = -509.583,-413.607,396.726,530.0`nglobal_rect = 200,1210,400,1418.23`nweathers = default`nmusic_tracks = l07_military_musics`n"
Write-DC (Join-Path $story 'config\game_maps_single.ltx') $maps
$strings = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'assets\stable_pravo_deadcity.xml'), [Text.Encoding]::UTF8)
Write-DC (Join-Path $story 'config\text\rus\stable_pravo_deadcity.xml') $strings
$locPath = Join-Path $story 'config\localization.ltx'
$loc = Read-DC $locPath
if ($loc -notmatch '\bstable_pravo_deadcity\b') { $loc = [regex]::Replace($loc, '(?m)^(files\s*=.*)$', '$1, stable_pravo_deadcity') }
Write-DC $locPath $loc
$idsPath = Join-Path $story 'config\game_story_ids.ltx'
$ids = Read-DC $idsPath
if ($ids -notmatch '(?m)^\s*6500\s*=') { $ids += "`n6500 = `"pravo_mil_to_dead_city`"`n6501 = `"pravo_dead_city_to_military`"`n" }
Write-DC $idsPath $ids

$current = Join-Path $ProjectRoot 'spawn-current'
$military = Blocks-DC (Read-DC (Join-Path $current 'alife_l07_military.ltx'))
$forward = @($military | Where-Object { $_ -match '(?m)^name\s*=\s*pravo_mil_to_dead_city\s*$' })
if ($forward.Count -ne 1) { throw 'Military transition template missing/ambiguous' }
$forward = $forward[0]
$forward = [regex]::Replace($forward, '(?m)^dest_game_vertex_id\s*=.*$', "dest_game_vertex_id = $($graph.entry_gv)")
$forward = [regex]::Replace($forward, '(?m)^restrictor_type\s*=.*$', 'restrictor_type = 0')
$forward = [regex]::Replace($forward, '(?m)^dest_level_name\s*=.*$', 'dest_level_name = dead_city')
$forward = Renumber-DC $forward 12000
$milPath = Join-Path $spawn 'alife_l07_military.ltx'
$mil = @(Blocks-DC (Read-DC $milPath) | Where-Object { $_ -notmatch '(?m)^name\s*=\s*pravo_mil_to_dead_city\s*$' })
Write-DC $milPath (($mil + @($forward)) -join "`n`n")

$dead = @()
$id = 12001
foreach ($block in (Blocks-DC (Read-DC (Join-Path $current 'alife_dead_city.ltx')))) {
    $isReturn = $block -match '(?m)^name\s*=\s*pravo_dead_city_to_military\s*$'
    $isStatic = $block -match '(?m)^section_name\s*=\s*climable_object\s*$' -or
        ($block -match '(?m)^section_name\s*=\s*lights_hanging_lamp\s*$' -and $block -match '(?m)^visual_name\s*=')
    if (-not ($isReturn -or $isStatic)) { continue }
    if ($isReturn) {
        $block = [regex]::Replace($block, '(?m)^game_vertex_id\s*=.*$', "game_vertex_id = $($graph.entry_gv)")
        $block = [regex]::Replace($block, '(?m)^level_vertex_id\s*=.*$', "level_vertex_id = $($graph.entry_lv)")
        $block = [regex]::Replace($block, '(?m)^dest_level_name\s*=.*$', 'dest_level_name = l07_military')
    } else {
        $pos = [regex]::Match($block, '(?m)^position\s*=\s*([^\r\n]+)').Groups[1].Value.Split(',')
        $nearest = $graph.vertices | Sort-Object { [math]::Pow([double]$_.position[0]-[double]::Parse($pos[0],[cultureinfo]::InvariantCulture),2) + [math]::Pow([double]$_.position[1]-[double]::Parse($pos[1],[cultureinfo]::InvariantCulture),2) + [math]::Pow([double]$_.position[2]-[double]::Parse($pos[2],[cultureinfo]::InvariantCulture),2) } | Select-Object -First 1
        $block = [regex]::Replace($block, '(?m)^game_vertex_id\s*=.*$', "game_vertex_id = $($nearest.gv)")
        $block = [regex]::Replace($block, '(?m)^level_vertex_id\s*=.*$', "level_vertex_id = $($nearest.lv)")
        $block = [regex]::Replace($block, '(?m)^name\s*=.*$', "name = pravo_dc_static_$id")
    }
    $dead += Renumber-DC $block $id
    $id++
}
Write-DC (Join-Path $spawn 'alife_dead_city.ltx') ($dead -join "`n`n")
$allPath = Join-Path $spawn 'all.ltx'
$all = (Read-DC $allPath).Replace("`r`n", "`n")
$all = [regex]::Replace($all, '(?m)^level_count\s*=.*$', 'level_count = 19')
$all = [regex]::Replace($all, '(?m)^graph_guid\s*=.*$', "graph_guid = $($graph.graph_guid)")
$all = [regex]::Replace($all, '(?m)^guid\s*=.*$', 'guid = 981a4fb8d52c4d79bdbf3c1171ba6702')
$all = $all.Replace("[alife]`nsource_files = <<END", "[alife]`nsource_files = <<END`nalife_dead_city.ltx,")
Write-DC $allPath $all
Write-Host "Dead City prepared: $($dead.Count) infrastructure objects; two-way Military transition; no donor NPCs."
