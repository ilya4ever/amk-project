param([string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference = 'Stop'
$cp = [Text.Encoding]::GetEncoding(1251)
$story = Join-Path $ProjectRoot 'story\gamedata'
function Read-Mil([string]$p) { [IO.File]::ReadAllText($p, $cp) }
function Write-Mil([string]$p, [string]$text) { [IO.File]::WriteAllText($p, $text.Replace("`r`n", "`n"), $cp) }

# Author readable UTF-8 sources, deploy X-Ray's Windows-1251 XML.
foreach ($file in Get-ChildItem (Join-Path $PSScriptRoot 'assets\military') -Filter '*.xml') {
    $folder = if ($file.Name -like 'stable_*') { 'config\text\rus' } else { 'config\gameplay' }
    Write-Mil (Join-Path (Join-Path $story $folder) $file.Name) ([IO.File]::ReadAllText($file.FullName, [Text.Encoding]::UTF8))
}

# New games get the dispatch immediately upon reporting the zombie job.
$dialogsPath = Join-Path $story 'config\gameplay\dialogs_pravo.xml'
$dialogs = Read-Mil $dialogsPath
$dialogs = $dialogs.Replace('<text>pravo_rad_freedom_leader_zombies_report_1</text>', '<text>pravo_mil_radar_report_dispatch</text>')
if ($dialogs -notmatch '<give_info>pravo_mil_barrier_started</give_info>') {
    $dialogs = $dialogs.Replace('<give_info>pravo_rad_zombies_done</give_info>', "<give_info>pravo_rad_zombies_done</give_info>`n<give_info>pravo_mil_barrier_started</give_info>")
}
Write-Mil $dialogsPath $dialogs

# Use the original named NPCs and IDs, but none of their vanilla quest offers.
$characters = Read-Mil (Join-Path $ProjectRoot 'vanilla-reference\config\gameplay\character_desc_military.xml')
foreach ($profile in @('mil_Svoboda_blockpost_leader', 'mil_Svoboda_leader')) {
    $pattern = '(?s)<specific_character id="' + $profile + '".*?</specific_character>[ \t]*'
    $m = [regex]::Match($characters, $pattern)
    if (-not $m.Success) { throw "Military profile missing: $profile" }
    $block = [regex]::Replace($m.Value, '<(?:start_dialog|actor_dialog)>.*?</(?:start_dialog|actor_dialog)>', '')
    $dialog = if ($profile -eq 'mil_Svoboda_blockpost_leader') { 'pravo_mil_barrier_intro' } else { 'pravo_mil_lukash_intro' }
    $block = $block.Replace('</specific_character>', "<actor_dialog>$dialog</actor_dialog>`n</specific_character>")
    if ($profile -eq 'mil_Svoboda_leader') {
        $block = $block.Replace('</specific_character>', "<actor_dialog>pravo_mil_gift_return</actor_dialog>`n</specific_character>")
    }
    $block = [regex]::Replace($block, '(?m)[ \t]+$', '')
    # character_dialogs.xml supplies a single generic hello and trade/help.
    $characters = $characters.Replace($m.Value, $block)
}
Write-Mil (Join-Path $story 'config\gameplay\character_desc_military.xml') $characters

$path = Join-Path $ProjectRoot 'spawn-clean\alife_l07_military.ltx'
$blocks = [regex]::Matches((Read-Mil $path), '(?ms)^\[\d+\].*?(?=^\[\d+\]|\z)')
$kept = @()
$removed = @()
foreach ($m in $blocks) {
    $b = $m.Value.TrimEnd()
    $name = [regex]::Match($b, '(?m)^name\s*=\s*([^\r\n]+)').Groups[1].Value.Trim()
    $profile = [regex]::Match($b, '(?m)^character_profile\s*=\s*([^\r\n]+)').Groups[1].Value.Trim()
    $sid = [regex]::Match($b, '(?m)^story_id\s*=\s*(\d+)\s*$').Groups[1].Value
    $remove = $profile -match '^mil_(Dolg|Monolit|Killer)' -or
        $profile -in @('mil_Svoboda_stukach', 'mil_Svoboda_zombi_stalker') -or
        $sid -in @('709', '720', '721', '722', '723', '706') -or
        $name -in @('mil_freedom_barier_respawn_1', 'mil_freedom_respawn_1', 'mil_killer_respawn_1')
    if ($remove) { $removed += $name; continue }
    if ($sid -in @('724', '707')) {
        $cfg = if ($sid -eq '724') { 'scripts\pravo_mil_barrier.ltx' } else { 'scripts\pravo_mil_lukash.ltx' }
        $custom = "custom_data = <<END`n[smart_terrains]`nnone = true`n[logic]`ncfg = $cfg`nEND"
        $b = [regex]::Replace($b, '(?ms)^custom_data\s*=\s*<<END\r?\n.*?^END[^\S\r\n]*$', $custom)
    }
    $kept += $b
}
Write-Mil $path (($kept -join "`n`n") + "`n")
Write-Host "Military story prepared; removed $($removed.Count) vanilla quest actors, props and respawners."
