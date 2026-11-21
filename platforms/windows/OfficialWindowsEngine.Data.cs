using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Threading;

namespace UURemoteClone;

public sealed partial class OfficialWindowsEngine
{
    public sealed record BinaryDataNotification(int Handle, byte[] Data);
    // Values are original Windows integers. Controller supplies a third detail
    // integer; controlled supplies only handle/state. No cross-platform enum.
    public readonly record struct PeerStateNotification(int Handle, int State, int? Detail);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate void BinaryDataCallback(int handle, IntPtr data, uint size);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate void ControllerPeerStateCallback(int handle, int state, int detail);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int SendBinaryFunction(int handle, IntPtr data, int size);

    private readonly BinaryDataCallback _binaryDataCallback;
    private readonly ControllerPeerStateCallback _controllerPeerStateCallback;
    private readonly RoomCallback _controlledPeerStateCallback;
    private readonly ConcurrentQueue<BinaryDataNotification> _binaryData = new();
    private readonly ConcurrentQueue<PeerStateNotification> _peerStates = new();
    private SendBinaryFunction _sendBinary = null!;

    private void InstallDataCallbacks(IntPtr[] callbacks)
    {
        callbacks[Role == OfficialStreamer.Role.Controller ? 6 : 3] = Marshal.GetFunctionPointerForDelegate(_binaryDataCallback);
        callbacks[11] = Role == OfficialStreamer.Role.Controller
            ? Marshal.GetFunctionPointerForDelegate(_controllerPeerStateCallback)
            : Marshal.GetFunctionPointerForDelegate(_controlledPeerStateCallback);
    }

    private void RecordBinaryData(int handle, IntPtr data, uint size)
    {
        try
        {
            // Borrowed memory belongs to this callback only.
            var bytes = size == 0 ? Array.Empty<byte>() : Copy(data, size, 512 * 1024 - 1);
            _binaryData.Enqueue(new BinaryDataNotification(handle, bytes));
        }
        catch (Exception error) { Interlocked.CompareExchange(ref _callbackFailure, error, null); }
    }

    private void RecordPeerState(int handle, int state, int? detail)
    {
        try { _peerStates.Enqueue(new PeerStateNotification(handle, state, detail)); }
        catch (Exception error) { Interlocked.CompareExchange(ref _callbackFailure, error, null); }
    }

    public BinaryDataNotification[] DrainBinaryData() => DrainDataQueue(_binaryData);
    public PeerStateNotification[] DrainPeerStates() => DrainDataQueue(_peerStates);

    private T[] DrainDataQueue<T>(ConcurrentQueue<T> queue)
    {
        lock (CallGate)
        {
            RequireActive();
            if (Volatile.Read(ref _callbackFailure) is Exception error)
                throw new InvalidOperationException("An original native callback could not be recorded.", error);
            var result = new List<T>();
            int count = queue.Count;
            while (count-- > 0 && queue.TryDequeue(out var value)) result.Add(value);
            return result.ToArray();
        }
    }

    /// <summary>
    /// Submits opaque bytes to the original binary channel. Normal return means
    /// native submission, not delivery. The original Windows implementation
    /// synchronously copies the input into its own buffer before asynchronous
    /// dispatch; unknown native outcomes retain this binding's input and owner.
    /// </summary>
    public void SendBinary(int handle, ReadOnlySpan<byte> data)
    {
        lock (CallGate)
        {
            RequireActive();
            if (!_openRooms.Contains(handle)) throw new ArgumentException("Room is not owned by this engine.", nameof(handle));
            if (data.Length is < 1 or >= 512 * 1024) throw new ArgumentOutOfRangeException(nameof(data));
            var input = new RoomInputs(data);
            try { _roomInputs.Add(input); }
            catch { input.Dispose(); throw; }
            _faulted = true;
            int status = _sendBinary(handle, input.Config, data.Length);
            if (status != 0) throw new InvalidOperationException($"Original binary submission failed: {status}");
            _faulted = false;
            _roomInputs.Remove(input);
            input.Dispose();
        }
    }
}
