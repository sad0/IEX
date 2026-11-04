# Object id test (Windows): runs tools/objidtest/probe/p10_body.lua in a private test copy (default
# IEX-data/testgame/eet-p10: EET + SadoEE with the BOT's 10-member save as P10TEST, BOT drivers moved to override_off,
# its own engine_name / Documents folder) and writes <Tag>.txt + <Tag>.IEX.log to -OutDir. Deploy the build first
# (tools/deploy_build.py). Only processes started from the copy are closed. Examples:
#   run.ps1 -Tag before -Config 'P10_POKE = 32600'      (table about to run out: crash in CGameArea::SortLists
#                                                          with IEX_OBJECT_IDS=0)
#   run.ps1 -Tag wrap -Config 'P10_POKEKEY = 14800 P10_ROUNDS = 8'
param([string]$Config = '', [string]$Tag = 'run', [int]$Timeout = 300, [string]$OutDir = 'E:\Dev\IEX-data\p10test',
      [string]$Copy = 'E:\Dev\IEX-data\testgame\eet-p10')
$ErrorActionPreference = 'Stop'
$env:IEX_SKIP_INTRO = '1'
$Repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
New-Item -ItemType Directory -Force $OutDir | Out-Null
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing @"
using System;
using System.Runtime.InteropServices;
public static class P10Win {
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


$bodyPath = Join-Path $PSScriptRoot 'probe\p10_body.lua'
$b = (Get-Content $bodyPath -Raw).Replace('-- P10_CONFIG', $Config)
$wrapped = "local src = [==========[`n" + $b + "`n]==========]`nlocal fn, err = (loadstring or load)(src, '=p10')`nlocal ok = fn ~= nil`nif fn then ok, err = pcall(fn) end`nif not ok and IEX_Log then pcall(IEX_Log, '[P10] load error ' .. tostring(err)) end`n"
[IO.File]::WriteAllText("$copy\override\M_P10.lua", $wrapped)
$menu = "menu`n{`n`tname `"P10_TICK`"`n`tignoreesc`n`tlabel`n`t{`n`t`tname `"P10LABEL`"`n`t`tarea 0 0 0 0`n`t`tenabled `"P10_Tick()`"`n`t}`n}`n"
[IO.File]::WriteAllText("$copy\override\P10.menu", $menu)
if (Get-OwnProcs) { Get-OwnProcs | Stop-Process -Force; Start-Sleep 2 }
Remove-Item "$copy\IEX\p10_out.txt", "$copy\IEX\p10_status.txt", "$copy\IEX.log" -ErrorAction SilentlyContinue
Start-Process "$copy\IEXLauncher.exe" -WorkingDirectory $copy -WindowStyle Minimized
$t0 = Get-Date; $lastKey = $t0; $muted = $false; $result = 'timeout'; $placed = @{}; $lastSt = ''; $lastChange = Get-Date
function Get-Status { $f = "$copy\IEX\p10_status.txt"; if (Test-Path $f) { return (Get-Content $f -Raw).Trim() }; return '' }
while (((Get-Date) - $t0).TotalSeconds -lt $Timeout) {
    Start-Sleep -Milliseconds 400
    $procs = @(Get-OwnProcs)
    foreach ($pr in $procs) {
        foreach ($w in [P10Win]::Windows([uint32]$pr.Id)) {
            $h, $cls, $title = $w.Split('|', 3)
            if ($cls -eq '#32770') { $result = "popup: $title" }
            elseif ($pr.ProcessName -eq 'Baldur' -and -not $placed[$h]) { [P10Win]::OffScreen([IntPtr][int64]$h); $placed[$h] = $true }
        }
    }
    if ($result -like 'popup*') { break }
    if (-not $muted -and ($procs | Where-Object ProcessName -eq 'Baldur')) {
        Start-Sleep 2
        & powershell -NoProfile -ExecutionPolicy Bypass -File "$Repo\tools\windows\mute_games.ps1" | Out-Null
        $muted = $true
    }
    $st = Get-Status
    if ($st -ne $lastSt) { $lastSt = $st; $lastChange = Get-Date }
    if ($st -like 'alive*' -and ((Get-Date) - $lastChange).TotalSeconds -gt 25) { $result = "frozen ($st)"; break }
    if (($st -like '*screen ready*' -or $st -like 'loading*' -or $st -like 'opening*') -and ((Get-Date) - $lastKey).TotalSeconds -ge 3) {
        foreach ($h in @($placed.Keys)) { [P10Win]::F11([IntPtr][int64]$h) }
        $lastKey = Get-Date
    }
    if ($st -like 'DONE*') { $result = 'done'; break }
    if ($st -like 'save not found*' -or $st -like '*load error*') { $result = $st; break }
    if ($procs.Count -eq 0 -and ((Get-Date) - $t0).TotalSeconds -gt 20) { $result = "exited ($st)"; break }
}
Start-Sleep 1
Get-OwnProcs | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep 2
if (Test-Path "$copy\IEX\p10_out.txt") { Copy-Item "$copy\IEX\p10_out.txt" "$OutDir\$Tag.txt" -Force }
if (Test-Path "$copy\IEX.log") { Copy-Item "$copy\IEX.log" "$OutDir\$Tag.IEX.log" -Force }
"$Tag : $result, $([int]((Get-Date) - $t0).TotalSeconds) s"
