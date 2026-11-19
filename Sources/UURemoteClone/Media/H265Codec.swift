import Foundation
import VideoToolbox
import CoreMedia
import CoreVideo

// MARK: - Annex-B 工具

enum H265NAL {
    static func split(_ data: Data) -> [Data] {
        var nals: [Data] = []
        var starts: [Int] = []
        let bytes = [UInt8](data)
        var i = 0
        while i + 3 < bytes.count {
            if bytes[i] == 0, bytes[i + 1] == 0, bytes[i + 2] == 1 {
                starts.append(i + 3)
                i += 3
            } else if i + 4 < bytes.count, bytes[i] == 0, bytes[i + 1] == 0, bytes[i + 2] == 0, bytes[i + 3] == 1 {
                starts.append(i + 4)
                i += 4
            } else {
                i += 1
            }
        }
        for (idx, s) in starts.enumerated() {
            let end = idx + 1 < starts.count ? starts[idx + 1] - 3 : bytes.count
            if end > s { nals.append(Data(bytes[s..<end])) }
        }
        return nals
    }

    static func nalType(_ nal: Data) -> UInt8 {
        guard nal.count > 0 else { return 0 }
        return (nal[0] >> 1) & 0x3f
    }

    static func annexB(_ nals: [Data]) -> Data {
        var out = Data()
        for nal in nals {
            out.append(contentsOf: [0, 0, 0, 1])
            out.append(nal)
        }
        return out
    }
}

// MARK: - 编码器（VideoToolbox HEVC）

final class H265Encoder {
    private var session: VTCompressionSession?
    private(set) var width = 0
    private(set) var height = 0
    private(set) var usingHardware = false
    private(set) var currentBitrate = 0
    private var configuredFps = 60
    private var frameCount = 0
    private var controller: EncoderRateController?
    var onFrame: ((Data, Bool) -> Void)?
    var onParameterSets: ((Data) -> Void)?

    deinit { invalidate() }

