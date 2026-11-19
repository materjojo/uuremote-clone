import Foundation

// MARK: - 枚举（取值与 gv_pb 一致）

public enum GvCodecType: Int32 { case unknown = 0, h264 = 1, h265 = 2 }
public enum GvVideoQuality: Int32 { case unknown = 0, fast = 1, general = 2, hd = 3, bluray = 4, auto = 5, custom = 6 }
public enum GvCaptureMode: Int32 { case unknown = 0, desktop = 1, window = 2, mumu = 3, hook = 4, global = 5 }
public enum GvClientType: Int32 { case unspecified = 0, ios = 1, android = 2, windows = 3, mac = 4 }
public enum GvChromaFormat: Int32 { case unknown = 0, f420 = 1, f422 = 2, f444 = 3, f400 = 4 }
public enum GvChooseResolutionType: Int32 { case unknown = 0, byDefault = 1, followLocal = 2, followRemote = 3, byResolution = 4 }
public enum GvScreenType: Int32 { case physics = 0, virtual = 1, superScreen = 2 }
public enum GvTouchEventType: Int32 { case undefined = 0, start = 1, move = 2, end = 3, cancel = 4 }
public enum GvControlConnectType: Int32 { case unknown = 0, normal = 1, assistance = 2 }

public enum GvPayloadField: Int {
    case simpleAction = 3
    case launchApp = 4
    case showApp = 5
    case mumuOperate = 6
    case screens = 7
    case captureChange = 8
    case captureConfig = 9
    case romMessage = 10
    case sendToRom = 11
    case reportError = 12
    case systemMetrics = 13
    case reportQosStats = 14
    case systemStateChange = 15
    case querySystemState = 16
    case clipboardChange = 17
    case codecNegotiation = 18
    case captureConfigResponse = 19
    case inputEvent = 20
    case rpcRequest = 21
    case rpcResponse = 22
    case activeWindowChange = 23
    case captureSettingSync = 25
    case remoteDownloadPath = 26
    case portMappingFrame = 27
    case terminalSessionChanged = 28
}

// MARK: - 基础结构

public struct GvResolution {
    public var width: Int32 = 0
    public var height: Int32 = 0
    public init(width: Int32 = 0, height: Int32 = 0) { self.width = width; self.height = height }
    public func encode() -> Data {
        var w = ProtoWriter()
        w.int32(width, field: 1); w.int32(height, field: 2)
        return w.data
    }
}

public struct GvDpiScale {
    public var scale: Double = 1
    public init(scale: Double = 1) { self.scale = scale }
    public func encode() -> Data {
        var w = ProtoWriter(); w.double(scale, field: 1); return w.data
    }
}

public struct GvCaptureParams {
    public var fps: Int32 = 60
    public var videoQuality: GvVideoQuality = .hd
    public var cursorCapture: Bool = true
    public var chooseResolutionType: GvChooseResolutionType = .byDefault
    public var localResolution: GvResolution?
    public var chooseResolution: GvResolution?
    public var chromaFormat: GvChromaFormat = .f420
    public var maxCustomBitrate: Int32 = 0
    public var enableHDR: Bool = false
    public var autoFrameQuality: Bool = true
    public var fpsCount: Int32 = 0

    public init() {}

    public func encode() -> Data {
        var w = ProtoWriter()
        w.int32(fps, field: 1)
        w.int32(videoQuality.rawValue, field: 2)
        w.bool(cursorCapture, field: 3)
        w.int32(chooseResolutionType.rawValue, field: 4)
        if let r = localResolution { w.message(r.encode(), field: 5) }
        if let r = chooseResolution { w.message(r.encode(), field: 6) }
        w.int32(chromaFormat.rawValue, field: 7)
        w.int32(maxCustomBitrate, field: 8)
        w.bool(enableHDR, field: 9)
        w.bool(autoFrameQuality, field: 10)
        w.int32(fpsCount, field: 11)
        return w.data
    }
}

public struct GvDecoderCap {
    public var fps: Int32
    public var codecType: GvCodecType
    public var width: Int32
    public var height: Int32
    public var chroma: GvChromaFormat
    public init(fps: Int32, codecType: GvCodecType, width: Int32, height: Int32, chroma: GvChromaFormat = .f420) {
        self.fps = fps; self.codecType = codecType; self.width = width; self.height = height; self.chroma = chroma
    }
    public func encode() -> Data {
        var w = ProtoWriter()
        w.int32(fps, field: 1)
        w.int32(codecType.rawValue, field: 2)
        w.int32(width, field: 3)
        w.int32(height, field: 4)
        w.int32(chroma.rawValue, field: 5)
        return w.data
    }
}

