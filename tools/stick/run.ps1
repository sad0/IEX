# StickLuaFunctions native-hook test (Windows): one private copy per side (EEex / IEX) of the test game with
# StickLuaFunctions installed by WeiDU, the probe (tools/stick/probe) in override, a save of <= 6 party members.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\stick\run.ps1 -Side iex [-Build <dir>] [-Refresh]
# Never saves. Only processes started from the copy are closed. Startup movies off (IEX_SKIP_INTRO=1 and the
# engine's 'Disable Movies' in the copy's Baldur.lua).
param(
    [ValidateSet('eeex', 'iex')][string]$Side = 'iex',
    [string]$Base = "E:\Dev\IEX-data\testgame\eet-2.7.3",
    [string]$SaveFrom = "$([Environment]::GetFolderPath('MyDocuments'))\Baldur's Gate - Enhanced Edition Trilogy (IEX bot)",
    [string]$SaveName = "000000678-AUTO 10-29 14h07 - AR2100 after fight",
    [string]$Mod = "E:\Dev\IEX-data\mods\stick-lua-functions\src\xbigxiangx-dot-StickLuaFunctions-5872ed0\StickLuaFunctions_v0.11.0-Alpha",
    [string]$Repo = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent),
    [string]$Build = "",
    [string]$OutDir = "E:\Dev\IEX-data\stick",
    [int]$Timeout = 420,
    [string]$Tag = '',
    [switch]$Refresh
)
$ErrorActionPreference = 'Stop'
$env:IEX_SKIP_INTRO = '1'
if (-not $Build) { $Build = "$Repo\build-stick" }
New-Item -ItemType Directory -Force $OutDir | Out-Null
$copy = "E:\Dev\IEX-data\testgame\stick$Tag-$Side"
$docsRoot = [Environment]::GetFolderPath('MyDocuments')

Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing @"
using System;
using System.Runtime.InteropServices;
public static class StkWin {
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

# 1. Copy + StickLuaFunctions (WeiDU, guarded: weidu.conf, language 0, no prompts, stdin NUL, timeout, log size cap)
if ($Refresh -or -not (Test-Path "$copy\chitin.key")) {
    & python -I "$Repo\tools\difftest\make_copy.py" $Base $copy
    if ($LASTEXITCODE) { throw 'copy failed' }
}
if (-not (Select-String -Path "$copy\WeiDU.log" -Pattern 'STICKLUAFUNCTIONS' -Quiet)) {
    Copy-Item "$Mod\StickLuaFunctions" "$copy\" -Recurse -Force
    Copy-Item "$copy\setup-EEex.exe" "$copy\setup-StickLuaFunctions.exe" -Force
    Set-Content "$copy\weidu.conf" 'lang_dir = en_US' -Encoding ascii
    if ($Side -eq 'iex') { & python -I "$Repo\tools\compat\patch_mod.py" "$copy\StickLuaFunctions" }
    $p = Start-Process "$copy\setup-StickLuaFunctions.exe" -WorkingDirectory $copy -PassThru -WindowStyle Hidden `
        -RedirectStandardInput "$Repo\tools\stick\empty.txt" -RedirectStandardOutput "$copy\stick_install.txt" `
        -ArgumentList '--language', '0', '--no-exit-pause', '--noautoupdate', '--force-install', '0', '--log', 'stick_weidu.debug', 'StickLuaFunctions/Setup-StickLuaFunctions.tp2'
    $t0 = Get-Date
    while (-not $p.HasExited) {
        Start-Sleep -Milliseconds 500
        $big = (Test-Path "$copy\stick_weidu.debug") -and (Get-Item "$copy\stick_weidu.debug").Length -gt 50MB
        if ($big -or ((Get-Date) - $t0).TotalSeconds -gt 180) { $p.Kill(); throw "WeiDU stopped (size or time limit)" }
    }
    Get-Content "$copy\stick_install.txt" | Select-Object -Last 4
    if (-not (Select-String -Path "$copy\WeiDU.log" -Pattern 'STICKLUAFUNCTIONS' -Quiet)) { throw 'StickLuaFunctions not installed' }
}

# 2. Same mods on both sides: M_ files that drive the game or need IEX are moved out.
New-Item -ItemType Directory -Force "$copy\override_off" | Out-Null
foreach ($f in 'M_I3CAM.lua', 'M_I3MOVE.lua', 'M_I3NET.lua', 'M_IEXTST.lua', 'M_ZMEMT.lua', 'M_BGBOT.lua', 'M_BGBCMB.lua', 'M_IEXFPS.lua', 'M_IEXSPL.lua', 'M_DIFFT.lua', 'M_DIFFTA.lua') {
    if (Test-Path "$copy\override\$f") { Move-Item "$copy\override\$f" "$copy\override_off\" -Force }
}
# SadoEE as in the dev game (the testgame base has an older M_SQOPT.lua without SQOPT.menu, and a missing menu
# file makes EEex_Menu_LoadFile crash the game under EEex). Copied, as tools/difftest does; same on both sides.
$modSync = 'E:\Enhanced Edition\Environnement de test\EET 2.7.3 (dev)\override'
Get-ChildItem $modSync -File | Where-Object { $_.Name -match '^(M_PS|M_SQ|SQOPT|PSX|PSTASH)' } | ForEach-Object {
    $dst = "$copy\override\$($_.Name)"
    if (-not (Test-Path $dst) -or (Get-Item $dst).Length -ne $_.Length) { Copy-Item $_.FullName $dst -Force }
}
# 3. Probe (body run inside load() + pcall: a load error never opens a popup)
$body = Get-Content "$Repo\tools\stick\probe\stkprb_body.lua" -Raw
$wrapped = "local src = [==========[`n" + $body + "`n]==========]`nlocal fn, err = (loadstring or load)(src, '=stkprb')`nlocal ok = fn ~= nil`nif fn then ok, err = pcall(fn) end`nif not ok and IEX_Log then pcall(IEX_Log, '[STKPRB] load error ' .. tostring(err)) end`nif not ok then pcall(print, 'STKPRB load error ' .. tostring(err)) end`n"
[IO.File]::WriteAllText("$copy\override\M_STKPRB.lua", $wrapped)
Copy-Item "$Repo\tools\stick\probe\STKPRB.menu" "$copy\override\" -Force
if ($Side -eq 'eeex' -and -not (Test-Path "$copy\override\M___EEex.lua")) {
    # EEex's start file: the testgame base lost it when IEX was installed (copied, as tools/difftest does)
    Copy-Item "E:\Enhanced Edition\Environnement de test\EET 2.7.3 (dev)\override\M___EEex.lua" "$copy\override\"
}
if ($Side -eq 'eeex') {
    # print() output (the probe's channel when Lua has no io) goes to InfinityLoader's log file
    $li = Get-Content "$copy\InfinityLoader.ini"
    Set-Content "$copy\InfinityLoader.ini" ($li -replace '^LogFile=.*$', 'LogFile=stick_loader.log') -Encoding ascii
}
if ($Side -eq 'iex') {
    Remove-Item "$copy\IEX.dll", "$copy\IEXLauncher.exe" -Force -ErrorAction SilentlyContinue
    Copy-Item "$Build\IEX.dll", "$Build\IEXLauncher.exe" $copy -Force
    New-Item -ItemType Directory -Force "$copy\IEX\engine" | Out-Null
    Copy-Item "$Repo\lua\*.lua" "$copy\IEX\" -Force
    Copy-Item "$Repo\ui\*.menu" "$copy\override\" -Force
    Copy-Item "$Repo\engine\*.iexd" "$copy\IEX\engine\" -Force
}
$engineName = "Baldur's Gate - Enhanced Edition Trilogy (IEX stick $Side$Tag)"
Set-Content "$copy\engine.lua" "engine_name = `"$engineName`"`r`nengine_mode = 1 -- 0 = BGEE, 1 = BG2EE, 2 = IWDEE" -Encoding ascii
$docs = "$docsRoot\$engineName"
New-Item -ItemType Directory -Force "$docs\save" | Out-Null
Get-ChildItem "$docs\save" -Directory | Remove-Item -Recurse -Force
Copy-Item "$SaveFrom\save\$SaveName" "$docs\save\000000099-STICKTEST" -Recurse -Force
$latin1 = [Text.Encoding]::GetEncoding(28591)
$ini = [IO.File]::ReadAllLines("$SaveFrom\Baldur.lua", $latin1) | Where-Object { $_ -notmatch "Disable Movies|Auto Pause State" }
[IO.File]::WriteAllText("$docs\Baldur.lua", (($ini -join "`r`n") + "`r`nSetPrivateProfileString('Program Options','Disable Movies','1')`r`nSetPrivateProfileString('Program Options','Auto Pause State','0')`r`n"), $latin1)

# 4. Run
if (Get-OwnProcs) { Get-OwnProcs | Stop-Process -Force; Start-Sleep 2 }
Remove-Item "$copy\stick_loader.log", "$copy\stick_out.txt", "$copy\stick_status.txt", "$copy\IEX\stick_out.txt", "$copy\IEX\stick_status.txt", "$copy\IEX.log" -ErrorAction SilentlyContinue
$exe = if ($Side -eq 'eeex') { "$copy\InfinityLoader.exe" } else { "$copy\IEXLauncher.exe" }
Start-Process $exe -WorkingDirectory $copy -WindowStyle Minimized
$t0 = Get-Date; $lastKey = $t0; $muted = $false; $result = 'timeout'; $placed = @{}; $shots = @{}; $menuAt = $null
function Get-Status {
    foreach ($f in "$copy\stick_status.txt", "$copy\IEX\stick_status.txt") { if (Test-Path $f) { return (Get-Content $f -Raw).Trim() } }
    if (Test-Path "$copy\stick_loader.log") {
        $l = Select-String -Path "$copy\stick_loader.log" -Pattern 'STKPRB\|STATUS (.*)' | Select-Object -Last 1
        if ($l) { return $l.Matches[0].Groups[1].Value.Trim() }
    }
    return ''
}
while (((Get-Date) - $t0).TotalSeconds -lt $Timeout) {
    Start-Sleep -Milliseconds 400
    $procs = @(Get-OwnProcs)
    foreach ($pr in $procs) {
        foreach ($w in [StkWin]::Windows([uint32]$pr.Id)) {
            $h, $cls, $title = $w.Split('|', 3)
            if ($cls -eq '#32770') { Get-OwnProcs | Stop-Process -Force -ErrorAction SilentlyContinue; $result = "popup: $title" }
            elseif ($pr.ProcessName -eq 'Baldur' -and -not $placed[$h]) { [StkWin]::OffScreen([IntPtr][int64]$h); $placed[$h] = $true }
        }
    }
    if ($result -like 'popup*') { break }
    if (-not $muted -and ($procs | Where-Object ProcessName -eq 'Baldur')) {
        Start-Sleep 2
        & powershell -NoProfile -ExecutionPolicy Bypass -File "$Repo\tools\windows\mute_games.ps1" | Out-Null
        $muted = $true
    }
    $st = Get-Status
    if (-not $menuAt -and $st -like '*screen ready*') { $menuAt = ((Get-Date) - $t0).TotalSeconds }
    if (($st -like '*screen ready*' -or $st -like 'loading*') -and ((Get-Date) - $lastKey).TotalSeconds -ge 3) {
        foreach ($h in @($placed.Keys)) { [StkWin]::F11([IntPtr][int64]$h) }
        $lastKey = Get-Date
    }
    if ($st -match '^(observe|forceHit|forceMiss|cancel|spells)$' -and ((Get-Date) - $lastKey).TotalSeconds -ge 3) {
        foreach ($h in @($placed.Keys)) { [StkWin]::Key([IntPtr][int64]$h, 0x31, 0x02); [StkWin]::Key([IntPtr][int64]$h, 0x0D, 0x1C) }
        $lastKey = Get-Date
    }
    if ($st -match '^(observe|forceHit|forceMiss|cancel|spells)$' -and -not $shots[$st]) {
        Start-Sleep 4
        foreach ($h in @($placed.Keys)) { try { [void][StkWin]::Shot([IntPtr][int64]$h, "$OutDir\$Side-$st.png") } catch {} }
        $shots[$st] = $true
    }
    if ($st -like 'DONE*') { $result = 'done'; break }
    if ($st -like 'save not found*' -or $st -like '*load error*') { $result = $st; break }
    if ($procs.Count -eq 0 -and ((Get-Date) - $t0).TotalSeconds -gt 20) { $result = "exited ($st)"; break }
}
$st = Get-Status
Get-OwnProcs | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep 2
$stamp = Get-Date -Format 'MMdd-HHmm'
foreach ($f in "$copy\stick_out.txt", "$copy\IEX\stick_out.txt") { if (Test-Path $f) { Copy-Item $f "$OutDir\$Side$Tag-$stamp.txt" -Force } }
if (Test-Path "$copy\stick_loader.log") {
    Copy-Item "$copy\stick_loader.log" "$OutDir\$Side$Tag-$stamp.loader.log" -Force
    $o = Get-Content "$copy\stick_loader.log" -Encoding utf8 | Where-Object { $_ -match 'STKPRB\|OUT ' } | ForEach-Object { $_.Substring($_.IndexOf('STKPRB|OUT ') + 11) }
    if ($o) { [IO.File]::WriteAllLines("$OutDir\$Side$Tag-$stamp.txt", [string[]]@($o)) }
}
if (Test-Path "$copy\IEX.log") { Copy-Item "$copy\IEX.log" "$OutDir\$Side$Tag-$stamp.IEX.log" -Force }
"$Side : $result, status '$st', start screen at $menuAt s, $([int]((Get-Date) - $t0).TotalSeconds) s -> $OutDir\$Side-$stamp.txt"
