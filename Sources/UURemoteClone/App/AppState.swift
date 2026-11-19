import SwiftUI

final class AppState: ObservableObject {
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
    @Published var session: RemoteSession?
    @Published var isLoading = false
    @Published var errorText: String?

    init() {
        Task { await loadDevices() }
    }

    @MainActor
    func loadDevices() async {
        isLoading = true
        defer { isLoading = false }
        do {
            devices = try await APIClient.shared.deviceList()
        } catch {
            errorText = error.localizedDescription
        }
    }

    @MainActor
    func connect(_ device: DeviceInfo) {
        let s = RemoteSession()
        session = s
        s.connect(device: device)
    }
}
