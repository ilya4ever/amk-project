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

# Story effects called directly by the Pripyat escape restrictor in all.spawn.
$effects = Read-Text1251 (Join-Path $vanillaScripts 'xr_effects.script')
if ($effects -notmatch 'function pravo_dead_city_thought') {
    $effects += @"


function pravo_dead_city_thought(actor, npc)
    if db.actor ~= nil then
        news_manager.send_tip(db.actor, "pravo_pri_dead_city_thought", nil, nil, 9000)
    end
end

function pravo_pri_escape_aftermath(actor, npc)
    pravo_dialogs.setup_kindergarten_aftermath(actor, npc)
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

"@
}
Write-Text1251 (Join-Path $storyScripts 'sound_theme.script') $soundTheme

# A Dead City-only subclass retains native respawn ownership and creation.
$classes = Read-Text1251 (Join-Path $vanillaScripts 'class_registrator.script')
$nativeRespawn = [regex]::Match($classes, '(?m)^.*"se_respawn.se_respawn"[^\r\n]*').Value
if (-not $nativeRespawn) { throw 'Native respawn class registration missing' }
$dcRespawn = $nativeRespawn.Replace('se_respawn.se_respawn', 'pravo_dc_respawn.dc_respawn').Replace('RE_SPAWN', 'PR_DC_RP').Replace('"respawn"', '"pravo_dc_respawn"')
$classes = $classes.Replace($nativeRespawn, $nativeRespawn + "`r`n" + $dcRespawn)
Write-Text1251 (Join-Path $storyScripts 'class_registrator.script') $classes

# SoC ships CZombie and its models, but omits it from the statistics table.
# se_monster:on_death otherwise aborts when a real mutant zombie is killed.
$statistics = Read-Text1251 (Join-Path $vanillaScripts 'xr_statistic.script')
$statistics = $statistics.Replace('monster_classes = {', "monster_classes = {`r`n`t[clsid.zombie_s] = `"zombie`",")
Write-Text1251 (Join-Path $storyScripts 'xr_statistic.script') $statistics

# OGSR uses an empty parent ID for a dialogue root, not SoC's numeric -1.
# Both generic NPC greetings and the custom trader's random jobs use these.
foreach ($file in @('dialog_manager.script', 'task_manager.script')) {
    $script = Read-Text1251 (Join-Path $vanillaScripts $file)
    $script = $script.Replace(',0,-1,-10000)', ',"0","",-10000)')
    if ($file -eq 'dialog_manager.script') {
        # OGSR sends phrase IDs to callbacks as strings. Keep the original
        # numeric phrase tables and the binary NPC save format compatible.
        $script = [regex]::Replace($script, '(?m)^(function [^\r\n]*\([^\r\n]*\bp2\b[^\r\n]*\))', '$1' + "`r`n`t" + 'p2 = tonumber(p2)')
        $script = [regex]::Replace($script, '(?m)^(function [^\r\n]*\([^\r\n]*\bp3\b[^\r\n]*\))', '$1' + "`r`n`t" + 'p3 = tonumber(p3)')
    } else {
        # Register the vendor directly by a stable all.spawn story ID.
        $script = $script.Replace('local parent_by_story = {', "local parent_by_story = {`r`n`t[6521] = `"pravo_rad_trader`",")
        $script = $script.Replace('local story_by_parent = {', "local story_by_parent = {`r`n`tpravo_rad_trader = 6521,")
        # Generated IDs are also used as keys by the custom trader callbacks.
        $script = $script.Replace('return self.task_phrase_id', 'return tostring(self.task_phrase_id)')
        # A clean story may omit entire task types or vanilla vendors. Item
        # registration still runs for every spawn, so missing lists are empty.
        $script = [regex]::Replace($script, 'pairs\((self\.task_id_by_(?:type|parent)\[[^\]]+\])\)', 'pairs($1 or {})')
    }
    Write-Text1251 (Join-Path $storyScripts $file) $script
}

# Retain map/transition helpers, but stop the original per-level plot handlers.
$levelTasks = Read-Text1251 (Join-Path $vanillaScripts 'level_tasks.script')
$levelTasks = [regex]::Replace($levelTasks, '(?s)local level_scripts\s*=\s*\{.*?\}', 'local level_scripts = {}', 1)
Write-Text1251 (Join-Path $storyScripts 'level_tasks.script') $levelTasks

Write-Host 'Clean OGSR script hooks prepared.'

# Keep the OGSR options fix, but no debug UI or key interception.
$menu = Read-Text1251 (Join-Path $vanillaScripts 'ui_main_menu.script')
# OGSR's options window initializes its own controls and owns its menu
# lifecycle. The SoC caller's UpdateControls method no longer exists, and
# toggling the owner here also conflicts with OGSR's return-to-menu path.
$optionsHandler = @'
function main_menu:OnButton_options_clicked()
    if self.opt_dlg == nil then
        self.opt_dlg = ui_mm_opt_main.options_dialog()
        self.opt_dlg.owner = self
    end
    self:GetHolder():start_stop_menu(self.opt_dlg, true)
    self:Show(false)
end

'@
$optionsPattern = '(?s)function main_menu:OnButton_options_clicked\(\).*?(?=function main_menu:OnButton_load_clicked\()'
if ([regex]::Matches($menu, $optionsPattern).Count -ne 1) { throw 'Cannot find unique options menu handler' }
$menu = [regex]::Replace($menu, $optionsPattern, $optionsHandler + "`r`n")
Write-Text1251 (Join-Path $storyScripts 'ui_main_menu.script') $menu

# NPC coordinate overlay: retain the vanilla custom statics and add one isolated block.
$customMessages = [IO.File]::ReadAllText((Join-Path $ProjectRoot 'vanilla-reference\config\ui\ui_custom_msgs.xml'), [Text.Encoding]::UTF8)
$coordinateBlock = @"
    <pravo_coords x="20" y="150" width="980" height="160" complex_mode="1" priority="100">
        <text x="0" y="0" font="letterica18" r="255" g="240" b="130" a="255" align="l"/>
    </pravo_coords>
"@
if (-not $customMessages.Contains('</header>')) { throw 'Invalid ui_custom_msgs.xml template' }
$customMessages = $customMessages.Replace('</header>', $coordinateBlock + "`r`n</header>")
$customMessagesPath = Join-Path $ProjectRoot 'story\gamedata\config\ui\ui_custom_msgs.xml'
New-Item -ItemType Directory -Path (Split-Path -Parent $customMessagesPath) -Force | Out-Null
[IO.File]::WriteAllText($customMessagesPath, $customMessages, [Text.UTF8Encoding]::new($false))
