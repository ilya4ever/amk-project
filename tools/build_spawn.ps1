param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$cp1251 = [System.Text.Encoding]::GetEncoding(1251)
$vanilla = Join-Path $ProjectRoot 'spawn-vanilla'
$current = Join-Path $ProjectRoot 'spawn-current'
$output = Join-Path $ProjectRoot 'spawn-clean'

if (Test-Path $output) {
    Remove-Item -LiteralPath $output -Recurse -Force
}
Copy-Item -LiteralPath $vanilla -Destination $output -Recurse

function Read-Ltx([string]$Path) {
    return [System.IO.File]::ReadAllText($Path, $cp1251)
}

function Write-Ltx([string]$Path, [string]$Text) {
    [System.IO.File]::WriteAllText($Path, $Text, $cp1251)
}

function Split-Blocks([string]$Text) {
    $matches = [regex]::Matches($Text, '(?ms)^\[(\d+)\]\s*.*?(?=^\[\d+\]\s*|\z)')
    return @($matches | ForEach-Object { $_.Value.TrimEnd() })
}

function Get-Name([string]$Block) {
    $m = [regex]::Match($Block, '(?m)^name\s*=\s*([^\r\n]+)')
    if ($m.Success) { return $m.Groups[1].Value.Trim() }
    return ''
}

function Get-Profile([string]$Block) {
    $m = [regex]::Match($Block, '(?m)^character_profile\s*=\s*([^\r\n]+)')
    if ($m.Success) { return $m.Groups[1].Value.Trim() }
    return ''
}

function Renumber-Block([string]$Block, [int]$Id) {
    $result = [regex]::Replace($Block, '(?m)^\[\d+\]', "[$Id]", 1)
    return [regex]::Replace($result, '(?m)^spawn_id\s*=\s*\d+', "spawn_id = $Id", 1)
}

function Join-Blocks([object[]]$Blocks) {
    return (($Blocks -join "`r`n`r`n;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;`r`n`r`n") + "`r`n")
}

# Move the vanilla actor to the kindergarten in Pripyat.
$actorPath = Join-Path $output 'alife_l01_escape.ltx'
$actorBlocks = Split-Blocks (Read-Ltx $actorPath)
for ($i = 0; $i -lt $actorBlocks.Count; $i++) {
    if ($actorBlocks[$i] -match '(?m)^section_name\s*=\s*actor\s*$') {
        $actorBlocks[$i] = [regex]::Replace($actorBlocks[$i], '(?m)^position\s*=.*$', 'position = 112.25, 5.64, -31.82', 1)
        $actorBlocks[$i] = [regex]::Replace($actorBlocks[$i], '(?m)^direction\s*=.*$', 'direction = 0, 0, 0', 1)
        $actorBlocks[$i] = [regex]::Replace($actorBlocks[$i], '(?m)^game_vertex_id\s*=.*$', 'game_vertex_id = 2232', 1)
        $actorBlocks[$i] = [regex]::Replace($actorBlocks[$i], '(?m)^level_vertex_id\s*=.*$', 'level_vertex_id = 214948', 1)
        # Vanilla all.spawn stores the starting detector as a bare inventory line,
        # not as a key/value pair.  The dosimeter is a later quest reward here.
        $actorBlocks[$i] = [regex]::Replace($actorBlocks[$i], '(?m)^\s*detector_simple\s*(?:=.*)?\r?\n?', '')
        break
    }
}
Write-Ltx $actorPath (Join-Blocks $actorBlocks)

# Pripyat: direct arrival in the Freedom camp on Radar, without the vanilla gauntlet.
$pripyatPath = Join-Path $output 'alife_l11_pripyat.ltx'
$pripyatBlocks = Split-Blocks (Read-Ltx $pripyatPath)
for ($i = 0; $i -lt $pripyatBlocks.Count; $i++) {
    if ($pripyatBlocks[$i] -match '(?m)^story_id\s*=\s*833\s*$') {
        $pripyatBlocks[$i] = [regex]::Replace($pripyatBlocks[$i], '(?m)^dest_game_vertex_id\s*=.*$', 'dest_game_vertex_id = 1994', 1)
        $pripyatBlocks[$i] = [regex]::Replace($pripyatBlocks[$i], '(?m)^dest_level_vertex_id\s*=.*$', 'dest_level_vertex_id = 20969', 1)
        $pripyatBlocks[$i] = [regex]::Replace($pripyatBlocks[$i], '(?m)^dest_position\s*=.*$', 'dest_position = 32.525554656982, -1.0207467079163, -65.378974914551', 1)
        $pripyatBlocks[$i] = [regex]::Replace($pripyatBlocks[$i], '(?m)^dest_direction\s*=.*$', 'dest_direction = 0, 0.980419, 0', 1)
    }
}
$pripyatBlocks = @($pripyatBlocks | Where-Object {
    $profile = Get-Profile $_
    $name = Get-Name $_
    -not ($profile -like 'pri_monolith_*' -or $name -like 'pri_heli*' -or $_ -match '(?m)^section_name\s*=\s*helicopter\s*$')
})
Write-Ltx $pripyatPath (Join-Blocks $pripyatBlocks)

