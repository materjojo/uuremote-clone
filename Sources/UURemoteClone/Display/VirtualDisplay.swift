import Foundation
import AppKit
import CoreGraphics
import CoreVideo
import ScreenCaptureKit
import AVFoundation

/// 通过私有 CGVirtualDisplay 系列类创建虚拟屏（与官方"自动创建虚拟屏"同源）
final class VirtualDisplayController {
    private var display: AnyObject?
    private(set) var displayID: CGDirectDisplayID = 0
    private(set) var size = CGSize.zero

    private static let msgSend: UnsafeMutableRawPointer? = {
        dlopen(nil, RTLD_LAZY)
        return dlsym(UnsafeMutableRawPointer(bitPattern: -2), "objc_msgSend")
    }()

    var isActive: Bool { display != nil }

    @discardableResult
    func create(width: Int, height: Int, refresh: Double = 60, name: String = "UU Remote Virtual Display") -> CGDirectDisplayID? {
        guard let descriptorClass = NSClassFromString("CGVirtualDisplayDescriptor") as? NSObject.Type,
              let displayClass = NSClassFromString("CGVirtualDisplay") as? NSObject.Type,
              let settingsClass = NSClassFromString("CGVirtualDisplaySettings") as? NSObject.Type,
              let modeClass = NSClassFromString("CGVirtualDisplayMode") as? NSObject.Type else {
            return nil
        }

        let descriptor = descriptorClass.init()
        descriptor.setValue(name, forKey: "name")
        descriptor.setValue(width, forKey: "maxPixelsWide")
        descriptor.setValue(height, forKey: "maxPixelsHigh")
        descriptor.setValue(NSValue(size: NSSize(width: width, height: height)), forKey: "sizeInMillimeters")
        descriptor.setValue(0x5555, forKey: "serialNum")
        descriptor.setValue(0x1234, forKey: "productID")
        descriptor.setValue(0x4321, forKey: "vendorID")
        _ = descriptor.perform(NSSelectorFromString("setDispatchQueue:"), with: DispatchQueue.main)

        typealias InitWithDescriptor = @convention(c) (AnyObject, Selector, AnyObject) -> AnyObject
        guard let sym = Self.msgSend else { return nil }
        let initWithDescriptor = unsafeBitCast(sym, to: InitWithDescriptor.self)
        let display = initWithDescriptor(displayClass as AnyObject, NSSelectorFromString("initWithDescriptor:"), descriptor)

        typealias InitMode = @convention(c) (AnyObject, Selector, Int32, Int32, Double) -> AnyObject
        let initWithMode = unsafeBitCast(sym, to: InitMode.self)
        let mode = initWithMode(modeClass as AnyObject, NSSelectorFromString("initWithWidth:height:refreshRate:"),
                                Int32(width), Int32(height), refresh)

        let settings = settingsClass.init()
        settings.setValue(true, forKey: "hiDPI")
        settings.setValue([mode], forKey: "modes")

        typealias Apply = @convention(c) (AnyObject, Selector, AnyObject) -> Bool
        let apply = unsafeBitCast(sym, to: Apply.self)
        _ = apply(display, NSSelectorFromString("applySettings:"), settings)

        let idNumber = display.value(forKey: "displayID") as? NSNumber
        guard let id = idNumber?.uint32Value, id != 0 else { return nil }
        self.display = display
        self.displayID = CGDirectDisplayID(id)
        self.size = CGSize(width: width, height: height)
        return self.displayID
    }

    func destroy() {
        display = nil
        displayID = 0
        size = .zero
    }

    /// 在 SCK 的显示器列表中查找该虚拟屏
    func shareableDisplay() async -> SCDisplay? {
        guard displayID != 0,
              let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) else {
            return nil
        }
        return content.displays.first { $0.displayID == displayID }
    }
}

/// 虚拟屏在 SCK 中不可见时的回退采集（CGDisplayStream）
final class CGDisplayStreamCapturer {
    private var stream: CGDisplayStream?
    private let queue = DispatchQueue(label: "com.uuremote.cgdisplay", qos: .userInteractive)

    func start(displayID: CGDirectDisplayID, width: Int, height: Int, fps: Int,
               onBuffer: @escaping (CVPixelBuffer) -> Void) -> Bool {
        // 常量在部分 SDK 中不再导出，直接使用其字符串值
        var config: [String: Any] = [
            "FrameRate": fps,
            "PreserveAspectRatio": true,
            "ShowCursor": true
        ]
        config["MinimumFrameTime"] = Double(fps)
        guard let stream = CGDisplayStream(dispatchQueueDisplay: displayID,
                                           outputWidth: width, outputHeight: height,
                                           pixelFormat: Int32(kCVPixelFormatType_32BGRA),
                                           properties: config as CFDictionary,
                                           queue: queue,
                                           handler: { _, _, surface, _ in
            guard let surface else { return }
            var out: Unmanaged<CVPixelBuffer>?
            CVPixelBufferCreateWithIOSurface(kCFAllocatorDefault, surface, nil, &out)
            if let pb = out?.takeRetainedValue() { onBuffer(pb) }
        }) else { return false }
        self.stream = stream
        return stream.start() == .success
    }

    func stop() {
        stream?.stop()
        stream = nil
    }
}

enum PrivateScreenMode: Int, CaseIterable {
    case off = 0
    case normal = 1     // 仅创建虚拟屏，内容只出现在虚拟屏
    case enhanced = 2   // 额外尝试隐藏物理屏（依赖私有 CGS 接口，失败自动降级）
}
