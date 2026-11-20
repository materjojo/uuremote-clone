using System;
using System.Collections.Generic;
using SIPSorceryMedia.Abstractions;
using SIPSorceryMedia.FFmpeg;
using FFmpeg.AutoGen;

namespace UURemoteClone;

/// <summary>
/// 独立连接路径的视频管线。尚未证明与官方 streamer.dll 编码路径相同。
/// 编码：BGRA(GDI 采集) -> FFmpeg H.264；硬件可用性需运行验证。
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

    public WindowsVideoPipeline(bool preferHardware = true, string? runtimePath = null)
    {
        FFmpegInit.Initialise(libPath: runtimePath ?? System.IO.Path.Combine(AppContext.BaseDirectory, "ffmpeg"));

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
        // FFmpegVideoEncoder 8.0.12 ignores its requested output format and
        // returns RGB24. Preserve RawImage.Stride, including row padding.
        foreach (var frame in _decoder.DecodeVideoFaster(annexB, VideoPixelFormatsEnum.Rgb, VideoCodecsEnum.H264))
        {
            int width = frame.Width, height = frame.Height;
            if (width <= 0 || height <= 0 || frame.Stride < width * 3) continue;
            var rgb = new byte[checked(frame.Stride * height)];
            System.Runtime.InteropServices.Marshal.Copy(frame.Sample, rgb, 0, rgb.Length);
            var bgra = new byte[checked(width * height * 4)];
            for (int y = 0; y < height; y++) for (int x = 0; x < width; x++) {
                int source = y * frame.Stride + x * 3, target = (y * width + x) * 4;
                bgra[target] = rgb[source + 2]; bgra[target + 1] = rgb[source + 1];
                bgra[target + 2] = rgb[source]; bgra[target + 3] = 255;
            }
            FrameDecoded?.Invoke(bgra, width, height);
        }
    }

    /// <summary>被控端：GDI 采集 -> 编码 -> 送 WebRTC RTP</summary>
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