public struct GvFeatureFlag {
    public var captureSetting: Int32 = 7      // initVerion…hdr 全开
    public var simpleAction: Int32 = 1
    public var systemMetrics: Int32 = 1
    public var privateScreen: Int32 = 1
    public var updateAcquire: Int32 = 1
    public var fileTransferFTP: Int32 = 1
    public var fileTransferFTP2: Int32 = 1
    public var clipboard: Int32 = 1
    public var qosStat: Int32 = 1
    public var mumuControl: Int32 = 0
    public var virtualMouse: Int32 = 0
    public init() {}
    public func encode() -> Data {
        var w = ProtoWriter()
        w.int32(captureSetting, field: 1)
        w.int32(simpleAction, field: 2)
        w.int32(systemMetrics, field: 3)
        w.int32(privateScreen, field: 4)
        w.int32(updateAcquire, field: 5)
        w.int32(fileTransferFTP, field: 6)
        w.int32(fileTransferFTP2, field: 7)
        w.int32(clipboard, field: 8)
        w.int32(qosStat, field: 9)
        w.int32(mumuControl, field: 10)
        w.int32(virtualMouse, field: 11)
        return w.data
    }
}

public struct GvConnectOptions {
    public var captureType: GvCaptureMode = .desktop
    public var typeValue: Int32 = 0
    public var captureParams = GvCaptureParams()
    public var decoderCaps: [GvDecoderCap] = []
    public var forceVirtualDisplay = false
    public var clientType: GvClientType = .mac
    public var deviceID: String = ""
    public var controlConnectType: GvControlConnectType = .normal
    public var featureFlag = GvFeatureFlag()
    public var clientVersion: String = "4.48.1"
    public var entitlementData: String = ""
    public var currentServerTime: Int64 = 0

    public init() {}

    public func encode() -> Data {
        var w = ProtoWriter()
        w.int32(captureType.rawValue, field: 1)
        w.int32(typeValue, field: 2)
        w.message(captureParams.encode(), field: 3)
        for cap in decoderCaps { w.message(cap.encode(), field: 4) }
        w.bool(forceVirtualDisplay, field: 5)
        w.int32(clientType.rawValue, field: 8)
        w.string(deviceID, field: 9)
        w.int32(controlConnectType.rawValue, field: 10)
        w.message(featureFlag.encode(), field: 11)
        w.string(clientVersion, field: 12)
        w.string(entitlementData, field: 13)
        w.int64(currentServerTime, field: 14)
        return w.data
    }
}

public struct GvCaptureSettingRequest {
    public var fps: Int32 = 60
    public var frameQuality: GvVideoQuality = .hd
    public var cursorCapture = true
    public var screenID: Int32 = 0
    public var width: Int32 = 0
    public var height: Int32 = 0
    public var chroma: GvChromaFormat = .f420
    public var maxCustomBitrate: Int32 = 0
    public var dpiScale: Int32 = 0
    public var resolutionType: GvChooseResolutionType = .followRemote
    public var enableHDR = false
    public var autoFrameQuality: GvVideoQuality = .auto
    public var codec: GvCodecType = .h264
    public var maxScaleWidth: Int32 = 0
    public var maxScaleHeight: Int32 = 0
    public var pixelWidth: Int32 = 0
    public var pixelHeight: Int32 = 0
    public var fpsCount: Int32 = 0

    public init() {}

    public func encode() -> Data {
        var w = ProtoWriter()
        w.int32(fps, field: 1)
        w.int32(frameQuality.rawValue, field: 2)
        w.bool(cursorCapture, field: 3)
        w.int32(screenID, field: 4)
        w.int32(width, field: 5)
        w.int32(height, field: 6)
        w.int32(chroma.rawValue, field: 7)
        w.int32(maxCustomBitrate, field: 8)
        w.int32(dpiScale, field: 9)
        w.int32(resolutionType.rawValue, field: 10)
        w.bool(enableHDR, field: 11)
        w.int32(autoFrameQuality.rawValue, field: 12)
        w.int32(codec.rawValue, field: 13)
        w.int32(maxScaleWidth, field: 14)
        w.int32(maxScaleHeight, field: 15)
        w.int32(pixelWidth, field: 16)
        w.int32(pixelHeight, field: 17)
        w.int32(fpsCount, field: 18)
        return w.data
    }
}

