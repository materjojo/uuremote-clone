using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace UURemoteClone;

/// <summary>
/// Windows 4.48.1.5606 lifecycle, reported capabilities and asynchronous room entry.
/// Owns the process-global original engine exclusively. A local room handle or
/// capability declaration does not establish a peer, media operation or GPU use.
/// </summary>
public sealed partial class OfficialWindowsEngine : IDisposable
{
    private const string LibrarySha256 = "ac351cf4e1d489e0b6e1a3df5cdf8aed96348876f7e2c7fcf7162fe59e1bb1c4";
    private const string DetectorSha256 = "4377ce244e2424cf7f598b98fb9f0427711b7ad71bd8d776ea3d7eefdb60693b";

    // The owner is rooted until successful Finalize. Abandoning an engine must
    // not allow another factory to overwrite its process-global callbacks.
    private static OfficialWindowsEngine? _owner;
    private static IntPtr _module; // Pinned for process lifetime; CRT static data owns pointers into it.
    internal static object CallGate { get; } = new();
    internal static void RequireNoEngine()
    {
        if (_owner is not null)
            throw new InvalidOperationException("The original Windows engine already has a process owner.");
    }

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate IntPtr FactoryFunction(IntPtr callbacks);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int InitializeFunction(IntPtr logDirectory, IntPtr configFile, IntPtr logSuffix);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int FinalizeFunction();
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int VersionFunction(out IntPtr data, out uint size);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int CapabilityFunction(out CapabilityData data);

    [StructLayout(LayoutKind.Sequential)]
    private struct CapabilityData
    {
        public IntPtr Data;
        public uint Size;
    }

    private IntPtr[] _inputs = Array.Empty<IntPtr>();
    private FinalizeFunction _finalize = null!;
    private VersionFunction _version = null!;
    private CapabilityFunction _capability = null!;
    private bool _disposed;
    private bool _faulted;
    public OfficialStreamer.Role Role { get; }

    public OfficialWindowsEngine(OfficialStreamer.Role role, string logDirectory, string configFile,
        string logSuffix, string? libraryPath = null)
    {
        if (!OperatingSystem.IsWindows() || RuntimeInformation.ProcessArchitecture != Architecture.X64)
            throw new PlatformNotSupportedException("This ABI is verified only for Windows x64.");
        if (role != OfficialStreamer.Role.Controller && role != OfficialStreamer.Role.Controlled)
            throw new ArgumentOutOfRangeException(nameof(role));
        ValidateString(logDirectory, nameof(logDirectory));
        ValidateString(configFile, nameof(configFile));
        ValidateString(logSuffix, nameof(logSuffix));
        // The native suffix is appended to a filename. Reject path components
        // before entering native code; a full path is not this API's third input.
        if (logSuffix.Length > 64 || logSuffix.IndexOfAny(Path.GetInvalidFileNameChars()) >= 0
            || logSuffix.EndsWith(' ') || logSuffix.EndsWith('.'))
            throw new ArgumentException("The log suffix must be a valid filename suffix of at most 64 characters.", nameof(logSuffix));
        string dll = Path.GetFullPath(libraryPath ?? Path.Combine(AppContext.BaseDirectory, "streamer.dll"));
        string config = Path.GetFullPath(configFile);
        string logs = Path.GetFullPath(logDirectory);
        VerifyIdentity(dll, LibrarySha256);
        VerifyIdentity(Path.Combine(Path.GetDirectoryName(dll)!, "StreamerCodecDetector.exe"), DetectorSha256);
        if (!File.Exists(config)) throw new FileNotFoundException("Original engine config not found.", config);
        Role = role;
        _roomStateCallback = (handle, value) => RecordRoomNotification(handle, RoomNotificationKind.RoomState, value);
        _connectionCodeCallback = (handle, value) => RecordRoomNotification(handle, RoomNotificationKind.ConnectionCode, value);
        _newControlCallback = RecordNewControl;
        _binaryDataCallback = RecordBinaryData;
        _controllerPeerStateCallback = (handle, state, detail) => RecordPeerState(handle, state, detail);
        _controlledPeerStateCallback = (handle, state) => RecordPeerState(handle, state, null);
        _mediaTrackCallback = RecordMediaTrack;
        _frameChangeCallback = RecordFrameChange;
        _captureFailureCallback = RecordCaptureFailure;
        _connectionStatsCallback = RecordConnectionStats;
        lock (CallGate)
        {
            RequireNoEngine();
            Directory.CreateDirectory(logs);
            bool initializeAttempted = false;
            try
            {
                if (_module == IntPtr.Zero) _module = NativeLibrary.Load(dll);
                var factory = Marshal.GetDelegateForFunctionPointer<FactoryFunction>(NativeLibrary.GetExport(_module,
                    role == OfficialStreamer.Role.Controller ? "ExchangeControllerInterface" : "ExchangeControlledInterface"));
                var callbacks = new IntPtr[role == OfficialStreamer.Role.Controller ? 18 : 16];
                callbacks[role == OfficialStreamer.Role.Controller ? 7 : 4] = Marshal.GetFunctionPointerForDelegate(_roomStateCallback);
                callbacks[12] = Marshal.GetFunctionPointerForDelegate(_connectionCodeCallback);
                if (role == OfficialStreamer.Role.Controlled) callbacks[10] = Marshal.GetFunctionPointerForDelegate(_newControlCallback);
                InstallDataCallbacks(callbacks);
                InstallMediaCallbacks(callbacks);
                InstallStatsCallbacks(callbacks);
                var pin = GCHandle.Alloc(callbacks, GCHandleType.Pinned);
                IntPtr table;
                try { table = factory(pin.AddrOfPinnedObject()); }
                finally { pin.Free(); }
                if (table == IntPtr.Zero) throw new InvalidOperationException("Original engine returned no function table.");
                T Slot<T>(int index) where T : Delegate => Marshal.GetDelegateForFunctionPointer<T>(
                    Marshal.ReadIntPtr(table, index * IntPtr.Size));
                var initialize = Slot<InitializeFunction>(0);
                _finalize = Slot<FinalizeFunction>(1);
                _openRoom = Slot<OpenRoomFunction>(2);
                _closeRoom = Slot<CloseRoomFunction>(3);
                if (role == OfficialStreamer.Role.Controller) _requestControl = Slot<RequestControlFunction>(4);
                // Slot 13/11 dispatch SendFileData; binary is the preceding entry.
                // Original tasks 0x180a5fa60 / 0x180a5fc00 identify SendBinaryData.
                _sendBinary = Slot<SendBinaryFunction>(role == OfficialStreamer.Role.Controller ? 12 : 10);
                if (role == OfficialStreamer.Role.Controlled)
                {
                    _startVideoCapture = Slot<StartVideoFunction>(4);
                    _stopVideoCapture = Slot<StopVideoFunction>(6);
                }
                else
                {
                    _startVideoRender = Slot<StartVideoFunction>(6);
                    _stopVideoRender = Slot<StopVideoFunction>(8);
                }
                _version = Slot<VersionFunction>(role == OfficialStreamer.Role.Controller ? 17 : 18);
                _capability = Slot<CapabilityFunction>(15);
                _requestConnectionStats = Slot<RequestConnectionStatsFunction>(14);
                if (Marshal.SizeOf<CapabilityData>() != 16 || Marshal.OffsetOf<CapabilityData>(nameof(CapabilityData.Size)).ToInt32() != 8)
                    throw new InvalidOperationException("Unsupported capability output layout.");
                if (CopyVersion() != "V4.14.2") throw new InvalidOperationException("Unexpected original engine version.");
                // Preserve all three UTF-16 buffers through Finalize, including
                // failure paths whose native ownership has not been established.
                _inputs = new IntPtr[3];
                _inputs[0] = Marshal.StringToHGlobalUni(logs);
                _inputs[1] = Marshal.StringToHGlobalUni(config);
                _inputs[2] = Marshal.StringToHGlobalUni(logSuffix);
                _owner = this;
                initializeAttempted = true;
                int status = initialize(_inputs[0], _inputs[1], _inputs[2]);
                if (status != 0) throw new InvalidOperationException($"Original engine Initialize failed: {status}");
            }
            catch
            {
                _faulted = initializeAttempted;
                if (!initializeAttempted)
                {
                    FreeInputs();
                    _owner = null;
                }
                // After an attempted but unsuccessful initialization, retain the
                // owner and buffers. A fresh process is required for unknown state.
                throw;
            }
        }
    }

