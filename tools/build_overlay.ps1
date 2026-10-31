param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$cp1251 = [System.Text.Encoding]::GetEncoding(1251)
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$story = Join-Path $ProjectRoot 'story\gamedata'

function Read-Text1251([string]$Path) {
    return [System.IO.File]::ReadAllText($Path, $cp1251)
}

function Write-Text1251([string]$Path, [string]$Text) {
    [System.IO.File]::WriteAllText($Path, $Text, $cp1251)
}

function Add-CsvValue([string]$Text, [string]$Section, [string]$Key, [string[]]$Values) {
    $pattern = "(?ms)(^\[$([regex]::Escape($Section))\]\s*.*?^$([regex]::Escape($Key))\s*=\s*)([^\r\n]*)(?=\r?$)"
    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success) {
        throw "Cannot find [$Section] $Key"
    }

    $items = @($match.Groups[2].Value -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    foreach ($value in $Values) {
        if ($items -notcontains $value) {
            $items += $value
        }
    }
    return $Text.Substring(0, $match.Groups[2].Index) + ($items -join ', ') + $Text.Substring($match.Groups[2].Index + $match.Groups[2].Length)
}

function Remove-CsvValue([string]$Text, [string]$Section, [string]$Key, [string[]]$Values) {
    $pattern = "(?ms)(^\[$([regex]::Escape($Section))\]\s*.*?^$([regex]::Escape($Key))\s*=\s*)([^\r\n]*)(?=\r?$)"
    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success) {
        throw "Cannot find [$Section] $Key"
    }

    $items = @($match.Groups[2].Value -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $Values -notcontains $_ })
    return $Text.Substring(0, $match.Groups[2].Index) + ($items -join ', ') + $Text.Substring($match.Groups[2].Index + $match.Groups[2].Length)
}

