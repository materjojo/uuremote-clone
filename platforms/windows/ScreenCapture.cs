using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Threading;
using System.Threading.Tasks;

namespace UURemoteClone;

/// <summary>Windows 桌面采集（GDI 路径；DXGI/WGC 硬件路径待接入）</summary>
public sealed class ScreenCapture : IDisposable
{
    public event Action<byte[], int, int>? FrameReady;

    private CancellationTokenSource? _cts;
    private Task? _loop;

    public void Start(int fps = 30)
    {
        Stop();
        _cts = new CancellationTokenSource();
        var token = _cts.Token;
        _loop = Task.Run(async () =>
        {
            int delay = Math.Max(1, 1000 / Math.Max(1, fps));
            while (!token.IsCancellationRequested)
            {
                try
                {
                    var bounds = System.Windows.Forms.SystemInformation.VirtualScreen;
                    using var bitmap = new Bitmap(bounds.Width, bounds.Height, PixelFormat.Format32bppArgb);
                    using (var graphics = Graphics.FromImage(bitmap))
                    {
                        graphics.CopyFromScreen(bounds.Left, bounds.Top, 0, 0, bounds.Size, CopyPixelOperation.SourceCopy);
                    }
                    var data = bitmap.LockBits(new Rectangle(0, 0, bitmap.Width, bitmap.Height),
                        ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
                    var buffer = new byte[data.Stride * data.Height];
                    System.Runtime.InteropServices.Marshal.Copy(data.Scan0, buffer, 0, buffer.Length);
                    bitmap.UnlockBits(data);
                    FrameReady?.Invoke(buffer, bitmap.Width, bitmap.Height);
                }
                catch
                {
                    // 锁屏/权限切换时跳过该帧
                }
                await Task.Delay(delay, token).ConfigureAwait(false);
            }
        }, token);
    }

    public void Stop()
    {
        _cts?.Cancel();
        try { _loop?.Wait(500); } catch { }
        _cts?.Dispose();
        _cts = null;
        _loop = null;
    }

    public void Dispose() => Stop();
}
