import Foundation
import WebRTC

protocol WebRTCSessionDelegate: AnyObject {
    func webRTC(_ session: WebRTCSession, didCreateOffer sdp: String)
    func webRTC(_ session: WebRTCSession, didCreateAnswer sdp: String)
    func webRTC(_ session: WebRTCSession, didGenerate candidate: RTCIceCandidate)
    func webRTC(_ session: WebRTCSession, didChange state: RTCIceConnectionState)
    func webRTC(_ session: WebRTCSession, didReceiveControl data: Data)
    func webRTC(_ session: WebRTCSession, didReceive videoTrack: RTCVideoTrack)
    func webRTC(_ session: WebRTCSession, didOpenControl channel: RTCDataChannel)
    func webRTC(_ session: WebRTCSession, didOpenVideo channel: H265Channel)
    func webRTC(_ session: WebRTCSession, didReceiveVideoFrame frame: Data, key: Bool)
}

extension WebRTCSessionDelegate {
    func webRTC(_ session: WebRTCSession, didOpenControl channel: RTCDataChannel) {}
    func webRTC(_ session: WebRTCSession, didOpenVideo channel: H265Channel) {}
    func webRTC(_ session: WebRTCSession, didReceiveVideoFrame frame: Data, key: Bool) {}
}

/// WebRTC 会话封装。DataChannel label 与官方一致：
/// CONTROL_DATA_CHANNEL / BINARY_DATA_CHANNEL / FILE_DATA_CHANNEL
final class WebRTCSession: NSObject {
    enum Role { case controller, controlled }

    weak var delegate: WebRTCSessionDelegate?
    let role: Role

    private let factory: RTCPeerConnectionFactory
    private(set) var peerConnection: RTCPeerConnection?
    private(set) var controlChannel: RTCDataChannel?
    private(set) var binaryChannel: RTCDataChannel?
    private(set) var fileChannel: RTCDataChannel?
    private(set) var videoSource: RTCVideoSource?
    private(set) var videoTrack: RTCVideoTrack?
    private(set) var h265: H265Channel?
    private var capturer: PixelBufferCapturer?
    private var remoteReady = false
    private var pendingCandidates: [RTCIceCandidate] = []
    private var overlayCandidates: [RTCIceCandidate] = []
    private var overlayEnabled = false
    private var overlayTimer: DispatchWorkItem?
    var onError: ((String) -> Void)?

    private let constraints = RTCMediaConstraints(
        mandatoryConstraints: [
            "OfferToReceiveAudio": "true",
            "OfferToReceiveVideo": "true"
        ],
        optionalConstraints: nil
    )

    init(role: Role, iceServers: [String] = []) {
        self.role = role
        _ = RTCInitializeSSL()
        let encoder = RTCDefaultVideoEncoderFactory()
        let decoder = RTCDefaultVideoDecoderFactory()
        self.factory = RTCPeerConnectionFactory(encoderFactory: encoder, decoderFactory: decoder)
        super.init()
        setup(iceServers: iceServers)
    }

    deinit {
        peerConnection?.close()
        _ = RTCCleanupSSL()
    }

    private func setup(iceServers: [String]) {
        let config = RTCConfiguration()
        config.sdpSemantics = .unifiedPlan
        config.continualGatheringPolicy = .gatherContinually
        if !iceServers.isEmpty {
            config.iceServers = [RTCIceServer(urlStrings: iceServers)]
        }
        peerConnection = factory.peerConnection(with: config, constraints: constraints, delegate: self)
    }

    // MARK: - 控制端

    func startAsController() {
        guard let pc = peerConnection else { return }
        let cfg = RTCDataChannelConfiguration()
        cfg.isOrdered = true
        controlChannel = pc.dataChannel(forLabel: "CONTROL_DATA_CHANNEL", configuration: cfg)
        controlChannel?.delegate = self

        for label in ["BINARY_DATA_CHANNEL", "FILE_DATA_CHANNEL"] {
            let channel = pc.dataChannel(forLabel: label, configuration: cfg)
            channel?.delegate = self
            if label == "BINARY_DATA_CHANNEL" { binaryChannel = channel } else { fileChannel = channel }
        }
        // Native RTP video, negotiated by both endpoints; no invented HEVC
        // DataChannel packetization in the independent connection path.

        pc.offer(for: constraints) { [weak self] sdp, error in
            guard let self else { return }
            guard let sdp else { self.onError?(error?.localizedDescription ?? "SDP offer failed"); return }
            pc.setLocalDescription(sdp) { error in
                if let error { self.onError?(error.localizedDescription); return }
                self.delegate?.webRTC(self, didCreateOffer: sdp.sdp)
            }
        }
    }

    // MARK: - 被控端

    func prepareLocalVideo() -> RTCVideoSource {
        if let source = videoSource { return source }
        let source = factory.videoSource()
        let track = factory.videoTrack(with: source, trackId: "video0")
        capturer = PixelBufferCapturer(delegate: source)
        videoSource = source
        videoTrack = track
        return source
    }

