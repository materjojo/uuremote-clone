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
        base.OnStartup(e);
        if (e.Args.Length != 2 || e.Args[0] != "--capture-ui") { new MainWindow().Show(); return; }
        // CI runs the published app's actual home window. No fixture devices,
        // transport bypass or alternate view hierarchy is used for the image.
        DispatcherUnhandledException += (_, error) => {
            File.WriteAllText(e.Args[1] + ".error.txt", error.Exception.ToString());
            error.Handled = true; Shutdown(1);
        };
        MainWindow window;
        try { window = new MainWindow(); window.Show(); }
        catch (Exception error) { File.WriteAllText(e.Args[1] + ".error.txt", error.ToString()); Shutdown(1); return; }
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
            } catch (Exception error) { File.WriteAllText(e.Args[1] + ".error.txt", error.ToString()); Shutdown(1); }
        }));
    }
}
