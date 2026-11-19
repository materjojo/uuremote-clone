import Foundation

/// 业务 API（端点与官方一致，字段名取自二进制 Codable 键）
final class APIClient {
    static let shared = APIClient()

    var baseURL = URL(string: "https://api.nrd.nie.163.com")!
    var accessToken: String?
    var useMock = true   // 无真实凭据时使用本地演示数据

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 15
        return URLSession(configuration: cfg)
    }()

    func deviceList() async throws -> [DeviceInfo] {
        if useMock { return MockBackend.devices }
        let data = try await post("/api/v1/device/list", body: [:])
        let env = try JSONDecoder().decode(APIEnvelope<DeviceListPayload>.self, from: data)
        return env.data?.devices ?? []
    }

    func createRoom(deviceID: String) async throws -> RoomInfo {
        if useMock { return MockBackend.room(deviceID: deviceID) }
        let data = try await post("/api/v1/room/create", body: [
            "device_id": deviceID,
            "client_type": 4,
            "client_version": "4.48.1"
        ])
        let env = try JSONDecoder().decode(APIEnvelope<RoomInfo>.self, from: data)
        guard let room = env.data else { throw APIError.server(env.message ?? "empty room") }
        return room
    }

    func wakeOnLANInfo(deviceID: String) async throws -> WakeOnLANInfo? {
        if useMock { return WakeOnLANInfo(mac: "AA:BB:CC:DD:EE:FF", macAddress: nil, ip: nil, port: 9) }
        let data = try await post("/api/v1/device/wake_on_lan/info", body: ["device_id": deviceID])
        let env = try JSONDecoder().decode(APIEnvelope<WakeOnLANInfo>.self, from: data)
        return env.data
    }

    private func post(_ path: String, body: [String: Any]) async throws -> Data {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = accessToken {
            req.setValue(token, forHTTPHeaderField: "X-NRD-AUTH")
            req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.http((resp as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return data
    }
}

enum APIError: Error, LocalizedError {
    case http(Int)
    case server(String)
    var errorDescription: String? {
        switch self {
        case .http(let code): return "HTTP \(code)"
        case .server(let msg): return msg
        }
    }
}

struct DeviceListPayload: Decodable { var devices: [DeviceInfo] }

enum MockBackend {
    static let devices: [DeviceInfo] = [
        .init(deviceID: "demo-mac-001", deviceName: "MacBook Pro", platform: "mac",
              versionName: "4.48.1", online: true, supportWOL: true, controlledSupport: true, tags: ["本机"]),
        .init(deviceID: "demo-win-002", deviceName: "工作室主机", platform: "windows",
              versionName: "4.48.1", online: false, supportWOL: true, controlledSupport: true, tags: nil)
    ]

    static func room(deviceID: String) -> RoomInfo {
        RoomInfo(roomID: "demo-room", token: "demo-token",
                 signalingServer: nil, signalingList: nil, sniRequiredSignalingList: nil,
                 publisherDeviceID: deviceID, publisherPlatform: "mac",
                 wsConnectTimeoutMS: 8000, maxReconnectDelta: 8000,
                 reportToken: nil, reportURL: nil, reportServerAddress: nil)
    }
}
