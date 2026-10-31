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
    # ACDC's Perl heredoc reader includes CR in the <<END terminator on Windows.
    [System.IO.File]::WriteAllText($Path, $Text.Replace("`r`n", "`n"), $cp1251)
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

# Neutralize original plot triggers on every level before importing our story.
# Leave physical restrictors in place because NPC paths can reference them.
foreach ($file in Get-ChildItem -LiteralPath $output -Filter 'alife_*.ltx') {
    $blocks = Split-Blocks (Read-Ltx $file.FullName)
    for ($i = 0; $i -lt $blocks.Count; $i++) {
        $block = $blocks[$i]
        if ($block -notmatch '(?m)^section_name\s*=\s*space_restrictor\s*$') { continue }
        $logic = $block
        $cfg = [regex]::Match($block, '(?m)^cfg\s*=\s*([^;\r\n]+)')
        if ($cfg.Success) {
            $cfgPath = Join-Path $ProjectRoot ('vanilla-reference\config\' + $cfg.Groups[1].Value.Trim())
            if (Test-Path -LiteralPath $cfgPath) { $logic += Read-Ltx $cfgPath }
        }
        if ($logic -match '(?m)^active\s*=\s*sr_(idle|cutscene|sound_act|teleport|timer|tip)(?:\b|@|\d)') {
            $blocks[$i] = [regex]::Replace($block, '(?ms)^custom_data\s*=\s*<<END\r?\n.*?^END\s*$', "custom_data = <<END`r`n[logic]`r`nactive = nil`r`nEND")
        }
    }
    Write-Ltx $file.FullName (Join-Blocks $blocks)
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
        # The actor has a second serialized position in the update packet.
        # Leaving the vanilla Cordon coordinates here makes the engine create
        # him at (-246, -24, -134) while Pripyat is loaded — below the map.
        $actorBlocks[$i] = [regex]::Replace($actorBlocks[$i], '(?m)^upd:position\s*=.*$', 'upd:position = 112.25, 5.64, -31.82', 1)
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
    -not ($profile -ne '' -or
        $name -in @('pri_respawn_military', 'pri_respawn_dolg', 'pri_respawn_freedom', 'pri_monolith_respawn_1') -or
        $name -like 'pri_heli*' -or
        $name -like 'pri_ambient_battle_sound_zone*' -or
        $_ -match '(?m)^section_name\s*=\s*helicopter\s*$')
})
Write-Ltx $pripyatPath (Join-Blocks $pripyatBlocks)

# Radar: remove the vanilla faction battle and scripted helicopter.
$radarPath = Join-Path $output 'alife_l10_radar.ltx'
$radarBlocks = Split-Blocks (Read-Ltx $radarPath)
# The original Brain Scorcher is already inactive in this story. Neutralize
# both its damaging fields and its negative-intensity shelter in new games.
for ($i = 0; $i -lt $radarBlocks.Count; $i++) {
    if ($radarBlocks[$i] -match '(?m)^section_name\s*=\s*space_restrictor\s*$' -and
        $radarBlocks[$i] -match '(?m)^active\s*=\s*sr_psy_antenna(?:\b|@)') {
        $radarBlocks[$i] = [regex]::Replace($radarBlocks[$i], '(?ms)^custom_data\s*=\s*<<END\r?\n.*?^END\s*$', "custom_data = <<END`r`n[logic]`r`nactive = nil`r`nEND")
    }
}
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
foreach ($fileName in @('alife_l11_pripyat.ltx', 'alife_l10_radar.ltx')) {
    $sourcePath = Join-Path $current $fileName
    $targetPath = Join-Path $output $fileName
    $custom = @()
    foreach ($block in (Split-Blocks (Read-Ltx $sourcePath))) {
        $name = Get-Name $block
        $isDeadCityChanger = $block -match '(?m)^section_name\s*=\s*level_changer\s*$' -and $block -match '(?m)^dest_level_name\s*=\s*dead_city\s*$'
        if (($name -like 'pravo_*') -and -not $isDeadCityChanger) {
            $custom += Renumber-Block $block $nextId
            $nextId++
        }
    }
    if ($custom.Count -gt 0) {
        $targetBlocks = Split-Blocks (Read-Ltx $targetPath)
        $target = (Join-Blocks $targetBlocks).TrimEnd()
        Write-Ltx $targetPath ($target + "`r`n`r`n;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;`r`n`r`n" + (Join-Blocks $custom))
    }
}

# OGSR can load added patrol paths from a standalone LTX file.
$pathSections = [ordered]@{}
foreach ($wayFile in @(
    (Get-Item (Join-Path $current 'way_l10_radar.ltx')),
    (Get-Item (Join-Path $current 'way_l11_pripyat.ltx'))
)) {
    $text = Read-Ltx $wayFile.FullName
    $matches = [regex]::Matches($text, '(?ms)^\[([^\]]+)\]\s*.*?(?=^\[[^\]]+\]\s*|\z)')
    $customForLevel = @()
    foreach ($match in $matches) {
        $section = $match.Groups[1].Value.Trim()
        if ($section -like 'pravo_*') {
            $pathSections[$section] = $match.Value.TrimEnd()
            $customForLevel += $match.Value.TrimEnd()
        }
    }
    if ($customForLevel.Count -gt 0) {
        # Put the paths into all.spawn itself.  This is required by vanilla
        # walker logic and avoids relying solely on OGSR's optional external
        # waypoint loader during the dialogue-triggered scheme switch.
        $targetWay = Join-Path $output $wayFile.Name
        $targetText = (Read-Ltx $targetWay).TrimEnd()
        Write-Ltx $targetWay ($targetText + "`r`n`r`n" + ($customForLevel -join "`r`n`r`n") + "`r`n")
    }
}
$wayOut = Join-Path $ProjectRoot 'story\gamedata\config\pravo_waypoints.ltx'
Write-Ltx $wayOut ((@($pathSections.Values) -join "`r`n`r`n") + "`r`n")

Write-Host "Clean spawn source prepared: $output"
Write-Host "Imported custom objects: $($nextId - 9000)"
