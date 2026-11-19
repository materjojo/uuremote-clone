import Foundation
import AVFoundation
import ScreenCaptureKit
import CoreMedia

/// ScreenCaptureKit 采集（对应官方 SCK video capture）
final class ScreenCapturer: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private let queue = DispatchQueue(label: "com.uuremote.capture", qos: .userInteractive)
    private var onPixelBuffer: ((CVPixelBuffer, CMTime) -> Void)?

    struct Config {
        var width: Int = 1920
        var height: Int = 1080
        var fps: Int = 60
        var showsCursor = true
        var capturesAudio = false
    }

    func start(display: SCDisplay, config: Config, onPixelBuffer: @escaping (CVPixelBuffer, CMTime) -> Void) async throws {
        self.onPixelBuffer = onPixelBuffer
        let filter = SCContentFilter(display: display, excludingWindows: [])

        let sc = SCStreamConfiguration()
        sc.width = config.width
        sc.height = config.height
        sc.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(config.fps))
        sc.queueDepth = 5
        sc.showsCursor = config.showsCursor
        sc.capturesAudio = config.capturesAudio
        sc.pixelFormat = kCVPixelFormatType_32BGRA

        let stream = SCStream(filter: filter, configuration: sc, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        if config.capturesAudio {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        }
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() async {
        try? await stream?.stopCapture()
        stream = nil
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              sampleBuffer.isValid,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        onPixelBuffer?(pixelBuffer, pts)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        stream.stopCapture { _ in }
    }
}
