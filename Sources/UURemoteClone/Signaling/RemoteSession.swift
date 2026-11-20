import Foundation
import AppKit
import Combine
import CoreMedia
import WebRTC

/// 一次远控会话：房间 → 信令 → WebRTC → 控制通道
final class RemoteSession: NSObject, ObservableObject {
    enum Phase: Equatable {
        case idle, creatingRoom, signaling, connecting, connected, failed(String)
        var text: String {
            switch self {
            case .idle: return "未连接"
            case .creatingRoom: return "正在创建房间…"
            case .signaling: return "正在建立信令…"
            case .connecting: return "正在连接被控端…"
            case .connected: return "已连接"
            case .failed(let m): return m
            }
        }
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var videoTrack: RTCVideoTrack?
    @Published private(set) var device: DeviceInfo?
    @Published private(set) var screenInfo: [GvScreenInfo] = []

    private var mailbox: PeerMailbox?
    private var connectTask: Task<Void, Never>?
    private var rtc: WebRTCSession?
    private var seq: Int64 = 0
    private var controlReady = false
    private var queued: [Data] = []
    private var reliable: ReliableChannel?
    private var reliableTimer: Timer?
    private let decoder = H265Decoder()
    let clipboard = ClipboardManager()
    private var clipboardTimer: Timer?

    /// 弱网增强（KCP + RS-FEC）；对端不支持时自动降级为裸 protobuf
    var useReliableTransport = false

    func connect(device: DeviceInfo) { phase = .failed("请使用对端生成的配对码添加设备") }

    func connect(peer: PeerInvitation, device: DeviceInfo) {
        self.device = device
        phase = .signaling
        connectTask = Task { @MainActor in
            do {
                let api = try PeerAPI(peer.server)
                let result = try await api.request("/v1/connect", body: [
                    "target": peer.id, "key": peer.key,
                    "name": Host.current().localizedName ?? ProcessInfo.processInfo.hostName, "platform": "mac"
                ])
                guard !Task.isCancelled, let id = result["id"] as? String, let token = result["token"] as? String else { return }
                let box = PeerMailbox(api: api, id: id, token: token)
                self.mailbox = box
                box.onSignal = { [weak self] signal in
                    guard let self else { return }
                    switch signal.type {
                    case "accepted":
                        let rtc = WebRTCSession(role: .controller, iceServers: PeerNetwork.stun)
                        rtc.delegate = self
                        rtc.onError = { [weak self] error in DispatchQueue.main.async { self?.phase = .failed(error) } }
                        self.rtc = rtc
                        self.phase = .connecting
                        rtc.startAsController()
                    case "answer": if let sdp = signal.data["sdp"] as? String { self.rtc?.handleAnswer(sdp) }
                    case "candidate":
                        if let sdp = signal.data["candidate"] as? String {
                            self.rtc?.handleCandidate(sdp, sdpMLineIndex: Int32(signal.data["sdpMLineIndex"] as? Int ?? 0), sdpMid: signal.data["sdpMid"] as? String)
                        }
                    case "close": self.disconnect(); self.phase = .failed("对端已拒绝或断开连接")
                    default: break
                    }
                }
                box.onError = { [weak self] error in self?.phase = .failed(error) }
                box.start()
            } catch { self.phase = .failed(error.localizedDescription) }
        }
    }

    func disconnect() {
        connectTask?.cancel()
        let box = mailbox
        Task { @MainActor in
            box?.send("close")
            try? await Task.sleep(nanoseconds: 500_000_000)
            box?.stop()
        }
        mailbox = nil
        rtc?.close()
        rtc = nil
        reliableTimer?.invalidate()
        reliableTimer = nil
        reliable = nil
        controlReady = false
        queued.removeAll()
        phase = .idle
        videoTrack = nil
    }

    // MARK: - 控制消息

    override init() {
        super.init()
        // The experimental wrapper has no observed official negotiation contract.
        // It must be explicitly enabled by a caller that controls both endpoints.
        useReliableTransport = false
        clipboardTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, self.controlReady else { return }
            var seq = self.seq
            if let data = self.clipboard.pollAndEncode(seq: &seq) {
                self.seq = seq
                if let reliable = self.reliable { reliable.send(data) }
                else { self.rtc?.sendControl(data) }
            }
        }
        decoder.onImage = { buffer, pts in
            VideoFrameBus.shared.push(buffer, pts: pts)
        }
    }

    func send(_ message: GvMessage) {
        let data = message.encode()
        guard controlReady, let rtc else { queued.append(data); return }
        if let reliable { reliable.send(data) } else { rtc.sendControl(data) }
    }