    func handleOffer(_ sdp: String) {
        guard let pc = peerConnection else { return }
        let desc = RTCSessionDescription(type: .offer, sdp: sdp)
        pc.setRemoteDescription(desc) { [weak self] error in
            guard let self else { return }
            if let error { self.onError?(error.localizedDescription); return }
            self.setRemoteReady()
            if self.role == .controlled {
                _ = self.prepareLocalVideo()
                if let track = self.videoTrack {
                    _ = pc.add(track, streamIds: ["stream0"])
                }
            }
            pc.answer(for: self.constraints) { answer, _ in
                guard let answer else { return }
                pc.setLocalDescription(answer) { _ in
                    self.delegate?.webRTC(self, didCreateAnswer: answer.sdp)
                }
            }
        }
    }

    func handleAnswer(_ sdp: String) {
        guard let pc = peerConnection else { return }
        pc.setRemoteDescription(RTCSessionDescription(type: .answer, sdp: sdp)) { [weak self] error in
            if let error { self?.onError?(error.localizedDescription); return }
            self?.setRemoteReady()
        }
    }

    func handleCandidate(_ sdp: String, sdpMLineIndex: Int32, sdpMid: String?) {
        let candidate = RTCIceCandidate(sdp: sdp, sdpMLineIndex: sdpMLineIndex, sdpMid: sdpMid)
        if remoteReady { peerConnection?.add(candidate) } else { pendingCandidates.append(candidate) }
    }

    private func setRemoteReady() {
        remoteReady = true
        pendingCandidates.forEach { peerConnection?.add($0) }
        pendingCandidates.removeAll()
    }

    func close() {
        overlayTimer?.cancel()
        overlayTimer = nil
        delegate = nil
        peerConnection?.close()
        peerConnection = nil
        pendingCandidates.removeAll()
        overlayCandidates.removeAll()
    }

    // MARK: - 数据

    private func attachVideo(channel: RTCDataChannel) {
        let h265 = H265Channel(channel: channel)
        h265.onFrame = { [weak self] frame, key in
            guard let self else { return }
            self.delegate?.webRTC(self, didReceiveVideoFrame: frame, key: key)
        }
        self.h265 = h265
        delegate?.webRTC(self, didOpenVideo: h265)
    }

    func sendVideo(_ annex: Data, key: Bool) {
        h265?.send(annex: annex, key: key)
    }

    func sendControl(_ data: Data) {
        let buffer = RTCDataBuffer(data: data, isBinary: true)
        _ = controlChannel?.sendData(buffer)
    }

    func push(pixelBuffer: CVPixelBuffer, timeNs: Int64) {
        capturer?.push(pixelBuffer, timeNs: timeNs)
    }
}

extension WebRTCSession: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        if let track = stream.videoTracks.first {
            delegate?.webRTC(self, didReceive: track)
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}

    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        delegate?.webRTC(self, didChange: newState)
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if PeerNetwork.isOverlay(candidate.sdp) && !self.overlayEnabled {
                self.overlayCandidates.append(candidate)
                if self.overlayTimer == nil {
                    let timer = DispatchWorkItem { [weak self] in
                        guard let self, let pc = self.peerConnection else { return }
                        if pc.iceConnectionState == .connected || pc.iceConnectionState == .completed { return }
                        self.overlayEnabled = true
                        self.overlayCandidates.forEach { self.delegate?.webRTC(self, didGenerate: $0) }
                        self.overlayCandidates.removeAll()
                    }
                    self.overlayTimer = timer
                    DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: timer)
                }
            } else { self.delegate?.webRTC(self, didGenerate: candidate) }
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        dataChannel.delegate = self
        switch dataChannel.label {
        case "CONTROL_DATA_CHANNEL": controlChannel = dataChannel
        case "BINARY_DATA_CHANNEL": binaryChannel = dataChannel
        case "FILE_DATA_CHANNEL": fileChannel = dataChannel
        case H265Channel.label: attachVideo(channel: dataChannel)
        default: break
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams mediaStreams: [RTCMediaStream]) {
        if let track = rtpReceiver.track as? RTCVideoTrack {
            delegate?.webRTC(self, didReceive: track)
        }
    }
}

extension WebRTCSession: RTCDataChannelDelegate {
    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        if dataChannel.label == "CONTROL_DATA_CHANNEL", dataChannel.readyState == .open {
            delegate?.webRTC(self, didOpenControl: dataChannel)
        }
    }

    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        if dataChannel.label == "CONTROL_DATA_CHANNEL" {
            delegate?.webRTC(self, didReceiveControl: buffer.data)
        } else if dataChannel.label == H265Channel.label {
            h265?.receive(buffer.data)
        }
    }
}

/// 把 CVPixelBuffer 推给 WebRTC 编码器
final class PixelBufferCapturer: RTCVideoCapturer {
    func push(_ buffer: CVPixelBuffer, timeNs: Int64) {
        let frame = RTCVideoFrame(buffer: RTCCVPixelBuffer(pixelBuffer: buffer),
                                  rotation: ._0,
                                  timeStampNs: timeNs)
        delegate?.capturer(self, didCapture: frame)
    }
}
