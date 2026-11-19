import Foundation

/// 码率控制器：按实际帧率在 min/max 之间 AIMD 调整（对应官方 encoder rate controller）
final class EncoderRateController {
    private(set) var targetBps: Int
    let maxBps: Int
    let minBps: Int
    private var lastAdjust = Date()
    private var lastFrames = 0
    private var lastSample = Date()

    init(startBps: Int, maxBps: Int, minBps: Int) {
        self.targetBps = startBps
        self.maxBps = max(maxBps, minBps)
        self.minBps = minBps
    }

    /// 每秒调用一次；返回需要下发的新码率（无变化返回 nil）
    func tick(frameCount: Int, configuredFps: Int) -> Int? {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastSample)
        guard elapsed >= 1.0 else { return nil }
        let fps = Double(frameCount - lastFrames) / elapsed
        lastFrames = frameCount
        lastSample = now

        var next = targetBps
        if fps < Double(configuredFps) * 0.8 {
            next = Int(Double(targetBps) * 0.9)
        } else if fps >= Double(configuredFps) * 0.95 {
            next = Int(Double(targetBps) * 1.05)
        }
        next = min(max(next, minBps), maxBps)
        guard next != targetBps else { return nil }
        targetBps = next
        lastAdjust = now
        return next
    }
}
