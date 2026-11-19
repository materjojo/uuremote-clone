import SwiftUI
import AppKit
import CoreGraphics

// MARK: - 控制端：把本地事件归一化为 TouchEvent

struct RemoteInputView: NSViewRepresentable {
    var onTouch: (GvTouchEvent) -> Void
    var onScroll: ((Float, Float) -> Void)? = nil

    func makeNSView(context: Context) -> InputNSView {
        let v = InputNSView()
        v.onTouch = onTouch
        v.onScroll = onScroll
        return v
    }

    func updateNSView(_ nsView: InputNSView, context: Context) {
        nsView.onTouch = onTouch
        nsView.onScroll = onScroll
    }
}

final class InputNSView: NSView {
    var onTouch: ((GvTouchEvent) -> Void)?
    var onScroll: ((Float, Float) -> Void)?

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
        let x = Float(p.x / max(bounds.width, 1))
        let y = Float(1 - p.y / max(bounds.height, 1))
        onTouch?(GvTouchEvent(type: type, points: [GvTouchPoint(id: 0, x: x, y: y)]))
    }
}

// MARK: - 被控端：把 TouchEvent 注入系统

final class InputInjector {
    private var lastPoint: CGPoint?
    private var screenSize: CGSize = .zero

    func updateScreenSize(_ size: CGSize) { screenSize = size }

    func handle(_ touch: GvTouchEvent) {
        guard let p = touch.points.first, screenSize.width > 0 else { return }
        let point = CGPoint(x: CGFloat(p.x) * screenSize.width,
                            y: CGFloat(p.y) * screenSize.height)
        switch touch.type {
        case .start:
            move(to: point)
            post(.leftMouseDown, at: point, button: .left)
        case .move:
            move(to: point)
        case .end:
            post(.leftMouseUp, at: point, button: .left)
        case .cancel:
            break
        case .undefined:
            break
        }
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
