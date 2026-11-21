using System;
using System.Collections.Concurrent;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

namespace UURemoteClone;

public sealed partial class OfficialWindowsEngine
{
    public sealed record ConnectionStatsNotification(int Handle, string Json);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int RequestConnectionStatsFunction(int handle);
    private RequestConnectionStatsFunction _requestConnectionStats = null!;
    private readonly BinaryDataCallback _connectionStatsCallback;
    private readonly ConcurrentQueue<ConnectionStatsNotification> _connectionStats = new();

    private void InstallStatsCallbacks(IntPtr[] callbacks)
    {
        callbacks[Role == OfficialStreamer.Role.Controller ? 9 : 6] =
            Marshal.GetFunctionPointerForDelegate(_connectionStatsCallback);
    }

    private void RecordConnectionStats(int handle, IntPtr data, uint size)
    {
        try
        {
            // Windows 0x180a36890 / 0x180a36bd0 release their temporary string
            // immediately after callback return. Own all bytes before returning.
            string json = new UTF8Encoding(false, true).GetString(Copy(data, size, 1024 * 1024));
            _connectionStats.Enqueue(new ConnectionStatsNotification(handle, json));
        }
        catch (Exception error) { Interlocked.CompareExchange(ref _callbackFailure, error, null); }
    }

    /// <summary>
    /// Requests the original connection statistics for an owned local room.
    /// A successful submission is not a received report or hardware evidence;
    /// consume the original callback JSON through DrainConnectionStats.
    /// </summary>
    public void RequestConnectionStats(int handle)
    {
        lock (CallGate)
        {
            RequireActive();
            if (!_openRooms.Contains(handle)) throw new ArgumentException("Room is not owned by this engine.", nameof(handle));
            _faulted = true;
            // Both slot-14 wrappers explicitly put 0/1 in EAX. The decompiler
            // omits this return; the preserved assembly establishes it.
            int status = _requestConnectionStats(handle);
            if (status != 0) throw new InvalidOperationException($"Original statistics submission failed: {status}");
            _faulted = false;
        }
    }

    public ConnectionStatsNotification[] DrainConnectionStats() => DrainDataQueue(_connectionStats);
}
