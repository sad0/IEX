# Differential test: runs the same probe (tools/difftest/probe) on the same save under real EEex and under IEX,
# then compares the results (compare.py).
#   powershell -NoProfile -ExecutionPolicy Bypass -File E:\Dev\IEX\tools\difftest\run.ps1 [-Runs 2] [-Sides eeex,iex]
# Two private copies of the base game (hardlinked data, real copies of everything written), each with its own
# Documents folder (unique engine_name), seeded with the same Baldur.lua and save. Only processes started from
# the copies are ever closed.
param(
    [string]$Base = "E:\Dev\IEX-data\testgame\eet-2.7.3",
    [string]$SaveFrom = "$([Environment]::GetFolderPath('MyDocuments'))\Baldur's Gate - Enhanced Edition Trilogy (IEX bot)",
    # EEex's own start file (override/M___EEex.lua): the testgame bases lost it when IEX was installed. Copied, never read.
    [string]$ModSync = "E:\Enhanced Edition\Environnement de test\EET 2.7.3 (dev)\override",
    [string]$EEexMain = "E:\Enhanced Edition\Environnement de test\EET 2.7.3 (dev)\override\M___EEex.lua",
    [string]$SaveName = "000000678-AUTO 10-29 14h07 - AR2100 after fight",
    [string]$Build = "",  # default: <Repo>\build-diff
    [string[]]$Sides = @('eeex', 'iex'),
    [int]$Runs = 2,
    [int]$Timeout = 360,
    [int]$MaxRetries = 4,
    [switch]$Refresh,
    [switch]$NoCompare,
    # Focus run: only these probe steps (probe/difft_body.lua DT.FOCUS_STEPS / STEPS names), no cases.
    [string]$Focus = '',
    # Private pair of copies (difftest-<Tag>-eeex / -iex, own Documents folders) so several agents can run at once.
    [string]$Tag = '',
    # Repository whose probe, lua/ and engine/ are used (default: the one this script is in, e.g. a worktree).
    [string]$Repo = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent),
    # Screenshots: the probe holds its UI steps (world, ESC menu, options screen) HoldMs and the runner saves a PNG
    # of the game window for each (<OutDir>\<side>-run<n>-<step>.png).
    [int]$HoldMs = 0,
    # Modules mode: the probe skips the cases and observes the player modules / menu API (status 'input ...' asks
    # for background key and mouse input, sent here).
    [switch]$Modules,
    # Modules mode: only these steps (comma list, e.g. the options UI steps ouWorld,ouEsc,...).
    [string]$ModSteps = '',
    [string]$OutDir = ""  # default: IEX-data\difftest\<date>[-<Tag>]
)
$ErrorActionPreference = 'Stop'
# No startup movies (logo / intro): IEX reads IEX_SKIP_INTRO (inherited by the game), and both sides get the
# engine's own 'Disable Movies' in their Baldur.lua (Reset-Docs).
$env:IEX_SKIP_INTRO = '1'
$env:DIFFT_FOCUS = $Focus  # read by gen_cases.py
$Sides = @($Sides | ForEach-Object { $_ -split ',' } | Where-Object { $_ })  # -File passes 'iex,eeex' as one string
$repo = $Repo
$here = "$repo\tools\difftest"
$docs = [Environment]::GetFolderPath('MyDocuments')
if (-not $Build) { $Build = "$repo\build-diff" }
if (-not $OutDir) {
    $OutDir = "E:\Dev\IEX-data\difftest\$(Get-Date -Format yyyy-MM-dd)"
    if ($Tag) { $OutDir += "-$Tag" }
}
New-Item -ItemType Directory -Force $OutDir | Out-Null

# M_ files that need IEX (or drive the game: the bot) are moved out of both copies: under EEex a Lua error in an
# M_ file opens a modal popup, and both sides must run the same mods.
$offFiles = 'M_I3CAM.lua', 'M_I3MOVE.lua', 'M_I3NET.lua', 'M_IEXTST.lua', 'M_ZMEMT.lua', 'M_BGBOT.lua', 'M_BGBCMB.lua',
    'M_IEXFPS.lua', 'M_IEXSPL.lua'

