# Engine-fix test (Windows): a private copy of the test game, the probe (tools/fixtest/probe) and its test resources
# (make_res.py) in override, a save of <= 6 party members. Runs the game with the engine fixes off (IEX_ENGINE_FIXES=0:
# the engine bugs) or on (default) and writes the probe output, IEX.log and screenshots to $OutDir.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\fixtest\run.ps1 -Fixes on|off [-Build <dir>] [-Refresh]
# Never saves. Only processes started from the copy are closed. Startup movies off.
param(
    [ValidateSet('on', 'off')][string]$Fixes = 'on',
    [string]$Base = "E:\Dev\IEX-data\testgame\eet-2.7.3",
    [string]$SaveFrom = "$([Environment]::GetFolderPath('MyDocuments'))\Baldur's Gate - Enhanced Edition Trilogy (IEX bot)",
    [string]$SaveName = "000000703-AUTO 10-30 04h12 - AR2100 after fight",
    [string]$Repo = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent),
    [string]$Build = "",
    [string]$OutDir = "E:\Dev\IEX-data\fixtest",
    [int]$Timeout = 300,
    [switch]$Refresh
)
$ErrorActionPreference = 'Stop'
$env:IEX_SKIP_INTRO = '1'
if (-not $Build) { $Build = "$Repo\build" }
New-Item -ItemType Directory -Force $OutDir | Out-Null
$copy = "E:\Dev\IEX-data\testgame\fixtest-iex"
$tag = "fixes$Fixes"

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

# 1. Copy + test resources
if ($Refresh -or -not (Test-Path "$copy\chitin.key")) {
    & python -I "$Repo\tools\difftest\make_copy.py" $Base $copy
    if ($LASTEXITCODE) { throw 'copy failed' }
}
& python -I "$Repo\tools\fixtest\make_res.py" "$copy\override"
if ($LASTEXITCODE) { throw 'test resources failed' }

# 2. M_ files that drive the game are moved out
New-Item -ItemType Directory -Force "$copy\override_off" | Out-Null
foreach ($f in 'M_I3CAM.lua', 'M_I3MOVE.lua', 'M_I3NET.lua', 'M_IEXTST.lua', 'M_ZMEMT.lua', 'M_BGBOT.lua', 'M_BGBCMB.lua',
        'M_IEXFPS.lua', 'M_IEXSPL.lua', 'M_DIFFT.lua', 'M_DIFFTA.lua', 'M_STKPRB.lua') {
    if (Test-Path "$copy\override\$f") { Move-Item "$copy\override\$f" "$copy\override_off\" -Force }
}

# 3. Probe (body run inside load() + pcall: a load error never opens a popup) and IEX
$body = Get-Content "$Repo\tools\fixtest\probe\fxt_body.lua" -Raw
$wrapped = "local src = [==========[`n" + $body + "`n]==========]`nlocal fn, err = (loadstring or load)(src, '=fxt')`nlocal ok = fn ~= nil`nif fn then ok, err = pcall(fn) end`nif not ok and IEX_Log then pcall(IEX_Log, '[FXT] load error ' .. tostring(err)) end`n"
[IO.File]::WriteAllText("$copy\override\M_FXT.lua", $wrapped)
Copy-Item "$Repo\tools\fixtest\probe\FXT.menu" "$copy\override\" -Force
Remove-Item "$copy\IEX.dll", "$copy\IEXLauncher.exe" -Force -ErrorAction SilentlyContinue
Copy-Item "$Build\IEX.dll", "$Build\IEXLauncher.exe" $copy -Force
New-Item -ItemType Directory -Force "$copy\IEX\engine" | Out-Null
Copy-Item "$Repo\lua\*.lua" "$copy\IEX\" -Force
Copy-Item "$Repo\ui\*.menu" "$copy\override\" -Force
Copy-Item "$Repo\engine\*.iexd" "$copy\IEX\engine\" -Force
$engineName = "Baldur's Gate - Enhanced Edition Trilogy (IEX fixtest)"
Set-Content "$copy\engine.lua" "engine_name = `"$engineName`"`r`nengine_mode = 1 -- 0 = BGEE, 1 = BG2EE, 2 = IWDEE" -Encoding ascii
$docs = "$([Environment]::GetFolderPath('MyDocuments'))\$engineName"
New-Item -ItemType Directory -Force "$docs\save" | Out-Null
Get-ChildItem "$docs\save" -Directory | Remove-Item -Recurse -Force
Copy-Item "$SaveFrom\save\$SaveName" "$docs\save\000000099-FIXTEST" -Recurse -Force
$latin1 = [Text.Encoding]::GetEncoding(28591)
$ini = [IO.File]::ReadAllLines("$SaveFrom\Baldur.lua", $latin1) | Where-Object { $_ -notmatch "Disable Movies|Auto Pause State" }
[IO.File]::WriteAllText("$docs\Baldur.lua", (($ini -join "`r`n") + "`r`nSetPrivateProfileString('Program Options','Disable Movies','1')`r`nSetPrivateProfileString('Program Options','Auto Pause State','0')`r`n"), $latin1)

# 4. Run
if (Get-OwnProcs) { Get-OwnProcs | Stop-Process -Force; Start-Sleep 2 }
Remove-Item "$copy\IEX\fixtest_out.txt", "$copy\IEX\fixtest_status.txt", "$copy\IEX.log" -ErrorAction SilentlyContinue
if ($Fixes -eq 'off') { $env:IEX_ENGINE_FIXES = '0' } else { Remove-Item Env:IEX_ENGINE_FIXES -ErrorAction SilentlyContinue }
Start-Process "$copy\IEXLauncher.exe" -WorkingDirectory $copy -WindowStyle Minimized
$t0 = Get-Date; $lastKey = $t0; $muted = $false; $result = 'timeout'; $placed = @{}; $shots = @{}
function Get-Status {
    $f = "$copy\IEX\fixtest_status.txt"
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
    if ($st -like 'shot *' -and -not $shots[$st]) {
        Start-Sleep 1
        foreach ($h in @($placed.Keys)) { try { [void][FxtWin]::Shot([IntPtr][int64]$h, "$OutDir\$tag-$($st.Substring(5)).png") } catch {} }
        $shots[$st] = $true
    }
    if ($st -like 'DONE*') { $result = 'done'; break }
    if ($st -like 'save not found*' -or $st -like '*load error*') { $result = $st; break }
    if ($procs.Count -eq 0 -and ((Get-Date) - $t0).TotalSeconds -gt 20) { $result = "exited ($st)"; break }
}
$st = Get-Status
Get-OwnProcs | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep 2
Remove-Item Env:IEX_ENGINE_FIXES -ErrorAction SilentlyContinue
if (Test-Path "$copy\IEX\fixtest_out.txt") { Copy-Item "$copy\IEX\fixtest_out.txt" "$OutDir\$tag.txt" -Force }
if (Test-Path "$copy\IEX.log") { Copy-Item "$copy\IEX.log" "$OutDir\$tag.IEX.log" -Force }
"$tag : $result, status '$st', $([int]((Get-Date) - $t0).TotalSeconds) s -> $OutDir\$tag.txt"
