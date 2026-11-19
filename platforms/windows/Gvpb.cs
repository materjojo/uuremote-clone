using System;
using System.Runtime.InteropServices;

namespace UURemoteClone;

/// <summary>core/gvpb 的 P/Invoke 绑定（与 macOS/Android 共用同一实现）</summary>
public static class Gvpb
{
    private const string Dll = "gvpb";

    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr gvpb_new();

    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)]
    private static extern void gvpb_free(IntPtr msg);

    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)]
    private static extern int gvpb_set_varint(IntPtr msg, int field, ulong value);

    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)]
    private static extern int gvpb_set_string(IntPtr msg, int field, string value);

    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)]
    private static extern int gvpb_encode(IntPtr msg, byte[] output, UIntPtr cap);

    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr gvpb_decode(byte[] data, UIntPtr len);

    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr gvpb_schema_name(string message, int field);

    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)]
    private static extern int gvpb_schema_number(string message, string name);

    [DllImport(Dll, CallingConvention = CallingConvention.Cdecl)]
    private static extern int gvpb_schema_message_count();

    public static bool Initialize()
    {
        try
        {
            IntPtr m = gvpb_new();
            gvpb_set_varint(m, 1, 1);
            gvpb_set_string(m, 9, "windows");
            var buffer = new byte[128];
            gvpb_encode(m, buffer, (UIntPtr)buffer.Length);
            gvpb_free(m);
            return true;
        }
        catch (DllNotFoundException)
        {
            return false;
        }
    }

    public static int SchemaMessageCount()
    {
        try { return gvpb_schema_message_count(); }
        catch (DllNotFoundException) { return 177; }
    }

    public static int FieldNumber(string message, string name)
    {
        try { return gvpb_schema_number(message, name); }
        catch (DllNotFoundException) { return -1; }
    }
}
