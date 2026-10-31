param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$cp1251 = [System.Text.Encoding]::GetEncoding(1251)
$vanillaScripts = Join-Path $ProjectRoot 'vanilla-reference\scripts'
$storyScripts = Join-Path $ProjectRoot 'story\gamedata\scripts'

function Read-Text1251([string]$Path) {
    return [System.IO.File]::ReadAllText($Path, $cp1251)
}

function Write-Text1251([string]$Path, [string]$Text) {
    [System.IO.File]::WriteAllText($Path, $Text, $cp1251)
}

# Bind the custom controller to the otherwise untouched vanilla actor binder.
$bind = Read-Text1251 (Join-Path $vanillaScripts 'bind_stalker.script')
$bind = $bind.Replace("`tdb.add_actor(self.object)`r`n", "`tdb.add_actor(self.object)`r`n`tpravo_story.init()`r`n")
$bind = $bind.Replace("`tdb.del_actor(self.object)`r`n", "`tpravo_story.shutdown()`r`n`tdb.del_actor(self.object)`r`n")
$updateNeedle = "`tif self.object.radiation >= 0.7 then"
if ($bind -notmatch 'pravo_story\.update\(\)') {
    $bind = $bind.Replace($updateNeedle, "`tpravo_story.update()`r`n`r`n$updateNeedle")
}
Write-Text1251 (Join-Path $storyScripts 'bind_stalker.script') $bind

# One small condlist effect is needed by the Pripyat escape trigger.
$effects = Read-Text1251 (Join-Path $vanillaScripts 'xr_effects.script')
if ($effects -notmatch 'function pravo_dead_city_thought') {
    $effects += @"


function pravo_dead_city_thought(actor, npc)
    if db.actor ~= nil then
        news_manager.send_tip(db.actor, "pravo_pri_dead_city_thought", nil, nil, 9000)
    end
end
"@
}
Write-Text1251 (Join-Path $storyScripts 'xr_effects.script') $effects

# Register both custom physical-radio themes without inheriting AMK's patched
# xr_sound implementation.  Vanilla xr_sound already reads this table.
$soundTheme = Read-Text1251 (Join-Path $vanillaScripts 'sound_theme.script')
if ($soundTheme -notmatch 'ph_snd_themes\["pravo_rad_freedom_radio"\]') {
    $soundTheme += @"


ph_snd_themes["pravo_rad_freedom_radio"] = {
    [[pravo\radar\invisible_los_libros_de_la_buena_memoria]]
}

ph_snd_themes["pravo_mil_freedom_bar_radio"] = {
    [[pravo\military_bar\bar_track_01]],
    [[pravo\military_bar\bar_track_02]],
    [[pravo\military_bar\bar_track_03]],
    [[pravo\military_bar\bar_track_04]],
    [[pravo\military_bar\bar_track_05]]
}
"@
}
Write-Text1251 (Join-Path $storyScripts 'sound_theme.script') $soundTheme

Write-Host 'Clean OGSR script hooks prepared.'
