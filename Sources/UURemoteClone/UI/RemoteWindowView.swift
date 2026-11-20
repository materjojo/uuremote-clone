import SwiftUI
import WebRTC
import AppKit
import AVFoundation

struct RemoteWindowView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        Group {
            if let session = app.session {
                RemoteSessionView(session: session)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "display").font(.system(size: 40))
                    Text("请选择要控制的设备").foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct RemoteSessionView: View {
    @ObservedObject var session: RemoteSession

    @State private var showToolbar = true
    @State private var quality: GvVideoQuality = .hd
    @State private var soundOn = true
    @State private var opacity: Double = 1.0
    @State private var showWindowSetting = false
    @State private var frameLimit: Double = 60
    @State private var hideWorkItem: DispatchWorkItem?

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            if session.videoTrack != nil || session.phase == .connected {
                VideoCanvas(track: session.videoTrack)
                    .ignoresSafeArea()
                RemoteInputView(
                    onTouch: { touch in session.send(touch: touch) },
                    onScroll: { _, dy in }
                )
                .ignoresSafeArea()
            } else {
                VStack(spacing: 14) {
                    ProgressView().controlSize(.large)
                    Text(session.phase.text).foregroundStyle(.white.opacity(0.8))
                    Text(session.device?.deviceName ?? "")
                        .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if let message = failureMessage {
                VStack {
                    Spacer()
                    Text(message)
                        .font(.system(size: 12))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Color.red.opacity(0.75))
                        .clipShape(Capsule())
                        .padding(.bottom, 24)
                }
            }

            if showToolbar {
                toolbar
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onHover { inside in
            hideWorkItem?.cancel()
            if inside {
                withAnimation(.easeOut(duration: 0.15)) { showToolbar = true }
            } else {
                let item = DispatchWorkItem {
                    withAnimation(.easeOut(duration: 0.25)) { showToolbar = false }
                }
                hideWorkItem = item
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: item)
            }
        }
    }

    private var failureMessage: String? {
        if case .failed(let message) = session.phase { return message }
        return nil
    }

    private var toolbar: some View {
        HStack(spacing: 6) {
            toolButton("display", L10n.Control.screen) {}
            toolButton("rectangle.arrowtriangle.2.outward", L10n.Control.fullScreen) {
                NSApplication.shared.keyWindow?.toggleFullScreen(nil)
            }
            Menu {
                Toggle("播放被控端声音", isOn: $soundOn)
                Toggle("常驻显示网络状态", isOn: .constant(true))
                Button("不透明度") { showWindowSetting.toggle() }
            } label: {
                toolLabel("slider.horizontal.3", L10n.Control.windowSetting)
            }
            .menuStyle(.borderlessButton).frame(width: 96)

            Menu {
                ForEach([GvVideoQuality.fast, .general, .hd, .bluray, .auto], id: \.rawValue) { q in
                    Button(qualityName(q)) { quality = q; applyQuality(q) }
                }
            } label: {
                toolLabel("sparkles", L10n.Control.quality)
            }
            .menuStyle(.borderlessButton).frame(width: 76)

            Menu {
                Button("智能鼠标") {}
                Button("使用被控端鼠标") {}
                Button("使用主控端鼠标") {}
            } label: {
                toolLabel("computermouse", L10n.Control.mouse)
            }
            .menuStyle(.borderlessButton).frame(width: 76)

            toolButton("keyboard", L10n.Control.keyboard) {}
            toolButton("speaker.wave.2", L10n.Control.sound) {}
            toolButton("arrow.up.arrow.down", L10n.Control.fileTransfer) {}

            Spacer()

            Text(session.phase.text)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.65))
                .padding(.trailing, 6)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 14)
    }

    private func toolButton(_ icon: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { toolLabel(icon, title) }
            .buttonStyle(.plain)
            .help(title)
    }

    private func toolLabel(_ icon: String, _ title: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 12))
            Text(title).font(.system(size: 11))
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(Color.white.opacity(0.001))
        .contentShape(Rectangle())
    }

    private func qualityName(_ q: GvVideoQuality) -> String {
        switch q {
        case .fast: return L10n.Quality.fast
        case .general: return L10n.Quality.general
        case .hd: return L10n.Quality.hd
        case .bluray: return L10n.Quality.bluray
        case .auto: return L10n.Quality.auto
        default: return L10n.Quality.custom
        }
    }

    private func applyQuality(_ q: GvVideoQuality) {
        var request = GvCaptureSettingRequest()
        request.frameQuality = q
        request.fps = Int32(frameLimit)
        session.sendCaptureSetting(request)
    }
}

