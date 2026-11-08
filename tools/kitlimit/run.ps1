# Kit-limit test (Windows, docs/KIT_LIMIT.md): the test game E:\Dev\IEX-data\testgame\kits-bg2ee (vanilla BG2EE +
# IEX + KitLimitTest, tools/kitlimit/make_mod.py), the probe tools/kitlimit/probe. Mode new: chargen with -Kit, world
# checks, save KLTSAVE, dual-class. Mode reload: loads KLTSAVE, checks, level-up. -Feature off: IEX_KIT_LIMIT=0.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\kitlimit\run.ps1 -Mode new -Kit KLT260 -Control KLT208 -Feature on -Tag win-on
# Only processes started from the test game are closed. Startup movies off, audio muted, window off screen.
param(
    [ValidateSet('new', 'reload')][string]$Mode = 'new',
    [string]$Kit = 'KLT260',
    [string]$Control = 'KLT208',
    [ValidateSet('on', 'off')][string]$Feature = 'on',
    [string]$Tag = 'win',
    [string]$Game = "E:\Dev\IEX-data\testgame\kits-bg2ee",
    [string]$Repo = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent),
    [string]$Build = "",
    [string]$OutDir = "E:\Dev\IEX-data\kitlimit",
    [int]$Timeout = 400
)
$ErrorActionPreference = 'Stop'
$env:IEX_SKIP_INTRO = '1'
if (-not $Build) { $Build = "$Repo\build" }
New-Item -ItemType Directory -Force $OutDir | Out-Null
$copy = $Game
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing @"
using System;
using System.Runtime.InteropServices;
public static class KltWin {
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
        wp.showCmd = 4; SetWindowPlacement(h, ref wp);
    }
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc f, IntPtr l);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr h, System.Text.StringBuilder s, int n);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, System.Text.StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    public static void F11(IntPtr h) {
        PostMessage(h, 0x100, (IntPtr)0x7A, (IntPtr)(1 | (0x57 << 16)));
        System.Threading.Thread.Sleep(60);
        PostMessage(h, 0x101, (IntPtr)0x7A, (IntPtr)unchecked((int)(0xC0000001 | (0x57 << 16))));
    }
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
    public static bool Shot(IntPtr h, string path) {
        RECT r; GetClientRect(h, out r);
        int w = r.r - r.l, ht = r.b - r.t;
        if (w <= 0 || ht <= 0) return false;
        using (var bmp = new System.Drawing.Bitmap(w, ht)) {
            using (var g = System.Drawing.Graphics.FromImage(bmp)) {
                IntPtr dc = g.GetHdc(); bool ok = PrintWindow(h, dc, 3); g.ReleaseHdc(dc);
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
                var c = new System.Text.StringBuilder(256); GetClassName(h, c, 256);
                var t = new System.Text.StringBuilder(256); GetWindowText(h, t, 256);
                list.Add(h.ToInt64().ToString() + "|" + c.ToString() + "|" + t.ToString());
            }
            return true;
        }, IntPtr.Zero);
        return list.ToArray();
    }
}
"@

function Get-OwnProcs {
    foreach ($pr in @(Get-Process -ErrorAction SilentlyContinue)) {
        try { $path = $pr.Path } catch { $path = $null }
        if ($path -and $path.StartsWith($copy, [StringComparison]::OrdinalIgnoreCase)) { $pr }
    }
}

# 1. IEX build + runtime files, probe
$body = Get-Content "$Repo\tools\kitlimit\probe\klt_body.lua" -Raw
$cfg = "KLT_MODE = '$Mode'`nKLT_KIT = '$Kit'`nKLT_CONTROL = '$Control'`n"
$wrapped = $cfg + "local src = [==========[`n" + $body + "`n]==========]`nlocal fn, err = (loadstring or load)(src, '=klt')`nlocal ok = fn ~= nil`nif fn then ok, err = pcall(fn) end`nif not ok and IEX_Log then pcall(IEX_Log, '[KLT] load error ' .. tostring(err)) end`n"
[IO.File]::WriteAllText("$copy\override\M_KLT.lua", $wrapped)
Remove-Item "$copy\IEX.dll", "$copy\IEXLauncher.exe" -Force -ErrorAction SilentlyContinue
Copy-Item "$Build\IEX.dll", "$Build\IEXLauncher.exe" $copy -Force
Copy-Item "$Repo\lua\*.lua" "$copy\IEX\" -Force
Copy-Item "$Repo\engine\*.iexd" "$copy\IEX\engine\" -Force
$engineName = "Baldur's Gate II - Enhanced Edition (IEX kits)"
$docs = "$([Environment]::GetFolderPath('MyDocuments'))\$engineName"
New-Item -ItemType Directory -Force "$docs\save" | Out-Null
if ($Mode -eq 'new') { Get-ChildItem "$docs\save" -Directory | Remove-Item -Recurse -Force }
$latin1 = [Text.Encoding]::GetEncoding(28591)
$ini = @()
if (Test-Path "$docs\Baldur.lua") { $ini = [IO.File]::ReadAllLines("$docs\Baldur.lua", $latin1) | Where-Object { $_ -notmatch "Disable Movies|Auto Pause State|'Language'|Skip Intro" } }
[IO.File]::WriteAllText("$docs\Baldur.lua", (($ini -join "`r`n") + "`r`nSetPrivateProfileString('Language','Text','en_US')`r`nSetPrivateProfileString('Program Options','Disable Movies','1')`r`nSetPrivateProfileString('IEX','Skip Intro Movies','1')`r`nSetPrivateProfileString('Game Options','Auto Pause State','0')`r`n"), $latin1)

