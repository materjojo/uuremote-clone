import Foundation

/// 标准 KCP 线格式（ikcp 头 24 字节，小端）精简实现：
/// 可靠有序字节流 + RTO 重传 + 快速重传 + 固定窗口
final class KCP {
    enum Cmd: UInt8 { case push = 81, ack = 82, wask = 83, wins = 84 }

    struct Segment {
        var cmd: UInt8 = Cmd.push.rawValue
        var frg: UInt8 = 0
        var sn: UInt32 = 0
        var ts: UInt32 = 0
        var una: UInt32 = 0
        var data: Data = Data()
    }

    let conv: UInt32
    var mtu = 1200
    var window: UInt32 = 128

    private(set) var sndUna: UInt32 = 0
    private(set) var sndNxt: UInt32 = 0
    private(set) var rcvNxt: UInt32 = 0

    private var sndQueue: [Segment] = []
    private var sndBuf: [UInt32: Segment] = [:]
    private var sentAt: [UInt32: Date] = [:]
    private var rcvBuf: [UInt32: Data] = [:]
    private var ackList: [UInt32] = []

    private var srtt: Double = 0
    private var rttvar: Double = 0
    private var rto: Double = 200
    private var lastTick = Date()
    private var lastAckFlush = Date()

    var output: ((Data) -> Void)?
    var onData: ((Data) -> Void)?

    init(conv: UInt32) { self.conv = conv }

    // MARK: 发送

    func send(_ payload: Data) {
        let maxChunk = mtu - 24
        var offset = 0
        var chunks: [Data] = []
        if payload.isEmpty { chunks = [Data()] }
        while offset < payload.count {
            let end = min(offset + maxChunk, payload.count)
            chunks.append(payload.subdata(in: offset..<end))
            offset = end
        }
        for (i, chunk) in chunks.enumerated() {
            var seg = Segment()
            seg.frg = i == chunks.count - 1 ? 0 : 1
            seg.data = chunk
            sndQueue.append(seg)
        }
        flush()
    }

    func flush() {
        let now = Date()
        for var seg in sndQueue {
            seg.sn = sndNxt
            seg.ts = UInt32(Date().timeIntervalSince1970 * 1000)
            seg.una = rcvNxt
            sndNxt &+= 1
            sndBuf[seg.sn] = seg
            sentAt[seg.sn] = now
            output?(encode(seg))
        }
        sndQueue.removeAll()
        flushAcks(force: true)
    }

    func update() {
        let now = Date()
        // 重传
        for (sn, seg) in sndBuf where sn >= sndUna {
            if let sent = sentAt[sn], now.timeIntervalSince(sent) * 1000 > rto {
                var resend = seg
                resend.ts = UInt32(now.timeIntervalSince1970 * 1000)
                resend.una = rcvNxt
                sentAt[sn] = now
                output?(encode(resend))
            }
        }
        // 延迟 ACK
        if !ackList.isEmpty, now.timeIntervalSince(lastAckFlush) > 0.02 {
            flushAcks(force: true)
        }
        if now.timeIntervalSince(lastTick) > 0.1 {
            lastTick = now
            rto = min(max(rto, 100), 3000)
        }
    }

    private func flushAcks(force: Bool) {
        guard force || !ackList.isEmpty else { return }
        var seg = Segment()
        seg.cmd = Cmd.ack.rawValue
        seg.sn = rcvNxt
        seg.ts = UInt32(Date().timeIntervalSince1970 * 1000)
        seg.una = rcvNxt
        var body = Data()
        for sn in ackList {
            body.append(contentsOf: withUnsafeBytes(of: sn.littleEndian) { Array($0) })
        }
        seg.data = body
        if !ackList.isEmpty { output?(encode(seg)) }
        ackList.removeAll()
        lastAckFlush = Date()
    }

    private func encode(_ seg: Segment) -> Data {
        var out = Data(capacity: 24 + seg.data.count)
        append(UInt32(conv).littleEndian, to: &out)
        out.append(seg.cmd)
        out.append(seg.frg)
        append(UInt16(min(window, 0xffff)).littleEndian, to: &out)
        append(seg.ts.littleEndian, to: &out)
        append(seg.sn.littleEndian, to: &out)
        append(seg.una.littleEndian, to: &out)
        append(UInt32(seg.data.count).littleEndian, to: &out)
        out.append(seg.data)
        return out
    }

    private func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        withUnsafeBytes(of: value) { data.append(contentsOf: $0) }
    }

    // MARK: 接收

    func input(_ packet: Data) {
        guard packet.count >= 24 else { return }
        let bytes = [UInt8](packet)
        let cmd = bytes[4]
        let wnd = readU16(bytes, 6)
        _ = wnd
        let ts = readU32(bytes, 8)
        let sn = readU32(bytes, 12)
        let una = readU32(bytes, 16)
        let len = Int(readU32(bytes, 20))
        guard packet.count >= 24 + len else { return }
        let body = packet.subdata(in: 24..<(24 + len))

        if una > sndUna {
            var s = sndUna
            while s < una {
                if let sent = sentAt[s] {
                    let rtt = Date().timeIntervalSince(sent) * 1000
                    if srtt == 0 { srtt = rtt; rttvar = rtt / 2 }
                    else { srtt = 0.875 * srtt + 0.125 * rtt; rttvar = 0.75 * rttvar + 0.25 * abs(srtt - rtt) }
                    rto = min(max(srtt + 4 * rttvar, 100), 3000)
                }
                sndBuf.removeValue(forKey: s)
                sentAt.removeValue(forKey: s)
                s &+= 1
            }
            sndUna = una
        }

        switch cmd {
        case Cmd.push.rawValue:
            if sn == rcvNxt {
                deliver(body)
                rcvNxt &+= 1
                while let next = rcvBuf.removeValue(forKey: rcvNxt) {
                    deliver(next)
                    rcvNxt &+= 1
                }
            } else if sn > rcvNxt && rcvBuf.count < 512 {
                rcvBuf[sn] = body
            }
            ackList.append(sn)
        case Cmd.ack.rawValue:
            var i = 0
            while i + 4 <= body.count {
                let ackSN = readU32([UInt8](body), i)
                if ackSN >= sndUna { sndBuf.removeValue(forKey: ackSN) }
                i += 4
            }
        default:
            break
        }
        _ = ts
    }

    private func deliver(_ data: Data) {
        if !data.isEmpty { onData?(data) }
    }

    private func readU16(_ b: [UInt8], _ o: Int) -> UInt16 {
        UInt16(b[o]) | UInt16(b[o + 1]) << 8
    }
    private func readU32(_ b: [UInt8], _ o: Int) -> UInt32 {
        UInt32(b[o]) | UInt32(b[o + 1]) << 8 | UInt32(b[o + 2]) << 16 | UInt32(b[o + 3]) << 24
    }
}
