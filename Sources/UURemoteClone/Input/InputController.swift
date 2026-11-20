import SwiftUI
import AppKit
import CoreGraphics

// MARK: - 控制端：把本地事件归一化为 TouchEvent

struct RemoteInputView: NSViewRepresentable {
    var onTouch: (GvTouchEvent) -> Void
    var onScroll: ((Float, Float) -> Void)? = nil
    var remoteSize: CGSize = .zero

    func makeNSView(context: Context) -> InputNSView {
        let v = InputNSView()
        v.onTouch = onTouch
        v.onScroll = onScroll
        v.remoteSize = remoteSize
        return v
    }

    func updateNSView(_ nsView: InputNSView, context: Context) {
        nsView.onTouch = onTouch
        nsView.onScroll = onScroll
        nsView.remoteSize = remoteSize
    }
}

final class InputNSView: NSView {
    var onTouch: ((GvTouchEvent) -> Void)?
    var onScroll: ((Float, Float) -> Void)?
    var remoteSize: CGSize = .zero

    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool { true }

    override func mouseDown(with event: NSEvent) { emit(.start, event) }
    override func mouseDragged(with event: NSEvent) { emit(.move, event) }
    override func mouseUp(with event: NSEvent) { emit(.end, event) }
    override func rightMouseDown(with event: NSEvent) { emit(.start, event) }
    override func rightMouseUp(with event: NSEvent) { emit(.end, event) }
    override func otherMouseDown(with event: NSEvent) { emit(.start, event) }
    override func otherMouseUp(with event: NSEvent) { emit(.end, event) }

    override func scrollWheel(with event: NSEvent) {
        onScroll?(Float(event.scrollingDeltaX), Float(event.scrollingDeltaY))
    }

    private func emit(_ type: GvTouchEventType, _ event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard remoteSize.width > 0, remoteSize.height > 0 else { return }
        let scale = min(bounds.width / remoteSize.width, bounds.height / remoteSize.height)
        let width = remoteSize.width * scale, height = remoteSize.height * scale
        guard width > 0, height > 0 else { return }
        let x = Float((p.x - (bounds.width - width) / 2) / width)
        let y = Float(1 - (p.y - (bounds.height - height) / 2) / height)
        guard x >= 0, x <= 1, y >= 0, y <= 1 else { return }
        onTouch?(GvTouchEvent(type: type, points: [GvTouchPoint(id: 0, x: x, y: y)]))
    }
}

// MARK: - 被控端：把 TouchEvent 注入系统

final class InputInjector {
    private var lastPoint: CGPoint?
    private var screenBounds: CGRect = .zero
    private var pressed = false

    func updateScreenSize(_ size: CGSize) { screenBounds = CGRect(origin: .zero, size: size) }
    func updateScreenBounds(_ bounds: CGRect) { screenBounds = bounds }

    func handle(_ touch: GvTouchEvent) {
        guard let p = touch.points.first, p.x.isFinite, p.y.isFinite, screenBounds.width > 0 else { return }
        let point = CGPoint(x: screenBounds.minX + CGFloat(max(0, min(1, p.x))) * screenBounds.width,
                            y: screenBounds.minY + CGFloat(max(0, min(1, p.y))) * screenBounds.height)
        switch touch.type {
        case .start:
            move(to: point)
            post(.leftMouseDown, at: point, button: .left)
            pressed = true
        case .move:
            post(pressed ? .leftMouseDragged : .mouseMoved, at: point, button: .left)
            lastPoint = point
        case .end:
            post(.leftMouseUp, at: point, button: .left)
            pressed = false
        case .cancel:
            cancel()
        case .undefined:
            break
        }
    }

    func cancel() {
        if pressed, let point = lastPoint { post(.leftMouseUp, at: point, button: .left) }
        pressed = false
    }

    private func move(to point: CGPoint) {
        guard let e = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                              mouseCursorPosition: point, mouseButton: .left) else { return }
        e.post(tap: .cghidEventTap)
        lastPoint = point
    }

    private func post(_ type: CGEventType, at point: CGPoint, button: CGMouseButton) {
        guard let e = CGEvent(mouseEventSource: nil, mouseType: type,
                              mouseCursorPosition: point, mouseButton: button) else { return }
        e.post(tap: .cghidEventTap)
    }

    func type(text: String) {
        let utf16 = Array(text.utf16)
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else { return }
        down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        up.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
