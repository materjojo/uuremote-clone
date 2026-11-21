using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

namespace UURemoteClone;

public sealed partial class OfficialWindowsEngine
{
    public enum RoomNotificationKind { RoomState, ConnectionCode }
    public readonly record struct RoomNotification(int Handle, RoomNotificationKind Kind, int Value);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate void RoomCallback(int handle, int value);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int OpenRoomFunction(IntPtr config);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int CloseRoomFunction(int handle);

    // The native helper reads these fields from a zero-filled 0xc0-byte input.
    // Report/proxy/SNI/streamer-config members stay zero; their public contracts
    // have not been established. Do not reuse this layout on another platform.
    [StructLayout(LayoutKind.Explicit, Size = 0xc0)]
    private struct RoomConfig
    {
        [FieldOffset(0x00)] public IntPtr Token;
        [FieldOffset(0x08)] public int TokenSize;
        [FieldOffset(0x10)] public IntPtr Servers;
        [FieldOffset(0x18)] public IntPtr ServerSizes;
        [FieldOffset(0x20)] public int ServerCount;
        [FieldOffset(0x24)] public int Timeout;
        [FieldOffset(0x28)] public int ReconnectDelay;
    }

    private readonly ConcurrentQueue<RoomNotification> _roomNotifications = new();
    private readonly HashSet<int> _openRooms = new();
    private readonly List<RoomInputs> _roomInputs = new();
    private readonly RoomCallback _roomStateCallback;
    private readonly RoomCallback _connectionCodeCallback;
    private Exception? _callbackFailure;
    private OpenRoomFunction _openRoom = null!;
    private CloseRoomFunction _closeRoom = null!;

    private void RecordRoomNotification(int handle, RoomNotificationKind kind, int value)
    {
        // Native callbacks can arrive while a foreground call holds CallGate.
        // Never acquire that gate or invoke application handlers on this thread.
        try { _roomNotifications.Enqueue(new RoomNotification(handle, kind, value)); }
        catch (Exception error) { Interlocked.CompareExchange(ref _callbackFailure, error, null); }
    }

    /// <summary>
    /// Starts the original asynchronous room operation using the caller's own
    /// TLS signaling service. The returned local handle does not imply login,
    /// peer consent, a control connection, capture, or media delivery.
    /// </summary>
    public int OpenRoom(string token, IReadOnlyList<Uri> signalServers,
        int timeoutMilliseconds = 3000, int reconnectDelayMilliseconds = 1000)
    {
        lock (CallGate)
        {
            RequireActive();
            var inputs = new RoomInputs(token, signalServers, timeoutMilliseconds, reconnectDelayMilliseconds);
            try { _roomInputs.Add(inputs); }
            catch { inputs.Dispose(); throw; }
            _faulted = true;
            int handle = _openRoom(inputs.Config);
            if (handle <= 0 || !_openRooms.Add(handle))
                throw new InvalidOperationException($"Original room entry returned an invalid or duplicate handle: {handle}");
            _faulted = false;
            return handle;
        }
    }

    /// <summary>Destroys an owned local room. Returns false if it was already closed.</summary>
    public bool CloseRoom(int handle)
    {
        lock (CallGate)
        {
            RequireActive();
            if (!_openRooms.Contains(handle)) return false;
            _faulted = true;
            int status = _closeRoom(handle);
            if (status != 0)
                throw new InvalidOperationException($"Original room shutdown failed: {status}");
            _openRooms.Remove(handle);
            _faulted = false;
            // Conservatively retain all borrowed input bytes until Finalize.
            return true;
        }
    }

    /// <summary>
    /// Copies queued native state/code values. The application chooses when and
    /// where to consume them; these are separate native notification domains.
    /// </summary>
    public RoomNotification[] DrainRoomNotifications()
    {
        lock (CallGate)
        {
            RequireActive();
            if (Volatile.Read(ref _callbackFailure) is Exception error)
                throw new InvalidOperationException("An original room callback could not be recorded.", error);
            var result = new List<RoomNotification>();
            // Take a finite snapshot even if new callbacks arrive during drain.
            int count = _roomNotifications.Count;
            while (count-- > 0 && _roomNotifications.TryDequeue(out var value)) result.Add(value);
            return result.ToArray();
        }
    }

