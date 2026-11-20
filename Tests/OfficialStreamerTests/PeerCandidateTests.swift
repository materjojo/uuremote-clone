import XCTest
import WebRTC
@testable import UURemoteClone

final class PeerCandidateTests: XCTestCase {
    func testEmbeddedSDPIsStagedAndKeepsMediaIdentity() {
        let ipv4 = expectation(description: "IPv4 candidate after IPv6 grace")
        let gate = PeerCandidateGate()
        var immediate: [String] = []
        gate.emit = { value in
            if value.sdp.contains("192.168.") {
                XCTAssertEqual(value.sdpMid, "screen"); XCTAssertEqual(value.sdpMLineIndex, 1); ipv4.fulfill()
            } else {
                XCTAssertFalse(PeerNetwork.isOverlay(value.sdp)); immediate.append(value.sdp)
            }
        }
        gate.connected = { false }
        let sdp = "v=0\r\nm=application 9 UDP/DTLS/SCTP webrtc-datachannel\r\na=mid:control\r\na=candidate:1 1 udp 1 2001:db8::1 9 typ host\r\nm=video 9 UDP/TLS/RTP/SAVPF 96\r\na=mid:screen\r\na=candidate:2 1 udp 1 192.168.1.2 9 typ host\r\na=candidate:3 1 udp 1 100.64.0.2 9 typ host\r\na=end-of-candidates\r\n"
        let signaled = gate.signalSDP(sdp)
        XCTAssertFalse(signaled.contains("a=candidate:"))
        XCTAssertFalse(signaled.contains("a=end-of-candidates"))
        XCTAssertTrue(signaled.contains("a=mid:screen"))
        XCTAssertEqual(immediate.count, 1)
        wait(for: [ipv4], timeout: 3)
        gate.close() // Overlay must never leak after teardown.
    }

    func testOverlayWaitsAndStopsAfterConnectionOrClose() {
        let released = expectation(description: "overlay fallback after 8 seconds")
        released.expectedFulfillmentCount = 2
        let start = Date()
        let fallback = PeerCandidateGate(), connected = PeerCandidateGate()
        let closed = PeerCandidateGate(), closedDuringSend = PeerCandidateGate()
        defer { [fallback, connected, closed, closedDuringSend].forEach { $0.close() } }
        var isConnected = false, fallbackCount = 0, stoppedCount = 0, connectedCount = 0, closedCount = 0
        fallback.connected = { isConnected }
        fallback.emit = { _ in
            XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(start), 7.8)
            fallbackCount += 1; released.fulfill()
        }
        connected.connected = { isConnected }
        connected.emit = { _ in connectedCount += 1 }
        closed.emit = { _ in closedCount += 1 }
        closedDuringSend.emit = { _ in stoppedCount += 1; closedDuringSend.close() }
        let values = ["100.64.0.2", "fd7a:115c:a1e0::2"].enumerated().map { index, ip in
            RTCIceCandidate(sdp: "candidate:\(index) 1 udp 1 \(ip) 9 typ host", sdpMLineIndex: 0, sdpMid: "control")
        }
        for gate in [fallback, connected, closed, closedDuringSend] {
            values.forEach { gate.submit($0); gate.submit($0) } // repeated trickle/SDP must be deduplicated
        }
        // Only the second gate is connected when its timer expires.
        connected.connected = { true }
        closed.close()
        XCTAssertEqual(fallbackCount, 0)
        wait(for: [released], timeout: 11)
        // Allow every timer on the main queue to finish before checking silence.
        let drained = expectation(description: "all timers drained")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { drained.fulfill() }
        wait(for: [drained], timeout: 1)
        XCTAssertEqual(fallbackCount, 2); XCTAssertEqual(connectedCount, 0)
        XCTAssertEqual(closedCount, 0); XCTAssertEqual(stoppedCount, 1)
        isConnected = true
        let late = RTCIceCandidate(sdp: "candidate:late 1 udp 1 100.64.0.3 9 typ host", sdpMLineIndex: 0, sdpMid: "control")
        fallback.submit(late); connected.submit(late); closed.submit(late); closedDuringSend.submit(late)
        XCTAssertEqual(fallbackCount, 2); XCTAssertEqual(connectedCount, 0)
        XCTAssertEqual(closedCount, 0); XCTAssertEqual(stoppedCount, 1)
    }

    func testAddressStages() {
        for (ip, stage) in [("2001:db8::1", 0), ("192.168.1.3", 1), ("peer.local", 1),
                            ("100.64.0.1", 2), ("fd7a:115c:a1e0::1", 2)] {
            XCTAssertEqual(PeerNetwork.candidateStage("candidate:1 1 udp 1 \(ip) 9 typ host"), stage)
        }
    }
}
