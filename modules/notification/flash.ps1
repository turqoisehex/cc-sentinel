# Drain stdin (CC pipes JSON to hooks; prevents caller blocking)
try { [Console]::In.ReadToEnd() | Out-Null } catch {}

# R2D2-style sounds (simplified)

function Boop { [console]::beep((Get-Random -Min 400 -Max 800), (Get-Random -Min 80 -Max 150)) }
function Beep { [console]::beep((Get-Random -Min 1800 -Max 2400), (Get-Random -Min 40 -Max 100)) }
function Chirp { [console]::beep((Get-Random -Min 1200 -Max 1800), (Get-Random -Min 50 -Max 120)) }

$sounds = @(
    { Boop },
    { Beep },
    { Chirp }
)

$count = Get-Random -Minimum 1 -Maximum 5
for ($i = 0; $i -lt $count; $i++) {
    $sound = $sounds | Get-Random
    & $sound
    if ($i -lt $count - 1) { Start-Sleep -Milliseconds (Get-Random -Min 30 -Max 100) }
}

# Flash taskbar
Add-Type @"
using System;
using System.Runtime.InteropServices;

public class WindowFlasher {
    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool FlashWindowEx(ref FLASHWINFO pwfi);

    [StructLayout(LayoutKind.Sequential)]
    public struct FLASHWINFO {
        public uint cbSize;
        public IntPtr hwnd;
        public uint dwFlags;
        public uint uCount;
        public uint dwTimeout;
    }

    public const uint FLASHW_ALL = 3;

    public static void Flash(IntPtr hwnd) {
        FLASHWINFO fInfo = new FLASHWINFO();
        fInfo.cbSize = (uint)Marshal.SizeOf(fInfo);
        fInfo.hwnd = hwnd;
        fInfo.dwFlags = FLASHW_ALL;
        fInfo.uCount = 5;
        fInfo.dwTimeout = 0;
        FlashWindowEx(ref fInfo);
    }
}
"@

$wt = Get-Process -Name "WindowsTerminal" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($wt -and $wt.MainWindowHandle -ne [IntPtr]::Zero) {
    [WindowFlasher]::Flash($wt.MainWindowHandle)
}