# Radar: remove the vanilla faction battle and scripted helicopter.
$radarPath = Join-Path $output 'alife_l10_radar.ltx'
$radarBlocks = Split-Blocks (Read-Ltx $radarPath)
$radarBlocks = @($radarBlocks | Where-Object {
    $profile = Get-Profile $_
    $name = Get-Name $_
    $removeProfile = $profile -like 'rad_monolit*' -or $profile -like 'rad_soldier*' -or $profile -like 'rad_Dolg*' -or $profile -like 'rad_Svoboda*'
    $removeRespawn = $_ -match 'respawn_section\s*=\s*(rad_freedom|rad_specnaz)'
    -not ($removeProfile -or $removeRespawn -or $name -eq 'rad_helicopter' -or $_ -match '(?m)^section_name\s*=\s*helicopter\s*$')
})
Write-Ltx $radarPath (Join-Blocks $radarBlocks)

# Import only objects authored for this storyline.  AMK's remaining spawn is ignored.
$nextId = 9000
foreach ($fileName in @('alife_l11_pripyat.ltx', 'alife_l10_radar.ltx', 'alife_l07_military.ltx')) {
    $sourcePath = Join-Path $current $fileName
    $targetPath = Join-Path $output $fileName
    $custom = @()
    foreach ($block in (Split-Blocks (Read-Ltx $sourcePath))) {
        $name = Get-Name $block
        $isDeadCityChanger = $block -match '(?m)^section_name\s*=\s*level_changer\s*$' -and $block -match '(?m)^dest_level_name\s*=\s*dead_city\s*$'
        $isBarRadio = $fileName -eq 'alife_l07_military.ltx' -and $block -match 'snd\s*=\s*pravo_mil_freedom_bar_radio'
        if (($name -like 'pravo_*' -or $isBarRadio) -and -not $isDeadCityChanger) {
            $custom += Renumber-Block $block $nextId
            $nextId++
        }
    }
    if ($custom.Count -gt 0) {
        $targetBlocks = Split-Blocks (Read-Ltx $targetPath)
        if ($fileName -eq 'alife_l07_military.ltx') {
            # The story turns this existing radio prop into the Freedom-bar
            # music source. Replace the stock instance instead of stacking an
            # identical second physic object at the same coordinates.
            $targetBlocks = @($targetBlocks | Where-Object {
                -not ((Get-Name $_) -eq 'mil_physic_object_0000' -and
                    $_ -match '(?m)^position\s*=\s*-75\.6556396484375,\s*-11\.339225769043,\s*27\.6867733001709\s*$')
            })
        }
        $target = (Join-Blocks $targetBlocks).TrimEnd()
        Write-Ltx $targetPath ($target + "`r`n`r`n;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;`r`n`r`n" + (Join-Blocks $custom))
    }
}

# OGSR can load added patrol paths from a standalone LTX file.
$pathSections = [ordered]@{}
foreach ($wayFile in (Get-ChildItem -LiteralPath $current -Filter 'way_*.ltx')) {
    $text = Read-Ltx $wayFile.FullName
    $matches = [regex]::Matches($text, '(?ms)^\[([^\]]+)\]\s*.*?(?=^\[[^\]]+\]\s*|\z)')
    foreach ($match in $matches) {
        $section = $match.Groups[1].Value.Trim()
        if ($section -like 'pravo_*') {
            $pathSections[$section] = $match.Value.TrimEnd()
        }
    }
}
$wayOut = Join-Path $ProjectRoot 'story\gamedata\config\pravo_waypoints.ltx'
Write-Ltx $wayOut ((@($pathSections.Values) -join "`r`n`r`n") + "`r`n")

Write-Host "Clean spawn source prepared: $output"
Write-Host "Imported custom objects: $($nextId - 9000)"
