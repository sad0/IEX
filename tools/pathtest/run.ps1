# Pathfinding test: runs the pathtest probe (tools/pathtest/probe) on the same save under
#   vanilla  (IEX copy, IEX_PATHFINDING=0: IEX loaded, the native policy off = the engine's own pathfinding),
#   iex      (IEX copy, BG Pathfinding Redux installed, IEX's native policy on),
#   eeex     (EEex copy, BG Pathfinding Redux installed and running on EEex),
# and writes <OutDir>\<side>-run<n>.txt (one line per mover and scenario, see probe/pth_body.lua).
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\pathtest\run.ps1 [-Sides vanilla,iex,eeex] [-StressMs 900000]
# Private copies of the test base (tools/difftest/make_copy.py), own Documents folders. Only processes started from
# the copies are ever closed. No startup movies (IEX_SKIP_INTRO + 'Disable Movies'), games off screen and muted.
param(
    [string]$Base = "E:\Dev\IEX-data\testgame\eet-2.7.3",
    [string]$SaveFrom = "$([Environment]::GetFolderPath('MyDocuments'))\Baldur's Gate - Enhanced Edition Trilogy (IEX asm-eeex)",
    [string]$SaveName = "000000009-Chapter 2 Start",
    [string]$Mod = "E:\Dev\IEX-data\mods\pathfinding-redux\src\zach-hopkins-bg-pathfinding-redux-35cc0a9\bg-redux-movement",
    [string]$EEexMain = "E:\Enhanced Edition\Environnement de test\EET 2.7.3 (dev)\override\M___EEex.lua",
    # WeiDU binary (any setup-*.exe is WeiDU); default: the first one in the copy, else this one.
    [string]$WeiDU = "E:\Dev\IEX-data\testgame\eet-2.7.3\setup-PartyStash.exe",
    [string]$Build = "",
    [string[]]$Sides = @('vanilla', 'iex', 'eeex'),
    [int]$Runs = 1,
    [int]$StressMs = 120000,
    [int]$LongDX = 600,
    [int]$LongDY = 0,
    [int]$Timeout = 0,
    [switch]$Refresh,
    [string]$Tag = 'path',
    [string]$Repo = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent),
    [string]$OutDir = ""
)
$ErrorActionPreference = 'Stop'
$env:IEX_SKIP_INTRO = '1'
$Sides = @($Sides | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
$here = "$Repo\tools\pathtest"
$docs = [Environment]::GetFolderPath('MyDocuments')
if (-not $Build) { $Build = "$Repo\build" }
if (-not $OutDir) { $OutDir = "E:\Dev\IEX-data\pathtest\$(Get-Date -Format yyyy-MM-dd-HHmm)" }
if ($Timeout -le 0) { $Timeout = 300 + [int]($StressMs / 1000) }
New-Item -ItemType Directory -Force $OutDir | Out-Null
# M_ files that drive the game or need IEX only: out of both copies.
$offFiles = 'M_I3CAM.lua', 'M_I3MOVE.lua', 'M_I3NET.lua', 'M_IEXTST.lua', 'M_ZMEMT.lua', 'M_BGBOT.lua', 'M_BGBCMB.lua',
    'M_IEXFPS.lua', 'M_IEXSPL.lua', 'M_DIFFT.lua', 'M_DIFFTA.lua'

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class PthWin {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int l, t, r, b; }
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int x, y; }
    [StructLayout(LayoutKind.Sequential)] public struct WINDOWPLACEMENT {
        public int length, flags, showCmd; public POINT minPos, maxPos; public RECT normal; }
    [DllImport("user32.dll")] public static extern bool GetWindowPlacement(IntPtr h, ref WINDOWPLACEMENT wp);
    [DllImport("user32.dll")] public static extern bool SetWindowPlacement(IntPtr h, ref WINDOWPLACEMENT wp);
    public static void OffScreen(IntPtr h) {
        var wp = new WINDOWPLACEMENT(); wp.length = Marshal.SizeOf(wp);
        GetWindowPlacement(h, ref wp);
        int w = wp.normal.r - wp.normal.l, ht = wp.normal.b - wp.normal.t;
        wp.normal.l = -6000; wp.normal.t = -6000; wp.normal.r = -6000 + w; wp.normal.b = -6000 + ht;
        wp.showCmd = 4;
        SetWindowPlacement(h, ref wp);
    }
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc f, IntPtr l);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, System.Text.StringBuilder s, int n);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr h, System.Text.StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    public static void F11(IntPtr h) {
        PostMessage(h, 0x100, (IntPtr)0x7A, (IntPtr)(1 | (0x57 << 16)));
        System.Threading.Thread.Sleep(60);
        PostMessage(h, 0x101, (IntPtr)0x7A, (IntPtr)unchecked((int)(0xC0000001 | (0x57 << 16))));
    }
    public static string[] Windows(uint pid) {
        var list = new System.Collections.Generic.List<string>();
        EnumWindows((h, l) => {
            uint p; GetWindowThreadProcessId(h, out p);
            if (p == pid && IsWindowVisible(h)) {
                var t = new System.Text.StringBuilder(256); GetWindowText(h, t, 256);
                var c = new System.Text.StringBuilder(256); GetClassName(h, c, 256);
                list.Add(h.ToInt64().ToString() + "|" + c.ToString() + "|" + t.ToString());
            }
            return true;
        }, IntPtr.Zero);
        return list.ToArray();
    }
}
"@

