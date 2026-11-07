param(
    [string]$GameDir = (Join-Path $PSScriptRoot 'game'),
    [string]$CacheDir
)

$ErrorActionPreference = 'Stop'
$game = (Resolve-Path -LiteralPath $GameDir).Path
$data = Join-Path $game 'gamedata'
$fsPath = Join-Path $game 'fsgame.ltx'
$utf8 = [Text.UTF8Encoding]::new($false)
$runtime = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'deploy/runtime.json') -Raw | ConvertFrom-Json

function Assert-GameClosed {
    if (Get-Process -Name xrEngine -ErrorAction SilentlyContinue) { throw 'Close OGSR before installing.' }
}

Assert-GameClosed
foreach ($required in @('bin_x64/xrEngine.exe', 'fsgame.ltx') + @(('0','1','2','3','4','5','6','7','8','9','a','b') | ForEach-Object { 'gamedata.db' + $_ })) {
    if (!(Test-Path -LiteralPath (Join-Path $game $required) -PathType Leaf)) {
        throw "Missing $required in $game. Pass the folder of an installed OGSR for Shadow of Chernobyl 1.0006."
    }
}
if ((Get-FileHash -LiteralPath (Join-Path $game 'gamedata.dbb')).Hash -ne $runtime.base_dbb_sha256) {
    throw 'This gamedata.dbb differs from the base used to compile the story. Use the same SoC 1.0006 base as the development PC.'
}
if (Test-Path -LiteralPath (Join-Path $data 'scripts/amk.script') -PathType Leaf) {
    throw 'This gamedata contains the old AMK scripts. Select a clean OGSR installation or the existing Pravo OGSR installation.'
}
$fs = [IO.File]::ReadAllText($fsPath)
if ($fs -notmatch '(?mi)^\$game_data\$[ \t]*=[^\r\n]+\|[ \t]*gamedata[\\/]?[ \t]*\r?$' -or
    $fs -notmatch '(?mi)^\$game_config\$[ \t]*=[^\r\n]+\|[ \t]*config[\\/]?[ \t]*\r?$') {
    throw 'fsgame.ltx must use the standard gamedata and config folders for OGSR SoC.'
}
$story = Join-Path $PSScriptRoot 'story/gamedata'
if ((Get-FileHash -LiteralPath (Join-Path $story 'game.graph')).Hash -ne $runtime.game_graph_sha256) {
    throw 'The game graph and the exported story must be updated together.'
}
foreach ($file in $runtime.files) {
    $source = Join-Path $PSScriptRoot $file.source
    if ((Get-FileHash -LiteralPath $source).Hash -ne $file.sha256) { throw "Runtime file checksum mismatch: $($file.source)" }
}

