import Foundation

public struct DeviceInfo: Identifiable, Codable, Hashable {
    public var id: String { deviceID }
    public var deviceID: String
    public var deviceName: String
    public var platform: String
    public var versionName: String?
    public var online: Bool
    public var supportWOL: Bool?
    public var controlledSupport: Bool?
    public var tags: [String]?

    enum CodingKeys: String, CodingKey {
        case deviceID = "device_id"
        case deviceName = "device_name"
        case platform
        case versionName = "version_name"
        case online
        case supportWOL = "support_wol"
        case controlledSupport = "controlled_support"
        case tags
    }
}

public struct RoomInfo: Codable {
    public var roomID: String
    public var token: String
    public var signalingServer: String?
    public var signalingList: [String]?
    public var sniRequiredSignalingList: [String]?
    public var publisherDeviceID: String?
    public var publisherPlatform: String?
    public var wsConnectTimeoutMS: Int?
    public var maxReconnectDelta: Int?
    public var reportToken: String?
    public var reportURL: String?
    public var reportServerAddress: String?

    enum CodingKeys: String, CodingKey {
        case roomID = "room_id"
        case token
        case signalingServer = "signaling_server"
        case signalingList = "signaling_list"
        case sniRequiredSignalingList = "sni_required_signaling_list"
        case publisherDeviceID = "publisher_device_id"
        case publisherPlatform = "publisher_platform"
        case wsConnectTimeoutMS = "ws_connect_timeout_ms"
        case maxReconnectDelta = "max_reconnect_delta"
        case reportToken = "report_token"
        case reportURL = "report_url"
        case reportServerAddress = "report_server_address"
    }
}

public struct APIEnvelope<T: Decodable>: Decodable {
    public var code: Int
    public var message: String?
    public var data: T?
}
