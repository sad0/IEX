# Mutes (or unmutes) the audio of running Baldur.exe test games, per process (Windows volume mixer sessions).
# Usage: powershell -ExecutionPolicy Bypass -File mute_games.ps1 [-PathLike '*\IEX-data\testgame\*'] [-Unmute]
# Only games whose executable path matches -PathLike are touched (default: IEX test copies). A restarted game
# gets a new audio session: run the script again after launching it.
param(
    [string]$PathLike = '*\IEX-data\testgame\*',
    [switch]$Unmute
)

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class GameMute {
    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class MMDeviceEnumerator {}

    [Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDeviceEnumerator {
        int EnumAudioEndpoints(int dataFlow, int stateMask, out IntPtr devices);
        int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice device);
    }

    [Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDevice {
        int Activate(ref Guid iid, int clsCtx, IntPtr activationParams, [MarshalAs(UnmanagedType.IUnknown)] out object iface);
    }

    [Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioSessionManager2 {
        int GetAudioSessionControl(IntPtr sessionGuid, int flags, out IntPtr control);
        int GetSimpleAudioVolume(IntPtr sessionGuid, int flags, out IntPtr volume);
        int GetSessionEnumerator(out IAudioSessionEnumerator sessions);
    }

    [Guid("E2F5BB11-0570-40CA-ACDD-3AA01277DEE8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioSessionEnumerator {
        int GetCount(out int count);
        int GetSession(int index, out IAudioSessionControl2 session);
    }

    [Guid("BFB7FF88-7239-4FC9-8FA2-07C950BE9C6D"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioSessionControl2 {
        int GetState(out int state);
        int GetDisplayName(out IntPtr name);
        int SetDisplayName(IntPtr name, IntPtr context);
        int GetIconPath(out IntPtr path);
        int SetIconPath(IntPtr path, IntPtr context);
        int GetGroupingParam(out Guid param);
        int SetGroupingParam(ref Guid param, IntPtr context);
        int RegisterAudioSessionNotification(IntPtr client);
        int UnregisterAudioSessionNotification(IntPtr client);
        int GetSessionIdentifier(out IntPtr id);
        int GetSessionInstanceIdentifier(out IntPtr id);
        int GetProcessId(out uint pid);
    }

    [Guid("87CE5498-68D6-44E5-9215-6DA47EF883D8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface ISimpleAudioVolume {
        int SetMasterVolume(float level, ref Guid context);
        int GetMasterVolume(out float level);
        int SetMute(bool mute, ref Guid context);
        int GetMute(out bool mute);
    }

    // Sets the mute state of every audio session (default render device) owned by one of the given processes.
    // Returns the number of sessions changed.
    public static int SetMute(uint[] pids, bool mute) {
        var enumerator = (IMMDeviceEnumerator)(new MMDeviceEnumerator());
        IMMDevice device;
        Marshal.ThrowExceptionForHR(enumerator.GetDefaultAudioEndpoint(0, 1, out device));
        Guid iid = typeof(IAudioSessionManager2).GUID;
        object o;
        Marshal.ThrowExceptionForHR(device.Activate(ref iid, 23, IntPtr.Zero, out o));
        var manager = (IAudioSessionManager2)o;
        IAudioSessionEnumerator sessions;
        Marshal.ThrowExceptionForHR(manager.GetSessionEnumerator(out sessions));
        int count, changed = 0;
        sessions.GetCount(out count);
        Guid ctx = Guid.Empty;
        for (int i = 0; i < count; i++) {
            IAudioSessionControl2 session;
            if (sessions.GetSession(i, out session) != 0) continue;
            uint pid;
            session.GetProcessId(out pid);
            if (Array.IndexOf(pids, pid) < 0) continue;
            var volume = session as ISimpleAudioVolume;
            if (volume != null && volume.SetMute(mute, ref ctx) == 0) changed++;
        }
        return changed;
    }
}
'@

$games = @(Get-Process Baldur -ErrorAction SilentlyContinue | Where-Object { $_.Path -like $PathLike })
if ($games.Count -eq 0) { Write-Output "No running game matches $PathLike"; exit 0 }
$pids = [uint32[]]@($games | ForEach-Object { [uint32]$_.Id })
$n = [GameMute]::SetMute($pids, -not $Unmute)
$state = if ($Unmute) { 'unmuted' } else { 'muted' }
foreach ($g in $games) { Write-Output "$($g.Id) $($g.Path)" }
Write-Output "$n audio session(s) $state"
