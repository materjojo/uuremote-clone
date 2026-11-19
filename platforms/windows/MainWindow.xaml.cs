using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using Google.Protobuf;
using SIPSorcery.Net;
using GvPb;

namespace UURemoteClone;

public record Device(string Id, string Name, string Platform);

/// <summary>主窗口：设备列表 -> 远控视图（WebRTC + H264 + gv_pb.InputEvent）</summary>
public partial class MainWindow : Window, StreamerSession.IListener, ClipboardSync.Sender
{
    private readonly List<Device> _devices = new()
    {
        new("demo-win-001", "工作室主机", "Windows · 4.48.1"),
        new("demo-mac-002", "MacBook Pro", "macOS · 4.48.1")
    };

    private StreamerSession? _session;
    private WindowsVideoPipeline? _pipeline;
    private ClipboardSync? _clipboard;
    private long _seq;

    public MainWindow()
    {
        InitializeComponent();
        DeviceList.ItemsSource = _devices;
    }

    private void Connect_Click(object sender, RoutedEventArgs e)
    {
        var id = (sender as Button)?.Tag as string ?? "";
        DeviceView.Visibility = Visibility.Collapsed;
        RemoteView.Visibility = Visibility.Visible;
        StatusText.Text = $"正在连接 {id} …";

        try
        {
            _pipeline = new WindowsVideoPipeline(preferHardware: true);
            _pipeline.FrameDecoded += (bgra, w, h) => VideoCanvas.RenderFrame(bgra, w, h);
            _session = new StreamerSession(this);
            _clipboard = new ClipboardSync(this, Dispatcher);
            _ = _session.StartAsControllerAsync();
        }
        catch (Exception ex)
        {
            StatusText.Text = "初始化失败：" + ex.Message;
        }
    }

    private void Disconnect_Click(object sender, RoutedEventArgs e)
    {
        _clipboard?.Dispose();
        _clipboard = null;
        _session?.Dispose();
        _session = null;
        _pipeline?.Dispose();
        _pipeline = null;
        VideoCanvas.Clear();
        RemoteView.Visibility = Visibility.Collapsed;
        DeviceView.Visibility = Visibility.Visible;
    }

    private void Nav_Click(object sender, RoutedEventArgs e)
    {
        var tag = (sender as Button)?.Tag as string ?? "devices";
        foreach (var b in new[] { NavDevices, NavFiles, NavTerminal, NavSettings })
            b.Foreground = b.Tag as string == tag
                ? (Brush)FindResource("Accent") : (Brush)FindResource("Muted");

        DeviceList.Visibility = tag == "devices" ? Visibility.Visible : Visibility.Collapsed;
        PagePlaceholder.Visibility = tag == "devices" ? Visibility.Collapsed : Visibility.Visible;
        switch (tag)
        {
            case "files":
                PagePlaceholder.Text = "文件传输\n\n连接后可在远控窗口中拖拽文件，使用官方 FileTransfer 协议。";
                break;
            case "terminal":
                PagePlaceholder.Text = "终端\n\n通过 tmux 会话管理被控端终端（uuyc-cli）。";
                break;
            case "settings":
                PagePlaceholder.Text = "设置\n\nUURemoteClone 4.48.1\n远程连接与媒体功能正在开发。";
                break;
            default:
                PagePlaceholder.Text = "";
                break;
        }
    }

    private void FullScreen_Click(object sender, RoutedEventArgs e)
    {
        WindowState = WindowState == WindowState.Maximized
            ? WindowState.Normal : WindowState.Maximized;
    }

    // ---- StreamerSession.IListener ----

    public void OnOffer(string sdp) =>
        Dispatcher.Invoke(() => StatusText.Text = $"已发送 Offer（SDP {sdp.Length} 字节），等待应答");

    public void OnCandidate(RTCIceCandidateInit candidate) { }

    public void SendControl(byte[] data) => _session?.SendControl(data);

    public void OnState(RTCPeerConnectionState state) =>
        Dispatcher.Invoke(() => StatusText.Text = "连接状态：" + state);

    public void OnControl(byte[] data)
    {
        try
        {
            var m = Message.Parser.ParseFrom(data);
            if (m.ClipboardChange != null) { _clipboard?.Apply(data); return; }
            if (m.Screens != null && m.Screens.Screens.Count > 0)
                Dispatcher.Invoke(() => StatusText.Text = $"屏幕列表：{m.Screens.Screens.Count} 个");
        }
        catch
        {
            // 非 protobuf：视为 H264 视频分片
            _pipeline?.DecodeH264(data);
        }
    }

    // ---- 输入：归一化 -> gv_pb.InputEvent -> CONTROL_DATA_CHANNEL ----

    private float NormX(double x) => (float)Math.Max(0, Math.Min(1, x / Math.Max(1, VideoCanvas.ActualWidth)));
    private float NormY(double y) => (float)Math.Max(0, Math.Min(1, y / Math.Max(1, VideoCanvas.ActualHeight)));

    private void SendTouch(int eventType, MouseEventArgs e)
    {
        if (_session == null) return;
        var pos = e.GetPosition(VideoCanvas);
        var point = new TouchEventPoint { Id = 0, X = NormX(pos.X), Y = NormY(pos.Y) };
        var touch = new TouchEvent { EventType = (TouchEvent.Types.TouchEventType)eventType };
        touch.TouchPoints.Add(point);
        var input = new InputEvent { TouchEvent = touch };
        var message = new Message
        {
            Seq = ++_seq,
            Timestamp = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds(),
            InputEvent = input
        };
        _session.SendControl(message.ToByteArray());
    }

    private void Video_MouseDown(object sender, MouseButtonEventArgs e) => SendTouch(1, e);
    private void Video_MouseUp(object sender, MouseButtonEventArgs e) => SendTouch(3, e);
    private void Video_MouseMove(object sender, MouseEventArgs e)
    {
        if (e.LeftButton == MouseButtonState.Pressed || e.RightButton == MouseButtonState.Pressed)
            SendTouch(2, e);
    }

    protected override void OnClosing(CancelEventArgs e)
    {
        _clipboard?.Dispose();
        _session?.Dispose();
        _pipeline?.Dispose();
        base.OnClosing(e);
    }
}