public struct GvTouchPoint {
    public var id: Int32
    public var x: Float   // 归一化 0…1
    public var y: Float
    public var radiusX: Float = 0
    public var radiusY: Float = 0
    public var angle: Float = 0
    public var pressure: Float = 0
    public init(id: Int32, x: Float, y: Float) { self.id = id; self.x = x; self.y = y }
    public func encode() -> Data {
        var w = ProtoWriter()
        w.int32(id, field: 1)
        w.float(x, field: 2)
        w.float(y, field: 3)
        w.float(radiusX, field: 4)
        w.float(radiusY, field: 5)
        w.float(angle, field: 6)
        w.float(pressure, field: 7)
        return w.data
    }
}

public struct GvTouchEvent {
    public var type: GvTouchEventType
    public var points: [GvTouchPoint]
    public init(type: GvTouchEventType, points: [GvTouchPoint]) { self.type = type; self.points = points }
    public func encode() -> Data {
        var w = ProtoWriter()
        w.int32(type.rawValue, field: 1)
        for p in points { w.message(p.encode(), field: 2) }
        return w.data
    }
}

public struct GvScreenInfo {
    public var id: Int32 = 0
    public var fps: Int32 = 0
    public var width: Int32 = 0
    public var height: Int32 = 0
    public var isPrimary = false
    public var dpr: Double = 1
    public var name: String = ""
    public var type: GvScreenType = .physics
    public var videoTrackIndex: Int32 = 0
    public static func decode(_ data: Data) -> GvScreenInfo? {
        var s = GvScreenInfo()
        var rr = ProtoReader(data)
        while let (field, wire) = try? rr.nextField() {
            switch field {
            case 1: s.id = (try? rr.readInt32()) ?? 0
            case 2: s.fps = (try? rr.readInt32()) ?? 0
            case 4:
                if let d = try? rr.readBytes() { s.width = Int32(GvResolution.decode(d).width); s.height = Int32(GvResolution.decode(d).height) }
            case 5: s.type = GvScreenType(rawValue: (try? rr.readInt32()) ?? 0) ?? .physics
            case 7: s.isPrimary = (try? rr.readBool()) ?? false
            case 8: s.dpr = (try? rr.readDouble()) ?? 1
            case 10: s.name = (try? rr.readString()) ?? ""
            case 12: s.videoTrackIndex = (try? rr.readInt32()) ?? 0
            default: try? rr.skip(wire)
            }
        }
        return s
    }
}

extension GvResolution {
    public static func decode(_ data: Data) -> (width: Int32, height: Int32) {
        var r = ProtoReader(data)
        var w: Int32 = 0, h: Int32 = 0
        while let (field, wire) = try? r.nextField() {
            switch field {
            case 1: w = (try? r.readInt32()) ?? 0
            case 2: h = (try? r.readInt32()) ?? 0
            default: try? r.skip(wire)
            }
        }
        return (w, h)
    }
}

// MARK: - 信封

public struct GvMessage {
    public var seq: Int64
    public var timestamp: Int64
    public var payloadField: Int
    public var payload: Data

    public init(seq: Int64, timestamp: Int64, payloadField: GvPayloadField, payload: Data) {
        self.seq = seq
        self.timestamp = timestamp
        self.payloadField = payloadField.rawValue
        self.payload = payload
    }

    public func encode() -> Data {
        var w = ProtoWriter()
        w.int64(seq, field: 1)
        w.int64(timestamp, field: 2)
        w.message(payload, field: payloadField)
        return w.data
    }

    public static func decode(_ data: Data) -> GvMessage? {
        var r = ProtoReader(data)
        var seq: Int64 = 0
        var ts: Int64 = 0
        var field = 0
        var payload = Data()
        while let (f, wire) = try? r.nextField() {
            switch f {
            case 1: seq = (try? r.readInt64()) ?? 0
            case 2: ts = (try? r.readInt64()) ?? 0
            case 3...28:
                guard let d = try? r.readBytes() else { return nil }
                field = f
                payload = d
            default:
                try? r.skip(wire)
            }
        }
        guard field != 0 else { return nil }
        return GvMessage(seq: seq, timestamp: ts, payloadField: field, payload: payload)
    }

    public var payloadKind: GvPayloadField? { GvPayloadField(rawValue: payloadField) }
}
