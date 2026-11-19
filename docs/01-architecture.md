# UU远程 macOS 4.48.1 逆向分析（一）：总体架构

> 目标样本：`uuyc_4.48.1_nochannel.pkg`
> SHA-256：`0e1c1c8e…45df9b`（完整值见 sig_report.txt）
> 版本：4.48.1 (build 633)，最低系统 macOS 11.0，Universal (arm64 + x86_64)
> 签名：Developer ID Application: Hangzhou Bobo Technology Co Ltd (PU9BNSBJW7)，hardened runtime
> 分析方式：Mach-O 静态解析 + Swift 元数据还原 + 字符串/日志语义分析（未运行样本）

---

## 1. 安装包结构

```
uuyc_4.48.1_nochannel.pkg  (91 MB, xar)
├── Distribution            # 安装判定（渠道 nochannel）
├── Resources/*.lproj       # 安装器文案
└── Payload                 # gzip cpio
    ├── Applications/UURemote.app        (185 MB)
    └── Library/
        ├── LaunchDaemons/com.netease.uuremote.daemon.plist
        └── LaunchAgents/com.netease.uuremote.agent.plist
```

`postinstall` 将 `UURemoteHelper.xpc` 设为 **setuid root (4755)**，用于静默自更新；主 App 未启用 App Sandbox，仅声明
`com.apple.security.device.audio-input` 与 `device.bluetooth`。

## 2. 进程与组件模型

| 组件 | 路径 | 角色 | 关键点 |
|---|---|---|---|
| UURemote | Contents/MacOS/UURemote (59 MB) | 主 UI 进程 | Swift + AppKit/SwiftUI 混合；`uuremote://` URL Scheme |
| UURemoteDaemon | 同目录 (13 MB) | root LaunchDaemon | 提权、服务守护、更新落地 |
| UURemoteService | 同目录 (13 MB) | 用户 LaunchAgent (LSUIElement) | 被控端常驻、权限探测、虚拟屏 |
| UURemoteServer | Contents/Helpers (26 MB) | 无人值守被控端 | 独立被控会话，可脱离 GUI 运行 |
| uuyc-cli | Contents/Helpers (2.5 MB) | CLI | tmux 会话管理，`--json` 面向 AI agent |
| uuyc-mux + tmux | Contents/Helpers/tmux | 自研 tmux 构建 | 终端会话承载 |
| libstreamer.dylib | Contents/Frameworks (26 MB) | 流媒体引擎 | C++ WebRTC 分支（nrd-webrtc）+ asio + websocketpp + OpenSSL/QUIC |
| UURemoteUpdater(.app) | Helpers | 自更新 | Sparkle 风格自研 |
| UURemoteHelper.xpc | XPCServices | 提权助手 | setuid root |

## 3. 代码组织（来自二进制内嵌源码路径）

构建机路径：`/Users/game-netease/Desktop/Runner/Builds/nrd-Mac/.../nrd-mac-clinet/nrd-mac-client`
（注意工程目录拼写为 `clinet`）。可恢复的 261 个 Module 源文件归入 33 个业务模块：

```
AboutApp  AddApp  AppPermission  AppSetting  ClientSecurityLock  CloudDisk  CloudPc
ControlDevice  ControlledDetail  DeviceAssist  DeviceGuide  DeviceInfo  DeviceList
DownloadMobile  Feedback  FileTransfer  FloatingBall  HomeUpdateConfirm  Login
ManageApp  MemberPermission  MessageCenter  NowDevice  PasteFile  PortMapping
RenameDevice  SpiltHome  SwitchDevice  Terminal  UIStyleSheet  VersionUpdate
```

从 Swift 类型描述符可恢复 **3526 个类型**，其中业务类 674 个（View/Controller/Model/Manager/Service）。
UI 采用 "ViewController + SwiftUI View 混编"：既有 `NSViewController`（`*WindowController`、`*ViewController`），
也有 SwiftUI `*View`/`*ViewModel`/`@Observable` 模型。

## 4. 第三方依赖（从类型与资源判定）

| 依赖 | 证据 | 用途 |
|---|---|---|
| SwiftProtobuf | `_protobuf_nameMap`、`SwiftProtobuf_SwiftProtobuf.bundle` | 控制协议编解码 |
| CryptoSwift | `CryptoSwift_CryptoSwiftResources.bundle` | AES/RSA/SHA |
| Lottie | `lottie-ios` 源码路径、`*.json` 动画 | 云队列/加载动画 |
| Sentry | `Sentry.bundle`、`SentryCrashExceptionApplication` | 崩溃上报 |
| Alamofire | Pods 路径 | HTTP |
| FeedbackSDK | `FeedbackSDK.bundle` | 帮助与反馈 |
| SwiftTerm | `SwiftTerm_SwiftTerm.bundle` | 终端仿真（tmux 会话） |
| WebRTC (自研分支) | `nrd-webrtc version`、`libstreamer` | 实时音视频 |
| OpenSSL / quictls | `quictls.c`、X509 字符串 | TLS/DTLS/QUIC |

## 5. 运行时拓扑

```
         ┌────────────── HTTPS (api.nrd.nie.163.com) ──────────────┐
         │ 登录 / 设备列表 / room/create / 版本 / 埋点              │
         ▼                                                        │
  ┌─────────────┐   ① POST /api/v1/room/create                   │
  │ UURemote    │──────────────────────────────────────────────► │
  │ (控制端)    │◄──── room_id, token, signaling_list ─────────── │
  └──────┬──────┘                                               │
         │ ② Socket.IO (EIO=4, wss://…/socket.io/?EIO=4&transport=websocket)
         ▼
  ┌─────────────────┐   ③ send_offer / send_candidates / bmsg_push
  │ 信令服务器       │◄──────────────────────────────────────────►
  └────────┬────────┘
           │ ④ WebRTC (ICE/DTLS/SRTP, UDP 或 TLS relay)
           ▼
  ┌─────────────────┐
  │ 被控端           │  UURemoteService / UURemoteServer
  │ ScreenCaptureKit │
  │ VideoToolbox     │
  └─────────────────┘
         │ ⑤ DataChannel: CONTROL / BINARY / FILE
         ▼
     GvPb_* protobuf 控制消息
```

## 6. 关键结论

1. **协议不是私有二进制格式，而是"标准 WebRTC + 自定义 Protobuf 控制层"**。信令走 Socket.IO v4（Engine.IO 4），
   媒体走标准 WebRTC（DTLS-SRTP），控制消息是 223 个 `gv_pb.*` Protobuf 消息。
2. 视频编码为 **H.264 / H.265（AV1 有代码路径但默认关闭）**，走 VideoToolbox 硬编；解码端支持 HDR、420/422/444。
3. 采集使用 **ScreenCaptureKit**（macOS 12.3+），旧系统回退 `CGDisplayStream`；音频为 SCK 系统声 + 麦克风。
4. 渲染使用 **Metal**（自研 shader，支持 HDR/BT.2020、点采样缩放）。
5. 云设备（CloudPC / CloudDisk）是**独立模块**，仅通过 `/api/v1/cloud_pc/*` 与 `GvPb_LaunchCloudPcApp` 接入，
   复刻时可整体移除而不影响本地远控主链路。
6. 安全上：信令 TLS 可配置 `sni_enabled` / `tls_verify_host`（存在关闭校验的开关），HTTP 层有 `X-AUTH-*`、
   `x-param-sign`、`x-param-nonce` 等签名/防重放头。
