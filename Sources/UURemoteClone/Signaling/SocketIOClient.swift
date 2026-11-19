import Foundation

/// Engine.IO v4 / Socket.IO v4 最小客户端
/// 与官方 4.48.1 使用的连接串一致：
/// wss://{host}/socket.io/?EIO=4&transport=websocket&t={ms}
final class SocketIOClient {
    enum State { case idle, connecting, connected, closed }

    private(set) var state: State = .idle
    private var task: URLSessionWebSocketTask?
    private let session: URLSession
    private let baseURL: URL
    private var pingTimer: DispatchSourceTimer?

    var onEvent: ((String, Any?) -> Void)?
    var onStateChange: ((State) -> Void)?

    init(host: String, useTLS: Bool = true) {
        var components = URLComponents()
        components.scheme = useTLS ? "wss" : "ws"
        components.host = host
        components.path = "/socket.io/"
        components.queryItems = [
            URLQueryItem(name: "EIO", value: "4"),
            URLQueryItem(name: "transport", value: "websocket"),
            URLQueryItem(name: "t", value: String(Int(Date().timeIntervalSince1970 * 1000)))
        ]
        self.baseURL = components.url!
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)
    }

    func connect() {
        guard state == .idle || state == .closed else { return }
        state = .connecting
        onStateChange?(state)
        let t = session.webSocketTask(with: baseURL)
        task = t
        t.resume()
        receiveLoop()
    }

    func disconnect() {
        pingTimer?.cancel(); pingTimer = nil
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        state = .closed
        onStateChange?(state)
    }

    func emit(_ event: String, _ payload: Any? = nil) {
        guard state == .connected, let task else { return }
        let array: [Any] = payload.map { [event, $0] } ?? [event]
        guard JSONSerialization.isValidJSONObject(array),
              let data = try? JSONSerialization.data(withJSONObject: array),
              let text = String(data: data, encoding: .utf8) else { return }
        task.send(.string("42" + text)) { _ in }
    }

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure:
                self.state = .closed
                self.onStateChange?(.closed)
            case .success(let message):
                switch message {
                case .string(let text): self.handle(text)
                case .data: break
                @unknown default: break
                }
                self.receiveLoop()
            }
        }
    }

    private func handle(_ text: String) {
        guard let first = text.first else { return }
        switch first {
        case "0":
            // OPEN -> 连接默认命名空间
            task?.send(.string("40")) { _ in }
        case "2":
            task?.send(.string("3")) { _ in }
        case "4":
            guard text.count > 1 else { return }
            let second = text[text.index(text.startIndex, offsetBy: 1)]
            if second == "0" {
                state = .connected
                onStateChange?(state)
            } else if second == "2" {
                let json = String(text.dropFirst(2))
                if let data = json.data(using: .utf8),
                   let arr = try? JSONSerialization.jsonObject(with: data) as? [Any],
                   let event = arr.first as? String {
                    onEvent?(event, arr.count > 1 ? arr[1] : nil)
                }
            }
        default:
            break
        }
    }
}
