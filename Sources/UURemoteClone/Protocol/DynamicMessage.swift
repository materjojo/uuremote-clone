import Foundation

/// 通用 protobuf 消息：保留任意 wire type 与重复字段，
/// 可无损读写 gv_pb 全部 160 条消息（字段名见 GvSchema）
public struct DynamicMessage {
    public enum Value {
        case varint(UInt64)
        case fixed64(UInt64)
        case bytes(Data)
        case fixed32(UInt32)
    }

    public private(set) var storage: [Int: [Value]] = [:]

    public init() {}

    // MARK: 写入

    public mutating func add(_ value: Value, field: Int) {
        storage[field, default: []].append(value)
    }

    public mutating func setInt(_ value: Int64, field: Int) {
        storage[field] = [.varint(UInt64(bitPattern: value))]
    }

    public mutating func setUInt(_ value: UInt64, field: Int) {
        storage[field] = [.varint(value)]
    }

    public mutating func setBool(_ value: Bool, field: Int) {
        storage[field] = [.varint(value ? 1 : 0)]
    }

    public mutating func setString(_ value: String, field: Int) {
        storage[field] = [.bytes(Data(value.utf8))]
    }

    public mutating func setBytes(_ value: Data, field: Int) {
        storage[field] = [.bytes(value)]
    }

    public mutating func setMessage(_ value: DynamicMessage, field: Int) {
        storage[field] = [.bytes(value.encode())]
    }

    public mutating func setFloat(_ value: Float, field: Int) {
        storage[field] = [.fixed32(value.bitPattern)]
    }

    public mutating func setDouble(_ value: Double, field: Int) {
        storage[field] = [.fixed64(value.bitPattern)]
    }

    // MARK: 读取

    public func all(_ field: Int) -> [Value] { storage[field] ?? [] }
    public func first(_ field: Int) -> Value? { storage[field]?.first }

    public func int(_ field: Int) -> Int64? {
        guard case .varint(let v)? = first(field) else { return nil }
        return Int64(bitPattern: v)
    }

    public func uint(_ field: Int) -> UInt64? {
        guard case .varint(let v)? = first(field) else { return nil }
        return v
    }

    public func bool(_ field: Int) -> Bool? {
        guard case .varint(let v)? = first(field) else { return nil }
        return v != 0
    }

    public func string(_ field: Int) -> String? {
        guard case .bytes(let d)? = first(field) else { return nil }
        return String(data: d, encoding: .utf8)
    }

    public func data(_ field: Int) -> Data? {
        guard case .bytes(let d)? = first(field) else { return nil }
        return d
    }

    public func message(_ field: Int) -> DynamicMessage? {
        guard case .bytes(let d)? = first(field) else { return nil }
        return DynamicMessage.decode(d)
    }

    public func float(_ field: Int) -> Float? {
        guard case .fixed32(let v)? = first(field) else { return nil }
        return Float(bitPattern: v)
    }

    public func double(_ field: Int) -> Double? {
        guard case .fixed64(let v)? = first(field) else { return nil }
        return Double(bitPattern: v)
    }

    // MARK: 编解码

    public static func decode(_ data: Data) -> DynamicMessage {
        var message = DynamicMessage()
        var reader = ProtoReader(data)
        while let (field, wire) = try? reader.nextField() {
            switch wire {
            case 0:
                if let v = try? reader.readVarint() { message.add(.varint(v), field: field) }
            case 1:
                if let v = try? reader.readDouble() { message.add(.fixed64(v.bitPattern), field: field) }
            case 2:
                if let v = try? reader.readBytes() { message.add(.bytes(v), field: field) }
            case 5:
                if let v = try? reader.readFloat() { message.add(.fixed32(v.bitPattern), field: field) }
            default:
                try? reader.skip(wire)
            }
        }
        return message
    }

    public func encode() -> Data {
        var writer = ProtoWriter()
        for field in storage.keys.sorted() {
            guard let values = storage[field] else { continue }
            for value in values {
                switch value {
                case .varint(let v):
                    writer.rawVarint(field: field, value: v)
                case .fixed64(let v):
                    writer.rawFixed64(field: field, value: v)
                case .bytes(let d):
                    writer.rawBytes(field: field, value: d)
                case .fixed32(let v):
                    writer.rawFixed32(field: field, value: v)
                }
            }
        }
        return writer.data
    }

    // MARK: 调试

    public func json(schema message: String) -> [String: Any] {
        var out: [String: Any] = [:]
        for (field, values) in storage {
            let key = GvSchema.name(message, field) ?? String(field)
            let converted: Any
            if values.count == 1, let v = values.first {
                converted = Self.jsonValue(v)
            } else {
                converted = values.map { Self.jsonValue($0) }
            }
            out[key] = converted
        }
        return out
    }

    private static func jsonValue(_ value: Value) -> Any {
        switch value {
        case .varint(let v): return v
        case .fixed64(let v): return v
        case .fixed32(let v): return v
        case .bytes(let d):
            return String(data: d, encoding: .utf8) ?? d.base64EncodedString()
        }
    }
}

