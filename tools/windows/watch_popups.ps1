# Waits until a test game (Baldur.exe / InfinityLoader / IEXLauncher under -PathLike) shows a dialog window
# (Lua error, crash report, InfinityLoader crash popup...), prints it and exits 0. Exits 1 after -Minutes.
# Usage: powershell -ExecutionPolicy Bypass -File watch_popups.ps1 [-PathLike '*\IEX-data\testgame\*'] [-Minutes 600]
param(
    [string]$PathLike = '*\IEX-data\testgame\*',
    [int]$Minutes = 600,
    [string[]]$Ignore = @()
)

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class PopupScan {
    delegate bool EnumProc(IntPtr hwnd, IntPtr lParam);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb, IntPtr lParam);
    [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr parent, EnumProc cb, IntPtr lParam);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hwnd);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr hwnd, StringBuilder s, int n);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr hwnd, StringBuilder s, int n);

    static string Text(IntPtr h) { var s = new StringBuilder(2048); GetWindowText(h, s, s.Capacity); return s.ToString(); }
    static string Cls(IntPtr h) { var s = new StringBuilder(256); GetClassName(h, s, s.Capacity); return s.ToString(); }

    // Visible popup windows owned by one of the pids: "pid|hwnd|class|title|text".
    public static List<string> Find(uint[] pids) {
        var found = new List<string>();
        EnumWindows((h, l) => {
            uint pid; GetWindowThreadProcessId(h, out pid);
            if (Array.IndexOf(pids, pid) < 0 || !IsWindowVisible(h)) return true;
            // The game window itself is SDL's "SDL_app"; any other visible top-level window (#32770 dialogs,
            // SDL message boxes, loader crash boxes) is a popup.
            var cls = Cls(h);
            if (cls == "SDL_app" || cls == "ConsoleWindowClass" || cls == "CASCADIA_HOSTING_WINDOW_CLASS") return true;
            var body = new StringBuilder();
            EnumChildWindows(h, (c, l2) => { if (Cls(c) == "Static") { var t = Text(c); if (t.Length > 0) body.Append(t).Append(" / "); } return true; }, IntPtr.Zero);
            found.Add(pid + "|0x" + h.ToString("X") + "|" + cls + "|" + Text(h) + "|" + body.ToString().Replace("\r", " ").Replace("\n", " "));
            return true;
        }, IntPtr.Zero);
        return found;
    }
}
'@

$deadline = (Get-Date).AddMinutes($Minutes)
while ((Get-Date) -lt $deadline) {
    $procs = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -like $PathLike })
    if ($procs.Count -gt 0) {
        $pids = [uint32[]]@($procs | ForEach-Object { [uint32]$_.Id })
        $hits = @([PopupScan]::Find($pids) | Where-Object { $h = $_; -not ($Ignore | Where-Object { $h -like "*$_*" }) })
        if ($hits.Count -gt 0) {
            foreach ($hit in $hits) {
                $p = $hit.Split('|')[0]
                $path = ($procs | Where-Object { $_.Id -eq [int]$p } | Select-Object -First 1).Path
                Write-Output "POPUP $hit | $path"
            }
            exit 0
        }
    }
    Start-Sleep -Seconds 3
}
Write-Output "no popup in $Minutes min"
exit 1
