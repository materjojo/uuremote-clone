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
    public sealed record NewControlNotification(int Handle, string ControlId, byte[] AppData, string NegotiationJson);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate void NewControlCallback(int handle, IntPtr data);

    [StructLayout(LayoutKind.Explicit, Size = 0x30)]
    private struct NewControlData
    {
        [FieldOffset(0x00)] public IntPtr ControlId;
        [FieldOffset(0x08)] public int ControlIdSize;
        [FieldOffset(0x10)] public IntPtr AppData;
        [FieldOffset(0x18)] public int AppDataSize;
        [FieldOffset(0x20)] public IntPtr Negotiation;
        [FieldOffset(0x28)] public int NegotiationSize;
    }

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate void RoomCallback(int handle, int value);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int OpenRoomFunction(IntPtr config);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int CloseRoomFunction(int handle);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int RequestControlFunction(int handle, IntPtr config);

    [StructLayout(LayoutKind.Explicit, Size = 0x30)]
    private struct ControlConfig
    {
        [FieldOffset(0x00)] public IntPtr AppData;
        [FieldOffset(0x08)] public int AppDataSize;
        [FieldOffset(0x10)] public IntPtr AppControlId;
        [FieldOffset(0x18)] public int AppControlIdSize;
        [FieldOffset(0x20)] public IntPtr GeoTimezone;
        [FieldOffset(0x28)] public int GeoTimezoneSize;
    }

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
    private readonly ConcurrentQueue<NewControlNotification> _newControls = new();
    private readonly NewControlCallback _newControlCallback;
    private readonly HashSet<int> _openRooms = new();
    private readonly List<RoomInputs> _roomInputs = new();
    private readonly RoomCallback _roomStateCallback;
    private readonly RoomCallback _connectionCodeCallback;
    private Exception? _callbackFailure;
    private OpenRoomFunction _openRoom = null!;
    private CloseRoomFunction _closeRoom = null!;
    private RequestControlFunction? _requestControl;

    private void RecordRoomNotification(int handle, RoomNotificationKind kind, int value)
    {
        // Native callbacks can arrive while a foreground call holds CallGate.
        // Never acquire that gate or invoke application handlers on this thread.
        try { _roomNotifications.Enqueue(new RoomNotification(handle, kind, value)); }
        catch (Exception error) { Interlocked.CompareExchange(ref _callbackFailure, error, null); }
    }

    private void RecordNewControl(int handle, IntPtr data)
    {
        try
        {
            if (data == IntPtr.Zero) throw new InvalidOperationException("Original new-control callback has no payload.");
            var input = Marshal.PtrToStructure<NewControlData>(data);
            byte[] CopySlice(IntPtr pointer, int size)
            {
                if (size < 0) throw new InvalidOperationException("Original new-control slice has a negative length.");
                return size == 0 ? Array.Empty<byte>() : Copy(pointer, checked((uint)size), 1024 * 1024);
            }
            // The three pointers are borrowed for this callback only. Copy all
            // bytes before returning to native code; no foreground lock here.
            var encoding = new UTF8Encoding(false, true);
            string id = encoding.GetString(CopySlice(input.ControlId, input.ControlIdSize));
            byte[] appData = CopySlice(input.AppData, input.AppDataSize);
            string negotiation = encoding.GetString(CopySlice(input.Negotiation, input.NegotiationSize));
            _newControls.Enqueue(new NewControlNotification(handle, id, appData, negotiation));
        }
        catch (Exception error) { Interlocked.CompareExchange(ref _callbackFailure, error, null); }
    }

    /// <summary>
    /// Copies queued controlled-role OnNewControl payloads. This notification
    /// alone does not establish authorization, peer connectivity or media.
    /// Capability negotiation is returned as original UTF-8 JSON text.
    /// </summary>
    public NewControlNotification[] DrainNewControls()
    {
        lock (CallGate)
        {
            RequireActive();
            if (Volatile.Read(ref _callbackFailure) is Exception error)
                throw new InvalidOperationException("An original native callback could not be recorded.", error);
            var result = new List<NewControlNotification>();
            int count = _newControls.Count;
            while (count-- > 0 && _newControls.TryDequeue(out var value)) result.Add(value);
            return result.ToArray();
        }
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

    /// <summary>
    /// Queues the original controller's control request for an owned room.
    /// App data is opaque binary, including embedded NUL. The signaling service
    /// and peer must authorize and complete this request; returning normally
    /// only means the native entry accepted it for asynchronous processing.
    /// </summary>
    public void RequestControl(int handle, ReadOnlySpan<byte> appData, string appControlId, string geoTimezone = "")
    {
        lock (CallGate)
        {
            RequireActive();
            if (Role != OfficialStreamer.Role.Controller || _requestControl is null)
                throw new InvalidOperationException("Only the original controller exposes this control-request ABI.");
            if (!_openRooms.Contains(handle)) throw new ArgumentOutOfRangeException(nameof(handle), "An owned open room is required.");
            var inputs = new RoomInputs(appData, appControlId, geoTimezone);
            try { _roomInputs.Add(inputs); }
            catch { inputs.Dispose(); throw; }
            _faulted = true;
            int status = _requestControl(handle, inputs.Config);
            if (status != 0) throw new InvalidOperationException($"Original control-request entry failed: {status}");
            _faulted = false;
        }
    }

    /// <summary>Destroys an owned local room. Returns false if it was already closed.</summary>
    public bool CloseRoom(int handle)
    {
        lock (CallGate)
        {
            RequireActive();
            if (!_openRooms.Contains(handle)) return false;
            CloseRoomMedia(handle);
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

    private sealed partial class RoomInputs : IDisposable
    {
        private readonly List<IntPtr> _allocations = new();
        public IntPtr Config { get; private set; }

        public RoomInputs(ReadOnlySpan<byte> binaryData)
        {
            try { Config = CopyBytes(binaryData.ToArray()); }
            catch { Dispose(); throw; }
        }

        public RoomInputs(ReadOnlySpan<byte> appData, string appControlId, string geoTimezone)
        {
            ValidateString(appControlId, nameof(appControlId));
            ArgumentNullException.ThrowIfNull(geoTimezone);
            if (geoTimezone.Contains('\0')) throw new ArgumentException("Timezone cannot contain embedded NUL.", nameof(geoTimezone));
            if (appData.Length > 1024 * 1024) throw new ArgumentOutOfRangeException(nameof(appData));
            var encoding = new UTF8Encoding(false, true);
            byte[] id = encoding.GetBytes(appControlId), timezone = encoding.GetBytes(geoTimezone);
            if (id.Length > 1024) throw new ArgumentException("Control ID exceeds the binding limit.", nameof(appControlId));
            if (timezone.Length > 256) throw new ArgumentException("Timezone exceeds the binding limit.", nameof(geoTimezone));
            if (Marshal.SizeOf<ControlConfig>() != 0x30) throw new InvalidOperationException("Unsupported original Windows control input layout.");
            try
            {
                var config = new ControlConfig
                {
                    AppData = CopyBytes(appData.ToArray()), AppDataSize = appData.Length,
                    AppControlId = CopyBytes(id), AppControlIdSize = id.Length,
                    GeoTimezone = CopyBytes(timezone), GeoTimezoneSize = timezone.Length
                };
                Config = Allocate(0x30);
                Marshal.StructureToPtr(config, Config, false);
            }
            catch { Dispose(); throw; }
        }

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
