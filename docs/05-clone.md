# 复刻工程说明

## 目标

在**不改变协议与主要交互**的前提下，用 Swift 重写一个 macOS 客户端 + 被控端，
并删除云设备（CloudPC / CloudDisk）相关功能。

## 目录

```
repo/
├── Package.swift
├── proto/gv_pb.proto              # 从二进制还原的核心消息（字段编号与原名一致）
├── Sources/UURemoteClone/
│   ├── App/                       # @main、AppState、窗口
│   ├── Core/                      # 配置、HTTP、凭据
│   ├── Protocol/                  # protobuf 读写 + 消息模型
│   ├── Signaling/                 # Socket.IO(EIO4) 客户端、房间状态机
│   ├── Media/                     # 采集、编码、解码、渲染
│   ├── Input/                     # 输入采集与注入
│   └── UI/                        # SwiftUI 界面
├── docs/                          # 逆向分析报告
└── .github/workflows/build.yml    # macOS runner 构建
```

## 已实现（协议等价）

1. `gv_pb` 消息编解码（varint / length-delimited / 嵌套消息 / oneof）。
2. HTTP 房间创建与设备列表客户端（端点与字段名与原版一致）。
3. Engine.IO 4 + Socket.IO 客户端（`send_offer`/`send_candidates`/`bmsg_push`）。
4. WebRTC 会话（DataChannel + H.264 视频 + Opus 音频），DataChannel label 与原版一致。
5. 控制消息：`ConnectOptions`、`CaptureSettingRequest`、`InputEvent`、`ScreenSources`、`FeatureFlag` 等。
6. 被控端：ScreenCaptureKit 采集 + VideoToolbox 编码 + `RTCVideoSource` 推流 + CGEvent 注入。
7. 控制端：`RTCMTLNSVideoView` 渲染 + 鼠标/键盘 → `TouchEvent` 归一化坐标。

## 未实现 / 差异

| 项 | 状态 |
|---|---|
| H.265 | 已实现：自建 VIDEO_DATA_CHANNEL 分片 + VideoToolbox 编解码（开源 WebRTC 不含 H265 RTP，故绕开 RTP） |
| KCP + RS-FEC | 已实现：Transport/ 下标准 KCP 头 + (8,2) 系统化 Reed-Solomon，可在设置中开关 |
| 虚拟屏 / 私有屏 | 已实现：私有 CGVirtualDisplay 创建 + SCK/CGDisplayStream 采集；增强防窥依赖私有 CGS，失败自动降级 |
| 无人值守 | 已实现：LaunchAgent 安装/卸载 + --agent 无界面常驻 + 被控采集 |
| 云设备 | 按要求移除 |
| 精确像素级 UI | 无 Assets.car 解码工具，图标以 SF Symbols 占位，布局按文案与类名还原 |

## 构建

GitHub Actions（macos-14）执行：

```bash
swift build -c release
bash scripts/make_app.sh
```

产物：`build/UURemoteClone.app`（未签名，ad-hoc）。

本地构建仅需 Xcode 15+ / Swift 5.9+，无私有依赖。
