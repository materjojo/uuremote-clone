# 三端架构与共享边界

样本：macOS 4.48.1 (pkg) / Android 4.48.1 (apk) / Windows 4.48.1.5606 (exe)。

## 1. 三端确实是同一套核心

| 证据 | macOS | Android | Windows |
|---|---|---|---|
| 流媒体核心 | libstreamer.dylib (26 MB) | libstreamer.so + libstreamer-jni.so | streamer.dll (20 MB) |
| 配置 | Resources/streamer-config.json | assets/streamer/streamer-config.json | streamer-config.json |
| 绑定 API | ObjC StreamerManager: createRoomWithToken/serverList/... | JNI AndroidStreamerController: LoginRoom/Connect/StartVideoRender... | 同源 C++ 导出 |
| 协议 | SwiftProtobuf gv_pb | protobuf（Java/Kotlin 侧） | FileDescriptorProto 内嵌 |

## 2. 权威协议来源（关键发现）

Windows 的 GameViewerServer.exe 内嵌了 **完整的 FileDescriptorProto**，已解析出：

- 13 个 proto 文件：main / connect / general / clipboard / draw / feature_flag / input_event / mumu / notification / port_mapping / rpc_main / rpc_message / rpc_file_transfer
- 177 条消息，包含**精确字段编号、类型、label、oneof、嵌套类型与枚举**
- 输出：proto/gv_pb/*.proto（可直接 protoc 生成任意语言绑定）

这取代了此前从 Swift 元数据推断的 160 条（且类型靠猜）。此前推断的差异已确认：
- CaptureParams.fps 是枚举 FPS，不是 int32
- Screen.resolutions 是 repeated WinRect
- ConnectOptions.capture_type 是嵌套枚举 ConnectOptions.Type

## 3. 共享代码边界

| 层 | 是否共享 | 位置 |
|---|---|---|
| protobuf 编解码 + schema | 共享 | core/src/gvpb.cpp, schema.cpp |
| KCP 可靠传输 | 共享 | core/src/kcp.cpp |
| RS-FEC | 共享 | core/src/fec.cpp |
| 信令状态机 | 共享（待迁移） | 目前 macOS 在 Swift，Android/Windows 待接 core |
| WebRTC 媒体 | 各端官方库 | macOS: stasel/WebRTC；Android: org.webrtc；Windows: libwebrtc |
| 采集 | 不共享 | SCK / MediaProjection / DXGI+WGC |
| 硬件编码 | 不共享 | VideoToolbox / MediaCodec / NVENC+MF |
| 输入注入 | 不共享 | CGEvent / Accessibility / SendInput |
| UI | 不共享 | SwiftUI / View / WPF |

共享的前提是安装包中确实同源：streamer 核心与 gv_pb 已证实同源；采集/编码/注入按平台原生实现，不能强行共用。

## 4. 目录

    core/                 C++ 共享核心（CMake，三平台 CI 编译 + 单测）
    proto/gv_pb/          官方 descriptor 还原的 proto 文件
    Sources/UURemoteClone macOS 客户端（SwiftUI + WebRTC）
    platforms/android/    Android 客户端骨架（Java + Gradle）
    platforms/windows/    Windows 客户端骨架（WPF + P/Invoke）

## 5. 现状与差距

| 能力 | macOS | Android | Windows |
|---|---|---|---|
| 协议（177 消息） | 已接（Swift 手写核心 + GvSchema） | JNI 待接 | P/Invoke 已接 |
| KCP + FEC | Swift 实现 | 待接 core | 待接 core |
| 采集 | SCK 已实现 | 未实现 | 未实现 |
| 硬编 | VT 已实现 | 未实现 | 未实现 |
| 渲染 | Metal 已实现 | 未实现 | 未实现 |
| 输入 | CGEvent 已实现 | 未实现 | 未实现 |
| UI | 主流程 | 设备列表骨架 | 设备列表骨架 |

三端 UI 与业务逻辑尚未达到 1:1；安装包内是编译后的机器码，逐行还原需要持续反编译，不是单次会话能完成的。
当前仓库提供的是：权威协议、跨平台核心、可编译的三端骨架，以及 macOS 端较完整的实现。
