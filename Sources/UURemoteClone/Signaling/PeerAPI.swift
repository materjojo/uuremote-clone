import Foundation

/// Versioned invitation for the independent rendezvous, not a NetEase room token.
struct PeerInvitation: Codable, Identifiable, Hashable {
    var v = 1
    var server: String
    var id: String
    var key: String
    var name: String
    var platform: String

    var code: String {
        let data = try! JSONEncoder().encode(self)
        return "uur1." + data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    static func parse(_ text: String) throws -> PeerInvitation {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("uur1."), text.count < 8192 else { throw PeerError.message("请输入被控设备生成的配对码") }
        var base = String(text.dropFirst(5)).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base += String(repeating: "=", count: (4 - base.count % 4) % 4)
        guard let bytes = Data(base64Encoded: base) else { throw PeerError.message("配对码损坏") }
        let value = try JSONDecoder().decode(PeerInvitation.self, from: bytes)
        _ = try PeerAPI.endpoint(value.server)
        guard value.v == 1, (16...64).contains(value.id.count), (32...128).contains(value.key.count),
              !value.name.isEmpty, ["mac", "windows", "android"].contains(value.platform) else {
            throw PeerError.message("配对码版本或设备信息不正确")
        }
        return value
    }
}

enum PeerError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

struct PeerIdentity: Codable {
    var id = UUID().uuidString
    var key = UUID().uuidString.replacingOccurrences(of: "-", with: "") + UUID().uuidString.replacingOccurrences(of: "-", with: "")
    var pairKey = UUID().uuidString.replacingOccurrences(of: "-", with: "") + UUID().uuidString.replacingOccurrences(of: "-", with: "")
    static func load() -> PeerIdentity {
        if let data = UserDefaults.standard.data(forKey: "peer.identity.v1"),
           let identity = try? JSONDecoder().decode(Self.self, from: data) { return identity }
        let identity = PeerIdentity()
        UserDefaults.standard.set(try? JSONEncoder().encode(identity), forKey: "peer.identity.v1")
        return identity
    }
}

struct PeerSignal {
    let seq: Int
    let type: String
    let data: [String: Any]
}

final class PeerAPI {
    let base: URL
    private let session: URLSession
    init(_ server: String) throws {
        base = try Self.endpoint(server)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 18
        session = URLSession(configuration: config)
    }

    static func endpoint(_ value: String) throws -> URL {
        guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["https", "http"].contains(url.scheme), url.host != nil,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/" else {
            throw PeerError.message("请输入自建信令服务根地址（https://主机 或局域网 http://地址:8080）")
        }
        return url
    }

    func request(_ path: String, token: String? = nil, body: [String: Any]? = nil) async throws -> [String: Any] {
        let url = URL(string: path, relativeTo: base)!.absoluteURL
        var request = URLRequest(url: url)
        request.httpMethod = body == nil ? "GET" : "POST"
        if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let reason = String(data: data, encoding: .utf8) ?? ""
            throw PeerError.message("信令服务 \(status)：\(reason.prefix(160))")
        }
        return (try JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }
}

/// Serializes sends and preserves the same message ID across network retries.
final class PeerMailbox {
    let api: PeerAPI
    let id: String
    let token: String
    var onSignal: ((PeerSignal) -> Void)?
    var onError: ((String) -> Void)?
    private var pollTask: Task<Void, Never>?
    private var sends: Task<Void, Never>?
    private var stopped = false

    init(api: PeerAPI, id: String, token: String) { self.api = api; self.id = id; self.token = token }

    func start() {
        pollTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var cursor = 0
            var failures = 0
            while !Task.isCancelled && !stopped {
                do {
                    let result = try await api.request("/v1/sessions/\(id)/signals?after=\(cursor)", token: token)
                    failures = 0
                    for item in result["events"] as? [[String: Any]] ?? [] {
                        guard let seq = item["seq"] as? Int, seq > cursor, let type = item["type"] as? String else { continue }
                        onSignal?(PeerSignal(seq: seq, type: type, data: item["data"] as? [String: Any] ?? [:]))
                        cursor = seq
                    }
                    if result["closed"] as? Bool == true { return }
                } catch {
                    if Task.isCancelled || stopped { return }
                    failures += 1
                    if failures >= 3 { onError?(error.localizedDescription); return }
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
        }
    }

    func send(_ type: String, _ data: [String: Any] = [:]) {
        guard !stopped else { return }
        let previous = sends
        sends = Task { @MainActor [weak self] in
            await previous?.value
            guard let self, !stopped else { return }
            let body: [String: Any] = ["type": type, "data": data, "message_id": UUID().uuidString]
            for attempt in 0..<3 {
                do { _ = try await api.request("/v1/sessions/\(id)/signals", token: token, body: body); return }
                catch {
                    if attempt == 2 { onError?(error.localizedDescription) }
                    else { try? await Task.sleep(nanoseconds: 500_000_000) }
                }
            }
        }
    }

    func stop() { stopped = true; pollTask?.cancel(); sends?.cancel(); onSignal = nil }
}

/// ICE tries native IPv6/IPv4 candidates first. Overlay candidates are released
/// after a grace interval; Tailscale must already be installed and connected.
enum PeerNetwork {
    static let stun = ["stun:stun.cloudflare.com:3478", "stun:stun.l.google.com:19302"]
    static func isOverlay(_ candidate: String) -> Bool {
        let fields = candidate.split(separator: " ")
        guard fields.count > 4 else { return false }
        let ip = fields[4].lowercased()
        if ip.hasPrefix("fd7a:115c:a1e0:") { return true }
        let bytes = ip.split(separator: ".").compactMap { Int($0) }
        return bytes.count == 4 && bytes[0] == 100 && (64...127).contains(bytes[1])
    }
}
