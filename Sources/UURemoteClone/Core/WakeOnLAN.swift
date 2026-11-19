import Foundation
import Darwin

/// Wake-on-LAN：魔术包（6×0xFF + 16×MAC）UDP 广播
enum WakeOnLAN {
    static func parseMAC(_ text: String) -> [UInt8]? {
        let parts = text.split(whereSeparator: { $0 == ":" || $0 == "-" })
        guard parts.count == 6 else { return nil }
        var bytes: [UInt8] = []
        for part in parts {
            guard let value = UInt8(part, radix: 16) else { return nil }
            bytes.append(value)
        }
        return bytes
    }

    static func magicPacket(mac: String) -> Data? {
        guard let bytes = parseMAC(mac) else { return nil }
        var packet = Data(repeating: 0xFF, count: 6)
        for _ in 0..<16 { packet.append(contentsOf: bytes) }
        return packet
    }

    @discardableResult
    static func send(mac: String, broadcast: String = "255.255.255.255", ports: [UInt16] = [9, 7]) -> Bool {
        guard let packet = magicPacket(mac: mac) else { return false }
        var sent = false
        for port in ports {
            if send(packet: packet, host: broadcast, port: port) { sent = true }
        }
        return sent
    }

    private static func send(packet: Data, host: String, port: UInt16) -> Bool {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var enable: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &enable, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        guard inet_pton(AF_INET, host, &addr.sin_addr) == 1 else { return false }

        let result = packet.withUnsafeBytes { raw -> Int in
            guard let base = raw.baseAddress else { return -1 }
            return withUnsafePointer(to: &addr) { ptr -> Int in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    sendto(fd, base, packet.count, 0, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        return result == packet.count
    }
}

struct WakeOnLANInfo: Decodable {
    var mac: String?
    var macAddress: String?
    var ip: String?
    var port: Int?

    enum CodingKeys: String, CodingKey {
        case mac
        case macAddress = "mac_address"
        case ip
        case port
    }

    var usableMAC: String? { mac ?? macAddress }
}