$systemPath = Join-Path $story 'config\system.ltx'
$system = Read-Text1251 $systemPath
if ($system -notmatch [regex]::Escape('#include "misc\pravo_items.ltx"')) {
    $system = $system.Replace('#include "misc\unique_items.ltx"', "#include `"misc\unique_items.ltx`"`r`n#include `"misc\pravo_items.ltx`"")
}
if ($system -notmatch [regex]::Escape('#include "creatures\pravo_story_sections.ltx"')) {
    $system = $system.Replace('#include "creatures\spawn_sections.ltx"', "#include `"creatures\spawn_sections.ltx`"`r`n#include `"creatures\pravo_story_sections.ltx`"")
}
$system = Add-CsvValue $system 'info_portions' 'files' @('info_pravo')
$system = Add-CsvValue $system 'encyclopedia' 'files' @('storyline_info_pravo', 'storyline_info_pravo_trader')
$system = Add-CsvValue $system 'dialogs' 'files' @('dialogs_pravo', 'dialogs_pravo_tasks')
# The dream dialogue file is intentionally included inside dialogs_pravo.xml;
# registering it as a separate top-level document would define both dialogues
# twice and its fragment has no game_dialogs wrapper.
$system = Remove-CsvValue $system 'dialogs' 'files' @('dialogs_pravo_bar_dream')
$system = Add-CsvValue $system 'profiles' 'files' @('npc_pravo')
$system = Add-CsvValue $system 'profiles' 'specific_characters_files' @('character_desc_pravo')
Write-Text1251 $systemPath $system

$localizationPath = Join-Path $story 'config\localization.ltx'
$localization = Read-Text1251 $localizationPath
$localization = Add-CsvValue $localization 'string_table' 'files' @('stable_pravo_story', 'stable_pravo_tasks')
$localization = Remove-CsvValue $localization 'string_table' 'files' @('stable_pravo_bar_dream')
Write-Text1251 $localizationPath $localization

$tasksPath = Join-Path $story 'config\gameplay\game_tasks.xml'
$tasks = Read-Text1251 $tasksPath
foreach ($include in @('#include "gameplay\tasks_pravo.xml"', '#include "gameplay\tasks_pravo_trader.xml"')) {
    if ($tasks -notmatch [regex]::Escape($include)) {
        $tasks = $tasks.Replace('</game_tasks_data>', "$include`r`n</game_tasks_data>")
    }
}
$tasks = [regex]::Replace($tasks, '(?m)^#include "gameplay\\tasks_pravo_bar_dream.xml"\s*\r?\n?', '')
Write-Text1251 $tasksPath $tasks

$storyIdsPath = Join-Path $story 'config\game_story_ids.ltx'
$storyIds = Read-Text1251 $storyIdsPath
if ($storyIds -notmatch '(?m)^\s*834\s*=') {
    $customIds = @"

  ; Pravo clean OGSR storyline
  834          = "pravo_pri_freedom_leader"
  835          = "pravo_rad_freedom_leader"
  836          = "pravo_rad_dogs_quest_spot"
  837          = "pravo_rad_herb_item"
  838          = "pravo_rad_makar"
  839          = "pravo_pri_makar_story"
  840          = "pravo_pri_volodya_story"
  841          = "pravo_rad_zombies_quest_spot"
"@
    $storyIds = $storyIds.TrimEnd() + $customIds + "`r`n"
}
$storyIds = [regex]::Replace($storyIds, '(?m)^\s*835\s*=.*$', '  835          = "pravo_rad_freedom_leader"')
$storyIds = [regex]::Replace($storyIds, '(?m)^\s*839\s*=.*$', '  839          = "pravo_pri_makar_story"')
$storyIds = [regex]::Replace($storyIds, '(?m)^\s*840\s*=.*$', '  840          = "pravo_pri_volodya_story"')
Write-Text1251 $storyIdsPath $storyIds

$taskManagerPath = Join-Path $story 'config\misc\task_manager.ltx'
$taskManager = Read-Text1251 (Join-Path $ProjectRoot 'vanilla-reference\config\misc\task_manager.ltx')
foreach ($taskId in @('pravo_rad_artifact_medusa', 'pravo_rad_artifact_flower', 'pravo_rad_artifact_blood', 'pravo_rad_artifact_meat')) {
    if ($taskManager -notmatch "(?m)^$taskId\s*$") {
        $taskManager = $taskManager.Replace("mercenary_kill_stalker`r`n", "mercenary_kill_stalker`r`n$taskId`r`n")
    }
}
$taskManager += @"


[pravo_rad_artifact_medusa]
type = artefact
community = actor
text = pravo_rad_artifact_medusa_text
description = pravo_rad_artifact_medusa_descr
parent = pravo_rad_trader
target = af_medusa
reward_money = 1500
reward_reputation = +5
reward_relation = freedom, +10
reward_rank = 1
time = 604800
idle_time = 86400
prior = 1

[pravo_rad_artifact_flower]
type = artefact
community = actor
text = pravo_rad_artifact_flower_text
description = pravo_rad_artifact_flower_descr
parent = pravo_rad_trader
target = af_cristall_flower
reward_money = 3000
reward_reputation = +5
reward_relation = freedom, +10
reward_rank = 1
time = 604800
idle_time = 86400
prior = 1

[pravo_rad_artifact_blood]
type = artefact
community = actor
text = pravo_rad_artifact_blood_text
description = pravo_rad_artifact_blood_descr
parent = pravo_rad_trader
target = af_blood
reward_money = 2000
reward_reputation = +5
reward_relation = freedom, +10
reward_rank = 1
time = 604800
idle_time = 86400
prior = 1

[pravo_rad_artifact_meat]
type = artefact
community = actor
text = pravo_rad_artifact_meat_text
description = pravo_rad_artifact_meat_descr
parent = pravo_rad_trader
target = af_mincer_meat
reward_money = 4500
reward_reputation = +5
reward_relation = freedom, +10
reward_rank = 1
time = 604800
idle_time = 86400
prior = 1
"@
Write-Text1251 $taskManagerPath $taskManager

$externalPath = Join-Path $story 'config\external.ltx'
$external = [System.IO.File]::ReadAllText($externalPath)
$external = [regex]::Replace($external, '(?m)^\s*;\s*\[engine_custom_spawn\]\s*$', '[engine_custom_spawn]')
if ($external -match '(?m)^\s*;?\s*waypoints_file\s*=.*$') {
    $external = [regex]::Replace($external, '(?m)^\s*;?\s*waypoints_file\s*=.*$', 'waypoints_file = pravo_waypoints.ltx')
} elseif ($external -match '(?m)^\[engine_custom_spawn\]\s*$') {
    $external = [regex]::Replace($external, '(?m)^\[engine_custom_spawn\]\s*$', "[engine_custom_spawn]`r`nwaypoints_file = pravo_waypoints.ltx")
} else {
    $external += "`r`n[engine_custom_spawn]`r`nwaypoints_file = pravo_waypoints.ltx`r`n"
}
[System.IO.File]::WriteAllText($externalPath, $external, $utf8NoBom)

foreach ($path in @(
    (Join-Path $story 'config\gameplay\tasks_pravo.xml')
)) {
    $xml = Read-Text1251 $path
    $xml = $xml.Replace('amk_ui_flame_quest', 'ui_iconsTotal_grouping')
    Write-Text1251 $path $xml
}

# Remove every not-yet-ported Army Warehouses entry from the active registries.
$dialogsPath = Join-Path $story 'config\gameplay\dialogs_pravo.xml'
$dialogs = Read-Text1251 $dialogsPath
$dialogs = [regex]::Replace($dialogs, '(?s)\s*<dialog id="pravo_mil_barrier_commander_intro">.*?</dialog>', '')
$dialogs = [regex]::Replace($dialogs, '(?s)\s*<dialog id="pravo_mil_lukash_welcome">.*?</dialog>', '')
$dialogs = [regex]::Replace($dialogs, '(?m)^#include "gameplay\\dialogs_pravo_bar_dream.xml"\s*\r?\n?', '')
$dialogs = $dialogs.Replace('<give_info>pravo_mil_barrier_talk_started</give_info>', '')
Write-Text1251 $dialogsPath $dialogs

$pravoTasksPath = Join-Path $story 'config\gameplay\tasks_pravo.xml'
$pravoTasks = Read-Text1251 $pravoTasksPath
$pravoTasks = [regex]::Replace($pravoTasks, '(?s)\s*<game_task id="pravo_mil_barrier_task">.*?</game_task>', '')
Write-Text1251 $pravoTasksPath $pravoTasks

$pravoInfoPath = Join-Path $story 'config\gameplay\info_pravo.xml'
$pravoInfo = Read-Text1251 $pravoInfoPath
$pravoInfo = [regex]::Replace(
    $pravoInfo,
    '\s*<info_portion id="pravo_mil_[^"]+"(?:\s*/>|>.*?</info_portion>)',
    '',
    [System.Text.RegularExpressions.RegexOptions]::Singleline
)
Write-Text1251 $pravoInfoPath $pravoInfo

$pravoArticlesPath = Join-Path $story 'config\gameplay\storyline_info_pravo.xml'
$pravoArticles = Read-Text1251 $pravoArticlesPath
$pravoArticles = [regex]::Replace($pravoArticles, '(?s)\s*<article id="pravo_mil_[^"]+".*?</article>', '')
Write-Text1251 $pravoArticlesPath $pravoArticles

Write-Host 'Story overlay master configs updated.'