# INI values the options cases read (keys absent from the seed are "fresh").
$iniSeed = @"
SetPrivateProfileString('DiffTest','Pre0','0')
SetPrivateProfileString('DiffTest','Pre1','1')
SetPrivateProfileString('DiffTest','Pre7','7')
SetPrivateProfileString('DiffTest','PreStr','abc')
SetPrivateProfileString('SadoQoL','Stash Tints','0')
SetPrivateProfileString('SadoQoL','FPS','0')
SetPrivateProfileString('SadoQoL','Passive Traps','0')
"@
if ($HoldMs -gt 0) { $iniSeed += "`r`nSetPrivateProfileString('DiffTest','HoldMs','$HoldMs')" }
if ($Modules) { $iniSeed += "`r`nSetPrivateProfileString('DiffTest','Modules','1')" }
if ($ModSteps) { $iniSeed += "`r`nSetPrivateProfileString('DiffTest','ModSteps','$ModSteps')" }
# SadoEE's valuable containers replace the Empty Container module's callback: off while the modules are observed
if ($Modules) { $offFiles += 'M_SQCONT.lua' }

Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing @"
using System;
using System.Runtime.InteropServices;
public static class DiffTWin {
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int l, t, r, b; }
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int x, y; }
    [StructLayout(LayoutKind.Sequential)] public struct WINDOWPLACEMENT {
        public int length, flags, showCmd; public POINT minPos, maxPos; public RECT normal; }
    [DllImport("user32.dll")] public static extern bool GetWindowPlacement(IntPtr h, ref WINDOWPLACEMENT wp);
    [DllImport("user32.dll")] public static extern bool SetWindowPlacement(IntPtr h, ref WINDOWPLACEMENT wp);
    // A minimized game renders at a fraction of a frame per second: the window is restored off screen instead,
    // without activation, so it runs at full speed and never shows on the desktop.
    public static void OffScreen(IntPtr h) {
        var wp = new WINDOWPLACEMENT(); wp.length = Marshal.SizeOf(wp);
        GetWindowPlacement(h, ref wp);
        int w = wp.normal.r - wp.normal.l, ht = wp.normal.b - wp.normal.t;
        wp.normal.l = -6000; wp.normal.t = -6000; wp.normal.r = -6000 + w; wp.normal.b = -6000 + ht;
        wp.showCmd = 4; // SW_SHOWNOACTIVATE
        SetWindowPlacement(h, ref wp);
    }
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc f, IntPtr l);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, System.Text.StringBuilder s, int n);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr h, System.Text.StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    // F11 as a background key press (WM_KEYDOWN / WM_KEYUP posted to the window: no focus change).
    // F10 down, F10 down again as an auto-repeat (lParam bit 30: key was already down), F10 up: key listener args.
    public static void F10Repeat(IntPtr h) {
        PostMessage(h, 0x100, (IntPtr)0x79, (IntPtr)(1 | (0x44 << 16)));
        System.Threading.Thread.Sleep(80);
        PostMessage(h, 0x100, (IntPtr)0x79, (IntPtr)(1 | (0x44 << 16) | (1 << 30)));
        System.Threading.Thread.Sleep(80);
        PostMessage(h, 0x101, (IntPtr)0x79, (IntPtr)unchecked((int)(0xC0000001 | (0x44 << 16))));
    }
    public static void F11(IntPtr h) {
        PostMessage(h, 0x100, (IntPtr)0x7A, (IntPtr)(1 | (0x57 << 16)));
        System.Threading.Thread.Sleep(60);
        PostMessage(h, 0x101, (IntPtr)0x7A, (IntPtr)unchecked((int)(0xC0000001 | (0x57 << 16))));
    }
    // Background input for the modules mode: key down / up (WM_SYSKEY* for Alt) and mouse moves, posted.
    public static void Key(IntPtr h, int vk, int scan, bool down) {
        bool sys = vk == 0x12;
        uint msg = down ? (sys ? 0x104u : 0x100u) : (sys ? 0x105u : 0x101u);
        long lp = 1 | ((long)scan << 16) | (sys ? (1L << 29) : 0) | (down ? 0 : (3L << 30));
        PostMessage(h, msg, (IntPtr)vk, (IntPtr)unchecked((int)lp));
    }
    public static void Mouse(IntPtr h, double fx, double fy) {
        RECT r; GetClientRect(h, out r);
        int x = (int)((r.r - r.l) * fx), y = (int)((r.b - r.t) * fy);
        PostMessage(h, 0x200, IntPtr.Zero, (IntPtr)((y << 16) | (x & 0xffff)));
    }
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
    // The window's client area as a PNG (PW_RENDERFULLCONTENT: works for a GL window restored off screen).
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
    # Path read once: a process exiting meanwhile (another agent's game) gives $null on a second read
    Get-Process -ErrorAction SilentlyContinue | Where-Object { $path = $_.Path; $path -and $path.StartsWith($dir, 'OrdinalIgnoreCase') }
}

