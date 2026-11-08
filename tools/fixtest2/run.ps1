# Engine-fix test 2 (Windows, IEX 0.4.1 fixes): the clean test game (make_clean.py fixes2-bg2ee bg2ee "(IEX fixes2)"),
# the probe (tools/fixtest2/probe) and its test resources (make_res.py) in override, the BG2EE "Chapter 1 Start" save.
# Runs the game with the engine fixes off (IEX_ENGINE_FIXES=0), on, or with some off, and writes the probe output,
# IEX.log and the process memory at the probe's 'mem <tag>' marks to $OutDir.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\fixtest2\run.ps1 -Fixes on|off [-Off a,b]
#       [-Mode main|op248|startup2da] [-Build <dir>] [-Tag t]
# Never saves. Only processes started from the test game are closed. Startup movies off, audio muted, window off screen.
param(
    [ValidateSet('on', 'off')][string]$Fixes = 'on',
    [string]$Off = '',
    [ValidateSet('main', 'op248', 'startup2da', 'rest')][string]$Mode = 'main',
    [string]$Game = "E:\Dev\IEX-data\testgame\fixes2-bg2ee",
    [string]$SaveFrom = "E:\Dev\IEX-data\fixtest2\save\000000007-Chapter 1 Start",
    [string]$Repo = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent),
    [string]$Build = "",
    [string]$OutDir = "E:\Dev\IEX-data\fixtest2",
    [string]$Tag = "",
    [int]$Timeout = 600
)
$ErrorActionPreference = 'Stop'
$env:IEX_SKIP_INTRO = '1'
if (-not $Build) { $Build = "$Repo\build" }
if (-not $Tag) {
    $Tag = "win-$Mode-fixes$Fixes"
    if ($Off) { $Tag += "-off-" + ($Off -replace ',', '+') }
}
New-Item -ItemType Directory -Force $OutDir | Out-Null
$copy = $Game
if ($copy -notlike '*\IEX-data\testgame\*' -or $copy -like '*eet-2.7.3*' -or $copy -like '*night*') { throw "refused game $copy" }

Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing @"
using System;
using System.Runtime.InteropServices;
public static class FxtWin {
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

# 1. Test resources, probe, IEX
& python -I "$Repo\tools\fixtest2\make_res.py" "$copy\override" $Mode
if ($LASTEXITCODE) { throw 'test resources failed' }
$body = Get-Content "$Repo\tools\fixtest2\probe\fx2_body.lua" -Raw
$wrapped = "local src = [==========[`n" + $body + "`n]==========]`nlocal fn, err = (loadstring or load)(src, '=fx2')`nlocal ok = fn ~= nil`nif fn then ok, err = pcall(fn) end`nif not ok and IEX_Log then pcall(IEX_Log, '[FX2] load error ' .. tostring(err)) end`n"
[IO.File]::WriteAllText("$copy\override\M_FX2.lua", $wrapped)
Copy-Item "$Repo\tools\fixtest2\probe\FX2.menu" "$copy\override\" -Force
Remove-Item "$copy\IEX.dll", "$copy\IEXLauncher.exe" -Force -ErrorAction SilentlyContinue
Copy-Item "$Build\IEX.dll", "$Build\IEXLauncher.exe" $copy -Force
New-Item -ItemType Directory -Force "$copy\IEX\engine" | Out-Null
Copy-Item "$Repo\lua\*.lua" "$copy\IEX\" -Force
Copy-Item "$Repo\ui\*.menu" "$copy\override\" -Force
Copy-Item "$Repo\engine\*.iexd" "$copy\IEX\engine\" -Force
$engineName = "Baldur's Gate II - Enhanced Edition (IEX fixes2)"
Set-Content "$copy\engine.lua" "engine_name = `"$engineName`"`r`nengine_mode = 1 -- 0 = BGEE, 1 = BG2EE, 2 = IWDEE" -Encoding ascii
$docs = "$([Environment]::GetFolderPath('MyDocuments'))\$engineName"
New-Item -ItemType Directory -Force "$docs\save" | Out-Null
Get-ChildItem "$docs\save" -Directory | Remove-Item -Recurse -Force
Copy-Item $SaveFrom "$docs\save\000000099-FIXTEST2" -Recurse -Force
$ini = @("SetPrivateProfileString('Language','Text','en_US')", "SetPrivateProfileString('Program Options','Disable Movies','1')",
    "SetPrivateProfileString('IEX','Skip Intro Movies','1')", "SetPrivateProfileString('MOVIES','BLACKPIT','1')",
    "SetPrivateProfileString('MOVIES','INTRO15F','1')", "SetPrivateProfileString('MOVIES','LOGO','1')",
    "SetPrivateProfileString('MOVIES','INTRO','1')", "SetPrivateProfileString('Game Options','Auto Pause State','0')")
[IO.File]::WriteAllText("$docs\Baldur.lua", (($ini -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)

# 2. Run
if (Get-OwnProcs) { Get-OwnProcs | Stop-Process -Force; Start-Sleep 2 }
Remove-Item "$copy\IEX\fixtest2_out.txt", "$copy\IEX\fixtest2_status.txt", "$copy\IEX.log" -ErrorAction SilentlyContinue
if ($Fixes -eq 'off') { $env:IEX_ENGINE_FIXES = '0' } else { Remove-Item Env:IEX_ENGINE_FIXES -ErrorAction SilentlyContinue }
if ($Off) { $env:IEX_ENGINE_FIXES_OFF = $Off } else { Remove-Item Env:IEX_ENGINE_FIXES_OFF -ErrorAction SilentlyContinue }
$env:IEX_FIX_DEBUG = '1'
Start-Process "$copy\IEXLauncher.exe" -WorkingDirectory $copy -WindowStyle Minimized
$t0 = Get-Date; $lastKey = $t0; $muted = $false; $result = 'timeout'; $placed = @{}; $memDone = @{}; $memLines = @(); $gone = 0
function Get-Status {
    $f = "$copy\IEX\fixtest2_status.txt"
    if (Test-Path $f) { return (Get-Content $f -Raw).Trim() }
    return ''
}
while (((Get-Date) - $t0).TotalSeconds -lt $Timeout) {
    Start-Sleep -Milliseconds 400
    $procs = @(Get-OwnProcs)
    foreach ($pr in $procs) {
        foreach ($w in [FxtWin]::Windows([uint32]$pr.Id)) {
            $h, $cls, $title = $w.Split('|', 3)
            if ($cls -eq '#32770') { Get-OwnProcs | Stop-Process -Force -ErrorAction SilentlyContinue; $result = "popup: $title" }
            elseif ($pr.ProcessName -eq 'Baldur' -and -not $placed[$h]) { [FxtWin]::OffScreen([IntPtr][int64]$h); $placed[$h] = $true }
        }
    }
    if ($result -like 'popup*') { break }
    if (-not $muted -and ($procs | Where-Object ProcessName -eq 'Baldur')) {
        Start-Sleep 2
        & powershell -NoProfile -ExecutionPolicy Bypass -File "$Repo\tools\windows\mute_games.ps1" | Out-Null
        $muted = $true
    }
    $st = Get-Status
    if (($st -like '*screen ready*' -or $st -like 'loading*' -or $st -eq 'main file loaded' -or $st -eq 'opening load screen') -and ((Get-Date) - $lastKey).TotalSeconds -ge 3) {
        foreach ($h in @($placed.Keys)) { [FxtWin]::F11([IntPtr][int64]$h) }
        $lastKey = Get-Date
    }
    if ($st -like 'mem *' -and -not $memDone[$st]) {
        $b = $procs | Where-Object ProcessName -eq 'Baldur' | Select-Object -First 1
        if ($b) {
            $b.Refresh()
            $memLines += ('{0} t={1:n0}s private={2:n1} MB workingset={3:n1} MB' -f $st, ((Get-Date) - $t0).TotalSeconds,
                ($b.PrivateMemorySize64 / 1MB), ($b.WorkingSet64 / 1MB))
        }
        $memDone[$st] = $true
    }
    if ($st -like 'DONE*') { $result = 'done'; break }
    if ($st -like 'save not found*' -or $st -like '*load error*') { $result = $st; break }
    # exited: no game process seen 5 times in a row (one failed process query is not an exit)
    if ($procs | Where-Object ProcessName -eq 'Baldur') { $gone = 0 } else { $gone++ }
    if ($gone -ge 5 -and ((Get-Date) - $t0).TotalSeconds -gt 20) { $result = "exited ($st)"; break }
}
$st = Get-Status
Get-OwnProcs | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep 2
Remove-Item Env:IEX_ENGINE_FIXES, Env:IEX_ENGINE_FIXES_OFF, Env:IEX_FIX_DEBUG -ErrorAction SilentlyContinue
$outFile = "$OutDir\$Tag.txt"
$text = @("run $Tag : $result, status '$st'") + $memLines
if (Test-Path "$copy\IEX\fixtest2_out.txt") { $text += Get-Content "$copy\IEX\fixtest2_out.txt" }
Set-Content $outFile $text
if (Test-Path "$copy\IEX.log") { Copy-Item "$copy\IEX.log" "$OutDir\$Tag.IEX.log" -Force }
"$Tag : $result, status '$st', $([int]((Get-Date) - $t0).TotalSeconds) s -> $outFile"
