using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace UURemoteClone;

/// <summary>
/// Inspect the supplied streamer.dll through the same native bridge as macOS.
/// This opens no room and performs no capture. No guessed callbacks or arbitrary
/// function-table slots are exposed to managed code.
/// </summary>
public sealed class OfficialStreamer : IDisposable
{
    public enum Role { Controller = 0, Controlled = 1 }

    private sealed class LibraryHandle : SafeHandleZeroOrMinusOneIsInvalid
    {
        public LibraryHandle(IntPtr value) : base(true) => SetHandle(value);
        protected override bool ReleaseHandle() { Close(handle); return true; }
    }

    [DllImport("gvpb", EntryPoint = "uu_official_open", CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr Open(
        [MarshalAs(UnmanagedType.LPUTF8Str)] string path, int role,
        [Out] byte[] error, nuint capacity);

    [DllImport("gvpb", EntryPoint = "uu_official_version", CallingConvention = CallingConvention.Cdecl)]
    private static extern int GetVersion(LibraryHandle library, [Out] byte[] bytes, nuint capacity);

    [DllImport("gvpb", EntryPoint = "uu_official_close", CallingConvention = CallingConvention.Cdecl)]
    private static extern void Close(IntPtr library);

    private readonly LibraryHandle _handle;

    public OfficialStreamer(string? path = null, Role role = Role.Controller)
    {
        var error = new byte[1024];
        var value = Open(Path.GetFullPath(path ?? Path.Combine(AppContext.BaseDirectory, "streamer.dll")),
            (int)role, error, (nuint)error.Length);
        if (value == IntPtr.Zero) throw new InvalidOperationException(Utf8(error));
        _handle = new LibraryHandle(value);
    }

    public string Version
    {
        get
        {
            ObjectDisposedException.ThrowIf(_handle.IsClosed, this);
            var bytes = new byte[4097];
            var status = GetVersion(_handle, bytes, (nuint)bytes.Length);
            if (status != 0) throw new InvalidOperationException($"Official streamer error: {status}");
            return Utf8(bytes);
        }
    }

    private static string Utf8(byte[] bytes)
    {
        var end = Array.IndexOf(bytes, (byte)0);
        return Encoding.UTF8.GetString(bytes, 0, end < 0 ? bytes.Length : end);
    }

    public void Dispose() => _handle.Dispose();
}
