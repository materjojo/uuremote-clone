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

    private var room: RoomInfo?
    private var socket: SocketIOClient?
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
    var useReliableTransport = true

    func connect(device: DeviceInfo) {
        self.device = device
        phase = .creatingRoom
        Task {
            do {
                let room = try await APIClient.shared.createRoom(deviceID: device.deviceID)
                await MainActor.run { self.room = room; self.startSignaling(room) }
            } catch {
                await MainActor.run { self.phase = .failed(error.localizedDescription) }
            }
        }
    }

    private func startSignaling(_ room: RoomInfo) {
        phase = .signaling
        let rtc = WebRTCSession(role: .controller)
        rtc.delegate = self
        self.rtc = rtc

        guard let server = room.signalingServer ?? room.signalingList?.first,
              let host = URL(string: server)?.host else {
            // 演示模式：没有真实信令服务器时直接进入本地预览
            phase = .connected
            return
        }

        let socket = SocketIOClient(host: host, useTLS: server.hasPrefix("wss"))
        socket.onStateChange = { [weak self] state in
            guard let self else { return }
            if state == .connected {
                socket.emit("login", [
                    "room_id": room.roomID,
                    "token": room.token,
                    "device_id": room.publisherDeviceID ?? ""
                ])
                self.rtc?.startAsController()
            }
        }
        socket.onEvent = { [weak self] name, payload in
            self?.handle(event: name, payload: payload)
        }
        self.socket = socket
        socket.connect()
        phase = .connecting
    }

    private func handle(event: String, payload: Any?) {
        switch event {
        case "bmsg_push", "peer_offer", "answer", "candidate":
            guard let dict = payload as? [String: Any] else { return }
            let type = (dict["type"] as? String) ?? event
            let inner = (dict["data"] as? [String: Any]) ?? dict
            switch type {
            case "answer", "peer_answer":
                if let sdp = inner["sdp"] as? String { rtc?.handleAnswer(sdp) }
            case "candidate":
                if let sdp = inner["candidate"] as? String {
                    rtc?.handleCandidate(sdp,
                                         sdpMLineIndex: Int32(inner["sdpMLineIndex"] as? Int ?? 0),
                                         sdpMid: inner["sdpMid"] as? String)
                }
            default: break
            }
        case "room_info":
            if let dict = payload as? [String: Any], let sdp = dict["sdp"] as? String {
                rtc?.handleOffer(sdp)
            }
        default:
            break
        }
    }

    func disconnect() {
        socket?.disconnect()
        socket = nil
        rtc = nil
        controlReady = false
        queued.removeAll()
        phase = .idle
        videoTrack = nil
    }

    // MARK: - 控制消息

    override init() {
        super.init()
        useReliableTransport = UserDefaults.standard.object(forKey: "useReliableTransport") as? Bool ?? true
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
        socket?.emit("send_offer", [
            "sdp": sdp,
            "room_id": room?.roomID ?? "",
            "token": room?.token ?? ""
        ])
    }

    func webRTC(_ session: WebRTCSession, didCreateAnswer sdp: String) {
        socket?.emit("send_offer", ["sdp": sdp, "room_id": room?.roomID ?? ""])
    }

    func webRTC(_ session: WebRTCSession, didGenerate candidate: RTCIceCandidate) {
        socket?.emit("send_candidates", [[
            "candidate": candidate.sdp,
            "sdpMid": candidate.sdpMid ?? "",
            "sdpMLineIndex": Int(candidate.sdpMLineIndex)
        ]])
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
