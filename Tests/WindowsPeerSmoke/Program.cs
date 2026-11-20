using System;
using System.Text;
using System.Threading.Tasks;
using SIPSorcery.Net;
using UURemoteClone;

static class Program
{
    static async Task Main(string[] args)
    {
        foreach (var platform in new[] { "mac", "windows", "android" }) {
            var peer = new PeerInvitation(1, "https://signal.example.org", "peer-00000000000001",
                new string('a', 64), "自定义设备", platform);
            if (PeerInvitation.Parse(peer.Code) != peer) throw new Exception("Invitation roundtrip failed");
            var stored = System.Text.Json.JsonSerializer.Serialize(peer, PeerInvitation.Json);
            if (stored.Contains("\"code\"")) throw new Exception("Calculated code must be omitted from invitation JSON");
        }
        var staged = new TaskCompletionSource<RTCIceCandidateInit>(TaskCreationOptions.RunContinuationsAsynchronously);
        int early = 0;
        using (var gate = new PeerCandidateGate(c => {
            if (c.candidate.Contains("192.168.")) staged.TrySetResult(c);
            else if (StreamerSession.IsOverlay(c.candidate)) throw new Exception("Overlay released before grace");
            else System.Threading.Interlocked.Increment(ref early);
        }, () => false)) {
            var filtered = gate.SignalSdp("v=0\r\nm=application 9 UDP/DTLS/SCTP webrtc-datachannel\r\na=mid:control\r\na=candidate:1 1 udp 1 2001:db8::1 9 typ host\r\nm=video 9 UDP/TLS/RTP/SAVPF 96\r\na=mid:screen\r\na=candidate:2 1 udp 1 192.168.1.2 9 typ host\r\na=candidate:3 1 udp 1 100.64.0.2 9 typ host\r\na=end-of-candidates\r\n");
            if (filtered.Contains("a=candidate:") || filtered.Contains("a=end-of-candidates") || early != 1 || staged.Task.IsCompleted)
                throw new Exception("SDP bypassed candidate staging");
            var value = await staged.Task.WaitAsync(TimeSpan.FromSeconds(3));
            if (value.sdpMid != "screen" || value.sdpMLineIndex != 1) throw new Exception("Candidate media identity lost");
        }
        await CheckOverlayLifecycle();
        var hostEvents = new Listener();
        var controllerEvents = new Listener();
        using var host = new StreamerSession(hostEvents, true);
        using var controller = new StreamerSession(controllerEvents);
        var offer = new TaskCompletionSource<string>(TaskCreationOptions.RunContinuationsAsynchronously);
        var connected = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var echo = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var decoded = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        hostEvents.Candidate = c => controller.AddCandidate(c.candidate, c.sdpMid, c.sdpMLineIndex);
        controllerEvents.Candidate = c => host.AddCandidate(c.candidate, c.sdpMid, c.sdpMLineIndex);
        controllerEvents.Offer = sdp => offer.TrySetResult(sdp);
        controllerEvents.State = state => { if (state == RTCPeerConnectionState.connected) connected.TrySetResult(); };
        hostEvents.Control = bytes => { if (Encoding.UTF8.GetString(bytes) == "input") host.SendControl(Encoding.UTF8.GetBytes("ack")); };
        controllerEvents.Control = bytes => { if (Encoding.UTF8.GetString(bytes) == "ack") echo.TrySetResult(); };
        using var encoder = new WindowsVideoPipeline(false, args[0]);
        using var decoder = new WindowsVideoPipeline(false, args[0]);
        controller.VideoFrame += decoder.DecodeH264;
        decoder.FrameDecoded += (bytes, w, h) => {
            if (w == 64 && h == 64 && bytes.Length == 64 * 64 * 4 &&
                Math.Abs(bytes[0] - 40) < 12 && Math.Abs(bytes[1] - 120) < 12 && Math.Abs(bytes[2] - 200) < 12 && bytes[3] == 255)
                decoded.TrySetResult();
        };
        encoder.FrameEncoded += host.SendVideo;
        await controller.StartAsControllerAsync();
        var answer = await host.HandleOfferAsync(await offer.Task.WaitAsync(TimeSpan.FromSeconds(10)));
        controller.HandleAnswer(answer);
        await connected.Task.WaitAsync(TimeSpan.FromSeconds(20));
        for (var i = 0; i < 30 && !echo.Task.IsCompleted; i++) {
            controller.SendControl(Encoding.UTF8.GetBytes("input"));
            await Task.Delay(100);
        }
        await echo.Task.WaitAsync(TimeSpan.FromSeconds(5));
        var frame = new byte[64 * 64 * 4];
        for (int i = 0; i < frame.Length; i += 4) { frame[i] = 40; frame[i + 1] = 120; frame[i + 2] = 200; frame[i + 3] = 255; }
        for (var i = 0; i < 90 && !decoded.Task.IsCompleted; i++) {
            encoder.EncodeBgra(frame, 64, 64, forceKey: i % 15 == 0);
            await Task.Delay(34);
        }
        await decoded.Task.WaitAsync(TimeSpan.FromSeconds(10));
        Console.WriteLine("PASS independent Windows peer: real ICE/DTLS, bidirectional SCTP control, H264 encode/RTP/decode, pairing for all three platforms.");
        Console.WriteLine("Synthetic video on one runner; not physical screen, hardware or UI parity validation.");
    }
    static async Task CheckOverlayLifecycle()
    {
        var watch = System.Diagnostics.Stopwatch.StartNew();
        var released = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var stopped = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var sent = new int[4];
        int connected = 0;
        string? error = null;
        using var fallback = new PeerCandidateGate(c => {
            if (watch.ElapsedMilliseconds < 7800) error = "Overlay emitted before 8 second grace";
            if (System.Threading.Interlocked.Increment(ref sent[0]) == 2) released.TrySetResult();
        }, () => System.Threading.Volatile.Read(ref connected) != 0);
        using var closed = new PeerCandidateGate(c => System.Threading.Interlocked.Increment(ref sent[2]), () => false);
        PeerCandidateGate? closedDuringSend = null;
        using var closing = new PeerCandidateGate(c => {
            System.Threading.Interlocked.Increment(ref sent[3]); closedDuringSend!.Dispose(); stopped.TrySetResult();
        }, () => false);
        closedDuringSend = closing;
        // The connected gate transitions to connected after candidates were queued.
        int onlyConnectedGate = 0;
        using var suppressed = new PeerCandidateGate(c => System.Threading.Interlocked.Increment(ref sent[1]),
            () => System.Threading.Volatile.Read(ref onlyConnectedGate) != 0);
        var gates = new[] { fallback, suppressed, closed, closing };
        foreach (var gate in gates) {
            foreach (string ip in new[] { "100.64.0.2", "fd7a:115c:a1e0::2" }) {
                var candidate = new RTCIceCandidateInit { candidate = $"candidate:1 1 udp 1 {ip} 9 typ host", sdpMid = "control", sdpMLineIndex = 0 };
                gate.Submit(candidate); gate.Submit(candidate);
            }
        }
        System.Threading.Volatile.Write(ref onlyConnectedGate, 1);
        closed.Dispose();
        if (sent[0] != 0) throw new Exception("Overlay did not wait for grace");
        await Task.WhenAll(released.Task, stopped.Task).WaitAsync(TimeSpan.FromSeconds(11));
        await Task.Delay(100);
        System.Threading.Volatile.Write(ref connected, 1);
        foreach (var gate in gates) gate.Submit(new RTCIceCandidateInit {
            candidate = "candidate:late 1 udp 1 100.64.0.3 9 typ host", sdpMid = "control", sdpMLineIndex = 0
        });
        if (error != null || sent[0] != 2 || sent[1] != 0 || sent[2] != 0 || sent[3] != 1)
            throw new Exception(error ?? $"Candidate lifecycle leaked: {string.Join(',', sent)}");
        Console.WriteLine("PASS candidate grace: overlay fallback waits 8 seconds; deduplication, connected suppression and close during release.");
    }

    sealed class Listener : StreamerSession.IListener
    {
        public Action<string>? Offer;
        public Action<RTCIceCandidateInit>? Candidate;
        public Action<byte[]>? Control;
        public Action<RTCPeerConnectionState>? State;
        public void OnOffer(string sdp) => Offer?.Invoke(sdp);
        public void OnCandidate(RTCIceCandidateInit value) => Candidate?.Invoke(value);
        public void OnControl(byte[] bytes) => Control?.Invoke(bytes);
        public void OnState(RTCPeerConnectionState state) => State?.Invoke(state);
    }
}
