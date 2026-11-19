import Foundation

/// GF(256) + 系统化 Reed-Solomon（k 数据片 + m 校验片）
enum GF256 {
    static let expTable: [UInt8] = {
        var table = [UInt8](repeating: 0, count: 512)
        var x: UInt16 = 1
        for i in 0..<255 {
            table[i] = UInt8(x)
            x <<= 1
            if x & 0x100 != 0 { x ^= 0x11d }
        }
        for i in 255..<512 { table[i] = table[i - 255] }
        return table
    }()

    static let logTable: [UInt8] = {
        var table = [UInt8](repeating: 0, count: 256)
        var x: UInt16 = 1
        for i in 0..<255 {
            table[Int(x)] = UInt8(i)
            x <<= 1
            if x & 0x100 != 0 { x ^= 0x11d }
        }
        return table
    }()

    static func mul(_ a: UInt8, _ b: UInt8) -> UInt8 {
        guard a != 0, b != 0 else { return 0 }
        let sum = Int(logTable[Int(a)]) + Int(logTable[Int(b)])
        return expTable[sum % 255]
    }

    static func div(_ a: UInt8, _ b: UInt8) -> UInt8 {
        guard a != 0 else { return 0 }
        guard b != 0 else { return 0 }
        let diff = Int(logTable[Int(a)]) - Int(logTable[Int(b)]) + 255
        return expTable[diff % 255]
    }

    static func pow(_ base: UInt8, _ exponent: Int) -> UInt8 {
        guard exponent > 0 else { return 1 }
        var result: UInt8 = 1
        for _ in 0..<exponent { result = mul(result, base) }
        return result
    }
}

enum RSEngine {
    /// 返回 m 个校验片
    static func encode(data: [Data], parity: Int) -> [Data] {
        guard !data.isEmpty, parity > 0 else { return [] }
        let k = data.count
        let shardSize = data.map { $0.count }.max() ?? 0
        let padded = data.map { d -> [UInt8] in
            var b = [UInt8](d); b.append(contentsOf: [UInt8](repeating: 0, count: shardSize - b.count)); return b
        }
        var result: [Data] = []
        for p in 0..<parity {
            var out = [UInt8](repeating: 0, count: shardSize)
            for j in 0..<k {
                let coef = GF256.pow(UInt8(j + 1), p)
                if coef == 0 { continue }
                for i in 0..<shardSize {
                    out[i] ^= GF256.mul(padded[j][i], coef)
                }
            }
            result.append(Data(out))
        }
        return result
    }

    /// 从任意 >= k 个碎片恢复全部数据片；返回按序数据
    static func decode(received: [Int: Data], k: Int, parity: Int) -> [Data]? {
        guard received.count >= k else { return nil }
        let shardSize = received.values.map { $0.count }.max() ?? 0
        let indices = received.keys.sorted().prefix(k)
        let rows = indices.map { index -> [UInt8] in
            if index < k {
                var row = [UInt8](repeating: 0, count: k); row[index] = 1; return row
            } else {
                let p = index - k
                return (0..<k).map { GF256.pow(UInt8($0 + 1), p) }
            }
        }
        guard let inverse = invert(rows) else { return nil }
        let shards = indices.map { received[$0] ?? Data() }.map { d -> [UInt8] in
            var b = [UInt8](d); b.append(contentsOf: [UInt8](repeating: 0, count: shardSize - b.count)); return b
        }
        var out: [Data] = []
        for i in 0..<k {
            var row = [UInt8](repeating: 0, count: shardSize)
            for j in 0..<k {
                let coef = inverse[i][j]
                if coef == 0 { continue }
                for x in 0..<shardSize { row[x] ^= GF256.mul(shards[j][x], coef) }
            }
            out.append(Data(row))
        }
        return out
    }

    private static func invert(_ matrix: [[UInt8]]) -> [[UInt8]]? {
        let n = matrix.count
        var a = matrix
        var inv = (0..<n).map { i -> [UInt8] in
            var row = [UInt8](repeating: 0, count: n); row[i] = 1; return row
        }
        for col in 0..<n {
            var pivot = -1
            for r in col..<n where a[r][col] != 0 { pivot = r; break }
            guard pivot >= 0 else { return nil }
            if pivot != col { a.swapAt(pivot, col); inv.swapAt(pivot, col) }
            let pv = a[col][col]
            let invPv = GF256.div(1, pv)
            for c in 0..<n { a[col][c] = GF256.mul(a[col][c], invPv); inv[col][c] = GF256.mul(inv[col][c], invPv) }
            for r in 0..<n where r != col {
                let factor = a[r][col]
                if factor == 0 { continue }
                for c in 0..<n {
                    a[r][c] ^= GF256.mul(a[col][c], factor)
                    inv[r][c] ^= GF256.mul(inv[col][c], factor)
                }
            }
        }
        return inv
    }
}
