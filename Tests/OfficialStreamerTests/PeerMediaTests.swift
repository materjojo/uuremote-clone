import XCTest
import CoreVideo
@testable import UURemoteClone
import WebRTC

final class PeerMediaTests: XCTestCase {
    final class Renderer: NSObject, RTCVideoRenderer {
        let frame: XCTestExpectation
        let converter = VideoPixelConverter()
        init(_ frame: XCTestExpectation) { self.frame = frame }
        func setSize(_ size: CGSize) {}
        func renderFrame(_ value: RTCVideoFrame?) {
            guard let value, let raw = converter.convert(value.buffer), let bgra = converter.bgra(raw) else { return }
            if CVPixelBufferGetWidth(bgra) == 64 && CVPixelBufferGetHeight(bgra) == 64 &&
                CVPixelBufferGetPixelFormatType(bgra) == kCVPixelFormatType_32BGRA { frame.fulfill() }
        }
    }
    final class Endpoint: NSObject, WebRTCSessionDelegate {
        var offer: ((String) -> Void)?
        var answer: ((String) -> Void)?
        var candidate: ((RTCIceCandidate) -> Void)?
        var control: ((Data) -> Void)?
        var track: ((RTCVideoTrack) -> Void)?
        var open: (() -> Void)?
        func webRTC(_ s: WebRTCSession, didCreateOffer value: String) { offer?(value) }
        func webRTC(_ s: WebRTCSession, didCreateAnswer value: String) { answer?(value) }
        func webRTC(_ s: WebRTCSession, didGenerate value: RTCIceCandidate) { candidate?(value) }
        func webRTC(_ s: WebRTCSession, didChange state: RTCIceConnectionState) {}
        func webRTC(_ s: WebRTCSession, didReceiveControl data: Data) { control?(data) }
        func webRTC(_ s: WebRTCSession, didReceive value: RTCVideoTrack) { track?(value) }
        func webRTC(_ s: WebRTCSession, didOpenControl channel: RTCDataChannel) { open?() }
    }

    func testRealPeerVideoAndBidirectionalControl() {
        let gotVideo = expectation(description: "RTP video decoded")
        gotVideo.assertForOverFulfill = false
        let gotEcho = expectation(description: "SCTP control roundtrip")
        gotEcho.assertForOverFulfill = false
        let host = WebRTCSession(role: .controlled)
        let controller = WebRTCSession(role: .controller)
        let h = Endpoint(), c = Endpoint(), renderer = Renderer(gotVideo)
        host.delegate = h; controller.delegate = c
        host.onError = { XCTFail($0) }; controller.onError = { XCTFail($0) }
        h.answer = { controller.handleAnswer($0) }
        c.offer = { host.handleOffer($0) }
        h.candidate = { controller.handleCandidate($0.sdp, sdpMLineIndex: $0.sdpMLineIndex, sdpMid: $0.sdpMid) }
        c.candidate = { host.handleCandidate($0.sdp, sdpMLineIndex: $0.sdpMLineIndex, sdpMid: $0.sdpMid) }
        h.control = { bytes in if bytes == Data("input".utf8) { host.sendControl(Data("ack".utf8)) } }
        c.control = { bytes in if bytes == Data("ack".utf8) { gotEcho.fulfill() } }
        var remoteTrack: RTCVideoTrack?
        c.track = { value in remoteTrack = value; value.add(renderer) }
        c.open = { controller.sendControl(Data("input".utf8)) }
        _ = host.prepareLocalVideo()
        controller.startAsController()
        var tick: Int64 = 0
        let timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32BGRA,
                                [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer)
            if let buffer {
                CVPixelBufferLockBaseAddress(buffer, [])
                if let address = CVPixelBufferGetBaseAddress(buffer) { memset(address, 100, CVPixelBufferGetDataSize(buffer)) }
                CVPixelBufferUnlockBaseAddress(buffer, [])
                tick += 50_000_000
                host.push(pixelBuffer: buffer, timeNs: tick)
            }
        }
        wait(for: [gotVideo, gotEcho], timeout: 25)
        timer.invalidate()
        remoteTrack?.remove(renderer)
        host.close(); controller.close()
        withExtendedLifetime((host, controller, h, c, renderer)) {}
    }
}
