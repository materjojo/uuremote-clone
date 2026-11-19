# 与原安装包的一致性核对

对照样本：uuyc 4.48.1 (build 633)。判定标准：字段/行为能否用二进制证据支撑。

## 1. 协议

| 项 | 原版 | 复刻 | 结论 |
|---|---|---|---|
| 信封结构 | Message: seq=1, timestamp=2, oneof 3..28 | 同 | 一致（字段编号来自元数据） |
| 消息数量 | 223 条 gv_pb 消息 | 178 条（官方 FileDescriptorProto 全量还原，含类型/oneof/枚举） | 已对齐（Java/C# 由同一 proto 生成） |
| 控制通道 framing | 一个 SCTP 消息 = 一个 protobuf | 同 | 一致 |
| DataChannel label | CONTROL / BINARY / FILE / internal | CONTROL / BINARY / FILE / VIDEO(新增) | 前三者一致 |
| 信令事件 | send_offer / send_candidates / bmsg_push / room_info / qos_stats_upload 等 | 同名事件 | 事件名一致，JSON 内层字段为推断 |
| 业务 API | 59 个 /api/v1|2 端点 | 设备列表、room/create、wol/info | 仅核心 3 个 |
| 弱网层 | KCP + RS-FEC（参数未知） | 标准 KCP 头 + (8,2) RS | 机制一致，参数未验证 |

## 2. 编解码

| 项 | 原版 | 复刻 | 结论 |
|---|---|---|---|
| H.264 | WebRTC RTP，VideoToolbox 硬编 | WebRTC 内置 H264（macOS 下走 VideoToolbox） | 可用，参数未逐项对齐 |
| H.265 | nrd-webrtc 的 H265 RTP | 自建 VIDEO_DATA_CHANNEL 分片 + VT 编解码 | 编码器一致，传输路径不同 |
| 关键帧 | 强制 IDR + VPS/SPS/PPS 前置 | 同 | 一致 |
| 码控 | 自研 rate controller（tier/headroom/downshift） | AIMD（帧率反馈，1s 周期） | 行为近似，非逐参数一致 |
| 色度/HDR | 420/422/444，10bit，BT.2020 | 420 输入，8bit 渲染 | 部分实现 |
| 音频 | Opus + SCK 系统声 + 麦克风 | WebRTC Opus（未接采集） | 未完成 |

## 3. 硬件编解码 / 加速

| 项 | 原版 | 复刻 | 结论 |
|---|---|---|---|
| 硬编 | VTCompressionSession + 硬件检查 | VTCompressionSession + UsingHardwareAcceleratedVideoEncoder 探测 | 一致 |
| 硬解 | VTDecompressionSession | VTDecompressionSession（H265） / WebRTC 内置（H264） | 一致 |
| 渲染 | 自研 Metal，Y/UV 双平面，点采样，HDR | Metal（BGRA），点采样，sRGB/2020 | 已实现，HDR 元数据未透传 |
| 零拷贝 | IOSurface/CVPixelBuffer 直通 | CVMetalTextureCache 直通 | 一致 |
| 采集加速 | SCK GPU 表面 | SCK 同 | 一致 |

## 4. 远程开机（WOL）

| 项 | 原版 | 复刻 | 结论 |
|---|---|---|---|
| API | POST /api/v1/device/wake_on_lan/info | 同路径 | 一致 |
| 魔术包 | 6×FF + 16×MAC，UDP 9/7 广播 | 同 | 一致 |
| UI | 离线设备卡片入口 | 卡片按钮 + 提示 | 一致（样式简化） |

## 5. 其他

| 项 | 状态 |
|---|---|
| 虚拟屏 | 已实现（私有 CGVirtualDisplay） |
| 私有屏增强 | 降级实现（缺私有 CGS） |
| 无人值守 | 用户级 LaunchAgent（root daemon 未做） |
| 剪贴板/文件传输 | 协议层可编解码，业务逻辑未接 |
| 键盘/手柄 | 未实现（InputEvent 仅暴露 touch_event） |
| 云设备 | 已移除 |

## 6. 结论

- 协议骨架、字段编号、DataChannel、信令事件名、采集与硬编硬解：与原版一致。
- H.265 传输路径、码控参数、音频、键盘、剪贴板业务：不一致或缺失。
- 若要逐字节一致，需要一次真实会话抓包（信令 JSON + RTP/DataChannel），当前不具备条件。
