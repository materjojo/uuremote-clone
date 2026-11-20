import CoreImage
import CoreVideo
import Foundation
import WebRTC

/// Normalize native NV12 and software I420 frames for the BGRA Metal renderer.
/// Reuses pixel-buffer pools; native BGRA buffers pass through without a copy.
final class VideoPixelConverter {
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let lock = NSLock()
    private var pools: [String: CVPixelBufferPool] = [:]

    private func allocate(width: Int, height: Int, format: OSType) -> CVPixelBuffer? {
        guard width > 0, height > 0, width <= 16384, height <= 16384 else { return nil }
        lock.lock(); defer { lock.unlock() }
        let key = "\(width)x\(height):\(format)"
        if pools[key] == nil {
            var pool: CVPixelBufferPool?
            let attributes: [CFString: Any] = [
                kCVPixelBufferWidthKey: width, kCVPixelBufferHeightKey: height,
                kCVPixelBufferPixelFormatTypeKey: format,
                kCVPixelBufferIOSurfacePropertiesKey: [:], kCVPixelBufferMetalCompatibilityKey: true
            ]
            guard CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attributes as CFDictionary, &pool) == kCVReturnSuccess,
                  let pool else { return nil }
            // A resolution change must not leave unbounded cached pools.
            if pools.count >= 4 { pools.removeAll() }
            pools[key] = pool
        }
        var buffer: CVPixelBuffer?
        guard let pool = pools[key],
              CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer) == kCVReturnSuccess else { return nil }
        return buffer
    }

    func convert(_ frame: RTCVideoFrameBuffer) -> CVPixelBuffer? {
        if let native = frame as? RTCCVPixelBuffer { return native.pixelBuffer }
        let source = frame.toI420()
        guard let output = allocate(width: Int(source.width), height: Int(source.height),
                                    format: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange) else { return nil }
        CVPixelBufferLockBaseAddress(output, [])
        defer { CVPixelBufferUnlockBaseAddress(output, []) }
        guard let y = CVPixelBufferGetBaseAddressOfPlane(output, 0),
              let uv = CVPixelBufferGetBaseAddressOfPlane(output, 1) else { return nil }
        let yStride = CVPixelBufferGetBytesPerRowOfPlane(output, 0)
        let uvStride = CVPixelBufferGetBytesPerRowOfPlane(output, 1)
        for row in 0..<Int(source.height) {
            memcpy(y.advanced(by: row * yStride), source.dataY.advanced(by: row * Int(source.strideY)), Int(source.width))
        }
        let chroma = uv.assumingMemoryBound(to: UInt8.self)
        for row in 0..<Int(source.chromaHeight) {
            for x in 0..<Int(source.chromaWidth) {
                chroma[row * uvStride + x * 2] = source.dataU[row * Int(source.strideU) + x]
                chroma[row * uvStride + x * 2 + 1] = source.dataV[row * Int(source.strideV) + x]
            }
        }
        CVBufferSetAttachment(output, kCVImageBufferYCbCrMatrixKey,
                              kCVImageBufferYCbCrMatrix_ITU_R_601_4, .shouldPropagate)
        return output
    }

    func bgra(_ source: CVPixelBuffer) -> CVPixelBuffer? {
        if CVPixelBufferGetPixelFormatType(source) == kCVPixelFormatType_32BGRA { return source }
        let width = CVPixelBufferGetWidth(source), height = CVPixelBufferGetHeight(source)
        guard let output = allocate(width: width, height: height, format: kCVPixelFormatType_32BGRA) else { return nil }
        context.render(CIImage(cvPixelBuffer: source), to: output,
                       bounds: CGRect(x: 0, y: 0, width: width, height: height),
                       colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return output
    }
}