struct VideoCanvas: NSViewRepresentable {
    let track: RTCVideoTrack?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> VideoRenderView {
        VideoRenderView(frame: .zero)
    }

    func updateNSView(_ nsView: VideoRenderView, context: Context) {
        context.coordinator.attach(track, to: nsView)
    }

    static func dismantleNSView(_ nsView: VideoRenderView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator {
        private weak var current: RTCVideoTrack?
        private weak var renderer: VideoRenderView?

        func attach(_ track: RTCVideoTrack?, to view: VideoRenderView) {
            guard let track else { return }
            if current === track, renderer === view { return }
            detach()
            track.add(view)
            current = track
            renderer = view
        }

        func detach() {
            if let track = current, let renderer { track.remove(renderer) }
            current = nil
            renderer = nil
        }
    }
}

/// 解码帧分发（H.265 路径不经过 RTCVideoTrack）
final class VideoFrameBus {
    static let shared = VideoFrameBus()
    weak var sink: VideoRenderView?

    func push(_ buffer: CVPixelBuffer, pts: CMTime) {
        DispatchQueue.main.async {
            self.sink?.display(buffer, pts: pts)
        }
    }
}

/// 自绘渲染视图：RTCCVPixelBuffer -> CMSampleBuffer -> AVSampleBufferDisplayLayer
/// （stasel/WebRTC 的 macOS 构建不含 RTCMTLNSVideoView）
final class VideoRenderView: NSView, RTCVideoRenderer {
    private let displayLayer = AVSampleBufferDisplayLayer()
    private var formatDescription: CMVideoFormatDescription?
    private var currentSize = CGSize.zero
    private var metal: MetalVideoView?
    private let pixelConverter = VideoPixelConverter()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        displayLayer.videoGravity = .resizeAspect
        layer?.addSublayer(displayLayer)

        let metal = MetalVideoView(frame: bounds)
        metal.autoresizingMask = [.width, .height]
        addSubview(metal)
        self.metal = metal
        VideoFrameBus.shared.sink = self
    }

    deinit {
        if VideoFrameBus.shared.sink === self { VideoFrameBus.shared.sink = nil }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        displayLayer.frame = bounds
        metal?.frame = bounds
        CATransaction.commit()
    }

    func setSize(_ size: CGSize) {}

    func renderFrame(_ frame: RTCVideoFrame?) {
        guard let frame, let pb = pixelConverter.convert(frame.buffer) else { return }
        let pts = CMTime(value: frame.timeStampNs, timescale: 1_000_000_000)
        DispatchQueue.main.async { self.display(pb, pts: pts) }
    }

    func display(_ pixelBuffer: CVPixelBuffer, pts: CMTime) {
        if let metal, let bgra = pixelConverter.bgra(pixelBuffer) {
            metal.display(bgra)
            return
        }
        let size = CVImageBufferGetEncodedSize(pixelBuffer)
        if formatDescription == nil || size != currentSize {
            var fd: CMVideoFormatDescription?
            let status = CMVideoFormatDescriptionCreateForImageBuffer(
                allocator: kCFAllocatorDefault,
                imageBuffer: pixelBuffer,
                formatDescriptionOut: &fd)
            guard status == noErr, let fd else { return }
            formatDescription = fd
            currentSize = size
        }
        guard let fd = formatDescription else { return }

        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: pts,
            decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        let status = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: fd,
            sampleTiming: &timing,
            sampleBufferOut: &sample)
        guard status == noErr, let sample else { return }
        if displayLayer.status == .failed { displayLayer.flush() }
        displayLayer.enqueue(sample)
    }
}
