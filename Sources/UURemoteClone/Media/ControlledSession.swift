import Foundation
import AppKit
import Combine
import CoreMedia
import ScreenCaptureKit
import WebRTC

/// 被控端：采集 → H.265/WebRTC → 注入
final class ControlledSession: NSObject, ObservableObject {
    @Published private(set) var running = false
    @Published private(set) var lastError: String?
    @Published private(set) var virtualDisplayActive = false
    @Published private(set) var hardwareEncode = false

    var codec: GvCodecType = .h265
    var fps: Int = 60
    var bitrate: Int = 6_000_000

    /// 信令回调（answer / candidate）
    var onSignal: ((String, Any) -> Void)?

    private var rtc: WebRTCSession?
    private let capturer = ScreenCapturer()
    private let cgCapturer = CGDisplayStreamCapturer()
    private let encoder = H265Encoder()
    private let injector = InputInjector()
    private let virtualDisplay = VirtualDisplayController()
    private var screenSize: CGSize = .zero
    private let clipboard = ClipboardManager()
    private var clipboardTimer: Timer?
    private var controlReady = false
    private var seq: Int64 = 0
    private var pendingFrames: [(Data, Bool)] = []

    deinit { encoder.invalidate() }

    // MARK: - 启动

    func start(display: SCDisplay, fps: Int = 60) async {
        self.fps = fps
        await start(source: .display(display), privateScreen: .off)
    }

    enum Source {
        case display(SCDisplay)
        case virtual(width: Int, height: Int)
    }

    func start(source: Source, privateScreen: PrivateScreenMode) async {
        do {
            let rtc = WebRTCSession(role: .controlled, iceServers: PeerNetwork.stun)
            rtc.delegate = self
            self.rtc = rtc

            let width: Int
            let height: Int
            let display: SCDisplay?

            switch source {
            case .display(let d):
                display = d
                width = d.width
                height = d.height
            case .virtual(let w, let h):
                guard let id = virtualDisplay.create(width: w, height: h, refresh: Double(fps)) else {
                    throw NSError(domain: "VirtualDisplay", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "无法创建虚拟屏"])
                }
                virtualDisplayActive = true
                _ = id
                if privateScreen == .enhanced {
                    lastError = "增强防窥依赖私有 CGS 接口，已降级为普通虚拟屏"
                }
                display = await virtualDisplay.shareableDisplay()
                width = w
                height = h
            }

            screenSize = CGSize(width: width, height: height)
            injector.updateScreenSize(screenSize)
            encoder.onFrame = { [weak self] annex, key in
                guard let self else { return }
                if let rtc = self.rtc {
                    rtc.sendVideo(annex, key: key)
                } else {
                    self.pendingFrames.append((annex, key))
                    if self.pendingFrames.count > 30 { self.pendingFrames.removeFirst() }
                }
            }
            if codec == .h265 {
                let bitrate = max(1_500_000, min(self.bitrate, width * height * 6))
                _ = encoder.prepare(width: width, height: height, fps: fps, bitrate: bitrate)
                hardwareEncode = encoder.usingHardware
            }
            // Native WebRTC owns its encoder in the RTP path; do not report
            // properties of an unused H.265 encoder as its hardware status.

            if let display {
                var config = ScreenCapturer.Config()
                config.width = width
                config.height = height
                config.fps = fps
                config.capturesAudio = false
                try await capturer.start(display: display, config: config) { [weak self] buffer, time in
                    self?.handle(buffer: buffer, time: time)
                }
            } else if case .virtual = source {
                let ok = cgCapturer.start(displayID: virtualDisplay.displayID,
                                          width: width, height: height, fps: fps) { [weak self] buffer in
                    self?.handle(buffer: buffer, time: CMClockGetTime(CMClockGetHostTimeClock()))
                }
                if !ok { throw NSError(domain: "VirtualDisplay", code: 2,
                                       userInfo: [NSLocalizedDescriptionKey: "虚拟屏采集启动失败"]) }
            }
            await MainActor.run {
                self.clipboardTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                    guard let self, self.controlReady else { return }
                    if let data = self.clipboard.pollAndEncode(seq: &self.seq) { self.rtc?.sendControl(data) }
                }
            }
            running = true
        } catch {
            await stop()
            lastError = error.localizedDescription
            running = false
        }
    }

    private func handle(buffer: CVPixelBuffer, time: CMTime) {
        if codec == .h265 {
            encoder.encode(buffer, pts: time)
        } else {
            let ns = Int64(CMTimeGetSeconds(time) * 1_000_000_000)
            rtc?.push(pixelBuffer: buffer, timeNs: ns)
        }
    }

    func stop() async {
        await MainActor.run { self.clipboardTimer?.invalidate(); self.clipboardTimer = nil; self.controlReady = false }
        await capturer.stop()
        cgCapturer.stop()
        encoder.invalidate()
        virtualDisplay.destroy()
        virtualDisplayActive = false
        rtc?.close()
        rtc = nil
        running = false
    }

    // MARK: - 信令

    func handleOffer(_ sdp: String) { rtc?.handleOffer(sdp) }

    func handleCandidate(_ sdp: String, index: Int32, mid: String?) {
        rtc?.handleCandidate(sdp, sdpMLineIndex: index, sdpMid: mid)
    }

    private func flushPending() {
        guard let rtc else { return }
        pendingFrames.forEach { rtc.sendVideo($0.0, key: $0.1) }
        pendingFrames.removeAll()
    }
}

