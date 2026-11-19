import AppKit

/// 剪贴板同步（官方协议 ClipboardChange，信封 field 17）。
/// 发送：NSPasteboard changeCount 变化 -> 读取文本 -> ClipboardChange(TEXT)
/// 接收：写回 NSPasteboard（避免回环：记录最近写入的内容）
final class ClipboardManager {
    /// 编码一条 ClipboardChange 消息（完整 gv_pb.Message 信封）
    static func encodeChange(contentId: UInt32, text: String, seq: inout Int64) -> Data {
        var w = ProtoWriter()
        w.int32(1, field: 1)                      // Type = TEXT
        w.string(text, field: 2)                   // content
        // to_be_continued = false（proto3 默认，省略）
        let payload = w.data

        var env = ProtoWriter()
        env.int64(seq, field: 1)
        env.int64(Int64(Date().timeIntervalSince1970 * 1000), field: 2)
        env.message(payload, field: 17)            // clipboard_change
        return env.data
    }

    private var lastSentChangeCount: Int = NSPasteboard.general.changeCount
    private var lastReceivedText: String?
    private var lastSentText: String?

    /// 轮询本地剪贴板，若有新文本则返回编码好的消息
    func pollAndEncode(seq: inout Int64) -> Data? {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastSentChangeCount else { return nil }
        lastSentChangeCount = pb.changeCount
        guard let text = pb.string(forType: .string), !text.isEmpty else { return nil }
        if text == lastReceivedText || text == lastSentText { return nil }
        lastSentText = text
        var s: Int64 = seq
        let data = Self.encodeChange(contentId: UInt32(truncatingIfNeeded: s), text: text, seq: &s)
        seq = s + 1
        return data
    }

    /// 收到对端 ClipboardChange：解析并写回本地剪贴板
    static func decodeAndApply(_ payload: Data, onPasteboard: (String) -> Void) -> String? {
        var r = ProtoReader(payload)
        var text: String?
        while let (field, wire) = try? r.nextField() {
            switch field {
            case 2: text = try? r.readString()
            default: try? r.skip(wire)
            }
        }
        guard let t = text, !t.isEmpty else { return nil }
        onPasteboard(t)
        return t
    }

    func markReceived(_ text: String) {
        lastReceivedText = text
        lastSentChangeCount = NSPasteboard.general.changeCount
    }
}
