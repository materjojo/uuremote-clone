using System;
using System.Collections.Generic;
using System.Linq;
using System.Net;
using System.Threading;
using System.Threading.Tasks;
using SIPSorcery.Net;
using SIPSorceryMedia.Abstractions;

namespace UURemoteClone;

/// <summary>Independent WebRTC transport. Does not claim the proprietary media ABI.</summary>
public sealed class StreamerSession : IDisposable
{
    public const string ControlLabel = "CONTROL_DATA_CHANNEL";
    public const string BinaryLabel = "BINARY_DATA_CHANNEL";
    public const string FileLabel = "FILE_DATA_CHANNEL";
    public interface IListener
    {
        void OnOffer(string sdp);
        void OnCandidate(RTCIceCandidateInit candidate);
        void OnControl(byte[] data);
        void OnState(RTCPeerConnectionState state);
    }
    private readonly IListener _listener;
    private readonly RTCPeerConnection _peer;
    private readonly object _gate = new();
    private readonly List<RTCIceCandidateInit> _pending = new(), _overlay = new();
    private readonly CancellationTokenSource _stop = new();
    private bool _remoteReady, _overlayReleased, _overlayScheduled;
    private RTCDataChannel? _control, _binary, _file;
    public event Action<byte[]>? VideoFrame;
    public event Action<string>? Error;

    public StreamerSession(IListener listener, bool host = false)
    {
        _listener = listener;
        _peer = new RTCPeerConnection(new RTCConfiguration {
            iceServers = new List<RTCIceServer> {
                new() { urls = "stun:stun.cloudflare.com:3478" },
                new() { urls = "stun:stun.l.google.com:19302" }
            },
            X_ICEIncludeAllInterfaceAddresses = true,
            X_UseRtpFeedbackProfile = true
        });
        var formats = new List<VideoFormat> {
            new(VideoCodecsEnum.H264, 96, 90000, "level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=42e01f")
        };
        _peer.addTrack(new MediaStreamTrack(formats, host ? MediaStreamStatusEnum.SendOnly : MediaStreamStatusEnum.RecvOnly));
        _peer.OnVideoFrameReceived += (ep, ts, frame, format) => VideoFrame?.Invoke(frame);
        _peer.onicecandidate += candidate => {
            if (candidate == null) return;
            var value = new RTCIceCandidateInit { candidate = candidate.candidate,
                sdpMid = candidate.sdpMid, sdpMLineIndex = candidate.sdpMLineIndex };
            bool hold;
            lock (_gate) {
                hold = IsOverlay(value.candidate) && !_overlayReleased;
                if (hold) _overlay.Add(value);
                if (!_overlayScheduled) { _overlayScheduled = true; _ = ReleaseOverlay(); }
            }
            if (!hold) _listener.OnCandidate(value);
        };
        _peer.onconnectionstatechange += state => _listener.OnState(state);
        _peer.ondatachannel += Bind;
    }

    internal static bool IsOverlay(string candidate)
    {
        var fields = candidate.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        if (fields.Length < 5 || !IPAddress.TryParse(fields[4], out var ip)) return false;
        var bytes = ip.GetAddressBytes();
        return bytes.Length == 4 ? bytes[0] == 100 && bytes[1] >= 64 && bytes[1] <= 127
            : ip.ToString().StartsWith("fd7a:115c:a1e0:", StringComparison.OrdinalIgnoreCase);
    }
    private async Task ReleaseOverlay()
    {
        try {
            await Task.Delay(8000, _stop.Token);
            lock (_gate) {
                _overlayReleased = true;
                foreach (var candidate in _overlay) _listener.OnCandidate(candidate);
                _overlay.Clear();
            }
        } catch (OperationCanceledException) { }
    }

    public async Task StartAsControllerAsync()
    {
        foreach (var label in new[] { ControlLabel, BinaryLabel, FileLabel })
            Bind(await _peer.createDataChannel(label, new RTCDataChannelInit { ordered = true }));
        var offer = _peer.createOffer();
        await _peer.setLocalDescription(offer);
        _listener.OnOffer(offer.sdp);
    }

    private void Bind(RTCDataChannel channel)
    {
        channel.onmessage += (dc, protocol, data) => {
            if (dc.label == ControlLabel && data.Length > 0) _listener.OnControl(data);
        };
        if (channel.label == ControlLabel) _control = channel;
        else if (channel.label == BinaryLabel) _binary = channel;
        else if (channel.label == FileLabel) _file = channel;
    }

    private void SetRemote(SdpType type, string sdp)
    {
        var result = _peer.setRemoteDescription(new RTCSessionDescriptionInit { type = type, sdp = sdp });
        if (result != SetDescriptionResultEnum.OK) throw new InvalidOperationException("SDP: " + result);
        lock (_gate) {
            _remoteReady = true;
            foreach (var candidate in _pending) _peer.addIceCandidate(candidate);
            _pending.Clear();
        }
    }
    public async Task<string> HandleOfferAsync(string sdp)
    {
        SetRemote(SdpType.offer, sdp);
        var answer = _peer.createAnswer();
        await _peer.setLocalDescription(answer);
        return answer.sdp;
    }
    public void HandleAnswer(string sdp) => SetRemote(SdpType.answer, sdp);
    public void AddCandidate(string candidate, string sdpMid, int sdpMLineIndex)
    {
        var value = new RTCIceCandidateInit { candidate = candidate, sdpMid = sdpMid,
            sdpMLineIndex = (ushort)Math.Max(0, sdpMLineIndex) };
        lock (_gate) { if (_remoteReady) _peer.addIceCandidate(value); else _pending.Add(value); }
    }
    public void SendVideo(byte[] frame) {
        if (_peer.connectionState == RTCPeerConnectionState.connected) _peer.SendVideo(3000, frame);
    }
    public void SendControl(byte[] data) { if (_control?.readyState == RTCDataChannelState.open) _control.send(data); }
    public void SendBinary(byte[] data) { if (_binary?.readyState == RTCDataChannelState.open) _binary.send(data); }
    public void SendFile(byte[] data) { if (_file?.readyState == RTCDataChannelState.open) _file.send(data); }
    public void Dispose()
    {
        _stop.Cancel();
        _control?.close(); _binary?.close(); _file?.close();
        _peer.close();
    }
}
