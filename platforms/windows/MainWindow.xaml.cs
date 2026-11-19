using System.Collections.Generic;
using System.Windows;
using System.Windows.Controls;

namespace UURemoteClone;

public record Device(string Id, string Name, string Platform);

public partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();
        DeviceList.ItemsSource = new List<Device>
        {
            new("demo-win-001", "工作室主机", "Windows · 4.48.1"),
            new("demo-mac-002", "MacBook Pro", "macOS · 4.48.1")
        };
        Gvpb.Initialize();
    }

    private void Connect_Click(object sender, RoutedEventArgs e)
    {
        var id = (sender as Button)?.Tag as string ?? "";
        MessageBox.Show($"将连接 {id}\n协议核心：{Gvpb.SchemaMessageCount()} 条消息", "UU远程");
    }
}
