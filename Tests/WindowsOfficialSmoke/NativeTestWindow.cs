using System.ComponentModel;
using System.Runtime.InteropServices;

// Runner-owned windows only. This helper paints test content and samples the
// desktop; it never supplies frames to the streamer or copies source pixels
// into the controller window. The controller window is painted dark gray.
internal sealed class NativeTestWindow : IDisposable
{
    [UnmanagedFunctionPointer(CallingConvention.Winapi)]
    private delegate IntPtr WindowProcedure(IntPtr window, uint message, UIntPtr wParam, IntPtr lParam);
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct WindowClass
    {
        public uint Size, Style;
        public IntPtr Procedure;
        public int ClassExtra, WindowExtra;
        public IntPtr Instance, Icon, Cursor, Background;
        public string? MenuName;
        public string ClassName;
        public IntPtr SmallIcon;
    }
    [StructLayout(LayoutKind.Sequential)]
    private struct Point { public int X, Y; }
    [StructLayout(LayoutKind.Sequential)]
    private struct Rect { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)]
    private struct Message
    {
        public IntPtr Window;
        public uint Kind;
        public UIntPtr WParam;
        public IntPtr LParam;
        public uint Time;
        public Point Position;
        public uint Private;
    }
    [StructLayout(LayoutKind.Explicit, Size = 72)]
    private struct Paint
    {
        [FieldOffset(0)] public IntPtr Context;
        [FieldOffset(12)] public Rect Area;
    }
    [StructLayout(LayoutKind.Sequential)]
    private struct BitmapHeader
    {
        public uint Size;
        public int Width, Height;
        public ushort Planes, BitCount;
        public uint Compression, ImageSize;
        public int XPixels, YPixels;
        public uint ColorsUsed, ColorsImportant;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] private static extern IntPtr GetModuleHandleW(string? name);
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)] private static extern ushort RegisterClassExW(ref WindowClass value);
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)] private static extern bool UnregisterClassW(string name, IntPtr instance);
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)] private static extern IntPtr CreateWindowExW(uint extended, string className, string title, uint style, int x, int y, int width, int height, IntPtr parent, IntPtr menu, IntPtr instance, IntPtr parameter);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern IntPtr DefWindowProcW(IntPtr window, uint message, UIntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)] private static extern int GetMessageW(out Message message, IntPtr window, uint min, uint max);
    [DllImport("user32.dll")] private static extern bool TranslateMessage(ref Message message);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern IntPtr DispatchMessageW(ref Message message);
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)] private static extern bool PostMessageW(IntPtr window, uint message, UIntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] private static extern void PostQuitMessage(int code);
    [DllImport("user32.dll")] private static extern bool DestroyWindow(IntPtr window);
    [DllImport("user32.dll")] private static extern bool UpdateWindow(IntPtr window);
    [DllImport("user32.dll")] private static extern bool GetClientRect(IntPtr window, out Rect rectangle);
    [DllImport("user32.dll")] private static extern bool ClientToScreen(IntPtr window, ref Point point);
    [DllImport("user32.dll")] private static extern bool InvalidateRect(IntPtr window, IntPtr rectangle, bool erase);
    [DllImport("user32.dll")] private static extern IntPtr BeginPaint(IntPtr window, out Paint paint);
    [DllImport("user32.dll")] private static extern bool EndPaint(IntPtr window, ref Paint paint);
    [DllImport("user32.dll")] private static extern int FillRect(IntPtr context, ref Rect rectangle, IntPtr brush);
    [DllImport("user32.dll")] private static extern IntPtr GetDC(IntPtr window);
    [DllImport("user32.dll")] private static extern int ReleaseDC(IntPtr window, IntPtr context);
    [DllImport("gdi32.dll")] private static extern IntPtr CreateSolidBrush(uint color);
    [DllImport("gdi32.dll")] private static extern bool DeleteObject(IntPtr value);
    [DllImport("gdi32.dll")] private static extern uint GetPixel(IntPtr context, int x, int y);
    [DllImport("gdi32.dll")] private static extern IntPtr CreateCompatibleDC(IntPtr context);
    [DllImport("gdi32.dll")] private static extern bool DeleteDC(IntPtr context);
    [DllImport("gdi32.dll")] private static extern IntPtr CreateCompatibleBitmap(IntPtr context, int width, int height);
    [DllImport("gdi32.dll")] private static extern IntPtr SelectObject(IntPtr context, IntPtr value);
    [DllImport("gdi32.dll")] private static extern bool BitBlt(IntPtr destination, int x, int y, int width, int height, IntPtr source, int sourceX, int sourceY, uint raster);
    [DllImport("gdi32.dll")] private static extern int GetDIBits(IntPtr context, IntPtr bitmap, uint start, uint count, [Out] byte[] pixels, ref BitmapHeader header, uint usage);
    [DllImport("dwmapi.dll")] private static extern int DwmFlush();

    private readonly WindowProcedure _procedure;
    private readonly Thread _thread;
    private readonly ManualResetEventSlim _ready = new();
    private readonly uint[][]? _patterns;
    private IntPtr _window;
    private Exception? _failure;
    private int _phase;
    public IntPtr Handle => _window;
    public bool Stopped { get; private set; }

    internal NativeTestWindow(bool source, uint[][]? patterns)
    {
        if (!OperatingSystem.IsWindows() || Environment.GetEnvironmentVariable("GITHUB_ACTIONS") != "true")
            throw new InvalidOperationException("Test windows require Windows Actions.");
        _patterns = source ? patterns ?? throw new ArgumentNullException(nameof(patterns)) : null;
        _procedure = Dispatch;
        _thread = new Thread(() => Run(source)) { IsBackground = true, Name = "original-native-media-window" };
        _thread.SetApartmentState(ApartmentState.STA);
        _thread.Start();
        if (!_ready.Wait(TimeSpan.FromSeconds(10))) throw new TimeoutException("Native test window did not start.");
        Check();
        if (_window == IntPtr.Zero) throw new InvalidOperationException("Native test window is absent.");
    }

    private void Check()
    {
        if (Volatile.Read(ref _failure) is Exception error) throw new InvalidOperationException("Native test window failed.", error);
    }

    private void Run(bool source)
    {
        string name = "OriginalMediaObservation-" + Environment.ProcessId;
        IntPtr instance = GetModuleHandleW(null);
        try
        {
            var type = new WindowClass { Size = checked((uint)Marshal.SizeOf<WindowClass>()),
                Procedure = Marshal.GetFunctionPointerForDelegate(_procedure), Instance = instance, ClassName = name };
            if (RegisterClassExW(ref type) == 0) throw new Win32Exception(Marshal.GetLastWin32Error());
            _window = CreateWindowExW(0x00000008, name, source ? "Original capture source" : "Original renderer output",
                0x90000000, source ? 32 : 480, 160, 320, 240, IntPtr.Zero, IntPtr.Zero, instance, IntPtr.Zero);
            if (_window == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
            UpdateWindow(_window);
            _ready.Set();
            while (true)
            {
                int status = GetMessageW(out var message, IntPtr.Zero, 0, 0);
                if (status == 0) break;
                if (status < 0) throw new Win32Exception(Marshal.GetLastWin32Error());
                TranslateMessage(ref message);
                DispatchMessageW(ref message);
            }
        }
        catch (Exception error) { Interlocked.CompareExchange(ref _failure, error, null); }
        finally
        {
            _ready.Set();
            UnregisterClassW(name, instance);
        }
    }

    private IntPtr Dispatch(IntPtr window, uint message, UIntPtr wParam, IntPtr lParam)
    {
        try
        {
            switch (message)
            {
                case 0x000f: // WM_PAINT
                    IntPtr context = BeginPaint(window, out var paint);
                    try
                    {
                        if (context == IntPtr.Zero || !GetClientRect(window, out var rect))
                            throw new InvalidOperationException("Cannot paint the test client area.");
                        int columns = _patterns is null ? 1 : 2;
                        for (int row = 0; row < columns; row++)
                            for (int col = 0; col < columns; col++)
                            {
                                var area = new Rect { Left = col * rect.Right / columns, Top = row * rect.Bottom / columns,
                                    Right = (col + 1) * rect.Right / columns, Bottom = (row + 1) * rect.Bottom / columns };
                                uint color = _patterns is null ? 0x202020u : _patterns[_phase][row * 2 + col];
                                IntPtr brush = CreateSolidBrush(color);
                                if (brush == IntPtr.Zero) throw new InvalidOperationException("Cannot allocate a test brush.");
                                try { if (FillRect(context, ref area, brush) == 0) throw new InvalidOperationException("Cannot paint test pattern."); }
                                finally { DeleteObject(brush); }
                            }
                    }
                    finally { EndPaint(window, ref paint); }
                    return IntPtr.Zero;
                case 0x0014: return new IntPtr(1); // WM_ERASEBKGND, WM_PAINT owns all pixels.
                case 0x8001:
                    _phase = checked((int)wParam.ToUInt64());
                    InvalidateRect(window, IntPtr.Zero, false);
                    UpdateWindow(window);
                    return IntPtr.Zero;
                case 0x0010:
                    DestroyWindow(window);
                    return IntPtr.Zero;
                case 0x0002:
                    PostQuitMessage(0);
                    return IntPtr.Zero;
            }
        }
        catch (Exception error) { Interlocked.CompareExchange(ref _failure, error, null); }
        return DefWindowProcW(window, message, wParam, lParam);
    }

    internal void SetPhase(int phase)
    {
        Check();
        if (_patterns is null || phase < 0 || phase >= _patterns.Length) throw new ArgumentOutOfRangeException(nameof(phase));
        if (!PostMessageW(_window, 0x8001, new UIntPtr(checked((uint)phase)), IntPtr.Zero))
            throw new Win32Exception(Marshal.GetLastWin32Error());
    }

    internal uint[] Sample()
    {
        Check();
        DwmFlush();
        if (!GetClientRect(_window, out var area)) throw new InvalidOperationException("Test client rectangle is absent.");
        IntPtr context = GetDC(IntPtr.Zero);
        if (context == IntPtr.Zero) throw new InvalidOperationException("Screen DC is unavailable.");
        try
        {
            var colors = new uint[4];
            for (int i = 0; i < colors.Length; i++)
            {
                var point = new Point { X = area.Right * (i % 2 == 0 ? 1 : 3) / 4,
                    Y = area.Bottom * (i < 2 ? 1 : 3) / 4 };
                if (!ClientToScreen(_window, ref point)) throw new InvalidOperationException("Test client cannot be located.");
                colors[i] = GetPixel(context, point.X, point.Y);
                if (colors[i] == uint.MaxValue) throw new InvalidOperationException("Screen pixel sampling is unsupported.");
            }
            return colors;
        }
        finally { ReleaseDC(IntPtr.Zero, context); }
    }

    internal void SaveBitmap(string path)
    {
        Check();
        DwmFlush();
        var point = new Point();
        if (!GetClientRect(_window, out var area) || !ClientToScreen(_window, ref point))
            throw new InvalidOperationException("Test client snapshot coordinates are unavailable.");
        int width = area.Right, height = area.Bottom;
        if (width is < 1 or > 4096 || height is < 1 or > 4096) throw new InvalidOperationException("Invalid test snapshot dimensions.");
        IntPtr screen = GetDC(IntPtr.Zero), memory = IntPtr.Zero, bitmap = IntPtr.Zero, previous = IntPtr.Zero;
        try
        {
            if (screen == IntPtr.Zero) throw new InvalidOperationException("Screen DC is unavailable.");
            memory = CreateCompatibleDC(screen);
            bitmap = CreateCompatibleBitmap(screen, width, height);
            if (memory == IntPtr.Zero || bitmap == IntPtr.Zero) throw new InvalidOperationException("Cannot allocate test snapshot.");
            previous = SelectObject(memory, bitmap);
            if (previous == IntPtr.Zero || previous == new IntPtr(-1))
                throw new InvalidOperationException("Cannot select the test snapshot bitmap.");
            if (!BitBlt(memory, 0, 0, width, height, screen, point.X, point.Y, 0x00cc0020))
                throw new InvalidOperationException("Test snapshot BitBlt failed.");
            SelectObject(memory, previous);
            previous = IntPtr.Zero;
            var pixels = new byte[checked(width * height * 4)];
            var header = new BitmapHeader { Size = 40, Width = width, Height = -height,
                Planes = 1, BitCount = 32, ImageSize = checked((uint)pixels.Length) };
            if (GetDIBits(screen, bitmap, 0, checked((uint)height), pixels, ref header, 0) != height)
                throw new InvalidOperationException("Test snapshot pixel read failed.");
            using var writer = new BinaryWriter(File.Open(path, FileMode.CreateNew));
            writer.Write((ushort)0x4d42); writer.Write(checked((uint)(54 + pixels.Length)));
            writer.Write(0u); writer.Write(54u); writer.Write(40u); writer.Write(width); writer.Write(-height);
            writer.Write((ushort)1); writer.Write((ushort)32); writer.Write(0u); writer.Write(checked((uint)pixels.Length));
            writer.Write(0); writer.Write(0); writer.Write(0u); writer.Write(0u); writer.Write(pixels);
        }
        finally
        {
            if (previous != IntPtr.Zero && memory != IntPtr.Zero) SelectObject(memory, previous);
            if (bitmap != IntPtr.Zero) DeleteObject(bitmap);
            if (memory != IntPtr.Zero) DeleteDC(memory);
            if (screen != IntPtr.Zero) ReleaseDC(IntPtr.Zero, screen);
        }
    }

    public void Dispose()
    {
        if (Stopped) return;
        PostMessageW(_window, 0x0010, UIntPtr.Zero, IntPtr.Zero);
        Stopped = _thread.Join(TimeSpan.FromSeconds(5));
        GC.KeepAlive(_procedure);
        if (!Stopped) throw new TimeoutException("Native test window did not stop.");
        _ready.Dispose();
        Check();
    }
}
