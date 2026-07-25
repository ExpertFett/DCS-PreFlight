# Native.ps1 - shared Win32 helpers for the DCS Pre-Flight tool.
# Provides: mouse click-at, global key polling (for the recorder), and
# find/foreground a window by partial title (for conditional clicks + popups).
# Dot-source this from the engine and the manager.

if (-not ('PfNative' -as [type])) {
@"
using System;
using System.Text;
using System.Runtime.InteropServices;

public class PfNative {
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X; public int Y; }

    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, IntPtr dwExtraInfo);
    [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vKey);
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
    [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
    [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr hwnd, uint flags);
    [DllImport("user32.dll", CharSet = CharSet.Auto)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr l);

    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    const uint LEFTDOWN = 0x0002, LEFTUP = 0x0004;
    const uint GA_ROOT = 2;

    public static void ClickAt(int x, int y) {
        SetCursorPos(x, y);
        System.Threading.Thread.Sleep(60);
        mouse_event(LEFTDOWN, 0, 0, 0, IntPtr.Zero);
        System.Threading.Thread.Sleep(40);
        mouse_event(LEFTUP, 0, 0, 0, IntPtr.Zero);
    }

    public static string TitleOf(IntPtr h) {
        StringBuilder sb = new StringBuilder(512);
        GetWindowText(h, sb, sb.Capacity);
        return sb.ToString();
    }

    public static string WindowTitleAtCursor() {
        POINT p; GetCursorPos(out p);
        IntPtr h = WindowFromPoint(p);
        if (h == IntPtr.Zero) return "";
        IntPtr root = GetAncestor(h, GA_ROOT);
        return TitleOf(root == IntPtr.Zero ? h : root);
    }

    public static IntPtr FindWindow(string substr) {
        IntPtr found = IntPtr.Zero;
        string needle = (substr == null ? "" : substr).ToLowerInvariant();
        if (needle.Length == 0) return IntPtr.Zero;
        EnumWindows(delegate(IntPtr h, IntPtr l) {
            if (!IsWindowVisible(h)) return true;
            string t = TitleOf(h);
            if (t.Length > 0 && t.ToLowerInvariant().Contains(needle)) { found = h; return false; }
            return true;
        }, IntPtr.Zero);
        return found;
    }
}
"@ | ForEach-Object { Add-Type -TypeDefinition $_ -ErrorAction Stop }
}
