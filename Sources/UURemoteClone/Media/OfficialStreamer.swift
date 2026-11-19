import Foundation

/// 直调官方 libstreamer.dylib（Ghidra 逆向确认，docs/09-official-api.md）：
///   _ExchangeControllerInterface(callbacks: 18 槽) -> vtable(21 槽)
///   _ExchangeControlledInterface(callbacks: 16 槽) -> vtable(23 槽)
/// 需将官方 libstreamer.dylib 放入 app bundle（@rpath 已与官方主程序一致）。
final class OfficialStreamer {
    static let shared = OfficialStreamer()
    private var handle: UnsafeMutableRawPointer?
    private(set) var controllerVTable: UnsafeMutableRawPointer?
    private(set) var controlledVTable: UnsafeMutableRawPointer?
    private var keepAlive: [Any] = []

    /// 回调函数指针占位类型：官方各回调均为 C 函数指针（参数签名待运行时核对）
    typealias Cb = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void

    func load(dylibName: String = "libstreamer.dylib") -> Bool {
        if handle != nil { return true }
        guard let lib = dlopen(dylibName, RTLD_NOW) else { return false }
        handle = lib
        return true
    }

    /// 获取工厂函数地址；返回 nil 表示未加载或符号缺失
    private func factory(_ symbol: String) -> UnsafeMutableRawPointer? {
        guard let handle else { return nil }
        guard let fn = dlsym(handle, symbol) else { return nil }
        return fn
    }

    /// 控制端：传入 18 槽回调结构体，返回 vtable 指针
    func startController(callbacks: [Cb?]) -> Bool {
        guard callbacks.count == 18, let fn = factory("ExchangeControllerInterface") else { return false }
        typealias Factory = @convention(c) (UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
        let call = unsafeBitCast(fn, to: Factory.self)
        var slots = [UnsafeMutableRawPointer?](repeating: nil, count: 18)
        for (i, cb) in callbacks.enumerated() {
            if let cb {
                let ptr = unsafeBitCast(cb, to: UnsafeMutableRawPointer.self)
                slots[i] = ptr
                keepAlive.append(cb)
            }
        }
        let result = withUnsafeMutableBytes(of: &slots) { raw -> UnsafeMutableRawPointer? in
            call(UnsafeMutableRawPointer(raw.baseAddress!))
        }
        controllerVTable = result
        return result != nil
    }

    /// 被控端：16 槽回调
    func startControlled(callbacks: [Cb?]) -> Bool {
        guard callbacks.count == 16, let fn = factory("ExchangeControlledInterface") else { return false }
        typealias Factory = @convention(c) (UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
        let call = unsafeBitCast(fn, to: Factory.self)
        var slots = [UnsafeMutableRawPointer?](repeating: nil, count: 16)
        for (i, cb) in callbacks.enumerated() {
            if let cb {
                slots[i] = unsafeBitCast(cb, to: UnsafeMutableRawPointer.self)
                keepAlive.append(cb)
            }
        }
        let result = withUnsafeMutableBytes(of: &slots) { raw -> UnsafeMutableRawPointer? in
            call(UnsafeMutableRawPointer(raw.baseAddress!))
        }
        controlledVTable = result
        return result != nil
    }

    /// 按 vtable 槽位调用（槽位语义见 docs/09；参数按运行时核对调整）
    func call(slot: Int, a: UnsafeMutableRawPointer? = nil,
              b: UnsafeMutableRawPointer? = nil,
              c: UnsafeMutableRawPointer? = nil,
              d: UnsafeMutableRawPointer? = nil, controller: Bool = true) {
        guard let vtable = controller ? controllerVTable : controlledVTable else { return }
        let fnPtr = UnsafeMutableRawPointer(bitPattern:
            UInt(bitPattern: vtable) + UInt(slot * MemoryLayout<UnsafeRawPointer>.size))
        guard let fnPtr else { return }
        typealias Method = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?,
                                           UnsafeMutableRawPointer?, UnsafeMutableRawPointer?,
                                           UnsafeMutableRawPointer?) -> Void
        let m = unsafeBitCast(fnPtr, to: Method.self)
        m(vtable, a, b, c, d)
    }
}
