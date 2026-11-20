using System;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace UURemoteClone;

/// <summary>
/// 控制端远端画面渲染（WPF）。
/// 解码后的 BGRA 帧拷入 WriteableBitmap；尚未验证与原版 D3D 渲染的视觉一致性。
/// </summary>
public sealed class RemoteVideoControl : Image
{
    private WriteableBitmap? _bitmap;
    private int _width, _height;
    private readonly object _lock = new();

    public RemoteVideoControl()
    {
        Stretch = Stretch.Uniform;
        SnapsToDevicePixels = true;
        RenderOptions.SetBitmapScalingMode(this, BitmapScalingMode.LowQuality);
    }

    /// <summary>提交一帧解码后的 BGRA 数据</summary>
    public void RenderFrame(byte[] bgra, int width, int height)
    {
        if (width <= 0 || height <= 0 || bgra.Length < width * height * 4) return;
        Dispatcher.Invoke(() =>
        {
            lock (_lock)
            {
                if (_bitmap == null || _bitmap.PixelWidth != width || _bitmap.PixelHeight != height)
                {
                    _bitmap = new WriteableBitmap(width, height, 96, 96, PixelFormats.Bgra32, null);
                    Source = _bitmap;
                    _width = width;
                    _height = height;
                }
                var rect = new Int32Rect(0, 0, width, height);
                _bitmap.WritePixels(rect, bgra, width * 4, 0);
            }
        });
    }

    public bool TryNormalize(Point position, out float nx, out float ny)
    {
        nx = ny = 0;
        if (_width <= 0 || _height <= 0 || ActualWidth <= 0 || ActualHeight <= 0) return false;
        double scale = Math.Min(ActualWidth / _width, ActualHeight / _height);
        double width = _width * scale, height = _height * scale;
        nx = (float)((position.X - (ActualWidth - width) / 2) / width);
        ny = (float)((position.Y - (ActualHeight - height) / 2) / height);
        return nx >= 0 && nx <= 1 && ny >= 0 && ny <= 1;
    }

    public void Clear()
    {
        Dispatcher.Invoke(() => { Source = null; _bitmap = null; _width = _height = 0; });
    }
}
