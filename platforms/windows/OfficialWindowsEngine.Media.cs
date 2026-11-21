using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

namespace UURemoteClone;

public sealed partial class OfficialWindowsEngine
{
    public sealed record MediaTrackNotification(int Handle, string Json);
    // Keep the original numeric arguments and six borrowed viewport integers.
    // Their domains are not inferred from Android's similarly named callback.
    public sealed record FrameChangeNotification(int Handle, int Value1, int Value2, int Value3,
        int TrackIndex, int[] Viewport);
    public readonly record struct CaptureFailureNotification(int Handle, int Value1, int Value2, int Value3, int Value4);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate void FrameChangeCallback(int handle, int value1, int value2, int value3,
        int trackIndex, IntPtr viewport);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate void CaptureFailureCallback(int handle, int value1, int value2, int value3, int value4);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int StartVideoFunction(int handle, IntPtr config);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int StopVideoFunction(int handle, int trackIndex);

    // Original Windows core 0x180a309c0 copies 0x68 bytes. Capture type 1
    // consumes HWND at +0x40 (0x180ba7d50 / 0x180ba7210). Other union members,
    // dump pointers and unrecovered options remain zero.
    [StructLayout(LayoutKind.Explicit, Size = 0x68)]
    private struct WindowCaptureConfig
    {
        [FieldOffset(0x00)] public int FramesPerSecond;
        [FieldOffset(0x04)] public int FrameQuality;
        [FieldOffset(0x0c)] public int TrackIndex;
        [FieldOffset(0x10)] public int CaptureType;
        [FieldOffset(0x14)] public int Codec;
        [FieldOffset(0x18)] public int Chroma;
        [FieldOffset(0x1c)] public int MaxScaleWidth;
        [FieldOffset(0x20)] public int MaxScaleHeight;
        [FieldOffset(0x40)] public IntPtr Window;
    }

    [StructLayout(LayoutKind.Explicit, Size = 0x10)]
    private struct VideoRenderConfig
    {
        [FieldOffset(0x00)] public IntPtr Window;
        [FieldOffset(0x08)] public int TrackIndex;
        // +0xc renderer option remains zero.
    }

    private readonly BinaryDataCallback _mediaTrackCallback;
    private readonly FrameChangeCallback _frameChangeCallback;
    private readonly CaptureFailureCallback _captureFailureCallback;
    private readonly ConcurrentQueue<MediaTrackNotification> _mediaTracks = new();
    private readonly ConcurrentQueue<FrameChangeNotification> _frameChanges = new();
    private readonly ConcurrentQueue<CaptureFailureNotification> _captureFailures = new();
    private readonly HashSet<(int Handle, int Track)> _videoCaptures = new();
    private readonly HashSet<(int Handle, int Track)> _videoRenderers = new();
    private StartVideoFunction? _startVideoCapture;
    private StartVideoFunction? _startVideoRender;
    private StopVideoFunction? _stopVideoCapture;
    private StopVideoFunction? _stopVideoRender;

    private void InstallMediaCallbacks(IntPtr[] callbacks)
    {
        if (Role == OfficialStreamer.Role.Controller)
        {
            callbacks[0] = Marshal.GetFunctionPointerForDelegate(_mediaTrackCallback);
            callbacks[2] = Marshal.GetFunctionPointerForDelegate(_frameChangeCallback);
        }
        else callbacks[8] = Marshal.GetFunctionPointerForDelegate(_captureFailureCallback);
    }

    private void RecordMediaTrack(int handle, IntPtr data, uint size)
    {
        try
        {
            string json = new UTF8Encoding(false, true).GetString(Copy(data, size, 65536));
            _mediaTracks.Enqueue(new MediaTrackNotification(handle, json));
        }
        catch (Exception error) { Interlocked.CompareExchange(ref _callbackFailure, error, null); }
    }

    private void RecordFrameChange(int handle, int value1, int value2, int value3, int trackIndex, IntPtr viewport)
    {
        try
        {
            if (viewport == IntPtr.Zero) throw new InvalidOperationException("Original viewport is absent.");
            var copy = new int[6];
            Marshal.Copy(viewport, copy, 0, copy.Length);
            _frameChanges.Enqueue(new FrameChangeNotification(handle, value1, value2, value3, trackIndex, copy));
        }
        catch (Exception error) { Interlocked.CompareExchange(ref _callbackFailure, error, null); }
    }

    private void RecordCaptureFailure(int handle, int value1, int value2, int value3, int value4)
    {
        try { _captureFailures.Enqueue(new CaptureFailureNotification(handle, value1, value2, value3, value4)); }
        catch (Exception error) { Interlocked.CompareExchange(ref _callbackFailure, error, null); }
    }

    public MediaTrackNotification[] DrainMediaTracks() => DrainDataQueue(_mediaTracks);
    public FrameChangeNotification[] DrainFrameChanges() => DrainDataQueue(_frameChanges);
    public CaptureFailureNotification[] DrainCaptureFailures() => DrainDataQueue(_captureFailures);

