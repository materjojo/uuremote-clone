using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using SIPSorcery.Net;

namespace UURemoteClone;

/// IPv6 disclosure first, IPv4/mDNS after 1.2s, installed overlay after 8s.
/// SDP candidates must use the same gate as trickled candidates.
internal sealed class PeerCandidateGate : IDisposable
{
    private readonly Action<RTCIceCandidateInit> _emit;
    private readonly Func<bool> _connected;
    private readonly object _gate = new();
    private readonly HashSet<string> _seen = new();
    private readonly Dictionary<int, List<RTCIceCandidateInit>> _queued = new();
    private readonly HashSet<int> _released = new();
    private readonly CancellationTokenSource _stop = new();
    public PeerCandidateGate(Action<RTCIceCandidateInit> emit, Func<bool> connected) { _emit = emit; _connected = connected; }

    internal static int Stage(string value)
    {
        if (StreamerSession.IsOverlay(value)) return 2;
        var fields = value.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        return fields.Length > 4 && fields[4].Contains(':') ? 0 : 1;
    }
    public void Submit(RTCIceCandidateInit value)
    {
        lock (_gate) {
            if (_stop.IsCancellationRequested || !_seen.Add($"{value.sdpMid}:{value.sdpMLineIndex}:{value.candidate}")) return;
            int stage = Stage(value.candidate);
            if (stage == 0 || _released.Contains(stage)) {
                if (stage == 0 || !_connected()) _emit(value);
            } else {
                if (!_queued.TryGetValue(stage, out var values)) {
                    values = new(); _queued[stage] = values;
                    _ = Release(stage);
                }
                values.Add(value);
            }
        }
    }
    private async Task Release(int stage)
    {
        try {
            await Task.Delay(stage == 1 ? 1200 : 8000, _stop.Token);
            lock (_gate) {
                if (_stop.IsCancellationRequested || !_queued.Remove(stage, out var values)) return;
                _released.Add(stage);
                foreach (var value in values) {
                    if (_stop.IsCancellationRequested || _connected()) break;
                    _emit(value);
                }
            }
        } catch (OperationCanceledException) { }
    }
    public string SignalSdp(string sdp)
    {
        var lines = sdp.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries);
        var mids = new Dictionary<int, string>(); int media = -1;
        foreach (var line in lines) {
            if (line.StartsWith("m=")) media++;
            if (line.StartsWith("a=mid:")) mids[media] = line[6..];
        }
        media = -1; var output = new List<string>();
        foreach (var line in lines) {
            if (line.StartsWith("m=")) media++;
            if (line.StartsWith("a=candidate:")) Submit(new RTCIceCandidateInit {
                candidate = line[2..], sdpMid = mids.GetValueOrDefault(media, "0"), sdpMLineIndex = (ushort)Math.Max(0, media)
            });
            else if (line != "a=end-of-candidates") output.Add(line);
        }
        return string.Join("\r\n", output) + "\r\n";
    }
    public void Dispose() { lock (_gate) { _stop.Cancel(); _queued.Clear(); } }
}
