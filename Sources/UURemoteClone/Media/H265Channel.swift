import Foundation
import WebRTC

/// H.265 帧分片通道（DataChannel 上自定义分片，不依赖 WebRTC 的 H265 RTP 支持）
final class H265Channel {
    static let label = "VIDEO_DATA_CHANNEL"
    private static let magic: UInt8 = 0x48
    private static let headerSize = 12
    private static let fragment = 1000

    private let channel: RTCDataChannel
    private var frameID: UInt32 = 0
    private var pending: [UInt32: (count: Int, parts: [Int: Data], key: Bool)] = [:]
    private var lastCleanup = Date()

    var onFrame: ((Data, Bool) -> Void)?
    var onKeyframeRequest: (() -> Void)?

    init(channel: RTCDataChannel) {
        self.channel = channel
    }

    func send(annex: Data, key: Bool) {
        frameID &+= 1
        let id = frameID
        let total = max(1, (annex.count + Self.fragment - 1) / Self.fragment)
        for index in 0..<total {
            let start = index * Self.fragment
            let end = min(start + Self.fragment, annex.count)
            let payload = annex.subdata(in: start..<end)
            var packet = Data(capacity: Self.headerSize + payload.count)
            packet.append(Self.magic)
            packet.append(key ? 0x01 : 0x00)
            packet.append(contentsOf: withUnsafeBytes(of: id.bigEndian) { Array($0) })
            packet.append(contentsOf: withUnsafeBytes(of: UInt16(index).bigEndian) { Array($0) })
            packet.append(contentsOf: withUnsafeBytes(of: UInt16(total).bigEndian) { Array($0) })
            packet.append(contentsOf: withUnsafeBytes(of: UInt16(payload.count).bigEndian) { Array($0) })
            packet.append(payload)
            _ = channel.sendData(RTCDataBuffer(data: packet, isBinary: true))
        }
    }

    func requestKeyframe() {
        var packet = Data([Self.magic, 0x02, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
        packet[2] = 0
        _ = channel.sendData(RTCDataBuffer(data: packet, isBinary: true))
    }

    func receive(_ data: Data) {
        guard data.count >= Self.headerSize, data[0] == Self.magic else { return }
        let flags = data[1]
        if flags & 0x02 != 0 { onKeyframeRequest?(); return }

        let bytes = [UInt8](data)
        let id = UInt32(bytes[2]) << 24 | UInt32(bytes[3]) << 16 | UInt32(bytes[4]) << 8 | UInt32(bytes[5])
        let index = Int(bytes[6]) << 8 | Int(bytes[7])
        let total = Int(bytes[8]) << 8 | Int(bytes[9])
        let length = Int(bytes[10]) << 8 | Int(bytes[11])
        guard total > 0, index < total, data.count >= Self.headerSize + length else { return }

        var entry = pending[id] ?? (count: total, parts: [:], key: flags & 0x01 != 0)
        entry.parts[index] = data.subdata(in: Self.headerSize..<(Self.headerSize + length))
        pending[id] = entry

        if entry.parts.count == total {
            var annex = Data()
            for i in 0..<total { annex.append(entry.parts[i] ?? Data()) }
            pending.removeValue(forKey: id)
            onFrame?(annex, entry.key)
        }

        if Date().timeIntervalSince(lastCleanup) > 1.0 {
            lastCleanup = Date()
            pending = pending.filter { $0.key > id &- 8 }
        }
    }
}
