using System;
using System.Collections.Generic;
using System.Text;
using System.Threading.Tasks;
using SIPSorcery.Net;

namespace UURemoteClone;

/// <summary>
/// Windows 端 WebRTC 会话（与 macOS/Android 同协议）：
/// 三个官方同名 DataChannel：CONTROL_DATA_CHANNEL / BINARY_DATA_CHANNEL / FILE_DATA_CHANNEL。
/// 使用 SIPSorcery 纯 C# WebRTC，无需 native 库，协议为标准 RTCPeerConnection + SCTP。
/// </summary>
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
    private readonly RTCConfiguration _config;
    private RTCPeerConnection? _peer;
    private RTCDataChannel? _control;
    private RTCDataChannel? _binary;
    private RTCDataChannel? _file;

    public StreamerSession(IListener listener, IEnumerable<string>? iceServers = null)
    {
        _listener = listener;
        var servers = new List<RTCIceServer>();
        if (iceServers != null)
        {
            foreach (var url in iceServers)
                servers.Add(new RTCIceServer { urls = url });
        }
        if (servers.Count == 0)
            servers.Add(new RTCIceServer { urls = "stun:stun.l.google.com:19302" });
        _config = new RTCConfiguration { iceServers = servers };
    }

    /// <summary>控制端：建 DataChannel 并发 Offer</summary>
    public async Task StartAsControllerAsync()
    {
        var pc = new RTCPeerConnection(_config);
        _peer = pc;

        pc.onicecandidate += candidate =>
        {
            if (candidate != null)
            {
                _listener.OnCandidate(new RTCIceCandidateInit
                {
                    candidate = candidate.candidate,
                    sdpMid = candidate.sdpMid,
                    sdpMLineIndex = candidate.sdpMLineIndex
                });
            }
        };

        pc.onconnectionstatechange += state => _listener.OnState(state);

        pc.ondatachannel += channel => Bind(channel);

        // 官方同名通道：控制可靠有序；二进制/文件可靠
        _control = await pc.createDataChannel(ControlLabel,
            new RTCDataChannelInit { ordered = true });
        _binary = await pc.createDataChannel(BinaryLabel,
            new RTCDataChannelInit { ordered = true });
        _file = await pc.createDataChannel(FileLabel,
            new RTCDataChannelInit { ordered = true });
        Bind(_control);
        Bind(_binary);
        Bind(_file);

        var offer = pc.createOffer();
        await pc.setLocalDescription(offer);
        _listener.OnOffer(offer.sdp);
    }

    private void Bind(RTCDataChannel channel)
    {
        channel.onopen += () => { };
        channel.onclose += () => { };
        channel.onmessage += (dc, protocol, data) =>
        {
            if (dc.label == ControlLabel && data != null && data.Length > 0)
                _listener.OnControl(data);
        };

        if (channel.label == ControlLabel) _control = channel;
        else if (channel.label == BinaryLabel) _binary = channel;
        else if (channel.label == FileLabel) _file = channel;
    }

    /// <summary>被控端：收到 Offer 后应答</summary>
    public async Task<string> HandleOfferAsync(string sdp)
    {
        var pc = _peer ?? new RTCPeerConnection(_config);
        _peer = pc;
        pc.ondatachannel += Bind;

        if (RTCSessionDescriptionInit.TryParse(sdp, out var offer))
            pc.setRemoteDescription(offer);

        var answer = pc.createAnswer();
        await pc.setLocalDescription(answer);
        return answer.sdp;
    }

    public void HandleAnswer(string sdp)
    {
        if (_peer == null) return;
        if (RTCSessionDescriptionInit.TryParse(sdp, out var answer))
            _peer.setRemoteDescription(answer);
    }

    public void AddCandidate(string candidate, string sdpMid, int sdpMLineIndex)
    {
        if (_peer == null) return;
        var init = new RTCIceCandidateInit
        {
            candidate = candidate,
            sdpMid = sdpMid,
            sdpMLineIndex = (ushort)Math.Max(0, sdpMLineIndex)
        };
        _peer.addIceCandidate(init);
    }

    public void SendControl(byte[] data)
    {
        if (_control != null && _control.readyState == RTCDataChannelState.open)
            _control.send(data);
    }

    public void SendBinary(byte[] data)
    {
        if (_binary != null && _binary.readyState == RTCDataChannelState.open)
            _binary.send(data);
    }

    public void SendFile(byte[] data)
    {
        if (_file != null && _file.readyState == RTCDataChannelState.open)
            _file.send(data);
    }

    public void Dispose()
    {
        _control?.close();
        _binary?.close();
        _file?.close();
        _peer?.close();
        _peer = null;
    }
}
