param([string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference = 'Stop'
$encoding = [System.Text.Encoding]::GetEncoding(1251)
$source = Join-Path $ProjectRoot 'vanilla-reference\config\gameplay'
$target = Join-Path $ProjectRoot 'story\gamedata\config\gameplay'

# Keep the original IDs: simulation/conditions may reference them. Remove
# automatic task grants and gate story conversations instead of deleting IDs.
$taskGrants = 0
$dialogCount = 0
foreach ($file in Get-ChildItem -LiteralPath $source -Filter '*.xml') {
    $text = [IO.File]::ReadAllText($file.FullName, $encoding)
    $changed = $false
    if ($text -match '<game_information_portions>') {
        $taskGrants += [regex]::Matches($text, '<task>.*?</task>').Count
        $text = [regex]::Replace($text, '<task>.*?</task>', '')
        $changed = $true
    }
    if ($text -match '<game_dialogs>') {
        $text = [regex]::Replace($text, '<dialog\s+id="([^"]+)"[^>]*>', {
            param($match)
            $id = $match.Groups[1].Value
            if ($id -like 'dm_*' -or $id -eq 'actor_break_dialog') {
                return $match.Value
            }
            return $match.Value + "`r`n<precondition>pravo_story.vanilla_story_disabled</precondition>"
        })
        $dialogCount += [regex]::Matches($text, 'pravo_story.vanilla_story_disabled').Count
        $changed = $true
    }
    if ($changed) {
        $text = [regex]::Replace($text, '(?m)^[\t ]+\r?$', '')
        [IO.File]::WriteAllText((Join-Path $target $file.Name), $text, $encoding)
    }
}
$jobsPath = Join-Path $ProjectRoot 'story\gamedata\config\misc\task_manager.ltx'
$jobs = [IO.File]::ReadAllText($jobsPath, $encoding)
$activeJobs = "[list]`r`npravo_rad_artifact_medusa`r`npravo_rad_artifact_flower`r`npravo_rad_artifact_blood`r`npravo_rad_artifact_meat`r`n`r`n"
$jobs = [regex]::Replace($jobs, '(?ms)^\[list\].*?(?=^\[|\z)', $activeJobs)
[IO.File]::WriteAllText($jobsPath, $jobs, $encoding)
Write-Host "Vanilla story disabled: $taskGrants automatic task grants, $dialogCount story/job dialogues."