extension ControlledSession: WebRTCSessionDelegate {
    func webRTC(_ session: WebRTCSession, didCreateOffer sdp: String) {}

    func webRTC(_ session: WebRTCSession, didCreateAnswer sdp: String) {
        onSignal?("answer", ["sdp": sdp])
    }

    func webRTC(_ session: WebRTCSession, didGenerate candidate: RTCIceCandidate) {
        onSignal?("candidate", [
            "candidate": candidate.sdp,
            "sdpMid": candidate.sdpMid ?? "",
            "sdpMLineIndex": Int(candidate.sdpMLineIndex)
        ])
    }

    func webRTC(_ session: WebRTCSession, didChange state: RTCIceConnectionState) {}

    func webRTC(_ session: WebRTCSession, didReceive videoTrack: RTCVideoTrack) {}

    func webRTC(_ session: WebRTCSession, didOpenVideo channel: H265Channel) {
        flushPending()
        channel.requestKeyframe()
    }

    func webRTC(_ session: WebRTCSession, didOpenControl channel: RTCDataChannel) { controlReady = true }

    func webRTC(_ session: WebRTCSession, didReceiveControl data: Data) {
        guard let message = GvMessage.decode(data) else { return }
        if message.payloadKind == .clipboardChange {
            if let value = ClipboardManager.decodeAndApply(message.payload, onPasteboard: { value in
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string)
            }) { clipboard.markReceived(value) }
            return
        }
        guard message.payloadKind == .inputEvent else { return }
        var reader = ProtoReader(message.payload)
        guard let (field, _) = try? reader.nextField(), field == 1,
              let body = try? reader.readBytes() else { return }
        handleTouch(body)
    }

    private func handleTouch(_ data: Data) {
        var reader = ProtoReader(data)
        var event = GvTouchEvent(type: .undefined, points: [])
        while let (field, wire) = try? reader.nextField() {
            switch field {
            case 1:
                let raw = (try? reader.readInt32()) ?? 0
                event.type = GvTouchEventType(rawValue: raw) ?? .undefined
            case 2:
                if let d = try? reader.readBytes() { event.points.append(decodePoint(d)) }
            default:
                try? reader.skip(wire)
            }
        }
        DispatchQueue.main.async { self.injector.handle(event) }
    }

    private func decodePoint(_ data: Data) -> GvTouchPoint {
        var reader = ProtoReader(data)
        var p = GvTouchPoint(id: 0, x: 0, y: 0)
        while let (field, wire) = try? reader.nextField() {
            switch field {
            case 1: p.id = (try? reader.readInt32()) ?? 0
            case 2: p.x = (try? reader.readFloat()) ?? 0
            case 3: p.y = (try? reader.readFloat()) ?? 0
            case 4: p.radiusX = (try? reader.readFloat()) ?? 0
            case 5: p.radiusY = (try? reader.readFloat()) ?? 0
            case 6: p.angle = (try? reader.readFloat()) ?? 0
            case 7: p.pressure = (try? reader.readFloat()) ?? 0
            default: try? reader.skip(wire)
            }
        }
        return p
    }
}
