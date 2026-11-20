using System;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Linq;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using Google.Protobuf;
using SIPSorcery.Net;
using GvPb;

namespace UURemoteClone;

public partial class MainWindow : Window, StreamerSession.IListener, ClipboardSync.Sender
{
    private readonly ObservableCollection<PeerInvitation> _devices = new();
    private readonly PeerSettings _settings;
    private StreamerSession? _session;
    private WindowsVideoPipeline? _pipeline;
    private ScreenCapture? _capture;
    private ClipboardSync? _clipboard;
    private PeerMailbox? _mailbox;
    private PeerAPI? _sessionApi, _hostApi;
    private CancellationTokenSource? _receiving;
    private bool _hostMode;
    private long _seq;

    public MainWindow()
    {
        InitializeComponent();
        try { _settings = PeerSettings.Load(); }
        catch (Exception ex) { MessageBox.Show("无法读取设备配置：" + ex.Message); _settings = new PeerSettings(); }
        foreach (var device in _settings.Devices) _devices.Add(device);
        DeviceList.ItemsSource = _devices;
        ServerBox.Text = _settings.Server;
        RefreshEmpty();
    }

    private void RefreshEmpty() => EmptyState.Visibility = _devices.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
    private void SaveDevices() { _settings.Devices = _devices.ToList(); _settings.Save(); RefreshEmpty(); }
    private void AddDevice_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new Window { Title = "添加设备", Width = 520, Height = 280, Owner = this,
            WindowStartupLocation = WindowStartupLocation.CenterOwner, Background = (Brush)FindResource("Bg") };
        var panel = new StackPanel { Margin = new Thickness(24) };
        panel.Children.Add(new TextBlock { Text = "粘贴对方生成的配对码", Foreground = Brushes.White, Margin = new Thickness(0, 0, 0, 12) });
        var input = new TextBox { AcceptsReturn = true, Height = 110, TextWrapping = TextWrapping.Wrap };
        panel.Children.Add(input);
        var add = new Button { Content = "添加", Margin = new Thickness(0, 16, 0, 0) };
        add.Click += (_, _) => {
            try {
                var peer = PeerInvitation.Parse(input.Text);
                if (peer.Id == _settings.Id) throw new ArgumentException("不能把本机添加为远程设备");
                var previous = _devices.FirstOrDefault(d => d.Id == peer.Id && d.Server == peer.Server);
                if (previous != null) _devices.Remove(previous);
                _devices.Add(peer); SaveDevices(); dialog.Close();
            } catch (Exception error) { MessageBox.Show(dialog, error.Message, "无法添加"); }
        };
        panel.Children.Add(add); dialog.Content = panel; dialog.ShowDialog();
    }
    private void RemoveDevice_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as Button)?.Tag is string id) {
            var device = _devices.FirstOrDefault(d => d.Id == id);
            if (device != null) { _devices.Remove(device); SaveDevices(); }
        }
    }

    private async void Connect_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as Button)?.Tag is not string id) return;
        var device = _devices.FirstOrDefault(d => d.Id == id);
        if (device == null) return;
        Disconnect();
        DeviceView.Visibility = Visibility.Collapsed;
        RemoteView.Visibility = Visibility.Visible;
        StatusText.Text = $"正在请求 {device.Name}，等待对端确认…";
        try {
            _sessionApi = new PeerAPI(device.Server);
            var result = await _sessionApi.RequestAsync("/v1/connect", body: new {
                target = device.Id, key = device.Key, name = Environment.MachineName, platform = "windows" });
            var mailbox = new PeerMailbox(_sessionApi, result.GetProperty("id").GetString()!, result.GetProperty("token").GetString()!);
            BindMailbox(mailbox, false);
        } catch (Exception ex) { StatusText.Text = "连接失败：" + ex.Message; }
    }

    private void CreateSession(bool host)
    {
        _hostMode = host;
        // This independent path uses packaged FFmpeg. Hardware parity with the
        // proprietary runtime is a separate integration, not inferred here.
        _pipeline = new WindowsVideoPipeline(preferHardware: false);
        _pipeline.FrameDecoded += (bgra, w, h) => VideoCanvas.RenderFrame(bgra, w, h);
        _session = new StreamerSession(this, host);
        _session.VideoFrame += _pipeline.DecodeH264;
        _clipboard = new ClipboardSync(this, Dispatcher);
        if (host) {
            _capture = new ScreenCapture();
            _pipeline.AttachCapture(_capture, _session.SendVideo);
        }
    }

    private void BindMailbox(PeerMailbox mailbox, bool host)
    {
        _mailbox = mailbox;
        mailbox.Error += message => Dispatcher.BeginInvoke(new Action(() => StatusText.Text = message));
        mailbox.Signal += (type, data) => Dispatcher.InvokeAsync(async () => {
            if (_mailbox != mailbox) return;
            try {
                switch (type) {
                    case "accepted": CreateSession(false); await _session!.StartAsControllerAsync(); break;
                    case "offer" when host:
                        var answer = await _session!.HandleOfferAsync(data.GetProperty("sdp").GetString()!);
                        mailbox.Send("answer", new { sdp = answer }); break;
                    case "answer": _session?.HandleAnswer(data.GetProperty("sdp").GetString()!); break;
                    case "candidate":
                        _session?.AddCandidate(data.GetProperty("candidate").GetString()!, data.GetProperty("sdpMid").GetString() ?? "0",
                            data.GetProperty("sdpMLineIndex").GetInt32()); break;
                    case "close": Disconnect(); HostStatus.Text = "对端已拒绝或断开"; break;
                }
            } catch (Exception ex) { StatusText.Text = "会话失败：" + ex.Message; mailbox.Send("close"); }
        }).Task.Unwrap();
        mailbox.Start();
    }

    private async void Receive_Click(object sender, RoutedEventArgs e)
    {
        if (_receiving != null) { StopReceiving(); return; }
        try {
            _settings.Server = PeerAPI.Endpoint(ServerBox.Text).AbsoluteUri;
            _settings.Save();
            _hostApi = new PeerAPI(_settings.Server);
            await _hostApi.RequestAsync("/v1/register", body: new { id = _settings.Id, key = _settings.OwnerKey,
                pair_key = _settings.PairKey, name = Environment.MachineName, platform = "windows" });
            _receiving = new CancellationTokenSource();
            ReceiveButton.Content = "停止接收";
            CopyCodeButton.IsEnabled = true;
            HostStatus.Text = "等待连接 · 每次连接需本机确认";
            _ = PollRequests(_receiving.Token);
        } catch (Exception ex) { StopReceiving(); HostStatus.Text = ex.Message; }
    }
    private async Task PollRequests(CancellationToken token)
    {
        var handled = new System.Collections.Generic.HashSet<string>();
        try {
            while (!token.IsCancellationRequested) {
                var response = await _hostApi!.RequestAsync($"/v1/devices/{_settings.Id}/inbox", _settings.OwnerKey, ct: token);
                foreach (var item in response.GetProperty("requests").EnumerateArray()) {
                    var id = item.GetProperty("id").GetString()!;
                    if (!handled.Add(id)) continue;
                    var box = new PeerMailbox(_hostApi, id, _settings.OwnerKey);
                    if (_session != null || MessageBox.Show(this, $"“{item.GetProperty("name").GetString()}”请求查看并控制本机屏幕。允许？",
                        "远程控制请求", MessageBoxButton.YesNo, MessageBoxImage.Question) != MessageBoxResult.Yes) {
                        box.Start(); box.Send("close"); _ = DisposeLater(box); continue;
                    }
                    try {
                        CreateSession(true);
                        BindMailbox(box, true);
                        box.Send("accept");
                        HostStatus.Text = "正在协商连接 · 可点击停止接收断开";
                    } catch (Exception ex) { box.Start(); box.Send("close"); _ = DisposeLater(box); Disconnect(); HostStatus.Text = ex.Message; }
                }
                await Task.Delay(2000, token);
            }
        } catch (OperationCanceledException) { }
        catch (Exception ex) { StopReceiving(); HostStatus.Text = ex.Message; }
    }
    private void CopyCode_Click(object sender, RoutedEventArgs e)
    {
        if (_receiving != null) System.Windows.Clipboard.SetText(new PeerInvitation(1, _settings.Server, _settings.Id,
            _settings.PairKey, Environment.MachineName, "windows").Code);
    }
    private static async Task DisposeLater(PeerMailbox mailbox) { await Task.Delay(600); mailbox.Dispose(); }
    private void StopReceiving()
    {
        _receiving?.Cancel(); _receiving = null;
        if (_hostMode) Disconnect();
        ReceiveButton.Content = "开启接收"; CopyCodeButton.IsEnabled = false;
        HostStatus.Text = "未开启接收远程连接";
    }
    private void Disconnect_Click(object sender, RoutedEventArgs e) => Disconnect();
    private void Disconnect()
    {
        _mailbox?.Send("close");
        if (_mailbox != null) _ = DisposeLater(_mailbox);
        _mailbox = null;
        _capture?.Dispose(); _capture = null;
        _clipboard?.Dispose(); _clipboard = null;
        _session?.Dispose(); _session = null;
        _pipeline?.Dispose(); _pipeline = null;
        VideoCanvas.Clear();
        RemoteView.Visibility = Visibility.Collapsed;
        DeviceView.Visibility = Visibility.Visible;
        _hostMode = false;
    }
    private void Nav_Click(object sender, RoutedEventArgs e)
    {
        var tag = (sender as Button)?.Tag as string ?? "devices";
        foreach (var b in new[] { NavDevices, NavFiles, NavTerminal, NavSettings })
            b.Foreground = b.Tag as string == tag ? (Brush)FindResource("Accent") : (Brush)FindResource("Muted");
        DeviceList.Visibility = tag == "devices" ? Visibility.Visible : Visibility.Collapsed;
        EmptyState.Visibility = tag == "devices" && _devices.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        PagePlaceholder.Visibility = tag == "devices" ? Visibility.Collapsed : Visibility.Visible;
        PagePlaceholder.Text = tag switch {
            "files" => "文件传输业务尚未接入当前会话。",
            "terminal" => "终端业务尚未接入当前会话。",
            "settings" => "配对记录仅保存在本机。公网信令使用 HTTPS；Tailscale 需要两端已加入同一网络。",
            _ => ""
        };
    }
    private void FullScreen_Click(object sender, RoutedEventArgs e) => WindowState = WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized;
    public void OnOffer(string sdp) => _mailbox?.Send("offer", new { sdp });
    public void OnCandidate(RTCIceCandidateInit candidate) => _mailbox?.Send("candidate", candidate);
    public void SendControl(byte[] data) => _session?.SendControl(data);
    public void OnState(RTCPeerConnectionState state) => Dispatcher.BeginInvoke(new Action(() => {
        StatusText.Text = "连接状态：" + state;
        if (_hostMode) {
            HostStatus.Text = "被控连接：" + state;
            if (state == RTCPeerConnectionState.connected) _capture?.Start(30);
            else if (state is RTCPeerConnectionState.failed or RTCPeerConnectionState.closed or RTCPeerConnectionState.disconnected) _capture?.Stop();
        }
    }));
    public void OnControl(byte[] data)
    {
        try {
            var message = Message.Parser.ParseFrom(data);
            if (message.ClipboardChange != null) { Dispatcher.BeginInvoke(new Action(() => _clipboard?.Apply(data))); return; }
            if (_hostMode && message.InputEvent?.TouchEvent is { } touch) {
                foreach (var p in touch.TouchPoints) InputInjector.HandleTouch((GvTouchEventType)(int)touch.EventType, p.X, p.Y, p.Id);
            }
        } catch (InvalidProtocolBufferException) { }
    }
    private float NormX(double x) => (float)Math.Clamp(x / Math.Max(1, VideoCanvas.ActualWidth), 0, 1);
    private float NormY(double y) => (float)Math.Clamp(y / Math.Max(1, VideoCanvas.ActualHeight), 0, 1);
    private void SendTouch(int eventType, MouseEventArgs e)
    {
        if (_session == null || _hostMode) return;
        var pos = e.GetPosition(VideoCanvas);
        var touch = new TouchEvent { EventType = (TouchEvent.Types.TouchEventType)eventType };
        touch.TouchPoints.Add(new TouchEventPoint { Id = 0, X = NormX(pos.X), Y = NormY(pos.Y) });
        _session.SendControl(new Message { Seq = ++_seq, Timestamp = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds(),
            InputEvent = new InputEvent { TouchEvent = touch } }.ToByteArray());
    }
    private void Video_MouseDown(object sender, MouseButtonEventArgs e) { VideoCanvas.CaptureMouse(); SendTouch(1, e); }
    private void Video_MouseUp(object sender, MouseButtonEventArgs e) { SendTouch(3, e); VideoCanvas.ReleaseMouseCapture(); }
    private void Video_MouseMove(object sender, MouseEventArgs e) { if (e.LeftButton == MouseButtonState.Pressed) SendTouch(2, e); }
    protected override void OnClosing(CancelEventArgs e) { StopReceiving(); Disconnect(); base.OnClosing(e); }
}