# The probe's status: a file (io or IEX_WriteFile) or the last DIFFT|STATUS line of the loader log.
function Get-Status($copy) {
    foreach ($f in "$copy\difftest_status.txt", "$copy\IEX\difftest_status.txt") {
        if (Test-Path $f) { return (Get-Content $f -Raw).Trim() }
    }
    if (Test-Path "$copy\difftest_loader.log") {
        $l = Select-String -Path "$copy\difftest_loader.log" -Pattern 'DIFFT\|STATUS (.*)|probe load error.*' | Select-Object -Last 1
        if ($l) { if ($l.Matches[0].Groups[1].Success) { return $l.Matches[0].Groups[1].Value.Trim() } else { return $l.Matches[0].Value } }
    }
    return ''
}

function Prepare-Side($side) {
    $tagPart = if ($Tag) { "$Tag-" } else { '' }
    $copy = "E:\Dev\IEX-data\testgame\difftest-$tagPart$side"
    if ($Refresh -or -not (Test-Path "$copy\chitin.key")) {
        & python -I "$here\make_copy.py" $Base $copy
        if ($LASTEXITCODE) { throw "copy failed" }
    }
    # No Steam connection in a copy: connected, the engine syncs saves with Steam Cloud (downloads every cloud save at
    # startup, uploads each save it writes, so a probe save reached the user's real game folders). Without the app id
    # file SteamAPI_Init fails and the game runs offline (cloud off, CPlatform::CloudSaveEnabled).
    Remove-Item "$copy\steam_appid.txt" -Force -ErrorAction SilentlyContinue
    $label = if ($side -eq 'eeex') { 'EEex' } else { 'IEX' }
    $tagLabel = if ($Tag) { " $Tag" } else { '' }
    $engineName = "Baldur's Gate - Enhanced Edition Trilogy (IEX difftest$tagLabel $label)"
    Set-Content "$copy\engine.lua" "engine_name = `"$engineName`"`r`nengine_mode = 1 -- 0 = BGEE, 1 = BG2EE, 2 = IWDEE" -Encoding ascii
    New-Item -ItemType Directory -Force "$copy\override_off" | Out-Null
    foreach ($f in $offFiles) { if (Test-Path "$copy\override\$f") { Move-Item "$copy\override\$f" "$copy\override_off\" -Force } }
    # SadoEE as in the dev game (the testgame base has an older M_SQOPT.lua and lacks SQOPT.menu: a missing menu
    # file makes EEex_Menu_LoadFile crash the game under EEex). Same files in both copies; copied, never linked.
    if ($ModSync -and (Test-Path $ModSync)) {
        Get-ChildItem $ModSync -File | Where-Object { $_.Name -match '^(M_PS|M_SQ|SQOPT|PSX|PSTASH)' -and $offFiles -notcontains $_.Name } | ForEach-Object {
            $dst = "$copy\override\$($_.Name)"
            if (-not (Test-Path $dst) -or (Get-Item $dst).Length -ne $_.Length) { Copy-Item $_.FullName $dst -Force }
        }
    }
    & python -I "$here\gen_cases.py" "$copy\override"
    if ($LASTEXITCODE) { throw "probe install failed" }
    if ($side -eq 'eeex') {
        if (-not (Test-Path "$copy\override\M___EEex.lua")) { Copy-Item $EEexMain "$copy\override\M___EEex.lua" }
        # print() output (the probe's last-resort channel) goes to InfinityLoader's log file
        $li = Get-Content "$copy\InfinityLoader.ini"
        $li = $li -replace '^LogFile=.*$', 'LogFile=difftest_loader.log'
        Set-Content "$copy\InfinityLoader.ini" $li -Encoding ascii
    }
    if ($side -eq 'iex') {
        # removed first: a hardlinked file would be overwritten for every copy sharing it
        Remove-Item "$copy\IEX.dll", "$copy\IEXLauncher.exe" -Force -ErrorAction SilentlyContinue
        Copy-Item "$Build\IEX.dll", "$Build\IEXLauncher.exe" $copy -Force
        foreach ($f in 'IEX.dll', 'IEXLauncher.exe') {
            if ((Get-FileHash "$Build\$f").Hash -ne (Get-FileHash "$copy\$f").Hash) { throw "$f copy differs from the build" }
        }
        New-Item -ItemType Directory -Force "$copy\IEX\engine" | Out-Null
        Copy-Item "$repo\lua\*.lua" "$copy\IEX\" -Force
        Copy-Item "$repo\ui\*.menu" "$copy\override\" -Force  # IEX.tp2 installs them there
        & python -I "$repo\tools\compat\api_list.py" "$copy\IEX\IEX_API.txt" | Out-Null
        Copy-Item "$repo\engine\*.iexd" "$copy\IEX\engine\" -Force
    }
    return @{ copy = $copy; docs = "$docs\$engineName" }
}

function Reset-Docs($d, $side) {
    New-Item -ItemType Directory -Force "$d\save" | Out-Null
    Get-ChildItem "$d\save" -Directory | Remove-Item -Recurse -Force
    Copy-Item "$SaveFrom\save\$SaveName" "$d\save\000000099-DIFFTEST" -Recurse -Force
    $latin1 = [Text.Encoding]::GetEncoding(28591)  # byte-preserving
    $ini = [IO.File]::ReadAllLines("$SaveFrom\Baldur.lua", $latin1) | Where-Object { $_ -notmatch "^SetPrivateProfileString\('(DiffTest|SadoQoL)'" }
    $seed = $iniSeed
    # Both sides: an IEX build older than the Skip Intro option ignores IEX_SKIP_INTRO.
    $seed += "`r`nSetPrivateProfileString('Program Options','Disable Movies','1')"
    [IO.File]::WriteAllText("$d\Baldur.lua", (($ini -join "`r`n") + "`r`n" + $seed + "`r`n"), $latin1)  # no BOM: Baldur.lua is run as Lua
}

function Run-Once($side, $p, $n) {
    $copy = $p.copy
    if (Get-OwnProcs $copy) { Get-OwnProcs $copy | Stop-Process -Force; Start-Sleep 2 }
    Reset-Docs $p.docs $side
    Remove-Item "$copy\difftest_out.txt", "$copy\difftest_status.txt", "$copy\IEX\difftest_out.txt", "$copy\IEX\difftest_status.txt", "$copy\difftest_loader.log" -ErrorAction SilentlyContinue
    $exe = if ($side -eq 'eeex') { "$copy\InfinityLoader.exe" } else { "$copy\IEXLauncher.exe" }
    $crashBefore = @(Get-ChildItem "$copy\InfinityLoader_Crash\*.log", "$copy\IEX_crash*" -ErrorAction SilentlyContinue).Count
    Start-Process $exe -WorkingDirectory $copy -WindowStyle Minimized
    $t0 = Get-Date; $lastKey = $t0; $keyTested = $false; $muted = $false; $result = 'timeout'; $minimized = @{}; $shots = @{}
    while (((Get-Date) - $t0).TotalSeconds -lt $Timeout) {
        Start-Sleep -Milliseconds 250  # a crash / error popup is closed (process killed) within a second
        $procs = @(Get-OwnProcs $copy)
        foreach ($pr in $procs) {
            foreach ($w in [DiffTWin]::Windows([uint32]$pr.Id)) {
                $h, $cls, $title = $w.Split('|', 3)
                # the game window is SDL's 'SDL_app'; any other visible top-level window of a test process (message
                # box, loader crash box, SDL message box) is a popup
                if ($cls -ne 'SDL_app' -and $cls -ne 'ConsoleWindowClass' -and $cls -ne 'CASCADIA_HOSTING_WINDOW_CLASS') {
                    # a message box (crash / Lua error popup): never leave it on the maintainer's screen
                    # (killed at once; the crash log / loader log say what happened)
                    Get-OwnProcs $copy | Stop-Process -Force -ErrorAction SilentlyContinue
                    "  popup in $($pr.ProcessName): '$title' -> our process closed"
                    $result = "popup: $title"
                } elseif ($pr.ProcessName -eq 'Baldur' -and -not $minimized[$h]) {
                    [DiffTWin]::OffScreen([IntPtr][int64]$h)
                    $minimized[$h] = $true
                }
            }
        }
        # a native crash: the loader writes its crash log before any popup shows: the process is closed at once
        $crashNow = @(Get-ChildItem "$copy\InfinityLoader_Crash\*.log", "$copy\IEX_crash*" -ErrorAction SilentlyContinue).Count
        if ($crashNow -gt $crashBefore) {
            Get-OwnProcs $copy | Stop-Process -Force -ErrorAction SilentlyContinue
            "  crash log written -> our process closed"
            $result = 'popup: crash log'
        }
        if ($result -like 'popup*') { break }
        if (-not $muted -and ($procs | Where-Object ProcessName -eq 'Baldur')) {
            Start-Sleep 3
            & powershell -NoProfile -ExecutionPolicy Bypass -File "$repo\tools\windows\mute_games.ps1" | Out-Null
            $muted = $true
        }
        $st = Get-Status $copy
        if (($st -like '*screen ready*' -or $st -like 'loading*' -or $st -like 'savekey*') -and ((Get-Date) - $lastKey).TotalSeconds -ge 3) {
            foreach ($h in @($minimized.Keys)) { [DiffTWin]::F11([IntPtr][int64]$h) }
            $lastKey = Get-Date
        }
        if ($st -like 'keytest*' -and -not $keyTested) {
            foreach ($h in @($minimized.Keys)) { [DiffTWin]::F10Repeat([IntPtr][int64]$h) }
            $keyTested = $true
        }
        if ($st -like 'input *' -and -not $shots[$st]) {
            $shots[$st] = $true
            $parts = $st -split ' '
            foreach ($h in @($minimized.Keys)) {
                $hw = [IntPtr][int64]$h
                switch ($parts[2]) {
                    'kd' { [DiffTWin]::Key($hw, [Convert]::ToInt32($parts[3], 16), [Convert]::ToInt32($parts[4], 16), $true) }
                    'ku' { [DiffTWin]::Key($hw, [Convert]::ToInt32($parts[3], 16), [Convert]::ToInt32($parts[4], 16), $false) }
                    'mm' { [DiffTWin]::Mouse($hw, [double]::Parse($parts[3], [Globalization.CultureInfo]::InvariantCulture), [double]::Parse($parts[4], [Globalization.CultureInfo]::InvariantCulture)) }
                }
            }
            "  input $($parts[2..4] -join ' ')"
        }
        if ($st -like 'hold *' -and -not $shots[$st]) {
            Start-Sleep -Milliseconds 700
            $tag = ($st -replace '^hold ', '') -replace '[^\w.-]', '_'
            foreach ($h in @($minimized.Keys)) {
                $png = "$OutDir\$side-run$n-$tag.png"
                try { if ([DiffTWin]::Shot([IntPtr][int64]$h, $png)) { "  screenshot $png" } } catch { "  screenshot failed: $_" }
            }
            $shots[$st] = $true
        }
        if ($st -like 'DONE*') { $result = 'done'; break }
        if ($st -like 'save not found*' -or $st -like 'probe load error*') { $result = $st; break }
        if ($procs.Count -eq 0 -and ((Get-Date) - $t0).TotalSeconds -gt 20) { $result = "exited ($st)"; break }
    }
    $st = Get-Status $copy
    Get-OwnProcs $copy | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep 2
    $dest = "$OutDir\$side-run$n.txt"
    if (Test-Path "$copy\difftest_out.txt") { Copy-Item "$copy\difftest_out.txt" $dest -Force }
    elseif (Test-Path "$copy\IEX\difftest_out.txt") { Copy-Item "$copy\IEX\difftest_out.txt" $dest -Force }
    elseif (Test-Path "$copy\difftest_loader.log") {
        $l = [Collections.Generic.List[string]]::new()
        foreach ($x in (Get-Content "$copy\difftest_loader.log" -Encoding utf8)) {
            if ($x -match 'DIFFT\|\{') { $l.Add($x.Substring($x.IndexOf('DIFFT|') + 6)) }
            elseif ($x -match 'DIFFT~\|' -and $l.Count) { $l[$l.Count - 1] += $x.Substring($x.IndexOf('DIFFT~|') + 7) }
        }
        [IO.File]::WriteAllLines($dest, [string[]]@($l))
    } else { Set-Content $dest '' }
    if (Test-Path "$copy\difftest_loader.log") { Copy-Item "$copy\difftest_loader.log" "$OutDir\$side-run$n.loader.log" -Force }
    # saves the probe wrote (private Documents folder): kept for the save format diffs
    Get-ChildItem "$($p.docs)\save" -Directory -ErrorAction SilentlyContinue | Where-Object Name -ne '000000099-DIFFTEST' | ForEach-Object {
        New-Item -ItemType Directory -Force "$OutDir\$side-run$n-saves" | Out-Null
        Copy-Item $_.FullName "$OutDir\$side-run$n-saves\" -Recurse -Force
    }
    if ($side -eq 'iex' -and (Test-Path "$copy\IEX.log")) { Copy-Item "$copy\IEX.log" "$OutDir\iex-run$n.IEX.log" -Force }
    if ($result -like 'popup*' -and (Test-Path "$OutDir\$side-run$n.loader.log")) {
        $tr = Select-String -Path "$OutDir\$side-run$n.loader.log" -Pattern 'DIFFT\|TRACE (.*)' | Select-Object -Last 1
        if ($tr -and $tr.Matches[0].Groups[1].Value -notlike '(*') {
            $bad = $tr.Matches[0].Groups[1].Value.Trim()
            if ((Get-Content "$here\skip.txt") -contains $bad) {
                $result = "crash in case '$bad' again although skipped: stopping"
            } else {
                Add-Content "$here\skip.txt" $bad
                $result = "crash in case '$bad' (added to skip.txt)"
            }
        }
    }
    $lines = (Get-Content $dest | Measure-Object -Line).Lines
    "$side run $n : $result, status '$st', $lines lines, $([int]((Get-Date) - $t0).TotalSeconds) s"
    return $result
}

foreach ($side in $Sides) {
    $p = Prepare-Side $side
    for ($n = 1; $n -le $Runs; $n++) {
        # a case that crashes the engine goes to skip.txt; the run is redone without it (both sides skip it)
        for ($try = 1; $try -le $MaxRetries; $try++) {
            $r = Run-Once $side $p $n
            $r | Select-Object -SkipLast 1 | Write-Output
            if ("$r" -notmatch 'added to skip.txt') { break }
            & python -I "$here\gen_cases.py" "$($p.copy)\override" | Out-Null
        }
    }
}
if (-not $NoCompare) {
    & python -I "$here\compare.py" $OutDir
}
