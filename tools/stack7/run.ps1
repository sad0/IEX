# Stack7 feature probe runner: the same probe (probe/M_ST7.lua) on the same save, in a full-mod copy under EEex and
# in the same copy under IEX, then compare.py.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\stack7\run.ps1 [-Sides eeex,iex] [-Runs 2]
# Copies: testgame\stack7-eeex / stack7-iex (make_copy.py of full-win-0.3.0b; EEex's loader, DLLs, EEex_scripts and
# override files copied in from the trap-eeex copy; both InfinityLoader.ini LuaPatchMode=INTERNAL). Each has its own
# Documents folder. Only processes started from these copies are ever closed. Popups: the process is killed at once.
param(
    [string[]]$Sides = @('eeex', 'iex'),
    [int]$Runs = 1,
    [int]$Timeout = 300,
    [string]$Build = "E:\Dev\IEX-wt-stack7\build",
    [string]$Repo = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent),
    [string]$SaveFrom = "$([Environment]::GetFolderPath('MyDocuments'))\Baldur's Gate II - Enhanced Edition (IEX 0.3.0 full b)",
    [string]$SaveName = "000000099-IEXRT",
    [string]$OutDir = "E:\Dev\IEX-data\stack7\$(Get-Date -Format yyyy-MM-dd-HHmm)",
    [switch]$NoCompare,
    # override files (wildcards) moved to override_off for this run only (bisecting a crash), EEex side only
    [string[]]$Off = @()
)
$ErrorActionPreference = 'Stop'
$env:IEX_SKIP_INTRO = '1'
$Sides = @($Sides | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
$here = $PSScriptRoot
$docs = [Environment]::GetFolderPath('MyDocuments')
New-Item -ItemType Directory -Force $OutDir | Out-Null
# the window helpers of the difftest runner (off-screen window, background keys, popup detection)
$dt = Get-Content "$Repo\tools\difftest\run.ps1" -Raw
$start = $dt.IndexOf('Add-Type -AssemblyName System.Drawing')
$end = $dt.IndexOf('function Get-OwnProcs')
Invoke-Expression $dt.Substring($start, $end - $start)

function Get-OwnProcs($dir) {
    Get-Process -ErrorAction SilentlyContinue | Where-Object { $path = $_.Path; $path -and $path.StartsWith($dir, 'OrdinalIgnoreCase') }
}
function Get-Status($copy) {
    foreach ($f in "$copy\st7_status.txt", "$copy\IEX\st7_status.txt") {
        if (Test-Path $f) { return (Get-Content $f -Raw).Trim() }
    }
    if (Test-Path "$copy\st7_loader.log") {
        $l = Select-String -Path "$copy\st7_loader.log" -Pattern 'ST7\|STATUS (.*)' | Select-Object -Last 1
        if ($l) { return $l.Matches[0].Groups[1].Value.Trim() }
    }
    return ''
}

function Prepare-Side($side) {
    $copy = "E:\Dev\IEX-data\testgame\stack7-$side"
    if (-not (Test-Path "$copy\chitin.key")) { throw "missing copy $copy" }
    $label = if ($side -eq 'eeex') { 'EEex' } else { 'IEX' }
    $engineName = "Baldur's Gate II - Enhanced Edition (IEX stack7 $label)"
    Set-Content "$copy\engine.lua" "engine_name = `"$engineName`"`r`nengine_mode = 1 -- 0 = BGEE, 1 = BG2EE, 2 = IWDEE`r`nlang_dir = en_US" -Encoding ascii
    Copy-Item "$here\probe\M_ST7.lua", "$here\probe\ST7.menu" "$copy\override\" -Force
    # files a previous bisect run moved out come back first
    Get-ChildItem "$copy\override_bisect" -File -ErrorAction SilentlyContinue | Move-Item -Destination "$copy\override\" -Force
    if ($Off.Count) {
        New-Item -ItemType Directory -Force "$copy\override_bisect" | Out-Null
        foreach ($pat in ($Off | ForEach-Object { $_ -split ',' })) { Get-ChildItem "$copy\override\$pat" -File | Move-Item -Destination "$copy\override_bisect\" -Force }
    }
    if ($side -eq 'iex') {
        Remove-Item "$copy\IEX.dll", "$copy\IEXLauncher.exe" -Force -ErrorAction SilentlyContinue
        Copy-Item "$Build\IEX.dll", "$Build\IEXLauncher.exe" $copy -Force
        New-Item -ItemType Directory -Force "$copy\IEX\engine" | Out-Null
        Copy-Item "$Repo\lua\*.lua" "$copy\IEX\" -Force
        Copy-Item "$Repo\ui\*.menu" "$copy\override\" -Force
        Copy-Item "$Repo\engine\*.iexd" "$copy\IEX\engine\" -Force
        & python -I "$Repo\tools\compat\api_list.py" "$copy\IEX\IEX_API.txt" | Out-Null
    }
    return @{ copy = $copy; docs = "$docs\$engineName" }
}

function Reset-Docs($d) {
    New-Item -ItemType Directory -Force "$d\save" | Out-Null
    Get-ChildItem "$d\save" -Directory | Remove-Item -Recurse -Force
    Copy-Item "$SaveFrom\save\$SaveName" "$d\save\000000099-IEXRT" -Recurse -Force
    $latin1 = [Text.Encoding]::GetEncoding(28591)
    $ini = [IO.File]::ReadAllLines("$SaveFrom\Baldur.lua", $latin1) | Where-Object { $_ -notmatch "Disable Movies|'Language'" }
    # English on both sides (the seed's French would make the engine restart itself)
    $seed = "SetPrivateProfileString('Program Options','Disable Movies','1')`r`nSetPrivateProfileString('Language','Text','en_US')"
    [IO.File]::WriteAllText("$d\Baldur.lua", (($ini -join "`r`n") + "`r`n" + $seed + "`r`n"), $latin1)
}

function Run-Once($side, $p, $n) {
    $copy = $p.copy
    if (Get-OwnProcs $copy) { Get-OwnProcs $copy | Stop-Process -Force; Start-Sleep 2 }
    Reset-Docs $p.docs
    Remove-Item "$copy\st7_out.txt", "$copy\st7_status.txt", "$copy\IEX\st7_out.txt", "$copy\IEX\st7_status.txt", "$copy\st7_loader.log", "$copy\IEX.log" -ErrorAction SilentlyContinue
    $exe = if ($side -eq 'eeex') { "$copy\InfinityLoader.exe" } else { "$copy\IEXLauncher.exe" }
    $crashBefore = @(Get-ChildItem "$copy\InfinityLoader_Crash\*.log", "$copy\IEX_crash*" -ErrorAction SilentlyContinue).Count
    Start-Process $exe -WorkingDirectory $copy -WindowStyle Minimized
    $t0 = Get-Date; $lastKey = $t0; $muted = $false; $result = 'timeout'; $minimized = @{}; $shots = @{}
    while (((Get-Date) - $t0).TotalSeconds -lt $Timeout) {
        Start-Sleep -Milliseconds 250
        $procs = @(Get-OwnProcs $copy)
        foreach ($pr in $procs) {
            foreach ($w in [DiffTWin]::Windows([uint32]$pr.Id)) {
                $h, $cls, $title = $w.Split('|', 3)
                if ($cls -ne 'SDL_app' -and $cls -ne 'ConsoleWindowClass' -and $cls -ne 'CASCADIA_HOSTING_WINDOW_CLASS') {
                    $png = "$OutDir\$side-run$n-popup.png"
                    try { [void][DiffTWin]::Shot([IntPtr][int64]$h, $png) } catch {}
                    Get-OwnProcs $copy | Stop-Process -Force -ErrorAction SilentlyContinue
                    "  popup in $($pr.ProcessName): '$title' -> our process closed"
                    $result = "popup: $title"
                } elseif ($pr.ProcessName -eq 'Baldur' -and -not $minimized[$h]) {
                    [DiffTWin]::OffScreen([IntPtr][int64]$h)
                    $minimized[$h] = $true
                }
            }
        }
        $crashNow = @(Get-ChildItem "$copy\InfinityLoader_Crash\*.log", "$copy\IEX_crash*" -ErrorAction SilentlyContinue).Count
        if ($crashNow -gt $crashBefore) {
            Get-OwnProcs $copy | Stop-Process -Force -ErrorAction SilentlyContinue
            "  crash log written -> our process closed"
            $result = 'popup: crash log'
        }
        if ($result -like 'popup*') { break }
        if (-not $muted -and ($procs | Where-Object ProcessName -eq 'Baldur')) {
            Start-Sleep 3
            & powershell -NoProfile -ExecutionPolicy Bypass -File "$Repo\tools\windows\mute_games.ps1" | Out-Null
            $muted = $true
        }
        $st = Get-Status $copy
        if (($st -like '*screen ready*' -or $st -like 'loading*' -or $st -like 'main file*' -or $st -like 'opening*') -and ((Get-Date) - $lastKey).TotalSeconds -ge 3) {
            foreach ($h in @($minimized.Keys)) { [DiffTWin]::F11([IntPtr][int64]$h) }
            $lastKey = Get-Date
        }
        if ($st -like 'hold *' -and -not $shots[$st]) {
            $shots[$st] = $true
            Start-Sleep -Milliseconds 500
            foreach ($h in @($minimized.Keys)) { try { [void][DiffTWin]::Shot([IntPtr][int64]$h, "$OutDir\$side-run$n-$($st -replace '[^\w]', '_').png") } catch {} }
        }
        if ($st -like 'DONE*') { $result = 'done'; break }
        if ($st -like 'save not found*' -or $st -like 'probe load error*') { $result = $st; break }
        if ($procs.Count -eq 0 -and ((Get-Date) - $t0).TotalSeconds -gt 20) { $result = "exited ($st)"; break }
    }
    $st = Get-Status $copy
    if ($result -eq 'timeout') {
        $png = "$OutDir\$side-run$n-timeout.png"
        foreach ($h in @($minimized.Keys)) { try { [void][DiffTWin]::Shot([IntPtr][int64]$h, $png) } catch {} }
    }
    Get-OwnProcs $copy | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep 2
    $dest = "$OutDir\$side-run$n.txt"
    if (Test-Path "$copy\st7_out.txt") { Copy-Item "$copy\st7_out.txt" $dest -Force }
    elseif (Test-Path "$copy\IEX\st7_out.txt") { Copy-Item "$copy\IEX\st7_out.txt" $dest -Force }
    elseif (Test-Path "$copy\st7_loader.log") {
        $l = [Collections.Generic.List[string]]::new()
        foreach ($x in (Get-Content "$copy\st7_loader.log" -Encoding utf8)) {
            if ($x -match 'ST7\|(?!STATUS)') { $l.Add($x.Substring($x.IndexOf('ST7|') + 4)) }
            elseif ($x -match 'ST7~\|' -and $l.Count) { $l[$l.Count - 1] += $x.Substring($x.IndexOf('ST7~|') + 5) }
        }
        [IO.File]::WriteAllLines($dest, [string[]]@($l))
    } else { Set-Content $dest '' }
    if (Test-Path "$copy\st7_loader.log") { Copy-Item "$copy\st7_loader.log" "$OutDir\$side-run$n.loader.log" -Force }
    if (Test-Path "$copy\IEX.log") { Copy-Item "$copy\IEX.log" "$OutDir\$side-run$n.IEX.log" -Force }
    if (Test-Path "$copy\IEX\missing_api.txt") { Copy-Item "$copy\IEX\missing_api.txt" "$OutDir\$side-run$n.missing_api.txt" -Force }
    $lines = (Get-Content $dest | Measure-Object -Line).Lines
    "$side run $n : $result, status '$st', $lines lines, $([int]((Get-Date) - $t0).TotalSeconds) s"
}

foreach ($side in $Sides) {
    $p = Prepare-Side $side
    for ($n = 1; $n -le $Runs; $n++) { Run-Once $side $p $n }
}
if (-not $NoCompare) { & python -I "$here\compare.py" $OutDir }