function Get-OwnProcs($dir) {
    Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path.StartsWith($dir, 'OrdinalIgnoreCase') }
}

function Get-Status($copy) {
    foreach ($f in "$copy\pathtest_status.txt", "$copy\IEX\pathtest_status.txt") {
        if (Test-Path $f) { return (Get-Content $f -Raw).Trim() }
    }
    if (Test-Path "$copy\pathtest_loader.log") {
        $l = Select-String -Path "$copy\pathtest_loader.log" -Pattern 'PTH\|STATUS (.*)' | Select-Object -Last 1
        if ($l) { return $l.Matches[0].Groups[1].Value.Trim() }
    }
    return ''
}

# WeiDU install of BG Pathfinding Redux component 0, with the guards: weidu.conf, --language 0, no pause, no
# auto-update, stdin from NUL, 10 min timeout, log size limit (a prompt loop is killed).
function Install-Mod($copy) {
    if (Test-Path "$copy\override\M_BGREDX.lua") { return }
    if (Test-Path "$copy\bg-redux-movement") { Remove-Item "$copy\bg-redux-movement" -Recurse -Force }
    Copy-Item $Mod "$copy\bg-redux-movement" -Recurse
    # install-time EEex checks accept IEX (docs/COMPAT_RULES.md); a no-op where EEex is installed
    & python -I "$Repo\tools\compat\patch_mod.py" "$copy\bg-redux-movement"
    $found = Get-ChildItem "$copy\setup-*.exe" | Where-Object Name -ne 'setup-bg-redux-movement.exe' | Select-Object -First 1
    $weiduExe = if ($found) { $found.FullName } else { $WeiDU }
    Copy-Item $weiduExe "$copy\setup-bg-redux-movement.exe" -Force
    Set-Content "$copy\weidu.conf" "lang_dir = en_us" -Encoding ascii
    $log = "$copy\pathtest_weidu.log"
    $p = Start-Process "$copy\setup-bg-redux-movement.exe" -WorkingDirectory $copy -PassThru -WindowStyle Hidden `
        -ArgumentList '--language', '0', '--force-install', '0', '--no-exit-pause', '--noautoupdate', '--log', 'pathtest_weidu.debug', 'bg-redux-movement/bg-redux-movement.tp2' `
        -RedirectStandardInput "$here\empty_stdin.txt" -RedirectStandardOutput $log -RedirectStandardError "$log.err"
    $t0 = Get-Date
    while (-not $p.HasExited) {
        Start-Sleep 1
        if (((Get-Date) - $t0).TotalSeconds -gt 600 -or ((Test-Path $log) -and (Get-Item $log).Length -gt 5MB)) {
            Stop-Process -Id $p.Id -Force; throw "WeiDU install stopped (timeout or runaway log) in $copy"
        }
    }
    if (-not (Test-Path "$copy\override\M_BGREDX.lua")) { Get-Content $log -Tail 20; throw "mod install failed in $copy" }
    "  BG Pathfinding Redux installed in $copy"
}

