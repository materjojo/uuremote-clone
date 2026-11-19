import Foundation
import Combine
import CoreMedia
import ScreenCaptureKit
import WebRTC

/// 被控端：采集 + 应答 + 注入
final class ControlledSession: NSObject, ObservableObject {
    @Published private(set) var running = false
    @Published private(set) var lastError: String?

    private var rtc: WebRTCSession?
    private let capturer = ScreenCapturer()
    private let injector = InputInjector()
    private var screenSize: CGSize = .zero

    func start(display: SCDisplay, fps: Int = 60) async {
        do {
            let rtc = WebRTCSession(role: .controlled)
            rtc.delegate = self
            _ = rtc.prepareLocalVideo()
            self.rtc = rtc

            screenSize = CGSize(width: display.width, height: display.height)
            injector.updateScreenSize(screenSize)

            var config = ScreenCapturer.Config()
            config.width = display.width
            config.height = display.height
            config.fps = fps
            config.capturesAudio = false

            try await capturer.start(display: display, config: config) { [weak rtc] buffer, time in
                let ns = Int64(CMTimeGetSeconds(time) * 1_000_000_000)
                rtc?.push(pixelBuffer: buffer, timeNs: ns)
            }
            running = true
        } catch {
            lastError = error.localizedDescription
            running = false
        }
    }

    func stop() async {
        await capturer.stop()
        running = false
    }

    func handleOffer(_ sdp: String) { rtc?.handleOffer(sdp) }

    func handleCandidate(_ sdp: String, index: Int32, mid: String?) {
        rtc?.handleCandidate(sdp, sdpMLineIndex: index, sdpMid: mid)
    }
}

extension ControlledSession: WebRTCSessionDelegate {
    func webRTC(_ session: WebRTCSession, didCreateOffer sdp: String) {}
    func webRTC(_ session: WebRTCSession, didCreateAnswer sdp: String) {}
    func webRTC(_ session: WebRTCSession, didGenerate candidate: RTCIceCandidate) {}
    func webRTC(_ session: WebRTCSession, didChange state: RTCIceConnectionState) {}
    func webRTC(_ session: WebRTCSession, didReceive videoTrack: RTCVideoTrack) {}

    func webRTC(_ session: WebRTCSession, didReceiveControl data: Data) {
        guard let message = GvMessage.decode(data) else { return }
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
