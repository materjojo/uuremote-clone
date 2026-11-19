using System;
using System.Collections.Generic;
using SIPSorceryMedia.Abstractions;
using SIPSorceryMedia.FFmpeg;
using FFmpeg.AutoGen;

namespace UURemoteClone;

/// <summary>
/// Windows 视频编解码管线（H.264，功能等价于官方 streamer.dll 的编码路径）。
/// 编码：BGRA(GDI 采集) -> FFmpeg H.264（D3D11VA/NVENC 硬件可用时自动启用）
/// 解码：H.264 Annex-B -> BGRA 帧回调（渲染层显示）
/// </summary>
public sealed class WindowsVideoPipeline : IDisposable
{
    private readonly FFmpegVideoEncoder _encoder;
    private readonly FFmpegVideoEncoder _decoder;
    private bool _initialised;
    private bool _disposed;

    public event Action<byte[]>? FrameEncoded;   // 编码后的 H.264 Annex-B
    public event Action<byte[], int, int>? FrameDecoded; // 解码后的 BGRA + 宽高

    public WindowsVideoPipeline(bool preferHardware = true)
    {
        FFmpegInit.Initialise();

        // 优先硬件：D3D11VA（Windows 通用）；失败时 FFmpeg 自动软编兜底
        var hw = preferHardware
            ? AVHWDeviceType.AV_HWDEVICE_TYPE_D3D11VA
            : AVHWDeviceType.AV_HWDEVICE_TYPE_NONE;
        _encoder = new FFmpegVideoEncoder(HWDeviceType: hw);
        _decoder = new FFmpegVideoEncoder(HWDeviceType: hw);
        _initialised = true;
    }

    /// <summary>把一个 BGRA 帧编码为 H.264 并触发 FrameEncoded</summary>
    public void EncodeBgra(byte[] bgra, int width, int height, bool forceKey = false)
    {
        if (!_initialised) return;
        if (forceKey) _encoder.ForceKeyFrame();
        var encoded = _encoder.EncodeVideo(width, height, bgra,
            VideoPixelFormatsEnum.Bgra, VideoCodecsEnum.H264);
        if (encoded != null && encoded.Length > 0)
            FrameEncoded?.Invoke(encoded);
    }

    /// <summary>解码 H.264 Annex-B，逐帧触发 FrameDecoded</summary>
    public void DecodeH264(byte[] annexB)
    {
        if (!_initialised) return;
        foreach (var frame in _decoder.DecodeVideo(annexB, VideoPixelFormatsEnum.Bgra, VideoCodecsEnum.H264))
        {
            if (frame is VideoSample sample && sample.Sample != null)
                FrameDecoded?.Invoke(sample.Sample, (int)sample.Width, (int)sample.Height);
        }
    }

    /// <summary>被控端：GDI 采集 -> 编码 -> 送 WebRTC DataChannel</summary>
    public void AttachCapture(ScreenCapture capture, Action<byte[]> sendEncoded)
    {
        capture.FrameReady += (bgra, w, h) =>
        {
            if (forceKeyNext)
            {
                _encoder.ForceKeyFrame();
                forceKeyNext = false;
            }
            var encoded = _encoder.EncodeVideo(w, h, bgra,
                VideoPixelFormatsEnum.Bgra, VideoCodecsEnum.H264);
            if (encoded != null && encoded.Length > 0)
                sendEncoded(encoded);
        };
    }

    private volatile bool forceKeyNext;
    public void RequestKeyFrame() => forceKeyNext = true;

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        (_encoder as IDisposable)?.Dispose();
        (_decoder as IDisposable)?.Dispose();
    }
}
