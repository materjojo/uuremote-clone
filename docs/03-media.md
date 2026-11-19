# UU远程 macOS 4.48.1 逆向分析（三）：采集 / 编码 / 传输 / 渲染

> 依据：`libstreamer.dylib` 的日志字符串、Objective-C 选择器、类名与 VideoToolbox/ScreenCaptureKit 常量。

---

## 1. 采集（被控端）

### 1.1 视频

两条路径，按系统版本选择：

| 路径 | 类/函数 | 说明 |
|---|---|---|
| ScreenCaptureKit | `SCStream` + `SCStreamOutput` | macOS 12.3+，日志 `SCK video init capture display={} resolution={}x{} fps={} quality={}` |
| CGDisplayStream | `CGDisplayStreamCreate` | 旧系统回退，日志 `CG display {} stream {}` |

关键行为：
- `SCStreamConfiguration`：`width/height`（目标分辨率）、`minimumFrameInterval`（fps）、`queueDepth`、
  `showsCursor`（cursor_capture）、`pixelFormat`（420v / 420f / x422 / x444）、`colorSpaceName`（HDR 用 BT.2020）。
- 动态改配：`updateConfiguration` → 日志 `SCK updateConfig applied display={} target={}x{} fps={} quality={}`
- 多屏：`DesktopConfigurationMonitor` 监听 `CGDisplayRegisterReconfigurationCallback`，
  事件包括 add/remove/enabled/disabled/mirror/unmirror/moved/set main/set mode。
- 虚拟屏：`GvPb_CreateVirtualDisplayRequest`，配合 `force_virtual_display`；私有屏（防窥）走 `CGVirtualDisplay` 私有 API。
- 采集失败上报：`OnCaptureFailed` → `GvPb_ReportError`。

### 1.2 音频

- 系统声：`SCStreamOutput` type `.audio`，重采样到 48 kHz 立体声，日志 `SCK audio conversion failed`。
- 麦克风：`MicrophoneAudioCapturer`（Voice-Processing I/O AudioUnit），
  日志 `Voice-Processing I/O audio unit recording is now started`，对应 entitlement `audio-input`。
- 编码固定 **Opus**（`create audio encoder num channels: {} payload type: {}`，支持 stereo/inbandfec）。

## 2. 编码

`VideoToolbox` 硬编（`VTCompressionSession`），日志完整暴露了参数：

```
video toolbox init {}x{} codec {} chroma {} bit_depth {}
kVTCompressionPropertyKey_RealTime
kVTCompressionPropertyKey_AllowFrameReordering = false
kVTCompressionPropertyKey_MaxFrameDelayCount = 0
kVTCompressionPropertyKey_MaxKeyFrameInterval / MaxKeyFrameIntervalDuration
kVTCompressionPropertyKey_PrioritizeEncodingSpeedOverQuality
kVTCompressionPropertyKey_ProfileLevel（H264 High / H265 Main10）
kVTCompressionPropertyKey_AllowOpenGOP / AllowTemporalCompression
EnableLowLatencyRateControl（失败时回退）
```

码率控制是自研 `encoder rate controller`：
- 输入：target bps / max bps / 配置 fps / 实际 fps / quality
- 策略：downshift samples、tier step、headroom%、rapid upshift%、bitrate up/down %
- 输出：`SetBitRate` 周期调整，关键帧请求 `request key frame after encoder session restart`

码率档位由 `VideoQuality` 决定（fast/general/hd/bluray/auto/custom），
分辨率由 `ChooseResolutionType`（default/follow local/follow remote/explicit）决定。

## 3. 传输

- **WebRTC**：自研分支 `nrd-webrtc`（`Init streamer version:{} nrd-webrtc version:{}`）。
- ICE：支持 host/srflx/prflx/relay；`SwitchIceNetwork` 支持 UDP ↔ TLS relay 自动切换：
  `filter_network_monitor loss rate is too high, try to switch to relay, prefer udp / tls relay`。
- 拥塞控制：`bwe_mon`（delay-based + loss-based，AIMD）、pacer、FEC、NACK。
- 统计：`v_mon` 每帧记录 capture/encode/pacer/transport/assembly/decode/e2e 七段延迟，
  jank 归因 `abnormal_network / controlled_driver / controlled_source / controller_source / send_delay / decode_delay`。
- 弱网数据：`dc_pro_kcp_*`、`rsfec` 表明控制通道叠加 KCP + RS-FEC。

## 4. 解码与渲染（控制端）

- 解码：VideoToolbox `VTDecompressionSession`，H.264 Annex-B → `CMSampleBuffer`（`H264AnnexBBufferToCMSampleBuffer`）。
- 渲染：**Metal**（`MetalRenderer` / `mac metal view` / `mac metal renderer pipeline`），
  支持：
  - NV12 双平面纹理（Y + UV），10bit HDR（`bit_depth=10`，BT.2020 + sRGB 输出）
  - 点采样/线性采样切换（`point_sample`）
  - 变换：`mac setTransform: scale/trans/pivot`
  - 自适应 drawable 尺寸，几何不匹配时丢帧重试（`retry frame: actual={}x{} expected={}x{}`）
- 帧调度：由 `[self draw]` 驱动（非 MTKView 定时器），避免额外延迟。

## 5. 关键性能参数（从日志默认值推断）

| 项 | 值 |
|---|---|
| 采集队列深度 | 3~5 帧 |
| 编码 GOP | 受 MaxKeyFrameInterval 限制（默认约 2s），支持强制 IDR |
| 帧率档 | 30 / 60 / 90 / 144（`GvPb_FPS`） |
| 色度采样 | 420 / 422 / 444 / 400 |
| 音频 | Opus 48 kHz，stereo，inband FEC |
| 控制通道单包上限 | 日志 `current msg size {} larger than {}kb`（约 64 KB 量级） |

## 6. 复刻取舍

- 控制端：直接使用 Google WebRTC 的 `RTCMTLNSVideoView` 渲染 + 内置 H.264 解码，行为等价。
- 被控端：`SCStream` 采集 → `VTCompressionSession` → `RTCVideoSource`（`RTCCVPixelBuffer`）推流。
- H.265 在开源 WebRTC 构建中默认不可用，复刻版以 H.264 为主，协议层保留 `CodecType` 协商字段。
