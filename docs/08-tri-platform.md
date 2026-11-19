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

- 14 个 proto 文件：defines / main / connect / general / clipboard / draw / feature_flag / input_event / mumu / notification / port_mapping / rpc_main / rpc_message / rpc_file_transfer
- 178 条消息（含嵌套共 179）+ 51 个枚举，覆盖官方全部消息定义；此前"223"是 Swift 类型名统计（含 StorageClass 与 oneof 枚举），非消息数
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
| 协议（179 消息） | Swift 手写核心 + GvSchema | protobuf-javalite 生成并编译进 APK | Google.Protobuf 生成并编译 |
| KCP + FEC | Swift 实现 | 待接 core | 待接 core |
| WebRTC | 已实现 | PeerConnection + 三个同名 DataChannel | SIPSorcery RTCPeerConnection + 三个同名 DataChannel |
| 采集 | SCK 已实现 | MediaProjection + VirtualDisplay | GDI CopyFromScreen（DXGI/WGC 待接） |
| 硬编/硬解 | VideoToolbox 已实现 | MediaCodec H.264 surface 输入 | FFmpeg D3D11VA/NVENC（需 FFmpeg shared 运行时） |
| 渲染 | Metal 已实现 | SurfaceViewRenderer 已实现 | WriteableBitmap 已实现 |
| 输入 | CGEvent 已实现 | Accessibility 手势已实现 | SendInput（鼠标/键盘）已实现 |
| UI | 主流程 | 设备列表 + 远控骨架 | 设备列表 + 远控工具条/画面/状态栏 |

### 仍与官方不一致的部分（如实说明）

- **采集**：Windows 用 GDI，官方用 DXGI/WGC；Android 用 MediaProjection（与官方一致）。
- **硬编**：Windows/Android 用 FFmpeg/MediaCodec 实现 H.264 功能等价；官方 Windows 走 MF/NVENC 私有 streamer.dll，Android 走 MediaCodec。H.265/10bit HDR 尚未在三端全部打通。
- **传输增强**：KCP + RS-FEC 仅在 macOS 接好；Android/Windows 仍待接 core。
- **UI**：三端均为结构还原（设备列表、远控工具条、画面、状态栏），未逐像素对齐官方；安装包只有机器码，逐页还原需持续反编译。
- **运行时依赖**：Windows FFmpeg 编码需目标机安装 FFmpeg shared DLL（LGPL）；官方为自带 streamer.dll。
- **信令 JSON 内层**：字段名按 WebRTC 通用约定与二进制 Codable 键推断，未经真实抓包验证。

三端已实现的能力均通过 GitHub Actions 编译验证（core×3 + macos-app + windows-app + android-app）。
安装包内是编译后的机器码，逐行/逐像素复刻需要持续反编译，不是单次会话能完成的。
