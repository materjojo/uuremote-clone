import Foundation

/// Legacy vendor API is deliberately disabled. Device ownership and sessions
/// now use PeerAPI with an explicitly configured independent rendezvous.
final class APIClient {
    static let shared = APIClient()
    func deviceList() async throws -> [DeviceInfo] { [] }
    func createRoom(deviceID: String) async throws -> RoomInfo {
        throw APIError.server("请通过对端配对码连接设备")
    }
    func wakeOnLANInfo(deviceID: String) async throws -> WakeOnLANInfo? { nil }
}

enum APIError: Error, LocalizedError {
    case http(Int)
    case server(String)
    var errorDescription: String? {
        switch self {
        case .http(let code): return "HTTP \(code)"
        case .server(let message): return message
        }
    }
}
