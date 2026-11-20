import XCTest
@testable import UURemoteClone

final class PeerInvitationTests: XCTestCase {
    func testInvitationRoundTripWithoutAssumingPeerPlatform() throws {
        for platform in ["windows", "mac", "android"] {
            let peer = PeerInvitation(server: "https://signal.example.org", id: "peer-00000000000001",
                                      key: String(repeating: "a", count: 64), name: "自定义设备", platform: platform)
            XCTAssertEqual(try PeerInvitation.parse(peer.code), peer)
        }
    }

    func testMalformedAndCredentialBearingURLsAreRejected() throws {
        XCTAssertThrowsError(try PeerInvitation.parse("MacBook Pro"))
        XCTAssertThrowsError(try PeerAPI.endpoint("https://user:password@example.org"))
        XCTAssertThrowsError(try PeerAPI.endpoint("file:///etc/passwd"))
        XCTAssertThrowsError(try PeerAPI.endpoint("https://example.org/api?key=secret"))
    }

    func testIPv6AndIPv4OverlayDetectionDoesNotMisclassifyNativeAddresses() {
        func candidate(_ ip: String) -> String { "candidate:1 1 udp 2113937151 \\(ip) 9999 typ host" }
        XCTAssertTrue(PeerNetwork.isOverlay(candidate("100.64.0.1")))
        XCTAssertTrue(PeerNetwork.isOverlay(candidate("100.127.255.1")))
        XCTAssertTrue(PeerNetwork.isOverlay(candidate("fd7a:115c:a1e0::1")))
        for ip in ["192.168.1.3", "2001:db8::1", "10.0.0.1", "100.128.0.1", "100.63.0.1"] {
            XCTAssertFalse(PeerNetwork.isOverlay(candidate(ip)))
        }
    }
}