    func prepare(width: Int, height: Int, fps: Int, bitrate: Int) -> Bool {
        if session != nil && self.width == width && self.height == height { return true }
        invalidate()
        var s: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: Int32(width), height: Int32(height),
            codecType: kCMVideoCodecType_HEVC,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: nil,
            refcon: nil,
            compressionSessionOut: &s)
        guard status == noErr, let session = s else { return false }

        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowTemporalCompression, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_HEVC_Main_AutoLevel)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: bitrate as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: (fps * 2) as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, value: 2 as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: fps as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowOpenGOP, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowTemporalCompression, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_PrioritizeEncodingSpeedOverQuality, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxFrameDelayCount, value: 0 as CFNumber)
        applyBitrate(bitrate)

        var property: CFTypeRef?
        let hwKey = "UsingHardwareAcceleratedVideoEncoder" as CFString
        if VTSessionCopyProperty(session, key: hwKey, allocator: kCFAllocatorDefault, propertyValueOut: &property) == noErr {
            usingHardware = (property as? Bool) ?? ((property as? NSNumber)?.boolValue ?? false)
        }

        configuredFps = fps
        controller = EncoderRateController(startBps: bitrate, maxBps: bitrate * 2, minBps: max(bitrate / 4, 800_000))
        currentBitrate = bitrate

        VTCompressionSessionPrepareToEncodeFrames(session)
        self.session = session
        self.width = width
        self.height = height
        return true
    }

    func invalidate() {
        if let session { VTCompressionSessionInvalidate(session) }
        session = nil
    }

    func setBitrate(_ bps: Int) {
        guard let session, bps != currentBitrate else { return }
        currentBitrate = bps
        applyBitrate(bps)
    }

    private func applyBitrate(_ bps: Int) {
        guard let session else { return }
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: bps as CFNumber)
        let limits: [NSNumber] = [NSNumber(value: bps / 8), NSNumber(value: 1.0)]
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_DataRateLimits, value: limits as CFArray)
    }

    func encode(_ pixelBuffer: CVPixelBuffer, pts: CMTime, forceKey: Bool = false) {
        guard let session else { return }
        frameCount += 1
        if let controller, let next = controller.tick(frameCount: frameCount, configuredFps: configuredFps) {
            setBitrate(next)
        }
        var flags: VTEncodeInfoFlags = []
        let props: CFDictionary? = forceKey
            ? [kVTEncodeFrameOptionKey_ForceKeyFrame: true] as CFDictionary
            : nil
        VTCompressionSessionEncodeFrame(
            session, imageBuffer: pixelBuffer,
            presentationTimeStamp: pts, duration: .invalid,
            frameProperties: props, infoFlagsOut: &flags
        ) { [weak self] status, _, sampleBuffer in
            guard status == noErr, let sb = sampleBuffer, let self else { return }
            guard let annex = Self.annexB(sampleBuffer: sb) else { return }
            let nals = H265NAL.split(annex)
            let isKey = nals.contains { [19, 20, 21].contains(H265NAL.nalType($0)) }
            if isKey, let params = Self.parameterSets(sampleBuffer: sb) {
                self.onParameterSets?(params)
                // 关键帧必须携带 VPS/SPS/PPS，解码端才能建立 format description
                var withParams = params
                withParams.append(annex)
                self.onFrame?(withParams, true)
            } else {
                self.onFrame?(annex, isKey)
            }
        }
    }

    // CMSampleBuffer 的 AVCC 数据转 Annex-B
    private static func annexB(sampleBuffer: CMSampleBuffer) -> Data? {
        guard let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { return nil }
        var length = 0
        var pointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(block, atOffset: 0,
                                                 lengthAtOffsetOut: nil,
                                                 totalLengthOut: &length,
                                                 dataPointerOut: &pointer)
        guard status == noErr, let ptr = pointer, length > 4 else { return nil }
        var out = Data(capacity: length + 64)
        var offset = 0
        while offset + 4 <= length {
            var nalLength: UInt32 = 0
            memcpy(&nalLength, ptr + offset, 4)
            nalLength = UInt32(bigEndian: nalLength)
            offset += 4
            guard offset + Int(nalLength) <= length else { break }
            out.append(contentsOf: [0, 0, 0, 1])
            out.append(contentsOf: UnsafeBufferPointer(start: UnsafeRawPointer(ptr + offset).assumingMemoryBound(to: UInt8.self),
                                                       count: Int(nalLength)))
            offset += Int(nalLength)
        }
        return out.isEmpty ? nil : out
    }

    static func parameterSets(sampleBuffer: CMSampleBuffer) -> Data? {
        guard let format = CMSampleBufferGetFormatDescription(sampleBuffer) else { return nil }
        var count = 0
        var nalLength: Int32 = 0
        var sets: [Data] = []
        CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(format, parameterSetIndex: 0,
                                                           parameterSetPointerOut: nil,
                                                           parameterSetSizeOut: nil,
                                                           parameterSetCountOut: &count,
                                                           nalUnitHeaderLengthOut: &nalLength)
        for i in 0..<count {
            var ptr: UnsafePointer<UInt8>?
            var size = 0
            let st = CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(format, parameterSetIndex: i,
                                                                        parameterSetPointerOut: &ptr,
                                                                        parameterSetSizeOut: &size,
                                                                        parameterSetCountOut: nil,
                                                                        nalUnitHeaderLengthOut: nil)
            if st == noErr, let p = ptr, size > 0 {
                sets.append(Data(bytes: p, count: size))
            }
        }
        return sets.isEmpty ? nil : H265NAL.annexB(sets)
    }
}

// MARK: - 解码器

final class H265Decoder {
    private var session: VTDecompressionSession?
    private var format: CMVideoFormatDescription?
    private var parameterSets: [Data] = []
    var onImage: ((CVPixelBuffer, CMTime) -> Void)?
    var onError: ((String) -> Void)?

    deinit { flush() }

    func flush() {
        if let session { VTDecompressionSessionInvalidate(session) }
        session = nil
        format = nil
        parameterSets.removeAll()
    }