if (!$CacheDir) { $CacheDir = Join-Path $game '_pravo_downloads' }
$CacheDir = [IO.Path]::GetFullPath($CacheDir)
New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null
$lock = [IO.File]::Open((Join-Path $game '.pravo-install.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
try {
    $metadata = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'tools/assets/atmospherics/source.json') -Raw | ConvertFrom-Json
    $media = $metadata.archives | Where-Object { $_.extract_to -eq 'base' } | Select-Object -First 1
    $archive = Join-Path $CacheDir $media.filename
    if (!(Test-Path -LiteralPath $archive -PathType Leaf)) {
        Write-Host 'Downloading Atmospherics textures and sounds (1.3 GB)...'
        & curl.exe --fail --location --retry 3 --output "$archive.partial" $media.download_url
        if ($LASTEXITCODE -ne 0) { throw 'Atmospherics download failed. Retry the installer.' }
        if ((Get-FileHash -LiteralPath "$archive.partial").Hash -ne $media.sha256) { throw 'Downloaded archive checksum mismatch.' }
        Move-Item -LiteralPath "$archive.partial" -Destination $archive
    } elseif ((Get-FileHash -LiteralPath $archive).Hash -ne $media.sha256) {
        throw "Archive checksum mismatch: $archive"
    }
    $extracted = Join-Path $CacheDir 'base'
    $mediaRoot = Join-Path $extracted 'gamedata'
    $marker = Join-Path $extracted '.archive-sha256'
    if (!(Test-Path -LiteralPath $marker -PathType Leaf) -or (Get-Content -LiteralPath $marker -Raw).Trim() -ne $media.sha256 -or
        !(Test-Path -LiteralPath (Join-Path $mediaRoot 'textures/sky') -PathType Container) -or
        !(Test-Path -LiteralPath (Join-Path $mediaRoot 'sounds/ambient') -PathType Container)) {
        New-Item -ItemType Directory -Path $extracted -Force | Out-Null
        Write-Host 'Extracting Atmospherics media...'
        & tar.exe -xf $archive -C $extracted gamedata/textures gamedata/sounds
        if ($LASTEXITCODE -ne 0) { throw 'Atmospherics extraction failed.' }
        [IO.File]::WriteAllText($marker, $media.sha256, $utf8)
    }

    Assert-GameClosed
    $backup = Join-Path $game ('_backups/pravo-transfer-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
    New-Item -ItemType Directory -Path $backup -Force | Out-Null
    $sources = [Collections.Generic.Dictionary[string,string]]::new([StringComparer]::OrdinalIgnoreCase)
    function Add-Overlay([string]$From, [string]$To) {
        foreach ($file in (Get-ChildItem -LiteralPath $From -Recurse -File)) {
            $sources[(Join-Path $To $file.FullName.Substring($From.Length + 1))] = $file.FullName
        }
    }
    foreach ($folder in @('textures','sounds')) {
        Add-Overlay (Join-Path $mediaRoot $folder) (Join-Path $data $folder)
    }
    Add-Overlay $story $data
    foreach ($file in $runtime.files) {
        $sources[(Join-Path $data $file.path)] = Join-Path $PSScriptRoot $file.source
    }
    foreach ($alias in @('game_weathers', 'game_weather_effects')) {
        $folder = if ($alias -eq 'game_weathers') { 'weathers' } else { 'weather_effects' }
        $line = '${0}$ = true| false| $game_config$| environment\{1}\' -f $alias, $folder
        $pattern = '(?mi)^\$' + $alias + '\$[^\r\n]*'
        if ([regex]::IsMatch($fs, $pattern)) { $fs = [regex]::Replace($fs, $pattern, [Text.RegularExpressions.MatchEvaluator]{ $line }) }
        else { $fs = $fs.TrimEnd() + "`r`n" + $line + "`r`n" }
    }
    $preparedFs = Join-Path $backup 'new-fsgame.ltx'
    [IO.File]::WriteAllText($preparedFs, $fs, $utf8)
    $sources[$fsPath] = $preparedFs
    $userPath = Join-Path $game '_appdata_/user_ogsr.ltx'
    if (Test-Path -LiteralPath $userPath -PathType Leaf) {
        $user = [IO.File]::ReadAllText($userPath)
        $preset = Join-Path $story 'config/rspec_atmospherics.ltx'
        foreach ($setting in (Get-Content -LiteralPath $preset | Where-Object { $_ -match '^[a-zA-Z_]' })) {
            $key = ($setting -split '[ \t]+', 2)[0]
            $pattern = '(?mi)^' + [regex]::Escape($key) + '[ \t]+[^\r\n]*'
            if ([regex]::IsMatch($user, $pattern)) { $user = [regex]::Replace($user, $pattern, [Text.RegularExpressions.MatchEvaluator]{ $setting }) }
            else { $user = $user.TrimEnd() + "`r`n" + $setting + "`r`n" }
        }
        $preparedUser = Join-Path $backup 'new-user_ogsr.ltx'
        [IO.File]::WriteAllText($preparedUser, $user, $utf8)
        $sources[$userPath] = $preparedUser
    }

    $changes = [Collections.Generic.List[object]]::new()
    function Update-GameFile([string]$Target, [string]$Source) {
        $targetPath = [IO.Path]::GetFullPath($Target)
        $gamePrefix = $game.TrimEnd('\') + '\'
        if (!$targetPath.StartsWith($gamePrefix, [StringComparison]::OrdinalIgnoreCase)) { throw "Invalid game path: $Target" }
        if (Test-Path -LiteralPath $targetPath -PathType Container) { throw "Expected a file, found a folder: $targetPath" }
        $previous = $null
        if (Test-Path -LiteralPath $targetPath -PathType Leaf) {
            if ($Source -and (Get-Item -LiteralPath $targetPath).Length -eq (Get-Item -LiteralPath $Source).Length -and
                (Get-FileHash -LiteralPath $targetPath).Hash -eq (Get-FileHash -LiteralPath $Source).Hash) { return }
            $previous = Join-Path $backup ('original/' + $targetPath.Substring($gamePrefix.Length))
            New-Item -ItemType Directory -Path (Split-Path -Parent $previous) -Force | Out-Null
            Copy-Item -LiteralPath $targetPath -Destination $previous -Force
        } elseif (!$Source) { return }
        $changes.Add([pscustomobject]@{ Target = $targetPath; Previous = $previous })
        if ($Source) {
            New-Item -ItemType Directory -Path (Split-Path -Parent $targetPath) -Force | Out-Null
            Copy-Item -LiteralPath $Source -Destination $targetPath -Force
        } else { Remove-Item -LiteralPath $targetPath -Force }
    }

    Write-Host "Installing the compiled story and Atmospherics into $game ..."
    try {
        foreach ($entry in $sources.GetEnumerator()) { Update-GameFile $entry.Key $entry.Value }
        foreach ($retired in (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'tools/retired_files.txt'))) {
            Update-GameFile (Join-Path $data $retired) ''
        }
    } catch {
        for ($i = $changes.Count - 1; $i -ge 0; $i--) {
            $change = $changes[$i]
            if ($change.Previous) { Copy-Item -LiteralPath $change.Previous -Destination $change.Target -Force -ErrorAction Continue }
            elseif (Test-Path -LiteralPath $change.Target -PathType Leaf) { Remove-Item -LiteralPath $change.Target -Force -ErrorAction Continue }
        }
        throw
    }
    [IO.File]::WriteAllText((Join-Path $backup 'changes.json'), (ConvertTo-Json -InputObject @($changes.ToArray()) -Depth 3), $utf8)
    Write-Host "Installed. Backup: $backup"
    Write-Host 'Start OGSR from this game folder. Start a NEW GAME to get the new traitor quest.'
} finally { $lock.Dispose() }