function Prepare-Copy($kind) {
    $copy = "E:\Dev\IEX-data\testgame\pathtest-$Tag-$kind"
    if ($Refresh -or -not (Test-Path "$copy\chitin.key")) {
        & python -I "$Repo\tools\difftest\make_copy.py" $Base $copy
        if ($LASTEXITCODE) { throw "copy failed" }
    }
    $label = if ($kind -eq 'eeex') { 'EEex' } else { 'IEX' }
    $engineName = "Baldur's Gate - Enhanced Edition Trilogy (IEX pathtest $Tag $label)"
    Set-Content "$copy\engine.lua" "engine_name = `"$engineName`"`r`nengine_mode = 1 -- 0 = BGEE, 1 = BG2EE, 2 = IWDEE" -Encoding ascii
    New-Item -ItemType Directory -Force "$copy\override_off" | Out-Null
    foreach ($f in $offFiles) { if (Test-Path "$copy\override\$f") { Move-Item "$copy\override\$f" "$copy\override_off\" -Force } }
    Install-Mod $copy
    & python -I "$here\install_probe.py" "$copy\override"
    if ($LASTEXITCODE) { throw "probe install failed" }
    if ($kind -eq 'eeex') {
        if (-not (Test-Path "$copy\override\M___EEex.lua")) { Copy-Item $EEexMain "$copy\override\M___EEex.lua" }
        $li = Get-Content "$copy\InfinityLoader.ini"
        $li = $li -replace '^LogFile=.*$', 'LogFile=pathtest_loader.log'
        Set-Content "$copy\InfinityLoader.ini" $li -Encoding ascii
    } else {
        Remove-Item "$copy\IEX.dll", "$copy\IEXLauncher.exe" -Force -ErrorAction SilentlyContinue
        Copy-Item "$Build\IEX.dll", "$Build\IEXLauncher.exe" $copy -Force
        New-Item -ItemType Directory -Force "$copy\IEX\engine" | Out-Null
        Copy-Item "$Repo\lua\*.lua" "$copy\IEX\" -Force
        Copy-Item "$Repo\ui\*.menu" "$copy\override\" -Force
        & python -I "$Repo\tools\compat\api_list.py" "$copy\IEX\IEX_API.txt" | Out-Null
        Copy-Item "$Repo\engine\*.iexd" "$copy\IEX\engine\" -Force
    }
    return @{ copy = $copy; docs = "$docs\$engineName" }
}

function Reset-Docs($d, $side) {
    New-Item -ItemType Directory -Force "$d\save" | Out-Null
    Get-ChildItem "$d\save" -Directory | Remove-Item -Recurse -Force
    Copy-Item "$SaveFrom\save\$SaveName" "$d\save\000000098-PATHTEST" -Recurse -Force
    $latin1 = [Text.Encoding]::GetEncoding(28591)
    $ini = @()
    if (Test-Path "$SaveFrom\Baldur.lua") {
        $ini = [IO.File]::ReadAllLines("$SaveFrom\Baldur.lua", $latin1) | Where-Object { $_ -notmatch "^SetPrivateProfileString\('(PathTest|DiffTest)'" }
    }
    $seed = "SetPrivateProfileString('Program Options','Disable Movies','1')`r`n" +
        "SetPrivateProfileString('PathTest','StressMs','$StressMs')`r`n" +
        "SetPrivateProfileString('PathTest','LongDX','$LongDX')`r`nSetPrivateProfileString('PathTest','LongDY','$LongDY')"
    # option0 / option1: the IEX option in Baldur.lua decides (no IEX_PATHFINDING)
    if ($side -like 'option*') { $seed += "`r`nSetPrivateProfileString('IEX','Pathfinding Redux','$($side.Substring(6))')" }
    [IO.File]::WriteAllText("$d\Baldur.lua", (($ini -join "`r`n") + "`r`n" + $seed + "`r`n"), $latin1)
}

function Run-Once($side, $p, $n) {
    $copy = $p.copy
    if (Get-OwnProcs $copy) { Get-OwnProcs $copy | Stop-Process -Force; Start-Sleep 2 }
    Reset-Docs $p.docs $side
    Remove-Item "$copy\pathtest_out.txt", "$copy\pathtest_status.txt", "$copy\IEX\pathtest_out.txt", "$copy\IEX\pathtest_status.txt", "$copy\pathtest_loader.log" -ErrorAction SilentlyContinue
    $env:IEX_PATHFINDING = if ($side -eq 'vanilla') { '0' } elseif ($side -like 'option*') { '' } else { '1' }
    $exe = if ($side -eq 'eeex') { "$copy\InfinityLoader.exe" } else { "$copy\IEXLauncher.exe" }
    Start-Process $exe -WorkingDirectory $copy -WindowStyle Minimized
    $t0 = Get-Date; $lastKey = $t0; $muted = $false; $result = 'timeout'; $off = @{}; $menuAt = $null
    while (((Get-Date) - $t0).TotalSeconds -lt $Timeout) {
        Start-Sleep -Milliseconds 400
        $procs = @(Get-OwnProcs $copy)
        foreach ($pr in $procs) {
            foreach ($w in [PthWin]::Windows([uint32]$pr.Id)) {
                $h, $cls, $title = $w.Split('|', 3)
                if ($cls -eq '#32770') {
                    Get-OwnProcs $copy | Stop-Process -Force -ErrorAction SilentlyContinue
                    "  popup in $($pr.ProcessName): '$title' -> our process closed"
                    $result = "popup: $title"
                } elseif ($pr.ProcessName -eq 'Baldur' -and -not $off[$h]) {
                    [PthWin]::OffScreen([IntPtr][int64]$h)
                    $off[$h] = $true
                }
            }
        }
        if ($result -like 'popup*') { break }
        if (-not $muted -and ($procs | Where-Object ProcessName -eq 'Baldur')) {
            Start-Sleep 3
            & powershell -NoProfile -ExecutionPolicy Bypass -File "$Repo\tools\windows\mute_games.ps1" | Out-Null
            $muted = $true
        }
        $st = Get-Status $copy
        if ($st -like 'start screen ready*' -and -not $menuAt) { $menuAt = ((Get-Date) - $t0).TotalSeconds }
        if (($st -like '*screen ready*' -or $st -like 'loading*') -and ((Get-Date) - $lastKey).TotalSeconds -ge 3) {
            foreach ($h in @($off.Keys)) { [PthWin]::F11([IntPtr][int64]$h) }
            $lastKey = Get-Date
        }
        if ($st -like 'DONE*') { $result = 'done'; break }
        if ($st -like 'save not found*' -or $st -like 'probe load error*' -or $st -like 'tick error*') { $result = $st; break }
        if ($procs.Count -eq 0 -and ((Get-Date) - $t0).TotalSeconds -gt 20) { $result = "exited ($st)"; break }
    }
    $st = Get-Status $copy
    Get-OwnProcs $copy | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep 2
    $dest = "$OutDir\$side-run$n.txt"
    if (Test-Path "$copy\pathtest_out.txt") { Copy-Item "$copy\pathtest_out.txt" $dest -Force }
    elseif (Test-Path "$copy\IEX\pathtest_out.txt") { Copy-Item "$copy\IEX\pathtest_out.txt" $dest -Force }
    elseif (Test-Path "$copy\pathtest_loader.log") {
        $l = Get-Content "$copy\pathtest_loader.log" -Encoding utf8 | Where-Object { $_ -match 'PTH\|' -and $_ -notmatch 'PTH\|STATUS' } | ForEach-Object { $_.Substring($_.IndexOf('PTH|') + 4) }
        [IO.File]::WriteAllLines($dest, [string[]]@($l))
    } else { Set-Content $dest '' }
    if (Test-Path "$copy\pathtest_loader.log") { Copy-Item "$copy\pathtest_loader.log" "$OutDir\$side-run$n.loader.log" -Force }
    if ($side -ne 'eeex' -and (Test-Path "$copy\IEX.log")) { Copy-Item "$copy\IEX.log" "$OutDir\$side-run$n.IEX.log" -Force }
    $lines = (Get-Content $dest | Measure-Object -Line).Lines
    "$side run $n : $result, status '$st', $lines lines, start screen at $([math]::Round([double]$menuAt,1)) s, $([int]((Get-Date) - $t0).TotalSeconds) s"
}

$prepared = @{}
foreach ($side in $Sides) {
    $kind = if ($side -eq 'eeex') { 'eeex' } else { 'iex' }
    if (-not $prepared[$kind]) { $prepared[$kind] = Prepare-Copy $kind }
    for ($n = 1; $n -le $Runs; $n++) { Run-Once $side $prepared[$kind] $n }
}
"results in $OutDir"
