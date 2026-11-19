import Foundation
import OfficialStreamerABI

/// Inspects the supplied desktop library through the shared, verified C ABI.
/// This does not initialize capture or create a room. See docs/11-native-contract.md.
final class OfficialStreamer {
    enum Role: Int32 { case controller = 0, controlled = 1 }
    enum Failure: Error, LocalizedError {
        case load(String)
        case native(Int32)
        var errorDescription: String? {
            switch self {
            case .load(let reason): return reason
            case .native(let code): return "官方 streamer 返回错误：\(code)"
            }
        }
    }

    private let handle: OpaquePointer

    init(path: String? = nil, role: Role = .controller) throws {
        let library = path ?? Bundle.main.bundleURL
            .appendingPathComponent("Contents/Frameworks/libstreamer.dylib").path
        var error = [CChar](repeating: 0, count: 1024)
        let result = error.withUnsafeMutableBufferPointer { buffer in
            library.withCString { name in
                uu_official_open(name, role.rawValue, buffer.baseAddress, buffer.count)
            }
        }
        guard let result else { throw Failure.load(String(cString: error)) }
        handle = result
    }

    var version: String {
        get throws {
            var bytes = [CChar](repeating: 0, count: 4097)
            let status = bytes.withUnsafeMutableBufferPointer {
                uu_official_version(handle, $0.baseAddress, $0.count)
            }
            guard status == 0 else { throw Failure.native(status) }
            return String(cString: bytes)
        }
    }

    deinit { uu_official_close(handle) }
}
