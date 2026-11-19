import XCTest
@testable import UURemoteClone

final class OfficialStreamerTests: XCTestCase {
    func testSuppliedLibraryVersionFromBothTables() throws {
        guard let path = ProcessInfo.processInfo.environment["UU_OFFICIAL_LIBRARY"] else {
            throw XCTSkip("Set UU_OFFICIAL_LIBRARY to the supplied 4.48.1 dylib")
        }
        for role in [OfficialStreamer.Role.controller, .controlled] {
            let library = try OfficialStreamer(path: path, role: role)
            XCTAssertEqual(try library.version, "V4.14.2")
        }
    }

    func testMissingLibraryReportsLoadFailure() {
        XCTAssertThrowsError(try OfficialStreamer(path: "/nonexistent/uuremote/libstreamer.dylib"))
    }

    func testDescriptorTablesIncludeRecoveredMessages() {
        XCTAssertEqual(GvSchema.messageCount, 179)
        XCTAssertEqual(GvSchema.name("GvPb_ScreenResolution", 1), "width")
        XCTAssertEqual(GvSchema.name("MumuSetting.MapKeyValueEntry", 2), "value")
    }
}
