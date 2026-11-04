# Game speed / frame rate test: runs the speedtest probe (tools/speedtest/probe) on the same save under EEex or IEX
# with given Baldur.lua settings, and writes <OutDir>\<Label>.txt (one line per phase, see probe/spd_body.lua).
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\speedtest\run.ps1 -Side eeex -Label eeex-uncap1 `
#       -Ini "EEex|Uncap FPS|1" [-Phases "30,60,120,30c,60c,ta,tac"] [-IexFrom <dir with IEX.dll, IEXLauncher.exe, IEX\>]
# Private copies of the test base (tools/difftest/make_copy.py), own Documents folders (own engine_name), Steam off
# (no steam_appid.txt). Only processes started from the copies are ever closed. No startup movies, off screen, muted.
param(
    [Parameter(Mandatory)] [ValidateSet('eeex', 'iex')] [string]$Side,
    [Parameter(Mandatory)] [string]$Label,
    [string[]]$Ini = @(),
    [string]$Phases = '30,60,120,30c,60c,ta,tac,30',
    [string]$Base = "E:\Dev\IEX-data\testgame\eet-2.7.3",
    [string]$SaveFrom = "$([Environment]::GetFolderPath('MyDocuments'))\Baldur's Gate - Enhanced Edition Trilogy (IEX asm-eeex)",
    [string]$SaveName = "000000009-Chapter 2 Start",
    [string]$ModSync = "E:\Enhanced Edition\Environnement de test\EET 2.7.3 (dev)\override",
    [string]$EEexMain ="E:\Enhanced Edition\Environnement de test\EET 2.7.3 (dev)\override\M___EEex.lua",
    [string]$Build = "",
    # IEX binaries + Lua from another install (e.g. a release copy), copied, never written: IEX.dll, IEXLauncher.exe, IEX\
    [string]$IexFrom = "",
    [int]$Timeout = 300,
    # After the phases: open the options screen and click these points ("fx,fy" client fractions, ';'-separated),
    # one screenshot each (<OutDir>\<Label>-shot<n>.png).
    [string[]]$Clicks = @(),
    [switch]$Shots,
    [switch]$Refresh,
    [string]$Repo = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent),
    [string]$OutDir = "",
    # Own copy folder and engine_name (default: speedtest-<Side>, EET name); the copy keeps its engine.lua lang_dir.
    [string]$Copy = "",
    [string]$EngineName = "",
    # Window left on screen (restored without activation) so a person can watch; default: moved off screen.
    [switch]$OnScreen
)
$ErrorActionPreference = 'Stop'
$env:IEX_SKIP_INTRO = '1'
$Ini = @($Ini | ForEach-Object { $_ -split ';' } | Where-Object { $_ })
$Clicks = @($Clicks | ForEach-Object { $_ -split ';' } | Where-Object { $_ })
if ($Shots) { $Ini += 'SpeedTest|Shots|1' }
$here = "$Repo\tools\speedtest"
$docs = [Environment]::GetFolderPath('MyDocuments')
if (-not $Build) { $Build = "$Repo\build" }
if (-not $OutDir) { $OutDir = "E:\Dev\IEX-data\speedtest\$(Get-Date -Format yyyy-MM-dd)" }
New-Item -ItemType Directory -Force $OutDir | Out-Null
$offFiles = 'M_I3CAM.lua', 'M_I3MOVE.lua', 'M_I3NET.lua', 'M_IEXTST.lua', 'M_ZMEMT.lua', 'M_BGBOT.lua', 'M_BGBCMB.lua',
    'M_IEXFPS.lua', 'M_IEXSPL.lua', 'M_DIFFT.lua', 'M_DIFFTA.lua', 'M_IEXPTH.lua'

Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing @"
using System;
using System.Runtime.InteropServices;
public static class SpdWin {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int l, t, r, b; }
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int x, y; }
    [StructLayout(LayoutKind.Sequential)] public struct WINDOWPLACEMENT {
        public int length, flags, showCmd; public POINT minPos, maxPos; public RECT normal; }
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] public static extern bool GetWindowPlacement(IntPtr h, ref WINDOWPLACEMENT wp);
    [DllImport("user32.dll")] public static extern bool SetWindowPlacement(IntPtr h, ref WINDOWPLACEMENT wp);
    // A minimized game draws a fraction of a frame per second: restored off screen instead, without activation.
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
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
    // Left click at a fraction of the client area, posted (no focus change).
    public static void Click(IntPtr h, double fx, double fy) {
        RECT r; GetClientRect(h, out r);
        int x = (int)((r.r - r.l) * fx), y = (int)((r.b - r.t) * fy);
        IntPtr lp = (IntPtr)((y << 16) | (x & 0xffff));
        PostMessage(h, 0x200, IntPtr.Zero, lp);
        System.Threading.Thread.Sleep(80);
        PostMessage(h, 0x201, (IntPtr)1, lp);
        System.Threading.Thread.Sleep(80);
        PostMessage(h, 0x202, IntPtr.Zero, lp);
    }
    public static bool Shot(IntPtr h, string path) {
        RECT r; GetClientRect(h, out r);
        int w = r.r - r.l, ht = r.b - r.t;
        if (w <= 0 || ht <= 0) return false;
        using (var bmp = new System.Drawing.Bitmap(w, ht)) {
            using (var g = System.Drawing.Graphics.FromImage(bmp)) {
                IntPtr dc = g.GetHdc();
                bool ok = PrintWindow(h, dc, 3);
                g.ReleaseHdc(dc);
                if (!ok) return false;
            }
            bmp.Save(path, System.Drawing.Imaging.ImageFormat.Png);
        }
        return true;
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
    Get-Process -ErrorAction SilentlyContinue | Where-Object { $path = $_.Path; $path -and $path.StartsWith($dir, 'OrdinalIgnoreCase') }
}

function Get-Status($copy) {
    foreach ($f in "$copy\speedtest_status.txt", "$copy\IEX\speedtest_status.txt") {
        if (Test-Path $f) { return (Get-Content $f -Raw).Trim() }
    }
    if (Test-Path "$copy\speedtest_loader.log") {
        $l = Select-String -Path "$copy\speedtest_loader.log" -Pattern 'SPD\|STATUS (.*)' | Select-Object -Last 1
        if ($l) { return $l.Matches[0].Groups[1].Value.Trim() }
    }
    return ''
}

$copy = if ($Copy) { $Copy } else { "E:\Dev\IEX-data\testgame\speedtest-$Side" }
if ($Refresh -or -not (Test-Path "$copy\chitin.key")) {
    & python -I "$Repo\tools\difftest\make_copy.py" $Base $copy
    if ($LASTEXITCODE) { throw "copy failed" }
}
Remove-Item "$copy\steam_appid.txt" -Force -ErrorAction SilentlyContinue
$engineName = if ($EngineName) { $EngineName } else { "Baldur's Gate - Enhanced Edition Trilogy (IEX speedtest $Side)" }
$engineLua = @("engine_name = `"$engineName`"", "engine_mode = 1 -- 0 = BGEE, 1 = BG2EE, 2 = IWDEE")
if (Test-Path "$copy\engine.lua") { $engineLua += @(Get-Content "$copy\engine.lua" | Where-Object { $_ -match '^\s*lang_dir' }) }
Set-Content "$copy\engine.lua" ($engineLua -join "`r`n") -Encoding ascii
New-Item -ItemType Directory -Force "$copy\override_off" | Out-Null
foreach ($f in $offFiles) { if (Test-Path "$copy\override\$f") { Move-Item "$copy\override\$f" "$copy\override_off\" -Force } }
# SadoEE as in the dev game (the base has an older M_SQOPT.lua and lacks SQOPT.menu: a missing menu file makes
# EEex_Menu_LoadFile crash the game under EEex). Same files in both copies; copied, never linked.
if ($ModSync -and (Test-Path $ModSync)) {
    Get-ChildItem $ModSync -File | Where-Object { $_.Name -match '^(M_PS|M_SQ|SQOPT|PSX|PSTASH)' -and $offFiles -notcontains $_.Name } | ForEach-Object {
        $dst = "$copy\override\$($_.Name)"
        if (-not (Test-Path $dst) -or (Get-Item $dst).Length -ne $_.Length) { Copy-Item $_.FullName $dst -Force }
    }
}
& python -I "$here\install_probe.py" "$copy\override"
if ($LASTEXITCODE) { throw "probe install failed" }
if ($Side -eq 'eeex') {
    if (-not (Test-Path "$copy\override\M___EEex.lua")) { Copy-Item $EEexMain "$copy\override\M___EEex.lua" }
    $li = Get-Content "$copy\InfinityLoader.ini"
    $li = $li -replace '^LogFile=.*$', 'LogFile=speedtest_loader.log'
    Set-Content "$copy\InfinityLoader.ini" $li -Encoding ascii
} else {
    Remove-Item "$copy\IEX.dll", "$copy\IEXLauncher.exe" -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force "$copy\IEX\engine" | Out-Null
    Get-ChildItem "$copy\IEX\*.lua" | Remove-Item -Force
    if ($IexFrom) {
        Copy-Item "$IexFrom\IEX.dll", "$IexFrom\IEXLauncher.exe" $copy -Force
        Copy-Item "$IexFrom\IEX\*.lua", "$IexFrom\IEX\IEX_API.txt" "$copy\IEX\" -Force
        Copy-Item "$IexFrom\IEX\engine\*.iexd" "$copy\IEX\engine\" -Force
    } else {
        Copy-Item "$Build\IEX.dll", "$Build\IEXLauncher.exe" $copy -Force
        Copy-Item "$Repo\lua\*.lua" "$copy\IEX\" -Force
        & python -I "$Repo\tools\compat\api_list.py" "$copy\IEX\IEX_API.txt" | Out-Null
        Copy-Item "$Repo\engine\*.iexd" "$copy\IEX\engine\" -Force
    }
    Copy-Item "$Repo\ui\*.menu" "$copy\override\" -Force
}

# Documents folder: the save and Baldur.lua (the source's, plus the run's settings)
$d = "$docs\$engineName"
New-Item -ItemType Directory -Force "$d\save" | Out-Null
Get-ChildItem "$d\save" -Directory | Remove-Item -Recurse -Force
Copy-Item "$SaveFrom\save\$SaveName" "$d\save\000000097-SPEEDTEST" -Recurse -Force
$latin1 = [Text.Encoding]::GetEncoding(28591)
$keys = @($Ini | ForEach-Object { ($_ -split '\|')[0..1] -join '|' })
$lines = [IO.File]::ReadAllLines("$SaveFrom\Baldur.lua", $latin1) | Where-Object {
    $_ -notmatch "^SetPrivateProfileString\('(SpeedTest|PathTest|DiffTest)'" -and
    -not ($_ -match "^SetPrivateProfileString\('([^']*)','([^']*)'" -and $keys -contains "$($Matches[1])|$($Matches[2])") -and
    $_ -notmatch "^SetPrivateProfileString\('IEX','Frame (Rate|Interpolation)'" }
$seed = @("SetPrivateProfileString('Program Options','Disable Movies','1')", "SetPrivateProfileString('SpeedTest','Phases','$Phases')")
foreach ($e in $Ini) { $s, $k, $v = $e -split '\|', 3; $seed += "SetPrivateProfileString('$s','$k','$v')" }
[IO.File]::WriteAllText("$d\Baldur.lua", ((@($lines) + $seed) -join "`r`n") + "`r`n", $latin1)

if (Get-OwnProcs $copy) { Get-OwnProcs $copy | Stop-Process -Force; Start-Sleep 2 }
Remove-Item "$copy\speedtest_out.txt", "$copy\speedtest_status.txt", "$copy\IEX\speedtest_out.txt", "$copy\IEX\speedtest_status.txt", "$copy\speedtest_loader.log" -ErrorAction SilentlyContinue
if ($Side -eq 'iex') { Remove-Item "$copy\IEX.log" -ErrorAction SilentlyContinue }
$exe = if ($Side -eq 'eeex') { "$copy\InfinityLoader.exe" } else { "$copy\IEXLauncher.exe" }
Start-Process $exe -WorkingDirectory $copy -WindowStyle Minimized
$t0 = Get-Date; $lastKey = $t0; $muted = $false; $result = 'timeout'; $off = @{}
while (((Get-Date) - $t0).TotalSeconds -lt $Timeout) {
    Start-Sleep -Milliseconds 300
    $procs = @(Get-OwnProcs $copy)
    foreach ($pr in $procs) {
        foreach ($w in [SpdWin]::Windows([uint32]$pr.Id)) {
            $h, $cls, $title = $w.Split('|', 3)
            if ($cls -ne 'SDL_app' -and $cls -ne 'ConsoleWindowClass' -and $cls -ne 'CASCADIA_HOSTING_WINDOW_CLASS') {
                Get-OwnProcs $copy | Stop-Process -Force -ErrorAction SilentlyContinue
                "  popup in $($pr.ProcessName): '$title' ($cls) -> our process closed"
                $result = "popup: $title"
            } elseif ($pr.ProcessName -eq 'Baldur' -and -not $off[$h]) {
                if (-not $OnScreen) { [SpdWin]::OffScreen([IntPtr][int64]$h) } else { [void][SpdWin]::ShowWindow([IntPtr][int64]$h, 4) }
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
    if (($st -like '*screen ready*' -or $st -like 'loading*') -and ((Get-Date) - $lastKey).TotalSeconds -ge 3) {
        foreach ($h in @($off.Keys)) { [SpdWin]::F11([IntPtr][int64]$h) }
        $lastKey = Get-Date
    }
    if ($st -like 'DONE*') { $result = 'done'; break }
    if ($st -like 'shots*') {
        # options screen open: screenshot, then one click + screenshot per -Clicks entry ("fx,fy" fractions)
        Start-Sleep 1
        $n = 0
        foreach ($h in @($off.Keys)) {
            $hw = [IntPtr][int64]$h
            [void][SpdWin]::Shot($hw, "$OutDir\$Label-shot$n.png")
            foreach ($c in $Clicks) {
                $n++
                $fx, $fy = $c -split ','
                [SpdWin]::Click($hw, [double]::Parse($fx, [Globalization.CultureInfo]::InvariantCulture), [double]::Parse($fy, [Globalization.CultureInfo]::InvariantCulture))
                Start-Sleep -Milliseconds 900
                [void][SpdWin]::Shot($hw, "$OutDir\$Label-shot$n.png")
            }
        }
        "  $($n + 1) screenshots in $OutDir"
        $result = 'done'; break
    }
    if ($st -like 'save not found*' -or $st -like 'probe load error*' -or $st -like 'tick error*') { $result = $st; break }
    if ($procs.Count -eq 0 -and ((Get-Date) - $t0).TotalSeconds -gt 20) { $result = "exited ($st)"; break }
}
$st = Get-Status $copy
Get-OwnProcs $copy | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep 2
$dest = "$OutDir\$Label.txt"
if (Test-Path "$copy\speedtest_out.txt") { Copy-Item "$copy\speedtest_out.txt" $dest -Force }
elseif (Test-Path "$copy\IEX\speedtest_out.txt") { Copy-Item "$copy\IEX\speedtest_out.txt" $dest -Force }
elseif (Test-Path "$copy\speedtest_loader.log") {
    $l = Get-Content "$copy\speedtest_loader.log" -Encoding utf8 | Where-Object { $_ -match 'SPD\|' -and $_ -notmatch 'SPD\|STATUS' } | ForEach-Object { $_.Substring($_.IndexOf('SPD|') + 4) }
    [IO.File]::WriteAllLines($dest, [string[]]@($l))
} else { Set-Content $dest '' }
if (Test-Path "$copy\speedtest_loader.log") { Copy-Item "$copy\speedtest_loader.log" "$OutDir\$Label.loader.log" -Force }
if ($Side -eq 'iex' -and (Test-Path "$copy\IEX.log")) { Copy-Item "$copy\IEX.log" "$OutDir\$Label.IEX.log" -Force }
"$Label : $result, status '$st', $([int]((Get-Date) - $t0).TotalSeconds) s"
Get-Content $dest