    func sendConnectOptions(capture: GvCaptureParams) {
        var options = GvConnectOptions()
        options.captureParams = capture
        options.deviceID = device?.deviceID ?? ""
        options.clientType = .mac
        options.decoderCaps = [
            GvDecoderCap(fps: 60, codecType: .h264, width: 3840, height: 2160, chroma: .f420),
            GvDecoderCap(fps: 60, codecType: .h264, width: 2560, height: 1600, chroma: .f444)
        ]
        let data = options.encode()
        if controlReady {
            if let reliable { reliable.send(data) } else { rtc?.sendControl(data) }
        } else {
            queued.append(data)
        }
    }

    private func flushQueue() {
        guard let rtc else { return }
        queued.forEach { data in
            if let reliable { reliable.send(data) } else { rtc.sendControl(data) }
        }
        queued.removeAll()
    }

    func sendCaptureSetting(_ request: GvCaptureSettingRequest) {
        seq += 1
        send(GvMessage(seq: seq, timestamp: Int64(Date().timeIntervalSince1970 * 1000),
                       payloadField: .captureConfig, payload: request.encode()))
    }

    func send(touch: GvTouchEvent) {
        var input = ProtoWriter()
        input.message(touch.encode(), field: 1)
        seq += 1
        send(GvMessage(seq: seq, timestamp: Int64(Date().timeIntervalSince1970 * 1000),
                       payloadField: .inputEvent, payload: input.data))
    }
}

extension RemoteSession: WebRTCSessionDelegate {
    func webRTC(_ session: WebRTCSession, didCreateOffer sdp: String) {
        Task { @MainActor in mailbox?.send("offer", ["sdp": sdp]) }
    }

    func webRTC(_ session: WebRTCSession, didCreateAnswer sdp: String) { }

    func webRTC(_ session: WebRTCSession, didGenerate candidate: RTCIceCandidate) {
        Task { @MainActor in mailbox?.send("candidate", [
            "candidate": candidate.sdp,
            "sdpMid": candidate.sdpMid ?? "",
            "sdpMLineIndex": Int(candidate.sdpMLineIndex)
        ]) }
    }

    func webRTC(_ session: WebRTCSession, didChange state: RTCIceConnectionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected, .completed: self.phase = .connected
            case .failed: self.phase = .failed("连接失败")
            case .disconnected: self.phase = .connecting
            default: break
            }
        }
    }

    func webRTC(_ session: WebRTCSession, didReceiveControl data: Data) {
        if let reliable {
            if data.first == 0xF2 {
                reliable.receive(data)
                return
            }
            // 对端未启用 FEC，降级
            self.reliable = nil
            reliableTimer?.invalidate()
            reliableTimer = nil
        }
        guard let message = GvMessage.decode(data) else { return }
        DispatchQueue.main.async { self.handleControl(message) }
    }

    func webRTC(_ session: WebRTCSession, didReceiveVideoFrame frame: Data, key: Bool) {
        let pts = CMTime(value: Int64(Date().timeIntervalSince1970 * 1000), timescale: 1000)
        decoder.decode(annex: frame, pts: pts)
    }

    func webRTC(_ session: WebRTCSession, didOpenVideo channel: H265Channel) {
        var request = GvCaptureSettingRequest()
        request.codec = .h265
        request.frameQuality = .hd
        sendCaptureSetting(request)
    }

    func webRTC(_ session: WebRTCSession, didReceive videoTrack: RTCVideoTrack) {
        DispatchQueue.main.async { self.videoTrack = videoTrack }
    }

    func webRTC(_ session: WebRTCSession, didOpenControl channel: RTCDataChannel) {
        DispatchQueue.main.async {
            if self.useReliableTransport {
                let reliable = ReliableChannel(channel: channel)
                reliable.onMessage = { [weak self] data in
                    guard let self, let message = GvMessage.decode(data) else { return }
                    DispatchQueue.main.async { self.handleControl(message) }
                }
                self.reliable = reliable
                self.reliableTimer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { _ in
                    reliable.tick()
                }
            }
            self.controlReady = true
            self.flushQueue()
        }
    }

    private func handleControl(_ message: GvMessage) {
        switch message.payloadKind {
        case .screens:
            var reader = ProtoReader(message.payload)
            var screens: [GvScreenInfo] = []
            while let (field, wire) = try? reader.nextField() {
                if field == 1, let d = try? reader.readBytes(), let s = GvScreenInfo.decode(d) {
                    screens.append(s)
                } else {
                    try? reader.skip(wire)
                }
            }
            screenInfo = screens
        case .clipboardChange:
            let text = ClipboardManager.decodeAndApply(message.payload) { pasteText in
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(pasteText, forType: .string)
            }
            if let t = text { clipboard.markReceived(t) }
        case .systemStateChange, .captureConfigResponse:
            break
        default:
            break
        }
    }
}
