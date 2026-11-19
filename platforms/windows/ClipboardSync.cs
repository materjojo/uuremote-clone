using System;
using System.Windows;
using System.Windows.Threading;
using GvPb;

namespace UURemoteClone;

/// <summary>
/// 剪贴板同步（官方协议 ClipboardChange，信封 field 17）。
/// 发送：轮询 WPF Clipboard（500ms）变化 -> ClipboardChange(TEXT)
/// 接收：写回 WPF Clipboard（带回环抑制）
/// protobuf 类型由官方 gv_pb proto 生成（Google.Protobuf）。
/// </summary>
public sealed class ClipboardSync : IDisposable
{
    public interface Sender { void SendControl(byte[] data); }

    private readonly DispatcherTimer _timer;
    private readonly Func<string?> _readClipboard;
    private readonly Action<string> _writeClipboard;
    private readonly Sender _sender;
    private string? _lastSent;
    private string? _lastReceived;
    private ulong _seq = 1;

    public ClipboardSync(Sender sender, Dispatcher dispatcher)
        : this(sender,
               () => Clipboard.ContainsText() ? Clipboard.GetText() : null,
               t => Clipboard.SetText(t),
               dispatcher) { }

    public ClipboardSync(Sender sender, Func<string?> read, Action<string> write, Dispatcher dispatcher)
    {
        _sender = sender;
        _readClipboard = read;
        _writeClipboard = write;
        _timer = new DispatcherTimer(DispatcherPriority.Background, dispatcher)
        {
            Interval = TimeSpan.FromMilliseconds(500)
        };
        _timer.Tick += (_, _) => Poll();
        _timer.Start();
    }

    public void Stop() => _timer.Stop();

    private void Poll()
    {
        try
        {
            var text = _readClipboard();
            if (string.IsNullOrEmpty(text)) return;
            if (text == _lastSent || text == _lastReceived) return;
            _lastSent = text;

            var message = new Message
            {
                Seq = _seq++,
                Timestamp = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds(),
                ClipboardChange = new ClipboardChange
                {
                    Type = ClipboardChange.Types.Type.Text,
                    ContentId = _seq,
                    Content = text,
                    ToBeContinued = false
                }
            };
            _sender.SendControl(message.ToByteArray());
        }
        catch { /* 剪贴板被占用时跳过本轮 */ }
    }

    /** 收到对端 ClipboardChange：解析并写回本地剪贴板 */
    public void Apply(byte[] data)
    {
        try
        {
            var message = Message.Parser.ParseFrom(data);
            if (message.ClipboardChange == null) return;
            var text = message.ClipboardChange.Content;
            if (string.IsNullOrEmpty(text)) return;
            if (text == _lastSent || text == _lastReceived) return;
            _lastReceived = text;
            _writeClipboard(text);
        }
        catch { }
    }

    public void Dispose() => Stop();
}
