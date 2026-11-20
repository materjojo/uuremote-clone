import SwiftUI

@MainActor final class AppState: ObservableObject {
    enum Route: String, CaseIterable, Identifiable {
        case devices, files, terminal, settings
        var id: String { rawValue }
        var title: String {
            switch self {
            case .devices: return L10n.devices
            case .files: return L10n.files
            case .terminal: return L10n.terminal
            case .settings: return L10n.settings
            }
        }
        var icon: String {
            switch self {
            case .devices: return "desktopcomputer"
            case .files: return "arrow.left.arrow.right"
            case .terminal: return "terminal"
            case .settings: return "gearshape"
            }
        }
    }

    @Published var route: Route = .devices
    @Published var devices: [DeviceInfo] = []
    @Published var peers: [PeerInvitation] = []
    @Published var session: RemoteSession?
    @Published var isLoading = false
    @Published var errorText: String?
    let host = PeerHost()

    init() { restore() }

    private func restore() {
        if let data = UserDefaults.standard.data(forKey: "peer.devices.v1"),
           let saved = try? JSONDecoder().decode([PeerInvitation].self, from: data) { peers = saved }
        devices = peers.map {
            DeviceInfo(deviceID: $0.id, deviceName: $0.name, platform: $0.platform,
                       versionName: nil, online: false, supportWOL: false, controlledSupport: true, tags: ["已配对"])
        }
    }

    func loadDevices() async { restore() }

    func addDevice(_ code: String) throws {
        let peer = try PeerInvitation.parse(code)
        guard peer.id != host.identity.id else { throw PeerError.message("不能把本机添加为远程设备") }
        peers.removeAll { $0.id == peer.id && $0.server == peer.server }
        peers.append(peer)
        UserDefaults.standard.set(try JSONEncoder().encode(peers), forKey: "peer.devices.v1")
        restore()
    }

    func removeDevice(_ id: String) {
        peers.removeAll { $0.id == id }
        UserDefaults.standard.set(try? JSONEncoder().encode(peers), forKey: "peer.devices.v1")
        restore()
    }

    func connect(_ device: DeviceInfo) {
        guard let peer = peers.first(where: { $0.id == device.deviceID }) else { return }
        session?.disconnect()
        let s = RemoteSession()
        session = s
        s.connect(peer: peer, device: device)
    }
}
