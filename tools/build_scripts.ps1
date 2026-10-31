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

"@
}
Write-Text1251 (Join-Path $storyScripts 'sound_theme.script') $soundTheme

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

# Debug shortcuts live in the pause menu; gameplay function-key bindings stay intact.
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
$menu = [regex]::Replace($menu, '(?m)^(\s*_ver:SetText[^\r\n]*)', '$1' + "`r`n`tpravo_debug.attach_panel(self)")
$menu = $menu.Replace('self.shniaga:SetVisibleMagnifier(f)', "self.shniaga:SetVisibleMagnifier(f)`r`n`tpravo_debug.show_panel(self, f)")
$menu = $menu.Replace('CUIScriptWnd.OnKeyboard(self,dik,keyboard_action)', "if keyboard_action == ui_events.WINDOW_KEY_PRESSED and pravo_debug.menu_key(dik) then return true end`r`n`tCUIScriptWnd.OnKeyboard(self,dik,keyboard_action)")
Write-Text1251 (Join-Path $storyScripts 'ui_main_menu.script') $menu
$debugXml = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'assets\ui_pravo_debug.xml'), [Text.Encoding]::UTF8)
New-Item -ItemType Directory -Path (Join-Path $ProjectRoot 'story\gamedata\config\ui') -Force | Out-Null
Write-Text1251 (Join-Path $ProjectRoot 'story\gamedata\config\ui\ui_pravo_debug.xml') $debugXml
