import Foundation

/// 最小 protobuf 线格式实现（与官方 gv_pb 编码兼容）
public struct ProtoWriter {
    public private(set) var data = Data()
    public init() {}

    private mutating func tag(_ field: Int, _ wire: UInt8) {
        varint(UInt64(field) << 3 | UInt64(wire))
    }

    public mutating func varint(_ value: UInt64) {
        var v = value
        repeat {
            var byte = UInt8(v & 0x7f)
            v >>= 7
            if v != 0 { byte |= 0x80 }
            data.append(byte)
        } while v != 0
    }

    public mutating func int32(_ value: Int32, field: Int) {
        guard value != 0 else { return }
        tag(field, 0)
        varint(UInt64(bitPattern: Int64(value)))
    }

    public mutating func int64(_ value: Int64, field: Int) {
        guard value != 0 else { return }
        tag(field, 0)
        varint(UInt64(bitPattern: value))
    }

    public mutating func bool(_ value: Bool, field: Int) {
        guard value else { return }
        tag(field, 0)
        varint(1)
    }

    public mutating func float(_ value: Float, field: Int) {
        guard value != 0 else { return }
        tag(field, 5)
        var bits = value.bitPattern.littleEndian
        withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
    }

    public mutating func double(_ value: Double, field: Int) {
        guard value != 0 else { return }
        tag(field, 1)
        var bits = value.bitPattern.littleEndian
        withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
    }

    public mutating func string(_ value: String, field: Int) {
        guard !value.isEmpty else { return }
        let bytes = Array(value.utf8)
        tag(field, 2)
        varint(UInt64(bytes.count))
        data.append(contentsOf: bytes)
    }

    public mutating func bytes(_ value: Data, field: Int) {
        guard !value.isEmpty else { return }
        tag(field, 2)
        varint(UInt64(value.count))
        data.append(value)
    }

    public mutating func message(_ value: Data, field: Int) {
        tag(field, 2)
        varint(UInt64(value.count))
        data.append(value)
    }
}

public enum ProtoError: Error { case truncated, badWireType, badUTF8 }

public struct ProtoReader {
    private let bytes: [UInt8]
    private var index = 0

    public init(_ data: Data) { bytes = [UInt8](data) }
    public var isAtEnd: Bool { index >= bytes.count }

    public mutating func readVarint() throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            result |= UInt64(byte & 0x7f) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
            if shift > 63 { throw ProtoError.badWireType }
        }
        throw ProtoError.truncated
    }

    public mutating func nextField() throws -> (field: Int, wire: Int)? {
        if isAtEnd { return nil }
        let key = try readVarint()
        return (Int(key >> 3), Int(key & 0x7))
    }

    public mutating func readInt32() throws -> Int32 { Int32(truncatingIfNeeded: try readVarint()) }
    public mutating func readInt64() throws -> Int64 { Int64(bitPattern: try readVarint()) }
    public mutating func readBool() throws -> Bool { try readVarint() != 0 }

    public mutating func readFloat() throws -> Float {
        guard index + 4 <= bytes.count else { throw ProtoError.truncated }
        var bits: UInt32 = 0
        for i in 0..<4 { bits |= UInt32(bytes[index + i]) << (8 * UInt32(i)) }
        index += 4
        return Float(bitPattern: bits)
    }

    public mutating func readDouble() throws -> Double {
        guard index + 8 <= bytes.count else { throw ProtoError.truncated }
        var bits: UInt64 = 0
        for i in 0..<8 { bits |= UInt64(bytes[index + i]) << (8 * UInt64(i)) }
        index += 8
        return Double(bitPattern: bits)
    }

    public mutating func readBytes() throws -> Data {
        let length = Int(try readVarint())
        guard index + length <= bytes.count else { throw ProtoError.truncated }
        let d = Data(bytes[index..<(index + length)])
        index += length
        return d
    }

    public mutating func readString() throws -> String {
        let d = try readBytes()
        guard let s = String(data: d, encoding: .utf8) else { throw ProtoError.badUTF8 }
        return s
    }

    public mutating func skip(_ wire: Int) throws {
        switch wire {
        case 0: _ = try readVarint()
        case 1: index += 8
        case 2: _ = try readBytes()
        case 5: index += 4
        default: throw ProtoError.badWireType
        }
        if index > bytes.count { throw ProtoError.truncated }
    }
}
