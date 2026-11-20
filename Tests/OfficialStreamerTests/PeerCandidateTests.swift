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

    func testAddressStages() {
        for (ip, stage) in [("2001:db8::1", 0), ("192.168.1.3", 1), ("peer.local", 1),
                            ("100.64.0.1", 2), ("fd7a:115c:a1e0::1", 2)] {
            XCTAssertEqual(PeerNetwork.candidateStage("candidate:1 1 udp 1 \(ip) 9 typ host"), stage)
        }
    }
}
