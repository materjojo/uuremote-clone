using System;
using System.Runtime.InteropServices;

namespace UURemoteClone;

/// <summary>
/// Windows 被控端输入注入：SendInput（官方 Windows 端同样走 SendInput）。
/// 鼠标使用绝对坐标（归一化 0..1 映射到虚拟桌面），键盘走 Unicode 注入。
/// </summary>
public static class InputInjector
{
    [StructLayout(LayoutKind.Sequential)]
    private struct POINT { public int x; public int y; }

    [StructLayout(LayoutKind.Sequential)]
    private struct MOUSEINPUT
    {
        public int dx, dy;
        public uint mouseData, dwFlags, time;
        public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct KEYBDINPUT
    {
        public ushort wVk, wScan;
        public uint dwFlags, time;
        public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct HARDWAREINPUT { public uint uMsg; public ushort wParamL, wParamH; }

    [StructLayout(LayoutKind.Explicit)]
    private struct INPUTUNION
    {
        [FieldOffset(0)] public MOUSEINPUT mi;
        [FieldOffset(0)] public KEYBDINPUT ki;
        [FieldOffset(0)] public HARDWAREINPUT hi;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct INPUT { public uint type; public INPUTUNION U; }

    private const uint INPUT_MOUSE = 0;
    private const uint INPUT_KEYBOARD = 1;

    private const uint MOUSEEVENTF_MOVE = 0x0001;
    private const uint MOUSEEVENTF_ABSOLUTE = 0x8000;
    private const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
    private const uint MOUSEEVENTF_LEFTUP = 0x0004;
    private const uint MOUSEEVENTF_RIGHTDOWN = 0x0008;
    private const uint MOUSEEVENTF_RIGHTUP = 0x0010;
    private const uint MOUSEEVENTF_WHEEL = 0x0800;

    private const uint KEYEVENTF_UNICODE = 0x0004;
    private const uint KEYEVENTF_KEYUP = 0x0002;

    private const int SM_XVIRTUALSCREEN = 76;
    private const int SM_YVIRTUALSCREEN = 77;
    private const int SM_CXVIRTUALSCREEN = 78;
    private const int SM_CYVIRTUALSCREEN = 79;

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

    [DllImport("user32.dll")]
    private static extern int GetSystemMetrics(int nIndex);

    private static INPUT MouseInput(uint flags, int x = 0, int y = 0, uint data = 0)
    {
        var input = new INPUT { type = INPUT_MOUSE };
        input.U.mi = new MOUSEINPUT
        {
            dx = x, dy = y, mouseData = data,
            dwFlags = flags | (flags == MOUSEEVENTF_MOVE ? MOUSEEVENTF_ABSOLUTE : 0),
            time = 0, dwExtraInfo = IntPtr.Zero
        };
        return input;
    }

    /// <summary>归一化坐标(0..1) → 绝对像素 → SendInput 绝对坐标(0..65535)</summary>
    private static (int ax, int ay) ToAbsolute(float nx, float ny)
    {
        int vx = GetSystemMetrics(SM_XVIRTUALSCREEN);
        int vy = GetSystemMetrics(SM_YVIRTUALSCREEN);
        int vw = Math.Max(1, GetSystemMetrics(SM_CXVIRTUALSCREEN));
        int vh = Math.Max(1, GetSystemMetrics(SM_CYVIRTUALSCREEN));
        int px = vx + (int)(nx * vw);
        int py = vy + (int)(ny * vh);
        int ax = (int)((px - vx) * 65535L / vw);
        int ay = (int)((py - vy) * 65535L / vh);
        return (ax, ay);
    }

    public static void Move(float nx, float ny)
    {
        var (ax, ay) = ToAbsolute(nx, ny);
        SendInput(1, new[] { MouseInput(MOUSEEVENTF_MOVE, ax, ay) }, Marshal.SizeOf<INPUT>());
    }

    public static void LeftDown(float nx, float ny) { Move(nx, ny); SendInput(1, new[] { MouseInput(MOUSEEVENTF_LEFTDOWN) }, Marshal.SizeOf<INPUT>()); }
    public static void LeftUp(float nx, float ny) { Move(nx, ny); SendInput(1, new[] { MouseInput(MOUSEEVENTF_LEFTUP) }, Marshal.SizeOf<INPUT>()); }
    public static void RightDown(float nx, float ny) { Move(nx, ny); SendInput(1, new[] { MouseInput(MOUSEEVENTF_RIGHTDOWN) }, Marshal.SizeOf<INPUT>()); }
    public static void RightUp(float nx, float ny) { Move(nx, ny); SendInput(1, new[] { MouseInput(MOUSEEVENTF_RIGHTUP) }, Marshal.SizeOf<INPUT>()); }
    public static void Wheel(int delta) { SendInput(1, new[] { MouseInput(MOUSEEVENTF_WHEEL, data: unchecked((uint)delta)) }, Marshal.SizeOf<INPUT>()); }

    /// <summary>Unicode 文本输入（与官方键盘注入等价）</summary>
    public static void TypeText(string text)
    {
        foreach (char ch in text)
        {
            var down = new INPUT { type = INPUT_KEYBOARD };
            down.U.ki = new KEYBDINPUT { wVk = 0, wScan = ch, dwFlags = KEYEVENTF_UNICODE };
            var up = new INPUT { type = INPUT_KEYBOARD };
            up.U.ki = new KEYBDINPUT { wVk = 0, wScan = ch, dwFlags = KEYEVENTF_UNICODE | KEYEVENTF_KEYUP };
            SendInput(2, new[] { down, up }, Marshal.SizeOf<INPUT>());
        }
    }

    /// <summary>处理 gv_pb.InputEvent.TouchEvent（归一化坐标）</summary>
    public static void HandleTouch(GvTouchEventType type, float nx, float ny, int pointerId)
    {
        switch (type)
        {
            case GvTouchEventType.Start:
                if (pointerId == 0) LeftDown(nx, ny);
                else RightDown(nx, ny);
                break;
            case GvTouchEventType.Move:
                Move(nx, ny);
                break;
            case GvTouchEventType.End:
                if (pointerId == 0) LeftUp(nx, ny);
                else RightUp(nx, ny);
                break;
            case GvTouchEventType.Cancel:
                LeftUp(nx, ny);
                break;
        }
    }
}

public enum GvTouchEventType
{
    Undefined = 0, Start = 1, Move = 2, End = 3, Cancel = 4
}
