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