    private void RequireVideoRoom(int handle, OfficialStreamer.Role role, int trackIndex)
    {
        RequireActive();
        if (Role != role) throw new InvalidOperationException("Original video operation is unavailable for this role.");
        if (!_openRooms.Contains(handle)) throw new ArgumentException("Room is not owned by this engine.", nameof(handle));
        if (trackIndex is < 0 or > 15) throw new ArgumentOutOfRangeException(nameof(trackIndex));
    }

    /// <summary>
    /// Starts the original Windows window-capture path with H264/chroma=1,
    /// quality=1 and bounded scaling. The caller owns the HWND and must keep it
    /// alive through StopVideoCapture or successful engine disposal. Invocation
    /// does not establish that the peer has decoded a frame or that a GPU is used.
    /// </summary>
    public void StartWindowCapture(int handle, IntPtr window, int trackIndex = 0, int framesPerSecond = 15)
    {
        lock (CallGate)
        {
            RequireVideoRoom(handle, OfficialStreamer.Role.Controlled, trackIndex);
            if (window == IntPtr.Zero) throw new ArgumentException("A live capture window is required.", nameof(window));
            if (framesPerSecond is < 1 or > 60) throw new ArgumentOutOfRangeException(nameof(framesPerSecond));
            if (_videoCaptures.Contains((handle, trackIndex))) throw new InvalidOperationException("Video track is already capturing.");
            var config = new WindowCaptureConfig
            {
                FramesPerSecond = framesPerSecond, FrameQuality = 1, TrackIndex = trackIndex,
                CaptureType = 1, Codec = 1, Chroma = 1, MaxScaleWidth = 1280, MaxScaleHeight = 720,
                Window = window
            };
            var input = new RoomInputs(config);
            try { _roomInputs.Add(input); }
            catch { input.Dispose(); throw; }
            _faulted = true;
            int status = _startVideoCapture!(handle, input.Config);
            if (status != 0) throw new InvalidOperationException($"Original window capture failed: {status}");
            _videoCaptures.Add((handle, trackIndex));
            _faulted = false;
        }
    }

    /// <summary>Attaches the original renderer to a caller-owned HWND and received video track.</summary>
    public void StartVideoRender(int handle, IntPtr window, int trackIndex)
    {
        lock (CallGate)
        {
            RequireVideoRoom(handle, OfficialStreamer.Role.Controller, trackIndex);
            if (window == IntPtr.Zero) throw new ArgumentException("A live render window is required.", nameof(window));
            if (_videoRenderers.Contains((handle, trackIndex))) throw new InvalidOperationException("Video track is already rendering.");
            var input = new RoomInputs(new VideoRenderConfig { Window = window, TrackIndex = trackIndex });
            try { _roomInputs.Add(input); }
            catch { input.Dispose(); throw; }
            _faulted = true;
            int status = _startVideoRender!(handle, input.Config);
            if (status != 0) throw new InvalidOperationException($"Original video renderer failed: {status}");
            _videoRenderers.Add((handle, trackIndex));
            _faulted = false;
        }
    }

    public bool StopVideoCapture(int handle, int trackIndex = 0)
    {
        lock (CallGate)
        {
            RequireVideoRoom(handle, OfficialStreamer.Role.Controlled, trackIndex);
            if (!_videoCaptures.Contains((handle, trackIndex))) return false;
            _faulted = true;
            int status = _stopVideoCapture!(handle, trackIndex);
            if (status != 0) throw new InvalidOperationException($"Original capture stop failed: {status}");
            _videoCaptures.Remove((handle, trackIndex));
            _faulted = false;
            return true;
        }
    }

    public bool StopVideoRender(int handle, int trackIndex)
    {
        lock (CallGate)
        {
            RequireVideoRoom(handle, OfficialStreamer.Role.Controller, trackIndex);
            if (!_videoRenderers.Contains((handle, trackIndex))) return false;
            _faulted = true;
            int status = _stopVideoRender!(handle, trackIndex);
            if (status != 0) throw new InvalidOperationException($"Original render stop failed: {status}");
            _videoRenderers.Remove((handle, trackIndex));
            _faulted = false;
            return true;
        }
    }

    private void CloseRoomMedia(int handle)
    {
        foreach (var item in new List<(int Handle, int Track)>(_videoCaptures))
            if (item.Handle == handle) StopVideoCapture(handle, item.Track);
        foreach (var item in new List<(int Handle, int Track)>(_videoRenderers))
            if (item.Handle == handle) StopVideoRender(handle, item.Track);
    }

    private sealed partial class RoomInputs
    {
        public RoomInputs(WindowCaptureConfig config)
        {
            try
            {
                if (Marshal.SizeOf<WindowCaptureConfig>() != 0x68) throw new InvalidOperationException("Unsupported capture layout.");
                Config = Allocate(0x68);
                Marshal.StructureToPtr(config, Config, false);
            }
            catch { Dispose(); throw; }
        }
        public RoomInputs(VideoRenderConfig config)
        {
            try
            {
                if (Marshal.SizeOf<VideoRenderConfig>() != 0x10) throw new InvalidOperationException("Unsupported renderer layout.");
                Config = Allocate(0x10);
                Marshal.StructureToPtr(config, Config, false);
            }
            catch { Dispose(); throw; }
        }
    }
}
