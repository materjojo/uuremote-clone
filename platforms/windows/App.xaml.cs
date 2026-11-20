using System;
using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

namespace UURemoteClone;

public partial class App : Application
{
    protected override void OnStartup(StartupEventArgs e)
    {
        if (e.Args.Length != 2 || e.Args[0] != "--capture-ui") { base.OnStartup(e); return; }
        // CI runs the published app's actual home window. No fixture devices,
        // transport bypass or alternate view hierarchy is used for the image.
        StartupUri = null;
        base.OnStartup(e);
        var window = new MainWindow();
        window.Show();
        Dispatcher.BeginInvoke(DispatcherPriority.ApplicationIdle, new Action(() => {
            try {
                window.UpdateLayout();
                var bitmap = new RenderTargetBitmap((int)window.ActualWidth, (int)window.ActualHeight,
                    96, 96, PixelFormats.Pbgra32);
                bitmap.Render(window);
                var encoder = new PngBitmapEncoder();
                encoder.Frames.Add(BitmapFrame.Create(bitmap));
                string path = Path.GetFullPath(e.Args[1]);
                Directory.CreateDirectory(Path.GetDirectoryName(path)!);
                using (var output = File.Create(path)) encoder.Save(output);
                Shutdown(0);
            } catch { Shutdown(1); }
        }));
    }
}