    public string Version
    {
        get { lock (CallGate) { RequireActive(); return CopyVersion(); } }
    }

    /// <summary>Copies the DLL-owned UTF-8 capability JSON without inventing codec support flags.</summary>
    public string GetCodecCapabilitiesJson()
    {
        lock (CallGate)
        {
            RequireActive();
            int status = _capability(out var result);
            if (status != 0) throw new InvalidOperationException($"Original engine capability query failed: {status}");
            var bytes = Copy(result.Data, result.Size, 1024 * 1024);
            string json = new UTF8Encoding(false, true).GetString(bytes);
            using var document = JsonDocument.Parse(json);
            return json;
        }
    }

    private string CopyVersion()
    {
        int status = _version(out var data, out uint size);
        if (status != 0) throw new InvalidOperationException($"Original engine version query failed: {status}");
        return new UTF8Encoding(false, true).GetString(Copy(data, size, 4096));
    }

    private static byte[] Copy(IntPtr data, uint size, uint maximum)
    {
        if (size == 0 || size > maximum || data == IntPtr.Zero)
            throw new InvalidOperationException($"Invalid original engine data length: {size}");
        var bytes = new byte[checked((int)size)];
        Marshal.Copy(data, bytes, 0, bytes.Length);
        return bytes; // Never free the DLL-owned pointer.
    }

    private void RequireActive()
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        if (_faulted || !ReferenceEquals(_owner, this))
            throw new InvalidOperationException("Original engine state is unknown; restart this process.");
    }

    private static void VerifyIdentity(string path, string expected)
    {
        using var file = File.OpenRead(path);
        if (!Convert.ToHexString(SHA256.HashData(file)).Equals(expected, StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("This original engine ABI does not match " + path);
    }
    private static void ValidateString(string value, string name)
    {
        if (string.IsNullOrWhiteSpace(value) || value.Contains('\0'))
            throw new ArgumentException("A non-empty string without embedded NUL is required.", name);
    }
    private void FreeInputs()
    {
        foreach (var pointer in _inputs) if (pointer != IntPtr.Zero) Marshal.FreeHGlobal(pointer);
        _inputs = Array.Empty<IntPtr>();
    }
    public void Dispose()
    {
        lock (CallGate)
        {
            if (_disposed) return;
            RequireActive();
            CloseOwnedRooms();
            // Mark unknown before crossing native code. Exceptions or a nonzero
            // return keep the process owner rooted and block subsequent factories.
            _faulted = true;
            int status = _finalize();
            if (status != 0) throw new InvalidOperationException($"Original engine Finalize failed: {status}");
            _disposed = true;
            FreeRoomInputs();
            FreeInputs();
            _owner = null;
        }
    }
}
