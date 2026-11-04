param(
    [Parameter(Mandatory)][ValidatePattern('^[a-zA-Z0-9_]+$')][string]$Level,
    [ValidateSet('Geometry','AI','VerifyAI','Details','Spawn')][string]$Stage = 'Geometry',
    [switch]$Draft,
    [ValidateRange(1,64)][int]$Threads = 8,
    [string[]]$SpawnLevels
)
$ErrorActionPreference = 'Stop'
$sdk = $PSScriptRoot
$compiler = Join-Path $sdk 'bin\compilers_sky_x64\xrCompiler.exe'
$levelPath = Join-Path $sdk ('gamedata\levels\' + $Level)
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$logName = $Level + '_' + $Stage.ToLowerInvariant() + '_' + $stamp
$logPath = Join-Path $sdk ('logs\' + $logName + '.log')
# This compiler's legacy fsltx parser retains quotes. Use the short ASCII SDK path.
if ($sdk -match '\s') { throw 'Place the SDK in a path without spaces, such as C:\razrabotka\ogsr-sdk.' }
$compileArgs = @('-version','shoc','-fsltx',(Join-Path $sdk 'fsgame.ltx'),'-both_texture_pathes','-t',"$Threads",'-log_name',$logName,'-silent')
switch ($Stage) {
    Geometry {
        if (-not (Test-Path (Join-Path $levelPath 'build.prj'))) { throw 'Use Build > Build Scene in Level Editor first (build.prj is missing).' }
        $compileArgs += @('-geometry','-f',$Level,'-removeinvalid','-nosmg')
        if ($Draft) { $compileArgs += @('-nohemi','-noise') } else { $compileArgs += '-static' }
    }
    AI {
        if (-not (Test-Path (Join-Path $levelPath 'build.aimap'))) { throw 'Export the AI map from Level Editor first (build.aimap is missing).' }
        $compileArgs += @('-aispawn','-f',$Level)
        if ($Draft) { $compileArgs += '-draft' }
    }
    VerifyAI { $compileArgs += @('-aispawn','-f',$Level,'-verify','-noverbose') }
    Details { $compileArgs += @('-details','-f',$Level); if ($Draft) { $compileArgs += '-nohemi' } else { $compileArgs += '-static' } }
    Spawn {
        if (-not $SpawnLevels) { $SpawnLevels = @($Level) }
        foreach ($name in $SpawnLevels) { if ($name -notmatch '^[a-zA-Z0-9_]+$') { throw "Invalid level name: $name" } }
        $compileArgs += @('-aispawn','-s',($SpawnLevels -join ','),'-out',($Level + '_sdk'))
        $versions = foreach ($name in $SpawnLevels) {
            $ai = Join-Path $sdk ('gamedata\levels\' + $name + '\level.ai')
            if (-not (Test-Path $ai)) { throw "Compile AI first: $name" }
            $stream = [IO.File]::OpenRead($ai)
            try { $reader = [IO.BinaryReader]::new($stream); $reader.ReadUInt32() } finally { $stream.Dispose() }
        }
        if (@($versions | Select-Object -Unique).Count -ne 1) { throw 'Spawn levels use different AI formats. Rebuild them with the same AI map format.' }
        if ($versions[0] -ge 13) { $compileArgs += '-large_aimap' }
    }
}
if (Get-Process xrCompiler -ErrorAction SilentlyContinue) { throw 'Another level compiler is running. Wait for it to finish.' }
Write-Host "Compiling $Level ($Stage). Log: $logPath"
$process = Start-Process -FilePath $compiler -ArgumentList $compileArgs -WorkingDirectory $sdk -WindowStyle Hidden -PassThru
$startup = [Diagnostics.Stopwatch]::StartNew()
while (-not $process.WaitForExit(500)) {
    if ($startup.Elapsed.TotalSeconds -gt 45 -and -not (Test-Path $logPath)) {
        Stop-Process -Id $process.Id
        throw 'Compiler startup failed before creating its log. Check fsgame.ltx and runtime DLLs.'
    }
}
if (-not (Test-Path $logPath)) { throw "Compiler did not create a log (exit $($process.ExitCode))." }
$log = Get-Content -LiteralPath $logPath -Raw
if ($process.ExitCode -ne 0 -or $log -match '(?im)FATAL ERROR|\[error\]Expression' -or $log -notmatch '(?i)Build succes+ful!|Build successful!|verification.*success|successfully') {
    Get-Content -LiteralPath $logPath -Tail 35
    throw "Compilation failed. See $logPath"
}
if ($Stage -eq 'Geometry') {
    foreach ($file in @('level','level.geom','level.cform')) {
        if (-not (Test-Path (Join-Path $levelPath $file))) { throw "Output missing: $file" }
    }
    $hashes = @{}; foreach ($file in @('level','level.geom','level.cform')) { $hashes[$file] = (Get-FileHash (Join-Path $levelPath $file)).Hash }
    [pscustomobject]@{ Level=$Level; Stage=$Stage; Draft=[bool]$Draft; Log=$logPath; Hashes=$hashes; Completed=(Get-Date).ToString('o') } |
        ConvertTo-Json | Set-Content (Join-Path $levelPath 'sdk-build.json') -Encoding UTF8
}
Write-Host "BUILD OK: $Level ($Stage)"
