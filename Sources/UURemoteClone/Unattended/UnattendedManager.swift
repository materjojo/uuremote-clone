import Foundation
import AppKit
import ScreenCaptureKit

/// 无人值守：安装/卸载用户级 LaunchAgent，开机自启并以 --agent 模式常驻
final class UnattendedManager {
    static let shared = UnattendedManager()
    static let label = "com.example.uuremote.clone.agent"

    private var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(Self.label).plist")
    }

    var isEnabled: Bool { FileManager.default.fileExists(atPath: plistURL.path) }

    func enable() throws {
        guard let executable = Bundle.main.executablePath else {
            throw NSError(domain: "Unattended", code: 1, userInfo: [NSLocalizedDescriptionKey: "找不到可执行文件"])
        }
        let plist: [String: Any] = [
            "Label": Self.label,
            "ProgramArguments": [executable, "--agent"],
            "RunAtLoad": true,
            "KeepAlive": ["SuccessfulExit": false],
            "ProcessType": "Interactive",
            "StandardOutPath": "/tmp/uuremote-clone-agent.log",
            "StandardErrorPath": "/tmp/uuremote-clone-agent.err"
        ]
        let dir = plistURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: plistURL)

        let uid = getuid()
        _ = run("/bin/launchctl", ["bootout", "gui/\(uid)/\(Self.label)"])
        let result = run("/bin/launchctl", ["bootstrap", "gui/\(uid)", plistURL.path])
        if result != 0 {
            _ = run("/bin/launchctl", ["load", "-w", plistURL.path])
        }
    }

    func disable() {
        let uid = getuid()
        _ = run("/bin/launchctl", ["bootout", "gui/\(uid)/\(Self.label)"])
        try? FileManager.default.removeItem(at: plistURL)
    }

    @discardableResult
    private func run(_ path: String, _ args: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }
}

/// --agent 模式：无界面常驻被控端
final class AgentService {
    static let shared = AgentService()
    static let offerNotification = Notification.Name("com.example.uuremote.clone.offer")

    private let session = ControlledSession()
    private var started = false

    func start() {
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(handleOffer(_:)),
            name: Self.offerNotification, object: nil)

        session.codec = (UserDefaults.standard.object(forKey: "useH265") as? Bool ?? true) ? .h265 : .h264
        let useVirtual = UserDefaults.standard.bool(forKey: "virtualDisplay")

        Task {
            if useVirtual {
                await session.start(source: .virtual(width: 1920, height: 1080), privateScreen: .normal)
                started = true
                return
            }
            guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
                  let display = content.displays.first else { return }
            await session.start(display: display, fps: 60)
            started = true
        }
    }

    @objc private func handleOffer(_ note: Notification) {
        guard let sdp = note.userInfo?["sdp"] as? String else { return }
        session.handleOffer(sdp)
    }
}

enum AgentRuntime {
    static func run() -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        AgentService.shared.start()
        app.run()
        exit(0)
    }
}
