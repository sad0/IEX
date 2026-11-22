# Per-creature UUID test (Windows, docs/UUID.md): runs tools/uuidtest/probe/uuid_body.lua in a private test copy
# (IEX-data/testgame/uuid-eeex or uuid-iex, made from a difftest copy with tools/difftest/make_copy.py, own
# engine_name / Documents folder, steam_appid.txt disabled) under EEex (InfinityLoader) or IEX (IEXLauncher).
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\uuidtest\run.ps1 -Side eeex|iex -Mode first|reload
#        [-Save DIFFTEST] [-Slot 9] [-Copy <dir>] [-Extra <lua file>] [-Tag x] [-Quit]
# Mode first saves with SaveGame(-Slot); mode reload loads -Save. Only processes started from the copy are closed.
param(
    [ValidateSet('eeex', 'iex')][string]$Side = 'iex',
    [ValidateSet('first', 'reload')][string]$Mode = 'first',
    [string]$Save = 'DIFFTEST',
    [int]$Slot = 9,
    [string]$Copy = '',
    [string]$Extra = '',
    [string]$OutDir = "E:\Dev\IEX-data\uuidtest",
    [int]$Timeout = 300,
    [string]$Tag = '',
    [switch]$Quit  # after DONE: close the game window (WM_CLOSE) and wait for a clean exit instead of killing it
)
$ErrorActionPreference = 'Stop'
$env:IEX_SKIP_INTRO = '1'
$Repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if (-not $Copy) { $Copy = "E:\Dev\IEX-data\testgame\uuid-$Side" }
$copy = $Copy
New-Item -ItemType Directory -Force $OutDir | Out-Null
if (Test-Path "$copy\steam_appid.txt") { throw "steam_appid.txt present in ${copy}: rename it to steam_appid.txt.disabled first" }
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing @"
using System;
using System.Runtime.InteropServices;
public static class UuidWin {
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
    // Background key press (posted to the window): dismisses NPC dialogs that pause the game (reply 1, then Enter).
    public static void Key(IntPtr h, int vk, int scan) {
        PostMessage(h, 0x100, (IntPtr)vk, (IntPtr)(1 | (scan << 16)));
        System.Threading.Thread.Sleep(60);
        PostMessage(h, 0x101, (IntPtr)vk, (IntPtr)unchecked((int)(0xC0000001u | ((uint)scan << 16))));
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

# Probe (body run inside load() + pcall: a load error never opens a popup)
$config = "UUID_MODE = '$Mode' UUID_SAVE = '$Save' UUID_SLOT = $Slot"
if ($Quit) { $config += " UUID_QUIT = true" }
$body = (Get-Content "$Repo\tools\uuidtest\probe\uuid_body.lua" -Raw).Replace('-- UUID_CONFIG', $config)
if ($Extra) { $body += "`n" + (Get-Content $Extra -Raw) }
$wrapped = "local src = [==========[`n" + $body + "`n]==========]`nlocal fn, err = (loadstring or load)(src, '=uuidt')`nlocal ok = fn ~= nil`nif fn then ok, err = pcall(fn) end`nif not ok and IEX_Log then pcall(IEX_Log, '[UUIDT] load error ' .. tostring(err)) end`nif not ok then pcall(print, 'UUIDT load error ' .. tostring(err)) end`n"
[IO.File]::WriteAllText("$copy\override\M_UUIDT.lua", $wrapped)
$menu = "menu`n{`n`tname `"UUIDT_TICK`"`n`tignoreesc`n`tlabel`n`t{`n`t`tname `"UUIDTLABEL`"`n`t`tarea 0 0 0 0`n`t`tenabled `"UUIDT_Tick()`"`n`t}`n}`n"
[IO.File]::WriteAllText("$copy\override\UUIDT.menu", $menu)

if (Get-OwnProcs) { Get-OwnProcs | Stop-Process -Force; Start-Sleep 2 }
# Under EEex the probe prints (no io library): status and output come from the InfinityLoader log.
$loaderLog = "$copy\InfinityLoader.log"
if (Test-Path "$copy\InfinityLoader.ini") {
    $m = Select-String -Path "$copy\InfinityLoader.ini" -Pattern '^LogFile=(.+)$' | Select-Object -First 1
    if ($m) { $loaderLog = Join-Path $copy $m.Matches[0].Groups[1].Value.Trim() }
}
$docs = Join-Path ([Environment]::GetFolderPath('MyDocuments')) ((Select-String -Path "$copy\engine.lua" -Pattern 'engine_name = "(.*)"').Matches[0].Groups[1].Value)
Remove-Item $loaderLog, "$copy\uuid_out.txt", "$copy\uuid_status.txt", "$copy\IEX\uuid_out.txt", "$copy\IEX\uuid_status.txt", "$copy\IEX.log" -ErrorAction SilentlyContinue
$exe = if ($Side -eq 'eeex') { "$copy\InfinityLoader.exe" } else { "$copy\IEXLauncher.exe" }
Start-Process $exe -WorkingDirectory $copy -WindowStyle Minimized
$t0 = Get-Date; $lastKey = $t0; $muted = $false; $result = 'timeout'; $placed = @{}
function Get-Status {
    foreach ($f in "$copy\uuid_status.txt", "$copy\IEX\uuid_status.txt") { if (Test-Path $f) { return (Get-Content $f -Raw).Trim() } }
    if ($Side -eq 'eeex' -and (Test-Path $loaderLog)) {
        $l = Select-String -Path $loaderLog -Pattern 'UUIDT\|STATUS (.*)' | Select-Object -Last 1
        if ($l) { return $l.Matches[0].Groups[1].Value.Trim() }
    }
    return ''
}
while (((Get-Date) - $t0).TotalSeconds -lt $Timeout) {
    Start-Sleep -Milliseconds 400
    $procs = @(Get-OwnProcs)
    foreach ($pr in $procs) {
        foreach ($w in [UuidWin]::Windows([uint32]$pr.Id)) {
            $h, $cls, $title = $w.Split('|', 3)
            if ($cls -eq '#32770') { Get-OwnProcs | Stop-Process -Force -ErrorAction SilentlyContinue; $result = "popup: $title" }
            elseif ($pr.ProcessName -eq 'Baldur' -and -not $placed[$h]) { [UuidWin]::OffScreen([IntPtr][int64]$h); $placed[$h] = $true }
        }
    }
    if ($result -like 'popup*') { break }
    if (-not $muted -and ($procs | Where-Object ProcessName -eq 'Baldur')) {
        Start-Sleep 2
        & powershell -NoProfile -ExecutionPolicy Bypass -File "$Repo\tools\windows\mute_games.ps1" | Out-Null
        $muted = $true
    }
    $st = Get-Status
    if (($st -like '*screen ready*' -or $st -like 'loading*' -or $st -like 'opening*') -and ((Get-Date) - $lastKey).TotalSeconds -ge 3) {
        foreach ($h in @($placed.Keys)) { [UuidWin]::F11([IntPtr][int64]$h) }
        $lastKey = Get-Date
    }
    if ($st -like 'DONE*') { $result = 'done'; break }
    if ($st -like 'save not found*' -or $st -like '*load error*') { $result = $st; break }
    if ($procs.Count -eq 0 -and ((Get-Date) - $t0).TotalSeconds -gt 20) { $result = "exited ($st)"; break }
}
$st = Get-Status
Start-Sleep 1
if ($Quit -and $result -eq 'done') {
    # the probe quits to the start screen (every creature deleted), then calls Infinity_ShutdownGame()
    $q0 = Get-Date; $quitResult = 'still running after 60 s'
    while (((Get-Date) - $q0).TotalSeconds -lt 60) {
        Start-Sleep -Milliseconds 500
        $procs = @(Get-OwnProcs)
        $popup = $false
        foreach ($pr in $procs) { foreach ($w in [UuidWin]::Windows([uint32]$pr.Id)) { if ($w.Split('|')[1] -eq '#32770') { $popup = $true } } }
        if ($popup) { $quitResult = "popup on exit ($(Get-Status))"; break }
        if (-not ($procs | Where-Object ProcessName -eq 'Baldur')) { $quitResult = "process exited ($(Get-Status))"; break }
        if ((Get-Status) -like 'DONE quit: game destroyed*' -and ((Get-Date) - $lastKey).TotalSeconds -ge 3) {
            foreach ($h in @($placed.Keys)) { [UuidWin]::F11([IntPtr][int64]$h) }
            $lastKey = Get-Date
        }
    }
    $result = "done, quit: $quitResult"
}
Get-OwnProcs | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep 2
$name = "$Side-$Mode$Tag-$(Get-Date -Format 'MMdd-HHmm')"
foreach ($f in "$copy\uuid_out.txt", "$copy\IEX\uuid_out.txt") { if (Test-Path $f) { Copy-Item $f "$OutDir\$name.txt" -Force } }
if ($Side -eq 'eeex' -and (Test-Path $loaderLog)) {
    Copy-Item $loaderLog "$OutDir\$name.loader.log" -Force
    $o = Get-Content $loaderLog -Encoding utf8 | Where-Object { $_ -match 'UUIDT\|OUT ' } | ForEach-Object { $_.Substring($_.IndexOf('UUIDT|OUT ') + 10) }
    if ($o) { [IO.File]::WriteAllLines("$OutDir\$name.txt", [string[]]@($o)) }
}
if (Test-Path "$copy\IEX.log") { Copy-Item "$copy\IEX.log" "$OutDir\$name.IEX.log" -Force }
$cloud = @(Get-ChildItem "$copy\*.log", "$docs\*.log" -ErrorAction SilentlyContinue | Select-String -Pattern '\.cloud:' -SimpleMatch)
if ($cloud) { "WARNING: .cloud: lines in logs: $($cloud.Count)" }
"$Side $Mode : $result, status '$st', $([int]((Get-Date) - $t0).TotalSeconds) s -> $OutDir\$name.txt"
