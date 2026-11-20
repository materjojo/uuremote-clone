import AppKit
import ScreenCaptureKit
import Combine

/// Hosting is an explicit, visible action and every new session needs consent.
@MainActor final class PeerHost: ObservableObject {
    let identity = PeerIdentity.load()
    @Published var server = UserDefaults.standard.string(forKey: "peer.server.v1") ?? ""
    @Published private(set) var running = false
    @Published private(set) var status = "未开启接收远程连接"
    @Published private(set) var invitation = ""
    private var inboxTask: Task<Void, Never>?
    private var mailbox: PeerMailbox?
    private var controlled: ControlledSession?
    private var handled = Set<String>()

    func start() {
        guard !running else { return }
        do {
            let api = try PeerAPI(server)
            UserDefaults.standard.set(server, forKey: "peer.server.v1")
            running = true
            status = "正在注册本机…"
            let name = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
            inboxTask = Task {
                do {
                    _ = try await api.request("/v1/register", body: [
                        "id": identity.id, "key": identity.key, "pair_key": identity.pairKey,
                        "name": name, "platform": "mac"
                    ])
                    invitation = PeerInvitation(server: api.base.absoluteString, id: identity.id,
                                                key: identity.pairKey, name: name, platform: "mac").code
                    status = "等待连接 · 每次连接需本机确认"
                    while !Task.isCancelled && running {
                        let result = try await api.request("/v1/devices/\(identity.id)/inbox", token: identity.key)
                        for item in result["requests"] as? [[String: Any]] ?? [] {
                            guard let id = item["id"] as? String, !handled.contains(id) else { continue }
                            handled.insert(id)
                            await receive(api: api, id: id, name: item["name"] as? String ?? "远程设备")
                        }
                        try await Task.sleep(nanoseconds: 2_000_000_000)
                    }
                } catch {
                    if !Task.isCancelled { status = error.localizedDescription; running = false }
                }
            }
        } catch { status = error.localizedDescription }
    }

    private func receive(api: PeerAPI, id: String, name: String) async {
        let box = PeerMailbox(api: api, id: id, token: identity.key)
        if mailbox != nil { box.send("close"); return }
        let alert = NSAlert()
        alert.messageText = "允许远程控制？"
        alert.informativeText = "“\(name)”请求查看屏幕并控制这台 Mac。"
        alert.addButton(withTitle: "允许")
        alert.addButton(withTitle: "拒绝")
        guard alert.runModal() == .alertFirstButtonReturn else { box.send("close"); return }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else { throw PeerError.message("没有可共享的显示器") }
            let controlled = ControlledSession()
            controlled.codec = .h264
            await controlled.start(display: display, fps: 30)
            guard controlled.running else { throw PeerError.message(controlled.lastError ?? "屏幕采集启动失败") }
            guard running, !Task.isCancelled else { await controlled.stop(); box.send("close"); return }
            self.controlled = controlled
            mailbox = box
            status = "已允许 \(name) · 正在协商连接"
            controlled.onSignal = { [weak box] type, value in
                DispatchQueue.main.async { box?.send(type, value as? [String: Any] ?? [:]) }
            }
            box.onSignal = { [weak self, weak controlled] signal in
                switch signal.type {
                case "offer": if let sdp = signal.data["sdp"] as? String { controlled?.handleOffer(sdp) }
                case "candidate":
                    if let sdp = signal.data["candidate"] as? String {
                        controlled?.handleCandidate(sdp, index: Int32(signal.data["sdpMLineIndex"] as? Int ?? 0),
                                                    mid: signal.data["sdpMid"] as? String)
                    }
                case "close": self?.endSession()
                default: break
                }
            }
            box.onError = { [weak self] error in self?.status = error; self?.endSession() }
            box.send("accept")
            box.start()
        } catch {
            box.send("close")
            status = error.localizedDescription
        }
    }

    func endSession(notify: Bool = false) {
        let box = mailbox
        mailbox = nil
        if notify {
            box?.onSignal = nil; box?.onError = nil
            box?.send("close")
            Task { try? await Task.sleep(nanoseconds: 500_000_000); box?.stop() }
        } else { box?.stop() }
        if let controlled { Task { await controlled.stop() } }
        controlled = nil
        if running { status = "等待连接 · 每次连接需本机确认" }
    }

    func stop() {
        endSession(notify: true)
        inboxTask?.cancel()
        inboxTask = nil
        running = false
        invitation = ""
        status = "未开启接收远程连接"
    }
}