    func decode(annex: Data, pts: CMTime) {
        let nals = H265NAL.split(annex)
        guard !nals.isEmpty else { return }

        // 收集参数集（即使不是关键帧也允许更新）
        for nal in nals {
            let t = H265NAL.nalType(nal)
            if t == 32 || t == 33 || t == 34 {
                let copy = nal
                if !parameterSets.contains(copy) { parameterSets.append(copy) }
            }
        }
        if format == nil {
            guard !parameterSets.isEmpty, createFormat() else { return }
        }
        guard let format else { return }

        let avcc = Self.avcc(nals)
        var block: CMBlockBuffer?
        let length = avcc.count
        let st1 = CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault,
                                                     memoryBlock: nil, blockLength: length,
                                                     blockAllocator: kCFAllocatorDefault,
                                                     customBlockSource: nil, offsetToData: 0,
                                                     dataLength: length, flags: 0,
                                                     blockBufferOut: &block)
        guard st1 == noErr, let blockBuffer = block else { return }
        avcc.withUnsafeBytes { raw in
            if let base = raw.baseAddress {
                CMBlockBufferReplaceDataBytes(with: base, blockBuffer: blockBuffer,
                                              offsetIntoDestination: 0, dataLength: length)
            }
        }

        var sample: CMSampleBuffer?
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: pts, decodeTimeStamp: .invalid)
        var sampleSize = length
        let st2 = CMSampleBufferCreateReady(allocator: kCFAllocatorDefault,
                                            dataBuffer: blockBuffer,
                                            formatDescription: format,
                                            sampleCount: 1, sampleTimingEntryCount: 1,
                                            sampleTimingArray: &timing,
                                            sampleSizeEntryCount: 1,
                                            sampleSizeArray: &sampleSize,
                                            sampleBufferOut: &sample)
        guard st2 == noErr, let sampleBuffer = sample else { return }

        if session == nil { createSession(format: format) }
        guard let session else { return }
        VTDecompressionSessionDecodeFrame(
            session, sampleBuffer: sampleBuffer,
            flags: [._EnableAsynchronousDecompression],
            infoFlagsOut: nil
        ) { [weak self] status, _, imageBuffer, pts, _ in
            guard status == noErr else { return }
            if let pb = imageBuffer {
                self?.onImage?(pb, pts)
            }
        }
    }

    private func createFormat() -> Bool {
        var flat: [UInt8] = []
        var offsets: [Int] = []
        var sizes: [Int] = []
        for data in parameterSets {
            offsets.append(flat.count)
            sizes.append(data.count)
            flat.append(contentsOf: data)
        }
        var fmt: CMVideoFormatDescription?
        var status: OSStatus = -1
        flat.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            var ptrs: [UnsafePointer<UInt8>] = offsets.map { base + $0 }
            var szs = sizes
            ptrs.withUnsafeMutableBufferPointer { p in
                szs.withUnsafeMutableBufferPointer { s in
                    status = CMVideoFormatDescriptionCreateFromHEVCParameterSets(
                        allocator: kCFAllocatorDefault,
                        parameterSetCount: parameterSets.count,
                        parameterSetPointers: p.baseAddress!,
                        parameterSetSizes: s.baseAddress!,
                        nalUnitHeaderLength: 4,
                        extensions: nil,
                        formatDescriptionOut: &fmt)
                }
            }
        }
        if status == noErr { format = fmt; return true }
        return false
    }

    private func createSession(format: CMVideoFormatDescription) {
        var s: VTDecompressionSession?
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        let st = VTDecompressionSessionCreate(allocator: kCFAllocatorDefault,
                                              formatDescription: format,
                                              decoderSpecification: nil,
                                              imageBufferAttributes: attrs as CFDictionary,
                                              outputCallback: nil,
                                              decompressionSessionOut: &s)
        if st == noErr { session = s }
    }

    static func avcc(_ nals: [Data]) -> Data {
        var out = Data()
        for nal in nals {
            var len = UInt32(nal.count).bigEndian
            withUnsafeBytes(of: &len) { out.append(contentsOf: $0) }
            out.append(nal)
        }
        return out
    }
}