# 2. Run
if (Get-OwnProcs) { Get-OwnProcs | Stop-Process -Force; Start-Sleep 2 }
Remove-Item "$copy\IEX\kitlimit_out.txt", "$copy\IEX\kitlimit_status.txt", "$copy\IEX.log" -ErrorAction SilentlyContinue
if ($Feature -eq 'off') { $env:IEX_KIT_LIMIT = '0' } else { Remove-Item Env:IEX_KIT_LIMIT -ErrorAction SilentlyContinue }
Start-Process "$copy\IEXLauncher.exe" -WorkingDirectory $copy -WindowStyle Minimized
$t0 = Get-Date; $lastKey = $t0; $keysSince = $null; $muted = $false; $result = 'timeout'; $placed = @{}
function Get-Status {
    $f = "$copy\IEX\kitlimit_status.txt"
    if (Test-Path $f) { return (Get-Content $f -Raw).Trim() }
    return ''
}
while (((Get-Date) - $t0).TotalSeconds -lt $Timeout) {
    Start-Sleep -Milliseconds 300
    $procs = @(Get-OwnProcs)
    foreach ($pr in $procs) {
        foreach ($w in [KltWin]::Windows([uint32]$pr.Id)) {
            $h, $cls, $title = $w.Split('|', 3)
            if ($cls -eq '#32770') {
                try { [void][KltWin]::Shot([IntPtr][int64]$h, "$OutDir\$Tag-popup.png") } catch {}
                Get-OwnProcs | Stop-Process -Force -ErrorAction SilentlyContinue; $result = "popup: $title"
            }
            elseif ($pr.ProcessName -eq 'Baldur' -and -not $placed[$h]) { [KltWin]::OffScreen([IntPtr][int64]$h); $placed[$h] = $true }
        }
    }
    if ($result -like 'popup*') { break }
    if (-not $muted -and ($procs | Where-Object ProcessName -eq 'Baldur')) {
        Start-Sleep 2
        & powershell -NoProfile -ExecutionPolicy Bypass -File "$Repo\tools\windows\mute_games.ps1" | Out-Null
        $muted = $true
    }
    $st = Get-Status
    if ($st -like '*- keys') {
        if (-not $keysSince) { $keysSince = Get-Date }
        if (((Get-Date) - $keysSince).TotalSeconds -ge 5 -and ((Get-Date) - $lastKey).TotalSeconds -ge 1) {
            foreach ($h in @($placed.Keys)) { [KltWin]::F11([IntPtr][int64]$h) }
            $lastKey = Get-Date
        }
    } else { $keysSince = $null }
    if ($st -like 'DONE*') { $result = 'done'; break }
    if ($st -like 'save not found*' -or $st -like '*load error*' -or $st -like 'chargen stuck*') { $result = $st; break }
    if ($procs.Count -eq 0 -and ((Get-Date) - $t0).TotalSeconds -gt 20) { $result = "exited ($st)"; break }
}
$st = Get-Status
foreach ($h in @($placed.Keys)) { try { [void][KltWin]::Shot([IntPtr][int64]$h, "$OutDir\$Tag-end.png") } catch {} }
Get-OwnProcs | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep 2
Remove-Item Env:IEX_KIT_LIMIT -ErrorAction SilentlyContinue
if (Test-Path "$copy\IEX\kitlimit_out.txt") { Copy-Item "$copy\IEX\kitlimit_out.txt" "$OutDir\$Tag.txt" -Force }
if (Test-Path "$copy\IEX.log") { Copy-Item "$copy\IEX.log" "$OutDir\$Tag.IEX.log" -Force }
"$Tag : $result, status '$st', $([int]((Get-Date) - $t0).TotalSeconds) s -> $OutDir\$Tag.txt"
