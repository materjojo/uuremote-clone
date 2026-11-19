import Foundation
import WebRTC

/// KCP + RS-FEC 可靠通道，承载 gv_pb 控制消息
/// 线格式：DataChannel -> [FEC 组包] -> [KCP 段] -> [长度前缀消息]
final class ReliableChannel {
    private static let fecMagic: UInt8 = 0xF2
    private let channel: RTCDataChannel
    private let kcp: KCP
    private let k: Int
    private let m: Int

    private var fecGroup: [Data] = []
    private var fecID: UInt32 = 0
    private var lastFECFlush = Date()
    private var rxGroups: [UInt32: [Int: Data]] = [:]
    private var rxGroupMeta: [UInt32: (k: Int, m: Int)] = [:]
    private var rxStream = Data()
    private var rxExpected = -1

    var onMessage: ((Data) -> Void)?

    init(channel: RTCDataChannel, k: Int = 8, m: Int = 2) {
        self.channel = channel
        self.k = k
        self.m = m
        self.kcp = KCP(conv: 0x4E5252)
        kcp.output = { [weak self] packet in self?.fecSend(packet) }
        kcp.onData = { [weak self] chunk in self?.appendStream(chunk) }
        channel.delegate = nil
    }

    // MARK: 上层

    func send(_ message: Data) {
        var framed = Data()
        var length = UInt32(message.count).bigEndian
        withUnsafeBytes(of: &length) { framed.append(contentsOf: $0) }
        framed.append(message)
        kcp.send(framed)
    }

    func tick() {
        kcp.update()
        if !fecGroup.isEmpty, Date().timeIntervalSince(lastFECFlush) > 0.03 {
            flushFEC()
        }
    }

    func receive(_ data: Data) {
        fecReceive(data)
    }

    // MARK: 流重组

    private func appendStream(_ chunk: Data) {
        rxStream.append(chunk)
        if rxExpected < 0, rxStream.count >= 4 {
            let b = [UInt8](rxStream.prefix(4))
            rxExpected = Int(UInt32(b[0]) << 24 | UInt32(b[1]) << 16 | UInt32(b[2]) << 8 | UInt32(b[3]))
            rxStream.removeFirst(4)
        }
        if rxExpected >= 0, rxStream.count >= rxExpected {
            let message = rxStream.prefix(rxExpected)
            rxStream.removeFirst(rxExpected)
            rxExpected = -1
            onMessage?(Data(message))
        }
    }

    // MARK: FEC

    private func fecSend(_ packet: Data) {
        var withLength = Data()
        var len = UInt16(min(packet.count, 0xffff)).bigEndian
        withUnsafeBytes(of: &len) { withLength.append(contentsOf: $0) }
        withLength.append(packet)
        fecGroup.append(withLength)
        if fecGroup.count == k { flushFEC() }
        lastFECFlush = Date()
    }

    private func flushFEC() {
        guard !fecGroup.isEmpty else { return }
        let group = fecGroup
        fecGroup.removeAll()
        let parity = RSEngine.encode(data: group, parity: m)
        let all = group + parity
        for (index, shard) in all.enumerated() {
            transmit(groupID: fecID, index: index, k: k, m: m, payload: shard)
        }
        fecID &+= 1
    }

    private func transmit(groupID: UInt32, index: Int, k: Int, m: Int, payload: Data) {
        var packet = Data(capacity: 12 + payload.count)
        packet.append(Self.fecMagic)
        packet.append(UInt8(index))
        packet.append(UInt8(k))
        packet.append(UInt8(m))
        withUnsafeBytes(of: groupID.bigEndian) { packet.append(contentsOf: $0) }
        var len = UInt16(payload.count).bigEndian
        withUnsafeBytes(of: &len) { packet.append(contentsOf: $0) }
        packet.append(payload)
        _ = channel.sendData(RTCDataBuffer(data: packet, isBinary: true))
    }

    private func fecReceive(_ data: Data) {
        guard data.count >= 12, data[0] == Self.fecMagic else { return }
        let bytes = [UInt8](data)
        let index = Int(bytes[1])
        let k = Int(bytes[2])
        let m = Int(bytes[3])
        let group = UInt32(bytes[4]) << 24 | UInt32(bytes[5]) << 16 | UInt32(bytes[6]) << 8 | UInt32(bytes[7])
        let len = Int(bytes[8]) << 8 | Int(bytes[9])
        guard data.count >= 12 + len else { return }
        let payload = data.subdata(in: 12..<(12 + len))

        var groupMap = rxGroups[group] ?? [:]
        groupMap[index] = payload
        rxGroups[group] = groupMap
        rxGroupMeta[group] = (k, m)

        guard groupMap.count >= k, let shards = RSEngine.decode(received: groupMap, k: k, parity: m) else { return }
        rxGroups.removeValue(forKey: group)
        rxGroupMeta.removeValue(forKey: group)
        for shard in shards {
            guard shard.count >= 2 else { continue }
            let b = [UInt8](shard.prefix(2))
            let packetLen = Int(b[0]) << 8 | Int(b[1])
            guard shard.count >= 2 + packetLen else { continue }
            kcp.input(shard.subdata(in: 2..<(2 + packetLen)))
        }
        if rxGroups.count > 64 { rxGroups.removeAll() }
    }
}