    private void CloseOwnedRooms()
    {
        foreach (int handle in new List<int>(_openRooms)) CloseRoom(handle);
    }

    private void FreeRoomInputs()
    {
        foreach (var inputs in _roomInputs) inputs.Dispose();
        _roomInputs.Clear();
    }

    private sealed class RoomInputs : IDisposable
    {
        private readonly List<IntPtr> _allocations = new();
        public IntPtr Config { get; private set; }

        public RoomInputs(string token, IReadOnlyList<Uri> servers, int timeout, int reconnectDelay)
        {
            ValidateString(token, nameof(token));
            ArgumentNullException.ThrowIfNull(servers);
            if (servers.Count is < 1 or > 16) throw new ArgumentOutOfRangeException(nameof(servers));
            if (timeout is < 100 or > 60000) throw new ArgumentOutOfRangeException(nameof(timeout));
            if (reconnectDelay is < 100 or > 60000) throw new ArgumentOutOfRangeException(nameof(reconnectDelay));
            var encoding = new UTF8Encoding(false, true);
            byte[] tokenBytes = encoding.GetBytes(token);
            if (tokenBytes.Length > 65536) throw new ArgumentException("Room token exceeds the binding limit.", nameof(token));
            var urls = new byte[servers.Count][];
            for (int i = 0; i < urls.Length; i++)
            {
                Uri server = servers[i] ?? throw new ArgumentException("A signaling URL is required.", nameof(servers));
                if (!server.IsAbsoluteUri || server.Scheme != "wss" || server.UserInfo.Length != 0
                    || server.Query.Length != 0 || server.Fragment.Length != 0)
                    throw new ArgumentException("Signaling URLs must use wss without userinfo, query or fragment.", nameof(servers));
                urls[i] = encoding.GetBytes(server.AbsoluteUri);
                if (urls[i].Length > 8192) throw new ArgumentException("Signaling URL exceeds the binding limit.", nameof(servers));
            }
            if (Marshal.SizeOf<RoomConfig>() != 0xc0)
                throw new InvalidOperationException("Unsupported original Windows room input layout.");
            try
            {
                IntPtr array = Allocate(urls.Length * IntPtr.Size), sizes = Allocate(urls.Length * sizeof(int));
                for (int i = 0; i < urls.Length; i++)
                {
                    Marshal.WriteIntPtr(array, i * IntPtr.Size, CopyBytes(urls[i]));
                    Marshal.WriteInt32(sizes, i * sizeof(int), urls[i].Length);
                }
                var config = new RoomConfig
                {
                    Token = CopyBytes(tokenBytes), TokenSize = tokenBytes.Length,
                    Servers = array, ServerSizes = sizes, ServerCount = urls.Length,
                    Timeout = timeout, ReconnectDelay = reconnectDelay
                };
                Config = Allocate(0xc0);
                Marshal.StructureToPtr(config, Config, false);
            }
            catch { Dispose(); throw; }
        }

        private IntPtr Allocate(int bytes)
        {
            IntPtr pointer = Marshal.AllocHGlobal(bytes);
            try { _allocations.Add(pointer); }
            catch { Marshal.FreeHGlobal(pointer); throw; }
            return pointer;
        }
        private IntPtr CopyBytes(byte[] bytes)
        {
            IntPtr pointer = Allocate(checked(bytes.Length + 1));
            Marshal.Copy(bytes, 0, pointer, bytes.Length);
            Marshal.WriteByte(pointer, bytes.Length, 0);
            return pointer;
        }
        public void Dispose()
        {
            foreach (IntPtr pointer in _allocations) Marshal.FreeHGlobal(pointer);
            _allocations.Clear();
            Config = IntPtr.Zero;
        }
    }
}
